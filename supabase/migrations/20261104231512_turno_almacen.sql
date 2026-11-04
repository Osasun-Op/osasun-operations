-- Tarea 35 · «Empezar turno» y «Fin de turno» del operario (ESTADO_DEL_SISTEMA.md §6.4, «El turno lo abre y lo cierra el
-- operario»; decisión del propietario, 04/11/2026). Solo en pruebas: producción espera con las de tiendas.
--   1. El turno del operario va en el mismo registro de turnos que usan las tiendas (turnos_tienda): una fila por
--      jornada y turno, sin persona de tienda, con terminado_en y si se cerró solo. Repetir no duplica.
--   2. «En turno» (motor.en_turno) es ahora «turno empezado y sin cerrar», en lugar del reloj:
--      - antes de «Empezar turno», ninguna tarea; tarea_activa lo dice en `turno`, para que la pantalla enseñe el botón;
--      - hasta «Fin de turno» le siguen saliendo las tareas, también pasada su hora;
--      - pasada su hora, solo lo obligatorio de ese turno que quede (el recuento) y lo obligatorio en curso; lo no
--        obligatorio se pausa y espera al siguiente turno (la pausa de la Tarea 24);
--      - pasada su hora y sin nada obligatorio, «Has terminado. Pulsa «Fin de turno»» (sin «Orden y limpieza»).
--   3. El cierre del turno (el de siempre, con su correo) sale al pulsar «Fin de turno»:
--      - con el recuento de stock de ese turno sin hacer, no se puede cerrar (RECUENTO_PENDIENTE): el recuento sale en ese
--        momento, aunque no sea su hora, para que la app vuelva a leer la hoja siempre (propietario, 04/11/2026);
--      - con otras obligatorias sin hacer, pide confirmación (CONFIRMAR_FIN_DE_TURNO) y constan en el cierre.
--      Si no lo pulsa, el turno se cierra solo al empezar el siguiente o al acabar el día (tarea programada, a
--      medianoche), y el cierre dice que no lo cerró el operario. Un turno que no se empezó también tiene su cierre
--      («No empezó el turno»). Un cierre sin recuento no cuenta como recuento: el almacén sigue contando desde el último.
--   4. No cambia: el reparto, las bolsas, la salida (también cuando sale Administración), los avisos y las tareas de
--      Administración. Administración no ficha.
--
-- Deshacer: volver a crear motor.en_turno, motor.elegir_tarea y motor.tarea_activa_de como están en
-- 20261102153923 / 20261103175352 / 20261103194512; motor.asegurar_en_curso y motor.terminar_tarea_de como en
-- 20261102153923; motor.pausar_fin_de_turno y motor.contenido_cierre como en 20261102153458; motor.texto_cierre como en
-- 20261027120100; motor.generar_cierres_programados como en 20261102190536 y la tarea programada generar_cierres_turno
-- ('0,30 11,12,16,17 * * 1-5'); borrar las funciones nuevas de esta migración, la tarea cerrar_turnos_olvidados, las filas
-- de turnos_tienda sin persona de tienda, el índice turnos_tienda_almacen_key, la restricción turnos_tienda_terminado_check
-- y las columnas terminado_en y terminado_solo, y volver a poner persona_tienda_id como obligatoria.

-- ---------------------------------------------------------------------------
-- 1. El registro de turnos sirve también para el almacén
-- ---------------------------------------------------------------------------
alter table public.turnos_tienda alter column persona_tienda_id drop not null;
alter table public.turnos_tienda add column terminado_en timestamptz, add column terminado_solo boolean;
alter table public.turnos_tienda add constraint turnos_tienda_terminado_check
  check ((terminado_en is null) = (terminado_solo is null) and (persona_tienda_id is not null or turno is not null));
-- Un turno del almacén por jornada y turno: repetir «Empezar turno» no lo duplica.
create unique index turnos_tienda_almacen_key on public.turnos_tienda (jornada_id, turno) where persona_tienda_id is null;
comment on table public.turnos_tienda is
  'Los turnos. En tienda, quién empieza (una fila por persona). En el almacén (Tarea 35), el turno del operario: '
  'sin persona de tienda, una fila por jornada y turno, con terminado_en y terminado_solo.';
