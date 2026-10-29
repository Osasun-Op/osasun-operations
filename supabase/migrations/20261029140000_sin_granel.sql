-- Tarea 16 · Producto sin granel en el reparto (ESTADO v1.30, §5 R1e).
-- 1. La producción del reparto marca lo que hay que hacer sin granel (lo calcula
--    el servidor: calculo.sin_granel, para y tiendas_con_stock).
-- 2. resolver_sin_granel(elemento_id, decisiones): el operario decide, tienda a
--    tienda, «quitar» o «otra_tienda». Las decisiones se guardan en el elemento
--    (calculo.decisiones) y todo lo demás sale de ellas (motor.aplicar_sin_granel):
--    la bolsa lleva menos, en la tienda que recibe aparece «Llama a …» (tipo
--    llamada), la parada para quien hace la ruta, el texto para WhatsApp y las
--    cuentas (lo de otra tienda no sale del almacén; en camino, −N en la que da y
--    +N en la que recibe, como el reparto).
-- 3. Al modificar el reparto se conservan las decisiones «otra_tienda» de las
--    tiendas que siguen (como mucho, lo que pide ahora la tienda); las «quitar» ya
--    están en la cantidad nueva de la línea.

alter table public.tarea_elementos drop constraint tarea_elementos_tipo_check;
alter table public.tarea_elementos add constraint tarea_elementos_tipo_check
  check (tipo in ('referencia_produccion', 'caja_bolsa', 'peticion', 'llamada'));

-- ---------------------------------------------------------------------------
-- Decisiones (una sola fuente)
-- ---------------------------------------------------------------------------
-- Las decisiones de las referencias sin granel ya resueltas de la producción del
-- reparto de una jornada.
create or replace function motor.decisiones_sin_granel(p_jornada uuid)
returns table (elemento_id uuid, destino_id uuid, accion text, origen_id uuid, producto text, formato text,
               cantidad integer, resuelto_en timestamptz)
language sql stable set search_path = '' as $$
  select e.id, (d ->> 'destino_id')::uuid, d ->> 'accion', (d ->> 'origen_id')::uuid, e.producto, e.formato,
         (d ->> 'cantidad')::int, (e.calculo ->> 'resuelto_en')::timestamptz
    from public.tareas t
    join public.tarea_elementos e on e.tarea_id = t.id and e.tipo = 'referencia_produccion' and e.lote = 'reparto'
    cross join lateral jsonb_array_elements(e.calculo -> 'decisiones') d
   where t.jornada_id = p_jornada and t.clave = 'produccion_reparto'
     and coalesce((e.calculo ->> 'resuelto')::boolean, false)
$$;

-- Las decisiones con el nombre de las tiendas, para las pantallas.
create or replace function motor.decisiones_json(p_decisiones jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('destino_id', d.id, 'destino', d.nombre, 'accion', x ->> 'accion',
                                               'origen_id', o.id, 'origen', o.nombre, 'cantidad', (x ->> 'cantidad')::int)
                            order by n), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_decisiones, '[]')) with ordinality a(x, n)
    join public.centros_trabajo d on d.id = (x ->> 'destino_id')::uuid
    left join public.centros_trabajo o on o.id = (x ->> 'origen_id')::uuid
$$;

-- Texto de la referencia: «BZ1 4g».
create or replace function motor.texto_referencia(p_producto text, p_formato text)
returns text language sql immutable set search_path = '' as $$
  select p_producto || case when coalesce(p_formato, '') <> '' then ' ' || p_formato else '' end
$$;

-- La parada para quien hace la ruta: «Recoge N [producto formato] en [origen] y déjalas en [destino]».
create or replace function motor.paradas_reparto(p_jornada uuid)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'origen_id', o.id, 'origen', o.nombre, 'destino_id', d.id, 'destino', d.nombre,
           'producto', x.producto, 'formato', x.formato, 'cantidad', x.cantidad,
           'texto', 'Recoge ' || x.cantidad || ' ' || motor.texto_referencia(x.producto, x.formato)
                    || ' en ' || o.nombre || ' y déjalas en ' || d.nombre)
           order by o.nombre, d.nombre, x.producto, x.formato), '[]'::jsonb)
    from motor.decisiones_sin_granel(p_jornada) x
    join public.centros_trabajo o on o.id = x.origen_id
    join public.centros_trabajo d on d.id = x.destino_id
   where x.accion = 'otra_tienda'
$$;

-- Los avisos de llamada de la bolsa de la tienda que recibe.
create or replace function motor.llamadas_sin_granel(p_jornada uuid)
returns table (destino_id uuid, texto text, calculo jsonb, orden integer)
language sql stable set search_path = '' as $$
  select x.destino_id,
         'Llama a ' || o.nombre || ' para que prepare ' || x.cantidad || ' ' || motor.texto_referencia(x.producto, x.formato)
           || ' para su retirada',
         jsonb_build_object('origen_id', x.origen_id, 'producto', x.producto, 'formato', x.formato, 'cantidad', x.cantidad),
         (row_number() over (order by o.nombre, x.producto, x.formato))::int
    from motor.decisiones_sin_granel(p_jornada) x join public.centros_trabajo o on o.id = x.origen_id
   where x.accion = 'otra_tienda'
$$;

