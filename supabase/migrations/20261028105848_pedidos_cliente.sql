-- Tarea 12 · Pedidos de cliente con la lista y cajas en camino
-- (ESTADO_DEL_SISTEMA.md v1.24, §5 R1b y R1c).
-- La función del servidor `guardar_pedido_cliente` lee la hoja y calcula «coge /
-- haz»; aquí, lo que necesita de la base de datos:
-- 1. pedidos_cliente: el pedido con su lista y cómo se entrega (recoger en una
--    tienda o envío por Nacex). Los datos de envío solo los ve el personal.
-- 2. Recoger en tienda: el pedido espera al siguiente reparto calculado; al
--    guardarlo, `guardar_reparto` lo asigna (servidor_asignar_pedidos): tarea
--    «Hay un pedido de cliente para dejar en [tienda]» (después de la producción
--    del reparto) y bolsa aparte «Pedido de cliente · [cliente]».
-- 3. Nacex: tarea «Prepara el pedido de cliente (Nacex)» con la lista y los datos
--    de envío, y Nacex activado ese día (como hay_envio, sin duplicar tareas).
-- 4. Cajas en camino (R1c): lo comprometido hoy que la hoja aún cuenta en el
--    almacén, y lo que ya ha salido hacia las tiendas (motor.comprometido).
-- 5. pedidos_cliente_abiertos() para el panel y para el operario.
-- Las plantillas de las tareas nuevas van en la migración siguiente, junto con
-- las restricciones que las permiten.

create table public.pedidos_cliente (
  id              uuid primary key default gen_random_uuid(),
  id_cliente      uuid not null unique,
  cliente         text not null check (btrim(cliente) <> ''),
  entrega         text not null check (entrega in ('tienda', 'nacex')),
  destino_id      uuid references public.centros_trabajo (id),
  datos_envio     text,
  lineas          jsonb not null,
  fecha_objetivo  date not null,
  jornada_id      uuid references public.jornadas (id),
  reparto_id      uuid references public.repartos (id),
  tarea_id        uuid references public.tareas (id),
  lectura_id      uuid references public.lecturas_sheets (id),
  registrado_por  uuid not null references public.personas (id),
  registrado_en   timestamptz not null,
  check ((entrega = 'tienda' and destino_id is not null)
         or (entrega = 'nacex' and nullif(btrim(datos_envio), '') is not null))
);
create index pedidos_cliente_jornada on public.pedidos_cliente (jornada_id);
create index pedidos_cliente_esperando on public.pedidos_cliente (fecha_objetivo) where jornada_id is null;
comment on table public.pedidos_cliente is
  'Pedidos de cliente (R1b): la lista, cómo se entrega y en qué jornada se prepara. Datos del cliente: solo el personal.';
comment on column public.pedidos_cliente.fecha_objetivo is
  'Recoger en tienda: primer día cuyo reparto lo lleva. Nacex: día de la salida a Nacex.';

revoke all on public.pedidos_cliente from anon, authenticated;
grant select on public.pedidos_cliente to authenticated;
alter table public.pedidos_cliente enable row level security;
-- Solo el personal (cualquier persona activa con ficha) ve los pedidos y sus datos de envío.
create policy lectura on public.pedidos_cliente for select to authenticated
  using ((select motor.es_admin())
         or exists (select 1 from public.personas p where p.id = (select auth.uid()) and p.activo));

-- ---------------------------------------------------------------------------
-- Ayudas
-- ---------------------------------------------------------------------------
create or replace function motor.siguiente_dia_trabajo(p_persona uuid, p_fecha date)
returns date language sql stable set search_path = '' as $$
  select min(d::date) from generate_series(p_fecha + 1, p_fecha + 14, interval '1 day') d
   where exists (select 1 from public.horarios h
                  where h.persona_id = p_persona and h.dia_semana = extract(isodow from d));
$$;

