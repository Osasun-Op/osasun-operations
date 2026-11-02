-- Tarea 24 (añadido del propietario, 02/11/2026, opción B): al acabar el turno, una tarea
-- no obligatoria que quedó en curso se pausa sola: vuelve a «pendiente» y conserva lo hecho.
-- Reutiliza la pausa que ya existe (registro «tarea_pausada», la misma que deja una tarea con hora
-- o urgente al entrar), con la hora de fin del turno, así que los minutos trabajados se paran ahí
-- y «Hoy» la enseña como interrupción «Fin del turno». Lo hace el cierre del turno, que ya se
-- genera solo al acabar cada turno (generar_cierres_programados). Las obligatorias no cambian:
-- siguen en curso para terminarlas. En el siguiente turno vuelve a salir por su prioridad, y al
-- final del día sigue su regla de siempre (recalcular, arrastrar o nada).
-- Sustituye: motor.generar_cierre (20261027093007), motor.contenido_cierre (20261027120100) y
-- motor.interrupciones_tarea (20261030105121). Nueva: motor.pausar_fin_de_turno.
-- Para deshacerlo: volver a crear esas tres como están en sus migraciones y borrar la nueva.

create or replace function motor.pausar_fin_de_turno(p_jornada uuid, p_turno text)
returns integer language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_fin timestamptz;
  t public.tareas;
  n integer := 0;
begin
  select * into j from public.jornadas where id = p_jornada;
  v_fin := (select motor.en_local(j.fecha, h.hora_fin) from public.horarios h
             where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha) and h.turno = p_turno);
  if v_fin is null then
    return 0;
  end if;
  for t in select * from public.tareas where jornada_id = p_jornada and estado = 'en_curso' and not obligatoria loop
    update public.tareas set estado = 'pendiente' where id = t.id;
    perform motor.registrar('tarea_pausada', null, p_jornada, t.id,
                            jsonb_build_object('a_las', v_fin, 'motivo', 'Fin del turno'));
    n := n + 1;
  end loop;
  return n;
end;
$$;
revoke execute on function motor.pausar_fin_de_turno(uuid, text) from public;

-- «Hoy»: una pausa sin tarea que entra (la del fin del turno) dice su motivo en «por».
create or replace function motor.interrupciones_tarea(p_tarea uuid)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'a_las', (p.datos ->> 'a_las')::timestamptz,
           'por', coalesce((select o.titulo from public.tareas o where o.id = (p.datos ->> 'entra')::uuid), p.datos ->> 'motivo'),
           'siguio_a_las', (select min((s.datos ->> 'a_las')::timestamptz) from public.registro_eventos s
                             where s.tarea_id = p.tarea_id and s.tipo = 'tarea_iniciada'
                               and (s.datos ->> 'a_las')::timestamptz > (p.datos ->> 'a_las')::timestamptz))
         order by (p.datos ->> 'a_las')::timestamptz, p.id), '[]'::jsonb)
  from public.registro_eventos p
  where p.tarea_id = p_tarea and p.tipo = 'tarea_pausada'
$$;

create or replace function motor.generar_cierre(p_jornada uuid, p_turno text, p_ahora timestamptz)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_ultimo boolean;
  j public.jornadas;
begin
  perform pg_advisory_xact_lock(hashtextextended('cierre:' || p_jornada || ':' || p_turno, 0));
  select id into v_id from public.cierres where jornada_id = p_jornada and turno = p_turno;
  if v_id is not null then
    return v_id;
  end if;
  -- Fin del turno (Tarea 24): lo no obligatorio que quedó en curso se pausa solo, antes del cierre.
  perform motor.pausar_fin_de_turno(p_jornada, p_turno);
  insert into public.cierres (jornada_id, turno, contenido, generado_en)
  values (p_jornada, p_turno, motor.contenido_cierre(p_jornada, p_turno, p_ahora), p_ahora)
  returning id into v_id;

  select * into j from public.jornadas where id = p_jornada;
  v_ultimo := p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                          and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio desc limit 1);
  if v_ultimo then
    update public.jornadas set estado = 'cerrada' where id = p_jornada;
  end if;
  perform motor.registrar('cierre_generado', null, p_jornada, null, jsonb_build_object('cierre', v_id, 'turno', p_turno));
  if exists (select 1 from public.configuracion k, jsonb_array_elements(k.valor) x
              where k.clave = 'cierres_sin_correo' and k.centro_id is null and jsonb_typeof(k.valor) = 'array'
                and x ->> 'persona' = j.persona_id::text and j.fecha >= (x ->> 'desde')::date) then
    perform motor.registrar('correo_no_enviado', null, p_jornada, null,
                            jsonb_build_object('tipo', 'cierre', 'ref', v_id, 'motivo', 'cierre sin correo para esta persona'));
  else
    perform motor.encolar_correo('cierre', v_id::text);
  end if;
  return v_id;
end;
$$;

create or replace function motor.contenido_cierre(p_jornada uuid, p_turno text, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
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
                                            else case when exists (select 1 from public.registro_eventos r
                                                                    where r.tarea_id = t.id and r.tipo = 'tarea_pausada'
                                                                      and r.datos ->> 'motivo' = 'Fin del turno')
                                                      then 'Sin terminar: fin del turno' else 'Sin motivo anotado' end end),
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
        'minutos_incidencias_manana', (select coalesce(sum((motor.incidencia_json(i.id, p_ahora) ->> 'minutos')::int), 0)::int
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
      select jsonb_agg(motor.incidencia_json(i.id, p_ahora) || jsonb_build_object(
               'tarea', t.titulo, 'inicio', motor.hora_texto(i.iniciada_en), 'fin', motor.hora_texto(i.terminada_en))
             order by i.iniciada_en)
        from public.incidencias i left join public.tareas t on t.id = i.tarea_id
       where i.persona_id = j.persona_id and i.iniciada_en <= p_ahora
         and ((i.jornada_id = j.id and (i.iniciada_en > v_desde or i.terminada_en > v_desde or i.estado <> 'cerrada'))
              or (i.jornada_id <> j.id
                  and (i.estado <> 'cerrada'
                       or i.terminada_en > greatest(v_desde, motor.en_local(j.fecha, '00:00')))))), '[]'::jsonb),
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
