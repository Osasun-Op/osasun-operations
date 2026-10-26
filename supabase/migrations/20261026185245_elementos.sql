-- Tarea 3 · Elementos de una tarea (CONTRATOS.md §3.5)
-- iniciar_elemento, terminar_elemento y marcar_cajas, con el punto de encaje:
-- al terminar una referencia, o una tienda entera en las bolsas, si toca otra
-- tarea (problema, urgente o con hora vencida) la lista vuelve a «pendiente»
-- conservando lo hecho. Cuando todos los elementos están hechos, la tarea
-- queda hecha.

-- La tarea ahora incluye sus elementos ------------------------------------------
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
    'elementos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'tipo', e.tipo, 'producto', e.producto, 'formato', e.formato,
               'categoria', e.categoria, 'destino', c.nombre, 'destino_id', e.destino_id,
               'cantidad', e.cantidad, 'cantidad_hecha', e.cantidad_hecha, 'motivo', e.motivo,
               'orden_sugerido', e.orden_sugerido, 'estado', e.estado)
             order by e.tipo desc, c.nombre nulls first, e.orden_sugerido, e.producto, e.formato)
      from public.tarea_elementos e
      left join public.centros_trabajo c on c.id = e.destino_id
      where e.tarea_id = t.id), '[]'::jsonb))
  from public.tareas t where t.id = p_tarea;
$$;

