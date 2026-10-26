-- Prueba 01 · Semana simulada de lunes a viernes (criterio «Jornada», §13)
-- Días con y sin envío, días en que sale el operario y días en que sale
-- Administración. Cada tarea debe aparecer el día y a la hora correctos.
-- Se ejecuta en una transacción que se deshace: la base queda como estaba.
-- Formato de cada tarea: clave@disponible_desde|hora_límite (hora de Madrid).

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;

create function pg_temp.resumen(p_jornada uuid)
returns text language sql as $$
  select string_agg(t.clave || '@' || to_char(t.disponible_desde at time zone 'Europe/Madrid', 'HH24:MI')
                    || '|' || coalesce(to_char(t.hora_limite at time zone 'Europe/Madrid', 'HH24:MI'), ''),
                    ' ' order by t.clave collate "C")
  from public.tareas t where t.jornada_id = p_jornada and t.estado <> 'cancelada'
$$;

create function pg_temp.comparar(p_prueba text, p_jornada uuid, p_esperado text[])
returns void language plpgsql as $$
declare
  v_obtenido text := pg_temp.resumen(p_jornada);
  v_esperado text := (select string_agg(e, ' ' order by e collate "C") from unnest(p_esperado) e);
begin
  perform pg_temp.comprobar(p_prueba, v_obtenido = v_esperado,
    'esperado: ' || v_esperado || E'\nobtenido: ' || coalesce(v_obtenido, '(nada)'));
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid;
  v_n integer;
  colas constant text[] := array['cola_stock@08:30|', 'cola_compras@08:30|', 'cola_orden@08:30|'];
