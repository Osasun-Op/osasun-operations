-- Prueba 36 · Productos atascados (Tarea 31; ESTADO_DEL_SISTEMA.md E2-8 v1.56 y v1.57).
-- El martes 15/12/2026: Basauri y Portugalete apuntan lo que no se mueve y se ofrece a las demás tiendas; Rentería
-- (franquicia) pide el V2 4g de Basauri y Portugalete el BZ1 4g; Donosti (franquicia) apunta un atascado que va directo
-- a Administración. El miércoles 16/12: lo que nadie ha pedido llega a Administración, que decide promoción, al almacén
-- o recogida; Eder recoge sin tocar el reparto y lo de Rentería va en el siguiente envío a Gipuzkoa. Cuentas y nombres
-- inventados (@osasun.invalid). Transacción deshecha al final.

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
-- La tarea del martes de una tienda.
create function pg_temp.tarea(p_persona uuid, p_fecha date) returns uuid language sql as $$
  select t.id from public.tareas t join public.jornadas j on j.id = t.jornada_id
   where j.persona_id = p_persona and j.fecha = p_fecha and t.clave = 'revisa_atascados' $$;
create function pg_temp.atascado(p_tienda text, p_producto text, p_formato text) returns uuid language sql as $$
  select id from public.atascados where centro_id = pg_temp.d(p_tienda) and producto = p_producto and formato = p_formato $$;
create function pg_temp.recogidas() returns jsonb language sql as $$
  select motor.incidencias_abiertas_de('00000000-0000-4000-a000-000000000001', pg_temp.a('2026-12-16', '12:00')) -> 'incidencias' $$;
-- Un envío a Gipuzkoa como lo guarda la función del servidor guardar_reparto: 2x V2 4g.
create function pg_temp.envio(p_fecha date) returns jsonb language sql as $$
  select public.servidor_guardar_reparto('00000000-0000-4000-a000-000000000002',
    motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_fecha), 'envio',
    E'ENVÍO\n\nGIPUZKOA\n2x V2 4g', 'h36-e', p_fecha, null, null,
    jsonb_build_array(
      jsonb_build_object('num', 3, 'texto', 'GIPUZKOA', 'clase', 'tienda', 'destino_id', pg_temp.d('GIPUZKOA')),
      jsonb_build_object('num', 4, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('GIPUZKOA'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 2, 'en_almacen', 10, 'faltan', 0, 'aviso', null, 'orden', 1)),
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'), 'items', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1)))),
    true, motor.en_local(p_fecha, '15:40')) $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"},
  {"correo": "tienda.donosti@osasun.invalid", "nombre": "Donosti", "rol": "tienda", "centro": "DONOSTI"},
  {"correo": "tienda.renteria@osasun.invalid", "nombre": "Rentería", "rol": "tienda", "centro": "RENTERIA"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.portu@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000003', 'tienda.donosti@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000005', 'tienda.renteria@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('PORTU'), 'Leire Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000004', pg_temp.d('DONOSTI'), 'Nora Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000006', pg_temp.d('RENTERIA'), 'Maite Prueba', 'siempre', null);
-- La última lectura de la hoja (la lista de la tableta).
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-15 08:00+01', 'stock', true, '{
  "productos": [
    {"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}, {"formato": "10g", "almacen": "3"}]},
    {"nombre": "BZ1", "orden": 2, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "5"}]},
    {"nombre": "CREMA", "orden": 3, "conTiendas": true, "formatos": []}],
  "categorias": {"V2": "Indoor", "BZ1": "Invernadero"}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');
-- Las jornadas del martes y del miércoles (aparte, antes de leer sus tareas).
select motor.generar_jornada(x.p, x.f)
  from (values ('00000000-0000-4000-b000-000000000001'::uuid), ('00000000-0000-4000-b000-000000000002'),
               ('00000000-0000-4000-b000-000000000003'), ('00000000-0000-4000-b000-000000000005'),
               ('00000000-0000-4000-a000-000000000001')) p(p)
  cross join (values ('2026-12-15'::date), ('2026-12-16')) f(f)
  cross join lateral (select p.p, f.f) x;
-- Lo del almacén antes de los atascados: sus tareas de esos días, para ver que no cambian.
insert into _v select 'tareas_almacen', to_jsonb(count(*)) from public.tareas t join public.jornadas j on j.id = t.jornada_id
 where j.persona_id = '00000000-0000-4000-a000-000000000001' and j.fecha in ('2026-12-15', '2026-12-16');
