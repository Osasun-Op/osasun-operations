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

function falso(o: { ctx?: Record<string, unknown>; previo?: unknown; lectura?: ResultadoLectura; guardado?: Record<string, unknown>;
                    fallaCobertura?: boolean } = {}) {
  const llamadas: { nombre: string; args: Record<string, unknown> }[] = [];
  let lecturas = 0;
  const d: Dependencias = {
    rpc: <T>(nombre: string, args: Record<string, unknown>) => {
      llamadas.push({ nombre, args });
      if (nombre === "servidor_guardar_cobertura" && o.fallaCobertura) return Promise.reject(new Error("Base de datos caída"));
      const r: Record<string, unknown> = {
        servidor_preparar: o.ctx ?? CTX,
        servidor_reparto_por_id_cliente: o.previo ?? null,
        servidor_guardar_lectura: "lectura-1",
        servidor_guardar_reparto: o.guardado ?? { reparto_id: "reparto-1", estado: "aceptado", tarea_activa: null },
        servidor_reparto_anotar_id_cliente: null,
        servidor_asignar_pedidos: { pedidos: [{ id: "pedido-1", estado: "por_preparar" }] },
        servidor_guardar_peticiones: { peticiones: args.p_peticiones },
        servidor_guardar_cobertura: null,
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

Deno.test("guardar_reparto: los pedidos de tienda van en el reparto con su lista, sin tocar la producción oficial", async () => {
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
  // Los pedidos de Bilbao y Portu, con su lista en el orden de la hoja; Donosti no es del reparto.
  const plan = f.args("servidor_asignar_pedidos")!.p_pedidos as { pedido_id: string; elementos: { producto: string; cantidad: number }[] }[];
  assertEquals(plan.map((p) => [p.pedido_id, p.elementos.map((e) => `${e.cantidad} ${e.producto}`)]), [
    ["pedido-1", ["3 V2"]],
    ["pedido-2", ["4 V2", "2 MINI"]],
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

Deno.test("guardar_reparto: peticiones especiales en el texto («Además: …» tras los productos de su tienda), sin tocar producción ni bolsas (R1d)", async () => {
  const sin = falso();
  await guardarRepartoDe(sin.d, "p", cuerpo());
  const f = falso();
  const r = await guardarRepartoDe(f.d, "p", cuerpo({ peticiones: [
    { destino_id: "algorta", texto: "  rollos   de TPV " }, { destino_id: "bilbao", texto: "Muestras de V2" },
    { destino_id: "bilbao", texto: "" }, { destino_id: "bilbao", texto: "muestras de v2" },
    { destino_id: "bilbao", texto: "Cajas vacías, 3" },
  ] })) as Record<string, unknown>;
  const g = f.args("servidor_guardar_reparto")!;
  const texto = (g.p_texto as string).split("\n");
  const i = texto.indexOf("ALGORTA");
  assertEquals(texto[i - 2], "Además: Muestras de V2; Cajas vacías, 3");
  assertEquals(texto.filter((l) => l.startsWith("Además:")), ["Además: Muestras de V2; Cajas vacías, 3", "Además: rollos de TPV"]);
  assertEquals((g.p_lineas as { clase: string; destino_id?: string }[]).filter((l) => l.clase === "peticion").map((l) => l.destino_id),
               ["bilbao", "algorta"]);
  const s0 = sin.args("servidor_guardar_reparto")!;
  assertEquals([g.p_produccion, g.p_bolsas], [s0.p_produccion, s0.p_bolsas]);
  const esperadas = [{ destino_id: "bilbao", texto: "Muestras de V2" }, { destino_id: "bilbao", texto: "Cajas vacías, 3" },
                     { destino_id: "algorta", texto: "rollos de TPV" }];
  assertEquals(f.args("servidor_guardar_peticiones"), { p_persona: "p", p_reparto: "reparto-1", p_peticiones: esperadas });
  assertEquals([r.peticiones, r.texto_whatsapp], [esperadas, g.p_texto]);
});

Deno.test("guardar_reparto: una tienda solo con peticiones también sale en el texto; sin peticiones, lista vacía", async () => {
  const f = falso();
  await guardarRepartoDe(f.d, "p", cuerpo({ lineas: [{ destino_id: "bilbao", producto: "V2", formato: "4g", cantidad: 2 }],
                                             peticiones: [{ destino_id: "portu", texto: "Rollos de TPV" }] }));
  assertEquals((f.args("servidor_guardar_reparto")!.p_texto as string).split("\n"),
               ["REPARTO 28/10", "SALE: YO", "", "BILBAO", "2x V2 4g", "", "PORTU", "Además: Rollos de TPV"]);
  const v = falso();
  await guardarRepartoDe(v.d, "p", cuerpo());
  assertEquals(v.args("servidor_guardar_peticiones")!.p_peticiones, []);
});

Deno.test("guardar_reparto: petición de más de 120 letras o de una tienda que no es del reparto: DATOS_NO_VALIDOS", async () => {
  const largo = await guardarRepartoDe(falso().d, "p", cuerpo({ peticiones: [{ destino_id: "bilbao", texto: "x".repeat(121) }] }));
  assertEquals((largo as { error: { mensaje: string } }).error.mensaje, "Cada petición especial, 120 letras como máximo.");
  const f = falso();
  const tienda = await guardarRepartoDe(f.d, "p", cuerpo({ peticiones: [{ destino_id: "gipuzkoa", texto: "Rollos" }] }));
  assertEquals([(tienda as { error: { codigo: string } }).error.codigo, f.args("servidor_guardar_reparto")], ["DATOS_NO_VALIDOS", undefined]);
  const ok = await guardarRepartoDe(falso().d, "p", cuerpo({ peticiones: [{ destino_id: "bilbao", texto: "x".repeat(120) }] }));
  assertEquals((ok as Record<string, unknown>).error, undefined);
});

// ===== Tarea 14: almacén ahora (R1c) y pedidos que activan el reparto =====
const conAlmacen = (bz1: string): DatosHoja => ({
  ...DATOS, productos: DATOS.productos.map((p) => p.nombre === "BZ1" ? { ...p, formatos: [{ formato: "4g", almacen: bz1 }] } : p),
});
const mov = (m: Record<string, { producto: string; formato: string; cantidad: number }[]>) =>
  ({ recuento_en: "2026-10-27T17:15:00Z", producido: [], producido_reparto: [], producido_envio: [], salido: [], ...m });
const bz1 = (cantidad: number) => [{ producto: "BZ1", formato: "4g", cantidad }];

Deno.test("guardar_reparto: el hueco — 6 BZ1 4g hechas para stock con 4 en la hoja; se piden 5 más → no hay que hacer ninguna", async () => {
  const lineas = [{ destino_id: "bilbao", producto: "BZ1", formato: "4g", cantidad: 5 }];
  const sin = falso({ lectura: { ok: true, datos: conAlmacen("4") } });
  await guardarRepartoDe(sin.d, "p", cuerpo({ lineas }));
  assertEquals((sin.args("servidor_guardar_reparto")!.p_produccion as { faltan: number }[])[0].faltan, 1);
  const f = falso({ lectura: { ok: true, datos: conAlmacen("4") }, ctx: { ...CTX, almacen: mov({ producido: bz1(6) }) } });
  await guardarRepartoDe(f.d, "p", cuerpo({ lineas }));
  const prod = (f.args("servidor_guardar_reparto")!.p_produccion as { en_almacen: number; faltan: number }[])[0];
  assertEquals([prod.en_almacen, prod.faltan], [10, 0]);
});

Deno.test("guardar_reparto: lo producido para el propio reparto no cuenta dos veces (ya está hecho en sus elementos)", async () => {
  const lineas = [{ destino_id: "bilbao", producto: "BZ1", formato: "4g", cantidad: 10 }];
  const f = falso({ lectura: { ok: true, datos: conAlmacen("4") },
                    ctx: { ...CTX, almacen: mov({ producido: bz1(6), producido_reparto: bz1(6) }) } });
  await guardarRepartoDe(f.d, "p", cuerpo({ lineas }));
  assertEquals((f.args("servidor_guardar_reparto")!.p_produccion as { faltan: number }[])[0].faltan, 6);
});

Deno.test("guardar_reparto: el envío cuenta lo que ya ha salido (bolsas listas antes del recuento) y no lo vuelve a apartar", async () => {
  const f = falso({ ctx: { ...CTX, almacen: mov({ salido: [{ producto: "V2", formato: "4g", cantidad: 25 }] }) } });
  await guardarRepartoDe(f.d, "p", { id_cliente: ID, tipo: "envio", lineas: [{ destino_id: "gipuzkoa", producto: "V2", formato: "4g", cantidad: 8 }] });
  // V2 4g: 30 en la hoja − 25 que ya han salido = 5; el reparto ya no está pendiente: faltan 3.
  const prod = (f.args("servidor_guardar_reparto")!.p_produccion as { en_almacen: number; faltan: number; apartado_reparto: number }[])[0];
  assertEquals([prod.apartado_reparto, prod.en_almacen, prod.faltan], [0, 5, 3]);
});

Deno.test("catalogo: los pedidos de tienda del reparto de hoy, para mostrarlos marcados y fijos («Pedido de Ane a tienda de Bilbao»)", async () => {
  const pedidos = [{ id: "pedido-1", cliente: "Ane", destino_id: "bilbao", lineas: [{ producto: "V2", formato: "4g", cantidad: 3 }] },
                   { id: "pedido-9", cliente: "Mikel", destino_id: "donosti", lineas: [{ producto: "V2", formato: "4g", cantidad: 1 }] }];
  const r = await catalogoDe(falso({ ctx: { ...CTX, pedidos_tienda: pedidos } }).d, "p") as Record<string, unknown>;
  assertEquals(r.pedidos_cliente, [{ id: "pedido-1", cliente: "Ane", destino_id: "bilbao", destino: "Bilbao",
                                     lineas: [{ producto: "V2", formato: "4g", cantidad: 3 }], texto: "Pedido de Ane a tienda de Bilbao" }]);
  assertEquals((await catalogoDe(falso().d, "p") as Record<string, unknown>).pedidos_cliente, []);
});

Deno.test("guardar_reparto: con un pedido de tienda esperando, el reparto puede ir solo con el pedido; sin pedido, hace falta un producto", async () => {
  const pedidos = [{ id: "pedido-1", cliente: "Ane", destino_id: "bilbao", lineas: [{ producto: "V2", formato: "4g", cantidad: 3 }] }];
  const f = falso({ ctx: { ...CTX, pedidos_tienda: pedidos } });
  const r = await guardarRepartoDe(f.d, "p", cuerpo({ lineas: [] })) as Record<string, unknown>;
  const g = f.args("servidor_guardar_reparto")!;
  assertEquals([r.error, g.p_texto, g.p_produccion, g.p_bolsas], [undefined, "REPARTO 28/10\nSALE: YO", [], []]);
  assertEquals((f.args("servidor_asignar_pedidos")!.p_pedidos as { pedido_id: string }[]).map((p) => p.pedido_id), ["pedido-1"]);
  const sin = await guardarRepartoDe(falso().d, "p", cuerpo({ lineas: [] })) as { error: { mensaje: string } };
  assertEquals(sin.error.mensaje, "Añade al menos un producto.");
  const donosti = falso({ ctx: { ...CTX, pedidos_tienda: [{ ...pedidos[0], destino_id: "donosti" }] } });
  assertEquals(((await guardarRepartoDe(donosti.d, "p", cuerpo({ lineas: [] }))) as { error: { codigo: string } }).error.codigo,
               "DATOS_NO_VALIDOS");
  const envio = await guardarRepartoDe(f.d, "p", { id_cliente: ID, tipo: "envio", lineas: [] }) as { error: { codigo: string } };
  assertEquals(envio.error.codigo, "DATOS_NO_VALIDOS");
});

Deno.test("guardar_reparto: guarda con la lectura la cobertura a 2 semanas (R4), sin los excluidos; si falla, el reparto sigue", async () => {
  const ctx = { ...CTX, config: { ...CTX.config, stock_excluidos: [{ producto: "MINI", formato: "10g", motivo: "Minis" }] } };
  const f = falso({ ctx });
  await guardarRepartoDe(f.d, "p", cuerpo());
  const a = f.args("servidor_guardar_cobertura")!;
  const cobertura = a.p_cobertura as { productos: { producto: string }[]; avisos: string[] };
  assertEquals(a.p_lectura, "lectura-1");
  assertEquals(cobertura.productos.some((x) => x.producto === "MINI"), false);
  const g = falso({ ctx, fallaCobertura: true });
  const r = await guardarRepartoDe(g.d, "p", cuerpo()) as Record<string, unknown>;
  assertEquals([r.error, r.reparto_id], [undefined, "reparto-1"]);
});

// ===== Tarea 16: producto sin granel en el reparto (R1e) =====
Deno.test("guardar_reparto: lo que hay que hacer sin granel va marcado a la producción; el texto lo da la base de datos", async () => {
  const sinGranel: DatosHoja = {
    ...DATOS, productos: DATOS.productos.map((p) => p.nombre === "BZ1"
      ? { ...p, granel: "0", formatos: [{ formato: "4g", almacen: "0", tiendas: { ALGORTA: "4", BILBAO: "1" } }] } : p),
  };
  const lineas = [{ destino_id: "bilbao", producto: "BZ1", formato: "4g", cantidad: 3 }];
  const f = falso({ lectura: { ok: true, datos: sinGranel },
                    guardado: { reparto_id: "reparto-1", estado: "aceptado", texto_whatsapp: "texto de la base de datos" } });
  const r = await guardarRepartoDe(f.d, "p", cuerpo({ lineas }));
  const prod = (f.args("servidor_guardar_reparto")!.p_produccion as Record<string, unknown>[])[0];
  assertEquals([prod.producto, prod.faltan, prod.sin_granel], ["BZ1", 3, true]);
  assertEquals(prod.para, [{ destino_id: "bilbao", destino: "Bilbao", pedido: 3, faltan: 3 }]);
  assertEquals(prod.tiendas_con_stock, [{ destino_id: "algorta", destino: "Algorta", cajas: 4 }]);
  assertEquals(r.texto_whatsapp, "texto de la base de datos");
});

// ===== Tarea 17: envío sin granel (R1e en el envío): se comprueba al calcular =====
const hojaEnvio = (granel: string, almacen: string): DatosHoja => ({
  ...DATOS, productos: DATOS.productos.map((p) => p.nombre === "BZ1"
    ? { ...p, granel, formatos: [{ formato: "4g", almacen }] } : p),
});
const envio = (lineas: { destino_id: string; cantidad: number }[], id = ID) =>
  ({ id_cliente: id, tipo: "envio", lineas: lineas.map((l) => ({ ...l, producto: "BZ1", formato: "4g" })) });

Deno.test("E-01 envío con granel: se guarda como siempre (BZ1 con 0 en el almacén se hace)", async () => {
  const f = falso({ lectura: { ok: true, datos: hojaEnvio("500", "0") } });
  const r = await guardarRepartoDe(f.d, "p", envio([{ destino_id: "gipuzkoa", cantidad: 5 }]));
  assertEquals([r.error, (f.args("servidor_guardar_reparto")!.p_produccion as { faltan: number }[])[0].faltan], [undefined, 5]);
});

Deno.test("E-02 y E-03 sin granel: no se guarda nada; SIN_GRANEL con lo pedido y lo que hay", async () => {
  const cero = falso({ lectura: { ok: true, datos: hojaEnvio("0", "0") } });
  const r0 = await guardarRepartoDe(cero.d, "p", envio([{ destino_id: "gipuzkoa", cantidad: 5 }])) as { error: Record<string, unknown> };
  assertEquals(r0.error.codigo, "SIN_GRANEL");
  assertEquals(r0.error.mensaje, "BZ1 4g: pides 5, en el almacén no hay cajas y no hay granel para hacerlas.");
  assertEquals(r0.error.referencias, [{ destino_id: "gipuzkoa", destino: "Gipuzkoa (envío a Rentería)", producto: "BZ1", formato: "4g",
                                        pedido: 5, hay: 0, mensaje: "BZ1 4g: pides 5, en el almacén no hay cajas y no hay granel para hacerlas." }]);
  assertEquals([cero.args("servidor_guardar_reparto"), cero.args("servidor_reparto_anotar_id_cliente")], [undefined, undefined]);
  const tres = falso({ lectura: { ok: true, datos: hojaEnvio("0", "3") } });
  const r3 = await guardarRepartoDe(tres.d, "p", envio([{ destino_id: "gipuzkoa", cantidad: 5 }])) as { error: Record<string, unknown> };
  assertEquals(r3.error.mensaje, "BZ1 4g: pides 5, en el almacén hay 3 cajas y no hay granel para hacer las otras 2.");
  assertEquals((r3.error.referencias as { hay: number }[])[0].hay, 3);
});

Deno.test("E-04 dos destinos: las cajas se las lleva el primero (Gipuzkoa); a Durango le faltan", async () => {
  const f = falso({ lectura: { ok: true, datos: hojaEnvio("0", "5") } });
  const r = await guardarRepartoDe(f.d, "p", envio([{ destino_id: "durango", cantidad: 3 }, { destino_id: "gipuzkoa", cantidad: 4 }])) as
    { error: { referencias: { destino: string; pedido: number; hay: number; mensaje: string }[] } };
  assertEquals(r.error.referencias.map((x) => [x.destino, x.pedido, x.hay]), [["Durango", 3, 1]]);
  assertEquals(r.error.referencias[0].mensaje, "BZ1 4g: pides 3, en el almacén hay 1 caja y no hay granel para hacer las otras 2.");
});

Deno.test("E-05 viernes con reparto el mismo día: primero se aparta lo del reparto", async () => {
  // 6 en el almacén, 4 para el reparto de hoy que aún no ha salido: para el envío quedan 2.
  const f = falso({ lectura: { ok: true, datos: hojaEnvio("0", "6") },
                    ctx: { ...CTX, comprometido: { ...CTX.comprometido, reparto: bz1(4) } } });
  const r = await guardarRepartoDe(f.d, "p", envio([{ destino_id: "gipuzkoa", cantidad: 3 }])) as { error: Record<string, unknown> };
  assertEquals(r.error.mensaje, "BZ1 4g: pides 3, en el almacén hay 2 cajas y no hay granel para hacer la otra.");
});

Deno.test("E-06 tras SIN_GRANEL, el mismo id_cliente con la lista corregida («Dejarlo en 3») se guarda normal", async () => {
  const f = falso({ lectura: { ok: true, datos: hojaEnvio("0", "3") } });
  const primero = await guardarRepartoDe(f.d, "p", envio([{ destino_id: "gipuzkoa", cantidad: 5 }])) as { error?: { codigo: string } };
  const segundo = await guardarRepartoDe(f.d, "p", envio([{ destino_id: "gipuzkoa", cantidad: 3 }])) as Record<string, unknown>;
  assertEquals([primero.error?.codigo, segundo.error, segundo.reparto_id], ["SIN_GRANEL", undefined, "reparto-1"]);
  assertEquals((f.args("servidor_guardar_reparto")!.p_produccion as { faltan: number }[])[0].faltan, 0);
});

Deno.test("E-07 el reparto no cambia: sin granel va a la producción (Tarea 16), no da SIN_GRANEL", async () => {
  const f = falso({ lectura: { ok: true, datos: hojaEnvio("0", "0") } });
  const r = await guardarRepartoDe(f.d, "p", cuerpo({ lineas: [{ destino_id: "bilbao", producto: "BZ1", formato: "4g", cantidad: 3 }] }));
  assertEquals([r.error, (f.args("servidor_guardar_reparto")!.p_produccion as { sin_granel?: boolean }[])[0].sin_granel], [undefined, true]);
});
