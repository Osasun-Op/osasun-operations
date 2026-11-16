-- T-0012 · Tarea 40 · Cierre de tiendas hasta una hora después, textos de las tareas y efectivo en la tarea del operario
-- (ESTADO_DEL_SISTEMA.md E2-8; decisiones del propietario, 16/11/2026). Solo en pruebas: espera con las de tiendas.
--   1. Las tareas de tienda se pueden marcar hasta una hora después de cerrar (entre semana, hasta las 21:30; el sábado,
--      una hora después de su cierre; también el «Cierre de caja» de las franquicias). Pasado ese margen, lo pendiente
--      queda como «no hecho», como antes al cerrar. Un solo sitio: motor.limite_tienda_en = motor.cierre_tienda_en + el
--      margen, que es un ajuste (configuración margen_cierre_tienda, 60 minutos). Lo usan:
--      - motor.tarea_tienda_json (no_hecha y se_puede_marcar);
--      - motor.tarea_tienda_marcable, la comprobación de todas las funciones que marcan (antes no miraba la hora de cierre:
--        lo bloqueaba solo la pantalla con no_hecha);
--      - motor.marcas_panel_json («N sin hacer»);
--      - motor.totales_cierres_de (los «faltan» de los cierres de caja).
--      «sin abrir» no cambia (va con la apertura).
--   2. Textos nuevos de las plantillas (almacén y tiendas), desde la jornada siguiente: lo ya creado (hoy incluido) y el
--      histórico no cambian. El punto del cierre de caja se reconoce por su texto (motor.punto_especial), que no cambia.
--   3. En la tarea del operario de comprobar el efectivo (efectivo_reporte), su «para qué» enseña, por cada tienda del
--      reparto de hoy y en el orden de la ruta, lo que ha apuntado al entregar la bolsa de ayer y, si no coincide con su
--      cierre de caja, el motivo. Se monta con los datos del momento (motor.efectivo_tiendas_texto, desde motor.tarea_json).
-- No cambia: cómo elige tareas el motor del almacén, las horas de las tareas, lo que hace cada tarea, las pantallas.
--
-- Deshacer: volver a crear motor.tarea_tienda_json y motor.totales_cierres_de como en 20261104210512,
-- motor.tarea_tienda_marcable como en 20261102190536, motor.marcas_panel_json como en 20261104215512 y motor.tarea_json
-- como en 20261104110512; borrar motor.limite_tienda_en, motor.efectivo_tiendas_texto y la configuración
-- margen_cierre_tienda; y volver a poner los textos de antes en plantillas_tarea (están en el punto 4 de esta migración,
-- en los comentarios «antes:»).

-- ---------------------------------------------------------------------------
-- 1. El margen del cierre: un ajuste y una sola ayuda
-- ---------------------------------------------------------------------------
insert into public.configuracion (clave, centro_id, valor) values ('margen_cierre_tienda', null, '60')
on conflict (clave, centro_id) do nothing;

