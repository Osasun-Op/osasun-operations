// Lista de un pedido de cliente: el orden de la hoja y la categoría. El «coge /
// haz» (P-01 a P-08 de REGLAS_CALCULO.md §2.10) se calcula en la base de datos
// al salir la tarea: supabase/tests/17_pedidos_cliente.sql.
import { assertEquals } from "jsr:@std/assert@1";
import type { EntradaCatalogo } from "./r1.ts";
import { listaPedido } from "./pedidos.ts";

const E = (producto: string, formato: string, orden: number): EntradaCatalogo => ({ producto, formato, almacen: "1", orden });

Deno.test("Lista del pedido: cada referencia con su orden en la hoja y su categoría", () => {
  const r = listaPedido([{ producto: "V2", formato: "4g", cantidad: 3 }, { producto: "FORTE", formato: "", cantidad: 1 },
                         { producto: "NUEVO", formato: "4g", cantidad: 2 }],
                        [E("FORTE", "", 900), E("V2", "4g", 6500)], { V2: "HIGH TECH" });
  assertEquals(r, [
    { producto: "V2", formato: "4g", cantidad: 3, orden: 6500, categoria: "HIGH TECH" },
    { producto: "FORTE", formato: "", cantidad: 1, orden: 900 },
    { producto: "NUEVO", formato: "4g", cantidad: 2, orden: 0 },
  ]);
});
