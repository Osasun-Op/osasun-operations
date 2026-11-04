-- Prueba 40 · «Empezar turno» y «Fin de turno» del operario (Tarea 35, ESTADO §6.4; propietario, 04/11/2026).
-- Del martes 22/12 al viernes 25/12/2026, con el operario de pruebas (cuenta y nombres inventados):
--   - antes de empezar, nada; empezar antes de la hora se puede; repetir no duplica;
--   - «Fin de turno» con el recuento sin hacer no cierra, y el recuento sale en ese momento; con otra obligatoria, hay
--     que confirmar; repetir no duplica;
--   - el caso del 04/11: el Chromebook se duerme de 17:10 a 18:31 y, con el turno abierto, sale el recuento; lo no
--     obligatorio en curso se pausa y espera; después, «Has terminado» (sin «Orden y limpieza»);
--   - el turno que se olvida se cierra solo (al empezar el siguiente o a medianoche) y el cierre lo dice; un turno sin
--     empezar también tiene su cierre; un cierre sin recuento no cuenta como recuento;
--   - el reparto y las bolsas, igual; permisos.
-- Transacción deshecha.

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
create function pg_temp.a(p_dia text, p_hora text) returns timestamptz language sql as $$
  select motor.en_local(('2026-12-' || p_dia)::date, p_hora::time) $$;
create function pg_temp.activa(p_dia text, p_hora text) returns jsonb language sql as $$
  select motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a(p_dia, p_hora)) $$;
create function pg_temp.toca(p_dia text, p_hora text) returns text language sql as $$
  select pg_temp.activa(p_dia, p_hora) -> 'tarea' ->> 'clave' $$;
create function pg_temp.empezar(p_dia text, p_hora text) returns jsonb language sql as $$
  select motor.empezar_turno_almacen_de('00000000-0000-4000-a000-000000000001', pg_temp.a(p_dia, p_hora)) $$;
create function pg_temp.fin(p_dia text, p_hora text, p_confirmar boolean default false) returns jsonb language sql as $$
  select motor.fin_turno_almacen_de('00000000-0000-4000-a000-000000000001', p_confirmar, pg_temp.a(p_dia, p_hora)) $$;
create function pg_temp.cierre(p_dia text, p_turno text) returns public.cierres language sql as $$
  select c.* from public.cierres c join public.jornadas j on j.id = c.jornada_id
   where j.persona_id = '00000000-0000-4000-a000-000000000001' and j.fecha = ('2026-12-' || p_dia)::date and c.turno = p_turno $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;

-- 1. Martes 22/12 por la mañana: empezar, el recuento y «Fin de turno» -------------------------------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  r jsonb;
  v_rec uuid;
  c public.cierres;