-- Hasta cuándo se pueden marcar las tareas de la tienda ese día: la hora de cierre más el margen (en minutos, de la
-- configuración; sin el ajuste, 0: a la hora de cierre, como antes). null si ese día no abre.
create or replace function motor.limite_tienda_en(p_persona uuid, p_fecha date)
returns timestamptz language sql stable set search_path = '' as $$
  select motor.cierre_tienda_en(p_persona, p_fecha)
         + make_interval(mins => coalesce((select (k.valor #>> '{}')::int from public.configuracion k
                                            where k.clave = 'margen_cierre_tienda' and k.centro_id is null), 0))
$$;

-- ---------------------------------------------------------------------------
-- 2. El efectivo de cada tienda, para la tarea del operario
-- ---------------------------------------------------------------------------
-- «Efectivo apuntado por cada tienda:» y una línea por tienda con parada en el reparto de ese día, en el orden de la ruta:
-- «· Basauri: 120,00 € (cierre del 15/11)», «· Portugalete: 80,00 €; su cierre dice 95,00 €. Motivo: «…»»,
-- «· Bilbao: todavía no ha apuntado la bolsa de ayer» o «· Algorta: sin datos en la app (todavía no la usa)».
-- null si ese día no hay reparto con paradas.
create or replace function motor.efectivo_tiendas_texto(p_jornada uuid)
returns text language sql stable set search_path = '' as $$
  with r as (select r.id, j.fecha from public.jornadas j
               join public.repartos r on r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'
              where j.id = p_jornada limit 1),
  l as (
    select p.orden, '· ' || p.nombre || ': ' ||
           case
             when not exists (select 1 from public.personas pe where pe.centro_id = p.centro_id and pe.rol = 'tienda' and pe.activo)
               then 'sin datos en la app (todavía no la usa)'
             when b.efectivo_en is null then 'todavía no ha apuntado la bolsa de ayer'
             when b.efectivo_esperado is null then motor.euros(b.efectivo_entregado) || ' (sin cierre de caja en la app)'
             when b.efectivo_entregado = b.efectivo_esperado then
               motor.euros(b.efectivo_entregado) || ' ('
               || case when coalesce(array_length(b.efectivo_dias, 1), 0) <= 1
                       then 'cierre del ' || to_char(coalesce(b.efectivo_dias[1], b.efectivo_de), 'DD/MM')
                       else 'cierres del '
                            || (select string_agg(to_char(d, 'DD/MM'), ', ' order by n)
                                  from unnest(b.efectivo_dias[1:array_length(b.efectivo_dias, 1) - 1]) with ordinality a(d, n))
                            || ' y ' || to_char(b.efectivo_dias[array_length(b.efectivo_dias, 1)], 'DD/MM') end || ')'
             else motor.euros(b.efectivo_entregado) || '; su cierre dice ' || motor.euros(b.efectivo_esperado)
                  || coalesce('. Motivo: «' || b.efectivo_motivo || '»', '')
           end as texto
      from r
      cross join lateral motor.paradas_bolsas(r.id) p
      left join public.bolsas_tienda b on b.centro_id = p.centro_id and b.fecha = r.fecha and b.reparto_id = r.id)
  select 'Efectivo apuntado por cada tienda:' || E'\n' || string_agg(l.texto, E'\n' order by l.orden)
    from l having count(*) > 0
$$;

-- ---------------------------------------------------------------------------
-- 3. Funciones que se rehacen
-- ---------------------------------------------------------------------------
create or replace function motor.tarea_tienda_json(p_tarea uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque, 'tipo', t.contenido,
    'hora', motor.hora_texto(t.disponible_desde), 'desde', t.disponible_desde,
    'estado', t.estado,
    -- Tarea 40: se puede marcar hasta una hora después de cerrar (limite_tienda_en); pasado eso, no.
    'se_puede_marcar', t.estado = 'pendiente' and t.disponible_desde <= p_ahora
                       and p_ahora < coalesce(motor.limite_tienda_en(j.persona_id, j.fecha), 'infinity'::timestamptz),
    -- Pasado el margen del cierre, lo que no se ha hecho queda como no hecho (no pasa al día siguiente).
    -- Tarea 33: con la ayuda que usan también las marcas del panel y los cierres de caja (Tarea 40: con el margen).
    'no_hecha', t.estado = 'pendiente' and p_ahora >= motor.limite_tienda_en(j.persona_id, j.fecha),
    'motivo', t.motivo_no_hecha,
    'terminada_en', t.terminada_en, 'hora_fin', motor.hora_texto(t.terminada_en),
    'hecha_por', case when t.estado in ('hecha', 'cancelada') then (
      select r.datos ->> 'hecha_por' from public.registro_eventos r
       where r.tarea_id = t.id and r.tipo in ('tarea_terminada', 'video_no_pudo') order by r.id desc limit 1) end,
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'texto', e.producto, 'hecho', e.estado = 'hecho',
                                          'hecho_por', e.calculo ->> 'hecho_por', 'a_las', motor.hora_texto(e.terminado_en),
                                          -- Tarea 28: los puntos que piden algo más que un toque.
                                          'pide', case motor.punto_especial(e) when 'efectivo' then 'efectivo'
                                                                               when 'cierre_caja' then 'cierre_caja'
                                                                               -- Tarea 30b: Z y nº de ventas.
                                                                               when 'cierre_caja_corto' then 'cierre_caja_corto' end,
                                          'efectivo_esperado', case when motor.punto_especial(e) = 'efectivo'
                                                                    then (e.calculo ->> 'esperado')::numeric end,
                                          'datos', e.calculo -> 'datos')
                       order by e.orden_sugerido, e.producto)
        from public.tarea_elementos e where e.tarea_id = t.id and e.tipo = 'punto'), '[]'::jsonb),
    'video', (select jsonb_build_object('enlace', v.enlace, 'aprendido', v.aprendido, 'no_pudo', v.no_pudo)
                from public.videos_tienda v where v.tarea_id = t.id),
    -- Tarea 28: lo que trae la bolsa («Recibe la bolsa» y «Coloca y apunta la reposición»).
    'bolsa', case when t.clave in ('recibe_bolsa', 'reposicion') then motor.bolsa_tienda_json(j.centro_id, j.fecha) end,
    -- Tarea 28: lo que se ha pedido en «Revisa las muestras».
    'muestras', case when t.contenido = 'muestras' then coalesce((
      select jsonb_agg(jsonb_build_object('producto', p.producto, 'formato', p.formato, 'cantidad', p.cantidad,
                                          'estado', p.estado) order by p.creada_en, p.id)
        from public.peticiones_tienda p where p.tarea_id = t.id), '[]'::jsonb) end,
    -- Tarea 31: lo que se ha apuntado en «Revisa los productos atascados», con su estado.
    'atascados', case when t.contenido = 'atascados' then coalesce((
      select jsonb_agg(motor.atascado_json(a.id, 'tiene', p_ahora) order by a.creada_en, a.producto)
        from public.atascados a where a.tarea_id = t.id), '[]'::jsonb) end)
  from public.tareas t join public.jornadas j on j.id = t.jornada_id
  where t.id = p_tarea;
