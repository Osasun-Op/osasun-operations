-- Tarea 4 · Problemas, incidencias, eventos y retraso de la salida (CONTRATOS.md §3.6, §3.7, §3.10)
-- Además: jornadas preparadas para otro día (sin arrastre hasta que llega el día)
-- y la cola de correos (avisos de retraso y cierres) hacia la función del
-- servidor enviar_correo, sin claves en la base de datos.

-- Jornadas ---------------------------------------------------------------------
-- generar_jornada: si la jornada se preparó antes de su día (tarea de
-- Administración para otro día), el arrastre se hace la primera vez que se
-- genera ese día.
create or replace function motor.generar_jornada(p_persona uuid, p_fecha date)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_centro uuid;
  v_envio_ayer boolean;
  v_arrastre_hecho boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('jornada:' || p_persona || ':' || p_fecha, 0));

  select envio_dia_siguiente into v_envio_ayer
    from public.jornadas where persona_id = p_persona and fecha = p_fecha - 1;

  select id, arrastre_hecho into v_id, v_arrastre_hecho
    from public.jornadas where persona_id = p_persona and fecha = p_fecha;
  if v_id is not null then
    if not v_arrastre_hecho then
      update public.jornadas
         set arrastre_hecho = true, hay_envio = hay_envio or coalesce(v_envio_ayer, false)
       where id = v_id;
      perform motor.registrar('jornada_generada', null, v_id, null, '{"preparada_antes": true}');
      perform motor.arrastrar(v_id);
      perform motor.generar_tareas(v_id);
    end if;
    return v_id;
  end if;

  select centro_id into v_centro from public.personas where id = p_persona and activo;
  if v_centro is null
     or not exists (select 1 from public.horarios
                    where persona_id = p_persona and dia_semana = extract(isodow from p_fecha)) then
    return null;
  end if;

  insert into public.jornadas (persona_id, centro_id, fecha, hay_envio)
  values (p_persona, v_centro, p_fecha,
          extract(isodow from p_fecha) = 1 or coalesce(v_envio_ayer, false))  -- el lunes siempre hay envío
  on conflict (persona_id, fecha) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.jornadas where persona_id = p_persona and fecha = p_fecha;
    return v_id;
  end if;

  perform motor.registrar('jornada_generada', null, v_id, null, '{}');
  perform motor.arrastrar(v_id);
  perform motor.generar_tareas(v_id);
  return v_id;
end;
$$;

-- Jornada de una persona para una fecha: la de hoy (o pasada) se genera; la de
-- un día futuro se prepara sin arrastrar nada todavía.
create or replace function motor.jornada_para(p_persona uuid, p_fecha date, p_ahora timestamptz)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_centro uuid;
begin
  if p_fecha <= motor.fecha_local(p_ahora) then
    return motor.generar_jornada(p_persona, p_fecha);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('jornada:' || p_persona || ':' || p_fecha, 0));
  select id into v_id from public.jornadas where persona_id = p_persona and fecha = p_fecha;
  if v_id is not null then
    return v_id;
  end if;
  select centro_id into v_centro from public.personas where id = p_persona and activo;
  if v_centro is null
     or not exists (select 1 from public.horarios
                    where persona_id = p_persona and dia_semana = extract(isodow from p_fecha)) then
    return null;
  end if;
  insert into public.jornadas (persona_id, centro_id, fecha, hay_envio, arrastre_hecho)
  values (p_persona, v_centro, p_fecha, extract(isodow from p_fecha) = 1, false)
  returning id into v_id;
  perform motor.registrar('jornada_preparada', null, v_id, null, '{}');
  perform motor.generar_tareas(v_id);
  return v_id;
end;
$$;

-- El operario del almacén (para quien van, por defecto, las tareas de Administración).
create or replace function motor.operario_por_defecto()
returns uuid
language sql stable
set search_path = ''
as $$
  select p.id from public.personas p join public.centros_trabajo c on c.id = p.centro_id
   where p.activo and p.rol = 'operario' and c.tipo = 'almacen'
   order by p.nombre, p.id limit 1;
$$;

