// R1 · Lectura del texto del reparto o del envío (REGLAS_CALCULO.md §2). Código puro.

import type { Producto } from "./hoja.ts";
import { centesimas, norm } from "./normalizar.ts";

export interface Destino {
  id: string;
  nombre: string;
  alias: string[];
}

export interface EntradaCatalogo {
  producto: string;
  formato: string;
  almacen: string;
  orden: number;
}

export type Clase = "cabecera" | "sale" | "tienda" | "producto" | "vacia" | "no_reconocida";

export interface Linea {
  num: number;
  texto: string;
  clase: Clase;
  destino_id?: string;
  cantidad?: number;
  producto?: string;
  formato?: string;
  error?: string;
  mensaje?: string;
}

export interface ElementoProduccion {
  producto: string;
  formato: string;
  pedido: number;
  en_almacen: number;          // disponible para este cálculo (ya descontado lo apartado)
  apartado_reparto: number;    // solo envío antes del recuento: cajas del reparto de hoy
  faltan: number;
  aviso: string | null;
  orden: number;
}

export interface Bolsa {
  destino_id: string;
  destino: string;
  items: { producto: string; formato: string; cantidad: number; orden: number }[];
}

export type Estado = "aceptado" | "con_errores" | "falta_sale" | "fecha_no_es_hoy";

export interface ResultadoR1 {
  estado: Estado;
  lineas: Linea[];
  errores: Linea[];
  sale: "operario" | "administracion" | null;
  fecha: { dia: number; mes: number } | null;
  produccion: ElementoProduccion[];
  bolsas: Bolsa[];
}

/** Catálogo de PRINCIPAL: una entrada por producto y formato (y los productos sin formato). */
export function catalogo(productos: Producto[]): { entradas: EntradaCatalogo[]; ambiguas: string[] } {
  const entradas: EntradaCatalogo[] = [];
  for (const p of productos) {
    if (p.formatos.length > 0) {
      p.formatos.forEach((f, i) =>
        entradas.push({ producto: p.nombre.trim(), formato: f.formato, almacen: f.almacen, orden: p.orden * 100 + i })
      );
    } else if (p.conTiendas) {
      entradas.push({ producto: p.nombre.trim(), formato: "", almacen: p.granel, orden: p.orden * 100 });
    }
  }
  const vistas = new Map<string, number>();
  for (const e of entradas) vistas.set(norm(e.producto + e.formato), (vistas.get(norm(e.producto + e.formato)) ?? 0) + 1);
  const ambiguas = [...vistas.entries()].filter(([, n]) => n > 1).map(([k]) => k);
  return { entradas, ambiguas };
}

const MENSAJES: Record<string, (l: Linea) => string> = {
  LINEA_NO_RECONOCIDA: (l) => `Línea ${l.num}: no entiendo "${l.texto.trim()}". Corrígela o pregunta a Administración.`,
  PRODUCTO_DESCONOCIDO: (l) => `Línea ${l.num}: "${l.texto.trim()}" no está en el catálogo.`,
  PRODUCTO_SIN_TIENDA: (l) => `Línea ${l.num}: falta la tienda antes de esta línea.`,
  CANTIDAD_NO_VALIDA: (l) => `Línea ${l.num}: la cantidad debe ser 1 o más.`,
  SALE_CONTRADICTORIA: () => "Hay dos líneas SALE: distintas.",
  REPARTO_VACIO: () => "No hay ninguna línea de producto.",
};

function conError(l: Linea, codigo: string): Linea {
  l.error = codigo;
  l.mensaje = MENSAJES[codigo](l);
  return l;
}

export interface OpcionesR1 {
  tipo: "reparto" | "envio";
  hoy: { dia: number; mes: number };
  sale?: "operario" | "administracion" | null;   // respuesta del operario si faltaba SALE:
  confirmarFecha?: boolean;
  /**
   * Solo envío pegado antes del recuento de la mañana (ESTADO_DEL_SISTEMA.md v1.11):
   * cajas pedidas en el reparto aceptado hoy, que se apartan antes de calcular.
   */
  apartadoReparto?: { producto: string; formato: string; pedido: number }[];
}

