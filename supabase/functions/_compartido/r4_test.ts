// Pruebas de R4 · cobertura a 2 semanas (REGLAS_CALCULO.md §4, casos R4-01 a R4-11).
import { assertEquals } from "jsr:@std/assert@1";
import type { Producto } from "./hoja.ts";
import { leerHoja } from "./hoja.ts";
import { calcularCobertura } from "./r4.ts";
import { ALMACEN, CONTEO, PRINCIPAL } from "./hoja_test.ts";

let fila = 0;
const p = (nombre: string, total: string, necesidad: string, formatos = ["4g"]): Producto => ({
  nombre, granel: "0", formatos: formatos.map((formato) => ({ formato, almacen: "0" })), conTiendas: false,
  orden: fila++, total, necesidad,
});
const variedades = { INVERNADERO: ["SLUSH MINTS", "ROYAL BERRY", "GRAPEFRUIT"], INDOOR: ["INDOOR PR RELAX"] };
const EXCLUIDOS = [{ producto: "MINI" }, { producto: "VAPER" }];
const calcular = (productos: Producto[]) => calcularCobertura({ productos, variedades }, EXCLUIDOS);

Deno.test("R4-01 por encima de 2 semanas: no sale", () => {
  // BZ1: 701 frente a 2 × 300 = 600.
  assertEquals(calcular([p("BZ1", "701", "300")]), { productos: [], avisos: [] });
});

Deno.test("R4-02 por debajo: sale, con sus semanas y su motivo", () => {
  // KUSH WATERHASH: 302 frente a 2 × 219 = 438 → 1,3 semanas.
  assertEquals(calcular([p("KUSH WATERHASH", "302", "219")]).productos, [{
    producto: "KUSH WATERHASH", formato: "", total: 302, necesidad_semana: 219, semanas: 1.3,
    motivo: "Hay 302 en total y se necesitan 219 a la semana: da para 1,3 semanas.",
  }]);
});

Deno.test("R4-03 justo 2 semanas: no sale (solo por debajo)", () => {
  assertEquals(calcular([p("ICE O LATOR", "198", "99")]).productos, []);
});

Deno.test("R4-04 Invernadero por categoría: se suma toda la categoría, una sola fila", () => {
  // 662 + 306 + 4 = 972 frente a 2 × (68,5 + 28 + 105,5) = 404: bien, aunque Grapefruit solo tenga 4.
  const bien = calcular([p("SLUSH MINTS", "662", "68,5"), p("ROYAL BERRY", "306", "28"), p("GRAPEFRUIT", "4", "105,5")]);
  assertEquals(bien.productos, []);
  // 100 + 50 + 4 = 154 frente a 404 → 0,7 semanas.
  const mal = calcular([p("SLUSH MINTS", "100", "68,5"), p("ROYAL BERRY", "50", "28"), p("GRAPEFRUIT", "4", "105,5")]);
  assertEquals(mal.productos.map((x) => [x.producto, x.total, x.necesidad_semana, x.semanas]), [["Invernadero", 154, 202, 0.7]]);
});

Deno.test("R4-05 minis y vapers fuera, y lo que tiene necesidad 0", () => {
  assertEquals(calcular([p("MINI", "10", "305", ["10g"]), p("VAPER", "1", "7", []), p("SUGAR", "0", "0", ["CBD"])]),
               { productos: [], avisos: [] });
});

Deno.test("R4-06 dato vacío o raro: no se inventa, va a un aviso", () => {
  const r = calcular([p("CBD DRY", "", "61"), p("TXABAKO SUST", "-40", "5"), p("INDOOR PR RELAX", "297", "x")]);
  assertEquals(r.productos, []);
  assertEquals(r.avisos, [
    "No puedo calcular CBD DRY en PRINCIPAL (CBD DRY: dato vacío o no válido).",
    "No puedo calcular TXABAKO SUST en PRINCIPAL (TXABAKO SUST: el total es negativo (-40)).",
    "No puedo calcular Indoor en PRINCIPAL (INDOOR PR RELAX: dato vacío o no válido).",
  ]);
});