comment on column public.turnos_tienda.terminado_en is 'Cuándo se cerró el turno (Tarea 35). Vacío: abierto.';
comment on column public.turnos_tienda.terminado_solo is
  'true: se cerró solo (al empezar el siguiente o al acabar el día), no lo cerró el operario (Tarea 35).';

-- ---------------------------------------------------------------------------
-- 2. El turno del operario
-- ---------------------------------------------------------------------------
-- El turno abierto de la jornada (empezado y sin cerrar).
create or replace function motor.turno_abierto(p_jornada uuid)
returns public.turnos_tienda language sql stable set search_path = '' as $$
  select * from public.turnos_tienda
   where jornada_id = p_jornada and persona_tienda_id is null and terminado_en is null
   order by empezado_en desc, id desc limit 1;
$$;

-- «En turno»: turno empezado y sin cerrar (antes, entre la hora de inicio y la de fin).
create or replace function motor.en_turno(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.turnos_tienda o
                  where o.jornada_id = p_jornada and o.persona_tienda_id is null and o.terminado_en is null
                    and o.empezado_en <= p_ahora)
$$;

-- La hora a la que acaba ese turno según su horario.
create or replace function motor.hora_fin_turno(p_jornada uuid, p_turno text)
returns timestamptz language sql stable set search_path = '' as $$
  select motor.en_local(j.fecha, h.hora_fin) from public.jornadas j
    join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
   where j.id = p_jornada and h.turno = p_turno
$$;

-- El último turno del día según su horario (las tareas sin turno cuentan en él, como en el cierre).
create or replace function motor.ultimo_turno(p_jornada uuid)
returns text language sql stable set search_path = '' as $$
  select h.turno from public.jornadas j
    join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
   where j.id = p_jornada order by h.hora_inicio desc limit 1
$$;

-- El turno abierto ya ha pasado su hora de fin.
create or replace function motor.pasada_la_hora(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select p_ahora >= motor.hora_fin_turno(p_jornada, o.turno) from motor.turno_abierto(p_jornada) o
                    where o.id is not null), false)
$$;

