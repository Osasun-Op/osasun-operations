-- Prueba 46 · Una urgente no cede ante una tarea con hora (T-0013 · Tarea 41; ESTADO_DEL_SISTEMA.md §6.4, decisión del
-- 17/11/2026). La tarea en curso solo se pausa si lo que entra va delante de ella en el orden de siempre.
-- El caso del 17/11, rehecho el martes 15/12/2026: una de Administración urgente, sin productos y no obligatoria, en curso
-- cuando vence «Revisa stock en Gipuzkoa/Durango…» (15:30): no se pausa (antes, 8 pausas y 9 inicios en 19 minutos); al
-- terminarla, sale la de hora. Y lo demás de la regla, igual. Cuenta y nombres inventados. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
update public.turnos_tienda set terminado_en = now(), terminado_solo = true
 where persona_tienda_id is null and terminado_en is null
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.a(p_dia date, p_hora text) returns timestamptz language sql as $$
  select motor.en_local(p_dia, p_hora::time) $$;
create function pg_temp.toca(p_dia date, p_hora text) returns text language sql as $$
  select motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a(p_dia, p_hora)) -> 'tarea' ->> 'clave' $$;
create function pg_temp.estado(p_id uuid) returns text language sql as $$ select estado from public.tareas where id = p_id $$;
create function pg_temp.id(p_jornada uuid, p_clave text) returns uuid language sql as $$
  select id from public.tareas where jornada_id = p_jornada and clave = p_clave $$;
create function pg_temp.pausas(p_id uuid) returns bigint language sql as $$
  select count(*) from public.registro_eventos where tarea_id = p_id and tipo = 'tarea_pausada' $$;
-- Una tarea de Administración como la del 17/11: sin productos, no obligatoria; urgente si se dice.
create function pg_temp.admin(p_jornada uuid, p_clave text, p_titulo text, p_desde timestamptz, p_urgente boolean)
returns uuid language sql as $$
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, urgente, obligatoria, creada_por)
  values (p_jornada, p_clave, 'administracion', p_titulo, p_desde, p_urgente, false, '00000000-0000-4000-a000-000000000002')
  returning id $$;
-- Un día de tarde en el que sale Administración: lo de la mañana, hecho; quedan «Revisa stock…» (15:30) y las colas.
create function pg_temp.tarde(p_dia date) returns uuid language plpgsql as $$
declare j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_dia);
begin
  perform prueba.fijar_condicion(j, 'sale', 'administracion');
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(p_dia, '12:00')
   where jornada_id = j and estado = 'pendiente' and clave <> 'revisar_envio' and clave not like 'cola_%';
  perform motor.empezar_turno_almacen_de('00000000-0000-4000-a000-000000000001', pg_temp.a(p_dia, '08:30'));
  -- La tarde: «Empezar turno» a las 15:00 (cierra sola la mañana).
  perform motor.empezar_turno_almacen_de('00000000-0000-4000-a000-000000000001', pg_temp.a(p_dia, '15:00'));
  return j;
end; $$;

-- 1. El caso del 17/11 (martes 15/12)
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  dia constant date := '2026-12-15';
  j uuid := pg_temp.tarde('2026-12-15');
  v_u uuid;
  v_r uuid;
  v_toca text;
  n int := 0;
begin
  v_r := pg_temp.id(j, 'revisar_envio');
  perform pg_temp.comprobar('Preparado: «Revisa stock en Gipuzkoa/Durango…» con hora a las 15:30',
    (select hora_programada from public.tareas where id = v_r) = pg_temp.a(dia, '15:30'));
  v_u := pg_temp.admin(j, 'admin:recoger', 'Recoger cajas en el proveedor', pg_temp.a(dia, '15:00'), true);
  perform pg_temp.comprobar('15:20: la urgente de Administración', pg_temp.toca(dia, '15:20') = 'admin:recoger', pg_temp.toca(dia, '15:20'));
  perform motor.iniciar_tarea_de(op, v_u, pg_temp.a(dia, '15:20'));
  -- La pantalla pide la tarea activa cada minuto: de 15:30 a 15:58, como el 17/11.
  for i in 30..58 loop
    v_toca := pg_temp.toca(dia, '15:' || i);
    if v_toca is distinct from 'admin:recoger' then n := n + 1; end if;
  end loop;
  perform pg_temp.comprobar('De 15:30 a 15:58, cada minuto: sigue la urgente, en curso, sin pausarse (el bucle del 17/11, arreglado)',
    n = 0 and pg_temp.estado(v_u) = 'en_curso' and pg_temp.pausas(v_u) = 0
    and (select count(*) from public.registro_eventos where tarea_id = v_u and tipo = 'tarea_iniciada') = 1,
    n || ' minutos con otra; pausas: ' || pg_temp.pausas(v_u));
  perform motor.terminar_tarea_de(op, v_u, null, null, pg_temp.a(dia, '15:59'));
  perform pg_temp.comprobar('15:59, al terminarla: sale la de hora', pg_temp.toca(dia, '15:59') = 'revisar_envio',
    pg_temp.toca(dia, '15:59'));
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(dia, '16:00') where id = v_r;

  -- 2. Una urgente en curso y llega «Llama a Administración» por un problema (escalón 2): se pausa.
  v_u := pg_temp.admin(j, 'admin:urgente2', 'Lleva el paquete a la oficina', pg_temp.a(dia, '16:00'), true);
  perform motor.iniciar_tarea_de(op, v_u, pg_temp.a(dia, '16:01'));
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde)
  values (j, 'problema:llamada', 'problema', 'Llama a Administración', pg_temp.a(dia, '16:10'));
  v_toca := pg_temp.toca(dia, '16:10');
  perform pg_temp.comprobar('16:10: una urgente en curso cede ante «Llama a Administración» (un problema va delante)',
    v_toca = 'problema:llamada' and pg_temp.estado(v_u) = 'pendiente' and pg_temp.pausas(v_u) = 1, v_toca);
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(dia, '16:12') where clave = 'problema:llamada' and jornada_id = j;
  perform pg_temp.comprobar('16:12: después, vuelve la urgente', pg_temp.toca(dia, '16:12') = 'admin:urgente2', pg_temp.toca(dia, '16:12'));

  -- 3. Una urgente en curso y llega otra urgente: no se pausa (mismo escalón).
  perform motor.iniciar_tarea_de(op, v_u, pg_temp.a(dia, '16:12'));
  perform pg_temp.admin(j, 'admin:urgente3', 'Otra urgente', pg_temp.a(dia, '16:15'), true);
  v_toca := pg_temp.toca(dia, '16:16');
  perform pg_temp.comprobar('16:16: con otra urgente, la urgente en curso no se pausa',
    v_toca = 'admin:urgente2' and pg_temp.estado(v_u) = 'en_curso' and pg_temp.pausas(v_u) = 1, v_toca);
  perform motor.terminar_tarea_de(op, v_u, null, null, pg_temp.a(dia, '16:20'));
  perform pg_temp.comprobar('16:20: al terminarla, la otra urgente', pg_temp.toca(dia, '16:20') = 'admin:urgente3',
    pg_temp.toca(dia, '16:20'));