insert into _v values ('activa_almacen', motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a('2026-12-15', '11:00')) -> 'id');

-- ---------------------------------------------------------------------------
-- 1. La tarea del martes
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  r jsonb;
begin
  perform pg_temp.comprobar('«Revisa los productos atascados» está en todas las tiendas, franquicias incluidas, el martes por la mañana (Bilbao alterna)',
    (select count(*) = 8 and bool_and(p.activa and p.dias_semana = '{2}' and p.turno = 'manana' and p.contenido = 'atascados'
                                      and p.no_terminada = 'nada')
            and bool_and(p.alterna_turno)
       from public.plantillas_tarea p join public.centros_trabajo c on c.id = p.centro_id
      where p.codigo = 'revisa_atascados' and c.tipo = 'tienda'));
  perform pg_temp.comprobar('Lo de Donosti, Rentería y Durango va directo a Administración; lo de las demás se ofrece',
    (select string_agg(c.codigo, ',' order by c.codigo) from public.configuracion k join public.centros_trabajo c on c.id = k.centro_id
      where k.clave = 'atascados' and k.valor #>> '{}' = 'administracion') = 'DONOSTI,DURANGO,RENTERIA'
    and (select count(*) = 5 from public.configuracion k where k.clave = 'atascados' and k.valor #>> '{}' = 'ofrecer'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-15', '11:05'));
  perform pg_temp.comprobar('El martes sale en la lista de Basauri con su tipo «atascados»',
    exists (select 1 from jsonb_array_elements(r -> 'tareas') t
             where t ->> 'clave' = 'revisa_atascados' and t ->> 'titulo' = 'Revisa los productos atascados'
               and t ->> 'tipo' = 'atascados' and t -> 'atascados' = '[]'::jsonb),
    r ->> 'tareas');
  perform pg_temp.comprobar('Y en Donosti también; el miércoles no sale',
    pg_temp.tarea('00000000-0000-4000-b000-000000000003', '2026-12-15') is not null
    and pg_temp.tarea(basauri, '2026-12-16') is null);
  perform pg_temp.comprobar('Sin nadie en el turno: SIN_PERSONA',
    pg_temp.err(motor.revisar_atascados_de(basauri, pg_temp.tarea(basauri, '2026-12-15'), '[]', pg_temp.a('2026-12-15', '11:05'))) = 'SIN_PERSONA');
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-15', '10:55'));
  perform motor.empezar_turno_tienda_de('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-c000-000000000002', pg_temp.a('2026-12-15', '10:55'));
  perform motor.empezar_turno_tienda_de('00000000-0000-4000-b000-000000000003', '00000000-0000-4000-c000-000000000004', pg_temp.a('2026-12-15', '10:55'));
  perform motor.empezar_turno_tienda_de('00000000-0000-4000-b000-000000000005', '00000000-0000-4000-c000-000000000006', pg_temp.a('2026-12-15', '10:55'));
end $$;

do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  t uuid := pg_temp.tarea('00000000-0000-4000-b000-000000000001', '2026-12-15');
  ahora timestamptz := pg_temp.a('2026-12-15', '11:05');
  r jsonb;
begin
  perform pg_temp.comprobar('Un producto que no está en la lista: DATOS_NO_VALIDOS',
    pg_temp.err(motor.revisar_atascados_de(basauri, t, '[{"producto": "NADA", "formato": "4g"}]', ahora)) = 'DATOS_NO_VALIDOS');
  perform pg_temp.comprobar('Un formato que no tiene ese producto: DATOS_NO_VALIDOS',
    pg_temp.err(motor.revisar_atascados_de(basauri, t, '[{"producto": "BZ1", "formato": "10g"}]', ahora)) = 'DATOS_NO_VALIDOS');
  perform pg_temp.comprobar('Cero cajas o el mismo producto dos veces: DATOS_NO_VALIDOS',
    pg_temp.err(motor.revisar_atascados_de(basauri, t, '[{"producto": "V2", "formato": "4g", "cantidad": 0}]', ahora)) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.revisar_atascados_de(basauri, t,
          '[{"producto": "V2", "formato": "4g"}, {"producto": "V2", "formato": "4g", "cantidad": 2}]', ahora)) = 'DATOS_NO_VALIDOS');
  r := motor.revisar_atascados_de(basauri, t,
         '[{"producto": "V2", "formato": "4g", "cantidad": 3, "nota": "  Caducan  en marzo "},
           {"producto": "CREMA", "formato": "", "cantidad": 1},
           {"producto": "BZ1", "formato": "4g"}]', ahora);
  perform pg_temp.comprobar('Basauri apunta tres: la tarea queda hecha y con lo apuntado, ofrecido a las demás',
    (select estado = 'hecha' and resultado = 'Atascados: 3' from public.tareas where id = t)
    and jsonb_array_length(r -> 'atascados') = 3
    and (select bool_and(x ->> 'estado' = 'ofrecido'
                         and x ->> 'estado_texto' = 'Ofrecido a las demás tiendas hasta el cierre del 15/12')
           from jsonb_array_elements(r -> 'atascados') x)
    and exists (select 1 from jsonb_array_elements(r -> 'tareas') x, jsonb_array_elements(x -> 'atascados') y
                 where x ->> 'clave' = 'revisa_atascados' and y ->> 'texto' = '3 cajas de V2 4g'
                   and y ->> 'nota' = 'Caducan en marzo' and y ->> 'por' = 'Ane Prueba'),
    r::text);
  perform pg_temp.comprobar('No se ofrece a sí misma; no le llega nada a Administración',
    r -> 'ofertas_atascados' = '[]'::jsonb
    and not exists (select 1 from public.incidencias where opcion = 'atascado'));
  -- Portugalete: dos cajas de V2 10g.
  perform motor.revisar_atascados_de('00000000-0000-4000-b000-000000000002',
    pg_temp.tarea('00000000-0000-4000-b000-000000000002', '2026-12-15'),
    '[{"producto": "V2", "formato": "10g", "cantidad": 2}]', pg_temp.a('2026-12-15', '11:10'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. Las ofertas, «Las quiero» y la franquicia que tiene un atascado
-- ---------------------------------------------------------------------------
do $$
declare
  portu constant uuid := '00000000-0000-4000-b000-000000000002';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  r jsonb;
begin
  r := motor.tienda_hoy_de(portu, pg_temp.a('2026-12-15', '11:30'));
  perform pg_temp.comprobar('Portugalete ve las tres ofertas de Basauri (no la suya), con su pregunta',
    jsonb_array_length(r -> 'ofertas_atascados') = 3
    and exists (select 1 from jsonb_array_elements(r -> 'ofertas_atascados') x
                 where x ->> 'texto' = 'Basauri tiene 3 cajas de V2 4g que no se mueven: ¿las quieres?' and x ->> 'nota' = 'Caducan en marzo')
    and exists (select 1 from jsonb_array_elements(r -> 'ofertas_atascados') x
                 where x ->> 'texto' = 'Basauri tiene 1 caja de CREMA que no se mueve: ¿la quieres?'),
    r ->> 'ofertas_atascados');
  r := motor.tienda_hoy_de(renteria, pg_temp.a('2026-12-15', '11:30'));
  perform pg_temp.comprobar('Las franquicias también las ven (las de Basauri y la de Portugalete)',
    jsonb_array_length(r -> 'ofertas_atascados') = 4, r ->> 'ofertas_atascados');

  -- Donosti, franquicia: va directo a Administración.
  r := motor.revisar_atascados_de(donosti, pg_temp.tarea(donosti, '2026-12-15'),
         '[{"producto": "BZ1", "formato": "4g", "cantidad": 2}]', pg_temp.a('2026-12-15', '11:40'));
  perform pg_temp.comprobar('Lo de Donosti no se ofrece: va directo a Administración, como incidencia abierta',
    r -> 'atascados' -> 0 ->> 'estado' = 'administracion' and r -> 'atascados' -> 0 ->> 'estado_texto' = 'Decide Administración'
    and exists (select 1 from jsonb_array_elements(motor.incidencias_tiendas_de(pg_temp.a('2026-12-15', '11:40')) -> 'incidencias') x
                 where x ->> 'tienda' = 'Donosti' and x ->> 'opcion' = 'atascado' and x ->> 'estado' = 'abierta'
                   and x ->> 'texto' = 'Atascado: 2 cajas de BZ1 4g (Nora Prueba)'
                   and x -> 'atascado' -> 'decisiones' = '["promocion", "recogida"]'::jsonb)
    and jsonb_array_length(motor.tienda_hoy_de(portu, pg_temp.a('2026-12-15', '11:45')) -> 'ofertas_atascados') = 3,
    r::text);
  perform pg_temp.comprobar('Donosti no lo ve repetido en sus incidencias',
    r -> 'incidencias' = '[]'::jsonb, r ->> 'incidencias');
end $$;

do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  portu constant uuid := '00000000-0000-4000-b000-000000000002';
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  v2 uuid := pg_temp.atascado('BASAURI', 'V2', '4g');
  r jsonb;
begin
  perform pg_temp.comprobar('Su propia oferta no la puede pedir',
    pg_temp.err(motor.querer_atascado_de(basauri, v2, pg_temp.a('2026-12-15', '12:00'))) = 'NO_ENCONTRADO');
  r := motor.querer_atascado_de(renteria, v2, pg_temp.a('2026-12-15', '12:00'));
  perform pg_temp.comprobar('Rentería pide el V2 4g: lo ve en lo que ha pedido y deja de ser una oferta',
    r -> 'atascados_pedidos' -> 0 ->> 'estado_texto' = 'Lo has pedido: el almacén lo recoge en Basauri y va en tu siguiente envío'
    and not exists (select 1 from jsonb_array_elements(r -> 'ofertas_atascados') x where (x ->> 'id')::uuid = v2), r::text);
  r := motor.querer_atascado_de(portu, v2, pg_temp.a('2026-12-15', '12:01'));
  perform pg_temp.comprobar('Se lo lleva la primera: Portugalete llega tarde',
    pg_temp.err(r) = 'ESTADO_NO_VALIDO' and r -> 'error' ->> 'mensaje' = 'Ya lo ha pedido Rentería.', r::text);
  perform pg_temp.comprobar('Repetir «Las quiero» desde Rentería no hace nada nuevo',
    motor.querer_atascado_de(renteria, v2, pg_temp.a('2026-12-15', '12:02')) ? 'atascados_pedidos'
    and (select count(*) = 1 from public.incidencias where opcion = 'recogida_atascado'));
  -- Portugalete pide el BZ1 4g de Basauri.
  perform motor.querer_atascado_de(portu, pg_temp.atascado('BASAURI', 'BZ1', '4g'), pg_temp.a('2026-12-15', '12:10'));

  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-15', '12:15'));
  perform pg_temp.comprobar('Basauri: «Lo quiere Rentería: prepáralo para recogida» y el aviso del almacén',
    exists (select 1 from jsonb_array_elements(r -> 'atascados') x
             where x ->> 'texto' = '3 cajas de V2 4g' and x ->> 'estado' = 'por_recoger'
               and x ->> 'estado_texto' = 'Lo quiere Rentería: prepáralo para recogida')
    and exists (select 1 from jsonb_array_elements(r -> 'avisos') x
                 where x ->> 'texto' = 'Prepara 3 cajas de V2 4g para recogida' and x ->> 'de' = 'Almacén')
    and exists (select 1 from jsonb_array_elements(r -> 'avisos') x
                 where x ->> 'texto' = 'Prepara 1 caja de BZ1 4g para recogida'),
    r::text);
  perform pg_temp.comprobar('Eder tiene dos incidencias de recogida, sin hora y sin tocar el reparto',
    exists (select 1 from jsonb_array_elements(pg_temp.recogidas()) x
             where x ->> 'descripcion' = 'Recoge 3 cajas de V2 4g en Basauri y llévalo al almacén: va en el siguiente envío a Rentería'
               and x ->> 'opcion' = 'recogida_atascado' and x ->> 'importancia' is null and x ->> 'tarea_id' is null
               and x ->> 'estado_texto' = 'Sin hora: cuando puedas, sin tocar el reparto. Ciérrala al entregarlo')
    and exists (select 1 from jsonb_array_elements(pg_temp.recogidas()) x
                 where x ->> 'descripcion' = 'Recoge 1 caja de BZ1 4g en Basauri y llévalo a Portugalete'),
    pg_temp.recogidas()::text);
  perform pg_temp.comprobar('El reparto de Eder no cambia: las mismas tareas y la misma tarea activa',
    (select count(*) from public.tareas t join public.jornadas j on j.id = t.jornada_id
      where j.persona_id = '00000000-0000-4000-a000-000000000001' and j.fecha in ('2026-12-15', '2026-12-16'))
      = (select (v #>> '{}')::int from _v where k = 'tareas_almacen')
    and motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a('2026-12-15', '11:00')) -> 'id'
        is not distinct from (select v from _v where k = 'activa_almacen')
    and motor.seguimiento_de('00000000-0000-4000-a000-000000000001', pg_temp.a('2026-12-15', '12:15')) -> 'incidencia_en_curso' = 'null'::jsonb);
end $$;

-- ---------------------------------------------------------------------------
-- 3. El miércoles: lo que nadie ha pedido llega a Administración
-- ---------------------------------------------------------------------------
do $$
declare
  portu constant uuid := '00000000-0000-4000-b000-000000000002';
  r jsonb;
begin
  perform pg_temp.comprobar('Hasta el cierre del martes no llega a Administración',
    (select count(*) = 1 from public.incidencias where opcion = 'atascado'));
  perform motor.vencer_atascados(pg_temp.a('2026-12-16', '09:00'));
  r := motor.incidencias_tiendas_de(pg_temp.a('2026-12-16', '09:00'));
  perform pg_temp.comprobar('El miércoles a las 9:00, la crema de Basauri y el V2 10g de Portugalete, con «promoción o al almacén»',
    exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
             where x ->> 'tienda' = 'Basauri' and x ->> 'texto' = 'Atascado: 1 caja de CREMA, nadie lo ha pedido (Ane Prueba)'
               and x -> 'atascado' -> 'decisiones' = '["promocion", "almacen"]'::jsonb
               and x -> 'atascado' ->> 'estado_texto' = 'Nadie lo ha pedido: decide Administración')
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
                 where x ->> 'tienda' = 'Portugalete' and x ->> 'texto' = 'Atascado: 2 cajas de V2 10g, nadie lo ha pedido (Leire Prueba)')
    and (select count(*) = 3 from public.incidencias where opcion = 'atascado'),
    r::text);
  r := motor.querer_atascado_de(portu, pg_temp.atascado('BASAURI', 'CREMA', ''), pg_temp.a('2026-12-16', '11:05'));
  perform pg_temp.comprobar('El miércoles ya no se puede pedir',
    pg_temp.err(r) in ('ESTADO_NO_VALIDO', 'SIN_PERSONA'), r::text);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Administración decide
-- ---------------------------------------------------------------------------
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  crema uuid := pg_temp.atascado('BASAURI', 'CREMA', '');
  ahora timestamptz := pg_temp.a('2026-12-16', '09:30');
  r jsonb;
begin
  perform pg_temp.comprobar('Para una propia: ni recogida ni promoción sin texto',
    pg_temp.err(motor.decidir_atascado_de(adm, crema, 'recogida', 'x', ahora)) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.decidir_atascado_de(adm, crema, 'promocion', '  ', ahora)) = 'DATOS_NO_VALIDOS');
  r := motor.decidir_atascado_de(adm, crema, 'promocion', 'Segunda unidad a mitad de precio', ahora);
  perform pg_temp.comprobar('Promoción: la incidencia queda cerrada con la decisión',
    exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
             where x -> 'atascado' ->> 'id' = crema::text and x ->> 'estado' = 'cerrada'
               and x ->> 'nota' = 'Promoción: Segunda unidad a mitad de precio'
               and x -> 'atascado' ->> 'estado' = 'promocion' and x -> 'atascado' -> 'decisiones' = '[]'::jsonb),
    r::text);
  perform pg_temp.comprobar('Decidir otra vez: ESTADO_NO_VALIDO',
    pg_temp.err(motor.decidir_atascado_de(adm, crema, 'almacen', null, ahora)) = 'ESTADO_NO_VALIDO');
  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-16', '11:05'));
  perform pg_temp.comprobar('Basauri recibe el aviso de Administración y tiene la promoción abierta',
    exists (select 1 from jsonb_array_elements(r -> 'avisos') x
             where x ->> 'texto' = 'Promoción de 1 caja de CREMA: Segunda unidad a mitad de precio' and x ->> 'de' = 'Administración')
    and r -> 'promociones' -> 0 ->> 'promocion' = 'Segunda unidad a mitad de precio'
    and r -> 'promociones' -> 0 ->> 'texto' = '1 caja de CREMA',
    r::text);
end $$;

do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  crema uuid := pg_temp.atascado('BASAURI', 'CREMA', '');
  bz1 uuid := pg_temp.atascado('DONOSTI', 'BZ1', '4g');
  v210 uuid := pg_temp.atascado('PORTU', 'V2', '10g');
  r jsonb;
begin
  perform pg_temp.comprobar('«Ya no queda» sin nadie en el turno: SIN_PERSONA',
    pg_temp.err(motor.ya_no_queda_de(basauri, crema, pg_temp.a('2026-12-16', '11:06'))) = 'SIN_PERSONA');
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-16', '10:55'));
  r := motor.ya_no_queda_de(basauri, crema, pg_temp.a('2026-12-16', '18:00'));
  perform pg_temp.comprobar('«Ya no queda» cierra la promoción',
    r -> 'promociones' = '[]'::jsonb
    and exists (select 1 from jsonb_array_elements(r -> 'atascados') x
                 where (x ->> 'id')::uuid = crema and x ->> 'estado' = 'terminado'
                   and x ->> 'estado_texto' = 'Promoción terminada: ya no queda')
    and (select terminado_por = 'Ane Prueba' from public.atascados where id = crema), r::text);

  -- Donosti: recogida (la organiza Administración).
  perform pg_temp.comprobar('Para una franquicia: no hay «al almacén»',
    pg_temp.err(motor.decidir_atascado_de(adm, bz1, 'almacen', null, pg_temp.a('2026-12-16', '09:40'))) = 'DATOS_NO_VALIDOS');
  r := motor.decidir_atascado_de(adm, bz1, 'recogida', 'La recoge el transportista el viernes', pg_temp.a('2026-12-16', '09:40'));
  perform pg_temp.comprobar('Recogida: se cierra con su nota y a Eder no le sale nada',
    exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
             where x -> 'atascado' ->> 'id' = bz1::text and x ->> 'estado' = 'cerrada'
               and x ->> 'nota' = 'Recogida: La recoge el transportista el viernes' and x -> 'atascado' ->> 'estado' = 'cerrado')
    and not exists (select 1 from jsonb_array_elements(pg_temp.recogidas()) x where x ->> 'descripcion' like '%Donosti%')
    and motor.tienda_hoy_de('00000000-0000-4000-b000-000000000003', pg_temp.a('2026-12-16', '11:00')) -> 'atascados' -> 0 ->> 'estado_texto'
        = 'Recogida: la organiza Administración (La recoge el transportista el viernes)',
    r::text);

  -- Portugalete: al almacén.
  r := motor.decidir_atascado_de(adm, v210, 'almacen', null, pg_temp.a('2026-12-16', '09:45'));
  perform pg_temp.comprobar('Al almacén: recogida para Eder y aviso de Administración a Portugalete',
    exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
             where x -> 'atascado' ->> 'id' = v210::text and x ->> 'nota' = 'Al almacén')
    and exists (select 1 from jsonb_array_elements(pg_temp.recogidas()) x
                 where x ->> 'descripcion' = 'Recoge 2 cajas de V2 10g en Portugalete y llévalo al almacén')
    and exists (select 1 from jsonb_array_elements(motor.tienda_hoy_de('00000000-0000-4000-b000-000000000002',
                                                                       pg_temp.a('2026-12-16', '11:00')) -> 'avisos') x
                 where x ->> 'texto' = 'Prepara 2 cajas de V2 10g para recogida' and x ->> 'de' = 'Administración'),
    pg_temp.recogidas()::text);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Eder lo entrega; lo de Rentería, en el siguiente envío a Gipuzkoa
