-- Prueba 44 · Reposición y envíos: lo que llega de más (T-0011 · Tarea 39; ESTADO_DEL_SISTEMA.md E2-8, decisión del
-- 12/11/2026). Martes 15/12/2026: reparto a Bilbao (2 V2 4g), Basauri (2 V2 4g, 3 CBD DRY 4g, 1 de ellas de Algorta,
-- y «Material: Rollos de TPV») y Portugalete (1 BZ1 4g de Algorta). La tienda pone lo que ha llegado de cada caja
-- (`llegado`), lo que ha llegado y no estaba (`de_mas`) y, como hasta ahora, lo que falta (`faltan`). El miércoles
-- 16/12, el envío a Gipuzkoa; Rentería lo confirma el jueves con lo de más. Cuentas y nombres inventados
-- (@osasun.invalid). Transacción deshecha al final.

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
create function pg_temp.punto(r jsonb, p_clave text, p_n integer) returns jsonb language sql as $$
  select pg_temp.tarea(r, p_clave) -> 'puntos' -> (p_n - 1) $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;
create function pg_temp.msg(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'mensaje' $$;
create function pg_temp.llamada(p_bolsas uuid, p_codigo text) returns uuid language sql as $$
  select id from public.tarea_elementos where tarea_id = p_bolsas and tipo = 'llamada' and destino_id = pg_temp.d(p_codigo) $$;
-- «Recibe la bolsa» hecha (los dos puntos, con el efectivo que espera) y la tarea de la reposición.
create function pg_temp.recibir(p_persona uuid, p_ahora timestamptz) returns uuid language plpgsql as $$
declare r jsonb := motor.tienda_hoy_de(p_persona, p_ahora);
begin
  perform motor.marcar_punto_de(p_persona, (pg_temp.punto(r, 'recibe_bolsa', 1) ->> 'id')::uuid, p_ahora);
  perform motor.entregar_efectivo_de(p_persona, (pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'id')::uuid,
                                     coalesce((pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'efectivo_esperado')::numeric, 40), null,
                                     p_ahora);
  return (pg_temp.tarea(motor.tienda_hoy_de(p_persona, p_ahora + interval '1 minute'), 'reposicion') ->> 'id')::uuid;
end;
$$;

-- La lista de productos de la hoja (la de los atascados), leída antes que nada de ese día.
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-15 08:00+01', 'stock', true, '{
  "productos": [
    {"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}, {"formato": "10g", "almacen": "3"}]},
    {"nombre": "CBD DRY", "orden": 2, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "2"}]},
    {"nombre": "BZ1", "orden": 3, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "5"}]},
    {"nombre": "CREMA", "orden": 4, "conTiendas": true, "formatos": []}],
  "categorias": {"V2": "Indoor", "BZ1": "Invernadero"}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.bilbao@osasun.invalid", "nombre": "Bilbao", "rol": "tienda", "centro": "BILBAO"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"},
  {"correo": "tienda.algorta@osasun.invalid", "nombre": "Algorta", "rol": "tienda", "centro": "ALGORTA"},
  {"correo": "tienda.renteria@osasun.invalid", "nombre": "Rentería", "rol": "tienda", "centro": "RENTERIA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.bilbao@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000004', 'tienda.portu@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000005', 'tienda.algorta@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000006', 'tienda.renteria@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('BILBAO'), 'Leire Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000005', pg_temp.d('PORTU'), 'Iker Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000006', pg_temp.d('ALGORTA'), 'Mikel Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000007', pg_temp.d('RENTERIA'), 'Maite Prueba', 'siempre', null);

-- El reparto del martes, como lo guarda la función del servidor guardar_reparto.
create function pg_temp.guardar(p_jornada uuid) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, 'reparto',
    E'REPARTO 15/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n\nBASAURI\n2x V2 4g\n3x CBD DRY 4g\n\nPORTU\n1x BZ1 4g',
    'h44', '2026-12-15', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 15/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 7, 'texto', 'BASAURI', 'clase', 'tienda', 'destino_id', pg_temp.d('BASAURI')),
      jsonb_build_object('num', 8, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 9, 'texto', '3x CBD DRY 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 3, 'producto', 'CBD DRY', 'formato', '4g'),
      jsonb_build_object('num', 11, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 12, 'texto', '1x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 1, 'producto', 'BZ1', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 4, 'en_almacen', 20, 'faltan', 0, 'aviso', null, 'orden', 1),
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
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1),
        jsonb_build_object('producto', 'CBD DRY', 'formato', '4g', 'cantidad', 3, 'orden', 2))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 1, 'orden', 3)))),
    true, pg_temp.a('2026-12-15', '08:40')) $$;

