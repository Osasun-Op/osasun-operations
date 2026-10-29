// Lectura de las pestañas con un extracto real de STOCK OSASUN-CLAUDE (26/10/2026)
// y casos de hoja cambiada (R3-15).
import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { ErrorEstructura, leerAlmacen, leerConteo, leerHoja, leerPrincipal } from "./hoja.ts";
import { calcularStock } from "./r3.ts";
import { catalogo } from "./r1.ts";

const v = (n: number) => Array(n).fill("");
// PRINCIPAL: columnas A..X; ALMACEN «FIN DIA» en la columna R (índice 17).
export const PRINCIPAL = [
  ["PRODUCTOS", "", "BILBAO", "", "ALGORTA", "", "DONOSTI", "", "BARAKALDO", "", "RENTERIA", "", "BASAURI", "", "LAUDIO", "", "PORTU", "ALMACEN", "", "LO QUE HAY EN TOTAL", "1 SEMANA", "1 MES", "", "CAJAS"],
  [...v(19), "TOTAL MERCADERÍAS", "NECESIDADES", "NECESIDADES", "", "EXTERIOR"],
  ["FIN DIA", "FIN DIA", "TOTAL GR", "FIN DIA", "TOTAL GR", "FIN DÍA", "TOTAL GR", "FIN DIA", "TOTAL GR", "FIN DIA", "TOTAL GR", "FIN DIA", "TOTAL GR", "TOTAL", "TOTAL GR", "TOTAL", "TOTAL GR", "FIN DIA", "TOTAL GR", "", "1 SEMANA", "1 MES", "", "275"],
  [...v(23), "INVERNADERO"],
  ["MINI", ...v(16), "1670", "1670", "1930", "315", "1260", "MINI", "225"],
  ["10g", "5", "50", "2", "20", "4", "40", "11", "110", "0", "0", "0", "0", "0", "0", "4", "40", "0", "", "", "", "", "", "INTERIOR"],
  [...v(23), "400"],
  ["SLUSH MINTS", ...v(16), "380", "490", "772", "68,5", "274", "SLUSH MINTS"],
  ["4g", "6", "24", "4", "16", "3", "12", "5", "20", "7", "28", "6", "24", "0", "0", "2", "8", "15"],
  ["10g", "3", "30", "2", "20", "1", "10", "2", "20", "4", "40", "1", "10", "0", "0", "2", "20", "5"],
  [],
  ["GRAPEFRUIT", ...v(16), "0", "0", "-10", "107,5", "430", "GRAPEFRUIT"],
  ["4g", "0", "0", "0", "0", "1", "4", "3", "12", "1", "4", "0", "0", "0", "0", "0", "0", "0"],
  [],
  ["INDOOR PR RELAX", ...v(16), "260", "260", "344", "157,5", "630", "INDOOR PR RELAX"],
  ["4g", "7", "28", "1", "4", "3", "12", "0", "0", "5", "20", "0", "0", "0", "0", "0", "0", "0"],
  [],
  ["INDOOR PR AFRU", ...v(16), "440", "440", "558", "133,5", "534", "INDOOR PR AFRU"],
  ["4g", "6", "24", "0", "0", "3", "12", "3", "12", "3", "12", "7", "28", "0", "0", "0", "0", "0"],
  ["", "", "", "", "", "", "", "", "  "],
  ["V2 ", ...v(16), "730", "930", "1498", "648,5", "2594", "MAZAR V2"],
  ["4g", "24", "96", "7", "28", "6", "24", "12", "48", "12", "48", "13", "52", "0", "0", "3", "12", "25"],
  ["10g", "12", "120", "2", "20", "2", "20", "4", "40", "2", "20", "4", "40", "0", "0", "0", "0", "10"],
  [],
  ["FORTE", "5", "", "0", "", "4", "", "6", "", "3", "", "5", "", "0", "", "4", "", "107", "", "134", "18", "73", "FORTE"],
  [],
  ["DISTILLATE", ...v(16), "5054"],
];