-- ---------------------------------------------------------------------------
-- Aplicar las decisiones: producción, bolsas y avisos de llamada
-- ---------------------------------------------------------------------------
-- Rehace, a partir de las decisiones, lo que depende de ellas. Se llama al
-- decidir y al guardar (o modificar) el reparto. Repetirlo no cambia nada.
create or replace function motor.aplicar_sin_granel(p_persona uuid, p_jornada uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  r public.repartos;
  v_prod uuid;
  v_bolsas uuid;
  e public.tarea_elementos;
  d jsonb;
  v_dec jsonb;
  v_falta integer;
  v_suma integer;
  v_pedido integer;
  v_cant integer;
  v_resuelto boolean;
begin
  select * into r from public.repartos where jornada_id = p_jornada and tipo = 'reparto' and estado = 'aceptado';
  if r.id is null then return; end if;
  select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
  select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';

  -- 1. Decisiones: solo de tiendas que siguen recibiendo, como mucho lo que piden,
  --    y entre todas como mucho lo que falta. Resuelta si cubren todo lo que falta.
  for e in select * from public.tarea_elementos
            where tarea_id = v_prod and tipo = 'referencia_produccion' and lote = 'reparto' and calculo ? 'decisiones'
  loop
    if not coalesce((e.calculo ->> 'sin_granel')::boolean, false) then
      update public.tarea_elementos set calculo = calculo - 'decisiones' - 'resuelto' - 'resuelto_por' - 'resuelto_en'
       where id = e.id;
      continue;
    end if;
    v_falta := (e.calculo ->> 'faltan')::int - e.cantidad_hecha;
    v_dec := '[]';
    v_suma := 0;
    for d in select x from jsonb_array_elements(e.calculo -> 'decisiones') x loop
      select (p ->> 'pedido')::int into v_pedido
        from jsonb_array_elements(coalesce(e.calculo -> 'para', '[]')) p where p ->> 'destino_id' = d ->> 'destino_id';
      v_cant := least((d ->> 'cantidad')::int, coalesce(v_pedido, 0), v_falta - v_suma);
      if v_cant > 0 then
        v_dec := v_dec || jsonb_build_array(jsonb_set(d, '{cantidad}', to_jsonb(v_cant)));
        v_suma := v_suma + v_cant;
      end if;
    end loop;
    v_resuelto := v_falta > 0 and v_suma = v_falta;
    update public.tarea_elementos
       set calculo = calculo || jsonb_build_object('decisiones', v_dec, 'resuelto', v_resuelto),
           cantidad = case when v_resuelto then cantidad_hecha else (calculo ->> 'faltan')::int end,
           estado = case when v_resuelto or cantidad_hecha >= (calculo ->> 'faltan')::int then 'hecho'
                         when estado = 'hecho' then 'pendiente' else estado end,
           terminado_en = case when v_resuelto or cantidad_hecha >= (calculo ->> 'faltan')::int
                               then coalesce(terminado_en, p_ahora) end,
           motivo = case when v_resuelto then 'No se produce: ' || (
                           select string_agg(case x ->> 'accion' when 'quitar' then (x ->> 'cantidad') || ' se quitan de ' || dn.nombre
                                                  else (x ->> 'cantidad') || ' para ' || dn.nombre || ' de ' || o.nombre end, '; ')
                             from jsonb_array_elements(v_dec) x
                             join public.centros_trabajo dn on dn.id = (x ->> 'destino_id')::uuid
                             left join public.centros_trabajo o on o.id = (x ->> 'origen_id')::uuid) || '.'
                         else calculo ->> 'aviso' end
     where id = e.id;
  end loop;

  if v_bolsas is null then return; end if;

  -- 2. Bolsas de reposición: lo que pide cada línea menos lo decidido (quitar o de otra tienda).
  with lineas as (
    select l.destino_id, l.producto, coalesce(l.formato, '') as formato, sum(l.cantidad)::int as cantidad
      from public.reparto_lineas l
     where l.reparto_id = r.id and l.clase = 'producto' and l.error is null
     group by 1, 2, 3),
  deseado as (
    select l.destino_id, l.producto, l.formato,
           l.cantidad - coalesce((select sum(x.cantidad) from motor.decisiones_sin_granel(p_jornada) x
                                   where x.destino_id = l.destino_id and x.producto = l.producto
                                     and x.formato = l.formato), 0)::int as cantidad
      from lineas l)
  update public.tarea_elementos b
     set cantidad = s.cantidad, cantidad_hecha = least(b.cantidad_hecha, s.cantidad),
         estado = case when least(b.cantidad_hecha, s.cantidad) >= s.cantidad then 'hecho'
                       when least(b.cantidad_hecha, s.cantidad) > 0 then 'en_curso' else 'pendiente' end,
         terminado_en = case when least(b.cantidad_hecha, s.cantidad) >= s.cantidad then coalesce(b.terminado_en, p_ahora) end
    from deseado s
   where b.tarea_id = v_bolsas and b.tipo = 'caja_bolsa' and b.lote = 'reparto' and b.destino_id = s.destino_id
     and b.producto = s.producto and b.formato = s.formato and s.cantidad > 0 and b.cantidad <> s.cantidad;

  delete from public.tarea_elementos b
   where b.tarea_id = v_bolsas and b.tipo = 'caja_bolsa' and b.lote = 'reparto'
     and exists (select 1 from motor.decisiones_sin_granel(p_jornada) x
                  where x.destino_id = b.destino_id and x.producto = b.producto and x.formato = b.formato)
     and (select coalesce(sum(l.cantidad), 0) from public.reparto_lineas l
           where l.reparto_id = r.id and l.clase = 'producto' and l.error is null and l.destino_id = b.destino_id
             and l.producto = b.producto and coalesce(l.formato, '') = b.formato)
         <= (select sum(x.cantidad) from motor.decisiones_sin_granel(p_jornada) x
              where x.destino_id = b.destino_id and x.producto = b.producto and x.formato = b.formato);

  -- Lo que vuelve a ir en la bolsa (una decisión que ya no está).
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
  select v_bolsas, 'caja_bolsa', 'reparto', s.producto, s.formato, s.destino_id, s.cantidad,
         coalesce((select p.orden_sugerido from public.tarea_elementos p
                    where p.tarea_id = v_prod and p.tipo = 'referencia_produccion' and p.lote = 'reparto'
                      and p.producto = s.producto and p.formato = s.formato), 0)
    from (select l.destino_id, l.producto, l.formato,
                 l.cantidad - coalesce((select sum(x.cantidad) from motor.decisiones_sin_granel(p_jornada) x
                                         where x.destino_id = l.destino_id and x.producto = l.producto
                                           and x.formato = l.formato), 0)::int as cantidad
            from (select k.destino_id, k.producto, coalesce(k.formato, '') as formato, sum(k.cantidad)::int as cantidad
                    from public.reparto_lineas k
                   where k.reparto_id = r.id and k.clase = 'producto' and k.error is null
                   group by 1, 2, 3) l) s
   where s.cantidad > 0
     and not exists (select 1 from public.tarea_elementos b
                      where b.tarea_id = v_bolsas and b.tipo = 'caja_bolsa' and b.lote = 'reparto'
                        and b.destino_id = s.destino_id and b.producto = s.producto and b.formato = s.formato);

  -- 3. «Llama a [origen] para que prepare N [producto formato] para su retirada», en la bolsa de la tienda que recibe.
  delete from public.tarea_elementos b
   where b.tarea_id = v_bolsas and b.tipo = 'llamada' and b.lote = 'reparto'
     and not exists (select 1 from motor.llamadas_sin_granel(p_jornada) l where l.destino_id = b.destino_id and l.texto = b.producto);
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido, calculo)
  select v_bolsas, 'llamada', 'reparto', l.texto, '', l.destino_id, 1, l.orden, l.calculo from motor.llamadas_sin_granel(p_jornada) l
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do nothing;
end;
$$;


