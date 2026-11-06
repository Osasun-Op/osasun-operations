-- Prueba 42 · Lo que tiene hora entra también entre dos referencias (Tarea 37; ESTADO §6.4 v1.68, primer punto).
-- El caso del 06/11, rehecho el martes 08/12/2026: bolsas hechas a las 10:23, +35 % empezado a las 10:25, V2 terminada a
-- las 10:43; a las 10:45 sale la salida del reparto y el +35 % queda pausado con lo hecho, y vuelve a salir después.
-- El miércoles 09/12, a mitad de una referencia, la salida espera a que la termine. El jueves 10/12, una obligatoria en
-- curso no se pausa, y «Orden y limpieza» en curso sí, al llegar el recuento. Y sin turno empezado, nada cambia.
-- Cuenta y nombres inventados. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
update public.turnos_tienda set terminado_en = now(), terminado_solo = true
 where persona_tienda_id is null and terminado_en is null
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.a(p_dia date, p_hora text) returns timestamptz language sql as $$
  select motor.en_local(p_dia, p_hora::time) $$;
create function pg_temp.toca(p_dia date, p_hora text) returns text language sql as $$
  select motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a(p_dia, p_hora)) -> 'tarea' ->> 'clave' $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.estado(p_jornada uuid, p_clave text) returns text language sql as $$
  select estado from public.tareas where jornada_id = p_jornada and clave = p_clave $$;
create function pg_temp.id(p_jornada uuid, p_clave text) returns uuid language sql as $$
  select id from public.tareas where jornada_id = p_jornada and clave = p_clave $$;
create function pg_temp.ref(p_jornada uuid, p_producto text) returns uuid language sql as $$
  select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
   where t.jornada_id = p_jornada and t.clave = 'cola_stock' and e.producto = p_producto $$;

-- Un día con reparto que sale el operario: turno empezado a las 08:30, reparto guardado a las 08:50, producción y bolsas
-- hechas (bolsas a las 10:23) y tres referencias en el +35 %.
create function pg_temp.dia_con_reparto(p_dia date) returns uuid language plpgsql as $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada(op, p_dia);
  v_s uuid;
begin
  perform motor.empezar_turno_almacen_de(op, pg_temp.a(p_dia, '08:30'));
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a(p_dia, '08:30'), terminada_en = pg_temp.a(p_dia, '08:45')
   where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto');
  perform public.servidor_guardar_reparto(
    adm, j, 'reparto', E'REPARTO\nSALE: ALMACÉN\n\nBILBAO\n20x V2 4g', 'h42-' || p_dia, p_dia, 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '20x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 20, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 20, 'en_almacen', 0, 'faltan', 20, 'aviso', null, 'orden', 1)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1)))),
    true, pg_temp.a(p_dia, '08:50'));
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a(p_dia, '09:00'), terminada_en = pg_temp.a(p_dia, '10:00')
   where jornada_id = j and clave = 'produccion_reparto';
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a(p_dia, '10:00'), terminada_en = pg_temp.a(p_dia, '10:23')
   where jornada_id = j and clave = 'bolsas';
  -- Lo demás de la mañana, hecho; quedan la salida, el recuento y las colas.
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(p_dia, '10:20')
   where jornada_id = j and estado = 'pendiente' and disponible_desde < pg_temp.a(p_dia, '13:00')
     and clave not in ('salida_reparto', 'recuento_manana') and clave not like 'cola_%';
  v_s := pg_temp.id(j, 'cola_stock');
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, orden_sugerido)
  values (v_s, 'referencia_produccion', 'manana', 'V2', '4g', 4, 1),
         (v_s, 'referencia_produccion', 'manana', 'BZ1', '4g', 4, 2),
         (v_s, 'referencia_produccion', 'manana', 'Indoor', '4g', 3, 3);
  return j;
end; $$;

-- 1. El caso del 06/11 (martes 08/12)
select pg_temp.dia_con_reparto('2026-12-08');
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  dia constant date := '2026-12-08';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-08');
  v_s uuid := pg_temp.id(j, 'cola_stock');
  r jsonb;
