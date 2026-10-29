// Pruebas de R1e · producto sin granel en el reparto (REGLAS_CALCULO.md §2.11, casos R1e-01 a R1e-05).
import { assertEquals } from "jsr:@std/assert@1";
import type { Producto } from "./hoja.ts";
import type { Bolsa, ElementoProduccion } from "./r1.ts";
import { marcarSinGranel } from "./sin_granel.ts";

const tienda = (id: string, codigo: string, nombre: string) => ({ id, codigo, nombre, alias: [codigo] });
const DESTINOS = [tienda("bilbao", "BILBAO", "Bilbao"), tienda("algorta", "ALGORTA", "Algorta"),
                  tienda("barakaldo", "BARAKALDO", "Barakaldo"), tienda("basauri", "BASAURI", "Basauri"),
                  tienda("portu", "PORTU", "Portugalete")];
const BZ1: Producto = { nombre: "BZ1", granel: "0", conTiendas: false, orden: 60, formatos: [
  { formato: "4g", almacen: "0", tiendas: { BILBAO: "1", ALGORTA: "4", BARAKALDO: "0", BASAURI: "-2", PORTU: "3" } }] };
const V2: Producto = { nombre: "V2 ", granel: "730", conTiendas: false, orden: 65, formatos: [{ formato: "4g", almacen: "0" }] };
const elemento = (producto: string, pedido: number, en_almacen: number): ElementoProduccion =>
  ({ producto, formato: "4g", pedido, en_almacen, apartado_reparto: 0, faltan: Math.max(pedido - en_almacen, 0), aviso: null, orden: 6000 });
const bolsa = (destino_id: string, producto: string, cantidad: number): Bolsa =>
  ({ destino_id, destino: destino_id, items: [{ producto, formato: "4g", cantidad, orden: 6000 }] });

Deno.test("R1e-01 sin granel, dos tiendas que lo reciben: se marca, con lo que le falta a cada una y quién tiene", () => {
  // Bilbao pide 3 y Portu 2; en el almacén hay 1: se lo lleva Bilbao (primera en el reparto).
  const [e] = marcarSinGranel([elemento("BZ1", 5, 1)], [bolsa("bilbao", "BZ1", 3), bolsa("portu", "BZ1", 2)],
                              { productos: [BZ1] }, DESTINOS);
  assertEquals(e.sin_granel, true);
  assertEquals(e.para, [{ destino_id: "bilbao", destino: "Bilbao", pedido: 3, faltan: 2 },
                        { destino_id: "portu", destino: "Portugalete", pedido: 2, faltan: 2 }]);
  // Las demás tiendas del reparto con cajas en PRINCIPAL (Barakaldo 0 y Basauri −2 no salen).
  assertEquals(e.tiendas_con_stock, [{ destino_id: "algorta", destino: "Algorta", cajas: 4 }]);
  assertEquals(e.faltan, 4);
});

Deno.test("R1e-02 con granel no se marca (se hace como siempre)", () => {
  const [e] = marcarSinGranel([elemento("V2", 5, 0)], [bolsa("bilbao", "V2", 5)], { productos: [V2] }, DESTINOS);
  assertEquals([e.sin_granel, e.para, e.tiendas_con_stock], [undefined, undefined, undefined]);
});

Deno.test("R1e-03 sin granel pero no hay que hacer nada (lo hay en el almacén): no se marca", () => {
  const [e] = marcarSinGranel([elemento("BZ1", 3, 3)], [bolsa("bilbao", "BZ1", 3)], { productos: [BZ1] }, DESTINOS);
  assertEquals(e.sin_granel, undefined);
});

Deno.test("R1e-04 granel vacío o no numérico: no se marca (R3 lo avisa, no se inventa)", () => {
  const [e] = marcarSinGranel([elemento("BZ1", 3, 0)], [bolsa("bilbao", "BZ1", 3)],
                              { productos: [{ ...BZ1, granel: "" }] }, DESTINOS);
  assertEquals(e.sin_granel, undefined);
});

Deno.test("R1e-05 producto sin formato (aceites): las cajas de las tiendas están en la fila del nombre", () => {
  const forte: Producto = { nombre: "FORTE", granel: "0", conTiendas: true, orden: 90, formatos: [],
                            tiendas: { BILBAO: "3", ALGORTA: "6" } };
  const [e] = marcarSinGranel([{ ...elemento("FORTE", 2, 0), formato: "" }],
                              [{ destino_id: "bilbao", destino: "Bilbao", items: [{ producto: "FORTE", formato: "", cantidad: 2, orden: 9000 }] }],
                              { productos: [forte] }, DESTINOS);
  assertEquals([e.sin_granel, e.tiendas_con_stock], [true, [{ destino_id: "algorta", destino: "Algorta", cajas: 6 }]]);
});
