-- Prueba 09 · Problemas, incidencias, eventos y retraso de la salida (Tarea 4)
-- Flujo completo del botón «Tengo un problema» (llamada, sin respuesta,
-- reaparición a los 30 min, solución obligatoria), incidencias, los tres
-- eventos, el retraso de la salida (15/30 min, con aviso por correo si sale
-- Administración) y el envío pegado antes del recuento (PR #3).
-- Martes 10/11/2026 y miércoles 11/11/2026. Transacción deshecha al final.

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
create function pg_temp.destino(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.reparto(p_sale text) returns jsonb language sql as $$
  select jsonb_build_object(
    'sale', p_sale,
    'produccion', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 30, 'en_almacen', 25, 'faltan', 5, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 9, 'en_almacen', 7, 'faltan', 2, 'aviso', null, 'orden', 3)),
    'bolsas', jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.destino('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 5, 'orden', 3))),
      jsonb_build_object('destino_id', pg_temp.destino('ALGORTA'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 10, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 4, 'orden', 3)))))
$$;
create function pg_temp.guardar(p_jornada uuid, p_datos jsonb, p_ahora timestamptz) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000001', p_jornada, 'reparto', 'texto ' || (p_datos ->> 'sale'), md5(p_jornada::text),
    motor.fecha_local(p_ahora), p_datos ->> 'sale', null, '[]', p_datos -> 'produccion', p_datos -> 'bolsas', true, p_ahora)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  d constant date := '2026-11-10';
  j uuid;
  j2 uuid;
  r jsonb;
  r2 jsonb;
  v_rev uuid;
  v_pegar uuid;
  v_prob uuid;
  v_prob2 uuid;
  v_llamada uuid;
  v_inc uuid;
  v_t uuid;
  c1 uuid := gen_random_uuid();
  c2 uuid := gen_random_uuid();