-- R1c · Lo comprometido hoy, por referencia ({ producto, formato, cantidad }):
--   reparto y pedidos de tienda (salen con el reparto) y, el viernes, envío y
--   pedidos de Nacex (también salen por la mañana): la hoja los cuenta en el
--   almacén hasta el recuento de la mañana; después ya no están en el almacén
--   y van «en camino» a las tiendas hasta la mañana siguiente.
--   De lunes a jueves, el envío y los pedidos de Nacex salen a las 18:10: la hoja
--   los cuenta en el almacén todo el día.
create or replace function motor.comprometido(p_jornada uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
  v_recuento boolean;
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
  v_recuento := exists (select 1 from public.tareas t
                         where t.jornada_id = j.id and t.clave = 'recuento_manana' and t.estado = 'hecha');
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
    'reparto', case when v_recuento then v_vacio else v_reparto end,
    'pedidos_tienda', case when v_recuento then v_vacio else v_tienda end,
    'envio', case when v_viernes and v_recuento then v_vacio else v_envio end,
    'pedidos_nacex', case when v_viernes and v_recuento then v_vacio else v_nacex end,
    'en_camino', case when not v_recuento then v_vacio
                      when v_viernes then v_reparto || v_tienda || v_envio || v_nacex
                      else v_reparto || v_tienda end);
end;
$$;

create or replace function motor.pedido_json(p_pedido uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'cliente', p.cliente, 'entrega', p.entrega,
    'entrega_texto', case p.entrega when 'tienda' then 'Recoger en ' || c.nombre else 'Envío por Nacex' end,
    'destino_id', p.destino_id, 'destino', c.nombre, 'datos_envio', p.datos_envio, 'lineas', p.lineas,
    'fecha', f.fecha, 'estado', e.estado,
    'estado_texto', case e.estado
      when 'esperando_reparto' then 'Va en el próximo reparto a ' || c.nombre
                                    || case when f.fecha > motor.fecha_local(now())
                                            then ' (desde el ' || to_char(f.fecha, 'DD/MM') || ')' else '' end
      when 'por_preparar' then case p.entrega when 'tienda' then 'En el reparto del ' || to_char(f.fecha, 'DD/MM') || ': por preparar'
                                              else 'Por preparar: sale a Nacex el ' || to_char(f.fecha, 'DD/MM') end
      when 'preparado' then case p.entrega when 'tienda' then 'Preparado: va en el reparto del ' || to_char(f.fecha, 'DD/MM')
                                           else 'Preparado: sale a Nacex el ' || to_char(f.fecha, 'DD/MM') end
      else 'Cancelado' end,
    'tarea_id', p.tarea_id, 'registrado_en', p.registrado_en,
    'registrado_por', p.registrado_por, 'registrado_por_nombre', pe.nombre)
  from public.pedidos_cliente p
  left join public.centros_trabajo c on c.id = p.destino_id
  left join public.tareas t on t.id = p.tarea_id
  left join public.personas pe on pe.id = p.registrado_por
  cross join lateral (select coalesce((select jo.fecha from public.jornadas jo where jo.id = coalesce(t.jornada_id, p.jornada_id)),
                                      p.fecha_objetivo) as fecha) f
  cross join lateral (select case when p.tarea_id is null then 'esperando_reparto'
                                  when t.estado = 'hecha' then 'preparado'
                                  when t.estado = 'cancelada' then 'cancelado'
                                  else 'por_preparar' end as estado) e
  where p.id = p_pedido;
$$;

-- Lista de un pedido con «coge / haz» (la calcula la función del servidor).
create or replace function motor.poner_elementos_pedido(p_tarea uuid, p_elementos jsonb, p_lectura uuid)
returns void language sql set search_path = '' as $$
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, cantidad, motivo,
                                      orden_sugerido, calculo)
  select p_tarea, 'referencia_produccion', 'pedido', x ->> 'producto', coalesce(x ->> 'formato', ''), x ->> 'categoria',
         (x ->> 'cantidad')::int, x ->> 'motivo', coalesce((x ->> 'orden')::int, 0),
         jsonb_build_object('coge', (x ->> 'coge')::int, 'haz', (x ->> 'haz')::int,
                            'en_almacen', (x ->> 'en_almacen')::int, 'lectura_id', p_lectura)
    from jsonb_array_elements(coalesce(p_elementos, '[]')) x
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set motivo = excluded.motivo, calculo = excluded.calculo, orden_sugerido = excluded.orden_sugerido;
$$;

