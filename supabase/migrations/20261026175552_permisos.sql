-- Tarea 2 · Permisos
-- RLS en todas las tablas, solo lectura para usuarios autenticados y
-- ninguna escritura directa: toda escritura pasa por funciones del esquema motor.

-- Nada nuevo nace con permisos abiertos.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema motor revoke execute on functions from public, anon, authenticated;
alter default privileges in schema prueba revoke execute on functions from public, anon, authenticated;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;

-- motor: los usuarios solo pueden ejecutar lo que se conceda expresamente.
revoke all on schema motor from public;
grant usage on schema motor to authenticated;
-- prueba: nadie salvo el propietario de la base de datos.
revoke all on schema prueba from public;

-- Ayudas para las políticas (SECURITY DEFINER para no depender de la RLS de personas).
create or replace function motor.es_admin()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.personas p
    where p.id = auth.uid() and p.activo and p.rol = 'administracion'
  );
$$;

create or replace function motor.mi_centro()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select p.centro_id from public.personas p where p.id = auth.uid() and p.activo;
$$;

revoke execute on function motor.es_admin(), motor.mi_centro() from public;
grant execute on function motor.es_admin(), motor.mi_centro() to authenticated;

alter table public.centros_trabajo  enable row level security;
alter table public.personas         enable row level security;
alter table public.horarios         enable row level security;
alter table public.plantillas_tarea enable row level security;
alter table public.configuracion    enable row level security;
alter table public.jornadas         enable row level security;
alter table public.tareas           enable row level security;
alter table public.registro_eventos enable row level security;

-- Una sola política de lectura por tabla. No hay políticas de escritura.
create policy lectura on public.centros_trabajo for select to authenticated
  using (true);

create policy lectura on public.personas for select to authenticated
  using (id = (select auth.uid()) or (select motor.es_admin()));

create policy lectura on public.horarios for select to authenticated
  using (persona_id = (select auth.uid()) or (select motor.es_admin()));

create policy lectura on public.plantillas_tarea for select to authenticated
  using (centro_id = (select motor.mi_centro()) or (select motor.es_admin()));

create policy lectura on public.configuracion for select to authenticated
  using (centro_id is null or centro_id = (select motor.mi_centro()) or (select motor.es_admin()));

create policy lectura on public.jornadas for select to authenticated
  using (persona_id = (select auth.uid()) or (select motor.es_admin()));

create policy lectura on public.tareas for select to authenticated
  using (
    (select motor.es_admin())
    or jornada_id in (select j.id from public.jornadas j where j.persona_id = (select auth.uid()))
  );

create policy lectura on public.registro_eventos for select to authenticated
  using ((select motor.es_admin()));
