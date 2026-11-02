-- Tarea 23 (respuesta del propietario, 02/11/2026): la revisión inicial, «Prepara el
-- reparto», la producción, las bolsas y, el viernes, la preparación del envío son
-- siempre lo primero de la mañana. Mientras falte algo de eso, no sale ninguna otra
-- tarea, venga de donde venga (de Administración, de hoy o de antes, arrastrada,
-- +35 %, compras, incidencias…). Siguen entrando lo urgente (Administración urgente,
-- incidencia «ahora», mercancía), volver a llamar por un problema, lo que va a su hora
-- (la salida, Nacex, el recuento), las de Administración con hora límite y los pedidos
-- para recoger en tienda (van con las bolsas). En los huecos, «Orden y limpieza».
-- Solo cuenta en el turno de mañana: desde el comienzo de la tarde ya no frena nada.
--
-- Una sola regla en motor.elegir_tarea (vale también para lo que ya existe). Sustituye
-- al requisito que la migración 20261102095949 ponía solo a las tareas de Administración.
--
-- Deshacer: volver a crear motor.elegir_tarea (20261030095607) y motor.crear_tarea_admin_de
-- (20261102095949) como estaban y drop function motor.lo_primero_pendiente(uuid, timestamptz),
-- motor.va_antes_que_lo_primero(public.tareas).

-- ¿Falta algo de lo primero de la mañana? (lo que no hay ese día no hace esperar)
create or replace function motor.lo_primero_pendiente(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select not motor.requisitos_hechos(p_jornada, 'revision_inicial+pegar_reparto+produccion_reparto+bolsas+preparar_envio_viernes')
     and p_ahora < coalesce((select motor.inicio_turno(j.persona_id, j.fecha, 'tarde') from public.jornadas j where j.id = p_jornada),
                            'infinity')
$$;

-- Lo que puede salir aunque falte lo primero de la mañana.
create or replace function motor.va_antes_que_lo_primero(t public.tareas)
returns boolean language sql stable set search_path = '' as $$
  select t.urgente or t.origen = 'problema' or t.hora_programada is not null
      or (t.origen = 'administracion' and t.hora_limite is not null)
      or split_part(t.clave, ':', 1) = any (array['revision_inicial', 'pegar_reparto', 'produccion_reparto', 'bolsas',
                                                  'preparar_envio_viernes', 'pedido_tienda'])
$$;
revoke execute on function motor.lo_primero_pendiente(uuid, timestamptz), motor.va_antes_que_lo_primero(public.tareas) from public;

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
  -- Lo primero de la mañana (Tarea 23): mientras falte, no sale nada más que lo urgente,
  -- lo que va a su hora y lo que forma parte de ello.
  v_primero boolean := motor.lo_primero_pendiente(p_jornada, p_ahora);
begin
  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and (t.estado = 'en_curso'
         or (t.estado = 'pendiente'
             and t.disponible_desde <= p_ahora
             and t.prioridad_cola is distinct from 'D'
             and motor.requisitos_hechos(t.jornada_id, t.requiere_clave)
             and (not v_primero or motor.va_antes_que_lo_primero(t))))
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
    and not v_primero
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

  -- No urgente y sin hora límite: después de lo primero de la mañana (lo decide motor.elegir_tarea).
  insert into public.tareas (jornada_id, clave, origen, titulo, porque, obligatoria, disponible_desde, hora_limite,
                             urgente, duracion_min, no_terminada, orden, creada_por, id_cliente)
  values (v_jornada, 'admin:' || p_id_cliente, 'administracion', btrim(p_que), nullif(btrim(p_porque), ''), false,
          case when v_fecha = v_hoy then p_ahora else motor.inicio_turno(v_persona, v_fecha, null) end, v_limite,
          coalesce(p_urgente, false), p_duracion_min, 'arrastrar', 50, p_admin, p_id_cliente)
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

-- Las de Administración que ya llevaban el requisito de la migración anterior: ya no hace falta.
update public.tareas set requiere_clave = null
 where origen = 'administracion'
   and requiere_clave = 'revision_inicial+pegar_reparto+produccion_reparto+bolsas+preparar_envio_viernes';
