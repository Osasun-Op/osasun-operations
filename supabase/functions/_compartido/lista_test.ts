// Reparto con lista (REGLAS_CALCULO.md §2.9, casos L-01 a L-08): catálogo con
// categorías, validación de la lista, texto de WhatsApp y el reparto real del
// 28/10/2026 rehecho con la lista (con el catálogo leído ese día).
import { assertEquals } from "jsr:@std/assert@1";
import type { DatosHoja, Producto } from "./hoja.ts";
import type { Destino } from "./r1.ts";
import { type LineaLista, prepararReparto, referencias, textoWhatsapp, validarLineas, validarPeticiones } from "./lista.ts";

// PRINCIPAL del 28/10/2026 a las 08:47 (cajas en el almacén; granel en los productos sin formato).
const P = (nombre: string, formatos: [string, string][], orden: number, granel = ""): Producto =>
  ({ nombre, granel, formatos: formatos.map(([formato, almacen]) => ({ formato, almacen })), conTiendas: formatos.length === 0, orden });
export const HOJA_28_10: Pick<DatosHoja, "productos" | "categorias"> = {
  productos: [
    P("MINI", [["10g", "30"]], 4), P("TXABAKO SUST", [["20gr", "0"]], 7), P("KRUSH", [["20gr", "8"]], 10),
    P("TROPICANA 2025", [["3g", "0"], ["10g", "9"]], 13), P("SLUSH MINTS", [["4g", "0"], ["10g", "10"]], 17),
    P("ROYAL BERRY", [["4g", "6"], ["10g", "2"]], 21), P("GRAPEFRUIT", [["4g", "0"], ["10g", "0"]], 25),
    P("SOUR DIESEL", [["4g", "20"], ["10g", "5"]], 29), P("YUZU", [["4g", "0"], ["10g", "0"]], 33),
    P("INDOOR PR RELAX", [["4g", "7"], ["10g", "1"]], 37), P("INDOOR PR AFRU", [["4g", "7"], ["10g", "2"]], 41),
    P("KUSH WATERHASH", [["4g", "16"], ["10g", "2"]], 45), P("CBD DRY", [["2g", "8"], ["4g", "0"]], 49),
    P("ICE O LATOR", [["4g", "10"], ["10g", "4"]], 53), P("T BALLS / GELATO DRY", [["2g", "16"], ["4g", "6"]], 57),
    P("BZ1", [["4g", "16"], ["10g", "10"]], 61), P("V2", [["4g", "30"], ["10g", "15"]], 65),
    P("SUGAR", [["CBD", "0"], ["CBDX", "13"]], 69),
    P("5% Aislado", [], 76, "1"), P("10% FS", [], 78, "12"), P("20% FS", [], 80, "90"), P("FORTE", [], 85, "105"),
    P("VAPER", [], 97, "33"),
    { nombre: "DISTILLATE", granel: "100", formatos: [], conTiendas: false, orden: 104 },
  ],
  categorias: {
    MINI: "EXTERIOR", TXABAKOSUST: "EXTERIOR", KRUSH: "EXTERIOR", TROPICANA2025: "EXTERIOR",
    SLUSHMINTS: "INVERNADERO", ROYALBERRY: "INVERNADERO", GRAPEFRUIT: "INVERNADERO", SOURDIESEL: "INVERNADERO",
    YUZU: "INVERNADERO", INDOORPRRELAX: "INDOOR POPS", INDOORPRAFRU: "INDOOR POPS", KUSHWATERHASH: "HIGH TECH",
    CBDDRY: "HIGH TECH", ICEOLATOR: "HIGH TECH", "TBALLS/GELATODRY": "HIGH TECH", BZ1: "HIGH TECH", V2: "HIGH TECH",
    "5%AISLADO": "ACEITES Y CREMAS", "10%FS": "ACEITES Y CREMAS", "20%FS": "ACEITES Y CREMAS", FORTE: "ACEITES Y CREMAS",
    VAPER: "ACEITES Y CREMAS",
  },
};
export const TIENDAS: Destino[] = [
  { id: "bilbao", nombre: "Bilbao", alias: ["BILBAO"] },
  { id: "algorta", nombre: "Algorta", alias: ["ALGORTA"] },
  { id: "barakaldo", nombre: "Barakaldo", alias: ["BARAKALDO"] },
  { id: "basauri", nombre: "Basauri", alias: ["BASAURI"] },
  { id: "portu", nombre: "Portugalete", alias: ["PORTU"] },
];

// El WhatsApp del 28/10 (36 de 52 líneas no se reconocieron), elegido en la lista.
const L = (destino_id: string, producto: string, formato: string, cantidad: number): LineaLista =>
  ({ destino_id, producto, formato, cantidad });
