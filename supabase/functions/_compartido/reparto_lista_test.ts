// Funciones del servidor `catalogo` y `guardar_reparto` con la hoja y la base de
// datos simuladas: permisos y jornada (los decide servidor_preparar), hoja no
// disponible, idempotencia por id_cliente, referencia inexistente y lo que se
// guarda (el texto de WhatsApp y el mismo cálculo R1).
import { assertEquals } from "jsr:@std/assert@1";
import type { ResultadoLectura } from "./google.ts";
import type { DatosHoja } from "./hoja.ts";
import { catalogoDe, type Dependencias, guardarRepartoDe } from "./reparto_lista.ts";
import { HOJA_28_10, REPARTO_28_10 } from "./lista_test.ts";

const DATOS: DatosHoja = { ...HOJA_28_10, conteo: [], variedades: { INVERNADERO: [], INDOOR: [] } };
const destino = (id: string, codigo: string, nombre: string, tipo = "tienda", activo = true) =>
  ({ id, codigo, nombre, tipo, activo, alias: codigo === "DURANGO" ? ["DURANGO", "LAUDIO"] : [codigo] });
const CTX = {
  persona_id: "p", rol: "administracion", jornada_id: "jornada-eder", fecha: "2026-10-28", dia: 28, mes: 10,
  destinos: [destino("algorta", "ALGORTA", "Algorta"), destino("barakaldo", "BARAKALDO", "Barakaldo"),
             destino("basauri", "BASAURI", "Basauri"), destino("bilbao", "BILBAO", "Bilbao"),
             destino("donosti", "DONOSTI", "Donosti"), destino("durango", "DURANGO", "Durango", "tienda", false),
             destino("gipuzkoa", "GIPUZKOA", "Gipuzkoa (envío a Rentería)", "destino"),
             destino("portu", "PORTU", "Portugalete"), destino("renteria", "RENTERIA", "Rentería")],
  config: { sheets_documento_id: "doc", sheets_pestanas: { principal: "PRINCIPAL", conteo: "CONTEO", almacen: "ALMACEN" },
            destinos_reparto: { reparto: ["BILBAO", "ALGORTA", "BARAKALDO", "BASAURI", "PORTU"], envio: ["GIPUZKOA", "DURANGO"] } },
  comprometido: { reparto: [], pedidos_tienda: [], envio: [], pedidos_nacex: [], en_camino: [] },
  pedidos_tienda: [] as { id: string; cliente: string; destino_id: string; lineas: { producto: string; formato: string; cantidad: number }[] }[],
};
const ID = "6b1f7a3e-9c1d-4f2a-8b7e-2d5c9a0e1f34";

function falso(o: { ctx?: Record<string, unknown>; previo?: unknown; lectura?: ResultadoLectura; guardado?: Record<string, unknown> } = {}) {
  const llamadas: { nombre: string; args: Record<string, unknown> }[] = [];
  let lecturas = 0;
  const d: Dependencias = {
    rpc: <T>(nombre: string, args: Record<string, unknown>) => {
      llamadas.push({ nombre, args });
      const r: Record<string, unknown> = {
        servidor_preparar: o.ctx ?? CTX,
        servidor_reparto_por_id_cliente: o.previo ?? null,
        servidor_guardar_lectura: "lectura-1",
        servidor_guardar_reparto: o.guardado ?? { reparto_id: "reparto-1", estado: "aceptado", tarea_activa: null },
        servidor_reparto_anotar_id_cliente: null,
        servidor_asignar_pedidos: { pedidos: [{ id: "pedido-1", estado: "por_preparar" }] },
      };
      return Promise.resolve(r[nombre] as T);
    },
    leer: () => { lecturas++; return Promise.resolve(o.lectura ?? { ok: true, datos: DATOS }); },
    huella: (tipo, texto) => Promise.resolve(`${tipo}:${texto.length}`),
    ahora: () => new Date("2026-10-28T08:00:00Z"),
  };
  return { d, llamadas, lecturas: () => lecturas, args: (n: string) => llamadas.find((l) => l.nombre === n)?.args };
}
const cuerpo = (extra: Record<string, unknown> = {}) => ({ id_cliente: ID, tipo: "reparto", sale: "administracion", lineas: REPARTO_28_10, ...extra });

