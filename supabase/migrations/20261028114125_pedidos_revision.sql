-- Tarea 12 (revisión del propietario, 28/10/2026) · Pedidos de cliente.
-- 1. Salida del reparto = bolsas listas (las termina siempre el almacén, salga
--    quien salga; el viernes, también el envío preparado). Lo que sale con el
--    reparto (reparto, pedidos de tienda y, el viernes, envío y pedidos de
--    Nacex) lo sigue contando la hoja en el almacén
--    hasta el recuento de la mañana; si el recuento es después de la salida, desde
--    ese momento ya no está en el almacén de la hoja y va «en camino».
-- 2. «Coge / haz» se calcula al salir la tarea de prepararlo (cuando le toca al
--    operario), con la última lectura de la hoja y lo que la hoja contaba en ese
--    momento.
-- 3. Nacex: de lunes a jueves los pedidos entran hasta las 18:00; si no, al
--    siguiente día de trabajo. El operario puede pasarlo al día siguiente
--    (aplazar_pedido_nacex) y, si queda sin hacer, pasa solo con Nacex activado.

-- ---------------------------------------------------------------------------
-- R1c con la salida = bolsas listas
-- ---------------------------------------------------------------------------
-- ¿La hoja (tal como estaba en p_momento) ya no cuenta en el almacén lo que sale
-- con el reparto? Sí si en ese momento había salido (bolsas listas y, el viernes,
-- el envío preparado) y el recuento de la mañana estaba hecho después.
create or replace function motor.hoja_sin_reparto(p_jornada uuid, p_momento timestamptz)
returns boolean language sql stable set search_path = '' as $$
  with s as (
    select count(*) > 0 and bool_and(estado = 'hecha' and coalesce(terminada_en, '-infinity') <= p_momento) as salio,
           max(coalesce(terminada_en, '-infinity')) as salida
      from public.tareas
     where jornada_id = p_jornada and clave in ('bolsas', 'preparar_envio_viernes') and estado <> 'cancelada')
  select coalesce((
    select s.salio and coalesce(r.terminada_en, '-infinity') >= s.salida
      from s, public.tareas r
     where r.jornada_id = p_jornada and r.clave = 'recuento_manana' and r.estado = 'hecha'
       and coalesce(r.terminada_en, '-infinity') <= p_momento), false);
$$;

