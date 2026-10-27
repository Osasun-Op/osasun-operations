-- Prueba 12 · Acceso solo para las cuentas autorizadas (Tarea 5)
-- El hook de Supabase Auth deja crear el usuario de una cuenta de la lista y
-- rechaza el resto; al crearse, la persona se da de alta con su rol, centro y
-- horario; una cuenta que entrase sin estar en la lista no tiene ficha y no
-- puede usar nada. La lista de la prueba es ficticia (@osasun.invalid) y
-- sustituye, dentro de la transacción, a la real del entorno.

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
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.usuario(p_id uuid, p_correo text)
returns void language sql as $$
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_correo,
          '{"provider": "google", "providers": ["google"]}', '{}', now(), now())
$$;

insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "Operaria.Nueva@osasun.invalid", "nombre": "Operaria nueva", "rol": "operario", "centro": "ALMACEN",
   "por_defecto": true,
   "horario": [{"dias": [1, 2, 3, 4, 5], "turno": "manana", "inicio": "08:30", "fin": "13:00"},
               {"dias": [1, 2, 3, 4], "turno": "tarde", "inicio": "15:30", "fin": "18:30"}]},
  {"correo": "jefa@osasun.invalid", "nombre": "Jefa", "rol": "administracion"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
update public.configuracion set clave = 'operario_por_defecto_real' where clave = 'operario_por_defecto' and centro_id is null;

do $$
declare
  r jsonb;
  v_j uuid;
  v_n integer;
  v_n2 integer;
begin
  r := public.hook_antes_de_crear_usuario('{"user": {"email": "operaria.nueva@OSASUN.invalid"}}');
  perform pg_temp.comprobar('Hook: una cuenta de la lista (sin importar mayúsculas) puede crear su usuario',
    r = '{}'::jsonb, r::text);
  r := public.hook_antes_de_crear_usuario('{"user": {"email": "desconocido@osasun.invalid"}}');
  perform pg_temp.comprobar('Hook: una cuenta fuera de la lista no crea usuario (error 403 con mensaje)',
    (r -> 'error' ->> 'http_code')::int = 403
    and r -> 'error' ->> 'message' = 'Esta cuenta no tiene acceso a Osasun Operations. Pide acceso a Administración.', r::text);
  r := public.hook_antes_de_crear_usuario('{"user": {"phone": "+34600000000"}}');
  perform pg_temp.comprobar('Hook: sin correo (teléfono, anónimo) tampoco', (r -> 'error' ->> 'http_code')::int = 403, r::text);

  perform pg_temp.usuario('00000000-0000-4000-a000-0000000000a1', 'operaria.nueva@osasun.invalid');
  perform pg_temp.comprobar('Al entrar por primera vez, la operaria queda dada de alta: rol, almacén y horario (9 turnos)',
    (select rol = 'operario' and nombre = 'Operaria nueva' and activo
            and centro_id = (select id from public.centros_trabajo where codigo = 'ALMACEN')
       from public.personas where id = '00000000-0000-4000-a000-0000000000a1')
    and (select count(*) from public.horarios where persona_id = '00000000-0000-4000-a000-0000000000a1') = 9
    and (select count(*) from public.horarios where persona_id = '00000000-0000-4000-a000-0000000000a1'
          and dia_semana = 5 and turno = 'tarde') = 0);
  perform pg_temp.comprobar('Marcada como operaria por defecto: le van las tareas de Administración',
    motor.operario_por_defecto() = '00000000-0000-4000-a000-0000000000a1');
  v_j := motor.generar_jornada('00000000-0000-4000-a000-0000000000a1', '2026-11-10');
  perform pg_temp.comprobar('Su jornada se genera con las tareas del día',
    (select count(*) from public.tareas where jornada_id = v_j) > 5);

  perform pg_temp.usuario('00000000-0000-4000-a000-0000000000a2', 'desconocido@osasun.invalid');
  perform pg_temp.comprobar('Un usuario fuera de la lista (si llegase a existir) no tiene ficha',
    not exists (select 1 from public.personas where id = '00000000-0000-4000-a000-0000000000a2'));

  -- Usuario que ya existía (entró antes de estar en la lista): se vincula, sin duplicar.
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-0000000000a3', 'authenticated', 'authenticated',
          'otra.jefa@osasun.invalid', '{}', '{}', now(), now());
  update public.configuracion set valor = valor || '[{"correo": "otra.jefa@osasun.invalid", "nombre": "Otra jefa", "rol": "administracion"}]'
   where clave = 'cuentas_autorizadas' and centro_id is null;
  v_n := motor.vincular_cuentas_autorizadas();
  v_n2 := motor.vincular_cuentas_autorizadas();
  perform pg_temp.comprobar('Usuario ya existente: vincular_cuentas_autorizadas le da de alta una vez (y repetirlo no duplica)',
    v_n = 1 and v_n2 = 0
    and (select rol = 'administracion' and centro_id is null from public.personas where id = '00000000-0000-4000-a000-0000000000a3'), v_n || '/' || v_n2);
end;
$$;

-- La operaria nueva usa la app; el usuario fuera de la lista no puede.
select pg_temp.como('00000000-0000-4000-a000-0000000000a1');
do $$
declare
  r jsonb := public.mi_perfil();
begin
  perform pg_temp.comprobar('Operaria nueva: mi_perfil con su rol y su centro',
    r ->> 'rol' = 'operario' and r -> 'centro' ->> 'nombre' is not null, r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-0000000000a2');
do $$
declare
  r jsonb := public.mi_perfil();
begin
  perform pg_temp.comprobar('Fuera de la lista: NO_AUTORIZADO y no ve nada',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO' and (select count(*) from public.tareas) = 0, r::text);
end;
$$;
reset role;

-- Permisos del hook: solo Supabase Auth lo usa.
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se puede llamar al hook ni a las funciones de alta',
    pg_temp.rechazada($q$select public.hook_antes_de_crear_usuario('{}')$q$)
    and pg_temp.rechazada($q$select motor.vincular_cuentas_autorizadas()$q$));
end;
$$;
reset role;
do $$
begin
  perform pg_temp.comprobar('Supabase Auth (supabase_auth_admin) puede usar el hook; un usuario con sesión no',
    has_function_privilege('supabase_auth_admin', 'public.hook_antes_de_crear_usuario(jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.hook_antes_de_crear_usuario(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.hook_antes_de_crear_usuario(jsonb)', 'execute'));
  perform pg_temp.comprobar('Tiempo real activado para tareas y elementos',
    (select count(*) from pg_publication_tables where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename in ('tareas', 'tarea_elementos')) = 2);
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
