-- Prueba 43 · Cajas de otra tienda (T-0010 · Tarea 38; ESTADO_DEL_SISTEMA.md R1e y E2-8, decisión del 11/11/2026).
-- Martes 15/12/2026. El caso real del 09/11: Basauri pide 3 CBD DRY 4g; en el almacén hay 2 y no hay granel; la otra
-- sale de Algorta. Además, Portugalete solo recibe 1 BZ1 4g de Algorta, y Bilbao, 2 V2 4g del almacén (sin cambios).
-- La línea del operario dice «Avisa a Algorta…»; al marcarla, Algorta recibe el aviso y la caja sale en la lista de la
-- tienda que recibe. Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

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
create function pg_temp.a(p_hora text) returns timestamptz language sql as $$ select motor.en_local('2026-12-15', p_hora::time) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.tarea(r jsonb, p_clave text) returns jsonb language sql as $$
  select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' like p_clave limit 1 $$;
create function pg_temp.punto(r jsonb, p_clave text, p_n integer) returns jsonb language sql as $$
  select pg_temp.tarea(r, p_clave) -> 'puntos' -> (p_n - 1) $$;
-- Los avisos del almacén que tiene hoy una tienda (texto).
create function pg_temp.avisos(p_persona uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(x ->> 'texto' order by x ->> 'texto'), '[]')
    from jsonb_array_elements(motor.tienda_hoy_de(p_persona, pg_temp.a('11:00')) -> 'avisos') x where x ->> 'de' = 'Almacén' $$;
-- La línea «Avisa a…» de una tienda en las bolsas de hoy.
create function pg_temp.llamada(p_bolsas uuid, p_codigo text) returns uuid language sql as $$
  select id from public.tarea_elementos where tarea_id = p_bolsas and tipo = 'llamada' and destino_id = pg_temp.d(p_codigo) $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.bilbao@osasun.invalid", "nombre": "Bilbao", "rol": "tienda", "centro": "BILBAO"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"},
  {"correo": "tienda.algorta@osasun.invalid", "nombre": "Algorta", "rol": "tienda", "centro": "ALGORTA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.bilbao@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000004', 'tienda.portu@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000005', 'tienda.algorta@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('BILBAO'), 'Leire Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000005', pg_temp.d('PORTU'), 'Iker Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000006', pg_temp.d('ALGORTA'), 'Mikel Prueba', 'siempre', null);

-- El reparto, como lo guarda la función del servidor guardar_reparto (R1e: dos referencias sin granel).
create function pg_temp.guardar(p_jornada uuid) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, 'reparto',
    E'REPARTO 15/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n\nBASAURI\n3x CBD DRY 4g\n\nPORTU\n1x BZ1 4g',
    'h43', '2026-12-15', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 15/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 7, 'texto', 'BASAURI', 'clase', 'tienda', 'destino_id', pg_temp.d('BASAURI')),
      jsonb_build_object('num', 8, 'texto', '3x CBD DRY 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 3, 'producto', 'CBD DRY', 'formato', '4g'),
      jsonb_build_object('num', 10, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 11, 'texto', '1x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 1, 'producto', 'BZ1', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 2, 'en_almacen', 20, 'faltan', 0, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'CBD DRY', 'formato', '4g', 'pedido', 3, 'en_almacen', 2, 'faltan', 1, 'aviso', null, 'orden', 2,
                         'sin_granel', true,
                         'para', jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'destino', 'Basauri',
                                                                      'pedido', 3, 'faltan', 1)),
                         'tiendas_con_stock', jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('ALGORTA'),
                                                                                   'destino', 'Algorta', 'cajas', 2))),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 1, 'en_almacen', 0, 'faltan', 1, 'aviso', null, 'orden', 3,
                         'sin_granel', true,
                         'para', jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'destino', 'Portugalete',
                                                                      'pedido', 1, 'faltan', 1)),
                         'tiendas_con_stock', jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('ALGORTA'),
                                                                                   'destino', 'Algorta', 'cajas', 4)))),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1))),
      jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'CBD DRY', 'formato', '4g', 'cantidad', 3, 'orden', 2))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 1, 'orden', 3)))),
    true, pg_temp.a('08:40')) $$;

do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  algorta constant uuid := '00000000-0000-4000-b000-000000000005';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-15');
  r jsonb;
  t jsonb;
  v_rep uuid;
  v_prod uuid;
  v_bolsas uuid;
  v_paradas jsonb;
  v_ll uuid;
