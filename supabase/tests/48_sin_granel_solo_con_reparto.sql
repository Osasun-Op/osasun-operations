-- Prueba 48 · Sin granel: de otra tienda, solo de las que tienen reparto ese día (T-0017 · Tarea 45; ESTADO_DEL_SISTEMA.md
-- R1e, REGLAS_CALCULO.md §2.11; decisión del propietario, 24/11/2026).
-- Martes 22/12/2026. El caso del 24/11: reparto en Algorta, Barakaldo, Bilbao y Portugalete (en Basauri no). Bilbao pide
-- 1 ANKA 4g y no hay granel. La lista para cogerlo de otra tienda la calcula el servidor (sin_granel.ts, R1e-14 y R1e-15 en
-- Deno): aquí llega como la manda. Basauri como origen se rechaza; sin nadie que lo tenga, «quitar» funciona; al modificar
-- el reparto, una tienda que entra se puede elegir y una que sale se lleva su decisión. Miércoles 23/12: una tienda solo con
-- una petición especial o con un pedido de cliente también tiene bolsa, también mientras se guarda el reparto otra vez.
-- Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

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
create function pg_temp.a(p_fecha date, p_hora text) returns timestamptz language sql as $$
  select motor.en_local(p_fecha, p_hora::time) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.nombre(p_codigo text) returns text language sql as $$
  select nombre from public.centros_trabajo where codigo = p_codigo $$;
-- Una tienda de la lista «Cogerlo de otra tienda», como la manda el servidor.
create function pg_temp.t(p_codigo text, p_cajas integer) returns jsonb language sql as $$
  select jsonb_build_object('destino_id', pg_temp.d(p_codigo), 'destino', pg_temp.nombre(p_codigo), 'cajas', p_cajas) $$;
-- Una referencia sin granel de la producción, como la manda el servidor: una tienda que la recibe (todo le falta).
create function pg_temp.sg(p_producto text, p_orden integer, p_codigo text, p_pedido integer, p_tiendas jsonb)
returns jsonb language sql as $$
  select jsonb_build_object('producto', p_producto, 'formato', '4g', 'pedido', p_pedido, 'en_almacen', 0, 'faltan', p_pedido,
                            'aviso', null, 'orden', p_orden, 'sin_granel', true,
                            'para', jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d(p_codigo),
                                                      'destino', pg_temp.nombre(p_codigo), 'pedido', p_pedido, 'faltan', p_pedido)),
                            'tiendas_con_stock', p_tiendas) $$;
