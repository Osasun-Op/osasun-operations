-- Tarea 4 · Tareas de Administración con detección de conflictos (PLAN_TECNICO.md §2.4),
-- cancelar tarea, estado actual, cierre por turno (D2) enviado por correo (D3)
-- y las funciones que usa el servidor para enviar cada correo una sola vez.

-- Duraciones (§6.10) --------------------------------------------------------------
-- producción = cajas que faltan × 1 min; bolsas = 3 min por tienda pendiente;
-- el resto, su duración (recuento 15, limpieza 30, ruta ~2 h, Administración la
-- orientativa). Sin duración: 0.
create or replace function motor.duracion_estimada(p_tarea uuid)
returns integer
language sql stable
set search_path = ''
as $$
  select case
    when t.contenido in ('produccion_reparto', 'stock_35') and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id) then
      (select coalesce(sum(greatest(e.cantidad - e.cantidad_hecha, 0)), 0)
         from public.tarea_elementos e where e.tarea_id = t.id and e.estado <> 'hecho')
      * coalesce((select (valor #>> '{}')::int from public.configuracion where clave = 'duracion_min_por_caja' and centro_id is null), 1)
    when t.contenido = 'bolsas' and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id) then
      (select count(distinct e.destino_id) from public.tarea_elementos e where e.tarea_id = t.id and e.estado <> 'hecho')::int
      * coalesce((select (valor #>> '{}')::int from public.configuracion where clave = 'duracion_min_por_bolsa' and centro_id is null), 3)
    else coalesce(t.duracion_min, 0)
  end
  from public.tareas t where t.id = p_tarea;
$$;

-- Conflicto (§2.4) -----------------------------------------------------------------
-- disponible = minutos de turno en la ventana − bloques fijos (ruta del reparto, Nacex)
-- necesario  = obligatorias y de Administración pendientes que vencen antes del final
--              de la ventana + la nueva
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
  vencen as (
    select t.id, t.titulo, t.obligatoria, t.origen, coalesce(t.hora_limite, t.hora_programada) as vence,
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
           (coalesce((select sum(minutos) from vencen), 0) + p_nueva)::int as necesario)
  select jsonb_build_object(
    'hay_conflicto', c.necesario > c.disponible,
    'disponible_min', c.disponible,
    'necesario_min', c.necesario,
    'minutos_que_faltan', greatest(c.necesario - c.disponible, 0),
    'obligatorias_en_riesgo', case when c.necesario > c.disponible then coalesce((
       select jsonb_agg(jsonb_build_object('tarea_id', v.id, 'titulo', v.titulo, 'vence', motor.hora_texto(v.vence),
                                           'duracion_min', v.minutos, 'origen', v.origen) order by v.vence, v.titulo)
         from vencen v where v.minutos > 0), '[]'::jsonb) else '[]'::jsonb end)
  from cuentas c;
$$;

-- Crear tarea de Administración (CONTRATOS.md §4.1) ---------------------------------
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
  v_encaje := case
    when coalesce(p_urgente, false) then 'Urgente: entra en cuanto termine lo que está haciendo (la referencia o la tienda en curso).'
    when v_limite is not null then 'Antes de las ' || motor.hora_texto(v_limite) || ', después de lo que tiene hora.'
    else 'Cuando termine las obligatorias y lo que tiene hora.' end
    || case when v_fecha <> v_hoy then ' El ' || to_char(v_fecha, 'DD/MM') || '.' else '' end;

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
    return jsonb_build_object('tarea_id', null, 'comprobado', true, 'encaje', v_encaje, 'conflicto', v_conflicto);
  end if;

  if v_accion = 'no_crear' and v_conflicto is not null then
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, null,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', 'no_crear', 'que', btrim(p_que), 'conflicto', v_conflicto));
    return jsonb_build_object('tarea_id', null, 'creada', false, 'decision', 'no_crear', 'conflicto', v_conflicto);
  end if;

  insert into public.tareas (jornada_id, clave, origen, titulo, porque, obligatoria, disponible_desde, hora_limite,
                             urgente, duracion_min, no_terminada, orden, creada_por, id_cliente)
  values (v_jornada, 'admin:' || p_id_cliente, 'administracion', btrim(p_que), nullif(btrim(p_porque), ''), false,
          case when v_fecha = v_hoy then p_ahora else motor.inicio_turno(v_persona, v_fecha, null) end, v_limite,
          coalesce(p_urgente, false), p_duracion_min, 'arrastrar', 50, p_admin, p_id_cliente)
  returning id into v_id;
  perform motor.registrar('tarea_creada', p_admin, v_jornada, v_id,
    jsonb_build_object('origen', 'administracion', 'urgente', coalesce(p_urgente, false), 'duracion_min', p_duracion_min,
                       'conflicto', v_conflicto is not null));

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
                            'conflicto', v_conflicto,
                            'decision', case when v_conflicto is not null then
                                          jsonb_build_object('cede', v_cede.id, 'titulo', v_cede.titulo, 'accion', v_accion) end);
end;
$$;

-- Cancelar tarea (CONTRATOS.md §4.2) ------------------------------------------------
create or replace function motor.cancelar_tarea_de(p_admin uuid, p_tarea uuid, p_motivo text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
begin
  select * into t from public.tareas where id = p_tarea for update;
  if t.id is null then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado = 'cancelada' and not t.retirada_por_condicion then
    return jsonb_build_object('tarea', motor.tarea_json(t.id), 'aviso',
                              jsonb_build_object('codigo', 'YA_CANCELADA', 'mensaje', 'Esta tarea ya estaba cancelada.'));
  end if;
  if nullif(btrim(p_motivo), '') is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el motivo.');
  end if;
  if t.estado not in ('pendiente', 'en_curso', 'bloqueada') then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea ya no se puede cancelar.', jsonb_build_object('estado', t.estado));
  end if;
  update public.tareas set estado = 'cancelada', motivo_no_hecha = btrim(p_motivo) where id = t.id;
  update public.tarea_elementos set estado = 'pendiente' where tarea_id = t.id and estado = 'en_curso';
  -- Si tenía un problema abierto, deja de hacer falta llamar.
  update public.tareas o set estado = 'cancelada', motivo_no_hecha = 'Ya no hace falta: tarea cancelada'
    from public.problemas p
   where p.tarea_id = t.id and p.estado <> 'resuelto'
     and o.jornada_id = p.jornada_id and o.clave like 'problema:' || p.id || ':%' and o.estado = 'pendiente';
  perform motor.registrar('tarea_cancelada', p_admin, t.jornada_id, t.id,
                          jsonb_build_object('motivo', btrim(p_motivo), 'a_las', p_ahora, 'estado_antes', t.estado));
  return jsonb_build_object('tarea', motor.tarea_json(t.id));
end;
$$;

-- Estado actual (CONTRATOS.md §4.3) -------------------------------------------------
-- Solo lee: no genera jornadas.
create or replace function motor.estado_actual_de(p_ahora timestamptz)
returns jsonb
language sql stable
set search_path = ''
as $$
  with op as (select id, nombre from public.personas where id = motor.operario_por_defecto()),
  j as (select jo.* from public.jornadas jo join op on op.id = jo.persona_id where jo.fecha = motor.fecha_local(p_ahora))
  select jsonb_build_object(
    'ahora', motor.hora_texto(p_ahora),
    'fecha', motor.fecha_local(p_ahora),
    'operario', (select jsonb_build_object('id', op.id, 'nombre', op.nombre) from op),
    'jornada', (select jsonb_build_object('id', j.id, 'sale', j.sale, 'hay_envio', j.hay_envio, 'estado', j.estado) from j),
    'en_curso', (select motor.tarea_json(t.id) from public.tareas t join j on j.id = t.jornada_id where t.estado = 'en_curso'),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.estado <> 'resuelto' and p.persona_id = (select id from op)), '[]'::jsonb),
    'incidencia_en_curso', (
      select jsonb_build_object('id', i.id, 'descripcion', i.descripcion, 'desde', motor.hora_texto(i.iniciada_en),
                                'minutos', round(extract(epoch from (p_ahora - i.iniciada_en)) / 60)::int)
        from public.incidencias i where i.persona_id = (select id from op) and i.terminada_en is null),
    'arrastradas', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado) order by t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id where t.tarea_origen_id is not null), '[]'::jsonb),
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado, 'origen', t.origen,
                                          'obligatoria', t.obligatoria, 'urgente', t.urgente,
                                          'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)),
                                          'motivo', t.motivo_no_hecha)
                       order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id
       where not t.retirada_por_condicion and t.origen <> 'problema'), '[]'::jsonb),
    'retrasos_salida', coalesce((
      select jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                          'minutos', (r.datos ->> 'minutos')::int, 'nueva_hora', r.datos ->> 'nueva_hora',
                                          'sale', r.datos ->> 'sale', 'aviso', r.datos ->> 'aviso') order by r.id)
        from public.registro_eventos r join j on j.id = r.jornada_id where r.tipo = 'salida_retrasada'), '[]'::jsonb),
    'lectura_sheets', jsonb_build_object(
      'ultima_correcta', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo)
                            from public.lecturas_sheets l where l.correcto order by l.leido_en desc limit 1),
      'ultimo_error', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo, 'error', l.error)
                         from public.lecturas_sheets l where not l.correcto
                          and l.leido_en > coalesce((select max(k.leido_en) from public.lecturas_sheets k where k.correcto), '-infinity')
                         order by l.leido_en desc limit 1)));
