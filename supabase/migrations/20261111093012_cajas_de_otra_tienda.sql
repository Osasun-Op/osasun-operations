-- T-0010 · Tarea 38 · Cajas de otra tienda: aviso a la tienda de origen y caja en la lista de la que recibe
-- (ESTADO_DEL_SISTEMA.md R1e y E2-8; decisión del propietario, 11/11/2026). Solo en pruebas: espera con las de tiendas.
--   1. La línea del operario en las bolsas (elemento «llamada») dice «Avisa a [origen] para que prepare N [producto
--      formato] para su retirada» (antes, «Llama a…»). Lo demás del elemento, igual. Las de hoy en adelante se renombran.
--   2. Al marcarla (el mismo toque de siempre, marcar_cajas), la tienda de origen recibe un aviso del almacén para hoy:
--      «Prepara N [producto formato] para [destino]: lo recoge hoy el reparto». Son los avisos del almacén a las tiendas
--      de siempre (crear_aviso_tienda); un aviso por elemento: marcarla otra vez no crea otro.
--   3. En la lista de la bolsa de la tienda que recibe (bolsa_contenido), desde que esa línea está marcada, las cajas de
--      la otra tienda se suman a la línea de su producto, con `de: [{ origen_id, origen, cantidad }]` (la forma de la
--      Tarea 28). Sin nada del almacén de ese producto, una línea solo con lo de la otra tienda. La clave no cambia.
--   4. «Falta algo» igual; si falta algo de una línea con `de`, la incidencia dice de dónde venía cada caja
--      («traía 3: 2 del almacén y 1 de Algorta»).
--   5. Una tienda que solo recibe cajas de otra tienda tiene igualmente su «Recibe la bolsa» (ya era así: sale en las
--      paradas del reparto) y su lista.
-- No cambia: el trabajo del operario (ningún paso nuevo), la ruta y sus paradas, las cuentas del almacén (R1c).
--
-- Deshacer: volver a crear motor.llamadas_sin_granel y motor.marcar_cajas_de como están en 20261029140000,
-- motor.bolsa_contenido como en 20261104110512 y motor.faltan_de_lista y motor.faltan_texto como en 20261103211530;
-- borrar motor.avisar_origen y motor.texto_de; y volver a poner «Llama a» en las líneas de hoy en adelante.

-- ---------------------------------------------------------------------------
-- 1. Las líneas que ya están creadas, de hoy en adelante, con el texto nuevo
-- ---------------------------------------------------------------------------
update public.tarea_elementos e
   set producto = 'Avisa a ' || substr(e.producto, length('Llama a ') + 1)
  from public.tareas t join public.jornadas j on j.id = t.jornada_id
 where t.id = e.tarea_id and e.tipo = 'llamada' and e.producto like 'Llama a %'
   and j.fecha >= motor.fecha_local(now());

-- ---------------------------------------------------------------------------
-- 2. Funciones nuevas
-- ---------------------------------------------------------------------------
-- De dónde venía cada caja de una línea: «traía 3: 2 del almacén y 1 de Algorta».
create or replace function motor.texto_de(p_total integer, p_de jsonb)
returns text language sql immutable set search_path = '' as $$
  with partes as (
    select 0 as n, (p_total - coalesce((select sum((d ->> 'cantidad')::int) from jsonb_array_elements(p_de) d), 0))
                   || ' del almacén' as t
     where p_total > coalesce((select sum((d ->> 'cantidad')::int) from jsonb_array_elements(p_de) d), 0)
    union all
    select k, (d ->> 'cantidad') || ' de ' || (d ->> 'origen') from jsonb_array_elements(p_de) with ordinality a(d, k)),
  l as (select array_agg(t order by n) as v from partes)
  select 'traía ' || p_total || ': '
         || case when array_length(v, 1) = 1 then v[1]
                 else array_to_string(v[1:array_length(v, 1) - 1], ', ') || ' y ' || v[array_length(v, 1)] end
    from l
$$;

