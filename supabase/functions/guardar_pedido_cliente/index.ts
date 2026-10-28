// guardar_pedido_cliente (CONTRATOS.md §3.16): guarda un pedido de cliente hecho
// con la lista. Valida cada referencia contra la hoja leída en ese momento.
// Recoger en tienda: espera al siguiente reparto. Nacex: tarea con «coge / haz»
// y Nacex activado ese día.

import { leerStock } from "../_compartido/google.ts";
import { guardarPedidoClienteDe } from "../_compartido/pedido_cliente.ts";
import { CORS, error, huella, quienLlama, responder, rpc } from "../_compartido/servidor.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const persona = await quienLlama(req, "guardar_pedido_cliente");
    if (!persona) return responder(error("NO_AUTENTICADO", "Tienes que iniciar sesión."), 401);
    const cuerpo = await req.json().catch(() => ({}));
    return responder(await guardarPedidoClienteDe({
      rpc, huella, leer: (documento, pestanas) => leerStock(Deno.env.get("GOOGLE_CUENTA_TECNICA"), documento, pestanas),
    }, persona, cuerpo));
  } catch (e) {
    console.error(e);
    return responder(error("ERROR_INTERNO", "Algo ha fallado en el servidor. Vuelve a intentarlo; si sigue, avisa a Administración."), 500);
  }
});
