-- Prueba 17 · Pedidos de cliente con la lista y cajas en camino (Tarea 12,
-- ESTADO v1.24 §5 R1b y R1c). Lo que la base de datos hace para
-- `guardar_pedido_cliente` y `guardar_reparto`: recoger en tienda (entra en el
-- reparto de hoy o en el siguiente, bolsa aparte, tarea después de la
-- producción, se mantiene al modificar el reparto), Nacex (tarea por la tarde o
-- el viernes por la mañana, Nacex activado una sola vez aunque haya envío),
-- lo comprometido y las cajas en camino (salida = bolsas listas; mismo día y día
-- siguiente), «coge / haz» al salir la tarea con la última lectura de la hoja,
-- pasar un pedido de Nacex al día siguiente (a mano o sin terminar),
-- idempotencia, pedidos abiertos y permisos. La lectura de la hoja está en
-- _compartido/pedido_cliente_test.ts. Semana del 23/11/2026. Transacción deshecha al final.

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
create function pg_temp.limpiar() returns void language sql as $$
  update public.tareas set estado = 'hecha'
   where estado in ('pendiente', 'en_curso', 'bloqueada')
     and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001') $$;
create function pg_temp.hecha(p_jornada uuid, p_claves text[]) returns void language sql as $$
  update public.tareas set estado = 'hecha' where jornada_id = p_jornada and clave = any (p_claves) $$;
create function pg_temp.tarea(p_jornada uuid, p_patron text) returns public.tareas language sql as $$
  select * from public.tareas where jornada_id = p_jornada and clave like p_patron order by creada_en desc limit 1 $$;
-- Lo que guarda guardar_reparto (o el envío) con una sola línea: V2 4g a Bilbao (o a Gipuzkoa).
create function pg_temp.guardar(p_jornada uuid, p_tipo text, p_v2 integer, p_faltan integer, p_ahora timestamptz)
returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, p_tipo,
    case p_tipo when 'reparto' then E'REPARTO\nSALE: ALMACÉN\n\nBILBAO\n' else E'ENVÍO\n\nGIPUZKOA\n' end || p_v2 || 'x V2 4g',
    'h17-' || p_tipo || p_v2 || p_jornada, motor.fecha_local(p_ahora),
    case p_tipo when 'reparto' then 'operario' end, null,
    jsonb_build_array(jsonb_build_object('num', 4, 'texto', p_v2 || 'x V2 4g', 'clase', 'producto',
                                         'destino_id', pg_temp.d(case p_tipo when 'reparto' then 'BILBAO' else 'GIPUZKOA' end),
                                         'cantidad', p_v2, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', p_v2, 'en_almacen', p_v2 - p_faltan,
                                         'faltan', p_faltan, 'aviso', null, 'orden', 1)),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d(case p_tipo when 'reparto' then 'BILBAO' else 'GIPUZKOA' end),
                                         'items', jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g',
                                                                                       'cantidad', p_v2, 'orden', 1)))),
    true, p_ahora) $$;
-- Un pedido con «coge / haz» (lo calcula la función del servidor).
create function pg_temp.elementos(p_coge integer, p_haz integer) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', p_coge + p_haz, 'coge', p_coge,
                                              'haz', p_haz, 'en_almacen', p_coge, 'orden', 6500,
                                              'motivo', case when p_haz = 0 then 'Coge ' || p_coge || ' del almacén'
                                                             when p_coge = 0 then 'Haz ' || p_haz
                                                             else 'Coge ' || p_coge || ' del almacén y haz ' || p_haz end)) $$;
-- Una lectura de la hoja con V2 4g en el almacén (el resto de la hoja no hace falta).
create function pg_temp.lectura(p_v2 text, p_cuando timestamptz) returns uuid language sql as $$
  insert into public.lecturas_sheets (leido_en, motivo, correcto, datos)
  values (p_cuando, 'stock', true, jsonb_build_object('productos', jsonb_build_array(
    jsonb_build_object('nombre', 'V2', 'granel', '500', 'conTiendas', false, 'orden', 65,
                       'formatos', jsonb_build_array(jsonb_build_object('formato', '4g', 'almacen', p_v2))))))
  returning id $$;
create function pg_temp.motivo(p_tarea uuid) returns text language sql as $$
  select string_agg(motivo, ' / ' order by orden_sugerido) from public.tarea_elementos where tarea_id = p_tarea $$;