-- ---------------------------------------------------------------------------
-- resolver_sin_granel(elemento_id, decisiones) · el operario, en la producción
-- ---------------------------------------------------------------------------
-- decisiones: [{ destino_id, accion: "quitar" | "otra_tienda", origen_id?, cantidad }],
-- una por tienda que recibe; entre todas, lo que falta.
create or replace function motor.resolver_sin_granel_de(p_persona uuid, p_elemento uuid, p_decisiones jsonb, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  t public.tareas;
  v_error jsonb;
  v_falta integer;
  v_dec jsonb;
  v_tiendas uuid[];
  x jsonb;
  v_para jsonb;
  v_suma integer := 0;
begin
  select * into e from public.tarea_elementos where id = p_elemento;
  select * into t from public.tareas where id = e.tarea_id;
  v_error := motor.comprobar_elemento(p_persona, p_elemento, p_ahora);
  if e.id is not null and t.clave = 'produccion_reparto' and coalesce((e.calculo ->> 'resuelto')::boolean, false) then
    -- Repetir lo mismo no es un error (aunque la tarea ya esté hecha).
    select jsonb_agg(jsonb_build_object('destino_id', y ->> 'destino_id', 'accion', y ->> 'accion',
                                        'origen_id', y ->> 'origen_id', 'cantidad', (y ->> 'cantidad')::int)
                     order by y ->> 'destino_id') into v_dec
      from jsonb_array_elements(case when jsonb_typeof(p_decisiones) = 'array' then p_decisiones else '[]' end) y;
    if v_dec = (select jsonb_agg(jsonb_build_object('destino_id', y ->> 'destino_id', 'accion', y ->> 'accion',
                                                    'origen_id', y ->> 'origen_id', 'cantidad', (y ->> 'cantidad')::int)
                                 order by y ->> 'destino_id')
                  from jsonb_array_elements(e.calculo -> 'decisiones') y) then
      return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
    end if;
  end if;
  if v_error is not null then return v_error; end if;
  if t.clave <> 'produccion_reparto' or e.tipo <> 'referencia_produccion' or e.lote <> 'reparto'
     or not coalesce((e.calculo ->> 'sin_granel')::boolean, false) then
    return motor.error('DATOS_NO_VALIDOS', 'Esta referencia no está sin granel: se hace como siempre.');
  end if;
  if jsonb_typeof(p_decisiones) is distinct from 'array' or jsonb_array_length(p_decisiones) = 0 then
    return motor.error('DATOS_NO_VALIDOS', 'Elige qué se hace en cada tienda: quitarlo o cogerlo de otra tienda.');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('reparto:' || t.jornada_id || ':reparto', 0));
  select * into e from public.tarea_elementos where id = p_elemento;
  v_falta := (e.calculo ->> 'faltan')::int - e.cantidad_hecha;
  v_tiendas := array(select c.id from public.centros_trabajo c,
                       jsonb_array_elements_text((select valor -> 'reparto' from public.configuracion
                                                   where clave = 'destinos_reparto' and centro_id is null)) k
                      where c.codigo = k);
  v_dec := '[]';
  for x in select y from jsonb_array_elements(p_decisiones) y loop
    select p into v_para from jsonb_array_elements(coalesce(e.calculo -> 'para', '[]')) p
     where p ->> 'destino_id' = x ->> 'destino_id';
    if v_para is null then
      return motor.error('DATOS_NO_VALIDOS', 'Esa tienda no recibe esta referencia en el reparto.',
                         jsonb_build_object('destino_id', x ->> 'destino_id'));
    end if;
    if exists (select 1 from jsonb_array_elements(v_dec) z where z ->> 'destino_id' = x ->> 'destino_id') then
      return motor.error('DATOS_NO_VALIDOS', 'Una sola decisión por tienda.', jsonb_build_object('destino_id', x ->> 'destino_id'));
    end if;
    if x ->> 'accion' is null or x ->> 'accion' not in ('quitar', 'otra_tienda') then
      return motor.error('DATOS_NO_VALIDOS', 'En cada tienda: «quitar» o «otra_tienda».');
    end if;
    if jsonb_typeof(x -> 'cantidad') is distinct from 'number' or (x ->> 'cantidad')::numeric <> floor((x ->> 'cantidad')::numeric)
       or (x ->> 'cantidad')::int < 1 or (x ->> 'cantidad')::int > (v_para ->> 'pedido')::int then
      return motor.error('DATOS_NO_VALIDOS', 'La cantidad de ' || (v_para ->> 'destino') || ' debe estar entre 1 y '
                                             || (v_para ->> 'pedido') || '.');
    end if;
    if x ->> 'accion' = 'otra_tienda' and (x ->> 'origen_id' is null or x ->> 'origen_id' = x ->> 'destino_id'
        or not exists (select 1 from unnest(v_tiendas) u where u::text = x ->> 'origen_id')) then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de qué otra tienda del reparto se coge.');
    end if;
    v_dec := v_dec || jsonb_build_array(jsonb_build_object(
      'destino_id', x ->> 'destino_id', 'accion', x ->> 'accion',
      'origen_id', case when x ->> 'accion' = 'otra_tienda' then x ->> 'origen_id' end, 'cantidad', (x ->> 'cantidad')::int));
    v_suma := v_suma + (x ->> 'cantidad')::int;
  end loop;
  if v_suma <> v_falta then
    return motor.error('DATOS_NO_VALIDOS', 'Entre todas las tiendas tienen que sumar ' || v_falta || ' (las que faltan).',
                       jsonb_build_object('faltan', v_falta, 'suman', v_suma));
  end if;

  v_error := motor.asegurar_en_curso(p_persona, e.tarea_id, p_ahora);
  if v_error is not null then return v_error; end if;
  update public.tarea_elementos
     set calculo = calculo || jsonb_build_object('decisiones', v_dec, 'resuelto_por', p_persona, 'resuelto_en', p_ahora),
         iniciado_en = coalesce(iniciado_en, p_ahora)
   where id = p_elemento;
  perform motor.aplicar_sin_granel(p_persona, t.jornada_id, p_ahora);
  perform motor.registrar('sin_granel_resuelto', p_persona, t.jornada_id, e.tarea_id,
                          jsonb_build_object('elemento', p_elemento, 'producto', e.producto, 'formato', e.formato,
                                             'decisiones', v_dec, 'a_las', p_ahora));
  -- La bolsa puede quedar completa o volver a abrirse (un aviso de llamada nuevo).
  perform motor.ajustar_estado_lista(p_persona, (select b.id from public.tareas b where b.jornada_id = t.jornada_id and b.clave = 'bolsas'),
                                     'Sin bolsas', p_ahora);
  perform motor.tras_elemento(p_persona, e.tarea_id, true, p_ahora);
  return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
