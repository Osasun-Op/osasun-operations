// Respuesta de PostgREST a una llamada a una función de la base de datos (Tarea 18).
// Código puro, para probarlo con respuestas de verdad (respuesta_test.ts).

/**
 * El valor que devuelve la función. Una función que no devuelve nada (`void`)
 * responde sin cuerpo (vacío o 204): entonces es `null`, no un error.
 */
export async function leerRespuesta<T = unknown>(nombre: string, r: Response): Promise<T> {
  const cuerpo = await r.text();
  if (!r.ok) throw new Error(`Base de datos: ${nombre} → HTTP ${r.status} ${cuerpo}`);
  return (cuerpo.trim() === "" ? null : JSON.parse(cuerpo)) as T;
}
