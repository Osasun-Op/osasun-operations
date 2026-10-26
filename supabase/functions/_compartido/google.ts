// Lectura de STOCK OSASUN-CLAUDE con la cuenta técnica (solo lectura).
// Alcance único: spreadsheets.readonly. Nunca escribe en la hoja.
// La clave de la cuenta llega como secreto del entorno (GOOGLE_CUENTA_TECNICA).

import { type DatosHoja, ErrorEstructura, leerHoja } from "./hoja.ts";

export const ALCANCE = "https://www.googleapis.com/auth/spreadsheets.readonly";
const ESPERA_MS = 10_000;

export interface Pestanas {
  principal: string;
  conteo: string;
  almacen: string;
}

export type ResultadoLectura =
  | { ok: true; datos: DatosHoja }
  | { ok: false; codigo: "SHEETS_NO_DISPONIBLE" | "ESTRUCTURA_SHEETS_CAMBIADA"; detalle: string };

type Fetch = typeof fetch;

const base64url = (datos: Uint8Array | string) => {
  const bytes = typeof datos === "string" ? new TextEncoder().encode(datos) : datos;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function firmar(clavePem: string, contenido: string): Promise<string> {
  const der = Uint8Array.from(
    atob(clavePem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")),
    (c) => c.charCodeAt(0),
  );
  const clave = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const firma = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", clave, new TextEncoder().encode(contenido));
  return base64url(new Uint8Array(firma));
}

async function conEspera(f: Fetch, url: string, init: RequestInit): Promise<Response> {
  const control = new AbortController();
  const temporizador = setTimeout(() => control.abort(), ESPERA_MS);
  try {
    return await f(url, { ...init, signal: control.signal });
  } finally {
    clearTimeout(temporizador);
  }
}

async function token(cuenta: { client_email: string; private_key: string; token_uri?: string }, f: Fetch) {
  const ahora = Math.floor(Date.now() / 1000);
  const aud = cuenta.token_uri ?? "https://oauth2.googleapis.com/token";
  const sinFirma = `${base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${
    base64url(JSON.stringify({ iss: cuenta.client_email, scope: ALCANCE, aud, iat: ahora, exp: ahora + 3600 }))
  }`;
  const jwt = `${sinFirma}.${await firmar(cuenta.private_key, sinFirma)}`;
  const r = await conEspera(f, aud, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!r.ok) throw new Error(`Google no da acceso a la cuenta técnica (HTTP ${r.status}).`);
  return (await r.json()).access_token as string;
}

async function intentar(claveJson: string, documento: string, p: Pestanas, f: Fetch): Promise<string[][][]> {
  const acceso = await token(JSON.parse(claveJson), f);
  const rangos = [p.principal, p.conteo, p.almacen].map((n) => `'${n.replace(/'/g, "''")}'!A1:Z500`);
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${encodeURIComponent(documento)}/values:batchGet?` +
    rangos.map((r) => `ranges=${encodeURIComponent(r)}`).join("&") + "&valueRenderOption=FORMATTED_VALUE";
  const r = await conEspera(f, url, { headers: { Authorization: `Bearer ${acceso}` } });
  if (r.status === 400) throw new ErrorEstructura("Google no encuentra alguna pestaña: ¿se ha cambiado el nombre?");
  if (!r.ok) throw new Error(`Google Sheets responde HTTP ${r.status}.`);
  const cuerpo = await r.json();
  return (cuerpo.valueRanges ?? []).map((v: { values?: string[][] }) => v.values ?? []);
}

/** Lee e interpreta la hoja. Espera 10 s como máximo y reintenta una vez. */
export async function leerStock(
  claveJson: string | undefined,
  documento: string,
  pestanas: Pestanas,
  f: Fetch = fetch,
): Promise<ResultadoLectura> {
  if (!claveJson) return { ok: false, codigo: "SHEETS_NO_DISPONIBLE", detalle: "Falta la clave de la cuenta técnica." };
  let ultimo = "";
  for (let intento = 1; intento <= 2; intento++) {
    try {
      const [principal, conteo, almacen] = await intentar(claveJson, documento, pestanas, f);
      return { ok: true, datos: leerHoja(principal ?? [], conteo ?? [], almacen ?? []) };
    } catch (e) {
      if (e instanceof ErrorEstructura) return { ok: false, codigo: "ESTRUCTURA_SHEETS_CAMBIADA", detalle: e.message };
      ultimo = e instanceof Error ? e.message : String(e);
    }
  }
  return { ok: false, codigo: "SHEETS_NO_DISPONIBLE", detalle: ultimo };
}