begin
  j := motor.generar_jornada(op, '2026-12-22');
  perform prueba.fijar_condicion(j, 'sale', 'operario');

  r := pg_temp.activa('22', '08:20');
  perform pg_temp.comprobar('08:20, antes de «Empezar turno»: ninguna tarea; tarea_activa pide empezar el de la mañana',
    r -> 'tarea' = 'null'::jsonb
    and r -> 'turno' = jsonb_build_object('estado', 'sin_empezar', 'turno', 'manana', 'empezado_a_las', null,
                                          'hora_fin', '13:00', 'pasada_la_hora', false, 'empezar', 'manana',
                                          'mensaje', 'Pulsa «Empezar turno» para empezar el turno de mañana.'), r::text);
  perform pg_temp.comprobar('08:40 sin empezar: tampoco (aunque sea su hora)', pg_temp.toca('22', '08:40') is null);

  r := pg_temp.empezar('22', '08:28');
  perform pg_temp.comprobar('08:28, «Empezar turno» antes de la hora: se puede; el turno de la mañana queda abierto',
    r -> 'turno' ->> 'estado' = 'abierto' and r -> 'turno' ->> 'turno' = 'manana'
    and r -> 'turno' ->> 'empezado_a_las' = '08:28' and r -> 'turno' -> 'empezar' = 'null'::jsonb, r::text);
  r := pg_temp.empezar('22', '08:29');
  perform pg_temp.comprobar('08:29, repetir «Empezar turno» no duplica (un turno, una vez, desde las 08:28)',
    pg_temp.err(r) is null
    and (select count(*) from public.turnos_tienda where jornada_id = j) = 1
    and (select count(*) from public.registro_eventos where jornada_id = j and tipo = 'turno_empezado') = 1
    and (select motor.hora_texto(empezado_en) from public.turnos_tienda where jornada_id = j) = '08:28'
    and (select nombre from public.turnos_tienda where jornada_id = j) = (select nombre from public.personas where id = op)
    and (select persona_tienda_id from public.turnos_tienda where jornada_id = j) is null);
  perform pg_temp.comprobar('08:31: la revisión inicial, como siempre', pg_temp.toca('22', '08:31') = 'revision_inicial',
    pg_temp.toca('22', '08:31'));

  -- Toda la mañana hecha salvo el recuento (y las colas).
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a('22', '10:30')
   where jornada_id = j and estado = 'pendiente' and disponible_desde < pg_temp.a('22', '13:00')
     and clave <> 'recuento_manana' and clave not like 'cola_%';
  v_rec := (select id from public.tareas where jornada_id = j and clave = 'recuento_manana');
  r := pg_temp.fin('22', '11:00');
  perform pg_temp.comprobar('11:00, «Fin de turno» con el recuento sin hacer: no se cierra (RECUENTO_PENDIENTE)',
    pg_temp.err(r) = 'RECUENTO_PENDIENTE'
    and r -> 'error' ->> 'mensaje' = 'Antes de cerrar el turno, haz el recuento de stock.'
    and r -> 'error' -> 'tarea' ->> 'id' = v_rec::text
    and pg_temp.cierre('22', 'manana') is null, r::text);
  perform pg_temp.comprobar('… y el recuento sale en ese momento, aunque no sean las 12:45',
    (select disponible_desde from public.tareas where id = v_rec) = pg_temp.a('22', '11:00')
    and r -> 'error' -> 'tarea_activa' -> 'tarea' ->> 'id' = v_rec::text
    and exists (select 1 from public.registro_eventos where tarea_id = v_rec and tipo = 'recuento_adelantado'),
    (r -> 'error' -> 'tarea_activa')::text);
  perform motor.iniciar_tarea_de(op, v_rec, pg_temp.a('22', '11:02'));
  perform motor.terminar_tarea_de(op, v_rec, null, null, pg_temp.a('22', '11:10'));

  -- Una obligatoria de la mañana sin hacer.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, hora_limite, obligatoria, creada_por)
  values (j, 'admin:impresora', 'administracion', 'Revisar la impresora', pg_temp.a('22', '08:30'), pg_temp.a('22', '12:00'),
          true, adm);
  r := pg_temp.fin('22', '11:15');
  perform pg_temp.comprobar('11:15, «Fin de turno» con otra obligatoria sin hacer: hay que confirmar (CONFIRMAR_FIN_DE_TURNO)',
    pg_temp.err(r) = 'CONFIRMAR_FIN_DE_TURNO'
    and r -> 'error' ->> 'mensaje' = 'Te queda 1 obligatoria sin hacer: Revisar la impresora. ¿Cerrar el turno igualmente?'
    and r -> 'error' -> 'pendientes' = '["Revisar la impresora"]'
    and pg_temp.cierre('22', 'manana') is null, r::text);
  r := pg_temp.fin('22', '11:16', true);
  c := pg_temp.cierre('22', 'manana');
  perform pg_temp.comprobar('11:16, confirmado: el cierre de la mañana, el de siempre, cerrado por el operario',
    pg_temp.err(r) is null and r ->> 'cierre' = c.id::text
    and c.contenido -> 'turno_operario'
        = '{"como": "operario", "empezado": "08:28", "terminado": "11:16", "al_dia_siguiente": false}'
    and c.contenido -> 'no_hecho' @> '[{"titulo": "Revisar la impresora"}]'
    and c.contenido -> 'hecho' @> jsonb_build_array(jsonb_build_object('titulo', (select titulo from public.tareas where id = v_rec)))
    and (select terminado_solo = false and motor.hora_texto(terminado_en) = '11:16'
           from public.turnos_tienda where jornada_id = j and turno = 'manana'), r::text);
  perform pg_temp.comprobar('… con su correo (o, para esta cuenta, «cierre sin correo»), una vez',
    (select count(*) from net.http_request_queue
      where convert_from(body, 'UTF8')::jsonb = jsonb_build_object('tipo', 'cierre', 'ref', c.id::text))
    + (select count(*) from public.registro_eventos where jornada_id = j and tipo = 'correo_no_enviado'
         and datos ->> 'ref' = c.id::text) = 1);
  perform pg_temp.comprobar('… y el texto del correo dice el turno: «Turno de 08:28 a 11:16.»',
    motor.texto_cierre(c.contenido) ->> 'texto' like '%' || E'\n' || 'Turno de 08:28 a 11:16.' || E'\n' || '%',
    motor.texto_cierre(c.contenido) ->> 'texto');
  r := pg_temp.fin('22', '11:17', true);
  perform pg_temp.comprobar('11:17, repetir «Fin de turno»: no hace nada (ni otro cierre ni otro correo)',
    pg_temp.err(r) is null and r -> 'cierre' = 'null'::jsonb
    and (select count(*) from public.cierres where jornada_id = j) = 1, r::text);
  r := pg_temp.activa('22', '11:20');
  perform pg_temp.comprobar('11:20, con la mañana cerrada: ninguna tarea; pide empezar el de la tarde',
    r -> 'tarea' = 'null'::jsonb and r -> 'turno' ->> 'estado' = 'sin_empezar' and r -> 'turno' ->> 'empezar' = 'tarde'
    and r -> 'turno' ->> 'mensaje' = 'Pulsa «Empezar turno» para empezar el turno de tarde.', r::text);
