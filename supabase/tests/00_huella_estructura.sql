-- Prueba 00 · Huella de la estructura
-- Resume en una sola cifra por apartado (md5) todo lo que definen las
-- migraciones: tablas y columnas, restricciones, índices, políticas RLS,
-- permisos sobre tablas y funciones, y el texto de cada función.
-- Se ejecuta en pruebas y en una base creada solo con supabase/migrations: si
-- las huellas coinciden, la estructura de pruebas es exactamente la del repositorio.
-- Solo lee; no cambia nada.

with
esquemas as (select unnest(array['public', 'motor', 'prueba']) as nspname),
columnas as (
  select string_agg(format('%s.%s.%s %s %s %s', c.table_schema, c.table_name, c.column_name, c.data_type,
                           c.is_nullable, coalesce(c.column_default, '')), E'\n'
                    order by c.table_schema, c.table_name, c.ordinal_position) as t
  from information_schema.columns c where c.table_schema in (select nspname from esquemas)),
restricciones as (
  select string_agg(format('%s %s %s', r.conrelid::regclass, r.conname, pg_get_constraintdef(r.oid)), E'\n'
                    order by r.conrelid::regclass::text, r.conname) as t
  from pg_constraint r join pg_namespace n on n.oid = r.connamespace
  where n.nspname in (select nspname from esquemas)),
indices as (
  select string_agg(indexdef, E'\n' order by schemaname, tablename, indexname) as t
  from pg_indexes where schemaname in (select nspname from esquemas)),
politicas as (
  select string_agg(format('%s.%s %s %s %s %s', schemaname, tablename, policyname, cmd, roles::text, qual), E'\n'
                    order by schemaname, tablename, policyname) as t
  from pg_policies where schemaname in (select nspname from esquemas)),
rls as (
  select string_agg(format('%s %s', c.oid::regclass, c.relrowsecurity), E'\n' order by c.oid::regclass::text) as t
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in (select nspname from esquemas) and c.relkind = 'r'),
permisos_tablas as (
  select string_agg(format('%s.%s %s %s', table_schema, table_name, grantee, privilege_type), E'\n'
                    order by table_schema, table_name, grantee, privilege_type) as t
  from information_schema.role_table_grants
  where table_schema in (select nspname from esquemas) and grantee in ('anon', 'authenticated')),
funciones as (
  select string_agg(format('%s.%s(%s) definer=%s config=%s src=%s', n.nspname, p.proname,
                           pg_get_function_identity_arguments(p.oid), p.prosecdef, p.proconfig::text, md5(p.prosrc)), E'\n'
                    order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) as t
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in (select nspname from esquemas)),
permisos_funciones as (
  select string_agg(format('%s.%s(%s) %s %s', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
                           r.rolname, has_function_privilege(r.oid, p.oid, 'EXECUTE')), E'\n'
                    order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid), r.rolname) as t
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join pg_roles r
  where n.nspname in (select nspname from esquemas) and r.rolname in ('anon', 'authenticated')),
permisos_esquemas as (
  select string_agg(format('%s %s %s', e.nspname, r.rolname, has_schema_privilege(r.oid, e.nspname, 'USAGE')), E'\n'
                    order by e.nspname, r.rolname) as t
  from esquemas e cross join pg_roles r where r.rolname in ('anon', 'authenticated')),
carga as (
  select md5(
    (select string_agg(format('%s %s %s %s %s %s', codigo, nombre, tipo, nombre_en_sheets, alias::text, activo), E'\n' order by codigo) from public.centros_trabajo)
    || (select string_agg(format('%s %s', clave, valor::text), E'\n' order by clave) from public.configuracion
        where clave not in ('entorno', 'correo_administracion'))  -- propias de cada entorno
    || (select string_agg(row(p.codigo, p.titulo, p.programacion, p.dias_semana, p.turno, p.hora_inicio, p.hora_limite,
                              p.duracion_min, p.condicion, p.requiere_codigo, p.contenido, p.obligatoria, p.prioridad_cola,
                              p.no_terminada, p.modo, p.orden, p.activa)::text, E'\n' order by p.codigo)
        from public.plantillas_tarea p)) as h)
select 'tablas y columnas' as apartado, md5(t) as huella from columnas
union all select 'restricciones', md5(t) from restricciones
union all select 'índices', md5(t) from indices
union all select 'políticas RLS', md5(t) from politicas
union all select 'RLS activado', md5(t) from rls
union all select 'permisos sobre tablas', md5(coalesce(t, '')) from permisos_tablas
union all select 'funciones', md5(t) from funciones
union all select 'permisos sobre funciones', md5(t) from permisos_funciones
union all select 'permisos sobre esquemas', md5(t) from permisos_esquemas
union all select 'carga inicial', h from carga
union all select 'generación programada', md5(coalesce((select string_agg(jobname || ' ' || schedule || ' ' || command, E'\n' order by jobname)
                                                       from cron.job), ''));