-- Correo -----------------------------------------------------------------------
-- Pide a la función del servidor enviar_correo que envíe un aviso (retraso) o un
-- cierre. Va por pg_net, de forma asíncrona, con una solicitud interna de un solo
-- uso; si la transacción se deshace, no se envía nada.
create or replace function motor.encolar_correo(p_tipo text, p_ref text)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_url text := (select valor #>> '{}' from public.configuracion where clave = 'url_proyecto' and centro_id is null);
  v_admin uuid := (select id from public.personas where rol = 'administracion' and activo order by nombre, id limit 1);
  v_solicitud uuid;
begin
  if v_url is null or v_admin is null then
    perform motor.registrar('correo_no_enviado', null, null, null,
      jsonb_build_object('tipo', p_tipo, 'ref', p_ref, 'motivo', 'falta la dirección del proyecto o Administración'));
    return null;
  end if;
  insert into motor.solicitudes_servidor (persona_id, funcion) values (v_admin, 'enviar_correo') returning id into v_solicitud;
  perform motor.registrar('correo_encolado', null, null, null, jsonb_build_object('tipo', p_tipo, 'ref', p_ref));
  return net.http_post(
    url := v_url || '/functions/v1/enviar_correo',
    body := jsonb_build_object('tipo', p_tipo, 'ref', p_ref),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-solicitud', v_solicitud::text),
    timeout_milliseconds := 30000);
end;
$$;

-- Problemas (§6.6) ---------------------------------------------------------------
create or replace function motor.problema_json(p_problema uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object('id', p.id, 'tarea_id', p.tarea_id, 'tipo', p.tipo, 'descripcion', p.descripcion,
                            'estado', p.estado, 'abierto_en', p.abierto_en, 'llamadas', p.llamadas,
                            'whatsapp_en', p.whatsapp_en, 'proxima_llamada_en', p.proxima_llamada_en,
                            'solucion', p.solucion, 'resuelto_en', p.resuelto_en,
                            'minutos_hasta_solucion',
                              case when p.resuelto_en is null then null
                                   else round(extract(epoch from (p.resuelto_en - p.abierto_en)) / 60)::int end)
  from public.problemas p where p.id = p_problema;
$$;

create or replace function motor.abrir_problema_de(
  p_persona uuid, p_id_cliente uuid, p_tarea uuid, p_tipo text, p_descripcion text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  j public.jornadas;
  v_id uuid;
  v_abierto uuid;
begin
  select id into v_id from public.problemas where id_cliente = p_id_cliente and persona_id = p_persona;
  if v_id is not null then
    return jsonb_build_object('problema', motor.problema_json(v_id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if p_tipo is null or p_tipo not in ('falta_material', 'no_encuentro', 'no_se_hacerlo', 'no_funciona', 'otro') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige el tipo de problema.');
  end if;
  if nullif(btrim(p_descripcion), '') is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe en una línea cuál es el problema.');
  end if;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  select id into v_abierto from public.problemas where tarea_id = t.id and estado <> 'resuelto';
  if v_abierto is not null then
    return motor.error('PROBLEMA_YA_ABIERTO', 'Esta tarea ya tiene un problema abierto.',
                       jsonb_build_object('problema', motor.problema_json(v_abierto)));
  end if;
  if t.estado not in ('pendiente', 'en_curso', 'bloqueada') or j.fecha <> motor.fecha_local(p_ahora) then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea no está abierta hoy.', jsonb_build_object('estado', t.estado));
  end if;

  insert into public.problemas (jornada_id, tarea_id, persona_id, tipo, descripcion, abierto_en, id_cliente)
  values (j.id, t.id, p_persona, p_tipo, btrim(p_descripcion), p_ahora, p_id_cliente)
  returning id into v_id;
  update public.tareas set estado = 'bloqueada' where id = t.id;
  perform motor.registrar('problema_abierto', p_persona, j.id, t.id, jsonb_build_object('problema', v_id, 'tipo', p_tipo));
  return jsonb_build_object(
    'problema', motor.problema_json(v_id),
    'pasos', case when p_tipo = 'no_encuentro' then 'Llama a Administración ahora.'
                  else 'Si en 1 minuto no está resuelto, llama a Administración.' end,
    'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- Llamada a Administración: contestada (falta escribir la solución) o sin
-- respuesta (WhatsApp enviado; la tarea de volver a llamar aparece a los 30 min).
create or replace function motor.problema_llamada_de(p_persona uuid, p_problema uuid, p_contestada boolean, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  p public.problemas;
  v_min integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                             where clave = 'problema_minutos_reaparicion' and centro_id is null), 30);
  v_proxima timestamptz;
begin
  select * into p from public.problemas where id = p_problema;
  if p.id is null or p.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Ese problema no existe.');
  end if;
  if p.estado = 'resuelto' then
    return jsonb_build_object('problema', motor.problema_json(p.id), 'aviso',
                              jsonb_build_object('codigo', 'PROBLEMA_YA_RESUELTO', 'mensaje', 'Este problema ya está resuelto.'));
  end if;
  if p_contestada is null then
    return motor.error('DATOS_NO_VALIDOS', 'Indica si te han contestado.');
  end if;

  -- La tarea «Llama a Administración» pendiente de este problema queda hecha.
  update public.tareas set estado = 'hecha', terminada_en = p_ahora, iniciada_en = coalesce(iniciada_en, p_ahora)
   where jornada_id = p.jornada_id and clave like 'problema:' || p.id || ':%' and estado in ('pendiente', 'en_curso');

  if p_contestada then
    update public.problemas set llamada_en = p_ahora, llamadas = llamadas + 1, estado = 'abierto',
           proxima_llamada_en = null
     where id = p.id;
    perform motor.registrar('problema_llamada', p_persona, p.jornada_id, p.tarea_id,
                            jsonb_build_object('problema', p.id, 'contestada', true));
    return jsonb_build_object('problema', motor.problema_json(p.id),
                              'pasos', 'Escribe en una línea la solución acordada.',
                              'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;

  v_proxima := p_ahora + make_interval(mins => v_min);
  update public.problemas set llamada_en = p_ahora, llamadas = llamadas + 1, estado = 'sin_respuesta',
         whatsapp_en = p_ahora, proxima_llamada_en = v_proxima
   where id = p.id;
  insert into public.tareas (jornada_id, clave, origen, titulo, obligatoria, disponible_desde, hora_programada,
                             duracion_min, no_terminada, orden)
  values (p.jornada_id, 'problema:' || p.id || ':' || (p.llamadas + 1), 'problema',
          'Llama a Administración: ' || p.descripcion, true, v_proxima, v_proxima, 2, 'nada', 1)
  on conflict (jornada_id, clave) do nothing;
  perform motor.registrar('problema_llamada', p_persona, p.jornada_id, p.tarea_id,
                          jsonb_build_object('problema', p.id, 'contestada', false, 'proxima_llamada_en', v_proxima));
  return jsonb_build_object('problema', motor.problema_json(p.id),
                            'pasos', 'Envía un WhatsApp con el problema y sigue con otra tarea. En ' || v_min ||
                                     ' minutos te aparecerá la tarea de volver a llamar.',
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- Solución (obligatoria). La puede escribir el operario o Administración.
create or replace function motor.resolver_problema_de(p_persona uuid, p_problema uuid, p_solucion text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  p public.problemas;
  v_admin boolean := exists (select 1 from public.personas where id = p_persona and rol = 'administracion' and activo);
begin
  select * into p from public.problemas where id = p_problema;
  if p.id is null or (p.persona_id is distinct from p_persona and not v_admin) then
    return motor.error('NO_ENCONTRADO', 'Ese problema no existe.');
  end if;
  if p.estado = 'resuelto' then
    return jsonb_build_object('problema', motor.problema_json(p.id), 'aviso',
                              jsonb_build_object('codigo', 'PROBLEMA_YA_RESUELTO', 'mensaje', 'Este problema ya está resuelto.'));
  end if;
  if nullif(btrim(p_solucion), '') is null then
    return motor.error('SOLUCION_OBLIGATORIA', 'Escribe en una línea la solución acordada.');
  end if;

  update public.problemas set estado = 'resuelto', solucion = btrim(p_solucion), resuelto_en = p_ahora,
         resuelto_por = p_persona, proxima_llamada_en = null
   where id = p.id;
  update public.tareas set estado = 'cancelada', motivo_no_hecha = 'Ya no hace falta: problema resuelto'
   where jornada_id = p.jornada_id and clave like 'problema:' || p.id || ':%' and estado in ('pendiente', 'en_curso');
  update public.tareas set estado = 'pendiente'
   where id = p.tarea_id and estado = 'bloqueada'
     and not exists (select 1 from public.problemas o where o.tarea_id = p.tarea_id and o.estado <> 'resuelto');
  perform motor.registrar('problema_resuelto', p_persona, p.jornada_id, p.tarea_id,
                          jsonb_build_object('problema', p.id, 'por_administracion', v_admin,
                                             'minutos', round(extract(epoch from (p_ahora - p.abierto_en)) / 60)));
  return jsonb_build_object('problema', motor.problema_json(p.id),
                            'tarea_activa', case when v_admin then null else motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

-- Incidencias (§6.6) --------------------------------------------------------------
create or replace function motor.iniciar_incidencia_de(p_persona uuid, p_id_cliente uuid, p_descripcion text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_jornada uuid;
begin
  select id into v_id from public.incidencias where id_cliente = p_id_cliente and persona_id = p_persona;
  if v_id is not null then
    return jsonb_build_object('incidencia_id', v_id);
  end if;
  if nullif(btrim(p_descripcion), '') is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe en una línea qué es y por qué.');
  end if;
  select id into v_id from public.incidencias where persona_id = p_persona and terminada_en is null;
  if v_id is not null then
    return motor.error('INCIDENCIA_YA_ABIERTA', 'Ya tienes una incidencia abierta: termínala primero.',
                       jsonb_build_object('incidencia_id', v_id));
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;
  insert into public.incidencias (jornada_id, persona_id, tarea_id, descripcion, iniciada_en, id_cliente)
  values (v_jornada, p_persona,
          (select id from public.tareas where jornada_id = v_jornada and estado = 'en_curso'),
          btrim(p_descripcion), p_ahora, p_id_cliente)
  returning id into v_id;
  perform motor.registrar('incidencia_iniciada', p_persona, v_jornada, null, jsonb_build_object('incidencia', v_id));
  return jsonb_build_object('incidencia_id', v_id);
end;
$$;

create or replace function motor.terminar_incidencia_de(p_persona uuid, p_incidencia uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  i public.incidencias;
begin
  select * into i from public.incidencias where id = p_incidencia;
  if i.id is null or i.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa incidencia no existe.');
  end if;
  if i.terminada_en is null then
    update public.incidencias set terminada_en = p_ahora where id = i.id;
    perform motor.registrar('incidencia_terminada', p_persona, i.jornada_id, null,
                            jsonb_build_object('incidencia', i.id,
                                               'minutos', round(extract(epoch from (p_ahora - i.iniciada_en)) / 60)));
  end if;
  return jsonb_build_object('incidencia_id', i.id,
                            'minutos', (select round(extract(epoch from (terminada_en - iniciada_en)) / 60)::int
                                        from public.incidencias where id = i.id));
end;
$$;

-- Eventos: llega mercancía, pedido de cliente, no quedan vapers -------------------
-- El operario registra los tres; Administración puede registrar un pedido de
-- cliente, que va a la jornada de hoy del operario del almacén.
create or replace function motor.registrar_evento_de(
  p_persona uuid, p_id_cliente uuid, p_tipo text, p_detalle text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_operario uuid;
  v_jornada uuid;
  v_id uuid;
  v_tarea uuid;
begin
  select id, tarea_id into v_id, v_tarea from public.eventos_jornada where id_cliente = p_id_cliente and registrado_por = p_persona;
  if v_id is not null then
    return jsonb_build_object('evento_id', v_id, 'tarea', motor.tarea_json(v_tarea));
  end if;
  if p_tipo is null or p_tipo not in ('llega_mercancia', 'pedido_cliente', 'no_quedan_vapers') then
    return motor.error('DATOS_NO_VALIDOS', 'Tipo de aviso no válido.');
  end if;
  if v_rol = 'administracion' and p_tipo <> 'pedido_cliente' then
    return motor.error('NO_AUTORIZADO', 'Desde Administración solo se registran pedidos de cliente.');
  end if;
  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  v_jornada := motor.generar_jornada(v_operario, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no hay jornada en el almacén.');
  end if;

  insert into public.eventos_jornada (jornada_id, tipo, detalle, registrado_por, registrado_en, id_cliente)
  values (v_jornada, p_tipo, nullif(btrim(p_detalle), ''), p_persona, p_ahora, p_id_cliente)
  returning id into v_id;
  select id into v_tarea from motor.crear_tarea_condicionada(v_jornada, p_tipo, v_id::text) id limit 1;
  if v_tarea is not null and nullif(btrim(p_detalle), '') is not null then
    update public.tareas set porque = coalesce(porque, btrim(p_detalle)) where id = v_tarea;
  end if;
  update public.eventos_jornada set tarea_id = v_tarea where id = v_id;
  perform motor.registrar('evento_registrado', p_persona, v_jornada, v_tarea, jsonb_build_object('evento', v_id, 'tipo', p_tipo));
  return jsonb_build_object('evento_id', v_id, 'tarea', motor.tarea_json(v_tarea),
                            'tarea_activa', case when v_rol = 'operario' then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

-- Retraso de la salida (§4, 10:45) ------------------------------------------------
-- Mueve la hora de las bolsas (y de lo que va con la salida) 15 o 30 minutos,
-- lo registra y, si sale Administración, se le avisa por correo en el momento.
create or replace function motor.retrasar_salida_de(p_persona uuid, p_id_cliente uuid, p_minutos integer, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  j public.jornadas;
  v_jornada uuid;
  v_bolsas public.tareas;
  v_nueva timestamptz;
  v_evento bigint;
  v_previo jsonb;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;
  select * into j from public.jornadas where id = v_jornada;
  select datos into v_previo from public.registro_eventos
   where jornada_id = j.id and tipo = 'salida_retrasada' and datos ->> 'id_cliente' = p_id_cliente::text;
  if v_previo is not null then
    return jsonb_build_object('nueva_hora_salida', v_previo ->> 'nueva_hora', 'minutos', (v_previo ->> 'minutos')::int,
                              'aviso', v_previo ->> 'aviso', 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if p_minutos is null or p_minutos not in (15, 30) then
    return motor.error('DATOS_NO_VALIDOS', 'El retraso es de 15 o 30 minutos.');
  end if;
  select * into v_bolsas from public.tareas where jornada_id = j.id and clave = 'bolsas';
  if v_bolsas.id is null then
    return motor.error('SIN_TAREA', 'Todavía no hay bolsas: pega primero el reparto.');
  end if;
  if v_bolsas.estado not in ('pendiente', 'en_curso', 'bloqueada') then
    return motor.error('ESTADO_NO_VALIDO', 'Las bolsas ya están listas.', jsonb_build_object('estado', v_bolsas.estado));
  end if;

  v_nueva := coalesce(v_bolsas.hora_limite, motor.en_local(j.fecha, '10:45')) + make_interval(mins => p_minutos);
  update public.tareas set hora_limite = hora_limite + make_interval(mins => p_minutos)
   where jornada_id = j.id and clave in ('bolsas', 'produccion_reparto', 'preparar_envio_viernes')
     and estado in ('pendiente', 'en_curso', 'bloqueada') and hora_limite is not null;
  update public.tareas
     set hora_programada = hora_programada + make_interval(mins => p_minutos),
         disponible_desde = disponible_desde + make_interval(mins => p_minutos)
   where jornada_id = j.id and clave in ('salida_reparto', 'nacex_viernes') and estado = 'pendiente';

  insert into public.registro_eventos (tipo, persona_id, jornada_id, tarea_id, datos)
  values ('salida_retrasada', p_persona, j.id, v_bolsas.id,
          jsonb_build_object('minutos', p_minutos, 'nueva_hora', motor.hora_texto(v_nueva), 'sale', j.sale,
                             'id_cliente', p_id_cliente,
                             'aviso', case when j.sale = 'administracion' then 'correo' else 'sin_aviso' end))
  returning id into v_evento;
  if j.sale = 'administracion' then
    perform motor.encolar_correo('retraso', v_evento::text);
  end if;
  return jsonb_build_object('nueva_hora_salida', motor.hora_texto(v_nueva), 'minutos', p_minutos,
                            'aviso', case when j.sale = 'administracion' then 'correo' else 'sin_aviso' end,
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- API ---------------------------------------------------------------------------
create or replace function motor.api_abrir_problema(p_id_cliente uuid, p_tarea_id uuid, p_tipo text, p_descripcion text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.abrir_problema_de(auth.uid(), p_id_cliente, p_tarea_id, p_tipo, p_descripcion, now());
end; $$;

create or replace function motor.api_problema_llamada(p_problema_id uuid, p_contestada boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.problema_llamada_de(auth.uid(), p_problema_id, p_contestada, now());
end; $$;

create or replace function motor.api_resolver_problema(p_problema_id uuid, p_solucion text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.resolver_problema_de(auth.uid(), p_problema_id, p_solucion, now());
end; $$;

create or replace function motor.api_iniciar_incidencia(p_id_cliente uuid, p_descripcion text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.iniciar_incidencia_de(auth.uid(), p_id_cliente, p_descripcion, now());
end; $$;

create or replace function motor.api_terminar_incidencia(p_incidencia_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.terminar_incidencia_de(auth.uid(), p_incidencia_id, now());
end; $$;

create or replace function motor.api_registrar_evento(p_id_cliente uuid, p_tipo text, p_detalle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.registrar_evento_de(auth.uid(), p_id_cliente, p_tipo, p_detalle, now());
end; $$;

create or replace function motor.api_retrasar_salida(p_id_cliente uuid, p_minutos integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.retrasar_salida_de(auth.uid(), p_id_cliente, p_minutos, now());
end; $$;

create or replace function public.abrir_problema(id_cliente uuid, tarea_id uuid, tipo text, descripcion text)
returns jsonb language sql set search_path = '' as $$ select motor.api_abrir_problema(id_cliente, tarea_id, tipo, descripcion) $$;
create or replace function public.problema_llamada(problema_id uuid, contestada boolean)
returns jsonb language sql set search_path = '' as $$ select motor.api_problema_llamada(problema_id, contestada) $$;
create or replace function public.resolver_problema(problema_id uuid, solucion text)
returns jsonb language sql set search_path = '' as $$ select motor.api_resolver_problema(problema_id, solucion) $$;
create or replace function public.iniciar_incidencia(id_cliente uuid, descripcion text)
returns jsonb language sql set search_path = '' as $$ select motor.api_iniciar_incidencia(id_cliente, descripcion) $$;
create or replace function public.terminar_incidencia(incidencia_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_terminar_incidencia(incidencia_id) $$;
create or replace function public.registrar_evento(id_cliente uuid, tipo text, detalle text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_registrar_evento(id_cliente, tipo, detalle) $$;
create or replace function public.retrasar_salida(id_cliente uuid, minutos integer)
returns jsonb language sql set search_path = '' as $$ select motor.api_retrasar_salida(id_cliente, minutos) $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.es_admin(), motor.mi_centro(),
  motor.api_mi_perfil(), motor.api_tarea_activa(), motor.api_iniciar_tarea(uuid),
  motor.api_terminar_tarea(uuid, text, text), motor.api_anotar_motivo(uuid, text),
  motor.api_iniciar_elemento(uuid), motor.api_terminar_elemento(uuid), motor.api_marcar_cajas(uuid, integer),
  motor.api_abrir_problema(uuid, uuid, text, text), motor.api_problema_llamada(uuid, boolean),
  motor.api_resolver_problema(uuid, text), motor.api_iniciar_incidencia(uuid, text),
  motor.api_terminar_incidencia(uuid), motor.api_registrar_evento(uuid, text, text),
  motor.api_retrasar_salida(uuid, integer)
to authenticated;

revoke execute on function
  public.abrir_problema(uuid, uuid, text, text), public.problema_llamada(uuid, boolean),
  public.resolver_problema(uuid, text), public.iniciar_incidencia(uuid, text), public.terminar_incidencia(uuid),
  public.registrar_evento(uuid, text, text), public.retrasar_salida(uuid, integer)
from public, anon;
grant execute on function
  public.abrir_problema(uuid, uuid, text, text), public.problema_llamada(uuid, boolean),
  public.resolver_problema(uuid, text), public.iniciar_incidencia(uuid, text), public.terminar_incidencia(uuid),
  public.registrar_evento(uuid, text, text), public.retrasar_salida(uuid, integer)
to authenticated;