begin
  perform pg_temp.comprobar('10:24: con las bolsas hechas y antes de la salida, el +35 %', pg_temp.toca(dia, '10:24') = 'cola_stock',
    pg_temp.toca(dia, '10:24'));
  perform motor.iniciar_tarea_de(op, v_s, pg_temp.a(dia, '10:25'));
  perform motor.iniciar_elemento_de(op, pg_temp.ref(j, 'V2'), pg_temp.a(dia, '10:26'));
  perform motor.terminar_elemento_de(op, pg_temp.ref(j, 'V2'), pg_temp.a(dia, '10:43'));
  perform pg_temp.comprobar('10:43: V2 terminada, dos minutos antes de la salida: sigue el +35 %',
    pg_temp.estado(j, 'cola_stock') = 'en_curso' and pg_temp.toca(dia, '10:44') = 'cola_stock', pg_temp.toca(dia, '10:44'));
  r := motor.tarea_activa_de(op, pg_temp.a(dia, '10:45'));
  perform pg_temp.comprobar('10:45, sin otra referencia empezada: sale la salida del reparto',
    r -> 'tarea' ->> 'clave' = 'salida_reparto', r::text);
  perform pg_temp.comprobar('… y el +35 % queda pausado con lo hecho (V2), y en «Hoy» consta la interrupción por la salida',
    pg_temp.estado(j, 'cola_stock') = 'pendiente'
    and (select estado = 'hecho' and cantidad_hecha = 4 from public.tarea_elementos where id = pg_temp.ref(j, 'V2'))
    and motor.interrupciones_tarea(v_s) -> 0 ->> 'por' = (select titulo from public.tareas where id = pg_temp.id(j, 'salida_reparto'))
    and (motor.interrupciones_tarea(v_s) -> 0 ->> 'a_las')::timestamptz = pg_temp.a(dia, '10:45'),
    motor.interrupciones_tarea(v_s)::text);
  perform motor.iniciar_tarea_de(op, pg_temp.id(j, 'salida_reparto'), pg_temp.a(dia, '10:46'));
  perform motor.terminar_tarea_de(op, pg_temp.id(j, 'salida_reparto'), null, null, pg_temp.a(dia, '10:48'));
  perform pg_temp.comprobar('10:46: el reparto sale a su hora (no a las 12:22)',
    motor.salida_reparto_en(j, pg_temp.a(dia, '10:49')) = pg_temp.a(dia, '10:46'),
    motor.salida_reparto_en(j, pg_temp.a(dia, '10:49'))::text);
  perform pg_temp.comprobar('10:49: vuelve a salir el +35 %, donde se quedó',
    pg_temp.toca(dia, '10:49') = 'cola_stock'
    and (select count(*) from public.tarea_elementos where tarea_id = v_s and estado = 'hecho') = 1, pg_temp.toca(dia, '10:49'));
end;
$$;

-- 2. A mitad de una referencia, espera a que la termine (miércoles 09/12)
select pg_temp.dia_con_reparto('2026-12-09');
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  dia constant date := '2026-12-09';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-09');
  v_s uuid := pg_temp.id(j, 'cola_stock');
begin
  perform motor.iniciar_tarea_de(op, v_s, pg_temp.a(dia, '10:25'));
  perform motor.iniciar_elemento_de(op, pg_temp.ref(j, 'BZ1'), pg_temp.a(dia, '10:40'));
  perform pg_temp.comprobar('10:46, a mitad de BZ1: la salida espera; sigue el +35 %',
    pg_temp.toca(dia, '10:46') = 'cola_stock' and pg_temp.estado(j, 'cola_stock') = 'en_curso', pg_temp.toca(dia, '10:46'));
  perform motor.terminar_elemento_de(op, pg_temp.ref(j, 'BZ1'), pg_temp.a(dia, '10:52'));
  perform pg_temp.comprobar('10:52, al terminar BZ1: entra la salida, como siempre (punto de encaje)',
    pg_temp.estado(j, 'cola_stock') = 'pendiente' and pg_temp.toca(dia, '10:52') = 'salida_reparto', pg_temp.toca(dia, '10:52'));
end;
$$;

-- 3. Jueves 10/12: una obligatoria en curso no se pausa; «Orden y limpieza» en curso, sí, al llegar el recuento
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  dia constant date := '2026-12-10';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-10');
  v_ob uuid;
  v_o uuid;
  v_toca text;
