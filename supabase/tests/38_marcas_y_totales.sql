-- Prueba 38 · Marcas en las pestañas del panel y totales de los cierres de caja (Tarea 33; ESTADO_DEL_SISTEMA.md E2-8,
-- v1.61 y v1.62). El martes 15/12/2026 y el miércoles 16/12/2026: el rojo (incidencias abiertas de la tienda, los
-- atascados por decidir y los problemas del almacén), «N sin hacer» hasta que Administración entra en la tienda,
-- «sin abrir» media hora después de empezar un turno sin nadie, y los totales por día (propias y franquicias, con las
-- que faltan). Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas y de las jornadas del operario. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;
create temp table _v (k text primary key, v jsonb) on commit drop;
grant all on _v to authenticated;

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
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
-- Las marcas de un centro para Administración (o para otra persona) a esa hora.
create function pg_temp.m(p_codigo text, p_ahora timestamptz, p_persona uuid default '00000000-0000-4000-a000-000000000002')
returns jsonb language sql as $$ select motor.marcas_panel_json(p_persona, p_ahora) -> (pg_temp.d(p_codigo)::text) $$;
-- Los totales de un día.
create function pg_temp.t(p_fecha date, p_ahora timestamptz) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.totales_cierres_de(p_fecha, p_fecha, null, p_ahora)) x $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"},
  {"correo": "tienda.renteria@osasun.invalid", "nombre": "Rentería", "rol": "tienda", "centro": "RENTERIA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.portu@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000005', 'tienda.renteria@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('PORTU'), 'Leire Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000006', pg_temp.d('RENTERIA'), 'Maite Prueba', 'siempre', null);
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-15 08:00+01', 'stock', true, '{
  "productos": [{"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}]}],
  "categorias": {}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');
-- Las jornadas del martes y del miércoles (aparte, antes de leer sus tareas).
select motor.generar_jornada(x.p, x.f)
  from (values ('00000000-0000-4000-b000-000000000001'::uuid), ('00000000-0000-4000-b000-000000000002'),
               ('00000000-0000-4000-b000-000000000005'), ('00000000-0000-4000-a000-000000000001')) p(p)
  cross join (values ('2026-12-15'::date), ('2026-12-16')) f(f)
  cross join lateral (select p.p, f.f) x;

-- ---------------------------------------------------------------------------
-- 1. «sin abrir»
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
begin
  perform pg_temp.comprobar('A las 11:20 (abre a las 11:00), todavía no: falta la media hora',
    not (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '11:20')) ->> 'sin_abrir')::boolean);
  perform pg_temp.comprobar('A las 11:31 sin nadie en el turno: «sin abrir»',
    (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '11:31')) ->> 'sin_abrir')::boolean
    and pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '11:31')) ->> 'texto' like '%sin abrir',
    pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '11:31'))::text);
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-15', '11:35'));
  perform pg_temp.comprobar('Se quita cuando alguien empieza el turno',
    not (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '11:36')) ->> 'sin_abrir')::boolean);
  perform pg_temp.comprobar('Por la tarde (abre a las 17:00), a las 17:31 sin nadie en la tarde: otra vez «sin abrir»',
    not (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '17:29')) ->> 'sin_abrir')::boolean
    and (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '17:31')) ->> 'sin_abrir')::boolean);
  perform pg_temp.comprobar('Solo mientras dura ese turno: Portugalete, sin nadie, sale a las 12:00, no a las 13:45 (entre turnos) y otra vez a las 17:31',
    (pg_temp.m('PORTU', pg_temp.a('2026-12-15', '12:00')) ->> 'sin_abrir')::boolean
    and not (pg_temp.m('PORTU', pg_temp.a('2026-12-15', '13:45')) ->> 'sin_abrir')::boolean
    and (pg_temp.m('PORTU', pg_temp.a('2026-12-15', '17:31')) ->> 'sin_abrir')::boolean
    and not (pg_temp.m('PORTU', pg_temp.a('2026-12-15', '21:00')) ->> 'sin_abrir')::boolean);
  perform pg_temp.comprobar('El domingo no abre: nada',
    not (pg_temp.m('BASAURI', pg_temp.a('2026-12-13', '12:00')) ->> 'sin_abrir')::boolean);
  perform motor.marcar_dia_cerrado_de('00000000-0000-4000-a000-000000000002', '2026-12-16', pg_temp.d('PORTU'), true, 'Festivo local',
                                      pg_temp.a('2026-12-15', '09:00'));
  perform pg_temp.comprobar('Un día marcado cerrado: nada (Portugalete el 16/12); y el almacén nunca',
    not (pg_temp.m('PORTU', pg_temp.a('2026-12-16', '12:00')) ->> 'sin_abrir')::boolean
    and not (pg_temp.m('ALMACEN', pg_temp.a('2026-12-15', '12:00')) ->> 'sin_abrir')::boolean);
