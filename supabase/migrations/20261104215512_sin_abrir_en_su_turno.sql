-- Tarea 33 · «sin abrir» solo mientras dura el turno (decisión del propietario, 04/11/2026, PR #37): sale media hora
-- después de que empiece un turno sin nadie, y deja de salir cuando alguien lo empieza o cuando acaba ese turno.
-- Solo en pruebas.
--
-- Deshacer: volver a crear motor.marcas_panel_json como está en 20261104210512.

create or replace function motor.marcas_panel_json(p_admin uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with hoy as (select motor.fecha_local(p_ahora) as f),
  cen as (select (x ->> 'id')::uuid as id, x ->> 'tipo' as tipo from jsonb_array_elements(motor.centros_panel_json()) x),
  -- Las incidencias abiertas de cada tienda, las mismas de incidencias_tiendas() (con los atascados por decidir).
  inc as (select (x ->> 'tienda_id')::uuid as centro, count(*)::int as n
            from jsonb_array_elements(motor.incidencias_tiendas_de(p_ahora) -> 'incidencias') x
           where x ->> 'estado' <> 'cerrada' group by 1),
  m as (
    select c.id, c.tipo,
           case when c.tipo = 'almacen' then jsonb_array_length(motor.estado_actual_de(p_ahora) -> 'problemas_abiertos')
                else coalesce(inc.n, 0) end as rojo,
           case when c.tipo = 'almacen' or pe.id is null then 0 else (
             select count(*)::int
               from public.jornadas j join public.tareas t on t.jornada_id = j.id
              where j.persona_id = pe.id and j.fecha between (select f from hoy) - 7 and (select f from hoy)
                and t.estado = 'pendiente' and not t.retirada_por_condicion
                and motor.cierre_tienda_en(j.persona_id, j.fecha) <= p_ahora
                and motor.cierre_tienda_en(j.persona_id, j.fecha) > coalesce(v.visto_en, '-infinity'::timestamptz)) end
             as sin_hacer,
           c.tipo = 'tienda' and pe.id is not null and not motor.dia_cerrado(c.id, (select f from hoy))
             and exists (select 1 from public.horarios h
                          where h.persona_id = pe.id and h.dia_semana = extract(isodow from (select f from hoy))
                            and p_ahora >= motor.en_local((select f from hoy), h.hora_inicio) + interval '30 minutes'
                            -- Solo mientras dura ese turno (decisión del propietario, PR #37).
                            and p_ahora < motor.en_local((select f from hoy), h.hora_fin)
                            and not exists (select 1 from public.turnos_tienda x join public.jornadas j on j.id = x.jornada_id
                                             where j.persona_id = pe.id and j.fecha = (select f from hoy) and x.turno = h.turno))
             as sin_abrir
      from cen c
      left join inc on inc.centro = c.id
      left join lateral (select p.id from public.personas p
                          where p.centro_id = c.id and p.rol = 'tienda' and p.activo order by p.id limit 1) pe on c.tipo = 'tienda'
      left join public.vistas_panel v on v.persona_id = p_admin and v.centro_id = c.id)
  select coalesce(jsonb_object_agg(m.id, jsonb_build_object(
           'rojo', m.rojo, 'sin_hacer', m.sin_hacer, 'sin_abrir', coalesce(m.sin_abrir, false),
           -- Lo que se pinta junto al nombre: «●2 · 3 sin hacer · sin abrir» (null si no hay nada).
           'texto', nullif(concat_ws(' · ', case when m.rojo > 0 then '●' || m.rojo end,
                                           case when m.sin_hacer > 0 then m.sin_hacer || ' sin hacer' end,
                                           case when m.sin_abrir then 'sin abrir' end), ''))), '{}'::jsonb)
    from m
$$;
