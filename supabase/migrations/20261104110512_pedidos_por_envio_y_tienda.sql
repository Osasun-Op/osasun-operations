-- Tarea 30c · Pedidos de cliente para todas las tiendas, por envío y desde la tableta (ESTADO_DEL_SISTEMA.md §5 R1b
-- v1.51 y E2-8). Solo en pruebas: producción espera con las de tiendas (AGENTE_BASE_DE_DATOS.md §4). Reutiliza los
-- pedidos de siempre (pedidos_cliente, servidor_asignar_pedidos, la tarea «Hay un pedido de cliente…» con su
-- «coge / haz», la caja aparte «Pedido de cliente») y la pestaña «Envíos» de la Tarea 30b. El reparto y los pedidos
-- de siempre no cambian.
--   1. «Recoger en tienda» acepta también las tiendas que reciben por envío (Donosti, Rentería y Durango cuando
--      abra): lo dice la configuración de siempre (destinos_reparto y peticiones_por_envio, motor.destino_peticion).
--   2. Van en el siguiente envío a esa tienda (Gipuzkoa para Donosti y Rentería; Durango para Durango): al guardar
--      el envío, su tarea propia «Hay un pedido de cliente para enviar a [tienda] · [cliente]» (como en el reparto,
--      decisión del propietario, 04/11/2026) y la caja aparte «Pedido de cliente · [cliente] · [tienda]» en
--      «Prepara el envío aprobado». Mientras no haya envío, espera. Sale del almacén con el envío preparado.
--   3. En «Revisa si toca envío…», tarea_json().aviso: «Hay N pedidos de cliente esperando envío a [destino]».
--   4. En la tienda, en «Envíos» con lo demás (los de Donosti, en los de Rentería), con la tienda de cada pedido.
--   5. La tableta apunta sus pedidos (crear_pedido_tienda): para recoger en su tienda, con la lista de la última
--      lectura de la hoja (productos_tienda, ahora con formatos) y el nombre de quien está en el turno. Siguen el
--      mismo camino que los de siempre. La tienda ve los suyos en tienda_hoy().pedidos; Administración, en los de
--      siempre, con qué tienda lo pidió.
--
-- Deshacer: borrar public.crear_pedido_tienda, motor.api_crear_pedido_tienda, motor.crear_pedido_tienda_de,
-- motor.pedidos_de_tienda_json, motor.fecha_pedido_tienda, motor.tiendas_pedido_json, motor.aviso_pedidos_envio,
-- motor.nombre_envio y motor.destino_pedido; volver a crear public.servidor_preparar y public.servidor_preparar_pedido
-- (20261102190536), public.servidor_asignar_pedidos y motor.pedido_json (20261028105848), motor.tarea_json
-- (20261030121241), motor.bolsa_contenido (20261103175352), motor.pendiente_salir (20261029140000),
-- motor.productos_tienda_de (20261103100515) y motor.tienda_hoy_de (20261103211530) como estaban; borrar la columna
-- pedidos_cliente.pedido_por.

-- ---------------------------------------------------------------------------
-- 1. Quién lo pidió en la tienda (solo se añade una columna)
-- ---------------------------------------------------------------------------
alter table public.pedidos_cliente add column pedido_por text;
comment on column public.pedidos_cliente.pedido_por is 'Si lo apuntó una tienda desde la tableta, quién estaba en el turno (Tarea 30c).';

-- ---------------------------------------------------------------------------
-- 2. Ayudas
-- ---------------------------------------------------------------------------
-- Cómo llega un pedido para recoger en esa tienda: en el reparto (su tienda) o en el envío (el destino del envío:
-- GIPUZKOA para Donosti y Rentería, DURANGO para Durango). Solo tiendas activas; ninguna fila si no se puede.
create or replace function motor.destino_pedido(p_centro uuid)
returns table (tipo text, destino_id uuid) language sql stable set search_path = '' as $$
  select d.tipo, d.destino_id
    from public.centros_trabajo c cross join lateral motor.destino_peticion(c.id) d
   where c.id = p_centro and c.tipo = 'tienda' and c.activo and d.tipo is not null and d.destino_id is not null
$$;

