-- Prueba 27 · Quién hizo cada tarea y nada fuera del turno (Tarea 24, ESTADO v1.39).
-- Lo del 02/11 rehecho un lunes (14/12/2026), sale el operario: Administración guarda el reparto
-- a las 08:27 («Prepara el reparto» se cierra sola) y el operario termina el recuento a las 13:04.
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

  -- 2. Fuera del turno, ninguna tarea -----------------------------------------------------------
  -- Toda la mañana hecha salvo el +35 % (como el 02/11) y el recuento.
  update public.tareas set estado = 'hecha'
   where jornada_id = j and estado = 'pendiente' and disponible_desde < pg_temp.h('13:00')
     and clave not in ('recuento_manana', 'cola_stock') and clave not like 'cola_orden%';
  perform pg_temp.comprobar('12:40: dentro del turno sale el +35 %', pg_temp.toca('12:40') = 'cola_stock', pg_temp.toca('12:40'));
  v_t := (select id from public.tareas where jornada_id = j and clave = 'recuento_manana');
  perform pg_temp.comprobar('12:45: el recuento', pg_temp.toca('12:45') = 'recuento_manana', pg_temp.toca('12:45'));
  r := motor.iniciar_tarea_de(op, v_t, pg_temp.h('12:46'));
  perform pg_temp.comprobar('13:02, fuera del turno: la tarea en curso (el recuento) sigue en pantalla',
    pg_temp.toca('13:02') = 'recuento_manana', pg_temp.toca('13:02'));
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h('13:04'));
  perform pg_temp.comprobar('13:04: y se puede terminar', r ->> 'error' is null
    and (select estado from public.tareas where id = v_t) = 'hecha', r::text);
  perform pg_temp.comprobar('13:04 (lo del 02/11): sin tarea, no sale el +35 %; «siguiente» dice lo de las 15:30',
    pg_temp.activa('13:04') -> 'tarea' = 'null'::jsonb and pg_temp.activa('13:04') ->> 'siguiente' like '%15:30',
    pg_temp.activa('13:04')::text);
  perform pg_temp.comprobar('14:30, entre turnos: tampoco', pg_temp.toca('14:30') is null, pg_temp.toca('14:30'));
  perform pg_temp.comprobar('15:31, empieza la tarde: vuelve a salir lo de su hora (revisar el envío)',
    pg_temp.toca('15:31') = 'revisar_envio', pg_temp.toca('15:31'));
  update public.tareas set estado = 'hecha' where jornada_id = j and clave in ('revisar_envio', 'minis');
  perform pg_temp.comprobar('… y lo pendiente de la mañana (el +35 %)', pg_temp.toca('15:40') = 'cola_stock', pg_temp.toca('15:40'));
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente' and clave not like 'cola_orden%';
  perform pg_temp.comprobar('18:31, después del turno: nada, ni «Orden y limpieza»', pg_temp.toca('18:31') is null, pg_temp.toca('18:31'));
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
