-- Prueba 27 · Quién hizo cada tarea y nada fuera del turno (Tarea 24, ESTADO v1.39).
-- Lo del 02/11 rehecho un lunes (14/12/2026), sale el operario: Administración guarda el reparto
-- a las 08:27 («Prepara el reparto» se cierra sola) y el operario termina el recuento a las 13:04.
-- El martes 15/12, lo no obligatorio que queda en curso al acabar el turno se pausa solo (opción B).
-- Desde la Tarea 35, con los botones: el operario empieza el turno y lo termina («Empezar turno», «Fin de turno»).
-- Transacción deshecha.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
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
create function pg_temp.h(p_hora text) returns timestamptz language sql as $$
  select ('2026-12-14 ' || p_hora || '+01')::timestamptz $$;
create function pg_temp.activa(p_hora text) returns jsonb language sql as $$
  select motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.h(p_hora)) $$;
create function pg_temp.toca(p_hora text) returns text language sql as $$
  select pg_temp.activa(p_hora) -> 'tarea' ->> 'clave' $$;
create function pg_temp.hoy(p_hora text, p_clave text) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.estado_actual_de(pg_temp.h(p_hora)) -> 'hoy') x
   where x ->> 'id' = (select t.id::text from public.tareas t join public.jornadas j on j.id = t.jornada_id
                        where j.persona_id = '00000000-0000-4000-a000-000000000001' and j.fecha = '2026-12-14'
                          and t.clave = p_clave) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  r jsonb;
  v_t uuid;
begin
  j := motor.generar_jornada(op, '2026-12-14');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform motor.empezar_turno_almacen_de(op, pg_temp.h('08:25'));

  -- 1. Quién hizo cada tarea ------------------------------------------------------------------
  -- 08:27: Administración guarda el reparto desde su cuenta; «Prepara el reparto» se cierra sola.
  r := public.servidor_guardar_reparto(
    adm, j, 'reparto', 'REPARTO 14/12', 'h-27', '2026-12-14', 'operario', null, '[]',
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 5, 'en_almacen', 0,
                                         'faltan', 5, 'aviso', null, 'orden', 1)),
    jsonb_build_array(jsonb_build_object('destino_id', (select id from public.centros_trabajo where codigo = 'BILBAO'),
      'items', jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 5, 'orden', 1)))),
    true, pg_temp.h('08:27'));
  perform pg_temp.comprobar('08:27: el reparto se guarda y «Prepara el reparto» queda hecha',
    r ->> 'error' is null and (select estado from public.tareas where jornada_id = j and clave = 'pegar_reparto') = 'hecha', r::text);
  -- 08:31–08:45: el operario hace la revisión inicial.
  v_t := (select id from public.tareas where jornada_id = j and clave = 'revision_inicial');
  perform motor.iniciar_tarea_de(op, v_t, pg_temp.h('08:31'));
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h('08:45'));
  perform pg_temp.comprobar('«Prepara el reparto», hecha por Administración (quien guardó el reparto)',
    pg_temp.hoy('08:50', 'pegar_reparto') ->> 'hecha_por' = (select nombre from public.personas where id = adm),
    pg_temp.hoy('08:50', 'pegar_reparto')::text);
  perform pg_temp.comprobar('La revisión inicial, hecha por el operario',
    pg_temp.hoy('08:50', 'revision_inicial') ->> 'hecha_por' = (select nombre from public.personas where id = op),
    pg_temp.hoy('08:50', 'revision_inicial')::text);
  perform pg_temp.comprobar('Lo no hecho trae hecha_por = null (el campo está)',
    pg_temp.hoy('08:50', 'produccion_reparto') ? 'hecha_por'
    and jsonb_typeof(pg_temp.hoy('08:50', 'produccion_reparto') -> 'hecha_por') = 'null',
    pg_temp.hoy('08:50', 'produccion_reparto')::text);

  -- 2. Pasada la hora, solo lo obligatorio; fuera del turno, ninguna tarea -----------------------------------------------------------
  -- Toda la mañana hecha salvo el +35 % (como el 02/11) y el recuento.
  update public.tareas set estado = 'hecha'
   where jornada_id = j and estado = 'pendiente' and disponible_desde < pg_temp.h('13:00')
     and clave not in ('recuento_manana', 'cola_stock') and clave not like 'cola_orden%';
  perform pg_temp.comprobar('12:40: dentro del turno sale el +35 %', pg_temp.toca('12:40') = 'cola_stock', pg_temp.toca('12:40'));
  v_t := (select id from public.tareas where jornada_id = j and clave = 'recuento_manana');
  perform pg_temp.comprobar('12:45: el recuento', pg_temp.toca('12:45') = 'recuento_manana', pg_temp.toca('12:45'));
  r := motor.iniciar_tarea_de(op, v_t, pg_temp.h('12:46'));
  perform pg_temp.comprobar('13:02, pasada la hora y con el turno abierto: el recuento en curso sigue en pantalla',
    pg_temp.toca('13:02') = 'recuento_manana', pg_temp.toca('13:02'));
  r := motor.fin_turno_almacen_de(op, false, pg_temp.h('13:03'));
  perform pg_temp.comprobar('13:03, «Fin de turno» con el recuento en curso: no se cierra, y el recuento sigue en curso',
    r -> 'error' ->> 'codigo' = 'RECUENTO_PENDIENTE'
    and not exists (select 1 from public.cierres where jornada_id = j)
    and (select estado from public.tareas where id = v_t) = 'en_curso', r::text);
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h('13:04'));
  perform pg_temp.comprobar('13:04: y se puede terminar', r ->> 'error' is null
    and (select estado from public.tareas where id = v_t) = 'hecha', r::text);
  perform pg_temp.comprobar('13:04 (lo del 02/11): sin tarea, no sale el +35 %; «siguiente» dice lo de las 15:30',
    pg_temp.activa('13:04') -> 'tarea' = 'null'::jsonb and pg_temp.activa('13:04') ->> 'siguiente' like '%15:30'
    and pg_temp.activa('13:04') -> 'turno' ->> 'mensaje' = 'Has terminado. Pulsa «Fin de turno».',
    pg_temp.activa('13:04')::text);
  r := motor.fin_turno_almacen_de(op, false, pg_temp.h('13:05'));
  perform pg_temp.comprobar('13:05, «Fin de turno»: el cierre de la mañana, cerrado por el operario',
    r ->> 'cierre' is not null
    and (select contenido -> 'turno_operario' from public.cierres where id = (r ->> 'cierre')::uuid)
        = '{"como": "operario", "empezado": "08:25", "terminado": "13:05", "al_dia_siguiente": false}', r::text);
  perform pg_temp.comprobar('14:30, entre turnos: tampoco', pg_temp.toca('14:30') is null, pg_temp.toca('14:30'));
  perform pg_temp.comprobar('15:31, sin empezar la tarde: nada', pg_temp.toca('15:31') is null, pg_temp.toca('15:31'));
  perform motor.empezar_turno_almacen_de(op, pg_temp.h('15:31'));
  perform pg_temp.comprobar('15:31, empieza la tarde: vuelve a salir lo de su hora (revisar el envío)',
    pg_temp.toca('15:31') = 'revisar_envio', pg_temp.toca('15:31'));
  update public.tareas set estado = 'hecha' where jornada_id = j and clave in ('revisar_envio', 'minis');
  perform pg_temp.comprobar('… y lo pendiente de la mañana (el +35 %)', pg_temp.toca('15:40') = 'cola_stock', pg_temp.toca('15:40'));
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente' and clave not like 'cola_orden%';
  perform pg_temp.comprobar('18:31, pasada la hora: nada, ni «Orden y limpieza»; «Has terminado»',
    pg_temp.toca('18:31') is null
    and pg_temp.activa('18:31') -> 'turno' ->> 'mensaje' = 'Has terminado. Pulsa «Fin de turno».', pg_temp.activa('18:31')::text);
