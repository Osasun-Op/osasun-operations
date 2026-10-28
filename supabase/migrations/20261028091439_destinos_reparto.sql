-- Tarea 10 (revisión del propietario, 28/10/2026) · Tiendas del reparto y del envío.
-- El reparto con lista se prepara solo con las tiendas que se reparten, en el
-- orden de las hojas de tienda de STOCK OSASUN:
--   reparto: BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU (Donosti y Rentería son
--            solo de consulta: no se reparten);
--   envío:   GIPUZKOA, DURANGO.
-- Va en la configuración (`destinos_reparto`) para poder cambiarla sin tocar el
-- código. servidor_preparar la entrega a las funciones del servidor.

insert into public.configuracion (clave, centro_id, valor) values
  ('destinos_reparto', null,
   '{"reparto": ["BILBAO", "ALGORTA", "BARAKALDO", "BASAURI", "PORTU"], "envio": ["GIPUZKOA", "DURANGO"]}');

create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_operario uuid;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada := motor.generar_jornada(v_operario, v_fecha);
  end if;
  if v_rol = 'operario' and v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;

  select h.turno into v_turno from public.horarios h
   where h.persona_id = v_operario and h.dia_semana = extract(isodow from v_fecha)
     and motor.en_local(v_fecha, h.hora_inicio) <= p_ahora
   order by h.hora_inicio desc limit 1;
  v_turno := coalesce(v_turno, 'manana');

  select t.id into v_stock from public.tareas t
   where t.jornada_id = v_jornada and t.clave = 'cola_stock'
     and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.lote = v_turno);

  return jsonb_build_object(
    'persona_id', p_persona, 'rol', v_rol, 'jornada_id', v_jornada,
    'fecha', v_fecha, 'dia', extract(day from v_fecha)::int, 'mes', extract(month from v_fecha)::int,
    'turno', v_turno,
    'destinos', (select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre,
                                                     'tipo', c.tipo, 'activo', c.activo, 'alias', to_jsonb(c.alias))
                                  order by c.codigo)
                 from public.centros_trabajo c where c.tipo <> 'almacen'),
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas',
                                                         'stock_objetivo_pct', 'stock_excluidos',
                                                         'destinos_reparto')),
    'repartos', jsonb_build_object(
      'reparto', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                  from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'),
      'envio', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'envio' and r.estado = 'aceptado')),
    -- Para el envío: cajas pedidas en el reparto aceptado hoy y si ya se hizo el recuento de la mañana.
    'reparto_hoy', coalesce((select jsonb_agg(jsonb_build_object('producto', x ->> 'producto',
                                                                 'formato', coalesce(x ->> 'formato', ''),
                                                                 'pedido', (x ->> 'pedido')::int))
                             from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                             where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'), '[]'::jsonb),
    'recuento_manana_hecho', exists (select 1 from public.tareas t
                                     where t.jornada_id = v_jornada and t.clave = 'recuento_manana' and t.estado = 'hecha'),
    'stock', case when v_stock is null or v_rol <> 'operario' then null else motor.tarea_json(v_stock) end);
end;
$$;
