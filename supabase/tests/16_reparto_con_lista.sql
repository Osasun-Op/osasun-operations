-- Prueba 16 · El reparto se prepara con una lista (Tarea 10, ESTADO v1.21 §5 R1)
-- Lo que la base de datos hace para `guardar_reparto` y la pantalla: el reparto
-- guardado con su texto para WhatsApp, reintentos por id_cliente, «Prepara el
-- reparto» que se cierra sola, modificar conservando lo hecho,
-- reparto_de_hoy_detalle (operario y Administración) y permisos. El cálculo con
-- la lista y la lectura de la hoja están en _compartido/lista_test.ts y
-- reparto_lista_test.ts. Jueves 19/11/2026. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.rechazada(p_sql text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
end;
$$;
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
-- Lo que guarda la función del servidor guardar_reparto con una lista de dos tiendas
-- (el texto para WhatsApp y las líneas de R1 calculadas con él).
create function pg_temp.guardar(p_jornada uuid, p_persona uuid, p_v2_bilbao integer, p_faltan_v2 integer, p_ahora timestamptz)
returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    p_persona, p_jornada, 'reparto',
    E'REPARTO 19/11\nSALE: YO\n\nBILBAO\n' || p_v2_bilbao || E'x V2 4g\n1x BZ1 4g\n\nPORTU\n2x V2 4g',
    'h16-' || p_v2_bilbao, '2026-11-19', 'administracion', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 19/11', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: YO', 'clase', 'sale', 'sale', 'administracion'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', p_v2_bilbao || 'x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', p_v2_bilbao, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 6, 'texto', '1x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 1, 'producto', 'BZ1', 'formato', '4g'),
      jsonb_build_object('num', 8, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 9, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', p_v2_bilbao + 2, 'en_almacen', p_v2_bilbao + 2 - p_faltan_v2,
                         'faltan', p_faltan_v2, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 1, 'en_almacen', 5, 'faltan', 0, 'aviso', null, 'orden', 3)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', p_v2_bilbao, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 1, 'orden', 3))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1)))),
    true, p_ahora) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  c1 constant uuid := '6b1f7a3e-9c1d-4f2a-8b7e-2d5c9a0e1f34';
  c2 constant uuid := '0d4c2e8a-5b7f-4e1d-9a3c-8f6b2d1e7c50';
  j uuid;
  r jsonb;
  v_rep uuid;
  v_rep2 uuid;
  v_el uuid;