create function pg_temp.lineas(p_cajas integer) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', p_cajas)) $$;
create function pg_temp.pedido(p_persona uuid, p_id uuid, p_cliente text, p_entrega text, p_destino uuid, p_cajas integer,
                               p_ahora timestamptz, p_coge integer default 0)
returns jsonb language plpgsql as $$
declare
  r jsonb := public.servidor_preparar_pedido(p_persona, p_id, p_entrega, p_destino, p_ahora);
begin
  if r ? 'error' or r ? 'previo' then return r; end if;
  return public.servidor_guardar_pedido_cliente(
    p_persona, p_id, p_cliente, p_entrega, p_destino,
    case when p_entrega = 'nacex' then E'Nombre Apellido\nCalle Mayor 1, 48001 Bilbao\n600 000 000' end,
    pg_temp.lineas(p_cajas), (r ->> 'fecha')::date, (r ->> 'jornada_id')::uuid, null,
    case when p_entrega = 'nacex' then pg_temp.elementos(p_coge, p_cajas - p_coge) end, p_ahora)
    || jsonb_build_object('preparado', r);
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  c_a constant uuid := 'a1000000-0000-4000-a000-000000000001';
  c_b constant uuid := 'a1000000-0000-4000-a000-000000000002';
  c_n constant uuid := 'a1000000-0000-4000-a000-000000000003';
  c_n2 constant uuid := 'a1000000-0000-4000-a000-000000000004';
  c_n3 constant uuid := 'a1000000-0000-4000-a000-000000000005';
  c_v constant uuid := 'a1000000-0000-4000-a000-000000000006';
  c_v2 constant uuid := 'a1000000-0000-4000-a000-000000000007';
  c_l constant uuid := 'a1000000-0000-4000-a000-000000000008';
  c_g constant uuid := 'a1000000-0000-4000-a000-000000000009';
  mar uuid;
  mie uuid;
  vie uuid;
  lun uuid;
  r jsonb;
  v_rep uuid;
  v_a uuid;
  v_b uuid;
  v_n uuid;
  v_g uuid;
  t public.tareas;
  v_bolsas uuid;
  v_limite timestamptz;
