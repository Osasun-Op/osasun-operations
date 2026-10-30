-- Prueba 22 · Auditoría de solo lectura (Tarea 19, docs/AUDITORIA.md).
-- Nunca en producción: prepara casos raros (quita un índice y una restricción)
-- dentro de una transacción. En producción solo se ejecuta la auditoría.
-- En una base sana da «Sin avisos»; cada caso raro, preparado dentro de la
-- transacción, da su aviso; la huella es la de la prueba 00; solo la ejecutan
-- postgres y service_role. Transacción deshecha al final.

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.rechazada(p_sql text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
end;
$$;
create function pg_temp.tiene(p_aviso text) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements_text(motor.auditoria() -> 'avisos') a where a like p_aviso) $$;

-- La base de pruebas, sana: la última lectura de la hoja es correcta.
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values (now(), 'stock', true, '{}');

do $$
declare
  a jsonb := motor.auditoria();
begin
  perform pg_temp.comprobar('Base sana: «Sin avisos» y lista de avisos vacía',
    a ->> 'resumen' = 'Sin avisos' and a -> 'avisos' = '[]', a ->> 'avisos');
  perform pg_temp.comprobar('Trae todos los apartados',
    a ?& array['generado_en', 'resumen', 'avisos', 'migraciones', 'huella', 'tablas', 'funciones', 'triggers', 'cron',
               'configuracion', 'datos'], (select string_agg(k, ', ') from jsonb_object_keys(a) k));
  perform pg_temp.comprobar('La huella es la misma que la de la prueba 00',
    a -> 'huella' = (select jsonb_object_agg(apartado, huella) from motor.huella_estructura())
    and (select count(*) from jsonb_object_keys(a -> 'huella')) = 11, a ->> 'huella');
  perform pg_temp.comprobar('Tablas: todas las de public con RLS; datos: la última lectura correcta',
    not exists (select 1 from jsonb_array_elements(a -> 'tablas') t where t ->> 'tabla' not like 'motor.%' and not (t ->> 'rls')::boolean)
    and a -> 'datos' -> 'ultima_lectura_correcta' ->> 'motivo' = 'stock'
    and a -> 'configuracion' -> 'faltan' = '[]', a ->> 'datos');
  perform pg_temp.comprobar('Funciones: anon no ejecuta ninguna de public; ninguna servidor_* para authenticated',
    a -> 'funciones' -> 'public_anon' = '[]'
    and not exists (select 1 from jsonb_array_elements_text(a -> 'funciones' -> 'public_authenticated') f where f like 'servidor\_%'),
    a ->> 'funciones');
end;
$$;

-- Casos raros, uno a uno.
create table public.prueba_sin_rls (x int);
select pg_temp.comprobar('Tabla de public sin RLS → aviso',
  pg_temp.tiene('La tabla public.prueba_sin_rls no tiene RLS.'));
drop table public.prueba_sin_rls;

create function public.servidor_prueba_auditoria() returns void language sql as '';
grant execute on function public.servidor_prueba_auditoria() to authenticated;
select pg_temp.comprobar('Función servidor_* que puede ejecutar alguien que no es service_role → aviso',
  pg_temp.tiene('La función del servidor public.servidor_prueba_auditoria la puede ejecutar %authenticated%'));
drop function public.servidor_prueba_auditoria();

create function public.prueba_auditoria_anon() returns int language sql as 'select 1';
grant execute on function public.prueba_auditoria_anon() to anon;
select pg_temp.comprobar('Función de public ejecutable por anon → aviso',
  pg_temp.tiene('La función public.prueba_auditoria_anon la puede ejecutar anon (sin sesión).'));
drop function public.prueba_auditoria_anon();

do $$
declare
  v jsonb := (select valor from public.configuracion where clave = 'stock_objetivo_pct' and centro_id is null);
begin
  delete from public.configuracion where clave = 'stock_objetivo_pct' and centro_id is null;
  perform pg_temp.comprobar('Falta una clave de configuración → aviso y en «faltan»',
    pg_temp.tiene('Falta la clave de configuración stock_objetivo_pct.')
    and motor.auditoria() -> 'configuracion' -> 'faltan' = '["stock_objetivo_pct"]');
  insert into public.configuracion (clave, centro_id, valor) values ('stock_objetivo_pct', null, v);
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j1 uuid := motor.generar_jornada(op, '2026-12-14');
  j2 uuid := motor.generar_jornada(op, '2026-12-15');
