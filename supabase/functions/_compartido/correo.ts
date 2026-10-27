// Envío de correo con Resend (D3). La clave va como secreto del entorno
// (RESEND_API_KEY); nunca en el repositorio.

export interface Correo {
  remitente: string;
  destino: string;
  asunto: string;
  texto: string;
}

export type ResultadoCorreo = { ok: true; id: string } | { ok: false; detalle: string };

export async function enviarResend(
  clave: string | undefined,
  correo: Correo,
  hacerFetch: typeof fetch = fetch,
): Promise<ResultadoCorreo> {
  if (!clave) return { ok: false, detalle: "Falta el secreto RESEND_API_KEY" };
  try {
    const r = await hacerFetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${clave}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: correo.remitente, to: [correo.destino], subject: correo.asunto, text: correo.texto }),
    });
    const cuerpo = await r.json().catch(() => ({}));
    if (!r.ok) return { ok: false, detalle: `Resend HTTP ${r.status}: ${cuerpo?.message ?? cuerpo?.name ?? ""}` };
    return { ok: true, id: String(cuerpo?.id ?? "") };
  } catch (e) {
    return { ok: false, detalle: `Resend no responde: ${(e as Error).message}` };
  }
}
