-- Prueba 29 · Tiendas, segunda parte (Tarea 28; ESTADO_DEL_SISTEMA.md E2-8).
-- El jueves 17/12/2026: «Revisa las muestras» (Basauri y la franquicia Donosti), material de
-- tienda y el cierre de caja. El viernes 18/12/2026: las peticiones salen ya puestas al preparar
-- el reparto y quedan atendidas al guardarlo; «Recibe la bolsa» al salir el reparto, con lo que
-- trae y el efectivo del cierre de ayer; por dónde va el reparto; «Coloca y apunta la reposición»
-- («todo bien» o «Falta algo», que llega a Administración). Permisos. Y que el almacén sigue
-- igual: preparar, bolsas, salida y peticiones de siempre.
-- Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas en pruebas. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
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
create function pg_temp.tarea(r jsonb, p_clave text) returns jsonb language sql as $$
  select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' like p_clave limit 1 $$;
create function pg_temp.punto(r jsonb, p_clave text, p_n integer) returns jsonb language sql as $$
  select pg_temp.tarea(r, p_clave) -> 'puntos' -> (p_n - 1) $$;
create function pg_temp.texto_pet(r jsonb) returns text language sql as $$
  select string_agg(x ->> 'texto' || ' [' || (x ->> 'destino') || ']', ' | ' order by x ->> 'texto') from jsonb_array_elements(r -> 'peticiones') x $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.bilbao@osasun.invalid", "nombre": "Bilbao", "rol": "tienda", "centro": "BILBAO"},
  {"correo": "tienda.donosti@osasun.invalid", "nombre": "Donosti", "rol": "tienda", "centro": "DONOSTI"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.bilbao@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000003', 'tienda.donosti@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000004', 'tienda.portu@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('BILBAO'), 'Leire Prueba', 'siempre', 'manana'),
  ('00000000-0000-4000-c000-000000000003', pg_temp.d('BILBAO'), 'Unai Prueba', 'siempre', 'tarde'),
  ('00000000-0000-4000-c000-000000000004', pg_temp.d('DONOSTI'), 'Nora Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000005', pg_temp.d('PORTU'), 'Iker Prueba', 'siempre', null);
-- La última lectura de la hoja (la lista de productos de las muestras).
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-17 08:00+01', 'stock', true, '{
  "productos": [
    {"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}, {"formato": "10g", "almacen": "3"}]},
    {"nombre": "BZ1", "orden": 2, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "5"}]},
    {"nombre": "CREMA", "orden": 3, "conTiendas": true, "formatos": []}],
  "categorias": {"V2": "Indoor", "BZ1": "Invernadero"}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');

-- El reparto del viernes, como lo guarda la función del servidor guardar_reparto: Bilbao, Basauri
-- y Portugalete (en el orden de las paradas: 1, 2 y 3).
create function pg_temp.guardar(p_jornada uuid, p_huella text, p_ahora timestamptz)
returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, 'reparto',
    E'REPARTO 18/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n\nBASAURI\n3x V2 4g\n1x BZ1 4g\n\nPORTU\n2x V2 10g',
    p_huella, '2026-12-18', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 18/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 7, 'texto', 'BASAURI', 'clase', 'tienda', 'destino_id', pg_temp.d('BASAURI')),
      jsonb_build_object('num', 8, 'texto', '3x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 3, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 9, 'texto', '1x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 1, 'producto', 'BZ1', 'formato', '4g'),
      jsonb_build_object('num', 11, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 12, 'texto', '2x V2 10g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '10g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 5, 'en_almacen', 5, 'faltan', 0, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'V2', 'formato', '10g', 'pedido', 2, 'en_almacen', 2, 'faltan', 0, 'aviso', null, 'orden', 2),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 1, 'en_almacen', 5, 'faltan', 0, 'aviso', null, 'orden', 3)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1))),
      jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 3, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 1, 'orden', 3))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '10g', 'cantidad', 2, 'orden', 2)))),
    true, p_ahora) $$;

-- ---------------------------------------------------------------------------
-- Jueves 17/12: muestras, material y cierre de caja
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  r jsonb;
  t jsonb;
  v_caja uuid;