-- Lo comprometido ese día tal como lo veía la hoja en p_momento (R1c).
create or replace function motor.comprometido_en(p_jornada uuid, p_momento timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
  v_fuera boolean;
  v_viernes boolean;
  v_reparto jsonb;
  v_envio jsonb;
  v_tienda jsonb;
  v_nacex jsonb;
  v_vacio constant jsonb := '[]';
begin
  select * into j from public.jornadas where id = p_jornada;
  if j.id is null then
    return jsonb_build_object('reparto', v_vacio, 'pedidos_tienda', v_vacio, 'envio', v_vacio,
                              'pedidos_nacex', v_vacio, 'en_camino', v_vacio);
  end if;
  v_fuera := motor.hoja_sin_reparto(j.id, p_momento);
  v_viernes := extract(isodow from j.fecha) = 5;

  select coalesce(jsonb_agg(jsonb_build_object('producto', x ->> 'producto', 'formato', coalesce(x ->> 'formato', ''),
                                               'cantidad', (x ->> 'pedido')::int) order by n)
                  filter (where r.tipo = 'reparto'), v_vacio),
         coalesce(jsonb_agg(jsonb_build_object('producto', x ->> 'producto', 'formato', coalesce(x ->> 'formato', ''),
                                               'cantidad', (x ->> 'pedido')::int) order by n)
                  filter (where r.tipo = 'envio'), v_vacio)
    into v_reparto, v_envio
    from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') with ordinality x(x, n)
   where r.jornada_id = j.id and r.estado = 'aceptado';

  select coalesce(jsonb_agg(l order by p.registrado_en, n) filter (where p.entrega = 'tienda'), v_vacio),
         coalesce(jsonb_agg(l order by p.registrado_en, n) filter (where p.entrega = 'nacex'), v_vacio)
    into v_tienda, v_nacex
    from public.pedidos_cliente p
    left join public.tareas t on t.id = p.tarea_id
    cross join lateral jsonb_array_elements(p.lineas) with ordinality l(l, n)
   where p.jornada_id = j.id and t.estado is distinct from 'cancelada';

  v_reparto := coalesce(v_reparto, v_vacio);
  v_envio := coalesce(v_envio, v_vacio);
  v_tienda := coalesce(v_tienda, v_vacio);
  v_nacex := coalesce(v_nacex, v_vacio);
  return jsonb_build_object(
    'reparto', case when v_fuera then v_vacio else v_reparto end,
    'pedidos_tienda', case when v_fuera then v_vacio else v_tienda end,
    'envio', case when v_viernes and v_fuera then v_vacio else v_envio end,
    'pedidos_nacex', case when v_viernes and v_fuera then v_vacio else v_nacex end,
    'en_camino', case when not v_fuera then v_vacio
                      when v_viernes then v_reparto || v_tienda || v_envio || v_nacex
                      else v_reparto || v_tienda end);
end;
$$;

-- Ahora (para servidor_preparar: el envío, Nacex y la lista del +35 %).
create or replace function motor.comprometido(p_jornada uuid)
returns jsonb language sql stable set search_path = '' as $$
  select motor.comprometido_en(p_jornada, 'infinity')
$$;

-- ---------------------------------------------------------------------------
-- «Coge / haz» al salir la tarea del pedido
-- ---------------------------------------------------------------------------
-- Cajas de una celda de la hoja (vacío, texto o negativo: 0, como en R1).
create or replace function motor.cajas_hoja(p_texto text)
returns integer language sql immutable set search_path = '' as $$
  select case when btrim(coalesce(p_texto, '')) ~ '^-?\d+([.,]\d{1,2})?$'
              then greatest(floor(replace(btrim(p_texto), ',', '.')::numeric), 0)::int else 0 end
$$;

create or replace function motor.clave_ref(p_producto text, p_formato text)
returns text language sql immutable set search_path = '' as $$
  select upper(regexp_replace(coalesce(p_producto, '') || coalesce(p_formato, ''), '\s', '', 'g'))
$$;

create or replace function motor.texto_coge_haz(p_coge integer, p_haz integer)
returns text language sql immutable set search_path = '' as $$
  select case when p_coge > 0 and p_haz > 0 then 'Coge ' || p_coge || ' del almacén y haz ' || p_haz
              when p_coge > 0 then 'Coge ' || p_coge || ' del almacén'
              else 'Haz ' || p_haz end
$$;

-- Cada referencia: queda = máx(0, almacén de la hoja − lo comprometido antes que
-- este pedido y que la hoja aún contaba); coge = mín(cantidad, queda); haz = el resto.
-- Antes que el pedido: el reparto y el envío de ese día (lo oficial) y los pedidos
-- que llegaron antes. La hoja es la de la última lectura correcta.
create or replace function motor.calcular_pedido(p_tarea uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  p public.pedidos_cliente;
  t public.tareas;
  j public.jornadas;
  l public.lecturas_sheets;
  v_fuera boolean;
  v_viernes boolean;
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
  v_fuera := l.id is not null and motor.hoja_sin_reparto(j.id, l.leido_en);
  v_viernes := extract(isodow from j.fecha) = 5;

  -- Almacén según la hoja leída (productos con formato; y los que no tienen formato).
  if l.id is not null then
    select coalesce(jsonb_object_agg(k, c), '{}') into v_alm from (
      select motor.clave_ref(pr ->> 'nombre', f ->> 'formato') as k, motor.cajas_hoja(f ->> 'almacen') as c
        from jsonb_array_elements(l.datos -> 'productos') pr, jsonb_array_elements(pr -> 'formatos') f
      union all
      select motor.clave_ref(pr ->> 'nombre', ''), motor.cajas_hoja(pr ->> 'granel')
        from jsonb_array_elements(l.datos -> 'productos') pr
       where jsonb_array_length(pr -> 'formatos') = 0 and (pr ->> 'conTiendas')::boolean) a;
  end if;

  -- Lo comprometido antes que este pedido que la hoja aún contaba en el almacén.
  select coalesce(jsonb_object_agg(k, c), '{}') into v_usado from (
    select motor.clave_ref(x ->> 'producto', x ->> 'formato') as k, sum((x ->> 'cantidad')::int) as c
      from (
        select jsonb_build_object('producto', y ->> 'producto', 'formato', y ->> 'formato', 'cantidad', y ->> 'pedido') as x
          from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') y
         where r.jornada_id = j.id and r.estado = 'aceptado'
           and (r.tipo = 'envio' and not (v_viernes and v_fuera) or r.tipo = 'reparto' and not v_fuera)
        union all
        select x
          from public.pedidos_cliente o
          left join public.tareas ot on ot.id = o.tarea_id
          cross join lateral jsonb_array_elements(o.lineas) l(x)
         where o.jornada_id = j.id and o.id <> p.id and o.registrado_en < p.registrado_en
           and ot.estado is distinct from 'cancelada'
           and (o.entrega = 'nacex' and not (v_viernes and v_fuera) or o.entrega = 'tienda' and not v_fuera)) s
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
                                        'lectura_id', l.id, 'datos_leidos_en', l.leido_en, 'calculado_en', p_ahora)
     where id = e.id;
    v_usado := jsonb_set(v_usado, array[v_k], to_jsonb(coalesce((v_usado ->> v_k)::int, 0) + e.cantidad));
  end loop;
  perform motor.registrar('pedido_cliente_calculado', null, j.id, p_tarea,
                          jsonb_build_object('pedido', p.id, 'lectura', l.id, 'a_las', p_ahora));
end;
$$;

-- La lista del pedido (el «coge / haz» se pone al salir la tarea). Repetirlo no
-- cambia lo ya calculado ni lo hecho.
create or replace function motor.poner_elementos_pedido(p_tarea uuid, p_elementos jsonb, p_lectura uuid)
returns void language sql set search_path = '' as $$
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, cantidad, orden_sugerido)
  select p_tarea, 'referencia_produccion', 'pedido', x ->> 'producto', coalesce(x ->> 'formato', ''), x ->> 'categoria',
         (x ->> 'cantidad')::int, coalesce((x ->> 'orden')::int, 0)
    from jsonb_array_elements(coalesce(p_elementos, '[]')) x
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set orden_sugerido = excluded.orden_sugerido, categoria = coalesce(excluded.categoria, public.tarea_elementos.categoria);
$$;

-- tarea_activa: al salir la tarea de un pedido de cliente se calcula su «coge / haz».
create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_jornada uuid;
  j public.jornadas;
  v_tarea uuid;
  v_sig uuid;
  v_prox uuid;
  s public.tareas;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return jsonb_build_object('jornada', null, 'pregunta', null, 'tarea', null, 'siguiente', null, 'reparto_de_hoy', null)
           || motor.seguimiento_de(p_persona, p_ahora);
  end if;
  select * into j from public.jornadas where id = v_jornada;

  v_tarea := motor.elegir_tarea(v_jornada, p_ahora, null);
  -- Pedido de cliente: «coge / haz» al salir su tarea (una sola vez).
  if v_tarea is not null
     and exists (select 1 from public.pedidos_cliente where tarea_id = v_tarea)
     and not exists (select 1 from public.tarea_elementos where tarea_id = v_tarea and calculo ? 'calculado_en') then
    perform motor.calcular_pedido(v_tarea, p_ahora);
  end if;
  -- «Lo que viene después»: lo que tocaría sin la tarea actual; pero si antes
  -- llega una tarea con hora (o el siguiente turno), se muestra esa.
  v_sig := motor.elegir_tarea(v_jornada, p_ahora, v_tarea);
  select t.id into v_prox from public.tareas t
   where t.jornada_id = v_jornada and t.estado = 'pendiente'
     and t.disponible_desde > p_ahora and t.id is distinct from v_tarea
   order by t.disponible_desde, t.orden limit 1;
  if v_prox is not null
     and (v_sig is null
          or (select motor.escalon(t) > 4 from public.tareas t where t.id = v_sig)) then
    v_sig := v_prox;
  end if;
  select * into s from public.tareas where id = v_sig;

  return jsonb_build_object(
    'jornada', jsonb_build_object('id', j.id, 'fecha', j.fecha, 'sale', j.sale, 'hay_envio', j.hay_envio),
    'pregunta', null,
    'tarea', motor.tarea_json(v_tarea),
    'siguiente', case when v_sig is null then null else
      s.titulo || coalesce(' · ' || motor.hora_texto(coalesce(s.hora_programada,
                    case when s.disponible_desde > p_ahora then s.disponible_desde end)), '') end,
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre)
        from public.repartos r left join public.personas pe on pe.id = r.pegado_por
       where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'))
    || motor.seguimiento_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- Nacex: pasar un pedido al día siguiente (a mano o si queda sin hacer)
-- ---------------------------------------------------------------------------
-- La tarea pasa a la jornada de destino como tarea de Nacex de ese día (por la
-- tarde de lunes a jueves; el viernes, antes de las 10:45), con su lista (lo
-- hecho, hecho; el «coge / haz» se vuelve a calcular al salir) y Nacex activado.
create or replace function motor.mover_pedido_nacex(p_pedido uuid, p_destino uuid, p_motivo text, p_persona uuid)
returns uuid language plpgsql set search_path = '' as $$
declare
  p public.pedidos_cliente;
  t public.tareas;
  v_nueva uuid;
begin
  select * into p from public.pedidos_cliente where id = p_pedido and entrega = 'nacex' for update;
  select * into t from public.tareas where id = p.tarea_id;
  if p.id is null or t.id is null or t.jornada_id = p_destino then
    return null;
  end if;
  select id into v_nueva from motor.crear_tarea_condicionada(p_destino, 'pedido_nacex', p.id::text) id limit 1;
  if v_nueva is null then
    raise exception 'No hay tarea para el pedido de cliente de ese día';
  end if;
  update public.tareas
     set titulo = t.titulo, porque = t.porque, creada_por = t.creada_por, tarea_origen_id = t.id
   where id = v_nueva;
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, cantidad, cantidad_hecha,
                                      orden_sugerido, estado, terminado_en)
  select v_nueva, e.tipo, e.lote, e.producto, e.formato, e.categoria, e.cantidad, e.cantidad_hecha,
         e.orden_sugerido, case when e.estado = 'hecho' then 'hecho' else 'pendiente' end, e.terminado_en
    from public.tarea_elementos e where e.tarea_id = t.id
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do nothing;
  update public.tareas set estado = 'arrastrada', motivo_no_hecha = coalesce(p_motivo, motivo_no_hecha) where id = t.id;
  update public.pedidos_cliente
     set tarea_id = v_nueva, jornada_id = p_destino,
         fecha_objetivo = (select fecha from public.jornadas where id = p_destino)
   where id = p.id;
  perform motor.fijar_envio(p_destino, true, null);
  perform motor.registrar('pedido_cliente_aplazado', p_persona, p_destino, v_nueva,
                          jsonb_build_object('pedido', p.id, 'desde', t.id, 'motivo', p_motivo));
  return v_nueva;
