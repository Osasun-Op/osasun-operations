-- Prueba 20 · Panel de Administración tras la prueba en el almacén (Tarea 15,
-- ESTADO v1.29 §5 R3 y R4, §8 «Administración · Inicio»): el mini se llama MINI,
-- cada tarea de hoy con sus horas y minutos, el tiempo de «Orden y limpieza» y
-- los productos con menos de 2 semanas (la cuenta está en _compartido/r4.ts; aquí,
-- que se guarda con la lectura y que el panel enseña la última). Lunes 14/12/2026.
-- Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.rechazada(p_sql text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
end;
$$;
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.lectura(p_cuando timestamptz, p_correcto boolean) returns uuid language sql as $$
  insert into public.lecturas_sheets (leido_en, motivo, correcto, datos)
  values (p_cuando, 'reparto', p_correcto, '{}') returning id $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  ahora constant timestamptz := '2026-12-14 10:45+01';
  j uuid;
  t1 uuid;
  o1 uuid;
  o2 uuid;
  l1 uuid;
  l2 uuid;
  r jsonb;
  baja constant jsonb := '{"productos": [{"producto": "Invernadero", "formato": "", "total": 154, "necesidad_semana": 202,
                                          "semanas": 0.7, "motivo": "Hay 154 en total y se necesitan 202 a la semana: da para 0,7 semanas."}],
                           "avisos": ["No puedo calcular CBD DRY en PRINCIPAL (CBD DRY: dato vacío o no válido)."]}';
