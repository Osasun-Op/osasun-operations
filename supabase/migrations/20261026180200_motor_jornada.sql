-- Tarea 2 · Motor de la jornada (lógica interna, esquema motor)
-- Generación diaria idempotente, tareas condicionadas, arrastres y elección de
-- la tarea activa (PLAN_TECNICO.md §2). Todas las funciones reciben la hora
-- («p_ahora») como parámetro para poder probarlas con días y horas simulados;
-- las funciones públicas pasan siempre now().
-- Estas funciones no se conceden a ningún usuario: solo las usan las funciones
-- de la API (motor.api_*), las tareas programadas y las pruebas.

-- Hora local (Madrid) -------------------------------------------------------
create or replace function motor.en_local(p_fecha date, p_hora time)
returns timestamptz
language sql immutable
set search_path = ''
as $$ select (p_fecha + p_hora) at time zone 'Europe/Madrid' $$;

create or replace function motor.fecha_local(p_momento timestamptz)
returns date
language sql immutable
set search_path = ''
as $$ select (p_momento at time zone 'Europe/Madrid')::date $$;

create or replace function motor.hora_texto(p_momento timestamptz)
returns text
language sql immutable
set search_path = ''
as $$ select to_char(p_momento at time zone 'Europe/Madrid', 'HH24:MI') $$;

-- Respuesta de error común (CONTRATOS.md §1) -------------------------------
create or replace function motor.error(p_codigo text, p_mensaje text, p_extra jsonb default '{}')
returns jsonb
language sql immutable
set search_path = ''
as $$
  select jsonb_build_object('error',
    jsonb_build_object('codigo', p_codigo, 'mensaje', p_mensaje) || coalesce(p_extra, '{}'::jsonb));
$$;

-- Registro de eventos -------------------------------------------------------
create or replace function motor.registrar(
  p_tipo text, p_persona uuid, p_jornada uuid, p_tarea uuid, p_datos jsonb default '{}')
returns void
language sql
set search_path = ''
as $$
  insert into public.registro_eventos (tipo, persona_id, jornada_id, tarea_id, datos)
  values (p_tipo, p_persona, p_jornada, p_tarea, coalesce(p_datos, '{}'::jsonb));
$$;

-- Inicio de un turno (o del primer turno del día si p_turno es nulo) ---------
create or replace function motor.inicio_turno(p_persona uuid, p_fecha date, p_turno text)
returns timestamptz
language sql stable
set search_path = ''
as $$
  select motor.en_local(p_fecha, h.hora_inicio)
  from public.horarios h
  where h.persona_id = p_persona
    and h.dia_semana = extract(isodow from p_fecha)
    and (p_turno is null or h.turno = p_turno)
  order by h.hora_inicio
  limit 1;
$$;

-- ¿Se cumple la condición de una plantilla con lo que ya se sabe del día?
-- true/false para condiciones de estado de la jornada; null para las que
-- dependen de algo que pasa durante el día (reparto, envío, eventos).
create or replace function motor.condicion_estado(p_jornada public.jornadas, p_condicion text)
returns boolean
language sql immutable
set search_path = ''
as $$
  select case when p_condicion is null then true else case p_condicion
    when 'sale_operario' then coalesce(p_jornada.sale = 'operario', false)
    when 'sale_administracion' then coalesce(p_jornada.sale = 'administracion', false)
    when 'hay_envio' then p_jornada.hay_envio
    when 'no_hay_envio' then not p_jornada.hay_envio
    else null
  end end;
$$;

create or replace function motor.texto_condicion(p_condicion text)
returns text
language sql immutable
set search_path = ''
as $$
  select case p_condicion
    when 'sale_operario' then 'hoy no sale el operario'
    when 'sale_administracion' then 'hoy no sale Administración'
    when 'hay_envio' then 'hoy no hay envío'
    when 'no_hay_envio' then 'hoy hay envío'
    else p_condicion
  end;
$$;

