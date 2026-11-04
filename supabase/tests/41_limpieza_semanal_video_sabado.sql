-- Prueba 41 · La limpieza semanal y la hora del vídeo del sábado (Tarea 36; ESTADO_DEL_SISTEMA.md E2-8 v1.67).
-- Cuentas y nombres inventados (@osasun.invalid). Jueves 17/12/2026 y sábado 19/12/2026 (semana ISO 51, impar: en
-- Bilbao las semanales van por la tarde). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas en pruebas. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.a(p_fecha date, p_hora time) returns timestamptz language sql as $$ select motor.en_local(p_fecha, p_hora) $$;
create function pg_temp.tarea(r jsonb, p_clave text) returns jsonb language sql as $$
  select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' like p_clave limit 1 $$;
-- La posición de una tarea en la lista de la tableta (el orden en que se ve).
create function pg_temp.pos(r jsonb, p_clave text) returns int language sql as $$
  select min(n)::int from jsonb_array_elements(r -> 'tareas') with ordinality x(t, n) where t ->> 'clave' like p_clave $$;

-- Cuentas de tienda (inventadas).
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

do $$
declare
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
begin
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BASAURI'), 'Ane Prueba', 'siempre', null, true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'PORTU'), 'Nora Prueba', 'sabados', null, true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BILBAO'), 'Leire Prueba', 'siempre', 'manana', true);
  perform motor.guardar_persona_tienda_de(admin, null, (select id from public.centros_trabajo where codigo = 'BILBAO'), 'Unai Prueba', 'siempre', 'tarde', true);
end;
$$;

-- 1. La limpieza semanal (jueves 17/12)
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  ane uuid := (select id from public.personas_tienda where nombre = 'Ane Prueba');
  r jsonb;
  t jsonb;
begin
  perform pg_temp.comprobar('Plantillas: todas las de la limpieza con el título y el porqué nuevos; ninguna con el de antes',
    not exists (select 1 from public.plantillas_tarea where codigo = 'limpieza_cristales'
                 and (titulo <> 'Limpieza semanal: cristales, polvo y baños' or porque <> 'Para que la tienda esté limpia y se vea bien.'))
    and exists (select 1 from public.plantillas_tarea where codigo = 'limpieza_cristales')
    and not exists (select 1 from public.plantillas_tarea where titulo = 'Limpieza de cristales'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-17', '16:55'));
  t := pg_temp.tarea(r, 'limpieza_cristales');
  perform pg_temp.comprobar('Jueves en Basauri: «Limpieza semanal: cristales, polvo y baños», a las 17:00, con su porqué',
    t ->> 'titulo' = 'Limpieza semanal: cristales, polvo y baños' and t ->> 'hora' = '17:00'
    and t ->> 'porque' = 'Para que la tienda esté limpia y se vea bien.', t::text);
  perform pg_temp.comprobar('… de un toque, sin casillas (la limpieza no se controla)',
    t ->> 'tipo' = 'simple' and t -> 'puntos' = '[]'::jsonb
    and not exists (select 1 from public.tarea_elementos where tarea_id = (t ->> 'id')::uuid), t::text);
  perform pg_temp.comprobar('Bilbao (semana impar, por la tarde): a las 16:30; Donosti (franquicia): no la tiene',
    pg_temp.tarea(motor.tienda_hoy_de(bilbao, pg_temp.a('2026-12-17', '16:25')), 'limpieza_cristales') ->> 'hora' = '16:30'
    and pg_temp.tarea(motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-17', '16:55')), 'limpieza_cristales') is null);
  perform motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-17', '16:55'));
  r := motor.terminar_tarea_tienda_de(basauri, (t ->> 'id')::uuid, pg_temp.a('2026-12-17', '17:10'));
  perform pg_temp.comprobar('«Hecho», como siempre', pg_temp.tarea(r, 'limpieza_cristales') ->> 'estado' = 'hecha', r::text);
end;
$$;

-- 2. El vídeo del sábado (19/12), a la hora de abrir de su turno, después de la apertura
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  bilbao constant uuid := '00000000-0000-4000-b000-000000000002';
  portu constant uuid := '00000000-0000-4000-b000-000000000004';
  ane uuid := (select id from public.personas_tienda where nombre = 'Ane Prueba');
  nora uuid := (select id from public.personas_tienda where nombre = 'Nora Prueba');
  leire uuid := (select id from public.personas_tienda where nombre = 'Leire Prueba');
  unai uuid := (select id from public.personas_tienda where nombre = 'Unai Prueba');
  r jsonb;
  v jsonb;
begin
  -- Basauri: Ane empieza a las 10:45.
  r := motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-19', '10:45'));
  v := pg_temp.tarea(r, 'video_semana%');
  perform pg_temp.comprobar('Sábado, Basauri: Ane empieza a las 10:45 y su vídeo sale a las 11:00, en gris hasta entonces',
    v ->> 'hora' = '11:00' and not (v ->> 'se_puede_marcar')::boolean, r::text);
  perform pg_temp.comprobar('… detrás de la apertura (lo primero es fichar, Glovo y carteles)',
    pg_temp.pos(r, 'apertura_manana') < pg_temp.pos(r, 'video_semana%')
    and pg_temp.pos(r, 'video_semana%') = pg_temp.pos(r, 'apertura_manana') + 1, r::text);
  perform pg_temp.comprobar('A las 11:00 ya se puede hacer',
    (pg_temp.tarea(motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-19', '11:00')), 'video_semana%') ->> 'se_puede_marcar')::boolean);
  r := motor.empezar_turno_tienda_de(basauri, ane, pg_temp.a('2026-12-19', '16:55'));
  perform pg_temp.comprobar('Si Ane vuelve a empezar por la tarde, su vídeo sigue a las 11:00 (uno por persona)',
    pg_temp.tarea(r, 'video_semana%') ->> 'hora' = '11:00'
    and (select count(*) from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' like 'video_semana%') = 1, r::text);

  -- Portugalete: Nora empieza por la tarde.
  r := motor.empezar_turno_tienda_de(portu, nora, pg_temp.a('2026-12-19', '16:40'));
  v := pg_temp.tarea(r, 'video_semana%');
  perform pg_temp.comprobar('Portugalete: Nora empieza por la tarde (16:40) y su vídeo sale a las 17:00, detrás de la apertura',
    v ->> 'hora' = '17:00' and not (v ->> 'se_puede_marcar')::boolean
    and pg_temp.pos(r, 'apertura_tarde') < pg_temp.pos(r, 'video_semana%'), r::text);

  -- Bilbao: Unai por la tarde (16:30); Leire entre turnos, a la hora de abrir del siguiente.
  r := motor.empezar_turno_tienda_de(bilbao, unai, pg_temp.a('2026-12-19', '16:15'));
  v := (select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' = 'video_semana:' || unai);
  perform pg_temp.comprobar('Bilbao por la tarde: el vídeo de Unai, a las 16:30, detrás de la apertura de la tarde',
    v ->> 'hora' = '16:30' and pg_temp.pos(r, 'apertura_tarde') < pg_temp.pos(r, 'video_semana:' || unai), r::text);
  r := motor.empezar_turno_tienda_de(bilbao, leire, pg_temp.a('2026-12-19', '14:15'));
  v := (select x from jsonb_array_elements(r -> 'tareas') x where x ->> 'clave' = 'video_semana:' || leire);
  perform pg_temp.comprobar('Bilbao, Leire empieza entre turnos (14:15): su vídeo, a la hora de abrir del siguiente (16:30)',
    v ->> 'hora' = '16:30', r::text);
end;
$$;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