end;
$$;

create or replace function motor.api_resolver_sin_granel(p_elemento_id uuid, p_decisiones jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.resolver_sin_granel_de(auth.uid(), p_elemento_id, p_decisiones, now());
end;
$$;

create or replace function public.resolver_sin_granel(elemento_id uuid, decisiones jsonb)
returns jsonb language sql set search_path = '' as $$ select motor.api_resolver_sin_granel(elemento_id, decisiones) $$;


-- ---------------------------------------------------------------------------
-- Texto para WhatsApp con lo decidido: «2x BZ1 4g (de Algorta)»; lo quitado ya no sale
-- ---------------------------------------------------------------------------
create or replace function motor.texto_reparto(p_reparto uuid)
returns text language plpgsql stable set search_path = '' as $$
declare
  r public.repartos;
  l public.reparto_lineas;
  v_salida text[] := '{}';
  v_tienda integer;           -- posición de la línea de la tienda en curso
  v_con_algo boolean := false;
  v_hechas text[] := '{}';
  v_quitar integer;
  v_otras integer;
  v_propias integer;
  o record;
begin
  select * into r from public.repartos where id = p_reparto;
  if r.id is null then return null; end if;
  if r.tipo <> 'reparto' or r.estado <> 'aceptado'
     or not exists (select 1 from motor.decisiones_sin_granel(r.jornada_id)) then
    return r.texto_original;
  end if;
  for l in select * from public.reparto_lineas where reparto_id = r.id order by num_linea loop
    if l.clase = 'tienda' then
      if v_tienda is not null and not v_con_algo then
        v_salida := v_salida[1:v_tienda - 2];   -- sin la tienda vacía ni su línea en blanco
      end if;
      v_salida := v_salida || l.texto;
      v_tienda := array_length(v_salida, 1);
      v_con_algo := false;
    elsif l.clase = 'producto' and l.error is null
          and not (l.destino_id || '|' || l.producto || '|' || coalesce(l.formato, '')) = any (v_hechas) then
      v_hechas := v_hechas || (l.destino_id || '|' || l.producto || '|' || coalesce(l.formato, ''));
      select coalesce(sum(x.cantidad) filter (where x.accion = 'quitar'), 0),
             coalesce(sum(x.cantidad) filter (where x.accion = 'otra_tienda'), 0)
        into v_quitar, v_otras
        from motor.decisiones_sin_granel(r.jornada_id) x
       where x.destino_id = l.destino_id and x.producto = l.producto and x.formato = coalesce(l.formato, '');
      if v_quitar + v_otras = 0 then
        v_salida := v_salida || l.texto;
        v_con_algo := true;
        continue;
      end if;
      v_propias := (select sum(k.cantidad) from public.reparto_lineas k
                     where k.reparto_id = r.id and k.clase = 'producto' and k.error is null and k.destino_id = l.destino_id
                       and k.producto = l.producto and coalesce(k.formato, '') = coalesce(l.formato, '')) - v_quitar - v_otras;
      if v_propias > 0 then
        v_salida := v_salida || (v_propias || 'x ' || motor.texto_referencia(l.producto, l.formato));
        v_con_algo := true;
      end if;
      for o in select c.nombre, sum(x.cantidad)::int as cantidad
                 from motor.decisiones_sin_granel(r.jornada_id) x join public.centros_trabajo c on c.id = x.origen_id
                where x.accion = 'otra_tienda' and x.destino_id = l.destino_id and x.producto = l.producto
                  and x.formato = coalesce(l.formato, '')
                group by c.nombre order by c.nombre loop
        v_salida := v_salida || (o.cantidad || 'x ' || motor.texto_referencia(l.producto, l.formato) || ' (de ' || o.nombre || ')');
        v_con_algo := true;
      end loop;
    elsif l.clase = 'producto' and l.error is null then
      continue;                 -- la misma referencia repetida en la tienda: ya va arriba
    else
      v_salida := v_salida || l.texto;
      if l.clase = 'peticion' then v_con_algo := true; end if;
    end if;
  end loop;
  if v_tienda is not null and not v_con_algo then
    v_salida := v_salida[1:v_tienda - 2];
  end if;
  return array_to_string(v_salida, E'\n');
end;
$$;


-- ---------------------------------------------------------------------------
-- Detalle del reparto (Modificar reparto e histórico), elementos y paradas
-- ---------------------------------------------------------------------------
create or replace function motor.reparto_detalle_json(p_reparto uuid, p_sale text)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'reparto_id', r.id, 'tipo', r.tipo, 'sale', p_sale,
    'aceptado_en', r.pegado_en, 'pegado_por', r.pegado_por,
    'pegado_por_nombre', (select nombre from public.personas where id = r.pegado_por),
    'texto_whatsapp', case when p_sale is null then motor.texto_reparto(r.id)
                           else regexp_replace(motor.texto_reparto(r.id), '^(REPARTO [^\n]*\n)SALE: [^\n]*',
                                               '\1SALE: ' || case p_sale when 'operario' then 'ALMACÉN' else 'YO' end) end,
    'lineas', coalesce((
      -- R1e: lo quitado ya no cuenta; lo que viene de otra tienda sigue en la línea, con `de`.
      select jsonb_agg(jsonb_build_object('destino_id', x.destino_id, 'destino', c.nombre, 'producto', x.producto,
                                          'formato', x.formato, 'cantidad', x.cantidad - coalesce(q.quitar, 0))
                       || case when q.de is not null then jsonb_build_object('de', q.de) else '{}'::jsonb end
                       order by x.primera)
        from (select l.destino_id, l.producto, coalesce(l.formato, '') as formato, sum(l.cantidad)::int as cantidad,
                     min(l.num_linea) as primera
                from public.reparto_lineas l
               where l.reparto_id = r.id and l.clase = 'producto' and l.error is null
               group by 1, 2, 3) x
        join public.centros_trabajo c on c.id = x.destino_id
        left join lateral (
          select sum(d.cantidad) filter (where d.accion = 'quitar') as quitar,
                 jsonb_agg(jsonb_build_object('origen_id', o.id, 'origen', o.nombre, 'cantidad', d.cantidad) order by o.nombre)
                   filter (where d.accion = 'otra_tienda') as de
            from motor.decisiones_sin_granel(r.jornada_id) d
            left join public.centros_trabajo o on o.id = d.origen_id
           where r.tipo = 'reparto' and r.estado = 'aceptado'
             and d.destino_id = x.destino_id and d.producto = x.producto and d.formato = x.formato) q on true
       where x.cantidad - coalesce(q.quitar, 0) > 0), '[]'::jsonb),
    'peticiones', motor.peticiones_json(r.peticiones))
  from public.repartos r where r.id = p_reparto;
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
    'elementos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'tipo', e.tipo, 'producto', e.producto, 'formato', e.formato,
               'texto', case when e.tipo in ('peticion', 'llamada') then e.producto end,
               'categoria', e.categoria, 'destino', c.nombre, 'destino_id', e.destino_id,
               'bolsa', case when e.tipo = 'referencia_produccion' then null
                             when e.lote like 'pedido:%' then 'Pedido de cliente · ' || pc.cliente
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
      where e.tarea_id = t.id), '[]'::jsonb))
  from public.tareas t where t.id = p_tarea;
