-- Prueba 24 · «Hoy» del panel con interrupciones, cajas y minutos trabajados
-- (Tarea 21, ESTADO v1.35 §8 Inicio, punto 4; CONTRATOS §4.3). Rehace lo del
-- 30/10: el +35 % empieza a las 09:54, a las 10:45 entra la salida del reparto
-- con 3 de 6 hechos (21 de 43 cajas, 52 min trabajados: todo el tiempo en marcha,
-- también entre productos, sin la ruta) y se retoma a las 12:05.
-- Con las horas exactas del 30/10. Martes 03/11/2026, sale el operario. Transacción deshecha.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.h(p_hora text) returns timestamptz language sql as $$
  select ('2026-11-03 ' || p_hora || '+01')::timestamptz $$;
-- La tarea de «hoy» con esa clave en estado_actual.
create function pg_temp.hoy(p_jornada uuid, p_clave text, p_ahora timestamptz) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.estado_actual_de(p_ahora) -> 'hoy') x
   where x ->> 'id' = (select id::text from public.tareas where jornada_id = p_jornada and clave = p_clave) $$;
create function pg_temp.elemento(p_jornada uuid, p_producto text) returns uuid language sql as $$
  select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
   where t.jornada_id = p_jornada and t.clave = 'cola_stock' and e.producto = p_producto $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid;
  v_stock uuid;
  x jsonb;
  r jsonb;
