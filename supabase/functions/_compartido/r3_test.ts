// Casos de R3 de REGLAS_CALCULO.md §3.8. R3-15/16 (hoja cambiada o no disponible)
// en hoja_test.ts y google_test.ts; R3-17 (dos veces en el turno) en supabase/tests/07.
import { assertEquals } from "jsr:@std/assert@1";
import type { Conteo, DatosHoja, Producto } from "./hoja.ts";
import { ajustesStock, cajasR3, calcularStock, type ConfigR3 } from "./r3.ts";

const CFG: ConfigR3 = {
  porcentaje: 35,
  excluidos: [
    { producto: "MINIBUDS MIX", formato: "10g", motivo: "Minis" },
    { producto: "VAPER", formato: "", motivo: "R7" },
  ],
};

let fila = 0;
const c = (producto: string, formato: string, contador: string, consumo: string, grupo = "HIGH TECH"): Conteo =>
  ({ grupo, producto, formato, contador, consumo, orden: fila++ });
const p = (nombre: string, granel: string): Producto => ({ nombre, granel, formatos: [], conTiendas: false, orden: fila++ });

function datos(conteo: Conteo[], productos: Producto[] = [], variedades: DatosHoja["variedades"] = { INVERNADERO: [], INDOOR: [] }): DatosHoja {
  return { conteo, productos, categorias: {}, variedades };
}
const unico = (d: DatosHoja) => calcularStock(d, CFG);
const cajas = (d: DatosHoja) => unico(d).lista.map((e) => e.cajas);

Deno.test("R3-01 V2 4g: consumo 74, contador +25 → 1 caja", () => {
  const r = unico(datos([c("V2 ", "4g", "25", "74")], [p("V2 ", "730")]));
  assertEquals(r.lista[0].cajas, 1);
  assertEquals(r.lista[0].producto, "V2");
  assertEquals(r.lista[0].motivo, "Se venden 74 cajas a la semana. Tienes +25 y el objetivo es +26. Haz 1.");
});

Deno.test("R3-02 Indoor 4g: consumo 51, contador −27 → 45 cajas", () => {
  const d = datos([c("INDOOR TOTAL", "4g", "-27", "51", "INDOOR")],
    [p("INDOOR PR RELAX", "260"), p("INDOOR PR AFRU", "440")],
    { INVERNADERO: [], INDOOR: ["INDOOR PR RELAX", "INDOOR PR AFRU"] });
  const r = unico(d);
  assertEquals([r.lista[0].producto, r.lista[0].cajas], ["Indoor", 45]);
});

Deno.test("R3-03 ICE O LATOR 4g ya cubierto: no aparece", () => {
  assertEquals(cajas(datos([c("ICE O LATOR", "4g", "27", "17")], [p("ICE O LATOR", "92")])), []);
});

Deno.test("R3-04 justo en el objetivo: no aparece", () => {
  assertEquals(cajas(datos([c("X", "4g", "7", "20")], [p("X", "100")])), []);
});

Deno.test("R3-05 consumo 0, contador −3 → 3 cajas", () => {
  assertEquals(cajas(datos([c("X", "4g", "-3", "0")], [p("X", "100")])), [3]);
});

Deno.test("R3-06 TROPICANA 2025 10g → 10 cajas", () => {
  assertEquals(cajas(datos([c("TROPICANA 2025", "10g", "3", "36")], [p("TROPICANA 2025", "1136")])), [10]);
});

Deno.test("R3-07 MINIBUDS MIX 10g excluido (minis)", () => {
  const r = unico(datos([c("MINIBUDS MIX", "10g", "-7", "33", "EXTERIOR")], [p("MINIBUDS MIX", "1670")]));
  assertEquals([r.lista.length, r.excluidos[0].motivo], [0, "Minis"]);
});

Deno.test("R3-08 sin granel: no se produce y se avisa", () => {
  const r = unico(datos([c("X", "4g", "0", "10")], [p("X", "0")]));
  assertEquals([r.lista.length, r.faltas], [0, ["X"]]);
});

Deno.test("R3-09 Invernadero 4g cubierto: no aparece", () => {
  assertEquals(cajas(datos([c("INVERNADERO TOTAL", "4g", "17", "45", "INVERNADERO")], [p("SLUSH MINTS", "380")],
    { INVERNADERO: ["SLUSH MINTS"], INDOOR: [] })), []);
});