$$;

-- Cierre por turno (D2) --------------------------------------------------------------
-- Turno de una tarea: el de su plantilla; si no, por su hora; sin hora, de todo el día (null).
create or replace function motor.turno_de_tarea(p_tarea uuid)
returns text
language sql stable
set search_path = ''
as $$
  select coalesce(p.turno,
                  case when coalesce(t.hora_limite, t.hora_programada) is null then null
                       when coalesce(t.hora_limite, t.hora_programada) >= motor.inicio_turno(j.persona_id, j.fecha, 'tarde')
                         then 'tarde' else 'manana' end)
  from public.tareas t
  join public.jornadas j on j.id = t.jornada_id
  left join public.plantillas_tarea p on p.id = t.plantilla_id
  where t.id = p_tarea;
$$;

create or replace function motor.contenido_cierre(p_jornada uuid, p_turno text, p_ahora timestamptz)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  j public.jornadas;
  v_desde timestamptz;
  v_ultimo boolean;
  v_primero boolean;
  v_siguiente date;
  v_no_hecho jsonb;
  v_retrasos jsonb;
  v_cruce jsonb;
begin
  select * into j from public.jornadas where id = p_jornada;
  v_desde := coalesce((select max(generado_en) from public.cierres where jornada_id = j.id and turno <> p_turno), '-infinity');
  v_ultimo := p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                          and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio desc limit 1);
  v_primero := p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                           and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio limit 1);

  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'estado', t.estado,
           'motivo', coalesce(t.motivo_no_hecha,
                              case t.estado when 'bloqueada' then 'Bloqueada por un problema sin resolver'
                                            when 'en_curso' then 'Se quedó a medias'
                                            else 'Sin motivo anotado' end),
           'pasa_a_manana', v_ultimo and t.estado <> 'cancelada' and t.no_terminada in ('arrastrar', 'sigue_abierta'))
         order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden), '[]'::jsonb)
    into v_no_hecho
    from public.tareas t
   where t.jornada_id = j.id and not t.retirada_por_condicion and t.origen <> 'problema'
     and (t.obligatoria or t.origen = 'administracion')
     and t.estado in ('pendiente', 'en_curso', 'bloqueada', 'cancelada')
     and t.disponible_desde <= p_ahora
     and (motor.turno_de_tarea(t.id) = p_turno or (motor.turno_de_tarea(t.id) is null and v_ultimo));

  if p_turno = 'manana' then
    select coalesce(jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                                 'minutos', (r.datos ->> 'minutos')::int,
                                                 'nueva_hora', r.datos ->> 'nueva_hora', 'sale', r.datos ->> 'sale')
                              order by r.id), '[]'::jsonb)
      into v_retrasos
      from public.registro_eventos r where r.jornada_id = j.id and r.tipo = 'salida_retrasada';
    if jsonb_array_length(v_retrasos) > 0 then
      v_cruce := jsonb_build_object(
        'cajas_reparto', (select coalesce(sum((x ->> 'pedido')::int), 0)
                            from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                           where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
        'cajas_a_producir', (select coalesce(sum(e.cantidad), 0) from public.tarea_elementos e
                               join public.tareas t on t.id = e.tarea_id
                              where t.jornada_id = j.id and t.clave = 'produccion_reparto'),
        'cajas_producidas', (select coalesce(sum(e.cantidad_hecha), 0) from public.tarea_elementos e
                               join public.tareas t on t.id = e.tarea_id
                              where t.jornada_id = j.id and t.clave = 'produccion_reparto'),
        'tiendas', (select count(distinct e.destino_id) from public.tarea_elementos e
                      join public.tareas t on t.id = e.tarea_id
                     where t.jornada_id = j.id and t.clave = 'bolsas'),
        'incidencias_manana', (select count(*) from public.incidencias i
                                where i.jornada_id = j.id and i.iniciada_en <= p_ahora),
        'minutos_incidencias_manana', (select coalesce(round(sum(extract(epoch from (coalesce(i.terminada_en, p_ahora) - i.iniciada_en)) / 60)), 0)::int
                                         from public.incidencias i where i.jornada_id = j.id and i.iniciada_en <= p_ahora));
    end if;
  end if;

  v_siguiente := (select min(d)::date from generate_series(j.fecha + 1, j.fecha + 7, interval '1 day') d
                   where exists (select 1 from public.horarios h where h.persona_id = j.persona_id
                                   and h.dia_semana = extract(isodow from d)));

  return jsonb_build_object(
    'fecha', j.fecha,
    'turno', p_turno,
    'operario', (select nombre from public.personas where id = j.persona_id),
    'sale', j.sale,
    'hay_envio', j.hay_envio,
    'generado_en', p_ahora,
    'hecho', coalesce((
      select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'resultado', t.resultado,
                                          'hora', motor.hora_texto(t.terminada_en), 'origen', t.origen)
                       order by t.terminada_en)
        from public.tareas t
       where t.jornada_id = j.id and t.estado = 'hecha' and t.origen <> 'problema'
         and t.terminada_en > v_desde and t.terminada_en <= p_ahora), '[]'::jsonb),
    'no_hecho', v_no_hecho,
    'problemas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tarea', t.titulo, 'tipo', p.tipo, 'descripcion', p.descripcion, 'abierto', motor.hora_texto(p.abierto_en),
               'estado', p.estado, 'solucion', p.solucion, 'llamadas', p.llamadas,
               'minutos', round(extract(epoch from (coalesce(p.resuelto_en, p_ahora) - p.abierto_en)) / 60)::int,
               'mas_de_5_min', coalesce(p.resuelto_en, p_ahora) - p.abierto_en > interval '5 minutes')
             order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.jornada_id = j.id and p.abierto_en <= p_ahora
         and (p.abierto_en > v_desde or p.resuelto_en > v_desde or p.resuelto_en is null)), '[]'::jsonb),
    'incidencias', coalesce((
      select jsonb_agg(jsonb_build_object(
               'descripcion', i.descripcion, 'tarea', t.titulo, 'inicio', motor.hora_texto(i.iniciada_en),
               'fin', motor.hora_texto(i.terminada_en),
               'minutos', round(extract(epoch from (coalesce(i.terminada_en, p_ahora) - i.iniciada_en)) / 60)::int)
             order by i.iniciada_en)
        from public.incidencias i left join public.tareas t on t.id = i.tarea_id
       where i.jornada_id = j.id and i.iniciada_en <= p_ahora
         and (i.iniciada_en > v_desde or i.terminada_en > v_desde or i.terminada_en is null)), '[]'::jsonb),
    'arrastrados', jsonb_build_object(
      'llegaron', case when v_primero then coalesce((
          select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'estado', t.estado) order by t.orden)
            from public.tareas t where t.jornada_id = j.id and t.tarea_origen_id is not null), '[]'::jsonb) end,
      'pasan_a_manana', case when v_ultimo then coalesce((
          select jsonb_agg(t.titulo order by t.orden, t.creada_en) from public.tareas t
           where t.jornada_id = j.id and t.origen <> 'problema' and t.estado in ('pendiente', 'en_curso', 'bloqueada')
             and t.no_terminada in ('arrastrar', 'sigue_abierta')), '[]'::jsonb) end),
    'retrasos_salida', v_retrasos,
    'cruce_retrasos', v_cruce,
    'siguiente', case
      when not v_ultimo then jsonb_build_object('turno', 'tarde', 'tareas', coalesce((
          select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)))
                           order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden)
            from public.tareas t
           where t.jornada_id = j.id and t.estado = 'pendiente' and not t.retirada_por_condicion
             and (t.obligatoria or t.origen = 'administracion') and motor.turno_de_tarea(t.id) = 'tarde'), '[]'::jsonb))
      when v_siguiente is not null then jsonb_build_object('fecha', v_siguiente, 'tareas', coalesce((
          select jsonb_agg(x.titulo order by x.h nulls last, x.orden) from (
            select p.titulo, p.hora_inicio as h, p.orden from public.plantillas_tarea p
             where p.activa and p.centro_id = j.centro_id and p.programacion in ('con_hora', 'dia_semana')
               and p.condicion is null and p.obligatoria
               and extract(isodow from v_siguiente)::smallint = any (p.dias_semana)
            union all
            select t.titulo, t.hora_limite::time, t.orden from public.tareas t
              join public.jornadas s on s.id = t.jornada_id
             where s.persona_id = j.persona_id and s.fecha = v_siguiente and t.origen = 'administracion'
               and t.estado = 'pendiente') x), '[]'::jsonb))
    end,
    'calidad', case when extract(isodow from j.fecha) = 5 and v_ultimo then
      jsonb_build_object('limpieza_viernes',
                         exists (select 1 from public.tareas t join public.plantillas_tarea p on p.id = t.plantilla_id
                                  where t.jornada_id = j.id and p.codigo = 'limpieza_resinas' and t.estado = 'hecha')) end);
