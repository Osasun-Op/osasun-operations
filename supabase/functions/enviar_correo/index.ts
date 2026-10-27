// enviar_correo: envía por correo un cierre de turno o un aviso de retraso de la
// salida (D3). Solo la llama la base de datos, con una solicitud interna de un
// solo uso; las pantallas no pueden. Cada correo se reclama antes de enviarlo,
// así nunca sale dos veces por el mismo intento.

import { enviarResend } from "../_compartido/correo.ts";
import { CORS, error, responder, rpc } from "../_compartido/servidor.ts";

interface Reclamo {
  error?: { codigo: string; mensaje: string };
  enviar: boolean;
  motivo?: string;
  destino: string;
  remitente: string;
  asunto: string;
  texto: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const solicitud = req.headers.get("x-solicitud");
    const persona = solicitud
      ? await rpc<string | null>("servidor_canjear_solicitud", { p_id: solicitud, p_funcion: "enviar_correo" })
      : null;
    if (!persona) return responder(error("NO_AUTORIZADO", "No tienes permiso para esto."), 401);

    const { tipo, ref } = await req.json();
    const reclamo = await rpc<Reclamo>("servidor_correo_reclamar", { p_tipo: String(tipo), p_ref: String(ref) });
    if (reclamo.error || !reclamo.enviar) return responder(reclamo);

    // Rechazado: la base de datos lo reintenta (hasta 3 veces, cada 5 min). Dudoso: no.
    const r = await enviarResend(Deno.env.get("RESEND_API_KEY"), reclamo);
    await rpc("servidor_correo_respuesta", {
      p_tipo: String(tipo), p_ref: String(ref), p_estado: r.estado,
      p_detalle: r.estado === "enviado" ? `resend:${r.id}` : r.detalle,
    });
    return responder(r.estado === "enviado"
      ? { enviado: true, asunto: reclamo.asunto }
      : error("CORREO_NO_ENVIADO", "No se ha podido enviar el correo.", { estado: r.estado, detalle: r.detalle }));
  } catch (e) {
    console.error(e);
    return responder(error("ERROR_INTERNO", "Ha fallado el servidor."), 500);
  }
});