$$;

-- Los avisos de llamada se marcan como las peticiones (0 o 1); la tienda no está completa sin ellos.
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

-- reparto_de_hoy (tarea_activa y estado_actual): las paradas para quien hace la ruta.
create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
as $$
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
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r left join public.personas pe on pe.id = r.pegado_por
       where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'))
    || motor.seguimiento_de(p_persona, p_ahora);
end;
$$;

create or replace function motor.estado_actual_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with op as (select id, nombre from public.personas where id = motor.operario_por_defecto()),
  j as (select jo.* from public.jornadas jo join op on op.id = jo.persona_id where jo.fecha = motor.fecha_local(p_ahora))
  select jsonb_build_object(
    'ahora', motor.hora_texto(p_ahora),
    'fecha', motor.fecha_local(p_ahora),
    'operario', (select jsonb_build_object('id', op.id, 'nombre', op.nombre) from op),
    'jornada', (select jsonb_build_object('id', j.id, 'sale', j.sale, 'hay_envio', j.hay_envio, 'estado', j.estado) from j),
    'en_curso', (select motor.tarea_json(t.id) from public.tareas t join j on j.id = t.jornada_id where t.estado = 'en_curso'),
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r join j on j.id = r.jornada_id
        left join public.personas pe on pe.id = r.pegado_por
       where r.tipo = 'reparto' and r.estado = 'aceptado'),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.estado <> 'resuelto' and p.persona_id = (select id from op)), '[]'::jsonb),
    'incidencia_en_curso', motor.seguimiento_de((select id from op), p_ahora) -> 'incidencia_en_curso',
    'incidencias_abiertas', coalesce((
      select jsonb_agg(motor.incidencia_json(i.id, p_ahora) order by i.iniciada_en)
        from public.incidencias i where i.persona_id = (select id from op) and i.estado <> 'cerrada'), '[]'::jsonb),
    'arrastradas', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado) order by t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id where t.tarea_origen_id is not null), '[]'::jsonb),
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado, 'origen', t.origen,
                                          'obligatoria', t.obligatoria, 'urgente', t.urgente,
                                          'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)),
                                          'motivo', t.motivo_no_hecha,
                                          'iniciada_en', t.iniciada_en, 'terminada_en', t.terminada_en,
                                          'minutos', motor.minutos_tarea(t, p_ahora))
                       order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id
       where not t.retirada_por_condicion and t.origen <> 'problema'), '[]'::jsonb),
    'retrasos_salida', coalesce((
      select jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                          'minutos', (r.datos ->> 'minutos')::int, 'nueva_hora', r.datos ->> 'nueva_hora',
                                          'sale', r.datos ->> 'sale', 'aviso', r.datos ->> 'aviso') order by r.id)
        from public.registro_eventos r join j on j.id = r.jornada_id where r.tipo = 'salida_retrasada'), '[]'::jsonb),
    'correos_no_enviados', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'asunto', m.asunto, 'estado', m.estado, 'intentos', m.intentos,
                                          'error', m.ultimo_error, 'creado_en', m.creado_en) order by m.id desc)
        from motor.correos m
       where m.estado in ('fallido', 'dudoso') and m.creado_en >= p_ahora - interval '7 days'), '[]'::jsonb),
    -- «Orden y limpieza» de hoy: cuántas se han empezado y cuántos minutos en total.
    'tiempo_libre', (
      select jsonb_build_object('veces', count(*),
                                'minutos', coalesce(round(sum(extract(epoch from
                                  coalesce(t.terminada_en, case when t.estado = 'en_curso' then p_ahora end) - t.iniciada_en)) / 60), 0)::int)
        from public.tareas t join j on j.id = t.jornada_id
        join public.plantillas_tarea p on p.id = t.plantilla_id
       where p.codigo = 'cola_orden' and t.iniciada_en is not null),
    -- R4: productos con menos de 2 semanas, de la última lectura de la hoja que la trae.
    'cobertura_baja', coalesce((
      select jsonb_build_object('datos_leidos_en', l.leido_en, 'productos', coalesce(l.cobertura -> 'productos', '[]'::jsonb),
                                'avisos', coalesce(l.cobertura -> 'avisos', '[]'::jsonb))
        from public.lecturas_sheets l where l.correcto and l.cobertura is not null and l.leido_en <= p_ahora
       order by l.leido_en desc limit 1),
      jsonb_build_object('datos_leidos_en', null, 'productos', '[]'::jsonb, 'avisos', '[]'::jsonb)),
    'lectura_sheets', jsonb_build_object(
      'ultima_correcta', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo)
                            from public.lecturas_sheets l where l.correcto order by l.leido_en desc limit 1),
      'ultimo_error', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo, 'error', l.error)
                         from public.lecturas_sheets l where not l.correcto
                          and l.leido_en > coalesce((select max(k.leido_en) from public.lecturas_sheets k where k.correcto), '-infinity')
                         order by l.leido_en desc limit 1)));
