-- Prueba 11 · Permisos de la Tarea 4
-- El operario no ve cierres ni puede usar las funciones de Administración; ve
-- sus problemas, incidencias y eventos, no los de otra persona. Administración
-- ve todo, resuelve problemas y consulta cierres, pero no usa los botones del
-- operario. Nadie escribe directamente ni usa las funciones del servidor.

begin;
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;
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
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;

-- Datos: el operario de pruebas y otro operario, cada uno con un problema, una
-- incidencia y un evento el martes 10/11/2026; y el cierre de la mañana del primero.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000003', 'authenticated',
        'authenticated', 'otro.operario@osasun.invalid', '{}', '{}', now(), now()),
       ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000004', 'authenticated',
        'authenticated', 'sin.ficha@osasun.invalid', '{}', '{}', now(), now());
insert into public.personas (id, nombre, rol, centro_id)
select '00000000-0000-4000-a000-000000000003', 'Otro operario', 'operario', id from public.centros_trabajo where codigo = 'ALMACEN';
insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
values ('00000000-0000-4000-a000-000000000003', 2, 'manana', '08:30', '13:00');

-- Las jornadas, en una sentencia aparte (la siguiente tiene que ver sus tareas).
select motor.generar_jornada(p, '2026-11-10')
from unnest(array['00000000-0000-4000-a000-000000000001', '00000000-0000-4000-a000-000000000003']::uuid[]) p;
create temp table _ids on commit drop as
select p.persona,
       (select id from public.jornadas where persona_id = p.persona and fecha = '2026-11-10') as jornada,
       (motor.abrir_problema_de(p.persona, gen_random_uuid(),
          (select t.id from public.tareas t join public.jornadas j on j.id = t.jornada_id
            where j.persona_id = p.persona and j.fecha = '2026-11-10' and t.clave = 'pegar_reparto'),
          'otro', 'Problema de prueba', '2026-11-10 08:50+01') -> 'problema' ->> 'id')::uuid as problema,
       (motor.iniciar_incidencia_de(p.persona, gen_random_uuid(), 'Incidencia de prueba', '2026-11-10 09:00+01')
          ->> 'incidencia_id')::uuid as incidencia,
       (motor.registrar_evento_de(p.persona, gen_random_uuid(), 'no_quedan_vapers', null, '2026-11-10 09:10+01')
          ->> 'evento_id')::uuid as evento
from (values ('00000000-0000-4000-a000-000000000001'::uuid), ('00000000-0000-4000-a000-000000000003'::uuid)) p(persona);
create temp table _cierre on commit drop as
select motor.generar_cierre(jornada, 'manana', '2026-11-10 13:00+01') as id from _ids
 where persona = '00000000-0000-4000-a000-000000000001';
grant select on _ids, _cierre to authenticated, anon;

-- OPERARIO ------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  otro constant uuid := '00000000-0000-4000-a000-000000000003';
  r jsonb;
