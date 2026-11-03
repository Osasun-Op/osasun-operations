-- Tarea 29b · El aviso de salida solo cuando toca (03/11/2026, 19:33: a Eder le salía por la tarde,
-- con las bolsas pasadas a mañana por error y el reparto salido a las 10:48). Solo en pruebas: espera
-- con las de tiendas (AGENTE_BASE_DE_DATOS.md §4).
--   1. tarea_activa().aviso_salida, solo si el reparto aún no ha salido (motor.salida_reparto_en, la
--      señal de la Tarea 28), el operario está en su turno (motor.en_turno) y las bolsas de hoy ya
--      están disponibles y han pasado su hora límite. Si no, null.
--   2. retrasar_salida: con el reparto ya fuera, ESTADO_NO_VALIDO («El reparto ya ha salido.») sin
--      mover ninguna hora.
--
-- Deshacer: volver a crear motor.tarea_activa_de como está en 20261103175352 y
-- motor.retrasar_salida_de como está en 20261028105848.

create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
as $$
declare
  v_jornada uuid;
  j public.jornadas;
  v_tarea uuid;
  v_sig uuid;
  v_prox uuid;
  s public.tareas;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return jsonb_build_object('jornada', null, 'pregunta', null, 'tarea', null, 'siguiente', null, 'reparto_de_hoy', null,
                              'aviso_salida', null)
           || motor.seguimiento_de(p_persona, p_ahora);
  end if;
  select * into j from public.jornadas where id = v_jornada;

  v_tarea := motor.elegir_tarea(v_jornada, p_ahora, null);
  -- Pedido de cliente: «coge / haz» al salir su tarea (una sola vez).
  if v_tarea is not null
     and exists (select 1 from public.pedidos_cliente where tarea_id = v_tarea)
     and not exists (select 1 from public.tarea_elementos where tarea_id = v_tarea and calculo ? 'calculado_en') then
    perform motor.calcular_pedido(v_tarea, p_ahora);
  end if;
  -- «Lo que viene después»: lo que tocaría sin la tarea actual; pero si antes
  -- llega una tarea con hora (o el siguiente turno), se muestra esa.
  v_sig := motor.elegir_tarea(v_jornada, p_ahora, v_tarea);
  select t.id into v_prox from public.tareas t
   where t.jornada_id = v_jornada and t.estado = 'pendiente'
     and t.disponible_desde > p_ahora and t.id is distinct from v_tarea
   order by t.disponible_desde, t.orden limit 1;
  if v_prox is not null
     and (v_sig is null
          or (select motor.escalon(t) > 4 from public.tareas t where t.id = v_sig)) then
    v_sig := v_prox;
  end if;
  select * into s from public.tareas where id = v_sig;

  return jsonb_build_object(
    'jornada', jsonb_build_object('id', j.id, 'fecha', j.fecha, 'sale', j.sale, 'hay_envio', j.hay_envio),
    'pregunta', null,
    'tarea', motor.tarea_json(v_tarea),
    'siguiente', case when v_sig is null then null else
      s.titulo || coalesce(' · ' || motor.hora_texto(coalesce(s.hora_programada,
                    case when s.disponible_desde > p_ahora then s.disponible_desde end)), '') end,
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r left join public.personas pe on pe.id = r.pegado_por
       where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
    -- Tarea 29: ha llegado la hora de salida y las bolsas no están: retrasar 15 o 30 min (retrasar_salida).
    -- Tarea 29b: solo si el reparto aún no ha salido, en el turno y con las bolsas ya disponibles.
    'aviso_salida', (
      select jsonb_build_object('texto', 'Es la hora de salida (' || motor.hora_texto(b.hora_limite)
                                         || ') y las bolsas no están listas: retrasa la salida.',
                                'hora_salida', motor.hora_texto(b.hora_limite), 'minutos', '[15, 30]'::jsonb)
        from public.tareas b
       where b.jornada_id = j.id and b.clave = 'bolsas' and b.estado in ('pendiente', 'en_curso', 'bloqueada')
         and b.hora_limite is not null and b.hora_limite <= p_ahora
         and b.disponible_desde <= p_ahora
         and motor.en_turno(j.id, p_ahora)
         and motor.salida_reparto_en(j.id, p_ahora) is null
       limit 1))
    || motor.seguimiento_de(p_persona, p_ahora);
