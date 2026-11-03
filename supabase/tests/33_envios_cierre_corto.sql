-- Prueba 33 · Franquicias y Durango: «Envíos» y cierre de caja corto (Tarea 30b; ESTADO_DEL_SISTEMA.md E2-8
-- v1.50). El miércoles 16/12/2026 se prepara el envío a Gipuzkoa (17:00); el jueves 17/12, Rentería lo ve en
-- «Envíos» con lo marcado y lo confirma («Falta algo» → Administración; desaparece en el momento); el jueves se
-- prepara otro y el viernes lo confirma con «Todo bien»; el viernes, con el reparto y saliendo Administración,
-- otro que se ve el sábado. Donosti no tiene «Envíos» (el envío a Gipuzkoa va entero a Rentería). Cierre de
-- caja corto en las franquicias (20:20; el sábado, 13:20). Las propias y el almacén, igual.
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
create function pg_temp.dia(p_persona uuid, p_fecha date) returns text language sql as $$
  select string_agg(t.clave || '@' || motor.hora_texto(t.disponible_desde), ' ' order by t.disponible_desde, t.orden)
    from public.tareas t where t.jornada_id = motor.generar_jornada(p_persona, p_fecha) $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;
-- Un envío a Gipuzkoa como lo guarda la función del servidor guardar_reparto: 4x V2 4g y 1x BZ1 4g.
create function pg_temp.envio(p_fecha date, p_huella text) returns jsonb language sql as $$
  select public.servidor_guardar_reparto('00000000-0000-4000-a000-000000000002',
    motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_fecha), 'envio',
    E'ENVÍO\n\nGIPUZKOA\n4x V2 4g\n1x BZ1 4g', p_huella, p_fecha, null, null,
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