begin
  j := motor.generar_jornada(op, d);
  select id into v_rev from public.tareas where jornada_id = j and clave = 'revision_inicial';
  select id into v_pegar from public.tareas where jornada_id = j and clave = 'pegar_reparto';

  -- Problemas ----------------------------------------------------------------------
  r := motor.abrir_problema_de(op, c1, v_rev, 'falta_material', 'No hay cinta', '2026-11-10 08:35+01');
  v_prob := (r -> 'problema' ->> 'id')::uuid;
  perform pg_temp.comprobar('Abrir problema: la tarea queda bloqueada y se dan los pasos (1 minuto y llamar)',
    (select estado from public.tareas where id = v_rev) = 'bloqueada'
    and r -> 'problema' ->> 'estado' = 'abierto'
    and r ->> 'pasos' = 'Si en 1 minuto no está resuelto, llama a Administración.', r::text);
  r2 := motor.abrir_problema_de(op, c1, v_rev, 'falta_material', 'No hay cinta', '2026-11-10 08:36+01');
  perform pg_temp.comprobar('Abrir problema dos veces con el mismo id_cliente: el mismo problema',
    (r2 -> 'problema' ->> 'id')::uuid = v_prob and (select count(*) from public.problemas where jornada_id = j) = 1, r2::text);
  r2 := motor.abrir_problema_de(op, gen_random_uuid(), v_rev, 'otro', 'Otra cosa', '2026-11-10 08:36+01');
  perform pg_temp.comprobar('Otro problema en la misma tarea: PROBLEMA_YA_ABIERTO',
    r2 -> 'error' ->> 'codigo' = 'PROBLEMA_YA_ABIERTO', r2::text);
  r2 := motor.abrir_problema_de(op, gen_random_uuid(), v_pegar, 'raro', 'x', '2026-11-10 08:36+01');
  perform pg_temp.comprobar('Tipo de problema no válido: DATOS_NO_VALIDOS', r2 -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r2::text);
  perform pg_temp.comprobar('Con el problema abierto, sigue con otra tarea (la bloqueada no sale)',
    motor.tarea_activa_de(op, '2026-11-10 08:36+01') -> 'tarea' ->> 'id' is distinct from v_rev::text);

  r := motor.problema_llamada_de(op, v_prob, false, '2026-11-10 08:37+01');
  select id into v_llamada from public.tareas where jornada_id = j and clave = 'problema:' || v_prob || ':1';
  perform pg_temp.comprobar('No contestan: WhatsApp registrado y «Llama a Administración» a las 09:07 (30 min después)',
    r -> 'problema' ->> 'estado' = 'sin_respuesta'
    and (select whatsapp_en = '2026-11-10 08:37+01' and proxima_llamada_en = '2026-11-10 09:07+01' and llamadas = 1
           from public.problemas where id = v_prob)
    and (select disponible_desde = '2026-11-10 09:07+01' and titulo = 'Llama a Administración: No hay cinta'
           from public.tareas where id = v_llamada), r::text);
  perform pg_temp.comprobar('A las 09:06 todavía no aparece la llamada',
    motor.tarea_activa_de(op, '2026-11-10 09:06+01') -> 'tarea' ->> 'id' is distinct from v_llamada::text);
  perform pg_temp.comprobar('A las 09:07 la tarea activa es «Llama a Administración» (escalón 2)',
    motor.tarea_activa_de(op, '2026-11-10 09:07+01') -> 'tarea' ->> 'id' = v_llamada::text,
    (motor.tarea_activa_de(op, '2026-11-10 09:07+01') -> 'tarea')::text);

  r := motor.problema_llamada_de(op, v_prob, false, '2026-11-10 09:08+01');
  perform pg_temp.comprobar('Segunda llamada sin respuesta: la anterior queda hecha y aparece otra a las 09:38',
    (select estado from public.tareas where id = v_llamada) = 'hecha'
    and (select disponible_desde from public.tareas where jornada_id = j and clave = 'problema:' || v_prob || ':2') = '2026-11-10 09:38+01'
    and (select llamadas from public.problemas where id = v_prob) = 2, r::text);

  r := motor.resolver_problema_de(op, v_prob, '   ', '2026-11-10 09:09+01');
  perform pg_temp.comprobar('Resolver sin solución: SOLUCION_OBLIGATORIA', r -> 'error' ->> 'codigo' = 'SOLUCION_OBLIGATORIA', r::text);
  r := motor.resolver_problema_de(adm, v_prob, 'Cinta en el armario 2', '2026-11-10 09:10+01');
  perform pg_temp.comprobar('Administración lo resuelve: solución guardada, la tarea vuelve a pendiente, la llamada pendiente se cancela; 35 min',
    (select estado = 'resuelto' and resuelto_por = adm and solucion = 'Cinta en el armario 2' from public.problemas where id = v_prob)
    and (select estado from public.tareas where id = v_rev) = 'pendiente'
    and (select estado from public.tareas where jornada_id = j and clave = 'problema:' || v_prob || ':2') = 'cancelada'
    and (r -> 'problema' ->> 'minutos_hasta_solucion')::int = 35, r::text);
  r := motor.resolver_problema_de(op, v_prob, 'Otra', '2026-11-10 09:11+01');
  perform pg_temp.comprobar('Resolver otra vez: aviso PROBLEMA_YA_RESUELTO, sin cambiar la solución',
    r -> 'aviso' ->> 'codigo' = 'PROBLEMA_YA_RESUELTO'
    and (select solucion from public.problemas where id = v_prob) = 'Cinta en el armario 2', r::text);

  r := motor.abrir_problema_de(op, gen_random_uuid(), v_pegar, 'no_encuentro', 'No encuentro el texto', '2026-11-10 09:12+01');
  v_prob2 := (r -> 'problema' ->> 'id')::uuid;
  perform pg_temp.comprobar('«No encuentro»: llamar a Administración ahora', r ->> 'pasos' = 'Llama a Administración ahora.', r::text);
  r := motor.problema_llamada_de(op, v_prob2, true, '2026-11-10 09:13+01');
  perform pg_temp.comprobar('Contestan: el problema sigue abierto y pide escribir la solución, sin tarea de volver a llamar',
    r -> 'problema' ->> 'estado' = 'abierto' and r ->> 'pasos' = 'Escribe en una línea la solución acordada.'
    and not exists (select 1 from public.tareas where jornada_id = j and clave like 'problema:' || v_prob2 || ':%'), r::text);
  r := motor.resolver_problema_de('00000000-0000-4000-a000-000000000009', v_prob2, 'x', '2026-11-10 09:14+01');
  perform pg_temp.comprobar('Otra persona no puede resolverlo: NO_ENCONTRADO', r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  r := motor.resolver_problema_de(op, v_prob2, 'Me lo ha mandado por WhatsApp', '2026-11-10 09:14+01');
  perform pg_temp.comprobar('El operario lo resuelve: 2 minutos', (r -> 'problema' ->> 'minutos_hasta_solucion')::int = 2, r::text);

  -- Incidencias --------------------------------------------------------------------
  perform motor.iniciar_tarea_de(op, v_pegar, '2026-11-10 09:15+01');
  r := motor.iniciar_incidencia_de(op, c2, 'Ha venido el técnico de la luz', '2026-11-10 09:20+01');
  v_inc := (r ->> 'incidencia_id')::uuid;
  perform pg_temp.comprobar('Incidencia: queda registrada con la tarea que estaba en curso',
    (select tarea_id = v_pegar and iniciada_en = '2026-11-10 09:20+01' from public.incidencias where id = v_inc), r::text);
  r := motor.iniciar_incidencia_de(op, c2, 'Ha venido el técnico de la luz', '2026-11-10 09:21+01');
  perform pg_temp.comprobar('Repetir con el mismo id_cliente: la misma incidencia', (r ->> 'incidencia_id')::uuid = v_inc, r::text);
  r := motor.iniciar_incidencia_de(op, gen_random_uuid(), 'Otra', '2026-11-10 09:22+01');
  perform pg_temp.comprobar('Otra incidencia con una abierta: INCIDENCIA_YA_ABIERTA', r -> 'error' ->> 'codigo' = 'INCIDENCIA_YA_ABIERTA', r::text);
  r := motor.iniciar_incidencia_de(op, gen_random_uuid(), '', '2026-11-10 09:22+01');
  perform pg_temp.comprobar('Incidencia sin descripción: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.terminar_incidencia_de(op, v_inc, '2026-11-10 09:32+01');
  r2 := motor.terminar_incidencia_de(op, v_inc, '2026-11-10 09:40+01');
  perform pg_temp.comprobar('Terminar incidencia: 12 minutos; repetirlo no cambia la hora',
    (r ->> 'minutos')::int = 12 and (r2 ->> 'minutos')::int = 12, r2::text);
  perform motor.terminar_tarea_de(op, v_pegar, null, null, '2026-11-10 09:41+01');

  -- Eventos ------------------------------------------------------------------------
  r := motor.registrar_evento_de(op, c1, 'llega_mercancia', 'Palé de cajas', '2026-11-10 09:45+01');
  perform pg_temp.comprobar('Llega mercancía: crea «Recepción de mercancía» urgente con el detalle como porqué',
    r -> 'tarea' ->> 'origen' = 'evento' and (r -> 'tarea' ->> 'urgente')::boolean
    and r -> 'tarea' ->> 'porque' is not null
    and (select tarea_id from public.eventos_jornada where id = (r ->> 'evento_id')::uuid) = (r -> 'tarea' ->> 'id')::uuid, r::text);
  r2 := motor.registrar_evento_de(op, c1, 'llega_mercancia', 'Palé de cajas', '2026-11-10 09:46+01');
  perform pg_temp.comprobar('El mismo evento dos veces (id_cliente): no duplica',
    r2 ->> 'evento_id' = r ->> 'evento_id' and (select count(*) from public.eventos_jornada where jornada_id = j) = 1, r2::text);
  r := motor.registrar_evento_de(adm, gen_random_uuid(), 'pedido_cliente', 'Cliente de Getxo', '2026-11-10 09:50+01');
  r2 := motor.registrar_evento_de(op, gen_random_uuid(), 'pedido_cliente', 'Cliente de Bilbao', '2026-11-10 09:51+01');
  perform pg_temp.comprobar('Pedido de cliente desde Administración y desde el operario: dos tareas en la jornada del operario',
    (select count(*) from public.tareas t join public.eventos_jornada e on e.tarea_id = t.id
      where t.jornada_id = j and e.tipo = 'pedido_cliente') = 2
    and r -> 'tarea_activa' = 'null'::jsonb, r::text || r2::text);
  r := motor.registrar_evento_de(adm, gen_random_uuid(), 'llega_mercancia', null, '2026-11-10 09:52+01');
  perform pg_temp.comprobar('Administración no registra «llega mercancía»: NO_AUTORIZADO', r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text);
  r := motor.registrar_evento_de(op, gen_random_uuid(), 'no_quedan_vapers', null, '2026-11-10 09:53+01');
  perform pg_temp.comprobar('No quedan vapers: crea la tirada de vapers', r -> 'tarea' ->> 'titulo' is not null and r -> 'tarea' ->> 'origen' = 'evento', r::text);
  r := motor.registrar_evento_de(op, gen_random_uuid(), 'otra_cosa', null, '2026-11-10 09:53+01');
  perform pg_temp.comprobar('Evento de tipo no válido: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);

  -- Retraso de la salida --------------------------------------------------------------
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-11-10 09:55+01');
  perform pg_temp.comprobar('Retrasar sin bolsas (sin reparto): SIN_TAREA', r -> 'error' ->> 'codigo' = 'SIN_TAREA', r::text);
  perform pg_temp.guardar(j, pg_temp.reparto('operario'), '2026-11-10 09:56+01');
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 20, '2026-11-10 10:30+01');
  perform pg_temp.comprobar('Retraso de 20 min: DATOS_NO_VALIDOS (solo 15 o 30)', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.retrasar_salida_de(op, c1, 15, '2026-11-10 10:30+01');
  r2 := motor.retrasar_salida_de(op, c1, 15, '2026-11-10 10:31+01');
  perform pg_temp.comprobar('Retrasar 15: bolsas y salida a las 11:00; sale el operario, sin correo; repetirlo no lo mueve otra vez',
    r ->> 'nueva_hora_salida' = '11:00' and r ->> 'aviso' = 'sin_aviso' and r2 ->> 'nueva_hora_salida' = '11:00'
    and (select hora_limite from public.tareas where jornada_id = j and clave = 'bolsas') = '2026-11-10 11:00+01'
    and (select hora_programada from public.tareas where jornada_id = j and clave = 'salida_reparto') = '2026-11-10 11:00+01'
    and (select count(*) from public.registro_eventos where jornada_id = j and tipo = 'salida_retrasada') = 1, r::text);
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 30, '2026-11-10 10:55+01');
  perform pg_temp.comprobar('Retrasar 30 más: salida a las 11:30', r ->> 'nueva_hora_salida' = '11:30', r::text);

  -- Miércoles: sale Administración → correo «Salida retrasada a las HH:MM»
  j2 := motor.generar_jornada(op, '2026-11-11');
  perform pg_temp.guardar(j2, pg_temp.reparto('administracion'), '2026-11-11 09:00+01');
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-11-11 10:35+01');
  perform pg_temp.comprobar('Sale Administración: aviso por correo encolado (una petición a enviar_correo)',
    r ->> 'aviso' = 'correo' and r ->> 'nueva_hora_salida' = '11:00'
    and (select count(*) from net.http_request_queue q, public.registro_eventos e
          where e.jornada_id = j2 and e.tipo = 'salida_retrasada' and q.url like '%/functions/v1/enviar_correo'
            and convert_from(q.body, 'UTF8')::jsonb = jsonb_build_object('tipo', 'retraso', 'ref', e.id::text)) = 1
    and exists (select 1 from public.registro_eventos where tipo = 'correo_encolado' and datos ->> 'tipo' = 'retraso'), r::text);
  perform pg_temp.comprobar('El retraso se ve en estado_actual',
    motor.estado_actual_de('2026-11-11 10:36+01') -> 'retrasos_salida' -> 0 ->> 'nueva_hora' = '11:00',
    (motor.estado_actual_de('2026-11-11 10:36+01') -> 'retrasos_salida')::text);
  update public.tareas set estado = 'hecha' where jornada_id = j2 and clave = 'bolsas';
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-11-11 10:50+01');
  perform pg_temp.comprobar('Con las bolsas ya listas no se retrasa: ESTADO_NO_VALIDO', r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);

  -- Del PR #3, sustituido en la Tarea 29d: el envío ya no descuenta el reparto de hoy y pegar_reparto se ha
  -- borrado (orden del propietario, 04/11/2026). servidor_preparar ya no da lo que solo usaba ella.
  r := public.servidor_preparar(op, '2026-11-11 11:30+01');
  perform pg_temp.comprobar('Tarea 29d: servidor_preparar ya no da reparto_hoy ni recuento_manana_hecho (pegar_reparto borrada)',
    not (r ? 'reparto_hoy') and not (r ? 'recuento_manana_hecho') and r ? 'almacen' and r ? 'comprometido', r::text);
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
