// Funciones del servidor del reparto con lista (CONTRATOS.md §3.13 y §3.14):
// `catalogo` y `guardar_reparto`. La lógica va aquí, con la lectura de la hoja
// y las llamadas a la base de datos recibidas desde fuera, para poder probarla
// sin red (reparto_lista_test.ts). Los index.ts solo la conectan.

import type { Pestanas, ResultadoLectura } from "./google.ts";
import type { Destino } from "./r1.ts";
import { prepararReparto, referencias, validarLineas, validarPeticiones } from "./lista.ts";
import { type Cajas, type Comprometido, listaPedido, SIN_COMPROMISOS } from "./pedidos.ts";
import { ajusteAlmacen, aplicarAjuste, type MovimientosAlmacen, SIN_MOVIMIENTOS } from "./almacen.ts";
import { guardarCobertura } from "./r4.ts";
import { marcarSinGranel, sinGranelEnvio } from "./sin_granel.ts";

export interface Dependencias {
  rpc: <T = unknown>(nombre: string, args: Record<string, unknown>) => Promise<T>;
  leer: (documento: string, pestanas: Pestanas) => Promise<ResultadoLectura>;
  huella: (tipo: string, texto: string) => Promise<string>;
  ahora?: () => Date;
}

interface DestinoCtx extends Destino {
  codigo: string;
}

interface Contexto {
  error?: { codigo: string; mensaje: string };
  rol: string;
  jornada_id: string | null;
  dia: number;
  mes: number;
  fecha: string;
  destinos: DestinoCtx[];
  config: {
    sheets_documento_id: string;
    sheets_pestanas: Pestanas;
    destinos_reparto?: { reparto: string[]; envio: string[] };
    stock_excluidos?: { producto: string; formato: string; motivo: string }[];
  };
  /** R1c: lo comprometido hoy que aún no ha salido del almacén, y lo que va en camino (motor.comprometido_en). */
  comprometido?: Comprometido;
  /** R1c: lo producido y lo salido desde el último recuento (almacén ahora = hoja + producido − salido). */
  almacen?: MovimientosAlmacen;
  /** Pedidos de cliente para recoger en tienda que van en el reparto de hoy. */
  pedidos_tienda?: { id: string; cliente: string; destino_id: string; lineas: Cajas[] }[];
}

type Respuesta = Record<string, unknown>;

const error = (codigo: string, mensaje: string, extra: Record<string, unknown> = {}): Respuesta =>
  ({ error: { codigo, mensaje, ...extra } });

const errorHoja = (l: Extract<ResultadoLectura, { ok: false }>) =>
  error(l.codigo, l.codigo === "SHEETS_NO_DISPONIBLE"
    ? "No puedo leer la hoja de stock ahora. Vuelve a intentarlo en un minuto; si sigue, avisa a Administración."
    : "La hoja de stock ha cambiado de forma. Avisa a Administración.", { detalle: l.detalle });

/**
 * Tiendas que se pueden elegir y su orden, el de las hojas de tienda de STOCK
 * OSASUN (configuración `destinos_reparto`): reparto BILBAO, ALGORTA, BARAKALDO,
 * BASAURI, PORTU; envío GIPUZKOA, DURANGO. Donosti y Rentería no entran.
 */
export const tiendasDe = (ctx: Pick<Contexto, "destinos" | "config">, tipo: "reparto" | "envio") =>
  (ctx.config.destinos_reparto?.[tipo] ?? [])
    .map((codigo) => ctx.destinos.find((d) => d.codigo === codigo))
    .filter((d): d is DestinoCtx => d !== undefined);