-- ---------------------------------------------------------------------------
-- guardar_pedido_cliente (función del servidor): preparar y guardar
-- ---------------------------------------------------------------------------
-- Decide el día: recoger en tienda → el reparto de hoy si aún no está calculado
-- (si no, el siguiente día de trabajo); Nacex → hoy si aún da tiempo (lunes a
-- jueves antes de las 18:10 y sin la salida a Nacex hecha; viernes antes de las
-- 10:45), si no, el siguiente día de trabajo.
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
        and p_ahora < motor.en_local(v_hoy, case when extract(isodow from v_hoy) = 5 then time '10:45' else time '18:10' end)
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

create or replace function public.servidor_guardar_pedido_cliente(
  p_persona uuid, p_id_cliente uuid, p_cliente text, p_entrega text, p_destino uuid, p_datos_envio text,
  p_lineas jsonb, p_fecha date, p_jornada uuid, p_lectura uuid, p_elementos jsonb, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_cliente text := regexp_replace(btrim(coalesce(p_cliente, '')), '\s+', ' ', 'g');
  v_id uuid;
  v_tarea uuid;
begin
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  insert into public.pedidos_cliente (id_cliente, cliente, entrega, destino_id, datos_envio, lineas, fecha_objetivo,
                                      jornada_id, lectura_id, registrado_por, registrado_en)
  values (p_id_cliente, v_cliente, p_entrega, case when p_entrega = 'tienda' then p_destino end,
          case when p_entrega = 'nacex' then btrim(p_datos_envio) end, p_lineas, p_fecha,
          case when p_entrega = 'nacex' then p_jornada end, p_lectura, p_persona, p_ahora)
  on conflict (id_cliente) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.pedidos_cliente where id_cliente = p_id_cliente;
    return jsonb_build_object('pedido', motor.pedido_json(v_id), 'ya_guardado', true);
  end if;

  if p_entrega = 'nacex' then
    select id into v_tarea from motor.crear_tarea_condicionada(p_jornada, 'pedido_nacex', v_id::text) id limit 1;
    if v_tarea is null then
      raise exception 'No hay tarea para el pedido de cliente de ese día';
    end if;
    update public.tareas
       set titulo = 'Prepara el pedido de cliente (Nacex) · ' || v_cliente,
           porque = 'Datos de envío:' || E'\n' || btrim(p_datos_envio), creada_por = p_persona
     where id = v_tarea;
    perform motor.poner_elementos_pedido(v_tarea, p_elementos, p_lectura);
    update public.pedidos_cliente set tarea_id = v_tarea where id = v_id;
    -- Nacex ese día, igual que con el envío: si ya lo hay, es el mismo viaje.
    perform motor.fijar_envio(p_jornada, true, null);
  end if;
  perform motor.registrar('pedido_cliente_registrado', p_persona, p_jornada, v_tarea,
                          jsonb_build_object('pedido', v_id, 'entrega', p_entrega, 'fecha', p_fecha));
  return jsonb_build_object(
    'pedido', motor.pedido_json(v_id),
    'tarea', case when v_tarea is not null then motor.tarea_json(v_tarea) end,
    'tarea_activa', case when v_rol = 'operario' then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

-- Recoger en tienda: guardar_reparto asigna al reparto los pedidos que esperan
-- (con «coge / haz» ya calculado). Repetirlo no duplica nada: actualiza «coge /
-- haz» y conserva lo hecho.
create or replace function public.servidor_asignar_pedidos(
  p_persona uuid, p_reparto uuid, p_pedidos jsonb, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r public.repartos;
  j public.jornadas;
  v_bolsas public.tareas;
  x jsonb;
  p public.pedidos_cliente;
  v_tienda text;
  v_tarea uuid;
  v_res jsonb := '[]';
begin
  select * into r from public.repartos where id = p_reparto and tipo = 'reparto' and estado = 'aceptado';
  if r.id is null then
    return jsonb_build_object('pedidos', v_res);
  end if;
  select * into j from public.jornadas where id = r.jornada_id;
  select * into v_bolsas from public.tareas where jornada_id = j.id and clave = 'bolsas';

  for x in select * from jsonb_array_elements(coalesce(p_pedidos, '[]')) loop
    select * into p from public.pedidos_cliente
     where id = (x ->> 'pedido_id')::uuid and entrega = 'tienda' for update;
    if p.id is null or (p.jornada_id is not null and p.jornada_id <> j.id) or p.fecha_objetivo > j.fecha then
      continue;
    end if;
    v_tienda := (select nombre from public.centros_trabajo where id = p.destino_id);
    v_tarea := (select t.id from public.tareas t where t.id = p.tarea_id and t.jornada_id = j.id);
    if v_tarea is null then
      select id into v_tarea from motor.crear_tarea_condicionada(j.id, 'pedido_tienda', p.id::text) id limit 1;
      if v_tarea is null then
        raise exception 'No hay tarea para el pedido de cliente de ese día';
      end if;
      update public.tareas
         set titulo = 'Hay un pedido de cliente para dejar en ' || v_tienda || ' · ' || p.cliente,
             porque = 'Va en una bolsa aparte, «Pedido de cliente · ' || p.cliente || '», junto con la de reposición de '
                      || v_tienda || '.',
             hora_limite = coalesce(v_bolsas.hora_limite, hora_limite), creada_por = p.registrado_por
       where id = v_tarea;
      perform motor.registrar('pedido_cliente_en_reparto', p_persona, j.id, v_tarea,
                              jsonb_build_object('pedido', p.id, 'reparto', r.id));
    end if;
    perform motor.poner_elementos_pedido(v_tarea, x -> 'elementos', r.lectura_id);
    update public.pedidos_cliente set jornada_id = j.id, reparto_id = r.id, tarea_id = v_tarea where id = p.id;

    -- Bolsa aparte en la tienda: «Pedido de cliente · [cliente]».
    if v_bolsas.id is not null then
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
      select v_bolsas.id, 'caja_bolsa', 'pedido:' || p.id, l ->> 'producto', coalesce(l ->> 'formato', ''), p.destino_id,
             (l ->> 'cantidad')::int,
             coalesce((select (e ->> 'orden')::int from jsonb_array_elements(x -> 'elementos') e
                        where e ->> 'producto' = l ->> 'producto'
                          and coalesce(e ->> 'formato', '') = coalesce(l ->> 'formato', '') limit 1), 0)
        from jsonb_array_elements(p.lineas) l
      on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do nothing;
      perform motor.ajustar_estado_lista(p_persona, v_bolsas.id, 'Sin bolsas', p_ahora);
    end if;
    v_res := v_res || motor.pedido_json(p.id);
  end loop;
  return jsonb_build_object('pedidos', v_res);
end;
$$;

-- ---------------------------------------------------------------------------
-- pedidos_cliente_abiertos(): para el panel y para el operario
-- ---------------------------------------------------------------------------
create or replace function motor.pedidos_cliente_abiertos_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('total', count(*),
                            'pedidos', coalesce(jsonb_agg(x.j order by x.j ->> 'fecha', x.registrado_en), '[]'::jsonb))
    from (select motor.pedido_json(p.id) as j, p.registrado_en
            from public.pedidos_cliente p) x
   where x.j ->> 'estado' in ('esperando_reparto', 'por_preparar')
      or (x.j ->> 'estado' = 'preparado' and (x.j ->> 'fecha')::date >= motor.fecha_local(p_ahora));
$$;

create or replace function motor.api_pedidos_cliente_abiertos()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.pedidos_cliente_abiertos_de(auth.uid(), now());
end; $$;

create or replace function public.pedidos_cliente_abiertos()
returns jsonb language sql set search_path = '' as $$ select motor.api_pedidos_cliente_abiertos() $$;

-- ---------------------------------------------------------------------------
-- Las tareas con lista dicen en qué bolsa va cada caja: «Bolsa de reposición»,
-- «Envío» o «Pedido de cliente · [cliente]» (bolsa aparte en la misma tienda).
-- ---------------------------------------------------------------------------
create or replace function motor.tarea_json(p_tarea uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque,
    'estado', t.estado, 'origen', t.origen, 'obligatoria', t.obligatoria,
    'urgente', t.urgente, 'contenido', t.contenido,
    'hora_programada', t.hora_programada, 'hora_limite', t.hora_limite,
    'duracion_min', t.duracion_min, 'arrastrada_de', t.tarea_origen_id,
    'iniciada_en', t.iniciada_en, 'terminada_en', t.terminada_en,
    'elementos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'tipo', e.tipo, 'producto', e.producto, 'formato', e.formato,
               'categoria', e.categoria, 'destino', c.nombre, 'destino_id', e.destino_id,
               'bolsa', case when e.tipo <> 'caja_bolsa' then null
                             when e.lote like 'pedido:%' then 'Pedido de cliente · ' || pc.cliente
                             when e.lote = 'envio' then 'Envío'
                             else 'Bolsa de reposición' end,
               'cantidad', e.cantidad, 'cantidad_hecha', e.cantidad_hecha, 'motivo', e.motivo,
               'orden_sugerido', e.orden_sugerido, 'estado', e.estado)
             order by e.tipo desc, c.nombre nulls first, e.lote like 'pedido:%', e.lote,
                      e.orden_sugerido, e.producto, e.formato)
      from public.tarea_elementos e
      left join public.centros_trabajo c on c.id = e.destino_id
      left join public.pedidos_cliente pc on e.lote like 'pedido:%' and pc.id::text = substr(e.lote, 8)
      where e.tarea_id = t.id), '[]'::jsonb))
  from public.tareas t where t.id = p_tarea;