-- «Gipuzkoa», «Durango»: el nombre corto del destino de un envío.
create or replace function motor.nombre_envio(p_destino uuid)
returns text language sql stable set search_path = '' as $$
  select initcap(lower(c.codigo)) from public.centros_trabajo c where c.id = p_destino
$$;

-- Las tiendas que se pueden elegir en «Pedido de cliente»: las del reparto en su orden y después las que reciben
-- por envío.
create or replace function motor.tiendas_pedido_json()
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre, 'va_en', d.tipo)
                            order by d.tipo = 'envio', o.n nulls last, c.nombre), '[]'::jsonb)
    from public.centros_trabajo c
    cross join lateral motor.destino_pedido(c.id) d
    left join (select x.codigo, x.n from public.configuracion k,
                      jsonb_array_elements_text(k.valor -> 'reparto') with ordinality x(codigo, n)
                where k.clave = 'destinos_reparto' and k.centro_id is null) o on o.codigo = c.codigo
$$;

-- «Hay N pedidos de cliente esperando envío a Gipuzkoa»: los que aún no van en ningún envío (null si no hay).
create or replace function motor.aviso_pedidos_envio()
returns text language sql stable set search_path = '' as $$
  select string_agg('Hay ' || x.n || case when x.n = 1 then ' pedido de cliente esperando envío a '
                                          else ' pedidos de cliente esperando envío a ' end || motor.nombre_envio(x.destino),
                    ' · ' order by motor.nombre_envio(x.destino))
    from (select d.destino_id as destino, count(*) as n
            from public.pedidos_cliente p cross join lateral motor.destino_pedido(p.destino_id) d
           where p.entrega = 'tienda' and p.tarea_id is null and p.jornada_id is null and d.tipo = 'envio'
           group by 1) x
$$;

-- Cuándo sale un pedido para recoger en esa tienda (y si entra ya en un reparto o envío de hoy).
--   Reparto (como siempre): hoy mientras el reparto no haya salido (bolsas listas); sin reparto todavía, mientras
--   «Prepara el reparto» siga abierta. Si no, el siguiente día de trabajo.
--   Envío (Tarea 30c): en el siguiente envío a su destino; si hoy hay uno sin preparar que va allí, entra en él.
create or replace function motor.fecha_pedido_tienda(p_operario uuid, p_jornada_hoy uuid, p_destino uuid, p_ahora timestamptz)
returns table (fecha date, reparto_id uuid) language plpgsql set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_tipo text;
  v_dest uuid;
  v_fecha date;
  v_reparto uuid;
begin
  select d.tipo, d.destino_id into v_tipo, v_dest from motor.destino_pedido(p_destino) d;
  if v_tipo = 'envio' then
    select r.id into v_reparto
      from public.repartos r join public.tareas t on t.id = (r.resultado -> 'tareas' ->> 'bolsas')::uuid
     where r.jornada_id = p_jornada_hoy and r.tipo = 'envio' and r.estado = 'aceptado' and t.estado <> 'hecha'
       and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.destino_id = v_dest)
     limit 1;
    return query select v_hoy, v_reparto;
    return;
  end if;
  select r.id into v_reparto from public.repartos r
   where r.jornada_id = p_jornada_hoy and r.tipo = 'reparto' and r.estado = 'aceptado';
  if p_jornada_hoy is not null
     and not exists (select 1 from public.tareas t
                      where t.jornada_id = p_jornada_hoy and t.clave = 'bolsas' and t.estado = 'hecha')
     and (v_reparto is not null
          or exists (select 1 from public.tareas t
                      where t.jornada_id = p_jornada_hoy and t.clave = 'pegar_reparto'
                        and t.estado in ('pendiente', 'en_curso', 'bloqueada'))) then
    v_fecha := v_hoy;
  elsif p_operario is not null then
    v_fecha := motor.siguiente_dia_trabajo(p_operario, v_hoy);
    v_reparto := null;
  end if;
  return query select v_fecha, v_reparto;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Funciones de siempre (solo se añade lo de esta tarea)
