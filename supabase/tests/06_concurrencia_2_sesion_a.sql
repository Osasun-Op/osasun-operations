-- Prueba 06 · Paso 2 de 4 (sesión A). Genera la jornada y retiene la
-- transacción 6 segundos antes de confirmarla.
begin;
select motor.generar_jornada('00000000-0000-4000-a000-0000000000c1', '2026-11-10') as jornada_a;
select pg_sleep(6);
commit;
select 'A' as sesion, id as jornada, (select count(*) from public.tareas t where t.jornada_id = j.id) as tareas
from public.jornadas j where persona_id = '00000000-0000-4000-a000-0000000000c1';
