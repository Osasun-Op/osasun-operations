-- Tarea 14 · Cuenta del almacén entre recuentos, cajas en camino con hora y
-- pedidos de tienda que activan el reparto (ESTADO v1.27 §5 R1c y decisión del
-- propietario del 28/10/2026). Sustituye al R1c de la Tarea 12.
-- 1. Almacén ahora = la hoja (última lectura) + lo producido y marcado desde el
--    recuento que esa lectura recoge − lo que ha salido desde entonces (bolsas
--    listas, envío preparado, pedidos de Nacex preparados). Cada recuento lo pone
--    a cero: la lectura siguiente ya lo trae.
-- 2. Cajas en camino, sumadas a su tienda solo en los cálculos: el reparto (y los
--    pedidos de tienda) desde las bolsas listas hasta las 23:30; el envío desde
--    que está preparado hasta las 11:59 del día siguiente. El recuento no las borra.
-- 3. Lo que aún no ha salido (reparto, envío, pedidos) se aparta para lo que va
--    después: envío, «coge / haz» de los pedidos.
-- 4. Un pedido para recoger en tienda entra en el reparto de hoy mientras las
--    bolsas no estén listas (y, si no hay reparto, mientras «Prepara el reparto»
--    siga abierta); «Prepara el reparto» no se cierra sin reparto con un pedido
--    esperando.

insert into public.configuracion (clave, centro_id, valor) values
  ('en_camino_reparto_hasta', null, '"23:30"'),
  ('en_camino_envio_hasta', null, '"11:59"')
on conflict (clave, centro_id) do nothing;