-- El aviso a la tienda de origen al marcar «Avisa a [origen]…»: un aviso del almacén para hoy, como los de siempre
-- (crear_aviso_tienda). El id del aviso sale del elemento: marcarlo otra vez no crea otro.
create or replace function motor.avisar_origen(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  v_destino text;
begin
  select * into e from public.tarea_elementos where id = p_elemento and tipo = 'llamada';
  if e.id is null or e.calculo ->> 'origen_id' is null then
    return null;
  end if;
  select nombre into v_destino from public.centros_trabajo where id = e.destino_id;
  return motor.crear_aviso_tienda_de(
    p_persona, md5('aviso_origen:' || e.id)::uuid, motor.fecha_local(p_ahora),
    'Prepara ' || (e.calculo ->> 'cantidad') || ' ' || motor.texto_referencia(e.calculo ->> 'producto', e.calculo ->> 'formato')
      || ' para ' || v_destino || ': lo recoge hoy el reparto',
    (e.calculo ->> 'origen_id')::uuid, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Funciones que se rehacen
-- ---------------------------------------------------------------------------
create or replace function motor.llamadas_sin_granel(p_jornada uuid)
returns table (destino_id uuid, texto text, calculo jsonb, orden integer)
language sql stable set search_path = '' as $$
  select x.destino_id,
         'Avisa a ' || o.nombre || ' para que prepare ' || x.cantidad || ' ' || motor.texto_referencia(x.producto, x.formato)
           || ' para su retirada',
         jsonb_build_object('origen_id', x.origen_id, 'producto', x.producto, 'formato', x.formato, 'cantidad', x.cantidad),
         (row_number() over (order by o.nombre, x.producto, x.formato))::int
    from motor.decisiones_sin_granel(p_jornada) x join public.centros_trabajo o on o.id = x.origen_id
   where x.accion = 'otra_tienda'
$$;

create or replace function motor.marcar_cajas_de(p_persona uuid, p_elemento uuid, p_cantidad_hecha integer, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  v_estado text;
  v_tienda_completa boolean;
begin
  v_error := motor.comprobar_elemento(p_persona, p_elemento, p_ahora);
  if v_error is not null then
    if exists (select 1 from public.tarea_elementos
               where id = p_elemento and cantidad_hecha = p_cantidad_hecha) then
      return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);  -- repetición
    end if;
    return v_error;
  end if;
  select * into e from public.tarea_elementos where id = p_elemento;
  if e.tipo not in ('caja_bolsa', 'peticion', 'llamada') then
    return motor.error('DATOS_NO_VALIDOS', 'Las cajas se marcan en las bolsas.');
  end if;
  if p_cantidad_hecha is null or p_cantidad_hecha < 0 or p_cantidad_hecha > e.cantidad then
    return motor.error('CANTIDAD_FUERA_DE_RANGO', 'La cantidad debe estar entre 0 y ' || e.cantidad || '.');
  end if;
  if e.cantidad_hecha = p_cantidad_hecha then
    return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);  -- repetición: nada cambia
  end if;

  v_error := motor.asegurar_en_curso(p_persona, e.tarea_id, p_ahora);
  if v_error is not null then return v_error; end if;

  v_estado := case when p_cantidad_hecha = e.cantidad then 'hecho'
                   when p_cantidad_hecha > 0 then 'en_curso' else 'pendiente' end;
  update public.tarea_elementos
     set cantidad_hecha = p_cantidad_hecha, estado = v_estado,
         iniciado_en = coalesce(iniciado_en, p_ahora),
         terminado_en = case when v_estado = 'hecho' then p_ahora end
   where id = p_elemento;
  perform motor.registrar('cajas_marcadas', p_persona, null, e.tarea_id,
                          jsonb_build_object('elemento', p_elemento, 'cajas', p_cantidad_hecha));
  -- Tarea 38: al marcar «Avisa a [origen]…», la tienda de origen recibe el aviso (una vez por elemento).
  if e.tipo = 'llamada' and v_estado = 'hecho' then
    perform motor.avisar_origen(p_persona, p_elemento, p_ahora);
  end if;

  if v_estado = 'hecho' then
    -- Punto de encaje: solo cuando la tienda (o el destino) está completa.
    select not exists (select 1 from public.tarea_elementos
                        where tarea_id = e.tarea_id and tipo in ('caja_bolsa', 'peticion', 'llamada')
                          and destino_id is not distinct from e.destino_id and estado <> 'hecho')
      into v_tienda_completa;
    perform motor.tras_elemento(p_persona, e.tarea_id, v_tienda_completa, p_ahora);
  end if;
  return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
end;
$$;

create or replace function motor.bolsa_contenido(p_reparto uuid, p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  with b as (select (r.resultado -> 'tareas' ->> 'bolsas')::uuid as tarea from public.repartos r where r.id = p_reparto),
  e as (select el.tipo, el.lote, el.producto, el.formato, el.orden_sugerido, el.calculo,
               coalesce(nullif(el.cantidad_hecha, 0), case when el.estado = 'hecho' then el.cantidad end, 0) as metidas
          from public.tarea_elementos el, b
         where el.tarea_id = b.tarea and el.destino_id = p_centro and el.tipo in ('caja_bolsa', 'peticion', 'llamada')),
  -- Tarea 38: las cajas que le llegan de otra tienda (R1e), desde que el operario marca «Avisa a [origen]…».
  otra as (select e.calculo ->> 'producto' as producto, coalesce(e.calculo ->> 'formato', '') as formato,
                  (e.calculo ->> 'origen_id')::uuid as origen_id, (e.calculo ->> 'cantidad')::int as cantidad
             from e where e.tipo = 'llamada' and e.metidas > 0),
  alm as (select producto, formato, sum(metidas)::int as cantidad, min(orden_sugerido) as orden
            from e where tipo = 'caja_bolsa' and lote not like 'pedido:%' and metidas > 0 group by 1, 2)
  select jsonb_build_object(
    'productos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'producto:' || x.producto || '|' || x.formato, 'producto', x.producto,
                                          'formato', x.formato, 'cantidad', x.cantidad)
                       -- Lo de otra tienda se suma a la línea de su producto, con `de` (la forma de la Tarea 28).
                       || case when x.de is not null then jsonb_build_object('de', x.de) else '{}'::jsonb end
                       order by x.orden, x.producto, x.formato)
        from (select coalesce(a.producto, o.producto) as producto, coalesce(a.formato, o.formato) as formato,
                     coalesce(a.cantidad, 0) + coalesce(o.cantidad, 0) as cantidad,
                     coalesce(a.orden, 2147483647) as orden, o.de
                from alm a
                full join (select ot.producto, ot.formato, sum(ot.cantidad)::int as cantidad,
                                  jsonb_agg(jsonb_build_object('origen_id', c.id, 'origen', c.nombre, 'cantidad', ot.cantidad)
                                            order by c.nombre) as de
                             from otra ot join public.centros_trabajo c on c.id = ot.origen_id
                            group by 1, 2) o on o.producto = a.producto and o.formato = a.formato) x), '[]'::jsonb),
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

