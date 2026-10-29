-- Tarea 19 · Auditoría de solo lectura para el coordinador.
-- motor.huella_estructura(): la huella por apartado que calculaba la prueba 00
-- (la lógica se mueve aquí; la prueba 00 llama a la función: una sola versión).
-- motor.auditoria(): una sola llamada con la estructura, la configuración, los
-- datos y los avisos. Las dos solo leen y solo las ejecutan postgres y
-- service_role. Ver docs/AUDITORIA.md.
-- Deshacer: drop function motor.auditoria(); drop function motor.huella_estructura();
-- y devolver a supabase/tests/00_huella_estructura.sql su consulta.

create or replace function motor.huella_estructura()
returns table (apartado text, huella text)
language sql stable
security definer
-- `public` en la ruta: los nombres de las tablas de public salen sin esquema, como en la prueba 00 de siempre.
set search_path = public
as $$
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
        where clave not in ('entorno', 'correo_administracion', 'cuentas_autorizadas',
                            'operario_por_defecto', 'telefono_administracion'))  -- propias de cada entorno
    || (select string_agg(row(p.codigo, p.titulo, p.programacion, p.dias_semana, p.turno, p.hora_inicio, p.hora_limite,
                              p.duracion_min, p.condicion, p.requiere_codigo, p.contenido, p.obligatoria, p.prioridad_cola,
                              p.no_terminada, p.modo, p.orden, p.activa)::text, E'\n' order by p.codigo)
        from public.plantillas_tarea p)) as h)
select 'tablas y columnas', md5(t) from columnas
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
                                                       from cron.job), ''))
$$;

