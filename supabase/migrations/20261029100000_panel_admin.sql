-- Tarea 15 · Panel de Administración tras la prueba en el almacén (ESTADO v1.29,
-- §5 R3 y R4, §8 «Administración · Inicio»).
-- 1. Minis: en la hoja real el mini se llama «MINI» (10g), no «MINIBUDS MIX».
-- 2. estado_actual.hoy: cada tarea con iniciada_en, terminada_en y minutos.
-- 3. estado_actual.tiempo_libre: veces y minutos de «Orden y limpieza» de hoy.
-- 4. estado_actual.cobertura_baja (R4): los productos con menos de 2 semanas. La
--    cuenta la hace el servidor (_compartido/r4.ts) cada vez que lee la hoja para
--    el reparto, el envío o el stock, y la guarda con esa lectura. El panel solo
--    lee la última: no se lee la hoja al abrirlo.

update public.configuracion
   set valor = (select jsonb_agg(case when e ->> 'producto' = 'MINIBUDS MIX' then jsonb_set(e, '{producto}', '"MINI"') else e end
                                 order by n)
                  from jsonb_array_elements(valor) with ordinality x(e, n))
 where clave = 'stock_excluidos' and centro_id is null;

-- ---------------------------------------------------------------------------
-- R4 · Cobertura guardada con cada lectura
-- ---------------------------------------------------------------------------
alter table public.lecturas_sheets add column cobertura jsonb;
comment on column public.lecturas_sheets.cobertura is
  'R4: productos con menos de 2 semanas y avisos, calculados por el servidor con esta lectura (_compartido/r4.ts).';

create or replace function public.servidor_guardar_cobertura(p_lectura uuid, p_cobertura jsonb)
returns void
language sql security definer
set search_path = ''
as $$
  update public.lecturas_sheets set cobertura = p_cobertura where id = p_lectura and correcto;
$$;

revoke execute on function public.servidor_guardar_cobertura(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.servidor_guardar_cobertura(uuid, jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Minutos de una tarea: de inicio a fin; hasta ahora si está en curso; null si
-- no ha empezado.
-- ---------------------------------------------------------------------------
create or replace function motor.minutos_tarea(t public.tareas, p_ahora timestamptz)
returns integer language sql stable set search_path = '' as $$
  select round(extract(epoch from coalesce(t.terminada_en, case when t.estado = 'en_curso' then p_ahora end) - t.iniciada_en) / 60)::int
$$;

-- ---------------------------------------------------------------------------
-- estado_actual: hoy con horas, tiempo libre y cobertura baja (lo demás, igual)
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
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre)
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
                                          'minutos', motor.minutos_tarea(t, p_ahora))
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
revoke execute on function motor.minutos_tarea(public.tareas, timestamptz) from public;
