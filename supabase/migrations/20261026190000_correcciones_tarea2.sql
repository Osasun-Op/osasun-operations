-- Tarea 3 · Correcciones de la revisión del PR #2
-- 1. La recepción de mercancía se atiende en el momento: escalón 3 (como las
--    urgentes), entra en el siguiente punto de encaje. Las plantillas pasan a
--    tener «urgente» y el escalón 3 es «urgente», venga de donde venga.
-- 2. Minis: sin duración hasta que se conozca.
-- 3. Envío del viernes: se prepara antes de las 10:45 y lo lleva a Nacex quien
--    sale; si sale Administración no es una tarea del operario. Para eso una
--    plantilla puede tener varias condiciones (todas deben cumplirse).
-- Además, las tareas de preparar el envío llevan sus cajas (contenido «bolsas»).

alter table public.plantillas_tarea drop constraint plantillas_tarea_condicion_check;
alter table public.plantillas_tarea
  alter column condicion type text[] using case when condicion is null then null else array[condicion] end;
alter table public.plantillas_tarea add constraint plantillas_tarea_condicion_check check (
  cardinality(condicion) > 0 and condicion <@ array[
    'sale_operario', 'sale_administracion', 'hay_envio', 'no_hay_envio',
    'reparto_pegado', 'envio_pegado', 'llega_mercancia', 'pedido_cliente', 'no_quedan_vapers']::text[]);
alter table public.plantillas_tarea add column urgente boolean not null default false;

-- ¿Se cumplen las condiciones con lo que ya se sabe del día? true/false si todas
-- son de estado; null si alguna depende de algo que pasa durante el día.
drop function motor.condicion_estado(public.jornadas, text);
create or replace function motor.condicion_estado(p_jornada public.jornadas, p_condiciones text[])
returns boolean
language sql immutable
set search_path = ''
as $$
  select case
    when p_condiciones is null or cardinality(p_condiciones) = 0 then true
    when exists (select 1 from unnest(p_condiciones) c
                 where c not in ('sale_operario', 'sale_administracion', 'hay_envio', 'no_hay_envio')) then null
    else (select bool_and(case c
            when 'sale_operario' then coalesce(p_jornada.sale = 'operario', false)
            when 'sale_administracion' then coalesce(p_jornada.sale = 'administracion', false)
            when 'hay_envio' then p_jornada.hay_envio
            when 'no_hay_envio' then not p_jornada.hay_envio
          end) from unnest(p_condiciones) c)
  end;
$$;

-- Motivo de la retirada: la primera condición que no se cumple.
create or replace function motor.texto_condiciones(p_jornada public.jornadas, p_condiciones text[])
returns text
language sql immutable
set search_path = ''
as $$
  select coalesce((select motor.texto_condicion(c) from unnest(p_condiciones) with ordinality u(c, n)
                   where not motor.condicion_estado(p_jornada, array[c]) order by n limit 1), '');
$$;

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
    jornada_id, clave, origen, plantilla_id, titulo, porque, contenido, obligatoria, urgente,
    prioridad_cola, condicion, requiere_clave, disponible_desde, hora_programada,
    hora_limite, duracion_min, no_terminada, orden)
  select
    j.id, p_clave, p_origen, p.id, p.titulo, p.porque, p.contenido, p.obligatoria, p.urgente,
    p.prioridad_cola, array_to_string(p.condicion, '+'), p.requiere_codigo,
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
               motivo_no_hecha = 'Ya no aplica: ' || motor.texto_condiciones(j, p.condicion)
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

-- Una plantilla de evento puede llevar además condiciones de estado: todas
-- deben cumplirse para crear la tarea.
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
    where centro_id = j.centro_id and activa and p_condicion = any (condicion)
      and extract(isodow from j.fecha)::smallint = any (dias_semana)
      and coalesce(motor.condicion_estado(j, array_remove(condicion, p_condicion)), false)
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

-- Escalón 3: urgentes (de Administración o, como la recepción de mercancía, por plantilla).
create or replace function motor.escalon(t public.tareas)
returns integer
language sql immutable
set search_path = ''
as $$
  select case
    when t.estado = 'en_curso' then 1
    when t.origen = 'problema' then 2
    when t.urgente then 3
    when t.hora_programada is not null then 4
    when t.obligatoria or (t.origen = 'administracion' and t.hora_limite is not null) then 5
    when t.origen = 'administracion' then 6
    when t.prioridad_cola is null then 7
    else 8
  end;
$$;

-- Entre urgentes (escalón 3), por orden de llegada.
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
           case when motor.escalon(t) = 3 then t.creada_en end,
           case t.prioridad_cola when 'A' then 1 when 'C' then 2 when 'D' then 3 end nulls first,
           t.hora_programada nulls last,
           t.hora_limite nulls last,
           t.obligatoria desc,
           t.orden,
           t.creada_en,
           t.id
  limit 1;
$$;

-- Datos de las plantillas
update public.plantillas_tarea set urgente = true where codigo = 'recepcion_mercancia';
update public.plantillas_tarea set duracion_min = null where codigo = 'minis';
update public.plantillas_tarea set hora_limite = '10:45', contenido = 'bolsas'
 where codigo = 'preparar_envio_viernes';
update public.plantillas_tarea set contenido = 'bolsas' where codigo = 'preparar_envio';
update public.plantillas_tarea
   set programacion = 'con_hora', hora_inicio = '10:45', condicion = array['hay_envio', 'sale_operario'],
       titulo = 'Lleva el envío de Gipuzkoa en el reparto y déjalo en Nacex de camino', orden = 49
 where codigo = 'nacex_viernes';

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.es_admin(), motor.mi_centro(),
  motor.api_mi_perfil(), motor.api_tarea_activa(), motor.api_iniciar_tarea(uuid),
  motor.api_terminar_tarea(uuid, text, text), motor.api_anotar_motivo(uuid, text)
to authenticated;
