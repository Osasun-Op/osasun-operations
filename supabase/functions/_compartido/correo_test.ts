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
  assertEquals(r, { estado: "enviado", id: "abc" });
  assertEquals(peticion!.url, "https://api.resend.com/emails");
  assertEquals((peticion!.init.headers as Record<string, string>).Authorization, "Bearer clave-de-prueba");
  assertEquals(JSON.parse(peticion!.init.body as string),
    { from: correo.remitente, to: [correo.destino], subject: "Prueba", text: "Hola" });
});

Deno.test("Correo: sin clave no se intenta enviar (rechazado)", async () => {
  const r = await enviarResend(undefined, correo, (() => { throw new Error("no debe llamar"); }) as unknown as typeof fetch);
  assertEquals(r.estado, "rechazado");
});

Deno.test("Correo: si Resend responde con un error, es «rechazado» (se puede reintentar)", async () => {
  const falso = (() => Promise.resolve(new Response(JSON.stringify({ message: "domain not verified" }), { status: 403 }))) as unknown as typeof fetch;
  assertEquals(await enviarResend("k", correo, falso), { estado: "rechazado", detalle: "Resend HTTP 403: domain not verified" });
  const caido = (() => Promise.resolve(new Response("", { status: 500 }))) as unknown as typeof fetch;
  assertEquals((await enviarResend("k", correo, caido)).estado, "rechazado");
});

Deno.test("Correo: sin respuesta a tiempo es «dudoso» (no se reintenta)", async () => {
  const lento = ((_url: string, init: RequestInit) =>
    new Promise<Response>((_res, rej) => init.signal!.addEventListener("abort", () => rej(new Error("tiempo agotado"))))
  ) as unknown as typeof fetch;
  const r = await enviarResend("k", correo, lento, 20);
  assertEquals(r.estado, "dudoso");
});