end;
$$;

-- Una lista JSON o, si no lo es (null), la lista vacía.
create or replace function motor.como_lista(p jsonb)
returns jsonb
language sql immutable
set search_path = ''
as $$ select case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end $$;

-- Texto del correo del cierre.
create or replace function motor.texto_cierre(c jsonb)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_fecha date := (c ->> 'fecha')::date;
  v_dia text := (array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'])[extract(isodow from v_fecha)];
  v_turno text := case c ->> 'turno' when 'manana' then 'mañana' else 'tarde' end;
  t text;
  x jsonb;
begin
  t := 'Cierre del turno de ' || v_turno || ' · ' || v_dia || ' ' || to_char(v_fecha, 'DD/MM')
       || coalesce(' · ' || (c ->> 'operario'), '') || E'\n';

  t := t || E'\nHECHO\n';
  if jsonb_array_length(c -> 'hecho') = 0 then t := t || E'- Nada\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'hecho') loop
    t := t || '- ' || (x ->> 'hora') || ' ' || (x ->> 'titulo') || coalesce(' → ' || (x ->> 'resultado'), '') || E'\n';
  end loop;

  t := t || E'\nNO HECHO\n';
  if jsonb_array_length(c -> 'no_hecho') = 0 then t := t || E'- Nada\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'no_hecho') loop
    t := t || '- ' || (x ->> 'titulo') || ': ' || (x ->> 'motivo')
         || case when (x ->> 'pasa_a_manana')::boolean then ' (pasa al día siguiente)' else '' end || E'\n';
  end loop;

  t := t || E'\nPROBLEMAS\n';
  if jsonb_array_length(c -> 'problemas') = 0 then t := t || E'- Ninguno\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'problemas') loop
    t := t || '- ' || (x ->> 'abierto') || ' ' || (x ->> 'tarea') || ': ' || (x ->> 'descripcion')
         || ' · ' || (x ->> 'minutos') || ' min'
         || case when (x ->> 'mas_de_5_min')::boolean then ' (más de 5 min)' else '' end
         || coalesce(' · Solución: ' || (x ->> 'solucion'), ' · Sin resolver') || E'\n';
  end loop;

  t := t || E'\nINCIDENCIAS\n';
  if jsonb_array_length(c -> 'incidencias') = 0 then t := t || E'- Ninguna\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'incidencias') loop
    t := t || '- ' || (x ->> 'inicio') || ' ' || (x ->> 'descripcion') || ' · ' || (x ->> 'minutos') || ' min'
         || case when x ->> 'fin' is null then ' (sigue abierta)' else '' end || E'\n';
  end loop;

  if jsonb_array_length(motor.como_lista(c -> 'arrastrados' -> 'llegaron')) > 0 then
    t := t || E'\nARRASTRADAS DE DÍAS ANTERIORES\n';
    for x in select * from jsonb_array_elements(c -> 'arrastrados' -> 'llegaron') loop
      t := t || '- ' || (x ->> 'titulo') || ' (' || (x ->> 'estado') || E')\n';
    end loop;
  end if;

  if jsonb_array_length(motor.como_lista(c -> 'arrastrados' -> 'pasan_a_manana')) > 0 then
    t := t || E'\nPASAN AL DÍA SIGUIENTE\n';
    for x in select * from jsonb_array_elements(c -> 'arrastrados' -> 'pasan_a_manana') loop
      t := t || '- ' || (x #>> '{}') || E'\n';
    end loop;
  end if;

  if jsonb_array_length(motor.como_lista(c -> 'retrasos_salida')) > 0 then
    t := t || E'\nRETRASOS DE LA SALIDA\n';
    for x in select * from jsonb_array_elements(c -> 'retrasos_salida') loop
      t := t || '- ' || (x ->> 'a_las') || ': +' || (x ->> 'minutos') || ' min, salida a las ' || (x ->> 'nueva_hora') || E'\n';
    end loop;
    t := t || '  Reparto: ' || (c -> 'cruce_retrasos' ->> 'cajas_reparto') || ' cajas pedidas, '
         || (c -> 'cruce_retrasos' ->> 'cajas_a_producir') || ' a producir ('
         || (c -> 'cruce_retrasos' ->> 'cajas_producidas') || ' hechas), '
         || (c -> 'cruce_retrasos' ->> 'tiendas') || ' tiendas. Incidencias de la mañana: '
         || (c -> 'cruce_retrasos' ->> 'incidencias_manana') || ' ('
         || (c -> 'cruce_retrasos' ->> 'minutos_incidencias_manana') || E' min).\n';
  end if;

  if c -> 'siguiente' is not null and c -> 'siguiente' <> 'null'::jsonb then
    t := t || case when c -> 'siguiente' ? 'fecha'
                   then E'\nLO QUE TOCA EL ' || to_char((c -> 'siguiente' ->> 'fecha')::date, 'DD/MM') || E'\n'
                   else E'\nLO QUE QUEDA PARA LA TARDE\n' end;
    for x in select * from jsonb_array_elements(c -> 'siguiente' -> 'tareas') loop
      t := t || '- ' || case when jsonb_typeof(x) = 'string' then x #>> '{}'
                             else coalesce((x ->> 'hora') || ' ', '') || (x ->> 'titulo') end || E'\n';
    end loop;
  end if;

  if c -> 'calidad' is not null and c -> 'calidad' <> 'null'::jsonb then
    t := t || E'\nCALIDAD DEL VIERNES\n- Limpieza hecha: '
         || case when (c -> 'calidad' ->> 'limpieza_viernes')::boolean then 'sí' else 'no' end || E'\n';
  end if;

  return jsonb_build_object(
    'asunto', 'Cierre ' || v_turno || ' · ' || v_dia || ' ' || to_char(v_fecha, 'DD/MM')
              || ' · Hecho: ' || jsonb_array_length(c -> 'hecho') || ' · Sin hacer: ' || jsonb_array_length(c -> 'no_hecho'),
    'texto', t);
end;
$$;

-- Genera (una sola vez) el cierre de un turno y lo envía por correo.
create or replace function motor.generar_cierre(p_jornada uuid, p_turno text, p_ahora timestamptz)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_ultimo boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('cierre:' || p_jornada || ':' || p_turno, 0));
  select id into v_id from public.cierres where jornada_id = p_jornada and turno = p_turno;
  if v_id is not null then
    return v_id;
  end if;
  insert into public.cierres (jornada_id, turno, contenido, generado_en)
  values (p_jornada, p_turno, motor.contenido_cierre(p_jornada, p_turno, p_ahora), p_ahora)
  returning id into v_id;

  select p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                     and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio desc limit 1)
    into v_ultimo from public.jornadas j where j.id = p_jornada;
  if v_ultimo then
    update public.jornadas set estado = 'cerrada' where id = p_jornada;
  end if;
  perform motor.registrar('cierre_generado', null, p_jornada, null, jsonb_build_object('cierre', v_id, 'turno', p_turno));
  perform motor.encolar_correo('cierre', v_id::text);
  return v_id;