/** Pedidos de cliente para recoger en tienda del reparto de hoy, en las tiendas del reparto. */
const pedidosDelReparto = (ctx: Pick<Contexto, "pedidos_tienda">, destinos: Destino[]) => {
  const enLista = new Set(destinos.map((x) => x.id));
  return (ctx.pedidos_tienda ?? []).filter((p) => enLista.has(p.destino_id));
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** catalogo(): tiendas y referencias de PRINCIPAL, con su categoría. */
export async function catalogoDe(d: Dependencias, persona: string): Promise<Respuesta> {
  const ctx = await d.rpc<Contexto>("servidor_preparar", { p_persona: persona });
  if (ctx.error) return ctx as unknown as Respuesta;
  const lectura = await d.leer(ctx.config.sheets_documento_id, ctx.config.sheets_pestanas);
  if (!lectura.ok) return errorHoja(lectura);
  const { referencias: lista, ambiguas } = referencias(lectura.datos);
  if (ambiguas.length > 0) {
    return error("CATALOGO_AMBIGUO", "Hay nombres repetidos en PRINCIPAL. Avisa a Administración.", { claves: ambiguas });
  }
  const tienda = (x: DestinoCtx) => ({ id: x.id, codigo: x.codigo, nombre: x.nombre });
  const reparto = tiendasDe(ctx, "reparto");
  return {
    tiendas: {
      reparto: reparto.map(tienda),
      envio: tiendasDe(ctx, "envio").map(tienda),
    },
    productos: lista,
    // Pedidos de cliente para recoger en tienda que van en el reparto de hoy:
    // en «Preparar reparto», marcados y fijos en su tienda (Tarea 14).
    pedidos_cliente: pedidosDelReparto(ctx, reparto).map((p) => {
      const destino = reparto.find((x) => x.id === p.destino_id)!.nombre;
      return { id: p.id, cliente: p.cliente, destino_id: p.destino_id, destino, lineas: p.lineas,
               texto: `Pedido de ${p.cliente} a tienda de ${destino}` };
    }),
    datos_leidos_en: (d.ahora?.() ?? new Date()).toISOString(),
  };
}

/** guardar_reparto(id_cliente, tipo, sale?, lineas, peticiones?): calcula y guarda el reparto o el envío. */
export async function guardarRepartoDe(d: Dependencias, persona: string, cuerpo: Record<string, unknown>): Promise<Respuesta> {
  const tipo = cuerpo.tipo === "envio" ? "envio" : cuerpo.tipo === "reparto" || cuerpo.tipo === undefined ? "reparto" : null;
  const idCliente = typeof cuerpo.id_cliente === "string" && UUID.test(cuerpo.id_cliente) ? cuerpo.id_cliente : null;
  if (!tipo || !idCliente) return error("DATOS_NO_VALIDOS", "Faltan datos del reparto (tipo o id_cliente).");
  const sale = cuerpo.sale === "operario" || cuerpo.sale === "administracion" ? cuerpo.sale : null;
  if (tipo === "reparto" && !sale) {
    return error("FALTA_SALE", "¿Quién sale hoy?", { opciones: ["operario", "administracion"] });
  }

  const ctx = await d.rpc<Contexto>("servidor_preparar", { p_persona: persona });
  if (ctx.error) return ctx as unknown as Respuesta;
  if (!ctx.jornada_id) return error("SIN_JORNADA", "Hoy no hay jornada en el almacén.");

  // Reintento de la misma petición: el mismo resultado, sin volver a calcular.
  const previo = await d.rpc<Respuesta | null>("servidor_reparto_por_id_cliente", { p_id_cliente: idCliente });
  if (previo) {
    return { ...previo, ya_guardado: true,
             aviso: { codigo: "REPARTO_YA_GUARDADO", mensaje: "Este reparto ya estaba guardado." } };
  }

  const lectura = await d.leer(ctx.config.sheets_documento_id, ctx.config.sheets_pestanas);
  const lecturaId = await d.rpc<string>("servidor_guardar_lectura", {
    p_persona: persona, p_motivo: tipo, p_correcto: lectura.ok,
    p_error: lectura.ok ? null : `${lectura.codigo}: ${lectura.detalle}`,
    p_datos: lectura.ok ? lectura.datos : {},
  });
  if (!lectura.ok) return errorHoja(lectura);
  // R4: la cobertura de esta lectura, para el panel de Administración.
  await guardarCobertura(d.rpc, lecturaId, lectura.datos, ctx.config.stock_excluidos ?? []);

  const { entradas, ambiguas } = referencias(lectura.datos);
  if (ambiguas.length > 0) {
    return error("CATALOGO_AMBIGUO", "Hay nombres repetidos en PRINCIPAL. Avisa a Administración.", { claves: ambiguas });
  }
  const destinos = tiendasDe(ctx, tipo);
  // Un pedido para recoger en tienda activa el reparto: puede ir solo, sin productos.
  const pedidos = tipo === "reparto" ? pedidosDelReparto(ctx, destinos) : [];
  const v = validarLineas(cuerpo.lineas, entradas, destinos, pedidos.length > 0);
  if (!v.ok) return error(v.codigo, v.mensaje, v.detalle);
  const pv = validarPeticiones(cuerpo.peticiones, destinos);
  if (!pv.ok) return error("DATOS_NO_VALIDOS", pv.mensaje, pv.detalle);

  const c = ctx.comprometido ?? SIN_COMPROMISOS;
  const { texto, r } = prepararReparto({
    tipo, hoy: { dia: ctx.dia, mes: ctx.mes }, sale, lineas: v.lineas, destinos, peticiones: pv.peticiones,
    // R1c: el almacén ahora (hoja + lo producido desde el recuento − lo que ha salido).
    entradas: aplicarAjuste(entradas, ajusteAlmacen(ctx.almacen ?? SIN_MOVIMIENTOS, tipo)),
    // Envío: primero se apartan las cajas del reparto y de los pedidos de tienda de
    // hoy que aún no han salido (bolsas sin terminar). Lo decide motor.comprometido_en.
    apartadoReparto: tipo === "envio"
      ? [...c.reparto, ...c.pedidos_tienda].map((x) => ({ producto: x.producto, formato: x.formato, pedido: x.cantidad }))
      : [],
    permitirVacio: pedidos.length > 0,
  });
  // R1e: lo que hay que hacer sin granel se resuelve en la producción (quitarlo o de otra tienda).
  const produccion = tipo === "reparto" ? marcarSinGranel(r.produccion, r.bolsas, lectura.datos, destinos) : r.produccion;
  if (r.estado !== "aceptado") {
    return error("REPARTO_NO_CALCULADO", "No se ha podido calcular el reparto. Avisa a Administración.",
                 { estado: r.estado, lineas: r.errores.map((l) => ({ num: l.num, texto: l.texto, error: l.error })) });
  }
  // R1e en el envío: lo que hay que hacer sin granel no se guarda; la pantalla
  // ofrece «Dejarlo en N» o «Quitarlo» y vuelve a calcular.
  if (tipo === "envio") {
    const sinGranel = sinGranelEnvio(r.produccion, r.bolsas, lectura.datos, destinos);
    if (sinGranel.length > 0) {
      return error("SIN_GRANEL", sinGranel.map((x) => x.mensaje).join("\n"), { referencias: sinGranel });
    }
  }

  const guardado = await d.rpc<Respuesta>("servidor_guardar_reparto", {
    p_persona: persona, p_jornada: ctx.jornada_id, p_tipo: tipo, p_texto: texto, p_huella: await d.huella(tipo, texto),
    p_fecha_texto: ctx.fecha, p_sale: r.sale, p_lectura: lecturaId, p_lineas: r.lineas,
    p_produccion: produccion, p_bolsas: r.bolsas, p_aceptado: true,
  });
  if (guardado.error) return guardado;

  // Peticiones especiales (R1d): en la bolsa de su tienda, sin tocar producción
  // ni stock. También si el reparto no cambia, por si la llamada anterior se cortó.
  const { peticiones } = await d.rpc<{ peticiones: unknown[] }>("servidor_guardar_peticiones", {
    p_persona: persona, p_reparto: guardado.reparto_id, p_peticiones: pv.peticiones,
  });

  // Pedidos de cliente para recoger en tienda (R1b): van en este reparto, con su
  // tarea y su bolsa aparte («coge / haz» al salir la tarea). También si el
  // reparto no cambia, para no perder un pedido si la llamada anterior se cortó.
  let pedidosCliente: unknown[] = [];
  if (tipo === "reparto") {
    if (pedidos.length > 0) {
      const asignados = await d.rpc<{ pedidos: unknown[] }>("servidor_asignar_pedidos", {
        p_persona: persona, p_reparto: guardado.reparto_id,
        p_pedidos: pedidos.map((p) => ({ pedido_id: p.id, elementos: listaPedido(p.lineas, entradas, lectura.datos.categorias) })),
      });
      pedidosCliente = asignados.pedidos ?? [];
    }
  }
  await d.rpc("servidor_reparto_anotar_id_cliente", { p_reparto: guardado.reparto_id, p_id_cliente: idCliente });
  // El texto lo da la base de datos: con lo decidido en la producción (R1e) ya aplicado.
  const textoWhatsapp = typeof guardado.texto_whatsapp === "string" ? guardado.texto_whatsapp : texto;
  if (guardado.ya_pegado) {
    return { ...guardado, texto_whatsapp: textoWhatsapp, peticiones, pedidos_cliente: pedidosCliente,
             aviso: { codigo: "REPARTO_SIN_CAMBIOS", mensaje: "El reparto de hoy ya era este: no cambia nada." } };
  }
  return { ...guardado, texto_whatsapp: textoWhatsapp, peticiones, pedidos_cliente: pedidosCliente };
}