begin
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-17', '10:55'));
  perform motor.empezar_turno_tienda_de(donosti, '00000000-0000-4000-c000-000000000004', pg_temp.a('2026-12-17', '10:55'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-17', '11:05'));
  t := pg_temp.tarea(r, 'revisa_muestras');
  perform pg_temp.comprobar('Jueves por la mañana: «Revisa las muestras» a las 11:00, también en la franquicia (Donosti)',
    t ->> 'hora' = '11:00' and t ->> 'tipo' = 'muestras' and (t ->> 'se_puede_marcar')::boolean
    and pg_temp.tarea(motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-17', '11:05')), 'revisa_muestras') ->> 'hora' = '11:00', r::text);
  perform motor.generar_jornada(bilbao, '2026-12-24');
  perform pg_temp.comprobar('Bilbao alterna: semana 51 (impar), por la tarde (16:30); semana 52 (par), por la mañana (11:00)',
    pg_temp.tarea(motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-17', '16:35')), 'revisa_muestras') ->> 'hora' = '16:30'
    and (select motor.hora_texto(t2.disponible_desde) from public.tareas t2
          where t2.jornada_id = motor.generar_jornada(bilbao, '2026-12-24') and t2.clave = 'revisa_muestras') = '11:00');
  perform pg_temp.comprobar('La lista para las muestras: cada producto una vez (sin formato), de la última lectura de la hoja, con su categoría',
    (select string_agg(x ->> 'clave' || ':' || (x ->> 'categoria'), ' ' order by n)
       from jsonb_array_elements(motor.productos_tienda_de() -> 'productos') with ordinality a(x, n))
    = 'V2:Indoor BZ1:Invernadero CREMA:Otros', (motor.productos_tienda_de())::text);
  r := motor.revisar_muestras_de(basauri, (t ->> 'id')::uuid, '[{"producto": "XX", "cantidad": 1}]', pg_temp.a('2026-12-17', '11:06'));
  perform pg_temp.comprobar('Muestras: solo de la lista', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.revisar_muestras_de(basauri, (t ->> 'id')::uuid, '[{"producto": "v2", "cantidad": 0}]', pg_temp.a('2026-12-17', '11:06'));
  perform pg_temp.comprobar('Muestras: la cantidad, de 1 a 99', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.revisar_muestras_de(basauri, (t ->> 'id')::uuid, '[{"producto": "v2", "cantidad": 2}]', pg_temp.a('2026-12-17', '11:07'));
  t := pg_temp.tarea(r, 'revisa_muestras');
  perform pg_temp.comprobar('Elegidas: la tarea queda hecha por quien está y la muestra, pendiente para el siguiente reparto',
    t ->> 'estado' = 'hecha' and t ->> 'hecha_por' = 'Ane Prueba'
    and t -> 'muestras' = '[{"producto": "V2", "formato": "", "cantidad": 2, "estado": "pendiente"}]'::jsonb
    and r -> 'peticiones' -> 0 ->> 'texto' = 'Muestra: V2 x2'
    and r -> 'peticiones' -> 0 ->> 'estado_texto' = 'Pendiente: irá en el siguiente reparto', r::text);

  r := motor.revisar_muestras_de(donosti, (pg_temp.tarea(motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-17', '11:10')), 'revisa_muestras') ->> 'id')::uuid,
                                 '[{"producto": "BZ1"}]', pg_temp.a('2026-12-17', '11:10'));
  perform pg_temp.comprobar('Franquicia: su muestra (sin cantidad = 1) va en el envío a Gipuzkoa, con el nombre de la tienda delante',
    r -> 'peticiones' -> 0 ->> 'texto' = 'Donosti · Muestra: BZ1'
    and r -> 'peticiones' -> 0 ->> 'estado_texto' = 'Pendiente: irá en el siguiente envío', r::text);

  r := motor.pedir_material_de(basauri, '00000000-0000-4000-d000-000000000001', '  Rollos  de TPV ', pg_temp.a('2026-12-17', '18:00'));
  r := motor.pedir_material_de(basauri, '00000000-0000-4000-d000-000000000001', 'Rollos de TPV', pg_temp.a('2026-12-17', '18:01'));
  perform pg_temp.comprobar('Material de tienda: en cualquier momento; repetir la misma petición no la duplica',
    (select count(*) from public.peticiones_tienda where centro_id = pg_temp.d('BASAURI') and tipo = 'material') = 1
    and (select texto from public.peticiones_tienda where centro_id = pg_temp.d('BASAURI') and tipo = 'material') = 'Material: Rollos de TPV'
    and (r ->> 'pedir_material')::boolean, r::text);
  r := motor.pedir_material_de(donosti, gen_random_uuid(), 'Bolsas', pg_temp.a('2026-12-17', '18:00'));
  perform pg_temp.comprobar('La franquicia no pide material (en esta tarea, solo las muestras)',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and not (motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-17', '18:00')) ->> 'pedir_material')::boolean, r::text);

  -- Cierre del día con el cierre de caja
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-17', '20:25'));
  t := pg_temp.tarea(r, 'cierre_dia');
  v_caja := (select (x ->> 'id')::uuid from jsonb_array_elements(t -> 'puntos') x where x ->> 'pide' = 'cierre_caja');
  perform pg_temp.comprobar('«Cierre del día» con el cierre de caja, el primero de los puntos de dinero',
    (select string_agg(coalesce(x ->> 'pide', '-'), ' ' order by n) from jsonb_array_elements(t -> 'puntos') with ordinality a(x, n))
      = '- - cierre_caja - -'
    and t -> 'puntos' -> 2 ->> 'texto' = 'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo', t::text);
  r := motor.marcar_punto_de(basauri, v_caja, pg_temp.a('2026-12-17', '20:25'));
  perform pg_temp.comprobar('El cierre de caja no se marca con un toque: pide sus datos',
    r -> 'error' ->> 'codigo' = 'FALTAN_DATOS' and r -> 'error' ->> 'pide' = 'cierre_caja', r::text);
  r := motor.cerrar_caja_de(basauri, v_caja, 412.30, 37, -1, 23, pg_temp.a('2026-12-17', '20:26'));
  perform pg_temp.comprobar('Cierre de caja: números válidos', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.cerrar_caja_de(basauri, v_caja, 412.30, 37, 85.505, 23, pg_temp.a('2026-12-17', '20:26'));
  perform pg_temp.comprobar('Cierre de caja: euros con dos decimales como máximo', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.cerrar_caja_de(basauri, v_caja, 412.30, 37, 85.50, 23, pg_temp.a('2026-12-17', '20:27'));
  perform pg_temp.comprobar('Guardado por tienda y día (Z, nº de ventas, efectivo y Glovo), y el punto hecho por quien está',
    (select z = 412.30 and ventas = 37 and efectivo = 85.50 and glovo = 23 and nombre = 'Ane Prueba'
       from public.cierres_caja where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-17')
    and (pg_temp.punto(r, 'cierre_dia', 3) ->> 'hecho')::boolean
    and pg_temp.punto(r, 'cierre_dia', 3) -> 'datos' = '{"z": 412.30, "ventas": 37, "efectivo": 85.50, "glovo": 23}'::jsonb, r::text);
  r := motor.cerrar_caja_de(basauri, v_caja, 412.30, 38, 85.50, 23, pg_temp.a('2026-12-17', '20:28'));
  perform pg_temp.comprobar('Se puede corregir mientras el cierre del día siga abierto (una fila por día)',
    (select count(*) = 1 and min(ventas) = 38 from public.cierres_caja where centro_id = pg_temp.d('BASAURI')), r::text);

  -- Bilbao: su cierre de caja (para el efectivo de mañana)
  perform motor.empezar_turno_tienda_de(bilbao, '00000000-0000-4000-c000-000000000003', pg_temp.a('2026-12-17', '16:25'));
  r := motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-17', '20:25'));
  r := motor.cerrar_caja_de(bilbao, (select (x ->> 'id')::uuid from jsonb_array_elements(pg_temp.tarea(r, 'cierre_dia') -> 'puntos') x
                                     where x ->> 'pide' = 'cierre_caja'), 500, 40, 100, 0, pg_temp.a('2026-12-17', '20:26'));
  perform pg_temp.comprobar('Bilbao también guarda su cierre de caja', r -> 'error' is null, r::text);

  r := motor.cierres_caja_de('2026-12-17', '2026-12-17', null);
  perform pg_temp.comprobar('Administración: los cierres de caja (función de lectura para su panel)',
    (select string_agg(x ->> 'tienda' || ' ' || (x ->> 'z') || ' ' || (x ->> 'efectivo') || ' ' || (x ->> 'por'), ', ' order by x ->> 'tienda')
       from jsonb_array_elements(r -> 'cierres') x) = 'Basauri 412.30 85.50 Ane Prueba, Bilbao 500.00 100.00 Unai Prueba', r::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Viernes 18/12: el reparto, la bolsa y la reposición
-- ---------------------------------------------------------------------------
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-18');
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada(op, '2026-12-18');
  r jsonb;
  t jsonb;
  v_rep uuid;
  v_bolsas uuid;
  v_lista jsonb;
  v_pet jsonb;
  v_salida timestamptz;
  v_despues timestamptz;
  v_ped uuid;
begin
  -- Preparar el reparto: las peticiones de las tiendas, ya puestas.
  v_pet := motor.peticiones_pendientes_de('reparto');
  perform pg_temp.comprobar('Al preparar el reparto: las peticiones pendientes de las tiendas que van en él, con su línea',
    pg_temp.texto_pet(v_pet) = 'Material: Rollos de TPV [Basauri] | Muestra: V2 x2 [Basauri]', v_pet::text);
  r := motor.peticiones_pendientes_de('envio');
  perform pg_temp.comprobar('Y al preparar el envío, las de las franquicias, en la casilla de Gipuzkoa',
    pg_temp.texto_pet(r) = 'Donosti · Muestra: BZ1 [Gipuzkoa (envío a Rentería)]', r::text);

  r := pg_temp.guardar(j, 'h29-a', pg_temp.a('2026-12-18', '08:40'));
  v_rep := (r ->> 'reparto_id')::uuid;
  v_bolsas := (r -> 'tareas' ->> 'bolsas')::uuid;
  insert into public.pedidos_cliente (id_cliente, cliente, entrega, destino_id, lineas, fecha_objetivo, jornada_id, reparto_id,
                                      registrado_por, registrado_en)
  values (gen_random_uuid(), 'Cliente Prueba', 'tienda', pg_temp.d('PORTU'), '[{"producto": "BZ1", "formato": "4g", "cantidad": 1}]',
          '2026-12-18', j, v_rep, admin, pg_temp.a('2026-12-18', '08:30'))
  returning id into v_ped;
  -- Su bolsa aparte, dentro de la tarea de bolsas (como hace servidor_asignar_pedidos).
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
  values (v_bolsas, 'caja_bolsa', 'pedido:' || v_ped, 'BZ1', '4g', pg_temp.d('PORTU'), 1, 90);
  -- Lo que pone Administración en las casillas: lo de siempre (Bilbao) y lo que ha salido ya puesto.
  v_lista := jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'texto', 'Cajas vacías'))
             || (select jsonb_agg(jsonb_build_object('destino_id', x -> 'destino_id', 'texto', x -> 'texto')) from jsonb_array_elements(v_pet -> 'peticiones') x);
  r := public.servidor_guardar_peticiones(admin, v_rep, v_lista, pg_temp.a('2026-12-18', '08:41'));
  perform pg_temp.comprobar('Almacén igual: en las bolsas, las peticiones guardadas, una a una (también las de la tienda)',
    (select string_agg(e.producto || '@' || c.codigo, ', ' order by c.codigo, e.producto)
       from public.tarea_elementos e join public.centros_trabajo c on c.id = e.destino_id
      where e.tarea_id = v_bolsas and e.tipo = 'peticion')
      = 'Material: Rollos de TPV@BASAURI, Muestra: V2 x2@BASAURI, Cajas vacías@BILBAO'
    and (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'caja_bolsa' and lote = 'reparto') = 4, r::text);
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '08:45'));
  perform pg_temp.comprobar('Al guardarlo quedan atendidas y la tienda lo ve («Va en el reparto de hoy»)',
    (select string_agg(x ->> 'detalle' || ': ' || (x ->> 'estado_texto'), ' | ' order by x ->> 'detalle') from jsonb_array_elements(r -> 'peticiones') x)
      = 'Rollos de TPV: Va en el reparto de hoy | V2 x2: Va en el reparto de hoy'
    and jsonb_array_length(motor.peticiones_pendientes_de('reparto') -> 'peticiones') = 0, r::text);
  perform public.servidor_guardar_peticiones(admin, v_rep, v_lista - 2, pg_temp.a('2026-12-18', '08:42'));
  perform pg_temp.comprobar('Si Administración la quita de la casilla, vuelve a pendiente (irá en el siguiente)',
    (select estado from public.peticiones_tienda where tipo = 'material') = 'pendiente'
    and (select estado from public.peticiones_tienda where tipo = 'muestra' and centro_id = pg_temp.d('BASAURI')) = 'atendida');
  perform public.servidor_guardar_peticiones(admin, v_rep, v_lista, pg_temp.a('2026-12-18', '08:43'));
  perform pg_temp.comprobar('Y si la vuelve a poner, atendida otra vez',
    (select count(*) from public.peticiones_tienda where centro_id = pg_temp.d('BASAURI') and estado = 'atendida' and reparto_id = v_rep) = 2);
  r := motor.descartar_peticion_tienda_de(admin, (select id from public.peticiones_tienda where tipo = 'material'), 'x', pg_temp.a('2026-12-18', '08:44'));
  perform pg_temp.comprobar('Una atendida ya no se descarta', r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);
  r := motor.descartar_peticion_tienda_de(admin, (select id from public.peticiones_tienda where centro_id = pg_temp.d('DONOSTI')),
                                         repeat('x', 121), pg_temp.a('2026-12-18', '08:44'));
  perform pg_temp.comprobar('El motivo de «No va», en una línea (120 letras)', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.descartar_peticion_tienda_de(admin, (select id from public.peticiones_tienda where centro_id = pg_temp.d('DONOSTI')),
                                         '  ', pg_temp.a('2026-12-18', '08:44'));
  perform pg_temp.comprobar('«No va» sin motivo: la tienda ve «No va: lo ha quitado Administración» y ya no sale al preparar',
    r -> 'peticion' ->> 'estado_texto' = 'No va: lo ha quitado Administración'
    and jsonb_array_length(motor.peticiones_pendientes_de('envio') -> 'peticiones') = 0, r::text);

  -- Antes de salir
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-18', '10:30'));
  perform motor.empezar_turno_tienda_de(portu, '00000000-0000-4000-c000-000000000005', pg_temp.a('2026-12-18', '10:30'));
  perform motor.empezar_turno_tienda_de(bilbao, '00000000-0000-4000-c000-000000000002', pg_temp.a('2026-12-18', '10:30'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '10:40'));
  perform pg_temp.comprobar('Antes de salir: sin «Recibe la bolsa»; el reparto, sin salir, con su parada (2 de 3)',
    pg_temp.tarea(r, 'recibe_bolsa') is null and not (r -> 'reparto' ->> 'salido')::boolean and r -> 'reparto' ->> 'texto' is null
    and (r -> 'reparto' ->> 'tu_parada')::int = 2 and (r -> 'reparto' ->> 'total')::int = 3, r::text);
  perform pg_temp.comprobar('Una tienda sin parada hoy (Donosti) no ve el reparto',
    motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-18', '10:40')) -> 'reparto' = 'null'::jsonb);

  -- El operario hace sus bolsas y sale como siempre (a las 10:50).
  -- Lo que marca como metido en cada bolsa (todo, menos 1 BZ1 de Basauri).
  update public.tarea_elementos e set estado = 'hecho', cantidad_hecha = e.cantidad, terminado_en = pg_temp.a('2026-12-18', '10:39')
   where e.tarea_id = v_bolsas and e.tipo in ('caja_bolsa', 'peticion')
     and not (e.destino_id = pg_temp.d('BASAURI') and e.producto = 'BZ1');
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('2026-12-18', '09:00'), terminada_en = pg_temp.a('2026-12-18', '10:40')
   where jornada_id = j and clave in ('produccion_reparto', 'bolsas');
  -- Si saliera Administración (sin «Salida del reparto»): a la hora de salida, con las bolsas listas.
  begin
    update public.jornadas set sale = 'administracion' where id = j;
    update public.tareas set retirada_por_condicion = true, estado = 'cancelada' where jornada_id = j and clave = 'salida_reparto';
    v_salida := motor.salida_reparto_en(j, pg_temp.a('2026-12-18', '10:44'));
    v_despues := motor.salida_reparto_en(j, pg_temp.a('2026-12-18', '10:46'));
    raise exception 'deshacer';
  exception when raise_exception then null;
  end;
  perform pg_temp.comprobar('Si sale Administración: ha salido a la hora de salida (10:45), con las bolsas listas',
    v_salida is null and motor.hora_texto(v_despues) = '10:45'
    and motor.salida_reparto_en(j, pg_temp.a('2026-12-18', '10:46')) is null,  -- deshecho: sale el operario y aún no ha salido
    coalesce(v_salida::text, '-') || ' ' || coalesce(v_despues::text, '-'));
  update public.tareas set estado = 'en_curso', iniciada_en = pg_temp.a('2026-12-18', '10:50')
   where jornada_id = j and clave = 'salida_reparto';
  insert into _v values ('tarea_activa', motor.tarea_activa_de(op, pg_temp.a('2026-12-18', '11:30')));
  insert into _v values ('tareas_almacen', (select jsonb_agg(jsonb_build_array(clave, estado) order by clave) from public.tareas where jornada_id = j));

  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '10:55'));
  t := pg_temp.tarea(r, 'recibe_bolsa');
  perform pg_temp.comprobar('Al salir el reparto: «Recibe la bolsa» con la hora de salida y sus dos puntos',
    t ->> 'hora' = '10:50' and t ->> 'porque' like 'El reparto ha salido a las 10:50.%'
    and pg_temp.punto(r, 'recibe_bolsa', 1) ->> 'texto' = 'Bolsa recibida'
    and pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'texto' = 'Bolsa de ayer entregada con 85,50 € en efectivo'
    and pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'pide' = 'efectivo'
    and (pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'efectivo_esperado')::numeric = 85.50, t::text);
  perform pg_temp.comprobar('Enseña lo que trae la bolsa: lo marcado como metido (el BZ1 sin marcar no aparece)',
    (select string_agg(x ->> 'cantidad' || 'x ' || (x ->> 'producto') || ' ' || (x ->> 'formato'), ', ') from jsonb_array_elements(t -> 'bolsa' -> 'productos') x)
      = '3x V2 4g'
    and (select string_agg(x ->> 'texto', ', ') from jsonb_array_elements(t -> 'bolsa' -> 'peticiones') x) = 'Muestra: V2 x2, Material: Rollos de TPV'
    and t -> 'bolsa' -> 'pedidos' = '[]'::jsonb and t -> 'bolsa' ->> 'salida' = '10:50', t::text);
  perform pg_temp.comprobar('Todas las tiendas con parada: «Ha salido a las 10:50»',
    r -> 'reparto' ->> 'texto' = 'Ha salido a las 10:50'
    and motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '10:55')) -> 'reparto' ->> 'texto' = 'Ha salido a las 10:50', r::text);
  r := motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '10:56'));
  perform pg_temp.comprobar('Portugalete: su pedido de cliente en la bolsa y, sin cierre de caja anterior, pide la cantidad',
    pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'pedidos' -> 0 ->> 'cliente' = 'Cliente Prueba'
    and pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'pedidos' -> 0 -> 'lineas' = '[{"producto": "BZ1", "formato": "4g", "cantidad": 1}]'::jsonb
    and pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'texto' = 'Bolsa de ayer entregada: di cuánto efectivo'
    and pg_temp.punto(r, 'recibe_bolsa', 2) -> 'efectivo_esperado' = 'null'::jsonb, r::text);
  perform pg_temp.comprobar('La franquicia no tiene «Recibe la bolsa»',
    pg_temp.tarea(motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-18', '11:00')), 'recibe_bolsa') is null);
  perform pg_temp.comprobar('Repetir no crea otra («Recibe la bolsa», una al día)',
    (select count(*) from public.tareas t2 join public.jornadas j2 on j2.id = t2.jornada_id
      where j2.persona_id = basauri and j2.fecha = '2026-12-18' and t2.clave = 'recibe_bolsa') = 1
    and (select count(*) from public.bolsas_tienda where fecha = '2026-12-18') = 2);  -- Bilbao aún no ha abierto la tableta

  -- Bolsa recibida en Basauri
  r := motor.marcar_punto_de(basauri, (pg_temp.punto(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '11:20')), 'recibe_bolsa', 1) ->> 'id')::uuid,
                             pg_temp.a('2026-12-18', '11:20'));
  perform pg_temp.comprobar('«Bolsa recibida»: la bolsa consta como recibida a esa hora, por quien está',
    (select recibida_en = pg_temp.a('2026-12-18', '11:20') and recibida_por = 'Ane Prueba' from public.bolsas_tienda
      where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-18')
    and pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' ->> 'recibida_a_las' = '11:20', r::text);
  r := motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '11:25'));
  perform pg_temp.comprobar('Las demás ven por dónde va: «Ha pasado por Basauri a las 11:20 (parada 2 de 3)»',
    r -> 'reparto' ->> 'texto' = 'Ha pasado por Basauri a las 11:20 (parada 2 de 3)'
    and r -> 'reparto' -> 'paradas' -> 1 ->> 'pasado_a_las' = '11:20' and r -> 'reparto' -> 'paradas' -> 0 -> 'pasado_a_las' = 'null'::jsonb
    and motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-18', '11:25')) -> 'reparto' ->> 'texto' = 'Ha pasado por Basauri a las 11:20 (parada 2 de 3)', r::text);
  perform pg_temp.comprobar('La reposición no sale hasta terminar «Recibe la bolsa»',
    pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '11:21')), 'reposicion') is null);

  -- El efectivo de ayer
  r := motor.marcar_punto_de(basauri, (pg_temp.punto(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '11:22')), 'recibe_bolsa', 2) ->> 'id')::uuid,
                             pg_temp.a('2026-12-18', '11:22'));
  t := pg_temp.tarea(r, 'recibe_bolsa');
  perform pg_temp.comprobar('Con un toque, el efectivo del cierre de ayer (85,50 €): «Recibe la bolsa» hecha',
    t ->> 'estado' = 'hecha' and t ->> 'hecha_por' = 'Ane Prueba'
    and (t -> 'bolsa' -> 'efectivo' ->> 'entregado')::numeric = 85.50 and t -> 'bolsa' -> 'efectivo' -> 'motivo' = 'null'::jsonb, t::text);
  t := pg_temp.tarea(r, 'reposicion');
  perform pg_temp.comprobar('Después, «Coloca y apunta la reposición», con la lista de lo que tenía que llegar',
    t ->> 'hora' = '11:22' and t ->> 'tipo' = 'reposicion'
    and jsonb_array_length(t -> 'bolsa' -> 'productos') = 1 and jsonb_array_length(t -> 'bolsa' -> 'peticiones') = 2, t::text);

  r := motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '11:40'));
  perform motor.marcar_punto_de(portu, (pg_temp.punto(r, 'recibe_bolsa', 1) ->> 'id')::uuid, pg_temp.a('2026-12-18', '11:40'));
  r := motor.marcar_punto_de(portu, (pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'id')::uuid, pg_temp.a('2026-12-18', '11:41'));
  perform pg_temp.comprobar('Sin cierre anterior, un toque no basta: pide la cantidad',
    r -> 'error' ->> 'codigo' = 'FALTAN_DATOS' and r -> 'error' ->> 'pide' = 'efectivo', r::text);
  r := motor.entregar_efectivo_de(portu, (pg_temp.punto(motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '11:41')), 'recibe_bolsa', 2) ->> 'id')::uuid,
                                  60, null, pg_temp.a('2026-12-18', '11:42'));
  perform pg_temp.comprobar('Con la cantidad, hecha',
    pg_temp.tarea(r, 'recibe_bolsa') ->> 'estado' = 'hecha'
    and (pg_temp.tarea(r, 'recibe_bolsa') -> 'bolsa' -> 'efectivo' ->> 'entregado')::numeric = 60, r::text);

  r := motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-18', '12:10'));
  perform motor.marcar_punto_de(bilbao, (pg_temp.punto(r, 'recibe_bolsa', 1) ->> 'id')::uuid, pg_temp.a('2026-12-18', '12:10'));
  r := motor.entregar_efectivo_de(bilbao, (pg_temp.punto(r, 'recibe_bolsa', 2) ->> 'id')::uuid, 120, null, pg_temp.a('2026-12-18', '12:11'));
  perform pg_temp.comprobar('Otra cantidad que la del cierre (100 €): di por qué',
    r -> 'error' ->> 'codigo' = 'MOTIVO_OBLIGATORIO', r::text);
  r := motor.entregar_efectivo_de(bilbao, (pg_temp.punto(motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-18', '12:11')), 'recibe_bolsa', 2) ->> 'id')::uuid,
                                  120, 'Monedas para cambio', pg_temp.a('2026-12-18', '12:12'));
  perform pg_temp.comprobar('Con el porqué (por ejemplo, monedas para cambio), queda apuntado',
    (select efectivo_esperado = 100 and efectivo_entregado = 120 and efectivo_motivo = 'Monedas para cambio' from public.bolsas_tienda
      where centro_id = pg_temp.d('BILBAO') and fecha = '2026-12-18')
    and r -> 'reparto' ->> 'texto' = 'Ha pasado por Bilbao a las 12:10 (parada 1 de 3)', r::text);

  -- La reposición
  t := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '12:30')), 'reposicion');
  r := motor.apuntar_reposicion_de(basauri, (t ->> 'id')::uuid, '[{"clave": "producto:V2|10g", "cantidad": 1}]', null, pg_temp.a('2026-12-18', '12:30'));
  perform pg_temp.comprobar('«Falta algo»: solo de la lista', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.apuntar_reposicion_de(basauri, (t ->> 'id')::uuid, '[{"clave": "producto:V2|4g", "cantidad": 4}]', null, pg_temp.a('2026-12-18', '12:30'));
  perform pg_temp.comprobar('«Falta algo»: como mucho lo que traía', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.apuntar_reposicion_de(basauri, (t ->> 'id')::uuid,
                                   '[{"clave": "producto:V2|4g", "cantidad": 1}, {"clave": "peticion:Material: Rollos de TPV"}]',
                                   'La caja venía abierta', pg_temp.a('2026-12-18', '12:31'));
  perform pg_temp.comprobar('«Falta algo»: la tarea queda hecha y lo que falta, apuntado',
    pg_temp.tarea(r, 'reposicion') ->> 'estado' = 'hecha'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' ->> 'resultado' = 'falta'
    and jsonb_array_length(pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' -> 'faltan') = 2, r::text);
  r := motor.incidencias_tiendas_de(pg_temp.a('2026-12-18', '12:35'));
  perform pg_temp.comprobar('Llega a Administración como incidencia abierta, con lo que falta (Tarea 39: «Bolsa del reparto del …. Falta: …»)',
    jsonb_array_length(r -> 'incidencias') = 1 and r -> 'incidencias' -> 0 ->> 'tienda' = 'Basauri'
    and r -> 'incidencias' -> 0 ->> 'opcion' = 'falta_reposicion' and r -> 'incidencias' -> 0 ->> 'estado' = 'abierta'
    and r -> 'incidencias' -> 0 ->> 'texto' = 'Bolsa del reparto del 18/12. Falta: 1x V2 4g; Material: Rollos de TPV. La caja venía abierta (Ane Prueba)', r::text);
  perform pg_temp.comprobar('A Eder no le sale nada: ni incidencia ni tarea nueva, y su pantalla igual',
    not exists (select 1 from public.incidencias where persona_id = op and opcion = 'falta_reposicion')
    and (select jsonb_agg(jsonb_build_array(clave, estado) order by clave) from public.tareas where jornada_id = j) = (select v from _v where k = 'tareas_almacen')
    and motor.tarea_activa_de(op, pg_temp.a('2026-12-18', '11:30')) = (select v from _v where k = 'tarea_activa')
    and jsonb_array_length(motor.estado_actual_de(pg_temp.a('2026-12-18', '12:35')) -> 'incidencias_abiertas') = 0);
  r := motor.cerrar_incidencia_tienda_de(admin, (r -> 'incidencias' -> 0 ->> 'id')::uuid, 'Va en el reparto del lunes', pg_temp.a('2026-12-18', '13:00'));
  perform pg_temp.comprobar('Administración la cierra al resolverla',
    r -> 'incidencias' -> 0 ->> 'estado' = 'cerrada' and r -> 'incidencias' -> 0 ->> 'nota' = 'Va en el reparto del lunes', r::text);

  t := pg_temp.tarea(motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '12:40')), 'reposicion');
  r := motor.apuntar_reposicion_de(portu, (t ->> 'id')::uuid, null, null, pg_temp.a('2026-12-18', '12:40'));
  perform pg_temp.comprobar('«Reposición metida, todo bien»: hecha, sin incidencia',
    pg_temp.tarea(r, 'reposicion') ->> 'estado' = 'hecha'
    and pg_temp.tarea(r, 'reposicion') -> 'bolsa' -> 'reposicion' ->> 'resultado' = 'bien'
    and jsonb_array_length(motor.incidencias_tiendas_de(pg_temp.a('2026-12-18', '12:41')) -> 'incidencias') = 1, r::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-b000-000000000004');  -- Portugalete
select pg_temp.comprobar('La tienda no usa lo del almacén ni lo de Administración de esta tarea',
  public.peticiones_tiendas_pendientes() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.cierres_caja() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.incidencias_tiendas() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.descartar_peticion_tienda(gen_random_uuid(), 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
select pg_temp.comprobar('Tablas: ve su bolsa, su cierre de caja y sus peticiones; no las de otra tienda',
  (select count(*) from public.bolsas_tienda where fecha = '2026-12-18') = 1
  and (select count(*) from public.cierres_caja where fecha = '2026-12-17') = 0
  and (select count(*) from public.peticiones_tienda) = 0
  and jsonb_array_length(public.productos_tienda() -> 'productos') = 3);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario ve las peticiones pendientes para preparar; no usa lo de la tienda ni los cierres de caja',
  public.peticiones_tiendas_pendientes('reparto') ? 'peticiones'
  and public.cierres_caja() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.productos_tienda() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.pedir_material(gen_random_uuid(), 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and (select count(*) from public.bolsas_tienda) = 0 and (select count(*) from public.cierres_caja) = 0);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('Administración: peticiones, cierres de caja e incidencias de las tiendas',
  public.peticiones_tiendas_pendientes('envio') ? 'peticiones'
  and jsonb_array_length(public.cierres_caja('2026-12-17', '2026-12-17') -> 'cierres') = 2
  and public.incidencias_tiendas() ? 'incidencias'
  and (select count(*) from public.bolsas_tienda where fecha = '2026-12-18') = 3);
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.cerrar_caja(uuid, numeric, integer, numeric, numeric)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.peticiones_tiendas_pendientes(text)', 'EXECUTE')
  and not has_table_privilege('anon', 'public.cierres_caja', 'SELECT'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