Deno.test("R3-10 Invernadero 10g → 5 cajas, con las variedades con granel y la frase de FIFO", () => {
  const r = unico(datos([c("INVERNADERO TOTAL", "10g", "0", "12", "INVERNADERO")],
    [p("SLUSH MINTS", "380"), p("ROYAL BERRY", "127"), p("GRAPEFRUIT", "0")],
    { INVERNADERO: ["SLUSH MINTS", "ROYAL BERRY", "GRAPEFRUIT"], INDOOR: [] }));
  assertEquals(r.lista[0].cajas, 5);
  assertEquals(r.lista[0].variedades?.map((v) => v.nombre), ["SLUSH MINTS", "ROYAL BERRY"]);
  assertEquals(r.lista[0].motivo.endsWith(
    "Variedades con granel: SLUSH MINTS, ROYAL BERRY. Usa primero el granel más antiguo (FIFO). Mínimo 2 variedades de invernadero y 2 de indoor."), true);
});

Deno.test("R3-11 Indoor sin granel en ninguna variedad: «falta Indoor»", () => {
  const r = unico(datos([c("INDOOR TOTAL", "4g", "-27", "51", "INDOOR")],
    [p("INDOOR PR RELAX", "0"), p("INDOOR PR AFRU", "0")], { INVERNADERO: [], INDOOR: ["INDOOR PR RELAX", "INDOOR PR AFRU"] }));
  assertEquals([r.lista.length, r.faltas], [0, ["Indoor"]]);
});

Deno.test("R3-12 orden por consumo; empate, el orden de la hoja", () => {
  const r = unico(datos([c("A", "4g", "-10", "52"), c("B", "4g", "-10", "73"), c("C", "4g", "-10", "52")],
    [p("A", "1"), p("B", "1"), p("C", "1")]));
  assertEquals(r.lista.map((e) => e.producto), ["B", "A", "C"]);
});

Deno.test("R3-13 dato vacío: esa referencia no se calcula y se avisa; las demás sí", () => {
  const r = unico(datos([c("A", "4g", "0", ""), c("B", "4g", "0", "10")], [p("A", "1"), p("B", "1")]));
  assertEquals(r.lista.map((e) => e.producto), ["B"]);
  assertEquals(r.avisos, ["No puedo calcular A 4g: dato vacío o no válido en CONTEO DE CAJAS TOTAL."]);
});

Deno.test("R3-14 consumo con coma decimal 2,5 → 1 caja", () => {
  assertEquals(cajas(datos([c("X", "4g", "0", "2,5")], [p("X", "1")])), [1]);
});

Deno.test("R3-18 redondeo hacia arriba: 0,3 → 1", () => {
  assertEquals(cajasR3(1000, 320), 1);
  assertEquals(cajas(datos([c("X", "4g", "3,2", "10")], [p("X", "1")])), [1]);
});

Deno.test("R3-19 VAPER excluido (R7)", () => {
  const r = unico(datos([c("VAPER", "", "-5", "9", "CBDX")], [p("VAPER", "33")]));
  assertEquals([r.lista.length, r.excluidos[0].motivo], [0, "R7"]);
});

Deno.test("R3-20 hay granel pero no da para todo: se lista igual", () => {
  assertEquals(cajas(datos([c("Y", "4g", "0", "40")], [p("Y", "8")])), [14]);
});

Deno.test("Granel vacío o producto que no está en PRINCIPAL: aviso, nunca se inventa", () => {
  const r = unico(datos([c("A", "4g", "0", "10"), c("B", "4g", "0", "10")], [p("A", "")]));
  assertEquals(r.lista.length, 0);
  assertEquals(r.avisos, [
    "No puedo calcular A 4g: el granel está vacío o no es un número en PRINCIPAL.",
    "No puedo calcular B 4g: no está en PRINCIPAL.",
  ]);
});

Deno.test("R3-21 cajas en camino (R1c): el contador sube por lo que ya salió hacia las tiendas", () => {
  // V2 4g: consumo 74, contador de la hoja +20 (el recuento ya quitó 5 cajas del reparto) → con las 5 en camino, +25 → 1 caja.
  const d = datos([c("V2 ", "4g", "20", "74")], [p("V2 ", "730")]);
  assertEquals(unico(d).lista[0].cajas, 6);
  const r = calcularStock(d, CFG, [{ producto: "V2", formato: "4g", en_camino: 5 }]);
  assertEquals([r.lista[0].cajas, r.lista[0].en_camino], [1, 5]);
  assertEquals(r.lista[0].motivo, "Se venden 74 cajas a la semana. Tienes +25 (con 5 en camino a las tiendas) y el objetivo es +26. Haz 1.");
});

