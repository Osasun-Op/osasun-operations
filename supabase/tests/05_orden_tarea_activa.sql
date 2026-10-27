-- Prueba 05 · Orden de tarea_activa (PLAN_TECNICO.md §2.3): un caso por escalón
-- 1 en curso · 2 llamar por un problema · 3 urgente de Administración ·
-- 4 con hora vencida · 5 obligatorias y de Administración con hora límite ·
-- 6 de Administración sin hora · 7 flexibles · 8 cola de tiempo libre (A, C, D).
-- Martes 03/11, sale el operario. Horas de Madrid (+01).

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas (la tarea
-- programada crea una cada día): sin pendientes que arrastrar. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;

-- Comprueba qué tarea devuelve tarea_activa a una hora dada.
create function pg_temp.toca(p_prueba text, p_hora text, p_clave text)
returns jsonb language plpgsql as $$
declare
  r jsonb := motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', ('2026-11-03 ' || p_hora || ':00+01')::timestamptz);
begin
  perform pg_temp.comprobar(p_prueba, r -> 'tarea' ->> 'clave' is not distinct from p_clave,
    'esperada: ' || coalesce(p_clave, '(ninguna)') || ' · obtenida: ' || coalesce(r -> 'tarea' ->> 'clave', '(ninguna)'));
  return r;
end;
$$;

create function pg_temp.hecha(p_jornada uuid, p_claves text[])
returns void language sql as $$
  update public.tareas set estado = 'hecha' where jornada_id = p_jornada and clave = any (p_claves)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  r jsonb;
