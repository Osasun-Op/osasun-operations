-- Prueba 37 · El panel de Administración por centro (Tarea 32; ESTADO_DEL_SISTEMA.md E2-8, «Panel de Administración»).
-- El selector (`tiendas().centros`) en el orden de la ruta, y resumen_tienda(): lo mismo que ve la tienda, solo de
-- lectura (no crea la jornada ni tareas, no pasa atascados a Administración, no cambia nada). El martes 15/12/2026 y
-- el miércoles 16/12/2026. Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas. Se deshace al final.
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
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;
-- Cuántas filas hay en lo que la tableta escribe al abrirse (para ver que el resumen no cambia nada).
create function pg_temp.filas() returns jsonb language sql as $$
  select jsonb_build_object(
    'jornadas', (select count(*) from public.jornadas), 'tareas', (select count(*) from public.tareas),
    'elementos', (select count(*) from public.tarea_elementos), 'bolsas', (select count(*) from public.bolsas_tienda),
    'atascados', (select count(*) from public.atascados where estado = 'ofrecido'),
    'incidencias', (select count(*) from public.incidencias), 'turnos', (select count(*) from public.turnos_tienda),
    'registro', (select count(*) from public.registro_eventos)) $$;
create function pg_temp.resumen(p_tienda text, p_fecha date, p_ahora timestamptz) returns jsonb language sql as $$
  select motor.resumen_tienda_de(pg_temp.d(p_tienda), p_fecha, p_ahora) $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.renteria@osasun.invalid", "nombre": "Rentería", "rol": "tienda", "centro": "RENTERIA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000005', 'tienda.renteria@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000006', pg_temp.d('RENTERIA'), 'Maite Prueba', 'siempre', null);
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-15 08:00+01', 'stock', true, '{
  "productos": [{"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}]}],
  "categorias": {}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');

-- ---------------------------------------------------------------------------
-- 1. El selector
-- ---------------------------------------------------------------------------
do $$
declare
  r jsonb := motor.centros_panel_json();
begin
  perform pg_temp.comprobar('El selector: el almacén y las tiendas activas en el orden de la ruta (Durango, cerrada, no sale)',
    (select jsonb_agg(x ->> 'codigo' order by n) from jsonb_array_elements(r) with ordinality a(x, n))
      = '["ALMACEN", "BILBAO", "ALGORTA", "BARAKALDO", "BASAURI", "PORTU", "DONOSTI", "RENTERIA"]'::jsonb
    and r -> 0 ->> 'tipo' = 'almacen' and r -> 0 -> 'va_en' = 'null'::jsonb
    and (select x ->> 'va_en' from jsonb_array_elements(r) x where x ->> 'codigo' = 'RENTERIA') = 'envio'
    and (select x ->> 'va_en' from jsonb_array_elements(r) x where x ->> 'codigo' = 'BILBAO') = 'reparto',
    r::text);
  update public.centros_trabajo set activo = true where codigo = 'DURANGO';
  perform pg_temp.comprobar('Cuando abra Durango (envío propio), sale la última',
    motor.centros_panel_json() -> -1 ->> 'codigo' = 'DURANGO' and jsonb_array_length(motor.centros_panel_json()) = 9);
  update public.centros_trabajo set activo = false where codigo = 'DURANGO';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Solo de lectura: sin jornada, el resumen no la crea
-- ---------------------------------------------------------------------------
insert into _v values ('antes', pg_temp.filas());
do $$
declare
  r jsonb := pg_temp.resumen('BASAURI', '2026-12-15', pg_temp.a('2026-12-15', '09:00'));
begin
  perform pg_temp.comprobar('Sin la lista del día todavía: lo dice, y no crea la jornada ni nada',
    (r ->> 'abre')::boolean = false
    and r ->> 'motivo' = 'Todavía no tiene la lista del día (se prepara a las 06:00 o al abrir la tableta)'
    and r -> 'tareas' = '[]'::jsonb and jsonb_array_length(r -> 'horario') > 0
    and pg_temp.filas() = (select v from _v where k = 'antes'), r::text);
  perform pg_temp.comprobar('Un domingo: «Ese día no abre»',
    pg_temp.resumen('BASAURI', '2026-12-13', pg_temp.a('2026-12-15', '09:00')) ->> 'motivo' = 'Ese día no abre');
  perform pg_temp.comprobar('Un día que viene: DATOS_NO_VALIDOS; el almacén no es una tienda: NO_ENCONTRADO',
    pg_temp.err(pg_temp.resumen('BASAURI', '2026-12-16', pg_temp.a('2026-12-15', '09:00'))) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(pg_temp.resumen('ALMACEN', '2026-12-15', pg_temp.a('2026-12-15', '09:00'))) = 'NO_ENCONTRADO');
  perform pg_temp.comprobar('Una tienda sin cuenta todavía: «Todavía no ha entrado con su cuenta»',
    pg_temp.resumen('ALGORTA', '2026-12-15', pg_temp.a('2026-12-15', '09:00')) ->> 'motivo' = 'Todavía no ha entrado con su cuenta');
  perform pg_temp.comprobar('Es STABLE: Postgres no le deja escribir',
    (select provolatile = 's' from pg_proc where oid = 'motor.resumen_tienda_de(uuid, date, timestamptz)'::regprocedure));
end $$;

-- ---------------------------------------------------------------------------
-- 3. El martes en Basauri: lo mismo que ve la tienda
-- ---------------------------------------------------------------------------
select motor.generar_jornada('00000000-0000-4000-b000-000000000001', '2026-12-15');
select motor.generar_jornada('00000000-0000-4000-b000-000000000005', '2026-12-15');
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-15');
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  t uuid;
begin
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-15', '10:55'));
  select tr.id into t from public.tareas tr join public.jornadas j on j.id = tr.jornada_id
   where j.persona_id = basauri and j.fecha = '2026-12-15' and tr.clave = 'revisa_atascados';
  perform motor.revisar_atascados_de(basauri, t, '[{"producto": "V2", "formato": "4g", "cantidad": 2}]', pg_temp.a('2026-12-15', '11:05'));
  perform motor.crear_aviso_tienda_de('00000000-0000-4000-a000-000000000002', 'c0c0c0c0-0000-4000-8000-000000000037',
                                      '2026-12-15', 'Mirad la cartelería nueva', pg_temp.d('BASAURI'), pg_temp.a('2026-12-15', '11:10'));
  insert into public.cierres_caja (centro_id, fecha, z, ventas, efectivo, glovo, nombre)
  values (pg_temp.d('BASAURI'), '2026-12-14', 812.40, 37, 120, 15.5, 'Ane Prueba');
end $$;

insert into _v values ('martes', pg_temp.filas());
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  ahora timestamptz := pg_temp.a('2026-12-15', '12:00');
  r jsonb := pg_temp.resumen('BASAURI', '2026-12-15', ahora);
  hoy jsonb;
begin
  perform pg_temp.comprobar('Abre y dice quién está ahora y quién ha estado',
    (r ->> 'abre')::boolean and r -> 'en_turno' ->> 'nombre' = 'Ane Prueba'
    and r -> 'turnos' = '[{"nombre": "Ane Prueba", "turno": "manana", "desde": "10:55"}]'::jsonb
    and r ->> 'va_en' = 'reparto', r::text);
  perform pg_temp.comprobar('Las tareas con su hora, estado y «hecha por» (la del martes, hecha por Ane)',
    exists (select 1 from jsonb_array_elements(r -> 'tareas') x
             where x ->> 'clave' = 'revisa_atascados' and x ->> 'estado' = 'hecha' and x ->> 'hecha_por' = 'Ane Prueba'
               and x ->> 'hora_fin' = '11:05')
    and (r -> 'cuantas' ->> 'hechas')::int >= 1
    and (r -> 'cuantas' ->> 'total')::int = jsonb_array_length(r -> 'tareas')
    and (r -> 'cuantas' ->> 'total')::int = (r -> 'cuantas' ->> 'hechas')::int + (r -> 'cuantas' ->> 'pendientes')::int
                                            + (r -> 'cuantas' ->> 'no_hechas')::int, r ->> 'cuantas');
  perform pg_temp.comprobar('Lo abierto: el atascado, el aviso sin leer; sin bolsa ni reparto hoy',
    r -> 'atascados' -> 0 ->> 'texto' = '2 cajas de V2 4g' and r -> 'atascados' -> 0 ->> 'estado' = 'ofrecido'
    and r -> 'avisos' -> 0 ->> 'texto' = 'Mirad la cartelería nueva' and r -> 'avisos' -> 0 ->> 'de' = 'Administración'
    and r -> 'bolsa' = 'null'::jsonb and r -> 'reparto' = 'null'::jsonb and r -> 'peticiones' = '[]'::jsonb, r::text);
  perform pg_temp.comprobar('El cierre de caja: el último (de ayer), avisando de que no es de ese día',
    r -> 'cierre_caja' ->> 'fecha' = '2026-12-14' and (r -> 'cierre_caja' ->> 'z')::numeric = 812.40
    and (r -> 'cierre_caja' ->> 'es_de_ese_dia')::boolean = false and r -> 'cierre_caja' ->> 'por' = 'Ane Prueba', r ->> 'cierre_caja');
  perform pg_temp.comprobar('Ver el resumen no cambia nada en la base de datos',
    pg_temp.filas() = (select v from _v where k = 'martes'));
  -- Lo mismo que ve la tableta (las mismas ayudas).
  hoy := motor.tienda_hoy_de(basauri, ahora);
  perform pg_temp.comprobar('Las tareas, los avisos, el horario y las incidencias son los mismos que en tienda_hoy()',
    hoy -> 'tareas' = r -> 'tareas' and hoy -> 'avisos' = r -> 'avisos' and hoy -> 'horario' = r -> 'horario'
    and hoy -> 'incidencias' = r -> 'incidencias' and hoy -> 'pedidos' = r -> 'pedidos'
    and (hoy -> 'envios_sin_confirmar') = (r -> 'envios_sin_confirmar'), hoy::text);
end $$;

-- ---------------------------------------------------------------------------
-- 4. El miércoles: el martes como quedó, y el atascado no pasa a Administración por mirar
-- ---------------------------------------------------------------------------
insert into _v values ('miercoles', pg_temp.filas());
do $$
declare
  r jsonb := pg_temp.resumen('BASAURI', '2026-12-15', pg_temp.a('2026-12-16', '09:00'));
begin
  perform pg_temp.comprobar('Un día pasado: como quedó al final, sin «quién está ahora» y con lo no hecho como no hecho',
    r ->> 'ahora' = '23:59' and r -> 'en_turno' = 'null'::jsonb and jsonb_array_length(r -> 'turnos') = 1
    and (r -> 'cuantas' ->> 'no_hechas')::int > 0 and (r -> 'cuantas' ->> 'pendientes')::int = 0
    and exists (select 1 from jsonb_array_elements(r -> 'tareas') x where (x ->> 'no_hecha')::boolean), r ->> 'cuantas');
  perform pg_temp.comprobar('Mirar el miércoles no pasa el atascado a Administración (eso lo hace la tableta o el panel de incidencias)',
    pg_temp.filas() = (select v from _v where k = 'miercoles')
    and not exists (select 1 from public.incidencias where opcion = 'atascado'));
  perform pg_temp.comprobar('Rentería (por envío): sin bolsa ni reparto, con «Envíos» (vacío)',
    pg_temp.resumen('RENTERIA', '2026-12-15', pg_temp.a('2026-12-15', '12:00')) ->> 'va_en' = 'envio'
    and pg_temp.resumen('RENTERIA', '2026-12-15', pg_temp.a('2026-12-15', '12:00')) -> 'envios' = '[]'::jsonb
    and (pg_temp.resumen('RENTERIA', '2026-12-15', pg_temp.a('2026-12-15', '12:00')) ->> 'envios_sin_confirmar')::int = 0);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Permisos
-- ---------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
insert into _v values ('api', pg_temp.filas());
select pg_temp.comprobar('Administración: resumen_tienda() y tiendas() con `centros` (y `tiendas` como antes)',
  public.resumen_tienda(pg_temp.d('BASAURI')) ->> 'tienda' is not null
  and public.resumen_tienda(pg_temp.d('BASAURI'), (now() at time zone 'Europe/Madrid')::date - 1) -> 'tienda' ->> 'codigo' = 'BASAURI'
  and jsonb_array_length(public.tiendas() -> 'centros') = 8
  and (select jsonb_agg(x ->> 'codigo' order by x ->> 'nombre') from jsonb_array_elements(public.tiendas() -> 'tiendas') x)
      = (select jsonb_agg(x ->> 'codigo') from jsonb_array_elements(public.tiendas() -> 'tiendas') x));
reset role;
select pg_temp.comprobar('Llamarlo desde la API tampoco cambia nada', pg_temp.filas() = (select v from _v where k = 'api'));
select pg_temp.como('00000000-0000-4000-b000-000000000001');  -- Basauri
select pg_temp.comprobar('Una tienda no ve el panel', public.resumen_tienda(pg_temp.d('BASAURI')) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario tampoco', public.resumen_tienda(pg_temp.d('BASAURI')) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.resumen_tienda(uuid, date)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.resumen_tienda_de(uuid, date, timestamptz)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
