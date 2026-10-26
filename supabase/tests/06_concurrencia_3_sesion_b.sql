-- Prueba 06 · Paso 3 de 4 (sesión B). Lanzada mientras A está dentro de su
-- transacción: debe esperar a A y devolver la MISMA jornada, sin error y sin
-- duplicar nada. Se lanza a la vez que A y espera 2 segundos para empezar
-- cuando A ya tiene la jornada a medio confirmar.
select pg_sleep(2);
select 'B' as sesion,
       motor.generar_jornada('00000000-0000-4000-a000-0000000000c1', '2026-11-10') as jornada_b,
       clock_timestamp() as terminada_a_las;
select count(*) as jornadas_del_dia,
       (select count(*) from public.tareas t join public.jornadas j on j.id = t.jornada_id
         where j.persona_id = '00000000-0000-4000-a000-0000000000c1') as tareas,
       (select count(*) from public.registro_eventos r join public.jornadas j on j.id = r.jornada_id
         where j.persona_id = '00000000-0000-4000-a000-0000000000c1' and r.tipo = 'jornada_generada') as generaciones
from public.jornadas where persona_id = '00000000-0000-4000-a000-0000000000c1' and fecha = '2026-11-10';