export const REPARTO_28_10: LineaLista[] = [
  L("bilbao", "MINI", "10g", 6), L("bilbao", "KRUSH", "20gr", 3), L("bilbao", "SLUSH MINTS", "10g", 5),
  L("bilbao", "INDOOR PR RELAX", "4g", 1), L("bilbao", "T BALLS / GELATO DRY", "2g", 4), L("bilbao", "BZ1", "4g", 2),
  L("algorta", "ROYAL BERRY", "4g", 3), L("algorta", "KUSH WATERHASH", "4g", 1), L("algorta", "CBD DRY", "4g", 2),
  L("algorta", "T BALLS / GELATO DRY", "2g", 2), L("algorta", "BZ1", "4g", 6), L("algorta", "BZ1", "10g", 4),
  L("algorta", "20% FS", "", 3),
  L("barakaldo", "ROYAL BERRY", "4g", 2), L("barakaldo", "INDOOR PR RELAX", "4g", 4), L("barakaldo", "INDOOR PR AFRU", "4g", 2),
  L("barakaldo", "BZ1", "4g", 2), L("barakaldo", "BZ1", "10g", 2), L("barakaldo", "V2", "4g", 4),
  L("basauri", "MINI", "10g", 16), L("basauri", "ROYAL BERRY", "4g", 4), L("basauri", "INDOOR PR RELAX", "4g", 4),
  L("basauri", "INDOOR PR AFRU", "4g", 6), L("basauri", "ICE O LATOR", "4g", 2), L("basauri", "ICE O LATOR", "10g", 1),
  L("basauri", "T BALLS / GELATO DRY", "2g", 4), L("basauri", "BZ1", "4g", 4), L("basauri", "BZ1", "10g", 2),
  L("basauri", "V2", "4g", 7), L("basauri", "V2", "10g", 4), L("basauri", "SUGAR", "CBDX", 5), L("basauri", "VAPER", "", 2),
  L("portu", "MINI", "10g", 2), L("portu", "TROPICANA 2025", "10g", 2), L("portu", "SLUSH MINTS", "10g", 4),
  L("portu", "INDOOR PR AFRU", "4g", 3), L("portu", "INDOOR PR AFRU", "10g", 1), L("portu", "CBD DRY", "4g", 3),
];

const { entradas, referencias: refs } = referencias(HOJA_28_10);

Deno.test("L-01 catálogo: una referencia por producto y formato, en el orden de la hoja, con su categoría", () => {
  assertEquals(refs.slice(0, 3).map((r) => [r.clave, r.categoria]),
    [["MINI|10g", "EXTERIOR"], ["TXABAKO SUST|20gr", "EXTERIOR"], ["KRUSH|20gr", "EXTERIOR"]]);
  assertEquals(refs.find((r) => r.producto === "VAPER"), { clave: "VAPER|", producto: "VAPER", formato: "", categoria: "ACEITES Y CREMAS", orden: 9700 });
  assertEquals(refs.some((r) => r.producto === "DISTILLATE"), false); // materia prima: no va a las tiendas
});

Deno.test("L-02 sin categoría en ALMACEN: «Otros»", () => {
  const r = referencias({ productos: [P("NUEVO", [["4g", "1"]], 1)], categorias: {} }).referencias;
  assertEquals(r[0].categoria, "Otros");
});

Deno.test("L-03 referencia que ya no está en la hoja: REFERENCIA_NO_EXISTE con cuál", () => {
  const v = validarLineas([L("bilbao", "V2", "4g", 1), L("bilbao", "GELATO", "4g", 2)], entradas, TIENDAS);
  assertEquals(v.ok ? null : [v.codigo, v.detalle], ["REFERENCIA_NO_EXISTE", { referencias: [{ producto: "GELATO", formato: "4g" }] }]);
});

Deno.test("L-04 tienda no válida, cantidad negativa o lista vacía: DATOS_NO_VALIDOS", () => {
  const codigo = (x: unknown) => { const v = validarLineas(x, entradas, TIENDAS); return v.ok ? "ok" : v.codigo; };
  assertEquals(codigo([L("donosti", "V2", "4g", 1)]), "DATOS_NO_VALIDOS");
  assertEquals(codigo([L("bilbao", "V2", "4g", -1)]), "DATOS_NO_VALIDOS");
  assertEquals(codigo([L("bilbao", "V2", "4g", 1.5)]), "DATOS_NO_VALIDOS");
  assertEquals(codigo([L("bilbao", "V2", "4g", 0)]), "DATOS_NO_VALIDOS");
  assertEquals(codigo([]), "DATOS_NO_VALIDOS");
  assertEquals(codigo("nada"), "DATOS_NO_VALIDOS");
});

Deno.test("L-05 contadores a 0 se ignoran, repetidas se suman y se ordena por tienda y por la hoja", () => {
  const v = validarLineas([L("algorta", "V2", "4g", 2), L("bilbao", "bz1", "4G", 1), L("bilbao", "MINI", "10g", 0),
                           L("algorta", "V2", "4g", 3), L("bilbao", "MINI", "10g", 4)], entradas, TIENDAS);
  assertEquals(v.ok ? v.lineas : v, [L("bilbao", "MINI", "10g", 4), L("bilbao", "BZ1", "4g", 1), L("algorta", "V2", "4g", 5)]);
});

