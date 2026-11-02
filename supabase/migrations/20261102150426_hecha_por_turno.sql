-- Tarea 24 · Quién hizo cada tarea y nada fuera del turno (ESTADO v1.39, aprobado el 02/11/2026).
-- 1. estado_actual().hoy: «hecha_por», el nombre de quien la cerró, del registro que ya existe
--    (registro_eventos «tarea_terminada»; al guardar el reparto se registra con quien lo guarda,
--    el mismo que repartos.pegado_por). null en las no hechas.
-- 2. motor.elegir_tarea: la comprobación del horario que ya hacía «Nunca sin tarea» vale ahora para
--    toda la elección. Fuera de su turno, solo la tarea en curso (para terminarla); nada más.
-- Sustituye: motor.elegir_tarea (20261102142821) y motor.estado_actual_de (20261102095949).
-- Para deshacerlo: volver a crear las dos funciones como están en esas migraciones.

create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
  v_id uuid;
  -- Lo primero de la mañana (Tarea 23): mientras falte, no sale nada más que lo urgente,
  -- lo que va a su hora y lo que forma parte de ello.
  v_primero boolean := motor.lo_primero_pendiente(p_jornada, p_ahora);
  v_en_turno boolean;
begin
  -- Fuera de su turno (Tarea 24), ninguna tarea nueva: solo la que tiene en curso, para terminarla.
  select * into j from public.jornadas where id = p_jornada;
  v_en_turno := exists (select 1 from public.horarios h
                         where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                           and p_ahora >= motor.en_local(j.fecha, h.hora_inicio)
                           and p_ahora < motor.en_local(j.fecha, h.hora_fin));

  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and (t.estado = 'en_curso'
         or (v_en_turno
             and t.estado = 'pendiente'
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
  if v_id is not null or not v_en_turno then
    return v_id;
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
                                          'minutos_trabajados', motor.minutos_trabajados(t.id, p_ahora),
                                          -- Quién la cerró: la persona del último «tarea_terminada» (también cuando
                                          -- «Prepara el reparto» se cierra sola al guardar el reparto).
                                          'hecha_por', case when t.estado = 'hecha' then (
                                            select pe.nombre from public.registro_eventos r
                                              join public.personas pe on pe.id = r.persona_id
                                             where r.tarea_id = t.id and r.tipo = 'tarea_terminada'
                                             order by r.id desc limit 1) end)
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