-- Crea una tarea a partir de una plantilla (idempotente por clave) ----------
create or replace function motor.insertar_desde_plantilla(
  p_jornada uuid, p_plantilla uuid, p_clave text, p_origen text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.tareas (
    jornada_id, clave, origen, plantilla_id, titulo, porque, contenido, obligatoria,
    prioridad_cola, condicion, requiere_clave, disponible_desde, hora_programada,
    hora_limite, duracion_min, no_terminada, orden)
  select
    j.id, p_clave, p_origen, p.id, p.titulo, p.porque, p.contenido, p.obligatoria,
    p.prioridad_cola, p.condicion, p.requiere_codigo,
    coalesce(motor.en_local(j.fecha, p.hora_inicio),
             motor.inicio_turno(j.persona_id, j.fecha, p.turno),
             motor.inicio_turno(j.persona_id, j.fecha, null)),
    motor.en_local(j.fecha, p.hora_inicio),
    motor.en_local(j.fecha, p.hora_limite),
    p.duracion_min, p.no_terminada, p.orden
  from public.jornadas j, public.plantillas_tarea p
  where j.id = p_jornada and p.id = p_plantilla
  on conflict (jornada_id, clave) do nothing
  returning id into v_id;

  if v_id is not null then
    perform motor.registrar('tarea_creada', null, p_jornada, v_id,
                            jsonb_build_object('clave', p_clave, 'origen', p_origen));
  end if;
  return v_id;
end;
$$;

-- Aplica las plantillas del día según lo que se sabe de la jornada ----------
-- Crea las que tocan; retira (cancela, con motivo) las pendientes cuya
-- condición ha dejado de cumplirse; recupera las retiradas si vuelve a cumplirse.
create or replace function motor.generar_tareas(p_jornada uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  j public.jornadas;
  p public.plantillas_tarea;
  v_cumple boolean;
  v_id uuid;
begin
  select * into j from public.jornadas where id = p_jornada;
  for p in
    select * from public.plantillas_tarea
    where centro_id = j.centro_id and activa
      and extract(isodow from j.fecha)::smallint = any (dias_semana)
    order by orden, codigo
  loop
    v_cumple := motor.condicion_estado(j, p.condicion);
    if v_cumple is null then
      continue;  -- se crea cuando pase (motor.crear_tarea_condicionada)
    elsif v_cumple then
      perform motor.insertar_desde_plantilla(j.id, p.id, p.codigo, 'plantilla');
      for v_id in
        update public.tareas
           set estado = 'pendiente', retirada_por_condicion = false, motivo_no_hecha = null
         where jornada_id = j.id and clave = p.codigo
           and retirada_por_condicion and estado = 'cancelada'
        returning id
      loop
        perform motor.registrar('tarea_recuperada', null, j.id, v_id, '{}');
      end loop;
    else
      for v_id in
        update public.tareas
           set estado = 'cancelada', retirada_por_condicion = true,
               motivo_no_hecha = 'Ya no aplica: ' || motor.texto_condicion(p.condicion)
         where jornada_id = j.id and clave = p.codigo and estado = 'pendiente'
        returning id
      loop
        perform motor.registrar('tarea_retirada', null, j.id, v_id,
                                jsonb_build_object('condicion', p.condicion));
      end loop;
    end if;
  end loop;
end;
$$;

-- Tareas que nacen de algo que pasa durante el día --------------------------
-- (reparto o envío aceptado, llega mercancía, pedido de cliente, no quedan vapers).
-- p_sufijo distingue varias del mismo tipo en un día (ej. dos pedidos).
create or replace function motor.crear_tarea_condicionada(p_jornada uuid, p_condicion text, p_sufijo text default null)
returns setof uuid
language plpgsql
set search_path = ''
as $$
declare
  j public.jornadas;
  p public.plantillas_tarea;
  v_clave text;
begin
  select * into j from public.jornadas where id = p_jornada;
  if not found then
    return;
  end if;
  for p in
    select * from public.plantillas_tarea
    where centro_id = j.centro_id and activa and condicion = p_condicion
      and extract(isodow from j.fecha)::smallint = any (dias_semana)
    order by orden, codigo
  loop
    v_clave := p.codigo || coalesce(':' || p_sufijo, '');
    perform motor.insertar_desde_plantilla(
      j.id, p.id, v_clave,
      case when p_condicion in ('reparto_pegado', 'envio_pegado') then 'reparto' else 'evento' end);
    return query select t.id from public.tareas t where t.jornada_id = j.id and t.clave = v_clave;
  end loop;
end;
$$;

-- Quién sale hoy (línea SALE: del reparto) ----------------------------------
create or replace function motor.fijar_sale(p_jornada uuid, p_sale text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.jornadas set sale = p_sale where id = p_jornada and sale is distinct from p_sale;
  if found then
    perform motor.registrar('sale_fijado', null, p_jornada, null, jsonb_build_object('sale', p_sale));
    perform motor.generar_tareas(p_jornada);
  end if;
end;
$$;

-- Envío a Gipuzkoa/Durango: hoy y, el jueves, el del viernes por la mañana ---
create or replace function motor.fijar_envio(p_jornada uuid, p_hay_envio boolean, p_envio_dia_siguiente boolean default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.jornadas
     set hay_envio = coalesce(p_hay_envio, hay_envio),
         envio_dia_siguiente = coalesce(p_envio_dia_siguiente, envio_dia_siguiente)
   where id = p_jornada
     and (hay_envio is distinct from coalesce(p_hay_envio, hay_envio)
          or envio_dia_siguiente is distinct from coalesce(p_envio_dia_siguiente, envio_dia_siguiente));
  if found then
    perform motor.registrar('envio_fijado', null, p_jornada, null,
      jsonb_build_object('hay_envio', p_hay_envio, 'envio_dia_siguiente', p_envio_dia_siguiente));
    perform motor.generar_tareas(p_jornada);
  end if;
end;
$$;

-- Arrastres (ESTADO_DEL_SISTEMA.md §6.5) ------------------------------------
-- Lo no terminado de la jornada anterior con política «arrastrar» o
-- «sigue_abierta» pasa a la nueva como copia; la original queda «arrastrada».
-- «recalcular» (stock) y «nada» (ligadas a hora o turno) no pasan: constan en
-- el cierre de su día.
create or replace function motor.arrastrar(p_jornada uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  j public.jornadas;
  v_anterior uuid;
  t public.tareas;
  v_id uuid;
begin
  select * into j from public.jornadas where id = p_jornada;
  select id into v_anterior from public.jornadas
   where persona_id = j.persona_id and fecha < j.fecha
   order by fecha desc limit 1;
  if v_anterior is null then
    return;
  end if;

  for t in
    select * from public.tareas
    where jornada_id = v_anterior
      and estado in ('pendiente', 'en_curso', 'bloqueada')
      and no_terminada in ('arrastrar', 'sigue_abierta')
    order by orden, creada_en
  loop
    insert into public.tareas (
      jornada_id, clave, origen, plantilla_id, titulo, porque, contenido, obligatoria,
      prioridad_cola, disponible_desde, urgente, duracion_min, no_terminada, orden,
      tarea_origen_id, creada_por)
    values (
      j.id, 'arrastre:' || t.id, t.origen, t.plantilla_id, t.titulo, t.porque, t.contenido, t.obligatoria,
      t.prioridad_cola, motor.inicio_turno(j.persona_id, j.fecha, null), t.urgente, t.duracion_min,
      t.no_terminada, t.orden, t.id, t.creada_por)
    on conflict (jornada_id, clave) do nothing
    returning id into v_id;

    update public.tareas set estado = 'arrastrada' where id = t.id;
    perform motor.registrar('tarea_arrastrada', null, j.id, coalesce(v_id, t.id),
                            jsonb_build_object('desde', t.id));
  end loop;
end;
$$;

-- Generación de la jornada (idempotente) ------------------------------------
-- Devuelve la jornada de esa persona y fecha; la crea si no existe y la persona
-- trabaja ese día. Un candado por persona y fecha hace que dos llamadas a la vez
-- esperen una a la otra; la restricción única (persona, fecha) es la última garantía.
create or replace function motor.generar_jornada(p_persona uuid, p_fecha date)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_centro uuid;
  v_envio_ayer boolean;
begin
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

  select envio_dia_siguiente into v_envio_ayer
    from public.jornadas where persona_id = p_persona and fecha = p_fecha - 1;

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

-- Generación programada: todas las personas activas, a las 06:00 de Madrid --
-- La tarea programada se lanza a las 04:00 y 05:00 UTC; solo actúa la que cae
-- a las 06:00 en Madrid (horario de verano o de invierno).
create or replace function motor.generar_jornadas_programadas(p_ahora timestamptz default now())
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_persona uuid;
  v_n integer := 0;
begin
  if extract(hour from (p_ahora at time zone 'Europe/Madrid')) <> 6 then
    return 0;
  end if;
  for v_persona in select id from public.personas where activo and centro_id is not null loop
    if motor.generar_jornada(v_persona, motor.fecha_local(p_ahora)) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end;
$$;

-- Qué tarea toca ahora (PLAN_TECNICO.md §2.3) -------------------------------
-- Escalones: 1 en curso · 2 llamar por un problema · 3 urgente de Administración ·
-- 4 con hora ya vencida · 5 obligatorias y de Administración con hora límite
-- (por hora límite; empate, la obligatoria) · 6 de Administración sin hora ·
-- 7 flexibles · 8 cola de tiempo libre (A, C, D).
create or replace function motor.escalon(t public.tareas)
returns integer
language sql immutable
set search_path = ''
as $$
  select case
    when t.estado = 'en_curso' then 1
    when t.origen = 'problema' then 2
    when t.origen = 'administracion' and t.urgente then 3
    when t.hora_programada is not null then 4
    when t.obligatoria or (t.origen = 'administracion' and t.hora_limite is not null) then 5
    when t.origen = 'administracion' then 6
    when t.prioridad_cola is null then 7
    else 8
  end;
$$;

create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid
language sql stable
set search_path = ''
as $$
  select t.id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and (t.estado = 'en_curso'
         or (t.estado = 'pendiente'
             and t.disponible_desde <= p_ahora
             and (t.requiere_clave is null
                  or exists (select 1 from public.tareas r
                             where r.jornada_id = t.jornada_id
                               and r.clave = t.requiere_clave and r.estado = 'hecha'))))
  order by motor.escalon(t),
           case t.prioridad_cola when 'A' then 1 when 'C' then 2 when 'D' then 3 end nulls first,
           t.hora_programada nulls last,
           t.hora_limite nulls last,
           t.obligatoria desc,
           t.orden,
           t.creada_en,
           t.id
  limit 1;
$$;

create or replace function motor.tarea_json(p_tarea uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque,
    'estado', t.estado, 'origen', t.origen, 'obligatoria', t.obligatoria,
    'urgente', t.urgente, 'contenido', t.contenido,
    'hora_programada', t.hora_programada, 'hora_limite', t.hora_limite,
    'duracion_min', t.duracion_min, 'arrastrada_de', t.tarea_origen_id,
    'iniciada_en', t.iniciada_en, 'terminada_en', t.terminada_en,
    'elementos', '[]'::jsonb)
  from public.tareas t where t.id = p_tarea;
$$;

create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_jornada uuid;
  j public.jornadas;
  v_tarea uuid;
  v_sig uuid;
  s public.tareas;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return jsonb_build_object('jornada', null, 'pregunta', null, 'tarea', null, 'siguiente', null);
  end if;
  select * into j from public.jornadas where id = v_jornada;

  v_tarea := motor.elegir_tarea(v_jornada, p_ahora, null);
  v_sig := motor.elegir_tarea(v_jornada, p_ahora, v_tarea);
  if v_sig is null then
    select t.id into v_sig from public.tareas t
     where t.jornada_id = v_jornada and t.estado = 'pendiente'
       and t.disponible_desde > p_ahora and t.id is distinct from v_tarea
     order by t.disponible_desde, t.orden limit 1;
  end if;
  select * into s from public.tareas where id = v_sig;

  return jsonb_build_object(
    'jornada', jsonb_build_object('id', j.id, 'fecha', j.fecha, 'sale', j.sale, 'hay_envio', j.hay_envio),
    'pregunta', null,
    'tarea', motor.tarea_json(v_tarea),
    'siguiente', case when v_sig is null then null else
      s.titulo || coalesce(' · ' || motor.hora_texto(coalesce(s.hora_programada,
                    case when s.disponible_desde > p_ahora then s.disponible_desde end)), '') end);
end;
$$;

-- Acciones sobre una tarea --------------------------------------------------
create or replace function motor.iniciar_tarea_de(p_persona uuid, p_tarea uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  j public.jornadas;
  v_otra uuid;
begin
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado = 'en_curso' then
    return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if t.estado <> 'pendiente' or j.fecha <> motor.fecha_local(p_ahora) then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea no se puede empezar ahora.', jsonb_build_object('estado', t.estado));
  end if;

  select id into v_otra from public.tareas where jornada_id = j.id and estado = 'en_curso';
  if v_otra is not null then
    return motor.error('OTRA_TAREA_EN_CURSO', 'Termina primero la tarea que tienes en curso.',
                       jsonb_build_object('tarea_en_curso', motor.tarea_json(v_otra)));
  end if;

  begin
    update public.tareas
       set estado = 'en_curso', iniciada_en = coalesce(iniciada_en, p_ahora)
     where id = t.id and estado = 'pendiente';
  exception when unique_violation then
    return motor.error('OTRA_TAREA_EN_CURSO', 'Termina primero la tarea que tienes en curso.');
  end;
  perform motor.registrar('tarea_iniciada', p_persona, j.id, t.id, jsonb_build_object('a_las', p_ahora));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.terminar_tarea_de(
  p_persona uuid, p_tarea uuid, p_resultado text, p_motivo text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  j public.jornadas;
begin
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado = 'hecha' then
    return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if t.estado <> 'en_curso' then
    return motor.error('ESTADO_NO_VALIDO', 'Solo se puede terminar una tarea en curso.', jsonb_build_object('estado', t.estado));
  end if;

  update public.tareas
     set estado = 'hecha', terminada_en = p_ahora,
         resultado = nullif(btrim(p_resultado), ''),
         motivo_no_hecha = coalesce(nullif(btrim(p_motivo), ''), motivo_no_hecha)
   where id = t.id and estado = 'en_curso';
  perform motor.registrar('tarea_terminada', p_persona, j.id, t.id,
                          jsonb_build_object('a_las', p_ahora, 'resultado', p_resultado));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.anotar_motivo_de(p_persona uuid, p_tarea uuid, p_motivo text)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  j public.jornadas;
begin
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if nullif(btrim(p_motivo), '') is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el motivo.');
  end if;
  if t.estado not in ('pendiente', 'en_curso', 'bloqueada') then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea ya está cerrada.', jsonb_build_object('estado', t.estado));
  end if;

  update public.tareas set motivo_no_hecha = btrim(p_motivo) where id = t.id;
  perform motor.registrar('motivo_anotado', p_persona, j.id, t.id, jsonb_build_object('motivo', btrim(p_motivo)));
  return jsonb_build_object('tarea', motor.tarea_json(t.id));
end;
$$;

create or replace function motor.mi_perfil_de(p_persona uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p.id, 'nombre', p.nombre, 'rol', p.rol,
    'centro', case when c.id is null then null else jsonb_build_object('id', c.id, 'nombre', c.nombre) end,
    'telefono_administracion', (select a.telefono from public.personas a
                                where a.rol = 'administracion' and a.activo and a.telefono is not null
                                order by a.nombre limit 1))
  from public.personas p
  left join public.centros_trabajo c on c.id = p.centro_id
  where p.id = p_persona;
$$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.es_admin(), motor.mi_centro() to authenticated;
