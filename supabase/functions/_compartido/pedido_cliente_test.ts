// Función del servidor `guardar_pedido_cliente` con la hoja y la base de datos
// simuladas: datos obligatorios, permisos, hoja no disponible, referencia que ya
// no está, reintento por id_cliente y la lista de Nacex.
import { assertEquals } from "jsr:@std/assert@1";
import type { ResultadoLectura } from "./google.ts";
import type { DatosHoja } from "./hoja.ts";
import { guardarPedidoClienteDe } from "./pedido_cliente.ts";
import type { Dependencias } from "./reparto_lista.ts";
import { HOJA_28_10 } from "./lista_test.ts";

const DATOS: DatosHoja = { ...HOJA_28_10, conteo: [], variedades: { INVERNADERO: [], INDOOR: [] } };
const ID = "1e2d3c4b-5a69-4788-9a0b-1c2d3e4f5a6b";
const BILBAO = "0b1c2d3e-4f50-4617-8293-a4b5c6d7e8f9";
const SIN = { reparto: [], pedidos_tienda: [], envio: [], pedidos_nacex: [], en_camino: [] };
const PREP = {
  fecha: "2026-10-28", jornada_id: "jornada-eder", comprometido: SIN,
  config: { sheets_documento_id: "doc", sheets_pestanas: { principal: "PRINCIPAL", conteo: "CONTEO", almacen: "ALMACEN" } },
};

function falso(o: { prep?: Record<string, unknown>; lectura?: ResultadoLectura } = {}) {
  const llamadas: { nombre: string; args: Record<string, unknown> }[] = [];
  let lecturas = 0;
  const d: Dependencias = {
    rpc: <T>(nombre: string, args: Record<string, unknown>) => {
      llamadas.push({ nombre, args });
      const r: Record<string, unknown> = {
        servidor_preparar_pedido: o.prep ?? PREP,
        servidor_guardar_lectura: "lectura-1",
        servidor_guardar_pedido_cliente: { pedido: { id: "pedido-1" }, tarea: null, tarea_activa: null },
      };
      return Promise.resolve(r[nombre] as T);
    },
    leer: () => { lecturas++; return Promise.resolve(o.lectura ?? { ok: true, datos: DATOS }); },
    huella: () => Promise.resolve(""),
  };
  return { d, lecturas: () => lecturas, args: (n: string) => llamadas.find((l) => l.nombre === n)?.args };
}
const tienda = (extra: Record<string, unknown> = {}) => ({
  id_cliente: ID, entrega: "tienda", destino_id: BILBAO, cliente: "  Ane   Etxeberria ",
  lineas: [{ producto: "V2", formato: "4g", cantidad: 2 }, { producto: "MINI", formato: "10g", cantidad: 0 }], ...extra,
});
const nacex = (extra: Record<string, unknown> = {}) => ({
  id_cliente: ID, entrega: "nacex", cliente: "Jon", datos_envio: "Jon Aguirre\nCalle Mayor 1, 48001 Bilbao\n600 000 000",
  lineas: [{ producto: "V2", formato: "4g", cantidad: 8 }, { producto: "BZ1", formato: "4g", cantidad: 1 }], ...extra,
});
const codigo = async (c: Record<string, unknown>, o = {}) =>
  ((await guardarPedidoClienteDe(falso(o).d, "p", c)) as { error?: { codigo: string; mensaje: string } }).error;

Deno.test("guardar_pedido_cliente: recoger en tienda se guarda sin «coge / haz» (se calcula con el reparto)", async () => {
  const f = falso();
  await guardarPedidoClienteDe(f.d, "p", tienda());
  const g = f.args("servidor_guardar_pedido_cliente")!;
  assertEquals([g.p_cliente, g.p_entrega, g.p_destino, g.p_datos_envio, g.p_elementos, g.p_fecha],
               ["Ane Etxeberria", "tienda", BILBAO, null, null, "2026-10-28"]);
  assertEquals(g.p_lineas, [{ producto: "V2", formato: "4g", cantidad: 2 }]);   // el contador a 0 no cuenta
  assertEquals(f.args("servidor_guardar_lectura")!.p_motivo, "pedido");
});

