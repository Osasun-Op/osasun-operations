-- Tarea 7 · Incidencias, reparto y «nunca sin tarea» (ESTADO_DEL_SISTEMA.md v1.17:
-- §4 «Nunca sin tarea», §5 R1 y §6.6 «Incidencias»). Va después de
-- 20261027120000_incidencias_estructura.sql.
--
-- 1. Reparto: Administración también puede pegarlo (va a la jornada del operario
--    por defecto); «Pega el reparto» se cierra sola al aceptarse un reparto y,
--    sin reparto, terminarla exige motivo; tarea_activa dice si ya hay reparto.
-- 2. Nunca sin tarea: si no queda nada disponible, se adelantan las fijas de la
--    tarde de ese día y, después, «Orden y limpieza», que no se gasta.
-- 3. Incidencias con opción, quién e importancia, sobre la tabla `incidencias`
--    de siempre: si la resuelve él, se convierte en tarea y se cierra sola al
--    hacerla (salvo las compras, que esperan a que llegue); si la resuelve
--    Administración, le llega un correo y espera a que él la cierre. «Estoy
--    bloqueado» es el flujo de problemas de siempre.
-- 4. tarea_activa devuelve también las incidencias abiertas, la incidencia en
--    curso y los problemas abiertos, para que nada se olvide al recargar.

-- ---------------------------------------------------------------------------
-- Estructura: la incidencia de siempre, con su opción, quién, importancia y estado
-- ---------------------------------------------------------------------------
alter table public.incidencias
  add column opcion text check (opcion in ('llega_mercancia', 'pedido_cliente', 'pedir_comprar', 'recogida_nacex', 'corregir')),
  add column quien text check (quien in ('operario', 'administracion')),
  add column importancia text check (importancia in ('ahora', 'hoy', 'cuando_pueda')),
  add column estado text not null default 'abierta'
    check (estado in ('abierta', 'esperando_llegada', 'esperando_administracion', 'cerrada')),
  add column tarea_resolucion_id uuid references public.tareas (id) on delete set null,
  add column nota_cierre text,
  add column cerrada_por uuid references public.personas (id);

comment on column public.incidencias.opcion is 'Qué pasa (§6.6). Vacía en las incidencias de antes de la v1.17 (solo miden su tiempo).';
comment on column public.incidencias.tarea_id is 'Tarea que estaba en curso al abrirla.';
comment on column public.incidencias.tarea_resolucion_id is 'Tarea creada para resolverla (si la resuelve el operario).';
comment on column public.incidencias.terminada_en is 'Cuándo se cerró.';

update public.incidencias set estado = 'cerrada' where terminada_en is not null;

create index incidencias_persona_id_idx on public.incidencias (persona_id);
create index incidencias_tarea_resolucion_id_idx on public.incidencias (tarea_resolucion_id);
create index incidencias_cerrada_por_idx on public.incidencias (cerrada_por);

-- ---------------------------------------------------------------------------
-- Textos y forma de una incidencia
-- ---------------------------------------------------------------------------
create or replace function motor.texto_opcion(p_opcion text)
returns text language sql immutable set search_path = '' as $$
  select case p_opcion
    when 'llega_mercancia' then 'Llega mercancía'
    when 'pedido_cliente' then 'Pedido de cliente'
    when 'pedir_comprar' then 'Hay que pedir o comprar algo'
    when 'recogida_nacex' then 'Recogida en Nacex'
    when 'corregir' then 'Corregir, limpiar o solucionar algo'
    when 'bloqueado' then 'Estoy bloqueado'
    else 'Incidencia' end;
$$;

-- minutos: de inicio a fin de su tarea; sin tarea (la resuelve Administración, o
-- las de antes de la v1.17), desde que se abre hasta que se cierra.
create or replace function motor.incidencia_json(p_incidencia uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', i.id, 'opcion', i.opcion, 'opcion_texto', motor.texto_opcion(i.opcion),
    'descripcion', i.descripcion, 'quien', i.quien, 'importancia', i.importancia,
    'estado', i.estado,
    'estado_texto', case
      when i.estado = 'cerrada' then 'Cerrada a las ' || motor.hora_texto(i.terminada_en)
      when i.estado = 'esperando_llegada' then 'Pedido, esperando a que llegue'
      when i.estado = 'esperando_administracion' then 'Esperando a Administración'
      when t.id is null then 'En curso desde las ' || motor.hora_texto(i.iniciada_en)
      when t.estado = 'en_curso' then 'En curso desde las ' || motor.hora_texto(t.iniciada_en)
      when t.estado = 'bloqueada' then 'Bloqueada por un problema'
      when t.estado = 'cancelada' then 'Su tarea se ha cancelado: ciérrala si ya está resuelta'
      when i.importancia = 'ahora' then 'Va ahora, al terminar lo que tienes entre manos'
      when i.importancia = 'hoy' then 'Pendiente para hoy'
      else 'En tu cola de tiempo libre' end,
    'abierta_en', i.iniciada_en, 'desde', motor.hora_texto(i.iniciada_en), 'fecha', motor.fecha_local(i.iniciada_en),
    'cerrada_en', i.terminada_en, 'nota', i.nota_cierre, 'tarea_id', i.tarea_resolucion_id,
    'minutos', round(extract(epoch from case
        when t.iniciada_en is not null then coalesce(t.terminada_en, p_ahora) - t.iniciada_en
        when t.id is not null then null
        else coalesce(i.terminada_en, p_ahora) - i.iniciada_en end) / 60)::int)
  from public.incidencias i
  left join public.tareas t on t.id = i.tarea_resolucion_id
  where i.id = p_incidencia;
$$;

-- Lo que el operario no puede perder al recargar (tarea_activa).
create or replace function motor.seguimiento_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'incidencias_abiertas', (select count(*) from public.incidencias i
                              where i.persona_id = p_persona and i.estado <> 'cerrada')::int,
    'incidencia_en_curso', (
      select motor.incidencia_json(i.id, p_ahora)
        from public.incidencias i left join public.tareas t on t.id = i.tarea_resolucion_id
       where i.persona_id = p_persona and i.estado = 'abierta' and (t.estado = 'en_curso' or i.opcion is null)
       order by i.iniciada_en desc limit 1),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.persona_id = p_persona and p.estado <> 'resuelto'), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- Nunca sin tarea (§4): 1) lo disponible, como siempre (sin «Orden y limpieza»);
-- 2) dentro del turno, las fijas de la tarde de ese día; 3) «Orden y limpieza».
-- Lo que va ligado a su hora (recuento, revisión del envío, Nacex, salida) no se adelanta.
-- ---------------------------------------------------------------------------
create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
  v_id uuid;