-- ---------------------------------------------------------------------------
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  inc uuid;
  r jsonb;
  e jsonb;
  pet jsonb;
begin
  for inc in select (x ->> 'id')::uuid from jsonb_array_elements(pg_temp.recogidas()) x loop
    perform motor.cerrar_incidencia_de(op, inc, 'Entregado', pg_temp.a('2026-12-16', '10:30'));
  end loop;
  perform pg_temp.comprobar('Las tres recogidas, entregadas',
    (select count(*) = 3 from public.atascados where estado = 'entregado')
    and pg_temp.recogidas() = '[]'::jsonb);
  r := motor.tienda_hoy_de('00000000-0000-4000-b000-000000000005', pg_temp.a('2026-12-16', '11:00'));
  perform pg_temp.comprobar('Rentería: queda como petición para su siguiente envío',
    r -> 'atascados_pedidos' -> 0 ->> 'estado_texto' = 'Pendiente: irá en el siguiente envío'
    and exists (select 1 from jsonb_array_elements(r -> 'peticiones') x
                 where x ->> 'tipo' = 'atascado' and x ->> 'texto' = 'Rentería · Atascado de Basauri: 3 cajas de V2 4g'
                   and x ->> 'pedida_por' = 'Maite Prueba'),
    r::text);
  pet := motor.peticiones_pendientes_de('envio');
  perform pg_temp.comprobar('Y sale en las peticiones del envío a Gipuzkoa (no en las del reparto)',
    exists (select 1 from jsonb_array_elements(pet -> 'peticiones') x
             where (x ->> 'destino_id')::uuid = pg_temp.d('GIPUZKOA') and x ->> 'tipo' = 'atascado' and x ->> 'tienda' = 'Rentería')
    and not exists (select 1 from jsonb_array_elements(motor.peticiones_pendientes_de('reparto') -> 'peticiones') x
                     where x ->> 'tipo' = 'atascado'),
    pet::text);
  r := motor.tienda_hoy_de('00000000-0000-4000-b000-000000000002', pg_temp.a('2026-12-16', '11:00'));
  perform pg_temp.comprobar('Portugalete (por reparto): entregado, sin petición',
    r -> 'atascados_pedidos' -> 0 ->> 'estado_texto' = 'Entregado el 16/12'
    and not exists (select 1 from public.peticiones_tienda where centro_id = pg_temp.d('PORTU') and tipo = 'atascado'),
    r ->> 'atascados_pedidos');
  -- El envío de la tarde la lleva (como las muestras y el material).
  e := pg_temp.envio('2026-12-16');
  perform public.servidor_guardar_peticiones('00000000-0000-4000-a000-000000000002', (e ->> 'reparto_id')::uuid,
    jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'),
                                         'texto', 'Rentería · Atascado de Basauri: 3 cajas de V2 4g')),
    pg_temp.a('2026-12-16', '15:41'));
  perform pg_temp.comprobar('Al guardar el envío con ella, la petición queda atendida',
    (select estado = 'atendida' from public.peticiones_tienda where tipo = 'atascado')
    and motor.tienda_hoy_de('00000000-0000-4000-b000-000000000005', pg_temp.a('2026-12-16', '16:00')) -> 'atascados_pedidos' -> 0 ->> 'estado_texto'
        = 'Va en el envío de hoy',
    e::text);