create or replace function motor.config_hora(p_clave text, p_defecto time)
returns time language sql stable set search_path = '' as $$
  select coalesce((select (valor #>> '{}')::time from public.configuracion where clave = p_clave and centro_id is null),
                  p_defecto)
$$;

-- ---------------------------------------------------------------------------
-- Movimientos del almacén
-- ---------------------------------------------------------------------------
-- Último recuento hecho (tareas con contenido «recuento») hasta ese momento.
create or replace function motor.ultimo_recuento(p_operario uuid, p_momento timestamptz)
returns timestamptz language sql stable set search_path = '' as $$
  select max(t.terminada_en)
    from public.tareas t join public.jornadas j on j.id = t.jornada_id
   where j.persona_id = p_operario and t.contenido = 'recuento' and t.estado = 'hecha'
     and t.terminada_en <= p_momento
$$;

-- Lo producido y marcado (en un pedido, solo lo que había que hacer) y lo que ha
-- salido del almacén entre dos momentos.
create or replace function motor.movimientos_almacen(p_operario uuid, p_desde timestamptz, p_hasta timestamptz)
returns table (movimiento text, tarea_id uuid, clave text, producto text, formato text, cantidad integer)
language sql stable set search_path = '' as $$
  select 'producido', t.id, t.clave, e.producto, e.formato,
         case when e.lote = 'pedido' then least(e.cantidad_hecha, coalesce((e.calculo ->> 'haz')::int, e.cantidad_hecha))
              else e.cantidad_hecha end
    from public.tarea_elementos e
    join public.tareas t on t.id = e.tarea_id
    join public.jornadas j on j.id = t.jornada_id
   where j.persona_id = p_operario and e.tipo = 'referencia_produccion' and e.estado = 'hecho'
     and e.terminado_en > p_desde and e.terminado_en <= p_hasta
  union all
  select 'salido', t.id, t.clave, e.producto, e.formato, e.cantidad_hecha
    from public.tareas t
    join public.jornadas j on j.id = t.jornada_id
    join public.tarea_elementos e on e.tarea_id = t.id
   where j.persona_id = p_operario and t.estado = 'hecha'
     and t.terminada_en > p_desde and t.terminada_en <= p_hasta
     and ((t.clave in ('bolsas', 'preparar_envio', 'preparar_envio_viernes') and e.tipo = 'caja_bolsa')
          or (t.clave like 'pedido_nacex%' and e.tipo = 'referencia_produccion'))
$$;

-- Cajas en camino a cada tienda en ese momento.
create or replace function motor.en_camino_en(p_operario uuid, p_ahora timestamptz)
returns table (destino_id uuid, producto text, formato text, cantidad integer)
language sql stable set search_path = '' as $$
  select e.destino_id, e.producto, e.formato, sum(e.cantidad_hecha)::int
    from public.tareas t
    join public.jornadas j on j.id = t.jornada_id
    join public.tarea_elementos e on e.tarea_id = t.id and e.tipo = 'caja_bolsa'
   where j.persona_id = p_operario and t.estado = 'hecha'
     and t.terminada_en <= p_ahora and t.terminada_en > p_ahora - interval '3 days'
     and ((t.clave = 'bolsas'
           and p_ahora <= motor.en_local(motor.fecha_local(t.terminada_en),
                                         motor.config_hora('en_camino_reparto_hasta', '23:30')))
          or (t.clave in ('preparar_envio', 'preparar_envio_viernes')
              and p_ahora <= motor.en_local(motor.fecha_local(t.terminada_en) + 1,
                                            motor.config_hora('en_camino_envio_hasta', '11:59'))))
   group by 1, 2, 3
  having sum(e.cantidad_hecha) > 0
$$;

-- Lo comprometido de una jornada que en ese momento aún no ha salido del almacén:
-- reparto (hasta las bolsas listas), envío (hasta prepararlo) y pedidos (los de
-- tienda, con las bolsas; los de Nacex, al prepararlos).
create or replace function motor.pendiente_salir(p_jornada uuid, p_momento timestamptz)
returns table (origen text, pedido_id uuid, registrado_en timestamptz, producto text, formato text, cantidad integer)
language sql stable set search_path = '' as $$
  with salio as (
    select coalesce(bool_or(t.clave = 'bolsas'), false) as bolsas,
           coalesce(bool_or(t.clave in ('preparar_envio', 'preparar_envio_viernes')), false) as envio
      from public.tareas t
     where t.jornada_id = p_jornada and t.estado = 'hecha' and coalesce(t.terminada_en, '-infinity') <= p_momento
       and t.clave in ('bolsas', 'preparar_envio', 'preparar_envio_viernes'))
  select r.tipo, null::uuid, r.pegado_en, x ->> 'producto', coalesce(x ->> 'formato', ''), (x ->> 'pedido')::int
    from public.repartos r cross join salio s
    cross join lateral jsonb_array_elements(r.resultado -> 'produccion') with ordinality a(x, n)
   where r.jornada_id = p_jornada and r.estado = 'aceptado'
     and not case r.tipo when 'reparto' then s.bolsas else s.envio end
  union all
  select 'pedido_' || p.entrega, p.id, p.registrado_en, l ->> 'producto', coalesce(l ->> 'formato', ''),
         (l ->> 'cantidad')::int
    from public.pedidos_cliente p
    left join public.tareas t on t.id = p.tarea_id
    cross join salio s
    cross join lateral jsonb_array_elements(p.lineas) l
   where p.jornada_id = p_jornada and t.estado is distinct from 'cancelada'
     and case p.entrega when 'tienda' then not s.bolsas
                        else not (t.estado = 'hecha' and coalesce(t.terminada_en, '-infinity') <= p_momento) end
$$;

-- Lo comprometido y en camino para las funciones del servidor (envío y +35 %).
create or replace function motor.comprometido_en(p_jornada uuid, p_momento timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'reparto', coalesce((select jsonb_agg(jsonb_build_object('producto', x.producto, 'formato', x.formato, 'cantidad', x.cantidad))
                           from motor.pendiente_salir(p_jornada, p_momento) x where x.origen = 'reparto'), '[]'::jsonb),
    'envio', coalesce((select jsonb_agg(jsonb_build_object('producto', x.producto, 'formato', x.formato, 'cantidad', x.cantidad))
                         from motor.pendiente_salir(p_jornada, p_momento) x where x.origen = 'envio'), '[]'::jsonb),
    'pedidos_tienda', coalesce((select jsonb_agg(jsonb_build_object('producto', x.producto, 'formato', x.formato,
                                                                    'cantidad', x.cantidad) order by x.registrado_en)
                                  from motor.pendiente_salir(p_jornada, p_momento) x where x.origen = 'pedido_tienda'), '[]'::jsonb),
    'pedidos_nacex', coalesce((select jsonb_agg(jsonb_build_object('producto', x.producto, 'formato', x.formato,
                                                                   'cantidad', x.cantidad) order by x.registrado_en)
                                 from motor.pendiente_salir(p_jornada, p_momento) x where x.origen = 'pedido_nacex'), '[]'::jsonb),
    'en_camino', coalesce((select jsonb_agg(jsonb_build_object('destino_id', c.destino_id, 'producto', c.producto,
                                                               'formato', c.formato, 'cantidad', c.cantidad)
                                            order by c.destino_id, c.producto, c.formato)
                             from public.jornadas j, motor.en_camino_en(j.persona_id, p_momento) c
                            where j.id = p_jornada), '[]'::jsonb))
$$;

create or replace function motor.comprometido(p_jornada uuid)
returns jsonb language sql stable set search_path = '' as $$
  select motor.comprometido_en(p_jornada, now())
$$;

comment on function motor.hoja_sin_reparto(uuid, timestamptz) is
  'Obsoleta desde la Tarea 14 (R1c rehecha): ya no la usa nadie.';

-- Cajas por referencia: [{ producto, formato, cantidad }] sumadas.
create or replace function motor.cajas_movimiento(p_operario uuid, p_desde timestamptz, p_hasta timestamptz,
                                                  p_movimiento text, p_tarea uuid default null)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('producto', m.producto, 'formato', m.formato, 'cantidad', m.c)
                            order by m.producto, m.formato), '[]'::jsonb)
    from (select x.producto, x.formato, sum(x.cantidad)::int as c
            from motor.movimientos_almacen(p_operario, p_desde, p_hasta) x
           where x.movimiento = p_movimiento and (p_tarea is null or x.tarea_id = p_tarea)
           group by 1, 2 having sum(x.cantidad) <> 0) m