begin
  perform prueba.fijar_condicion(j, 'sale', 'administracion');
  -- Antes de empezar el turno: «Orden y limpieza» en curso (de otro turno) no se toca.
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(dia, '08:20')
   where jornada_id = j and estado = 'pendiente' and clave <> 'recuento_manana' and clave not like 'cola_orden%';
  v_o := (select id from public.tareas where jornada_id = j and clave like 'cola_orden%' and estado = 'pendiente' limit 1);
  update public.tareas set estado = 'en_curso', iniciada_en = pg_temp.a(dia, '08:15') where id = v_o;
  v_toca := pg_temp.toca(dia, '08:25');
  perform pg_temp.comprobar('Sin turno empezado: nada sale y nada se pausa',
    v_toca is null and (select estado from public.tareas where id = v_o) = 'en_curso', v_toca);
  update public.tareas set estado = 'pendiente' where id = v_o;
  perform motor.empezar_turno_almacen_de(op, pg_temp.a(dia, '08:30'));

  -- Una obligatoria de Administración, sin referencias, en curso desde las 12:30.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, obligatoria, creada_por)
  values (j, 'admin:palets', 'administracion', 'Ordena los palés del pasillo', pg_temp.a(dia, '12:00'), true, adm)
  returning id into v_ob;
  perform motor.iniciar_tarea_de(op, v_ob, pg_temp.a(dia, '12:30'));
  perform pg_temp.comprobar('12:46: la obligatoria en curso no se pausa; el recuento espera a que la termine',
    pg_temp.toca(dia, '12:46') = 'admin:palets' and (select estado from public.tareas where id = v_ob) = 'en_curso',
    pg_temp.toca(dia, '12:46'));
  perform motor.terminar_tarea_de(op, v_ob, null, null, pg_temp.a(dia, '12:47'));
  perform pg_temp.comprobar('12:47, al terminarla: el recuento', pg_temp.toca(dia, '12:47') = 'recuento_manana',
    pg_temp.toca(dia, '12:47'));

  -- «Orden y limpieza» en curso antes de la hora del recuento (con el recuento de otra hora).
  update public.tareas set disponible_desde = pg_temp.a(dia, '12:55'), hora_programada = pg_temp.a(dia, '12:55')
   where jornada_id = j and clave = 'recuento_manana';
  perform pg_temp.comprobar('12:48: sin nada más, «Orden y limpieza»', pg_temp.toca(dia, '12:48') like 'cola_orden%',
    pg_temp.toca(dia, '12:48'));
  perform motor.iniciar_tarea_de(op, v_o, pg_temp.a(dia, '12:48'));
  perform pg_temp.comprobar('12:54: «Orden y limpieza» sigue en curso',
    pg_temp.toca(dia, '12:54') like 'cola_orden%' and (select estado from public.tareas where id = v_o) = 'en_curso');
  v_toca := pg_temp.toca(dia, '12:55');
  perform pg_temp.comprobar('12:55: llega el recuento; «Orden y limpieza» se pausa',
    v_toca = 'recuento_manana' and (select estado from public.tareas where id = v_o) = 'pendiente'
    and exists (select 1 from public.registro_eventos where tarea_id = v_o and tipo = 'tarea_pausada'
                 and (datos ->> 'a_las')::timestamptz = pg_temp.a(dia, '12:55')),
    v_toca);
end;
$$;

-- 4. Una sola regla
select pg_temp.comprobar('Una sola regla: tras_elemento y tarea_activa_de usan motor.pausar_si_toca',
  (select prosrc from pg_proc where oid = 'motor.tras_elemento(uuid, uuid, boolean, timestamptz)'::regprocedure) like '%motor.pausar_si_toca(%'
  and (select prosrc from pg_proc where oid = 'motor.tarea_activa_de(uuid, timestamptz)'::regprocedure) like '%motor.pausar_si_toca(%'
  and (select prosrc from pg_proc where oid = 'motor.tras_elemento(uuid, uuid, boolean, timestamptz)'::regprocedure) not like '%escalon%'
  and not has_function_privilege('authenticated', 'motor.pausar_si_toca(uuid, uuid, timestamptz)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