-- ---------------------------------------------------------------------------
create or replace function motor.pedido_json(p_pedido uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'cliente', p.cliente, 'entrega', p.entrega,
    'entrega_texto', case p.entrega when 'tienda' then 'Recoger en ' || c.nombre else 'Envío por Nacex' end,
    'destino_id', p.destino_id, 'destino', c.nombre, 'datos_envio', p.datos_envio, 'lineas', p.lineas,
    'fecha', f.fecha, 'estado', e.estado,
    'estado_texto', case e.estado
      when 'esperando_reparto' then case when v.tipo = 'envio' then 'Va en el próximo envío a ' else 'Va en el próximo reparto a ' end
                                    || c.nombre
                                    || case when f.fecha > motor.fecha_local(now())
                                            then ' (desde el ' || to_char(f.fecha, 'DD/MM') || ')' else '' end
      when 'por_preparar' then case p.entrega when 'tienda' then case when v.tipo = 'envio' then 'En el envío del ' else 'En el reparto del ' end
                                                                 || to_char(f.fecha, 'DD/MM') || ': por preparar'
                                              else 'Por preparar: sale a Nacex el ' || to_char(f.fecha, 'DD/MM') end
      when 'preparado' then case p.entrega when 'tienda' then case when v.tipo = 'envio' then 'Preparado: va en el envío del '
                                                                   else 'Preparado: va en el reparto del ' end || to_char(f.fecha, 'DD/MM')
                                           else 'Preparado: sale a Nacex el ' || to_char(f.fecha, 'DD/MM') end
      else 'Cancelado' end,
    'tarea_id', p.tarea_id, 'registrado_en', p.registrado_en,
    'registrado_por', p.registrado_por, 'registrado_por_nombre', pe.nombre,
    -- Tarea 30c: en el reparto o en el envío; si lo pidió una tienda, cuál y quién estaba en el turno.
    'va_en', case when p.entrega = 'tienda' then coalesce(v.tipo, 'reparto') end,
    'pedido_en_tienda', case when pe.rol = 'tienda' then (select x.nombre from public.centros_trabajo x where x.id = pe.centro_id) end,
    'pedido_por', p.pedido_por)
  from public.pedidos_cliente p
  left join public.centros_trabajo c on c.id = p.destino_id
  left join public.tareas t on t.id = p.tarea_id
  left join public.personas pe on pe.id = p.registrado_por
  left join lateral (select d.tipo from motor.destino_pedido(p.destino_id) d) v on true
  cross join lateral (select coalesce((select jo.fecha from public.jornadas jo where jo.id = coalesce(t.jornada_id, p.jornada_id)),
                                      p.fecha_objetivo) as fecha) f
  cross join lateral (select case when p.tarea_id is null then 'esperando_reparto'
                                  when t.estado = 'hecha' then 'preparado'
                                  when t.estado = 'cancelada' then 'cancelado'
                                  else 'por_preparar' end as estado) e
  where p.id = p_pedido;
$$;

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
    -- Compra por internet (Tarea 22): el enlace de la lista de compras.
    'enlace', (select c.enlace from public.incidencias i join public.compras c on c.id = i.compra_id
                where i.tarea_resolucion_id = t.id and c.forma = 'internet' limit 1),
    'elementos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'tipo', e.tipo, 'producto', e.producto, 'formato', e.formato,
               'texto', case when e.tipo in ('peticion', 'llamada') then e.producto end,
               'categoria', e.categoria, 'destino', c.nombre, 'destino_id', e.destino_id,
               'bolsa', case when e.tipo = 'referencia_produccion' then null
                             when e.lote like 'pedido:%' then 'Pedido de cliente · ' || pc.cliente
                                                              -- Tarea 30c: en el envío, para qué tienda es.
                                                              || case when pc.destino_id is distinct from e.destino_id
                                                                      then ' · ' || pcd.nombre else '' end
                             when e.lote = 'envio' then 'Envío'
                             else 'Bolsa de reposición' end,
               'cantidad', e.cantidad, 'cantidad_hecha', e.cantidad_hecha, 'motivo', e.motivo,
               'orden_sugerido', e.orden_sugerido, 'estado', e.estado)
             -- R1e: referencia sin granel, con quién la recibe, quién tiene y lo decidido.
             || case when e.tipo = 'referencia_produccion' and coalesce((e.calculo ->> 'sin_granel')::boolean, false)
                     then jsonb_build_object('sin_granel', true, 'para', coalesce(e.calculo -> 'para', '[]'::jsonb),
                                             'tiendas_con_stock', coalesce(e.calculo -> 'tiendas_con_stock', '[]'::jsonb),
                                             'resuelto', coalesce((e.calculo ->> 'resuelto')::boolean, false),
                                             'decisiones', motor.decisiones_json(e.calculo -> 'decisiones'))
                     else '{}'::jsonb end
             order by e.tipo = 'referencia_produccion' desc, c.nombre nulls first, e.lote like 'pedido:%',
                      e.tipo in ('peticion', 'llamada'), e.tipo = 'llamada', e.lote, e.orden_sugerido, e.producto, e.formato)
      from public.tarea_elementos e
      left join public.centros_trabajo c on c.id = e.destino_id
      left join public.pedidos_cliente pc on e.lote like 'pedido:%' and pc.id::text = substr(e.lote, 8)
      left join public.centros_trabajo pcd on pcd.id = pc.destino_id
      where e.tarea_id = t.id), '[]'::jsonb),
    -- Tarea 30c: en «Revisa si toca envío…», los pedidos de cliente que esperan envío.
    'aviso', case when t.clave = 'revisar_envio' then motor.aviso_pedidos_envio() end)
  from public.tareas t where t.id = p_tarea;