end;
$$;

create or replace function motor.aplazar_pedido_nacex_de(p_persona uuid, p_pedido uuid, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  p public.pedidos_cliente;
  t public.tareas;
  j public.jornadas;
  v_fecha date;
  v_destino uuid;
begin
  select * into p from public.pedidos_cliente where id = p_pedido;
  select * into t from public.tareas where id = p.tarea_id;
  select * into j from public.jornadas where id = t.jornada_id;
  if p.id is null or (v_rol = 'operario' and j.persona_id is distinct from p_persona) then
    return motor.error('NO_ENCONTRADO', 'Ese pedido no existe.');
  end if;
  if p.entrega <> 'nacex' then
    return motor.error('DATOS_NO_VALIDOS', 'Solo se pasan al día siguiente los pedidos de Nacex.');
  end if;
  if t.estado not in ('pendiente', 'en_curso', 'bloqueada') then
    return motor.error('ESTADO_NO_VALIDO', 'Ese pedido ya está preparado o cancelado.', jsonb_build_object('estado', t.estado));
  end if;
  v_fecha := motor.siguiente_dia_trabajo(j.persona_id, greatest(j.fecha, motor.fecha_local(p_ahora)));
  v_destino := case when v_fecha is not null then motor.jornada_para(j.persona_id, v_fecha, p_ahora) end;
  if v_destino is null then
    return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
  end if;
  perform motor.mover_pedido_nacex(p.id, v_destino,
            'Pasa al ' || to_char(v_fecha, 'DD/MM') || coalesce(': ' || nullif(btrim(p_motivo), ''), ''), p_persona);
  return jsonb_build_object('pedido', motor.pedido_json(p.id),
                            'tarea_activa', case when v_rol = 'operario' then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

create or replace function motor.api_aplazar_pedido_nacex(p_pedido uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.aplazar_pedido_nacex_de(auth.uid(), p_pedido, p_motivo, now());
end; $$;

create or replace function public.aplazar_pedido_nacex(pedido_id uuid, motivo text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_aplazar_pedido_nacex(pedido_id, motivo) $$;

-- Lo que no se termina pasa al día siguiente; un pedido de Nacex, como tarea de
-- Nacex de ese día y con Nacex activado.
create or replace function motor.arrastrar(p_jornada uuid)
returns void language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_anterior uuid;
  t public.tareas;
  v_id uuid;
  v_pedido uuid;
begin
  select * into j from public.jornadas where id = p_jornada;
  select id into v_anterior from public.jornadas
   where persona_id = j.persona_id and fecha < j.fecha
   order by fecha desc limit 1;
  if v_anterior is null then
    return;
  end if;

  for t in
    select * from public.tareas
    where jornada_id = v_anterior
      and estado in ('pendiente', 'en_curso', 'bloqueada')
      and no_terminada in ('arrastrar', 'sigue_abierta')
    order by orden, creada_en
  loop
    select id into v_pedido from public.pedidos_cliente where tarea_id = t.id and entrega = 'nacex';
    if v_pedido is not null then
      perform motor.mover_pedido_nacex(v_pedido, j.id, 'Pasa al ' || to_char(j.fecha, 'DD/MM') || ': no se terminó', null);
      continue;
    end if;

    insert into public.tareas (
      jornada_id, clave, origen, plantilla_id, titulo, porque, contenido, obligatoria,
      prioridad_cola, disponible_desde, urgente, duracion_min, no_terminada, orden,
      tarea_origen_id, creada_por)
    values (
      j.id, 'arrastre:' || t.id, t.origen, t.plantilla_id, t.titulo, t.porque, t.contenido, t.obligatoria,
      t.prioridad_cola, motor.inicio_turno(j.persona_id, j.fecha, null), t.urgente, t.duracion_min,
      t.no_terminada, t.orden, t.id, t.creada_por)
    on conflict (jornada_id, clave) do nothing
    returning id into v_id;

    update public.tareas set estado = 'arrastrada' where id = t.id;
    if v_id is not null then
      update public.incidencias set tarea_resolucion_id = v_id where tarea_resolucion_id = t.id;
      update public.pedidos_cliente set tarea_id = v_id where tarea_id = t.id;
      -- La lista pasa con lo hecho; el «coge / haz» de un pedido se vuelve a calcular al salir.
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, destino_id, cantidad,
                                          cantidad_hecha, motivo, orden_sugerido, calculo, estado, terminado_en)
      select v_id, e.tipo, e.lote, e.producto, e.formato, e.categoria, e.destino_id, e.cantidad,
             e.cantidad_hecha, case when e.lote = 'pedido' then null else e.motivo end, e.orden_sugerido,
             case when e.lote = 'pedido' then '{}'::jsonb else e.calculo end,
             case when e.estado = 'hecho' then 'hecho' else 'pendiente' end, e.terminado_en
        from public.tarea_elementos e where e.tarea_id = t.id;
    end if;
    perform motor.registrar('tarea_arrastrada', null, j.id, coalesce(v_id, t.id),
                            jsonb_build_object('desde', t.id));
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Nacex: de lunes a jueves, hasta las 18:00 (el viernes, hasta las 10:45).
-- ---------------------------------------------------------------------------
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
    if v_jornada_hoy is not null
       and not exists (select 1 from public.repartos r
                        where r.jornada_id = v_jornada_hoy and r.tipo = 'reparto' and r.estado = 'aceptado') then
      v_fecha := v_hoy;
    elsif v_operario is not null then
      v_fecha := motor.siguiente_dia_trabajo(v_operario, v_hoy);
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
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas')),
    'comprometido', motor.comprometido(v_jornada));
end;
$$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_aplazar_pedido_nacex(uuid, text) to authenticated;
revoke execute on function public.aplazar_pedido_nacex(uuid, text) from public, anon;
grant execute on function public.aplazar_pedido_nacex(uuid, text) to authenticated;
