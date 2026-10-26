-- Tarea 2 · Generación programada de la jornada a las 06:00 de Madrid.
-- pg_cron trabaja en UTC: se lanza a las 04:00 y a las 05:00 UTC y la función
-- solo actúa en la ejecución que cae a las 06:00 en Madrid (verano o invierno).
-- La generación es idempotente: si el operario abre la app antes, no se duplica.

create extension if not exists pg_cron;

select cron.schedule(
  'generar_jornada_diaria',
  '0 4,5 * * *',
  $$select motor.generar_jornadas_programadas(now())$$
);
