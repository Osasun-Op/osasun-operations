-- Prueba 28 · Tiendas, primera parte (Tarea 27; ESTADO_DEL_SISTEMA.md E2-8).
-- Acceso de tienda con su cuenta (rol tienda), horario por tienda, días cerrados, personas y
-- quién está en el turno, la lista del día con sus horas y sus puntos, el vídeo de la semana,
-- los avisos de Administración y los permisos. Y que el almacén sigue igual.
-- Cuentas y nombres inventados (@osasun.invalid). Semana del lunes 14/12/2026 (ISO 51, impar)
-- y jueves 24/12/2026 (ISO 52, par). Transacción deshecha al final.

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.a(p_fecha date, p_hora time) returns timestamptz language sql as $$ select motor.en_local(p_fecha, p_hora) $$;
create function pg_temp.tareas(r jsonb) returns text language sql as $$
  select string_agg((x ->> 'clave') || '@' || (x ->> 'hora'), ' ' order by x ->> 'hora', x ->> 'clave')
  from jsonb_array_elements(r -> 'tareas') x $$;
create function pg_temp.tarea(r jsonb, p_clave text) returns jsonb language sql as $$
  select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' like p_clave limit 1 $$;
create function pg_temp.dia(p_persona uuid, p_fecha date) returns text language plpgsql as $$
declare v_j uuid := motor.generar_jornada(p_persona, p_fecha);
begin
  return (select string_agg(t.clave || '@' || motor.hora_texto(t.disponible_desde), ' ' order by t.disponible_desde, t.clave)
            from public.tareas t where t.jornada_id = v_j and t.estado <> 'cancelada');
end; $$;

