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

/** Petición especial de una tienda (R1d): texto libre que va en su bolsa. */
export interface Peticion {
  destino_id: string;
  texto: string;
}

export const MAX_PETICION = 120;

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
 * tienda (orden de `destinos`) y por el orden de la hoja. `permitirVacia`: un
 * reparto que solo lleva pedidos de cliente (Tarea 14).
 */
export function validarLineas(
  lineas: unknown, entradas: EntradaCatalogo[], destinos: Destino[], permitirVacia = false,
): Validacion {
  if (permitirVacia && (lineas === undefined || lineas === null)) return { ok: true, lineas: [] };
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
  if (suma.size === 0 && !permitirVacia) {
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

/**
 * Peticiones especiales (R1d): una por línea y tienda, texto libre de 120
 * letras como máximo. Las vacías se ignoran y las repetidas en la misma tienda
 * cuentan una vez. Sin peticiones (`undefined` o `null`), lista vacía.
 */
export function validarPeticiones(
  peticiones: unknown, destinos: Destino[],
): { ok: true; peticiones: Peticion[] } | { ok: false; mensaje: string; detalle: Record<string, unknown> } {
  if (peticiones === undefined || peticiones === null) return { ok: true, peticiones: [] };
  if (!Array.isArray(peticiones)) return { ok: false, mensaje: "Las peticiones especiales no son válidas.", detalle: {} };
  const posDestino = new Map(destinos.map((d, i) => [d.id, i]));
  const vistas = new Set<string>();
  const lista: (Peticion & { n: number })[] = [];
  for (const [n, p] of (peticiones as Record<string, unknown>[]).entries()) {
    const texto = typeof p?.texto === "string" ? p.texto.replace(/\s+/g, " ").trim() : "";
    const destino = typeof p?.destino_id === "string" ? p.destino_id : "";
    if (texto === "") continue;
    if (!posDestino.has(destino)) {
      return { ok: false, mensaje: "Esa tienda no es válida para este reparto.", detalle: { destino_id: destino } };
    }
    if (texto.length > MAX_PETICION) {
      return { ok: false, mensaje: `Cada petición especial, ${MAX_PETICION} letras como máximo.`, detalle: { texto } };
    }
    const k = `${destino}|${texto.toUpperCase()}`;
    if (vistas.has(k)) continue;
    vistas.add(k);
    lista.push({ destino_id: destino, texto, n });
  }
  lista.sort((a, b) => posDestino.get(a.destino_id)! - posDestino.get(b.destino_id)! || a.n - b.n);
  return { ok: true, peticiones: lista.map(({ destino_id, texto }) => ({ destino_id, texto })) };
}

const dosCifras = (n: number) => String(n).padStart(2, "0");

/**
 * Texto para WhatsApp, con el formato de siempre (R1). Cada tienda con
 * peticiones especiales lleva después de sus productos una línea «Además: …»
 * (R1d), con las peticiones separadas por «; ».
 */
export function textoWhatsapp(
  tipo: "reparto" | "envio",
  hoy: { dia: number; mes: number },
  sale: "operario" | "administracion" | null,
  lineas: LineaLista[],
  destinos: Destino[],
  peticiones: Peticion[] = [],
): string {
  const t: string[] = [`${tipo === "reparto" ? "REPARTO" : "ENVÍO"} ${dosCifras(hoy.dia)}/${dosCifras(hoy.mes)}`];
  if (tipo === "reparto") t.push(`SALE: ${sale === "operario" ? "ALMACÉN" : "YO"}`);
  for (const d of destinos) {
    const suyas = lineas.filter((l) => l.destino_id === d.id);
    const ademas = peticiones.filter((p) => p.destino_id === d.id).map((p) => p.texto);
    if (suyas.length === 0 && ademas.length === 0) continue;
    t.push("", d.alias[0] ?? d.nombre.toUpperCase());
    for (const l of suyas) t.push(`${l.cantidad}x ${l.producto}${l.formato ? " " + l.formato : ""}`);
    if (ademas.length > 0) t.push(`Además: ${ademas.join("; ")}`);
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
  peticiones?: Peticion[];
  permitirVacio?: boolean;
}): { texto: string; r: ResultadoR1 } {
  const texto = textoWhatsapp(op.tipo, op.hoy, op.sale, op.lineas, op.destinos, op.peticiones ?? []);
  const r = analizarReparto(texto, op.entradas, op.destinos, {
    tipo: op.tipo, hoy: op.hoy, sale: op.sale, confirmarFecha: true, apartadoReparto: op.apartadoReparto ?? [],
    permitirVacio: op.permitirVacio ?? false,
  });
  return { texto, r };
}