-- Comprueba que el elemento es de la persona y de hoy; devuelve error o null.
create or replace function motor.comprobar_elemento(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb
language plpgsql stable
set search_path = ''
as $$
declare
  v_persona uuid;
  v_fecha date;
  v_estado text;
begin
  select j.persona_id, j.fecha, t.estado into v_persona, v_fecha, v_estado
    from public.tarea_elementos e
    join public.tareas t on t.id = e.tarea_id
    join public.jornadas j on j.id = t.jornada_id
   where e.id = p_elemento;
  if v_persona is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Ese elemento no existe.');
  end if;
  if v_fecha <> motor.fecha_local(p_ahora) or v_estado not in ('pendiente', 'en_curso') then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea no está abierta hoy.', jsonb_build_object('estado_tarea', v_estado));
  end if;
  return null;
end;
$$;

-- Pone la tarea en curso si estaba pendiente (sin pisar otra en curso).
create or replace function motor.asegurar_en_curso(p_persona uuid, p_tarea uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_otra uuid;
begin
  select * into t from public.tareas where id = p_tarea;
  if t.estado = 'en_curso' then
    return null;
  end if;
  select id into v_otra from public.tareas where jornada_id = t.jornada_id and estado = 'en_curso';
  if v_otra is not null then
    return motor.error('OTRA_TAREA_EN_CURSO', 'Termina primero la tarea que tienes en curso.',
                       jsonb_build_object('tarea_en_curso', motor.tarea_json(v_otra)));
  end if;
  update public.tareas set estado = 'en_curso', iniciada_en = coalesce(iniciada_en, p_ahora)
   where id = p_tarea and estado = 'pendiente';
  perform motor.registrar('tarea_iniciada', p_persona, t.jornada_id, p_tarea, jsonb_build_object('a_las', p_ahora));
  return null;
end;
$$;

-- Después de terminar una referencia o una tienda: ¿tarea hecha o encaje?
create or replace function motor.tras_elemento(p_persona uuid, p_tarea uuid, p_punto_de_encaje boolean, p_ahora timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_otra uuid;
  v_cajas integer;
begin
  select * into t from public.tareas where id = p_tarea;
  if t.estado <> 'en_curso' then
    return;
  end if;

  if not exists (select 1 from public.tarea_elementos where tarea_id = p_tarea and estado <> 'hecho') then
    select coalesce(sum(cantidad_hecha), 0) into v_cajas from public.tarea_elementos where tarea_id = p_tarea;
    update public.tareas
       set estado = 'hecha', terminada_en = p_ahora,
           resultado = coalesce(resultado, v_cajas || ' cajas')
     where id = p_tarea;
    perform motor.registrar('tarea_terminada', p_persona, t.jornada_id, p_tarea,
                            jsonb_build_object('a_las', p_ahora, 'por', 'todos los elementos hechos'));
    return;
  end if;

  if p_punto_de_encaje then
    v_otra := motor.elegir_tarea(t.jornada_id, p_ahora, p_tarea);
    if v_otra is not null
       and (select motor.escalon(o) in (2, 3, 4) from public.tareas o where o.id = v_otra) then
      update public.tareas set estado = 'pendiente' where id = p_tarea;
      perform motor.registrar('tarea_pausada', p_persona, t.jornada_id, p_tarea,
                              jsonb_build_object('a_las', p_ahora, 'entra', v_otra));
    end if;
  end if;
end;
$$;

create or replace function motor.respuesta_elemento(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb
language sql
set search_path = ''
as $$
  select jsonb_build_object(
    'elemento', (select jsonb_build_object('id', e.id, 'estado', e.estado, 'cantidad', e.cantidad,
                                           'cantidad_hecha', e.cantidad_hecha)
                 from public.tarea_elementos e where e.id = p_elemento),
    'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
$$;

-- iniciar_elemento: el operario elige la referencia (o la tienda) ---------------
create or replace function motor.iniciar_elemento_de(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  v_otro uuid;
begin
  v_error := motor.comprobar_elemento(p_persona, p_elemento, p_ahora);
  if v_error is not null then return v_error; end if;
  select * into e from public.tarea_elementos where id = p_elemento;
  if e.estado = 'hecho' then
    return motor.error('ESTADO_NO_VALIDO', 'Esta referencia ya está hecha.');
  end if;
  if e.tipo = 'referencia_produccion' and e.estado = 'pendiente' then
    select id into v_otro from public.tarea_elementos
     where tarea_id = e.tarea_id and tipo = 'referencia_produccion' and estado = 'en_curso';
    if v_otro is not null then
      return motor.error('OTRO_ELEMENTO_EN_CURSO', 'Termina primero la referencia que tienes empezada.',
                         jsonb_build_object('elemento_en_curso', v_otro));
    end if;
  end if;

  v_error := motor.asegurar_en_curso(p_persona, e.tarea_id, p_ahora);
  if v_error is not null then return v_error; end if;

  if e.tipo = 'referencia_produccion' then
    update public.tarea_elementos set estado = 'en_curso', iniciado_en = coalesce(iniciado_en, p_ahora)
     where id = p_elemento and estado = 'pendiente';
  else
    update public.tarea_elementos set iniciado_en = coalesce(iniciado_en, p_ahora) where id = p_elemento;
  end if;
  return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
end;
$$;

-- terminar_elemento: referencia de producción hecha --------------------------------
create or replace function motor.terminar_elemento_de(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  v_otro uuid;
begin
  v_error := motor.comprobar_elemento(p_persona, p_elemento, p_ahora);
  if v_error is not null then
    -- Repetir sobre algo ya hecho no es un error.
    if exists (select 1 from public.tarea_elementos where id = p_elemento and estado = 'hecho') then
      return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
    end if;
    return v_error;
  end if;
  select * into e from public.tarea_elementos where id = p_elemento;
  if e.tipo <> 'referencia_produccion' then
    return motor.error('DATOS_NO_VALIDOS', 'En las bolsas se marca cada caja.');
  end if;
  if e.estado = 'hecho' then
    return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
  end if;
  if e.estado = 'pendiente' then
    select id into v_otro from public.tarea_elementos
     where tarea_id = e.tarea_id and tipo = 'referencia_produccion' and estado = 'en_curso';
    if v_otro is not null then
      return motor.error('OTRO_ELEMENTO_EN_CURSO', 'Termina primero la referencia que tienes empezada.',
                         jsonb_build_object('elemento_en_curso', v_otro));
    end if;
  end if;

  v_error := motor.asegurar_en_curso(p_persona, e.tarea_id, p_ahora);
  if v_error is not null then return v_error; end if;

  update public.tarea_elementos
     set estado = 'hecho', cantidad_hecha = greatest(cantidad, cantidad_hecha),
         iniciado_en = coalesce(iniciado_en, p_ahora), terminado_en = p_ahora
   where id = p_elemento;
  perform motor.registrar('elemento_terminado', p_persona, null, e.tarea_id,
                          jsonb_build_object('elemento', p_elemento, 'producto', e.producto,
                                             'formato', e.formato, 'cajas', e.cantidad));
  perform motor.tras_elemento(p_persona, e.tarea_id, true, p_ahora);
  return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
end;
$$;

-- marcar_cajas: cuántas cajas de esta referencia lleva metidas en la bolsa ----------
create or replace function motor.marcar_cajas_de(p_persona uuid, p_elemento uuid, p_cantidad_hecha integer, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  v_estado text;
  v_tienda_completa boolean;
begin
  v_error := motor.comprobar_elemento(p_persona, p_elemento, p_ahora);
  if v_error is not null then
    if exists (select 1 from public.tarea_elementos
               where id = p_elemento and cantidad_hecha = p_cantidad_hecha) then
      return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);  -- repetición
    end if;
    return v_error;
  end if;
  select * into e from public.tarea_elementos where id = p_elemento;
  if e.tipo <> 'caja_bolsa' then
    return motor.error('DATOS_NO_VALIDOS', 'Las cajas se marcan en las bolsas.');
  end if;
  if p_cantidad_hecha is null or p_cantidad_hecha < 0 or p_cantidad_hecha > e.cantidad then
    return motor.error('CANTIDAD_FUERA_DE_RANGO', 'La cantidad debe estar entre 0 y ' || e.cantidad || '.');
  end if;
  if e.cantidad_hecha = p_cantidad_hecha then
    return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);  -- repetición: nada cambia
  end if;

  v_error := motor.asegurar_en_curso(p_persona, e.tarea_id, p_ahora);
  if v_error is not null then return v_error; end if;

  v_estado := case when p_cantidad_hecha = e.cantidad then 'hecho'
                   when p_cantidad_hecha > 0 then 'en_curso' else 'pendiente' end;
  update public.tarea_elementos
     set cantidad_hecha = p_cantidad_hecha, estado = v_estado,
         iniciado_en = coalesce(iniciado_en, p_ahora),
         terminado_en = case when v_estado = 'hecho' then p_ahora end
   where id = p_elemento;
  perform motor.registrar('cajas_marcadas', p_persona, null, e.tarea_id,
                          jsonb_build_object('elemento', p_elemento, 'cajas', p_cantidad_hecha));

  if v_estado = 'hecho' then
    -- Punto de encaje: solo cuando la tienda (o el destino) está completa.
    select not exists (select 1 from public.tarea_elementos
                        where tarea_id = e.tarea_id and tipo = 'caja_bolsa'
                          and destino_id is not distinct from e.destino_id and estado <> 'hecho')
      into v_tienda_completa;
    perform motor.tras_elemento(p_persona, e.tarea_id, v_tienda_completa, p_ahora);
  end if;
  return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
end;
$$;

-- terminar_tarea: con elementos pendientes hace falta un motivo -------------------
create or replace function motor.terminar_tarea_de(
  p_persona uuid, p_tarea uuid, p_resultado text, p_motivo text, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
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

-- API (operario) -----------------------------------------------------------------
create or replace function motor.api_iniciar_elemento(p_elemento_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.iniciar_elemento_de(auth.uid(), p_elemento_id, now());
end;
$$;

create or replace function motor.api_terminar_elemento(p_elemento_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.terminar_elemento_de(auth.uid(), p_elemento_id, now());
end;
$$;

create or replace function motor.api_marcar_cajas(p_elemento_id uuid, p_cantidad_hecha integer)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.marcar_cajas_de(auth.uid(), p_elemento_id, p_cantidad_hecha, now());
end;
$$;

create or replace function public.iniciar_elemento(elemento_id uuid)
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_iniciar_elemento(elemento_id) $$;

create or replace function public.terminar_elemento(elemento_id uuid)
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_terminar_elemento(elemento_id) $$;

create or replace function public.marcar_cajas(elemento_id uuid, cantidad_hecha integer)
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_marcar_cajas(elemento_id, cantidad_hecha) $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.es_admin(), motor.mi_centro(),
  motor.api_mi_perfil(), motor.api_tarea_activa(), motor.api_iniciar_tarea(uuid),
  motor.api_terminar_tarea(uuid, text, text), motor.api_anotar_motivo(uuid, text),
  motor.api_iniciar_elemento(uuid), motor.api_terminar_elemento(uuid), motor.api_marcar_cajas(uuid, integer)
to authenticated;

revoke execute on function public.iniciar_elemento(uuid), public.terminar_elemento(uuid),
  public.marcar_cajas(uuid, integer) from public, anon;
grant execute on function public.iniciar_elemento(uuid), public.terminar_elemento(uuid),
  public.marcar_cajas(uuid, integer) to authenticated;