-- ---------------------------------------------------------------------------
-- Miércoles 16/12: el envío a Gipuzkoa se guarda y se prepara (se mete en la caja)
-- ---------------------------------------------------------------------------
do $$
declare
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  r jsonb;
  v_env uuid;
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-16');
begin
  r := pg_temp.envio('2026-12-16', 'h33-a');
  v_env := (r -> 'tareas' ->> 'bolsas')::uuid;
  perform public.servidor_guardar_peticiones('00000000-0000-4000-a000-000000000002', (r ->> 'reparto_id')::uuid,
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'), 'texto', 'Donosti · Muestra: V2')), pg_temp.a('2026-12-16', '15:41'));
  -- El operario mete en la caja 3 de las 4 V2 y la petición; la BZ1 no la marca.
  update public.tarea_elementos set cantidad_hecha = 3 where tarea_id = v_env and tipo = 'caja_bolsa' and producto = 'V2';
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = cantidad where tarea_id = v_env and tipo = 'peticion';
  perform pg_temp.comprobar('Sin terminar de preparar el envío, Rentería no lo ve (ni el día siguiente)',
    motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-17', '11:05')) -> 'envios' = '[]'::jsonb);
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('2026-12-16', '16:00'), terminada_en = pg_temp.a('2026-12-16', '17:00')
   where id = v_env;
  insert into _v values ('tareas_almacen', (select jsonb_agg(jsonb_build_array(clave, estado) order by clave) from public.tareas where jornada_id = j));
  perform pg_temp.comprobar('Preparado: el mismo día, todavía no (sin esperar a «Salida a Nacex»)',
    motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-16', '19:00')) -> 'envios' = '[]'::jsonb
    and (select estado from public.tareas where jornada_id = j and clave = 'nacex_salida') = 'pendiente');
end;
$$;

-- ---------------------------------------------------------------------------
-- Jueves 17/12: Rentería lo ve y lo confirma («Falta algo»)
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  r jsonb;
  e jsonb;
  v_id uuid;
begin
  r := motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-17', '11:05'));
  e := r -> 'envios' -> 0;
  v_id := (e ->> 'id')::uuid;
  perform pg_temp.comprobar('Al día siguiente de prepararlo, Rentería lo ve en «Envíos», con su número y la hora de preparado',
    jsonb_array_length(r -> 'envios') = 1 and (r ->> 'envios_sin_confirmar')::int = 1
    and e ->> 'fecha' = '2026-12-16' and e ->> 'preparado' = '17:00' and e ->> 'destino' = 'Gipuzkoa (envío a Rentería)'
    and not e ? 'salida' and not e ? 'confirmado', r::text);
  perform pg_temp.comprobar('Trae lo marcado al meterlo en la caja: 3x V2 4g y la petición; la BZ1 sin marcar no aparece',
    e -> 'productos' = '[{"clave": "producto:V2|4g", "producto": "V2", "formato": "4g", "cantidad": 3}]'::jsonb
    and e -> 'peticiones' -> 0 ->> 'texto' = 'Donosti · Muestra: V2' and e -> 'pedidos' = '[]'::jsonb, e::text);
  perform pg_temp.comprobar('No es una tarea: Rentería no tiene «Recibe la bolsa» ni reposición',
    pg_temp.tarea(r, 'recibe_bolsa') is null and pg_temp.tarea(r, 'reposicion') is null);
  perform pg_temp.comprobar('Donosti no tiene «Envíos» (el envío a Gipuzkoa lo confirma Rentería); Basauri tampoco',
    motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-17', '11:05')) -> 'envios' = '[]'::jsonb
    and (motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-17', '11:05')) ->> 'envios_sin_confirmar')::int = 0
    and motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-17', '11:05')) -> 'envios' = '[]'::jsonb);
  perform pg_temp.comprobar('Durango recibe su propio envío (configuración)',
    motor.destino_envio(pg_temp.d('DURANGO')) = pg_temp.d('DURANGO') and motor.destino_envio(pg_temp.d('DONOSTI')) is null
    and motor.destino_envio(pg_temp.d('RENTERIA')) = pg_temp.d('GIPUZKOA'));

  perform pg_temp.comprobar('Sin nadie en el turno: SIN_PERSONA',
    pg_temp.err(motor.confirmar_envio_de(renteria, v_id, null, null, pg_temp.a('2026-12-17', '11:06'))) = 'SIN_PERSONA');
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000006', pg_temp.a('2026-12-17', '10:55'));
  perform pg_temp.comprobar('«Falta algo»: solo de la lista y como mucho lo que traía',
    pg_temp.err(motor.confirmar_envio_de(renteria, v_id, '[{"clave": "producto:BZ1|4g"}]', null, pg_temp.a('2026-12-17', '11:10'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.confirmar_envio_de(renteria, v_id, '[{"clave": "producto:V2|4g", "cantidad": 4}]', null, pg_temp.a('2026-12-17', '11:10'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.confirmar_envio_de(renteria, gen_random_uuid(), null, null, pg_temp.a('2026-12-17', '11:10'))) = 'NO_ENCONTRADO'
    and pg_temp.err(motor.confirmar_envio_de(donosti, v_id, null, null, pg_temp.a('2026-12-17', '11:10'))) = 'NO_ENCONTRADO');
  r := motor.confirmar_envio_de(renteria, v_id, '[{"clave": "producto:V2|4g", "cantidad": 1}]', 'La caja venía abierta',
                                pg_temp.a('2026-12-17', '11:15'));
  perform pg_temp.comprobar('«Falta algo»: desaparece de «Envíos» en el momento y de la cuenta de la pestaña',
    r -> 'envios' = '[]'::jsonb and (r ->> 'envios_sin_confirmar')::int = 0, r::text);
  perform pg_temp.comprobar('… queda apuntado lo que falta, quién y cuándo',
    (select reposicion = 'falta' and reposicion_por = 'Maite Prueba' and reposicion_en = pg_temp.a('2026-12-17', '11:15')
            and faltan = '[{"clave": "producto:V2|4g", "texto": "V2 4g", "cantidad": 1}]'::jsonb and incidencia_id is not null
       from public.bolsas_tienda where id = v_id));
  perform pg_temp.comprobar('… y llega a Administración como incidencia abierta (y la tienda la ve en sus incidencias)',
    exists (select 1 from jsonb_array_elements(motor.incidencias_tiendas_de(pg_temp.a('2026-12-17', '11:20')) -> 'incidencias') x
             where x ->> 'tienda' = 'Rentería' and x ->> 'opcion' = 'falta_envio' and x ->> 'estado' = 'abierta'
               and x ->> 'texto' = 'Falta en el envío del 16/12: 1x V2 4g. La caja venía abierta (Maite Prueba)')
    and r -> 'incidencias' -> 0 ->> 'opcion' = 'falta_envio', r::text);
  perform pg_temp.comprobar('Confirmar otra vez: ESTADO_NO_VALIDO, sin otra incidencia',
    pg_temp.err(motor.confirmar_envio_de(renteria, v_id, null, null, pg_temp.a('2026-12-17', '11:20'))) = 'ESTADO_NO_VALIDO'
    and (select count(*) from public.incidencias where opcion = 'falta_envio') = 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- Jueves 17/12, otro envío; el viernes 18/12, «Todo bien»
-- ---------------------------------------------------------------------------
do $$
declare
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  r jsonb;
  v_env uuid;
begin
  r := pg_temp.envio('2026-12-17', 'h33-b');
  v_env := (r -> 'tareas' ->> 'bolsas')::uuid;
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = cantidad where tarea_id = v_env and tipo = 'caja_bolsa';
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('2026-12-17', '16:00'), terminada_en = pg_temp.a('2026-12-17', '16:45')
   where id = v_env;
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000006', pg_temp.a('2026-12-18', '10:55'));
  r := motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-18', '11:00'));
  perform pg_temp.comprobar('El viernes sale el envío del jueves, con todo lo marcado',
    jsonb_array_length(r -> 'envios') = 1 and r -> 'envios' -> 0 ->> 'fecha' = '2026-12-17'
    and jsonb_array_length(r -> 'envios' -> 0 -> 'productos') = 2 and (r ->> 'envios_sin_confirmar')::int = 1, r::text);
  v_env := (r -> 'envios' -> 0 ->> 'id')::uuid;
  r := motor.confirmar_envio_de(renteria, v_env, null, null, pg_temp.a('2026-12-18', '11:05'));
  perform pg_temp.comprobar('«Todo bien»: desaparece en el momento, sin incidencia',
    r -> 'envios' = '[]'::jsonb and (r ->> 'envios_sin_confirmar')::int = 0
    and (select reposicion = 'bien' and incidencia_id is null from public.bolsas_tienda where id = v_env)
    and (select count(*) from public.incidencias where opcion = 'falta_envio') = 1, r::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Viernes 18/12, envío con el reparto: cuenta al prepararlo, salga quien salga
-- (sin «Lleva en el reparto lo que va a Nacex», que solo existe si sale el operario)
-- ---------------------------------------------------------------------------
do $$
declare
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  r jsonb;
  v_env uuid;
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-18');
begin
  update public.jornadas set sale = 'administracion' where id = j;
  r := pg_temp.envio('2026-12-18', 'h33-c');
  v_env := (r -> 'tareas' ->> 'bolsas')::uuid;
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = cantidad where tarea_id = v_env and tipo = 'caja_bolsa';
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('2026-12-18', '09:30'), terminada_en = pg_temp.a('2026-12-18', '10:20')
   where id = v_env;
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000006', pg_temp.a('2026-12-19', '10:55'));
  r := motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-19', '11:00'));
  perform pg_temp.comprobar('Viernes, sale Administración: el sábado Rentería ve el envío, preparado a las 10:20',
    (select clave from public.tareas where id = v_env) = 'preparar_envio_viernes'
    and not exists (select 1 from public.tareas where jornada_id = j and clave = 'nacex_viernes' and not retirada_por_condicion)
    and jsonb_array_length(r -> 'envios') = 1 and r -> 'envios' -> 0 ->> 'fecha' = '2026-12-18'
    and r -> 'envios' -> 0 ->> 'preparado' = '10:20', r::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Cierre de caja corto (franquicias) y las propias igual
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  r jsonb;
  t jsonb;
  v_punto uuid;
begin
  -- Las jornadas, antes de leer sus tareas (en otra sentencia).
  perform motor.generar_jornada(renteria, '2026-12-17'), motor.generar_jornada(donosti, '2026-12-19'),
          motor.generar_jornada(basauri, '2026-12-17');
  perform pg_temp.comprobar('Franquicias: «Cierre de caja» a las 20:20 entre semana y a las 13:20 el sábado',
    pg_temp.dia(renteria, '2026-12-17') like '%cierre_caja@20:20%' and pg_temp.dia(donosti, '2026-12-19') = 'cierre_caja@13:20',
    pg_temp.dia(renteria, '2026-12-17') || ' / ' || pg_temp.dia(donosti, '2026-12-19'));
  perform pg_temp.comprobar('Las propias, sin «Cierre de caja» aparte: su «Cierre del día» completo',
    pg_temp.dia(basauri, '2026-12-17') not like '%cierre_caja@%' and pg_temp.dia(basauri, '2026-12-17') like '%cierre_dia@20:20%');
  perform motor.empezar_turno_tienda_de(donosti, '00000000-0000-4000-c000-000000000004', pg_temp.a('2026-12-19', '10:55'));
  t := pg_temp.tarea(motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-19', '13:20')), 'cierre_caja');
  v_punto := (t -> 'puntos' -> 0 ->> 'id')::uuid;
  perform pg_temp.comprobar('Un solo punto, que pide la Z y el nº de ventas',
    jsonb_array_length(t -> 'puntos') = 1 and t -> 'puntos' -> 0 ->> 'pide' = 'cierre_caja_corto'
    and t -> 'puntos' -> 0 ->> 'texto' = 'Cierre de caja en la app: Z y nº de ventas', t::text);
  r := motor.marcar_punto_de(donosti, v_punto, pg_temp.a('2026-12-19', '13:21'));
  perform pg_temp.comprobar('Con un toque no vale: FALTAN_DATOS con pide cierre_caja_corto',
    pg_temp.err(r) = 'FALTAN_DATOS' and r -> 'error' ->> 'pide' = 'cierre_caja_corto', r::text);
  perform pg_temp.comprobar('Sin la Z o sin las ventas: DATOS_NO_VALIDOS',
    pg_temp.err(motor.cerrar_caja_de(donosti, v_punto, null, 40, null, null, pg_temp.a('2026-12-19', '13:22'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.cerrar_caja_de(donosti, v_punto, 512.30, null, null, null, pg_temp.a('2026-12-19', '13:22'))) = 'DATOS_NO_VALIDOS');
  r := motor.cerrar_caja_de(donosti, v_punto, 512.30, 41, 100, 5, pg_temp.a('2026-12-19', '13:23'));
  perform pg_temp.comprobar('Se guarda solo la Z y el nº de ventas (sin efectivo ni Glovo) y la tarea queda hecha',
    pg_temp.tarea(r, 'cierre_caja') ->> 'estado' = 'hecha'
    and (select z = 512.30 and ventas = 41 and efectivo is null and glovo is null and nombre = 'Nora Prueba'
           from public.cierres_caja where centro_id = pg_temp.d('DONOSTI') and fecha = '2026-12-19')
    and exists (select 1 from jsonb_array_elements(motor.cierres_caja_de('2026-12-19', '2026-12-19', null) -> 'cierres') x
                 where x ->> 'tienda' = 'Donosti' and x -> 'efectivo' = 'null'::jsonb and x ->> 'z' = '512.30'), r::text);

  -- Las propias, igual: el cierre de caja del «Cierre del día» sigue pidiendo efectivo y Glovo.
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-17', '16:55'));
  t := pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-17', '20:21')), 'cierre_dia');
  select (x ->> 'id')::uuid into v_punto from jsonb_array_elements(t -> 'puntos') x where x ->> 'pide' = 'cierre_caja';
  perform pg_temp.comprobar('Propias: el cierre de caja sigue pidiendo Z, ventas, efectivo y Glovo',
    v_punto is not null
    and pg_temp.err(motor.cerrar_caja_de(basauri, v_punto, 500, 40, null, null, pg_temp.a('2026-12-17', '20:22'))) = 'DATOS_NO_VALIDOS'
    and motor.marcar_punto_de(basauri, v_punto, pg_temp.a('2026-12-17', '20:22')) -> 'error' ->> 'pide' = 'cierre_caja'
    and motor.cerrar_caja_de(basauri, v_punto, 500, 40, 120.50, 15, pg_temp.a('2026-12-17', '20:23')) ? 'tareas', t::text);
  perform pg_temp.comprobar('… y se guarda con el efectivo y Glovo',
    (select efectivo = 120.50 and glovo = 15 from public.cierres_caja where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-17'));

  -- El almacén, igual: sus tareas del 16/12 no cambian y a Eder no le sale nada.
  perform pg_temp.comprobar('El almacén sigue igual: las tareas del envío y ninguna incidencia para Eder',
    (select jsonb_agg(jsonb_build_array(clave, estado) order by clave) from public.tareas
      where jornada_id = motor.generar_jornada(op, '2026-12-16'))
      = (select v from _v where k = 'tareas_almacen')
    and not exists (select 1 from public.incidencias where persona_id = op and opcion = 'falta_envio'));
end;
$$;

-- Permisos
select pg_temp.como('00000000-0000-4000-b000-000000000005');  -- Rentería
select pg_temp.comprobar('La tienda: confirmar_envio y cerrar_caja sin efectivo ni Glovo; ve solo sus envíos',
  public.confirmar_envio(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO'
  and public.cerrar_caja(gen_random_uuid(), 1, 1) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO'
  and (select count(*) from public.bolsas_tienda) = 3);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario no confirma envíos',
  public.confirmar_envio(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('Administración tampoco; ve los cierres cortos en cierres_caja()',
  public.confirmar_envio(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and jsonb_array_length(public.cierres_caja('2026-12-19', '2026-12-19') -> 'cierres') = 1);
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.confirmar_envio(uuid, jsonb, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'motor.api_confirmar_envio(uuid, jsonb, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.confirmar_envio_de(uuid, uuid, jsonb, text, timestamptz)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