$$;

-- ---------------------------------------------------------------------------
-- Cuentas (R1c, una sola fuente)
-- ---------------------------------------------------------------------------
create or replace function motor.en_camino_en(p_operario uuid, p_ahora timestamp with time zone)
 RETURNS TABLE(destino_id uuid, producto text, formato text, cantidad integer)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
as $$
  -- Las cajas de las bolsas y, R1e, lo que se coge de otra tienda: −N en la que da y
  -- +N en la que recibe, con la misma hora que el reparto.
  select s.destino_id, s.producto, s.formato, sum(s.cantidad)::int
    from (
      select e.destino_id, e.producto, e.formato, e.cantidad_hecha as cantidad, t.clave, t.terminada_en
        from public.tareas t
        join public.jornadas j on j.id = t.jornada_id
        join public.tarea_elementos e on e.tarea_id = t.id and e.tipo = 'caja_bolsa'
       where j.persona_id = p_operario and t.estado = 'hecha'
      union all
      select v.destino_id, x.producto, x.formato, v.cantidad, t.clave, t.terminada_en
        from public.tareas t
        join public.jornadas j on j.id = t.jornada_id
        cross join lateral motor.decisiones_sin_granel(t.jornada_id) x
        cross join lateral (values (x.destino_id, x.cantidad), (x.origen_id, -x.cantidad)) v(destino_id, cantidad)
       where j.persona_id = p_operario and t.estado = 'hecha' and t.clave = 'bolsas' and x.accion = 'otra_tienda') s
   where s.terminada_en <= p_ahora and s.terminada_en > p_ahora - interval '3 days'
     and ((s.clave = 'bolsas'
           and p_ahora <= motor.en_local(motor.fecha_local(s.terminada_en),
                                         motor.config_hora('en_camino_reparto_hasta', '23:30')))
          or (s.clave in ('preparar_envio', 'preparar_envio_viernes')
              and p_ahora <= motor.en_local(motor.fecha_local(s.terminada_en) + 1,
                                            motor.config_hora('en_camino_envio_hasta', '11:59'))))
   group by 1, 2, 3
  having sum(s.cantidad) <> 0
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
    cross join salio s
    cross join lateral jsonb_array_elements(p.lineas) l
   where p.jornada_id = p_jornada and t.estado is distinct from 'cancelada'
     and case p.entrega when 'tienda' then not s.bolsas
                        else not (t.estado = 'hecha' and coalesce(t.terminada_en, '-infinity') <= p_momento) end
$$;

