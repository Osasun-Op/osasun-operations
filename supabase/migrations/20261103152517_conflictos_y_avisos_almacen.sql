-- Tarea 29 · Conflictos al crear una tarea de Administración (ESTADO_DEL_SISTEMA.md §6.4, v1.46) y
-- avisos del almacén a las tiendas (E2-8, v1.47). Solo en pruebas: va detrás de las de tiendas y
-- espera con ellas (AGENTE_BASE_DE_DATOS.md §4).
--   1. Sin falsa alarma: una tarea no urgente y sin hora límite no da conflicto (espera a lo primero
--      de la mañana, §6.4): se crea y el encaje dice cuándo saldrá.
--   2. Las tareas del reparto y del envío del día (producción, bolsas, salida, preparación del envío)
--      no pueden ceder: en obligatorias_en_riesgo traen se_puede_mover: false; si llegan como `cede`,
--      DATOS_NO_VALIDOS.
--   3. Opciones para la tarea nueva en decision_conflicto: nueva_manana (el siguiente día de trabajo
--      de esa persona) y nueva_despues (sin hora límite ni urgencia). no_crear, igual.
--   4. Avisos a las tiendas también desde el almacén (el operario solo los manda); cada aviso dice de
--      quién viene («Almacén» o «Administración»). public.tiendas() para elegir la tienda.
--
-- Deshacer: volver a crear motor.conflicto (20261027103708), motor.crear_tarea_admin_de
-- (20261102142821), motor.aviso_tienda_json y motor.api_crear_aviso_tienda (20261102190536) y
-- motor.tienda_hoy_de (20261103091220) como estaban; borrar motor.es_del_reparto,
-- motor.siguiente_dia_de_trabajo, motor.api_tiendas y
-- public.tiendas.

-- ---------------------------------------------------------------------------
-- 1. Conflictos
-- ---------------------------------------------------------------------------
-- Las tareas del reparto y del envío del día: nunca ceden ante una tarea de Administración (§6.4).
create or replace function motor.es_del_reparto(p_clave text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_clave in ('produccion_reparto', 'bolsas', 'salida_reparto', 'preparar_envio', 'preparar_envio_viernes'), false)
$$;

create or replace function motor.conflicto(p_jornada uuid, p_inicio timestamptz, p_fin timestamptz, p_nueva integer)
returns jsonb
language sql stable
set search_path = ''
as $$
  with j as (select * from public.jornadas where id = p_jornada),
  turnos as (
    select coalesce(sum(greatest(0, extract(epoch from (least(p_fin, motor.en_local(j.fecha, h.hora_fin))
                                                       - greatest(p_inicio, motor.en_local(j.fecha, h.hora_inicio)))) / 60)), 0) as m
      from j join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)),
  bloques as (
    select coalesce(sum(greatest(0, extract(epoch from (least(p_fin, t.hora_programada + make_interval(mins => t.duracion_min))
                                                       - greatest(p_inicio, t.hora_programada))) / 60)), 0) as m
      from public.tareas t
     where t.jornada_id = p_jornada and t.clave in ('salida_reparto', 'nacex_salida', 'nacex_viernes')
       and t.estado in ('pendiente', 'en_curso') and t.hora_programada is not null and t.duracion_min is not null),
  -- Pendientes que vencen hasta el final de la ventana, incluidas las ya vencidas.
  vencen as (
    select t.id, t.clave, t.titulo, t.obligatoria, t.origen, coalesce(t.hora_limite, t.hora_programada) as vence,
           coalesce(t.hora_limite, t.hora_programada) <= p_inicio as vencida,
           motor.duracion_estimada(t.id) as minutos
      from public.tareas t
     where t.jornada_id = p_jornada
       and t.estado in ('pendiente', 'en_curso', 'bloqueada')
       and (t.obligatoria or t.origen = 'administracion')
       and t.origen <> 'problema'
       and t.clave not in ('salida_reparto', 'nacex_salida', 'nacex_viernes')
       and coalesce(t.hora_limite, t.hora_programada) <= p_fin),
  cuentas as (
    select round((select m from turnos) - (select m from bloques))::int as disponible,
           (coalesce((select sum(minutos) from vencen), 0) + p_nueva)::int as necesario,
           coalesce((select sum(minutos) from vencen where vencida), 0)::int as ya_vencidas),
  -- En riesgo solo las obligatorias que vencen dentro de la ventana. Tarea 29: se_puede_mover (las
  -- del reparto y del envío del día, no).
  riesgo as (
    select coalesce(jsonb_agg(jsonb_build_object('tarea_id', v.id, 'titulo', v.titulo, 'vence', motor.hora_texto(v.vence),
                                                 'duracion_min', v.minutos, 'origen', v.origen,
                                                 'se_puede_mover', not motor.es_del_reparto(v.clave)) order by v.vence, v.titulo),
                    '[]'::jsonb) as lista
      from vencen v where v.obligatoria and not v.vencida and v.minutos > 0)
  select jsonb_build_object(
    'hay_conflicto', c.necesario > c.disponible and jsonb_array_length(r.lista) > 0,
    'disponible_min', c.disponible,
    'necesario_min', c.necesario,
    'vencidas_min', c.ya_vencidas,
    'minutos_que_faltan', greatest(c.necesario - c.disponible, 0),
    'obligatorias_en_riesgo', case when c.necesario > c.disponible then r.lista else '[]'::jsonb end)
  from cuentas c, riesgo r;