end;
$$;

-- 4. Una incidencia «Varios → ahora» del operario en curso, y vence una con hora (miércoles 16/12): no se pausa
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  dia constant date := '2026-12-16';
  j uuid := pg_temp.tarde('2026-12-16');
  r jsonb;
  v_v uuid;
  v_toca text;
begin
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'varios', 'Mover el palé de cajas vacías', 'operario', 'ahora',
                                 null, null, null, pg_temp.a(dia, '15:20'));
  v_v := (r -> 'tarea' ->> 'id')::uuid;
  perform pg_temp.comprobar('15:20: la de «Varios → ahora» es urgente y sale',
    (select urgente from public.tareas where id = v_v) and pg_temp.toca(dia, '15:20') = (select clave from public.tareas where id = v_v),
    r::text);
  perform motor.iniciar_tarea_de(op, v_v, pg_temp.a(dia, '15:21'));
  v_toca := pg_temp.toca(dia, '15:31');
  perform pg_temp.comprobar('15:31: vence «Revisa stock…», pero la incidencia en curso no se pausa',
    v_toca = (select clave from public.tareas where id = v_v) and pg_temp.estado(v_v) = 'en_curso' and pg_temp.pausas(v_v) = 0, v_toca);
  perform motor.terminar_tarea_de(op, v_v, null, null, pg_temp.a(dia, '15:40'));
  perform pg_temp.comprobar('15:40: al terminarla, sale la de hora', pg_temp.toca(dia, '15:40') = 'revisar_envio',
    pg_temp.toca(dia, '15:40'));
end;
$$;

-- 5. «Orden y limpieza» sigue cediendo ante lo que tiene hora y ante lo urgente (jueves 17/12)
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  dia constant date := '2026-12-17';
  j uuid := pg_temp.tarde('2026-12-17');
  v_o uuid := (select id from public.tareas where jornada_id = j and clave like 'cola_orden%' and estado = 'pendiente' limit 1);
  v_u uuid;
  v_toca text;
begin
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(dia, '12:00')
   where jornada_id = j and estado = 'pendiente' and clave like 'cola_%' and id <> v_o;
  perform pg_temp.comprobar('15:00: sin nada más, «Orden y limpieza»', pg_temp.toca(dia, '15:00') like 'cola_orden%', pg_temp.toca(dia, '15:00'));
  perform motor.iniciar_tarea_de(op, v_o, pg_temp.a(dia, '15:00'));
  v_u := pg_temp.admin(j, 'admin:urgente', 'Una urgente', pg_temp.a(dia, '15:10'), true);
  v_toca := pg_temp.toca(dia, '15:10');
  perform pg_temp.comprobar('15:10: «Orden y limpieza» cede ante lo urgente',
    v_toca = 'admin:urgente' and pg_temp.estado(v_o) = 'pendiente' and pg_temp.pausas(v_o) = 1, v_toca);
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.a(dia, '15:15') where id = v_u;
  perform motor.iniciar_tarea_de(op, v_o, pg_temp.a(dia, '15:16'));
  v_toca := pg_temp.toca(dia, '15:30');
  perform pg_temp.comprobar('15:30: y ante lo que tiene hora',
    v_toca = 'revisar_envio' and pg_temp.estado(v_o) = 'pendiente' and pg_temp.pausas(v_o) = 2, v_toca);
end;
$$;

-- 6. Una sola regla
select pg_temp.comprobar('Una sola regla: tras_elemento y tarea_activa_de usan motor.pausar_si_toca, que compara los escalones',
  (select prosrc from pg_proc where oid = 'motor.tras_elemento(uuid, uuid, boolean, timestamptz)'::regprocedure) like '%motor.pausar_si_toca(%'
  and (select prosrc from pg_proc where oid = 'motor.tarea_activa_de(uuid, timestamptz)'::regprocedure) like '%motor.pausar_si_toca(%'
  and (select prosrc from pg_proc where oid = 'motor.pausar_si_toca(uuid, uuid, timestamptz)'::regprocedure) like '%v_escalon >= motor.escalon(v_pendiente)%'
  and not has_function_privilege('authenticated', 'motor.pausar_si_toca(uuid, uuid, timestamptz)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