end;
$$;

-- 2. Martes 22/12 por la tarde: el caso del 04/11 y el cierre a medianoche --------------------------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-22');
  r jsonb;
  v_s uuid;
  v_rec uuid;
  c public.cierres;
  n integer;
begin
  r := pg_temp.empezar('22', '15:28');
  perform pg_temp.comprobar('15:28, «Empezar turno»: el de la tarde', r -> 'turno' ->> 'turno' = 'tarde'
    and r -> 'turno' ->> 'estado' = 'abierto', r::text);
  -- Toda la tarde hecha salvo el recuento (y las colas). A las 17:05 empieza el +35 %.
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a('22', '16:30')
   where jornada_id = j and estado = 'pendiente' and clave not in ('recuento_tarde', 'recuento_manana')
     and clave not like 'cola_%';
  v_s := (select id from public.tareas where jornada_id = j and clave = 'cola_stock');
  v_rec := (select id from public.tareas where jornada_id = j and clave = 'recuento_tarde' and not retirada_por_condicion);
  perform motor.iniciar_tarea_de(op, v_s, pg_temp.a('22', '17:05'));
  perform pg_temp.comprobar('17:05: el +35 % en curso', pg_temp.toca('22', '17:06') = 'cola_stock');

  -- El Chromebook se duerme de 17:10 a 18:31 (no pide nada). Al despertarlo:
  r := pg_temp.activa('22', '18:31');
  perform pg_temp.comprobar('18:31, el caso del 04/11: con el turno abierto, sale «Recuento de stock y cierre»',
    r -> 'tarea' ->> 'id' = v_rec::text and (r -> 'turno' ->> 'pasada_la_hora')::boolean
    and r -> 'turno' -> 'mensaje' = 'null'::jsonb, r::text);
  perform pg_temp.comprobar('18:31: el +35 % (no obligatorio) se ha pausado y espera al siguiente turno, con «Fin del turno»',
    (select estado from public.tareas where id = v_s) = 'pendiente'
    and motor.interrupciones_tarea(v_s) -> 0 ->> 'por' = 'Fin del turno'
    and (motor.interrupciones_tarea(v_s) -> 0 ->> 'a_las')::timestamptz = pg_temp.a('22', '18:30'),
    motor.interrupciones_tarea(v_s)::text);
  perform motor.iniciar_tarea_de(op, v_rec, pg_temp.a('22', '18:32'));
  r := motor.iniciar_tarea_de(op, v_s, pg_temp.a('22', '18:33'));
  perform pg_temp.comprobar('18:33: el +35 % no vuelve a ponerse en curso pasada la hora (sigue el recuento)',
    (select estado from public.tareas where id = v_s) = 'pendiente'
    and (select estado from public.tareas where id = v_rec) = 'en_curso', r::text);
  perform motor.terminar_tarea_de(op, v_rec, null, null, pg_temp.a('22', '18:40'));
  r := pg_temp.activa('22', '18:41');
  perform pg_temp.comprobar('18:41, pasada la hora y sin nada obligatorio: «Has terminado», sin «Orden y limpieza»',
    r -> 'tarea' = 'null'::jsonb
    and r -> 'turno' ->> 'mensaje' = 'Has terminado. Pulsa «Fin de turno».'
    and exists (select 1 from public.tareas where jornada_id = j and clave like 'cola_orden%' and estado = 'pendiente'), r::text);
  r := motor.terminar_tarea_de(op, v_s, null, null, pg_temp.a('22', '18:42'));
  perform pg_temp.comprobar('… y lo que tenía entre manos (el +35 %) se puede dar por terminado',
    r ->> 'error' is null and (select estado from public.tareas where id = v_s) = 'hecha', r::text);

  -- Se va sin pulsar «Fin de turno». A medianoche, la tarea programada lo cierra.
  perform pg_temp.comprobar('23:59: la tarea programada no cierra nada todavía',
    motor.generar_cierres_programados(pg_temp.a('22', '23:59')) = 0 and pg_temp.cierre('22', 'tarde') is null);
  n := motor.generar_cierres_programados(pg_temp.a('23', '00:05'));
  perform pg_temp.comprobar('00:05: cierra la tarde (una sola vez) y la jornada queda cerrada',
    n = 1 and motor.generar_cierres_programados(pg_temp.a('23', '01:05')) = 0
    and (select estado from public.jornadas where id = j) = 'cerrada', n::text);
  c := pg_temp.cierre('22', 'tarde');
  perform pg_temp.comprobar('El cierre de la tarde dice que no lo cerró el operario (se cerró al acabar el día)',
    c.contenido -> 'turno_operario'
      = '{"como": "solo", "empezado": "15:28", "terminado": "00:05", "al_dia_siguiente": true}'
    and motor.texto_cierre(c.contenido) ->> 'texto'
        like '%Turno desde las 15:28. No cerrado por el operario: se cerró solo al acabar el día.%'
    and (select terminado_solo from public.turnos_tienda where jornada_id = j and turno = 'tarde'),
    c.contenido::text);