-- El reparto como lo guarda guardar_reparto. p_lineas: [[tienda, cantidad, producto]] en orden de tienda; con cantidad 0,
-- una petición especial («Además: …»).
create function pg_temp.guardar(p_jornada uuid, p_fecha date, p_huella text, p_lineas jsonb, p_produccion jsonb)
returns jsonb language plpgsql as $$
declare
  v_lineas jsonb := jsonb_build_array(
    jsonb_build_object('num', 1, 'texto', 'REPARTO ' || to_char(p_fecha, 'DD/MM'), 'clase', 'cabecera'),
    jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'));
  v_texto text := 'REPARTO ' || to_char(p_fecha, 'DD/MM') || E'\nSALE: ALMACÉN';
  v_bolsas jsonb := '[]';
  v_n integer := 2;
  v_tienda text;
  x jsonb;
begin
  for x in select y from jsonb_array_elements(p_lineas) y loop
    if v_tienda is distinct from x ->> 0 then
      v_tienda := x ->> 0;
      v_lineas := v_lineas || jsonb_build_array(
        jsonb_build_object('num', v_n + 1, 'texto', '', 'clase', 'vacia'),
        jsonb_build_object('num', v_n + 2, 'texto', v_tienda, 'clase', 'tienda', 'destino_id', pg_temp.d(v_tienda)));
      v_texto := v_texto || E'\n\n' || v_tienda;
      v_n := v_n + 2;
    end if;
    v_n := v_n + 1;
    if (x ->> 1)::int = 0 then
      v_lineas := v_lineas || jsonb_build_object('num', v_n, 'texto', 'Además: ' || (x ->> 2), 'clase', 'peticion',
                                                 'destino_id', pg_temp.d(v_tienda));
      v_texto := v_texto || E'\nAdemás: ' || (x ->> 2);
    else
      v_lineas := v_lineas || jsonb_build_object('num', v_n, 'texto', (x ->> 1) || 'x ' || (x ->> 2) || ' 4g', 'clase', 'producto',
                                                 'destino_id', pg_temp.d(v_tienda), 'cantidad', (x ->> 1)::int,
                                                 'producto', x ->> 2, 'formato', '4g');
      v_texto := v_texto || E'\n' || (x ->> 1) || 'x ' || (x ->> 2) || ' 4g';
      v_bolsas := v_bolsas || jsonb_build_object('destino_id', pg_temp.d(v_tienda), 'items', jsonb_build_array(
        jsonb_build_object('producto', x ->> 2, 'formato', '4g', 'cantidad', (x ->> 1)::int, 'orden', 1)));
    end if;
  end loop;
  -- Una bolsa por tienda.
  select coalesce(jsonb_agg(jsonb_build_object('destino_id', d, 'items', i)), '[]') into v_bolsas
    from (select b ->> 'destino_id' as d, jsonb_agg(b -> 'items' -> 0) as i from jsonb_array_elements(v_bolsas) b group by 1) s;
  return public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002'::uuid, p_jornada, 'reparto', v_texto, p_huella, p_fecha, 'operario', null,
    v_lineas, p_produccion, v_bolsas, true, pg_temp.a(p_fecha, '08:40'));
end;
$$;
-- La referencia de la producción de una jornada.
create function pg_temp.ref(p_jornada uuid, p_producto text) returns public.tarea_elementos language sql as $$
  select e.* from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
   where t.jornada_id = p_jornada and t.clave = 'produccion_reparto' and e.producto = p_producto $$;
-- Cómo la ve la pantalla de producción.
create function pg_temp.ref_json(p_jornada uuid, p_producto text) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.tarea_json((pg_temp.ref(p_jornada, p_producto)).tarea_id) -> 'elementos') x
   where x ->> 'producto' = p_producto $$;
create function pg_temp.otra(p_destino text, p_origen text, p_cantidad integer) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d(p_destino), 'accion', 'otra_tienda',
                                              'origen_id', pg_temp.d(p_origen), 'cantidad', p_cantidad)) $$;
-- Las líneas «Avisa a…» de las bolsas de una jornada.
create function pg_temp.avisa(p_jornada uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(e.producto order by e.producto), '[]') from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
   where t.jornada_id = p_jornada and t.clave = 'bolsas' and e.tipo = 'llamada' $$;
create function pg_temp.paradas(p_jornada uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(x ->> 'texto' order by x ->> 'texto'), '[]') from jsonb_array_elements(motor.paradas_reparto(p_jornada)) x $$;
create function pg_temp.con_bolsa(p_jornada uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(c.codigo order by c.codigo), '[]')
    from motor.tiendas_con_bolsa(p_jornada) x join public.centros_trabajo c on c.id = x.centro_id $$;

-- La cuenta de Basauri (inventada), para el aviso a la tienda de origen.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-b000-000000000001', 'authenticated', 'authenticated',
        'tienda.basauri@osasun.invalid', '{"provider": "google", "providers": ["google"]}', '{}', now(), now());
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null);

