// Casos de R1 de REGLAS_CALCULO.md §2.8 (los que no dependen de la base de datos).
// R1-10 (pegar dos veces) y R1-21 (reparto corregido) están en supabase/tests/07;
// R1-11 (hoja no disponible) en google_test.ts.
import { assertEquals } from "jsr:@std/assert@1";
import { analizarReparto, catalogo, type Destino, type EntradaCatalogo, type OpcionesR1 } from "./r1.ts";
import type { Producto } from "./hoja.ts";

const CAT: EntradaCatalogo[] = [
  { producto: "V2", formato: "4g", almacen: "25", orden: 1 },
  { producto: "V2", formato: "10g", almacen: "10", orden: 2 },
  { producto: "BZ1", formato: "4g", almacen: "7", orden: 3 },
  { producto: "T BALLS / GELATO DRY", formato: "2g", almacen: "0", orden: 4 },
  { producto: "KRUSH", formato: "20gr", almacen: "0", orden: 5 },
  { producto: "FORTE", formato: "", almacen: "107", orden: 6 },
  { producto: "LORANAT", formato: "", almacen: "", orden: 7 },
];
const DESTINOS: Destino[] = [
  { id: "bilbao", nombre: "Bilbao", alias: ["BILBAO"] },
  { id: "algorta", nombre: "Algorta", alias: ["ALGORTA"] },
  { id: "durango", nombre: "Durango", alias: ["DURANGO", "LAUDIO"] },
  { id: "gipuzkoa", nombre: "Gipuzkoa (envío a Rentería)", alias: ["GIPUZKOA"] },
];
const HOY = { dia: 27, mes: 10 };
const r1 = (lineas: string[], op: Partial<OpcionesR1> = {}) =>
  analizarReparto(lineas.join("\n"), CAT, DESTINOS, { tipo: "reparto", hoy: HOY, ...op });
const faltan = (r: ReturnType<typeof r1>) =>
  Object.fromEntries(r.produccion.map((p) => [`${p.producto} ${p.formato}`.trim(), p.faltan]));
const errores = (r: ReturnType<typeof r1>) => r.errores.map((e) => `${e.num}:${e.error}`);

Deno.test("R1-01 reparto normal: suma, resta lo del almacén y bolsas por tienda", () => {
  const r = r1(["REPARTO 27/10", "SALE: ALMACÉN", "BILBAO", "20x V2 4g", "5x BZ1 4g", "ALGORTA", "10x V2 4g", "4x BZ1 4g", "1x FORTE"]);
  assertEquals(r.estado, "aceptado");
  assertEquals(r.sale, "operario");
  assertEquals(faltan(r), { "V2 4g": 5, "BZ1 4g": 2, "FORTE": 0 });
  assertEquals(r.produccion.find((p) => p.producto === "V2")?.pedido, 30);
  assertEquals(r.bolsas.map((b) => [b.destino, b.items.map((i) => `${i.cantidad} ${i.producto} ${i.formato}`.trim())]), [
    ["Bilbao", ["20 V2 4g", "5 BZ1 4g"]],
    ["Algorta", ["10 V2 4g", "4 BZ1 4g", "1 FORTE"]],
  ]);
});

Deno.test("R1-02 ignora mayúsculas y espacios; SALE: YO = Administración", () => {
  const r = r1(["bilbao", "  3 X  t balls / gelato dry 2G ", "1x v2 4 g", "SALE: YO"]);
  assertEquals(r.estado, "aceptado");
  assertEquals(r.sale, "administracion");
  assertEquals(faltan(r), { "V2 4g": 0, "T BALLS / GELATO DRY 2g": 3 });
});

Deno.test("R1-03 producto desconocido: no se calcula", () => {
  const r = r1(["SALE: ALMACÉN", "BILBAO", "2x V2 5g"]);
  assertEquals(r.estado, "con_errores");
  assertEquals(errores(r), ["3:PRODUCTO_DESCONOCIDO"]);
});

Deno.test("R1-04 línea no reconocida", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN", "BILBAO", "2x V2 4g", "lo de ayer también"])), ["4:LINEA_NO_RECONOCIDA"]);
});

Deno.test("R1-05 producto sin tienda antes", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN", "2x V2 4g", "BILBAO"])), ["2:PRODUCTO_SIN_TIENDA"]);
});

