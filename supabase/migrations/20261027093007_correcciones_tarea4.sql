-- Tarea 5 · Correcciones del PR #4 (comentario del coordinador):
-- 1. Solo hay conflicto si se sacrifica una obligatoria (§6.4) que vence dentro de
--    la ventana (las ya vencidas no cuentan). Si no cabe pero
--    no hay ninguna obligatoria en riesgo, la tarea se crea y se informa del encaje;
--    lo que no termine hoy se arrastra como cualquier tarea de Administración.
-- 2. Correo: si Resend lo rechaza (responde con un error), se reintenta solo,
--    hasta 3 intentos separados 5 minutos. Si la respuesta es dudosa (sin
--    respuesta a tiempo), no se reintenta. El fallo final se ve en estado_actual.
-- 3. Cierres sin correo para las personas indicadas en la configuración desde una
--    fecha (en pruebas, el operario ficticio a partir del 03/11/2026).

-- 1. Conflicto -----------------------------------------------------------------------
create or replace function motor.conflicto(p_jornada uuid, p_inicio timestamptz, p_fin timestamptz, p_nueva integer)
returns jsonb
language sql stable
set search_path = ''
as $$
  with j as (select * from public.jornadas where id = p_jornada),
  turnos as (
    select coalesce(sum(greatest(0, extract(epoch from (least(p_fin, motor.en_local(j.fecha, h.hora_fin))
                                                       - greatest(p_inicio, motor.en_local(j.fecha, h.hora_inicio)))) / 60)), 0) as m
      from j join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)),
  bloques as (
    select coalesce(sum(greatest(0, extract(epoch from (least(p_fin, t.hora_programada + make_interval(mins => t.duracion_min))
                                                       - greatest(p_inicio, t.hora_programada))) / 60)), 0) as m
      from public.tareas t
     where t.jornada_id = p_jornada and t.clave in ('salida_reparto', 'nacex_salida', 'nacex_viernes')
       and t.estado in ('pendiente', 'en_curso') and t.hora_programada is not null and t.duracion_min is not null),
  vencen as (
    select t.id, t.titulo, t.obligatoria, t.origen, coalesce(t.hora_limite, t.hora_programada) as vence,
           motor.duracion_estimada(t.id) as minutos
      from public.tareas t
     where t.jornada_id = p_jornada
       and t.estado in ('pendiente', 'en_curso', 'bloqueada')
       and (t.obligatoria or t.origen = 'administracion')
       and t.origen <> 'problema'
       and t.clave not in ('salida_reparto', 'nacex_salida', 'nacex_viernes')
       -- Solo las que vencen dentro de la ventana (las ya vencidas no se ponen en riesgo).
       and coalesce(t.hora_limite, t.hora_programada) > p_inicio
       and coalesce(t.hora_limite, t.hora_programada) <= p_fin),
  cuentas as (
    select round((select m from turnos) - (select m from bloques))::int as disponible,
           (coalesce((select sum(minutos) from vencen), 0) + p_nueva)::int as necesario),
  riesgo as (
    select coalesce(jsonb_agg(jsonb_build_object('tarea_id', v.id, 'titulo', v.titulo, 'vence', motor.hora_texto(v.vence),
                                                 'duracion_min', v.minutos, 'origen', v.origen) order by v.vence, v.titulo),
                    '[]'::jsonb) as lista
      from vencen v where v.obligatoria and v.minutos > 0)
  select jsonb_build_object(
    -- Conflicto solo si no cabe y hay obligatorias que se sacrificarían.
    'hay_conflicto', c.necesario > c.disponible and jsonb_array_length(r.lista) > 0,
    'disponible_min', c.disponible,
    'necesario_min', c.necesario,
    'minutos_que_faltan', greatest(c.necesario - c.disponible, 0),
    'obligatorias_en_riesgo', case when c.necesario > c.disponible then r.lista else '[]'::jsonb end)
  from cuentas c, riesgo r;
$$;