-- ---------------------------------------------------------------------------
-- Martes 22/12: el caso del 24/11 y modificar el reparto
-- ---------------------------------------------------------------------------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  f constant date := '2026-12-22';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-22');
  v_sin jsonb := '[["BILBAO", 1, "ANKA"], ["BILBAO", 2, "CBD DRY"], ["ALGORTA", 1, "V2"], ["BARAKALDO", 1, "V2"],
                   ["PORTU", 1, "V2"], ["PORTU", 1, "BZ1"]]';
  v_anka jsonb;
  v_cbd jsonb := pg_temp.sg('CBD DRY', 2, 'BILBAO', 2, jsonb_build_array(pg_temp.t('ALGORTA', 3)));
  r jsonb;
  v_n integer;
begin
  -- v1: el reparto del 24/11 (sin Basauri).
  v_anka := pg_temp.sg('ANKA', 1, 'BILBAO', 1, jsonb_build_array(pg_temp.t('ALGORTA', 1), pg_temp.t('BARAKALDO', 1), pg_temp.t('PORTU', 1)));
  perform pg_temp.guardar(j, f, 'h48-a', v_sin,
                          jsonb_build_array(v_anka, v_cbd, pg_temp.sg('BZ1', 3, 'PORTU', 1, '[]')));
  r := pg_temp.ref_json(j, 'ANKA');
  perform pg_temp.comprobar('El caso del 24/11: la lista da Algorta, Barakaldo y Portugalete; con bolsa, las cuatro del reparto (Basauri no)',
    (select jsonb_agg(x ->> 'destino') from jsonb_array_elements(r -> 'tiendas_con_stock') x) = '["Algorta", "Barakaldo", "Portugalete"]'
    and pg_temp.con_bolsa(j) = '["ALGORTA", "BARAKALDO", "BILBAO", "PORTU"]', r::text || pg_temp.con_bolsa(j)::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'ANKA')).id, pg_temp.otra('BILBAO', 'BASAURI', 1), pg_temp.a(f, '09:10'));
  perform pg_temp.comprobar('Basauri como origen: DATOS_NO_VALIDOS con la frase para enseñar tal cual, y no se guarda nada',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and r -> 'error' ->> 'mensaje' = 'Basauri no tiene reparto hoy: elige una tienda que esté en el reparto de hoy.'
    and r -> 'error' ->> 'origen_id' = pg_temp.d('BASAURI')::text
    and (pg_temp.ref(j, 'ANKA')).calculo -> 'decisiones' is null
    and not exists (select 1 from public.registro_eventos where tipo = 'sin_granel_resuelto' and jornada_id = j), r::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'ANKA')).id, pg_temp.otra('BILBAO', 'DONOSTI', 1), pg_temp.a(f, '09:10'));
  perform pg_temp.comprobar('Una tienda que no es de la ruta (Donosti), tampoco',
    r -> 'error' ->> 'mensaje' = 'Donosti no tiene reparto hoy: elige una tienda que esté en el reparto de hoy.', r::text);

  -- Ninguna tienda con reparto tiene BZ1: la lista va vacía y «quitar» funciona.
  r := pg_temp.ref_json(j, 'BZ1');
  perform pg_temp.comprobar('BZ1: ninguna tienda con reparto lo tiene, la lista va vacía',
    r -> 'sin_granel' = 'true' and r -> 'tiendas_con_stock' = '[]', r::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'BZ1')).id,
         jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'accion', 'quitar', 'cantidad', 1)), pg_temp.a(f, '09:11'));
  perform pg_temp.comprobar('… y «quitar» funciona: resuelta, hecha sin producir',
    r -> 'error' is null and (pg_temp.ref(j, 'BZ1')).estado = 'hecho' and ((pg_temp.ref(j, 'BZ1')).calculo ->> 'resuelto')::boolean, r::text);

  -- CBD DRY para Bilbao, de Algorta (que sigue en el reparto todo el día).
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'CBD DRY')).id, pg_temp.otra('BILBAO', 'ALGORTA', 2), pg_temp.a(f, '09:12'));
  perform pg_temp.comprobar('Una tienda con reparto (Algorta) como origen: vale, como siempre',
    r -> 'error' is null and ((pg_temp.ref(j, 'CBD DRY')).calculo ->> 'resuelto')::boolean, r::text);

  -- v2: se modifica y Basauri entra en el reparto (1 V2 4g); Portugalete ya no lleva BZ1 (lo quitado ya está en la línea).
  v_anka := pg_temp.sg('ANKA', 1, 'BILBAO', 1, jsonb_build_array(pg_temp.t('ALGORTA', 1), pg_temp.t('BARAKALDO', 1),
                                                                  pg_temp.t('BASAURI', 1), pg_temp.t('PORTU', 1)));
  perform pg_temp.guardar(j, f, 'h48-b',
    '[["BILBAO", 1, "ANKA"], ["BILBAO", 2, "CBD DRY"], ["ALGORTA", 1, "V2"], ["BARAKALDO", 1, "V2"], ["BASAURI", 1, "V2"], ["PORTU", 1, "V2"]]',
    jsonb_build_array(v_anka, v_cbd));
  r := pg_temp.ref_json(j, 'ANKA');
  perform pg_temp.comprobar('Modificar: Basauri entra en el reparto y sale en la lista desde ese momento',
    (select jsonb_agg(x ->> 'destino') from jsonb_array_elements(r -> 'tiendas_con_stock') x)
      = '["Algorta", "Barakaldo", "Basauri", "Portugalete"]'
    and pg_temp.con_bolsa(j) = '["ALGORTA", "BARAKALDO", "BASAURI", "BILBAO", "PORTU"]', r::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'ANKA')).id, pg_temp.otra('BILBAO', 'BASAURI', 1), pg_temp.a(f, '09:20'));
  perform pg_temp.comprobar('… y ahora Basauri como origen vale: parada y «Avisa a Basauri…»',
    r -> 'error' is null and ((pg_temp.ref(j, 'ANKA')).calculo ->> 'resuelto')::boolean
    and pg_temp.paradas(j) = '["Recoge 1 ANKA 4g en Basauri y déjalas en Bilbao", "Recoge 2 CBD DRY 4g en Algorta y déjalas en Bilbao"]'
    and pg_temp.avisa(j) = '["Avisa a Algorta para que prepare 2 CBD DRY 4g para su retirada",
                             "Avisa a Basauri para que prepare 1 ANKA 4g para su retirada"]',
    r::text || pg_temp.paradas(j)::text || pg_temp.avisa(j)::text);
  -- El operario marca «Avisa a Basauri…»: Basauri recibe el aviso (T-0010).
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a(f, '09:00'), terminada_en = pg_temp.a(f, '09:30')
   where jornada_id = j and clave = 'produccion_reparto';
  perform motor.marcar_cajas_de(op, (select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
                                      where t.jornada_id = j and t.clave = 'bolsas' and e.tipo = 'llamada'
                                        and e.producto like 'Avisa a Basauri%'), 1, pg_temp.a(f, '09:40'));
  v_n := (select count(*) from jsonb_array_elements(motor.tienda_hoy_de(basauri, pg_temp.a(f, '11:00')) -> 'avisos') x
           where x ->> 'texto' = 'Prepara 1 ANKA 4g para Bilbao: lo recoge hoy el reparto');
  perform pg_temp.comprobar('Al marcarla, Basauri tiene el aviso del almacén', v_n = 1, v_n::text);

  -- v3: se modifica otra vez; Basauri se queda sin bolsa y Portugalete vuelve a pedir 1 BZ1 (sigue sin granel).
  perform pg_temp.guardar(j, f, 'h48-c', v_sin,
    jsonb_build_array(v_anka - 'tiendas_con_stock'
                        || jsonb_build_object('tiendas_con_stock', jsonb_build_array(pg_temp.t('ALGORTA', 1), pg_temp.t('BARAKALDO', 1),
                                                                                     pg_temp.t('PORTU', 1))),
                      v_cbd, pg_temp.sg('BZ1', 3, 'PORTU', 1, jsonb_build_array(pg_temp.t('ALGORTA', 2)))));
  r := pg_temp.ref_json(j, 'ANKA');
  perform pg_temp.comprobar('Basauri sale del reparto: la decisión con Basauri se va y el ANKA vuelve sin resolver',
    r -> 'resuelto' = 'false' and r ->> 'estado' = 'pendiente' and r ->> 'cantidad' = '1' and r -> 'decisiones' = '[]'
    and (select jsonb_agg(x ->> 'destino') from jsonb_array_elements(r -> 'tiendas_con_stock') x) = '["Algorta", "Barakaldo", "Portugalete"]'
    and pg_temp.con_bolsa(j) = '["ALGORTA", "BARAKALDO", "BILBAO", "PORTU"]', r::text);
  perform pg_temp.comprobar('… sin su parada ni su «Avisa a Basauri…»; la bolsa de Bilbao vuelve a llevar el ANKA',
    pg_temp.paradas(j) = '["Recoge 2 CBD DRY 4g en Algorta y déjalas en Bilbao"]'
    and pg_temp.avisa(j) = '["Avisa a Algorta para que prepare 2 CBD DRY 4g para su retirada"]'
    and exists (select 1 from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
                 where t.jornada_id = j and t.clave = 'bolsas' and e.tipo = 'caja_bolsa' and e.destino_id = pg_temp.d('BILBAO')
                   and e.producto = 'ANKA' and e.cantidad = 1)
    and (select estado from public.tareas where jornada_id = j and clave = 'produccion_reparto') = 'pendiente',
    pg_temp.paradas(j)::text || pg_temp.avisa(j)::text);
  v_n := (select count(*) from jsonb_array_elements(motor.tienda_hoy_de(basauri, pg_temp.a(f, '11:00')) -> 'avisos') x
           where x ->> 'texto' = 'Prepara 1 ANKA 4g para Bilbao: lo recoge hoy el reparto');
  perform pg_temp.comprobar('El aviso que ya tenía Basauri se queda (T-0010)', v_n = 1, v_n::text);
  perform pg_temp.comprobar('La decisión con un origen que sigue en el reparto (CBD DRY de Algorta) se queda',
    ((pg_temp.ref(j, 'CBD DRY')).calculo ->> 'resuelto')::boolean and (pg_temp.ref(j, 'CBD DRY')).estado = 'hecho'
    and pg_temp.ref_json(j, 'CBD DRY') -> 'decisiones' -> 0 ->> 'origen' = 'Algorta');
  r := pg_temp.ref_json(j, 'BZ1');
  perform pg_temp.comprobar('Lo quitado (BZ1) se vuelve a pedir y sigue sin granel: sale otra vez sin resolver, con la lista nueva',
    r -> 'resuelto' = 'false' and r ->> 'estado' = 'pendiente' and r ->> 'cantidad' = '1'
    and (select jsonb_agg(x ->> 'destino') from jsonb_array_elements(r -> 'tiendas_con_stock') x) = '["Algorta"]', r::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'ANKA')).id, pg_temp.otra('BILBAO', 'BASAURI', 1), pg_temp.a(f, '09:50'));
  perform pg_temp.comprobar('… y Basauri, ya sin bolsa, vuelve a rechazarse',
    r -> 'error' ->> 'mensaje' = 'Basauri no tiene reparto hoy: elige una tienda que esté en el reparto de hoy.', r::text);