$$;

-- ---------------------------------------------------------------------------
-- Lo que pasa al día siguiente lleva su lista (lo hecho, hecho) y el pedido de
-- cliente sigue a su tarea.
-- ---------------------------------------------------------------------------
create or replace function motor.arrastrar(p_jornada uuid)
returns void language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_anterior uuid;
  t public.tareas;
  v_id uuid;
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
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, destino_id, cantidad,
                                          cantidad_hecha, motivo, orden_sugerido, calculo, estado, terminado_en)
      select v_id, e.tipo, e.lote, e.producto, e.formato, e.categoria, e.destino_id, e.cantidad,
             e.cantidad_hecha, e.motivo, e.orden_sugerido, e.calculo,
             case when e.estado = 'hecho' then 'hecho' else 'pendiente' end, e.terminado_en
        from public.tarea_elementos e where e.tarea_id = t.id;
    end if;
    perform motor.registrar('tarea_arrastrada', null, j.id, coalesce(v_id, t.id),
                            jsonb_build_object('desde', t.id));
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Retrasar la salida retrasa también los pedidos de cliente que salen con el
-- reparto (los de tienda y, el viernes, los de Nacex).
-- ---------------------------------------------------------------------------
create or replace function motor.retrasar_salida_de(p_persona uuid, p_id_cliente uuid, p_minutos integer, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  j public.jornadas;
  v_jornada uuid;
  v_bolsas public.tareas;
  v_nueva timestamptz;
  v_evento bigint;
  v_previo jsonb;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;
  select * into j from public.jornadas where id = v_jornada;
  select datos into v_previo from public.registro_eventos
   where jornada_id = j.id and tipo = 'salida_retrasada' and datos ->> 'id_cliente' = p_id_cliente::text;
  if v_previo is not null then
    return jsonb_build_object('nueva_hora_salida', v_previo ->> 'nueva_hora', 'minutos', (v_previo ->> 'minutos')::int,
                              'aviso', v_previo ->> 'aviso', 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if p_minutos is null or p_minutos not in (15, 30) then
    return motor.error('DATOS_NO_VALIDOS', 'El retraso es de 15 o 30 minutos.');
  end if;
  select * into v_bolsas from public.tareas where jornada_id = j.id and clave = 'bolsas';
  if v_bolsas.id is null then
    return motor.error('SIN_TAREA', 'Todavía no hay bolsas: prepara primero el reparto.');
  end if;
  if v_bolsas.estado not in ('pendiente', 'en_curso', 'bloqueada') then
    return motor.error('ESTADO_NO_VALIDO', 'Las bolsas ya están listas.', jsonb_build_object('estado', v_bolsas.estado));
  end if;

  v_nueva := coalesce(v_bolsas.hora_limite, motor.en_local(j.fecha, '10:45')) + make_interval(mins => p_minutos);
  update public.tareas set hora_limite = hora_limite + make_interval(mins => p_minutos)
   where jornada_id = j.id
     and (clave in ('bolsas', 'produccion_reparto', 'preparar_envio_viernes')
          or clave like 'pedido_tienda:%' or clave like 'pedido_nacex_viernes:%')
     and estado in ('pendiente', 'en_curso', 'bloqueada') and hora_limite is not null;
  update public.tareas
     set hora_programada = hora_programada + make_interval(mins => p_minutos),
         disponible_desde = disponible_desde + make_interval(mins => p_minutos)
   where jornada_id = j.id and clave in ('salida_reparto', 'nacex_viernes') and estado = 'pendiente';

  insert into public.registro_eventos (tipo, persona_id, jornada_id, tarea_id, datos)
  values ('salida_retrasada', p_persona, j.id, v_bolsas.id,
          jsonb_build_object('minutos', p_minutos, 'nueva_hora', motor.hora_texto(v_nueva), 'sale', j.sale,
                             'id_cliente', p_id_cliente, 'a_las', p_ahora,
                             'aviso', case when j.sale = 'administracion' then 'correo' else 'sin_aviso' end))
  returning id into v_evento;
  if j.sale = 'administracion' then
    perform motor.encolar_correo('retraso', v_evento::text);
  end if;
  return jsonb_build_object('nueva_hora_salida', motor.hora_texto(v_nueva), 'minutos', p_minutos,
                            'aviso', case when j.sale = 'administracion' then 'correo' else 'sin_aviso' end,
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- ---------------------------------------------------------------------------
-- Nacex también lleva los pedidos de cliente: títulos que valen para los dos.
-- ---------------------------------------------------------------------------
update public.plantillas_tarea
   set titulo = 'Salida a Nacex con el envío o el pedido de cliente (vuelta hacia las 18:25 para cerrar)'
 where codigo = 'nacex_salida';
update public.plantillas_tarea
   set titulo = 'Lleva en el reparto lo que va a Nacex (envío o pedido de cliente) y déjalo de camino'
 where codigo = 'nacex_viernes';

-- ---------------------------------------------------------------------------
-- servidor_preparar: lo comprometido hoy (R1c) y los pedidos de tienda que
-- esperan al reparto.
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
    -- R1c: lo comprometido hoy que la hoja aún cuenta en el almacén, y lo que va en camino a las tiendas.
    'comprometido', motor.comprometido(v_jornada),
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


revoke execute on all functions in schema motor from public;
grant execute on function motor.api_pedidos_cliente_abiertos() to authenticated;
revoke execute on function public.pedidos_cliente_abiertos() from public, anon;
grant execute on function public.pedidos_cliente_abiertos() to authenticated;
revoke execute on function
  public.servidor_preparar_pedido(uuid, uuid, text, uuid, timestamptz),
  public.servidor_guardar_pedido_cliente(uuid, uuid, text, text, uuid, text, jsonb, date, uuid, uuid, jsonb, timestamptz),
  public.servidor_asignar_pedidos(uuid, uuid, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function
  public.servidor_preparar_pedido(uuid, uuid, text, uuid, timestamptz),
  public.servidor_guardar_pedido_cliente(uuid, uuid, text, text, uuid, text, jsonb, date, uuid, uuid, jsonb, timestamptz),
  public.servidor_asignar_pedidos(uuid, uuid, jsonb, timestamptz)
  to service_role;