end $$;

-- ---------------------------------------------------------------------------
-- 2. El rojo
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  ahora timestamptz := pg_temp.a('2026-12-15', '12:00');
  inc uuid;
  t uuid;
  antes int := (pg_temp.m('ALMACEN', pg_temp.a('2026-12-15', '12:00')) ->> 'rojo')::int;
  -- Lo que ya hubiera abierto antes (en pruebas puede haber incidencias reales): se cuenta lo que cambia.
  b0 int := (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '12:00')) ->> 'rojo')::int;
  p0 int := (pg_temp.m('PORTU', pg_temp.a('2026-12-15', '12:00')) ->> 'rojo')::int;
  r0 int := (pg_temp.m('RENTERIA', pg_temp.a('2026-12-15', '12:00')) ->> 'rojo')::int;
begin
  perform pg_temp.comprobar('Sin nada abierto de la prueba: el rojo es el que había', b0 >= 0 and p0 >= 0 and r0 >= 0);
  perform motor.crear_incidencia_tienda_de(basauri, 'e0e0e0e0-0000-4000-8000-000000000038', 'otros', 'Se ha roto la persiana',
                                           null, pg_temp.a('2026-12-15', '11:40'));
  perform pg_temp.comprobar('Una incidencia abierta de Basauri: una más en rojo (●N), y Portugalete igual',
    (pg_temp.m('BASAURI', ahora) ->> 'rojo')::int = b0 + 1 and pg_temp.m('BASAURI', ahora) ->> 'texto' like '●' || (b0 + 1) || '%'
    and (pg_temp.m('PORTU', ahora) ->> 'rojo')::int = p0, pg_temp.m('BASAURI', ahora)::text);
  -- Rentería (franquicia): su atascado va directo a Administración, por decidir.
  perform motor.empezar_turno_tienda_de(renteria, '00000000-0000-4000-c000-000000000006', pg_temp.a('2026-12-15', '10:55'));
  select tr.id into t from public.tareas tr join public.jornadas j on j.id = tr.jornada_id
   where j.persona_id = renteria and j.fecha = '2026-12-15' and tr.clave = 'revisa_atascados';
  perform motor.revisar_atascados_de(renteria, t, '[{"producto": "V2", "formato": "4g", "cantidad": 2}]', pg_temp.a('2026-12-15', '11:05'));
  perform pg_temp.comprobar('Un atascado por decidir de Rentería: uno más en rojo', (pg_temp.m('RENTERIA', ahora) ->> 'rojo')::int = r0 + 1);
  select id into inc from public.incidencias where id_cliente = 'e0e0e0e0-0000-4000-8000-000000000038';
  perform motor.cerrar_incidencia_tienda_de(adm, inc, 'Arreglada', pg_temp.a('2026-12-15', '12:10'));
  perform motor.decidir_atascado_de(adm, (select id from public.atascados where centro_id = pg_temp.d('RENTERIA')), 'recogida', null,
                                    pg_temp.a('2026-12-15', '12:10'));
  perform pg_temp.comprobar('Baja al cerrarla o decidirlo',
    (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '12:15')) ->> 'rojo')::int = b0
    and (pg_temp.m('RENTERIA', pg_temp.a('2026-12-15', '12:15')) ->> 'rojo')::int = r0);
  -- El almacén: los problemas abiertos (botón «Resolver»).
  select tr.id into t from public.tareas tr join public.jornadas j on j.id = tr.jornada_id
   where j.persona_id = op and j.fecha = '2026-12-15' and tr.estado = 'pendiente' order by tr.orden limit 1;
  perform motor.abrir_problema_de(op, 'e1e1e1e1-0000-4000-8000-000000000038', t, 'falta_material', 'No hay cinta', pg_temp.a('2026-12-15', '12:20'));
  perform pg_temp.comprobar('Un problema abierto en el almacén: uno más en rojo',
    (pg_temp.m('ALMACEN', pg_temp.a('2026-12-15', '12:21')) ->> 'rojo')::int = antes + 1,
    pg_temp.m('ALMACEN', pg_temp.a('2026-12-15', '12:21'))::text);
end $$;

-- ---------------------------------------------------------------------------
-- 3. «N sin hacer», hasta que Administración entra en esa tienda
-- ---------------------------------------------------------------------------
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  n int := (select count(*) from public.tareas t join public.jornadas j on j.id = t.jornada_id
             where j.persona_id = '00000000-0000-4000-b000-000000000001' and j.fecha = '2026-12-15'
               and t.estado = 'pendiente' and not t.retirada_por_condicion);
  r jsonb;