Deno.test("catalogo: tiendas del reparto y del envío en el orden de las hojas (sin Donosti ni Rentería) y productos con categoría", async () => {
  const f = falso();
  const r = await catalogoDe(f.d, "p") as { tiendas: Record<string, { codigo: string }[]>; productos: { clave: string }[] };
  assertEquals(r.tiendas.reparto.map((t) => t.codigo), ["BILBAO", "ALGORTA", "BARAKALDO", "BASAURI", "PORTU"]);
  assertEquals(r.tiendas.envio.map((t) => t.codigo), ["GIPUZKOA", "DURANGO"]);
  assertEquals([r.productos.length, r.productos[0].clave], [38, "MINI|10g"]);
});

Deno.test("catalogo y guardar_reparto: sin permiso o sin ficha, el error de la base de datos tal cual", async () => {
  const err = { error: { codigo: "NO_AUTORIZADO", mensaje: "No tienes permiso para esto." } };
  assertEquals(await catalogoDe(falso({ ctx: err }).d, "x"), err);
  const f = falso({ ctx: err });
  assertEquals(await guardarRepartoDe(f.d, "x", cuerpo()), err);
  assertEquals(f.lecturas(), 0);
});

Deno.test("hoja no disponible: SHEETS_NO_DISPONIBLE, la lectura fallida queda guardada y no se calcula nada", async () => {
  const caida: ResultadoLectura = { ok: false, codigo: "SHEETS_NO_DISPONIBLE", detalle: "HTTP 503" };
  assertEquals((await catalogoDe(falso({ lectura: caida }).d, "p") as { error: { codigo: string } }).error.codigo, "SHEETS_NO_DISPONIBLE");
  const f = falso({ lectura: caida });
  const r = await guardarRepartoDe(f.d, "p", cuerpo()) as { error: { codigo: string } };
  assertEquals(r.error.codigo, "SHEETS_NO_DISPONIBLE");
  assertEquals(f.args("servidor_guardar_lectura")?.p_correcto, false);
  assertEquals(f.args("servidor_guardar_reparto"), undefined);
});

Deno.test("guardar_reparto: guarda el texto de WhatsApp, el cálculo R1 y anota el id_cliente", async () => {
  const f = falso();
  const r = await guardarRepartoDe(f.d, "p", cuerpo()) as Record<string, unknown>;
  const g = f.args("servidor_guardar_reparto")!;
  assertEquals([g.p_jornada, g.p_tipo, g.p_sale, g.p_aceptado, g.p_lectura, g.p_fecha_texto],
               ["jornada-eder", "reparto", "administracion", true, "lectura-1", "2026-10-28"]);
  assertEquals((g.p_texto as string).split("\n").slice(0, 4), ["REPARTO 28/10", "SALE: YO", "", "BILBAO"]);
  assertEquals((g.p_produccion as { faltan: number }[]).filter((p) => p.faltan > 0).length, 4);
  assertEquals((g.p_bolsas as unknown[]).length, 5);
  assertEquals(f.args("servidor_reparto_anotar_id_cliente"), { p_reparto: "reparto-1", p_id_cliente: ID });
  assertEquals(r.texto_whatsapp, g.p_texto);
});

Deno.test("guardar_reparto: repetir con el mismo id_cliente devuelve lo guardado sin leer la hoja ni recalcular", async () => {
  const f = falso({ previo: { reparto_id: "reparto-1", estado: "aceptado", texto_whatsapp: "REPARTO 28/10" } });
  const r = await guardarRepartoDe(f.d, "p", cuerpo()) as Record<string, unknown>;
  assertEquals([r.reparto_id, r.ya_guardado, (r.aviso as { codigo: string }).codigo], ["reparto-1", true, "REPARTO_YA_GUARDADO"]);
  assertEquals([f.lecturas(), f.args("servidor_guardar_reparto")], [0, undefined]);
});