-- Cuentas de tienda (inventadas) y personas de la ficha de pruebas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.bilbao@osasun.invalid", "nombre": "Bilbao", "rol": "tienda", "centro": "BILBAO"},
  {"correo": "tienda.donosti@osasun.invalid", "nombre": "Donosti", "rol": "tienda", "centro": "DONOSTI"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.bilbao@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000003', 'tienda.donosti@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000004', 'tienda.portu@osasun.invalid')) x(id, correo);

-- Almacén antes de nada (para comparar al final). Las jornadas se generan en su propia sentencia:
-- una consulta no ve las tareas que se crean dentro de ella misma.
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-14');
create temp table _almacen as
select t.clave, t.disponible_desde, t.hora_programada, t.hora_limite, t.obligatoria, t.no_terminada, t.contenido
  from public.tareas t where t.jornada_id = motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-14');
grant all on _almacen to authenticated;

do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  r jsonb;
  v_j uuid;
begin
  -- Acceso y horario
  perform pg_temp.comprobar('Alta: cada cuenta de tienda es rol tienda, con su tienda y el horario de su tienda (12, 12 y 11 franjas)',
    (select count(*) from public.personas p join public.centros_trabajo c on c.id = p.centro_id
      where p.rol = 'tienda' and ((p.id = basauri and c.codigo = 'BASAURI') or (p.id = bilbao and c.codigo = 'BILBAO')
                                  or (p.id = donosti and c.codigo = 'DONOSTI') or (p.id = portu and c.codigo = 'PORTU'))) = 4
    and (select count(*) from public.horarios where persona_id = basauri) = 12
    and (select count(*) from public.horarios where persona_id = bilbao) = 12
    and (select count(*) from public.horarios where persona_id = donosti) = 11);
  perform pg_temp.comprobar('Horario: sábado de Basauri 11:00–13:30 y 17:00–19:30; Bilbao por la tarde desde las 16:30',
    (select string_agg(turno || ' ' || to_char(hora_inicio, 'HH24:MI') || '-' || to_char(hora_fin, 'HH24:MI'), ', ' order by hora_inicio)
       from public.horarios where persona_id = basauri and dia_semana = 6) = 'manana 11:00-13:30, tarde 17:00-19:30'
    and (select hora_inicio from public.horarios where persona_id = bilbao and dia_semana = 2 and turno = 'tarde') = '16:30');

  -- El día de cada tienda
  perform pg_temp.comprobar('Lunes en Basauri: apertura 10:50, cierre de la mañana 13:20, apertura de la tarde 16:50, cierre del día 20:20',
    pg_temp.dia(basauri, '2026-12-14') = 'apertura_manana@10:50 cierre_manana@13:20 apertura_tarde@16:50 cierre_dia@20:20',
    pg_temp.dia(basauri, '2026-12-14'));
  v_j := motor.generar_jornada(basauri, '2026-12-14');
  perform pg_temp.comprobar('Cada tarea con sus puntos (5, 2, 4 y 4) y sin pasar al día siguiente',
    (select string_agg(t.clave || ':' || (select count(*) from public.tarea_elementos e where e.tarea_id = t.id and e.tipo = 'punto'), ' '
                       order by t.disponible_desde)
       from public.tareas t where t.jornada_id = v_j) = 'apertura_manana:5 cierre_manana:2 apertura_tarde:4 cierre_dia:4'
    and not exists (select 1 from public.tareas where jornada_id = v_j and no_terminada <> 'nada'));
  perform pg_temp.comprobar('Bilbao: apertura de la tarde 16:20; cierre del día 20:20 también el sábado',
    pg_temp.dia(bilbao, '2026-12-14') = 'apertura_manana@10:50 cierre_manana@13:20 apertura_tarde@16:20 cierre_dia@20:20'
    and pg_temp.dia(bilbao, '2026-12-19') like '%cierre_dia@20:20%', pg_temp.dia(bilbao, '2026-12-19'));
  perform pg_temp.comprobar('Sábado en Basauri: cierre del día a las 19:20',
    pg_temp.dia(basauri, '2026-12-19') = 'apertura_manana@10:50 cierre_manana@13:20 apertura_tarde@16:50 cierre_dia@19:20',
    pg_temp.dia(basauri, '2026-12-19'));
  perform pg_temp.comprobar('Jueves: limpieza de cristales por la tarde (Basauri 17:00)',
    pg_temp.dia(basauri, '2026-12-17') like '%limpieza_cristales@17:00%', pg_temp.dia(basauri, '2026-12-17'));
  perform pg_temp.comprobar('Bilbao alterna las semanales: semana impar (51) por la tarde, semana par (52) por la mañana',
    pg_temp.dia(bilbao, '2026-12-17') like '%limpieza_cristales@16:30%'
    and pg_temp.dia(bilbao, '2026-12-24') like '%limpieza_cristales@11:00%'
    and pg_temp.dia(bilbao, '2026-12-18') like '%video_semana@16:30%',
    pg_temp.dia(bilbao, '2026-12-17') || ' / ' || pg_temp.dia(bilbao, '2026-12-24'));
  perform motor.generar_jornada(basauri, '2026-12-18');
  perform pg_temp.comprobar('Viernes: vídeo de la semana por la mañana (Basauri 11:00), con el texto aprobado',
    pg_temp.dia(basauri, '2026-12-18') like '%video_semana@11:00%'
    and (select porque from public.tareas t where t.jornada_id = motor.generar_jornada(basauri, '2026-12-18') and t.clave = 'video_semana')
        like 'Busca y mira un vídeo sobre nuestro sector: cannabis y CBD,%para recomendarlo a compañeros y clientes.',
    pg_temp.dia(basauri, '2026-12-18'));
  perform pg_temp.comprobar('Franquicia (Donosti): sin aperturas ni cierres; el viernes, solo el vídeo; el sábado no abre por la tarde',
    pg_temp.dia(donosti, '2026-12-14') is null and pg_temp.dia(donosti, '2026-12-18') = 'video_semana@11:00'
    and not exists (select 1 from public.horarios where persona_id = donosti and dia_semana = 6 and turno = 'tarde'),
    coalesce(pg_temp.dia(donosti, '2026-12-14'), '-') || ' / ' || coalesce(pg_temp.dia(donosti, '2026-12-18'), '-'));
  perform pg_temp.comprobar('Domingo: nada', motor.generar_jornada(basauri, '2026-12-20') is null);

  -- Días cerrados
  r := motor.marcar_dia_cerrado_de(admin, '2026-12-15', (select id from public.centros_trabajo where codigo = 'BASAURI'),
                                   true, 'Fiesta local', pg_temp.a('2026-12-01', '10:00'));
  perform pg_temp.comprobar('Día cerrado para una tienda: ese día no tiene jornada; las demás, sí',
    motor.generar_jornada(basauri, '2026-12-15') is null and motor.generar_jornada(portu, '2026-12-15') is not null
    and r -> 'dias' @> '[{"fecha": "2026-12-15", "tienda": "Basauri", "motivo": "Fiesta local"}]', r::text);
  perform motor.marcar_dia_cerrado_de(admin, '2026-12-16', null, true, 'Festivo', pg_temp.a('2026-12-01', '10:00'));
  perform motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-16');
  perform pg_temp.comprobar('Día cerrado para todas: ninguna tienda tiene jornada; el almacén, sí, con sus tareas de siempre',
    motor.generar_jornada(bilbao, '2026-12-16') is null and motor.generar_jornada(portu, '2026-12-16') is null
    and (select count(*) from public.tareas where jornada_id = motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-16')) > 5);
  perform motor.marcar_dia_cerrado_de(admin, '2026-12-16', null, false, null, pg_temp.a('2026-12-01', '10:00'));
  perform pg_temp.comprobar('Quitar el día cerrado: vuelve a ser un día normal',
    motor.generar_jornada(bilbao, '2026-12-16') is not null);
  v_j := motor.generar_jornada(portu, '2026-12-17');
  perform motor.marcar_dia_cerrado_de(admin, '2026-12-17', (select id from public.centros_trabajo where codigo = 'PORTU'),
                                      true, null, pg_temp.a('2026-12-01', '10:00'));
  perform pg_temp.comprobar('Marcado con la jornada ya hecha: sus tareas se cancelan («Tienda cerrada ese día»)',
    not exists (select 1 from public.tareas where jornada_id = v_j and estado = 'pendiente')
    and exists (select 1 from public.tareas where jornada_id = v_j and motivo_no_hecha = 'Tienda cerrada ese día'));
  perform motor.marcar_dia_cerrado_de(admin, '2026-12-17', (select id from public.centros_trabajo where codigo = 'PORTU'),
                                      false, null, pg_temp.a('2026-12-01', '10:00'));
  perform pg_temp.comprobar('Y al quitarlo, vuelven a estar pendientes',
    (select count(*) from public.tareas where jornada_id = v_j and estado = 'pendiente') = 5);
  r := motor.marcar_dia_cerrado_de(admin, '2026-11-01', null, true, null, pg_temp.a('2026-12-01', '10:00'));
  perform pg_temp.comprobar('No se marca un día pasado', r -> 'error' ->> 'codigo' = 'FECHA_PASADA', r::text);
end;
$$;

-- Personas de las tiendas (Administración)
do $$
declare
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  r jsonb;
begin
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BASAURI'), 'Ane Prueba', 'siempre', null, true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'PORTU'), 'Iker Prueba', 'entre_semana', null, true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'PORTU'), 'Nora Prueba', 'sabados', null, true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BILBAO'), 'Leire Prueba', 'siempre', 'manana', true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BILBAO'), 'Unai Prueba', 'siempre', 'tarde', true);
  r := motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BILBAO'), 'Temporal', 'siempre', null, true);
  perform motor.guardar_persona_tienda_de(admin, (r -> 'persona' ->> 'id')::uuid, null, 'Temporal', null, null, false);
  perform pg_temp.comprobar('Administración añade y quita nombres: Bilbao tiene 2 (el quitado ya no sale)',
    jsonb_array_length(motor.personas_tienda_de((select id from public.centros_trabajo where codigo = 'BILBAO')) -> 'personas') = 2);
  r := motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'ALMACEN'), 'X', null, null, true);
  perform pg_temp.comprobar('Solo en tiendas, y con nombre',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BILBAO'), '  ', null, null, true)
        -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
end;
$$;

-- La lista del día en la tablet (lunes 14/12, Basauri)
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  ane uuid := (select id from public.personas_tienda where nombre = 'Ane Prueba');
  r jsonb;
  p jsonb;
begin
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '10:40'));
  perform pg_temp.comprobar('tienda_hoy: todas las tareas del día con su hora; ninguna se puede marcar antes de su hora',
    pg_temp.tareas(r) = 'apertura_manana@10:50 cierre_manana@13:20 apertura_tarde@16:50 cierre_dia@20:20'
    and not exists (select 1 from jsonb_array_elements(r -> 'tareas') x where (x ->> 'se_puede_marcar')::boolean)
    and r -> 'tienda' ->> 'codigo' = 'BASAURI' and r ->> 'turno' = 'manana' and r -> 'en_turno' = 'null'
    and r -> 'personas' -> 0 ->> 'nombre' = 'Ane Prueba', r::text);
  p := pg_temp.tarea(r, 'apertura_manana') -> 'puntos' -> 0;
  r := motor.marcar_punto_de(basauri, (p ->> 'id')::uuid, pg_temp.a('2026-12-14', '10:45'));
  perform pg_temp.comprobar('Antes de su hora no se marca («Esta tarea es desde las 10:50»)',
    r -> 'error' ->> 'codigo' = 'TODAVIA_NO' and r -> 'error' ->> 'mensaje' = 'Esta tarea es desde las 10:50.', r::text);
  r := motor.marcar_punto_de(basauri, (p ->> 'id')::uuid, pg_temp.a('2026-12-14', '10:52'));
  perform pg_temp.comprobar('Sin elegir quién está, tampoco', r -> 'error' ->> 'codigo' = 'SIN_PERSONA', r::text);
  r := motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-14', '10:52'));
  perform pg_temp.comprobar('Al empezar el turno elige su nombre: queda quién está',
    r -> 'en_turno' ->> 'nombre' = 'Ane Prueba' and r -> 'en_turno' ->> 'turno' = 'manana', r -> 'en_turno' ->> 'nombre');
  r := motor.empezar_turno_tienda_de(basauri, (select id from public.personas_tienda where nombre = 'Leire Prueba'), pg_temp.a('2026-12-14', '10:52'));
  perform pg_temp.comprobar('Una persona de otra tienda no se puede elegir', r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  for p in select x from jsonb_array_elements(pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '10:53')), 'apertura_manana') -> 'puntos') x loop
    r := motor.marcar_punto_de(basauri, (p ->> 'id')::uuid, pg_temp.a('2026-12-14', '10:58'));
  end loop;
  p := pg_temp.tarea(r, 'apertura_manana');
  perform pg_temp.comprobar('Al tocar el último punto la tarea queda hecha, hecha por quien está (Ane)',
    p ->> 'estado' = 'hecha' and p ->> 'hecha_por' = 'Ane Prueba' and p ->> 'hora_fin' = '10:58'
    and not exists (select 1 from jsonb_array_elements(p -> 'puntos') x where not (x ->> 'hecho')::boolean or x ->> 'hecho_por' <> 'Ane Prueba'),
    p::text);
  perform pg_temp.comprobar('Queda en el registro, como en el almacén (tarea_terminada de la cuenta de la tienda)',
    exists (select 1 from public.registro_eventos e where e.tarea_id = (p ->> 'id')::uuid and e.tipo = 'tarea_terminada'
              and e.persona_id = basauri and e.datos ->> 'hecha_por' = 'Ane Prueba'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '20:45'));
  perform pg_temp.comprobar('Al cerrar, lo que no se ha hecho queda como no hecho',
    (pg_temp.tarea(r, 'cierre_manana') ->> 'no_hecha')::boolean and not (pg_temp.tarea(r, 'apertura_manana') ->> 'no_hecha')::boolean, r::text);
  perform pg_temp.comprobar('Y no pasa al día siguiente: el martes, solo las 4 del martes',
    pg_temp.tareas(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-15', '10:40'))) is null  -- el martes está cerrado (fiesta local)
    and pg_temp.dia('00000000-0000-4000-b000-000000000001', '2026-12-17') like 'apertura_manana@10:50 cierre_manana@13:20 apertura_tarde@16:50 limpieza_cristales@17:00 cierre_dia@20:20');
  r := motor.terminar_tarea_tienda_de(basauri, (pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '13:25')), 'cierre_manana') ->> 'id')::uuid,
                                      pg_temp.a('2026-12-14', '13:25'));
  perform pg_temp.comprobar('Una tarea con puntos no se cierra con «Hecho»: se tocan sus puntos', r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
  perform pg_temp.comprobar('Bilbao por la tarde sugiere primero a quien trabaja por la tarde',
    motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-14', '16:25')) -> 'personas' -> 0 ->> 'nombre' = 'Unai Prueba');
end;
$$;

-- Limpieza de cristales y vídeo de la semana
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  ane uuid := (select id from public.personas_tienda where nombre = 'Ane Prueba');
  iker uuid := (select id from public.personas_tienda where nombre = 'Iker Prueba');
  nora uuid := (select id from public.personas_tienda where nombre = 'Nora Prueba');
  r jsonb;
  v_t uuid;
begin
  perform motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-17', '16:55'));
  r := motor.terminar_tarea_tienda_de(basauri, (pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-17', '17:10')), 'limpieza_cristales') ->> 'id')::uuid,
                                      pg_temp.a('2026-12-17', '17:10'));
  perform pg_temp.comprobar('Limpieza de cristales: «Hecho»', pg_temp.tarea(r, 'limpieza_cristales') ->> 'estado' = 'hecha', r::text);

  -- Viernes: Basauri comparte; Portugalete no ha podido.
  perform motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-18', '10:55'));
  v_t := (pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-18', '11:05')), 'video_semana') ->> 'id')::uuid;
  r := motor.compartir_video_de(basauri, v_t, 'https://www.vimeo.com/123456', 'Algo', false, pg_temp.a('2026-12-18', '11:30'));
  perform pg_temp.comprobar('Vídeo: tiene que ser un enlace de YouTube', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.compartir_video_de(basauri, v_t, 'https://youtu.be/dQw4w9WgXcQ', '   ', false, pg_temp.a('2026-12-18', '11:30'));
  perform pg_temp.comprobar('Y con una línea de lo aprendido', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.compartir_video_de(basauri, v_t, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
                                E'Los terpenos dan\n el olor y el sabor', false, pg_temp.a('2026-12-18', '11:30'));
  perform pg_temp.comprobar('Compartido: la tarea queda hecha por quien está, con el enlace y lo aprendido en una línea',
    pg_temp.tarea(r, 'video_semana') ->> 'estado' = 'hecha' and pg_temp.tarea(r, 'video_semana') ->> 'hecha_por' = 'Ane Prueba'
    and pg_temp.tarea(r, 'video_semana') -> 'video' ->> 'aprendido' = 'Los terpenos dan el olor y el sabor', r::text);
  perform motor.empezar_turno_tienda_de(portu, iker, pg_temp.a('2026-12-18', '10:55'));
  v_t := (pg_temp.tarea(motor.tienda_hoy_de(portu, pg_temp.a('2026-12-18', '12:00')), 'video_semana') ->> 'id')::uuid;
  r := motor.compartir_video_de(portu, v_t, null, null, true, pg_temp.a('2026-12-18', '13:00'));
  perform pg_temp.comprobar('«Hoy no he podido»: la cierra sin enlace (no hecha, sin pasar al día siguiente)',
    pg_temp.tarea(r, 'video_semana') ->> 'estado' = 'cancelada' and pg_temp.tarea(r, 'video_semana') ->> 'motivo' = 'Hoy no he podido'
    and pg_temp.tarea(r, 'video_semana') ->> 'hecha_por' = 'Iker Prueba', r::text);

  -- Sábado
  r := motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-19', '10:55'));
  perform pg_temp.comprobar('Sábado: a quien ya compartió esa semana (Ane) no le sale otro', pg_temp.tarea(r, 'video_semana%') is null, r::text);
  r := motor.empezar_turno_tienda_de(portu, iker, pg_temp.a('2026-12-19', '10:55'));
  perform pg_temp.comprobar('Sábado: a quien no pudo el viernes (Iker) no le vuelve a salir', pg_temp.tarea(r, 'video_semana%') is null, r::text);
  r := motor.empezar_turno_tienda_de(portu, nora, pg_temp.a('2026-12-19', '11:10'));
  perform pg_temp.comprobar('Sábado: a quien trabaja y no ha compartido esa semana (Nora) le sale, ya',
    (pg_temp.tarea(r, 'video_semana%') ->> 'se_puede_marcar')::boolean, r::text);
  r := motor.compartir_video_de(portu, (pg_temp.tarea(r, 'video_semana%') ->> 'id')::uuid, 'https://youtu.be/abcdefghijk',
                                'Cómo se hace una extracción en frío', false, pg_temp.a('2026-12-19', '12:00'));
  r := motor.videos_semana_de(null);
  perform pg_temp.comprobar('Lista de vídeos: los compartidos, los más nuevos primero, con tienda y persona (sin los «no he podido»)',
    jsonb_array_length(r -> 'videos') = 2
    and r -> 'videos' -> 0 ->> 'tienda' = 'Portugalete' and r -> 'videos' -> 0 ->> 'persona' = 'Nora Prueba'
    and r -> 'videos' -> 1 ->> 'tienda' = 'Basauri' and r -> 'videos' -> 1 ->> 'enlace' = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', r::text);
end;
$$;

-- Avisos de Administración a las tiendas
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  v_ops integer := (select count(*) from public.incidencias where persona_id = op);
  r jsonb;
  v_cli uuid := gen_random_uuid();
begin
  r := motor.crear_aviso_tienda_de(admin, gen_random_uuid(), '2026-12-14', 'Hoy viene el técnico del TPV',
                                   (select id from public.centros_trabajo where codigo = 'BASAURI'), pg_temp.a('2026-12-14', '09:00'));
  perform pg_temp.comprobar('Aviso a una tienda: la tienda lo ve al entrar; otra, no',
    jsonb_array_length(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '10:40')) -> 'avisos') = 1
    and jsonb_array_length(motor.tienda_hoy_de(portu, pg_temp.a('2026-12-14', '10:40')) -> 'avisos') = 0, r::text);
  r := motor.crear_aviso_tienda_de(admin, v_cli, '2026-12-14', 'Mañana cambia el precio del aceite', null, pg_temp.a('2026-12-14', '09:00'));
  perform pg_temp.comprobar('Aviso a todas: las 4 con cuenta (franquicia incluida); las que aún no han entrado, aparte',
    jsonb_array_length(r -> 'avisos') = 4
    and r -> 'sin_aviso' @> '[{"tienda": "Algorta"}, {"tienda": "Barakaldo"}, {"tienda": "Rentería"}]'
    and not (r -> 'sin_aviso') @> '[{"tienda": "Durango"}]', r::text);
  r := motor.crear_aviso_tienda_de(admin, v_cli, '2026-12-14', 'Mañana cambia el precio del aceite', null, pg_temp.a('2026-12-14', '09:01'));
  perform pg_temp.comprobar('Repetir la misma petición no lo duplica',
    (select count(*) from public.incidencias where descripcion = 'Mañana cambia el precio del aceite') = 4);
  r := motor.crear_aviso_tienda_de(admin, gen_random_uuid(), '2026-12-15', 'Para el martes', null, pg_temp.a('2026-12-14', '09:00'));
  perform pg_temp.comprobar('Un aviso para otro día no sale antes; la tienda cerrada ese día no lo recibe',
    jsonb_array_length(motor.tienda_hoy_de(portu, pg_temp.a('2026-12-14', '10:40')) -> 'avisos') = 1
    and r -> 'sin_aviso' @> '[{"tienda": "Basauri", "motivo": "Ese día no abre"}]', r::text);
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-14', '11:00'));
  r := motor.marcar_aviso_leido_de(basauri, (r -> 'avisos' -> 0 ->> 'id')::uuid, pg_temp.a('2026-12-14', '11:01'));
  perform pg_temp.comprobar('Leído: ya no sale y queda quién lo leyó',
    jsonb_array_length(r -> 'avisos') = 1
    and exists (select 1 from public.incidencias where persona_id = basauri and nota_cierre = 'Leído por Ane Prueba'), r::text);
  perform pg_temp.comprobar('Administración ve los avisos a las tiendas (y su estado)',
    jsonb_array_length(motor.avisos_tiendas_de(pg_temp.a('2026-12-14', '12:00')) -> 'avisos') >= 6
    and motor.avisos_tiendas_de(pg_temp.a('2026-12-14', '12:00')) -> 'avisos' @> '[{"tienda": "Basauri", "leido": true}]');
  perform pg_temp.comprobar('El almacén no recibe los avisos de las tiendas',
    (select count(*) from public.incidencias where persona_id = op) = v_ops);
end;
$$;

-- Permisos: la tienda solo usa lo suyo
select pg_temp.como('00000000-0000-4000-b000-000000000001');
select pg_temp.comprobar('La tienda no usa las funciones del almacén ni las de Administración',
  public.tarea_activa() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.estado_actual() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.crear_incidencia(gen_random_uuid(), 'varios', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.pedidos_cliente_abiertos() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.compras_lista() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.registrar_evento(gen_random_uuid(), 'llega_mercancia', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.guardar_persona_tienda('X') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.crear_aviso_tienda(gen_random_uuid(), '2026-12-14', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.marcar_dia_cerrado('2026-12-30') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
select pg_temp.comprobar('mi_perfil: rol tienda y su tienda', public.mi_perfil() ->> 'rol' = 'tienda'
  and public.mi_perfil() -> 'centro' ->> 'nombre' = 'Basauri');
select pg_temp.comprobar('Sus funciones sí: tienda_hoy, la lista de vídeos y los nombres de su tienda (solo los suyos)',
  public.tienda_hoy() -> 'tienda' ->> 'codigo' = 'BASAURI'
  and jsonb_array_length(public.videos_semana() -> 'videos') = 2
  and jsonb_array_length(public.personas_tienda((select id from public.centros_trabajo where codigo = 'BILBAO')) -> 'personas') = 1
  and public.personas_tienda((select id from public.centros_trabajo where codigo = 'BILBAO')) -> 'personas' -> 0 ->> 'nombre' = 'Ane Prueba');
select pg_temp.comprobar('Tablas: ve sus jornadas y tareas, no las de otra tienda ni las del almacén',
  (select count(distinct j.persona_id) from public.jornadas j) = 1
  and not exists (select 1 from public.tareas t join public.jornadas j on j.id = t.jornada_id
                   where j.persona_id <> '00000000-0000-4000-b000-000000000001'));
select pg_temp.comprobar('Tablas: no ve la configuración general (cuentas, correos) ni los pedidos de cliente; sí el horario de su tienda',
  not exists (select 1 from public.configuracion where centro_id is null)
  and exists (select 1 from public.configuracion where clave = 'horario_tienda')
  and (select count(*) from public.configuracion where clave = 'horario_tienda') = 1
  and not exists (select 1 from public.pedidos_cliente)
  and (select count(*) from public.personas_tienda) = 1
  and (select count(distinct centro_id) from public.personas_tienda) = 1);
reset role;
select pg_temp.comprobar('Las funciones del servidor del reparto rechazan a la tienda',
  public.servidor_preparar('00000000-0000-4000-b000-000000000001') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.servidor_preparar_pedido('00000000-0000-4000-b000-000000000001', gen_random_uuid(), 'tienda', null) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
select pg_temp.como('00000000-0000-4000-a000-000000000001');
select pg_temp.comprobar('El operario no usa las funciones de tienda; sigue viendo la configuración general',
  public.tienda_hoy() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.videos_semana() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.personas_tienda() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and exists (select 1 from public.configuracion where clave = 'cuentas_autorizadas'));
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
select pg_temp.comprobar('Administración: personas, días cerrados, avisos y la lista de vídeos',
  jsonb_array_length(public.personas_tienda() -> 'personas') = 5
  and public.dias_cerrados('2026-12-01', '2026-12-31') -> 'dias' @> '[{"fecha": "2026-12-15", "tienda": "Basauri"}]'
  and public.avisos_tiendas() ? 'avisos'
  and jsonb_array_length(public.videos_semana() -> 'videos') = 2
  and public.tienda_hoy() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;

-- El almacén sigue igual
select pg_temp.comprobar('Almacén: el lunes, las mismas tareas a las mismas horas que antes de las tiendas',
  (select count(*) from _almacen) > 5
  and not exists (
    (select clave, disponible_desde, hora_programada, hora_limite, obligatoria, no_terminada, contenido from _almacen
     except
     select t.clave, t.disponible_desde, t.hora_programada, t.hora_limite, t.obligatoria, t.no_terminada, t.contenido
       from public.tareas t where t.jornada_id = motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-14')))
  and not exists (select 1 from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
                   join public.jornadas j on j.id = t.jornada_id
                  where e.tipo = 'punto' and j.persona_id = '00000000-0000-4000-a000-000000000001'));
select pg_temp.comprobar('Almacén: para sus plantillas, la hora de salida se calcula como siempre',
  not exists (select 1 from public.plantillas_tarea p
                join public.jornadas j on j.persona_id = '00000000-0000-4000-a000-000000000001' and j.fecha = '2026-12-14'
               where p.centro_id = j.centro_id
                 and motor.desde_plantilla(j.id, p.id) is distinct from
                     coalesce(motor.en_local(j.fecha, p.hora_inicio), motor.inicio_turno(j.persona_id, j.fecha, p.turno),
                              motor.inicio_turno(j.persona_id, j.fecha, null))));
select motor.generar_cierres_programados(pg_temp.a('2026-12-14', '13:31'));
select pg_temp.comprobar('Los cierres de turno (y su correo) siguen siendo solo del almacén',
  exists (select 1 from public.cierres c join public.jornadas j on j.id = c.jornada_id
           where j.persona_id = '00000000-0000-4000-a000-000000000001' and j.fecha = '2026-12-14')
  and not exists (select 1 from public.cierres c join public.jornadas j on j.id = c.jornada_id
                   join public.personas p on p.id = j.persona_id where p.rol = 'tienda'));

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
