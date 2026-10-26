-- Prueba 04 · Permisos (criterio «Permisos», §13)
-- El operario no ve la jornada de otra persona, no escribe directamente en
-- ninguna tabla y no puede usar funciones internas ni de Administración.
-- Se simula cada usuario con el rol «authenticated» y su identificador, como
-- hace Supabase con la sesión.

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;

-- Ejecuta una sentencia y dice si la base de datos la rechaza por falta de permisos.
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
  perform set_config('request.jwt.claims',
                     coalesce(jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, ''), true);
  execute 'set local role authenticated';
end;
$$;

-- Otro operario (ficticio) con su jornada, solo dentro de esta prueba.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000003', 'authenticated',
        'authenticated', 'otro.operario@osasun.invalid', '{}', '{}', now(), now());
insert into public.personas (id, nombre, rol, centro_id)
select '00000000-0000-4000-a000-000000000003', 'Otro operario', 'operario', id from public.centros_trabajo where codigo = 'ALMACEN';
insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
values ('00000000-0000-4000-a000-000000000003', 1, 'manana', '08:30', '13:00');
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-11-02');
select motor.generar_jornada('00000000-0000-4000-a000-000000000003', '2026-11-02');

create temp table _ids on commit drop as
  select t.id as tarea_otro from public.tareas t join public.jornadas j on j.id = t.jornada_id
  where j.persona_id = '00000000-0000-4000-a000-000000000003' limit 1;
grant select on _ids to authenticated, anon;

-- OPERARIO ------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb;
  v_otro uuid := (select tarea_otro from _ids);
begin
  perform pg_temp.comprobar('Operario: solo ve su jornada',
    (select count(*) from public.jornadas) = 1
    and (select count(*) from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000003') = 0);
  perform pg_temp.comprobar('Operario: no ve las tareas de otra persona',
    (select count(*) from public.tareas where id = v_otro) = 0
    and (select count(*) from public.tareas) > 0);
  perform pg_temp.comprobar('Operario: solo ve su propia ficha de persona',
    (select count(*) from public.personas) = 1);
  perform pg_temp.comprobar('Operario: no ve el registro de eventos (es de Administración)',
    (select count(*) from public.registro_eventos) = 0);

  perform pg_temp.comprobar('Operario: no puede insertar tareas directamente',
    pg_temp.rechazada($q$insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde)
                        select id, 'x', 'plantilla', 'x', now() from public.jornadas limit 1$q$));
  perform pg_temp.comprobar('Operario: no puede modificar tareas directamente',
    pg_temp.rechazada($q$update public.tareas set estado = 'hecha'$q$));
  perform pg_temp.comprobar('Operario: no puede borrar jornadas',
    pg_temp.rechazada($q$delete from public.jornadas$q$));
  perform pg_temp.comprobar('Operario: no puede crear jornadas',
    pg_temp.rechazada($q$insert into public.jornadas (persona_id, centro_id, fecha)
                        select id, centro_id, '2026-12-01' from public.personas$q$));
  perform pg_temp.comprobar('Operario: no puede escribir en el registro de eventos',
    pg_temp.rechazada($q$insert into public.registro_eventos (tipo) values ('x')$q$));
  perform pg_temp.comprobar('Operario: no puede cambiar plantillas, horarios, configuración ni personas',
    pg_temp.rechazada($q$update public.plantillas_tarea set obligatoria = false$q$)
    and pg_temp.rechazada($q$update public.horarios set hora_inicio = '09:00'$q$)
    and pg_temp.rechazada($q$insert into public.configuracion (clave, valor) values ('x', '1')$q$)
    and pg_temp.rechazada($q$update public.personas set rol = 'administracion'$q$)
    and pg_temp.rechazada($q$update public.centros_trabajo set activo = false$q$));
  perform pg_temp.comprobar('Operario: no puede usar las funciones internas del motor',
    pg_temp.rechazada($q$select motor.generar_jornada(auth.uid(), '2026-12-01')$q$)
    and pg_temp.rechazada($q$select motor.iniciar_tarea_de(auth.uid(), gen_random_uuid(), now())$q$)
    and pg_temp.rechazada($q$select motor.fijar_sale(gen_random_uuid(), 'operario')$q$));
  perform pg_temp.comprobar('Operario: no puede usar la función de pruebas',
    pg_temp.rechazada($q$select prueba.fijar_condicion(gen_random_uuid(), 'sale', 'operario')$q$));

  r := public.iniciar_tarea(v_otro);
  perform pg_temp.comprobar('Operario: no puede iniciar una tarea de otra persona (NO_ENCONTRADO)',
    r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  r := public.anotar_motivo(v_otro, 'x');
  perform pg_temp.comprobar('Operario: no puede anotar en una tarea de otra persona (NO_ENCONTRADO)',
    r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  r := public.mi_perfil();
  perform pg_temp.comprobar('Operario: mi_perfil devuelve su rol y el teléfono de Administración',
    r ->> 'rol' = 'operario' and r ->> 'telefono_administracion' = '+34 600 000 000', r::text);
  r := public.tarea_activa();
  perform pg_temp.comprobar('Operario: puede pedir su tarea activa', not r ? 'error' and r ? 'jornada', r::text);
end;
$$;
reset role;

-- ADMINISTRACIÓN --------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb;
begin
  perform pg_temp.comprobar('Administración: ve las jornadas de todos',
    (select count(*) from public.jornadas where fecha = '2026-11-02') = 2);
  perform pg_temp.comprobar('Administración: ve el registro de eventos',
    (select count(*) from public.registro_eventos) > 0);
  perform pg_temp.comprobar('Administración: tampoco escribe directamente en las tablas',
    pg_temp.rechazada($q$update public.tareas set estado = 'hecha'$q$));
  r := public.tarea_activa();
  perform pg_temp.comprobar('Administración: tarea_activa es solo del operario (NO_AUTORIZADO)',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text);
end;
$$;
reset role;

-- USUARIO SIN FICHA DE PERSONA -----------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-0000000000ff');
do $$
declare
  r jsonb := public.tarea_activa();
begin
  perform pg_temp.comprobar('Usuario autenticado sin ficha: NO_AUTORIZADO y no ve nada',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO' and (select count(*) from public.tareas) = 0, r::text);
end;
$$;
reset role;

-- SIN SESIÓN (anon) -------------------------------------------------------------
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión: no puede usar ninguna función de la API',
    pg_temp.rechazada($q$select public.tarea_activa()$q$)
    and pg_temp.rechazada($q$select public.mi_perfil()$q$));
  perform pg_temp.comprobar('Sin sesión: no puede leer ninguna tabla',
    pg_temp.rechazada($q$select count(*) from public.tareas$q$)
    and pg_temp.rechazada($q$select count(*) from public.personas$q$));
end;
$$;
reset role;

-- La función de pruebas no funciona fuera del entorno de pruebas -------------
do $$
begin
  update public.configuracion set valor = '"produccion"' where clave = 'entorno' and centro_id is null;
  begin
    perform prueba.fijar_condicion(gen_random_uuid(), 'sale', 'operario');
    perform pg_temp.comprobar('La función de pruebas se niega fuera del entorno de pruebas', false, 'no se negó');
  exception when raise_exception then
    perform pg_temp.comprobar('La función de pruebas se niega fuera del entorno de pruebas', true);
  end;
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
