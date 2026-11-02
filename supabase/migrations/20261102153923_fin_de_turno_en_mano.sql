-- Tarea 24 · Fin del turno: lo que tenía entre manos se puede terminar (corrige 20261102153458).
-- Al pausarse sola una tarea no obligatoria al acabar el turno, marcar después la referencia que
-- tenía entre manos (13:03) la volvía a poner en curso, y así se quedaba toda la comida. Ahora,
-- fuera del turno, lo no obligatorio no vuelve a ponerse en curso: se puede marcar la referencia
-- (y si era la última, la tarea queda hecha) o pulsar «Terminada», pero si no, sigue pausada
-- hasta el siguiente turno.
-- La comprobación del horario pasa a una sola función, motor.en_turno, que usan elegir_tarea,
-- asegurar_en_curso y terminar_tarea_de (una sola fuente; antes estaba dentro de elegir_tarea).
-- Sustituye: motor.elegir_tarea (20261102150426), motor.asegurar_en_curso y motor.tras_elemento
-- (20261026185245) y motor.terminar_tarea_de (20261028160000). Nueva: motor.en_turno.
-- Para deshacerlo: volver a crear esas cuatro como están en sus migraciones y borrar motor.en_turno.

-- ¿Está la persona de esa jornada dentro de uno de sus turnos?
create or replace function motor.en_turno(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.jornadas j
                   join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                  where j.id = p_jornada
                    and p_ahora >= motor.en_local(j.fecha, h.hora_inicio)
                    and p_ahora < motor.en_local(j.fecha, h.hora_fin))
$$;
revoke execute on function motor.en_turno(uuid, timestamptz) from public;

create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  v_id uuid;
  -- Lo primero de la mañana (Tarea 23): mientras falte, no sale nada más que lo urgente,
  -- lo que va a su hora y lo que forma parte de ello.
  v_primero boolean := motor.lo_primero_pendiente(p_jornada, p_ahora);
  v_en_turno boolean;
begin
  -- Fuera de su turno (Tarea 24), ninguna tarea nueva: solo la que tiene en curso, para terminarla.
  v_en_turno := motor.en_turno(p_jornada, p_ahora);

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

