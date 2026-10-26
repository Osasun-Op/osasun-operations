// lista_stock (CONTRATOS.md §3.9): lista de producción para el stock del almacén
// (R3, cola de tiempo libre A). Se calcula una vez por turno y se guarda en la
// tarea «Producción para el stock del almacén». Administración puede consultarla
// sin guardar nada.

import { leerStock, type Pestanas } from "../_compartido/google.ts";
import { calcularStock, type ConfigR3 } from "../_compartido/r3.ts";
import { CORS, error, quienLlama, responder, rpc } from "../_compartido/servidor.ts";

interface Contexto {
  error?: { codigo: string; mensaje: string };
  rol: string;
  jornada_id: string | null;
  turno: string;
  config: {
    sheets_documento_id: string;
    sheets_pestanas: Pestanas;
    stock_objetivo_pct: number;
    stock_excluidos: ConfigR3["excluidos"];
  };
  stock: Record<string, unknown> | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const persona = await quienLlama(req, "lista_stock");
    if (!persona) return responder(error("NO_AUTENTICADO", "Tienes que iniciar sesión."), 401);

    const ctx = await rpc<Contexto>("servidor_preparar", { p_persona: persona });
    if (ctx.error) return responder(ctx);
    if (ctx.rol === "operario" && ctx.stock) {
      return responder({ tarea: ctx.stock, ya_calculado: true, lote: ctx.turno });
    }

    const lectura = await leerStock(
      Deno.env.get("GOOGLE_CUENTA_TECNICA"), ctx.config.sheets_documento_id, ctx.config.sheets_pestanas,
    );
    const lecturaId = await rpc<string>("servidor_guardar_lectura", {
      p_persona: persona, p_motivo: "stock", p_correcto: lectura.ok,
      p_error: lectura.ok ? null : `${lectura.codigo}: ${lectura.detalle}`,
      p_datos: lectura.ok ? lectura.datos : {},
    });
    if (!lectura.ok) {
      return responder(error(lectura.codigo, lectura.codigo === "SHEETS_NO_DISPONIBLE"
        ? "No puedo leer el stock ahora: la lista de stock no está disponible. El resto de tareas sigue igual."
        : "La hoja de stock ha cambiado de forma: no hay lista de stock. Avisa a Administración.", { detalle: lectura.detalle }));
    }

    const r = calcularStock(lectura.datos, {
      porcentaje: Number(ctx.config.stock_objetivo_pct ?? 35),
      excluidos: ctx.config.stock_excluidos ?? [],
    });
    const leidoEn = new Date().toISOString();

    if (ctx.rol !== "operario") {
      return responder({ lista: r.lista, faltas: r.faltas, avisos: r.avisos, excluidos: r.excluidos, datos_leidos_en: leidoEn });
    }
    const guardado = await rpc<Record<string, unknown>>("servidor_guardar_stock", {
      p_persona: persona, p_jornada: ctx.jornada_id, p_lote: ctx.turno, p_lectura: lecturaId,
      p_lista: r.lista, p_faltas: r.faltas,
    });
    if (guardado.error) return responder(guardado);
    return responder({ ...guardado, lote: ctx.turno, faltas: r.faltas, avisos: r.avisos, excluidos: r.excluidos, datos_leidos_en: leidoEn });
  } catch (e) {
    console.error(e);
    return responder(error("ERROR_INTERNO", "Algo ha fallado en el servidor. Vuelve a intentarlo; si sigue, avisa a Administración."), 500);
  }
});
