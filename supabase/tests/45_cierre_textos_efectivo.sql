-- Prueba 45 · Cierre de tiendas hasta una hora después, textos de las tareas y efectivo en la tarea del operario
-- (T-0012 · Tarea 40; ESTADO_DEL_SISTEMA.md E2-8, decisiones del 16/11/2026). Lunes 14/12/2026 (Basauri, Bilbao y
-- Rentería cierran a las 20:30; el margen, 60 minutos) y sábado 19/12 (Basauri cierra a las 19:30). El reparto del lunes
-- va a Bilbao, Algorta, Barakaldo, Basauri y Portugalete. Cuentas y nombres inventados (@osasun.invalid).
-- Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y nombres reales de las tiendas y de las jornadas reales del operario. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.a(p_fecha date, p_hora text) returns timestamptz language sql as $$ select motor.en_local(p_fecha, p_hora::time) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.tarea(r jsonb, p_clave text) returns jsonb language sql as $$
  select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' like p_clave limit 1 $$;
create function pg_temp.punto(t jsonb, p_texto text) returns uuid language sql as $$
  select (x ->> 'id')::uuid from jsonb_array_elements(t -> 'puntos') x where x ->> 'texto' = p_texto $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;
create function pg_temp.m(p_codigo text, p_ahora timestamptz) returns jsonb language sql as $$
  select motor.marcas_panel_json('00000000-0000-4000-a000-000000000002', p_ahora) -> (pg_temp.d(p_codigo)::text) $$;
create function pg_temp.t(p_fecha date, p_ahora timestamptz) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.totales_cierres_de(p_fecha, p_fecha, null, p_ahora)) x $$;
create function pg_temp.nombres(p jsonb) returns jsonb language sql as $$
  select coalesce(jsonb_agg(x ->> 'tienda' order by x ->> 'tienda'), '[]') from jsonb_array_elements(p) x $$;