end;
$$;

-- ---------------------------------------------------------------------------
-- Miércoles 23/12: una tienda solo con una petición especial o con un pedido de cliente
-- ---------------------------------------------------------------------------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  f constant date := '2026-12-23';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-23');
  v_lineas jsonb := '[["BILBAO", 1, "ANKA"], ["BILBAO", 1, "CBD DRY"], ["BARAKALDO", 0, "Rollos de TPV"]]';
  v_prod jsonb := jsonb_build_array(pg_temp.sg('ANKA', 1, 'BILBAO', 1, jsonb_build_array(pg_temp.t('BARAKALDO', 1))),
                                    pg_temp.sg('CBD DRY', 2, 'BILBAO', 1, jsonb_build_array(pg_temp.t('BASAURI', 1))));
  v_peticion jsonb := jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BARAKALDO'), 'texto', 'Rollos de TPV'));
  v_rep uuid;
  v_ped uuid;
  r jsonb;
begin
  -- Barakaldo solo con «Además: Rollos de TPV»; Basauri solo con un pedido de cliente para recoger en la tienda.
  v_rep := (pg_temp.guardar(j, f, 'h48-d', v_lineas, v_prod) ->> 'reparto_id')::uuid;
  perform public.servidor_guardar_peticiones(adm, v_rep, v_peticion, pg_temp.a(f, '08:41'));
  insert into public.pedidos_cliente (id_cliente, cliente, entrega, destino_id, lineas, fecha_objetivo, jornada_id, reparto_id,
                                      registrado_por, registrado_en)
  values (gen_random_uuid(), 'Cliente Prueba', 'tienda', pg_temp.d('BASAURI'), '[{"producto": "V2", "formato": "4g", "cantidad": 1}]',
          f, j, v_rep, adm, pg_temp.a(f, '08:30'))
  returning id into v_ped;
  perform pg_temp.comprobar('Con bolsa: Bilbao, Barakaldo (la petición) y Basauri (el pedido de cliente)',
    pg_temp.con_bolsa(j) = '["BARAKALDO", "BASAURI", "BILBAO"]', pg_temp.con_bolsa(j)::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'ANKA')).id, pg_temp.otra('BILBAO', 'BARAKALDO', 1), pg_temp.a(f, '09:10'));
  perform pg_temp.comprobar('Barakaldo, solo con una petición especial, vale como origen', r -> 'error' is null, r::text);
  r := motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'CBD DRY')).id, pg_temp.otra('BILBAO', 'BASAURI', 1), pg_temp.a(f, '09:11'));
  perform pg_temp.comprobar('Basauri, solo con un pedido de cliente, vale como origen', r -> 'error' is null, r::text);

  -- Se calcula otra vez (el mismo reparto): mientras se guarda, la versión nueva aún no tiene sus peticiones ni sus pedidos.
  v_rep := (pg_temp.guardar(j, f, 'h48-e', v_lineas, v_prod) ->> 'reparto_id')::uuid;
  perform pg_temp.comprobar('Al guardarlo otra vez, las dos decisiones se quedan (las dos tiendas siguen con bolsa)',
    ((pg_temp.ref(j, 'ANKA')).calculo ->> 'resuelto')::boolean and ((pg_temp.ref(j, 'CBD DRY')).calculo ->> 'resuelto')::boolean
    and pg_temp.paradas(j) = '["Recoge 1 ANKA 4g en Barakaldo y déjalas en Bilbao", "Recoge 1 CBD DRY 4g en Basauri y déjalas en Bilbao"]',
    pg_temp.paradas(j)::text);
  -- Lo que hace guardar_reparto después: las peticiones y los pedidos pasan a la versión nueva.
  perform public.servidor_guardar_peticiones(adm, v_rep, v_peticion, pg_temp.a(f, '09:20'));
  update public.pedidos_cliente set reparto_id = v_rep where id = v_ped;
  perform pg_temp.comprobar('… y siguen después, con la versión nueva completa',
    pg_temp.con_bolsa(j) = '["BARAKALDO", "BASAURI", "BILBAO"]'
    and (select count(*) from motor.paradas_bolsas(v_rep)) = 3
    and motor.resolver_sin_granel_de(op, (pg_temp.ref(j, 'ANKA')).id, pg_temp.otra('BILBAO', 'BARAKALDO', 1), pg_temp.a(f, '09:30'))
          -> 'error' is null);
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
