// Funciones del servidor del reparto con lista (CONTRATOS.md §3.13 y §3.14):
// `catalogo` y `guardar_reparto`. La lógica va aquí, con la lectura de la hoja
// y las llamadas a la base de datos recibidas desde fuera, para poder probarla
// sin red (reparto_lista_test.ts). Los index.ts solo la conectan.

import type { Pestanas, ResultadoLectura } from "./google.ts";
import type { Destino } from "./r1.ts";
import { prepararReparto, referencias, validarLineas } from "./lista.ts";

export interface Dependencias {
  rpc: <T = unknown>(nombre: string, args: Record<string, unknown>) => Promise<T>;
  leer: (documento: string, pestanas: Pestanas) => Promise<ResultadoLectura>;
  huella: (tipo: string, texto: string) => Promise<string>;
  ahora?: () => Date;
}

interface DestinoCtx extends Destino {
  codigo: string;
  tipo: string;
  activo: boolean;
}

interface Contexto {
  error?: { codigo: string; mensaje: string };
  rol: string;
  jornada_id: string | null;
  dia: number;
  mes: number;
  fecha: string;
  destinos: DestinoCtx[];
  config: { sheets_documento_id: string; sheets_pestanas: Pestanas };
  reparto_hoy: { producto: string; formato: string; pedido: number }[];
  recuento_manana_hecho: boolean;
}

type Respuesta = Record<string, unknown>;

const error = (codigo: string, mensaje: string, extra: Record<string, unknown> = {}): Respuesta =>
  ({ error: { codigo, mensaje, ...extra } });

const errorHoja = (l: Extract<ResultadoLectura, { ok: false }>) =>
  error(l.codigo, l.codigo === "SHEETS_NO_DISPONIBLE"
    ? "No puedo leer la hoja de stock ahora. Vuelve a intentarlo en un minuto; si sigue, avisa a Administración."
    : "La hoja de stock ha cambiado de forma. Avisa a Administración.", { detalle: l.detalle });

/** Tiendas válidas: las activas para el reparto; el destino del envío (GIPUZKOA) para el envío. */
export const tiendasDe = (destinos: DestinoCtx[], tipo: "reparto" | "envio") =>
  destinos.filter((d) => d.activo && (tipo === "reparto" ? d.tipo === "tienda" : d.tipo === "destino"));

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
      reparto: tiendasDe(ctx.destinos, "reparto").map(tienda),
      envio: tiendasDe(ctx.destinos, "envio").map(tienda),
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
  const destinos = tiendasDe(ctx.destinos, tipo);
  const v = validarLineas(cuerpo.lineas, entradas, destinos);
  if (!v.ok) return error(v.codigo, v.mensaje, v.detalle);

  const { texto, r } = prepararReparto({
    tipo, hoy: { dia: ctx.dia, mes: ctx.mes }, sale, lineas: v.lineas, destinos, entradas,
    // Envío antes del recuento de la mañana: se apartan las cajas del reparto de hoy (v1.11).
    apartadoReparto: tipo === "envio" && !ctx.recuento_manana_hecho ? ctx.reparto_hoy : [],
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
  await d.rpc("servidor_reparto_anotar_id_cliente", { p_reparto: guardado.reparto_id, p_id_cliente: idCliente });
  if (guardado.ya_pegado) {
    return { ...guardado, texto_whatsapp: texto,
             aviso: { codigo: "REPARTO_SIN_CAMBIOS", mensaje: "El reparto de hoy ya era este: no cambia nada." } };
  }
  return { ...guardado, texto_whatsapp: texto };
}
