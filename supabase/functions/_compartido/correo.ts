// Envío de correo con Resend (D3). La clave va como secreto del entorno
// (RESEND_API_KEY); nunca en el repositorio.
// Resultado: enviado; rechazado (Resend respondió con un error: el correo no
// salió y se puede reintentar); o dudoso (sin respuesta a tiempo: puede que haya
// salido, así que no se reintenta para no enviarlo dos veces).

export interface Correo {
  remitente: string;
  destino: string;
  asunto: string;
  texto: string;
}

export type ResultadoCorreo =
  | { estado: "enviado"; id: string }
  | { estado: "rechazado" | "dudoso"; detalle: string };

const ESPERA_MS = 15_000;

export async function enviarResend(
  clave: string | undefined,
  correo: Correo,
  hacerFetch: typeof fetch = fetch,
  esperaMs = ESPERA_MS,
): Promise<ResultadoCorreo> {
  if (!clave) return { estado: "rechazado", detalle: "Falta el secreto RESEND_API_KEY" };
  const control = new AbortController();
  const temporizador = setTimeout(() => control.abort(), esperaMs);
  let r: Response;
  try {
    r = await hacerFetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${clave}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: correo.remitente, to: [correo.destino], subject: correo.asunto, text: correo.texto }),
      signal: control.signal,
    });
  } catch (e) {
    return { estado: "dudoso", detalle: `Resend no responde: ${(e as Error).message}` };
  } finally {
    clearTimeout(temporizador);
  }
  const cuerpo = await r.json().catch(() => ({}));
  if (!r.ok) return { estado: "rechazado", detalle: `Resend HTTP ${r.status}: ${cuerpo?.message ?? cuerpo?.name ?? ""}` };
  return { estado: "enviado", id: String(cuerpo?.id ?? "") };
}