Deno.test("guardar_reparto: el mismo contenido que el de hoy no cambia nada (aviso REPARTO_SIN_CAMBIOS)", async () => {
  const f = falso({ guardado: { reparto_id: "reparto-0", estado: "aceptado", ya_pegado: true } });
  const r = await guardarRepartoDe(f.d, "p", cuerpo()) as Record<string, unknown>;
  assertEquals([(r.aviso as { codigo: string }).codigo, typeof r.texto_whatsapp], ["REPARTO_SIN_CAMBIOS", "string"]);
});

Deno.test("guardar_reparto: referencia que ya no está en la hoja, sin quién sale, sin jornada o tienda que no está en la lista", async () => {
  const codigo = async (c: Record<string, unknown>, o = {}) =>
    ((await guardarRepartoDe(falso(o).d, "p", c)) as { error?: { codigo: string } }).error?.codigo;
  assertEquals(await codigo(cuerpo({ lineas: [{ destino_id: "bilbao", producto: "GELATO", formato: "4g", cantidad: 1 }] })), "REFERENCIA_NO_EXISTE");
  assertEquals(await codigo(cuerpo({ sale: undefined })), "FALTA_SALE");
  assertEquals(await codigo(cuerpo({ id_cliente: "no" })), "DATOS_NO_VALIDOS");
  assertEquals(await codigo(cuerpo(), { ctx: { ...CTX, jornada_id: null } }), "SIN_JORNADA");
  // Gipuzkoa y Durango van en el envío, no en el reparto; Bilbao no es del envío; Donosti y Rentería no están en ninguna lista.
  const linea = (destino_id: string) => [{ destino_id, producto: "V2", formato: "4g", cantidad: 1 }];
  for (const d of ["gipuzkoa", "durango", "donosti", "renteria"]) {
    assertEquals(await codigo(cuerpo({ lineas: linea(d) })), "DATOS_NO_VALIDOS");
  }
  assertEquals(await codigo(cuerpo({ tipo: "envio", lineas: linea("bilbao") })), "DATOS_NO_VALIDOS");
  assertEquals(await codigo(cuerpo({ tipo: "envio", lineas: linea("renteria") })), "DATOS_NO_VALIDOS");
});

Deno.test("guardar_reparto: envío (sin quién sale) a Gipuzkoa, apartando el reparto de hoy antes del recuento", async () => {
  const f = falso({ ctx: { ...CTX, comprometido: { ...CTX.comprometido, reparto: [{ producto: "V2", formato: "4g", cantidad: 25 }] } } });
  await guardarRepartoDe(f.d, "p", { id_cliente: ID, tipo: "envio", lineas: [{ destino_id: "gipuzkoa", producto: "V2", formato: "4g", cantidad: 8 }] });
  const g = f.args("servidor_guardar_reparto")!;
  assertEquals([g.p_tipo, g.p_sale, g.p_texto], ["envio", null, "ENVÍO 28/10\n\nGIPUZKOA\n8x V2 4g"]);
  assertEquals((g.p_produccion as { faltan: number }[])[0].faltan, 3);
});

Deno.test("guardar_reparto: envío a Gipuzkoa y a Durango (aunque Durango esté cerrada como tienda), en ese orden", async () => {
  const f = falso();
  await guardarRepartoDe(f.d, "p", { id_cliente: ID, tipo: "envio", lineas: [
    { destino_id: "durango", producto: "BZ1", formato: "4g", cantidad: 2 }, { destino_id: "gipuzkoa", producto: "V2", formato: "4g", cantidad: 4 }] });
  const g = f.args("servidor_guardar_reparto")!;
  assertEquals(g.p_texto, "ENVÍO 28/10\n\nGIPUZKOA\n4x V2 4g\n\nDURANGO\n2x BZ1 4g");
  assertEquals((g.p_bolsas as { destino_id: string }[]).map((b) => b.destino_id), ["gipuzkoa", "durango"]);
});