$$;

-- Almacén ahora, por referencia con movimiento desde el recuento (para el panel).
create or replace function motor.almacen_ahora_de(p_operario uuid, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  l public.lecturas_sheets;
  v_desde timestamptz;
begin
  select * into l from public.lecturas_sheets where correcto and leido_en <= p_ahora order by leido_en desc limit 1;
  v_desde := coalesce(motor.ultimo_recuento(p_operario, coalesce(l.leido_en, p_ahora)), l.leido_en, p_ahora);
  return jsonb_build_object(
    'recuento_en', motor.ultimo_recuento(p_operario, coalesce(l.leido_en, p_ahora)),
    'datos_leidos_en', l.leido_en,
    'referencias', coalesce((
      select jsonb_agg(jsonb_build_object('producto', m.producto, 'formato', m.formato, 'hoja', m.hoja,
                                          'producido', m.producido, 'salido', m.salido,
                                          'ahora', m.hoja + m.producido - m.salido)
                       order by m.producto, m.formato)
        from (select x.producto, x.formato,
                     coalesce((select motor.cajas_hoja(f ->> 'almacen')
                                 from jsonb_array_elements(l.datos -> 'productos') pr, jsonb_array_elements(pr -> 'formatos') f
                                where motor.clave_ref(pr ->> 'nombre', f ->> 'formato') = motor.clave_ref(x.producto, x.formato)
                                limit 1),
                              (select motor.cajas_hoja(pr ->> 'granel')
                                 from jsonb_array_elements(l.datos -> 'productos') pr
                                where jsonb_array_length(pr -> 'formatos') = 0
                                  and motor.clave_ref(pr ->> 'nombre', '') = motor.clave_ref(x.producto, x.formato)
                                limit 1), 0) as hoja,
                     coalesce(sum(x.cantidad) filter (where x.movimiento = 'producido'), 0)::int as producido,
                     coalesce(sum(x.cantidad) filter (where x.movimiento = 'salido'), 0)::int as salido
                from motor.movimientos_almacen(p_operario, v_desde, p_ahora) x
               group by 1, 2) m
       where m.producido <> 0 or m.salido <> 0), '[]'::jsonb),
    'en_camino', coalesce((
      select jsonb_agg(jsonb_build_object('destino_id', c.destino_id, 'destino', ct.nombre, 'producto', c.producto,
                                          'formato', c.formato, 'cantidad', c.cantidad)
                       order by ct.nombre, c.producto, c.formato)
        from motor.en_camino_en(p_operario, p_ahora) c join public.centros_trabajo ct on ct.id = c.destino_id),
      '[]'::jsonb));
end;
$$;

create or replace function motor.api_almacen_ahora()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.almacen_ahora_de(motor.operario_por_defecto(), now());
end; $$;

create or replace function public.estado_actual()
returns jsonb language plpgsql set search_path = '' as $$
declare
  r jsonb := motor.api_estado_actual();
begin
  if r ? 'error' then
    return r;
  end if;
  return r || jsonb_build_object('almacen_ahora', motor.api_almacen_ahora());
end;
$$;

-- ---------------------------------------------------------------------------
-- «Coge / haz» con el almacén ahora
-- ---------------------------------------------------------------------------
-- queda = almacén ahora (hoja + producido − salido desde su recuento) − lo que
-- aún no ha salido y va antes que este pedido (reparto, envío y pedidos
-- anteriores); coge = mín(cantidad, queda); haz = el resto.
create or replace function motor.calcular_pedido(p_tarea uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  p public.pedidos_cliente;
  t public.tareas;
  j public.jornadas;
  l public.lecturas_sheets;
  v_desde timestamptz;
  m record;
  e public.tarea_elementos;
  v_alm jsonb := '{}';
  v_usado jsonb := '{}';
  v_k text;
  v_queda integer;
  v_coge integer;
begin
  select * into p from public.pedidos_cliente where tarea_id = p_tarea;
  select * into t from public.tareas where id = p_tarea;
  if p.id is null or t.id is null then
    return;
  end if;
  select * into j from public.jornadas where id = t.jornada_id;
  select * into l from public.lecturas_sheets where correcto and leido_en <= p_ahora order by leido_en desc limit 1;

  if l.id is not null then
    select coalesce(jsonb_object_agg(k, c), '{}') into v_alm from (
      select motor.clave_ref(pr ->> 'nombre', f ->> 'formato') as k, motor.cajas_hoja(f ->> 'almacen') as c
        from jsonb_array_elements(l.datos -> 'productos') pr, jsonb_array_elements(pr -> 'formatos') f
      union all
      select motor.clave_ref(pr ->> 'nombre', ''), motor.cajas_hoja(pr ->> 'granel')
        from jsonb_array_elements(l.datos -> 'productos') pr
       where jsonb_array_length(pr -> 'formatos') = 0 and (pr ->> 'conTiendas')::boolean) a;
  end if;

  -- La hoja recoge el último recuento anterior a la lectura; desde ahí, lo producido y lo salido.
  v_desde := coalesce(motor.ultimo_recuento(j.persona_id, coalesce(l.leido_en, p_ahora)), l.leido_en, p_ahora);
  for m in select * from motor.movimientos_almacen(j.persona_id, v_desde, p_ahora) x where x.tarea_id <> p_tarea loop
    v_k := motor.clave_ref(m.producto, m.formato);
    v_alm := jsonb_set(v_alm, array[v_k], to_jsonb(coalesce((v_alm ->> v_k)::int, 0)
                                                   + case m.movimiento when 'producido' then m.cantidad else -m.cantidad end));
  end loop;

  select coalesce(jsonb_object_agg(k, c), '{}') into v_usado from (
    select motor.clave_ref(x.producto, x.formato) as k, sum(x.cantidad) as c
      from motor.pendiente_salir(j.id, p_ahora) x
     where x.pedido_id is null or (x.pedido_id <> p.id and x.registrado_en < p.registrado_en)
     group by 1) u;

  for e in select * from public.tarea_elementos
            where tarea_id = p_tarea and tipo = 'referencia_produccion'
            order by orden_sugerido, producto, formato loop
    v_k := motor.clave_ref(e.producto, e.formato);
    v_queda := greatest(coalesce((v_alm ->> v_k)::int, 0) - coalesce((v_usado ->> v_k)::int, 0), 0);
    v_coge := least(e.cantidad, v_queda);
    update public.tarea_elementos
       set motivo = motor.texto_coge_haz(v_coge, e.cantidad - v_coge),
           calculo = jsonb_build_object('coge', v_coge, 'haz', e.cantidad - v_coge, 'en_almacen', v_queda,
                                        'lectura_id', l.id, 'datos_leidos_en', l.leido_en, 'recuento_en', v_desde,
                                        'calculado_en', p_ahora)
     where id = e.id;
    v_usado := jsonb_set(v_usado, array[v_k], to_jsonb(coalesce((v_usado ->> v_k)::int, 0) + e.cantidad));
  end loop;
  perform motor.registrar('pedido_cliente_calculado', null, j.id, p_tarea,
                          jsonb_build_object('pedido', p.id, 'lectura', l.id, 'a_las', p_ahora));
end;
$$;

-- ---------------------------------------------------------------------------
-- servidor_preparar: lo comprometido y en camino ahora, y los movimientos del
-- almacén desde el último recuento.
-- ---------------------------------------------------------------------------
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
    'reparto_hoy', coalesce((select jsonb_agg(jsonb_build_object('producto', x ->> 'producto',
                                                                 'formato', coalesce(x ->> 'formato', ''),
                                                                 'pedido', (x ->> 'pedido')::int))
                             from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                             where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'), '[]'::jsonb),
    'recuento_manana_hecho', exists (select 1 from public.tareas t
                                     where t.jornada_id = v_jornada and t.clave = 'recuento_manana' and t.estado = 'hecha'),
    -- R1c: lo que aún no ha salido del almacén (reparto, envío, pedidos) y lo que va en camino a las tiendas.
    'comprometido', motor.comprometido_en(v_jornada, p_ahora),
    -- R1c: lo producido y lo salido desde el último recuento (la hoja aún no lo recoge).
    'almacen', jsonb_build_object(
      'recuento_en', v_recuento,
      'producido', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido'),
      'producido_reparto', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido',
                             (select id from public.tareas where jornada_id = v_jornada and clave = 'produccion_reparto')),
      'producido_envio', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido',
                           (select id from public.tareas where jornada_id = v_jornada
                               and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1)),
      'salido', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'salido')),
    -- Pedidos de cliente para recoger en tienda que van en el reparto de hoy (en orden de llegada).
    'pedidos_tienda', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'cliente', p.cliente, 'destino_id', p.destino_id,
                                          'lineas', p.lineas) order by p.registrado_en)
        from public.pedidos_cliente p
        left join public.tareas t on t.id = p.tarea_id
       where p.entrega = 'tienda' and t.estado is distinct from 'cancelada'
         and (p.jornada_id = v_jornada or (p.jornada_id is null and p.fecha_objetivo <= v_fecha))), '[]'::jsonb),
    'stock', case when v_stock is null or v_rol <> 'operario' then null else motor.tarea_json(v_stock) end);