create or replace function motor.auditoria()
returns jsonb
language plpgsql stable
security definer
set search_path = ''
as $$
declare
  -- Funciones de public que puede ejecutar anon a propósito (hoy, ninguna).
  anon_permitidas constant text[] := '{}';
  -- Claves globales de configuración que usan los cálculos.
  claves constant text[] := array['destinos_reparto', 'duracion_min_por_bolsa', 'duracion_min_por_caja',
    'en_camino_envio_hasta', 'en_camino_reparto_hasta', 'hora_generacion_jornada', 'problema_minutos_reaparicion',
    'sheets_documento_id', 'sheets_pestanas', 'stock_excluidos', 'stock_objetivo_pct'];
  hoy constant date := motor.fecha_local(now());
  v_migraciones jsonb := null;
  v_funciones_publicas jsonb;
  v_correcta jsonb;
  v_error jsonb;
  avisos text[] := '{}';
  r record;
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    execute 'select jsonb_build_object(''cuantas'', count(*), ''ultima'', max(version))
               from supabase_migrations.schema_migrations' into v_migraciones;
  end if;

  -- Estructura.
  for r in select c.oid::regclass::text as tabla from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity order by 1 loop
    avisos := avisos || format('La tabla %s no tiene RLS.', r.tabla);
  end loop;
  for r in select p.proname, string_agg(ro.rolname, ', ' order by ro.rolname) as roles
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             cross join (select oid, rolname from pg_roles where rolname in ('anon', 'authenticated')) ro
            where n.nspname = 'public' and p.proname like 'servidor\_%' and has_function_privilege(ro.oid, p.oid, 'EXECUTE')
            group by p.proname order by 1 loop
    avisos := avisos || format('La función del servidor public.%s la puede ejecutar %s (solo service_role).', r.proname, r.roles);
  end loop;
  for r in select distinct p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
              and p.proname not like 'servidor\_%' and p.proname <> all (anon_permitidas) order by 1 loop
    avisos := avisos || format('La función public.%s la puede ejecutar anon (sin sesión).', r.proname);
  end loop;

  -- Configuración.
  for r in select k from unnest(claves) k
            where not exists (select 1 from public.configuracion c where c.clave = k and c.centro_id is null) order by 1 loop
    avisos := avisos || format('Falta la clave de configuración %s.', r.k);
  end loop;

  -- Datos.
  for r in select j.persona_id, count(*) as n from public.tareas t join public.jornadas j on j.id = t.jornada_id
            where t.estado = 'en_curso' group by j.persona_id having count(*) > 1 order by 1 loop
    avisos := avisos || format('La persona %s tiene %s tareas en curso a la vez.', r.persona_id, r.n);
  end loop;
  for r in select j.fecha, x.tipo, count(*) as n from public.repartos x join public.jornadas j on j.id = x.jornada_id
            where x.estado = 'aceptado' group by x.jornada_id, j.fecha, x.tipo having count(*) > 1 order by 1, 2 loop
    avisos := avisos || format('La jornada del %s tiene %s %s aceptados.', to_char(r.fecha, 'DD/MM/YYYY'), r.n,
                               case r.tipo when 'envio' then 'envíos' else 'repartos' end);
  end loop;
  for r in select count(*) as n from public.tarea_elementos e
            where not exists (select 1 from public.tareas t where t.id = e.tarea_id) having count(*) > 0 loop
    avisos := avisos || format('Hay %s elementos sin su tarea.', r.n);
  end loop;
  select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo) into v_correcta
    from public.lecturas_sheets l where l.correcto order by l.leido_en desc limit 1;
  select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo, 'error', l.error) into v_error
    from public.lecturas_sheets l where not l.correcto order by l.leido_en desc limit 1;
  if v_error is not null and (v_correcta is null or (v_error ->> 'leido_en')::timestamptz > (v_correcta ->> 'leido_en')::timestamptz) then
    avisos := avisos || format('La última lectura de la hoja (%s) dio error: %s', v_error ->> 'leido_en', v_error ->> 'error');
  end if;

  select jsonb_build_object(
           'cuantas', (select jsonb_object_agg(e, (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                                     where n.nspname = e)) from unnest(array['public', 'motor', 'prueba']) e),
           'public_anon', coalesce(jsonb_agg(distinct p.proname) filter (where has_function_privilege('anon', p.oid, 'EXECUTE')), '[]'),
           'public_authenticated', coalesce(jsonb_agg(distinct p.proname) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')), '[]'),
           'public_security_definer', coalesce(jsonb_agg(distinct p.proname) filter (where p.prosecdef), '[]'))
    into v_funciones_publicas
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public';

  return jsonb_build_object(
    'generado_en', now(),
    'resumen', case cardinality(avisos) when 0 then 'Sin avisos' when 1 then '1 aviso' else cardinality(avisos) || ' avisos' end,
    'avisos', to_jsonb(avisos),
    'migraciones', v_migraciones,
    'huella', (select jsonb_object_agg(h.apartado, h.huella) from motor.huella_estructura() h),
    'tablas', (select jsonb_agg(jsonb_build_object('tabla', c.oid::regclass::text, 'rls', c.relrowsecurity,
                                                   'politicas', (select count(*) from pg_policy pl where pl.polrelid = c.oid))
                                order by n.nspname, c.relname)
                 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                where n.nspname in ('public', 'motor') and c.relkind = 'r'),
    'funciones', v_funciones_publicas,
    'triggers', (select coalesce(jsonb_agg(format('%s %s → %s.%s', tg.tgrelid::regclass, tg.tgname, n.nspname, p.proname)
                                           order by tg.tgrelid::regclass::text, tg.tgname), '[]')
                   from pg_trigger tg join pg_proc p on p.oid = tg.tgfoid join pg_namespace n on n.oid = p.pronamespace
                  where not tg.tgisinternal and n.nspname in ('public', 'motor')),
    'cron', (select coalesce(jsonb_agg(jsonb_build_object('nombre', j.jobname, 'cuando', j.schedule, 'activa', (to_jsonb(j) ->> 'active')::boolean)
                                       order by j.jobname), '[]') from cron.job j),
    'configuracion', jsonb_build_object(
       'valores', (select jsonb_object_agg(c.clave, c.valor) from public.configuracion c
                    where c.clave = any (claves) and c.centro_id is null),
       'faltan', to_jsonb(array(select k from unnest(claves) k
                                 where not exists (select 1 from public.configuracion c where c.clave = k and c.centro_id is null)
                                 order by 1))),
    'datos', jsonb_build_object(
       'ultima_lectura_correcta', v_correcta,
       'ultima_lectura_con_error', v_error,
       'correos_fallidos_7_dias', (select count(*) from motor.correos c
                                    where c.estado = 'fallido' and c.creado_en > now() - interval '7 days'),
       'jornada_hoy', exists (select 1 from public.jornadas j where j.fecha = hoy)));
end;
$$;

revoke execute on function motor.huella_estructura() from public, anon, authenticated;
revoke execute on function motor.auditoria() from public, anon, authenticated;
grant execute on function motor.huella_estructura() to service_role;
grant execute on function motor.auditoria() to service_role;
