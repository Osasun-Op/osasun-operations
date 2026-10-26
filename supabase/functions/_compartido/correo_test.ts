import { assertEquals } from "jsr:@std/assert@1";
import { enviarResend } from "./correo.ts";

const correo = { remitente: "Osasun <onboarding@resend.dev>", destino: "admin@osasun.invalid", asunto: "Prueba", texto: "Hola" };

Deno.test("Correo: envía a Resend con la clave y los datos", async () => {
  let peticion: { url: string; init: RequestInit } | null = null;
  const falso = ((url: string, init: RequestInit) => {
    peticion = { url, init };
    return Promise.resolve(new Response(JSON.stringify({ id: "abc" }), { status: 200 }));
  }) as unknown as typeof fetch;
  const r = await enviarResend("clave-de-prueba", correo, falso);
  assertEquals(r, { ok: true, id: "abc" });
  assertEquals(peticion!.url, "https://api.resend.com/emails");
  assertEquals((peticion!.init.headers as Record<string, string>).Authorization, "Bearer clave-de-prueba");
  assertEquals(JSON.parse(peticion!.init.body as string),
    { from: correo.remitente, to: [correo.destino], subject: "Prueba", text: "Hola" });
});

Deno.test("Correo: sin clave no se intenta enviar", async () => {
  const r = await enviarResend(undefined, correo, (() => { throw new Error("no debe llamar"); }) as unknown as typeof fetch);
  assertEquals(r.ok, false);
});

Deno.test("Correo: un rechazo de Resend se devuelve como fallo", async () => {
  const falso = (() => Promise.resolve(new Response(JSON.stringify({ message: "domain not verified" }), { status: 403 }))) as unknown as typeof fetch;
  const r = await enviarResend("k", correo, falso);
  assertEquals(r, { ok: false, detalle: "Resend HTTP 403: domain not verified" });
});