end;
$$;

-- ---------------------------------------------------------------------------
-- Pedidos para recoger en tienda: activan el reparto de hoy
-- ---------------------------------------------------------------------------
-- Pedidos de tienda que esperan al reparto de ese día y aún no van en ninguno.
create or replace function motor.pedidos_tienda_esperando(p_jornada uuid)
returns setof public.pedidos_cliente language sql stable set search_path = '' as $$
  select p.* from public.pedidos_cliente p, public.jornadas j
   where j.id = p_jornada and p.entrega = 'tienda' and p.tarea_id is null and p.jornada_id is null
     and p.fecha_objetivo <= j.fecha
   order by p.registrado_en
$$;

create or replace function public.servidor_preparar_pedido(
  p_persona uuid, p_id_cliente uuid, p_entrega text, p_destino uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_operario uuid;
  v_hoy date := motor.fecha_local(p_ahora);
  v_jornada_hoy uuid;
  v_fecha date;
  v_jornada uuid;
  v_reparto uuid;
  v_previo uuid;
begin
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  select id into v_previo from public.pedidos_cliente where id_cliente = p_id_cliente;
  if v_previo is not null then
    return jsonb_build_object('previo', motor.pedido_json(v_previo));
  end if;
  if p_entrega is null or p_entrega not in ('tienda', 'nacex') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige cómo se entrega: recoger en tienda o envío por Nacex.');
  end if;
  if p_entrega = 'tienda' and not exists (
       select 1 from public.centros_trabajo c, public.configuracion k,
                     jsonb_array_elements_text(k.valor -> 'reparto') x
        where k.clave = 'destinos_reparto' and k.centro_id is null and c.id = p_destino and c.codigo = x) then
    return motor.error('DATOS_NO_VALIDOS', 'Elige una de las tiendas del reparto.');
  end if;

  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada_hoy := motor.generar_jornada(v_operario, v_hoy);
  end if;
  if p_entrega = 'tienda' then
    -- Hoy, mientras el reparto no haya salido (bolsas listas). Sin reparto todavía,
    -- mientras «Prepara el reparto» siga abierta: el pedido activa el reparto.
    select r.id into v_reparto from public.repartos r
     where r.jornada_id = v_jornada_hoy and r.tipo = 'reparto' and r.estado = 'aceptado';
    if v_jornada_hoy is not null
       and not exists (select 1 from public.tareas t
                        where t.jornada_id = v_jornada_hoy and t.clave = 'bolsas' and t.estado = 'hecha')
       and (v_reparto is not null
            or exists (select 1 from public.tareas t
                        where t.jornada_id = v_jornada_hoy and t.clave = 'pegar_reparto'
                          and t.estado in ('pendiente', 'en_curso', 'bloqueada'))) then
      v_fecha := v_hoy;
    elsif v_operario is not null then
      v_fecha := motor.siguiente_dia_trabajo(v_operario, v_hoy);
      v_reparto := null;
    end if;
  elsif v_jornada_hoy is not null
        and p_ahora < motor.en_local(v_hoy, case when extract(isodow from v_hoy) = 5 then time '10:45' else time '18:00' end)
        and not exists (select 1 from public.tareas t
                         where t.jornada_id = v_jornada_hoy and t.clave in ('nacex_salida', 'nacex_viernes')
                           and t.estado = 'hecha') then
    v_fecha := v_hoy;
    v_jornada := v_jornada_hoy;
  elsif v_operario is not null then
    v_fecha := motor.siguiente_dia_trabajo(v_operario, v_hoy);
    v_jornada := motor.jornada_para(v_operario, v_fecha, p_ahora);
  end if;
  if v_fecha is null or (p_entrega = 'nacex' and v_jornada is null) then
    return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
  end if;

  return jsonb_build_object(
    'rol', v_rol, 'fecha', v_fecha, 'jornada_id', v_jornada,
    -- Recoger en tienda con el reparto de hoy ya guardado: entra en él al momento.
    'reparto_id', v_reparto,
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas')),
    'comprometido', motor.comprometido_en(coalesce(v_jornada, v_jornada_hoy), p_ahora));
end;
$$;

-- «Prepara el reparto» sin reparto aceptado: con motivo, salvo si hay un pedido
-- para recoger en tienda esperando (entonces hay que preparar el reparto, aunque
-- sea solo con el pedido).
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
  if t.estado <> 'en_curso' then
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
   where id = t.id and estado = 'en_curso';
  update public.tarea_elementos set estado = 'pendiente' where tarea_id = t.id and estado = 'en_curso';
  perform motor.registrar('tarea_terminada', p_persona, j.id, t.id,
                          jsonb_build_object('a_las', p_ahora, 'resultado', p_resultado,
                                             'motivo', p_motivo, 'pendientes', v_pendientes));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema motor from public;
grant execute on function motor.api_almacen_ahora() to authenticated;
revoke execute on function public.estado_actual() from public, anon;
grant execute on function public.estado_actual() to authenticated;