begin
  j := motor.generar_jornada(op, '2026-11-03');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'reparto_pegado');

  r := pg_temp.toca('Antes de empezar el turno no hay tarea', '08:20', null);
  perform pg_temp.comprobar('Antes de empezar el turno, «lo que viene después» es la primera tarea',
    r ->> 'siguiente' like 'Revisión inicial%08:30', r ->> 'siguiente');

  r := pg_temp.toca('Escalón 4: tarea con hora ya vencida (revisión de las 08:30) antes que la cola', '08:31', 'revision_inicial');
  perform pg_temp.comprobar('«Lo que viene después» anuncia la siguiente tarea con hora',
    r ->> 'siguiente' = 'Pega el reparto de hoy · 08:45', r ->> 'siguiente');
  perform pg_temp.toca('Escalón 4: con dos vencidas, primero la de hora más temprana', '08:50', 'revision_inicial');

  perform pg_temp.hecha(j, array['revision_inicial', 'pegar_reparto']);
  perform pg_temp.toca('Escalón 5: obligatoria con hora límite (producción antes de las 10:45)', '09:00', 'produccion_reparto');

  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, hora_limite, duracion_min, no_terminada, creada_por)
  values (j, 'admin:limite', 'administracion', 'Llama a la imprenta', '2026-11-03 08:30:00+01',
          '2026-11-03 10:00:00+01', 10, 'arrastrar', adm);
  perform pg_temp.toca('Escalón 5: la de Administración con hora límite más próxima va antes', '09:00', 'admin:limite');
  update public.tareas set hora_limite = '2026-11-03 10:45:00+01' where jornada_id = j and clave = 'admin:limite';
  perform pg_temp.toca('Escalón 5: con la misma hora límite, primero la obligatoria', '09:00', 'produccion_reparto');

  perform pg_temp.toca('Escalón 4 antes que 5: la salida de las 10:45 ya vencida', '10:46', 'salida_reparto');

  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, urgente, duracion_min, no_terminada, creada_por)
  values (j, 'admin:urgente', 'administracion', 'Mira el pedido de Bilbao', '2026-11-03 10:40:00+01', true, 5, 'arrastrar', adm);
  -- Entre urgentes manda el orden de llegada: esta llegó antes que la mercancía.
  update public.tareas set creada_en = now() - interval '1 minute' where jornada_id = j and clave = 'admin:urgente';
  perform pg_temp.toca('Escalón 3: la urgente de Administración antes que la tarea con hora', '10:46', 'admin:urgente');

  perform prueba.fijar_condicion(j, 'llega_mercancia', 'm1');
  perform pg_temp.toca('Escalón 3: entre urgentes, por orden de llegada (la urgente llegó antes que la mercancía)',
                       '10:46', 'admin:urgente');
  update public.tareas set estado = 'hecha' where jornada_id = j and clave = 'admin:urgente';
  perform pg_temp.toca('Escalón 3: con la urgente hecha, entra la recepción de mercancía', '10:46', 'recepcion_mercancia:m1');
  update public.tareas set estado = 'pendiente' where jornada_id = j and clave = 'admin:urgente';
  update public.tareas set estado = 'hecha' where jornada_id = j and clave = 'recepcion_mercancia:m1';

  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, hora_programada, obligatoria)
  values (j, 'problema:llamar', 'problema', 'Llama a Administración: no encuentro el kief',
          '2026-11-03 10:40:00+01', '2026-11-03 10:40:00+01', true);
  perform pg_temp.toca('Escalón 2: volver a llamar por un problema antes que la urgente', '10:46', 'problema:llamar');

  perform motor.iniciar_tarea_de(op, (select id from public.tareas where jornada_id = j and clave = 'bolsas'), '2026-11-03 10:46:00+01');
  perform pg_temp.toca('Escalón 1: la tarea en curso no se interrumpe', '10:47', 'bolsas');

  perform pg_temp.hecha(j, array['bolsas', 'problema:llamar', 'admin:urgente', 'admin:limite', 'produccion_reparto']);
  perform pg_temp.toca('Requisito: el efectivo no aparece mientras la salida no esté hecha', '10:30', 'cola_stock');
  perform pg_temp.hecha(j, array['salida_reparto']);
  perform pg_temp.toca('Escalón 5: obligatoria sin hora límite (efectivo, tras la salida)', '12:40', 'efectivo_reporte');
  perform pg_temp.hecha(j, array['efectivo_reporte']);

  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, duracion_min, no_terminada, creada_por)
  values (j, 'admin:hoy', 'administracion', 'Ordena la estantería de cajas', '2026-11-03 08:30:00+01', 20, 'arrastrar', adm);
  perform prueba.fijar_condicion(j, 'no_quedan_vapers', 'v1');
  perform pg_temp.toca('Escalón 6: la de Administración sin hora antes que las flexibles', '12:40', 'admin:hoy');
  perform pg_temp.hecha(j, array['admin:hoy']);
  perform pg_temp.toca('Escalón 7: flexible (tirada de vapers) antes que la cola', '12:40', 'tirada_vapers:v1');
  perform pg_temp.hecha(j, array['tirada_vapers:v1']);

  perform pg_temp.toca('Escalón 8: cola A (stock) primero', '12:40', 'cola_stock');
  perform pg_temp.hecha(j, array['cola_stock']);
  perform pg_temp.toca('Escalón 8: después cola C (compras)', '12:40', 'cola_compras');
  perform pg_temp.hecha(j, array['cola_compras']);
  -- Nunca sin tarea (v1.17): sin nada disponible, primero se adelanta la fija de la tarde.
  perform pg_temp.toca('Nunca sin tarea: sin nada disponible, se adelanta la fija de la tarde (resinas del martes)', '12:40', 'resinas');
  update public.tareas set estado = 'bloqueada' where jornada_id = j and clave = 'resinas';
  perform pg_temp.toca('Escalón 8: después cola D (orden y limpieza)', '12:40', 'cola_orden');

  update public.tareas set estado = 'bloqueada' where jornada_id = j and clave = 'cola_orden';
  r := pg_temp.toca('Una tarea bloqueada (problema abierto) se salta', '12:40', null);
  perform pg_temp.comprobar('Sin nada que hacer, «lo que viene después» es el recuento de las 12:45',
    r ->> 'siguiente' like 'Recuento de stock%12:45', r ->> 'siguiente');
  perform pg_temp.toca('A las 12:45 toca el recuento', '12:45', 'recuento_manana');
  perform pg_temp.hecha(j, array['recuento_manana']);
  update public.tareas set estado = 'pendiente' where jornada_id = j and clave in ('resinas', 'cola_orden');
  perform pg_temp.toca('Entre turnos no se adelanta nada: las tareas de la tarde no aparecen antes de las 15:30', '13:00', null);
  perform pg_temp.toca('A las 15:30, la revisión del envío (con hora) va primero', '15:31', 'revisar_envio');
  perform pg_temp.hecha(j, array['revisar_envio']);
  perform pg_temp.toca('Después, la obligatoria de la tarde (resinas del martes)', '15:40', 'resinas');
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