end;
$$;

-- 3. Miércoles 23/12: la mañana se olvida y se cierra al empezar la tarde; la tarde sin recuento -------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid;
  r jsonb;
  c public.cierres;
  v_recuento timestamptz;
begin
  j := motor.generar_jornada(op, '2026-12-23');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  v_recuento := motor.ultimo_recuento(op, pg_temp.a('23', '08:00'));
  perform pg_temp.empezar('23', '08:30');
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a('23', '10:30')
   where jornada_id = j and estado = 'pendiente' and clave not like 'recuento%' and clave not like 'cola_%';
  r := pg_temp.activa('23', '13:30');
  perform pg_temp.comprobar('13:30, la mañana sin cerrar: el recuento sigue; los dos botones (Fin y «Empezar» la tarde)',
    r -> 'tarea' ->> 'clave' = 'recuento_manana' and r -> 'turno' ->> 'estado' = 'abierto'
    and r -> 'turno' ->> 'turno' = 'manana' and r -> 'turno' ->> 'empezar' = 'tarde', r::text);
  r := pg_temp.empezar('23', '15:30');
  c := pg_temp.cierre('23', 'manana');
  perform pg_temp.comprobar('15:30, «Empezar turno» de la tarde: la mañana se cierra sola y lo dice; el recuento, no hecho',
    r -> 'turno' ->> 'turno' = 'tarde' and r -> 'turno' ->> 'estado' = 'abierto'
    and c.contenido -> 'turno_operario' ->> 'como' = 'solo'
    and motor.texto_cierre(c.contenido) ->> 'texto' like '%No cerrado por el operario: se cerró solo a las 15:30.%'
    and c.contenido -> 'no_hecho' @> jsonb_build_array(jsonb_build_object('titulo',
          (select titulo from public.tareas where jornada_id = j and clave = 'recuento_manana'))), c.contenido::text);
  perform pg_temp.comprobar('… y no cuenta como recuento: el almacén sigue contando desde el último hecho (el 22/12)',
    motor.ultimo_recuento(op, pg_temp.a('23', '15:31')) = v_recuento and v_recuento = pg_temp.a('22', '18:40'));
  r := pg_temp.fin('23', '18:35');
  perform pg_temp.comprobar('18:35, «Fin de turno» con el recuento de la tarde sin hacer: no se cierra',
    pg_temp.err(r) = 'RECUENTO_PENDIENTE' and pg_temp.cierre('23', 'tarde') is null
    and not exists (select 1 from public.registro_eventos where jornada_id = j and tipo = 'recuento_adelantado'), r::text);
  perform motor.generar_cierres_programados(pg_temp.a('24', '00:05'));
  c := pg_temp.cierre('23', 'tarde');
  perform pg_temp.comprobar('A medianoche se cierra solo, con el recuento como no hecho',
    c.contenido -> 'turno_operario' ->> 'como' = 'solo'
    and c.contenido -> 'no_hecho' @> jsonb_build_array(jsonb_build_object('titulo',
          (select titulo from public.tareas where jornada_id = j and clave = 'recuento_tarde' and not retirada_por_condicion))),
    c.contenido::text);
