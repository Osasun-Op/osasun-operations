-- Prueba 03 · Arrastres (ESTADO_DEL_SISTEMA.md §6.5)
-- Pasan al día siguiente: obligatorias fijas, tareas de Administración y lo que
-- sigue abierto. No pasan: las ligadas a hora o turno (recuento, Nacex, salida,
-- efectivo) ni el stock (se recalcula).

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  jj uuid;  -- jueves
  jv uuid;  -- viernes
  jl uuid;  -- lunes
  v_control uuid;
  v_recuento uuid;
  v_salida uuid;
  v_stock uuid;
  v_admin uuid;
  v_recepcion uuid;
  v_vapers uuid;
  v_copia uuid;
begin
  -- Jueves 05/11 · sale el operario
  jj := motor.generar_jornada(op, '2026-11-05');
  perform prueba.fijar_condicion(jj, 'sale', 'operario');
  perform prueba.fijar_condicion(jj, 'llega_mercancia', 'm1');
  perform prueba.fijar_condicion(jj, 'no_quedan_vapers', 'v1');

  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, duracion_min, no_terminada, creada_por)
  values (jj, 'admin:prueba', 'administracion', 'Llama a la imprenta', '2026-11-05 08:30:00+01', 10, 'arrastrar',
          '00000000-0000-4000-a000-000000000002')
  returning id into v_admin;

  select id into v_control from public.tareas where jornada_id = jj and clave = 'control_materiales';
  select id into v_recuento from public.tareas where jornada_id = jj and clave = 'recuento_tarde';
  select id into v_salida from public.tareas where jornada_id = jj and clave = 'salida_reparto';
  select id into v_stock from public.tareas where jornada_id = jj and clave = 'cola_stock';
  select id into v_recepcion from public.tareas where jornada_id = jj and clave = 'recepcion_mercancia:m1';
  select id into v_vapers from public.tareas where jornada_id = jj and clave = 'tirada_vapers:v1';

  -- Se queda sin terminar: control de materiales, recuento, salida, stock, la
  -- tarea de Administración, la recepción (en curso) y los vapers (bloqueada).
  update public.tareas set estado = 'hecha'
   where jornada_id = jj and id not in (v_control, v_recuento, v_salida, v_stock, v_admin, v_recepcion, v_vapers);
  update public.tareas set estado = 'en_curso', iniciada_en = '2026-11-05 18:20:00+01' where id = v_recepcion;
  update public.tareas set estado = 'bloqueada' where id = v_vapers;

  -- Viernes 06/11
  jv := motor.generar_jornada(op, '2026-11-06');

  select id into v_copia from public.tareas where jornada_id = jv and tarea_origen_id = v_control;
  perform pg_temp.comprobar('Control de materiales (obligatoria fija) pasa al viernes como arrastrada',
    v_copia is not null
    and (select estado from public.tareas where id = v_control) = 'arrastrada'
    and (select estado = 'pendiente' and obligatoria and hora_limite is null and origen = 'plantilla'
                and disponible_desde = '2026-11-06 08:30:00+01'
         from public.tareas where id = v_copia));
  perform pg_temp.comprobar('La tarea de Administración pasa al viernes y sigue siendo de Administración',
    exists (select 1 from public.tareas where jornada_id = jv and tarea_origen_id = v_admin
            and origen = 'administracion' and creada_por = '00000000-0000-4000-a000-000000000002')
    and (select estado from public.tareas where id = v_admin) = 'arrastrada');
  perform pg_temp.comprobar('La recepción en curso y los vapers bloqueados también pasan',
    (select count(*) from public.tareas where jornada_id = jv and tarea_origen_id in (v_recepcion, v_vapers)) = 2
    and (select count(*) from public.tareas where id in (v_recepcion, v_vapers) and estado = 'arrastrada') = 2);
  perform pg_temp.comprobar('El recuento (ligado al turno) no pasa: consta como no hecho en su día',
    not exists (select 1 from public.tareas where jornada_id = jv and tarea_origen_id = v_recuento)
    and (select estado from public.tareas where id = v_recuento) = 'pendiente');
  perform pg_temp.comprobar('La salida del reparto (ligada a hora) no pasa',
    not exists (select 1 from public.tareas where jornada_id = jv and tarea_origen_id = v_salida));
  perform pg_temp.comprobar('El stock no se arrastra (se recalcula): el viernes solo tiene su propia tarea de stock',
    not exists (select 1 from public.tareas where jornada_id = jv and tarea_origen_id = v_stock)
    and (select count(*) from public.tareas where jornada_id = jv and clave = 'cola_stock') = 1);
  perform pg_temp.comprobar('Exactamente 4 tareas arrastradas al viernes',
    (select count(*) from public.tareas where jornada_id = jv and tarea_origen_id is not null) = 4);

  -- Repetir la generación del viernes no arrastra otra vez
  perform motor.generar_jornada(op, '2026-11-06');
  perform motor.arrastrar(jv);
  perform pg_temp.comprobar('Generar otra vez el viernes no duplica los arrastres',
    (select count(*) from public.tareas where jornada_id = jv and tarea_origen_id is not null) = 4);

  -- Cadena: lo arrastrado que tampoco se hace el viernes pasa al lunes (salta el fin de semana)
  update public.tareas set estado = 'hecha' where jornada_id = jv and id <> v_copia;
  jl := motor.generar_jornada(op, '2026-11-09');
  perform pg_temp.comprobar('Lo arrastrado y no hecho el viernes vuelve a pasar al lunes',
    exists (select 1 from public.tareas where jornada_id = jl and tarea_origen_id = v_copia)
    and (select estado from public.tareas where id = v_copia) = 'arrastrada'
    and (select count(*) from public.tareas where jornada_id = jl and tarea_origen_id is not null) = 1);
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
