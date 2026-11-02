-- Prueba 21 · Producto sin granel en el reparto (Tarea 16, ESTADO v1.30 §5 R1e).
-- El reparto pide BZ1 4g para Bilbao (3) y Portu (2); no hay en el almacén ni
-- granel (lo marca el servidor: _compartido/sin_granel.ts). En la producción, el
-- operario decide: Bilbao, quitarlo; Portu, de Algorta. Bolsas, aviso de llamada,
-- texto para WhatsApp, parada para quien hace la ruta, cuentas (en camino) y
-- modificar el reparto. Miércoles 16/12/2026. Transacción deshecha al final.

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
-- El reparto tal como lo calcula y lo manda el servidor: Bilbao 2 V2 4g (hay en el
-- almacén) y p_bilbao BZ1 4g; Portu p_portu BZ1 4g. BZ1 sin granel, con 4 en Algorta.
create function pg_temp.guardar(p_jornada uuid, p_huella text, p_bilbao integer, p_portu integer, p_ahora timestamptz)
returns jsonb language plpgsql as $$
declare
  v_lineas jsonb := jsonb_build_array(
    jsonb_build_object('num', 1, 'texto', 'REPARTO 16/12', 'clase', 'cabecera'),
    jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
    jsonb_build_object('num', 3, 'texto', '', 'clase', 'vacia'),
    jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
    jsonb_build_object('num', 5, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                       'cantidad', 2, 'producto', 'V2', 'formato', '4g'));
  v_texto text := E'REPARTO 16/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g';
  v_para jsonb := '[]';
  v_bolsas jsonb;
begin
  if p_bilbao > 0 then
    v_lineas := v_lineas || jsonb_build_object('num', 6, 'texto', p_bilbao || 'x BZ1 4g', 'clase', 'producto',
                  'destino_id', pg_temp.d('BILBAO'), 'cantidad', p_bilbao, 'producto', 'BZ1', 'formato', '4g');
    v_texto := v_texto || E'\n' || p_bilbao || 'x BZ1 4g';
    v_para := v_para || jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'destino', 'Bilbao', 'pedido', p_bilbao, 'faltan', p_bilbao);
  end if;
  if p_portu > 0 then
    v_lineas := v_lineas || jsonb_build_array(
      jsonb_build_object('num', 7, 'texto', '', 'clase', 'vacia'),
      jsonb_build_object('num', 8, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 9, 'texto', p_portu || 'x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', p_portu, 'producto', 'BZ1', 'formato', '4g'));
    v_texto := v_texto || E'\n\nPORTU\n' || p_portu || 'x BZ1 4g';
    v_para := v_para || jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'destino', 'Portugalete', 'pedido', p_portu, 'faltan', p_portu);
  end if;
  v_bolsas := jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items',
                jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 6500))
                || case when p_bilbao > 0 then jsonb_build_array(jsonb_build_object('producto', 'BZ1', 'formato', '4g',
                                                                                    'cantidad', p_bilbao, 'orden', 6100))
                        else '[]' end));
  if p_portu > 0 then
    v_bolsas := v_bolsas || jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items',
                  jsonb_build_array(jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', p_portu, 'orden', 6100)));
  end if;
  return public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, 'reparto', v_texto, p_huella, '2026-12-16', 'operario', null, v_lineas,
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 2, 'en_almacen', 20, 'faltan', 0, 'aviso', null, 'orden', 6500),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', p_bilbao + p_portu, 'en_almacen', 0,
                         'faltan', p_bilbao + p_portu, 'aviso', null, 'orden', 6100, 'sin_granel', true, 'para', v_para,
                         'tiendas_con_stock', jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('ALGORTA'),
                                                                                   'destino', 'Algorta', 'cajas', 4)))),
    v_bolsas, true, p_ahora);
