// Reparto con lista (ESTADO_DEL_SISTEMA.md v1.21, §5 R1). El reparto ya no se
// pega: se prepara eligiendo referencias del catálogo de PRINCIPAL. Con la lista
// se genera el texto de WhatsApp de siempre (con los nombres exactos de la hoja)
// y se calcula con R1, así el cálculo y la sustitución son los mismos que al
// pegarlo. Código puro: sin red ni base de datos.

import type { DatosHoja } from "./hoja.ts";
import { analizarReparto, catalogo, type Destino, type EntradaCatalogo, type ResultadoR1 } from "./r1.ts";
import { norm } from "./normalizar.ts";

export interface Referencia {
  clave: string;      // estable: producto + formato
  producto: string;
  formato: string;
  categoria: string;  // pestaña ALMACEN; «Otros» si no tiene
  orden: number;      // orden de la hoja
}

export interface LineaLista {
  destino_id: string;
  producto: string;
  formato: string;
  cantidad: number;
}

export type Validacion =
  | { ok: true; lineas: LineaLista[] }
  | { ok: false; codigo: "REFERENCIA_NO_EXISTE" | "DATOS_NO_VALIDOS"; mensaje: string; detalle: Record<string, unknown> };

export const claveDe = (producto: string, formato: string) => `${producto}|${formato}`;

/** Referencias del catálogo, en el orden de la hoja y con su categoría. */
export function referencias(datos: Pick<DatosHoja, "productos" | "categorias">) {
  const { entradas, ambiguas } = catalogo(datos.productos);
  const lista: Referencia[] = entradas.map((e) => ({
    clave: claveDe(e.producto, e.formato),
    producto: e.producto,
    formato: e.formato,
    categoria: datos.categorias[norm(e.producto)] ?? "Otros",
    orden: e.orden,
  }));
  return { referencias: lista, entradas, ambiguas };
}

/**
 * Comprueba la lista contra el catálogo leído ahora y las tiendas válidas para
 * el tipo. Las cantidades 0 se ignoran (contador sin tocar); las repetidas se
 * suman. Devuelve las líneas con los nombres exactos de la hoja, ordenadas por
 * tienda (orden de `destinos`) y por el orden de la hoja.
 */
export function validarLineas(lineas: unknown, entradas: EntradaCatalogo[], destinos: Destino[]): Validacion {
  if (!Array.isArray(lineas)) {
    return { ok: false, codigo: "DATOS_NO_VALIDOS", mensaje: "Añade al menos un producto.", detalle: {} };
  }
  const porClave = new Map(entradas.map((e) => [norm(e.producto + e.formato), e]));
  const posDestino = new Map(destinos.map((d, i) => [d.id, i]));
  const suma = new Map<string, { destino: string; e: EntradaCatalogo; cantidad: number }>();
  const noExisten: { producto: string; formato: string }[] = [];

  for (const l of lineas as Record<string, unknown>[]) {
    const producto = typeof l?.producto === "string" ? l.producto.trim() : "";
    const formato = typeof l?.formato === "string" ? l.formato.trim() : "";
    const cantidad = l?.cantidad;
    const destino = typeof l?.destino_id === "string" ? l.destino_id : "";
    if (typeof cantidad !== "number" || !Number.isInteger(cantidad) || cantidad < 0) {
      return { ok: false, codigo: "DATOS_NO_VALIDOS", mensaje: "La cantidad debe ser un número entero, 0 o más.",
               detalle: { producto, formato, cantidad } };
    }
    if (cantidad === 0) continue;
    if (!posDestino.has(destino)) {
      return { ok: false, codigo: "DATOS_NO_VALIDOS", mensaje: "Esa tienda no es válida para este reparto.",
               detalle: { destino_id: destino } };
    }
    const e = porClave.get(norm(producto + formato));
    if (!e) {
      if (!noExisten.some((x) => x.producto === producto && x.formato === formato)) noExisten.push({ producto, formato });
      continue;
    }
    const k = `${destino}|${claveDe(e.producto, e.formato)}`;
    const previa = suma.get(k);
    suma.set(k, { destino, e, cantidad: (previa?.cantidad ?? 0) + cantidad });
  }

  if (noExisten.length > 0) {
    const nombres = noExisten.map((x) => `${x.producto} ${x.formato}`.trim()).join(", ");
    return { ok: false, codigo: "REFERENCIA_NO_EXISTE",
             mensaje: `Ya no está en la hoja: ${nombres}. Quítalo de la lista o vuelve a cargarla.`,
             detalle: { referencias: noExisten } };
  }
  if (suma.size === 0) {
    return { ok: false, codigo: "DATOS_NO_VALIDOS", mensaje: "Añade al menos un producto.", detalle: {} };
  }
  const ordenadas = [...suma.values()].sort((a, b) =>
    posDestino.get(a.destino)! - posDestino.get(b.destino)! || a.e.orden - b.e.orden
  );
  return {
    ok: true,
    lineas: ordenadas.map((x) => ({ destino_id: x.destino, producto: x.e.producto, formato: x.e.formato, cantidad: x.cantidad })),
  };
}

const dosCifras = (n: number) => String(n).padStart(2, "0");

/** Texto para WhatsApp, con el formato de siempre (R1). */
export function textoWhatsapp(
  tipo: "reparto" | "envio",
  hoy: { dia: number; mes: number },
  sale: "operario" | "administracion" | null,
  lineas: LineaLista[],
  destinos: Destino[],
): string {
  const t: string[] = [`${tipo === "reparto" ? "REPARTO" : "ENVÍO"} ${dosCifras(hoy.dia)}/${dosCifras(hoy.mes)}`];
  if (tipo === "reparto") t.push(`SALE: ${sale === "operario" ? "ALMACÉN" : "YO"}`);
  let actual = "";
  for (const l of lineas) {
    if (l.destino_id !== actual) {
      actual = l.destino_id;
      const d = destinos.find((x) => x.id === actual)!;
      t.push("", d.alias[0] ?? d.nombre.toUpperCase());
    }
    t.push(`${l.cantidad}x ${l.producto}${l.formato ? " " + l.formato : ""}`);
  }
  return t.join("\n");
}

/** Texto y cálculo R1 de una lista ya validada. */
export function prepararReparto(op: {
  tipo: "reparto" | "envio";
  hoy: { dia: number; mes: number };
  sale: "operario" | "administracion" | null;
  lineas: LineaLista[];
  destinos: Destino[];
  entradas: EntradaCatalogo[];
  apartadoReparto?: { producto: string; formato: string; pedido: number }[];
}): { texto: string; r: ResultadoR1 } {
  const texto = textoWhatsapp(op.tipo, op.hoy, op.sale, op.lineas, op.destinos);
  const r = analizarReparto(texto, op.entradas, op.destinos, {
    tipo: op.tipo, hoy: op.hoy, sale: op.sale, confirmarFecha: true, apartadoReparto: op.apartadoReparto ?? [],
  });
  return { texto, r };
}