begin
  -- ===== Martes 24/11: recoger en tienda =====
  -- P-03 y P-05: frases y celdas del almacén (vacía, negativa o con decimales, como en R1).
  perform pg_temp.comprobar('Frases «coge / haz» y almacén vacío, negativo o con decimales (P-03, P-05)',
    motor.texto_coge_haz(2, 0) = 'Coge 2 del almacén' and motor.texto_coge_haz(0, 3) = 'Haz 3'
    and motor.texto_coge_haz(1, 1) = 'Coge 1 del almacén y haz 1'
    and motor.cajas_hoja('') = 0 and motor.cajas_hoja(null) = 0 and motor.cajas_hoja('-3') = 0
    and motor.cajas_hoja('2,5') = 2 and motor.cajas_hoja(' 7 ') = 7 and motor.cajas_hoja('abc') = 0
    and motor.clave_ref('v2 ', '4 g') = 'V24G');

  mar := motor.generar_jornada(op, '2026-11-24');
  perform pg_temp.lectura('30', '2026-11-24 08:30+01');
  r := pg_temp.pedido(adm, c_a, 'Ane', 'tienda', pg_temp.d('BILBAO'), 3, '2026-11-24 08:00+01');
  v_a := (r -> 'pedido' ->> 'id')::uuid;
  perform pg_temp.comprobar('Tienda, antes del reparto de hoy: espera al reparto de hoy, sin tarea todavía',
    r -> 'pedido' ->> 'estado' = 'esperando_reparto' and r -> 'pedido' ->> 'fecha' = '2026-11-24'
    and r -> 'pedido' ->> 'entrega_texto' = 'Recoger en Bilbao' and r -> 'tarea' = 'null'::jsonb
    and not exists (select 1 from public.tareas where jornada_id = mar and clave like 'pedido_tienda:%'), r::text);
  r := pg_temp.pedido(adm, c_a, 'Ane', 'tienda', pg_temp.d('BILBAO'), 3, '2026-11-24 08:01+01');
  perform pg_temp.comprobar('Repetir con el mismo id_cliente: el mismo pedido, sin duplicar',
    (r -> 'previo' ->> 'id')::uuid = v_a
    and (public.servidor_guardar_pedido_cliente(adm, c_a, 'Ane', 'tienda', pg_temp.d('BILBAO'), null, pg_temp.lineas(3),
                                                '2026-11-24', null, null, null, '2026-11-24 08:01+01') ->> 'ya_guardado')::boolean
    and (select count(*) from public.pedidos_cliente where id_cliente = c_a) = 1, r::text);
  perform pg_temp.comprobar('Tienda: solo las del reparto (Donosti y Gipuzkoa no); entrega no válida',
    pg_temp.pedido(adm, c_l, 'X', 'tienda', pg_temp.d('DONOSTI'), 1, '2026-11-24 08:02+01') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and pg_temp.pedido(adm, c_l, 'X', 'tienda', pg_temp.d('GIPUZKOA'), 1, '2026-11-24 08:02+01') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and pg_temp.pedido(adm, c_l, 'X', 'correo', null, 1, '2026-11-24 08:02+01') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS');
  r := public.servidor_preparar(adm, '2026-11-24 08:40+01');
  perform pg_temp.comprobar('servidor_preparar lleva los pedidos de tienda que esperan al reparto de hoy',
    r -> 'pedidos_tienda' = jsonb_build_array(jsonb_build_object('id', v_a, 'cliente', 'Ane', 'destino_id', pg_temp.d('BILBAO'),
                                                                 'lineas', pg_temp.lineas(3))), r -> 'pedidos_tienda' #>> '{}');

  -- El reparto de hoy (V2 4g: 20 pedidas, faltan 5) y el pedido de Ane asignado con su «coge / haz».
  r := pg_temp.guardar(mar, 'reparto', 20, 5, '2026-11-24 08:50+01');
  v_rep := (r ->> 'reparto_id')::uuid;
  r := public.servidor_asignar_pedidos(adm, v_rep,
         jsonb_build_array(jsonb_build_object('pedido_id', v_a, 'elementos', pg_temp.elementos(0, 3))), '2026-11-24 08:50+01');
  t := pg_temp.tarea(mar, 'pedido_tienda:%');
  v_bolsas := (select id from public.tareas where jornada_id = mar and clave = 'bolsas');
  perform pg_temp.comprobar('Al guardar el reparto: tarea «Hay un pedido de cliente para dejar en Bilbao · Ane», después de la producción y con la hora de las bolsas',
    r -> 'pedidos' -> 0 ->> 'estado' = 'por_preparar'
    and t.titulo = 'Hay un pedido de cliente para dejar en Bilbao · Ane' and t.requiere_clave = 'produccion_reparto'
    and t.hora_limite = (select hora_limite from public.tareas where id = v_bolsas) and t.obligatoria
    and (select reparto_id = v_rep and tarea_id = t.id from public.pedidos_cliente where id = v_a), r::text);
  perform pg_temp.comprobar('Su lista (el «coge / haz» aún no: se calcula al salir la tarea) y la producción del reparto es solo la oficial',
    (select motivo is null and cantidad = 3 from public.tarea_elementos where tarea_id = t.id)
    and (select sum(cantidad) from public.tarea_elementos e join public.tareas p on p.id = e.tarea_id
          where p.jornada_id = mar and p.clave = 'produccion_reparto') = 5);
  r := motor.tarea_json(v_bolsas);
  perform pg_temp.comprobar('Bolsa aparte en Bilbao: «Bolsa de reposición» y «Pedido de cliente · Ane»',
    (select jsonb_agg(e ->> 'bolsa' order by n) from jsonb_array_elements(r -> 'elementos') with ordinality x(e, n))
      = '["Bolsa de reposición", "Pedido de cliente · Ane"]'::jsonb
    and (select (e ->> 'cantidad')::int from jsonb_array_elements(r -> 'elementos') e where e ->> 'bolsa' like 'Pedido%') = 3,
    r -> 'elementos' #>> '{}');

  -- La tarea del pedido aparece en cuanto termina la producción del reparto, antes que las bolsas.
  perform pg_temp.hecha(mar, array['revision_inicial', 'pegar_reparto']);
  perform pg_temp.comprobar('Con la producción del reparto pendiente, toca la producción (no el pedido)',
    motor.tarea_activa_de(op, '2026-11-24 09:00+01') -> 'tarea' ->> 'clave' = 'produccion_reparto');
  perform pg_temp.hecha(mar, array['produccion_reparto']);
  r := motor.tarea_activa_de(op, '2026-11-24 09:05+01');
  perform pg_temp.comprobar('Terminada la producción, sale el pedido de cliente (antes que las bolsas) con su «coge / haz»: hoja 30 − reparto 20 → coge 3',
    r -> 'tarea' ->> 'clave' = t.clave and r -> 'tarea' -> 'elementos' -> 0 ->> 'motivo' = 'Coge 3 del almacén'
    and (select (calculo ->> 'en_almacen')::int = 10 from public.tarea_elementos where tarea_id = t.id), r::text);

  -- Tarea 14 (cambiada a propósito): con el reparto de hoy ya calculado y las bolsas sin terminar,
  -- el pedido entra en el de hoy al momento (antes iba al siguiente día de trabajo).
  r := pg_temp.pedido(op, c_b, 'Jon', 'tienda', pg_temp.d('PORTU'), 2, '2026-11-24 09:10+01');
  v_b := (r -> 'pedido' ->> 'id')::uuid;
  perform pg_temp.comprobar('Tienda, con el reparto de hoy ya calculado y las bolsas sin terminar: entra en el de hoy al momento',
    r -> 'pedido' ->> 'fecha' = '2026-11-24' and (r -> 'preparado' ->> 'reparto_id')::uuid = v_rep, r::text);
  r := public.servidor_asignar_pedidos(adm, v_rep, jsonb_build_array(jsonb_build_object('pedido_id', v_b, 'elementos',
         jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 6500)))),
         '2026-11-24 09:12+01');
  perform pg_temp.comprobar('… con su tarea y su bolsa aparte en Portugalete',
    r -> 'pedidos' -> 0 ->> 'estado' = 'por_preparar'
    and exists (select 1 from public.tareas where jornada_id = mar and clave = 'pedido_tienda:' || v_b)
    and exists (select 1 from public.tarea_elementos where tarea_id = v_bolsas and lote = 'pedido:' || v_b), r::text);

  -- Modificar el reparto: los pedidos se mantienen (tarea, lista y bolsa), sin duplicar.
  update public.tarea_elementos set cantidad_hecha = 1, estado = 'en_curso' where tarea_id = t.id;
  r := pg_temp.guardar(mar, 'reparto', 24, 9, '2026-11-24 09:30+01');
  perform public.servidor_asignar_pedidos(adm, (r ->> 'reparto_id')::uuid,
         jsonb_build_array(jsonb_build_object('pedido_id', v_a, 'elementos', pg_temp.elementos(1, 2))), '2026-11-24 09:30+01');
  perform pg_temp.comprobar('Al modificar el reparto el pedido se mantiene: la misma tarea, lo hecho, su «coge / haz» y una sola bolsa',
    (r ->> 'sustituye_a')::uuid = v_rep
    and (select count(*) from public.tareas where jornada_id = mar and clave = 'pedido_tienda:' || v_a) = 1
    and (select cantidad_hecha = 1 and motivo = 'Coge 3 del almacén' from public.tarea_elementos where tarea_id = t.id)
    and (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and lote = 'pedido:' || v_a) = 1
    and (select reparto_id from public.pedidos_cliente where id = v_a) = (r ->> 'reparto_id')::uuid, r::text);

  -- Retrasar la salida retrasa también el pedido de tienda.
  v_limite := (select hora_limite from public.tareas where id = t.id);
  perform motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-11-24 10:30+01');
  perform pg_temp.comprobar('Retrasar la salida 15 min retrasa también el pedido de tienda',
    (select hora_limite from public.tareas where id = t.id) = v_limite + interval '15 minutes');

  -- ===== Nacex =====
  r := pg_temp.pedido(op, c_n, 'Miren', 'nacex', null, 4, '2026-11-24 10:00+01', 1);
  v_n := (r -> 'pedido' ->> 'id')::uuid;
  t := pg_temp.tarea(mar, 'pedido_nacex:%');
  perform pg_temp.comprobar('Nacex (martes por la mañana): «Prepara el pedido de cliente (Nacex)» para la tarde, con los datos de envío',
    r -> 'pedido' ->> 'estado' = 'por_preparar' and r -> 'pedido' ->> 'fecha' = '2026-11-24'
    and t.titulo = 'Prepara el pedido de cliente (Nacex) · Miren'
    and t.porque = E'Datos de envío:\nNombre Apellido\nCalle Mayor 1, 48001 Bilbao\n600 000 000'
    and t.disponible_desde = '2026-11-24 15:30+01' and t.hora_limite = '2026-11-24 18:10+01'
    and pg_temp.motivo(t.id) is null
    and r -> 'tarea' ->> 'id' = t.id::text and r -> 'tarea_activa' is not null, r::text);
  perform pg_temp.comprobar('Nacex activado ese día: recuento a las 17:55 y salida a las 18:10 (sin el cierre de 18:15)',
    (select hay_envio from public.jornadas where id = mar)
    and (select estado = 'pendiente' and hora_programada = '2026-11-24 18:10+01' from public.tareas where jornada_id = mar and clave = 'nacex_salida')
    and (select estado = 'pendiente' from public.tareas where jornada_id = mar and clave = 'recuento_tarde_envio')
    and (select estado = 'cancelada' from public.tareas where jornada_id = mar and clave = 'recuento_tarde'));
  r := pg_temp.pedido(adm, c_n2, 'Koldo', 'nacex', null, 1, '2026-11-24 11:00+01');
  perform pg_temp.comprobar('Otro pedido de Nacex el mismo día: el mismo viaje (una sola salida a Nacex)',
    (select count(*) from public.tareas where jornada_id = mar and clave like 'pedido_nacex:%') = 2
    and (select count(*) from public.tareas where jornada_id = mar and clave in ('nacex_salida', 'recuento_tarde_envio')) = 2
    and r -> 'tarea_activa' = 'null'::jsonb, r::text);

  -- Lo comprometido hoy (R1c, rehecha en la Tarea 14): lo que aún no ha salido del almacén.
  r := public.servidor_preparar(adm, '2026-11-24 11:30+01') -> 'comprometido';
  perform pg_temp.comprobar('Antes de las bolsas: el reparto, los pedidos de tienda y los de Nacex siguen en el almacén; nada en camino',
    r -> 'reparto' = pg_temp.lineas(24) and r -> 'pedidos_tienda' = pg_temp.lineas(3) || pg_temp.lineas(2)
    and r -> 'pedidos_nacex' = pg_temp.lineas(4) || pg_temp.lineas(1) and r -> 'envio' = '[]'::jsonb
    and r -> 'en_camino' = '[]'::jsonb, r::text);
  -- Tarea 14 (cambiada a propósito): el recuento ya no decide si ha salido; sale con las bolsas listas.
  update public.tareas set estado = 'hecha', terminada_en = '2026-11-24 12:50+01' where jornada_id = mar and clave = 'recuento_manana';
  perform pg_temp.comprobar('Recuento hecho pero bolsas sin terminar: el reparto y los pedidos de tienda siguen en el almacén',
    public.servidor_preparar(adm, '2026-11-24 12:55+01') -> 'comprometido' -> 'reparto' = pg_temp.lineas(24));
  update public.tarea_elementos set cantidad_hecha = cantidad, estado = 'hecho' where tarea_id = v_bolsas;
  update public.tareas set estado = 'hecha', terminada_en = '2026-11-24 12:58+01' where id = v_bolsas;
  r := public.servidor_preparar(adm, '2026-11-24 13:00+01');
  perform pg_temp.comprobar('Bolsas listas (12:58): el reparto y los pedidos de tienda han salido y van en camino a su tienda; Nacex sigue en el almacén',
    r -> 'comprometido' -> 'reparto' = '[]'::jsonb and r -> 'comprometido' -> 'pedidos_tienda' = '[]'::jsonb
    and r -> 'comprometido' -> 'pedidos_nacex' = pg_temp.lineas(4) || pg_temp.lineas(1)
    and (select jsonb_object_agg(c.codigo, x -> 'cantidad') from jsonb_array_elements(r -> 'comprometido' -> 'en_camino') x
           join public.centros_trabajo c on c.id = (x ->> 'destino_id')::uuid) = '{"BILBAO": 27, "PORTU": 2}'::jsonb
    and r -> 'almacen' -> 'salido' = pg_temp.lineas(29), r::text);

  -- Un pedido de tienda que llega con las bolsas ya listas va en el siguiente reparto.
  r := pg_temp.pedido(op, c_g, 'Gorka', 'tienda', pg_temp.d('PORTU'), 2, '2026-11-24 13:05+01');
  v_g := (r -> 'pedido' ->> 'id')::uuid;
  perform pg_temp.comprobar('Tienda, con las bolsas ya listas: va en el del siguiente día de trabajo',
    r -> 'pedido' ->> 'fecha' = '2026-11-25' and r -> 'pedido' ->> 'estado_texto' = 'Va en el próximo reparto a Portugalete (desde el 25/11)'
    and r -> 'preparado' -> 'reparto_id' = 'null'::jsonb, r::text);
  r := public.servidor_asignar_pedidos(adm, (select reparto_id from public.pedidos_cliente where id = v_a),
         jsonb_build_array(jsonb_build_object('pedido_id', v_g, 'elementos', '[]'::jsonb)), '2026-11-24 13:06+01');
  perform pg_temp.comprobar('Aunque se pida, un pedido de mañana no entra en el reparto de hoy',
    r -> 'pedidos' = '[]'::jsonb and (select jornada_id is null from public.pedidos_cliente where id = v_g), r::text);

  -- Por la tarde, primero la revisión del envío y después el pedido de Nacex.
  perform pg_temp.hecha(mar, array['produccion_reparto', 'salida_reparto', 'efectivo_reporte']);
  update public.tareas set estado = 'hecha' where jornada_id = mar and clave like 'pedido_tienda:%';
  perform pg_temp.comprobar('A las 15:31 toca la revisión del envío',
    motor.tarea_activa_de(op, '2026-11-24 15:31+01') -> 'tarea' ->> 'clave' = 'revisar_envio');
  perform pg_temp.hecha(mar, array['revisar_envio']);
  -- Tarea 14 (cambiada a propósito): «coge / haz» con el almacén ahora = hoja + producido − salido desde su recuento.
  -- Hoja de las 08:30 (30, sin recuento anterior): − 29 que salieron con las bolsas = 1.
  perform motor.calcular_pedido(t.id, '2026-11-24 13:00+01');
  perform pg_temp.comprobar('Nacex con la hoja de las 08:30: 30 − 29 que han salido con las bolsas → coge 1 y haz 3',
    pg_temp.motivo(t.id) = 'Coge 1 del almacén y haz 3', pg_temp.motivo(t.id));
  -- La hoja de las 13:30 recoge el recuento de las 12:50, que fue antes de las bolsas (aún las contaba: 30).
  perform pg_temp.lectura('30', '2026-11-24 13:30+01');
  update public.tarea_elementos set calculo = '{}', motivo = null where tarea_id = t.id;
  r := motor.tarea_activa_de(op, '2026-11-24 15:40+01');
  perform motor.calcular_pedido(x.id, '2026-11-24 15:40+01')
     from public.tareas x where x.jornada_id = mar and x.clave like 'pedido_nacex:%';
  perform pg_temp.comprobar('… y después sale un pedido de Nacex; con la hoja del recuento: Miren coge 1 y hace 3; Koldo (llegó después) hace 1',
    r -> 'tarea' ->> 'clave' like 'pedido_nacex:%' and pg_temp.motivo(t.id) = 'Coge 1 del almacén y haz 3'
    and pg_temp.motivo((select id from public.tareas where jornada_id = mar and clave like 'pedido_nacex:%' and id <> t.id)) = 'Haz 1',
    r::text);

  -- Pedidos abiertos: el de tienda (preparado hoy), los de Nacex (por preparar) y el de mañana (esperando).
  r := motor.pedidos_cliente_abiertos_de(adm, '2026-11-24 16:00+01');
  perform pg_temp.comprobar('pedidos_cliente_abiertos: cliente, entrega, estado y fecha',
    (r ->> 'total')::int = 5
    and (select jsonb_agg(jsonb_build_array(p ->> 'cliente', p ->> 'estado') order by p ->> 'cliente') from jsonb_array_elements(r -> 'pedidos') p)
        = '[["Ane", "preparado"], ["Gorka", "esperando_reparto"], ["Jon", "preparado"], ["Koldo", "por_preparar"], ["Miren", "por_preparar"]]'::jsonb
    and (select p ->> 'estado_texto' from jsonb_array_elements(r -> 'pedidos') p where p ->> 'cliente' = 'Ane')
        = 'Preparado: va en el reparto del 24/11', r::text);

  -- Nacex fuera de hora (martes 18:20): el siguiente día de trabajo, con su jornada preparada.
  r := pg_temp.pedido(adm, c_n3, 'Itziar', 'nacex', null, 2, '2026-11-24 18:05+01');
  mie := (select id from public.jornadas where persona_id = op and fecha = '2026-11-25');
  perform pg_temp.comprobar('Nacex después de las 18:00: va al día siguiente, con Nacex activado ese día',
    r -> 'pedido' ->> 'fecha' = '2026-11-25' and mie is not null
    and (select hay_envio from public.jornadas where id = mie)
    and exists (select 1 from public.tareas where jornada_id = mie and clave like 'pedido_nacex:%'), r::text);

  -- ===== Miércoles 25/11: lo que no se hizo pasa con su lista; nada en camino =====
  -- El operario pasa el pedido de Koldo al día siguiente (la producción ha llegado tarde).
  r := motor.aplazar_pedido_nacex_de(op, (select id from public.pedidos_cliente where id_cliente = c_n2), 'Producción tarde',
                                     '2026-11-24 17:30+01');
  perform pg_temp.comprobar('Pasar un pedido de Nacex al día siguiente: su tarea pasa al miércoles (por la tarde, Nacex activado) con su lista',
    r -> 'pedido' ->> 'fecha' = '2026-11-25' and r -> 'pedido' ->> 'estado' = 'por_preparar' and r -> 'tarea_activa' is not null
    and exists (select 1 from public.tareas x join public.pedidos_cliente pc on pc.tarea_id = x.id
                 where pc.id_cliente = c_n2 and x.jornada_id = mie and x.clave like 'pedido_nacex:%'
                   and x.hora_limite = '2026-11-25 18:10+01' and x.disponible_desde = '2026-11-25 15:30+01'
                   and (select count(*) from public.tarea_elementos where tarea_id = x.id) = 1)
    and (select motivo_no_hecha = 'Pasa al 25/11: Producción tarde' and estado = 'arrastrada' from public.tareas
          where jornada_id = mar and clave = 'pedido_nacex:' || (select id from public.pedidos_cliente where id_cliente = c_n2)), r::text);
  perform pg_temp.comprobar('Pasar al día siguiente: solo pedidos de Nacex sin preparar',
    motor.aplazar_pedido_nacex_de(op, v_a, null, '2026-11-24 17:31+01') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.aplazar_pedido_nacex_de(op, gen_random_uuid(), null, '2026-11-24 17:31+01') -> 'error' ->> 'codigo' = 'NO_ENCONTRADO');

  -- El de Miren queda sin hacer: al generar el miércoles pasa solo, como tarea de Nacex de ese día.
  mie := motor.generar_jornada(op, '2026-11-25');
  t := (select x from public.tareas x where x.jornada_id = mie and x.tarea_origen_id = t.id);
  perform pg_temp.comprobar('El pedido de Nacex sin hacer pasa al día siguiente como tarea de Nacex, con su lista (el «coge / haz» se recalcula al salir)',
    t.id is not null and t.clave = 'pedido_nacex:' || v_n and t.hora_limite = '2026-11-25 18:10+01'
    and (select tarea_id from public.pedidos_cliente where id = v_n) = t.id
    and (select count(*) = 1 and bool_and(motivo is null and cantidad = 4) from public.tarea_elementos where tarea_id = t.id)
    and (select hay_envio from public.jornadas where id = mie)
    and motor.pedido_json(v_n) ->> 'fecha' = '2026-11-25');
  r := public.servidor_preparar(adm, '2026-11-25 08:40+01');
  perform pg_temp.comprobar('Al día siguiente: el reparto de ayer ya no va en camino (hasta las 23:30) y el pedido de Gorka espera a este reparto',
    r -> 'comprometido' -> 'en_camino' = '[]'::jsonb
    and r -> 'pedidos_tienda' @> jsonb_build_array(jsonb_build_object('id', v_g)), r::text);

  -- ===== Viernes 27/11: Nacex por la mañana, con el reparto =====
  perform pg_temp.limpiar();
  vie := motor.generar_jornada(op, '2026-11-27');
  perform motor.fijar_sale(vie, 'operario');
  r := pg_temp.pedido(op, c_v, 'Unai', 'nacex', null, 2, '2026-11-27 09:00+01', 2);
  t := pg_temp.tarea(vie, 'pedido_nacex_viernes:%');
  perform pg_temp.comprobar('Viernes: el pedido de Nacex se prepara antes de las 10:45 y lo lleva quien sale de reparto',
    t.hora_limite = '2026-11-27 10:45+01' and t.titulo = 'Prepara el pedido de cliente (Nacex) · Unai'
    and (select hay_envio from public.jornadas where id = vie)
    and exists (select 1 from public.tareas where jornada_id = vie and clave = 'nacex_viernes' and estado = 'pendiente'), r::text);
  perform pg_temp.guardar(vie, 'envio', 6, 0, '2026-11-27 09:10+01');
  -- Tarea 14 (cambiada a propósito): el envío preparado va en camino a Gipuzkoa; el pedido de Nacex sale del stock.
  update public.tarea_elementos e set cantidad_hecha = e.cantidad, estado = 'hecho'
    from public.tareas x where x.id = e.tarea_id and x.jornada_id = vie
     and (x.clave = 'preparar_envio_viernes' or x.clave like 'pedido_nacex_viernes:%');
  update public.tareas set estado = 'hecha', terminada_en = '2026-11-27 10:40+01'
   where jornada_id = vie and (clave = 'preparar_envio_viernes' or clave like 'pedido_nacex_viernes:%');
  perform pg_temp.hecha(vie, array['recuento_manana']);
  r := public.servidor_preparar(adm, '2026-11-27 13:00+01') -> 'comprometido';
  perform pg_temp.comprobar('Viernes: el envío preparado va en camino a Gipuzkoa; el pedido de Nacex no (sale del stock)',
    r -> 'envio' = '[]'::jsonb and r -> 'pedidos_nacex' = '[]'::jsonb
    and r -> 'en_camino' = jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'), 'producto', 'V2',
                                                                'formato', '4g', 'cantidad', 6)), r::text);
  r := pg_temp.pedido(op, c_v2, 'Leire', 'nacex', null, 1, '2026-11-27 11:00+01');
  lun := (select id from public.jornadas where persona_id = op and fecha = '2026-11-30');
  perform pg_temp.comprobar('Viernes después de las 10:45: al lunes',
    r -> 'pedido' ->> 'fecha' = '2026-11-30' and exists (select 1 from public.tareas where jornada_id = lun and clave like 'pedido_nacex:%'),
    r::text);

  -- ===== Lunes 30/11: ya hay envío (el lunes siempre): Nacex una sola vez =====
  update public.tareas set estado = 'hecha' where jornada_id = vie and estado in ('pendiente', 'en_curso', 'bloqueada');
  lun := motor.generar_jornada(op, '2026-11-30');
  r := pg_temp.pedido(op, c_l, 'Nerea', 'nacex', null, 1, '2026-11-30 09:00+01');
  perform pg_temp.comprobar('Con envío ese día, el pedido de Nacex va en el mismo viaje (sin duplicar tareas)',
    (select count(*) from public.tareas where jornada_id = lun and clave in ('nacex_salida', 'recuento_tarde_envio')) = 2
    and (select count(*) from public.tareas where jornada_id = lun and clave like 'pedido_nacex:%') = 2, r::text);
