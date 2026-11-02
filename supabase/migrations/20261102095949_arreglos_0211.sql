-- Tarea 23 · Cuatro arreglos tras la prueba del 02/11/2026 (ESTADO_DEL_SISTEMA.md v1.38).
--   1. Tareas de Administración no urgentes y sin hora límite: después de la revisión
--      inicial, «Prepara el reparto», la producción, las bolsas y la preparación del
--      envío del viernes. Con el requisito de la Tarea 20 (requiere_clave).
--   2. estado_actual().hoy: primero lo hecho y lo que está en curso, por cuándo empezó.
--   3. Administración por defecto: clave de configuración `administracion_por_defecto`
--      (propia de cada entorno, como `operario_por_defecto`); si falta, como antes.
--   4. «Calcular» siempre recalcula: servidor_guardar_reparto ya no devuelve lo de
--      antes cuando el texto es el mismo (la huella); sustituye conservando lo hecho.
--
-- Deshacer: volver a crear motor.mi_perfil_de (20261027141334), motor.huella_estructura
-- (20261029153724), motor.crear_tarea_admin_de (20261027093007), motor.estado_actual_de
-- (20261030121241) y public.servidor_guardar_reparto (20261029140000) como estaban, y
-- drop function motor.administracion_por_defecto().

create or replace function motor.administracion_por_defecto()
returns uuid language sql stable set search_path = '' as $$
  select p.id from public.personas p
   where p.activo and p.rol = 'administracion'
   order by p.id::text = (select valor #>> '{}' from public.configuracion
                           where clave = 'administracion_por_defecto' and centro_id is null) desc nulls last,
            p.nombre, p.id
   limit 1;
$$;
revoke execute on function motor.administracion_por_defecto() from public;

create or replace function motor.mi_perfil_de(p_persona uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'nombre', p.nombre, 'rol', p.rol,
    'centro', case when c.id is null then null else jsonb_build_object('id', c.id, 'nombre', c.nombre) end,
    'telefono_administracion', coalesce(
      (select valor #>> '{}' from public.configuracion where clave = 'telefono_administracion' and centro_id is null),
      (select a.telefono from public.personas a
        where a.rol = 'administracion' and a.activo and a.telefono is not null
        order by a.id = motor.administracion_por_defecto() desc, a.nombre limit 1)),
    'quien_sale_opciones', jsonb_build_array(
      jsonb_build_object('valor', 'administracion',
                         'nombre', coalesce((select a.nombre from public.personas a
                                              where a.id = motor.administracion_por_defecto()), 'Administración')),
      jsonb_build_object('valor', 'operario',
                         'nombre', coalesce((select o.nombre from public.personas o where o.id = motor.operario_por_defecto()),
                                            'Operario'))))
  from public.personas p
  left join public.centros_trabajo c on c.id = p.centro_id
  where p.id = p_persona;
$$;

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
                            'operario_por_defecto', 'administracion_por_defecto', 'telefono_administracion'))  -- propias de cada entorno
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

