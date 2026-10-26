-- Prueba 10 · Tareas de Administración, conflictos, cancelar, estado actual y
-- cierre por turno con su correo (Tarea 4).
-- Martes 10/11/2026 a viernes 13/11/2026 y un martes de verano. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- Correo de destino ficticio solo para esta prueba (el real está en la configuración del entorno).
update public.configuracion set clave = 'correo_administracion_real' where clave = 'correo_administracion' and centro_id is null;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.destino(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
-- Reparto con 40 cajas que faltan (V2 4g 30, BZ1 4g 10) y dos tiendas; sale el operario.
create function pg_temp.guardar(p_jornada uuid, p_ahora timestamptz) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000001', p_jornada, 'reparto', 'texto', md5(p_jornada::text),
    motor.fecha_local(p_ahora), 'operario', null, '[]',
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 30, 'en_almacen', 0, 'faltan', 30, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 10, 'en_almacen', 0, 'faltan', 10, 'aviso', null, 'orden', 3)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.destino('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1))),
      jsonb_build_object('destino_id', pg_temp.destino('ALGORTA'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 10, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 10, 'orden', 3)))),
    true, p_ahora)
$$;
create function pg_temp.crear(p_id uuid, p_que text, p_cuando jsonb, p_dur integer, p_ahora timestamptz,
                              p_urgente boolean default false, p_confirmar boolean default true, p_decision jsonb default null)
returns jsonb language sql as $$
  select motor.crear_tarea_admin_de('00000000-0000-4000-a000-000000000002', p_id, p_que, null, p_cuando, p_dur,
                                    p_urgente, 'Prueba', p_confirmar, p_decision, p_ahora)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  j_mie uuid;
  j_jue uuid;
  j_vie uuid;
  r jsonb;
  r2 jsonb;
  v_prod uuid;
  v_bolsas uuid;
  v_el uuid;
  v_t uuid;
  v_t2 uuid;
  v_urg uuid;
  v_cierre uuid;
  v_cierre2 uuid;
  c1 uuid := gen_random_uuid();
  c2 uuid := gen_random_uuid();
  c3 uuid := gen_random_uuid();
  c4 uuid := gen_random_uuid();
  n integer;