create or replace function motor.crear_tarea_admin_de(
  p_admin uuid, p_id_cliente uuid, p_que text, p_para_quien uuid, p_cuando jsonb, p_duracion_min integer,
  p_urgente boolean, p_porque text, p_confirmar boolean, p_decision jsonb, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_tipo text := p_cuando ->> 'tipo';
  v_fecha date;
  v_hora time;
  v_persona uuid := coalesce(p_para_quien, motor.operario_por_defecto());
  v_jornada uuid;
  v_inicio timestamptz;
  v_fin timestamptz;
  v_limite timestamptz;
  v_conflicto jsonb;
  v_faltan integer;
  v_accion text := p_decision ->> 'accion';
  v_cede public.tareas;
  v_id uuid;
  v_previo jsonb;
  v_encaje text;
begin
  if p_id_cliente is null then
    return motor.error('DATOS_NO_VALIDOS', 'Falta el identificador de la petición.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('admin:' || p_id_cliente, 0));
  select id into v_id from public.tareas where id_cliente = p_id_cliente;
  if v_id is not null then
    return jsonb_build_object('tarea_id', v_id, 'tarea', motor.tarea_json(v_id), 'ya_creada', true, 'conflicto', null);
  end if;
  select datos into v_previo from public.registro_eventos
   where tipo = 'conflicto_decidido' and datos ->> 'id_cliente' = p_id_cliente::text and datos ->> 'accion' = 'no_crear';
  if v_previo is not null then
    return jsonb_build_object('tarea_id', null, 'creada', false, 'decision', 'no_crear', 'conflicto', v_previo -> 'conflicto');
  end if;

  -- Datos
  if nullif(btrim(p_que), '') is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe qué hay que hacer.');
  end if;
  if p_duracion_min is null or p_duracion_min <= 0 or p_duracion_min > 600 then
    return motor.error('DATOS_NO_VALIDOS', 'Pon una duración orientativa en minutos.');
  end if;
  if v_tipo is null or v_tipo not in ('hoy', 'dia', 'antes_de') then
    return motor.error('DATOS_NO_VALIDOS', 'Indica cuándo: hoy, un día o antes de una hora.');
  end if;
  begin
    v_fecha := case when v_tipo = 'hoy' then v_hoy else (p_cuando ->> 'fecha')::date end;
    v_hora := case when v_tipo = 'antes_de' then (p_cuando ->> 'hora')::time end;
  exception when others then
    return motor.error('DATOS_NO_VALIDOS', 'La fecha o la hora no son válidas.');
  end;
  if v_fecha is null or (v_tipo = 'antes_de' and v_hora is null) then
    return motor.error('DATOS_NO_VALIDOS', 'Falta la fecha o la hora.');
  end if;
  if not exists (select 1 from public.personas where id = v_persona and activo and rol = 'operario') then
    return motor.error('NO_ENCONTRADO', 'Esa persona no existe.');
  end if;
  if v_fecha < v_hoy then
    return motor.error('FECHA_PASADA', 'Esa fecha ya ha pasado.');
  end if;
  if v_hora is not null then
    v_limite := motor.en_local(v_fecha, v_hora);
    if v_limite <= p_ahora then
      return motor.error('FECHA_PASADA', 'Esa hora ya ha pasado.');
    end if;
  end if;

  -- Ventana: desde ahora (o el inicio del día) hasta la hora límite (o el final del turno).
  v_jornada := motor.jornada_para(v_persona, v_fecha, p_ahora);
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Ese día no trabaja.');
  end if;
  v_inicio := greatest(case when v_fecha = v_hoy then p_ahora end, motor.inicio_turno(v_persona, v_fecha, null));
  v_fin := coalesce(v_limite,
                    (select motor.en_local(v_fecha, h.hora_fin) from public.horarios h
                      where h.persona_id = v_persona and h.dia_semana = extract(isodow from v_fecha)
                        and motor.en_local(v_fecha, h.hora_fin) > v_inicio
                      order by h.hora_inicio limit 1));
  if v_fin is null then
    return motor.error('FECHA_PASADA', 'Hoy ya ha terminado su jornada: elige otro día.');
  end if;
  v_conflicto := motor.conflicto(v_jornada, v_inicio, greatest(v_fin, v_inicio), p_duracion_min);
  v_faltan := (v_conflicto ->> 'minutos_que_faltan')::int;
  v_encaje := case
    when coalesce(p_urgente, false) then 'Urgente: entra en cuanto termine lo que está haciendo (la referencia o la tienda en curso).'
    when v_limite is not null then 'Antes de las ' || motor.hora_texto(v_limite) || ', después de lo que tiene hora.'
    else 'Cuando termine las obligatorias y lo que tiene hora.' end
    || case when v_fecha <> v_hoy then ' El ' || to_char(v_fecha, 'DD/MM') || '.' else '' end
    -- Sin obligatorias en riesgo se crea igualmente; se avisa de lo que no le da tiempo.
    || case when not (v_conflicto ->> 'hay_conflicto')::boolean and v_faltan > 0
            then ' No le da tiempo entera (faltan unos ' || v_faltan || ' min): lo que no termine pasa al día siguiente.'
            else '' end;

  if not (v_conflicto ->> 'hay_conflicto')::boolean then
    v_conflicto := null;
  elsif v_accion is null or v_accion not in ('no_crear', 'despues', 'manana', 'cancelar') then
    return motor.error('CONFLICTO', 'No cabe: decide qué cede o no la crees.', jsonb_build_object('conflicto', v_conflicto));
  elsif v_accion <> 'no_crear' then
    begin
      select * into v_cede from public.tareas where id = (p_decision ->> 'cede')::uuid;
    exception when others then
      v_cede := null;
    end;
    if v_cede.id is null or v_cede.jornada_id <> v_jornada or v_cede.estado not in ('pendiente', 'en_curso', 'bloqueada') then
      return motor.error('DATOS_NO_VALIDOS', 'Elige una de las tareas en riesgo para que ceda.',
                         jsonb_build_object('conflicto', v_conflicto));
    end if;
  end if;

  if not coalesce(p_confirmar, false) then
    return jsonb_build_object('tarea_id', null, 'comprobado', true, 'encaje', v_encaje, 'conflicto', v_conflicto,
                              'minutos_que_faltan', v_faltan);
  end if;

  if v_accion = 'no_crear' and v_conflicto is not null then
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, null,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', 'no_crear', 'que', btrim(p_que), 'conflicto', v_conflicto));
    return jsonb_build_object('tarea_id', null, 'creada', false, 'decision', 'no_crear', 'conflicto', v_conflicto);
  end if;

  insert into public.tareas (jornada_id, clave, origen, titulo, porque, obligatoria, disponible_desde, hora_limite,
                             urgente, duracion_min, no_terminada, orden, creada_por, id_cliente)
  values (v_jornada, 'admin:' || p_id_cliente, 'administracion', btrim(p_que), nullif(btrim(p_porque), ''), false,
          case when v_fecha = v_hoy then p_ahora else motor.inicio_turno(v_persona, v_fecha, null) end, v_limite,
          coalesce(p_urgente, false), p_duracion_min, 'arrastrar', 50, p_admin, p_id_cliente)
  returning id into v_id;
  perform motor.registrar('tarea_creada', p_admin, v_jornada, v_id,
    jsonb_build_object('origen', 'administracion', 'urgente', coalesce(p_urgente, false), 'duracion_min', p_duracion_min,
                       'conflicto', v_conflicto is not null, 'minutos_que_faltan', v_faltan));

  if v_conflicto is not null then
    if v_accion = 'despues' then
      update public.tareas set hora_limite = null,
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: se hace después'
       where id = v_cede.id;
    elsif v_accion = 'manana' then
      update public.tareas set no_terminada = 'arrastrar', estado = case when estado = 'en_curso' then 'pendiente' else estado end,
             disponible_desde = motor.en_local(v_fecha + 1, '00:00'),
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: pasa al día siguiente'
       where id = v_cede.id;
    else
      update public.tareas set estado = 'cancelada',
             motivo_no_hecha = 'Cede ante «' || btrim(p_que) || '»: cancelada por Administración'
       where id = v_cede.id;
    end if;
    perform motor.registrar('conflicto_decidido', p_admin, v_jornada, v_cede.id,
      jsonb_build_object('id_cliente', p_id_cliente, 'accion', v_accion, 'cede', v_cede.id, 'cede_titulo', v_cede.titulo,
                         'nueva', v_id, 'conflicto', v_conflicto));
  end if;

  return jsonb_build_object('tarea_id', v_id, 'tarea', motor.tarea_json(v_id), 'encaje', v_encaje,
                            'conflicto', v_conflicto, 'minutos_que_faltan', v_faltan,
                            'decision', case when v_conflicto is not null then
                                          jsonb_build_object('cede', v_cede.id, 'titulo', v_cede.titulo, 'accion', v_accion) end);
end;
$$;

-- 2. Correos con reintento -------------------------------------------------------------
-- Un correo por cierre o aviso. estado: pendiente → enviando → enviado; si Resend
-- lo rechaza: reintentar (5 min) → … → fallido al tercer intento; sin respuesta: dudoso.
create table motor.correos (
  id                  bigint generated always as identity primary key,
  tipo                text not null check (tipo in ('cierre', 'retraso')),
  ref                 text not null,
  estado              text not null default 'pendiente'
                        check (estado in ('pendiente', 'enviando', 'reintentar', 'enviado', 'fallido', 'dudoso')),
  intentos            integer not null default 0,
  proximo_intento_en  timestamptz,
  asunto              text,
  ultimo_error        text,
  creado_en           timestamptz not null default now(),
  enviado_en          timestamptz,
  unique (tipo, ref)
);
alter table motor.correos enable row level security;
create policy nadie on motor.correos for all to authenticated, anon using (false) with check (false);
revoke all on motor.correos from anon, authenticated;

insert into public.configuracion (clave, centro_id, valor) values
  ('correo_max_intentos', null, '3'),
  ('correo_minutos_reintento', null, '5');

-- Llama a enviar_correo para un correo concreto (con una solicitud de un solo uso).
create or replace function motor.pedir_envio(p_correo bigint)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  c motor.correos;
  v_url text := (select valor #>> '{}' from public.configuracion where clave = 'url_proyecto' and centro_id is null);
  v_admin uuid := (select id from public.personas where rol = 'administracion' and activo order by nombre, id limit 1);
  v_solicitud uuid;
begin
  select * into c from motor.correos where id = p_correo;
  if v_url is null or v_admin is null then
    update motor.correos set estado = 'fallido', ultimo_error = 'Falta la dirección del proyecto o Administración'
     where id = c.id;
    perform motor.registrar('correo_no_enviado', null, null, null,
      jsonb_build_object('tipo', c.tipo, 'ref', c.ref, 'motivo', 'falta la dirección del proyecto o Administración'));
    return null;
  end if;
  insert into motor.solicitudes_servidor (persona_id, funcion) values (v_admin, 'enviar_correo') returning id into v_solicitud;
  return net.http_post(
    url := v_url || '/functions/v1/enviar_correo',
    body := jsonb_build_object('tipo', c.tipo, 'ref', c.ref),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-solicitud', v_solicitud::text),
    timeout_milliseconds := 30000);
end;
$$;

-- Crea el correo (una sola vez por cierre o aviso) y pide enviarlo.
create or replace function motor.encolar_correo(p_tipo text, p_ref text)
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_id bigint;
begin
  insert into motor.correos (tipo, ref) values (p_tipo, p_ref)
  on conflict (tipo, ref) do nothing
  returning id into v_id;
  if v_id is null then
    return null;  -- ya estaba: nunca dos correos
  end if;
  perform motor.registrar('correo_encolado', null, null, null, jsonb_build_object('tipo', p_tipo, 'ref', p_ref));
  return motor.pedir_envio(v_id);
end;
$$;

-- Tarea programada cada minuto: vuelve a pedir los correos rechazados cuya espera ha pasado.
create or replace function motor.reintentar_correos(p_ahora timestamptz)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  c motor.correos;
  n integer := 0;
begin
  for c in
    select * from motor.correos
     where estado = 'reintentar' and proximo_intento_en <= p_ahora
     order by id
     for update skip locked
  loop
    update motor.correos set estado = 'pendiente' where id = c.id;
    perform motor.registrar('correo_reintento', null, null, null,
                            jsonb_build_object('tipo', c.tipo, 'ref', c.ref, 'intento', c.intentos + 1));
    perform motor.pedir_envio(c.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

select cron.schedule('reintentar_correos', '* * * * *', $$select motor.reintentar_correos(now())$$);

-- Reclamar: solo un correo pendiente se puede enviar, y solo una vez por intento.
create or replace function public.servidor_correo_reclamar(p_tipo text, p_ref text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_destino text := (select valor #>> '{}' from public.configuracion where clave = 'correo_administracion' and centro_id is null);
  v_remitente text := (select valor #>> '{}' from public.configuracion where clave = 'correo_remitente' and centro_id is null);
  m motor.correos;
  c public.cierres;
  r public.registro_eventos;
  v_texto jsonb;
begin
  if v_destino is null then
    return motor.error('SIN_DESTINO', 'Falta el correo de Administración en la configuración.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('correo:' || p_tipo || ':' || p_ref, 0));
  select * into m from motor.correos where tipo = p_tipo and ref = p_ref for update;
  if m.id is null then
    return jsonb_build_object('enviar', false, 'motivo', 'no_encolado');
  end if;
  if m.estado <> 'pendiente' then
    return jsonb_build_object('enviar', false, 'motivo', 'ya_reclamado');
  end if;

  if p_tipo = 'cierre' then
    select * into c from public.cierres where id = p_ref::uuid;
    if c.id is null then
      return motor.error('NO_ENCONTRADO', 'Ese cierre no existe.');
    end if;
    v_texto := motor.texto_cierre(c.contenido);
    update public.cierres set envio_reclamado_en = coalesce(envio_reclamado_en, now()) where id = c.id;
  elsif p_tipo = 'retraso' then
    select * into r from public.registro_eventos where id = p_ref::bigint and tipo = 'salida_retrasada';
    if r.id is null then
      return motor.error('NO_ENCONTRADO', 'Ese aviso no existe.');
    end if;
    v_texto := jsonb_build_object(
      'asunto', 'Salida retrasada a las ' || (r.datos ->> 'nueva_hora'),
      'texto', 'El operario ha retrasado la salida del reparto ' || (r.datos ->> 'minutos') || ' minutos.' || E'\n'
               || 'Nueva hora de salida: ' || (r.datos ->> 'nueva_hora') || '.' || E'\n'
               || 'Aviso enviado a las ' || motor.hora_texto((r.datos ->> 'a_las')::timestamptz) || '.');
  else
    return motor.error('DATOS_NO_VALIDOS', 'Tipo de correo no válido.');
  end if;

  update motor.correos set estado = 'enviando', intentos = intentos + 1, asunto = v_texto ->> 'asunto',
         proximo_intento_en = null
   where id = m.id;
  perform motor.registrar('correo_reclamado', null, coalesce(c.jornada_id, r.jornada_id), null,
                          jsonb_build_object('tipo', p_tipo, 'ref', p_ref, 'intento', m.intentos + 1));
  return jsonb_build_object('enviar', true, 'destino', v_destino, 'remitente', v_remitente,
                            'asunto', v_texto ->> 'asunto', 'texto', v_texto ->> 'texto');
end;
$$;

-- Respuesta de Resend: enviado, rechazado (respondió con un error: se reintenta)
-- o dudoso (no respondió a tiempo: no se reintenta, para no enviar dos veces).
create or replace function public.servidor_correo_respuesta(p_tipo text, p_ref text, p_estado text, p_detalle text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  m motor.correos;
  v_max integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                             where clave = 'correo_max_intentos' and centro_id is null), 3);
  v_min integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                             where clave = 'correo_minutos_reintento' and centro_id is null), 5);
  v_nuevo text;
  v_jornada uuid;
begin
  if p_estado is null or p_estado not in ('enviado', 'rechazado', 'dudoso') then
    return motor.error('DATOS_NO_VALIDOS', 'Estado de envío no válido.');
  end if;
  select * into m from motor.correos where tipo = p_tipo and ref = p_ref for update;
  if m.id is null or m.estado <> 'enviando' then
    return jsonb_build_object('ok', false, 'motivo', 'no_estaba_enviando');
  end if;
  v_nuevo := case p_estado
               when 'enviado' then 'enviado'
               when 'dudoso' then 'dudoso'
               else case when m.intentos < v_max then 'reintentar' else 'fallido' end end;
  update motor.correos
     set estado = v_nuevo,
         enviado_en = case when v_nuevo = 'enviado' then now() end,
         ultimo_error = case when v_nuevo = 'enviado' then null else left(p_detalle, 500) end,
         proximo_intento_en = case when v_nuevo = 'reintentar' then now() + make_interval(mins => v_min) end
   where id = m.id;

  if p_tipo = 'cierre' then
    update public.cierres
       set enviado_en = case when v_nuevo = 'enviado' then now() end,
           canal = case when v_nuevo = 'enviado' then 'correo' end,
           error_envio = case when v_nuevo = 'enviado' then null else left(p_detalle, 500) end
     where id = p_ref::uuid
    returning jornada_id into v_jornada;
  else
    select jornada_id into v_jornada from public.registro_eventos where id = p_ref::bigint;
  end if;
  perform motor.registrar(case v_nuevo when 'enviado' then 'correo_enviado' when 'reintentar' then 'correo_rechazado'
                                       when 'dudoso' then 'correo_dudoso' else 'correo_fallido' end,
                          null, v_jornada, null,
                          jsonb_build_object('tipo', p_tipo, 'ref', p_ref, 'intento', m.intentos, 'detalle', left(p_detalle, 500)));
  return jsonb_build_object('ok', true, 'estado', v_nuevo);
end;
$$;

-- La de la Tarea 4 se conserva por compatibilidad: ok → enviado; si no, rechazado.
create or replace function public.servidor_correo_resultado(p_tipo text, p_ref text, p_ok boolean, p_detalle text)
returns jsonb
language sql security definer
set search_path = ''
as $$ select public.servidor_correo_respuesta(p_tipo, p_ref, case when p_ok then 'enviado' else 'rechazado' end, p_detalle) $$;

revoke execute on function public.servidor_correo_reclamar(text, text), public.servidor_correo_resultado(text, text, boolean, text),
  public.servidor_correo_respuesta(text, text, text, text) from public, anon, authenticated;
grant execute on function public.servidor_correo_reclamar(text, text), public.servidor_correo_resultado(text, text, boolean, text),
  public.servidor_correo_respuesta(text, text, text, text) to service_role;

-- 3. Cierres sin correo para algunas personas desde una fecha (configuración del entorno:
--    cierres_sin_correo = [{"persona": "<uuid>", "desde": "AAAA-MM-DD"}]).
create or replace function motor.generar_cierre(p_jornada uuid, p_turno text, p_ahora timestamptz)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_ultimo boolean;
  j public.jornadas;
begin
  perform pg_advisory_xact_lock(hashtextextended('cierre:' || p_jornada || ':' || p_turno, 0));
  select id into v_id from public.cierres where jornada_id = p_jornada and turno = p_turno;
  if v_id is not null then
    return v_id;
  end if;
  insert into public.cierres (jornada_id, turno, contenido, generado_en)
  values (p_jornada, p_turno, motor.contenido_cierre(p_jornada, p_turno, p_ahora), p_ahora)
  returning id into v_id;

  select * into j from public.jornadas where id = p_jornada;
  v_ultimo := p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                          and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio desc limit 1);
  if v_ultimo then
    update public.jornadas set estado = 'cerrada' where id = p_jornada;
  end if;
  perform motor.registrar('cierre_generado', null, p_jornada, null, jsonb_build_object('cierre', v_id, 'turno', p_turno));
  if exists (select 1 from public.configuracion k, jsonb_array_elements(k.valor) x
              where k.clave = 'cierres_sin_correo' and k.centro_id is null and jsonb_typeof(k.valor) = 'array'
                and x ->> 'persona' = j.persona_id::text and j.fecha >= (x ->> 'desde')::date) then
    perform motor.registrar('correo_no_enviado', null, p_jornada, null,
                            jsonb_build_object('tipo', 'cierre', 'ref', v_id, 'motivo', 'cierre sin correo para esta persona'));
  else
    perform motor.encolar_correo('cierre', v_id::text);
  end if;
  return v_id;
end;
$$;

-- estado_actual: además, los correos que no se han podido enviar (últimos 7 días).
create or replace function motor.estado_actual_de(p_ahora timestamptz)
returns jsonb
language sql stable
set search_path = ''
as $$
  with op as (select id, nombre from public.personas where id = motor.operario_por_defecto()),
  j as (select jo.* from public.jornadas jo join op on op.id = jo.persona_id where jo.fecha = motor.fecha_local(p_ahora))
  select jsonb_build_object(
    'ahora', motor.hora_texto(p_ahora),
    'fecha', motor.fecha_local(p_ahora),
    'operario', (select jsonb_build_object('id', op.id, 'nombre', op.nombre) from op),
    'jornada', (select jsonb_build_object('id', j.id, 'sale', j.sale, 'hay_envio', j.hay_envio, 'estado', j.estado) from j),
    'en_curso', (select motor.tarea_json(t.id) from public.tareas t join j on j.id = t.jornada_id where t.estado = 'en_curso'),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.estado <> 'resuelto' and p.persona_id = (select id from op)), '[]'::jsonb),
    'incidencia_en_curso', (
      select jsonb_build_object('id', i.id, 'descripcion', i.descripcion, 'desde', motor.hora_texto(i.iniciada_en),
                                'minutos', round(extract(epoch from (p_ahora - i.iniciada_en)) / 60)::int)
        from public.incidencias i where i.persona_id = (select id from op) and i.terminada_en is null),
    'arrastradas', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado) order by t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id where t.tarea_origen_id is not null), '[]'::jsonb),
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado, 'origen', t.origen,
                                          'obligatoria', t.obligatoria, 'urgente', t.urgente,
                                          'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)),
                                          'motivo', t.motivo_no_hecha)
                       order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id
       where not t.retirada_por_condicion and t.origen <> 'problema'), '[]'::jsonb),
    'retrasos_salida', coalesce((
      select jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                          'minutos', (r.datos ->> 'minutos')::int, 'nueva_hora', r.datos ->> 'nueva_hora',
                                          'sale', r.datos ->> 'sale', 'aviso', r.datos ->> 'aviso') order by r.id)
        from public.registro_eventos r join j on j.id = r.jornada_id where r.tipo = 'salida_retrasada'), '[]'::jsonb),
    'correos_no_enviados', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'asunto', m.asunto, 'estado', m.estado, 'intentos', m.intentos,
                                          'error', m.ultimo_error, 'creado_en', m.creado_en) order by m.id desc)
        from motor.correos m
       where m.estado in ('fallido', 'dudoso') and m.creado_en >= p_ahora - interval '7 days'), '[]'::jsonb),
    'lectura_sheets', jsonb_build_object(
      'ultima_correcta', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo)
                            from public.lecturas_sheets l where l.correcto order by l.leido_en desc limit 1),
      'ultimo_error', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo, 'error', l.error)
                         from public.lecturas_sheets l where not l.correcto
                          and l.leido_en > coalesce((select max(k.leido_en) from public.lecturas_sheets k where k.correcto), '-infinity')
                         order by l.leido_en desc limit 1)));
$$;

revoke execute on all functions in schema motor from public;