Deno.test("R1-06 falta SALE: se pregunta; con la respuesta, aceptado", () => {
  assertEquals(r1(["BILBAO", "2x V2 4g"]).estado, "falta_sale");
  const r = r1(["BILBAO", "2x V2 4g"], { sale: "administracion" });
  assertEquals([r.estado, r.sale], ["aceptado", "administracion"]);
});

Deno.test("R1-07 DURANGO y LAUDIO son la misma bolsa", () => {
  const r = r1(["SALE: ALMACÉN", "DURANGO", "2x V2 4g", "LAUDIO", "1x V2 4g"]);
  assertEquals(r.bolsas.length, 1);
  assertEquals([r.bolsas[0].destino, r.bolsas[0].items[0].cantidad], ["Durango", 3]);
});

Deno.test("R1-08 cantidad 0 no vale", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN", "BILBAO", "0x V2 4g"])), ["3:CANTIDAD_NO_VALIDA"]);
});

Deno.test("R1-09 la misma referencia repetida en una tienda se suma", () => {
  const r = r1(["SALE: ALMACÉN", "BILBAO", "2x V2 4g", "3x V2 4g"]);
  assertEquals(r.bolsas[0].items, [{ producto: "V2", formato: "4g", cantidad: 5, orden: 1 }]);
});

Deno.test("R1-12 dos SALE: distintas", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN", "SALE: YO", "BILBAO", "1x V2 4g"])), ["0:SALE_CONTRADICTORIA"]);
});

Deno.test("R1-13 KRUSH 20gr sí; 20g no (no hay equivalencias)", () => {
  assertEquals(r1(["SALE: ALMACÉN", "BILBAO", "1x KRUSH 20gr"]).estado, "aceptado");
  assertEquals(errores(r1(["SALE: ALMACÉN", "BILBAO", "1x KRUSH 20g"])), ["3:PRODUCTO_DESCONOCIDO"]);
});

Deno.test("R1-14 todos los errores a la vez", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN", "BILBAO", "2x V2 4g", "1x XX 4g", "hola"])),
    ["4:PRODUCTO_DESCONOCIDO", "5:LINEA_NO_RECONOCIDA"]);
});

Deno.test("R1-15 las líneas vacías se ignoran", () => {
  assertEquals(r1(["SALE: ALMACÉN", "", "   ", "BILBAO", "", "2x V2 4g"]).estado, "aceptado");
});

Deno.test("R1-16 sin líneas de producto", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN"])), ["0:REPARTO_VACIO"]);
});

Deno.test("R1-17 SALE: almacen sin tilde (P-R1a)", () => {
  const r = r1(["SALE: almacen", "BILBAO", "1x V2 4g"]);
  assertEquals([r.estado, r.sale], ["aceptado", "operario"]);
});

Deno.test("R1-18 fecha que no es hoy: se pide confirmación (P-R1b)", () => {
  const lineas = ["REPARTO 26/10", "SALE: YO", "BILBAO", "1x V2 4g"];
  assertEquals(r1(lineas).estado, "fecha_no_es_hoy");
  assertEquals(r1(lineas, { confirmarFecha: true }).estado, "aceptado");
});

Deno.test("R1-19 almacén vacío en PRINCIPAL: cuenta como 0, con aviso", () => {
  const p = r1(["SALE: ALMACÉN", "BILBAO", "1x LORANAT"]).produccion[0];
  assertEquals([p.faltan, p.aviso], [1, "Dato de almacén vacío en PRINCIPAL: se cuenta como 0."]);
});

Deno.test("R1-20 envío a Gipuzkoa: no pide SALE:", () => {
  const r = r1(["GIPUZKOA", "4x V2 4g"], { tipo: "envio" });
  assertEquals([r.estado, r.sale, r.bolsas[0].destino], ["aceptado", null, "Gipuzkoa (envío a Rentería)"]);
});

Deno.test("Catálogo: «V2 » con espacio final y productos sin formato; nombres repetidos se detectan", () => {
  const productos: Producto[] = [
    { nombre: "V2 ", granel: "730", formatos: [{ formato: "4g", almacen: "25" }], conTiendas: false, orden: 1 },
    { nombre: "FORTE", granel: "107", formatos: [], conTiendas: true, orden: 2 },
    { nombre: "DISTILLATE", granel: "5054", formatos: [], conTiendas: false, orden: 3 },
    { nombre: "V 2", granel: "1", formatos: [{ formato: "4 g", almacen: "1" }], conTiendas: false, orden: 4 },
  ];
  const { entradas, ambiguas } = catalogo(productos);
  assertEquals(entradas.map((e) => `${e.producto}|${e.formato}|${e.almacen}`), ["V2|4g|25", "FORTE||107", "V 2|4 g|1"]);
  assertEquals(ambiguas, ["V24G"]);
});

