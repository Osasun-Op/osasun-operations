// pegar_reparto (CONTRATOS.md §3.8): el operario o Administración pegan el texto
// del reparto o del envío. Lee la hoja, aplica R1 y, si no hay errores, crea o
// actualiza las tareas de producción y bolsas. Con errores no se calcula nada.
// Si lo pega Administración, va a la jornada del operario por defecto.

import { leerStock, type Pestanas } from "../_compartido/google.ts";
import { analizarReparto, catalogo, type Destino } from "../_compartido/r1.ts";
import { CORS, error, huella, quienLlama, responder, rpc } from "../_compartido/servidor.ts";

interface Contexto {
  error?: { codigo: string; mensaje: string };
  persona_id: string;
  rol: string;
  jornada_id: string | null;
  dia: number;
  mes: number;
  fecha: string;
  destinos: Destino[];
  config: { sheets_documento_id: string; sheets_pestanas: Pestanas };
  repartos: Record<string, { id: string; huella: string; resultado: Record<string, unknown> } | null>;
  reparto_hoy: { producto: string; formato: string; pedido: number }[];
  recuento_manana_hecho: boolean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const persona = await quienLlama(req, "pegar_reparto");
    if (!persona) return responder(error("NO_AUTENTICADO", "Tienes que iniciar sesión."), 401);

    const cuerpo = await req.json().catch(() => ({}));
    const texto = typeof cuerpo.texto === "string" ? cuerpo.texto : "";
    const tipo = cuerpo.tipo === "envio" ? "envio" : cuerpo.tipo === "reparto" || cuerpo.tipo === undefined ? "reparto" : null;
    const saleRespuesta = cuerpo.sale === "operario" || cuerpo.sale === "administracion" ? cuerpo.sale : null;
    if (!tipo || texto.trim() === "") {
      return responder(error("DATOS_NO_VALIDOS", "Pega el texto del reparto."));
    }

    const ctx = await rpc<Contexto>("servidor_preparar", { p_persona: persona });
    if (ctx.error) return responder(ctx);
    if (!ctx.jornada_id) return responder(error("SIN_JORNADA", "Hoy no hay jornada en el almacén."));

    const laHuella = await huella(tipo, texto);
    const actual = ctx.repartos[tipo];
    if (actual && actual.huella === laHuella) {
      return responder({ ...actual.resultado, ya_pegado: true, aviso: { codigo: "REPARTO_YA_PEGADO", mensaje: "Este reparto ya estaba pegado." } });
    }

    const lectura = await leerStock(
      Deno.env.get("GOOGLE_CUENTA_TECNICA"), ctx.config.sheets_documento_id, ctx.config.sheets_pestanas,
    );
    const lecturaId = await rpc<string>("servidor_guardar_lectura", {
      p_persona: persona, p_motivo: tipo, p_correcto: lectura.ok,
      p_error: lectura.ok ? null : `${lectura.codigo}: ${lectura.detalle}`,
      p_datos: lectura.ok ? lectura.datos : {},
    });
    if (!lectura.ok) {
      return responder(error(lectura.codigo, lectura.codigo === "SHEETS_NO_DISPONIBLE"
        ? "No puedo leer el stock ahora. Vuelve a intentarlo en un minuto; si sigue, avisa a Administración."
        : "La hoja de stock ha cambiado de forma. Avisa a Administración.", { detalle: lectura.detalle }));
    }

    const { entradas, ambiguas } = catalogo(lectura.datos.productos);
    if (ambiguas.length > 0) {
      return responder(error("CATALOGO_AMBIGUO", "Hay nombres repetidos en PRINCIPAL. Avisa a Administración.", { claves: ambiguas }));
    }

    const r = analizarReparto(texto, entradas, ctx.destinos, {
      tipo, hoy: { dia: ctx.dia, mes: ctx.mes }, sale: saleRespuesta, confirmarFecha: cuerpo.confirmar_fecha === true,
      // Envío antes del recuento de la mañana: se apartan las cajas del reparto de hoy (v1.11).
      apartadoReparto: tipo === "envio" && !ctx.recuento_manana_hecho ? ctx.reparto_hoy : [],
    });
    const fechaTexto = r.fecha
      ? `${ctx.fecha.slice(0, 4)}-${String(r.fecha.mes).padStart(2, "0")}-${String(r.fecha.dia).padStart(2, "0")}`
      : null;

    if (r.estado === "falta_sale") {
      return responder(error("FALTA_SALE", "¿Quién sale hoy?", { opciones: ["operario", "administracion"] }));
    }
    if (r.estado === "fecha_no_es_hoy") {
      return responder(error("FECHA_NO_ES_HOY",
        `Este reparto es del ${r.fecha!.dia}/${r.fecha!.mes}. ¿Seguro que es el de hoy?`, { fecha: r.fecha }));
    }

    const guardado = await rpc<Record<string, unknown>>("servidor_guardar_reparto", {
      p_persona: persona, p_jornada: ctx.jornada_id, p_tipo: tipo, p_texto: texto, p_huella: laHuella,
      p_fecha_texto: fechaTexto, p_sale: r.sale, p_lectura: lecturaId, p_lineas: r.lineas,
      p_produccion: r.produccion, p_bolsas: r.bolsas, p_aceptado: r.estado === "aceptado",
    });

    if (r.estado === "con_errores") {
      return responder(error("REPARTO_CON_ERRORES", "Hay líneas que no entiendo. Corrígelas y vuelve a pegarlo.", {
        reparto_id: guardado.reparto_id,
        lineas: r.errores.map((l) => ({ num: l.num, texto: l.texto, error: l.error, mensaje: l.mensaje })),
      }));
    }
    if (guardado.ya_pegado) {
      return responder({ ...guardado, aviso: { codigo: "REPARTO_YA_PEGADO", mensaje: "Este reparto ya estaba pegado." } });
    }
    return responder(guardado);
  } catch (e) {
    console.error(e);
    return responder(error("ERROR_INTERNO", "Algo ha fallado en el servidor. Vuelve a intentarlo; si sigue, avisa a Administración."), 500);
  }
});