$$;

create or replace function motor.bolsa_contenido(p_reparto uuid, p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  with b as (select (r.resultado -> 'tareas' ->> 'bolsas')::uuid as tarea from public.repartos r where r.id = p_reparto),
  e as (select el.tipo, el.lote, el.producto, el.formato, el.orden_sugerido,
               coalesce(nullif(el.cantidad_hecha, 0), case when el.estado = 'hecho' then el.cantidad end, 0) as metidas
          from public.tarea_elementos el, b
         where el.tarea_id = b.tarea and el.destino_id = p_centro and el.tipo in ('caja_bolsa', 'peticion'))
  select jsonb_build_object(
    'productos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'producto:' || x.producto || '|' || x.formato, 'producto', x.producto,
                                          'formato', x.formato, 'cantidad', x.cantidad) order by x.orden, x.producto, x.formato)
        from (select producto, formato, sum(metidas)::int as cantidad, min(orden_sugerido) as orden
                from e where tipo = 'caja_bolsa' and lote not like 'pedido:%' and metidas > 0 group by 1, 2) x), '[]'::jsonb),
    'peticiones', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'peticion:' || e.producto, 'texto', e.producto) order by e.orden_sugerido, e.producto)
        from e where e.tipo = 'peticion' and e.metidas > 0), '[]'::jsonb),
    'pedidos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'pedido:' || p.id, 'pedido_id', p.id, 'cliente', p.cliente, 'lineas', x.lineas,
                                          -- Tarea 30c: la tienda del pedido (en el envío a Gipuzkoa, Donosti o Rentería).
                                          'tienda', (select c.nombre from public.centros_trabajo c where c.id = p.destino_id))
                       order by p.registrado_en)
        from (select split_part(lote, ':', 2)::uuid as pedido,
                     jsonb_agg(jsonb_build_object('producto', producto, 'formato', formato, 'cantidad', metidas)
                               order by orden_sugerido, producto) as lineas
                from e where tipo = 'caja_bolsa' and lote like 'pedido:%' and metidas > 0 group by 1) x
        join public.pedidos_cliente p on p.id = x.pedido), '[]'::jsonb))
$$;