create or replace function motor.crear_tarea_admin_de(
  p_admin uuid, p_id_cliente uuid, p_que text, p_para_quien uuid, p_cuando jsonb, p_duracion_min integer,
  p_urgente boolean, p_porque text, p_confirmar boolean, p_decision jsonb, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_tipo text := p_cuando ->> 'tipo';
  v_fecha date;
  v_hora time;
  v_persona uuid := coalesce(p_para_quien, motor.operario_por_defecto());
  v_jornada uuid;
  v_inicio timestamptz;
  v_fin timestamptz;
  v_limite timestamptz;
  v_conflicto jsonb;
  v_faltan integer;
  v_accion text := p_decision ->> 'accion';
  v_cede public.tareas;
  v_id uuid;
  v_previo jsonb;
  v_encaje text;
begin
  if p_id_cliente is null then
    return motor.error('DATOS_NO_VALIDOS', 'Falta el identificador de la petición.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('admin:' || p_id_cliente, 0));
  select id into v_id from public.tareas where id_cliente = p_id_cliente;
  if v_id is not null then
    return jsonb_build_object('tarea_id', v_id, 'tarea', motor.tarea_json(v_id), 'ya_creada', true, 'conflicto', null);
  end if;
  select datos into v_previo from public.registro_eventos
   where tipo = 'conflicto_decidido' and datos ->> 'id_cliente' = p_id_cliente::text and datos ->> 'accion' = 'no_crear';
  if v_previo is not null then
    return jsonb_build_object('tarea_id', null, 'creada', false, 'decision', 'no_crear', 'conflicto', v_previo -> 'conflicto');
  end if;

  -- Datos
  if nullif(btrim(p_que), '') is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe qué hay que hacer.');
  end if;
  if p_duracion_min is null or p_duracion_min <= 0 or p_duracion_min > 600 then
    return motor.error('DATOS_NO_VALIDOS', 'Pon una duración orientativa en minutos.');
  end if;
  if v_tipo is null or v_tipo not in ('hoy', 'dia', 'antes_de') then
    return motor.error('DATOS_NO_VALIDOS', 'Indica cuándo: hoy, un día o antes de una hora.');
  end if;
  begin
    v_fecha := case when v_tipo = 'hoy' then v_hoy else (p_cuando ->> 'fecha')::date end;
    v_hora := case when v_tipo = 'antes_de' then (p_cuando ->> 'hora')::time end;
  exception when others then
    return motor.error('DATOS_NO_VALIDOS', 'La fecha o la hora no son válidas.');
  end;
  if v_fecha is null or (v_tipo = 'antes_de' and v_hora is null) then
    return motor.error('DATOS_NO_VALIDOS', 'Falta la fecha o la hora.');
  end if;
  if not exists (select 1 from public.personas where id = v_persona and activo and rol = 'operario') then
    return motor.error('NO_ENCONTRADO', 'Esa persona no existe.');
  end if;
  if v_fecha < v_hoy then
    return motor.error('FECHA_PASADA', 'Esa fecha ya ha pasado.');
  end if;
  if v_hora is not null then
    v_limite := motor.en_local(v_fecha, v_hora);
    if v_limite <= p_ahora then
      return motor.error('FECHA_PASADA', 'Esa hora ya ha pasado.');
    end if;
  end if;

  -- Ventana: desde ahora (o el inicio del día) hasta la hora límite (o el final del turno).
  v_jornada := motor.jornada_para(v_persona, v_fecha, p_ahora);
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Ese día no trabaja.');
  end if;
  v_inicio := greatest(case when v_fecha = v_hoy then p_ahora end, motor.inicio_turno(v_persona, v_fecha, null));
  v_fin := coalesce(v_limite,
                    (select motor.en_local(v_fecha, h.hora_fin) from public.horarios h
                      where h.persona_id = v_persona and h.dia_semana = extract(isodow from v_fecha)
                        and motor.en_local(v_fecha, h.hora_fin) > v_inicio
                      order by h.hora_inicio limit 1));
  if v_fin is null then
    return motor.error('FECHA_PASADA', 'Hoy ya ha terminado su jornada: elige otro día.');
  end if;
  v_conflicto := motor.conflicto(v_jornada, v_inicio, greatest(v_fin, v_inicio), p_duracion_min);
  v_faltan := (v_conflicto ->> 'minutos_que_faltan')::int;
  v_encaje := case
    when coalesce(p_urgente, false) then 'Urgente: entra en cuanto termine lo que está haciendo (la referencia o la tienda en curso).'
    when v_limite is not null then 'Antes de las ' || motor.hora_texto(v_limite) || ', después de lo que tiene hora.'
    else 'Cuando termine lo del reparto, las obligatorias y lo que tiene hora.' end
    || case when v_fecha <> v_hoy then ' El ' || to_char(v_fecha, 'DD/MM') || '.' else '' end
    -- Sin obligatorias en riesgo se crea igualmente; se avisa de lo que no le da tiempo.
    || case when not (v_conflicto ->> 'hay_conflicto')::boolean and v_faltan > 0
            then ' No le da tiempo entera (faltan unos ' || v_faltan || ' min): lo que no termine pasa al día siguiente.'
            else '' end;

  if not (v_conflicto ->> 'hay_conflicto')::boolean then
    v_conflicto := null;
  elsif v_accion is null or v_accion not in ('no_crear', 'despues', 'manana', 'cancelar') then
    return motor.error('CONFLICTO', 'No cabe: decide qué cede o no la crees.', jsonb_build_object('conflicto', v_conflicto));
  elsif v_accion <> 'no_crear' then
    begin
      select * into v_cede from public.tareas where id = (p_decision ->> 'cede')::uuid;
    exception when others then
      v_cede := null;
    end;
    if v_cede.id is null or v_cede.jornada_id <> v_jornada or v_cede.estado not in ('pendiente', 'en_curso', 'bloqueada') then
      return motor.error('DATOS_NO_VALIDOS', 'Elige una de las tareas en riesgo para que ceda.',
                         jsonb_build_object('conflicto', v_conflicto));
    end if;
  end if;

  if not coalesce(p_confirmar, false) then
    return jsonb_build_object('tarea_id', null, 'comprobado', true, 'encaje', v_encaje, 'conflicto', v_conflicto,
                              'minutos_que_faltan', v_faltan);
  end if;

  if v_accion = 'no_crear' and v_conflicto is not null then
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, null,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', 'no_crear', 'que', btrim(p_que), 'conflicto', v_conflicto));
    return jsonb_build_object('tarea_id', null, 'creada', false, 'decision', 'no_crear', 'conflicto', v_conflicto);
  end if;

  -- No urgente y sin hora límite: después de la revisión inicial y de lo del reparto
  -- (el requisito de la Tarea 20: lo que no hay ese día no hace esperar).
  insert into public.tareas (jornada_id, clave, origen, titulo, porque, obligatoria, disponible_desde, hora_limite,
                             urgente, duracion_min, no_terminada, orden, creada_por, id_cliente, requiere_clave)
  values (v_jornada, 'admin:' || p_id_cliente, 'administracion', btrim(p_que), nullif(btrim(p_porque), ''), false,
          case when v_fecha = v_hoy then p_ahora else motor.inicio_turno(v_persona, v_fecha, null) end, v_limite,
          coalesce(p_urgente, false), p_duracion_min, 'arrastrar', 50, p_admin, p_id_cliente,
          case when not coalesce(p_urgente, false) and v_limite is null
               then 'revision_inicial+pegar_reparto+produccion_reparto+bolsas+preparar_envio_viernes' end)
  returning id into v_id;
  perform motor.registrar('tarea_creada', p_admin, v_jornada, v_id,
    jsonb_build_object('origen', 'administracion', 'urgente', coalesce(p_urgente, false), 'duracion_min', p_duracion_min,
                       'conflicto', v_conflicto is not null, 'minutos_que_faltan', v_faltan));

  if v_conflicto is not null then
    if v_accion = 'despues' then
      update public.tareas set hora_limite = null,
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: se hace después'
       where id = v_cede.id;
    elsif v_accion = 'manana' then
      update public.tareas set no_terminada = 'arrastrar', estado = case when estado = 'en_curso' then 'pendiente' else estado end,
             disponible_desde = motor.en_local(v_fecha + 1, '00:00'),
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: pasa al día siguiente'
       where id = v_cede.id;
    else
      update public.tareas set estado = 'cancelada',
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: cancelada por Administración'
       where id = v_cede.id;
    end if;
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, v_cede.id,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', v_accion, 'cede', v_cede.id, 'cede_titulo', v_cede.titulo,
                         'nueva', v_id, 'conflicto', v_conflicto));
  end if;

  return jsonb_build_object('tarea_id', v_id, 'tarea', motor.tarea_json(v_id), 'encaje', v_encaje,
                            'conflicto', v_conflicto, 'minutos_que_faltan', v_faltan,
                            'decision', case when v_conflicto is not null then
                                          jsonb_build_object('cede', v_cede.id, 'titulo', v_cede.titulo, 'accion', v_accion) end);