begin
  r := pg_temp.guardar(j);
  v_rep := (r ->> 'reparto_id')::uuid;
  v_prod := (r -> 'tareas' ->> 'produccion')::uuid;
  v_bolsas := (r -> 'tareas' ->> 'bolsas')::uuid;
  -- El operario decide en la producción: de Algorta (R1e).
  perform motor.resolver_sin_granel_de(op, (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'CBD DRY'),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'accion', 'otra_tienda',
                                         'origen_id', pg_temp.d('ALGORTA'), 'cantidad', 1)), pg_temp.a('09:10'));
  perform motor.resolver_sin_granel_de(op, (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1'),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'accion', 'otra_tienda',
                                         'origen_id', pg_temp.d('ALGORTA'), 'cantidad', 1)), pg_temp.a('09:11'));
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('09:00'), terminada_en = pg_temp.a('10:00')
   where jornada_id = j and clave = 'produccion_reparto';
  v_paradas := motor.paradas_reparto(j);

  -- 1. La línea del operario: «Avisa a…»; lo demás, igual.
  perform pg_temp.comprobar('Bolsas: Basauri, 2 CBD DRY 4g del almacén y «Avisa a Algorta para que prepare 1 CBD DRY 4g para su retirada»',
    (select string_agg(tipo || ':' || producto || ':' || cantidad, ' | ' order by tipo, producto) from public.tarea_elementos
      where tarea_id = v_bolsas and destino_id = pg_temp.d('BASAURI'))
      = 'caja_bolsa:CBD DRY:2 | llamada:Avisa a Algorta para que prepare 1 CBD DRY 4g para su retirada:1'
    and (select calculo from public.tarea_elementos where id = pg_temp.llamada(v_bolsas, 'BASAURI'))
        = jsonb_build_object('origen_id', pg_temp.d('ALGORTA'), 'producto', 'CBD DRY', 'formato', '4g', 'cantidad', 1));
  perform pg_temp.comprobar('Portugalete solo tiene «Avisa a Algorta para que prepare 1 BZ1 4g para su retirada» (nada del almacén)',
    (select string_agg(tipo || ':' || producto, ' | ') from public.tarea_elementos
      where tarea_id = v_bolsas and destino_id = pg_temp.d('PORTU'))
      = 'llamada:Avisa a Algorta para que prepare 1 BZ1 4g para su retirada');

  -- 2. Sin marcar: ni aviso ni caja en la lista.
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = cantidad, terminado_en = pg_temp.a('10:20')
   where tarea_id = v_bolsas and tipo = 'caja_bolsa';
  perform pg_temp.comprobar('Sin marcar la línea: Algorta no tiene ningún aviso y en la lista de Basauri solo van las 2 del almacén',
    pg_temp.avisos(algorta) = '[]'
    and motor.bolsa_contenido(v_rep, pg_temp.d('BASAURI')) -> 'productos'
        = '[{"clave": "producto:CBD DRY|4g", "producto": "CBD DRY", "formato": "4g", "cantidad": 2}]',
    motor.bolsa_contenido(v_rep, pg_temp.d('BASAURI'))::text);

  -- 3. Al marcarla (el toque de siempre): el aviso a Algorta y la caja en la lista de Basauri.
  r := motor.marcar_cajas_de(op, pg_temp.llamada(v_bolsas, 'BASAURI'), 1, pg_temp.a('10:22'));
  perform pg_temp.comprobar('Al marcarla, Algorta tiene en su tablet el aviso del almacén para hoy',
    r ->> 'error' is null
    and pg_temp.avisos(algorta) = '["Prepara 1 CBD DRY 4g para Basauri: lo recoge hoy el reparto"]', pg_temp.avisos(algorta)::text);
  perform pg_temp.comprobar('… y la caja de Algorta se suma a la línea de CBD DRY de Basauri, con `de` (la misma clave)',
    motor.bolsa_contenido(v_rep, pg_temp.d('BASAURI')) -> 'productos'
      = jsonb_build_array(jsonb_build_object('clave', 'producto:CBD DRY|4g', 'producto', 'CBD DRY', 'formato', '4g', 'cantidad', 3,
                          'de', jsonb_build_array(jsonb_build_object('origen_id', pg_temp.d('ALGORTA'), 'origen', 'Algorta', 'cantidad', 1)))),
    motor.bolsa_contenido(v_rep, pg_temp.d('BASAURI'))::text);
  -- Marcarla otra vez (quitarla y volver a ponerla) no repite el aviso.
  perform motor.marcar_cajas_de(op, pg_temp.llamada(v_bolsas, 'BASAURI'), 0, pg_temp.a('10:23'));
  perform pg_temp.comprobar('Desmarcada, la caja de Algorta deja de estar en la lista',
    motor.bolsa_contenido(v_rep, pg_temp.d('BASAURI')) -> 'productos' -> 0 ->> 'cantidad' = '2'
    and not (motor.bolsa_contenido(v_rep, pg_temp.d('BASAURI')) -> 'productos' -> 0 ? 'de'));
  perform motor.marcar_cajas_de(op, pg_temp.llamada(v_bolsas, 'BASAURI'), 1, pg_temp.a('10:24'));
  perform pg_temp.comprobar('Marcarla otra vez no repite el aviso: uno por línea',
    pg_temp.avisos(algorta) = '["Prepara 1 CBD DRY 4g para Basauri: lo recoge hoy el reparto"]'
    and (select count(*) from public.incidencias where opcion = 'aviso' and descripcion like 'Prepara 1 CBD DRY 4g para Basauri%') = 1);

  -- 4. Portugalete, que solo recibe de otra tienda.
  perform pg_temp.comprobar('La de Portugalete, sin marcar: sin aviso del BZ1 y sin lista',
    pg_temp.avisos(algorta) = '["Prepara 1 CBD DRY 4g para Basauri: lo recoge hoy el reparto"]'
    and motor.bolsa_contenido(v_rep, pg_temp.d('PORTU')) -> 'productos' = '[]');
  perform motor.marcar_cajas_de(op, pg_temp.llamada(v_bolsas, 'PORTU'), 1, pg_temp.a('10:25'));
  perform pg_temp.comprobar('Marcada: aviso a Algorta y una línea solo con lo de la otra tienda',
    pg_temp.avisos(algorta) = '["Prepara 1 BZ1 4g para Portugalete: lo recoge hoy el reparto", "Prepara 1 CBD DRY 4g para Basauri: lo recoge hoy el reparto"]'
    and motor.bolsa_contenido(v_rep, pg_temp.d('PORTU')) -> 'productos'
        = jsonb_build_array(jsonb_build_object('clave', 'producto:BZ1|4g', 'producto', 'BZ1', 'formato', '4g', 'cantidad', 1,
                            'de', jsonb_build_array(jsonb_build_object('origen_id', pg_temp.d('ALGORTA'), 'origen', 'Algorta', 'cantidad', 1)))),
    pg_temp.avisos(algorta)::text);

  -- 5. Lo del operario, igual: con todo marcado, las bolsas quedan hechas; la ruta, la misma.
  perform pg_temp.comprobar('Las bolsas quedan hechas con el último toque, y la ruta (paradas) no cambia',
    (select estado from public.tareas where id = v_bolsas) = 'hecha'
    and motor.paradas_reparto(j) = v_paradas and jsonb_array_length(v_paradas) = 2, motor.paradas_reparto(j)::text);
  update public.tareas set estado = 'en_curso', iniciada_en = pg_temp.a('10:50') where jornada_id = j and clave = 'salida_reparto';

  -- 6. En las tablets: «Recibe la bolsa» con su lista.
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('10:55'));
  perform motor.empezar_turno_tienda_de(portu, '00000000-0000-4000-c000-000000000005', pg_temp.a('10:55'));
  perform motor.empezar_turno_tienda_de(bilbao, '00000000-0000-4000-c000-000000000002', pg_temp.a('10:55'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('11:00'));
  perform pg_temp.comprobar('Basauri: «Recibe la bolsa» con CBD DRY 4g 3 (1 de Algorta)',
    pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'productos' -> 0 ->> 'cantidad' = '3'
    and pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'productos' -> 0 -> 'de' -> 0 ->> 'origen' = 'Algorta', r::text);
  r := motor.tienda_hoy_de(portu, pg_temp.a('11:00'));
  perform pg_temp.comprobar('Portugalete, que solo recibe de Algorta, tiene igualmente su «Recibe la bolsa» y su lista',
    pg_temp.tarea(r, 'recibe_bolsa') is not null
    and pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'productos' -> 0 ->> 'clave' = 'producto:BZ1|4g', r::text);
  r := motor.tienda_hoy_de(bilbao, pg_temp.a('11:00'));
  perform pg_temp.comprobar('Bilbao, sin cajas de otra tienda, igual que siempre (sin `de`)',
    pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'productos'
      = '[{"clave": "producto:V2|4g", "producto": "V2", "formato": "4g", "cantidad": 2}]', r::text);

  -- 7. «Falta algo» de la caja de otra tienda.
  r := motor.tienda_hoy_de(basauri, pg_temp.a('11:20'));
  perform motor.marcar_punto_de(basauri, (pg_temp.punto(r, 'recibe_bolsa', 1) ->> 'id')::uuid, pg_temp.a('11:20'));
  -- Lo que espera el punto (en pruebas, el último cierre real de la tienda): esta prueba no va del efectivo.
  perform motor.entregar_efectivo_de(basauri, (pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'id')::uuid,
                                     coalesce((pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'efectivo_esperado')::numeric, 40), null,
                                     pg_temp.a('11:21'));
  t := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('11:30')), 'reposicion');
  r := motor.apuntar_reposicion_de(basauri, (t ->> 'id')::uuid, '[{"clave": "producto:CBD DRY|4g", "cantidad": 1}]', null,
                                   pg_temp.a('11:30'));
  perform pg_temp.comprobar('«Falta algo»: como siempre, y la incidencia dice de dónde venía cada caja',
    pg_temp.tarea(r, 'reposicion') ->> 'estado' = 'hecha'
    and (select descripcion from public.incidencias where opcion = 'falta_reposicion' and persona_id = basauri)
        = 'Falta en la bolsa del reparto del 15/12: 1x CBD DRY 4g (traía 3: 2 del almacén y 1 de Algorta) (Ane Prueba)',
    (select descripcion from public.incidencias where opcion = 'falta_reposicion' and persona_id = basauri));
end;
$$;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