export function analizarReparto(
  texto: string,
  cat: EntradaCatalogo[],
  destinos: Destino[],
  op: OpcionesR1,
): ResultadoR1 {
  const porClave = new Map<string, EntradaCatalogo[]>();
  for (const e of cat) {
    const k = norm(e.producto + e.formato);
    porClave.set(k, [...(porClave.get(k) ?? []), e]);
  }
  const porAlias = new Map<string, Destino>();
  for (const d of destinos) for (const a of d.alias) porAlias.set(norm(a), d);

  const lineas: Linea[] = [];
  const errores: Linea[] = [];
  const sales = new Set<"operario" | "administracion">();
  let fecha: { dia: number; mes: number } | null = null;
  let destino: Destino | null = null;
  const pedidos = new Map<string, { e: EntradaCatalogo; cantidad: number }>();
  const bolsas = new Map<string, Bolsa>();
  let productos = 0;

  texto.split(/\r?\n/).forEach((original, i) => {
    const t = original.trim();
    const l: Linea = { num: i + 1, texto: original, clase: "no_reconocida" };
    lineas.push(l);
    let m: RegExpExecArray | null;

    if (t === "") {
      l.clase = "vacia";
    } else if ((m = /^(?:REPARTO|ENV[IÍ]O)\s+(\d{1,2})\/(\d{1,2})$/i.exec(t))) {
      l.clase = "cabecera";
      fecha = { dia: Number(m[1]), mes: Number(m[2]) };
    } else if ((m = /^SALE\s*:(.*)$/i.exec(t))) {
      l.clase = "sale";
      const v = norm(m[1]);
      if (v === "ALMACÉN" || v === "ALMACEN") sales.add("operario");
      else if (v === "YO") sales.add("administracion");
    } else if ((m = /^(\d+)\s*[xX]\s*(.+)$/.exec(t))) {
      l.clase = "producto";
      productos++;
      const cantidad = Number(m[1]);
      const candidatas = porClave.get(norm(m[2])) ?? [];
      l.cantidad = cantidad;
      if (candidatas.length !== 1) {
        errores.push(conError(l, "PRODUCTO_DESCONOCIDO"));
      } else if (cantidad < 1) {
        errores.push(conError(l, "CANTIDAD_NO_VALIDA"));
      } else if (destino === null) {
        errores.push(conError(l, "PRODUCTO_SIN_TIENDA"));
      } else {
        const e = candidatas[0];
        l.producto = e.producto;
        l.formato = e.formato;
        l.destino_id = destino.id;
        const k = norm(e.producto + e.formato);
        pedidos.set(k, { e, cantidad: (pedidos.get(k)?.cantidad ?? 0) + cantidad });
        const bolsa = bolsas.get(destino.id) ?? { destino_id: destino.id, destino: destino.nombre, items: [] };
        bolsas.set(destino.id, bolsa);
        const item = bolsa.items.find((x) => x.producto === e.producto && x.formato === e.formato);
        if (item) item.cantidad += cantidad;
        else bolsa.items.push({ producto: e.producto, formato: e.formato, cantidad, orden: e.orden });
      }
    } else if (porAlias.has(norm(t))) {
      l.clase = "tienda";
      destino = porAlias.get(norm(t))!;
      l.destino_id = destino.id;
    } else {
      errores.push(conError(l, "LINEA_NO_RECONOCIDA"));
    }
  });

  if (op.tipo === "reparto" && sales.size > 1) {
    errores.push(conError({ num: 0, texto: "", clase: "sale" }, "SALE_CONTRADICTORIA"));
  }
  if (productos === 0) errores.push(conError({ num: 0, texto: "", clase: "vacia" }, "REPARTO_VACIO"));

  const sale = op.tipo === "envio" ? null : sales.size === 1 ? [...sales][0] : (op.sale ?? null);
  const f = fecha as { dia: number; mes: number } | null;

  const apartados = new Map<string, number>();
  if (op.tipo === "envio") {
    for (const a of op.apartadoReparto ?? []) {
      const k = norm(a.producto + a.formato);
      apartados.set(k, (apartados.get(k) ?? 0) + a.pedido);
    }
  }

  const produccion: ElementoProduccion[] = [...pedidos.values()]
    .sort((a, b) => a.e.orden - b.e.orden)
    .map(({ e, cantidad }) => {
      const c = centesimas(e.almacen);
      let aviso: string | null = null;
      let enAlmacen = 0;
      if (c === null) aviso = "Dato de almacén vacío en PRINCIPAL: se cuenta como 0.";
      else if (c < 0) aviso = "Dato de almacén negativo en PRINCIPAL: se cuenta como 0.";
      else enAlmacen = Math.floor(c / 100);
      const apartado = apartados.get(norm(e.producto + e.formato)) ?? 0;
      const disponible = Math.max(0, enAlmacen - apartado);
      return {
        producto: e.producto, formato: e.formato, pedido: cantidad, en_almacen: disponible,
        apartado_reparto: apartado, faltan: Math.max(0, cantidad - disponible), aviso, orden: e.orden,
      };
    });

  let estado: Estado = "aceptado";
  if (errores.length > 0) estado = "con_errores";
  else if (op.tipo === "reparto" && sale === null) estado = "falta_sale";
  else if (f && (f.dia !== op.hoy.dia || f.mes !== op.hoy.mes) && !op.confirmarFecha) estado = "fecha_no_es_hoy";

  return { estado, lineas, errores, sale, fecha: f, produccion, bolsas: [...bolsas.values()] };
}