end;
$$;

create or replace function motor.retrasar_salida_de(p_persona uuid, p_id_cliente uuid, p_minutos integer, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  j public.jornadas;
  v_jornada uuid;
  v_bolsas public.tareas;
  v_nueva timestamptz;
  v_evento bigint;
  v_previo jsonb;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;
  select * into j from public.jornadas where id = v_jornada;
  select datos into v_previo from public.registro_eventos
   where jornada_id = j.id and tipo = 'salida_retrasada' and datos ->> 'id_cliente' = p_id_cliente::text;
  if v_previo is not null then
    return jsonb_build_object('nueva_hora_salida', v_previo ->> 'nueva_hora', 'minutos', (v_previo ->> 'minutos')::int,
                              'aviso', v_previo ->> 'aviso', 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if p_minutos is null or p_minutos not in (15, 30) then
    return motor.error('DATOS_NO_VALIDOS', 'El retraso es de 15 o 30 minutos.');
  end if;
  select * into v_bolsas from public.tareas where jornada_id = j.id and clave = 'bolsas';
  if v_bolsas.id is null then
    return motor.error('SIN_TAREA', 'Todavía no hay bolsas: prepara primero el reparto.');
  end if;
  -- Tarea 29b: con el reparto ya fuera no se mueve ninguna hora.
  if motor.salida_reparto_en(j.id, p_ahora) is not null then
    return motor.error('ESTADO_NO_VALIDO', 'El reparto ya ha salido.');
  end if;
  if v_bolsas.estado not in ('pendiente', 'en_curso', 'bloqueada') then
    return motor.error('ESTADO_NO_VALIDO', 'Las bolsas ya están listas.', jsonb_build_object('estado', v_bolsas.estado));
  end if;

  v_nueva := coalesce(v_bolsas.hora_limite, motor.en_local(j.fecha, '10:45')) + make_interval(mins => p_minutos);
  update public.tareas set hora_limite = hora_limite + make_interval(mins => p_minutos)
   where jornada_id = j.id
     and (clave in ('bolsas', 'produccion_reparto', 'preparar_envio_viernes')
          or clave like 'pedido_tienda:%' or clave like 'pedido_nacex_viernes:%')
     and estado in ('pendiente', 'en_curso', 'bloqueada') and hora_limite is not null;
  update public.tareas
     set hora_programada = hora_programada + make_interval(mins => p_minutos),
         disponible_desde = disponible_desde + make_interval(mins => p_minutos)
   where jornada_id = j.id and clave in ('salida_reparto', 'nacex_viernes') and estado = 'pendiente';

  insert into public.registro_eventos (tipo, persona_id, jornada_id, tarea_id, datos)
  values ('salida_retrasada', p_persona, j.id, v_bolsas.id,
          jsonb_build_object('minutos', p_minutos, 'nueva_hora', motor.hora_texto(v_nueva), 'sale', j.sale,
                             'id_cliente', p_id_cliente, 'a_las', p_ahora,
                             'aviso', case when j.sale = 'administracion' then 'correo' else 'sin_aviso' end))
  returning id into v_evento;
  if j.sale = 'administracion' then
    perform motor.encolar_correo('retraso', v_evento::text);
  end if;
  return jsonb_build_object('nueva_hora_salida', motor.hora_texto(v_nueva), 'minutos', p_minutos,
                            'aviso', case when j.sale = 'administracion' then 'correo' else 'sin_aviso' end,
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;
