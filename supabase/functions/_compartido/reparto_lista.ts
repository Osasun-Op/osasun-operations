// Funciones del servidor del reparto con lista (CONTRATOS.md §3.13 y §3.14):
// `catalogo` y `guardar_reparto`. La lógica va aquí, con la lectura de la hoja
// y las llamadas a la base de datos recibidas desde fuera, para poder probarla
// sin red (reparto_lista_test.ts). Los index.ts solo la conectan.

import type { Pestanas, ResultadoLectura } from "./google.ts";
import type { Destino } from "./r1.ts";
import { prepararReparto, referencias, validarLineas } from "./lista.ts";
import { type Cajas, type Comprometido, listaPedido, SIN_COMPROMISOS } from "./pedidos.ts";

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
  };
  /** R1c: lo comprometido hoy que la hoja aún cuenta en el almacén (motor.comprometido). */
  comprometido?: Comprometido;
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
  return {
    tiendas: {
      reparto: tiendasDe(ctx, "reparto").map(tienda),
      envio: tiendasDe(ctx, "envio").map(tienda),
    },
    productos: lista,
    datos_leidos_en: (d.ahora?.() ?? new Date()).toISOString(),
  };
}

/** guardar_reparto(id_cliente, tipo, sale?, lineas): calcula y guarda el reparto o el envío. */
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

  const { entradas, ambiguas } = referencias(lectura.datos);
  if (ambiguas.length > 0) {
    return error("CATALOGO_AMBIGUO", "Hay nombres repetidos en PRINCIPAL. Avisa a Administración.", { claves: ambiguas });
  }
  const destinos = tiendasDe(ctx, tipo);
  const v = validarLineas(cuerpo.lineas, entradas, destinos);
  if (!v.ok) return error(v.codigo, v.mensaje, v.detalle);

  const c = ctx.comprometido ?? SIN_COMPROMISOS;
  const { texto, r } = prepararReparto({
    tipo, hoy: { dia: ctx.dia, mes: ctx.mes }, sale, lineas: v.lineas, destinos, entradas,
    // Envío: primero se apartan las cajas que salen hoy con el reparto (reparto y
    // pedidos de tienda) mientras la hoja aún las cuenta, es decir, antes del
    // recuento de la mañana (v1.11 y R1c). Lo decide motor.comprometido.
    apartadoReparto: tipo === "envio"
      ? [...c.reparto, ...c.pedidos_tienda].map((x) => ({ producto: x.producto, formato: x.formato, pedido: x.cantidad }))
      : [],
  });
  if (r.estado !== "aceptado") {
    return error("REPARTO_NO_CALCULADO", "No se ha podido calcular el reparto. Avisa a Administración.",
                 { estado: r.estado, lineas: r.errores.map((l) => ({ num: l.num, texto: l.texto, error: l.error })) });
  }

  const guardado = await d.rpc<Respuesta>("servidor_guardar_reparto", {
    p_persona: persona, p_jornada: ctx.jornada_id, p_tipo: tipo, p_texto: texto, p_huella: await d.huella(tipo, texto),
    p_fecha_texto: ctx.fecha, p_sale: r.sale, p_lectura: lecturaId, p_lineas: r.lineas,
    p_produccion: r.produccion, p_bolsas: r.bolsas, p_aceptado: true,
  });
  if (guardado.error) return guardado;

  // Pedidos de cliente para recoger en tienda (R1b): van en este reparto, con su
  // tarea y su bolsa aparte («coge / haz» al salir la tarea). También si el
  // reparto no cambia, para no perder un pedido si la llamada anterior se cortó.
  let pedidosCliente: unknown[] = [];
  if (tipo === "reparto") {
    const enLista = new Set(destinos.map((x) => x.id));
    const pedidos = (ctx.pedidos_tienda ?? []).filter((p) => enLista.has(p.destino_id));
    if (pedidos.length > 0) {
      const asignados = await d.rpc<{ pedidos: unknown[] }>("servidor_asignar_pedidos", {
        p_persona: persona, p_reparto: guardado.reparto_id,
        p_pedidos: pedidos.map((p) => ({ pedido_id: p.id, elementos: listaPedido(p.lineas, entradas, lectura.datos.categorias) })),
      });
      pedidosCliente = asignados.pedidos ?? [];
    }
  }
  await d.rpc("servidor_reparto_anotar_id_cliente", { p_reparto: guardado.reparto_id, p_id_cliente: idCliente });
  if (guardado.ya_pegado) {
    return { ...guardado, texto_whatsapp: texto, pedidos_cliente: pedidosCliente,
             aviso: { codigo: "REPARTO_SIN_CAMBIOS", mensaje: "El reparto de hoy ya era este: no cambia nada." } };
  }
  return { ...guardado, texto_whatsapp: texto, pedidos_cliente: pedidosCliente };
}