Deno.test("guardar_pedido_cliente: Nacex guarda la lista en el orden de la hoja (el «coge / haz», al salir la tarea)", async () => {
  const f = falso();
  await guardarPedidoClienteDe(f.d, "p", nacex());
  const g = f.args("servidor_guardar_pedido_cliente")!;
  assertEquals([g.p_entrega, g.p_destino, g.p_jornada, g.p_datos_envio],
               ["nacex", null, "jornada-eder", "Jon Aguirre\nCalle Mayor 1, 48001 Bilbao\n600 000 000"]);
  const e = g.p_elementos as { producto: string; orden: number; categoria?: string; motivo?: string }[];
  assertEquals(e.map((x) => [x.producto, x.categoria, x.motivo]), [["BZ1", "HIGH TECH", undefined], ["V2", "HIGH TECH", undefined]]);
  assertEquals(e[0].orden < e[1].orden, true);
});

Deno.test("guardar_pedido_cliente: datos obligatorios", async () => {
  assertEquals((await codigo(tienda({ cliente: "   " })))?.mensaje, "Escribe el nombre del cliente.");
  assertEquals((await codigo(tienda({ destino_id: undefined })))?.mensaje, "Elige la tienda donde lo recoge.");
  assertEquals((await codigo(nacex({ datos_envio: " " })))?.mensaje, "Pega los datos de envío (nombre, dirección, teléfono…).");
  assertEquals((await codigo(tienda({ entrega: "correo" })))?.codigo, "DATOS_NO_VALIDOS");
  assertEquals((await codigo(tienda({ id_cliente: "no" })))?.codigo, "DATOS_NO_VALIDOS");
  assertEquals((await codigo(tienda({ lineas: [] })))?.mensaje, "Añade al menos un producto.");
  assertEquals((await codigo(tienda({ lineas: [{ producto: "V2", formato: "4g", cantidad: -1 }] })))?.codigo, "DATOS_NO_VALIDOS");
});

Deno.test("guardar_pedido_cliente: referencia que ya no está en la hoja", async () => {
  const e = await codigo(tienda({ lineas: [{ producto: "GELATO", formato: "4g", cantidad: 1 }] }));
  assertEquals([e?.codigo, e?.mensaje], ["REFERENCIA_NO_EXISTE", "Ya no está en la hoja: GELATO 4g. Quítalo de la lista o vuelve a cargarla."]);
});

Deno.test("guardar_pedido_cliente: sin permiso, tienda no válida o sin jornada, el error de la base de datos tal cual", async () => {
  for (const c of ["NO_AUTORIZADO", "DATOS_NO_VALIDOS", "SIN_JORNADA"]) {
    const f = falso({ prep: { error: { codigo: c, mensaje: "…" } } });
    assertEquals(((await guardarPedidoClienteDe(f.d, "p", tienda())) as { error: { codigo: string } }).error.codigo, c);
    assertEquals(f.lecturas(), 0);
  }
});

Deno.test("guardar_pedido_cliente: hoja no disponible, no se guarda nada", async () => {
  const f = falso({ lectura: { ok: false, codigo: "SHEETS_NO_DISPONIBLE", detalle: "HTTP 503" } });
  const r = await guardarPedidoClienteDe(f.d, "p", nacex()) as { error: { codigo: string } };
  assertEquals([r.error.codigo, f.args("servidor_guardar_lectura")!.p_correcto, f.args("servidor_guardar_pedido_cliente")],
               ["SHEETS_NO_DISPONIBLE", false, undefined]);
});

Deno.test("guardar_pedido_cliente: repetir con el mismo id_cliente devuelve lo guardado sin leer la hoja", async () => {
  const f = falso({ prep: { previo: { id: "pedido-1", estado: "esperando_reparto" } } });
  const r = await guardarPedidoClienteDe(f.d, "p", tienda()) as Record<string, unknown>;
  assertEquals([r.ya_guardado, (r.aviso as { codigo: string }).codigo, f.lecturas()], [true, "PEDIDO_YA_GUARDADO", 0]);
});
