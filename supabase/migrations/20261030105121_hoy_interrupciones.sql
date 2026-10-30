-- Tarea 21 · «Hoy» del panel (ESTADO_DEL_SISTEMA.md v1.35, §8 Inicio, punto 4):
-- interrupciones de cada tarea y, en las de producción, cajas y minutos trabajados.
-- Solo se añaden campos a estado_actual().hoy (CONTRATOS.md 1.7).
--
-- Reutiliza lo que ya se registra: `tarea_pausada` (motor.tras_elemento, con
-- `a_las` y `entra`) y `tarea_iniciada` (cada vez que la tarea pasa a en curso,
-- también al retomarla: motor.iniciar_tarea_de y motor.asegurar_en_curso). No
-- hace falta un evento nuevo. Las cajas y los minutos salen de los elementos.
--
-- Deshacer: volver a crear motor.estado_actual_de como en
-- 20261029140000_sin_granel.sql y drop function motor.interrupciones_tarea(uuid),
-- motor.cajas_tarea(uuid), motor.minutos_trabajados(uuid, timestamptz).

-- Cada vez que otra tarea (con hora o urgente) entró en un punto de encaje, en
-- orden: a qué hora, qué tarea entró y cuándo siguió (null si aún no).
create or replace function motor.interrupciones_tarea(p_tarea uuid)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'a_las', (p.datos ->> 'a_las')::timestamptz,
           'por', (select o.titulo from public.tareas o where o.id = (p.datos ->> 'entra')::uuid),
           'siguio_a_las', (select min((s.datos ->> 'a_las')::timestamptz) from public.registro_eventos s
                             where s.tarea_id = p.tarea_id and s.tipo = 'tarea_iniciada'
                               and (s.datos ->> 'a_las')::timestamptz > (p.datos ->> 'a_las')::timestamptz))
         order by (p.datos ->> 'a_las')::timestamptz, p.id), '[]'::jsonb)
  from public.registro_eventos p
  where p.tarea_id = p_tarea and p.tipo = 'tarea_pausada'
$$;

-- Tareas de producción (las que tienen referencias que producir): cajas hechas de
-- las totales. En las demás, null.
create or replace function motor.cajas_tarea(p_tarea uuid)
returns jsonb language sql stable set search_path = '' as $$
  select case when count(*) > 0
              then jsonb_build_object('hechas', sum(e.cantidad_hecha), 'total', sum(e.cantidad)) end
  from public.tarea_elementos e
  where e.tarea_id = p_tarea and e.tipo = 'referencia_produccion'
$$;

-- Minutos trabajados en una tarea de producción: lo que ha tardado en cada
-- referencia (la que esté en curso, hasta ahora). Una referencia se empieza y se
-- termina sin interrupciones (solo se interrumpe entre una y otra), así que no
-- cuentan ni las interrupciones ni la ruta. En las demás tareas, null.
create or replace function motor.minutos_trabajados(p_tarea uuid, p_ahora timestamptz)
returns integer language sql stable set search_path = '' as $$
  select case when count(*) > 0
              then coalesce(round(sum(extract(epoch from
                     coalesce(e.terminado_en, case when e.estado = 'en_curso' then p_ahora end) - e.iniciado_en)) / 60), 0)::int end
  from public.tarea_elementos e
  where e.tarea_id = p_tarea and e.tipo = 'referencia_produccion'
$$;

revoke execute on function motor.interrupciones_tarea(uuid) from public;
revoke execute on function motor.cajas_tarea(uuid) from public;
revoke execute on function motor.minutos_trabajados(uuid, timestamptz) from public;

-- ---------------------------------------------------------------------------
-- estado_actual: «hoy» con interrupciones, cajas y minutos trabajados (lo demás, igual)
-- ---------------------------------------------------------------------------
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
        from public.incidencias i where i.persona_id = (select id from op) and i.estado <> 'cerrada'), '[]'::jsonb),
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
                       order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id
       where not t.retirada_por_condicion and t.origen <> 'problema'), '[]'::jsonb),
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