$$;

-- El siguiente día de trabajo de una persona después de una fecha (sin crear su jornada).
create or replace function motor.siguiente_dia_de_trabajo(p_persona uuid, p_fecha date)
returns date language sql stable set search_path = '' as $$
  select d::date from generate_series(p_fecha + 1, p_fecha + 14, interval '1 day') d
   where exists (select 1 from public.horarios h where h.persona_id = p_persona and h.dia_semana = extract(isodow from d))
     and not motor.dia_cerrado((select centro_id from public.personas where id = p_persona), d::date)
   order by d limit 1
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
  v_sin_alarma boolean;
  v_urgente boolean := coalesce(p_urgente, false);
  v_fecha_nueva date;
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
  -- Tarea 29: una no urgente y sin hora límite espera a lo primero de la mañana (§6.4): sin conflicto.
  v_sin_alarma := not v_urgente and v_limite is null;
  if not (v_conflicto ->> 'hay_conflicto')::boolean or v_sin_alarma then
    v_conflicto := null;
    if v_accion in ('nueva_manana', 'nueva_despues') then
      v_accion := null;  -- sin conflicto, la decisión no hace falta
    end if;
  elsif v_accion is null or v_accion not in ('no_crear', 'despues', 'manana', 'cancelar', 'nueva_manana', 'nueva_despues') then
    return motor.error('CONFLICTO', 'No cabe: decide qué hacer con la tarea nueva o qué cede.', jsonb_build_object('conflicto', v_conflicto));
  elsif v_accion in ('despues', 'manana', 'cancelar') then
    begin
      select * into v_cede from public.tareas where id = (p_decision ->> 'cede')::uuid;
    exception when others then
      v_cede := null;
    end;
    if v_cede.id is null or v_cede.jornada_id <> v_jornada or v_cede.estado not in ('pendiente', 'en_curso', 'bloqueada') then
      return motor.error('DATOS_NO_VALIDOS', 'Elige una de las tareas en riesgo para que ceda.',
                         jsonb_build_object('conflicto', v_conflicto));
    end if;
    -- Tarea 29: el reparto y el envío del día no se mueven ni se cancelan.
    if motor.es_del_reparto(v_cede.clave) then
      return motor.error('DATOS_NO_VALIDOS', '«' || v_cede.titulo || '» es del reparto o del envío de hoy: no se puede pasar a mañana, '
                         || 'dejar para después ni cancelar. Decide qué hacer con la tarea nueva.',
                         jsonb_build_object('conflicto', v_conflicto, 'cede', v_cede.id));
    end if;
  elsif v_accion = 'nueva_manana' then
    v_fecha_nueva := motor.siguiente_dia_de_trabajo(v_persona, v_fecha);
    if v_fecha_nueva is null then
      return motor.error('SIN_JORNADA', 'No tiene ningún día de trabajo próximo.', jsonb_build_object('conflicto', v_conflicto));
    end if;
  end if;

  v_encaje := case
    when v_accion = 'nueva_manana' then 'Para el ' || to_char(v_fecha_nueva, 'DD/MM') || ': '
      || case when v_urgente then 'urgente, entra en cuanto termine lo que esté haciendo.'
              when v_limite is not null then 'antes de las ' || motor.hora_texto(v_limite) || ', después de lo que tiene hora.'
              else 'cuando termine lo del reparto, las obligatorias y lo que tiene hora.' end
    when v_accion = 'nueva_despues' then 'Después de lo que está en riesgo: cuando termine lo del reparto, las obligatorias y lo que tiene hora (sin hora límite).'
    when v_urgente then 'Urgente: entra en cuanto termine lo que está haciendo (la referencia o la tienda en curso).'
    when v_limite is not null then 'Antes de las ' || motor.hora_texto(v_limite) || ', después de lo que tiene hora.'
    else 'Cuando termine lo del reparto, las obligatorias y lo que tiene hora.' end
    || case when v_fecha <> v_hoy and v_accion is distinct from 'nueva_manana' then ' El ' || to_char(v_fecha, 'DD/MM') || '.' else '' end
    -- Sin conflicto se crea igualmente; se avisa de lo que no le da tiempo.
    || case when v_conflicto is null and v_faltan > 0
            then ' No le da tiempo entera (faltan unos ' || v_faltan || ' min): lo que no termine pasa al día siguiente.'
            else '' end;

  if not coalesce(p_confirmar, false) then
    return jsonb_build_object('tarea_id', null, 'comprobado', true, 'encaje', v_encaje, 'conflicto', v_conflicto,
                              'minutos_que_faltan', v_faltan);
  end if;

  if v_accion = 'no_crear' and v_conflicto is not null then
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, null,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', 'no_crear', 'que', btrim(p_que), 'conflicto', v_conflicto));
    return jsonb_build_object('tarea_id', null, 'creada', false, 'decision', 'no_crear', 'conflicto', v_conflicto);
  end if;

  -- Tarea 29: la tarea nueva, para el siguiente día de trabajo o sin hora límite ni urgencia.
  if v_accion = 'nueva_manana' then
    v_jornada := motor.jornada_para(v_persona, v_fecha_nueva, p_ahora);
    if v_jornada is null then
      return motor.error('SIN_JORNADA', 'No tiene ningún día de trabajo próximo.', jsonb_build_object('conflicto', v_conflicto));
    end if;
    v_limite := case when v_limite is not null then motor.en_local(v_fecha_nueva, v_hora) end;
  elsif v_accion = 'nueva_despues' then
    v_limite := null;
    v_urgente := false;
  end if;

  -- No urgente y sin hora límite: después de lo primero de la mañana (lo decide motor.elegir_tarea).
  insert into public.tareas (jornada_id, clave, origen, titulo, porque, obligatoria, disponible_desde, hora_limite,
                             urgente, duracion_min, no_terminada, orden, creada_por, id_cliente)
  values (v_jornada, 'admin:' || p_id_cliente, 'administracion', btrim(p_que), nullif(btrim(p_porque), ''), false,
          case when v_accion = 'nueva_manana' then motor.inicio_turno(v_persona, v_fecha_nueva, null)
               when v_fecha = v_hoy then p_ahora else motor.inicio_turno(v_persona, v_fecha, null) end, v_limite,
          v_urgente, p_duracion_min, 'arrastrar', 50, p_admin, p_id_cliente)
  returning id into v_id;
  perform motor.registrar('tarea_creada', p_admin, v_jornada, v_id,
    jsonb_build_object('origen', 'administracion', 'urgente', v_urgente, 'duracion_min', p_duracion_min,
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
    elsif v_accion = 'cancelar' then
      update public.tareas set estado = 'cancelada',
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: cancelada por Administración'
       where id = v_cede.id;
    end if;
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, v_cede.id,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', v_accion, 'cede', v_cede.id, 'cede_titulo', v_cede.titulo,
                         'nueva', v_id, 'fecha_nueva', v_fecha_nueva, 'conflicto', v_conflicto));
  end if;

  return jsonb_build_object('tarea_id', v_id, 'tarea', motor.tarea_json(v_id), 'encaje', v_encaje,
                            'conflicto', v_conflicto, 'minutos_que_faltan', v_faltan,
                            'decision', case when v_conflicto is not null then
                                          jsonb_build_object('cede', v_cede.id, 'titulo', v_cede.titulo, 'accion', v_accion,
                                                             'fecha', v_fecha_nueva) end);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Avisos del almacén a las tiendas
