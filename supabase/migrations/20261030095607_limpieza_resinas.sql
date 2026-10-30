-- Tarea 20 · La limpieza de resinas del viernes, después de lo del reparto, el
-- envío y el +35 % (ESTADO_DEL_SISTEMA.md v1.33, §4 «Viernes»), y retoques de la auditoría.
--
-- Se reutiliza el requisito que ya tenían las tareas (`requiere_codigo` en la
-- plantilla, `requiere_clave` en la tarea: el efectivo no sale hasta hacer la
-- salida). Ahora puede ser una lista separada por «+», como las condiciones, y
-- una tarea con requisito sale cuando ninguna de esas tareas del día está por
-- hacer (pendiente, en curso o bloqueada): las que no hay ese día no esperan.
--
-- Deshacer: volver a crear motor.elegir_tarea y motor.auditoria como en
-- 20261027120100_incidencias_reparto_motor.sql y 20261029153724_auditoria.sql,
-- drop function motor.requisitos_hechos(uuid, text), y en la plantilla y las
-- tareas pendientes de limpieza_resinas: requiere = null, hora_limite = 10:45.

create or replace function motor.requisitos_hechos(p_jornada uuid, p_requiere text)
returns boolean language sql stable set search_path = '' as $$
  select p_requiere is null
      or not exists (select 1 from public.tareas r
                      where r.jornada_id = p_jornada
                        and r.clave = any (string_to_array(p_requiere, '+'))
                        and r.estado in ('pendiente', 'en_curso', 'bloqueada'))
$$;
revoke execute on function motor.requisitos_hechos(uuid, text) from public;

-- ---------------------------------------------------------------------------
-- Nunca sin tarea (§4): 1) lo disponible, como siempre (sin «Orden y limpieza»);
-- 2) dentro del turno, las fijas de la tarde de ese día; 3) «Orden y limpieza».
-- Lo que va ligado a su hora (recuento, revisión del envío, Nacex, salida) no se adelanta.
-- ---------------------------------------------------------------------------
create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
  v_id uuid;
begin
  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and (t.estado = 'en_curso'
         or (t.estado = 'pendiente'
             and t.disponible_desde <= p_ahora
             and t.prioridad_cola is distinct from 'D'
             and motor.requisitos_hechos(t.jornada_id, t.requiere_clave)))
  order by motor.escalon(t),
           case when motor.escalon(t) = 3 then t.creada_en end,
           case t.prioridad_cola when 'A' then 1 when 'C' then 2 when 'D' then 3 end nulls first,
           t.hora_programada nulls last,
           t.hora_limite nulls last,
           t.obligatoria desc,
           t.orden,
           t.creada_en,
           t.id
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  -- Solo dentro de su turno: entre turnos no se le ofrece nada.
  select * into j from public.jornadas where id = p_jornada;
  if not exists (select 1 from public.horarios h
                  where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                    and p_ahora >= motor.en_local(j.fecha, h.hora_inicio)
                    and p_ahora < motor.en_local(j.fecha, h.hora_fin)) then
    return null;
  end if;

  select t.id into v_id
  from public.tareas t
  join public.plantillas_tarea p on p.id = t.plantilla_id
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and p.programacion = 'dia_semana' and p.turno = 'tarde' and p.hora_inicio is null
    and t.requiere_clave is null
  order by t.hora_limite nulls last, t.orden, t.creada_en, t.id
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and t.prioridad_cola = 'D' and t.disponible_desde <= p_ahora
  order by t.orden, t.creada_en, t.id
  limit 1;
  return v_id;
end;
$$;

-- La limpieza de resinas: después de preparar el reparto (para saber si lo hay),
-- su producción y sus bolsas, la preparación del envío y el +35 %; antes del
-- recuento de las 12:45. Si no da tiempo, se arrastra como hasta ahora.
update public.plantillas_tarea
   set requiere_codigo = 'pegar_reparto+produccion_reparto+bolsas+preparar_envio_viernes+cola_stock',
       hora_limite = '12:45'
 where codigo = 'limpieza_resinas';
update public.tareas t
   set requiere_clave = 'pegar_reparto+produccion_reparto+bolsas+preparar_envio_viernes+cola_stock',
       hora_limite = motor.en_local(j.fecha, '12:45')
  from public.jornadas j
 where j.id = t.jornada_id and t.clave = 'limpieza_resinas' and t.estado = 'pendiente';

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
  for r in select x.tipo from public.repartos x join public.jornadas j on j.id = x.jornada_id
            where x.estado = 'aceptado' and j.fecha = hoy
              and (case x.tipo
                     when 'reparto' then (select count(distinct t.clave) from public.tareas t
                                           where t.jornada_id = x.jornada_id and t.estado <> 'cancelada'
                                             and t.clave in ('produccion_reparto', 'bolsas')) < 2
                     else not exists (select 1 from public.tareas t
                                       where t.jornada_id = x.jornada_id and t.estado <> 'cancelada'
                                         and t.clave in ('preparar_envio', 'preparar_envio_viernes')) end)
            order by 1 desc loop
    avisos := avisos || case r.tipo when 'reparto' then 'El reparto aceptado hoy no tiene su tarea de producción o de bolsas.'
                                   else 'El envío aceptado hoy no tiene su tarea de preparación.' end;
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
