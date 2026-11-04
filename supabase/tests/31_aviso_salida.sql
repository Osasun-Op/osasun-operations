-- Prueba 31 · El aviso de salida solo cuando toca (Tarea 29b). El caso del 03/11/2026, rehecho el martes
-- 01/12/2026: las bolsas pendientes con disponible_desde mañana, la salida hecha a las 10:48; a las 19:33
-- a Eder le salía «Es la hora de salida…». Y el caso normal: a las 10:46, sin bolsas y sin salir, el
-- aviso sale. Cuenta y nombres inventados. Transacción deshecha al final.

begin;
-- Tarea 35: estas pruebas son de antes de «Empezar turno». Aquí el turno está abierto de su hora de inicio a la de fin,
-- como si el operario lo empezara y lo terminara a su hora (solo dentro de esta transacción, que se deshace). La 40
-- prueba los botones.
create or replace function motor.en_turno(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.jornadas j
                   join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                  where j.id = p_jornada
                    and p_ahora >= motor.en_local(j.fecha, h.hora_inicio)
                    and p_ahora < motor.en_local(j.fecha, h.hora_fin))
$$;
-- Aísla la prueba de los datos reales de pruebas (tiendas y jornadas del operario). Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;

-- El reparto del martes 01/12, como lo guarda guardar_reparto: Bilbao.
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-01');
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada(op, '2026-12-01');
begin
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-01 08:30+01', terminada_en = '2026-12-01 08:45+01'
   where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto');
  perform public.servidor_guardar_reparto(
    adm, j, 'reparto', E'REPARTO 01/12\nSALE: ALMACÉN\n\nBILBAO\n20x V2 4g', 'h31', '2026-12-01', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 01/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '20x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 20, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 20, 'en_almacen', 0, 'faltan', 20, 'aviso', null, 'orden', 1)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1)))),
    true, '2026-12-01 08:50+01');
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada(op, '2026-12-01');
  v_bolsas public.tareas;
  v_salida public.tareas;
  v_antes jsonb;
  r jsonb;
begin
  select * into v_bolsas from public.tareas where jornada_id = j and clave = 'bolsas';
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-01 09:00+01', terminada_en = '2026-12-01 10:30+01'
   where jornada_id = j and clave = 'produccion_reparto';

  -- 1. El caso normal: a las 10:46, las bolsas sin hacer y el reparto sin salir → el aviso sale.
  r := motor.tarea_activa_de(op, '2026-12-01 10:46+01');
  perform pg_temp.comprobar('10:46, bolsas sin hacer y reparto sin salir: sale el aviso de salida',
    r -> 'aviso_salida' ->> 'hora_salida' = '10:45' and r -> 'tarea' ->> 'id' = v_bolsas.id::text, r::text);

  -- 2. Fuera del turno (13:30, entre turnos), con lo demás igual: sin aviso.
  perform pg_temp.comprobar('Entre turnos (13:30), con las bolsas sin hacer: sin aviso',
    motor.tarea_activa_de(op, '2026-12-01 13:30+01') -> 'aviso_salida' = 'null'::jsonb);

  -- 3. Las bolsas pasadas a mañana (disponible_desde mañana), sin salir: sin aviso.
  update public.tareas set disponible_desde = '2026-12-02 08:30+01' where id = v_bolsas.id;
  perform pg_temp.comprobar('Bolsas con disponible_desde mañana: sin aviso aunque pase su hora límite',
    motor.tarea_activa_de(op, '2026-12-01 10:46+01') -> 'aviso_salida' = 'null'::jsonb);

  -- 4. El caso del 03/11: además, la salida hecha a las 10:48.
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-01 10:48+01', terminada_en = '2026-12-01 12:10+01'
   where jornada_id = j and clave = 'salida_reparto';
  r := motor.tarea_activa_de(op, '2026-12-01 19:33+01');
  perform pg_temp.comprobar('El caso del 03/11 a las 19:33: aviso_salida null', r -> 'aviso_salida' = 'null'::jsonb, r::text);

  -- 5. Con el reparto fuera, aunque las bolsas estén disponibles y en el turno: sin aviso.
  update public.tareas set disponible_desde = v_bolsas.disponible_desde where id = v_bolsas.id;
  perform pg_temp.comprobar('Reparto salido a las 10:48, a las 11:30 (en el turno, bolsas disponibles): sin aviso',
    motor.tarea_activa_de(op, '2026-12-01 11:30+01') -> 'aviso_salida' = 'null'::jsonb);

  -- 6. retrasar_salida con el reparto fuera: ESTADO_NO_VALIDO y ninguna hora se mueve.
  select jsonb_agg(jsonb_build_array(clave, hora_limite, hora_programada, disponible_desde) order by id) into v_antes
    from public.tareas where jornada_id = j;
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-12-01 19:33+01');
  perform pg_temp.comprobar('retrasar_salida con el reparto fuera: ESTADO_NO_VALIDO «El reparto ya ha salido.»',
    r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO' and r -> 'error' ->> 'mensaje' = 'El reparto ya ha salido.', r::text);
  perform pg_temp.comprobar('… sin mover ninguna hora ni registrar el retraso',
    v_antes = (select jsonb_agg(jsonb_build_array(clave, hora_limite, hora_programada, disponible_desde) order by id)
                 from public.tareas where jornada_id = j)
    and not exists (select 1 from public.registro_eventos where jornada_id = j and tipo = 'salida_retrasada'));

  -- 7. Con la salida solo empezada (en curso) también cuenta como salido.
  update public.tareas set estado = 'en_curso', terminada_en = null where jornada_id = j and clave = 'salida_reparto';
  perform pg_temp.comprobar('Salida en curso desde las 10:48: sin aviso y retrasar da ESTADO_NO_VALIDO',
    motor.tarea_activa_de(op, '2026-12-01 10:50+01') -> 'aviso_salida' = 'null'::jsonb
    and motor.retrasar_salida_de(op, gen_random_uuid(), 30, '2026-12-01 10:50+01') -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO');

  -- 8. Sin salir, retrasar sigue como siempre (la salida aún pendiente).
  update public.tareas set estado = 'pendiente', iniciada_en = null where jornada_id = j and clave = 'salida_reparto';
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-12-01 10:47+01');
  perform pg_temp.comprobar('Sin salir, «Retrasar 15 min» sigue igual: la salida a las 11:00',
    r ->> 'nueva_hora_salida' = '11:00' and r -> 'tarea_activa' -> 'aviso_salida' = 'null'::jsonb, r::text);
end;
$$;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