begin
  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and (t.estado = 'en_curso'
         or (t.estado = 'pendiente'
             and t.disponible_desde <= p_ahora
             and t.prioridad_cola is distinct from 'D'
             and (t.requiere_clave is null
                  or exists (select 1 from public.tareas r
                             where r.jornada_id = t.jornada_id
                               and r.clave = t.requiere_clave and r.estado = 'hecha'))))
  order by motor.escalon(t),
           case when motor.escalon(t) = 3 then t.creada_en end,
           case t.prioridad_cola when 'A' then 1 when 'C' then 2 when 'D' then 3 end nulls first,
           t.hora_programada nulls last,
           t.hora_limite nulls last,
           t.obligatoria desc,
           t.orden,
           t.creada_en,
           t.id
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  -- Solo dentro de su turno: entre turnos no se le ofrece nada.
  select * into j from public.jornadas where id = p_jornada;
  if not exists (select 1 from public.horarios h
                  where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                    and p_ahora >= motor.en_local(j.fecha, h.hora_inicio)
                    and p_ahora < motor.en_local(j.fecha, h.hora_fin)) then
    return null;
  end if;

  select t.id into v_id
  from public.tareas t
  join public.plantillas_tarea p on p.id = t.plantilla_id
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and p.programacion = 'dia_semana' and p.turno = 'tarde' and p.hora_inicio is null
    and t.requiere_clave is null
  order by t.hora_limite nulls last, t.orden, t.creada_en, t.id
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and t.prioridad_cola = 'D' and t.disponible_desde <= p_ahora
  order by t.orden, t.creada_en, t.id
  limit 1;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Al hacerse una tarea: se cierra su incidencia (las compras pasan a «pedido,
-- esperando a que llegue») y «Orden y limpieza» vuelve a estar disponible.
-- ---------------------------------------------------------------------------
create or replace function motor.tras_tarea_hecha()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_persona uuid := (select persona_id from public.jornadas where id = new.jornada_id);
  v_cuando timestamptz := coalesce(new.terminada_en, now());
  i public.incidencias;
  p public.plantillas_tarea;
begin
  for i in
    update public.incidencias
       set estado = case when opcion = 'pedir_comprar' then 'esperando_llegada' else 'cerrada' end,
           terminada_en = case when opcion = 'pedir_comprar' then null else v_cuando end,
           cerrada_por = case when opcion = 'pedir_comprar' then null else v_persona end
     where tarea_resolucion_id = new.id and estado = 'abierta'
    returning *
  loop
    perform motor.registrar(case when i.estado = 'cerrada' then 'incidencia_cerrada' else 'incidencia_pedida' end,
                            v_persona, new.jornada_id, new.id,
                            jsonb_build_object('incidencia', i.id, 'por', 'tarea hecha', 'a_las', v_cuando));
  end loop;

  if new.prioridad_cola = 'D' and new.plantilla_id is not null then
    select * into p from public.plantillas_tarea where id = new.plantilla_id;
    perform motor.insertar_desde_plantilla(new.jornada_id, p.id, p.codigo || ':' || new.id, 'plantilla');
  end if;
  return null;
end;
$$;

create trigger tareas_tras_hecha
  after update of estado on public.tareas
  for each row when (new.estado = 'hecha' and old.estado is distinct from 'hecha')
  execute function motor.tras_tarea_hecha();