end;
$$;

-- 4. Jueves 24/12: no empieza ningún turno. Viernes 25/12: un solo turno, cerrado; ya no se puede empezar otro ----
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid;
  r jsonb;
begin
  j := motor.generar_jornada(op, '2026-12-24');
  perform pg_temp.comprobar('Jueves 10:00 sin empezar: ninguna tarea', pg_temp.toca('24', '10:00') is null
    and pg_temp.activa('24', '10:00') -> 'turno' ->> 'estado' = 'sin_empezar');
  r := to_jsonb(motor.generar_cierres_programados(pg_temp.a('25', '00:05')));
  perform pg_temp.comprobar('A medianoche, los dos turnos sin empezar tienen su cierre: «No empezó el turno»',
    r = '2'
    and (pg_temp.cierre('24', 'manana')).contenido -> 'turno_operario' ->> 'como' = 'sin_empezar'
    and motor.texto_cierre((pg_temp.cierre('24', 'tarde')).contenido) ->> 'texto'
        like '%No empezó el turno: no pulsó «Empezar turno».%'
    and not exists (select 1 from public.turnos_tienda where jornada_id = j));

  j := motor.generar_jornada(op, '2026-12-25');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform pg_temp.empezar('25', '08:30');
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a('25', '12:45')
   where jornada_id = j and estado = 'pendiente' and clave not like 'cola_%';
  r := pg_temp.fin('25', '12:50');
  perform pg_temp.comprobar('Viernes 12:50, «Fin de turno»: el único turno, cerrado; la jornada, cerrada',
    r ->> 'cierre' is not null and (select estado from public.jornadas where id = j) = 'cerrada'
    and r -> 'tarea_activa' -> 'turno' ->> 'estado' = 'terminado'
    and r -> 'tarea_activa' -> 'turno' ->> 'mensaje' = 'Has cerrado los turnos de hoy.', r::text);
  r := pg_temp.empezar('25', '12:55');
  perform pg_temp.comprobar('12:55, «Empezar turno» otra vez: TURNOS_CERRADOS (un turno cerrado no se vuelve a abrir)',
    pg_temp.err(r) = 'TURNOS_CERRADOS' and (select count(*) from public.turnos_tienda where jornada_id = j) = 1, r::text);
  perform pg_temp.comprobar('Sábado: SIN_JORNADA', pg_temp.err(pg_temp.empezar('26', '09:00')) = 'SIN_JORNADA');
