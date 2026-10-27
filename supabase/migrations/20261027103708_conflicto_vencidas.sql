-- Tarea 6 · Revisión del PR #5 (comentario del coordinador, duda 3):
-- las obligatorias (y de Administración) pendientes que ya han vencido no están
-- «en riesgo» —ya llegan tarde—, pero siguen ocupando tiempo: su duración se
-- resta del tiempo disponible antes de decidir si la tarea nueva cabe.

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
    select t.id, t.titulo, t.obligatoria, t.origen, coalesce(t.hora_limite, t.hora_programada) as vence,
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
  -- En riesgo solo las obligatorias que vencen dentro de la ventana.
  riesgo as (
    select coalesce(jsonb_agg(jsonb_build_object('tarea_id', v.id, 'titulo', v.titulo, 'vence', motor.hora_texto(v.vence),
                                                 'duracion_min', v.minutos, 'origen', v.origen) order by v.vence, v.titulo),
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

revoke execute on all functions in schema motor from public;