end;
$$;

-- 3. Fin del turno: lo no obligatorio en curso se pausa solo -------------------------------------
create function pg_temp.h2(p_hora text) returns timestamptz language sql as $$
  select ('2026-12-15 ' || p_hora || '+01')::timestamptz $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  v_s uuid;
  v_a uuid;
  r jsonb;
begin
  j := motor.generar_jornada(op, '2026-12-15');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform motor.empezar_turno_almacen_de(op, pg_temp.h2('08:30'));
  update public.tareas set estado = 'hecha'
   where jornada_id = j and estado = 'pendiente' and disponible_desde < pg_temp.h2('13:00')
     and clave <> 'cola_stock' and clave not like 'cola_orden%';
  v_s := (select id from public.tareas where jornada_id = j and clave = 'cola_stock');
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, orden_sugerido)
  values (v_s, 'referencia_produccion', 'manana', 'Indoor', '4g', 6, 1),
         (v_s, 'referencia_produccion', 'manana', 'BZ1', '4g', 4, 2),
         (v_s, 'referencia_produccion', 'manana', 'V2', '4g', 3, 3);
  perform motor.iniciar_tarea_de(op, v_s, pg_temp.h2('12:20'));
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = 6, terminado_en = pg_temp.h2('12:35')
   where tarea_id = v_s and producto = 'Indoor';

  -- Tarea 35: a las 13:00, con el turno abierto, la pantalla pide la tarea activa y lo no obligatorio se pausa.
  perform motor.tarea_activa_de(op, pg_temp.h2('13:00'));
  perform pg_temp.comprobar('13:00, acaba la hora del turno: el +35 % (no obligatoria) en curso pasa a pendiente, con lo hecho',
    (select estado from public.tareas where id = v_s) = 'pendiente'
    and (select cantidad_hecha from public.tarea_elementos where tarea_id = v_s and producto = 'Indoor') = 6);
  r := motor.interrupciones_tarea(v_s);
  perform pg_temp.comprobar('«Hoy»: interrumpida a las 13:00 por «Fin del turno»',
    jsonb_array_length(r) = 1 and r -> 0 ->> 'por' = 'Fin del turno'
    and (r -> 0 ->> 'a_las')::timestamptz = pg_temp.h2('13:00') and r -> 0 -> 'siguio_a_las' = 'null'::jsonb, r::text);
  perform pg_temp.comprobar('13:01: sin tarea', motor.tarea_activa_de(op, pg_temp.h2('13:01')) -> 'tarea' = 'null'::jsonb);
  -- 13:03: termina la referencia que tenía entre manos (BZ1).
  r := motor.terminar_elemento_de(op, (select id from public.tarea_elementos where tarea_id = v_s and producto = 'BZ1'),
                                  pg_temp.h2('13:03'));
  perform pg_temp.comprobar('13:03: puede marcar la referencia que tenía entre manos, y la tarea sigue pausada',
    r ->> 'error' is null
    and (select estado from public.tarea_elementos where tarea_id = v_s and producto = 'BZ1') = 'hecho'
    and (select estado from public.tareas where id = v_s) = 'pendiente'
    and motor.tarea_activa_de(op, pg_temp.h2('13:04')) -> 'tarea' = 'null'::jsonb, r::text);

  perform motor.empezar_turno_almacen_de(op, pg_temp.h2('15:31'));
  perform pg_temp.comprobar('15:31: primero la revisión del envío',
    motor.tarea_activa_de(op, pg_temp.h2('15:31')) -> 'tarea' ->> 'clave' = 'revisar_envio');
  update public.tareas set estado = 'hecha' where jornada_id = j and clave in ('revisar_envio', 'resinas');
  perform pg_temp.comprobar('15:40: vuelve el +35 %, donde se quedó (Indoor hecho)',
    motor.tarea_activa_de(op, pg_temp.h2('15:40')) -> 'tarea' ->> 'clave' = 'cola_stock');
  perform motor.iniciar_tarea_de(op, v_s, pg_temp.h2('15:40'));
  perform pg_temp.comprobar('… «siguió a las 15:40» y los minutos trabajados no cuentan la pausa (12:20–13:00 + 15:40–15:50)',
    (motor.interrupciones_tarea(v_s) -> 0 ->> 'siguio_a_las')::timestamptz = pg_temp.h2('15:40')
    and motor.minutos_trabajados(v_s, pg_temp.h2('15:50')) = 50,
    motor.minutos_trabajados(v_s, pg_temp.h2('15:50'))::text);
  update public.tareas set estado = 'hecha' where id = v_s;

  -- Una de Administración (no obligatoria) empezada a las 18:00 y sin terminar a las 18:30.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, duracion_min, no_terminada, creada_por)
  values (j, 'admin:estanteria', 'administracion', 'Ordena la estantería de cajas', pg_temp.h2('15:30'), 20, 'arrastrar', adm)
  returning id into v_a;
  update public.tareas set estado = 'hecha'
   where jornada_id = j and estado = 'pendiente' and id <> v_a and clave not like 'cola_orden%';
  perform motor.iniciar_tarea_de(op, v_a, pg_temp.h2('18:00'));
  r := motor.fin_turno_almacen_de(op, false, pg_temp.h2('18:30'));
  perform pg_temp.comprobar('18:30: la de Administración pasa a pendiente; en el cierre, «Sin terminar: fin del turno» y pasa a mañana',
    (select estado from public.tareas where id = v_a) = 'pendiente'
    and exists (select 1 from public.cierres c, jsonb_array_elements(c.contenido -> 'no_hecho') x
                 where c.jornada_id = j and c.turno = 'tarde' and x ->> 'titulo' = 'Ordena la estantería de cajas'
                   and x ->> 'motivo' = 'Sin terminar: fin del turno' and (x ->> 'pasa_a_manana')::boolean),
    (select c.contenido -> 'no_hecho' from public.cierres c where c.jornada_id = j and c.turno = 'tarde')::text);
  r := motor.terminar_tarea_de(op, v_a, null, null, pg_temp.h2('18:33'));
  perform pg_temp.comprobar('18:33: la que tenía entre manos se puede dar por terminada después de la pausa',
    r ->> 'error' is null and (select estado from public.tareas where id = v_a) = 'hecha', r::text);
  update public.tareas set estado = 'pendiente', iniciada_en = null where jornada_id = j and clave = 'cola_orden';
  perform pg_temp.comprobar('Fuera del turno, una no obligatoria sin empezar no se puede terminar',
    motor.terminar_tarea_de(op, (select id from public.tareas where jornada_id = j and clave = 'cola_orden' limit 1),
                            null, null, pg_temp.h2('18:40')) -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO');
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
