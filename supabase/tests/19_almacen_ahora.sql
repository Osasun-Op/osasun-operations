-- Prueba 19 · Cuenta del almacén entre recuentos, cajas en camino con hora y
-- pedidos de tienda que activan el reparto (Tarea 14, ESTADO v1.27 §5 R1c y
-- decisión del propietario del 28/10/2026). Lo que la base de datos da a las
-- funciones del servidor (servidor_preparar.almacen y .comprometido), el panel
-- (estado_actual.almacen_ahora) y el «coge / haz». Los cálculos con la hoja
-- (el hueco, el envío, R3) están en _compartido/*_test.ts. Semana del
-- 07/12/2026. Transacción deshecha al final.

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
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.c(p_producto text, p_cantidad integer) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('producto', p_producto, 'formato', '4g', 'cantidad', p_cantidad)) $$;
-- La hoja: V2 4g y BZ1 4g en el almacén.
create function pg_temp.lectura(p_v2 text, p_bz1 text, p_cuando timestamptz) returns uuid language sql as $$
  insert into public.lecturas_sheets (leido_en, motivo, correcto, datos)
  values (p_cuando, 'stock', true, jsonb_build_object('productos', jsonb_build_array(
    jsonb_build_object('nombre', 'V2', 'granel', '500', 'conTiendas', false, 'orden', 65,
                       'formatos', jsonb_build_array(jsonb_build_object('formato', '4g', 'almacen', p_v2))),
    jsonb_build_object('nombre', 'BZ1', 'granel', '500', 'conTiendas', false, 'orden', 61,
                       'formatos', jsonb_build_array(jsonb_build_object('formato', '4g', 'almacen', p_bz1))))))
  returning id $$;
-- Reparto (Bilbao) o envío (Gipuzkoa) de V2 4g, sin nada que producir; con 0 cajas, sin productos (solo pedidos).
create function pg_temp.guardar(p_jornada uuid, p_tipo text, p_v2 integer, p_ahora timestamptz)
returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, p_tipo,
    case p_tipo when 'reparto' then E'REPARTO\nSALE: YO' else 'ENVÍO' end
      || case when p_v2 > 0 then case p_tipo when 'reparto' then E'\n\nBILBAO\n' else E'\n\nGIPUZKOA\n' end || p_v2 || 'x V2 4g' else '' end,
    'h19-' || p_tipo || p_v2 || p_jornada, motor.fecha_local(p_ahora),
    case p_tipo when 'reparto' then 'administracion' end, null,
    case when p_v2 > 0 then jsonb_build_array(jsonb_build_object(
      'num', 4, 'texto', p_v2 || 'x V2 4g', 'clase', 'producto', 'cantidad', p_v2, 'producto', 'V2', 'formato', '4g',
      'destino_id', pg_temp.d(case p_tipo when 'reparto' then 'BILBAO' else 'GIPUZKOA' end))) else '[]'::jsonb end,
    case when p_v2 > 0 then jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', p_v2,
                                                                 'en_almacen', p_v2, 'faltan', 0, 'aviso', null, 'orden', 1))
         else '[]'::jsonb end,
    case when p_v2 > 0 then jsonb_build_array(jsonb_build_object(
      'destino_id', pg_temp.d(case p_tipo when 'reparto' then 'BILBAO' else 'GIPUZKOA' end),
      'items', jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', p_v2, 'orden', 1))))
         else '[]'::jsonb end,
    true, p_ahora) $$;
-- La tarea terminada a esa hora, con todo lo suyo marcado (bolsas listas, envío preparado, pedido preparado).
create function pg_temp.terminar(p_tarea uuid, p_a_las timestamptz) returns void language sql as $$
  update public.tarea_elementos set cantidad_hecha = cantidad, estado = 'hecho', terminado_en = p_a_las
   where tarea_id = p_tarea and tipo <> 'peticion';
  update public.tareas set estado = 'hecha', terminada_en = p_a_las where id = p_tarea $$;
create function pg_temp.tarea(p_jornada uuid, p_clave text) returns uuid language sql as $$
  select id from public.tareas where jornada_id = p_jornada and clave like p_clave order by creada_en desc limit 1 $$;
create function pg_temp.pedido(p_persona uuid, p_cliente text, p_entrega text, p_destino uuid, p_v2 integer, p_ahora timestamptz)
returns jsonb language plpgsql as $$
declare
  r jsonb := public.servidor_preparar_pedido(p_persona, gen_random_uuid(), p_entrega, p_destino, p_ahora);
begin
  if r ? 'error' then return r; end if;
  return public.servidor_guardar_pedido_cliente(
    p_persona, gen_random_uuid(), p_cliente, p_entrega, p_destino,
    case when p_entrega = 'nacex' then 'Nombre, dirección y teléfono' end, pg_temp.c('V2', p_v2),
    (r ->> 'fecha')::date, (r ->> 'jornada_id')::uuid, null,
    case when p_entrega = 'nacex' then pg_temp.c('V2', p_v2) end, p_ahora)
    || jsonb_build_object('preparado', r);
end;
$$;
-- Suma por tienda de lo que va en camino: { "BILBAO": 10, ... }.
create function pg_temp.en_camino(p_comprometido jsonb) returns jsonb language sql as $$
  select coalesce(jsonb_object_agg(c.codigo, x -> 'cantidad'), '{}'::jsonb)
    from jsonb_array_elements(p_comprometido -> 'en_camino') x join public.centros_trabajo c on c.id = (x ->> 'destino_id')::uuid $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  mar uuid;
  mie uuid;
  jue uuid;
  vie uuid;
  lun uuid;
  r jsonb;
  v_rep uuid;
  v_t uuid;
  v_a uuid;
begin
  -- ===== Martes 08/12: el recuento de la tarde (base del miércoles) =====
  mar := motor.generar_jornada(op, '2026-12-08');
  update public.tareas set estado = 'hecha', terminada_en = '2026-12-08 18:20+01' where jornada_id = mar and clave = 'recuento_tarde';
  update public.tareas set estado = 'hecha' where jornada_id = mar and estado in ('pendiente', 'en_curso', 'bloqueada');

  -- ===== Miércoles 09/12 =====
  mie := motor.generar_jornada(op, '2026-12-09');
  perform pg_temp.lectura('30', '4', '2026-12-09 08:30+01');
  -- El hueco: a las 09:30 se hacen 6 BZ1 4g para el stock (con 4 en la hoja).
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, cantidad_hecha, estado, terminado_en)
  values (pg_temp.tarea(mie, 'cola_stock'), 'referencia_produccion', 'manana', 'BZ1', '4g', 6, 6, 'hecho', '2026-12-09 09:30+01');
  r := public.servidor_preparar(adm, '2026-12-09 09:40+01') -> 'almacen';
  perform pg_temp.comprobar('Lo producido desde el último recuento (el de ayer por la tarde) suma: 6 BZ1 4g; nada ha salido',
    (r ->> 'recuento_en')::timestamptz = '2026-12-08 18:20+01' and r -> 'producido' = pg_temp.c('BZ1', 6)
    and r -> 'salido' = '[]'::jsonb and r -> 'producido_reparto' = '[]'::jsonb, r::text);
  r := motor.almacen_ahora_de(op, '2026-12-09 09:40+01');
  perform pg_temp.comprobar('Almacén ahora (panel): BZ1 4g hoja 4 + producido 6 = 10',
    r -> 'referencias' = jsonb_build_array(jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'hoja', 4, 'producido', 6,
                                                              'salido', 0, 'ahora', 10))
    and (r ->> 'datos_leidos_en')::timestamptz = '2026-12-09 08:30+01', r::text);

  -- Reparto (10 V2 4g a Bilbao) y bolsas listas a las 10:45.
  r := pg_temp.guardar(mie, 'reparto', 10, '2026-12-09 09:50+01');
  r := public.servidor_preparar(adm, '2026-12-09 10:00+01') -> 'comprometido';
  perform pg_temp.comprobar('Antes de las bolsas, el reparto aún no ha salido: comprometido, nada en camino',
    r -> 'reparto' = pg_temp.c('V2', 10) and r -> 'en_camino' = '[]'::jsonb, r::text);
  perform pg_temp.terminar(pg_temp.tarea(mie, 'bolsas'), '2026-12-09 10:45+01');
  r := public.servidor_preparar(adm, '2026-12-09 11:00+01');
  perform pg_temp.comprobar('Bolsas listas: el reparto sale del almacén (salido 10) y va en camino a Bilbao',
    r -> 'comprometido' -> 'reparto' = '[]'::jsonb and r -> 'almacen' -> 'salido' = pg_temp.c('V2', 10)
    and pg_temp.en_camino(r -> 'comprometido') = '{"BILBAO": 10}'::jsonb, r::text);
  perform pg_temp.comprobar('Almacén ahora (panel): V2 4g hoja 30 − salido 10 = 20',
    motor.almacen_ahora_de(op, '2026-12-09 11:00+01') -> 'referencias' @> jsonb_build_array(jsonb_build_object(
      'producto', 'V2', 'formato', '4g', 'hoja', 30, 'producido', 0, 'salido', 10, 'ahora', 20)));

  -- Recuento de la mañana (12:50): pone el almacén al día; lo que va en camino sigue.
  update public.tareas set estado = 'hecha', terminada_en = '2026-12-09 12:50+01' where jornada_id = mie and clave = 'recuento_manana';
  r := public.servidor_preparar(adm, '2026-12-09 13:00+01');
  perform pg_temp.comprobar('Cada recuento (también el de la mañana) pone a cero lo producido y lo salido; el recuento no borra lo que va en camino',
    (r -> 'almacen' ->> 'recuento_en')::timestamptz = '2026-12-09 12:50+01'
    and r -> 'almacen' -> 'producido' = '[]'::jsonb and r -> 'almacen' -> 'salido' = '[]'::jsonb
    and pg_temp.en_camino(r -> 'comprometido') = '{"BILBAO": 10}'::jsonb, r::text);
  perform pg_temp.comprobar('El reparto va en camino hasta las 23:30 de ese día',
    pg_temp.en_camino(motor.comprometido_en(mie, '2026-12-09 23:29+01')) = '{"BILBAO": 10}'::jsonb
    and pg_temp.en_camino(motor.comprometido_en(mie, '2026-12-09 23:31+01')) = '{}'::jsonb);

  -- Envío (miércoles, no solo el viernes): en camino desde que está preparado hasta las 11:59 del día siguiente.
  perform pg_temp.guardar(mie, 'envio', 4, '2026-12-09 15:40+01');
  perform pg_temp.terminar(pg_temp.tarea(mie, 'preparar_envio'), '2026-12-09 16:30+01');
  -- Pedido de Nacex (2 V2 4g: coge 1 y haz 1), preparado a las 17:00: sale del stock.
  r := pg_temp.pedido(op, 'Miren', 'nacex', null, 2, '2026-12-09 15:00+01');
  v_t := (r -> 'tarea' ->> 'id')::uuid;
  update public.tarea_elementos set calculo = '{"coge": 1, "haz": 1}' where tarea_id = v_t;
  perform pg_temp.terminar(v_t, '2026-12-09 17:00+01');
  r := public.servidor_preparar(adm, '2026-12-09 17:10+01');
  perform pg_temp.comprobar('El envío preparado sale (4) y va en camino a Gipuzkoa; el pedido de Nacex sale (2) y no va a ninguna tienda; de él solo se produjo 1',
    r -> 'almacen' -> 'salido' = pg_temp.c('V2', 6) and r -> 'almacen' -> 'producido' = pg_temp.c('V2', 1)
    and pg_temp.en_camino(r -> 'comprometido') = '{"BILBAO": 10, "GIPUZKOA": 4}'::jsonb, r::text);
  update public.tareas set estado = 'hecha', terminada_en = '2026-12-09 18:00+01' where jornada_id = mie and clave = 'recuento_tarde_envio';
  r := public.servidor_preparar(adm, '2026-12-09 18:05+01');
  perform pg_temp.comprobar('El recuento de la tarde también pone el almacén al día',
    r -> 'almacen' -> 'salido' = '[]'::jsonb and r -> 'almacen' -> 'producido' = '[]'::jsonb, r::text);
  update public.tareas set estado = 'hecha' where jornada_id = mie and estado in ('pendiente', 'en_curso', 'bloqueada');

  -- ===== Jueves 10/12 =====
  jue := motor.generar_jornada(op, '2026-12-10');
  perform pg_temp.comprobar('El envío de ayer sigue en camino hasta las 11:59 de hoy (el de hoy aún no hay); el reparto de ayer, no',
    pg_temp.en_camino(motor.comprometido_en(jue, '2026-12-10 11:58+01')) = '{"GIPUZKOA": 4}'::jsonb
    and pg_temp.en_camino(motor.comprometido_en(jue, '2026-12-10 12:00+01')) = '{}'::jsonb);

  -- Un pedido para recoger en tienda activa el reparto.
  r := pg_temp.pedido(adm, 'Ane', 'tienda', pg_temp.d('BILBAO'), 3, '2026-12-10 08:00+01');
  v_a := (r -> 'pedido' ->> 'id')::uuid;
  perform pg_temp.comprobar('Sin reparto todavía y con «Prepara el reparto» abierta: el pedido es para hoy',
    r -> 'pedido' ->> 'fecha' = '2026-12-10' and r -> 'pedido' ->> 'estado' = 'esperando_reparto'
    and r -> 'preparado' -> 'reparto_id' = 'null'::jsonb, r::text);
  perform motor.iniciar_tarea_de(op, pg_temp.tarea(jue, 'pegar_reparto'), '2026-12-10 08:10+01');
  r := motor.terminar_tarea_de(op, pg_temp.tarea(jue, 'pegar_reparto'), null, 'Hoy no hay reparto', '2026-12-10 08:11+01');
  perform pg_temp.comprobar('«Prepara el reparto» no se cierra sin reparto con un pedido esperando (ni con motivo)',
    r -> 'error' ->> 'codigo' = 'PEDIDO_ESPERANDO_REPARTO'
    and r -> 'error' ->> 'mensaje' = 'Hay un pedido de cliente para recoger en Bilbao (Ane). Prepara el reparto, aunque sea solo con el pedido.'
    and (select estado from public.tareas where id = pg_temp.tarea(jue, 'pegar_reparto')) = 'en_curso', r::text);

  -- Reparto solo con el pedido: sin productos; la función del servidor asigna el pedido.
  r := pg_temp.guardar(jue, 'reparto', 0, '2026-12-10 08:30+01');
  v_rep := (r ->> 'reparto_id')::uuid;
  perform public.servidor_asignar_pedidos(adm, v_rep, jsonb_build_array(jsonb_build_object('pedido_id', v_a,
            'elementos', jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 3, 'orden', 6500)))),
            '2026-12-10 08:30+01');
  perform pg_temp.comprobar('Reparto solo con el pedido: «Prepara el reparto» hecha, bolsas pendientes con la bolsa del pedido y su tarea',
    (select estado from public.tareas where id = pg_temp.tarea(jue, 'pegar_reparto')) = 'hecha'
    and (select estado = 'pendiente' and terminada_en is null from public.tareas where id = pg_temp.tarea(jue, 'bolsas'))
    and exists (select 1 from public.tarea_elementos where tarea_id = pg_temp.tarea(jue, 'bolsas') and lote = 'pedido:' || v_a)
    and exists (select 1 from public.tareas where jornada_id = jue and clave = 'pedido_tienda:' || v_a)
    and (select sale from public.jornadas where id = jue) = 'administracion', r::text);
  r := pg_temp.pedido(op, 'Jon', 'tienda', pg_temp.d('PORTU'), 2, '2026-12-10 09:00+01');
  perform pg_temp.comprobar('Con el reparto guardado y las bolsas sin terminar, otro pedido entra en el de hoy',
    r -> 'pedido' ->> 'fecha' = '2026-12-10' and (r -> 'preparado' ->> 'reparto_id')::uuid = v_rep, r::text);
  -- (guardar_pedido_cliente lo asigna en ese momento)
  perform public.servidor_asignar_pedidos(op, v_rep, jsonb_build_array(jsonb_build_object(
            'pedido_id', (r -> 'pedido' ->> 'id')::uuid, 'elementos', '[]'::jsonb)), '2026-12-10 09:00+01');
  perform pg_temp.terminar(pg_temp.tarea(jue, 'bolsas'), '2026-12-10 10:45+01');
  r := pg_temp.pedido(op, 'Gorka', 'tienda', pg_temp.d('PORTU'), 1, '2026-12-10 11:00+01');
  perform pg_temp.comprobar('Con las bolsas listas, el pedido va al siguiente día de trabajo',
    r -> 'pedido' ->> 'fecha' = '2026-12-11' and r -> 'preparado' -> 'reparto_id' = 'null'::jsonb, r::text);

  -- ===== Viernes 11/12: el pedido de Gorka va en el reparto =====
  update public.tareas set estado = 'hecha' where jornada_id = jue and estado in ('pendiente', 'en_curso', 'bloqueada');
  vie := motor.generar_jornada(op, '2026-12-11');
  perform pg_temp.comprobar('El pedido que espera aparece en servidor_preparar para el reparto del viernes',
    exists (select 1 from jsonb_array_elements(public.servidor_preparar(adm, '2026-12-11 08:30+01') -> 'pedidos_tienda') x
             where x ->> 'cliente' = 'Gorka'));
  r := pg_temp.guardar(vie, 'reparto', 5, '2026-12-11 08:40+01');
  perform public.servidor_asignar_pedidos(adm, (r ->> 'reparto_id')::uuid, jsonb_build_array(jsonb_build_object(
            'pedido_id', (select id from public.pedidos_cliente where cliente = 'Gorka' and fecha_objetivo = '2026-12-11'),
            'elementos', '[]'::jsonb)), '2026-12-11 08:40+01');
  update public.tareas set estado = 'hecha' where jornada_id = vie and estado in ('pendiente', 'en_curso', 'bloqueada');

  -- ===== Lunes 14/12: sin pedidos, «Prepara el reparto» se cierra con motivo; un pedido después va al día siguiente =====
  lun := motor.generar_jornada(op, '2026-12-14');
  perform motor.iniciar_tarea_de(op, pg_temp.tarea(lun, 'pegar_reparto'), '2026-12-14 08:40+01');
  r := motor.terminar_tarea_de(op, pg_temp.tarea(lun, 'pegar_reparto'), null, null, '2026-12-14 08:41+01');
  perform pg_temp.comprobar('Sin pedidos esperando, sigue pidiendo motivo (MOTIVO_OBLIGATORIO) y con motivo se cierra',
    r -> 'error' ->> 'codigo' = 'MOTIVO_OBLIGATORIO'
    and motor.terminar_tarea_de(op, pg_temp.tarea(lun, 'pegar_reparto'), null, 'Hoy no hay reparto', '2026-12-14 08:42+01')
        -> 'tarea' ->> 'estado' = 'hecha', r::text);
  r := pg_temp.pedido(adm, 'Leire', 'tienda', pg_temp.d('BILBAO'), 1, '2026-12-14 09:00+01');
  perform pg_temp.comprobar('Con «Prepara el reparto» ya cerrada sin reparto, el pedido va al siguiente día de trabajo',
    r -> 'pedido' ->> 'fecha' = '2026-12-15', r::text);
end;
$$;

-- estado_actual: el bloque almacen_ahora (solo Administración) ------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.estado_actual();
begin
  perform pg_temp.comprobar('estado_actual trae almacen_ahora (recuento, lectura, referencias y en camino) sin cambiar el resto',
    r ? 'almacen_ahora' and r -> 'almacen_ahora' ? 'recuento_en' and r -> 'almacen_ahora' ? 'referencias'
    and r -> 'almacen_ahora' ? 'en_camino' and r ? 'reparto_de_hoy' and r ? 'en_curso' and not r ? 'error', r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.estado_actual();
begin
  perform pg_temp.comprobar('El operario sigue sin poder usar estado_actual (NO_AUTORIZADO, sin almacen_ahora)',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO' and not r ? 'almacen_ahora', r::text);
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
