// Almacén ahora (R1c, Tarea 14): lo producido y lo salido aplicados a la hoja.
import { assertEquals } from "jsr:@std/assert@1";
import { ajusteAlmacen, aplicarAjuste } from "./almacen.ts";
import type { EntradaCatalogo } from "./r1.ts";

const E = (producto: string, almacen: string): EntradaCatalogo => ({ producto, formato: "4g", almacen, orden: 1 });
const c = (producto: string, cantidad: number) => ({ producto, formato: "4g", cantidad });

Deno.test("Almacén ahora: hoja + producido (sin lo del propio reparto) − salido", () => {
  const m = { recuento_en: null, producido: [c("V2", 6), c("BZ1", 2)], producido_reparto: [c("BZ1", 2)],
              producido_envio: [], salido: [c("V2", 1), c("FORTE", 3)] };
  const ajuste = ajusteAlmacen(m, "reparto");
  assertEquals([...ajuste.entries()].filter(([, v]) => v !== 0), [["V24G", 5], ["FORTE4G", -3]]);
  assertEquals(ajusteAlmacen(m, "envio").get("BZ14G"), 2);
  assertEquals(aplicarAjuste([E("V2", "4"), E("BZ1", "7"), E("FORTE", "1")], ajuste).map((e) => e.almacen), ["9", "7", "0"]);
});

Deno.test("Almacén ahora: celda vacía o negativa (cuenta 0) con movimiento; sin movimiento, la hoja tal cual", () => {
  const ajuste = new Map([["V24G", 3], ["BZ14G", 2]]);
  assertEquals(aplicarAjuste([E("V2", ""), E("BZ1", "-5"), E("FORTE", "")], ajuste).map((e) => e.almacen), ["3", "2", ""]);
  assertEquals(aplicarAjuste([E("V2", "2,5")], ajuste)[0].almacen, "5,5");
});