create or replace function motor.pendiente_salir(p_jornada uuid, p_momento timestamp with time zone)
 RETURNS TABLE(origen text, pedido_id uuid, registrado_en timestamp with time zone, producto text, formato text, cantidad integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
as $$
  with salio as (
    select coalesce(bool_or(t.clave = 'bolsas'), false) as bolsas,
           coalesce(bool_or(t.clave in ('preparar_envio', 'preparar_envio_viernes')), false) as envio
      from public.tareas t
     where t.jornada_id = p_jornada and t.estado = 'hecha' and coalesce(t.terminada_en, '-infinity') <= p_momento
       and t.clave in ('bolsas', 'preparar_envio', 'preparar_envio_viernes'))
  -- R1e: lo que se quita o se coge de otra tienda no sale del almacén.
  select r.tipo, null::uuid, r.pegado_en, x ->> 'producto', coalesce(x ->> 'formato', ''),
         (x ->> 'pedido')::int - case when r.tipo = 'reparto' then coalesce((
           select sum(d.cantidad) from motor.decisiones_sin_granel(p_jornada) d
            where d.producto = x ->> 'producto' and d.formato = coalesce(x ->> 'formato', '')
              and d.resuelto_en <= p_momento), 0)::int else 0 end
    from public.repartos r cross join salio s
    cross join lateral jsonb_array_elements(r.resultado -> 'produccion') with ordinality a(x, n)
   where r.jornada_id = p_jornada and r.estado = 'aceptado'
     and not case r.tipo when 'reparto' then s.bolsas else s.envio end
  union all
  select 'pedido_' || p.entrega, p.id, p.registrado_en, l ->> 'producto', coalesce(l ->> 'formato', ''),
         (l ->> 'cantidad')::int
    from public.pedidos_cliente p
    left join public.tareas t on t.id = p.tarea_id
    left join public.repartos rp on rp.id = p.reparto_id
    cross join salio s
    cross join lateral jsonb_array_elements(p.lineas) l
   where p.jornada_id = p_jornada and t.estado is distinct from 'cancelada'
     -- Tarea 30c: el de una tienda que recibe por envío sale con el envío preparado.
     and case p.entrega when 'tienda' then not case when rp.tipo = 'envio' then s.envio else s.bolsas end
                        else not (t.estado = 'hecha' and coalesce(t.terminada_en, '-infinity') <= p_momento) end
$$;

create or replace function motor.productos_tienda_de()
returns jsonb language sql stable set search_path = '' as $$
  with l as (select datos, leido_en from public.lecturas_sheets
              where correcto and jsonb_typeof(datos -> 'productos') = 'array' order by leido_en desc limit 1),
  x as (
    select distinct on (upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')))
           btrim(p ->> 'nombre') as producto,
           -- Tarea 30c: los formatos, para el pedido de cliente desde la tableta (las muestras no lo usan).
           coalesce((select jsonb_agg(f ->> 'formato' order by n) from jsonb_array_elements(coalesce(p -> 'formatos', '[]'))
                       with ordinality a(f, n)), '[""]'::jsonb) as formatos,
           coalesce(l.datos -> 'categorias' ->> upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')), 'Otros') as categoria,
           (p ->> 'orden')::int as orden
      from l, jsonb_array_elements(l.datos -> 'productos') p
     where jsonb_array_length(coalesce(p -> 'formatos', '[]')) > 0 or coalesce((p ->> 'conTiendas')::boolean, false)
     order by upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')), (p ->> 'orden')::int)
  select jsonb_build_object(
    'productos', coalesce((select jsonb_agg(jsonb_build_object('clave', x.producto, 'producto', x.producto,
                                                               'categoria', x.categoria, 'formatos', x.formatos)
                                            order by x.orden, x.producto)
                             from x), '[]'::jsonb),
    'leidos_en', (select leido_en from l))
$$;

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
  if v_rol is null or v_rol = 'tienda' then  -- una tienda no usa las funciones del reparto (Tarea 27)
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  select id into v_previo from public.pedidos_cliente where id_cliente = p_id_cliente;
  if v_previo is not null then
    return jsonb_build_object('previo', motor.pedido_json(v_previo));
  end if;
  if p_entrega is null or p_entrega not in ('tienda', 'nacex') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige cómo se entrega: recoger en tienda o envío por Nacex.');
  end if;
  -- Tarea 30c: las tiendas del reparto y las que reciben por envío (configuración).
  if p_entrega = 'tienda' and not exists (select 1 from motor.destino_pedido(p_destino)) then
    return motor.error('DATOS_NO_VALIDOS', 'Elige una de las tiendas de la lista.');
  end if;

  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada_hoy := motor.generar_jornada(v_operario, v_hoy);
  end if;
  if p_entrega = 'tienda' then
    -- Tarea 30c: en el reparto (como siempre) o en el siguiente envío a esa tienda.
    select f.fecha, f.reparto_id into v_fecha, v_reparto
      from motor.fecha_pedido_tienda(v_operario, v_jornada_hoy, p_destino, p_ahora) f;
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
  v_dest uuid;
  v_tarea uuid;
  v_res jsonb := '[]';
begin
  -- Tarea 30c: también el envío (los pedidos de las tiendas que reciben por envío).
  select * into r from public.repartos where id = p_reparto and tipo in ('reparto', 'envio') and estado = 'aceptado';
  if r.id is null then
    return jsonb_build_object('pedidos', v_res);
  end if;
  select * into j from public.jornadas where id = r.jornada_id;
  select * into v_bolsas from public.tareas
   where id = coalesce((r.resultado -> 'tareas' ->> 'bolsas')::uuid,
                       (select t.id from public.tareas t where t.jornada_id = j.id and t.clave = 'bolsas'));

  for x in select * from jsonb_array_elements(coalesce(p_pedidos, '[]')) loop
    select * into p from public.pedidos_cliente
     where id = (x ->> 'pedido_id')::uuid and entrega = 'tienda' for update;
    if p.id is null or (p.jornada_id is not null and p.jornada_id <> j.id) or p.fecha_objetivo > j.fecha then
      continue;
    end if;
    -- La tienda tiene que ir en este reparto o envío (Donosti y Rentería, en el envío a Gipuzkoa).
    v_dest := (select d.destino_id from motor.destino_pedido(p.destino_id) d where d.tipo = r.tipo);
    if v_dest is null then
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
         set titulo = case r.tipo when 'envio' then 'Hay un pedido de cliente para enviar a ' || v_tienda || ' · ' || p.cliente
                              else 'Hay un pedido de cliente para dejar en ' || v_tienda || ' · ' || p.cliente end,
             porque = case r.tipo
                        when 'envio' then 'Va en una caja aparte, «Pedido de cliente · ' || p.cliente || ' · ' || v_tienda
                                          || '», en el envío a ' || motor.nombre_envio(v_dest) || '.'
                        else 'Va en una bolsa aparte, «Pedido de cliente · ' || p.cliente || '», junto con la de reposición de '
                             || v_tienda || '.' end,
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
      select v_bolsas.id, 'caja_bolsa', 'pedido:' || p.id, l ->> 'producto', coalesce(l ->> 'formato', ''), v_dest,
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
-- 4. La tableta: sus pedidos y apuntar uno
-- ---------------------------------------------------------------------------
-- Los pedidos para recoger en la tienda: los que esperan o están por preparar, y los preparados hasta su día.
create or replace function motor.pedidos_de_tienda_json(p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(x.j order by x.j ->> 'fecha', x.registrado_en), '[]'::jsonb)
    from (select motor.pedido_json(p.id) - 'datos_envio' as j, p.registrado_en
            from public.pedidos_cliente p where p.entrega = 'tienda' and p.destino_id = p_centro) x
   where x.j ->> 'estado' in ('esperando_reparto', 'por_preparar')
      or (x.j ->> 'estado' = 'preparado' and (x.j ->> 'fecha')::date >= motor.fecha_local(p_ahora))
$$;

-- «Pedido de cliente» desde la tableta: para recoger en esta tienda, con la lista de productos_tienda() (producto y
-- formato de la última lectura de la hoja), de 1 a 99 de cada uno (0 no cuenta; repetidos se suman). Queda con el
-- nombre de quien está en el turno y sigue el camino de siempre (reparto o envío).
create or replace function motor.crear_pedido_tienda_de(p_persona uuid, p_id_cliente uuid, p_cliente text, p_lineas jsonb,
                                                        p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  v_cliente text := nullif(regexp_replace(btrim(coalesce(p_cliente, '')), '\s+', ' ', 'g'), '');
  v_productos jsonb := coalesce(motor.productos_tienda_de() -> 'productos', '[]'::jsonb);
  v_todas jsonb := '[]';
  v_lineas jsonb;
  v_elementos jsonb;
  x jsonb;
  v_prod jsonb;
  v_cant integer;
  v_jornada uuid;
  tt public.turnos_tienda;
  v_operario uuid := motor.operario_por_defecto();
  v_jornada_hoy uuid;
  v_fecha date;
  v_reparto uuid;
  v_lectura uuid;
  v_id uuid;
begin
  select * into pe from public.personas where id = p_persona;
  if not exists (select 1 from motor.destino_pedido(pe.centro_id)) then
    return motor.error('NO_AUTORIZADO', 'Esta tienda no apunta pedidos de cliente desde aquí.');
  end if;
  if p_id_cliente is null then
    return motor.error('DATOS_NO_VALIDOS', 'Falta el id_cliente del pedido.');
  end if;
  -- Repetir con el mismo id_cliente no lo duplica.
  if exists (select 1 from public.pedidos_cliente where id_cliente = p_id_cliente) then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  if v_cliente is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el nombre del cliente.');
  end if;
  if length(v_cliente) > 60 then
    return motor.error('DATOS_NO_VALIDOS', 'El nombre del cliente es demasiado largo (60 letras como máximo).');
  end if;
  if p_lineas is null or jsonb_typeof(p_lineas) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige los productos del pedido.');
  end if;
  for x in select * from jsonb_array_elements(p_lineas) loop
    select pr into v_prod from jsonb_array_elements(v_productos) pr
     where pr ->> 'producto' = x ->> 'producto' and pr -> 'formatos' ? coalesce(x ->> 'formato', '');
    if v_prod is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista: «' || btrim(coalesce(x ->> 'producto', '') || ' '
                                             || coalesce(x ->> 'formato', '')) || '» no está.',
                         jsonb_build_object('producto', x ->> 'producto', 'formato', x ->> 'formato'));
    end if;
    v_cant := case when jsonb_typeof(x -> 'cantidad') = 'number'
                        and (x ->> 'cantidad')::numeric = trunc((x ->> 'cantidad')::numeric)
                   then (x ->> 'cantidad')::numeric::int else -1 end;
    if v_cant < 0 or v_cant > 99 then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas de ' || btrim((x ->> 'producto') || ' ' || coalesce(x ->> 'formato', ''))
                                             || ': de 1 a 99.', jsonb_build_object('producto', x ->> 'producto'));
    end if;
    if v_cant > 0 then
      v_todas := v_todas || jsonb_build_object('producto', x ->> 'producto', 'formato', coalesce(x ->> 'formato', ''),
                                               'cantidad', v_cant);
    end if;
  end loop;
  select jsonb_agg(jsonb_build_object('producto', l.producto, 'formato', l.formato, 'cantidad', l.cantidad)
                   order by l.primera)
    into v_lineas
    from (select y.e ->> 'producto' as producto, y.e ->> 'formato' as formato, sum((y.e ->> 'cantidad')::int)::int as cantidad,
                 min(y.n) as primera
            from jsonb_array_elements(v_todas) with ordinality y(e, n)
           group by 1, 2) l;
  if v_lineas is null then
    return motor.error('DATOS_NO_VALIDOS', 'Elige al menos un producto.');
  end if;
  if exists (select 1 from jsonb_array_elements(v_lineas) l where (l ->> 'cantidad')::int > 99) then
    return motor.error('DATOS_NO_VALIDOS', 'De cada producto, 99 como máximo.');
  end if;

  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  if v_operario is not null then
    v_jornada_hoy := motor.generar_jornada(v_operario, motor.fecha_local(p_ahora));
  end if;
  select f.fecha, f.reparto_id into v_fecha, v_reparto
    from motor.fecha_pedido_tienda(v_operario, v_jornada_hoy, pe.centro_id, p_ahora) f;
  if v_fecha is null then
    return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
  end if;
  select id into v_lectura from public.lecturas_sheets
   where correcto and jsonb_typeof(datos -> 'productos') = 'array' order by leido_en desc limit 1;

  insert into public.pedidos_cliente (id_cliente, cliente, entrega, destino_id, datos_envio, lineas, fecha_objetivo,
                                      jornada_id, lectura_id, registrado_por, registrado_en, pedido_por)
  values (p_id_cliente, v_cliente, 'tienda', pe.centro_id, null, v_lineas, v_fecha, null, v_lectura, p_persona, p_ahora,
          tt.nombre)
  on conflict (id_cliente) do nothing
  returning id into v_id;
  if v_id is null then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  perform motor.registrar('pedido_cliente_registrado', p_persona, v_jornada, null,
                          jsonb_build_object('pedido', v_id, 'entrega', 'tienda', 'fecha', v_fecha, 'desde', 'tienda',
                                             'por', tt.nombre));
  -- Si el reparto (o el envío) de hoy ya está guardado y sin salir, entra en él al momento, como los de siempre.
  if v_reparto is not null then
    select jsonb_agg(jsonb_build_object('producto', l ->> 'producto', 'formato', l ->> 'formato',
                                        'cantidad', (l ->> 'cantidad')::int, 'orden', (pp.pos - 1) * 100 + ff.n - 1)
                     || case when pp.pr ->> 'categoria' is not null
                             then jsonb_build_object('categoria', pp.pr ->> 'categoria') else '{}'::jsonb end)
      into v_elementos
      from jsonb_array_elements(v_lineas) l
      join jsonb_array_elements(v_productos) with ordinality pp(pr, pos) on pp.pr ->> 'producto' = l ->> 'producto'
      cross join lateral (select f.n from jsonb_array_elements_text(pp.pr -> 'formatos') with ordinality f(fo, n)
                           where f.fo = l ->> 'formato' limit 1) ff;
    perform public.servidor_asignar_pedidos(p_persona, v_reparto,
                                            jsonb_build_array(jsonb_build_object('pedido_id', v_id, 'elementos', v_elementos)),
                                            p_ahora);
  end if;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

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
begin
  select * into pe from public.personas where id = p_persona;
  select * into c from public.centros_trabajo where id = pe.centro_id;
  v_jornada := motor.generar_jornada(p_persona, v_hoy);
  -- Tarea 28: si ha salido el reparto y trae bolsa para esta tienda, «Recibe la bolsa».
  perform motor.preparar_bolsa_tienda(p_persona, v_jornada, p_ahora);
  -- Tarea 30b: las tiendas que reciben por envío, los envíos que les han salido.
  perform motor.preparar_envios_tienda(p_persona, p_ahora);
  v_turno := motor.turno_tienda_ahora(p_persona, p_ahora);
  tt := motor.en_turno_tienda(v_jornada);
  return jsonb_build_object(
    'tienda', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre),
    'fecha', v_hoy,
    'ahora', motor.hora_texto(p_ahora),
    'abierta_hoy', v_jornada is not null,
    'cerrado', motor.dia_cerrado(c.id, v_hoy),
    'horario', coalesce((select jsonb_agg(jsonb_build_object('turno', h.turno, 'inicio', to_char(h.hora_inicio, 'HH24:MI'),
                                                             'fin', to_char(h.hora_fin, 'HH24:MI')) order by h.hora_inicio)
                           from public.horarios h where h.persona_id = p_persona and h.dia_semana = v_dia), '[]'::jsonb),
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
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'fecha', motor.fecha_local(i.iniciada_en),
                                          -- Tarea 29: de quién viene («Almacén» o «Administración»).
                                          'de', case when a.rol = 'operario' then 'Almacén' else 'Administración' end)
                       order by i.iniciada_en)
        from public.incidencias i left join public.personas a on a.id = i.creada_por
       where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'tareas', coalesce((
      select jsonb_agg(motor.tarea_tienda_json(t.id, p_ahora) order by t.disponible_desde, t.orden, t.creada_en)
        from public.tareas t where t.jornada_id = v_jornada and not t.retirada_por_condicion), '[]'::jsonb),
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
    'envios_sin_confirmar', (select count(*)::int from public.bolsas_tienda b join public.repartos r on r.id = b.reparto_id
                              where b.centro_id = c.id and r.tipo = 'envio' and b.reposicion is null),
    -- Tarea 30c: los pedidos de cliente para recoger en la tienda, con su estado.
    'pedidos', motor.pedidos_de_tienda_json(c.id, p_ahora));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Para la pantalla
-- ---------------------------------------------------------------------------
create or replace function motor.api_crear_pedido_tienda(p_id_cliente uuid, p_cliente text, p_lineas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_pedido_tienda_de(auth.uid(), p_id_cliente, p_cliente, p_lineas, now());
end; $$;

create or replace function public.crear_pedido_tienda(id_cliente uuid, cliente text, lineas jsonb)
returns jsonb language sql set search_path = '' as $$ select motor.api_crear_pedido_tienda(id_cliente, cliente, lineas) $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_crear_pedido_tienda(uuid, text, jsonb) to authenticated;
revoke execute on function public.crear_pedido_tienda(uuid, text, jsonb) from public, anon;
grant execute on function public.crear_pedido_tienda(uuid, text, jsonb) to authenticated;