end;
$$;

-- Permisos
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.pedidos_cliente_abiertos();
begin
  perform pg_temp.comprobar('Operario: ve los pedidos abiertos (y sus datos de envío); no las funciones del servidor',
    (r ->> 'total')::int >= 1 and (select count(*) from public.pedidos_cliente where datos_envio is not null) >= 1
    and pg_temp.rechazada($q$select public.servidor_preparar_pedido(gen_random_uuid(), gen_random_uuid(), 'tienda', null)$q$)
    and pg_temp.rechazada($q$select public.servidor_asignar_pedidos(gen_random_uuid(), gen_random_uuid(), '[]')$q$)
    and pg_temp.rechazada($q$select public.servidor_guardar_pedido_cliente(gen_random_uuid(), gen_random_uuid(), 'x', 'tienda',
                                null, null, '[]', current_date, null, null, null)$q$)
    and pg_temp.rechazada($q$insert into public.pedidos_cliente (id_cliente, cliente, entrega, destino_id, lineas, fecha_objetivo,
                                registrado_por, registrado_en) values (gen_random_uuid(), 'x', 'tienda',
                                (select id from public.centros_trabajo limit 1), '[]', current_date, auth.uid(), now())$q$), r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.pedidos_cliente_abiertos();
begin
  perform pg_temp.comprobar('Administración: también ve los pedidos abiertos', (r ->> 'total')::int >= 1, r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-0000000000ff');
do $$
declare
  r jsonb := public.pedidos_cliente_abiertos();
begin
  perform pg_temp.comprobar('Usuario sin ficha: NO_AUTORIZADO y no ve ningún pedido',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO' and (select count(*) from public.pedidos_cliente) = 0
    and public.aplazar_pedido_nacex(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text);
end;
$$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se ven los pedidos ni se usan las funciones del servidor',
    pg_temp.rechazada($q$select public.pedidos_cliente_abiertos()$q$)
    and pg_temp.rechazada($q$select count(*) from public.pedidos_cliente$q$)
    and pg_temp.rechazada($q$select public.servidor_preparar_pedido(gen_random_uuid(), gen_random_uuid(), 'tienda', null)$q$)
    and pg_temp.rechazada($q$select public.aplazar_pedido_nacex(gen_random_uuid())$q$));
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
