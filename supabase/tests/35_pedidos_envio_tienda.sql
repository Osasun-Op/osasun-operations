-- Prueba 35 · Pedidos de cliente por envío y desde la tableta (Tarea 30c; ESTADO_DEL_SISTEMA.md §5 R1b v1.51 y E2-8).
-- El miércoles 16/12/2026: Administración apunta un pedido para recoger en Donosti (va en el siguiente envío a
-- Gipuzkoa), el aviso en «Revisa si toca envío…», el envío de la tarde lo lleva con su tarea propia y su caja aparte,
-- y el jueves sale en «Envíos» de Rentería. Basauri y Donosti apuntan pedidos desde la tableta. El reparto y los
-- pedidos de siempre, igual. Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas y de las jornadas del operario. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
update public.pedidos_cliente set tarea_id = null, jornada_id = null, entrega = 'nacex', destino_id = null,
       datos_envio = coalesce(datos_envio, '-')
 where entrega = 'tienda' and tarea_id is null;
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;
create temp table _v (k text primary key, v jsonb) on commit drop;
grant all on _v to authenticated;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.a(p_fecha date, p_hora time) returns timestamptz language sql as $$ select motor.en_local(p_fecha, p_hora) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;
-- Lo que hace la función del servidor guardar_pedido_cliente (recoger en tienda), sin leer la hoja.
create function pg_temp.pedido(p_id uuid, p_cliente text, p_tienda text, p_ahora timestamptz) returns jsonb language plpgsql as $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  prep jsonb := public.servidor_preparar_pedido(adm, p_id, 'tienda', pg_temp.d(p_tienda), p_ahora);
  r jsonb;
begin
  if prep ? 'error' then return prep; end if;
  r := public.servidor_guardar_pedido_cliente(adm, p_id, p_cliente, 'tienda', pg_temp.d(p_tienda), null,
         '[{"producto": "V2", "formato": "4g", "cantidad": 1}]', (prep ->> 'fecha')::date, null, null, null, p_ahora);
  if prep ->> 'reparto_id' is not null then
    perform public.servidor_asignar_pedidos(adm, (prep ->> 'reparto_id')::uuid,
      jsonb_build_array(jsonb_build_object('pedido_id', r -> 'pedido' ->> 'id',
        'elementos', '[{"producto": "V2", "formato": "4g", "cantidad": 1, "orden": 1}]'::jsonb)), p_ahora);
  end if;
  return r || jsonb_build_object('prep', prep);
end; $$;
-- Un envío a Gipuzkoa como lo guarda la función del servidor guardar_reparto: 2x V2 4g.
create function pg_temp.envio(p_fecha date, p_huella text) returns jsonb language sql as $$
  select public.servidor_guardar_reparto('00000000-0000-4000-a000-000000000002',
    motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_fecha), 'envio',
    E'ENVÍO\n\nGIPUZKOA\n2x V2 4g', p_huella, p_fecha, null, null,
    jsonb_build_array(
      jsonb_build_object('num', 3, 'texto', 'GIPUZKOA', 'clase', 'tienda', 'destino_id', pg_temp.d('GIPUZKOA')),
      jsonb_build_object('num', 4, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('GIPUZKOA'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 2, 'en_almacen', 10, 'faltan', 0, 'aviso', null, 'orden', 1)),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'), 'items', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1)))),
    true, motor.en_local(p_fecha, '15:40')) $$;