end;
$$;

create or replace function motor.estado_actual_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with op as (select id, nombre from public.personas where id = motor.operario_por_defecto()),
  j as (select jo.* from public.jornadas jo join op on op.id = jo.persona_id where jo.fecha = motor.fecha_local(p_ahora))
  select jsonb_build_object(
    'ahora', motor.hora_texto(p_ahora),
    'fecha', motor.fecha_local(p_ahora),
    'operario', (select jsonb_build_object('id', op.id, 'nombre', op.nombre) from op),
    'jornada', (select jsonb_build_object('id', j.id, 'sale', j.sale, 'hay_envio', j.hay_envio, 'estado', j.estado) from j),
    'en_curso', (select motor.tarea_json(t.id) from public.tareas t join j on j.id = t.jornada_id where t.estado = 'en_curso'),
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r join j on j.id = r.jornada_id
        left join public.personas pe on pe.id = r.pegado_por
       where r.tipo = 'reparto' and r.estado = 'aceptado'),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.estado <> 'resuelto' and p.persona_id = (select id from op)), '[]'::jsonb),
    'incidencia_en_curso', motor.seguimiento_de((select id from op), p_ahora) -> 'incidencia_en_curso',
    'incidencias_abiertas', coalesce((
      select jsonb_agg(motor.incidencia_json(i.id, p_ahora) order by i.iniciada_en)
        from public.incidencias i where i.persona_id = (select id from op) and i.estado <> 'cerrada'
                                    and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'arrastradas', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado) order by t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id where t.tarea_origen_id is not null), '[]'::jsonb),
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado, 'origen', t.origen,
                                          'obligatoria', t.obligatoria, 'urgente', t.urgente,
                                          'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)),
                                          'motivo', t.motivo_no_hecha,
                                          'iniciada_en', t.iniciada_en, 'terminada_en', t.terminada_en,
                                          'minutos', motor.minutos_tarea(t, p_ahora),
                                          'interrupciones', motor.interrupciones_tarea(t.id),
                                          'cajas', motor.cajas_tarea(t.id),
                                          'minutos_trabajados', motor.minutos_trabajados(t.id, p_ahora))
                       -- Primero lo hecho y lo que está en curso, en el orden en que se empezó; después lo pendiente.
                       order by t.estado in ('hecha', 'en_curso') desc,
                                case when t.estado in ('hecha', 'en_curso') then coalesce(t.iniciada_en, t.terminada_en) end,
                                coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id
       where not t.retirada_por_condicion and t.origen <> 'problema'), '[]'::jsonb),
    -- Avisos para el almacén que siguen abiertos (de hoy y de días que vienen), para verlos y cancelarlos.
    'avisos_almacen', coalesce((
      select jsonb_agg(motor.aviso_json(i.id) order by i.iniciada_en)
        from public.incidencias i
       where i.opcion = 'aviso' and i.estado <> 'cerrada' and i.persona_id = (select id from op)), '[]'::jsonb),
    'retrasos_salida', coalesce((
      select jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                          'minutos', (r.datos ->> 'minutos')::int, 'nueva_hora', r.datos ->> 'nueva_hora',
                                          'sale', r.datos ->> 'sale', 'aviso', r.datos ->> 'aviso') order by r.id)
        from public.registro_eventos r join j on j.id = r.jornada_id where r.tipo = 'salida_retrasada'), '[]'::jsonb),
    'correos_no_enviados', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'asunto', m.asunto, 'estado', m.estado, 'intentos', m.intentos,
                                          'error', m.ultimo_error, 'creado_en', m.creado_en) order by m.id desc)
        from motor.correos m
       where m.estado in ('fallido', 'dudoso') and m.creado_en >= p_ahora - interval '7 days'), '[]'::jsonb),
    -- «Orden y limpieza» de hoy: cuántas se han empezado y cuántos minutos en total.
    'tiempo_libre', (
      select jsonb_build_object('veces', count(*),
                                'minutos', coalesce(round(sum(extract(epoch from
                                  coalesce(t.terminada_en, case when t.estado = 'en_curso' then p_ahora end) - t.iniciada_en)) / 60), 0)::int)
        from public.tareas t join j on j.id = t.jornada_id
        join public.plantillas_tarea p on p.id = t.plantilla_id
       where p.codigo = 'cola_orden' and t.iniciada_en is not null),
    -- R4: productos con menos de 2 semanas, de la última lectura de la hoja que la trae.
    'cobertura_baja', coalesce((
      select jsonb_build_object('datos_leidos_en', l.leido_en, 'productos', coalesce(l.cobertura -> 'productos', '[]'::jsonb),
                                'avisos', coalesce(l.cobertura -> 'avisos', '[]'::jsonb))
        from public.lecturas_sheets l where l.correcto and l.cobertura is not null and l.leido_en <= p_ahora
       order by l.leido_en desc limit 1),
      jsonb_build_object('datos_leidos_en', null, 'productos', '[]'::jsonb, 'avisos', '[]'::jsonb)),
    'lectura_sheets', jsonb_build_object(
      'ultima_correcta', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo)
                            from public.lecturas_sheets l where l.correcto order by l.leido_en desc limit 1),
      'ultimo_error', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo, 'error', l.error)
                         from public.lecturas_sheets l where not l.correcto
                          and l.leido_en > coalesce((select max(k.leido_en) from public.lecturas_sheets k where k.correcto), '-infinity')
                         order by l.leido_en desc limit 1)));