Deno.test("R3-22 cajas en camino de una variedad de Indoor: suman al total de su categoría y formato", () => {
  const d = datos([c("INDOOR TOTAL", "4g", "-27", "51", "INDOOR"), c("INDOOR TOTAL", "10g", "-5", "10", "INDOOR")],
    [p("INDOOR PR RELAX", "260")], { INVERNADERO: [], INDOOR: ["INDOOR PR RELAX"] });
  const r = calcularStock(d, CFG, [{ producto: "INDOOR PR RELAX", formato: "4g", en_camino: 10 }, { producto: "NADA", formato: "4g", en_camino: 3 }]);
  // 4g: −27 + 10 = −17 → 18 + 17 = 35 cajas (antes 45). 10g sin cambios: 4 + 5 = 9.
  assertEquals(r.lista.map((e) => [e.formato, e.cajas, e.en_camino ?? 0]), [["4g", 35, 10], ["10g", 9, 0]]);
});

Deno.test("R3-23 sin cajas en camino (antes del recuento o al día siguiente) la lista es la de siempre", () => {
  const d = datos([c("V2 ", "4g", "25", "74")], [p("V2 ", "730")]);
  assertEquals(calcularStock(d, CFG, []).lista, unico(d).lista);
});

// R1c rehecha (Tarea 14): cajas de todas partes = hoja + hechas desde el recuento − salidas + en camino.
Deno.test("R3-24 12:45, después del recuento: almacén 5 y tienda 3 en la hoja, más 3 del reparto en camino → 11", () => {
  const d = datos([c("V2 ", "4g", "8", "40")], [p("V2 ", "730")]);
  const r = calcularStock(d, CFG, ajustesStock({ producido: [], salido: [] }, [{ producto: "V2", formato: "4g", cantidad: 3 }]));
  assertEquals(r.lista[0].motivo, "Se venden 40 cajas a la semana. Tienes +11 (con 3 en camino a las tiendas) y el objetivo es +14. Haz 3.");
});

Deno.test("R3-25 17:55: almacén 8 y Gipuzkoa 4 en la hoja, más 4 en la caja de Nacex → 16", () => {
  const d = datos([c("V2 ", "4g", "12", "60")], [p("V2 ", "730")]);
  const r = calcularStock(d, CFG, [{ producto: "V2", formato: "4g", en_camino: 4 }]);
  assertEquals([r.lista[0].cajas, r.lista[0].en_camino], [5, 4]);
  assertEquals(r.lista[0].motivo, "Se venden 60 cajas a la semana. Tienes +16 (con 4 en camino a las tiendas) y el objetivo es +21. Haz 5.");
});

Deno.test("R3-26 antes del recuento: la hoja aún cuenta en el almacén lo que ya salió; salido y en camino se compensan (no cuenta dos veces)", () => {
  const d = datos([c("V2 ", "4g", "11", "40")], [p("V2 ", "730")]);
  const r = calcularStock(d, CFG, ajustesStock({ producido: [], salido: [{ producto: "V2", formato: "4g", cantidad: 3 }] },
                                              [{ producto: "V2", formato: "4g", cantidad: 3 }]));
  assertEquals([r.lista[0].cajas, r.lista[0].en_camino], [3, undefined]);
  assertEquals(r.lista[0].motivo, "Se venden 40 cajas a la semana. Tienes +11 y el objetivo es +14. Haz 3.");
});

Deno.test("R3-27 lo hecho desde el recuento suma; un pedido de Nacex sale del stock (no va a ninguna tienda)", () => {
  const d = datos([c("V2 ", "4g", "8", "40")], [p("V2 ", "730")]);
  const r = calcularStock(d, CFG, ajustesStock({ producido: [{ producto: "V2", formato: "4g", cantidad: 6 }],
                                                 salido: [{ producto: "V2", formato: "4g", cantidad: 2 }] }, []));
  assertEquals(r.lista[0].motivo,
    "Se venden 40 cajas a la semana. Tienes +12 (con 6 hechas desde el recuento y sin 2 que ya han salido) y el objetivo es +14. Haz 2.");
});