begin
  -- 1. Minis (R3): el producto es MINI 10g, como en la hoja real.
  r := (select valor from public.configuracion where clave = 'stock_excluidos' and centro_id is null);
  perform pg_temp.comprobar('stock_excluidos: el mini es «MINI» 10g (no «MINIBUDS MIX»); los vapers siguen',
    r @> '[{"producto": "MINI", "formato": "10g"}]' and not r @> '[{"producto": "MINIBUDS MIX"}]'
    and r @> '[{"producto": "VAPER", "formato": ""}]' and jsonb_array_length(r) = 2, r::text);

  -- 2. Hoy con horas.
  j := motor.generar_jornada(op, '2026-12-14');
  t1 := (select id from public.tareas where jornada_id = j and hora_programada is not null
          order by hora_programada, orden limit 1);
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-14 08:00+01', terminada_en = '2026-12-14 08:25+01'
   where id = t1;
  -- 3. Tiempo libre: una «Orden y limpieza» hecha (20 min) y la siguiente en curso desde las 10:30.
  o1 := (select t.id from public.tareas t join public.plantillas_tarea p on p.id = t.plantilla_id
          where t.jornada_id = j and p.codigo = 'cola_orden' and t.estado = 'pendiente' limit 1);
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-14 10:00+01', terminada_en = '2026-12-14 10:20+01'
   where id = o1;
  o2 := (select t.id from public.tareas t join public.plantillas_tarea p on p.id = t.plantilla_id
          where t.jornada_id = j and p.codigo = 'cola_orden' and t.estado = 'pendiente' and t.id <> o1 limit 1);
  update public.tareas set estado = 'en_curso', iniciada_en = '2026-12-14 10:30+01' where id = o2;

  r := motor.estado_actual_de(ahora);
  perform pg_temp.comprobar('hoy: una tarea hecha trae su inicio, su fin y los minutos que ha tardado (25)',
    (select x ->> 'minutos' = '25' and (x ->> 'iniciada_en')::timestamptz = '2026-12-14 08:00+01'
            and (x ->> 'terminada_en')::timestamptz = '2026-12-14 08:25+01'
       from jsonb_array_elements(r -> 'hoy') x where x ->> 'id' = t1::text), r -> 'hoy' ->> 0);
  perform pg_temp.comprobar('hoy: la que está en curso cuenta hasta ahora (15) y no tiene fin',
    (select x ->> 'minutos' = '15' and x -> 'terminada_en' = 'null'
       from jsonb_array_elements(r -> 'hoy') x where x ->> 'id' = o2::text), r::text);
  perform pg_temp.comprobar('hoy: una sin empezar, sin horas ni minutos (null)',
    exists (select 1 from jsonb_array_elements(r -> 'hoy') x
             where x ->> 'estado' = 'pendiente' and x -> 'iniciada_en' = 'null' and x -> 'minutos' = 'null'), r::text);
  perform pg_temp.comprobar('hoy: los campos de antes siguen igual',
    (select bool_and(x ?& array['id', 'titulo', 'estado', 'origen', 'obligatoria', 'urgente', 'hora', 'motivo'])
       from jsonb_array_elements(r -> 'hoy') x), r::text);
  perform pg_temp.comprobar('tiempo_libre: 2 veces «Orden y limpieza», 35 minutos (20 + 15 de la que sigue en curso)',
    r -> 'tiempo_libre' = '{"veces": 2, "minutos": 35}', r ->> 'tiempo_libre');
  perform pg_temp.comprobar('tiempo_libre sin jornada: 0 veces y 0 minutos',
    motor.estado_actual_de('2026-12-19 10:00+01') -> 'tiempo_libre' = '{"veces": 0, "minutos": 0}');

  -- 4. Menos de 2 semanas (R4): se guarda con la lectura y el panel enseña la última que la trae.
  perform pg_temp.comprobar('cobertura_baja sin ninguna lectura con cobertura: vacía, sin error',
    motor.estado_actual_de('2000-01-03 10:00+01') -> 'cobertura_baja'
      = '{"datos_leidos_en": null, "productos": [], "avisos": []}');
  l1 := pg_temp.lectura('2026-12-14 08:30+01', true);
  perform public.servidor_guardar_cobertura(l1, baja);
  l2 := pg_temp.lectura('2026-12-14 09:30+01', true);     -- p. ej. un pedido: sin cobertura
  perform public.servidor_guardar_cobertura(pg_temp.lectura('2026-12-14 10:00+01', false), '{"productos": [], "avisos": []}');
  r := motor.estado_actual_de(ahora) -> 'cobertura_baja';
  perform pg_temp.comprobar('cobertura_baja: la de la última lectura que la trae, con su hora (una lectura fallida no guarda nada)',
    (r ->> 'datos_leidos_en')::timestamptz = '2026-12-14 08:30+01'
    and r -> 'productos' = baja -> 'productos' and r -> 'avisos' = baja -> 'avisos'
    and not exists (select 1 from public.lecturas_sheets where not correcto and cobertura is not null
                     and leido_en = '2026-12-14 10:00+01'), r::text);
  perform public.servidor_guardar_cobertura(l2, '{"productos": [], "avisos": []}');
  r := motor.estado_actual_de(ahora) -> 'cobertura_baja';
  perform pg_temp.comprobar('cobertura_baja: una lectura nueva sin productos por debajo deja la lista vacía',
    (r ->> 'datos_leidos_en')::timestamptz = '2026-12-14 09:30+01' and r -> 'productos' = '[]', r::text);
end;
$$;

-- Permisos ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.estado_actual();
begin
  perform pg_temp.comprobar('Administración: estado_actual trae tiempo_libre y cobertura_baja, y sigue con almacen_ahora',
    r ?& array['tiempo_libre', 'cobertura_baja', 'almacen_ahora', 'hoy', 'en_curso', 'lectura_sheets']
    and r -> 'cobertura_baja' ?& array['datos_leidos_en', 'productos', 'avisos'], r::text);
  perform pg_temp.comprobar('Nadie con sesión puede guardar la cobertura (solo el servidor)',
    pg_temp.rechazada($q$select public.servidor_guardar_cobertura(gen_random_uuid(), '{}')$q$));
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.estado_actual();
begin
  perform pg_temp.comprobar('El operario sigue sin poder usar estado_actual (NO_AUTORIZADO)',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO' and not r ? 'cobertura_baja', r::text);
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