create or replace function motor.asegurar_en_curso(p_persona uuid, p_tarea uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_otra uuid;
begin
  select * into t from public.tareas where id = p_tarea;
  if t.estado = 'en_curso' then
    return null;
  end if;
  -- Fuera del turno (Tarea 24), lo no obligatorio que se pausó al acabar no vuelve a ponerse en curso:
  -- se puede marcar lo que tenía entre manos, pero la tarea sigue pausada hasta el siguiente turno.
  if not t.obligatoria and not motor.en_turno(t.jornada_id, p_ahora) then
    return null;
  end if;
  select id into v_otra from public.tareas where jornada_id = t.jornada_id and estado = 'en_curso';
  if v_otra is not null then
    return motor.error('OTRA_TAREA_EN_CURSO', 'Termina primero la tarea que tienes en curso.',
                       jsonb_build_object('tarea_en_curso', motor.tarea_json(v_otra)));
  end if;
  update public.tareas set estado = 'en_curso', iniciada_en = coalesce(iniciada_en, p_ahora)
   where id = p_tarea and estado = 'pendiente';
  perform motor.registrar('tarea_iniciada', p_persona, t.jornada_id, p_tarea, jsonb_build_object('a_las', p_ahora));
  return null;
end;
$$;

create or replace function motor.tras_elemento(p_persona uuid, p_tarea uuid, p_punto_de_encaje boolean, p_ahora timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_otra uuid;
  v_cajas integer;
begin
  select * into t from public.tareas where id = p_tarea;
  -- «pendiente»: la pausada al acabar el turno, en la que aún se marca lo que tenía entre manos.
  if t.estado not in ('en_curso', 'pendiente') then
    return;
  end if;

  if not exists (select 1 from public.tarea_elementos where tarea_id = p_tarea and estado <> 'hecho') then
    select coalesce(sum(cantidad_hecha), 0) into v_cajas from public.tarea_elementos where tarea_id = p_tarea;
    update public.tareas
       set estado = 'hecha', terminada_en = p_ahora,
           resultado = coalesce(resultado, v_cajas || ' cajas')
     where id = p_tarea;
    perform motor.registrar('tarea_terminada', p_persona, t.jornada_id, p_tarea,
                            jsonb_build_object('a_las', p_ahora, 'por', 'todos los elementos hechos'));
    return;
  end if;

  if p_punto_de_encaje and t.estado = 'en_curso' then
    v_otra := motor.elegir_tarea(t.jornada_id, p_ahora, p_tarea);
    if v_otra is not null
       and (select motor.escalon(o) in (2, 3, 4) from public.tareas o where o.id = v_otra) then
      update public.tareas set estado = 'pendiente' where id = p_tarea;
      perform motor.registrar('tarea_pausada', p_persona, t.jornada_id, p_tarea,
                              jsonb_build_object('a_las', p_ahora, 'entra', v_otra));
    end if;
  end if;
end;
$$;

create or replace function motor.terminar_tarea_de(p_persona uuid, p_tarea uuid, p_resultado text, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  t public.tareas;
  j public.jornadas;
  v_pendientes integer;
  v_pedido public.pedidos_cliente;
begin
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado = 'hecha' then
    return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  -- También la pausada al acabar el turno (Tarea 24): lo que tenía entre manos se puede terminar.
  if t.estado <> 'en_curso'
     and not (t.estado = 'pendiente' and not t.obligatoria and t.iniciada_en is not null
              and not motor.en_turno(j.id, p_ahora)) then
    return motor.error('ESTADO_NO_VALIDO', 'Solo se puede terminar una tarea en curso.', jsonb_build_object('estado', t.estado));
  end if;
  select count(*) into v_pendientes from public.tarea_elementos where tarea_id = t.id and estado <> 'hecho';
  if v_pendientes > 0 and nullif(btrim(p_motivo), '') is null then
    return motor.error('ELEMENTOS_PENDIENTES', 'Quedan ' || v_pendientes || ' sin hacer. Escribe el motivo para terminarla así.',
                       jsonb_build_object('pendientes', v_pendientes));
  end if;
  if t.clave = 'pegar_reparto'
     and not exists (select 1 from public.repartos r where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado') then
    select * into v_pedido from motor.pedidos_tienda_esperando(j.id) limit 1;
    if v_pedido.id is not null then
      return motor.error('PEDIDO_ESPERANDO_REPARTO',
                         'Hay un pedido de cliente para recoger en '
                         || (select nombre from public.centros_trabajo where id = v_pedido.destino_id)
                         || ' (' || v_pedido.cliente || '). Prepara el reparto, aunque sea solo con el pedido.',
                         jsonb_build_object('pedido', motor.pedido_json(v_pedido.id)));
    end if;
    if nullif(btrim(p_motivo), '') is null then
      return motor.error('MOTIVO_OBLIGATORIO', 'Todavía no hay reparto. Prepáralo, o escribe el motivo para terminarla así.');
    end if;
  end if;

  update public.tareas
     set estado = 'hecha', terminada_en = p_ahora,
         resultado = nullif(btrim(p_resultado), ''),
         motivo_no_hecha = coalesce(nullif(btrim(p_motivo), ''), motivo_no_hecha)
   where id = t.id and estado in ('en_curso', 'pendiente');
  update public.tarea_elementos set estado = 'pendiente' where tarea_id = t.id and estado = 'en_curso';
  perform motor.registrar('tarea_terminada', p_persona, j.id, t.id,
                          jsonb_build_object('a_las', p_ahora, 'resultado', p_resultado,
                                             'motivo', p_motivo, 'pendientes', v_pendientes));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;
