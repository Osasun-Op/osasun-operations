-- T-0017 · Tarea 45 · Sin granel: de otra tienda, solo de las que tienen reparto ese día (ESTADO_DEL_SISTEMA.md R1e,
-- REGLAS_CALCULO.md §2.11; decisión del propietario, 24/11/2026). Solo en pruebas: producción espera.
-- El 24/11, el ANKA para Bilbao no tenía granel y «Cogerlo de otra tienda» ofreció también Basauri, que ese día no tenía
-- reparto: se eligió y hubo un viaje que no hacía falta. tiendas_con_stock (sin_granel.ts) eran «las demás tiendas del
-- reparto» de la configuración de la ruta, tuvieran bolsa ese día o no, y resolver_sin_granel aceptaba cualquiera de ellas.
--   1. tiendas_con_stock: solo las tiendas con bolsa en el reparto de ese día (lo calcula el servidor, sin_granel.ts).
--   2. resolver_sin_granel rechaza como origen una tienda sin bolsa ese día (DATOS_NO_VALIDOS, con una frase para enseñar).
--   3. Al modificar el reparto (o al resolver otra referencia), una decisión «otra_tienda» cuya tienda de origen se ha
--      quedado sin bolsa se va (motor.aplicar_sin_granel): la referencia vuelve a salir sin resolver y su parada y su línea
--      «Avisa a…» se quitan, como cuando lo decidido deja de cubrir lo que falta. El aviso a la tienda de origen ya creado
--      se queda (T-0010). Las decisiones con un origen que sigue en el reparto, se quedan.
-- «Tener bolsa» es ser parada del reparto (motor.paradas_bolsas: productos, peticiones especiales o pedidos de cliente).
-- motor.tiendas_con_bolsa añade lo que, mientras se guarda una versión nueva del reparto, todavía no está en ella: sus
-- peticiones (ya están en sus líneas «Además:») y sus pedidos de cliente (aún con la versión anterior).
--
-- Deshacer: volver a crear motor.aplicar_sin_granel y motor.resolver_sin_granel_de como están en 20261029140000 y
-- borrar motor.tiendas_con_bolsa.

-- Las tiendas con bolsa en el reparto de una jornada (las paradas de la ruta).
create or replace function motor.tiendas_con_bolsa(p_jornada uuid)
returns table (centro_id uuid)
language sql stable set search_path = '' as $$
  with r as (select id from public.repartos where jornada_id = p_jornada and tipo = 'reparto' and estado = 'aceptado')
  select p.centro_id from r cross join lateral motor.paradas_bolsas(r.id) p
  union
  select l.destino_id from r join public.reparto_lineas l on l.reparto_id = r.id
   where l.clase = 'peticion' and l.destino_id is not null
  union
  select c.destino_id from public.pedidos_cliente c join public.repartos k on k.id = c.reparto_id
   where k.jornada_id = p_jornada and k.tipo = 'reparto' and c.entrega = 'tienda'
$$;

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
  v_con_bolsa uuid[];
begin
  select * into r from public.repartos where jornada_id = p_jornada and tipo = 'reparto' and estado = 'aceptado';
  if r.id is null then return; end if;
  select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
  select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';
  -- Tarea 45: las tiendas con bolsa en el reparto de ese día (las que pueden dar cajas a otra).
  v_con_bolsa := array(select x.centro_id from motor.tiendas_con_bolsa(p_jornada) x);

  -- 1. Decisiones: solo de tiendas que siguen recibiendo, como mucho lo que piden,
  --    y entre todas como mucho lo que falta. Resuelta si cubren todo lo que falta.
  --    Tarea 45: «otra_tienda» solo si la tienda de origen sigue con bolsa en el reparto.
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
      if d ->> 'accion' = 'otra_tienda' and not ((d ->> 'origen_id')::uuid = any (v_con_bolsa)) then
        continue;
      end if;
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


create or replace function motor.resolver_sin_granel_de(p_persona uuid, p_elemento uuid, p_decisiones jsonb, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  t public.tareas;
  v_error jsonb;
  v_falta integer;
  v_dec jsonb;
  v_con_bolsa uuid[];
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
  -- Tarea 45: de otra tienda, solo de las que tienen bolsa en el reparto de hoy (no todas las de la ruta).
  v_con_bolsa := array(select b.centro_id from motor.tiendas_con_bolsa(t.jornada_id) b);
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
        or not exists (select 1 from public.centros_trabajo c where c.id::text = x ->> 'origen_id')) then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de qué otra tienda del reparto se coge.');
    end if;
    if x ->> 'accion' = 'otra_tienda' and not exists (select 1 from unnest(v_con_bolsa) u where u::text = x ->> 'origen_id') then
      return motor.error('DATOS_NO_VALIDOS',
                         (select c.nombre from public.centros_trabajo c where c.id::text = x ->> 'origen_id')
                           || ' no tiene reparto hoy: elige una tienda que esté en el reparto de hoy.',
                         jsonb_build_object('origen_id', x ->> 'origen_id'));
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


revoke execute on all functions in schema motor from public;