Deno.test("L-06 texto para WhatsApp con el formato de siempre", () => {
  const v = validarLineas([L("bilbao", "MINI", "10g", 6), L("bilbao", "20% FS", "", 3), L("portu", "BZ1", "4g", 2)], entradas, TIENDAS);
  assertEquals(textoWhatsapp("reparto", { dia: 3, mes: 11 }, "operario", v.ok ? v.lineas : [], TIENDAS),
    "REPARTO 03/11\nSALE: ALMACÉN\n\nBILBAO\n6x MINI 10g\n3x 20% FS\n\nPORTU\n2x BZ1 4g");
  assertEquals(textoWhatsapp("envio", { dia: 3, mes: 11 }, null, [L("gipuzkoa", "V2", "4g", 4)],
    [{ id: "gipuzkoa", nombre: "Gipuzkoa (envío a Rentería)", alias: ["GIPUZKOA"] }]),
    "ENVÍO 03/11\n\nGIPUZKOA\n4x V2 4g");
});

Deno.test("L-10 peticiones especiales: «Además: …» tras los productos de su tienda; vacías fuera y repetidas una vez (R1d)", () => {
  const pv = validarPeticiones([{ destino_id: "portu", texto: "Rollos de TPV" }, { destino_id: "bilbao", texto: " muestras\n de V2 " },
                                { destino_id: "bilbao", texto: "   " }, { destino_id: "bilbao", texto: "MUESTRAS DE V2" }], TIENDAS);
  assertEquals(pv, { ok: true, peticiones: [{ destino_id: "bilbao", texto: "muestras de V2" }, { destino_id: "portu", texto: "Rollos de TPV" }] });
  assertEquals(textoWhatsapp("reparto", { dia: 3, mes: 11 }, "operario", [L("bilbao", "MINI", "10g", 6)], TIENDAS, pv.ok ? pv.peticiones : []),
    "REPARTO 03/11\nSALE: ALMACÉN\n\nBILBAO\n6x MINI 10g\nAdemás: muestras de V2\n\nPORTU\nAdemás: Rollos de TPV");
  assertEquals(validarPeticiones(undefined, TIENDAS), { ok: true, peticiones: [] });
  assertEquals(validarPeticiones("rollos", TIENDAS).ok, false);
  assertEquals(validarPeticiones([{ destino_id: "donosti", texto: "x" }], TIENDAS).ok, false);
});

Deno.test("L-07 el reparto real del 28/10 con la lista: se reconoce entero; producción y bolsas coherentes", () => {
  const v = validarLineas(REPARTO_28_10, entradas, TIENDAS);
  if (!v.ok) throw new Error(v.mensaje);
  const { texto, r } = prepararReparto({ tipo: "reparto", hoy: { dia: 28, mes: 10 }, sale: "administracion", lineas: v.lineas, destinos: TIENDAS, entradas });
  assertEquals([r.estado, r.sale, r.errores.length], ["aceptado", "administracion", 0]);
  assertEquals(texto.split("\n").slice(0, 4), ["REPARTO 28/10", "SALE: YO", "", "BILBAO"]);
  // Pedido total frente a lo que hay en el almacén: solo faltan cuatro referencias.
  const falta = Object.fromEntries(r.produccion.filter((p) => p.faltan > 0).map((p) => [`${p.producto} ${p.formato}`.trim(), p.faltan]));
  assertEquals(falta, { "INDOOR PR RELAX 4g": 2, "INDOOR PR AFRU 4g": 4, "ROYAL BERRY 4g": 3, "CBD DRY 4g": 5 });
  assertEquals(r.produccion.find((p) => p.producto === "MINI"), { producto: "MINI", formato: "10g", pedido: 24, en_almacen: 30, apartado_reparto: 0, faltan: 0, aviso: null, orden: 400 });
  assertEquals(r.produccion.length, 20); // referencias distintas pedidas
  // Bolsas: las cinco tiendas, con todas sus cajas (134 en total).
  const bolsas = Object.fromEntries(r.bolsas.map((b) => [b.destino, [b.items.length, b.items.reduce((s, i) => s + i.cantidad, 0)]]));
  assertEquals(bolsas, { Bilbao: [6, 21], Algorta: [7, 21], Barakaldo: [6, 16], Basauri: [13, 61], Portugalete: [6, 15] });
});

Deno.test("L-08 envío antes del recuento con la lista: se apartan las cajas del reparto de hoy", () => {
  const destinos = [{ id: "gipuzkoa", nombre: "Gipuzkoa (envío a Rentería)", alias: ["GIPUZKOA"] }];
  const v = validarLineas([L("gipuzkoa", "V2", "4g", 8)], entradas, destinos);
  const { r } = prepararReparto({ tipo: "envio", hoy: { dia: 28, mes: 10 }, sale: null, lineas: v.ok ? v.lineas : [], destinos, entradas,
                                  apartadoReparto: [{ producto: "V2", formato: "4g", pedido: 25 }] });
  assertEquals([r.estado, r.sale, r.produccion[0].en_almacen, r.produccion[0].faltan], ["aceptado", null, 5, 3]);
});