-- Lo no terminado que pasa al día siguiente sigue resolviendo su incidencia.
create or replace function motor.arrastrar(p_jornada uuid)
returns void language plpgsql set search_path = '' as $$
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
    if v_id is not null then
      update public.incidencias set tarea_resolucion_id = v_id where tarea_resolucion_id = t.id;
    end if;
    perform motor.registrar('tarea_arrastrada', null, j.id, coalesce(v_id, t.id),
                            jsonb_build_object('desde', t.id));
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Incidencias (§6.6)
-- ---------------------------------------------------------------------------
create or replace function motor.crear_incidencia_de(
  p_persona uuid, p_id_cliente uuid, p_opcion text, p_descripcion text, p_quien text, p_importancia text,
  p_tarea uuid, p_tipo_problema text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_desc text := nullif(btrim(regexp_replace(coalesce(p_descripcion, ''), '\s+', ' ', 'g')), '');
  v_quien text := coalesce(p_quien, 'operario');
  v_imp text := coalesce(p_importancia, case when p_opcion in ('llega_mercancia', 'corregir') then 'ahora' else 'hoy' end);
  v_jornada uuid;
  v_id uuid;
  v_tarea uuid;
  v_evento jsonb;
begin
  select id into v_id from public.incidencias where id_cliente = p_id_cliente and persona_id = p_persona;
  if v_id is not null then
    return jsonb_build_object('incidencia', motor.incidencia_json(v_id, p_ahora),
                              'tarea', motor.tarea_json((select tarea_resolucion_id from public.incidencias where id = v_id)),
                              'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if p_opcion is null
     or p_opcion not in ('llega_mercancia', 'pedido_cliente', 'pedir_comprar', 'recogida_nacex', 'corregir', 'bloqueado') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige qué pasa.');
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;

  -- «Estoy bloqueado»: el flujo de problemas, sobre la tarea en curso (o la que le toca).
  if p_opcion = 'bloqueado' then
    v_tarea := coalesce(p_tarea,
                        (select id from public.tareas where jornada_id = v_jornada and estado = 'en_curso'),
                        motor.elegir_tarea(v_jornada, p_ahora, null));
    if v_tarea is null then
      return motor.error('SIN_TAREA', 'No tienes ninguna tarea abierta que se haya bloqueado.');
    end if;
    v_evento := motor.abrir_problema_de(p_persona, p_id_cliente, v_tarea, coalesce(p_tipo_problema, 'otro'), v_desc, p_ahora);
    return case when v_evento ? 'error' then v_evento else jsonb_build_object('incidencia', null) || v_evento end;
  end if;

  if v_desc is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe en una línea qué pasa.');
  end if;
  if v_quien not in ('operario', 'administracion') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige quién la resuelve.');
  end if;
  if v_imp not in ('ahora', 'hoy', 'cuando_pueda') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige la importancia.');
  end if;

  v_id := gen_random_uuid();
  if v_quien = 'operario' then
    -- Llega mercancía y pedido de cliente: la tarea de siempre (registrar_evento).
    if p_opcion in ('llega_mercancia', 'pedido_cliente') then
      v_evento := motor.registrar_evento_de(p_persona, p_id_cliente, p_opcion, v_desc, p_ahora);
      if v_evento ? 'error' then
        return v_evento;
      end if;
      v_tarea := (v_evento -> 'tarea' ->> 'id')::uuid;
    end if;
    if v_tarea is null then
      insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, no_terminada, orden, creada_por)
      values (v_jornada, 'incidencia:' || v_id, 'evento',
              case p_opcion when 'pedir_comprar' then 'Pedir o comprar: '
                            when 'recogida_nacex' then 'Recogida en Nacex: '
                            when 'llega_mercancia' then 'Llega mercancía: '
                            when 'pedido_cliente' then 'Pedido de cliente: '
                            else 'Corregir: ' end || v_desc,
              p_ahora, 'arrastrar', 35, p_persona)
      returning id into v_tarea;
      perform motor.registrar('tarea_creada', p_persona, v_jornada, v_tarea,
                              jsonb_build_object('clave', 'incidencia:' || v_id, 'origen', 'evento'));
    end if;
    -- Ahora: como las urgentes. Hoy: obligatoria del día. Cuando pueda: cola de tiempo libre.
    update public.tareas
       set urgente = v_imp = 'ahora',
           obligatoria = v_imp <> 'cuando_pueda',
           prioridad_cola = case when v_imp = 'cuando_pueda' then 'C' end,
           no_terminada = case when v_imp = 'cuando_pueda' then 'sigue_abierta' else 'arrastrar' end
     where id = v_tarea;
  end if;

  insert into public.incidencias (id, jornada_id, persona_id, tarea_id, descripcion, iniciada_en, id_cliente,
                                  opcion, quien, importancia, estado, tarea_resolucion_id)
  values (v_id, v_jornada, p_persona,
          (select id from public.tareas where jornada_id = v_jornada and estado = 'en_curso'),
          v_desc, p_ahora, p_id_cliente, p_opcion, v_quien, v_imp,
          case when v_quien = 'administracion' then 'esperando_administracion' else 'abierta' end, v_tarea);
  perform motor.registrar('incidencia_creada', p_persona, v_jornada, v_tarea,
                          jsonb_build_object('incidencia', v_id, 'opcion', p_opcion, 'quien', v_quien, 'importancia', v_imp));
  if v_quien = 'administracion' then
    perform motor.encolar_correo('incidencia', v_id::text);
  end if;

  return jsonb_build_object('incidencia', motor.incidencia_json(v_id, p_ahora),
                            'tarea', motor.tarea_json(v_tarea),
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.cerrar_incidencia_de(p_persona uuid, p_incidencia uuid, p_nota text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
  t public.tareas;
begin
  select * into i from public.incidencias where id = p_incidencia for update;
  if i.id is null or i.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa incidencia no existe.');
  end if;
  if i.estado = 'cerrada' then
    return jsonb_build_object('incidencia', motor.incidencia_json(i.id, p_ahora),
                              'aviso', jsonb_build_object('codigo', 'INCIDENCIA_YA_CERRADA', 'mensaje', 'Esta incidencia ya estaba cerrada.'),
                              'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;

  -- Su tarea, si sigue abierta, ya no hace falta.
  select * into t from public.tareas where id = i.tarea_resolucion_id;
  if t.estado in ('pendiente', 'en_curso', 'bloqueada') then
    perform motor.cancelar_tarea_de(p_persona, t.id, 'Ya no hace falta: incidencia cerrada', p_ahora);
    update public.tareas set terminada_en = p_ahora where id = t.id and iniciada_en is not null and terminada_en is null;
  end if;

  update public.incidencias
     set estado = 'cerrada', terminada_en = p_ahora, cerrada_por = p_persona,
         nota_cierre = nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '')
   where id = i.id;
  perform motor.registrar('incidencia_cerrada', p_persona, i.jornada_id, i.tarea_resolucion_id,
                          jsonb_build_object('incidencia', i.id, 'por', 'a mano', 'a_las', p_ahora));
  return jsonb_build_object('incidencia', motor.incidencia_json(i.id, p_ahora),
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.incidencias_abiertas_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'total', count(*)::int,
    'incidencias', coalesce(jsonb_agg(motor.incidencia_json(i.id, p_ahora) order by i.iniciada_en), '[]'::jsonb))
  from public.incidencias i
  where i.persona_id = p_persona and i.estado <> 'cerrada';
$$;

-- Las de antes (iniciar_incidencia / terminar_incidencia) siguen funcionando:
-- una sola a la vez, midiendo su tiempo.
create or replace function motor.iniciar_incidencia_de(p_persona uuid, p_id_cliente uuid, p_descripcion text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
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
  select id into v_id from public.incidencias where persona_id = p_persona and opcion is null and estado <> 'cerrada';
  if v_id is not null then
    return motor.error('INCIDENCIA_YA_ABIERTA', 'Ya tienes una incidencia abierta: termínala primero.',
                       jsonb_build_object('incidencia_id', v_id, 'incidencia', motor.incidencia_json(v_id, p_ahora)));
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
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
begin
  select * into i from public.incidencias where id = p_incidencia;
  if i.id is null or i.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa incidencia no existe.');
  end if;
  if i.opcion is not null then
    return motor.cerrar_incidencia_de(p_persona, i.id, null, p_ahora);
  end if;
  if i.terminada_en is null then
    update public.incidencias set terminada_en = p_ahora, estado = 'cerrada', cerrada_por = p_persona where id = i.id;
    perform motor.registrar('incidencia_terminada', p_persona, i.jornada_id, null,
                            jsonb_build_object('incidencia', i.id,
                                               'minutos', round(extract(epoch from (p_ahora - i.iniciada_en)) / 60)));
  end if;
  return jsonb_build_object('incidencia_id', i.id,
                            'minutos', (select round(extract(epoch from (terminada_en - iniciada_en)) / 60)::int
                                        from public.incidencias where id = i.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- tarea_activa: reparto de hoy, incidencias y problemas abiertos
-- ---------------------------------------------------------------------------
create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_jornada uuid;
  j public.jornadas;
  v_tarea uuid;
  v_sig uuid;
  v_prox uuid;
  s public.tareas;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return jsonb_build_object('jornada', null, 'pregunta', null, 'tarea', null, 'siguiente', null, 'reparto_de_hoy', null)
           || motor.seguimiento_de(p_persona, p_ahora);
  end if;
  select * into j from public.jornadas where id = v_jornada;

  v_tarea := motor.elegir_tarea(v_jornada, p_ahora, null);
  -- «Lo que viene después»: lo que tocaría sin la tarea actual; pero si antes
  -- llega una tarea con hora (o el siguiente turno), se muestra esa.
  v_sig := motor.elegir_tarea(v_jornada, p_ahora, v_tarea);
  select t.id into v_prox from public.tareas t
   where t.jornada_id = v_jornada and t.estado = 'pendiente'
     and t.disponible_desde > p_ahora and t.id is distinct from v_tarea
   order by t.disponible_desde, t.orden limit 1;
  if v_prox is not null
     and (v_sig is null
          or (select motor.escalon(t) > 4 from public.tareas t where t.id = v_sig)) then
    v_sig := v_prox;
  end if;
  select * into s from public.tareas where id = v_sig;

  return jsonb_build_object(
    'jornada', jsonb_build_object('id', j.id, 'fecha', j.fecha, 'sale', j.sale, 'hay_envio', j.hay_envio),
    'pregunta', null,
    'tarea', motor.tarea_json(v_tarea),
    'siguiente', case when v_sig is null then null else
      s.titulo || coalesce(' · ' || motor.hora_texto(coalesce(s.hora_programada,
                    case when s.disponible_desde > p_ahora then s.disponible_desde end)), '') end,
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre)
        from public.repartos r left join public.personas pe on pe.id = r.pegado_por
       where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'))
    || motor.seguimiento_de(p_persona, p_ahora);
end;
$$;

-- «Pega el reparto» sin reparto aceptado: solo con motivo.
create or replace function motor.terminar_tarea_de(p_persona uuid, p_tarea uuid, p_resultado text, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  t public.tareas;
  j public.jornadas;
  v_pendientes integer;
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
  select count(*) into v_pendientes from public.tarea_elementos where tarea_id = t.id and estado <> 'hecho';
  if v_pendientes > 0 and nullif(btrim(p_motivo), '') is null then
    return motor.error('ELEMENTOS_PENDIENTES', 'Quedan ' || v_pendientes || ' sin hacer. Escribe el motivo para terminarla así.',
                       jsonb_build_object('pendientes', v_pendientes));
  end if;
  if t.clave = 'pegar_reparto' and nullif(btrim(p_motivo), '') is null
     and not exists (select 1 from public.repartos r where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado') then
    return motor.error('MOTIVO_OBLIGATORIO', 'Todavía no hay reparto pegado. Pégalo, o escribe el motivo para terminarla así.');
  end if;

  update public.tareas
     set estado = 'hecha', terminada_en = p_ahora,
         resultado = nullif(btrim(p_resultado), ''),
         motivo_no_hecha = coalesce(nullif(btrim(p_motivo), ''), motivo_no_hecha)
   where id = t.id and estado = 'en_curso';
  update public.tarea_elementos set estado = 'pendiente' where tarea_id = t.id and estado = 'en_curso';
  perform motor.registrar('tarea_terminada', p_persona, j.id, t.id,
                          jsonb_build_object('a_las', p_ahora, 'resultado', p_resultado,
                                             'motivo', p_motivo, 'pendientes', v_pendientes));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- ---------------------------------------------------------------------------
-- Pegar el reparto también desde Administración (va a la jornada del operario
-- por defecto) y «Pega el reparto» se cierra sola al aceptarse un reparto.
-- ---------------------------------------------------------------------------
create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_operario uuid;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada := motor.generar_jornada(v_operario, v_fecha);
  end if;
  if v_rol = 'operario' and v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;

  select h.turno into v_turno from public.horarios h
   where h.persona_id = v_operario and h.dia_semana = extract(isodow from v_fecha)
     and motor.en_local(v_fecha, h.hora_inicio) <= p_ahora
   order by h.hora_inicio desc limit 1;
  v_turno := coalesce(v_turno, 'manana');

  select t.id into v_stock from public.tareas t
   where t.jornada_id = v_jornada and t.clave = 'cola_stock'
     and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.lote = v_turno);

  return jsonb_build_object(
    'persona_id', p_persona, 'rol', v_rol, 'jornada_id', v_jornada,
    'fecha', v_fecha, 'dia', extract(day from v_fecha)::int, 'mes', extract(month from v_fecha)::int,
    'turno', v_turno,
    'destinos', (select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre,
                                                     'tipo', c.tipo, 'alias', to_jsonb(c.alias)) order by c.codigo)
                 from public.centros_trabajo c where c.tipo <> 'almacen'),
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas',
                                                         'stock_objetivo_pct', 'stock_excluidos')),
    'repartos', jsonb_build_object(
      'reparto', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                  from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'),
      'envio', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'envio' and r.estado = 'aceptado')),
    -- Para el envío: cajas pedidas en el reparto aceptado hoy y si ya se hizo el recuento de la mañana.
    'reparto_hoy', coalesce((select jsonb_agg(jsonb_build_object('producto', x ->> 'producto',
                                                                 'formato', coalesce(x ->> 'formato', ''),
                                                                 'pedido', (x ->> 'pedido')::int))
                             from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                             where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'), '[]'::jsonb),
    'recuento_manana_hecho', exists (select 1 from public.tareas t
                                     where t.jornada_id = v_jornada and t.clave = 'recuento_manana' and t.estado = 'hecha'),
    'stock', case when v_stock is null or v_rol <> 'operario' then null else motor.tarea_json(v_stock) end);
end;
$$;

create or replace function public.servidor_guardar_reparto(
  p_persona uuid, p_jornada uuid, p_tipo text, p_texto text, p_huella text, p_fecha_texto date, p_sale text,
  p_lectura uuid, p_lineas jsonb, p_produccion jsonb, p_bolsas jsonb, p_aceptado boolean, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r0 public.repartos;
  v_id uuid;
  v_cond text := case when p_tipo = 'reparto' then 'reparto_pegado' else 'envio_pegado' end;
  v_prod uuid;
  v_bolsas uuid;
  v_destino uuid;
  v_antes jsonb;
  v_despues jsonb;
  v_bolsas_resultado jsonb := '[]';
  v_min_caja integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                  where clave = 'duracion_min_por_caja' and centro_id is null), 1);
  v_min_bolsa integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                   where clave = 'duracion_min_por_bolsa' and centro_id is null), 3);
  v_dur_prod integer;
  v_dur_bolsas integer;
  v_resultado jsonb;
  v_es_suya boolean := p_persona = (select persona_id from public.jornadas where id = p_jornada);
  v_pegar uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('reparto:' || p_jornada || ':' || p_tipo, 0));

  if not p_aceptado then
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'con_errores', p_lectura, p_persona, p_ahora)
    returning id into v_id;
  else
    select * into r0 from public.repartos where jornada_id = p_jornada and tipo = p_tipo and estado = 'aceptado';
    if r0.huella = p_huella then
      return r0.resultado || jsonb_build_object('ya_pegado', true);
    end if;
    if r0.id is not null then
      update public.repartos set estado = 'sustituido' where id = r0.id;
    end if;
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado,
                                 sustituye_a, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'aceptado', r0.id, p_lectura, p_persona, p_ahora)
    returning id into v_id;
  end if;

  insert into public.reparto_lineas (reparto_id, num_linea, texto, clase, destino_id, cantidad, producto, formato, error, mensaje)
  select v_id, (l ->> 'num')::int, l ->> 'texto', l ->> 'clase', (l ->> 'destino_id')::uuid, (l ->> 'cantidad')::int,
         l ->> 'producto', l ->> 'formato', l ->> 'error', l ->> 'mensaje'
  from jsonb_array_elements(coalesce(p_lineas, '[]')) l;

  if not p_aceptado then
    perform motor.registrar('reparto_con_errores', p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo));
    return jsonb_build_object('reparto_id', v_id, 'estado', 'con_errores');
  end if;

  -- Tareas del reparto o del envío
  if p_tipo = 'reparto' then
    perform motor.fijar_sale(p_jornada, p_sale);
  else
    perform motor.fijar_envio(p_jornada, true, null);
  end if;
  perform motor.crear_tarea_condicionada(p_jornada, v_cond);
  if p_tipo = 'reparto' then
    select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
    select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';
  else
    select id into v_prod from public.tareas where jornada_id = p_jornada
       and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1;
    v_bolsas := v_prod;
  end if;
  if v_prod is null or v_bolsas is null then
    raise exception 'No hay tarea para el % de hoy', p_tipo;
  end if;
  update public.tareas set reparto_id = v_id where id in (v_prod, v_bolsas);

  -- Producción: lo que falta. Se conservan las cajas ya hechas.
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, motivo, orden_sugerido, calculo)
  select v_prod, 'referencia_produccion', p_tipo, x ->> 'producto', coalesce(x ->> 'formato', ''),
         (x ->> 'faltan')::int, x ->> 'aviso', coalesce((x ->> 'orden')::int, 0), x || jsonb_build_object('lectura_id', p_lectura)
  from jsonb_array_elements(coalesce(p_produccion, '[]')) x
  where (x ->> 'faltan')::int > 0
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set cantidad = excluded.cantidad, motivo = excluded.motivo, orden_sugerido = excluded.orden_sugerido,
         calculo = excluded.calculo,
         estado = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad then 'hecho'
                       when public.tarea_elementos.estado = 'hecho' then 'pendiente'
                       else public.tarea_elementos.estado end,
         terminado_en = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad
                             then coalesce(public.tarea_elementos.terminado_en, p_ahora) end;

  -- Referencias que ya no hacen falta: sin nada hecho se quitan; con algo hecho se cierran.
  delete from public.tarea_elementos e
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha = 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);
  update public.tarea_elementos e
     set cantidad = e.cantidad_hecha, estado = 'hecho', terminado_en = coalesce(e.terminado_en, p_ahora),
         motivo = 'Ya no hace falta con el reparto corregido'
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha > 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);

  -- Bolsas: las tiendas sin cambios se conservan; las que cambian se vuelven a
  -- comprobar caja a caja; las que ya no están se quitan.
  for v_destino in
    select distinct d from (
      select e.destino_id as d from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo
      union
      select (b ->> 'destino_id')::uuid from jsonb_array_elements(coalesce(p_bolsas, '[]')) b) s
  loop
    select jsonb_agg(jsonb_build_array(e.producto, e.formato, e.cantidad) order by e.producto, e.formato)
      into v_antes from public.tarea_elementos e
     where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
    select jsonb_agg(jsonb_build_array(i ->> 'producto', coalesce(i ->> 'formato', ''), (i ->> 'cantidad')::int)
                     order by i ->> 'producto', coalesce(i ->> 'formato', ''))
      into v_despues
      from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
     where (b ->> 'destino_id')::uuid = v_destino;

    if v_antes is distinct from v_despues then
      delete from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
      select v_bolsas, 'caja_bolsa', p_tipo, i ->> 'producto', coalesce(i ->> 'formato', ''), v_destino,
             (i ->> 'cantidad')::int, coalesce((i ->> 'orden')::int, 0)
        from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
       where (b ->> 'destino_id')::uuid = v_destino;
    end if;
    if v_despues is not null then
      v_bolsas_resultado := v_bolsas_resultado || jsonb_build_object(
        'destino_id', v_destino,
        'destino', (select nombre from public.centros_trabajo where id = v_destino),
        'cajas', (select sum((x ->> 2)::int) from jsonb_array_elements(v_despues) x),
        'cambia', r0.id is not null and v_antes is distinct from v_despues);
    end if;
  end loop;

  -- Duraciones de referencia (§6.10): 1 min por caja que falta, 3 min por tienda.
  select coalesce(sum((x ->> 'faltan')::int), 0) * v_min_caja into v_dur_prod
    from jsonb_array_elements(coalesce(p_produccion, '[]')) x where (x ->> 'faltan')::int > 0;
  v_dur_bolsas := jsonb_array_length(v_bolsas_resultado) * v_min_bolsa;
  if v_prod = v_bolsas then
    update public.tareas set duracion_min = nullif(v_dur_prod + v_dur_bolsas, 0) where id = v_prod;
  else
    update public.tareas set duracion_min = nullif(v_dur_prod, 0) where id = v_prod;
    update public.tareas set duracion_min = nullif(v_dur_bolsas, 0) where id = v_bolsas;
  end if;

  perform motor.ajustar_estado_lista(p_persona, v_prod, 'No falta producir nada: todo está hecho en el almacén', p_ahora);
  if v_bolsas <> v_prod then
    perform motor.ajustar_estado_lista(p_persona, v_bolsas, 'Sin bolsas', p_ahora);
  end if;

  -- «Pega el reparto» queda hecha al aceptarse el reparto, lo pegue quien lo pegue.
  if p_tipo = 'reparto' then
    for v_pegar in
      update public.tareas
         set estado = 'hecha', iniciada_en = coalesce(iniciada_en, p_ahora), terminada_en = p_ahora,
             resultado = case when v_es_suya then 'Reparto pegado' else 'Reparto pegado por Administración' end
       where jornada_id = p_jornada and clave = 'pegar_reparto' and estado in ('pendiente', 'en_curso')
      returning id
    loop
      perform motor.registrar('tarea_terminada', p_persona, p_jornada, v_pegar,
                              jsonb_build_object('a_las', p_ahora, 'por', 'reparto aceptado'));
    end loop;
  end if;

  v_resultado := jsonb_build_object(
    'reparto_id', v_id, 'estado', 'aceptado', 'tipo', p_tipo, 'sale', p_sale, 'sustituye_a', r0.id,
    'produccion', coalesce(p_produccion, '[]'), 'bolsas', v_bolsas_resultado,
    'tareas', jsonb_build_object('produccion', v_prod, 'bolsas', v_bolsas),
    'datos_leidos_en', (select leido_en from public.lecturas_sheets where id = p_lectura));
  update public.repartos set resultado = v_resultado where id = v_id;
  perform motor.registrar(case when r0.id is null then 'reparto_aceptado' else 'reparto_sustituido' end,
                          p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo, 'anterior', r0.id));
  return v_resultado || jsonb_build_object('tarea_activa',
                                           case when v_es_suya then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

-- ---------------------------------------------------------------------------
-- Correo «Incidencia: …» a Administración (mismo sistema y reintentos)
-- ---------------------------------------------------------------------------
create or replace function public.servidor_correo_reclamar(p_tipo text, p_ref text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_destino text := (select valor #>> '{}' from public.configuracion where clave = 'correo_administracion' and centro_id is null);
  v_remitente text := (select valor #>> '{}' from public.configuracion where clave = 'correo_remitente' and centro_id is null);
  m motor.correos;
  c public.cierres;
  r public.registro_eventos;
  i public.incidencias;
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
  elsif p_tipo = 'incidencia' then
    select * into i from public.incidencias where id = p_ref::uuid;
    if i.id is null then
      return motor.error('NO_ENCONTRADO', 'Esa incidencia no existe.');
    end if;
    v_texto := jsonb_build_object(
      'asunto', 'Incidencia: ' || i.descripcion,
      'texto', motor.texto_opcion(i.opcion) || ' · Importancia: '
               || case i.importancia when 'ahora' then 'ahora' when 'hoy' then 'hoy' else 'cuando se pueda' end || E'\n'
               || i.descripcion || E'\n\n'
               || 'La ha abierto ' || coalesce((select nombre from public.personas where id = i.persona_id), 'el operario')
               || ' el ' || to_char(motor.fecha_local(i.iniciada_en), 'DD/MM') || ' a las ' || motor.hora_texto(i.iniciada_en)
               || ' para que la resuelva Administración.' || E'\n'
               || 'Queda «esperando a Administración» hasta que el operario la cierre.');
  else
    return motor.error('DATOS_NO_VALIDOS', 'Tipo de correo no válido.');
  end if;

  update motor.correos set estado = 'enviando', intentos = intentos + 1, asunto = v_texto ->> 'asunto',
         proximo_intento_en = null
   where id = m.id;
  perform motor.registrar('correo_reclamado', null, coalesce(c.jornada_id, r.jornada_id, i.jornada_id), null,
                          jsonb_build_object('tipo', p_tipo, 'ref', p_ref, 'intento', m.intentos + 1));
  return jsonb_build_object('enviar', true, 'destino', v_destino, 'remitente', v_remitente,
                            'asunto', v_texto ->> 'asunto', 'texto', v_texto ->> 'texto');
end;
$$;

create or replace function public.servidor_correo_respuesta(p_tipo text, p_ref text, p_estado text, p_detalle text)
returns jsonb language plpgsql security definer set search_path = '' as $$
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
  elsif p_tipo = 'incidencia' then
    select jornada_id into v_jornada from public.incidencias where id = p_ref::uuid;
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

-- ---------------------------------------------------------------------------
-- Estado actual (Administración) y cierre del turno con las incidencias nuevas
-- ---------------------------------------------------------------------------
create or replace function motor.estado_actual_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
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
    'incidencia_en_curso', motor.seguimiento_de((select id from op), p_ahora) -> 'incidencia_en_curso',
    'incidencias_abiertas', coalesce((
      select jsonb_agg(motor.incidencia_json(i.id, p_ahora) order by i.iniciada_en)
        from public.incidencias i where i.persona_id = (select id from op) and i.estado <> 'cerrada'), '[]'::jsonb),
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

-- Incidencias del cierre: las abiertas en el turno, las cerradas en el turno y
-- las que siguen abiertas (aunque sean de otro día).
create or replace function motor.contenido_cierre(p_jornada uuid, p_turno text, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
  v_desde timestamptz;
  v_ultimo boolean;
  v_primero boolean;
  v_siguiente date;
  v_no_hecho jsonb;
  v_retrasos jsonb;
  v_cruce jsonb;
begin
  select * into j from public.jornadas where id = p_jornada;
  v_desde := coalesce((select max(generado_en) from public.cierres where jornada_id = j.id and turno <> p_turno), '-infinity');
  v_ultimo := p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                          and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio desc limit 1);
  v_primero := p_turno = (select h.turno from public.horarios h where h.persona_id = j.persona_id
                           and h.dia_semana = extract(isodow from j.fecha) order by h.hora_inicio limit 1);

  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', t.titulo, 'estado', t.estado,
           'motivo', coalesce(t.motivo_no_hecha,
                              case t.estado when 'bloqueada' then 'Bloqueada por un problema sin resolver'
                                            when 'en_curso' then 'Se quedó a medias'
                                            else 'Sin motivo anotado' end),
           'pasa_a_manana', v_ultimo and t.estado <> 'cancelada' and t.no_terminada in ('arrastrar', 'sigue_abierta'))
         order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden), '[]'::jsonb)
    into v_no_hecho
    from public.tareas t
   where t.jornada_id = j.id and not t.retirada_por_condicion and t.origen <> 'problema'
     and (t.obligatoria or t.origen = 'administracion')
     and t.estado in ('pendiente', 'en_curso', 'bloqueada', 'cancelada')
     and t.disponible_desde <= p_ahora
     and (motor.turno_de_tarea(t.id) = p_turno or (motor.turno_de_tarea(t.id) is null and v_ultimo));

  if p_turno = 'manana' then
    select coalesce(jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                                 'minutos', (r.datos ->> 'minutos')::int,
                                                 'nueva_hora', r.datos ->> 'nueva_hora', 'sale', r.datos ->> 'sale')
                              order by r.id), '[]'::jsonb)
      into v_retrasos
      from public.registro_eventos r where r.jornada_id = j.id and r.tipo = 'salida_retrasada';
    if jsonb_array_length(v_retrasos) > 0 then
      v_cruce := jsonb_build_object(
        'cajas_reparto', (select coalesce(sum((x ->> 'pedido')::int), 0)
                            from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                           where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
        'cajas_a_producir', (select coalesce(sum(e.cantidad), 0) from public.tarea_elementos e
                               join public.tareas t on t.id = e.tarea_id
                              where t.jornada_id = j.id and t.clave = 'produccion_reparto'),
        'cajas_producidas', (select coalesce(sum(e.cantidad_hecha), 0) from public.tarea_elementos e
                               join public.tareas t on t.id = e.tarea_id
                              where t.jornada_id = j.id and t.clave = 'produccion_reparto'),
        'tiendas', (select count(distinct e.destino_id) from public.tarea_elementos e
                      join public.tareas t on t.id = e.tarea_id
                     where t.jornada_id = j.id and t.clave = 'bolsas'),
        'incidencias_manana', (select count(*) from public.incidencias i
                                where i.jornada_id = j.id and i.iniciada_en <= p_ahora),
        'minutos_incidencias_manana', (select coalesce(sum((motor.incidencia_json(i.id, p_ahora) ->> 'minutos')::int), 0)::int
                                         from public.incidencias i where i.jornada_id = j.id and i.iniciada_en <= p_ahora));
    end if;
  end if;

  v_siguiente := (select min(d)::date from generate_series(j.fecha + 1, j.fecha + 7, interval '1 day') d
                   where exists (select 1 from public.horarios h where h.persona_id = j.persona_id
                                   and h.dia_semana = extract(isodow from d)));

  return jsonb_build_object(
    'fecha', j.fecha,
    'turno', p_turno,
    'operario', (select nombre from public.personas where id = j.persona_id),
    'sale', j.sale,
    'hay_envio', j.hay_envio,
    'generado_en', p_ahora,
    'hecho', coalesce((
      select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'resultado', t.resultado,
                                          'hora', motor.hora_texto(t.terminada_en), 'origen', t.origen)
                       order by t.terminada_en)
        from public.tareas t
       where t.jornada_id = j.id and t.estado = 'hecha' and t.origen <> 'problema'
         and t.terminada_en > v_desde and t.terminada_en <= p_ahora), '[]'::jsonb),
    'no_hecho', v_no_hecho,
    'problemas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tarea', t.titulo, 'tipo', p.tipo, 'descripcion', p.descripcion, 'abierto', motor.hora_texto(p.abierto_en),
               'estado', p.estado, 'solucion', p.solucion, 'llamadas', p.llamadas,
               'minutos', round(extract(epoch from (coalesce(p.resuelto_en, p_ahora) - p.abierto_en)) / 60)::int,
               'mas_de_5_min', coalesce(p.resuelto_en, p_ahora) - p.abierto_en > interval '5 minutes')
             order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.jornada_id = j.id and p.abierto_en <= p_ahora
         and (p.abierto_en > v_desde or p.resuelto_en > v_desde or p.resuelto_en is null)), '[]'::jsonb),
    'incidencias', coalesce((
      select jsonb_agg(motor.incidencia_json(i.id, p_ahora) || jsonb_build_object(
               'tarea', t.titulo, 'inicio', motor.hora_texto(i.iniciada_en), 'fin', motor.hora_texto(i.terminada_en))
             order by i.iniciada_en)
        from public.incidencias i left join public.tareas t on t.id = i.tarea_id
       where i.persona_id = j.persona_id and i.iniciada_en <= p_ahora
         and ((i.jornada_id = j.id and (i.iniciada_en > v_desde or i.terminada_en > v_desde or i.estado <> 'cerrada'))
              or (i.jornada_id <> j.id
                  and (i.estado <> 'cerrada'
                       or i.terminada_en > greatest(v_desde, motor.en_local(j.fecha, '00:00')))))), '[]'::jsonb),
    'arrastrados', jsonb_build_object(
      'llegaron', case when v_primero then coalesce((
          select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'estado', t.estado) order by t.orden)
            from public.tareas t where t.jornada_id = j.id and t.tarea_origen_id is not null), '[]'::jsonb) end,
      'pasan_a_manana', case when v_ultimo then coalesce((
          select jsonb_agg(t.titulo order by t.orden, t.creada_en) from public.tareas t
           where t.jornada_id = j.id and t.origen <> 'problema' and t.estado in ('pendiente', 'en_curso', 'bloqueada')
             and t.no_terminada in ('arrastrar', 'sigue_abierta')), '[]'::jsonb) end),
    'retrasos_salida', v_retrasos,
    'cruce_retrasos', v_cruce,
    'siguiente', case
      when not v_ultimo then jsonb_build_object('turno', 'tarde', 'tareas', coalesce((
          select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)))
                           order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden)
            from public.tareas t
           where t.jornada_id = j.id and t.estado = 'pendiente' and not t.retirada_por_condicion
             and (t.obligatoria or t.origen = 'administracion') and motor.turno_de_tarea(t.id) = 'tarde'), '[]'::jsonb))
      when v_siguiente is not null then jsonb_build_object('fecha', v_siguiente, 'tareas', coalesce((
          select jsonb_agg(x.titulo order by x.h nulls last, x.orden) from (
            select p.titulo, p.hora_inicio as h, p.orden from public.plantillas_tarea p
             where p.activa and p.centro_id = j.centro_id and p.programacion in ('con_hora', 'dia_semana')
               and p.condicion is null and p.obligatoria
               and extract(isodow from v_siguiente)::smallint = any (p.dias_semana)
            union all
            select t.titulo, t.hora_limite::time, t.orden from public.tareas t
              join public.jornadas s on s.id = t.jornada_id
             where s.persona_id = j.persona_id and s.fecha = v_siguiente and t.origen = 'administracion'
               and t.estado = 'pendiente') x), '[]'::jsonb))
    end,
    'calidad', case when extract(isodow from j.fecha) = 5 and v_ultimo then
      jsonb_build_object('limpieza_viernes',
                         exists (select 1 from public.tareas t join public.plantillas_tarea p on p.id = t.plantilla_id
                                  where t.jornada_id = j.id and p.codigo = 'limpieza_resinas' and t.estado = 'hecha')) end);