-- ---------------------------------------------------------------------------
create or replace function motor.aviso_tienda_json(p_incidencia uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', i.id, 'fecha', motor.fecha_local(i.iniciada_en), 'texto', i.descripcion,
                            'tienda_id', c.id, 'tienda', c.nombre, 'estado', i.estado,
                            'leido', i.estado = 'cerrada' and i.nota_cierre like 'Leído%', 'cerrado_en', i.terminada_en,
                            'nota', i.nota_cierre, 'creado_por', a.nombre,
                            -- Tarea 29: de quién viene.
                            'de', case when a.rol = 'operario' then 'Almacén' else 'Administración' end)
  from public.incidencias i
  join public.personas p on p.id = i.persona_id
  join public.centros_trabajo c on c.id = p.centro_id
  left join public.personas a on a.id = i.creada_por
  where i.id = p_incidencia and i.opcion = 'aviso';
$$;

create or replace function motor.tienda_hoy_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_dia integer := extract(isodow from v_hoy);
  pe public.personas;
  c public.centros_trabajo;
  v_jornada uuid;
  v_turno text;
  tt public.turnos_tienda;
begin
  select * into pe from public.personas where id = p_persona;
  select * into c from public.centros_trabajo where id = pe.centro_id;
  v_jornada := motor.generar_jornada(p_persona, v_hoy);
  -- Tarea 28: si ha salido el reparto y trae bolsa para esta tienda, «Recibe la bolsa».
  perform motor.preparar_bolsa_tienda(p_persona, v_jornada, p_ahora);
  v_turno := motor.turno_tienda_ahora(p_persona, p_ahora);
  tt := motor.en_turno_tienda(v_jornada);
  return jsonb_build_object(
    'tienda', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre),
    'fecha', v_hoy,
    'ahora', motor.hora_texto(p_ahora),
    'abierta_hoy', v_jornada is not null,
    'cerrado', motor.dia_cerrado(c.id, v_hoy),
    'horario', coalesce((select jsonb_agg(jsonb_build_object('turno', h.turno, 'inicio', to_char(h.hora_inicio, 'HH24:MI'),
                                                             'fin', to_char(h.hora_fin, 'HH24:MI')) order by h.hora_inicio)
                           from public.horarios h where h.persona_id = p_persona and h.dia_semana = v_dia), '[]'::jsonb),
    'turno', v_turno,
    'en_turno', case when tt.id is not null then
      jsonb_build_object('persona_id', tt.persona_tienda_id, 'nombre', tt.nombre, 'turno', tt.turno,
                         'desde', motor.hora_texto(tt.empezado_en)) end,
    'personas', coalesce((
      select jsonb_agg(x.o order by x.sugerida desc, x.nombre)
        from (select pt.nombre,
                     (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                     and (pt.turno is null or v_turno is null or pt.turno = v_turno) as sugerida,
                     jsonb_build_object('id', pt.id, 'nombre', pt.nombre, 'cuando', pt.cuando, 'turno', pt.turno,
                       'sugerida', (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                                   and (pt.turno is null or v_turno is null or pt.turno = v_turno)) as o
                from public.personas_tienda pt where pt.centro_id = c.id and pt.activo) x), '[]'::jsonb),
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'fecha', motor.fecha_local(i.iniciada_en),
                                          -- Tarea 29: de quién viene («Almacén» o «Administración»).
                                          'de', case when a.rol = 'operario' then 'Almacén' else 'Administración' end)
                       order by i.iniciada_en)
        from public.incidencias i left join public.personas a on a.id = i.creada_por
       where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'tareas', coalesce((
      select jsonb_agg(motor.tarea_tienda_json(t.id, p_ahora) order by t.disponible_desde, t.orden, t.creada_en)
        from public.tareas t where t.jornada_id = v_jornada and not t.retirada_por_condicion), '[]'::jsonb),
    -- Tarea 28: por dónde va el reparto, las peticiones (muestras y material) y si puede pedir material.
    'reparto', motor.seguimiento_reparto_json(c.id, v_hoy, p_ahora),
    'peticiones', motor.peticiones_tienda_json(c.id, p_ahora),
    'pedir_material', coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                                 where k.clave = 'pedir_material' and k.centro_id = c.id), false));
end;
$$;

-- Administración y, desde la Tarea 29, el operario mandan avisos a las tiendas (el operario, solo eso).
create or replace function motor.api_crear_aviso_tienda(p_id_cliente uuid, p_fecha date, p_texto text, p_tienda_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if not (motor.es_admin() or exists (select 1 from public.personas where id = auth.uid() and activo and rol = 'operario')) then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  return motor.crear_aviso_tienda_de(auth.uid(), p_id_cliente, p_fecha, p_texto, p_tienda_id, now());
end; $$;

-- Las tiendas, para elegir a cuál mandar un aviso (Administración y el operario).
create or replace function motor.api_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if motor.es_tienda() then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  return jsonb_build_object('tiendas', coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre) order by c.nombre)
      from public.centros_trabajo c where c.tipo = 'tienda' and c.activo), '[]'::jsonb));
end; $$;

create or replace function public.tiendas()
returns jsonb language sql set search_path = '' as $$ select motor.api_tiendas() $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_crear_aviso_tienda(uuid, date, text, uuid), motor.api_tiendas() to authenticated;
revoke execute on function public.tiendas() from public, anon;
grant execute on function public.tiendas() to authenticated;