Deno.test("R1-22 envío antes del recuento: se apartan las cajas del reparto de hoy", () => {
  // V2 4g: 25 en almacén, el reparto de hoy pidió 20 → quedan 5 para el envío; se piden 8 → faltan 3.
  const r = r1(["GIPUZKOA", "8x V2 4g", "1x BZ1 4g"], {
    tipo: "envio",
    apartadoReparto: [{ producto: "V2", formato: "4g", pedido: 20 }, { producto: "BZ1", formato: "4g", pedido: 9 }],
  });
  const v2 = r.produccion.find((p) => p.producto === "V2")!;
  assertEquals([v2.en_almacen, v2.apartado_reparto, v2.faltan], [5, 20, 3]);
  // BZ1 4g: 7 en almacén, 9 apartadas → 0 disponibles; se pide 1 → falta 1.
  assertEquals(faltan(r)["BZ1 4g"], 1);
});

Deno.test("R1-23 envío después del recuento: no se descuenta nada (la hoja ya lo refleja)", () => {
  const r = r1(["GIPUZKOA", "8x V2 4g"], { tipo: "envio", apartadoReparto: [] });
  assertEquals([r.produccion[0].en_almacen, r.produccion[0].faltan], [25, 0]);
});

Deno.test("R1-24 en un reparto nunca se aparta nada", () => {
  const r = r1(["SALE: YO", "BILBAO", "8x V2 4g"], { apartadoReparto: [{ producto: "V2", formato: "4g", pedido: 20 }] });
  assertEquals([r.produccion[0].apartado_reparto, r.produccion[0].faltan], [0, 0]);
});

Deno.test("R1-25 el desplegable manda sobre SALE: (v1.20)", () => {
  const r = r1(["SALE: ALMACÉN", "BILBAO", "1x V2 4g"], { sale: "administracion" });
  assertEquals([r.estado, r.sale, r.saleTexto], ["aceptado", "administracion", "operario"]);
  assertEquals(r.lineas[0].sale, "operario");
});

Deno.test("R1-26 con desplegable, dos SALE: distintas no son error", () => {
  const r = r1(["SALE: ALMACÉN", "SALE: YO", "BILBAO", "1x V2 4g"], { sale: "operario" });
  assertEquals([r.estado, r.sale, r.saleTexto, errores(r)], ["aceptado", "operario", "contradictoria", []]);
});

Deno.test("R1-27 sin desplegable ni SALE: sigue FALTA_SALE; con SALE: y sin desplegable, manda el texto", () => {
  assertEquals(r1(["BILBAO", "1x V2 4g"]).estado, "falta_sale");
  const r = r1(["SALE: YO", "BILBAO", "1x V2 4g"]);
  assertEquals([r.estado, r.sale, r.saleTexto], ["aceptado", "administracion", "administracion"]);
});

Deno.test("R1-28 «Además: …» tras los productos de una tienda: petición especial, no cuenta para producción ni bolsas (R1d)", () => {
  const r = r1(["SALE: ALMACÉN", "BILBAO", "2x V2 4g", "Además: rollos de TPV; muestras", "ALGORTA", "ademas: cajas vacías"]);
  assertEquals([r.estado, faltan(r), r.bolsas.map((b) => b.items.length)], ["aceptado", { "V2 4g": 0 }, [1]]);
  assertEquals(r.lineas.filter((l) => l.clase === "peticion").map((l) => [l.num, l.destino_id]), [[4, "bilbao"], [6, "algorta"]]);
});

Deno.test("R1-29 «Además:» sin tienda antes o vacío: línea no reconocida", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN", "Además: rollos", "BILBAO", "2x V2 4g", "Además:   "])),
               ["2:LINEA_NO_RECONOCIDA", "5:LINEA_NO_RECONOCIDA"]);
});

Deno.test("R1-30 un reparto sin productos vale solo si lleva pedidos de cliente (Tarea 14)", () => {
  assertEquals(errores(r1(["SALE: ALMACÉN"])), ["0:REPARTO_VACIO"]);
  const r = r1(["SALE: ALMACÉN"], { permitirVacio: true });
  assertEquals([r.estado, r.produccion, r.bolsas], ["aceptado", [], []]);
});
