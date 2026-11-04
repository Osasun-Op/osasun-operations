-- Tarea 32 · Corrección de texto (propietario, 04/11/2026, PR #36): las tiendas no «abren la tableta», entran en la
-- app web. Solo cambia el `motivo` de resumen_tienda() cuando todavía no hay lista del día. Solo en pruebas.
--
-- Deshacer: volver a crear motor.resumen_tienda_de como está en 20261104190512.

create or replace function motor.resumen_tienda_de(p_centro uuid, p_fecha date, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_fecha date := coalesce(p_fecha, v_hoy);
  v_ahora timestamptz;
  c public.centros_trabajo;
  pe public.personas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_cerrado boolean;
  v_horario jsonb;
  v_motivo text;
  v_tareas jsonb;
  v_atascados jsonb;
  v_ultimo jsonb;
begin
  select * into c from public.centros_trabajo where id = p_centro and tipo = 'tienda';
  if c.id is null then
    return motor.error('NO_ENCONTRADO', 'Esa tienda no existe.');
  end if;
  if v_fecha > v_hoy then
    return motor.error('DATOS_NO_VALIDOS', 'Elige hoy o un día que ya ha pasado.');
  end if;
  v_ahora := case when v_fecha = v_hoy then p_ahora else motor.en_local(v_fecha, '23:59') end;
  select * into pe from public.personas where centro_id = c.id and rol = 'tienda' and activo order by id limit 1;
  select * into j from public.jornadas where persona_id = pe.id and fecha = v_fecha;
  v_cerrado := motor.dia_cerrado(c.id, v_fecha);
  v_horario := case when pe.id is not null then motor.horario_tienda_json(pe.id, v_fecha) else '[]'::jsonb end;
  -- Si ese día no abre, se dice por qué (y no hay nada más que enseñar).
  v_motivo := case
    when pe.id is null then 'Todavía no ha entrado con su cuenta'
    when v_cerrado then 'Ese día la tienda está cerrada (lo ha marcado Administración)'
    when jsonb_array_length(v_horario) = 0 then 'Ese día no abre'
    when j.id is null then 'Todavía no tiene la lista del día (se prepara a las 06:00 o al entrar en la app)' end;
  tt := motor.en_turno_tienda(j.id);
  v_tareas := motor.tareas_tienda_json(j.id, v_ahora);
  v_atascados := motor.atascados_tienda_json(c.id, v_ahora);
  v_ultimo := motor.cierres_caja_de(v_fecha - 60, v_fecha, c.id) -> 'cierres' -> 0;
  return jsonb_build_object(
    'tienda', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre),
    'fecha', v_fecha,
    'ahora', motor.hora_texto(v_ahora),
    'abre', v_motivo is null,
    'motivo', v_motivo,
    'cerrado', v_cerrado,
    'horario', v_horario,
    'va_en', (select d.tipo from motor.destino_peticion(c.id) d),
    -- Quién está ahora (solo hoy) y quién ha estado ese día.
    'en_turno', case when tt.id is not null and v_fecha = v_hoy then
      jsonb_build_object('persona_id', tt.persona_tienda_id, 'nombre', tt.nombre, 'turno', tt.turno,
                         'desde', motor.hora_texto(tt.empezado_en)) end,
    'turnos', coalesce((select jsonb_agg(jsonb_build_object('nombre', x.nombre, 'turno', x.turno,
                                                            'desde', motor.hora_texto(x.empezado_en)) order by x.empezado_en, x.id)
                          from public.turnos_tienda x where x.jornada_id = j.id), '[]'::jsonb),
    -- Las tareas del día (el objeto tarea de la tienda) y cuántas van.
    'tareas', v_tareas,
    'cuantas', jsonb_build_object(
      'total', jsonb_array_length(v_tareas),
      'hechas', (select count(*)::int from jsonb_array_elements(v_tareas) t where t ->> 'estado' in ('hecha', 'cancelada')),
      'no_hechas', (select count(*)::int from jsonb_array_elements(v_tareas) t where (t ->> 'no_hecha')::boolean),
      'pendientes', (select count(*)::int from jsonb_array_elements(v_tareas) t
                      where t ->> 'estado' = 'pendiente' and not (t ->> 'no_hecha')::boolean)),
    -- La bolsa del reparto (recibida, efectivo, reposición) y por dónde va; o sus envíos sin confirmar.
    'bolsa', motor.bolsa_tienda_json(c.id, v_fecha),
    'reparto', motor.seguimiento_reparto_json(c.id, v_fecha, v_ahora),
    'envios', motor.envios_tienda_json(c.id, v_ahora),
    'envios_sin_confirmar', motor.envios_sin_confirmar(c.id),
    -- Lo abierto: incidencias (y los atascados con lo suyo), avisos sin leer, peticiones y pedidos de cliente.
    'incidencias', case when pe.id is not null then motor.incidencias_tienda_json(pe.id, v_ahora) else '[]'::jsonb end,
    'atascados', coalesce((select jsonb_agg(a) from jsonb_array_elements(v_atascados -> 'atascados') a
                            where a ->> 'estado' in ('ofrecido', 'administracion', 'promocion', 'por_recoger')), '[]'::jsonb),
    'avisos', case when pe.id is not null then motor.avisos_tienda_json(pe.id, v_ahora) else '[]'::jsonb end,
    'peticiones', coalesce((select jsonb_agg(p) from jsonb_array_elements(motor.peticiones_tienda_json(c.id, v_ahora)) p
                             where p ->> 'estado' = 'pendiente'), '[]'::jsonb),
    'pedidos', motor.pedidos_de_tienda_json(c.id, v_ahora),
    -- El cierre de caja de ese día o, si no lo hay, el último (de los 60 días anteriores).
    'cierre_caja', case when v_ultimo is not null then v_ultimo || jsonb_build_object('es_de_ese_dia', (v_ultimo ->> 'fecha')::date = v_fecha) end);
end;
$$;