end;
$$;
create function pg_temp.bolsa(p_tarea uuid) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_array(c.codigo, e.tipo, e.producto, e.cantidad, e.estado)
                            order by c.codigo, e.tipo, e.producto), '[]')
    from public.tarea_elementos e join public.centros_trabajo c on c.id = e.destino_id
   where e.tarea_id = p_tarea and e.lote = 'reparto' $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  ahora constant timestamptz := '2026-12-16 09:30+01';
  j uuid;
  r jsonb;
  v_prod uuid;
  v_bolsas uuid;
  v_el uuid;
  v_dec jsonb;

begin
  j := motor.generar_jornada(op, '2026-12-16');
  r := pg_temp.guardar(j, 'h21-a', 3, 2, '2026-12-16 08:40+01');
  v_prod := (r -> 'tareas' ->> 'produccion')::uuid;
  v_bolsas := (r -> 'tareas' ->> 'bolsas')::uuid;
  v_el := (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1');

  -- 1. Detectarlo: en la producción, con quién lo recibe y quién tiene.
  r := (select x from jsonb_array_elements(motor.tarea_json(v_prod) -> 'elementos') x where x ->> 'producto' = 'BZ1');
  perform pg_temp.comprobar('R1e-06 producción: BZ1 sin granel, para Bilbao (3) y Portu (2), con Algorta (4) para cogerlo; sin decidir',
    r -> 'sin_granel' = 'true' and r ->> 'cantidad' = '5' and r -> 'resuelto' = 'false' and r -> 'decisiones' = '[]'
    and (select jsonb_agg(p ->> 'destino' || ':' || (p ->> 'faltan')) from jsonb_array_elements(r -> 'para') p) = '["Bilbao:3", "Portugalete:2"]'
    and r -> 'tiendas_con_stock' -> 0 ->> 'destino' = 'Algorta', r::text);
  perform pg_temp.comprobar('Sin decidir, el texto y las bolsas son los de siempre (sin paradas)',
    motor.texto_reparto((select id from public.repartos where jornada_id = j and estado = 'aceptado'))
      = E'REPARTO 16/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n3x BZ1 4g\n\nPORTU\n2x BZ1 4g'
    and pg_temp.bolsa(v_bolsas) = '[["BILBAO", "caja_bolsa", "BZ1", 3, "pendiente"], ["BILBAO", "caja_bolsa", "V2", 2, "pendiente"],
                                    ["PORTU", "caja_bolsa", "BZ1", 2, "pendiente"]]'
    and motor.paradas_reparto(j) = '[]', pg_temp.bolsa(v_bolsas)::text);

  -- 2. Decidir: lo que no vale.
  v_dec := jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'accion', 'quitar', 'cantidad', 3),
                             jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'accion', 'otra_tienda',
                                                'origen_id', pg_temp.d('ALGORTA'), 'cantidad', 2));
  perform pg_temp.comprobar('Entre todas tienen que sumar lo que falta (5): DATOS_NO_VALIDOS',
    motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(v_dec -> 0), ahora) -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and (motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(v_dec -> 0), ahora) -> 'error' ->> 'faltan')::int = 5);
  perform pg_temp.comprobar('Una tienda que no lo recibe, más de lo que pide o de otra tienda sin origen (o la misma): DATOS_NO_VALIDOS',
    motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(jsonb_set(v_dec -> 0, '{destino_id}', to_jsonb(pg_temp.d('ALGORTA'))), v_dec -> 1), ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(jsonb_set(v_dec -> 0, '{cantidad}', '4'),
                                                                 jsonb_set(v_dec -> 1, '{cantidad}', '1')), ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(v_dec -> 0, (v_dec -> 1) - 'origen_id'), ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(v_dec -> 0, jsonb_set(v_dec -> 1, '{origen_id}',
                                                                 to_jsonb(pg_temp.d('PORTU')))), ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(v_dec -> 0, jsonb_set(v_dec -> 1, '{origen_id}',
                                                                 to_jsonb(pg_temp.d('DONOSTI')))), ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS');
  perform pg_temp.comprobar('Una referencia con granel o una caja de la bolsa: DATOS_NO_VALIDOS; de otra persona: NO_ENCONTRADO',
    motor.resolver_sin_granel_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas and producto = 'V2'), v_dec, ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.resolver_sin_granel_de(adm, v_el, v_dec, ahora) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO'
    and (select calculo -> 'decisiones' is null from public.tarea_elementos where id = v_el));

  -- 3. Decidir: Bilbao, quitar 3; Portu, 2 de Algorta.
  r := motor.resolver_sin_granel_de(op, v_el, v_dec, ahora);
  perform pg_temp.comprobar('R1e-06 resuelto: no hay que hacerlo, dice por qué y queda quién y cuándo',
    r -> 'elemento' ->> 'estado' = 'hecho' and r -> 'elemento' ->> 'cantidad' = '0'
    and (select motivo = 'No se produce: 3 se quitan de Bilbao; 2 para Portugalete de Algorta.'
                and calculo ->> 'resuelto_por' = op::text and (calculo ->> 'resuelto_en')::timestamptz = ahora
           from public.tarea_elementos where id = v_el)
    and (select count(*) from public.registro_eventos where tipo = 'sin_granel_resuelto' and tarea_id = v_prod) = 1, r::text);
  perform pg_temp.comprobar('La producción sigue como siempre: sin nada más que hacer, queda hecha',
    (select estado from public.tareas where id = v_prod) = 'hecha');
  perform pg_temp.comprobar('Bolsas: Bilbao sin BZ1; Portu sin cajas de BZ1 y con «Llama a Algorta…» (como una petición)',
    pg_temp.bolsa(v_bolsas) = '[["BILBAO", "caja_bolsa", "V2", 2, "pendiente"],
                                ["PORTU", "llamada", "Llama a Algorta para que prepare 2 BZ1 4g para su retirada", 1, "pendiente"]]'
    and (select x ->> 'texto' = 'Llama a Algorta para que prepare 2 BZ1 4g para su retirada' and x ->> 'bolsa' = 'Bolsa de reposición'
           from jsonb_array_elements(motor.tarea_json(v_bolsas) -> 'elementos') x where x ->> 'tipo' = 'llamada'),
    pg_temp.bolsa(v_bolsas)::text);
  r := (select x from jsonb_array_elements(motor.tarea_json(v_prod) -> 'elementos') x where x ->> 'producto' = 'BZ1');
  perform pg_temp.comprobar('La producción dice lo decidido, con el nombre de las tiendas',
    r -> 'resuelto' = 'true'
    and r -> 'decisiones' = jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'destino', 'Bilbao', 'accion', 'quitar', 'origen_id', null,
                         'origen', null, 'cantidad', 3),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'destino', 'Portugalete', 'accion', 'otra_tienda',
                         'origen_id', pg_temp.d('ALGORTA'), 'origen', 'Algorta', 'cantidad', 2)), r::text);
  r := motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(v_dec -> 1, v_dec -> 0), '2026-12-16 09:35+01');
  perform pg_temp.comprobar('Repetirlo (aunque la producción ya esté hecha) no cambia nada; decidir otra cosa ya no se puede',
    r -> 'error' is null and (select count(*) from public.registro_eventos where tipo = 'sin_granel_resuelto' and tarea_id = v_prod) = 1
    and motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(jsonb_set(v_dec -> 0, '{accion}', '"otra_tienda"')
                                                                 || jsonb_build_object('origen_id', pg_temp.d('ALGORTA')), v_dec -> 1), ahora)
          -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);

  -- 4. Texto, detalle y parada.
  r := motor.reparto_de_hoy_detalle_de(op, 'reparto', ahora) -> 'reparto';
  perform pg_temp.comprobar('R1e-08 WhatsApp: lo quitado ya no sale y Portu dice «2x BZ1 4g (de Algorta)»',
    r ->> 'texto_whatsapp' = E'REPARTO 16/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n\nPORTU\n2x BZ1 4g (de Algorta)', r ->> 'texto_whatsapp');
  perform pg_temp.comprobar('Detalle (Modificar reparto): Bilbao sin BZ1; Portu 2 BZ1 con `de` Algorta',
    (select jsonb_agg(jsonb_build_array(x ->> 'destino', x ->> 'producto', (x ->> 'cantidad')::int, x -> 'de' -> 0 ->> 'origen'))
       from jsonb_array_elements(r -> 'lineas') x)
      = '[["Bilbao", "V2", 2, null], ["Portugalete", "BZ1", 2, "Algorta"]]', r ->> 'lineas');
  r := motor.estado_actual_de(ahora) -> 'reparto_de_hoy';
  perform pg_temp.comprobar('Parada en reparto_de_hoy (panel y tarea activa): «Recoge 2 BZ1 4g en Algorta y déjalas en Portugalete»',
    r -> 'paradas' = jsonb_build_array(jsonb_build_object(
      'origen_id', pg_temp.d('ALGORTA'), 'origen', 'Algorta', 'destino_id', pg_temp.d('PORTU'), 'destino', 'Portugalete',
      'producto', 'BZ1', 'formato', '4g', 'cantidad', 2, 'texto', 'Recoge 2 BZ1 4g en Algorta y déjalas en Portugalete'))
    and motor.tarea_activa_de(op, ahora) -> 'reparto_de_hoy' -> 'paradas' = r -> 'paradas', r::text);
  perform pg_temp.comprobar('Lo quitado o de otra tienda no está pendiente de salir del almacén (BZ1: 5 − 5)',
    (select sum(x.cantidad) from motor.pendiente_salir(j, ahora) x where x.origen = 'reparto' and x.producto = 'BZ1') = 0
    and (select sum(x.cantidad) from motor.pendiente_salir(j, ahora) x where x.origen = 'reparto' and x.producto = 'V2') = 2);

  -- 5. Modificar el reparto.
  r := pg_temp.guardar(j, 'h21-b', 0, 3, '2026-12-16 09:45+01');
  perform pg_temp.comprobar('R1e-07 modificar (Bilbao ya sin BZ1, Portu pide 3): lo de Algorta (2) no cubre las 3 → hay que volver a decidir',
    (select estado = 'pendiente' and cantidad = 3 and not (calculo ->> 'resuelto')::boolean
            and calculo -> 'decisiones' = jsonb_build_array(v_dec -> 1)
       from public.tarea_elementos where id = v_el)
    and (select estado from public.tareas where id = v_prod) = 'pendiente'
    and pg_temp.bolsa(v_bolsas) = '[["BILBAO", "caja_bolsa", "V2", 2, "pendiente"], ["PORTU", "caja_bolsa", "BZ1", 3, "pendiente"]]'
    and motor.paradas_reparto(j) = '[]', pg_temp.bolsa(v_bolsas)::text);
  r := pg_temp.guardar(j, 'h21-c', 0, 2, '2026-12-16 09:50+01');
  perform pg_temp.comprobar('R1e-07 y si Portu vuelve a 2: la decisión de Algorta se conserva y vuelve a valer',
    (select estado = 'hecho' and (calculo ->> 'resuelto')::boolean from public.tarea_elementos where id = v_el)
    and (select estado from public.tareas where id = v_prod) = 'hecha'
    and pg_temp.bolsa(v_bolsas) = '[["BILBAO", "caja_bolsa", "V2", 2, "pendiente"],
                                    ["PORTU", "llamada", "Llama a Algorta para que prepare 2 BZ1 4g para su retirada", 1, "pendiente"]]'
    and r ->> 'texto_whatsapp' = E'REPARTO 16/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n\nPORTU\n2x BZ1 4g (de Algorta)', r::text);
  r := pg_temp.guardar(j, 'h21-c', 0, 2, '2026-12-16 09:51+01');
  perform pg_temp.comprobar('El mismo reparto otra vez: se recalcula (Tarea 23) y la decisión de Algorta se conserva',
    r -> 'ya_pegado' is null and (r ->> 'sustituye_a') is not null
    and (select estado = 'hecho' and (calculo ->> 'resuelto')::boolean from public.tarea_elementos where id = v_el)
    and r ->> 'texto_whatsapp' like '%2x BZ1 4g (de Algorta)', r::text);

  -- 6. Bolsas: el aviso de llamada se marca como una petición; la tienda no está completa sin él.
  update public.tareas set estado = 'hecha' where jornada_id = j and id not in (v_prod, v_bolsas) and estado in ('pendiente', 'en_curso');
  perform motor.marcar_cajas_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas and producto = 'V2'), 2,
                                '2026-12-16 10:40+01');
  perform pg_temp.comprobar('Con las cajas de Bilbao pero sin la llamada de Portu, las bolsas no están listas',
    (select estado from public.tareas where id = v_bolsas) = 'en_curso');
  r := motor.marcar_cajas_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'llamada'), 1,
                             '2026-12-16 10:45+01');
  perform pg_temp.comprobar('Marcada la llamada (1), las bolsas quedan listas',
    (select estado from public.tareas where id = v_bolsas) = 'hecha', r::text);

  -- 7. Cuentas (R1c): lo de otra tienda no sale del almacén; en camino −2 en Algorta y +2 en Portu, hasta las 23:30.
  perform pg_temp.comprobar('R1e-09 en camino a las 12:00: Bilbao +2 V2; Portu +2 BZ1 y Algorta −2 BZ1 (en total, igual)',
    (select jsonb_agg(jsonb_build_array(c.codigo, x.producto, x.cantidad) order by c.codigo, x.producto)
       from motor.en_camino_en(op, '2026-12-16 12:00+01') x join public.centros_trabajo c on c.id = x.destino_id)
      = '[["ALGORTA", "BZ1", -2], ["BILBAO", "V2", 2], ["PORTU", "BZ1", 2]]'
    and not exists (select 1 from motor.en_camino_en(op, '2026-12-16 23:45+01'))
    and (select coalesce(sum(m.cantidad), 0) from motor.movimientos_almacen(op, '2026-12-16 08:00+01', '2026-12-16 12:00+01') m
          where m.movimiento = 'salido' and m.producto = 'BZ1') = 0);

  -- 8. Otro día: Portu se queda sin nada (se quita del texto) y Bilbao recibe de Algorta.
  j := motor.generar_jornada(op, '2026-12-17');
  r := pg_temp.guardar(j, 'h21-d', 3, 2, '2026-12-17 08:40+01');
  v_el := (select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
            where t.jornada_id = j and t.clave = 'produccion_reparto' and e.producto = 'BZ1');
  r := motor.resolver_sin_granel_de(op, v_el, jsonb_build_array(
         jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'accion', 'quitar', 'cantidad', 2),
         jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'accion', 'otra_tienda', 'origen_id', pg_temp.d('ALGORTA'),
                            'cantidad', 3)), '2026-12-17 09:30+01');
  perform pg_temp.comprobar('R1e-08 una tienda sin nada se quita del texto; «3x BZ1 4g (de Algorta)» en Bilbao',
    motor.texto_reparto((select id from public.repartos where jornada_id = j and estado = 'aceptado'))
      = E'REPARTO 16/12\nSALE: ALMACÉN\n\nBILBAO\n2x V2 4g\n3x BZ1 4g (de Algorta)', r::text);
end;
$$;

-- Permisos ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
begin
  perform pg_temp.comprobar('Administración no decide en la producción del operario (NO_AUTORIZADO)',
    public.resolver_sin_granel(gen_random_uuid(), '[]') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
end;
$$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se usa resolver_sin_granel',
    pg_temp.rechazada($q$select public.resolver_sin_granel(gen_random_uuid(), '[]')$q$));
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