end;
$$;

-- 5. Martes 29/12: el reparto y las bolsas, igual con el turno empezado con el botón ----------------------
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-29');
  r jsonb;
begin
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('29', '08:30'), terminada_en = pg_temp.a('29', '08:45')
   where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto');
  perform public.servidor_guardar_reparto(
    adm, j, 'reparto', E'REPARTO 29/12\nSALE: ALMACÉN\n\nBILBAO\n20x V2 4g', 'h40', '2026-12-29', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 29/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '20x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 20, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 20, 'en_almacen', 0, 'faltan', 20, 'aviso', null, 'orden', 1)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1)))),
    true, pg_temp.a('29', '08:50'));
  perform pg_temp.comprobar('08:55 sin empezar el turno: con el reparto guardado, tampoco sale la producción',
    pg_temp.toca('29', '08:55') is null);
  perform pg_temp.empezar('29', '08:56');
  perform pg_temp.comprobar('08:56, empezado: la producción del reparto, como siempre',
    pg_temp.toca('29', '08:57') = 'produccion_reparto', pg_temp.toca('29', '08:57'));
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.a('29', '09:00'), terminada_en = pg_temp.a('29', '10:30')
   where jornada_id = j and clave = 'produccion_reparto';
  r := pg_temp.activa('29', '10:46');
  perform pg_temp.comprobar('10:46: las bolsas y el aviso de salida, como siempre',
    r -> 'tarea' ->> 'clave' = 'bolsas' and r -> 'aviso_salida' ->> 'hora_salida' = '10:45', r::text);
end;
$$;

-- 6. Permisos -----------------------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('Administración no ficha en esta tarea (NO_AUTORIZADO)',
  public.empezar_turno_almacen() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.fin_turno_almacen(true) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario sí (fin_turno_almacen sin turno abierto: no hace nada)',
  public.fin_turno_almacen() ? 'tarea_activa' and public.fin_turno_almacen() -> 'cierre' = 'null'::jsonb);
reset role;
select pg_temp.comprobar('Sin sesión, nada; las funciones internas no se llaman desde fuera',
  not has_function_privilege('anon', 'public.empezar_turno_almacen()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.fin_turno_almacen(boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.empezar_turno_almacen()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.empezar_turno_almacen_de(uuid, timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.cerrar_turno_almacen(uuid, text, timestamptz, boolean)', 'EXECUTE'));
select pg_temp.comprobar('La tarea programada: solo cierra lo que quedó sin cerrar, a las 00:05 de Madrid',
  exists (select 1 from cron.job where jobname = 'cerrar_turnos_olvidados' and schedule = '5 22,23 * * *')
  and not exists (select 1 from cron.job where jobname = 'generar_cierres_turno'));

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
