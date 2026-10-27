-- Tarea 5 · Acceso solo con Google y solo para las cuentas autorizadas.
-- La lista está en la configuración de cada entorno (cuentas_autorizadas), nunca
-- en el repositorio:
--   [{"correo": "...", "nombre": "...", "rol": "operario"|"administracion",
--     "centro": "ALMACEN", "telefono": "...", "por_defecto": true,
--     "horario": [{"dias": [1,2,3,4,5], "turno": "manana", "inicio": "08:30", "fin": "13:00"}, ...]}]
-- 1. Hook «Before User Created» de Supabase Auth: una cuenta que no está en la
--    lista no crea usuario (se activa en Authentication → Hooks).
-- 2. Al crearse el usuario de una cuenta autorizada se da de alta su persona
--    (rol, centro, horario). Para usuarios que ya existían: motor.vincular_cuentas_autorizadas().
-- 3. Operario por defecto (para las tareas de Administración, estado_actual…):
--    configuración operario_por_defecto; si no hay, el primero por nombre.
-- 4. Teléfono de Administración para el operario: configuración telefono_administracion.
-- 5. Tiempo real (Realtime) para las pantallas: tareas y sus elementos.

-- Entrada de la lista para un correo (sin distinguir mayúsculas).
create or replace function motor.cuenta_autorizada(p_correo text)
returns jsonb
language sql stable
set search_path = ''
as $$
  select x
    from public.configuracion k, jsonb_array_elements(k.valor) x
   where k.clave = 'cuentas_autorizadas' and k.centro_id is null and jsonb_typeof(k.valor) = 'array'
     and lower(btrim(x ->> 'correo')) = lower(btrim(p_correo))
   limit 1;
$$;

-- 1. Hook de Supabase Auth (antes de crear un usuario).
create or replace function public.hook_antes_de_crear_usuario(event jsonb)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
begin
  if nullif(btrim(event -> 'user' ->> 'email'), '') is not null
     and motor.cuenta_autorizada(event -> 'user' ->> 'email') is not null then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'Esta cuenta no tiene acceso a Osasun Operations. Pide acceso a Administración.'));
end;
$$;

revoke execute on function public.hook_antes_de_crear_usuario(jsonb) from public, anon, authenticated;
grant execute on function public.hook_antes_de_crear_usuario(jsonb) to supabase_auth_admin;

-- 2. Alta de la persona de una cuenta autorizada.
create or replace function motor.alta_cuenta_autorizada(p_usuario uuid, p_correo text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  e jsonb := motor.cuenta_autorizada(p_correo);
  v_centro uuid;
  h jsonb;
  d integer;
begin
  if e is null or exists (select 1 from public.personas where id = p_usuario) then
    return null;
  end if;
  select id into v_centro from public.centros_trabajo where codigo = coalesce(e ->> 'centro', 'ALMACEN');
  insert into public.personas (id, nombre, rol, centro_id, telefono)
  values (p_usuario, coalesce(nullif(btrim(e ->> 'nombre'), ''), 'Sin nombre'), e ->> 'rol',
          case when e ->> 'rol' = 'operario' then v_centro end, nullif(btrim(e ->> 'telefono'), ''));
  for h in select * from jsonb_array_elements(coalesce(e -> 'horario', '[]'::jsonb)) loop
    for d in select (jsonb_array_elements_text(h -> 'dias'))::int loop
      insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
      values (p_usuario, d, h ->> 'turno', (h ->> 'inicio')::time, (h ->> 'fin')::time)
      on conflict (persona_id, dia_semana, turno) do nothing;
    end loop;
  end loop;
  if e ->> 'rol' = 'operario' and coalesce((e ->> 'por_defecto')::boolean, false) then
    insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, to_jsonb(p_usuario::text))
    on conflict (clave, centro_id) do update set valor = excluded.valor;
  end if;
  perform motor.registrar('persona_dada_de_alta', null, null, null,
                          jsonb_build_object('persona', p_usuario, 'rol', e ->> 'rol'));
  return p_usuario;
end;
$$;

-- Al crearse un usuario (después del hook). Nunca impide el alta del usuario.
create or replace function motor.tras_crear_usuario()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  begin
    perform motor.alta_cuenta_autorizada(new.id, new.email);
  exception when others then
    perform motor.registrar('alta_persona_fallida', null, null, null,
                            jsonb_build_object('usuario', new.id, 'error', sqlerrm));
  end;
  return new;
end;
$$;

-- Supabase Auth crea el usuario con su propio rol: necesita llegar a la función.
grant usage on schema motor to supabase_auth_admin;
grant execute on function motor.tras_crear_usuario() to supabase_auth_admin;

create trigger alta_persona_autorizada
  after insert on auth.users
  for each row execute function motor.tras_crear_usuario();

-- Para usuarios que ya existían antes de estar en la lista (o de esta función).
create or replace function motor.vincular_cuentas_autorizadas()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  u record;
  n integer := 0;
begin
  for u in select id, email from auth.users where email is not null loop
    if motor.alta_cuenta_autorizada(u.id, u.email) is not null then
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

-- 3. Operario por defecto.
create or replace function motor.operario_por_defecto()
returns uuid
language sql stable
set search_path = ''
as $$
  select p.id from public.personas p join public.centros_trabajo c on c.id = p.centro_id
   where p.activo and p.rol = 'operario' and c.tipo = 'almacen'
   order by p.id::text = (select valor #>> '{}' from public.configuracion
                           where clave = 'operario_por_defecto' and centro_id is null) desc nulls last,
            p.nombre, p.id
   limit 1;
$$;

-- 4. Teléfono de Administración que ve el operario.
create or replace function motor.mi_perfil_de(p_persona uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'nombre', p.nombre, 'rol', p.rol,
    'centro', case when c.id is null then null else jsonb_build_object('id', c.id, 'nombre', c.nombre) end,
    'telefono_administracion', coalesce(
      (select valor #>> '{}' from public.configuracion where clave = 'telefono_administracion' and centro_id is null),
      (select a.telefono from public.personas a
        where a.rol = 'administracion' and a.activo and a.telefono is not null
        order by a.nombre limit 1)))
  from public.personas p
  left join public.centros_trabajo c on c.id = p.centro_id
  where p.id = p_persona;
$$;

-- 5. Tiempo real: las pantallas se suscriben a los cambios de tareas y elementos
--    (cada usuario solo recibe lo que su rol puede leer).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                     and schemaname = 'public' and tablename in ('tareas', 'tarea_elementos')) then
    alter publication supabase_realtime add table public.tareas, public.tarea_elementos;
  end if;
end;
$$;

revoke execute on all functions in schema motor from public;