end;
$$;

-- Tarea programada: cierra los turnos de hoy que ya han terminado (13:00 y 18:30
-- de lunes a jueves, 13:00 el viernes, según el horario). pg_cron va en UTC: se
-- lanza a y media y en punto de 11, 12, 16 y 17 UTC (verano e invierno).
create or replace function motor.generar_cierres_programados(p_ahora timestamptz)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select j.id, h.turno
      from public.jornadas j
      join public.personas p on p.id = j.persona_id and p.activo
      join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
     where j.fecha = motor.fecha_local(p_ahora)
       and motor.en_local(j.fecha, h.hora_fin) <= p_ahora
       and not exists (select 1 from public.cierres c where c.jornada_id = j.id and c.turno = h.turno)
     order by h.hora_inicio
  loop
    perform motor.generar_cierre(r.id, r.turno, p_ahora);
    n := n + 1;
  end loop;
  return n;
end;
$$;

select cron.schedule(
  'generar_cierres_turno',
  '0,30 11,12,16,17 * * 1-5',
  $$select motor.generar_cierres_programados(now())$$
);

-- Correo: lo usa solo la función del servidor enviar_correo ---------------------------
-- Reclama el envío una sola vez (nunca dos correos del mismo cierre o aviso) y
-- devuelve el destino, el asunto y el texto. El destino está en configuracion
-- (correo_administracion), solo en el entorno, nunca en el repositorio.
create or replace function public.servidor_correo_reclamar(p_tipo text, p_ref text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_destino text := (select valor #>> '{}' from public.configuracion where clave = 'correo_administracion' and centro_id is null);
  v_remitente text := (select valor #>> '{}' from public.configuracion where clave = 'correo_remitente' and centro_id is null);
  c public.cierres;
  r public.registro_eventos;
  v_texto jsonb;
begin
  if v_destino is null then
    return motor.error('SIN_DESTINO', 'Falta el correo de Administración en la configuración.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('correo:' || p_tipo || ':' || p_ref, 0));
  if p_tipo = 'cierre' then
    update public.cierres set envio_reclamado_en = now()
     where id = p_ref::uuid and envio_reclamado_en is null
    returning * into c;
    if c.id is null then
      return jsonb_build_object('enviar', false, 'motivo', 'ya_reclamado');
    end if;
    v_texto := motor.texto_cierre(c.contenido);
  elsif p_tipo = 'retraso' then
    select * into r from public.registro_eventos where id = p_ref::bigint and tipo = 'salida_retrasada';
    if r.id is null then
      return motor.error('NO_ENCONTRADO', 'Ese aviso no existe.');
    end if;
    if exists (select 1 from public.registro_eventos where tipo = 'correo_reclamado'
                and datos ->> 'tipo' = 'retraso' and datos ->> 'ref' = p_ref) then
      return jsonb_build_object('enviar', false, 'motivo', 'ya_reclamado');
    end if;
    v_texto := jsonb_build_object(
      'asunto', 'Salida retrasada a las ' || (r.datos ->> 'nueva_hora'),
      'texto', 'El operario ha retrasado la salida del reparto ' || (r.datos ->> 'minutos') || ' minutos.' || E'\n'
               || 'Nueva hora de salida: ' || (r.datos ->> 'nueva_hora') || '.' || E'\n'
               || 'Aviso enviado a las ' || motor.hora_texto((r.datos ->> 'a_las')::timestamptz) || '.');
  else
    return motor.error('DATOS_NO_VALIDOS', 'Tipo de correo no válido.');
  end if;
  perform motor.registrar('correo_reclamado', null, coalesce(c.jornada_id, r.jornada_id), null,
                          jsonb_build_object('tipo', p_tipo, 'ref', p_ref));
  return jsonb_build_object('enviar', true, 'destino', v_destino, 'remitente', v_remitente,
                            'asunto', v_texto ->> 'asunto', 'texto', v_texto ->> 'texto');
end;
$$;

create or replace function public.servidor_correo_resultado(p_tipo text, p_ref text, p_ok boolean, p_detalle text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_jornada uuid;
begin
  if p_tipo = 'cierre' then
    update public.cierres
       set enviado_en = case when p_ok then now() end, canal = case when p_ok then 'correo' end,
           error_envio = case when p_ok then null else left(p_detalle, 500) end
     where id = p_ref::uuid
    returning jornada_id into v_jornada;
  else
    select jornada_id into v_jornada from public.registro_eventos where id = p_ref::bigint;
  end if;
  perform motor.registrar(case when p_ok then 'correo_enviado' else 'correo_fallido' end, null, v_jornada, null,
                          jsonb_build_object('tipo', p_tipo, 'ref', p_ref, 'detalle', left(p_detalle, 500)));
  return jsonb_build_object('ok', true);
end;
$$;

revoke execute on function public.servidor_correo_reclamar(text, text), public.servidor_correo_resultado(text, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.servidor_correo_reclamar(text, text), public.servidor_correo_resultado(text, text, boolean, text)
  to service_role;

-- API de Administración ---------------------------------------------------------------
create or replace function motor.api_crear_tarea_admin(
  p_id_cliente uuid, p_que text, p_cuando jsonb, p_duracion_min integer, p_para_quien uuid, p_urgente boolean,
  p_porque text, p_confirmar boolean, p_decision jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_tarea_admin_de(auth.uid(), p_id_cliente, p_que, p_para_quien, p_cuando, p_duracion_min,
                                    p_urgente, p_porque, p_confirmar, p_decision, now());
end; $$;

create or replace function motor.api_cancelar_tarea(p_tarea_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.cancelar_tarea_de(auth.uid(), p_tarea_id, p_motivo, now());
end; $$;

create or replace function motor.api_estado_actual()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.estado_actual_de(now());
end; $$;

create or replace function motor.api_cierre(p_cierre_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_error jsonb := motor.persona_actual('administracion');
  c public.cierres;
begin
  if v_error is not null then return v_error; end if;
  select * into c from public.cierres where id = p_cierre_id;
  if c.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese cierre no existe.');
  end if;
  return jsonb_build_object('id', c.id, 'fecha', c.contenido ->> 'fecha', 'turno', c.turno, 'generado_en', c.generado_en,
                            'enviado_en', c.enviado_en, 'canal', c.canal, 'contenido', c.contenido,
                            'texto', motor.texto_cierre(c.contenido) ->> 'texto');
end; $$;

create or replace function motor.api_cierres_recientes(p_limite integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return jsonb_build_object('cierres', coalesce((
    select jsonb_agg(x.o order by x.generado_en desc) from (
      select c.generado_en,
             jsonb_build_object('id', c.id, 'fecha', c.contenido ->> 'fecha', 'turno', c.turno,
                                'generado_en', c.generado_en, 'enviado_en', c.enviado_en,
                                'hechas', jsonb_array_length(c.contenido -> 'hecho'),
                                'sin_hacer', jsonb_array_length(c.contenido -> 'no_hecho'),
                                'problemas', jsonb_array_length(c.contenido -> 'problemas'),
                                'incidencias', jsonb_array_length(c.contenido -> 'incidencias')) as o
        from public.cierres c
       order by c.generado_en desc
       limit least(greatest(coalesce(p_limite, 10), 1), 50)) x), '[]'::jsonb));
end; $$;

create or replace function public.crear_tarea_admin(
  id_cliente uuid, que text, cuando jsonb, duracion_min integer, para_quien uuid default null,
  urgente boolean default false, porque text default null, confirmar boolean default false,
  decision_conflicto jsonb default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_crear_tarea_admin(id_cliente, que, cuando, duracion_min, para_quien, urgente, porque, confirmar, decision_conflicto) $$;
create or replace function public.cancelar_tarea(tarea_id uuid, motivo text)
returns jsonb language sql set search_path = '' as $$ select motor.api_cancelar_tarea(tarea_id, motivo) $$;
create or replace function public.estado_actual()
returns jsonb language sql set search_path = '' as $$ select motor.api_estado_actual() $$;
create or replace function public.cierre(cierre_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_cierre(cierre_id) $$;
create or replace function public.cierres_recientes(limite integer default 10)
returns jsonb language sql set search_path = '' as $$ select motor.api_cierres_recientes(limite) $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.es_admin(), motor.mi_centro(),
  motor.api_mi_perfil(), motor.api_tarea_activa(), motor.api_iniciar_tarea(uuid),
  motor.api_terminar_tarea(uuid, text, text), motor.api_anotar_motivo(uuid, text),
  motor.api_iniciar_elemento(uuid), motor.api_terminar_elemento(uuid), motor.api_marcar_cajas(uuid, integer),
  motor.api_abrir_problema(uuid, uuid, text, text), motor.api_problema_llamada(uuid, boolean),
  motor.api_resolver_problema(uuid, text), motor.api_iniciar_incidencia(uuid, text),
  motor.api_terminar_incidencia(uuid), motor.api_registrar_evento(uuid, text, text),
  motor.api_retrasar_salida(uuid, integer),
  motor.api_crear_tarea_admin(uuid, text, jsonb, integer, uuid, boolean, text, boolean, jsonb),
  motor.api_cancelar_tarea(uuid, text), motor.api_estado_actual(), motor.api_cierre(uuid),
  motor.api_cierres_recientes(integer)
to authenticated;

revoke execute on function
  public.crear_tarea_admin(uuid, text, jsonb, integer, uuid, boolean, text, boolean, jsonb),
  public.cancelar_tarea(uuid, text), public.estado_actual(), public.cierre(uuid), public.cierres_recientes(integer)
from public, anon;
grant execute on function
  public.crear_tarea_admin(uuid, text, jsonb, integer, uuid, boolean, text, boolean, jsonb),
  public.cancelar_tarea(uuid, text), public.estado_actual(), public.cierre(uuid), public.cierres_recientes(integer)
to authenticated;