Deno.test("guardar_reparto: el envío aparta también los pedidos de tienda que salen hoy con el reparto (R1c)", async () => {
  const f = falso({ ctx: { ...CTX, comprometido: { ...CTX.comprometido,
    reparto: [{ producto: "V2", formato: "4g", cantidad: 20 }], pedidos_tienda: [{ producto: "V2", formato: "4g", cantidad: 6 }] } } });
  await guardarRepartoDe(f.d, "p", { id_cliente: ID, tipo: "envio", lineas: [{ destino_id: "gipuzkoa", producto: "V2", formato: "4g", cantidad: 8 }] });
  // V2 4g: 30 en la hoja − 20 del reparto − 6 del pedido = 4; faltan 4.
  const prod = (f.args("servidor_guardar_reparto")!.p_produccion as { en_almacen: number; faltan: number; apartado_reparto: number }[])[0];
  assertEquals([prod.apartado_reparto, prod.en_almacen, prod.faltan], [26, 4, 4]);
  assertEquals(f.args("servidor_asignar_pedidos"), undefined);
});

Deno.test("guardar_reparto: los pedidos de tienda van en el reparto con «coge / haz», sin tocar la producción oficial", async () => {
  const pedidos = [
    { id: "pedido-1", cliente: "Ane", destino_id: "bilbao", lineas: [{ producto: "V2", formato: "4g", cantidad: 3 }] },
    { id: "pedido-2", cliente: "Jon", destino_id: "portu", lineas: [{ producto: "V2", formato: "4g", cantidad: 4 }, { producto: "MINI", formato: "10g", cantidad: 2 }] },
    { id: "pedido-3", cliente: "Mikel", destino_id: "donosti", lineas: [{ producto: "V2", formato: "4g", cantidad: 1 }] },
  ];
  const f = falso({ ctx: { ...CTX, pedidos_tienda: pedidos } });
  const lineas = [{ destino_id: "bilbao", producto: "V2", formato: "4g", cantidad: 25 }];
  const r = await guardarRepartoDe(f.d, "p", cuerpo({ lineas })) as Record<string, unknown>;
  // La producción del reparto es solo la oficial: 25 pedidas, 30 en el almacén, faltan 0.
  const prod = (f.args("servidor_guardar_reparto")!.p_produccion as { pedido: number; faltan: number }[])[0];
  assertEquals([prod.pedido, prod.faltan], [25, 0]);
  // Quedan 5 V2 4g: Ane coge 3; Jon coge 2 y hace 2. MINI 10g: 30 en el almacén, coge 2. Donosti no es del reparto.
  const plan = f.args("servidor_asignar_pedidos")!.p_pedidos as { pedido_id: string; elementos: { producto: string; motivo: string }[] }[];
  assertEquals(plan.map((p) => [p.pedido_id, p.elementos.map((e) => `${e.producto}: ${e.motivo}`)]), [
    ["pedido-1", ["V2: Coge 3 del almacén"]],
    ["pedido-2", ["V2: Coge 2 del almacén y haz 2", "MINI: Coge 2 del almacén"]],
  ]);
  assertEquals(f.args("servidor_asignar_pedidos")!.p_reparto, "reparto-1");
  assertEquals(r.pedidos_cliente, [{ id: "pedido-1", estado: "por_preparar" }]);
  // Se asignan antes de anotar el id_cliente: si la llamada se corta, el reintento lo vuelve a hacer.
  const orden = f.llamadas.map((l) => l.nombre);
  assertEquals(orden.indexOf("servidor_asignar_pedidos") < orden.indexOf("servidor_reparto_anotar_id_cliente"), true);
});

Deno.test("guardar_reparto: sin cambios en el reparto, los pedidos que esperan se asignan igual", async () => {
  const f = falso({ ctx: { ...CTX, pedidos_tienda: [{ id: "pedido-1", cliente: "Ane", destino_id: "bilbao", lineas: [{ producto: "V2", formato: "4g", cantidad: 1 }] }] },
                    guardado: { reparto_id: "reparto-0", estado: "aceptado", ya_pegado: true } });
  const r = await guardarRepartoDe(f.d, "p", cuerpo()) as Record<string, unknown>;
  assertEquals([(r.aviso as { codigo: string }).codigo, f.args("servidor_asignar_pedidos")!.p_reparto], ["REPARTO_SIN_CAMBIOS", "reparto-0"]);
});