create or replace function motor.faltan_de_lista(p_contenido jsonb, p_faltan jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_items jsonb;
  v_faltan jsonb := '[]';
  x jsonb;
  it jsonb;
  v_cant integer;
begin
  select coalesce(jsonb_agg(y), '[]') into v_items from (
    select jsonb_build_object('clave', c ->> 'clave', 'texto', trim((c ->> 'producto') || ' ' || (c ->> 'formato')),
                              'maximo', (c ->> 'cantidad')::int, 'producto', true)
           -- Tarea 38: si trae cajas de otra tienda, de dónde venía cada una («traía 3: 2 del almacén y 1 de Algorta»).
           || case when c ? 'de' then jsonb_build_object('traia', motor.texto_de((c ->> 'cantidad')::int, c -> 'de'))
                   else '{}'::jsonb end as y
      from jsonb_array_elements(p_contenido -> 'productos') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', c ->> 'texto', 'maximo', 1, 'producto', false)
      from jsonb_array_elements(p_contenido -> 'peticiones') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', 'Pedido de ' || (c ->> 'cliente'), 'maximo', 1, 'producto', false)
      from jsonb_array_elements(p_contenido -> 'pedidos') c) s;
  if p_faltan is not null and jsonb_typeof(p_faltan) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_faltan, '[]')) loop
    select i into it from jsonb_array_elements(v_items) i where i ->> 'clave' = x ->> 'clave';
    if it is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    if exists (select 1 from jsonb_array_elements(v_faltan) f where f ->> 'clave' = x ->> 'clave') then
      return motor.error('DATOS_NO_VALIDOS', 'Cada cosa, una sola vez.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_cant := case when x ? 'cantidad' and jsonb_typeof(x -> 'cantidad') = 'number' then (x ->> 'cantidad')::numeric::int
                   when x ? 'cantidad' then -1 else (it ->> 'maximo')::int end;
    if v_cant < 1 or v_cant > (it ->> 'maximo')::int or (x ? 'cantidad' and (x ->> 'cantidad')::numeric <> v_cant) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas faltan de ' || (it ->> 'texto') || ': de 1 a ' || (it ->> 'maximo') || '.',
                         jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_faltan := v_faltan || (jsonb_build_object('clave', it ->> 'clave', 'texto', it ->> 'texto', 'cantidad', v_cant)
                             || case when it ? 'traia' then jsonb_build_object('traia', it -> 'traia') else '{}'::jsonb end);
  end loop;
  return v_faltan;
end;
$$;

create or replace function motor.faltan_texto(p_faltan jsonb)
returns text language sql immutable set search_path = '' as $$
  select string_agg(case when (f ->> 'cantidad')::int > 1 or (f ->> 'clave') like 'producto:%'
                         then (f ->> 'cantidad') || 'x ' else '' end || (f ->> 'texto')
                    || coalesce(' (' || (f ->> 'traia') || ')', ''), '; ')
    from jsonb_array_elements(p_faltan) f
$$;

revoke execute on all functions in schema motor from public;
