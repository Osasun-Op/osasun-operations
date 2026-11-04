-- Tarea 36 · La limpieza semanal y la hora del vídeo del sábado (ESTADO_DEL_SISTEMA.md E2-8, v1.67; propietario,
-- 04/11/2026). Solo en pruebas: producción espera con las de tiendas.
--   1. «Limpieza de cristales» pasa a «Limpieza semanal: cristales, polvo y baños», con su porqué. Sigue igual: un toque
--      (simple, sin puntos), el jueves por la tarde, en las mismas tiendas (en las franquicias, desactivada). El código de
--      la plantilla (limpieza_cristales) no cambia, para no romper nada que lo use. Las tareas que ya estaban creadas de hoy
--      en adelante y sin hacer cogen el título nuevo.
--   2. El vídeo del sábado (motor.video_sabado) ya no sale en el momento de elegir el nombre: sale a la hora de abrir de
--      su turno, después de la apertura (11:00 por la mañana; 17:00 por la tarde, Bilbao 16:30). Hasta esa hora, en gris
--      como las demás. Lo demás, igual (a quien no ha compartido esa semana, uno por persona).
--
-- Deshacer: volver a crear motor.video_sabado como está en 20261102190536 y poner otra vez en la plantilla
-- limpieza_cristales el título «Limpieza de cristales» y el porqué «Para que la tienda se vea bien desde fuera.» (y en
-- las tareas sin hacer de hoy en adelante).

-- ---------------------------------------------------------------------------
-- 1. La limpieza semanal
-- ---------------------------------------------------------------------------
update public.plantillas_tarea
   set titulo = 'Limpieza semanal: cristales, polvo y baños',
       porque = 'Para que la tienda esté limpia y se vea bien.'
 where codigo = 'limpieza_cristales';
update public.tareas t
   set titulo = 'Limpieza semanal: cristales, polvo y baños',
       porque = 'Para que la tienda esté limpia y se vea bien.'
  from public.jornadas j
 where j.id = t.jornada_id and t.clave = 'limpieza_cristales' and t.estado = 'pendiente'
   and j.fecha >= motor.fecha_local(now());

-- ---------------------------------------------------------------------------
-- 2. El vídeo del sábado, a la hora de abrir de su turno
-- ---------------------------------------------------------------------------
create or replace function motor.video_sabado(p_jornada uuid, p_persona_tienda uuid, p_ahora timestamptz)
returns uuid language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_plantilla uuid;
  v_id uuid;
  v_turno text;
begin
  select * into j from public.jornadas where id = p_jornada;
  select id into v_plantilla from public.plantillas_tarea
   where centro_id = j.centro_id and codigo = 'video_semana' and activa;
  if v_plantilla is null or extract(isodow from j.fecha) <> 6
     or exists (select 1 from public.videos_tienda v
                 where v.persona_tienda_id = p_persona_tienda and v.semana = date_trunc('week', j.fecha)::date) then
    return null;
  end if;
  v_id := motor.insertar_desde_plantilla(j.id, v_plantilla, 'video_semana:' || p_persona_tienda, 'plantilla');
  -- Tarea 36: sale a la hora de abrir de su turno, después de la apertura (11:00 por la mañana; 17:00 por la tarde,
  -- Bilbao 16:30). Si empieza fuera de los dos turnos, a la hora de abrir del siguiente; si ya no hay otro, en ese momento.
  -- Solo al crearla: si vuelve a empezar otro turno el mismo día, el vídeo sigue donde estaba.
  v_turno := motor.turno_tienda_ahora(j.persona_id, p_ahora);
  update public.tareas
     set disponible_desde = coalesce(
           case when v_turno is not null then motor.inicio_turno(j.persona_id, j.fecha, v_turno) end,
           (select min(motor.en_local(j.fecha, h.hora_inicio)) from public.horarios h
             where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
               and motor.en_local(j.fecha, h.hora_inicio) > p_ahora),
           p_ahora)
   where id = v_id;
  return v_id;
end;
$$;

revoke execute on all functions in schema motor from public;