begin
  perform pg_temp.comprobar('Antes de cerrar el martes, 0 sin hacer', (pg_temp.m('BASAURI', pg_temp.a('2026-12-15', '20:00')) ->> 'sin_hacer')::int = 0);
  perform pg_temp.comprobar('El miércoles: lo que quedó sin hacer el martes (las mismas que «no hecha» en la lista del día)',
    n > 0 and (pg_temp.m('BASAURI', pg_temp.a('2026-12-16', '09:00')) ->> 'sin_hacer')::int = n
    and (select count(*) from jsonb_array_elements(motor.resumen_tienda_de(pg_temp.d('BASAURI'), '2026-12-15', pg_temp.a('2026-12-16', '09:00')) -> 'tareas') x
          where (x ->> 'no_hecha')::boolean) = n
    and pg_temp.m('BASAURI', pg_temp.a('2026-12-16', '09:00')) ->> 'texto' like '%' || n || ' sin hacer',
    pg_temp.m('BASAURI', pg_temp.a('2026-12-16', '09:00'))::text);
  insert into _v values ('renteria', to_jsonb((pg_temp.m('RENTERIA', pg_temp.a('2026-12-16', '09:00')) ->> 'sin_hacer')::int));
  r := motor.marcar_tienda_vista_de(adm, pg_temp.d('BASAURI'), pg_temp.a('2026-12-16', '09:05'));
  perform pg_temp.comprobar('Administración entra en Basauri: se quita su «sin hacer» (y la respuesta trae sus marcas)',
    (r -> 'marcas' ->> 'sin_hacer')::int = 0 and (pg_temp.m('BASAURI', pg_temp.a('2026-12-16', '09:10')) ->> 'sin_hacer')::int = 0, r::text);
  perform pg_temp.comprobar('Solo la de Basauri: Rentería sigue con las suyas',
    (pg_temp.m('RENTERIA', pg_temp.a('2026-12-16', '09:10')) ->> 'sin_hacer')::int = (select (v #>> '{}')::int from _v where k = 'renteria')
    and (select (v #>> '{}')::int from _v where k = 'renteria') > 0);
  perform pg_temp.comprobar('Y solo para quien ha entrado: otra persona las sigue viendo',
    (pg_temp.m('BASAURI', pg_temp.a('2026-12-16', '09:10'), op) ->> 'sin_hacer')::int = n);
  perform pg_temp.comprobar('Lo que quede sin hacer el miércoles sale al cerrar el miércoles',
    (pg_temp.m('BASAURI', pg_temp.a('2026-12-16', '21:00')) ->> 'sin_hacer')::int
      = (select count(*) from public.tareas t join public.jornadas j on j.id = t.jornada_id
          where j.persona_id = '00000000-0000-4000-b000-000000000001' and j.fecha = '2026-12-16'
            and t.estado = 'pendiente' and not t.retirada_por_condicion));
  perform pg_temp.comprobar('Un centro que no existe: NO_ENCONTRADO',
    motor.marcar_tienda_vista_de(adm, gen_random_uuid(), pg_temp.a('2026-12-16', '09:05')) -> 'error' ->> 'codigo' = 'NO_ENCONTRADO');
end $$;

-- ---------------------------------------------------------------------------
-- 4. Totales de los cierres de caja
-- ---------------------------------------------------------------------------
insert into public.cierres_caja (centro_id, fecha, z, ventas, efectivo, glovo, nombre) values
  (pg_temp.d('BASAURI'), '2026-12-15', 812.40, 37, 120, 15.5, 'Ane Prueba'),
  (pg_temp.d('RENTERIA'), '2026-12-15', 640.10, 29, null, null, 'Maite Prueba');
do $$
declare
  t jsonb := pg_temp.t('2026-12-15', pg_temp.a('2026-12-16', '12:00'));
begin
  perform pg_temp.comprobar('Qué es franquicia sale de la configuración (el cierre corto): Donosti y Rentería sí; Durango y Basauri no',
    motor.cierre_corto(pg_temp.d('DONOSTI')) and motor.cierre_corto(pg_temp.d('RENTERIA'))
    and not motor.cierre_corto(pg_temp.d('DURANGO')) and not motor.cierre_corto(pg_temp.d('BASAURI')));
  perform pg_temp.comprobar('El martes: propias (Basauri) con Z, ventas, efectivo y Glovo; falta Portugalete',
    (t -> 'propias' ->> 'z')::numeric = 812.40 and (t -> 'propias' ->> 'ventas')::int = 37
    and (t -> 'propias' ->> 'efectivo')::numeric = 120 and (t -> 'propias' ->> 'glovo')::numeric = 15.5
    and (t -> 'propias' ->> 'cierres')::int = 1
    and t -> 'propias' -> 'faltan' = jsonb_build_array(jsonb_build_object('tienda_id', pg_temp.d('PORTU'), 'tienda', 'Portugalete')), t::text);
  perform pg_temp.comprobar('Las franquicias aparte (Rentería: Z y ventas), sin efectivo ni Glovo y sin faltar ninguna',
    (t -> 'franquicias' ->> 'z')::numeric = 640.10 and (t -> 'franquicias' ->> 'ventas')::int = 29
    and not (t -> 'franquicias' ? 'efectivo') and t -> 'franquicias' -> 'faltan' = '[]'::jsonb, t ->> 'franquicias');
  -- El miércoles (hoy en la prueba): Portugalete cerrado ese día, Basauri y Rentería sin cierre.
  perform pg_temp.comprobar('Hoy, antes de la hora de cierre, no falta nadie; el día cerrado no cuenta',
    pg_temp.t('2026-12-16', pg_temp.a('2026-12-16', '12:00')) -> 'propias' -> 'faltan' = '[]'::jsonb
    and pg_temp.t('2026-12-16', pg_temp.a('2026-12-16', '12:00')) -> 'franquicias' -> 'faltan' = '[]'::jsonb);
  perform pg_temp.comprobar('Hoy, pasada su hora de cierre: falta Basauri (Portugalete, cerrado, no) y falta Rentería',
    (select jsonb_agg(x ->> 'tienda') from jsonb_array_elements(pg_temp.t('2026-12-16', pg_temp.a('2026-12-16', '21:00')) -> 'propias' -> 'faltan') x)
      = '["Basauri"]'::jsonb
    and (select jsonb_agg(x ->> 'tienda') from jsonb_array_elements(pg_temp.t('2026-12-16', pg_temp.a('2026-12-16', '21:00')) -> 'franquicias' -> 'faltan') x)
      = '["Rentería"]'::jsonb, pg_temp.t('2026-12-16', pg_temp.a('2026-12-16', '21:00'))::text);
  perform pg_temp.comprobar('El domingo, sin tiendas que abran ni cierres: no sale',
    jsonb_array_length(motor.totales_cierres_de('2026-12-13', '2026-12-13', null, pg_temp.a('2026-12-16', '12:00'))) = 0);
  perform pg_temp.comprobar('Con una sola tienda, los totales son los suyos',
    (motor.totales_cierres_de('2026-12-15', '2026-12-15', pg_temp.d('BASAURI'), pg_temp.a('2026-12-16', '12:00')) -> 0 -> 'propias' -> 'faltan') = '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Por la API y permisos
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('Administración: tiendas().centros trae las marcas; cierres_caja() trae los totales',
  (select bool_and(x ? 'marcas' and x -> 'marcas' ? 'rojo' and x -> 'marcas' ? 'sin_hacer' and x -> 'marcas' ? 'sin_abrir')
     from jsonb_array_elements(public.tiendas() -> 'centros') x)
  and public.cierres_caja('2026-12-15', '2026-12-15') ? 'totales'
  and public.cierres_caja('2026-12-15', '2026-12-15') ? 'cierres'
  and public.marcar_tienda_vista(pg_temp.d('BASAURI')) ->> 'centro_id' = pg_temp.d('BASAURI')::text);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario ve tiendas() como antes (sin marcas) y no marca nada',
  not exists (select 1 from jsonb_array_elements(public.tiendas() -> 'centros') x where x ? 'marcas')
  and public.tiendas() ? 'tiendas'
  and public.marcar_tienda_vista(pg_temp.d('BASAURI')) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-b000-000000000001');  -- Basauri
select pg_temp.comprobar('Una tienda, tampoco', public.marcar_tienda_vista(pg_temp.d('BASAURI')) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.comprobar('Sin sesión, nada; vistas_panel solo se escribe con marcar_tienda_vista()',
  not has_function_privilege('anon', 'public.marcar_tienda_vista(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.marcas_panel_json(uuid, timestamptz)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.vistas_panel', 'INSERT')
  and not has_table_privilege('anon', 'public.vistas_panel', 'SELECT'));
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('vistas_panel: el operario no ve nada', (select count(*) from public.vistas_panel) = 0);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('vistas_panel: Administración ve solo lo suyo',
  (select count(*) > 0 and bool_and(persona_id = '00000000-0000-4000-a000-000000000002') from public.vistas_panel));
reset role;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
