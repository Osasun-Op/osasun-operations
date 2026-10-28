// Casos P-01 a P-05 de REGLAS_CALCULO.md §2.10 (pedidos de cliente: «coge / haz»).
import { assertEquals } from "jsr:@std/assert@1";
import type { EntradaCatalogo } from "./r1.ts";
import { cogeHaz, planPedidosTienda, textoCogeHaz } from "./pedidos.ts";

const E = (producto: string, formato: string, almacen: string, orden: number): EntradaCatalogo => ({ producto, formato, almacen, orden });
const CAT = [E("V2", "4g", "25", 100), E("BZ1", "4g", "7", 200), E("KRUSH", "20gr", "", 300), E("FORTE", "", "-3", 400)];
const L = (producto: string, formato: string, cantidad: number) => ({ producto, formato, cantidad });

Deno.test("P-01 coge lo que hay en el almacén; lo que falta, lo hace", () => {
  const r = cogeHaz([L("V2", "4g", 3), L("BZ1", "4g", 9)], CAT, []);
  assertEquals(r.map((e) => [e.coge, e.haz, e.motivo]), [
    [3, 0, "Coge 3 del almacén"],
    [7, 2, "Coge 7 del almacén y haz 2"],
  ]);
});

Deno.test("P-02 después de apartar lo comprometido hoy (reparto que la hoja aún cuenta): V2 25 − 20 → coge 5, haz 3", () => {
  const r = cogeHaz([L("V2", "4g", 8)], CAT, [L("V2", "4g", 20)]);
  assertEquals([r[0].en_almacen, r[0].coge, r[0].haz], [5, 5, 3]);
});

Deno.test("P-03 almacén vacío o negativo en la hoja: se cuenta como 0 (haz todo)", () => {
  const r = cogeHaz([L("KRUSH", "20gr", 2), L("FORTE", "", 1), L("NUEVO", "4g", 1)], CAT, []);
  assertEquals(r.map((e) => e.motivo), ["Haz 2", "Haz 1", "Haz 1"]);
});

Deno.test("P-04 varios pedidos de tienda: primero lo oficial y después cada pedido, en orden de llegada", () => {
  const plan = planPedidosTienda(
    [{ id: "a", lineas: [L("V2", "4g", 4)] }, { id: "b", lineas: [L("V2", "4g", 4), L("BZ1", "4g", 1)] }],
    CAT, [L("V2", "4g", 20)]);
  assertEquals(plan.map((p) => [p.pedido_id, p.elementos.map((e) => e.motivo)]), [
    ["a", ["Coge 4 del almacén"]],
    ["b", ["Coge 1 del almacén y haz 3", "Coge 1 del almacén"]],
  ]);
});

Deno.test("P-05 frases de «coge / haz»", () => {
  assertEquals([textoCogeHaz(2, 0), textoCogeHaz(0, 3), textoCogeHaz(1, 1)],
               ["Coge 2 del almacén", "Haz 3", "Coge 1 del almacén y haz 1"]);
});