-- El reparto del miércoles 16/12 a Basauri: 3x V2 4g.
create function pg_temp.reparto(p_fecha date) returns jsonb language sql as $$
  select public.servidor_guardar_reparto('00000000-0000-4000-a000-000000000002',
    motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_fecha), 'reparto',
    E'REPARTO\nSALE: ALMACÉN\n\nBASAURI\n3x V2 4g', 'h35-r', p_fecha, 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BASAURI', 'clase', 'tienda', 'destino_id', pg_temp.d('BASAURI')),
      jsonb_build_object('num', 5, 'texto', '3x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 3, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 3, 'en_almacen', 10, 'faltan', 0, 'aviso', null, 'orden', 1)),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'items', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 3, 'orden', 1)))),
    true, motor.en_local(p_fecha, '08:50')) $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.donosti@osasun.invalid", "nombre": "Donosti", "rol": "tienda", "centro": "DONOSTI"},
  {"correo": "tienda.renteria@osasun.invalid", "nombre": "Rentería", "rol": "tienda", "centro": "RENTERIA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000003', 'tienda.donosti@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000005', 'tienda.renteria@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000004', pg_temp.d('DONOSTI'), 'Nora Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000006', pg_temp.d('RENTERIA'), 'Maite Prueba', 'siempre', null);
-- La última lectura de la hoja (la lista de la tableta).
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-16 08:00+01', 'stock', true, '{
  "productos": [
    {"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}, {"formato": "10g", "almacen": "3"}]},
    {"nombre": "BZ1", "orden": 2, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "5"}]},
    {"nombre": "CREMA", "orden": 3, "conTiendas": true, "formatos": []}],
  "categorias": {"V2": "Indoor", "BZ1": "Invernadero"}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-16');
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-17');

-- ---------------------------------------------------------------------------
-- 1. Las tiendas que se pueden elegir y un pedido para recoger en Donosti
-- ---------------------------------------------------------------------------
do $$
declare
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-16');
  r jsonb;
  c uuid := '00000000-0000-4000-d000-000000000001';
begin
  r := motor.tiendas_pedido_json();
  perform pg_temp.comprobar('Las tiendas de «Pedido de cliente»: las del reparto en su orden y Donosti y Rentería por envío (sin Gipuzkoa ni Durango, cerrada)',
    (select jsonb_agg(x ->> 'codigo' || ':' || (x ->> 'va_en')) from jsonb_array_elements(r) x)
      = '["BILBAO:reparto", "ALGORTA:reparto", "BARAKALDO:reparto", "BASAURI:reparto", "PORTU:reparto", "DONOSTI:envio", "RENTERIA:envio"]'::jsonb,
    r::text);
  perform pg_temp.comprobar('Gipuzkoa (el destino del envío) no se elige',
    pg_temp.err(pg_temp.pedido(gen_random_uuid(), 'X', 'GIPUZKOA', pg_temp.a('2026-12-16', '10:00'))) = 'DATOS_NO_VALIDOS');

  r := pg_temp.pedido(c, 'Mikel', 'DONOSTI', pg_temp.a('2026-12-16', '10:00'));
  insert into _v values ('pedido_donosti', r -> 'pedido');
  perform pg_temp.comprobar('Pedido para recoger en Donosti: espera al siguiente envío',
    r -> 'pedido' ->> 'estado' = 'esperando_reparto' and r -> 'pedido' ->> 'va_en' = 'envio'
    and r -> 'pedido' ->> 'estado_texto' like 'Va en el próximo envío a Donosti%'
    and r -> 'pedido' ->> 'entrega_texto' = 'Recoger en Donosti' and r -> 'prep' -> 'reparto_id' = 'null'::jsonb, r::text);
  r := motor.tarea_json((select id from public.tareas where jornada_id = j and clave = 'revisar_envio'));
  perform pg_temp.comprobar('En «Revisa si toca envío…», el aviso de los pedidos que esperan envío',
    r ->> 'aviso' = 'Hay 1 pedido de cliente esperando envío a Gipuzkoa'
    and motor.tarea_json((select id from public.tareas where jornada_id = j and clave = 'revision_inicial')) -> 'aviso' = 'null'::jsonb,
    r::text);
  r := public.servidor_preparar('00000000-0000-4000-a000-000000000002', pg_temp.a('2026-12-16', '10:05'));
  perform pg_temp.comprobar('servidor_preparar lo lleva con el destino del envío (GIPUZKOA) y las tiendas para elegir',
    exists (select 1 from jsonb_array_elements(r -> 'pedidos_tienda') x
             where x ->> 'cliente' = 'Mikel' and x ->> 'envio_destino_id' = pg_temp.d('GIPUZKOA')::text)
    and jsonb_array_length(r -> 'tiendas_pedido') = 7, r -> 'pedidos_tienda' #>> '{}');
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. El reparto no lo lleva; el envío de la tarde, sí (tarea propia y caja aparte)
-- ---------------------------------------------------------------------------
select pg_temp.reparto('2026-12-16');
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-16');
  v_ped uuid := (select v ->> 'id' from _v where k = 'pedido_donosti')::uuid;
  v_rep uuid := (select id from public.repartos where jornada_id = j and tipo = 'reparto' and estado = 'aceptado');
  r jsonb;
  v_env uuid;
  v_tarea uuid;
  t jsonb;
begin
  perform public.servidor_asignar_pedidos(adm, v_rep, jsonb_build_array(jsonb_build_object('pedido_id', v_ped,
    'elementos', '[{"producto": "V2", "formato": "4g", "cantidad": 1, "orden": 1}]'::jsonb)), pg_temp.a('2026-12-16', '09:00'));
  perform pg_temp.comprobar('El reparto no se lleva un pedido de Donosti',
    (select tarea_id is null and jornada_id is null from public.pedidos_cliente where id = v_ped));
  r := pg_temp.envio('2026-12-16', 'h35-e');
  v_env := (r -> 'tareas' ->> 'bolsas')::uuid;
  perform public.servidor_asignar_pedidos(adm, (r ->> 'reparto_id')::uuid, jsonb_build_array(jsonb_build_object('pedido_id', v_ped,
    'elementos', '[{"producto": "V2", "formato": "4g", "cantidad": 1, "orden": 1}]'::jsonb)), pg_temp.a('2026-12-16', '15:40'));
  select tarea_id into v_tarea from public.pedidos_cliente where id = v_ped;
  perform pg_temp.comprobar('El envío lo lleva: tarea propia «Hay un pedido de cliente para enviar a Donosti · Mikel», como en el reparto',
    (select clave = 'pedido_tienda:' || v_ped and titulo = 'Hay un pedido de cliente para enviar a Donosti · Mikel'
            and porque = 'Va en una caja aparte, «Pedido de cliente · Mikel · Donosti», en el envío a Gipuzkoa.' and jornada_id = j
       from public.tareas where id = v_tarea));
  t := motor.tarea_json(v_env);
  perform pg_temp.comprobar('… y caja aparte en «Prepara el envío aprobado», en Gipuzkoa, que dice para qué tienda es',
    exists (select 1 from jsonb_array_elements(t -> 'elementos') x
             where x ->> 'bolsa' = 'Pedido de cliente · Mikel · Donosti' and x ->> 'destino_id' = pg_temp.d('GIPUZKOA')::text
               and x ->> 'producto' = 'V2' and (x ->> 'cantidad')::int = 1), t::text);
  perform pg_temp.comprobar('El pedido ya va en el envío del 16/12 y el aviso desaparece',
    motor.pedido_json(v_ped) ->> 'estado_texto' = 'En el envío del 16/12: por preparar'
    and motor.aviso_pedidos_envio() is null);
  -- R1c: sale del almacén con el envío preparado, no con las bolsas del reparto.
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a('2026-12-16', '10:40') where jornada_id = j and clave = 'bolsas';
  perform pg_temp.comprobar('Con las bolsas hechas, sigue comprometido (va con el envío)',
    exists (select 1 from motor.pendiente_salir(j, pg_temp.a('2026-12-16', '16:00')) x where x.pedido_id = v_ped));
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = cantidad where tarea_id = v_env;
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a('2026-12-16', '17:00') where id in (v_env, v_tarea);
  perform pg_temp.comprobar('Con el envío preparado, ya ha salido; el pedido, «Preparado: va en el envío del 16/12»',
    not exists (select 1 from motor.pendiente_salir(j, pg_temp.a('2026-12-16', '17:30')) x where x.pedido_id = v_ped)
    and motor.pedido_json(v_ped) ->> 'estado_texto' = 'Preparado: va en el envío del 16/12');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. El jueves, en «Envíos» de Rentería (que recibe el envío a Gipuzkoa)
-- ---------------------------------------------------------------------------
do $$
declare
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  r jsonb;
begin
  r := motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-17', '11:00'));
  perform pg_temp.comprobar('Rentería lo ve en «Envíos» con lo demás, con la tienda del pedido (Donosti)',
    exists (select 1 from jsonb_array_elements(r -> 'envios' -> 0 -> 'pedidos') x
             where x ->> 'cliente' = 'Mikel' and x ->> 'tienda' = 'Donosti'
               and x -> 'lineas' = '[{"producto": "V2", "formato": "4g", "cantidad": 1}]'::jsonb), r -> 'envios' #>> '{}');
  perform pg_temp.comprobar('Donosti no tiene «Envíos»; ve su pedido en tienda_hoy().pedidos, sin datos de envío',
    motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-16', '17:30')) -> 'envios' = '[]'::jsonb
    and exists (select 1 from jsonb_array_elements(motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-16', '17:30')) -> 'pedidos') x
                 where x ->> 'cliente' = 'Mikel' and x ->> 'estado' = 'preparado' and not x ? 'datos_envio'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Desde la tableta
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  c uuid := '00000000-0000-4000-d000-000000000002';
  r jsonb;
  v_ped uuid;
  j uuid;
begin
  -- Un reparto nuevo el jueves 17/12, guardado y sin bolsas hechas: el pedido entra en él al momento.
  perform pg_temp.reparto('2026-12-17');
  j := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-17');
  perform pg_temp.comprobar('productos_tienda trae los formatos de cada producto (para el pedido)',
    (select x -> 'formatos' from jsonb_array_elements(motor.productos_tienda_de() -> 'productos') x where x ->> 'producto' = 'V2')
      = '["4g", "10g"]'::jsonb
    and (select x -> 'formatos' from jsonb_array_elements(motor.productos_tienda_de() -> 'productos') x where x ->> 'producto' = 'CREMA')
      = '[""]'::jsonb);
  perform pg_temp.comprobar('Sin nadie en el turno: SIN_PERSONA',
    pg_temp.err(motor.crear_pedido_tienda_de(basauri, c, 'Josu', '[{"producto": "V2", "formato": "4g", "cantidad": 2}]',
                                             pg_temp.a('2026-12-17', '10:00'))) = 'SIN_PERSONA');
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-17', '10:55'));
  perform pg_temp.comprobar('Solo de la lista, de 1 a 99, con cliente y al menos un producto',
    pg_temp.err(motor.crear_pedido_tienda_de(basauri, c, 'Josu', '[{"producto": "V2", "formato": "7g", "cantidad": 2}]', pg_temp.a('2026-12-17', '11:00'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.crear_pedido_tienda_de(basauri, c, 'Josu', '[{"producto": "V2", "formato": "4g", "cantidad": 100}]', pg_temp.a('2026-12-17', '11:00'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.crear_pedido_tienda_de(basauri, c, 'Josu', '[{"producto": "V2", "formato": "4g", "cantidad": 0}]', pg_temp.a('2026-12-17', '11:00'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.crear_pedido_tienda_de(basauri, c, '  ', '[{"producto": "V2", "formato": "4g", "cantidad": 1}]', pg_temp.a('2026-12-17', '11:00'))) = 'DATOS_NO_VALIDOS'
    and not exists (select 1 from public.pedidos_cliente where id_cliente = c));
  r := motor.crear_pedido_tienda_de(basauri, c, 'Josu',
         '[{"producto": "V2", "formato": "4g", "cantidad": 2}, {"producto": "BZ1", "formato": "4g", "cantidad": 0},
           {"producto": "V2", "formato": "4g", "cantidad": 1}, {"producto": "CREMA", "formato": "", "cantidad": 1}]',
         pg_temp.a('2026-12-17', '11:00'));
  select id into v_ped from public.pedidos_cliente where id_cliente = c;
  perform pg_temp.comprobar('Basauri apunta un pedido: para recoger en Basauri, repetidos sumados, con quién estaba',
    (select entrega = 'tienda' and destino_id = pg_temp.d('BASAURI') and pedido_por = 'Ane Prueba' and datos_envio is null
            and lineas = '[{"producto": "V2", "formato": "4g", "cantidad": 3}, {"producto": "CREMA", "formato": "", "cantidad": 1}]'::jsonb
       from public.pedidos_cliente where id = v_ped)
    and exists (select 1 from jsonb_array_elements(r -> 'pedidos') x where x ->> 'id' = v_ped::text), r::text);
  perform pg_temp.comprobar('Con el reparto de hoy guardado y sin salir, entra en él al momento (su tarea y su bolsa aparte)',
    (select t.clave = 'pedido_tienda:' || v_ped and t.titulo = 'Hay un pedido de cliente para dejar en Basauri · Josu'
       from public.tareas t where t.id = (select tarea_id from public.pedidos_cliente where id = v_ped))
    and (select count(*) from public.tarea_elementos e join public.tareas b on b.id = e.tarea_id
          where b.jornada_id = j and b.clave = 'bolsas' and e.lote = 'pedido:' || v_ped and e.destino_id = pg_temp.d('BASAURI')) = 2);
  perform pg_temp.comprobar('Repetir con el mismo id_cliente no lo duplica',
    motor.crear_pedido_tienda_de(basauri, c, 'Josu', '[{"producto": "V2", "formato": "4g", "cantidad": 2}]', pg_temp.a('2026-12-17', '11:01')) ? 'pedidos'
    and (select count(*) from public.pedidos_cliente where id_cliente = c) = 1);
  r := motor.pedidos_cliente_abiertos_de('00000000-0000-4000-a000-000000000002', pg_temp.a('2026-12-17', '11:05'));
  perform pg_temp.comprobar('Administración lo ve en sus pedidos de siempre, con qué tienda y quién lo pidió',
    exists (select 1 from jsonb_array_elements(r -> 'pedidos') x
             where x ->> 'id' = v_ped::text and x ->> 'pedido_en_tienda' = 'Basauri' and x ->> 'pedido_por' = 'Ane Prueba'
               and x ->> 'estado_texto' = 'En el reparto del 17/12: por preparar' and x ->> 'va_en' = 'reparto'), r::text);

  -- Donosti, desde su tableta: va en el siguiente envío a Gipuzkoa.
  perform motor.empezar_turno_tienda_de(donosti, '00000000-0000-4000-c000-000000000004', pg_temp.a('2026-12-17', '10:55'));
  r := motor.crear_pedido_tienda_de(donosti, gen_random_uuid(), 'Leire', '[{"producto": "BZ1", "formato": "4g", "cantidad": 1}]',
                                    pg_temp.a('2026-12-17', '11:10'));
  perform pg_temp.comprobar('Donosti también apunta pedidos: van en el siguiente envío a Gipuzkoa',
    exists (select 1 from jsonb_array_elements(r -> 'pedidos') x
             where x ->> 'cliente' = 'Leire' and x ->> 'estado_texto' like 'Va en el próximo envío a Donosti%' and x ->> 'va_en' = 'envio')
    and motor.aviso_pedidos_envio() = 'Hay 1 pedido de cliente esperando envío a Gipuzkoa', r -> 'pedidos' #>> '{}');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Durango (cuando abra) y permisos
-- ---------------------------------------------------------------------------
update public.centros_trabajo set activo = true where codigo = 'DURANGO';
select pg_temp.comprobar('Durango, al abrir, se elige y va en su envío (configuración, no código)',
  exists (select 1 from jsonb_array_elements(motor.tiendas_pedido_json()) x where x ->> 'codigo' = 'DURANGO' and x ->> 'va_en' = 'envio')
  and (select destino_id from motor.destino_pedido(pg_temp.d('DURANGO'))) = pg_temp.d('DURANGO'));
update public.centros_trabajo set activo = false where codigo = 'DURANGO';

select pg_temp.como('00000000-0000-4000-b000-000000000001');  -- Basauri
select pg_temp.comprobar('La tienda usa crear_pedido_tienda, pero no las funciones del almacén',
  public.crear_pedido_tienda(gen_random_uuid(), '', '[]') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
  and public.pedidos_cliente_abiertos() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.comprobar('Las funciones del servidor de pedidos siguen cerradas para una tienda',
  public.servidor_preparar_pedido('00000000-0000-4000-b000-000000000001', gen_random_uuid(), 'tienda', pg_temp.d('BASAURI'))
    -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario y Administración no usan crear_pedido_tienda (tienen «Pedido de cliente»)',
  public.crear_pedido_tienda(gen_random_uuid(), 'X', '[]') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.crear_pedido_tienda(uuid, text, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.crear_pedido_tienda_de(uuid, uuid, text, jsonb, timestamptz)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