-- Cuentas de tienda (inventadas) y sus personas. Algorta no tiene cuenta: no usa la app.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.bilbao@osasun.invalid", "nombre": "Bilbao", "rol": "tienda", "centro": "BILBAO"},
  {"correo": "tienda.barakaldo@osasun.invalid", "nombre": "Barakaldo", "rol": "tienda", "centro": "BARAKALDO"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"},
  {"correo": "tienda.renteria@osasun.invalid", "nombre": "Rentería", "rol": "tienda", "centro": "RENTERIA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.bilbao@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000003', 'tienda.barakaldo@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000004', 'tienda.portu@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000006', 'tienda.renteria@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('BILBAO'), 'Leire Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000007', pg_temp.d('RENTERIA'), 'Maite Prueba', 'siempre', null);

-- ---------------------------------------------------------------------------
-- 1. Los textos nuevos de las plantillas, en las jornadas que se crean a partir de ahora
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada(basauri, '2026-12-14');
  jo uuid := motor.generar_jornada(op, '2026-12-14');
begin
  perform pg_temp.comprobar('Tienda: «Apertura de la mañana» y «Apertura de la tarde» sin «para qué»',
    (select string_agg(clave || '=' || coalesce(porque, 'null'), ' ' order by clave) from public.tareas
      where jornada_id = j and clave in ('apertura_manana', 'apertura_tarde')) = 'apertura_manana= apertura_tarde=');
  perform pg_temp.comprobar('Tienda: los puntos nuevos de «Cierre de la mañana», «Apertura de la tarde» y «Cierre del día»',
    (select string_agg(t.clave || ': ' || (select string_agg(e.producto, ' | ' order by e.orden_sugerido)
                                             from public.tarea_elementos e where e.tarea_id = t.id and e.tipo = 'punto'), E'\n'
                       order by t.disponible_desde)
       from public.tareas t where t.jornada_id = j and t.clave in ('cierre_manana', 'apertura_tarde', 'cierre_dia'))
      = 'cierre_manana: Ventas y stock de la plantilla al día (todo en verde) | Cerrar turno en Woffu | Incidencias del turno registradas' || E'\n'
        || 'apertura_tarde: Fichar en Woffu | Abrir | Cartelería | Glovo' || E'\n'
        || 'cierre_dia: Ventas del día en la plantilla (todo en verde) | Suelo fregado | Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo | Cerrar turno en Woffu | Efectivo contado y en la bolsa para mañana | Incidencias de la tarde registradas');
  perform pg_temp.comprobar('Tienda: «Apertura de la mañana», los puntos de siempre',
    (select string_agg(e.producto, ' | ' order by e.orden_sugerido) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
      where t.jornada_id = j and t.clave = 'apertura_manana') = 'Fichar en Woffu | Abrir | Cartelería | Glovo | Barrido y puesta a punto');
  perform pg_temp.comprobar('Almacén: los títulos nuevos',
    (select titulo from public.tareas where jornada_id = jo and clave = 'revision_inicial')
      = 'Revisión inicial: estado de las tiendas, revisar incidencias y stock empaquetado'
    and (select titulo from public.plantillas_tarea where codigo = 'efectivo_reporte' and centro_id = pg_temp.d('ALMACEN'))
      = 'Comprobar el efectivo de cada tienda, si no cuadra preguntar a la tienda por qué. Comunicar resultado final a Administración'
    and (select count(distinct titulo) from public.plantillas_tarea
          where codigo in ('recuento_manana', 'recuento_tarde_envio', 'recuento_tarde') and centro_id = pg_temp.d('ALMACEN')) = 1
    and (select titulo from public.plantillas_tarea where codigo = 'recuento_tarde' and centro_id = pg_temp.d('ALMACEN'))
      = 'Recuento de stock, cajas y actualizar STOCK ALMACEN DIARIO'
    and (select titulo from public.plantillas_tarea where codigo = 'cola_compras' and centro_id = pg_temp.d('ALMACEN'))
      = 'Revisar necesidades de material de almacén y oficina');
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. El lunes: hasta una hora después del cierre (20:30 + 60 min)
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  renteria constant uuid := '00000000-0000-4000-b000-000000000006';
  r jsonb;
  t jsonb;
  v_n int;
begin
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-14', '17:00'));
  perform motor.empezar_turno_tienda_de(bilbao, '00000000-0000-4000-c000-000000000002', pg_temp.a('2026-12-14', '17:00'));
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000007', pg_temp.a('2026-12-14', '17:00'));

  t := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '20:35')), 'cierre_dia');
  perform pg_temp.comprobar('20:35, pasada la hora de cierre: el «Cierre del día» se puede marcar (no está «no hecha»)',
    (t ->> 'se_puede_marcar')::boolean and not (t ->> 'no_hecha')::boolean, t::text);
  r := motor.marcar_punto_de(basauri, pg_temp.punto(t, 'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo'), pg_temp.a('2026-12-14', '20:35'));
  perform pg_temp.comprobar('El cierre de caja sigue pidiendo sus datos (en su sitio nuevo, el 3.º de 6)',
    pg_temp.err(r) = 'FALTAN_DATOS' and r -> 'error' ->> 'pide' = 'cierre_caja'
    and t -> 'puntos' -> 2 ->> 'pide' = 'cierre_caja' and jsonb_array_length(t -> 'puntos') = 6, r::text);
  r := motor.cerrar_caja_de(basauri, pg_temp.punto(t, 'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo'),
                            412.30, 37, 120, 23, pg_temp.a('2026-12-14', '20:36'));
  perform pg_temp.comprobar('… y a las 20:36 se hace el cierre de caja',
    r ->> 'error' is null and exists (select 1 from public.cierres_caja where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-14'), r::text);
  r := motor.marcar_punto_de(basauri, pg_temp.punto(t, 'Cerrar turno en Woffu'), pg_temp.a('2026-12-14', '21:29'));
  perform pg_temp.comprobar('21:29: todavía se marca un punto («Cerrar turno en Woffu»)', r ->> 'error' is null, r::text);

  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '21:31'));
  t := pg_temp.tarea(r, 'cierre_dia');
  perform pg_temp.comprobar('21:31: lo pendiente queda como no hecho y ya no se puede marcar',
    (t ->> 'no_hecha')::boolean and not (t ->> 'se_puede_marcar')::boolean
    and (pg_temp.tarea(r, 'cierre_manana') ->> 'no_hecha')::boolean, t::text);
  r := motor.marcar_punto_de(basauri, pg_temp.punto(t, 'Suelo fregado'), pg_temp.a('2026-12-14', '21:31'));
  perform pg_temp.comprobar('… y si se intenta: ESTADO_NO_VALIDO, con una frase para enseñar',
    pg_temp.err(r) = 'ESTADO_NO_VALIDO' and r -> 'error' ->> 'mensaje' = 'Ya ha pasado la hora: esta tarea queda como no hecha.', r::text);

  -- La franquicia: su «Cierre de caja» (Z y nº de ventas), con el mismo margen.
  t := pg_temp.tarea(motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-14', '21:15')), 'cierre_caja');
  r := motor.cerrar_caja_de(renteria, pg_temp.punto(t, 'Cierre de caja en la app: Z y nº de ventas'), 640.10, 29, null, null,
                            pg_temp.a('2026-12-14', '21:15'));
  perform pg_temp.comprobar('Rentería (franquicia): a las 21:15 hace su «Cierre de caja»',
    (t ->> 'se_puede_marcar')::boolean and r ->> 'error' is null
    and exists (select 1 from public.cierres_caja where centro_id = pg_temp.d('RENTERIA') and fecha = '2026-12-14'), r::text);

  -- Las marcas del panel y los «faltan» de los cierres de caja, con la misma hora.
  select count(*) into v_n from public.tareas t join public.jornadas j on j.id = t.jornada_id
   where j.persona_id = basauri and j.fecha = '2026-12-14' and t.estado = 'pendiente' and not t.retirada_por_condicion;
  perform pg_temp.comprobar('Panel: «sin hacer» de Basauri, 0 a las 21:29 y lo pendiente a las 21:31',
    (pg_temp.m('BASAURI', pg_temp.a('2026-12-14', '21:29')) ->> 'sin_hacer')::int = 0
    and (pg_temp.m('BASAURI', pg_temp.a('2026-12-14', '21:31')) ->> 'sin_hacer')::int = v_n and v_n > 0,
    pg_temp.m('BASAURI', pg_temp.a('2026-12-14', '21:31'))::text);
  perform pg_temp.comprobar('Cierres de caja: a las 21:29 no «falta» nadie; a las 21:31, las que no lo han hecho (Basauri y Rentería, sí)',
    pg_temp.nombres(pg_temp.t('2026-12-14', pg_temp.a('2026-12-14', '21:29')) -> 'propias' -> 'faltan') = '[]'
    and pg_temp.nombres(pg_temp.t('2026-12-14', pg_temp.a('2026-12-14', '21:31')) -> 'propias' -> 'faltan') = '["Barakaldo", "Bilbao", "Portugalete"]'
    and pg_temp.nombres(pg_temp.t('2026-12-14', pg_temp.a('2026-12-14', '21:31')) -> 'franquicias' -> 'faltan') = '[]',
    pg_temp.t('2026-12-14', pg_temp.a('2026-12-14', '21:31'))::text);
  perform pg_temp.comprobar('El margen es un ajuste (configuración margen_cierre_tienda: 60)',
    (select valor #>> '{}' from public.configuracion where clave = 'margen_cierre_tienda' and centro_id is null) = '60'
    and motor.limite_tienda_en(basauri, '2026-12-14') = pg_temp.a('2026-12-14', '21:30'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. El sábado: una hora después de su cierre (19:30 + 60 min); y la franquicia, otro día, sin hacer
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  renteria constant uuid := '00000000-0000-4000-b000-000000000006';
  t jsonb;
begin
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-19', '17:00'));
  t := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-19', '20:29')), 'cierre_dia');
  perform pg_temp.comprobar('Sábado, 20:29: el «Cierre del día» (cierra a las 19:30) todavía se puede marcar',
    (t ->> 'se_puede_marcar')::boolean and not (t ->> 'no_hecha')::boolean, t::text);
  t := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-19', '20:31')), 'cierre_dia');
  perform pg_temp.comprobar('Sábado, 20:31: no hecho',
    (t ->> 'no_hecha')::boolean and not (t ->> 'se_puede_marcar')::boolean, t::text);
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000007', pg_temp.a('2026-12-16', '17:00'));
  t := pg_temp.tarea(motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-16', '21:31')), 'cierre_caja');
  perform pg_temp.comprobar('Rentería, el miércoles sin hacer: a las 21:31 su «Cierre de caja» queda no hecho y «falta»',
    (t ->> 'no_hecha')::boolean
    and pg_temp.nombres(pg_temp.t('2026-12-16', pg_temp.a('2026-12-16', '21:31')) -> 'franquicias' -> 'faltan') = '["Rentería"]', t::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. El efectivo en la tarea del operario (el lunes, con el reparto a cinco tiendas)
-- ---------------------------------------------------------------------------
create function pg_temp.guardar(p_jornada uuid) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, 'reparto',
    E'REPARTO 14/12\nSALE: ALMACÉN\n\nBILBAO\n1x V2 4g\n\nALGORTA\n1x V2 4g\n\nBARAKALDO\n1x V2 4g\n\nBASAURI\n1x V2 4g\n\nPORTU\n1x V2 4g',
    'h45', '2026-12-14', 'operario', null,
    (select jsonb_agg(x order by n) from (
       select 0 as n, jsonb_build_object('num', 1, 'texto', 'REPARTO 14/12', 'clase', 'cabecera') as x
       union all select 1, jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario')
       union all
       select 10 * k, jsonb_build_object('num', 10 * k, 'texto', c, 'clase', 'tienda', 'destino_id', pg_temp.d(c))
         from unnest(array['BILBAO', 'ALGORTA', 'BARAKALDO', 'BASAURI', 'PORTU']) with ordinality a(c, k)
       union all
       select 10 * k + 1, jsonb_build_object('num', 10 * k + 1, 'texto', '1x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d(c),
                                             'cantidad', 1, 'producto', 'V2', 'formato', '4g')
         from unnest(array['BILBAO', 'ALGORTA', 'BARAKALDO', 'BASAURI', 'PORTU']) with ordinality a(c, k)) s),
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 5, 'en_almacen', 20, 'faltan', 0,
                                         'aviso', null, 'orden', 1)),
    (select jsonb_agg(jsonb_build_object('destino_id', pg_temp.d(c), 'items', jsonb_build_array(
                        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 1, 'orden', 1))) order by k)
       from unnest(array['BILBAO', 'ALGORTA', 'BARAKALDO', 'BASAURI', 'PORTU']) with ordinality a(c, k)),
    true, pg_temp.a('2026-12-14', '08:40')) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-14');
  r jsonb;
  v_rep uuid;
  v_t uuid;
  v_ef uuid;
begin
  perform pg_temp.comprobar('Sin reparto todavía, la tarea del efectivo deja su «para qué» como está',
    motor.efectivo_tiendas_texto(j) is null);
  r := pg_temp.guardar(j);
  v_rep := (r ->> 'reparto_id')::uuid;
  v_t := (r -> 'tareas' ->> 'bolsas')::uuid;
  select id into v_ef from public.tareas where jornada_id = j and clave = 'efectivo_reporte';
  -- Lo que han apuntado las tiendas al recibir la bolsa (bolsas_tienda), como lo deja «Recibe la bolsa».
  insert into public.bolsas_tienda (centro_id, fecha, reparto_id, tarea_id, salida_en, efectivo_esperado, efectivo_de, efectivo_dias,
                                    efectivo_entregado, efectivo_motivo, efectivo_en)
  values
    -- Bilbao: la bolsa en camino, sin apuntar todavía.
    (pg_temp.d('BILBAO'), '2026-12-14', v_rep, v_t, pg_temp.a('2026-12-14', '11:00'), 150, '2026-12-12', array['2026-12-12'::date],
     null, null, null),
    -- Barakaldo: cuadra, con un cierre (el del sábado).
    (pg_temp.d('BARAKALDO'), '2026-12-14', v_rep, v_t, pg_temp.a('2026-12-14', '11:00'), 120, '2026-12-12', array['2026-12-12'::date],
     120, null, pg_temp.a('2026-12-14', '11:40')),
    -- Basauri: el lunes, con dos cierres (viernes y sábado), cuadra.
    (pg_temp.d('BASAURI'), '2026-12-14', v_rep, v_t, pg_temp.a('2026-12-14', '11:00'), 200, '2026-12-12',
     array['2026-12-11'::date, '2026-12-12'::date], 200, null, pg_temp.a('2026-12-14', '12:00')),
    -- Portugalete: no cuadra, con su motivo.
    (pg_temp.d('PORTU'), '2026-12-14', v_rep, v_t, pg_temp.a('2026-12-14', '11:00'), 95, '2026-12-12', array['2026-12-12'::date],
     80, 'Monedas para cambio', pg_temp.a('2026-12-14', '12:20'));
  perform pg_temp.comprobar('El «para qué» de la tarea del efectivo: cada tienda, en el orden de la ruta',
    (motor.tarea_json(v_ef) ->> 'porque') = 'Efectivo apuntado por cada tienda:' || E'\n'
      || '· Bilbao: todavía no ha apuntado la bolsa de ayer' || E'\n'
      || '· Algorta: sin datos en la app (todavía no la usa)' || E'\n'
      || '· Barakaldo: 120,00 € (cierre del 12/12)' || E'\n'
      || '· Basauri: 200,00 € (cierres del 11/12 y 12/12)' || E'\n'
      || '· Portugalete: 80,00 € (cierre del 12/12); su cierre dice 95,00 €. Motivo: «Monedas para cambio»',
    motor.tarea_json(v_ef) ->> 'porque');
  perform pg_temp.comprobar('El título nuevo de la tarea del efectivo, y las demás tareas, con su «para qué» de siempre',
    motor.tarea_json(v_ef) ->> 'titulo'
      = 'Comprobar el efectivo de cada tienda, si no cuadra preguntar a la tienda por qué. Comunicar resultado final a Administración'
    and (select porque from public.tareas where id = v_t) is not distinct from motor.tarea_json(v_t) ->> 'porque');
  -- Bilbao lo apunta: la tarea lo enseña en el momento.
  update public.bolsas_tienda set efectivo_entregado = 150, efectivo_en = pg_temp.a('2026-12-14', '12:40')
   where centro_id = pg_temp.d('BILBAO') and fecha = '2026-12-14';
  perform pg_temp.comprobar('Con los datos del momento: Bilbao, en cuanto lo apunta',
    (motor.tarea_json(v_ef) ->> 'porque') like '%· Bilbao: 150,00 € (cierre del 12/12)%', motor.tarea_json(v_ef) ->> 'porque');
  -- Decisión del propietario (16/11/2026, PR #48): si no cuadra, también con los días; con varios, «sus cierres dicen».
  update public.bolsas_tienda set efectivo_entregado = 180, efectivo_motivo = 'Falta cambio'
   where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-14';
  perform pg_temp.comprobar('No cuadra con dos cierres: con los días y «sus cierres dicen»',
    (motor.tarea_json(v_ef) ->> 'porque') like '%· Basauri: 180,00 € (cierres del 11/12 y 12/12); sus cierres dicen 200,00 €. Motivo: «Falta cambio»%',
    motor.tarea_json(v_ef) ->> 'porque');
  -- Una tienda que entrega efectivo sin cierre de caja anterior en la app.
  update public.bolsas_tienda set efectivo_esperado = null, efectivo_de = null, efectivo_dias = null
   where centro_id = pg_temp.d('BILBAO') and fecha = '2026-12-14';
  perform pg_temp.comprobar('Sin cierre de caja anterior en la app: «(sin cierre de caja en la app)»',
    (motor.tarea_json(v_ef) ->> 'porque') like '%· Bilbao: 150,00 € (sin cierre de caja en la app)%', motor.tarea_json(v_ef) ->> 'porque');
end;
$$;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