-- El envío a Gipuzkoa del miércoles: 4x V2 4g y 1x BZ1 4g.
create function pg_temp.envio(p_fecha date) returns jsonb language sql as $$
  select public.servidor_guardar_reparto('00000000-0000-4000-a000-000000000002',
    motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_fecha), 'envio',
    E'ENVÍO\n\nGIPUZKOA\n4x V2 4g\n1x BZ1 4g', 'h44-envio', p_fecha, null, null,
    jsonb_build_array(
      jsonb_build_object('num', 3, 'texto', 'GIPUZKOA', 'clase', 'tienda', 'destino_id', pg_temp.d('GIPUZKOA')),
      jsonb_build_object('num', 4, 'texto', '4x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('GIPUZKOA'),
                         'cantidad', 4, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 5, 'texto', '1x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('GIPUZKOA'),
                         'cantidad', 1, 'producto', 'BZ1', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 4, 'en_almacen', 4, 'faltan', 0, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 1, 'en_almacen', 1, 'faltan', 0, 'aviso', null, 'orden', 2)),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'), 'items', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 4, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 1, 'orden', 2)))),
    true, motor.en_local(p_fecha, '15:40')) $$;

-- ---------------------------------------------------------------------------
-- Martes 15/12: el reparto, las bolsas hechas y la salida
-- ---------------------------------------------------------------------------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-15');
  r jsonb;
  v_rep uuid;
  v_prod uuid;
  v_bolsas uuid;
begin
  r := pg_temp.guardar(j);
  v_rep := (r ->> 'reparto_id')::uuid;
  v_prod := (r -> 'tareas' ->> 'produccion')::uuid;
  v_bolsas := (r -> 'tareas' ->> 'bolsas')::uuid;
  perform public.servidor_guardar_peticiones(admin, v_rep,
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'texto', 'Material: Rollos de TPV')),
    pg_temp.a('2026-12-15', '08:41'));
  perform motor.resolver_sin_granel_de(op, (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'CBD DRY'),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'accion', 'otra_tienda',
                                         'origen_id', pg_temp.d('ALGORTA'), 'cantidad', 1)), pg_temp.a('2026-12-15', '09:10'));
  perform motor.resolver_sin_granel_de(op, (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1'),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'accion', 'otra_tienda',
                                         'origen_id', pg_temp.d('ALGORTA'), 'cantidad', 1)), pg_temp.a('2026-12-15', '09:11'));
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('2026-12-15', '09:00'), terminada_en = pg_temp.a('2026-12-15', '10:00')
   where jornada_id = j and clave = 'produccion_reparto';
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = cantidad, terminado_en = pg_temp.a('2026-12-15', '10:20')
   where tarea_id = v_bolsas and tipo in ('caja_bolsa', 'peticion');
  perform motor.marcar_cajas_de(op, pg_temp.llamada(v_bolsas, 'BASAURI'), 1, pg_temp.a('2026-12-15', '10:22'));
  perform motor.marcar_cajas_de(op, pg_temp.llamada(v_bolsas, 'PORTU'), 1, pg_temp.a('2026-12-15', '10:23'));
  update public.tareas set estado = 'en_curso', iniciada_en = pg_temp.a('2026-12-15', '10:50') where jornada_id = j and clave = 'salida_reparto';
  perform pg_temp.comprobar('Preparado: las bolsas hechas',
    (select estado from public.tareas where id = v_bolsas) = 'hecha');