$$;

create or replace function motor.tarea_tienda_marcable(p_persona uuid, p_tarea uuid, p_contenido text, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  t public.tareas;
  v_ok boolean;
begin
  select tr.* into t from public.tareas tr join public.jornadas j on j.id = tr.jornada_id
   where tr.id = p_tarea and j.persona_id = p_persona;
  if t.id is null or (p_contenido is not null and t.contenido <> p_contenido) then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado not in ('pendiente', 'en_curso') then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea ya está cerrada.', jsonb_build_object('estado', t.estado));
  end if;
  -- Tarea 40: hasta una hora después de cerrar la tienda; pasado eso, queda como no hecha.
  if p_ahora >= (select motor.limite_tienda_en(j.persona_id, j.fecha) from public.jornadas j where j.id = t.jornada_id) then
    return motor.error('ESTADO_NO_VALIDO', 'Ya ha pasado la hora: esta tarea queda como no hecha.',
                       jsonb_build_object('estado', 'no_hecha'));
  end if;
  if t.disponible_desde > p_ahora then
    return motor.error('TODAVIA_NO', 'Esta tarea es desde las ' || motor.hora_texto(t.disponible_desde) || '.');
  end if;
  v_ok := (motor.en_turno_tienda(t.jornada_id)).id is not null;
  if not v_ok then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  return null;
end;
$$;

create or replace function motor.marcas_panel_json(p_admin uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with hoy as (select motor.fecha_local(p_ahora) as f),
  cen as (select (x ->> 'id')::uuid as id, x ->> 'tipo' as tipo from jsonb_array_elements(motor.centros_panel_json()) x),
  -- Las incidencias abiertas de cada tienda, las mismas de incidencias_tiendas() (con los atascados por decidir).
  inc as (select (x ->> 'tienda_id')::uuid as centro, count(*)::int as n
            from jsonb_array_elements(motor.incidencias_tiendas_de(p_ahora) -> 'incidencias') x
           where x ->> 'estado' <> 'cerrada' group by 1),
  m as (
    select c.id, c.tipo,
           case when c.tipo = 'almacen' then jsonb_array_length(motor.estado_actual_de(p_ahora) -> 'problemas_abiertos')
                else coalesce(inc.n, 0) end as rojo,
           case when c.tipo = 'almacen' or pe.id is null then 0 else (
             select count(*)::int
               from public.jornadas j join public.tareas t on t.jornada_id = j.id
              where j.persona_id = pe.id and j.fecha between (select f from hoy) - 7 and (select f from hoy)
                and t.estado = 'pendiente' and not t.retirada_por_condicion
                -- Tarea 40: «sin hacer» desde que pasa el margen del cierre (lo mismo que «no hecha» en la tienda).
                and motor.limite_tienda_en(j.persona_id, j.fecha) <= p_ahora
                and motor.limite_tienda_en(j.persona_id, j.fecha) > coalesce(v.visto_en, '-infinity'::timestamptz)) end
             as sin_hacer,
           c.tipo = 'tienda' and pe.id is not null and not motor.dia_cerrado(c.id, (select f from hoy))
             and exists (select 1 from public.horarios h
                          where h.persona_id = pe.id and h.dia_semana = extract(isodow from (select f from hoy))
                            and p_ahora >= motor.en_local((select f from hoy), h.hora_inicio) + interval '30 minutes'
                            -- Solo mientras dura ese turno (decisión del propietario, PR #37).
                            and p_ahora < motor.en_local((select f from hoy), h.hora_fin)
                            and not exists (select 1 from public.turnos_tienda x join public.jornadas j on j.id = x.jornada_id
                                             where j.persona_id = pe.id and j.fecha = (select f from hoy) and x.turno = h.turno))
             as sin_abrir
      from cen c
      left join inc on inc.centro = c.id
      left join lateral (select p.id from public.personas p
                          where p.centro_id = c.id and p.rol = 'tienda' and p.activo order by p.id limit 1) pe on c.tipo = 'tienda'
      left join public.vistas_panel v on v.persona_id = p_admin and v.centro_id = c.id)
  select coalesce(jsonb_object_agg(m.id, jsonb_build_object(
           'rojo', m.rojo, 'sin_hacer', m.sin_hacer, 'sin_abrir', coalesce(m.sin_abrir, false),
           -- Lo que se pinta junto al nombre: «●2 · 3 sin hacer · sin abrir» (null si no hay nada).
           'texto', nullif(concat_ws(' · ', case when m.rojo > 0 then '●' || m.rojo end,
                                           case when m.sin_hacer > 0 then m.sin_hacer || ' sin hacer' end,
                                           case when m.sin_abrir then 'sin abrir' end), ''))), '{}'::jsonb)
    from m
$$;

create or replace function motor.totales_cierres_de(p_desde date, p_hasta date, p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with t as (
    select c.id, c.nombre, motor.cierre_corto(c.id) as corto,
           (select p.id from public.personas p where p.centro_id = c.id and p.rol = 'tienda' and p.activo order by p.id limit 1) as pe
      from public.centros_trabajo c
     where c.tipo = 'tienda' and c.activo and (p_centro is null or c.id = p_centro)),
  d as (select g::date as f from generate_series(p_desde, p_hasta, interval '1 day') g),
  -- Las tiendas que abrían cada día y si ya tenían que haber cerrado (Tarea 40: con el margen del cierre).
  abre as (
    select d.f, t.id, t.nombre, t.corto, motor.limite_tienda_en(t.pe, d.f) as cierra_en
      from d cross join t
     where t.pe is not null and motor.cierre_tienda_en(t.pe, d.f) is not null and not motor.dia_cerrado(t.id, d.f)),
  k as (select k.*, t.corto from public.cierres_caja k join t on t.id = k.centro_id where k.fecha between p_desde and p_hasta)
  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha', d.f,
           'propias', jsonb_build_object(
             'z', coalesce((select sum(k.z) from k where k.fecha = d.f and not k.corto), 0),
             'ventas', coalesce((select sum(k.ventas) from k where k.fecha = d.f and not k.corto), 0),
             'efectivo', coalesce((select sum(k.efectivo) from k where k.fecha = d.f and not k.corto), 0),
             'glovo', coalesce((select sum(k.glovo) from k where k.fecha = d.f and not k.corto), 0),
             'cierres', (select count(*) from k where k.fecha = d.f and not k.corto),
             'faltan', coalesce((select jsonb_agg(jsonb_build_object('tienda_id', a.id, 'tienda', a.nombre) order by a.nombre)
                                   from abre a where a.f = d.f and not a.corto and a.cierra_en <= p_ahora
                                    and not exists (select 1 from k where k.centro_id = a.id and k.fecha = d.f)), '[]'::jsonb)),
           'franquicias', jsonb_build_object(
             'z', coalesce((select sum(k.z) from k where k.fecha = d.f and k.corto), 0),
             'ventas', coalesce((select sum(k.ventas) from k where k.fecha = d.f and k.corto), 0),
             'cierres', (select count(*) from k where k.fecha = d.f and k.corto),
             'faltan', coalesce((select jsonb_agg(jsonb_build_object('tienda_id', a.id, 'tienda', a.nombre) order by a.nombre)
                                   from abre a where a.f = d.f and a.corto and a.cierra_en <= p_ahora
                                    and not exists (select 1 from k where k.centro_id = a.id and k.fecha = d.f)), '[]'::jsonb)))
           order by d.f desc), '[]'::jsonb)
    from d
   where exists (select 1 from abre a where a.f = d.f) or exists (select 1 from k where k.fecha = d.f)
$$;

create or replace function motor.tarea_json(p_tarea uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo,
    -- Tarea 40: en la del efectivo, lo que ha apuntado cada tienda (con los datos del momento, como aviso_salida).
    'porque', case when t.clave = 'efectivo_reporte' then coalesce(motor.efectivo_tiendas_texto(t.jornada_id), t.porque)
                   else t.porque end,
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

-- ---------------------------------------------------------------------------
-- 4. Textos nuevos de las plantillas (desde la jornada siguiente; lo ya creado no cambia)
-- ---------------------------------------------------------------------------
-- Almacén, por código (el título). Antes:
--   revision_inicial: «Revisión inicial: estado de las tiendas, formulario de incidencias y stock empaquetado»
--   efectivo_reporte: «Efectivo frente a la Z y reporte a Administración»
--   revisar_envio: «Revisa si toca envío a Gipuzkoa/Durango y propónselo a Administración»
--   recuento_manana: «Recuento de stock y cajas hechas, y actualización de STOCK ALMACEN DIARIO»
--   recuento_tarde_envio: «Recuento de stock y cajas hechas»
--   recuento_tarde: «Recuento de stock y cierre»
--   nacex_salida: «Salida a Nacex con el envío o el pedido de cliente (vuelta hacia las 18:25 para cerrar)»
--   minis: «Minis (unos 35, para llevar el miércoles)»
--   control_materiales: «Control semanal de materiales y aviso de cobertura a 2 semanas»
--   cola_stock: «Producción para el stock del almacén (+35 %)»
--   cola_compras: «Compras y aprovisionamientos pendientes»
update public.plantillas_tarea p set titulo = x.titulo
  from (values
    ('revision_inicial', 'Revisión inicial: estado de las tiendas, revisar incidencias y stock empaquetado'),
    ('efectivo_reporte', 'Comprobar el efectivo de cada tienda, si no cuadra preguntar a la tienda por qué. Comunicar resultado final a Administración'),
    ('revisar_envio', 'Revisa stock en Gipuzkoa/Durango y ver si hay que enviar o no'),
    ('recuento_manana', 'Recuento de stock, cajas y actualizar STOCK ALMACEN DIARIO'),
    ('recuento_tarde_envio', 'Recuento de stock, cajas y actualizar STOCK ALMACEN DIARIO'),
    ('recuento_tarde', 'Recuento de stock, cajas y actualizar STOCK ALMACEN DIARIO'),
    ('nacex_salida', 'Salida a Nacex con el envío o el pedido de cliente'),
    ('minis', 'Minis (calcular según consumo semanal y stock de cajas en tiendas)'),
    ('control_materiales', 'Control semanal de materias primas y aviso de cobertura a 2 semanas'),
    ('cola_stock', 'Producción para el stock del almacén'),
    ('cola_compras', 'Revisar necesidades de material de almacén y oficina')) x(codigo, titulo)
 where p.codigo = x.codigo and p.centro_id = (select c.id from public.centros_trabajo c where c.codigo = 'ALMACEN');

-- Tiendas (todas las que tienen cada plantilla). Antes:
--   apertura_manana, porque: «Para abrir la tienda a su hora y lista.»
--   apertura_tarde, porque: «Para abrir la tienda a su hora.»; puntos: Fichar | Abrir | Cartelería | Glovo
--   cierre_manana, puntos: Ventas y stock de la plantilla al día (todo en verde) | Incidencias del turno registradas
--   cierre_dia, puntos: Ventas del día en la plantilla (todo en verde) | Suelo fregado | Cierre de caja en la app: Z, nº de
--     ventas, efectivo y Glovo | Efectivo contado y en la bolsa para mañana | Incidencias de la tarde registradas
update public.plantillas_tarea p set porque = ''
  from public.centros_trabajo c
 where c.id = p.centro_id and c.tipo = 'tienda' and p.codigo in ('apertura_manana', 'apertura_tarde');
update public.plantillas_tarea p set puntos = x.puntos
  from public.centros_trabajo c,
       (values
         ('cierre_manana', array['Ventas y stock de la plantilla al día (todo en verde)', 'Cerrar turno en Woffu',
                                 'Incidencias del turno registradas']),
         ('apertura_tarde', array['Fichar en Woffu', 'Abrir', 'Cartelería', 'Glovo']),
         ('cierre_dia', array['Ventas del día en la plantilla (todo en verde)', 'Suelo fregado',
                              'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo', 'Cerrar turno en Woffu',
                              'Efectivo contado y en la bolsa para mañana', 'Incidencias de la tarde registradas'])) x(codigo, puntos)
 where c.id = p.centro_id and c.tipo = 'tienda' and p.codigo = x.codigo;

revoke execute on all functions in schema motor from public;