$$;

create or replace function public.servidor_guardar_reparto(
  p_persona uuid, p_jornada uuid, p_tipo text, p_texto text, p_huella text, p_fecha_texto date, p_sale text,
  p_lectura uuid, p_lineas jsonb, p_produccion jsonb, p_bolsas jsonb, p_aceptado boolean, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r0 public.repartos;
  v_id uuid;
  v_cond text := case when p_tipo = 'reparto' then 'reparto_pegado' else 'envio_pegado' end;
  v_prod uuid;
  v_bolsas uuid;
  v_destino uuid;
  v_antes jsonb;
  v_despues jsonb;
  v_bolsas_resultado jsonb := '[]';
  v_min_caja integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                  where clave = 'duracion_min_por_caja' and centro_id is null), 1);
  v_min_bolsa integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                   where clave = 'duracion_min_por_bolsa' and centro_id is null), 3);
  v_dur_prod integer;
  v_dur_bolsas integer;
  v_resultado jsonb;
  v_es_suya boolean := p_persona = (select persona_id from public.jornadas where id = p_jornada);
  v_pegar uuid;
  v_previas jsonb := '[]';
begin
  perform pg_advisory_xact_lock(hashtextextended('reparto:' || p_jornada || ':' || p_tipo, 0));
  -- R1e: lo decidido hasta ahora (la bolsa lleva menos por ello).
  if p_tipo = 'reparto' then
    select coalesce(jsonb_agg(jsonb_build_object('destino_id', x.destino_id, 'producto', x.producto,
                                                 'formato', x.formato, 'cantidad', x.cantidad)), '[]')
      into v_previas from motor.decisiones_sin_granel(p_jornada) x;
  end if;

  if not p_aceptado then
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'con_errores', p_lectura, p_persona, p_ahora)
    returning id into v_id;
  else
    -- Siempre se recalcula con la hoja de ahora, aunque el texto sea el mismo (Tarea 23): se
    -- sustituye conservando lo hecho y lo decidido. Repetir la misma petición lo para el
    -- id_cliente (guardar_reparto); pegar_reparto mira la huella antes de llamar.
    select * into r0 from public.repartos where jornada_id = p_jornada and tipo = p_tipo and estado = 'aceptado';
    if r0.id is not null then
      update public.repartos set estado = 'sustituido' where id = r0.id;
    end if;
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado,
                                 sustituye_a, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'aceptado', r0.id, p_lectura, p_persona, p_ahora)
    returning id into v_id;
  end if;

  insert into public.reparto_lineas (reparto_id, num_linea, texto, clase, destino_id, cantidad, producto, formato, error, mensaje)
  select v_id, (l ->> 'num')::int, l ->> 'texto', l ->> 'clase', (l ->> 'destino_id')::uuid, (l ->> 'cantidad')::int,
         l ->> 'producto', l ->> 'formato', l ->> 'error', l ->> 'mensaje'
  from jsonb_array_elements(coalesce(p_lineas, '[]')) l;

  if not p_aceptado then
    perform motor.registrar('reparto_con_errores', p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo));
    return jsonb_build_object('reparto_id', v_id, 'estado', 'con_errores');
  end if;

  -- Tareas del reparto o del envío
  if p_tipo = 'reparto' then
    perform motor.fijar_sale(p_jornada, p_sale);
  else
    perform motor.fijar_envio(p_jornada, true, null);
  end if;
  perform motor.crear_tarea_condicionada(p_jornada, v_cond);
  if p_tipo = 'reparto' then
    select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
    select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';
  else
    select id into v_prod from public.tareas where jornada_id = p_jornada
       and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1;
    v_bolsas := v_prod;
  end if;
  if v_prod is null or v_bolsas is null then
    raise exception 'No hay tarea para el % de hoy', p_tipo;
  end if;
  update public.tareas set reparto_id = v_id where id in (v_prod, v_bolsas);

  -- Producción: lo que falta. Se conservan las cajas ya hechas.
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, motivo, orden_sugerido, calculo)
  select v_prod, 'referencia_produccion', p_tipo, x ->> 'producto', coalesce(x ->> 'formato', ''),
         (x ->> 'faltan')::int, x ->> 'aviso', coalesce((x ->> 'orden')::int, 0), x || jsonb_build_object('lectura_id', p_lectura)
  from jsonb_array_elements(coalesce(p_produccion, '[]')) x
  where (x ->> 'faltan')::int > 0
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set cantidad = excluded.cantidad, motivo = excluded.motivo, orden_sugerido = excluded.orden_sugerido,
         -- R1e: se conservan las decisiones «otra_tienda» (las «quitar» ya están en la línea nueva).
         calculo = excluded.calculo
                   || case when coalesce((excluded.calculo ->> 'sin_granel')::boolean, false)
                                and public.tarea_elementos.calculo ? 'decisiones'
                           then jsonb_build_object(
                                  'decisiones', coalesce((select jsonb_agg(z) from jsonb_array_elements(public.tarea_elementos.calculo -> 'decisiones') z
                                                           where z ->> 'accion' = 'otra_tienda'), '[]'::jsonb),
                                  'resuelto_por', public.tarea_elementos.calculo -> 'resuelto_por',
                                  'resuelto_en', public.tarea_elementos.calculo -> 'resuelto_en')
                           else '{}'::jsonb end,
         estado = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad then 'hecho'
                       when public.tarea_elementos.estado = 'hecho' then 'pendiente'
                       else public.tarea_elementos.estado end,
         terminado_en = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad
                             then coalesce(public.tarea_elementos.terminado_en, p_ahora) end;

  -- Referencias que ya no hacen falta: sin nada hecho se quitan; con algo hecho se cierran.
  delete from public.tarea_elementos e
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha = 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);
  update public.tarea_elementos e
     set cantidad = e.cantidad_hecha, estado = 'hecho', terminado_en = coalesce(e.terminado_en, p_ahora),
         motivo = 'Ya no hace falta con el reparto corregido'
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha > 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);

  -- Bolsas: las tiendas sin cambios se conservan; las que cambian se vuelven a
  -- comprobar caja a caja; las que ya no están se quitan.
  for v_destino in
    select distinct d from (
      select e.destino_id as d from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo
      union
      select (d ->> 'destino_id')::uuid from jsonb_array_elements(v_previas) d
      union
      select (b ->> 'destino_id')::uuid from jsonb_array_elements(coalesce(p_bolsas, '[]')) b) s
  loop
    -- Lo de antes: la bolsa más lo que no llevaba por lo decidido en la producción (R1e).
    select jsonb_agg(jsonb_build_array(x.producto, x.formato, x.cantidad) order by x.producto, x.formato)
      into v_antes
      from (select u.producto, u.formato, sum(u.cantidad)::int as cantidad
              from (select e.producto, e.formato, e.cantidad from public.tarea_elementos e
                     where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino
                    union all
                    select d ->> 'producto', d ->> 'formato', (d ->> 'cantidad')::int from jsonb_array_elements(v_previas) d
                     where (d ->> 'destino_id')::uuid = v_destino) u
             group by 1, 2) x;
    select jsonb_agg(jsonb_build_array(i ->> 'producto', coalesce(i ->> 'formato', ''), (i ->> 'cantidad')::int)
                     order by i ->> 'producto', coalesce(i ->> 'formato', ''))
      into v_despues
      from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
     where (b ->> 'destino_id')::uuid = v_destino;

    if v_antes is distinct from v_despues then
      delete from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
      select v_bolsas, 'caja_bolsa', p_tipo, i ->> 'producto', coalesce(i ->> 'formato', ''), v_destino,
             (i ->> 'cantidad')::int, coalesce((i ->> 'orden')::int, 0)
        from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
       where (b ->> 'destino_id')::uuid = v_destino;
    end if;
    if v_despues is not null then
      v_bolsas_resultado := v_bolsas_resultado || jsonb_build_object(
        'destino_id', v_destino,
        'destino', (select nombre from public.centros_trabajo where id = v_destino),
        'cajas', (select sum((x ->> 2)::int) from jsonb_array_elements(v_despues) x),
        'cambia', r0.id is not null and v_antes is distinct from v_despues);
    end if;
  end loop;

  -- Duraciones de referencia (§6.10): 1 min por caja que falta, 3 min por tienda.
  select coalesce(sum((x ->> 'faltan')::int), 0) * v_min_caja into v_dur_prod
    from jsonb_array_elements(coalesce(p_produccion, '[]')) x where (x ->> 'faltan')::int > 0;
  v_dur_bolsas := jsonb_array_length(v_bolsas_resultado) * v_min_bolsa;
  if v_prod = v_bolsas then
    update public.tareas set duracion_min = nullif(v_dur_prod + v_dur_bolsas, 0) where id = v_prod;
  else
    update public.tareas set duracion_min = nullif(v_dur_prod, 0) where id = v_prod;
    update public.tareas set duracion_min = nullif(v_dur_bolsas, 0) where id = v_bolsas;
  end if;

  -- R1e: lo decidido en la producción (bolsas con menos, avisos de llamada).
  if p_tipo = 'reparto' then
    perform motor.aplicar_sin_granel(p_persona, p_jornada, p_ahora);
  end if;

  perform motor.ajustar_estado_lista(p_persona, v_prod, 'No falta producir nada: todo está hecho en el almacén', p_ahora);
  if v_bolsas <> v_prod then
    perform motor.ajustar_estado_lista(p_persona, v_bolsas, 'Sin bolsas', p_ahora);
  end if;

  -- «Prepara el reparto» queda hecha al aceptarse el reparto, lo prepare quien lo prepare.
  if p_tipo = 'reparto' then
    for v_pegar in
      update public.tareas
         set estado = 'hecha', iniciada_en = coalesce(iniciada_en, p_ahora), terminada_en = p_ahora,
             resultado = case when v_es_suya then 'Reparto preparado'
                              else 'Reparto preparado por ' || coalesce((select nombre from public.personas where id = p_persona),
                                                                        'Administración') end
       where jornada_id = p_jornada and clave = 'pegar_reparto' and estado in ('pendiente', 'en_curso')
      returning id
    loop
      perform motor.registrar('tarea_terminada', p_persona, p_jornada, v_pegar,
                              jsonb_build_object('a_las', p_ahora, 'por', 'reparto aceptado'));
    end loop;
  end if;

  v_resultado := jsonb_build_object(
    'reparto_id', v_id, 'estado', 'aceptado', 'tipo', p_tipo, 'sale', p_sale, 'sustituye_a', r0.id,
    'produccion', coalesce(p_produccion, '[]'), 'bolsas', v_bolsas_resultado,
    'tareas', jsonb_build_object('produccion', v_prod, 'bolsas', v_bolsas),
    'datos_leidos_en', (select leido_en from public.lecturas_sheets where id = p_lectura),
    'texto_whatsapp', motor.texto_reparto(v_id));
  update public.repartos set resultado = v_resultado where id = v_id;
  perform motor.registrar(case when r0.id is null then 'reparto_aceptado' else 'reparto_sustituido' end,
                          p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo, 'anterior', r0.id));
  return v_resultado || jsonb_build_object('tarea_activa',
                                           case when v_es_suya then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;