end;
$$;

-- ---------------------------------------------------------------------------
-- La comprobación (una sola para la reposición y los envíos), con la lista de Basauri
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  c jsonb;
  r jsonb;
begin
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-15', '10:55'));
  c := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-15', '11:00')), 'recibe_bolsa') -> 'bolsa';
  perform pg_temp.comprobar('La lista de Basauri: V2 4g 2, CBD DRY 4g 3 (1 de Algorta) y la petición',
    c -> 'productos' -> 0 ->> 'clave' = 'producto:V2|4g' and c -> 'productos' -> 0 ->> 'cantidad' = '2'
    and c -> 'productos' -> 1 ->> 'clave' = 'producto:CBD DRY|4g' and c -> 'productos' -> 1 ->> 'cantidad' = '3'
    and c -> 'productos' -> 1 ? 'de' and c -> 'peticiones' -> 0 ->> 'texto' = 'Material: Rollos de TPV', c::text);

  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Falta 1 de una línea: ha llegado 1 de las 2 V2',
    r = '{"faltan": [{"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 1}], "sobran": []}', r::text);
  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g", "cantidad": 3}]');
  perform pg_temp.comprobar('Sobra 1 de una línea: han llegado 3 V2 y traía 2',
    r = '{"faltan": [], "sobran": [{"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 1}]}', r::text);
  r := motor.faltan_de_lista(c, null, null, '[{"producto": "BZ1", "formato": "4g", "cantidad": 2}]');
  perform pg_temp.comprobar('Ha llegado algo que no está en la lista: 2 BZ1 4g',
    r = '{"faltan": [], "sobran": [{"clave": "de_mas:BZ1|4g", "texto": "BZ1 4g", "cantidad": 2, "fuera_de_lista": true}]}', r::text);
  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g", "cantidad": 2}, {"clave": "producto:CBD DRY|4g", "cantidad": 3}]');
  perform pg_temp.comprobar('Todo igual: ni falta ni sobra nada',
    r = '{"faltan": [], "sobran": []}', r::text);
  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:CBD DRY|4g", "cantidad": 2}]');
  perform pg_temp.comprobar('Una línea con cajas de otra tienda: lo que falta dice de dónde venía cada caja',
    r -> 'faltan' = '[{"clave": "producto:CBD DRY|4g", "texto": "CBD DRY 4g", "cantidad": 1, "traia": "traía 3: 2 del almacén y 1 de Algorta"}]',
    r::text);
  perform pg_temp.comprobar('El texto: «Falta: … · Sobra: …», solo con lo que haya',
    motor.diferencias_texto('[{"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 1}]',
                            '[{"clave": "de_mas:BZ1|4g", "texto": "BZ1 4g", "cantidad": 1, "fuera_de_lista": true}]')
      = 'Falta: 1x V2 4g · Sobra: 1x BZ1 4g (no estaba en la lista)'
    and motor.diferencias_texto('[]', '[{"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 2}]') = 'Sobra: 2x V2 4g'
    and motor.diferencias_texto('[]', '[]') is null);

  -- Errores de datos, con una frase para enseñar tal cual.
  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g", "cantidad": -1}]');
  perform pg_temp.comprobar('Error: cantidad negativa',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'Cuántas han llegado de V2 4g: un número entero, 0 o más.', r::text);
  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g", "cantidad": 1.5}]');
  perform pg_temp.comprobar('Error: cantidad no entera (y sin cantidad)',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g"}]')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.faltan_de_lista(c, null, '[{"clave": "producto:V2|4g", "cantidad": "2"}]')) = 'DATOS_NO_VALIDOS', r::text);
  r := motor.faltan_de_lista(c, null, '[{"clave": "producto:BZ1|4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Error: una clave que no está en la lista (o que no es una caja)',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'Pon lo que ha llegado de cada caja de la lista.'
    and pg_temp.err(motor.faltan_de_lista(c, null, '[{"clave": "peticion:Material: Rollos de TPV", "cantidad": 0}]')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.faltan_de_lista(c, null, '{"clave": "producto:V2|4g"}')) = 'DATOS_NO_VALIDOS', r::text);
  r := motor.faltan_de_lista(c, '[{"clave": "producto:V2|4g", "cantidad": 1}]', '[{"clave": "producto:V2|4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Error: la misma caja en «faltan» y en «llegado»',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'Cada cosa, una sola vez.', r::text);
  r := motor.faltan_de_lista(c, null, null, '[{"producto": "NO EXISTE", "formato": "4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Error: un producto que no existe',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'Elige de la lista: «NO EXISTE 4g» no está.', r::text);
  r := motor.faltan_de_lista(c, null, null, '[{"producto": "BZ1", "formato": "10g", "cantidad": 1}]');
  perform pg_temp.comprobar('Error: un formato que no existe para ese producto',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'Elige de la lista: «BZ1 10g» no está.', r::text);
  r := motor.faltan_de_lista(c, null, null, '[{"producto": "V2", "formato": "4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Error: algo «de más» que sí está en la lista',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'V2 4g ya está en la lista: pon ahí lo que ha llegado.', r::text);
  r := motor.faltan_de_lista(c, null, null, '[{"producto": "BZ1", "formato": "4g", "cantidad": 0}]');
  perform pg_temp.comprobar('Error: «de más» con 0 o repetido',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and pg_temp.msg(r) = 'Cuántas cajas de BZ1 4g: de 1 a 99.'
    and pg_temp.msg(motor.faltan_de_lista(c, null, null, '[{"producto": "BZ1", "formato": "4g", "cantidad": 1},
                                                           {"producto": "BZ1", "formato": "4g", "cantidad": 1}]'))
        = 'Cada producto, una sola vez.', r::text);
  perform pg_temp.comprobar('«De más» sin formato, de un producto que no lo tiene (CREMA)',
    motor.faltan_de_lista(c, null, null, '[{"producto": "CREMA", "cantidad": 1}]') -> 'sobran' -> 0 ->> 'texto' = 'CREMA');
end;
$$;

-- ---------------------------------------------------------------------------
-- Las tiendas apuntan la reposición
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  r jsonb;
  v_t uuid;
  v_inc int;
begin
  perform motor.empezar_turno_tienda_de(bilbao, '00000000-0000-4000-c000-000000000002', pg_temp.a('2026-12-15', '10:55'));
  perform motor.empezar_turno_tienda_de(portu, '00000000-0000-4000-c000-000000000005', pg_temp.a('2026-12-15', '10:55'));

  -- Bilbao: pone que ha llegado lo mismo → «todo bien», como ahora.
  v_t := pg_temp.recibir(bilbao, pg_temp.a('2026-12-15', '11:20'));
  r := motor.apuntar_reposicion_de(bilbao, v_t, null, null, pg_temp.a('2026-12-15', '11:30'),
                                   '[{"clave": "producto:V2|4g", "cantidad": 2}]', '[]');
  perform pg_temp.comprobar('Bilbao, todo igual: «Reposición metida, todo bien», sin incidencia',
    pg_temp.tarea(r, 'reposicion') ->> 'estado' = 'hecha'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' ->> 'resultado' = 'bien'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' -> 'faltan' = '[]'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' -> 'sobran' = '[]'
    and (select resultado from public.tareas where id = v_t) = 'Reposición metida, todo bien'
    and not exists (select 1 from public.incidencias where opcion = 'falta_reposicion' and persona_id = bilbao), r::text);

  -- Basauri, errores con la tarea de verdad: no se apunta nada.
  v_t := pg_temp.recibir(basauri, pg_temp.a('2026-12-15', '11:20'));
  r := motor.apuntar_reposicion_de(basauri, v_t, null, null, pg_temp.a('2026-12-15', '11:30'),
                                   '[{"clave": "producto:V2|4g", "cantidad": -2}]');
  perform pg_temp.comprobar('Con un error de datos, la reposición sigue sin apuntar',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and (select estado from public.tareas where id = v_t) = 'pendiente'
    and (select reposicion from public.bolsas_tienda where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-15') is null, r::text);

  -- Basauri: falta y sobra a la vez (falta 1 V2 y la petición; sobra 1 CBD DRY, que trae de Algorta, y 1 BZ1 que no estaba).
  r := motor.apuntar_reposicion_de(basauri, v_t, '[{"clave": "peticion:Material: Rollos de TPV"}]', 'La caja venía abierta',
                                   pg_temp.a('2026-12-15', '11:31'),
                                   '[{"clave": "producto:V2|4g", "cantidad": 1}, {"clave": "producto:CBD DRY|4g", "cantidad": 4}]',
                                   '[{"producto": "BZ1", "formato": "4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Basauri, falta y sobra a la vez: la tarea queda hecha con lo que falta y lo que sobra',
    pg_temp.tarea(r, 'reposicion') ->> 'estado' = 'hecha'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' ->> 'resultado' = 'falta'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' -> 'faltan'
        = '[{"clave": "peticion:Material: Rollos de TPV", "texto": "Material: Rollos de TPV", "cantidad": 1},
            {"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 1}]'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' -> 'sobran'
        = '[{"clave": "producto:CBD DRY|4g", "texto": "CBD DRY 4g", "cantidad": 1, "traia": "traía 3: 2 del almacén y 1 de Algorta"},
            {"clave": "de_mas:BZ1|4g", "texto": "BZ1 4g", "cantidad": 1, "fuera_de_lista": true}]'
    and (select resultado from public.tareas where id = v_t) = 'Falta o sobra algo', r::text);
  perform pg_temp.comprobar('… y llega a Administración como la incidencia de siempre, con «Falta: … · Sobra: …»',
    (select descripcion from public.incidencias where opcion = 'falta_reposicion' and persona_id = basauri and estado = 'abierta')
      = 'Bolsa del reparto del 15/12. Falta: Material: Rollos de TPV; 1x V2 4g · Sobra: 1x CBD DRY 4g (traía 3: 2 del almacén y 1 de Algorta); 1x BZ1 4g (no estaba en la lista). La caja venía abierta (Ane Prueba)',
    (select descripcion from public.incidencias where opcion = 'falta_reposicion' and persona_id = basauri));

  -- Repetir no crea otra incidencia.
  select count(*) into v_inc from public.incidencias where opcion = 'falta_reposicion';
  r := motor.apuntar_reposicion_de(basauri, v_t, null, null, pg_temp.a('2026-12-15', '11:32'),
                                   '[{"clave": "producto:V2|4g", "cantidad": 1}]');
  perform pg_temp.comprobar('Repetir: ESTADO_NO_VALIDO, sin otra incidencia',
    pg_temp.err(r) = 'ESTADO_NO_VALIDO' and (select count(*) from public.incidencias where opcion = 'falta_reposicion') = v_inc, r::text);

  -- Portugalete, como hasta ahora: solo con faltan (la caja que traía de Algorta).
  v_t := pg_temp.recibir(portu, pg_temp.a('2026-12-15', '11:20'));
  r := motor.apuntar_reposicion_de(portu, v_t, '[{"clave": "producto:BZ1|4g"}]', null, pg_temp.a('2026-12-15', '11:40'));
  perform pg_temp.comprobar('Portugalete, una llamada solo con faltan, como hasta ahora: sigue funcionando',
    pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' ->> 'resultado' = 'falta'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' -> 'sobran' = '[]'
    and (select descripcion from public.incidencias where opcion = 'falta_reposicion' and persona_id = portu)
        = 'Bolsa del reparto del 15/12. Falta: 1x BZ1 4g (traía 1: 1 de Algorta) (Iker Prueba)',
    (select descripcion from public.incidencias where opcion = 'falta_reposicion' and persona_id = portu));
end;
$$;

-- ---------------------------------------------------------------------------
-- Miércoles 16/12 y jueves 17/12: el envío de Rentería
-- ---------------------------------------------------------------------------
do $$
declare
  renteria constant uuid := '00000000-0000-4000-b000-000000000006';
  r jsonb;
  v_env uuid;
  v_id uuid;
begin
  r := pg_temp.envio('2026-12-16');
  v_env := (r -> 'tareas' ->> 'bolsas')::uuid;
  -- El operario mete en la caja 3 de las 4 V2; la BZ1 no la marca.
  update public.tarea_elementos set cantidad_hecha = 3 where tarea_id = v_env and tipo = 'caja_bolsa' and producto = 'V2';
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('2026-12-16', '16:00'), terminada_en = pg_temp.a('2026-12-16', '17:00')
   where id = v_env;
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000007', pg_temp.a('2026-12-17', '10:55'));
  r := motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-17', '11:05'));
  v_id := (r -> 'envios' -> 0 ->> 'id')::uuid;
  perform pg_temp.comprobar('Rentería ve el envío con 3x V2 4g (la BZ1 sin marcar no aparece)',
    r -> 'envios' -> 0 -> 'productos' = '[{"clave": "producto:V2|4g", "producto": "V2", "formato": "4g", "cantidad": 3}]', r::text);
  r := motor.confirmar_envio_de(renteria, v_id, null, null, pg_temp.a('2026-12-17', '11:10'),
                                '[{"clave": "producto:V2|4g", "cantidad": 4}]', '[{"producto": "BZ1", "formato": "4g"}]');
  perform pg_temp.comprobar('En el envío, lo mismo: sobra 1 V2 y ha llegado 1 BZ1 que no estaba',
    r -> 'envios' = '[]'::jsonb
    and (select reposicion = 'falta' and faltan = '[]'::jsonb
                and sobran = '[{"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 1},
                               {"clave": "de_mas:BZ1|4g", "texto": "BZ1 4g", "cantidad": 1, "fuera_de_lista": true}]'::jsonb
           from public.bolsas_tienda where id = v_id), r::text);
  perform pg_temp.comprobar('… y llega a Administración como la incidencia de siempre del envío',
    (select descripcion from public.incidencias where opcion = 'falta_envio' and persona_id = renteria)
      = 'Envío del 16/12. Sobra: 1x V2 4g; 1x BZ1 4g (no estaba en la lista) (Maite Prueba)',
    (select descripcion from public.incidencias where opcion = 'falta_envio' and persona_id = renteria));
  perform pg_temp.comprobar('Confirmar otra vez: ESTADO_NO_VALIDO, sin otra incidencia',
    pg_temp.err(motor.confirmar_envio_de(renteria, v_id, null, null, pg_temp.a('2026-12-17', '11:20'))) = 'ESTADO_NO_VALIDO'
    and (select count(*) from public.incidencias where opcion = 'falta_envio' and persona_id = renteria) = 1);
end;
$$;

-- Lo de la pantalla: los mismos permisos que antes (solo con la cuenta de la tienda).
select pg_temp.comprobar('Permisos: la pantalla con su cuenta; sin sesión, nada',
  has_function_privilege('authenticated', 'public.apuntar_reposicion(uuid, jsonb, text, jsonb, jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.confirmar_envio(uuid, jsonb, text, jsonb, jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apuntar_reposicion(uuid, jsonb, text, jsonb, jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.confirmar_envio(uuid, jsonb, text, jsonb, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.apuntar_reposicion_de(uuid, uuid, jsonb, text, timestamptz, jsonb, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.faltan_de_lista(jsonb, jsonb, jsonb, jsonb)', 'EXECUTE')
  and to_regprocedure('public.apuntar_reposicion(uuid, jsonb, text)') is null
  and to_regprocedure('public.confirmar_envio(uuid, jsonb, text)') is null);

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