-- ---------------------------------------------------------------------------
-- Guardar el reparto: conserva las decisiones y las aplica; devuelve el texto
-- ---------------------------------------------------------------------------
create or replace function public.servidor_guardar_reparto(
  p_persona uuid, p_jornada uuid, p_tipo text, p_texto text, p_huella text, p_fecha_texto date, p_sale text,
  p_lectura uuid, p_lineas jsonb, p_produccion jsonb, p_bolsas jsonb, p_aceptado boolean, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r0 public.repartos;
  v_id uuid;
  v_cond text := case when p_tipo = 'reparto' then 'reparto_pegado' else 'envio_pegado' end;
  v_prod uuid;
  v_bolsas uuid;
  v_destino uuid;
  v_antes jsonb;
  v_despues jsonb;
  v_bolsas_resultado jsonb := '[]';
  v_min_caja integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                  where clave = 'duracion_min_por_caja' and centro_id is null), 1);
  v_min_bolsa integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                   where clave = 'duracion_min_por_bolsa' and centro_id is null), 3);
  v_dur_prod integer;
  v_dur_bolsas integer;
  v_resultado jsonb;
  v_es_suya boolean := p_persona = (select persona_id from public.jornadas where id = p_jornada);
  v_pegar uuid;
  v_previas jsonb := '[]';
