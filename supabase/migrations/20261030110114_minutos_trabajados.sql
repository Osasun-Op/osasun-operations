-- Tarea 21 (respuesta del propietario, 30/10/2026): los minutos trabajados de una
-- tarea de producción son todo el tiempo que está en marcha (producir cada
-- producto y el tiempo entre uno y otro), sin contar lo que estuvo interrumpida
-- por otra tarea (la salida y la ruta). Sirve para ver lo que dura la tarea con
-- las cajas que se hacen.
--
-- Cada tramo va de que la tarea pasa a en curso (`tarea_iniciada`, también al
-- retomarla) a lo primero que llegue: otra tarea entra (`tarea_pausada`), la
-- tarea se termina (`tarea_terminada` o `terminada_en`) o, si sigue en curso,
-- ahora. Solo se cambia esta función.
--
-- Deshacer: volver a crear motor.minutos_trabajados como en
-- 20261030105121_hoy_interrupciones.sql.

create or replace function motor.minutos_trabajados(p_tarea uuid, p_ahora timestamptz)
returns integer language sql stable set search_path = '' as $$
  with t as (select * from public.tareas where id = p_tarea),
  ev as (
    select r.tipo, (r.datos ->> 'a_las')::timestamptz as a_las
      from public.registro_eventos r
     where r.tarea_id = p_tarea and r.tipo in ('tarea_iniciada', 'tarea_pausada', 'tarea_terminada')
       and r.datos ? 'a_las'),
  tramos as (
    select i.a_las as desde,
           least((select min(e.a_las) from ev e where e.a_las > i.a_las),   -- pausa, fin u otro inicio
                 (select t.terminada_en from t where t.terminada_en >= i.a_las),
                 (select p_ahora from t where t.estado = 'en_curso')) as hasta
      from ev i where i.tipo = 'tarea_iniciada')
  select case when exists (select 1 from public.tarea_elementos e
                            where e.tarea_id = p_tarea and e.tipo = 'referencia_produccion')
              then coalesce(round(sum(extract(epoch from (hasta - desde))) / 60), 0)::int end
  from tramos
$$;
