-- Tarea 29d · Se borra del todo `pegar_reparto`, la función del servidor obsoleta desde la Tarea 10 (pegar el
-- texto del reparto). Orden del propietario (04/11/2026, PR #35): no la usa ninguna pantalla y llevaba su propia
-- copia de la regla antigua del envío (apartar el reparto de hoy antes del recuento), que la Tarea 29d quita de
-- «Calcular» (ESTADO_DEL_SISTEMA.md §5 R1c v1.58). Solo en pruebas: producción espera con las de tiendas.
-- Se quita lo que solo usaba ella:
--   1. public.servidor_anotar_sale (anotaba si el desplegable «¿Quién sale?» no coincidía con la línea SALE: del
--      texto pegado; con la lista ya no hay texto que pegar).
--   2. En public.servidor_preparar, `reparto_hoy` y `recuento_manana_hecho` (lo que usaba para apartar el reparto).
--      Lo demás de servidor_preparar no cambia (lo usan catalogo, guardar_reparto y lista_stock).
-- La clave de la tarea «Prepara el reparto» se sigue llamando `pegar_reparto`: no es la función y no cambia.
--
-- Deshacer: volver a crear public.servidor_anotar_sale (20261027141334, con sus permisos) y public.servidor_preparar
-- (20261104110512) como estaban, y volver a desplegar pegar_reparto desde main.

drop function public.servidor_anotar_sale(uuid, uuid, text, text);

create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_operario uuid;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
  v_recuento timestamptz;
  v_desde timestamptz;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null or v_rol = 'tienda' then  -- una tienda no usa las funciones del reparto (Tarea 27)
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

  -- La hoja que se lee ahora recoge el último recuento: desde ahí cuentan lo producido y lo salido.
  v_recuento := motor.ultimo_recuento(v_operario, p_ahora);
  v_desde := coalesce(v_recuento, p_ahora);

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
    -- R1c: lo que aún no ha salido del almacén (reparto, envío, pedidos) y lo que va en camino a las tiendas.
    'comprometido', motor.comprometido_en(v_jornada, p_ahora),
    -- R1c: lo producido y lo salido desde el último recuento (la hoja aún no lo recoge).
    'almacen', jsonb_build_object(
      'recuento_en', v_recuento,
      'producido', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido'),
      'producido_reparto', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido', true,
                             (select id from public.tareas where jornada_id = v_jornada and clave = 'produccion_reparto')),
      'producido_envio', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido', true,
                           (select id from public.tareas where jornada_id = v_jornada
                               and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1)),
      'salido', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'salido')),
    -- Pedidos de cliente para recoger en tienda que van en el reparto de hoy (en orden de llegada).
    'pedidos_tienda', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'cliente', p.cliente, 'destino_id', p.destino_id,
                                          'lineas', p.lineas,
                                          -- Tarea 30c: el destino del envío que lo lleva (Donosti → GIPUZKOA).
                                          'envio_destino_id', (select d.destino_id from motor.destino_pedido(p.destino_id) d
                                                                where d.tipo = 'envio'))
                       order by p.registrado_en)
        from public.pedidos_cliente p
        left join public.tareas t on t.id = p.tarea_id
       where p.entrega = 'tienda' and t.estado is distinct from 'cancelada'
         and (p.jornada_id = v_jornada or (p.jornada_id is null and p.fecha_objetivo <= v_fecha))), '[]'::jsonb),
    -- Tarea 30c: las tiendas que se pueden elegir en «Pedido de cliente» (también las que reciben por envío).
    'tiendas_pedido', motor.tiendas_pedido_json(),
    'stock', case when v_stock is null or v_rol <> 'operario' then null else motor.tarea_json(v_stock) end);
end;
$$;