begin
  perform pg_temp.comprobar('Operario: no ve los cierres (son de Administración)',
    (select count(*) from public.cierres) = 0);
  perform pg_temp.comprobar('Operario: ve su problema, su incidencia y su evento, no los de otra persona',
    (select count(*) from public.problemas where id in (select problema from _ids)) = 1
    and (select count(*) from public.incidencias where id in (select incidencia from _ids)) = 1
    and (select count(*) from public.eventos_jornada where id in (select evento from _ids)) = 1
    and (select count(*) from public.problemas where persona_id = otro) = 0);
  perform pg_temp.comprobar('Operario: no puede usar las funciones de Administración (NO_AUTORIZADO)',
    public.crear_tarea_admin(gen_random_uuid(), 'x', '{"tipo": "hoy"}', 10) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.cancelar_tarea(gen_random_uuid(), 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.estado_actual() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.cierre((select id from _cierre)) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.cierres_recientes(5) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
  perform pg_temp.comprobar('Operario: no escribe directamente en problemas, incidencias, eventos ni cierres',
    pg_temp.rechazada($q$insert into public.problemas (jornada_id, tarea_id, persona_id, tipo, descripcion, abierto_en)
                        select jornada, (select id from public.tareas limit 1), persona, 'otro', 'x', now() from _ids limit 1$q$)
    and pg_temp.rechazada($q$update public.incidencias set terminada_en = now()$q$)
    and pg_temp.rechazada($q$delete from public.eventos_jornada$q$)
    and pg_temp.rechazada($q$update public.cierres set enviado_en = now()$q$));
  perform pg_temp.comprobar('Operario: no puede usar las funciones del correo ni las internas del motor',
    pg_temp.rechazada($q$select public.servidor_correo_reclamar('cierre', (select id::text from _cierre))$q$)
    and pg_temp.rechazada($q$select public.servidor_correo_resultado('cierre', (select id::text from _cierre), true, 'x')$q$)
    and pg_temp.rechazada($q$select motor.generar_cierre((select jornada from _ids limit 1), 'tarde', now())$q$)
    and pg_temp.rechazada($q$select motor.crear_tarea_admin_de(auth.uid(), gen_random_uuid(), 'x', null, '{"tipo": "hoy"}', 10,
                                 false, null, true, null, now())$q$)
    and pg_temp.rechazada($q$select motor.encolar_correo('cierre', 'x')$q$));
  r := public.resolver_problema((select problema from _ids where persona = otro), 'x');
  perform pg_temp.comprobar('Operario: no puede resolver, llamar ni cerrar lo de otra persona (NO_ENCONTRADO)',
    r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO'
    and public.problema_llamada((select problema from _ids where persona = otro), false) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO'
    and public.terminar_incidencia((select incidencia from _ids where persona = otro)) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
end;
$$;
reset role;

-- ADMINISTRACIÓN --------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  otro constant uuid := '00000000-0000-4000-a000-000000000003';
  r jsonb;
begin
  perform pg_temp.comprobar('Administración: ve los cierres, problemas, incidencias y eventos de todos',
    (select count(*) from public.cierres where id = (select id from _cierre)) = 1
    and (select count(*) from public.problemas where id in (select problema from _ids)) = 2
    and (select count(*) from public.incidencias where id in (select incidencia from _ids)) = 2
    and (select count(*) from public.eventos_jornada where id in (select evento from _ids)) = 2);
  perform pg_temp.comprobar('Administración: los botones del operario no son suyos (NO_AUTORIZADO)',
    public.abrir_problema(gen_random_uuid(), gen_random_uuid(), 'otro', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.problema_llamada((select problema from _ids where persona = otro), false) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.iniciar_incidencia(gen_random_uuid(), 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.terminar_incidencia(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.retrasar_salida(gen_random_uuid(), 15) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
  r := public.cierre((select id from _cierre));
  perform pg_temp.comprobar('Administración: consulta el cierre (contenido y texto) y los cierres recientes',
    r ->> 'turno' = 'manana' and r -> 'contenido' ? 'hecho' and r ->> 'texto' like 'Cierre del turno de mañana%'
    and public.cierres_recientes(5) -> 'cierres' @> jsonb_build_array(jsonb_build_object('id', (select id from _cierre)))
    and public.cierre(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  perform pg_temp.comprobar('Administración: estado_actual responde',
    public.estado_actual() ? 'operario' and not public.estado_actual() ? 'error');
  r := public.resolver_problema((select problema from _ids where persona = otro), 'Resuelto desde Administración');
  perform pg_temp.comprobar('Administración: resuelve el problema de cualquier operario',
    r -> 'problema' ->> 'estado' = 'resuelto', r::text);
  perform pg_temp.comprobar('Administración: tampoco escribe directamente ni usa las funciones del correo',
    pg_temp.rechazada($q$update public.cierres set enviado_en = now()$q$)
    and pg_temp.rechazada($q$select public.servidor_correo_reclamar('cierre', (select id::text from _cierre))$q$));
end;
$$;
reset role;

-- USUARIO SIN FICHA -----------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000004');
do $$
begin
  perform pg_temp.comprobar('Usuario sin ficha: NO_AUTORIZADO y no ve cierres ni problemas',
    public.estado_actual() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.resolver_problema(gen_random_uuid(), 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and (select count(*) from public.cierres) = 0 and (select count(*) from public.problemas) = 0);
end;
$$;
reset role;

-- SIN SESIÓN ----------------------------------------------------------------------
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión: ni tablas ni funciones de la Tarea 4',
    pg_temp.rechazada($q$select count(*) from public.cierres$q$)
    and pg_temp.rechazada($q$select count(*) from public.problemas$q$)
    and pg_temp.rechazada($q$select public.estado_actual()$q$)
    and pg_temp.rechazada($q$select public.abrir_problema(gen_random_uuid(), gen_random_uuid(), 'otro', 'x')$q$)
    and pg_temp.rechazada($q$select public.crear_tarea_admin(gen_random_uuid(), 'x', '{"tipo": "hoy"}', 10)$q$)
    and pg_temp.rechazada($q$select public.servidor_correo_reclamar('cierre', 'x')$q$));
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
