-- Tarea 32 · El panel de Administración por centro (ESTADO_DEL_SISTEMA.md E2-8, «Panel de Administración»;
-- AGENTE_COORDINADOR.md, bloque 1, punto 23 y nota del 03/11, «Panel (Tarea 32)»). Solo en pruebas: producción espera
-- con las de tiendas (AGENTE_BASE_DE_DATOS.md §4). El almacén no cambia: el panel sigue con estado_actual().
--   1. tiendas() trae además `centros`, para el selector del panel: el almacén y las tiendas activas en el orden de la
--      ruta (las del reparto en su orden, después las que reciben por el envío de otro destino y después las que
--      tienen envío propio). Sale de la configuración (destinos_reparto y peticiones_por_envio), no de una lista fija.
--   2. resumen_tienda(tienda_id, fecha?): lo que ve la tienda, para Administración y solo de lectura (función STABLE:
--      no crea la jornada ni tareas, no prepara la bolsa ni los envíos y no pasa atascados a Administración). Usa las
--      mismas piezas que tienda_hoy(); el horario, los avisos, las tareas y los envíos sin confirmar pasan a ayudas que
--      usan las dos, para que no haya dos copias.
--
-- Deshacer: borrar public.resumen_tienda, motor.api_resumen_tienda, motor.resumen_tienda_de, motor.centros_panel_json,
-- motor.horario_tienda_json, motor.avisos_tienda_json, motor.tareas_tienda_json y motor.envios_sin_confirmar; volver a
-- crear motor.api_tiendas (20261103152517) y motor.tienda_hoy_de (20261104140512) como estaban.

-- ---------------------------------------------------------------------------
-- 1. Ayudas que usan la tableta y el panel (lo mismo que tienda_hoy() tenía dentro)
-- ---------------------------------------------------------------------------
create or replace function motor.horario_tienda_json(p_persona uuid, p_fecha date)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('turno', h.turno, 'inicio', to_char(h.hora_inicio, 'HH24:MI'),
                                               'fin', to_char(h.hora_fin, 'HH24:MI')) order by h.hora_inicio), '[]'::jsonb)
    from public.horarios h where h.persona_id = p_persona and h.dia_semana = extract(isodow from p_fecha)
$$;

-- Los avisos sin leer de la tienda (los de hoy y los de días anteriores que no se leyeron), con de quién vienen.
create or replace function motor.avisos_tienda_json(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'fecha', motor.fecha_local(i.iniciada_en),
                                               -- Tarea 29: de quién viene («Almacén» o «Administración»).
                                               'de', case when a.rol = 'operario' then 'Almacén' else 'Administración' end)
                            order by i.iniciada_en), '[]'::jsonb)
    from public.incidencias i left join public.personas a on a.id = i.creada_por
   where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora
$$;

-- Las tareas del día de la tienda, por hora (el objeto tarea de la tienda).
create or replace function motor.tareas_tienda_json(p_jornada uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(motor.tarea_tienda_json(t.id, p_ahora) order by t.disponible_desde, t.orden, t.creada_en),
                  '[]'::jsonb)
    from public.tareas t where t.jornada_id = p_jornada and not t.retirada_por_condicion
$$;

-- Cuántos envíos tiene la tienda sin confirmar (el número de la pestaña «Envíos»).
create or replace function motor.envios_sin_confirmar(p_centro uuid)
returns integer language sql stable set search_path = '' as $$
  select count(*)::int from public.bolsas_tienda b join public.repartos r on r.id = b.reparto_id
   where b.centro_id = p_centro and r.tipo = 'envio' and b.reposicion is null
$$;

-- ---------------------------------------------------------------------------
-- 2. tienda_hoy() con las ayudas (devuelve lo mismo que antes)
-- ---------------------------------------------------------------------------
create or replace function motor.tienda_hoy_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_dia integer := extract(isodow from v_hoy);
  pe public.personas;
  c public.centros_trabajo;
  v_jornada uuid;
  v_turno text;
  tt public.turnos_tienda;
  v_atascados jsonb;