begin
  r := public.servidor_preparar(adm, '2026-11-19 08:40+01');
  perform pg_temp.comprobar('servidor_preparar dice qué tiendas están activas (Durango no)',
    (select bool_and(x ? 'activo') from jsonb_array_elements(r -> 'destinos') x)
    and (select (x ->> 'activo')::boolean from jsonb_array_elements(r -> 'destinos') x where x ->> 'codigo' = 'DURANGO') = false
    and (select (x ->> 'activo')::boolean from jsonb_array_elements(r -> 'destinos') x where x ->> 'codigo' = 'BILBAO'), r -> 'destinos' #>> '{}');

  j := motor.generar_jornada(op, '2026-11-19');
  perform pg_temp.comprobar('La tarea del operario se llama «Prepara el reparto»',
    (select titulo from public.tareas where jornada_id = j and clave = 'pegar_reparto') = 'Prepara el reparto');
  r := motor.reparto_de_hoy_detalle_de(adm, 'reparto', '2026-11-19 08:40+01');
  perform pg_temp.comprobar('reparto_de_hoy_detalle sin reparto: { reparto: null }',
    r = '{"reparto": null}'::jsonb, r::text);
  perform motor.iniciar_tarea_de(op, (select id from public.tareas where jornada_id = j and clave = 'pegar_reparto'), '2026-11-19 08:45+01');
  r := motor.terminar_tarea_de(op, (select id from public.tareas where jornada_id = j and clave = 'pegar_reparto'), null, null, '2026-11-19 08:46+01');
  perform pg_temp.comprobar('Terminarla sin reparto: MOTIVO_OBLIGATORIO, sin hablar de pegar',
    r -> 'error' ->> 'codigo' = 'MOTIVO_OBLIGATORIO' and r -> 'error' ->> 'mensaje' not like '%peg%', r::text);

  -- Administración guarda el reparto preparado con la lista.
  r := pg_temp.guardar(j, adm, 5, 3, '2026-11-19 08:50+01');
  v_rep := (r ->> 'reparto_id')::uuid;
  perform public.servidor_reparto_anotar_id_cliente(v_rep, c1);
  perform pg_temp.comprobar('Guardado: «Prepara el reparto» se cierra sola y la producción y las bolsas quedan creadas',
    (select estado from public.tareas where jornada_id = j and clave = 'pegar_reparto') = 'hecha'
    and (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
          where t.jornada_id = j and t.clave = 'produccion_reparto') = 1
    and (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
          where t.jornada_id = j and t.clave = 'bolsas') = 3, r::text);
  r := public.servidor_reparto_por_id_cliente(c1);
  perform pg_temp.comprobar('Reintento con el mismo id_cliente: devuelve lo guardado con su texto para WhatsApp',
    (r ->> 'reparto_id')::uuid = v_rep and r ->> 'texto_whatsapp' like E'REPARTO 19/11\nSALE: YO\n%', r::text);
  perform pg_temp.comprobar('Un id_cliente que no se ha usado: nada (null)',
    public.servidor_reparto_por_id_cliente(gen_random_uuid()) is null);

  r := motor.reparto_de_hoy_detalle_de(adm, 'reparto', '2026-11-19 09:00+01');
  perform pg_temp.comprobar('reparto_de_hoy_detalle: las líneas en su orden (tienda y producto), quién sale y el texto',
    (r -> 'reparto' ->> 'reparto_id')::uuid = v_rep and r -> 'reparto' ->> 'sale' = 'administracion'
    and r -> 'reparto' -> 'lineas' = jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'destino', 'Bilbao', 'producto', 'V2', 'formato', '4g', 'cantidad', 5),
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'destino', 'Bilbao', 'producto', 'BZ1', 'formato', '4g', 'cantidad', 1),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'destino', 'Portugalete', 'producto', 'V2', 'formato', '4g', 'cantidad', 2))
    and r -> 'reparto' ->> 'texto_whatsapp' like E'REPARTO 19/11\nSALE: YO\n%'
    and (r -> 'reparto' ->> 'pegado_por')::uuid = adm, r::text);
  perform pg_temp.comprobar('El operario ve el mismo reparto de su jornada',
    motor.reparto_de_hoy_detalle_de(op, 'reparto', '2026-11-19 09:00+01') = r);
  perform motor.cambiar_quien_sale_de(adm, 'operario', '2026-11-19 09:05+01');
  r := motor.reparto_de_hoy_detalle_de(adm, 'reparto', '2026-11-19 09:06+01');
  perform pg_temp.comprobar('Si se cambia quién sale sin tocar el reparto, el detalle y su texto lo dicen (SALE: ALMACÉN)',
    r -> 'reparto' ->> 'sale' = 'operario' and r -> 'reparto' ->> 'texto_whatsapp' like E'REPARTO 19/11\nSALE: ALMACÉN\n\nBILBAO%', r::text);
  perform motor.cambiar_quien_sale_de(adm, 'administracion', '2026-11-19 09:07+01');
  r := motor.reparto_de_hoy_detalle_de(adm, 'envio', '2026-11-19 09:07+01');
  r := r || jsonb_build_object('x', motor.reparto_de_hoy_detalle_de(adm, 'otro', '2026-11-19 09:07+01'));
  perform pg_temp.comprobar('Envío sin preparar: { reparto: null }; tipo no válido: DATOS_NO_VALIDOS',
    r -> 'reparto' = 'null'::jsonb and r -> 'x' -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.reparto_de_hoy_detalle_de(adm, 'reparto', '2026-11-21 10:00+01');
  perform pg_temp.comprobar('Sábado (sin jornada): SIN_JORNADA', r -> 'error' ->> 'codigo' = 'SIN_JORNADA', r::text);

  -- Modificar: 2 cajas de V2 ya hechas; ahora Bilbao pide 8 (faltan 6). Se conserva lo hecho.
  v_el := (select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
            where t.jornada_id = j and t.clave = 'produccion_reparto' and e.producto = 'V2');
  update public.tarea_elementos set cantidad_hecha = 2 where id = v_el;
  r := pg_temp.guardar(j, op, 8, 6, '2026-11-19 09:30+01');
  v_rep2 := (r ->> 'reparto_id')::uuid;
  perform public.servidor_reparto_anotar_id_cliente(v_rep2, c2);
  perform public.servidor_reparto_anotar_id_cliente(v_rep2, c1);
  perform pg_temp.comprobar('Modificar sustituye al de antes y conserva lo hecho (2 de 6 cajas de V2)',
    (r ->> 'sustituye_a')::uuid = v_rep
    and (select cantidad = 6 and cantidad_hecha = 2 from public.tarea_elementos where id = v_el)
    and (motor.reparto_de_hoy_detalle_de(adm, 'reparto', '2026-11-19 09:31+01') -> 'reparto' ->> 'reparto_id')::uuid = v_rep2, r::text);
  perform pg_temp.comprobar('Cada petición conserva su id_cliente (uno por reparto; el de otro no se reutiliza)',
    (select id_cliente from public.repartos where id = v_rep) = c1
    and (select id_cliente from public.repartos where id = v_rep2) = c2
    and (public.servidor_reparto_por_id_cliente(c2) ->> 'reparto_id')::uuid = v_rep2);
end;
$$;

-- Permisos
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.reparto_de_hoy_detalle('otro');
begin
  perform pg_temp.comprobar('Operario: puede usar reparto_de_hoy_detalle; no las funciones del servidor',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and pg_temp.rechazada($q$select public.servidor_reparto_por_id_cliente(gen_random_uuid())$q$)
    and pg_temp.rechazada($q$select public.servidor_reparto_anotar_id_cliente(gen_random_uuid(), gen_random_uuid())$q$), r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.reparto_de_hoy_detalle('otro');
begin
  perform pg_temp.comprobar('Administración: también puede usar reparto_de_hoy_detalle',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-0000000000ff');
do $$
declare
  r jsonb := public.reparto_de_hoy_detalle('reparto');
begin
  perform pg_temp.comprobar('Usuario sin ficha: NO_AUTORIZADO', r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text);
end;
$$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se puede consultar el reparto ni usar las funciones del servidor',
    pg_temp.rechazada($q$select public.reparto_de_hoy_detalle('reparto')$q$)
    and pg_temp.rechazada($q$select public.servidor_reparto_por_id_cliente(gen_random_uuid())$q$));
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
