// leerRespuesta (lo que usa `rpc`) con respuestas HTTP de verdad (Tarea 18). Las pruebas de las funciones del
// servidor usan una base de datos simulada que devuelve `null` para las funciones
// `void`, así que nunca pasaban por `r.json()` con un cuerpo vacío: por eso no se
// vio que `guardar_reparto` daba 500 después de guardar. Aquí se prueba con
// respuestas (`Response`) tal como llegan de PostgREST.
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { leerRespuesta } from "./respuesta.ts";

Deno.test("rpc/leerRespuesta: una función void responde sin cuerpo (204) → null, sin error", async () => {
  assertEquals(await leerRespuesta("servidor_reparto_anotar_id_cliente", new Response(null, { status: 204 })), null);
});

Deno.test("rpc/leerRespuesta: 200 con el cuerpo vacío (o solo espacios) → null", async () => {
  assertEquals(await leerRespuesta("servidor_guardar_cobertura", new Response("", { status: 200 })), null);
  assertEquals(await leerRespuesta("servidor_anotar_sale", new Response(" \n", { status: 200 })), null);
});

Deno.test("rpc/leerRespuesta: JSON de siempre (objeto, texto, null)", async () => {
  assertEquals(await leerRespuesta("servidor_preparar", new Response('{"rol":"operario"}')), { rol: "operario" });
  assertEquals(await leerRespuesta("servidor_guardar_lectura", new Response('"6b1f7a3e"')), "6b1f7a3e");
  assertEquals(await leerRespuesta("servidor_reparto_por_id_cliente", new Response("null")), null);
});

Deno.test("rpc/leerRespuesta: un error de la base de datos sigue siendo un error (con su cuerpo)", async () => {
  await assertRejects(
    () => leerRespuesta("servidor_preparar", new Response('{"message":"x"}', { status: 400 })),
    Error, "HTTP 400 {\"message\":\"x\"}",
  );
});