begin
  j := motor.generar_jornada(op, '2026-11-10');
  update public.tareas set estado = 'hecha', terminada_en = '2026-11-10 08:50+01', iniciada_en = '2026-11-10 08:45+01',
         resultado = 'ok'
   where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto');

  -- Validaciones ---------------------------------------------------------------------
  r := pg_temp.crear(gen_random_uuid(), 'Llamar al proveedor', '{"tipo": "hoy"}', null, '2026-11-10 09:00+01');
  perform pg_temp.comprobar('Sin duración orientativa: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := pg_temp.crear(gen_random_uuid(), 'X', '{"tipo": "dia", "fecha": "2026-11-09"}', 10, '2026-11-10 09:00+01');
  perform pg_temp.comprobar('Un día pasado: FECHA_PASADA', r -> 'error' ->> 'codigo' = 'FECHA_PASADA', r::text);
  r := pg_temp.crear(gen_random_uuid(), 'X', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "08:55"}', 10, '2026-11-10 09:00+01');
  perform pg_temp.comprobar('Una hora pasada: FECHA_PASADA', r -> 'error' ->> 'codigo' = 'FECHA_PASADA', r::text);
  r := pg_temp.crear(gen_random_uuid(), 'X', '{"tipo": "dia", "fecha": "2026-11-14"}', 10, '2026-11-10 09:00+01');
  perform pg_temp.comprobar('Un sábado: SIN_JORNADA', r -> 'error' ->> 'codigo' = 'SIN_JORNADA', r::text);
  r := pg_temp.crear(gen_random_uuid(), 'X', '{"tipo": "mañana"}', 10, '2026-11-10 09:00+01');
  perform pg_temp.comprobar('«cuando» no válido: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);

  -- Comprobar y crear sin conflicto -----------------------------------------------------
  r := pg_temp.crear(c1, 'Llamar al proveedor', '{"tipo": "hoy"}', 10, '2026-11-10 09:00+01', false, false);
  perform pg_temp.comprobar('Solo comprobar (confirmar = false): sin conflicto y no crea nada',
    (r ->> 'comprobado')::boolean and r -> 'conflicto' = 'null'::jsonb
    and not exists (select 1 from public.tareas where id_cliente = c1), r::text);
  r := pg_temp.crear(c1, 'Llamar al proveedor', '{"tipo": "hoy"}', 10, '2026-11-10 09:00+01');
  v_t := (r ->> 'tarea_id')::uuid;
  r2 := pg_temp.crear(c1, 'Llamar al proveedor', '{"tipo": "hoy"}', 10, '2026-11-10 09:01+01');
  perform pg_temp.comprobar('Crear: tarea de Administración para hoy con su duración; repetirla no duplica',
    (select origen = 'administracion' and duracion_min = 10 and no_terminada = 'arrastrar' and creada_por = adm
            and jornada_id = j and porque = 'Prueba' from public.tareas where id = v_t)
    and (r2 ->> 'tarea_id')::uuid = v_t and (r2 ->> 'ya_creada')::boolean
    and (select count(*) from public.tareas where jornada_id = j and origen = 'administracion') = 1, r::text);

  -- Urgente: entra al terminar la referencia en curso ------------------------------------
  perform pg_temp.guardar(j, '2026-11-10 09:05+01');
  select id into v_prod from public.tareas where jornada_id = j and clave = 'produccion_reparto';
  select id into v_bolsas from public.tareas where jornada_id = j and clave = 'bolsas';
  select id into v_el from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1';
  perform motor.iniciar_elemento_de(op, v_el, '2026-11-10 09:10+01');
  r := pg_temp.crear(c2, 'Bajar cajas al coche', '{"tipo": "hoy"}', 5, '2026-11-10 09:12+01', true);
  v_urg := (r ->> 'tarea_id')::uuid;
  perform pg_temp.comprobar('Urgente creada: no interrumpe la referencia en curso',
    r ->> 'encaje' like 'Urgente:%'
    and motor.tarea_activa_de(op, '2026-11-10 09:13+01') -> 'tarea' ->> 'id' = v_prod::text, r::text);
  perform motor.terminar_elemento_de(op, v_el, '2026-11-10 09:20+01');
  perform pg_temp.comprobar('Al terminar la referencia, la tarea activa es la urgente',
    motor.tarea_activa_de(op, '2026-11-10 09:20+01') -> 'tarea' ->> 'id' = v_urg::text
    and (select estado from public.tareas where id = v_prod) = 'pendiente',
    (motor.tarea_activa_de(op, '2026-11-10 09:20+01') -> 'tarea' ->> 'titulo'));
  perform motor.iniciar_tarea_de(op, v_urg, '2026-11-10 09:21+01');
  perform motor.terminar_tarea_de(op, v_urg, 'Hecho', null, '2026-11-10 09:25+01');

  -- Conflicto -----------------------------------------------------------------------
  -- 09:30 → 10:45 = 75 min. Pendiente antes de las 10:45: producción 30 cajas + bolsas 2 tiendas × 3 = 36.
  r := pg_temp.crear(c3, 'Inventario de etiquetas', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 30,
                     '2026-11-10 09:30+01');
  perform pg_temp.comprobar('Cabe (36 + 30 ≤ 75): se crea con hora límite 10:45',
    r -> 'conflicto' = 'null'::jsonb
    and (select hora_limite from public.tareas where id = (r ->> 'tarea_id')::uuid) = '2026-11-10 10:45+01', r::text);
  r := pg_temp.crear(c4, 'Ordenar estantería', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 20,
                     '2026-11-10 09:30+01');
  perform pg_temp.comprobar('No cabe (36 + 30 + 20 = 86 > 75): CONFLICTO con las obligatorias en riesgo y 11 min que faltan; no se crea',
    r -> 'error' ->> 'codigo' = 'CONFLICTO'
    and (r -> 'error' -> 'conflicto' ->> 'minutos_que_faltan')::int = 11
    and (r -> 'error' -> 'conflicto' ->> 'disponible_min')::int = 75
    and r -> 'error' -> 'conflicto' -> 'obligatorias_en_riesgo' @> jsonb_build_array(jsonb_build_object('tarea_id', v_prod, 'duracion_min', 30))
    and r -> 'error' -> 'conflicto' -> 'obligatorias_en_riesgo' @> jsonb_build_array(jsonb_build_object('tarea_id', v_bolsas, 'duracion_min', 6))
    and not exists (select 1 from public.tareas where id_cliente = c4), r::text);
  r := pg_temp.crear(c4, 'Ordenar estantería', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 20,
                     '2026-11-10 09:30+01', false, true, jsonb_build_object('cede', gen_random_uuid(), 'accion', 'despues'));
  perform pg_temp.comprobar('Decisión con una tarea que no es de ese día: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := pg_temp.crear(c4, 'Ordenar estantería', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 20,
                     '2026-11-10 09:30+01', false, true, '{"accion": "no_crear"}');
  r2 := pg_temp.crear(c4, 'Ordenar estantería', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 20,
                      '2026-11-10 09:31+01', false, true, '{"accion": "no_crear"}');
  perform pg_temp.comprobar('Decisión «no crear»: no se crea, queda en el registro una sola vez',
    not (r ->> 'creada')::boolean and r2 ->> 'decision' = 'no_crear'
    and not exists (select 1 from public.tareas where id_cliente = c4)
    and (select count(*) from public.registro_eventos where tipo = 'conflicto_decidido' and datos ->> 'id_cliente' = c4::text) = 1, r::text);
  c4 := gen_random_uuid();
  r := pg_temp.crear(c4, 'Ordenar estantería', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 20,
                     '2026-11-10 09:30+01', false, true, jsonb_build_object('cede', v_bolsas, 'accion', 'despues'));
  perform pg_temp.comprobar('Decisión «cede las bolsas, después»: se crea la nueva, las bolsas pierden la hora y queda en el registro',
    (r ->> 'tarea_id') is not null and r -> 'decision' ->> 'accion' = 'despues'
    and (select hora_limite is null and motivo_no_hecha like 'Cede ante «Ordenar estantería»%' from public.tareas where id = v_bolsas)
    and exists (select 1 from public.registro_eventos where tipo = 'conflicto_decidido' and tarea_id = v_bolsas
                and datos ->> 'accion' = 'despues' and datos ->> 'nueva' = r ->> 'tarea_id'), r::text);
  r := pg_temp.crear(gen_random_uuid(), 'Revisar caducidades', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 60,
                     '2026-11-10 09:30+01', false, true, jsonb_build_object('cede', v_t, 'accion', 'manana'));
  perform pg_temp.comprobar('Decisión «pasa a mañana»: la que cede ya no sale hoy y se arrastrará',
    (select no_terminada = 'arrastrar' and disponible_desde = '2026-11-11 00:00+01' from public.tareas where id = v_t), r::text);
  v_t2 := (select id from public.tareas where jornada_id = j and titulo = 'Inventario de etiquetas');
  r := pg_temp.crear(gen_random_uuid(), 'Contar palés', '{"tipo": "antes_de", "fecha": "2026-11-10", "hora": "10:45"}', 60,
                     '2026-11-10 09:30+01', false, true, jsonb_build_object('cede', v_t2, 'accion', 'cancelar'));
  perform pg_temp.comprobar('Decisión «cancelar»: la que cede queda cancelada con su motivo',
    (select estado = 'cancelada' and motivo_no_hecha like 'Cede ante «Contar palés»%' from public.tareas where id = v_t2), r::text);

  -- Cancelar tarea -------------------------------------------------------------------
  v_t2 := (select id from public.tareas where jornada_id = j and titulo = 'Contar palés');
  r := motor.cancelar_tarea_de(adm, v_t2, ' ', '2026-11-10 09:40+01');
  perform pg_temp.comprobar('Cancelar sin motivo: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.cancelar_tarea_de(adm, v_t2, 'Ya no hace falta', '2026-11-10 09:40+01');
  r2 := motor.cancelar_tarea_de(adm, v_t2, 'Otra vez', '2026-11-10 09:41+01');
  perform pg_temp.comprobar('Cancelar con motivo: cancelada; repetirlo avisa YA_CANCELADA sin cambiar el motivo',
    (select estado = 'cancelada' and motivo_no_hecha = 'Ya no hace falta' from public.tareas where id = v_t2)
    and r2 -> 'aviso' ->> 'codigo' = 'YA_CANCELADA', r2::text);
  r := motor.cancelar_tarea_de(adm, v_urg, 'x', '2026-11-10 09:42+01');
  perform pg_temp.comprobar('Cancelar una tarea hecha: ESTADO_NO_VALIDO', r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);

  -- Tarea para otro día: la jornada se prepara y el arrastre se hace al llegar el día ---
  r := pg_temp.crear(gen_random_uuid(), 'Pedir precintos', '{"tipo": "dia", "fecha": "2026-11-12"}', 15, '2026-11-10 09:45+01');
  select id into j_jue from public.jornadas where persona_id = op and fecha = '2026-11-12';
  perform pg_temp.comprobar('Tarea para el jueves: su jornada queda preparada sin arrastre todavía',
    (select not arrastre_hecho from public.jornadas where id = j_jue)
    and (select jornada_id from public.tareas where id = (r ->> 'tarea_id')::uuid) = j_jue, r::text);

  -- Estado actual ----------------------------------------------------------------------
  perform motor.abrir_problema_de(op, gen_random_uuid(), v_prod, 'no_funciona', 'Báscula sin pilas', '2026-11-10 10:00+01');
  perform motor.iniciar_incidencia_de(op, gen_random_uuid(), 'Visita del inspector', '2026-11-10 10:05+01');
  perform motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-11-10 10:30+01');
  r := motor.estado_actual_de('2026-11-10 10:31+01');
  perform pg_temp.comprobar('estado_actual: operario, problemas abiertos, incidencia en curso, tareas de hoy, retrasos y lectura de Sheets',
    r -> 'operario' ->> 'id' = op::text
    and jsonb_array_length(r -> 'problemas_abiertos') = 1
    and r -> 'incidencia_en_curso' ->> 'descripcion' = 'Visita del inspector'
    and (r -> 'incidencia_en_curso' ->> 'minutos')::int = 26
    and jsonb_array_length(r -> 'hoy') > 5
    and r -> 'retrasos_salida' -> 0 ->> 'nueva_hora' = '11:00'
    and r -> 'lectura_sheets' ? 'ultima_correcta' and r ? 'arrastradas' and r ? 'en_curso', r::text);

  -- Cierre de la mañana (martes 13:00) ----------------------------------------------------
  perform motor.terminar_incidencia_de(op, (select id from public.incidencias where jornada_id = j and terminada_en is null), '2026-11-10 10:20+01');
  perform pg_temp.comprobar('A las 12:59 no se genera ningún cierre', motor.generar_cierres_programados('2026-11-10 12:59+01') = 0);
  n := motor.generar_cierres_programados('2026-11-10 13:00+01');
  select id into v_cierre from public.cierres where jornada_id = j and turno = 'manana';
  perform pg_temp.comprobar('A las 13:00 se genera el cierre de la mañana y se encola su correo',
    n = 1 and v_cierre is not null
    and (select count(*) from net.http_request_queue
          where convert_from(body, 'UTF8')::jsonb = jsonb_build_object('tipo', 'cierre', 'ref', v_cierre::text)) = 1);
  perform pg_temp.comprobar('Otra vez a las 13:30: no se genera otro ni se encola otro correo',
    motor.generar_cierres_programados('2026-11-10 13:30+01') = 0
    and (select count(*) from net.http_request_queue
          where convert_from(body, 'UTF8')::jsonb = jsonb_build_object('tipo', 'cierre', 'ref', v_cierre::text)) = 1
    and motor.generar_cierre(j, 'manana', '2026-11-10 13:31+01') = v_cierre
    and (select count(*) from public.cierres where jornada_id = j) = 1);
  r := (select contenido from public.cierres where id = v_cierre);
  perform pg_temp.comprobar('Cierre de la mañana: hecho con resultado (revisión, pegar, la urgente)',
    r -> 'hecho' @> '[{"titulo": "Bajar cajas al coche", "resultado": "Hecho", "hora": "09:25"}]'
    and jsonb_array_length(r -> 'hecho') = 3, (r -> 'hecho')::text);
  perform pg_temp.comprobar('Cierre de la mañana: no hecho con motivo (recuento sin hacer, producción bloqueada, la cancelada)',
    r -> 'no_hecho' @> '[{"titulo": "Contar palés", "estado": "cancelada", "motivo": "Ya no hace falta"}]'
    and exists (select 1 from jsonb_array_elements(r -> 'no_hecho') x
                where x ->> 'estado' = 'bloqueada' and x ->> 'motivo' = 'Bloqueada por un problema sin resolver')
    and exists (select 1 from jsonb_array_elements(r -> 'no_hecho') x, public.tareas t
                where t.jornada_id = j and t.clave = 'recuento_manana' and x ->> 'titulo' = t.titulo
                  and x ->> 'motivo' = 'Sin motivo anotado'), (r -> 'no_hecho')::text);
  perform pg_temp.comprobar('Cierre de la mañana: problema sin resolver con su tiempo (180 min, más de 5) e incidencia de 15 min',
    r -> 'problemas' @> '[{"descripcion": "Báscula sin pilas", "minutos": 180, "mas_de_5_min": true, "estado": "abierto"}]'
    and r -> 'incidencias' @> '[{"descripcion": "Visita del inspector", "minutos": 15}]', r::text);
  perform pg_temp.comprobar('Cierre de la mañana: retraso cruzado con el reparto (40 cajas pedidas, 40 a producir, 10 hechas, 2 tiendas) y 1 incidencia',
    r -> 'retrasos_salida' @> '[{"minutos": 15, "nueva_hora": "11:00", "a_las": "10:30"}]'
    and r -> 'cruce_retrasos' = '{"cajas_reparto": 40, "cajas_a_producir": 40, "cajas_producidas": 10, "tiendas": 2, "incidencias_manana": 1, "minutos_incidencias_manana": 15}'::jsonb,
    (r -> 'cruce_retrasos')::text);
  perform pg_temp.comprobar('Cierre de la mañana: lo que queda para la tarde, sin calidad (no es viernes), jornada sigue abierta',
    r -> 'siguiente' ->> 'turno' = 'tarde' and r -> 'calidad' = 'null'::jsonb
    and (select estado from public.jornadas where id = j) = 'abierta', r::text);
  r2 := motor.texto_cierre(r);
  perform pg_temp.comprobar('Texto del correo del cierre: asunto y apartados',
    r2 ->> 'asunto' = 'Cierre mañana · martes 10/11 · Hecho: 3 · Sin hacer: ' || jsonb_array_length(r -> 'no_hecho')
    and r2 ->> 'texto' like '%HECHO%NO HECHO%PROBLEMAS%Báscula sin pilas%INCIDENCIAS%RETRASOS DE LA SALIDA%LO QUE QUEDA PARA LA TARDE%',
    r2::text);

  -- Correo: se reclama una sola vez ----------------------------------------------------
  r := public.servidor_correo_reclamar('cierre', v_cierre::text);
  perform pg_temp.comprobar('Sin correo de destino en la configuración: SIN_DESTINO (no se envía nada)',
    r -> 'error' ->> 'codigo' = 'SIN_DESTINO' and (select envio_reclamado_en is null from public.cierres where id = v_cierre), r::text);
  insert into public.configuracion (clave, centro_id, valor) values ('correo_administracion', null, '"admin@osasun.invalid"');
  r := public.servidor_correo_reclamar('cierre', v_cierre::text);
  r2 := public.servidor_correo_reclamar('cierre', v_cierre::text);
  perform pg_temp.comprobar('Cierre: la primera vez se envía (destino, asunto, texto); la segunda no (nunca dos correos)',
    (r ->> 'enviar')::boolean and r ->> 'destino' = 'admin@osasun.invalid' and r ->> 'asunto' like 'Cierre mañana%'
    and not (r2 ->> 'enviar')::boolean, r2::text);
  perform public.servidor_correo_resultado('cierre', v_cierre::text, true, 'resend:abc');
  perform pg_temp.comprobar('Resultado del envío: queda enviado por correo',
    (select enviado_en is not null and canal = 'correo' from public.cierres where id = v_cierre));
  r := public.servidor_correo_reclamar('retraso',
         (select id::text from public.registro_eventos where jornada_id = j and tipo = 'salida_retrasada'));
  r2 := public.servidor_correo_reclamar('retraso',
         (select id::text from public.registro_eventos where jornada_id = j and tipo = 'salida_retrasada'));
  perform pg_temp.comprobar('Retraso: asunto «Salida retrasada a las 11:00», una sola vez',
    r ->> 'asunto' = 'Salida retrasada a las 11:00' and not (r2 ->> 'enviar')::boolean, r::text);

  -- Cierre de la tarde (martes 18:30) ----------------------------------------------------
  perform motor.resolver_problema_de(adm, (select id from public.problemas where jornada_id = j and estado <> 'resuelto'),
                                     'Pilas nuevas', '2026-11-10 15:40+01');
  n := motor.generar_cierres_programados('2026-11-10 18:30+01');
  select id into v_cierre2 from public.cierres where jornada_id = j and turno = 'tarde';
  r := (select contenido from public.cierres where id = v_cierre2);
  perform pg_temp.comprobar('A las 18:30 se genera el cierre de la tarde y la jornada queda cerrada',
    n = 1 and v_cierre2 is not null and (select estado from public.jornadas where id = j) = 'cerrada', n::text);
  perform pg_temp.comprobar('Cierre de la tarde: el problema resuelto por la tarde con su solución; sin lo hecho por la mañana',
    r -> 'problemas' @> '[{"descripcion": "Báscula sin pilas", "solucion": "Pilas nuevas", "estado": "resuelto"}]'
    and not r -> 'hecho' @> '[{"titulo": "Bajar cajas al coche"}]' and r -> 'retrasos_salida' = 'null'::jsonb, r::text);
  perform pg_temp.comprobar('Cierre de la tarde: lo de Administración sin hacer pasa al día siguiente; lo que toca el miércoles',
    r -> 'arrastrados' -> 'pasan_a_manana' @> '["Ordenar estantería"]'
    and r -> 'siguiente' ->> 'fecha' = '2026-11-11' and jsonb_array_length(r -> 'siguiente' -> 'tareas') > 0
    and motor.texto_cierre(r) ->> 'texto' like '%PASAN AL DÍA SIGUIENTE%Ordenar estantería%', r::text);

  -- Miércoles y jueves: arrastres, también a la jornada preparada ---------------------------
  j_mie := motor.generar_jornada(op, '2026-11-11');
  perform pg_temp.comprobar('Miércoles: llegan arrastradas la que cedió «a mañana» y las de Administración sin hacer',
    exists (select 1 from public.tareas where jornada_id = j_mie and tarea_origen_id = v_t)
    and exists (select 1 from public.tareas where jornada_id = j_mie and titulo = 'Ordenar estantería' and tarea_origen_id is not null));
  update public.tareas set estado = 'hecha' where jornada_id = j_mie and estado in ('pendiente', 'en_curso', 'bloqueada');
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, no_terminada, obligatoria)
  values (j_mie, 'prueba_arrastre', 'administracion', 'Pendiente del miércoles', '2026-11-11 08:30+01', 'arrastrar', false);
  perform motor.generar_jornada(op, '2026-11-12');
  perform pg_temp.comprobar('Jueves (preparado el martes): al llegar el día se arrastra lo del miércoles, una vez, y sigue la tarea del martes',
    (select arrastre_hecho from public.jornadas where id = j_jue)
    and (select count(*) from public.tareas where jornada_id = j_jue and titulo = 'Pendiente del miércoles') = 1
    and (select count(*) from public.tareas where jornada_id = j_jue and titulo = 'Pedir precintos') = 1
    and motor.generar_jornada(op, '2026-11-12') = j_jue
    and (select count(*) from public.tareas where jornada_id = j_jue and titulo = 'Pendiente del miércoles') = 1);

  -- Viernes: un solo cierre a las 13:00 con la calidad (limpieza hecha) --------------------
  update public.tareas set estado = 'hecha' where jornada_id = j_jue and estado in ('pendiente', 'en_curso', 'bloqueada');
  j_vie := motor.generar_jornada(op, '2026-11-13');
  update public.tareas t set estado = 'hecha', terminada_en = '2026-11-13 10:00+01'
    from public.plantillas_tarea p where p.id = t.plantilla_id and t.jornada_id = j_vie and p.codigo = 'limpieza_resinas';
  n := motor.generar_cierres_programados('2026-11-13 13:00+01');
  r := (select contenido from public.cierres where jornada_id = j_vie);
  perform pg_temp.comprobar('Viernes 13:00: un solo cierre, con calidad = limpieza hecha, y la jornada cerrada',
    n = 1 and r -> 'calidad' = '{"limpieza_viernes": true}'::jsonb and (select estado from public.jornadas where id = j_vie) = 'cerrada'
    and r -> 'siguiente' ->> 'fecha' = '2026-11-16', r::text);
  perform pg_temp.comprobar('Viernes 18:30: no hay turno de tarde, no se genera nada más',
    motor.generar_cierres_programados('2026-11-13 18:30+01') = 0
    and (select count(*) from public.cierres where jornada_id = j_vie) = 1);
  perform pg_temp.comprobar('Texto del viernes: «Limpieza hecha: sí»',
    motor.texto_cierre(r) ->> 'texto' like '%CALIDAD DEL VIERNES%Limpieza hecha: sí%');

  -- Verano: 13:00 en Madrid son las 11:00 UTC -----------------------------------------------
  update public.tareas set estado = 'hecha' where jornada_id = j_vie and estado in ('pendiente', 'en_curso', 'bloqueada');
  perform motor.generar_jornada(op, '2027-06-15');
  perform pg_temp.comprobar('Verano: el cierre de la mañana se genera a las 11:00 UTC (13:00 en Madrid), no antes',
    motor.generar_cierres_programados('2027-06-15 10:30+00') = 0
    and motor.generar_cierres_programados('2027-06-15 11:00+00') = 1);
  perform pg_temp.comprobar('Tarea programada de los cierres: a y media y en punto de 11, 12, 16 y 17 UTC, de lunes a viernes',
    exists (select 1 from cron.job where jobname = 'generar_cierres_turno' and schedule = '0,30 11,12,16,17 * * 1-5'));
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