begin
  select * into pe from public.personas where id = p_persona;
  select * into c from public.centros_trabajo where id = pe.centro_id;
  v_jornada := motor.generar_jornada(p_persona, v_hoy);
  -- Tarea 28: si ha salido el reparto y trae bolsa para esta tienda, «Recibe la bolsa».
  perform motor.preparar_bolsa_tienda(p_persona, v_jornada, p_ahora);
  -- Tarea 30b: las tiendas que reciben por envío, los envíos que les han salido.
  perform motor.preparar_envios_tienda(p_persona, p_ahora);
  -- Tarea 31: lo ofrecido el martes que nadie ha pedido pasa a Administración.
  perform motor.vencer_atascados(p_ahora);
  v_atascados := motor.atascados_tienda_json(c.id, p_ahora);
  v_turno := motor.turno_tienda_ahora(p_persona, p_ahora);
  tt := motor.en_turno_tienda(v_jornada);
  return jsonb_build_object(
    'tienda', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre),
    'fecha', v_hoy,
    'ahora', motor.hora_texto(p_ahora),
    'abierta_hoy', v_jornada is not null,
    'cerrado', motor.dia_cerrado(c.id, v_hoy),
    -- Tarea 32: el horario, los avisos y las tareas, con las mismas ayudas que el panel de Administración.
    'horario', motor.horario_tienda_json(p_persona, v_hoy),
    'turno', v_turno,
    'en_turno', case when tt.id is not null then
      jsonb_build_object('persona_id', tt.persona_tienda_id, 'nombre', tt.nombre, 'turno', tt.turno,
                         'desde', motor.hora_texto(tt.empezado_en)) end,
    'personas', coalesce((
      select jsonb_agg(x.o order by x.sugerida desc, x.nombre)
        from (select pt.nombre,
                     (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                     and (pt.turno is null or v_turno is null or pt.turno = v_turno) as sugerida,
                     jsonb_build_object('id', pt.id, 'nombre', pt.nombre, 'cuando', pt.cuando, 'turno', pt.turno,
                       'sugerida', (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                                   and (pt.turno is null or v_turno is null or pt.turno = v_turno)) as o
                from public.personas_tienda pt where pt.centro_id = c.id and pt.activo) x), '[]'::jsonb),
    'avisos', motor.avisos_tienda_json(p_persona, p_ahora),
    'tareas', motor.tareas_tienda_json(v_jornada, p_ahora),
    -- Tarea 28: por dónde va el reparto, las peticiones (muestras y material) y si puede pedir material.
    'reparto', motor.seguimiento_reparto_json(c.id, v_hoy, p_ahora),
    'peticiones', motor.peticiones_tienda_json(c.id, p_ahora),
    'pedir_material', coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                                 where k.clave = 'pedir_material' and k.centro_id = c.id), false),
    -- Tarea 30: las incidencias de la tienda (abiertas y cerradas hoy) y qué opciones tiene.
    'incidencias', motor.incidencias_tienda_json(p_persona, p_ahora),
    'opciones_incidencia', motor.opciones_incidencia_json(c.id),
    -- Tarea 30b: «Envíos» (tiendas que reciben por envío) y cuántos quedan sin confirmar.
    'envios', motor.envios_tienda_json(c.id, p_ahora),
    'envios_sin_confirmar', motor.envios_sin_confirmar(c.id),
    -- Tarea 30c: los pedidos de cliente para recoger en la tienda, con su estado.
    'pedidos', motor.pedidos_de_tienda_json(c.id, p_ahora),
    -- Tarea 31: lo atascado de la tienda, las ofertas de las demás («Las quiero»), lo que ha pedido y sus promociones
    -- abiertas («Ya no queda»).
    'atascados', v_atascados -> 'atascados',
    'ofertas_atascados', v_atascados -> 'ofertas_atascados',
    'atascados_pedidos', v_atascados -> 'atascados_pedidos',
    'promociones', v_atascados -> 'promociones');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. El selector del panel: tiendas() trae también `centros`
-- ---------------------------------------------------------------------------
-- El almacén y las tiendas activas en el orden de la ruta: las del reparto en el orden de `destinos_reparto`; después
-- las que reciben por el envío de otro destino (Donosti y Rentería, por Gipuzkoa); después las de envío propio
-- (Durango, cuando abra); el resto, al final. `va_en`: «reparto» o «envio» (null en el almacén).
create or replace function motor.centros_panel_json()
returns jsonb language sql stable set search_path = '' as $$
  with o as (
    select a.codigo, a.n from public.configuracion k,
           jsonb_array_elements_text(k.valor -> 'reparto') with ordinality a(codigo, n)
     where k.clave = 'destinos_reparto' and k.centro_id is null)
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'codigo', x.codigo, 'nombre', x.nombre, 'tipo', x.tipo,
                                               'va_en', x.va_en)
                            order by x.grupo, x.n nulls last, x.nombre), '[]'::jsonb)
    from (select c.id, c.codigo, c.nombre, c.tipo, d.tipo as va_en, o.n,
                 case when c.tipo = 'almacen' then 0
                      when d.tipo = 'reparto' then 1
                      when d.tipo = 'envio' and d.destino_id <> c.id then 2
                      when d.tipo = 'envio' then 3
                      else 4 end as grupo
            from public.centros_trabajo c
            left join lateral motor.destino_peticion(c.id) d on c.tipo = 'tienda'
            left join o on o.codigo = c.codigo
           where c.activo and c.tipo in ('almacen', 'tienda')) x
$$;

create or replace function motor.api_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if motor.es_tienda() then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  return jsonb_build_object('tiendas', coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre) order by c.nombre)
      from public.centros_trabajo c where c.tipo = 'tienda' and c.activo), '[]'::jsonb),
    -- Tarea 32: el selector del panel (el almacén y las tiendas, en el orden de la ruta).
    'centros', motor.centros_panel_json());
end; $$;

-- ---------------------------------------------------------------------------
-- 4. resumen_tienda(tienda_id, fecha?): la tienda vista por Administración, solo de lectura
-- ---------------------------------------------------------------------------
-- STABLE: Postgres no le deja escribir nada. Para hoy, con la hora de ahora; para un día pasado, como quedó al final.
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
    when j.id is null then 'Todavía no tiene la lista del día (se prepara a las 06:00 o al abrir la tableta)' end;
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

create or replace function motor.api_resumen_tienda(p_tienda_id uuid, p_fecha date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.resumen_tienda_de(p_tienda_id, p_fecha, now());
end; $$;

create or replace function public.resumen_tienda(tienda_id uuid, fecha date default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_resumen_tienda(tienda_id, fecha) $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_resumen_tienda(uuid, date), motor.api_tiendas() to authenticated;
revoke execute on function public.resumen_tienda(uuid, date) from public, anon;
grant execute on function public.resumen_tienda(uuid, date) to authenticated;