-- Solo lo obligatorio: sin turno empezado o pasada su hora (lo no obligatorio espera al siguiente turno).
create or replace function motor.solo_obligatorio(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select not motor.en_turno(p_jornada, p_ahora) or motor.pasada_la_hora(p_jornada, p_ahora)
$$;

-- El turno que empieza «Empezar turno»: el primero del día sin cerrar que aún no ha acabado su hora; si ya han acabado
-- todos, el último sin cerrar. Nada si los dos están cerrados.
create or replace function motor.turno_a_empezar(p_jornada uuid, p_ahora timestamptz)
returns text language sql stable set search_path = '' as $$
  select h.turno from public.jornadas j
    join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
   where j.id = p_jornada
     and not exists (select 1 from public.cierres c where c.jornada_id = j.id and c.turno = h.turno)
   order by motor.en_local(j.fecha, h.hora_fin) <= p_ahora,
            case when motor.en_local(j.fecha, h.hora_fin) > p_ahora then h.hora_inicio end,
            h.hora_inicio desc
   limit 1
$$;

-- Lo que dice tarea_activa del turno (CONTRATOS §3.2): qué botón enseñar y «Has terminado».
create or replace function motor.turno_json(p_jornada uuid, p_ahora timestamptz, p_tarea uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  o public.turnos_tienda := motor.turno_abierto(p_jornada);
  v_empezar text := motor.turno_a_empezar(p_jornada, p_ahora);
  v_turno text;
  v_pasada boolean;
begin
  if o.id is not null and o.empezado_en > p_ahora then
    o := null;
  end if;
  v_turno := coalesce(o.turno, v_empezar);
  v_pasada := o.id is not null and p_ahora >= motor.hora_fin_turno(p_jornada, o.turno);
  return jsonb_build_object(
    'estado', case when o.id is not null then 'abierto' when v_empezar is not null then 'sin_empezar' else 'terminado' end,
    'turno', v_turno,
    'empezado_a_las', motor.hora_texto(o.empezado_en),
    'hora_fin', motor.hora_texto(motor.hora_fin_turno(p_jornada, v_turno)),
    'pasada_la_hora', v_pasada,
    -- El turno que empezaría «Empezar turno» (cierra solo el abierto, si es otro). Vacío: no hay que enseñar el botón.
    'empezar', case when v_empezar is distinct from o.turno then v_empezar end,
    'mensaje', case
      when o.id is null and v_empezar is not null
        then 'Pulsa «Empezar turno» para empezar el turno de ' || case v_empezar when 'manana' then 'mañana' else 'tarde' end || '.'
      when o.id is null then 'Has cerrado los turnos de hoy.'
      when v_pasada and p_tarea is null then 'Has terminado. Pulsa «Fin de turno».' end);
end;
$$;

-- Lo que dice el cierre del turno (contenido.turno_operario).
create or replace function motor.turno_cierre_json(p_jornada uuid, p_turno text)
returns jsonb language sql stable set search_path = '' as $$
  select case when o.id is null then
                jsonb_build_object('como', 'sin_empezar', 'empezado', null, 'terminado', null, 'al_dia_siguiente', false)
              else jsonb_build_object(
                'como', case when o.terminado_en is null then 'abierto' when o.terminado_solo then 'solo' else 'operario' end,
                'empezado', motor.hora_texto(o.empezado_en), 'terminado', motor.hora_texto(o.terminado_en),
                'al_dia_siguiente', coalesce(o.terminado_en >= motor.en_local(j.fecha + 1, '00:00'), false)) end
    from public.jornadas j
    left join public.turnos_tienda o on o.jornada_id = j.id and o.turno = p_turno and o.persona_tienda_id is null
   where j.id = p_jornada
$$;

-- Cierra el turno (si estaba abierto) y genera su cierre con el correo, el de siempre.
create or replace function motor.cerrar_turno_almacen(p_jornada uuid, p_turno text, p_ahora timestamptz, p_solo boolean)
returns uuid language plpgsql set search_path = '' as $$
begin
  update public.turnos_tienda set terminado_en = p_ahora, terminado_solo = p_solo
   where jornada_id = p_jornada and turno = p_turno and persona_tienda_id is null and terminado_en is null;
  if found then
    perform motor.registrar('turno_terminado', null, p_jornada, null,
                            jsonb_build_object('turno', p_turno, 'a_las', p_ahora, 'solo', p_solo));
  end if;
  return motor.generar_cierre(p_jornada, p_turno, p_ahora);
end;
$$;

-- «Empezar turno». Repetir no duplica. Si hay otro turno abierto, o uno anterior que no se empezó, se cierran solos.
create or replace function motor.empezar_turno_almacen_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_jornada uuid;
  o public.turnos_tienda;
  v_turno text;
  r record;
begin
  perform pg_advisory_xact_lock(hashtextextended('turno_almacen:' || p_persona, 0));
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes turno.');
  end if;
  o := motor.turno_abierto(v_jornada);
  v_turno := motor.turno_a_empezar(v_jornada, p_ahora);
  if o.id is not null and o.turno = v_turno then
    return motor.tarea_activa_de(p_persona, p_ahora);
  end if;
  if v_turno is null then
    return motor.error('TURNOS_CERRADOS', 'Ya has cerrado los turnos de hoy.');
  end if;
  -- Lo que quedó abierto (también de otro día) o sin empezar antes de este turno se cierra solo.
  for r in
    select x.jornada_id, x.turno from public.turnos_tienda x join public.jornadas j on j.id = x.jornada_id
     where j.persona_id = p_persona and x.persona_tienda_id is null and x.terminado_en is null
    union
    select j.id, h.turno from public.jornadas j
      join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
     where j.id = v_jornada
       and h.hora_inicio < (select h2.hora_inicio from public.horarios h2
                             where h2.persona_id = j.persona_id and h2.dia_semana = h.dia_semana and h2.turno = v_turno)
       and not exists (select 1 from public.cierres c where c.jornada_id = j.id and c.turno = h.turno)
  loop
    perform motor.cerrar_turno_almacen(r.jornada_id, r.turno, p_ahora, true);
  end loop;
  insert into public.turnos_tienda (jornada_id, turno, persona_tienda_id, nombre, empezado_en)
  select v_jornada, v_turno, null, p.nombre, p_ahora from public.personas p where p.id = p_persona
  on conflict (jornada_id, turno) where persona_tienda_id is null do nothing;
  if found then
    perform motor.registrar('turno_empezado', p_persona, v_jornada, null, jsonb_build_object('turno', v_turno, 'a_las', p_ahora));
  end if;
  return motor.tarea_activa_de(p_persona, p_ahora);
end;
$$;

-- «Fin de turno». Con el recuento de ese turno sin hacer, no se cierra: el recuento sale en ese momento. Con otras
-- obligatorias sin hacer, hay que confirmar. Sin turno abierto, no hace nada (repetir no duplica).
create or replace function motor.fin_turno_almacen_de(p_persona uuid, p_confirmar boolean, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_jornada uuid;
  o public.turnos_tienda;
  v_ultimo text;
  v_recuento public.tareas;
  v_pendientes jsonb;
  v_cierre uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('turno_almacen:' || p_persona, 0));
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  o := motor.turno_abierto(v_jornada);
  if v_jornada is null or o.id is null then
    return jsonb_build_object('cierre', null, 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  v_ultimo := motor.ultimo_turno(v_jornada);

  -- El recuento no se puede dejar sin hacer: la app vuelve a leer la hoja siempre (propietario, 04/11/2026).
  select * into v_recuento from public.tareas t
   where t.jornada_id = v_jornada and t.contenido = 'recuento' and not t.retirada_por_condicion
     and t.estado in ('pendiente', 'en_curso', 'bloqueada')
     and coalesce(motor.turno_de_tarea(t.id), v_ultimo) = o.turno
   order by t.disponible_desde, t.orden limit 1;
  if v_recuento.id is not null then
    if v_recuento.disponible_desde > p_ahora then
      update public.tareas set disponible_desde = p_ahora where id = v_recuento.id;
      perform motor.registrar('recuento_adelantado', p_persona, v_jornada, v_recuento.id,
                              jsonb_build_object('a_las', p_ahora, 'turno', o.turno));
    end if;
    return motor.error('RECUENTO_PENDIENTE', 'Antes de cerrar el turno, haz el recuento de stock.',
                       jsonb_build_object('tarea', motor.tarea_json(v_recuento.id),
                                          'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora)));
  end if;

  select jsonb_agg(t.titulo order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden) into v_pendientes
    from public.tareas t
   where t.jornada_id = v_jornada and t.obligatoria and not t.retirada_por_condicion and t.origen <> 'problema'
     and t.estado in ('pendiente', 'en_curso', 'bloqueada')
     and coalesce(motor.turno_de_tarea(t.id), v_ultimo) = o.turno;
  if v_pendientes is not null and not coalesce(p_confirmar, false) then
    return motor.error('CONFIRMAR_FIN_DE_TURNO',
                       case when jsonb_array_length(v_pendientes) = 1 then 'Te queda 1 obligatoria sin hacer: '
                            else 'Te quedan ' || jsonb_array_length(v_pendientes) || ' obligatorias sin hacer: ' end
                       || (select string_agg(x, ', ' order by n) from jsonb_array_elements_text(v_pendientes)
                                                                       with ordinality a(x, n))
                       || '. ¿Cerrar el turno igualmente?',
                       jsonb_build_object('pendientes', v_pendientes));
  end if;

  v_cierre := motor.cerrar_turno_almacen(v_jornada, o.turno, p_ahora, false);
  return jsonb_build_object('cierre', v_cierre, 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- API del operario (Chromebook y Pixel).
create or replace function motor.api_empezar_turno_almacen()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.empezar_turno_almacen_de(auth.uid(), now());
end; $$;

create or replace function motor.api_fin_turno_almacen(p_confirmar boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.fin_turno_almacen_de(auth.uid(), p_confirmar, now());
end; $$;

create or replace function public.empezar_turno_almacen()
returns jsonb language sql set search_path = '' as $$ select motor.api_empezar_turno_almacen() $$;
create or replace function public.fin_turno_almacen(confirmar boolean default false)
returns jsonb language sql set search_path = '' as $$ select motor.api_fin_turno_almacen(confirmar) $$;

-- ---------------------------------------------------------------------------
-- 3. Funciones que se rehacen
-- ---------------------------------------------------------------------------
create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  v_id uuid;
  -- Lo primero de la mañana (Tarea 23): mientras falte, no sale nada más que lo urgente,
  -- lo que va a su hora y lo que forma parte de ello.
  v_primero boolean := motor.lo_primero_pendiente(p_jornada, p_ahora);
  v_en_turno boolean;
  -- Tarea 29: las bolsas del reparto sin terminar. Con la producción hecha, solo salen ellas.
  v_bolsas public.tareas;
  v_solo_bolsas boolean;
  -- Tarea 35: pasada la hora del turno abierto, solo lo obligatorio de ese turno.
  v_pasada boolean;
  v_turno text;
  v_ultimo text;
begin
  v_en_turno := motor.en_turno(p_jornada, p_ahora);
  -- Tarea 35: el turno lo empieza y lo termina el operario. Sin turno empezado, ninguna tarea.
  if not v_en_turno then
    return null;
  end if;
  v_pasada := motor.pasada_la_hora(p_jornada, p_ahora);
  v_turno := (motor.turno_abierto(p_jornada)).turno;
  v_ultimo := motor.ultimo_turno(p_jornada);
  select * into v_bolsas from public.tareas b
   where b.jornada_id = p_jornada and b.clave = 'bolsas' and b.estado in ('pendiente', 'en_curso', 'bloqueada') limit 1;
  v_solo_bolsas := v_bolsas.id is not null and v_bolsas.disponible_desde <= p_ahora
                   and motor.requisitos_hechos(p_jornada, 'produccion_reparto');

  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and ((t.estado = 'en_curso' and (not v_pasada or t.obligatoria))
         or (t.estado = 'pendiente'
             -- Tarea 35: pasada la hora, solo lo obligatorio de ese turno que quede (y lo que abre un problema).
             and (not v_pasada or t.origen = 'problema'
                  or (t.obligatoria and coalesce(motor.turno_de_tarea(t.id), v_ultimo) = v_turno))
             and t.disponible_desde <= p_ahora
             and t.prioridad_cola is distinct from 'D'
             and motor.requisitos_hechos(t.jornada_id, t.requiere_clave)
             and (not v_primero or motor.va_antes_que_lo_primero(t))
             -- Tarea 29: la salida del reparto, solo con las bolsas hechas; y con la producción
             -- hecha, nada entre ella y las bolsas (salvo un problema que abre él).
             and (v_bolsas.id is null or t.clave is distinct from 'salida_reparto')
             and (not v_solo_bolsas or t.origen = 'problema'
                  or split_part(t.clave, ':', 1) in ('bolsas', 'pedido_tienda'))))
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
  if v_id is not null or v_pasada or v_solo_bolsas then
    return v_id;
  end if;

  select t.id into v_id
  from public.tareas t
  join public.plantillas_tarea p on p.id = t.plantilla_id
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and p.programacion = 'dia_semana' and p.turno = 'tarde' and p.hora_inicio is null
    and t.requiere_clave is null
    and not v_primero
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

create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
as $$
declare
  v_jornada uuid;
  j public.jornadas;
  v_tarea uuid;
  v_sig uuid;
  v_prox uuid;
  s public.tareas;
  o public.turnos_tienda;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return jsonb_build_object('jornada', null, 'pregunta', null, 'tarea', null, 'siguiente', null, 'reparto_de_hoy', null,
                              'aviso_salida', null, 'turno', null)
           || motor.seguimiento_de(p_persona, p_ahora);
  end if;
  select * into j from public.jornadas where id = v_jornada;
  -- Tarea 35: pasada la hora del turno abierto, lo no obligatorio en curso se pausa y espera al siguiente turno.
  o := motor.turno_abierto(v_jornada);
  if o.id is not null and motor.pasada_la_hora(v_jornada, p_ahora) then
    perform motor.pausar_fin_de_turno(v_jornada, o.turno);
  end if;

  v_tarea := motor.elegir_tarea(v_jornada, p_ahora, null);
  -- Pedido de cliente: «coge / haz» al salir su tarea (una sola vez).
  if v_tarea is not null
     and exists (select 1 from public.pedidos_cliente where tarea_id = v_tarea)
     and not exists (select 1 from public.tarea_elementos where tarea_id = v_tarea and calculo ? 'calculado_en') then
    perform motor.calcular_pedido(v_tarea, p_ahora);
  end if;
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
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r left join public.personas pe on pe.id = r.pegado_por
       where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
    -- Tarea 29: ha llegado la hora de salida y las bolsas no están: retrasar 15 o 30 min (retrasar_salida).
    -- Tarea 29b: solo si el reparto aún no ha salido, en el turno y con las bolsas ya disponibles.
    'aviso_salida', (
      select jsonb_build_object('texto', 'Es la hora de salida (' || motor.hora_texto(b.hora_limite)
                                         || ') y las bolsas no están listas: retrasa la salida.',
                                'hora_salida', motor.hora_texto(b.hora_limite), 'minutos', '[15, 30]'::jsonb)
        from public.tareas b
       where b.jornada_id = j.id and b.clave = 'bolsas' and b.estado in ('pendiente', 'en_curso', 'bloqueada')
         and b.hora_limite is not null and b.hora_limite <= p_ahora
         and b.disponible_desde <= p_ahora
         and motor.en_turno(j.id, p_ahora)
         and motor.salida_reparto_en(j.id, p_ahora) is null
       limit 1),
    -- Tarea 35: el turno (los botones «Empezar turno» y «Fin de turno», y «Has terminado»).
    'turno', motor.turno_json(j.id, p_ahora, v_tarea))
    || motor.seguimiento_de(p_persona, p_ahora);
end;
$$;

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
  -- Fuera del turno (Tarea 24), lo no obligatorio que se pausó al acabar no vuelve a ponerse en curso:
  -- se puede marcar lo que tenía entre manos, pero la tarea sigue pausada hasta el siguiente turno.
  -- Tarea 35: también pasada la hora del turno abierto.
  if not t.obligatoria and motor.solo_obligatorio(t.jornada_id, p_ahora) then
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

create or replace function motor.terminar_tarea_de(p_persona uuid, p_tarea uuid, p_resultado text, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  t public.tareas;
  j public.jornadas;
  v_pendientes integer;
  v_pedido public.pedidos_cliente;
begin
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado = 'hecha' then
    return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  -- También la pausada al acabar el turno (Tarea 24): lo que tenía entre manos se puede terminar.
  if t.estado <> 'en_curso'
     and not (t.estado = 'pendiente' and not t.obligatoria and t.iniciada_en is not null
              and motor.solo_obligatorio(j.id, p_ahora)) then
    return motor.error('ESTADO_NO_VALIDO', 'Solo se puede terminar una tarea en curso.', jsonb_build_object('estado', t.estado));
  end if;
  select count(*) into v_pendientes from public.tarea_elementos where tarea_id = t.id and estado <> 'hecho';
  if v_pendientes > 0 and nullif(btrim(p_motivo), '') is null then
    return motor.error('ELEMENTOS_PENDIENTES', 'Quedan ' || v_pendientes || ' sin hacer. Escribe el motivo para terminarla así.',
                       jsonb_build_object('pendientes', v_pendientes));
  end if;
  if t.clave = 'pegar_reparto'
     and not exists (select 1 from public.repartos r where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado') then
    select * into v_pedido from motor.pedidos_tienda_esperando(j.id) limit 1;
    if v_pedido.id is not null then
      return motor.error('PEDIDO_ESPERANDO_REPARTO',
                         'Hay un pedido de cliente para recoger en '
                         || (select nombre from public.centros_trabajo where id = v_pedido.destino_id)
                         || ' (' || v_pedido.cliente || '). Prepara el reparto, aunque sea solo con el pedido.',
                         jsonb_build_object('pedido', motor.pedido_json(v_pedido.id)));
    end if;
    if nullif(btrim(p_motivo), '') is null then
      return motor.error('MOTIVO_OBLIGATORIO', 'Todavía no hay reparto. Prepáralo, o escribe el motivo para terminarla así.');
    end if;
  end if;

  update public.tareas
     set estado = 'hecha', terminada_en = p_ahora,
         resultado = nullif(btrim(p_resultado), ''),
         motivo_no_hecha = coalesce(nullif(btrim(p_motivo), ''), motivo_no_hecha)
   where id = t.id and estado in ('en_curso', 'pendiente');
  update public.tarea_elementos set estado = 'pendiente' where tarea_id = t.id and estado = 'en_curso';
  perform motor.registrar('tarea_terminada', p_persona, j.id, t.id,
                          jsonb_build_object('a_las', p_ahora, 'resultado', p_resultado,
                                             'motivo', p_motivo, 'pendientes', v_pendientes));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.pausar_fin_de_turno(p_jornada uuid, p_turno text)
returns integer language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_fin timestamptz;
  t public.tareas;
  n integer := 0;
begin
  select * into j from public.jornadas where id = p_jornada;
  v_fin := motor.hora_fin_turno(p_jornada, p_turno);
  if v_fin is null then
    return 0;
  end if;
  for t in select * from public.tareas where jornada_id = p_jornada and estado = 'en_curso' and not obligatoria loop
    update public.tareas set estado = 'pendiente' where id = t.id;
    perform motor.registrar('tarea_pausada', null, p_jornada, t.id,
                            jsonb_build_object('a_las', v_fin, 'motivo', 'Fin del turno'));
    n := n + 1;
  end loop;
  return n;
end;
$$;

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
                                            else case when exists (select 1 from public.registro_eventos r
                                                                    where r.tarea_id = t.id and r.tipo = 'tarea_pausada'
                                                                      and r.datos ->> 'motivo' = 'Fin del turno')
                                                      then 'Sin terminar: fin del turno' else 'Sin motivo anotado' end end),
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
    -- Tarea 35: cuándo empezó y acabó el turno, y si lo cerró el operario.
    'turno_operario', motor.turno_cierre_json(j.id, p_turno),
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
  -- Tarea 35: cómo empezó y acabó el turno.
  x := c -> 'turno_operario';
  if x is not null then
    t := t || case x ->> 'como'
      when 'sin_empezar' then 'No empezó el turno: no pulsó «Empezar turno».'
      when 'solo' then 'Turno desde las ' || (x ->> 'empezado') || '. No cerrado por el operario: se cerró solo '
                       || case when (x ->> 'al_dia_siguiente')::boolean then 'al acabar el día'
                               else 'a las ' || (x ->> 'terminado') end || '.'
      when 'operario' then 'Turno de ' || (x ->> 'empezado') || ' a ' || (x ->> 'terminado') || '.'
      else 'Turno desde las ' || (x ->> 'empezado') || '.' end || E'\n';
  end if;

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
-- 4. La tarea programada: solo cierra los turnos que se quedaron sin cerrar
-- ---------------------------------------------------------------------------
-- Al acabar el día (a medianoche, hora de Madrid), los turnos de ayer sin cierre se cierran solos: abiertos («no lo
-- cerró el operario») o sin empezar («no empezó el turno»). Ya no se cierra nada a la hora de fin del turno.
create or replace function motor.generar_cierres_programados(p_ahora timestamptz)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select j.id, h.turno
      from public.jornadas j
      join public.personas p on p.id = j.persona_id and p.activo and p.rol <> 'tienda'
      join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
     where j.fecha = motor.fecha_local(p_ahora) - 1
       and not exists (select 1 from public.cierres c where c.jornada_id = j.id and c.turno = h.turno)
     order by j.fecha, h.hora_inicio
  loop
    perform motor.cerrar_turno_almacen(r.id, r.turno, p_ahora, true);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- A las 00:05 de Madrid: 22:05 UTC en verano y 23:05 UTC en invierno. La otra de las dos no encuentra nada que cerrar.
select cron.unschedule('generar_cierres_turno');
select cron.schedule('cerrar_turnos_olvidados', '5 22,23 * * *', $$select motor.generar_cierres_programados(now())$$);

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_empezar_turno_almacen(), motor.api_fin_turno_almacen(boolean) to authenticated;
revoke execute on function public.empezar_turno_almacen(), public.fin_turno_almacen(boolean) from public, anon;
grant execute on function public.empezar_turno_almacen(), public.fin_turno_almacen(boolean) to authenticated;
