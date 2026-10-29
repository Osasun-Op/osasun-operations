// Utilidades de las funciones del servidor: quién llama, llamadas a la base de
// datos con la clave interna del servidor y respuestas JSON (CONTRATOS.md §1).
// La clave interna solo existe aquí (variable del entorno de Supabase); nunca
// llega a las pantallas.

import { leerRespuesta } from "./respuesta.ts";

const URL_PROYECTO = Deno.env.get("SUPABASE_URL") ?? "";
const CLAVE_SERVIDOR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CLAVE_PUBLICA = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

export const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function responder(cuerpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8" },
  });
}

export const error = (codigo: string, mensaje: string, extra: Record<string, unknown> = {}) =>
  ({ error: { codigo, mensaje, ...extra } });

/** Llama a una función de la base de datos con la clave interna del servidor (una `void` devuelve `null`). */
export async function rpc<T = unknown>(nombre: string, args: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${URL_PROYECTO}/rest/v1/rpc/${nombre}`, {
    method: "POST",
    headers: {
      apikey: CLAVE_SERVIDOR,
      Authorization: `Bearer ${CLAVE_SERVIDOR}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  return await leerRespuesta<T>(nombre, r);
}

/**
 * Quién llama: la sesión del usuario (pantallas) o una solicitud interna de un
 * solo uso creada por la base de datos (pruebas y tareas programadas).
 */
export async function quienLlama(req: Request, funcion: string): Promise<string | null> {
  const solicitud = req.headers.get("x-solicitud");
  if (solicitud) {
    const persona = await rpc<string | null>("servidor_canjear_solicitud", { p_id: solicitud, p_funcion: funcion });
    return persona || null;
  }
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return null;
  const r = await fetch(`${URL_PROYECTO}/auth/v1/user`, { headers: { apikey: CLAVE_PUBLICA, Authorization: auth } });
  if (!r.ok) return null;
  const usuario = await r.json();
  return typeof usuario?.id === "string" ? usuario.id : null;
}

/** Huella del texto (para no duplicar un reparto pegado dos veces). */
export async function huella(tipo: string, texto: string): Promise<string> {
  const limpio = texto.split(/\r?\n/).map((l) => l.trim().replace(/\s+/g, " ")).filter((l) => l !== "").join("\n");
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${tipo}\n${limpio}`));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