begin
  update public.tareas set estado = 'en_curso', iniciada_en = now()
   where id in ((select id from public.tareas where jornada_id = j1 order by orden limit 1),
                (select id from public.tareas where jornada_id = j2 order by orden limit 1));
  perform pg_temp.comprobar('Más de una tarea en curso para la misma persona → aviso',
    pg_temp.tiene('La persona ' || op || ' tiene % tareas en curso a la vez.'));
  update public.tareas set estado = 'pendiente', iniciada_en = null where jornada_id in (j1, j2) and estado = 'en_curso';

  drop index public.repartos_uno_aceptado;
  insert into public.repartos (jornada_id, tipo, texto_original, huella, estado)
  values (j1, 'reparto', 'x', 'a', 'aceptado'), (j1, 'reparto', 'y', 'b', 'aceptado');
  perform pg_temp.comprobar('Más de un reparto aceptado en la misma jornada → aviso',
    pg_temp.tiene('La jornada del 14/12/2026 tiene 2 repartos aceptados.'));
  delete from public.repartos where jornada_id = j1;

  alter table public.tarea_elementos drop constraint tarea_elementos_tarea_id_fkey;
  insert into public.tarea_elementos (tarea_id, tipo, producto, formato, cantidad)
  values (gen_random_uuid(), 'referencia_produccion', 'BZ1', '4g', 1);
  perform pg_temp.comprobar('Elemento sin su tarea → aviso', pg_temp.tiene('Hay 1 elementos sin su tarea.'));
end;
$$;
delete from public.tarea_elementos e where not exists (select 1 from public.tareas t where t.id = e.tarea_id);

insert into public.lecturas_sheets (leido_en, motivo, correcto, error, datos)
values (now() + interval '1 minute', 'reparto', false, 'SHEETS_NO_DISPONIBLE: prueba', '{}');
select pg_temp.comprobar('Lectura con error más reciente que la última correcta → aviso y resumen «1 aviso»',
  pg_temp.tiene('La última lectura de la hoja (%) dio error: SHEETS_NO_DISPONIBLE: prueba')
  and motor.auditoria() ->> 'resumen' = '1 aviso', motor.auditoria() ->> 'avisos');

-- Reparto y envío aceptados hoy sin sus tareas (Tarea 20).
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada(op, motor.fecha_local(now()));
begin
  if j is null then  -- fin de semana: una jornada de hoy solo para la prueba
    insert into public.jornadas (persona_id, centro_id, fecha)
    select op, centro_id, motor.fecha_local(now()) from public.personas where id = op returning id into j;
  end if;
  insert into public.repartos (jornada_id, tipo, texto_original, huella, estado)
  select j, x.tipo, 'x', 'auditoria', 'aceptado' from (values ('reparto'), ('envio')) x(tipo)
   where not exists (select 1 from public.repartos r where r.jornada_id = j and r.tipo = x.tipo and r.estado = 'aceptado');
  update public.tareas set estado = 'cancelada'
   where jornada_id = j and clave in ('bolsas', 'preparar_envio', 'preparar_envio_viernes');
  perform pg_temp.comprobar('Reparto aceptado hoy sin su tarea de bolsas → aviso',
    pg_temp.tiene('El reparto aceptado hoy no tiene su tarea de producción o de bolsas.'));
  perform pg_temp.comprobar('Envío aceptado hoy sin su tarea de preparación → aviso',
    pg_temp.tiene('El envío aceptado hoy no tiene su tarea de preparación.'));
end;
$$;

-- Permisos.
set local role authenticated;
select pg_temp.comprobar('authenticated no puede ejecutar la auditoría ni la huella',
  pg_temp.rechazada('select motor.auditoria()') and pg_temp.rechazada('select * from motor.huella_estructura()'));
reset role;
set local role anon;
select pg_temp.comprobar('anon no puede ejecutar la auditoría', pg_temp.rechazada('select motor.auditoria()'));
reset role;
select pg_temp.comprobar('service_role sí puede ejecutarlas',
  has_function_privilege('service_role', 'motor.auditoria()', 'EXECUTE')
  and has_function_privilege('service_role', 'motor.huella_estructura()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.auditoria()', 'EXECUTE')
  and not has_function_privilege('anon', 'motor.huella_estructura()', 'EXECUTE'));
select pg_temp.comprobar('Solo lee: es stable',
  (select bool_and(provolatile = 's') from pg_proc where oid in ('motor.auditoria()'::regprocedure, 'motor.huella_estructura()'::regprocedure)));

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
