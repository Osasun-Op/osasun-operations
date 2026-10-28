// guardar_reparto (CONTRATOS.md §3.14): guarda el reparto (o el envío) preparado
// con la lista. Valida cada referencia contra la hoja leída en ese momento y
// hace el mismo cálculo y la misma sustitución que pegar el texto (R1).
// Devuelve también el texto para WhatsApp.

import { leerStock } from "../_compartido/google.ts";
import { guardarRepartoDe } from "../_compartido/reparto_lista.ts";
import { CORS, error, huella, quienLlama, responder, rpc } from "../_compartido/servidor.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const persona = await quienLlama(req, "guardar_reparto");
    if (!persona) return responder(error("NO_AUTENTICADO", "Tienes que iniciar sesión."), 401);
    const cuerpo = await req.json().catch(() => ({}));
    return responder(await guardarRepartoDe({
      rpc, huella, leer: (documento, pestanas) => leerStock(Deno.env.get("GOOGLE_CUENTA_TECNICA"), documento, pestanas),
    }, persona, cuerpo));
  } catch (e) {
    console.error(e);
    return responder(error("ERROR_INTERNO", "Algo ha fallado en el servidor. Vuelve a intentarlo; si sigue, avisa a Administración."), 500);
  }
});
