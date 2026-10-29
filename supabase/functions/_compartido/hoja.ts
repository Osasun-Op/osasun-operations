// Interpretación de las pestañas de STOCK OSASUN-CLAUDE (REGLAS_CALCULO.md §1).
// Código puro: recibe las filas tal como las devuelve la API de Google Sheets
// (valores formateados) y las convierte en datos. Busca encabezados y nombres,
// no celdas fijas. Si la forma de la hoja no es la esperada, lanza
// ErrorEstructura: nunca devuelve datos a medias.

import { celda, norm } from "./normalizar.ts";

export class ErrorEstructura extends Error {
  constructor(mensaje: string) {
    super(mensaje);
    this.name = "ErrorEstructura";
  }
}

export type Filas = string[][];

/** R1e: cajas de cada tienda («FIN DIA» de su columna en PRINCIPAL), por el nombre de la tienda en la fila 1. */
export type Tiendas = Record<string, string>;

/** Producto de PRINCIPAL: fila del nombre y, debajo, una fila por formato. */
export interface Producto {
  nombre: string;            // tal cual, recortado («V2 » → «V2»)
  granel: string;            // gramos de granel en el almacén (columna ALMACEN de la fila del nombre)
  formatos: { formato: string; almacen: string; tiendas?: Tiendas }[];
  conTiendas: boolean;       // la fila del nombre tiene datos de tiendas (producto sin formato)
  /** Producto sin formato: cajas de cada tienda (en la fila del nombre). */
  tiendas?: Tiendas;
  orden: number;             // fila en la hoja
  /** R4: «LO QUE HAY EN TOTAL» y «1 SEMANA NECESIDADES» de la fila del nombre (sin las columnas, no están). */
  total?: string;
  necesidad?: string;
}

/** Línea de CONTEO DE CAJAS TOTAL. */
export interface Conteo {
  grupo: string;
  producto: string;
  formato: string;
  contador: string;          // «CAJAS TOTALES HECHAS» (hechas − consumo)
  consumo: string;           // «CONSUMO CAJAS SEMANAL»
  orden: number;             // columna de grupo y fila (empates de R3)
}

export interface DatosHoja {
  productos: Producto[];
  conteo: Conteo[];
  /** norm(nombre de producto) → grupo de la pestaña ALMACEN. */
  categorias: Record<string, string>;
  /** Variedades (nombres de PRINCIPAL) de las categorías que rotan. */
  variedades: { INVERNADERO: string[]; INDOOR: string[] };
}

const vacia = (fila: unknown[] | undefined, desde: number, hasta: number) => {
  for (let c = desde; c <= hasta; c++) if (celda(fila, c) !== "") return false;
  return true;
};

/** PRINCIPAL: catálogo, cajas del almacén y granel. */
export function leerPrincipal(filas: Filas): Producto[] {
  if (norm(celda(filas[0], 0)) !== "PRODUCTOS") {
    throw new ErrorEstructura("PRINCIPAL: la celda A1 no es «PRODUCTOS».");
  }
  const colAlmacen = (filas[0] ?? []).findIndex((v) => norm(String(v ?? "")) === "ALMACEN");
  if (colAlmacen < 1) throw new ErrorEstructura("PRINCIPAL: no encuentro la columna «ALMACEN» en la fila 1.");
  const filaFinDia = filas.findIndex((f, i) => i < 5 && norm(celda(f, colAlmacen)) === "FINDIA");
  if (filaFinDia < 0) throw new ErrorEstructura("PRINCIPAL: no encuentro «FIN DIA» bajo «ALMACEN».");
  // R4: si faltan estas columnas, el reparto y el stock siguen; la cobertura lo avisa.
  const colTotal = (filas[0] ?? []).findIndex((v) => norm(String(v ?? "")) === "LOQUEHAYENTOTAL");
  const colNecesidad = (filas[0] ?? []).findIndex((v, c) =>
    norm(String(v ?? "")) === "1SEMANA" && norm(celda(filas[1], c)) === "NECESIDADES");
  const conCobertura = colTotal >= 0 && colNecesidad >= 0;
  // R1e: cada tienda tiene su nombre en la fila 1 y sus cajas en la columna de la
  // izquierda («FIN DIA», o «TOTAL» en Durango y Portu).
  const columnasTienda: [string, number][] = [];
  for (let c = 2; c < colAlmacen; c++) {
    const nombre = celda(filas[0], c);
    if (nombre !== "" && ["FINDIA", "FINDÍA", "TOTAL"].includes(norm(celda(filas[filaFinDia], c - 1)))) {
      columnasTienda.push([nombre, c - 1]);
    }
  }
  const tiendasDe = (fila: unknown[] | undefined): Tiendas =>
    Object.fromEntries(columnasTienda.map(([n, c]) => [n, celda(fila, c)]).filter(([, v]) => v !== ""));

  const productos: Producto[] = [];
  let actual: Producto | null = null;
  for (let i = filaFinDia + 1; i < filas.length; i++) {
    const fila = filas[i];
    const a = celda(fila, 0);
    if (a === "") {
      actual = null;
      continue;
    }
    if (actual === null) {
      actual = {
        nombre: a,
        granel: celda(fila, colAlmacen),
        formatos: [],
        conTiendas: !vacia(fila, 1, colAlmacen - 1),
        orden: i,
        ...(conCobertura ? { total: celda(fila, colTotal), necesidad: celda(fila, colNecesidad) } : {}),
      };
      if (actual.conTiendas) actual.tiendas = tiendasDe(fila);
      productos.push(actual);
    } else {
      actual.formatos.push({ formato: a, almacen: celda(fila, colAlmacen), tiendas: tiendasDe(fila) });
    }
  }
  if (productos.length < 5) throw new ErrorEstructura("PRINCIPAL: casi no hay productos; la hoja ha cambiado.");
  return productos;
}