end $$;

-- ---------------------------------------------------------------------------
-- 6. «Nada atascado esta semana» y permisos
-- ---------------------------------------------------------------------------
do $$
declare
  renteria constant uuid := '00000000-0000-4000-b000-000000000005';
  t uuid := pg_temp.tarea('00000000-0000-4000-b000-000000000005', '2026-12-15');
begin
  perform motor.revisar_atascados_de(renteria, t, '[]', pg_temp.a('2026-12-15', '12:30'));
  perform pg_temp.comprobar('«Nada atascado esta semana» cierra la tarea sin apuntar nada',
    (select estado = 'hecha' and resultado = 'Nada atascado esta semana' from public.tareas where id = t)
    and not exists (select 1 from public.atascados where centro_id = pg_temp.d('RENTERIA')));
end $$;

select pg_temp.como('00000000-0000-4000-b000-000000000001');  -- Basauri
select pg_temp.comprobar('Una tienda no decide por Administración',
  public.decidir_atascado(gen_random_uuid(), 'promocion', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
select pg_temp.comprobar('Una tienda lee lo suyo y lo que ha pedido, no lo de las demás',
  (select count(*) from public.atascados) = 3);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario no usa las funciones de la tableta',
  public.querer_atascado(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.revisar_atascados(gen_random_uuid(), '[]') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.ya_no_queda(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.querer_atascado(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.decidir_atascado(uuid, text, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.decidir_atascado_de(uuid, uuid, text, text, timestamptz)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.atascados', 'INSERT'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