begin
  j := motor.generar_jornada(op, '2026-11-03');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.h('08:30'), terminada_en = pg_temp.h('08:40')
   where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto', 'produccion_reparto', 'bolsas');

  -- La lista del +35 % del 30/10: 6 referencias, 43 cajas.
  v_stock := (select id from public.tareas where jornada_id = j and clave = 'cola_stock');
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, orden_sugerido)
  values (v_stock, 'referencia_produccion', 'manana', 'Indoor', '4g', 6, 1),
         (v_stock, 'referencia_produccion', 'manana', 'Invernadero', '4g', 14, 2),
         (v_stock, 'referencia_produccion', 'manana', 'BZ1', '4g', 1, 3),
         (v_stock, 'referencia_produccion', 'manana', 'SLUSH MINTS', '10g', 13, 4),
         (v_stock, 'referencia_produccion', 'manana', 'KUSH WATERHASH', '4g', 4, 5),
         (v_stock, 'referencia_produccion', 'manana', 'SUGAR', 'CBDX', 5, 6);

  perform motor.iniciar_elemento_de(op, pg_temp.elemento(j, 'Indoor'), pg_temp.h('09:54:09.451908'));
  perform motor.terminar_elemento_de(op, pg_temp.elemento(j, 'Indoor'), pg_temp.h('10:05:52.0361'));
  perform motor.iniciar_elemento_de(op, pg_temp.elemento(j, 'Invernadero'), pg_temp.h('10:05:55.80187'));
  perform motor.terminar_elemento_de(op, pg_temp.elemento(j, 'Invernadero'), pg_temp.h('10:22:17.911059'));
  perform motor.iniciar_elemento_de(op, pg_temp.elemento(j, 'BZ1'), pg_temp.h('10:42:23.674781'));
  perform motor.terminar_elemento_de(op, pg_temp.elemento(j, 'BZ1'), pg_temp.h('10:45:48.718458'));

  perform pg_temp.comprobar('10:45: al terminar BZ1 entra la salida y el +35 % vuelve a pendiente',
    (select estado from public.tareas where id = v_stock) = 'pendiente');

  x := pg_temp.hoy(j, 'cola_stock', pg_temp.h('11:00'));
  perform pg_temp.comprobar('11:00: interrumpida a las 10:45 por «Salida del reparto», sin seguir todavía',
    x -> 'interrupciones' = jsonb_build_array(jsonb_build_object(
      'a_las', pg_temp.h('10:45:48.718458'), 'por', 'Salida del reparto', 'siguio_a_las', null)), x ->> 'interrupciones');
  perform pg_temp.comprobar('11:00: «21 de 43» cajas y 52 min trabajados (de 09:54 a 10:45, también entre productos; sin la ruta)',
    x -> 'cajas' = '{"hechas": 21, "total": 43}' and (x ->> 'minutos_trabajados')::int = 52, x::text);
  perform pg_temp.comprobar('Los campos de antes no cambian (iniciada a las 09:54; pendiente: minutos null)',
    (x ->> 'iniciada_en')::timestamptz = pg_temp.h('09:54:09.451908') and x -> 'terminada_en' = 'null'
    and x -> 'minutos' = 'null' and x ->> 'estado' = 'pendiente', x::text);

  -- Vuelve de la ruta y sigue a las 12:05.
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.h('10:46'), terminada_en = pg_temp.h('12:00')
   where jornada_id = j and clave in ('salida_reparto', 'efectivo_reporte');
  perform motor.iniciar_elemento_de(op, pg_temp.elemento(j, 'SLUSH MINTS'), pg_temp.h('12:05'));
  x := pg_temp.hoy(j, 'cola_stock', pg_temp.h('12:15'));
  perform pg_temp.comprobar('12:15: siguió a las 12:05; en marcha otra vez, cuenta hasta ahora (52 + 10)',
    x -> 'interrupciones' -> 0 ->> 'siguio_a_las' is not null
    and (x -> 'interrupciones' -> 0 ->> 'siguio_a_las')::timestamptz = pg_temp.h('12:05')
    and (x ->> 'minutos_trabajados')::int = 62 and x -> 'cajas' = '{"hechas": 21, "total": 43}', x::text);
  perform motor.terminar_elemento_de(op, pg_temp.elemento(j, 'SLUSH MINTS'), pg_temp.h('12:20'));
  x := pg_temp.hoy(j, 'cola_stock', pg_temp.h('12:20'));
  perform pg_temp.comprobar('12:20: SLUSH MINTS hecho: «34 de 43» y 67 min trabajados (minutos de inicio a fin, 146, con la ruta)',
    x -> 'cajas' = '{"hechas": 34, "total": 43}' and (x ->> 'minutos_trabajados')::int = 67
    and (x ->> 'minutos')::int = 146 and jsonb_array_length(x -> 'interrupciones') = 1, x::text);

  -- Termina a las 12:40 con el resto: 52 + 35 = 87 min trabajados (la ruta no cuenta).
  perform motor.iniciar_elemento_de(op, pg_temp.elemento(j, 'KUSH WATERHASH'), pg_temp.h('12:22'));
  perform motor.terminar_elemento_de(op, pg_temp.elemento(j, 'KUSH WATERHASH'), pg_temp.h('12:30'));
  perform motor.iniciar_elemento_de(op, pg_temp.elemento(j, 'SUGAR'), pg_temp.h('12:31'));
  perform motor.terminar_elemento_de(op, pg_temp.elemento(j, 'SUGAR'), pg_temp.h('12:40'));
  x := pg_temp.hoy(j, 'cola_stock', pg_temp.h('13:00'));
  perform pg_temp.comprobar('12:40: hecha, «43 de 43» y 87 min trabajados (09:54–10:45 y 12:05–12:40); de inicio a fin, 166',
    x ->> 'estado' = 'hecha' and x -> 'cajas' = '{"hechas": 43, "total": 43}'
    and (x ->> 'minutos_trabajados')::int = 87 and (x ->> 'minutos')::int = 166, x::text);

  -- Tareas sin interrupciones y que no son de producción.
  x := pg_temp.hoy(j, 'revision_inicial', pg_temp.h('12:30'));
  perform pg_temp.comprobar('Sin interrupciones: lista vacía; no es de producción: cajas y minutos_trabajados null',
    x -> 'interrupciones' = '[]' and x -> 'cajas' = 'null' and x -> 'minutos_trabajados' = 'null', x::text);
  x := pg_temp.hoy(j, 'produccion_reparto', pg_temp.h('12:30'));
  perform pg_temp.comprobar('La producción del reparto también es de producción (sin elementos: cajas null)',
    x -> 'interrupciones' = '[]' and x ? 'cajas' and x ? 'minutos_trabajados', x::text);
  r := motor.estado_actual_de(pg_temp.h('12:30'));
  perform pg_temp.comprobar('Todas las tareas de «hoy» traen los tres campos nuevos',
    (select bool_and(t ?& array['interrupciones', 'cajas', 'minutos_trabajados', 'iniciada_en', 'terminada_en', 'minutos'])
       from jsonb_array_elements(r -> 'hoy') t), r ->> 'hoy');
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