/** CONTEO DE CAJAS TOTAL: contador y consumo de cada referencia. */
export function leerConteo(filas: Filas): Conteo[] {
  const grupos: { columna: number; nombre: string }[] = [];
  const cabecera = filas[0] ?? [];
  for (let c = 0; c < cabecera.length; c++) {
    const nombre = celda(cabecera, c);
    if (nombre === "") continue;
    const ok = norm(celda(filas[1], c + 1)) === "CAJAS" && norm(celda(filas[1], c + 2)) === "CONSUMO"
      && norm(celda(filas[3], c + 1)) === "HECHAS" && norm(celda(filas[3], c + 2)) === "SEMANAL";
    if (!ok) throw new ErrorEstructura(`CONTEO DE CAJAS TOTAL: el grupo «${nombre}» no tiene las columnas CAJAS HECHAS / CONSUMO SEMANAL.`);
    grupos.push({ columna: c, nombre });
  }
  if (grupos.length === 0) throw new ErrorEstructura("CONTEO DE CAJAS TOTAL: no encuentro los grupos en la fila 1.");

  const conteo: Conteo[] = [];
  grupos.forEach((g, n) => {
    let producto: string | null = null;
    for (let i = 4; i < filas.length; i++) {
      const fila = filas[i];
      const nombre = celda(fila, g.columna);
      const v1 = celda(fila, g.columna + 1);
      const v2 = celda(fila, g.columna + 2);
      if (nombre === "" && v1 === "" && v2 === "") {
        producto = null;
      } else if (producto === null || (nombre !== "" && v1 === "" && v2 === "")) {
        producto = nombre;
        if (v1 !== "" || v2 !== "") {
          conteo.push({ grupo: g.nombre, producto, formato: "", contador: v1, consumo: v2, orden: n * 100000 + i });
        }
      } else {
        conteo.push({ grupo: g.nombre, producto, formato: nombre, contador: v1, consumo: v2, orden: n * 100000 + i });
      }
    }
  });
  const nombres = new Set(conteo.map((c) => norm(c.producto)));
  if (!nombres.has("INVERNADEROTOTAL") || !nombres.has("INDOORTOTAL")) {
    throw new ErrorEstructura("CONTEO DE CAJAS TOTAL: faltan las filas «INVERNADERO TOTAL» o «INDOOR TOTAL».");
  }
  return conteo;
}

/** ALMACEN: a qué grupo pertenece cada producto y variedades que rotan. */
export function leerAlmacen(filas: Filas): Pick<DatosHoja, "categorias" | "variedades"> {
  const categorias: Record<string, string> = {};
  const variedades = { INVERNADERO: [] as string[], INDOOR: [] as string[] };
  const cabecera = filas[0] ?? [];
  let hayInvernadero = false;
  let hayIndoor = false;
  for (let c = 0; c < cabecera.length; c++) {
    const grupo = celda(cabecera, c);
    if (grupo === "") continue;
    const filaFinDia = filas.findIndex((f, i) => i < 8 && norm(celda(f, c + 1)) === "FINDIA");
    if (filaFinDia < 0) throw new ErrorEstructura(`ALMACEN: el grupo «${grupo}» no tiene la fila «FIN DIA».`);
    const g = norm(grupo);
    if (g === "INVERNADERO") hayInvernadero = true;
    if (g.startsWith("INDOOR")) hayIndoor = true;
    let enBloque = false;
    for (let i = filaFinDia + 1; i < filas.length; i++) {
      const nombre = celda(filas[i], c);
      if (nombre === "") {
        enBloque = false;
        continue;
      }
      if (enBloque) continue; // fila de formato
      enBloque = true;
      categorias[norm(nombre)] = grupo;
      if (g === "INVERNADERO") variedades.INVERNADERO.push(nombre);
      if (g.startsWith("INDOOR")) variedades.INDOOR.push(nombre);
    }
  }
  if (!hayInvernadero || !hayIndoor) throw new ErrorEstructura("ALMACEN: faltan los grupos INVERNADERO o INDOOR.");
  return { categorias, variedades };
}

export function leerHoja(principal: Filas, conteo: Filas, almacen: Filas): DatosHoja {
  return { productos: leerPrincipal(principal), conteo: leerConteo(conteo), ...leerAlmacen(almacen) };
}