begin
  -- Generación programada: solo actúa a las 06:00 de Madrid.
  v_n := motor.generar_jornadas_programadas('2026-11-02 05:00:00+01');
  perform pg_temp.comprobar('Programada: a las 05:00 no genera nada', v_n = 0 and not exists (
    select 1 from public.jornadas where persona_id = op and fecha = '2026-11-02'), 'generadas: ' || v_n);
  v_n := motor.generar_jornadas_programadas('2026-11-02 06:00:00+01');
  perform pg_temp.comprobar('Programada: a las 06:00 (invierno) genera la jornada del lunes', v_n = 1, 'generadas: ' || v_n);
  v_n := motor.generar_jornadas_programadas('2026-06-01 04:00:00+00') * 10
         + motor.generar_jornadas_programadas('2026-06-01 05:00:00+00');
  perform pg_temp.comprobar('Programada: en verano actúa a las 04:00 UTC (06:00 en Madrid) y no a las 05:00 UTC',
    v_n = 10 and (select count(*) from public.jornadas where persona_id = op and fecha = '2026-06-01') = 1,
    'resultado: ' || v_n);

  -- LUNES 02/11 · sale Administración · hay envío (el lunes siempre)
  j := motor.generar_jornada(op, '2026-11-02');
  perform prueba.fijar_condicion(j, 'sale', 'administracion');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform prueba.fijar_condicion(j, 'envio_pegado');
  perform pg_temp.comprobar('Lunes: hay envío desde el principio',
    (select hay_envio from public.jornadas where id = j));
  perform pg_temp.comprobar('Lunes: los minis no tienen duración hasta que se conozca',
    (select duracion_min from public.tareas where jornada_id = j and clave = 'minis') is null);
  perform pg_temp.comparar('Lunes (sale Administración, con envío): tareas y horas', j, colas || array[
    'revision_inicial@08:30|', 'pegar_reparto@08:45|', 'produccion_reparto@08:30|10:45', 'bolsas@08:30|10:45',
    'recuento_manana@12:45|13:00', 'revisar_envio@15:30|', 'minis@15:30|', 'preparar_envio@15:30|18:10',
    'recuento_tarde_envio@17:55|18:10', 'nacex_salida@18:10|']);
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente';

  -- MARTES 03/11 · sale el operario · sin envío
  j := motor.generar_jornada(op, '2026-11-03');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform pg_temp.comparar('Martes (sale el operario, sin envío): tareas y horas', j, colas || array[
    'revision_inicial@08:30|', 'pegar_reparto@08:45|', 'produccion_reparto@08:30|10:45', 'bolsas@08:30|10:45',
    'salida_reparto@10:45|', 'efectivo_reporte@08:30|', 'recuento_manana@12:45|13:00',
    'revisar_envio@15:30|', 'resinas@15:30|', 'recuento_tarde@18:15|18:30']);
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente';

  -- MIÉRCOLES 04/11 · sale Administración · el envío se aprueba por la tarde
  j := motor.generar_jornada(op, '2026-11-04');
  perform prueba.fijar_condicion(j, 'sale', 'administracion');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform pg_temp.comprobar('Miércoles: sin envío al empezar, recuento a las 18:15',
    exists (select 1 from public.tareas where jornada_id = j and clave = 'recuento_tarde' and estado = 'pendiente'));
  perform prueba.fijar_condicion(j, 'hay_envio', 'true');
  perform prueba.fijar_condicion(j, 'envio_pegado');
  perform pg_temp.comparar('Miércoles (sale Administración, envío aprobado): tareas y horas', j, colas || array[
    'revision_inicial@08:30|', 'pegar_reparto@08:45|', 'produccion_reparto@08:30|10:45', 'bolsas@08:30|10:45',
    'recuento_manana@12:45|13:00', 'revisar_envio@15:30|', 'preparar_envio@15:30|18:10',
    'recuento_tarde_envio@17:55|18:10', 'nacex_salida@18:10|']);
  perform pg_temp.comprobar('Miércoles: el recuento de las 18:15 queda retirado con su motivo, no borrado',
    exists (select 1 from public.tareas where jornada_id = j and clave = 'recuento_tarde'
            and estado = 'cancelada' and retirada_por_condicion and motivo_no_hecha = 'Ya no aplica: hoy hay envío')
    and exists (select 1 from public.registro_eventos where jornada_id = j and tipo = 'tarea_retirada'));
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente';

  -- JUEVES 05/11 · sale el operario · sin envío hoy; a las 15:30 se decide el del viernes
  j := motor.generar_jornada(op, '2026-11-05');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  -- Cambio de quién sale: se retiran salida y efectivo, y vuelven si se corrige.
  perform prueba.fijar_condicion(j, 'sale', 'administracion');
  perform pg_temp.comprobar('Jueves: si pasa a salir Administración, salida y efectivo se retiran',
    (select count(*) from public.tareas where jornada_id = j and clave in ('salida_reparto', 'efectivo_reporte')
       and estado = 'cancelada' and retirada_por_condicion) = 2);
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform pg_temp.comprobar('Jueves: si vuelve a salir el operario, salida y efectivo se recuperan',
    (select count(*) from public.tareas where jornada_id = j and clave in ('salida_reparto', 'efectivo_reporte')
       and estado = 'pendiente') = 2);
  perform prueba.fijar_condicion(j, 'envio_dia_siguiente', 'true');
  perform pg_temp.comparar('Jueves (sale el operario, sin envío): tareas y horas', j, colas || array[
    'revision_inicial@08:30|', 'pegar_reparto@08:45|', 'produccion_reparto@08:30|10:45', 'bolsas@08:30|10:45',
    'salida_reparto@10:45|', 'efectivo_reporte@08:30|', 'recuento_manana@12:45|13:00',
    'revisar_envio@15:30|', 'control_materiales@15:30|17:55', 'recuento_tarde@18:15|18:30']);
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente';

  -- VIERNES 06/11 · sale el operario · envío por la mañana (decidido el jueves)
  j := motor.generar_jornada(op, '2026-11-06');
  perform pg_temp.comprobar('Viernes: hay envío porque se decidió el jueves',
    (select hay_envio from public.jornadas where id = j));
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform prueba.fijar_condicion(j, 'envio_pegado');
  perform pg_temp.comparar('Viernes (sale el operario, envío por la mañana): tareas y horas', j, colas || array[
    'revision_inicial@08:30|', 'pegar_reparto@08:45|', 'limpieza_resinas@08:30|10:45',
    'produccion_reparto@08:30|10:45', 'bolsas@08:30|10:45', 'salida_reparto@10:45|', 'efectivo_reporte@08:30|',
    'nacex_viernes@10:45|', 'preparar_envio_viernes@08:30|10:45', 'recuento_manana@12:45|13:00']);
  perform pg_temp.comprobar('Viernes: el envío se prepara antes de las 10:45 y se lleva a Nacex con la salida',
    exists (select 1 from public.tareas where jornada_id = j and clave = 'nacex_viernes'
            and hora_programada = '2026-11-06 10:45:00+01'
            and orden < (select orden from public.tareas where jornada_id = j and clave = 'salida_reparto')));
  -- Si sale Administración, llevar el envío a Nacex no es tarea del operario (pero prepararlo sí).
  perform prueba.fijar_condicion(j, 'sale', 'administracion');
  perform pg_temp.comprobar('Viernes: si sale Administración, el operario prepara el envío pero no lo lleva a Nacex',
    exists (select 1 from public.tareas where jornada_id = j and clave = 'nacex_viernes'
            and estado = 'cancelada' and retirada_por_condicion and motivo_no_hecha = 'Ya no aplica: hoy no sale el operario')
    and exists (select 1 from public.tareas where jornada_id = j and clave = 'preparar_envio_viernes' and estado = 'pendiente'));
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  update public.tareas set estado = 'hecha' where jornada_id = j and estado = 'pendiente';

  -- SÁBADO 07/11 · no trabaja
  perform pg_temp.comprobar('Sábado: no hay jornada', motor.generar_jornada(op, '2026-11-07') is null);

  -- Lunes siguiente sin decisión del viernes: envío porque es lunes, no por arrastre
  j := motor.generar_jornada(op, '2026-11-09');
  perform pg_temp.comprobar('Lunes siguiente: hay envío y nada arrastrado (todo se hizo)',
    (select hay_envio from public.jornadas where id = j)
    and not exists (select 1 from public.tareas where jornada_id = j and tarea_origen_id is not null));
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
