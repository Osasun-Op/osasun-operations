// catalogo (CONTRATOS.md §3.13): las tiendas y los productos de PRINCIPAL, con
// su categoría, para preparar el reparto con una lista. Lee la hoja en solo
// lectura. Para el operario y para Administración.

import { leerStock } from "../_compartido/google.ts";
import { catalogoDe } from "../_compartido/reparto_lista.ts";
import { CORS, error, huella, quienLlama, responder, rpc } from "../_compartido/servidor.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const persona = await quienLlama(req, "catalogo");
    if (!persona) return responder(error("NO_AUTENTICADO", "Tienes que iniciar sesión."), 401);
    return responder(await catalogoDe({
      rpc, huella, leer: (documento, pestanas) => leerStock(Deno.env.get("GOOGLE_CUENTA_TECNICA"), documento, pestanas),
    }, persona));
  } catch (e) {
    console.error(e);
    return responder(error("ERROR_INTERNO", "Algo ha fallado en el servidor. Vuelve a intentarlo; si sigue, avisa a Administración."), 500);
  }
});
