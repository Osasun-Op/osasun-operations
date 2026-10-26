-- Tarea 4 · Del PR #3 (ESTADO_DEL_SISTEMA.md v1.11): si el envío se pega antes
-- del recuento de la mañana del mismo día, al calcular lo que falta primero se
-- apartan las cajas del reparto aceptado ese día (la hoja aún no las refleja).
-- Después del recuento no se descuenta: la hoja ya lo refleja.
-- servidor_preparar devuelve además lo pedido en el reparto de hoy y si el
-- recuento de la mañana está hecho; el cálculo lo hace el servidor (r1.ts).

create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_rol text;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  if v_rol = 'operario' then
    v_jornada := motor.generar_jornada(p_persona, v_fecha);
    if v_jornada is null then
      return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
    end if;
  end if;

  select h.turno into v_turno from public.horarios h
   where h.persona_id = p_persona and h.dia_semana = extract(isodow from v_fecha)
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
                                                     'tipo', c.tipo, 'alias', to_jsonb(c.alias)) order by c.codigo)
                 from public.centros_trabajo c where c.tipo <> 'almacen'),
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas',
                                                         'stock_objetivo_pct', 'stock_excluidos')),
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
    'stock', case when v_stock is null then null else motor.tarea_json(v_stock) end);
end;
$$;

revoke execute on function public.servidor_preparar(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.servidor_preparar(uuid, timestamptz) to service_role;