end;
$$;

create or replace function motor.texto_cierre(c jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_fecha date := (c ->> 'fecha')::date;
  v_dia text := (array['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'])[extract(isodow from v_fecha)];
  v_turno text := case c ->> 'turno' when 'manana' then 'mañana' else 'tarde' end;
  t text;
  x jsonb;
begin
  t := 'Cierre del turno de ' || v_turno || ' · ' || v_dia || ' ' || to_char(v_fecha, 'DD/MM')
       || coalesce(' · ' || (c ->> 'operario'), '') || E'\n';

  t := t || E'\nHECHO\n';
  if jsonb_array_length(c -> 'hecho') = 0 then t := t || E'- Nada\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'hecho') loop
    t := t || '- ' || (x ->> 'hora') || ' ' || (x ->> 'titulo') || coalesce(' → ' || (x ->> 'resultado'), '') || E'\n';
  end loop;

  t := t || E'\nNO HECHO\n';
  if jsonb_array_length(c -> 'no_hecho') = 0 then t := t || E'- Nada\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'no_hecho') loop
    t := t || '- ' || (x ->> 'titulo') || ': ' || (x ->> 'motivo')
         || case when (x ->> 'pasa_a_manana')::boolean then ' (pasa al día siguiente)' else '' end || E'\n';
  end loop;

  t := t || E'\nPROBLEMAS\n';
  if jsonb_array_length(c -> 'problemas') = 0 then t := t || E'- Ninguno\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'problemas') loop
    t := t || '- ' || (x ->> 'abierto') || ' ' || (x ->> 'tarea') || ': ' || (x ->> 'descripcion')
         || ' · ' || (x ->> 'minutos') || ' min'
         || case when (x ->> 'mas_de_5_min')::boolean then ' (más de 5 min)' else '' end
         || coalesce(' · Solución: ' || (x ->> 'solucion'), ' · Sin resolver') || E'\n';
  end loop;

  t := t || E'\nINCIDENCIAS\n';
  if jsonb_array_length(c -> 'incidencias') = 0 then t := t || E'- Ninguna\n'; end if;
  for x in select * from jsonb_array_elements(c -> 'incidencias') loop
    t := t || '- ' || (x ->> 'inicio')
         || case when x ->> 'fecha' is not null and (x ->> 'fecha')::date <> v_fecha
                 then ' del ' || to_char((x ->> 'fecha')::date, 'DD/MM') else '' end
         || ' ' || case when x ->> 'opcion' is not null then (x ->> 'opcion_texto') || ': ' else '' end
         || (x ->> 'descripcion')
         || case when x ->> 'quien' = 'administracion' then ' · la resuelve Administración' else '' end
         || coalesce(' · ' || (x ->> 'minutos') || ' min', '')
         || case when coalesce(x ->> 'estado', case when x ->> 'fin' is null then 'abierta' else 'cerrada' end) = 'cerrada'
                 then coalesce(' · cerrada a las ' || (x ->> 'fin'), '') || coalesce(' («' || (x ->> 'nota') || '»)', '')
                 when x ->> 'opcion' is null then ' (sigue abierta)'
                 else ' · ' || (x ->> 'estado_texto') end
         || E'\n';
  end loop;

  if jsonb_array_length(motor.como_lista(c -> 'arrastrados' -> 'llegaron')) > 0 then
    t := t || E'\nARRASTRADAS DE DÍAS ANTERIORES\n';
    for x in select * from jsonb_array_elements(c -> 'arrastrados' -> 'llegaron') loop
      t := t || '- ' || (x ->> 'titulo') || ' (' || (x ->> 'estado') || E')\n';
    end loop;
  end if;

  if jsonb_array_length(motor.como_lista(c -> 'arrastrados' -> 'pasan_a_manana')) > 0 then
    t := t || E'\nPASAN AL DÍA SIGUIENTE\n';
    for x in select * from jsonb_array_elements(c -> 'arrastrados' -> 'pasan_a_manana') loop
      t := t || '- ' || (x #>> '{}') || E'\n';
    end loop;
  end if;

  if jsonb_array_length(motor.como_lista(c -> 'retrasos_salida')) > 0 then
    t := t || E'\nRETRASOS DE LA SALIDA\n';
    for x in select * from jsonb_array_elements(c -> 'retrasos_salida') loop
      t := t || '- ' || (x ->> 'a_las') || ': +' || (x ->> 'minutos') || ' min, salida a las ' || (x ->> 'nueva_hora') || E'\n';
    end loop;
    t := t || '  Reparto: ' || (c -> 'cruce_retrasos' ->> 'cajas_reparto') || ' cajas pedidas, '
         || (c -> 'cruce_retrasos' ->> 'cajas_a_producir') || ' a producir ('
         || (c -> 'cruce_retrasos' ->> 'cajas_producidas') || ' hechas), '
         || (c -> 'cruce_retrasos' ->> 'tiendas') || ' tiendas. Incidencias de la mañana: '
         || (c -> 'cruce_retrasos' ->> 'incidencias_manana') || ' ('
         || (c -> 'cruce_retrasos' ->> 'minutos_incidencias_manana') || E' min).\n';
  end if;

  if c -> 'siguiente' is not null and c -> 'siguiente' <> 'null'::jsonb then
    t := t || case when c -> 'siguiente' ? 'fecha'
                   then E'\nLO QUE TOCA EL ' || to_char((c -> 'siguiente' ->> 'fecha')::date, 'DD/MM') || E'\n'
                   else E'\nLO QUE QUEDA PARA LA TARDE\n' end;
    for x in select * from jsonb_array_elements(c -> 'siguiente' -> 'tareas') loop
      t := t || '- ' || case when jsonb_typeof(x) = 'string' then x #>> '{}'
                             else coalesce((x ->> 'hora') || ' ', '') || (x ->> 'titulo') end || E'\n';
    end loop;
  end if;

  if c -> 'calidad' is not null and c -> 'calidad' <> 'null'::jsonb then
    t := t || E'\nCALIDAD DEL VIERNES\n- Limpieza hecha: '
         || case when (c -> 'calidad' ->> 'limpieza_viernes')::boolean then 'sí' else 'no' end || E'\n';
  end if;

  return jsonb_build_object(
    'asunto', 'Cierre ' || v_turno || ' · ' || v_dia || ' ' || to_char(v_fecha, 'DD/MM')
              || ' · Hecho: ' || jsonb_array_length(c -> 'hecho') || ' · Sin hacer: ' || jsonb_array_length(c -> 'no_hecho'),
    'texto', t);
end;
$$;

-- ---------------------------------------------------------------------------
-- Funciones para las pantallas
-- ---------------------------------------------------------------------------
create or replace function motor.api_crear_incidencia(
  p_id_cliente uuid, p_opcion text, p_descripcion text, p_quien text, p_importancia text, p_tarea_id uuid, p_tipo_problema text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_incidencia_de(auth.uid(), p_id_cliente, p_opcion, p_descripcion, p_quien, p_importancia,
                                   p_tarea_id, p_tipo_problema, now());
end; $$;

create or replace function motor.api_incidencias_abiertas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.incidencias_abiertas_de(auth.uid(), now());
end; $$;

create or replace function motor.api_cerrar_incidencia(p_incidencia_id uuid, p_nota text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.cerrar_incidencia_de(auth.uid(), p_incidencia_id, p_nota, now());
end; $$;

create or replace function public.crear_incidencia(
  id_cliente uuid, opcion text, descripcion text, quien text default null, importancia text default null,
  tarea_id uuid default null, tipo_problema text default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_crear_incidencia(id_cliente, opcion, descripcion, quien, importancia, tarea_id, tipo_problema) $$;
create or replace function public.incidencias_abiertas()
returns jsonb language sql set search_path = '' as $$ select motor.api_incidencias_abiertas() $$;
create or replace function public.cerrar_incidencia(incidencia_id uuid, nota text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_cerrar_incidencia(incidencia_id, nota) $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.api_crear_incidencia(uuid, text, text, text, text, uuid, text),
  motor.api_incidencias_abiertas(), motor.api_cerrar_incidencia(uuid, text)
to authenticated;

revoke execute on function
  public.crear_incidencia(uuid, text, text, text, text, uuid, text),
  public.incidencias_abiertas(), public.cerrar_incidencia(uuid, text)
from public, anon;
grant execute on function
  public.crear_incidencia(uuid, text, text, text, text, uuid, text),
  public.incidencias_abiertas(), public.cerrar_incidencia(uuid, text)
to authenticated;
