// Lectura de la hoja con una Google simulada: sin red real.
// R1-11 / R3-16 hoja no disponible; R3-15 pestaña renombrada; alcance de solo lectura.
import { assertEquals } from "jsr:@std/assert@1";
import { ALCANCE, leerStock } from "./google.ts";
import { ALMACEN, CONTEO, PRINCIPAL } from "./hoja_test.ts";

const PESTANAS = { principal: "PRINCIPAL", conteo: "CONTEO DE CAJAS TOTAL", almacen: "ALMACEN" };

async function claveDePrueba(): Promise<string> {
  const par = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", par.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  return JSON.stringify({ client_email: "lector@prueba.invalid", private_key: pem, token_uri: "https://token.invalid/token" });
}

function googleSimulada(opciones: { sheets?: number; caida?: boolean }) {
  const llamadas: string[] = [];
  let alcance = "";
  const f = (async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada);
    llamadas.push(url);
    if (opciones.caida) throw new TypeError("network error");
    if (url.startsWith("https://token.invalid")) {
      const jwt = new URLSearchParams(String(init?.body)).get("assertion")!;
      alcance = JSON.parse(atob(jwt.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).scope;
      return new Response(JSON.stringify({ access_token: "t" }));
    }
    const estado = opciones.sheets ?? 200;
    if (estado !== 200) return new Response("{}", { status: estado });
    return new Response(JSON.stringify({ valueRanges: [{ values: PRINCIPAL }, { values: CONTEO }, { values: ALMACEN }] }));
  }) as typeof fetch;
  return { f, llamadas, alcance: () => alcance };
}

Deno.test("Lectura correcta con alcance de solo lectura", async () => {
  const g = googleSimulada({});
  const r = await leerStock(await claveDePrueba(), "doc", PESTANAS, g.f);
  assertEquals(r.ok, true);
  assertEquals(g.alcance(), "https://www.googleapis.com/auth/spreadsheets.readonly");
  assertEquals(ALCANCE.endsWith(".readonly"), true);
  assertEquals(g.llamadas.every((u) => !u.includes(":batchUpdate") && !u.includes("values:append")), true);
});

Deno.test("R1-11 / R3-16 hoja no disponible: se reintenta una vez y no se calcula nada", async () => {
  const g = googleSimulada({ caida: true });
  const r = await leerStock(await claveDePrueba(), "doc", PESTANAS, g.f);
  assertEquals([r.ok, !r.ok && r.codigo], [false, "SHEETS_NO_DISPONIBLE"]);
  assertEquals(g.llamadas.length, 2);
});

Deno.test("Google responde con error de permiso: no disponible", async () => {
  const r = await leerStock(await claveDePrueba(), "doc", PESTANAS, googleSimulada({ sheets: 403 }).f);
  assertEquals(!r.ok && r.codigo, "SHEETS_NO_DISPONIBLE");
});

Deno.test("R3-15 pestaña renombrada (Google responde 400): estructura cambiada", async () => {
  const r = await leerStock(await claveDePrueba(), "doc", PESTANAS, googleSimulada({ sheets: 400 }).f);
  assertEquals(!r.ok && r.codigo, "ESTRUCTURA_SHEETS_CAMBIADA");
});

Deno.test("Sin clave de la cuenta técnica: no disponible, sin llamar a Google", async () => {
  const g = googleSimulada({});
  const r = await leerStock(undefined, "doc", PESTANAS, g.f);
  assertEquals([!r.ok && r.codigo, g.llamadas.length], ["SHEETS_NO_DISPONIBLE", 0]);
});
