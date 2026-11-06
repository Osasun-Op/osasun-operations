-- Tarea 37 · Lo que tiene hora entra también entre dos referencias (ESTADO_DEL_SISTEMA.md §6.4, v1.68, primer punto;
-- propietario, 06/11/2026). Solo en pruebas: producción espera.
-- El 06/11 Eder terminó la referencia V2 del +35 % a las 10:43 y no empezó otra; la salida (10:45) no le saltó hasta
-- que cerró el +35 % a las 12:22. El paso a lo que tiene hora solo se miraba al terminar una referencia (punto de
-- encaje, motor.tras_elemento), y elegir_tarea deja siempre primero lo que está en curso.
--   1. Al pedir la tarea activa (la pantalla la pide cada minuto y al volver), si la tarea en curso no es obligatoria y
--      no tiene ninguna referencia empezada, se hace la misma comprobación que al terminar una referencia: si ya toca algo
--      de escalón 2–4 (un problema, lo urgente, lo que tiene hora), se pausa como ahora (lo hecho se guarda; en «Hoy»
--      consta la interrupción) y sale lo que toca.
--   2. Una sola regla: la de tras_elemento pasa a motor.pausar_si_toca, y la usan tras_elemento y tarea_activa_de.
--   3. No cambia: a mitad de una referencia, lo que tiene hora entra al terminarla; lo obligatorio en curso no se pausa;
--      las bolsas, la salida solo con las bolsas hechas y los turnos (Tareas 29 y 35).
--
-- Deshacer: volver a crear motor.tras_elemento como está en 20261102153923 y motor.tarea_activa_de como está en
-- 20261104231512; borrar motor.pausar_si_toca.

-- La regla del punto de encaje (antes, dentro de tras_elemento): si la tarea está en curso y ya toca algo de escalón
-- 2–4, se pausa (vuelve a pendiente con lo hecho) y queda la interrupción con lo que entra. Devuelve si la ha pausado.
create or replace function motor.pausar_si_toca(p_persona uuid, p_tarea uuid, p_ahora timestamptz)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_otra uuid;
begin
  select * into t from public.tareas where id = p_tarea;
  if t.estado is distinct from 'en_curso' then
    return false;
  end if;
  v_otra := motor.elegir_tarea(t.jornada_id, p_ahora, p_tarea);
  if v_otra is null
     or not (select motor.escalon(o) in (2, 3, 4) from public.tareas o where o.id = v_otra) then
    return false;
  end if;
  update public.tareas set estado = 'pendiente' where id = p_tarea;
  perform motor.registrar('tarea_pausada', p_persona, t.jornada_id, p_tarea,
                          jsonb_build_object('a_las', p_ahora, 'entra', v_otra));
  return true;
end;
$$;

create or replace function motor.tras_elemento(p_persona uuid, p_tarea uuid, p_punto_de_encaje boolean, p_ahora timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_cajas integer;
begin
  select * into t from public.tareas where id = p_tarea;
  -- «pendiente»: la pausada al acabar el turno, en la que aún se marca lo que tenía entre manos.
  if t.estado not in ('en_curso', 'pendiente') then
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

  -- Punto de encaje: si ya toca lo de escalón 2–4, la tarea se pausa (la regla, en motor.pausar_si_toca; Tarea 37).
  if p_punto_de_encaje then
    perform motor.pausar_si_toca(p_persona, p_tarea, p_ahora);
  end if;
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
  c public.tareas;
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
  -- Tarea 37: lo que tiene hora entra también sin ninguna referencia empezada (entre dos referencias de una tarea no
  -- obligatoria, como el +35 %, o en una no obligatoria sin referencias, como «Orden y limpieza»): la misma comprobación
  -- que al terminar una referencia (motor.pausar_si_toca). A mitad de una referencia, espera a que la termine.
  select * into c from public.tareas t
   where t.jornada_id = v_jornada and t.estado = 'en_curso' and not t.obligatoria
     and not exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.estado = 'en_curso')
   limit 1;
  if c.id is not null then
    perform motor.pausar_si_toca(p_persona, c.id, p_ahora);
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

revoke execute on all functions in schema motor from public;