export const CONTEO = [
  ["EXTERIOR", "", "", "INVERNADERO", "", "", "INDOOR", "", "", "HIGH TECH", "", "", "CBDX"],
  ["", "CAJAS", "CONSUMO", "", "CAJAS", "CONSUMO", "", "CAJAS", "CONSUMO", "", "CAJAS", "CONSUMO", "", "CAJAS", "CONSUMO"],
  ["", "TOTALES", "CAJAS", "", "TOTALES", "CAJAS", "", "TOTALES", "CAJAS", "", "TOTALES", "CAJAS", "", "TOTALES", "CAJAS"],
  ["", "HECHAS", "SEMANAL", "", "HECHAS", "SEMANAL", "", "HECHAS", "SEMANAL", "", "HECHAS", "SEMANAL", "", "HECHAS", "SEMANAL"],
  [],
  ["MINI", "", "", "INVERNADERO TOTAL", "", "", "INDOOR TOTAL", "", "", "KUSH WATERHASH", "", "", "T BALLS / GELATO DRY"],
  ["10g", "-7", "33", "4g", "17", "45", "4g", "-14", "52", "4g", "9", "35", "2g", "2", "33"],
  ["", "", "", "10g", "0", "12", "10g", "-5", "10", "10g", "6", "10", "10g", "10", "12"],
  ["TXABAKO SUST"],
  ["10g", "0", "1", "", "", "", "", "", "", "ICE O LATOR", "", "", "BZ1"],
  ["", "", "", "", "", "", "", "", "", "4g", "27", "17", "4g", "11", "37"],
  ["", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
  ["", "", "", "", "", "", "", "", "", "", "", "", "V2 "],
  ["", "", "", "", "", "", "", "", "", "", "", "", "4g", "30", "73"],
  ["", "", "", "", "", "", "", "", "", "", "", "", "10g", "1", "35"],
  [],
  ["", "", "", "", "", "", "", "", "", "", "", "", "VAPER"],
  ["", "", "", "", "", "", "", "", "", "", "", "", "", "51", "9"],
];

export const ALMACEN = [
  ["EXTERIOR", "", "", "INVERNADERO", "", "", "INDOOR POPS", "", "", "HIGH TECH", "", "", "ACEITES Y CREMAS"],
  ["", "", "", "TOTAL 4GR", "25", "100", "TOTAL 4GR", "0", "0", "TOTAL 4GR", "52", "208"],
  ["", "", "", "TOTAL 10GR", "9", "90", "TOTAL 10GR", "0", "0", "TOTAL 10GR", "19", "190"],
  ["", "FIN DIA", "TOTAL GR", "", "FIN DIA", "TOTAL GR", "", "FIN DIA", "TOTAL GR", "", "FIN DIA", "TOTAL GR", "", "FIN DIA"],
  [],
  ["MINI", "1670", "1670", "SLUSH MINTS", "380", "490", "INDOOR PR RELAX", "260", "260", "KUSH WATERHASH", "195", "265", "5% Aislado", "1"],
  ["10g", "0", "", "4g", "15", "", "4g", "0", "", "4g", "10"],
  ["", "", "", "10g", "5", "", "10g", "0", "", "10g", "3", "", "10% FS", "12"],
  ["TXABAKO SUST", "0", "0"],
  ["10g", "0", "", "GRAPEFRUIT", "0", "0", "INDOOR PR AFRU", "440", "440", "BZ1", "417", "505", "20% FS", "94"],
  ["", "", "", "4g", "0", "", "4g", "0", "", "4g", "7"],
];

Deno.test("PRINCIPAL: bloques de producto, granel y cajas del almacén por formato", () => {
  const ps = leerPrincipal(PRINCIPAL);
  assertEquals(ps.map((p) => p.nombre), ["MINI", "SLUSH MINTS", "GRAPEFRUIT", "INDOOR PR RELAX", "INDOOR PR AFRU", "V2", "FORTE", "DISTILLATE"]);
  const v2 = ps.find((p) => p.nombre === "V2")!;
  assertEquals([v2.granel, v2.formatos], ["730", [{ formato: "4g", almacen: "25" }, { formato: "10g", almacen: "10" }]]);
  assertEquals(ps.find((p) => p.nombre === "FORTE")!.conTiendas, true);
  assertEquals(ps.find((p) => p.nombre === "DISTILLATE")!.conTiendas, false);
  const { entradas } = catalogo(ps);
  assertEquals(entradas.some((e) => e.producto === "DISTILLATE"), false); // materia prima, no se reparte
});

Deno.test("CONTEO DE CAJAS TOTAL: grupos, productos sin formato (VAPER) y totales de categoría", () => {
  const cs = leerConteo(CONTEO);
  const fila = (prod: string, f: string) => cs.find((c) => c.producto.trim() === prod && c.formato === f);
  assertEquals([fila("INDOOR TOTAL", "4g")?.contador, fila("INDOOR TOTAL", "4g")?.consumo], ["-14", "52"]);
  assertEquals([fila("V2", "4g")?.contador, fila("V2", "4g")?.consumo], ["30", "73"]);
  assertEquals([fila("VAPER", "")?.contador, fila("VAPER", "")?.consumo], ["51", "9"]);
  assertEquals(fila("TXABAKO SUST", "10g")?.consumo, "1");
  assertEquals(fila("ICE O LATOR", "4g")?.grupo, "HIGH TECH");
});

Deno.test("ALMACEN: categoría de cada producto y variedades que rotan", () => {
  const a = leerAlmacen(ALMACEN);
  assertEquals(a.variedades, { INVERNADERO: ["SLUSH MINTS", "GRAPEFRUIT"], INDOOR: ["INDOOR PR RELAX", "INDOOR PR AFRU"] });
  assertEquals([a.categorias["BZ1"], a.categorias["10%FS"]], ["HIGH TECH", "ACEITES Y CREMAS"]);
});

Deno.test("Extracto real completo: lista de stock calculada", () => {
  const r = calcularStock(leerHoja(PRINCIPAL, CONTEO, ALMACEN), {
    porcentaje: 35,
    excluidos: [{ producto: "MINI", formato: "10g", motivo: "Minis" }, { producto: "VAPER", formato: "", motivo: "R7" }],
  });
  // Indoor 4g: 0,35×52 = 18,2 + 14 = 32,2 → 33. Indoor 10g: 3,5 + 5 = 8,5 → 9. Invernadero 10g: 4,2 → 5.
  // V2 4g: 25,55 − 30 < 0; V2 10g: 12,25 − 1 = 11,25 → 12. Los que no están en el extracto de PRINCIPAL se avisan.
  assertEquals(r.lista.map((e) => `${e.producto} ${e.formato} ${e.cajas}`),
    ["Indoor 4g 33", "V2 10g 12", "Invernadero 10g 5", "Indoor 10g 9"]);
  assertEquals(r.excluidos.map((e) => e.producto), ["MINI", "VAPER"]);
});

Deno.test("R3-15 hoja cambiada: falta un encabezado o una pestaña → ErrorEstructura", () => {
  assertThrows(() => leerPrincipal([["NOMBRE"], ...PRINCIPAL.slice(1)]), ErrorEstructura);
  assertThrows(() => leerPrincipal([PRINCIPAL[0].map((x) => x === "ALMACEN" ? "ALM" : x), ...PRINCIPAL.slice(1)]), ErrorEstructura);
  assertThrows(() => leerConteo([]), ErrorEstructura);
  assertThrows(() => leerConteo([CONTEO[0], CONTEO[1], CONTEO[2], CONTEO[3].map((x) => x === "SEMANAL" ? "MES" : x)]), ErrorEstructura);
  assertThrows(() => leerConteo(CONTEO.filter((f) => !String(f[3] ?? "").includes("INVERNADERO"))), ErrorEstructura);
  assertThrows(() => leerAlmacen([["EXTERIOR"], [], [], ["", "FIN DIA"]]), ErrorEstructura);
});