begin
  perform pg_advisory_xact_lock(hashtextextended('reparto:' || p_jornada || ':' || p_tipo, 0));
  -- R1e: lo decidido hasta ahora (la bolsa lleva menos por ello).
  if p_tipo = 'reparto' then
    select coalesce(jsonb_agg(jsonb_build_object('destino_id', x.destino_id, 'producto', x.producto,
                                                 'formato', x.formato, 'cantidad', x.cantidad)), '[]')
      into v_previas from motor.decisiones_sin_granel(p_jornada) x;
  end if;

  if not p_aceptado then
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'con_errores', p_lectura, p_persona, p_ahora)
    returning id into v_id;
  else
    select * into r0 from public.repartos where jornada_id = p_jornada and tipo = p_tipo and estado = 'aceptado';
    if r0.huella = p_huella then
      return r0.resultado || jsonb_build_object('ya_pegado', true, 'texto_whatsapp', motor.texto_reparto(r0.id));
    end if;
    if r0.id is not null then
      update public.repartos set estado = 'sustituido' where id = r0.id;
    end if;
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado,
                                 sustituye_a, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'aceptado', r0.id, p_lectura, p_persona, p_ahora)
    returning id into v_id;
  end if;

  insert into public.reparto_lineas (reparto_id, num_linea, texto, clase, destino_id, cantidad, producto, formato, error, mensaje)
  select v_id, (l ->> 'num')::int, l ->> 'texto', l ->> 'clase', (l ->> 'destino_id')::uuid, (l ->> 'cantidad')::int,
         l ->> 'producto', l ->> 'formato', l ->> 'error', l ->> 'mensaje'
  from jsonb_array_elements(coalesce(p_lineas, '[]')) l;

  if not p_aceptado then
    perform motor.registrar('reparto_con_errores', p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo));
    return jsonb_build_object('reparto_id', v_id, 'estado', 'con_errores');
  end if;

  -- Tareas del reparto o del envío
  if p_tipo = 'reparto' then
    perform motor.fijar_sale(p_jornada, p_sale);
  else
    perform motor.fijar_envio(p_jornada, true, null);
  end if;
  perform motor.crear_tarea_condicionada(p_jornada, v_cond);
  if p_tipo = 'reparto' then
    select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
    select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';
  else
    select id into v_prod from public.tareas where jornada_id = p_jornada
       and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1;
    v_bolsas := v_prod;
  end if;
  if v_prod is null or v_bolsas is null then
    raise exception 'No hay tarea para el % de hoy', p_tipo;
  end if;
  update public.tareas set reparto_id = v_id where id in (v_prod, v_bolsas);

  -- Producción: lo que falta. Se conservan las cajas ya hechas.
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, motivo, orden_sugerido, calculo)
  select v_prod, 'referencia_produccion', p_tipo, x ->> 'producto', coalesce(x ->> 'formato', ''),
         (x ->> 'faltan')::int, x ->> 'aviso', coalesce((x ->> 'orden')::int, 0), x || jsonb_build_object('lectura_id', p_lectura)
  from jsonb_array_elements(coalesce(p_produccion, '[]')) x
  where (x ->> 'faltan')::int > 0
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set cantidad = excluded.cantidad, motivo = excluded.motivo, orden_sugerido = excluded.orden_sugerido,
         -- R1e: se conservan las decisiones «otra_tienda» (las «quitar» ya están en la línea nueva).
         calculo = excluded.calculo
                   || case when coalesce((excluded.calculo ->> 'sin_granel')::boolean, false)
                                and public.tarea_elementos.calculo ? 'decisiones'
                           then jsonb_build_object(
                                  'decisiones', coalesce((select jsonb_agg(z) from jsonb_array_elements(public.tarea_elementos.calculo -> 'decisiones') z
                                                           where z ->> 'accion' = 'otra_tienda'), '[]'::jsonb),
                                  'resuelto_por', public.tarea_elementos.calculo -> 'resuelto_por',
                                  'resuelto_en', public.tarea_elementos.calculo -> 'resuelto_en')
                           else '{}'::jsonb end,
         estado = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad then 'hecho'
                       when public.tarea_elementos.estado = 'hecho' then 'pendiente'
                       else public.tarea_elementos.estado end,
         terminado_en = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad
                             then coalesce(public.tarea_elementos.terminado_en, p_ahora) end;

  -- Referencias que ya no hacen falta: sin nada hecho se quitan; con algo hecho se cierran.
  delete from public.tarea_elementos e
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha = 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);
  update public.tarea_elementos e
     set cantidad = e.cantidad_hecha, estado = 'hecho', terminado_en = coalesce(e.terminado_en, p_ahora),
         motivo = 'Ya no hace falta con el reparto corregido'
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha > 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);

  -- Bolsas: las tiendas sin cambios se conservan; las que cambian se vuelven a
  -- comprobar caja a caja; las que ya no están se quitan.
  for v_destino in
    select distinct d from (
      select e.destino_id as d from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo
      union
      select (d ->> 'destino_id')::uuid from jsonb_array_elements(v_previas) d
      union
      select (b ->> 'destino_id')::uuid from jsonb_array_elements(coalesce(p_bolsas, '[]')) b) s
  loop
    -- Lo de antes: la bolsa más lo que no llevaba por lo decidido en la producción (R1e).
    select jsonb_agg(jsonb_build_array(x.producto, x.formato, x.cantidad) order by x.producto, x.formato)
      into v_antes
      from (select u.producto, u.formato, sum(u.cantidad)::int as cantidad
              from (select e.producto, e.formato, e.cantidad from public.tarea_elementos e
                     where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino
                    union all
                    select d ->> 'producto', d ->> 'formato', (d ->> 'cantidad')::int from jsonb_array_elements(v_previas) d
                     where (d ->> 'destino_id')::uuid = v_destino) u
             group by 1, 2) x;
    select jsonb_agg(jsonb_build_array(i ->> 'producto', coalesce(i ->> 'formato', ''), (i ->> 'cantidad')::int)
                     order by i ->> 'producto', coalesce(i ->> 'formato', ''))
      into v_despues
      from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
     where (b ->> 'destino_id')::uuid = v_destino;

    if v_antes is distinct from v_despues then
      delete from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
      select v_bolsas, 'caja_bolsa', p_tipo, i ->> 'producto', coalesce(i ->> 'formato', ''), v_destino,
             (i ->> 'cantidad')::int, coalesce((i ->> 'orden')::int, 0)
        from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
       where (b ->> 'destino_id')::uuid = v_destino;
    end if;
    if v_despues is not null then
      v_bolsas_resultado := v_bolsas_resultado || jsonb_build_object(
        'destino_id', v_destino,
        'destino', (select nombre from public.centros_trabajo where id = v_destino),
        'cajas', (select sum((x ->> 2)::int) from jsonb_array_elements(v_despues) x),
        'cambia', r0.id is not null and v_antes is distinct from v_despues);
    end if;
  end loop;

  -- Duraciones de referencia (§6.10): 1 min por caja que falta, 3 min por tienda.
  select coalesce(sum((x ->> 'faltan')::int), 0) * v_min_caja into v_dur_prod
    from jsonb_array_elements(coalesce(p_produccion, '[]')) x where (x ->> 'faltan')::int > 0;
  v_dur_bolsas := jsonb_array_length(v_bolsas_resultado) * v_min_bolsa;
  if v_prod = v_bolsas then
    update public.tareas set duracion_min = nullif(v_dur_prod + v_dur_bolsas, 0) where id = v_prod;
  else
    update public.tareas set duracion_min = nullif(v_dur_prod, 0) where id = v_prod;
    update public.tareas set duracion_min = nullif(v_dur_bolsas, 0) where id = v_bolsas;
  end if;

  -- R1e: lo decidido en la producción (bolsas con menos, avisos de llamada).
  if p_tipo = 'reparto' then
    perform motor.aplicar_sin_granel(p_persona, p_jornada, p_ahora);
  end if;

  perform motor.ajustar_estado_lista(p_persona, v_prod, 'No falta producir nada: todo está hecho en el almacén', p_ahora);
  if v_bolsas <> v_prod then
    perform motor.ajustar_estado_lista(p_persona, v_bolsas, 'Sin bolsas', p_ahora);
  end if;

  -- «Prepara el reparto» queda hecha al aceptarse el reparto, lo prepare quien lo prepare.
  if p_tipo = 'reparto' then
    for v_pegar in
      update public.tareas
         set estado = 'hecha', iniciada_en = coalesce(iniciada_en, p_ahora), terminada_en = p_ahora,
             resultado = case when v_es_suya then 'Reparto preparado'
                              else 'Reparto preparado por ' || coalesce((select nombre from public.personas where id = p_persona),
                                                                        'Administración') end
       where jornada_id = p_jornada and clave = 'pegar_reparto' and estado in ('pendiente', 'en_curso')
      returning id
    loop
      perform motor.registrar('tarea_terminada', p_persona, p_jornada, v_pegar,
                              jsonb_build_object('a_las', p_ahora, 'por', 'reparto aceptado'));
    end loop;
  end if;

  v_resultado := jsonb_build_object(
    'reparto_id', v_id, 'estado', 'aceptado', 'tipo', p_tipo, 'sale', p_sale, 'sustituye_a', r0.id,
    'produccion', coalesce(p_produccion, '[]'), 'bolsas', v_bolsas_resultado,
    'tareas', jsonb_build_object('produccion', v_prod, 'bolsas', v_bolsas),
    'datos_leidos_en', (select leido_en from public.lecturas_sheets where id = p_lectura),
    'texto_whatsapp', motor.texto_reparto(v_id));
  update public.repartos set resultado = v_resultado where id = v_id;
  perform motor.registrar(case when r0.id is null then 'reparto_aceptado' else 'reparto_sustituido' end,
                          p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo, 'anterior', r0.id));
  return v_resultado || jsonb_build_object('tarea_activa',
                                           case when v_es_suya then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

revoke execute on function
  motor.decisiones_sin_granel(uuid), motor.decisiones_json(jsonb), motor.texto_referencia(text, text),
  motor.paradas_reparto(uuid), motor.llamadas_sin_granel(uuid), motor.aplicar_sin_granel(uuid, uuid, timestamptz),
  motor.resolver_sin_granel_de(uuid, uuid, jsonb, timestamptz), motor.texto_reparto(uuid)
from public;
revoke execute on function motor.api_resolver_sin_granel(uuid, jsonb), public.resolver_sin_granel(uuid, jsonb) from public, anon;
grant execute on function motor.api_resolver_sin_granel(uuid, jsonb), public.resolver_sin_granel(uuid, jsonb) to authenticated;
