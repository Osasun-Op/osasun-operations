-- Prueba 02 · Idempotencia (criterio «Duplicados», §13) y acciones sobre tareas
-- Generar dos veces, repetir condiciones, iniciar o terminar dos veces: nada se
-- duplica. La base de datos rechaza duplicados aunque se intenten a mano.
-- Las dos llamadas a la vez se prueban en 06_concurrencia_*.sql.

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  ahora constant timestamptz := '2026-11-03 09:00:00+01';
  j uuid;
  j2 uuid;
  v_tareas integer;
  v_t uuid;
  v_otra uuid;
  r jsonb;
  r2 jsonb;
  v_fin timestamptz;
begin
  -- Generar dos veces
  j := motor.generar_jornada(op, '2026-11-03');
  select count(*) into v_tareas from public.tareas where jornada_id = j;
  j2 := motor.generar_jornada(op, '2026-11-03');
  perform pg_temp.comprobar('Generar la jornada dos veces devuelve la misma y no duplica tareas',
    j = j2 and (select count(*) from public.jornadas where persona_id = op and fecha = '2026-11-03') = 1
    and (select count(*) from public.tareas where jornada_id = j) = v_tareas,
    'tareas: ' || v_tareas || ' / ' || (select count(*) from public.tareas where jornada_id = j));

  perform motor.generar_jornadas_programadas('2026-11-03 06:00:00+01');
  perform motor.tarea_activa_de(op, ahora);
  perform motor.tarea_activa_de(op, ahora);
  perform pg_temp.comprobar('La generación programada y abrir la app varias veces no duplican nada',
    (select count(*) from public.jornadas where persona_id = op and fecha = '2026-11-03') = 1
    and (select count(*) from public.tareas where jornada_id = j) = v_tareas
    and (select count(*) from public.registro_eventos where jornada_id = j and tipo = 'jornada_generada') = 1);

  -- Repetir condiciones
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform prueba.fijar_condicion(j, 'hay_envio', 'true');
  perform prueba.fijar_condicion(j, 'hay_envio', 'true');
  perform pg_temp.comprobar('Repetir SALE:, reparto y envío no duplica tareas',
    (select count(*) from public.tareas where jornada_id = j and clave = 'salida_reparto') = 1
    and (select count(*) from public.tareas where jornada_id = j and clave = 'produccion_reparto') = 1
    and (select count(*) from public.tareas where jornada_id = j and clave = 'nacex_salida') = 1);

  perform prueba.fijar_condicion(j, 'pedido_cliente', 'p1');
  perform prueba.fijar_condicion(j, 'pedido_cliente', 'p1');
  perform prueba.fijar_condicion(j, 'pedido_cliente', 'p2');
  perform pg_temp.comprobar('El mismo pedido dos veces es uno; un segundo pedido es otra tarea',
    (select count(*) from public.tareas where jornada_id = j and clave like 'pedido_cliente:%') = 2);

  -- Iniciar dos veces
  select id into v_t from public.tareas where jornada_id = j and clave = 'produccion_reparto';
  r := motor.iniciar_tarea_de(op, v_t, ahora);
  r2 := motor.iniciar_tarea_de(op, v_t, ahora + interval '1 minute');
  perform pg_temp.comprobar('Iniciar dos veces: sin error, una sola tarea en curso y la hora de la primera vez',
    r ? 'tarea' and r2 ? 'tarea' and not r2 ? 'error'
    and (select iniciada_en from public.tareas where id = v_t) = ahora
    and (select count(*) from public.tareas where jornada_id = j and estado = 'en_curso') = 1
    and (select count(*) from public.registro_eventos where tarea_id = v_t and tipo = 'tarea_iniciada') = 1,
    r2::text);
  perform pg_temp.comprobar('La respuesta trae la nueva tarea activa (la que está en curso)',
    r -> 'tarea_activa' -> 'tarea' ->> 'id' = v_t::text, r::text);

  -- Otra tarea mientras hay una en curso
  select id into v_otra from public.tareas where jornada_id = j and clave = 'bolsas';
  r := motor.iniciar_tarea_de(op, v_otra, ahora);
  perform pg_temp.comprobar('Iniciar otra con una en curso: OTRA_TAREA_EN_CURSO',
    r -> 'error' ->> 'codigo' = 'OTRA_TAREA_EN_CURSO', r::text);

  -- Terminar dos veces
  r := motor.terminar_tarea_de(op, v_t, 'Hechas 12 cajas', null, ahora + interval '30 minutes');
  select terminada_en into v_fin from public.tareas where id = v_t;
  r2 := motor.terminar_tarea_de(op, v_t, 'otra vez', null, ahora + interval '40 minutes');
  perform pg_temp.comprobar('Terminar dos veces: sin error y se conserva el primer final y su resultado',
    not r2 ? 'error' and v_fin = ahora + interval '30 minutes'
    and (select terminada_en from public.tareas where id = v_t) = v_fin
    and (select resultado from public.tareas where id = v_t) = 'Hechas 12 cajas'
    and (select count(*) from public.registro_eventos where tarea_id = v_t and tipo = 'tarea_terminada') = 1,
    r2::text);

  -- Estados no válidos
  r := motor.terminar_tarea_de(op, v_otra, null, null, ahora);
  perform pg_temp.comprobar('Terminar una tarea que no está en curso: ESTADO_NO_VALIDO',
    r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);
  r := motor.iniciar_tarea_de(op, gen_random_uuid(), ahora);
  perform pg_temp.comprobar('Iniciar una tarea que no existe: NO_ENCONTRADO',
    r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  r := motor.iniciar_tarea_de(op, v_otra, '2026-11-04 09:00:00+01');
  perform pg_temp.comprobar('Iniciar una tarea de otro día: ESTADO_NO_VALIDO',
    r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);

  -- Anotar motivo
  r := motor.anotar_motivo_de(op, v_otra, '   ');
  perform pg_temp.comprobar('Anotar un motivo vacío: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.anotar_motivo_de(op, v_otra, 'Falta Bilbao por confirmar');
  perform pg_temp.comprobar('Anotar motivo: se guarda sin cambiar el estado',
    (select motivo_no_hecha from public.tareas where id = v_otra) = 'Falta Bilbao por confirmar'
    and (select estado from public.tareas where id = v_otra) = 'pendiente', r::text);
  r := motor.anotar_motivo_de(op, v_t, 'tarde');
  perform pg_temp.comprobar('Anotar motivo en una tarea hecha: ESTADO_NO_VALIDO',
    r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);

  -- La base de datos rechaza duplicados hechos a mano
  begin
    insert into public.jornadas (persona_id, centro_id, fecha)
    select op, centro_id, '2026-11-03' from public.personas where id = op;
    perform pg_temp.comprobar('Una segunda jornada a mano para el mismo día se rechaza', false, 'se insertó');
  exception when unique_violation then
    perform pg_temp.comprobar('Una segunda jornada a mano para el mismo día se rechaza', true);
  end;
  begin
    update public.tareas set estado = 'en_curso' where id in (v_otra, (select id from public.tareas where jornada_id = j and clave = 'cola_stock'));
    perform pg_temp.comprobar('Dos tareas en curso a la vez se rechazan', false, 'se aceptaron');
  exception when unique_violation then
    perform pg_temp.comprobar('Dos tareas en curso a la vez se rechazan', true);
  end;
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