// Un bloque de PRINCIPAL sin formatos ni tiendas: materia prima o consumible (Tarea 44).
const bloque = (nombre: string, total: string, necesidad: string): Producto =>
  ({ nombre, granel: "0", formatos: [], conTiendas: false, orden: fila++, total, necesidad });

Deno.test("R4-07 orden: de menos a más semanas; la materia prima cuenta como lo demás (Tarea 44)", () => {
  // La lectura del 23/11 a las 15:16: DISTILLATE 0 y 581 (sale, 0 semanas); CBDX 810 y 114,6 (no sale: 810 ≥ 229,2).
  const r = calcular([p("KUSH WATERHASH", "302", "219"), p("GRAPEFRUIT", "4", "105,5"),
                      bloque("DISTILLATE", "0", "581"), bloque("CBDX", "810", "114,6")]);
  assertEquals(r.productos.map((x) => [x.producto, x.semanas]), [["Invernadero", 0], ["DISTILLATE", 0], ["KUSH WATERHASH", 1.3]]);
  assertEquals(r.productos.find((x) => x.producto === "DISTILLATE")?.motivo,
               "Hay 0 en total y se necesitan 581 a la semana: da para 0 semanas.");
  assertEquals(r.avisos, []);
});

Deno.test("R4-09 materia prima con necesidad 0: no sale", () => {
  assertEquals(calcular([bloque("DISTILLATE", "0", "0")]), { productos: [], avisos: [] });
});

Deno.test("R4-10 un consumible nuevo en su propio bloque: sale sin tocar nada más", () => {
  // «CAJAS ENVÍO», 50 frente a 2 × 40 = 80 → 1,2 semanas.
  assertEquals(calcular([bloque("CAJAS ENVÍO", "50", "40")]).productos, [{
    producto: "CAJAS ENVÍO", formato: "", total: 50, necesidad_semana: 40, semanas: 1.2,
    motivo: "Hay 50 en total y se necesitan 40 a la semana: da para 1,2 semanas.",
  }]);
});

Deno.test("R4-11 materia prima con la necesidad vacía: aviso, como el resto", () => {
  assertEquals(calcular([bloque("DISTILLATE", "0", "")]), {
    productos: [], avisos: ["No puedo calcular DISTILLATE en PRINCIPAL (DISTILLATE: dato vacío o no válido)."],
  });
});

Deno.test("R4-08 con el extracto real de la hoja (columnas por su encabezado)", () => {
  const r = calcularCobertura(leerHoja(PRINCIPAL, CONTEO, ALMACEN), EXCLUIDOS);
  // Invernadero: 772 − 10 = 762 frente a 2 × (68,5 + 107,5) = 352: bien. GRAPEFRUIT tiene −10 en total → aviso de la categoría.
  // Indoor: 344 + 558 = 902 frente a 2 × (157,5 + 133,5) = 582: bien. V2: 1498 frente a 1297: bien. FORTE: 134 frente a 36: bien.
  // Tarea 44: el DISTILLATE (materia prima) también cuenta; en este extracto (26/10) no tiene total ni necesidad → aviso.
  assertEquals(r.productos, []);
  assertEquals(r.avisos, ["No puedo calcular Invernadero en PRINCIPAL (GRAPEFRUIT: el total es negativo (-10)).",
                          "No puedo calcular DISTILLATE en PRINCIPAL (DISTILLATE: dato vacío o no válido)."]);
  const sinColumnas = leerHoja([PRINCIPAL[0].map((x) => x === "LO QUE HAY EN TOTAL" ? "" : x), ...PRINCIPAL.slice(1)], CONTEO, ALMACEN);
  assertEquals(calcularCobertura(sinColumnas, EXCLUIDOS).avisos,
               ["No encuentro las columnas «LO QUE HAY EN TOTAL» y «1 SEMANA NECESIDADES» en PRINCIPAL."]);
});
