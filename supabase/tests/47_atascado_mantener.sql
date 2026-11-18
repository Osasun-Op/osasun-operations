-- Prueba 47 · Atascados: «Mantener» en la tienda (T-0014 · Tarea 42; decisión del propietario, 18/11/2026).
-- El martes 15/12/2026 Basauri (propia) apunta V2 4g y BZ1 4g, que nadie pide; Donosti (franquicia) apunta V2 10g y
-- CREMA, que van directo a Administración. El miércoles 16/12 Administración decide «mantener» con y sin texto en las
-- dos: se cierra, sin aviso ni recogida, con «Se queda en la tienda». Al final, las dos de pruebas del 18/11 que se
-- corrigen en la migración (solo en pruebas). Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha.

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
create temp table _v (k text primary key, v jsonb) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.a(p_fecha date, p_hora time) returns timestamptz language sql as $$ select motor.en_local(p_fecha, p_hora) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;
create function pg_temp.tarea(p_persona uuid, p_fecha date) returns uuid language sql as $$
  select t.id from public.tareas t join public.jornadas j on j.id = t.jornada_id
   where j.persona_id = p_persona and j.fecha = p_fecha and t.clave = 'revisa_atascados' $$;
-- Lo que apunta la tienda de la prueba (por su tarea: en pruebas, las tiendas tienen también atascados de verdad).
create function pg_temp.atascado(p_persona uuid, p_producto text, p_formato text) returns uuid language sql as $$
  select a.id from public.atascados a where a.tarea_id = pg_temp.tarea(p_persona, '2026-12-15')
     and a.producto = p_producto and a.formato = p_formato $$;
create function pg_temp.en_panel(p_atascado uuid, p_ahora timestamptz) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.incidencias_tiendas_de(p_ahora) -> 'incidencias') x
   where x -> 'atascado' ->> 'id' = p_atascado::text $$;
create function pg_temp.en_tienda(p_tienda text, p_atascado uuid, p_ahora timestamptz) returns jsonb language sql as $$
  select x from jsonb_array_elements(motor.atascados_tienda_json(pg_temp.d(p_tienda), p_ahora) -> 'atascados') x
   where x ->> 'id' = p_atascado::text $$;

-- ---------------------------------------------------------------------------
-- 0. Las dos de pruebas del 18/11, como las deja la migración (antes de tocar nada; solo en pruebas)
-- ---------------------------------------------------------------------------
do $$
declare
  es_pruebas boolean := coalesce((select valor #>> '{}' from public.configuracion where clave = 'entorno' and centro_id is null), '') = 'pruebas';
  spray constant uuid := '0a362adf-bb52-440b-8d07-7f57b03efe69';
  ice constant uuid := '8d057ab4-0be4-46ec-8252-6a4096515a5e';
  r jsonb;
begin
  if not es_pruebas or not exists (select 1 from public.atascados where id in (spray, ice)) then
    perform pg_temp.comprobar('Datos de pruebas: no es el proyecto de pruebas (o no están); no se comprueban', true);
    return;
  end if;
  perform pg_temp.comprobar('Basauri, 3 SPRAY BUCAL: «mantener» con el mismo texto, y la nota de su incidencia como la de «mantener»',
    (select a.estado = 'cerrado' and a.decision = 'mantener' and a.decision_texto = 'De momento dejalas'
            and i.estado = 'cerrada' and i.nota_cierre = 'Se queda en la tienda: De momento dejalas'
       from public.atascados a join public.incidencias i on i.id = a.incidencia_id where a.id = spray));
  perform pg_temp.comprobar('Barakaldo, 1 ICE O LATOR 10g: igual',
    (select a.estado = 'cerrado' and a.decision = 'mantener' and a.decision_texto = 'Siempre hay q tener 1 por si acaso'
            and i.nota_cierre = 'Se queda en la tienda: Siempre hay q tener 1 por si acaso'
       from public.atascados a join public.incidencias i on i.id = a.incidencia_id where a.id = ice));
  perform pg_temp.comprobar('Su aviso de promoción ya no está pendiente',
    not exists (select 1 from public.atascados a join public.incidencias av on av.id = a.aviso_id
                 where a.id in (spray, ice) and av.estado <> 'cerrada'));
  r := motor.atascados_tienda_json(pg_temp.d('BASAURI'), now());
  perform pg_temp.comprobar('En Basauri ya no sale como promoción abierta, sino «Se queda en la tienda: …»',
    not exists (select 1 from jsonb_array_elements(r -> 'promociones') x where (x ->> 'id')::uuid = spray)
    and exists (select 1 from jsonb_array_elements(r -> 'atascados') x
                 where (x ->> 'id')::uuid = spray and x ->> 'estado_texto' = 'Se queda en la tienda: De momento dejalas'),
    r::text);
  perform pg_temp.comprobar('En Barakaldo, igual',
    not exists (select 1 from jsonb_array_elements(motor.atascados_tienda_json(pg_temp.d('BARAKALDO'), now()) -> 'promociones') x
                 where (x ->> 'id')::uuid = ice));
  perform pg_temp.comprobar('Las de EGUZKI de Portugalete y Rentería siguen en promoción',
    (select count(*) = 2 from public.atascados where producto = 'EGUZKI' and decision = 'promocion' and estado = 'promocion'
        and centro_id in (pg_temp.d('PORTU'), pg_temp.d('RENTERIA'))));
end $$;

-- Aísla la prueba de las cuentas y los nombres reales de las tiendas. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.donosti@osasun.invalid", "nombre": "Donosti", "rol": "tienda", "centro": "DONOSTI"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000003', 'tienda.donosti@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000004', pg_temp.d('DONOSTI'), 'Nora Prueba', 'siempre', null);
-- La última lectura de la hoja (la lista de la tableta).
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-15 08:00+01', 'stock', true, '{
  "productos": [
    {"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}, {"formato": "10g", "almacen": "3"}]},
    {"nombre": "BZ1", "orden": 2, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "5"}]},
    {"nombre": "CREMA", "orden": 3, "conTiendas": true, "formatos": []}],
  "categorias": {"V2": "Indoor", "BZ1": "Invernadero"}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');
select motor.generar_jornada(x.p, x.f)
  from (values ('00000000-0000-4000-b000-000000000001'::uuid), ('00000000-0000-4000-b000-000000000003'),
               ('00000000-0000-4000-a000-000000000001')) p(p)
  cross join (values ('2026-12-15'::date), ('2026-12-16')) f(f)
  cross join lateral (select p.p, f.f) x;

-- ---------------------------------------------------------------------------
-- 1. El martes: Basauri apunta dos (nadie las pide) y Donosti dos (directo a Administración)
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
begin
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('2026-12-15', '10:55'));
  perform motor.empezar_turno_tienda_de(donosti, '00000000-0000-4000-c000-000000000004', pg_temp.a('2026-12-15', '10:55'));
  perform motor.revisar_atascados_de(basauri, pg_temp.tarea(basauri, '2026-12-15'),
    '[{"producto": "V2", "formato": "4g", "cantidad": 3}, {"producto": "BZ1", "formato": "4g"}]', pg_temp.a('2026-12-15', '11:05'));
  perform motor.revisar_atascados_de(donosti, pg_temp.tarea(donosti, '2026-12-15'),
    '[{"producto": "V2", "formato": "10g", "cantidad": 2}, {"producto": "CREMA", "formato": ""}]', pg_temp.a('2026-12-15', '11:10'));
  perform pg_temp.comprobar('Se apuntan los cuatro',
    (select count(*) = 4 from public.atascados where tarea_id in (pg_temp.tarea(basauri, '2026-12-15'), pg_temp.tarea(donosti, '2026-12-15'))));
end $$;

-- Lo de antes de decidir, para comparar: los avisos de las dos tiendas y las recogidas de Eder.
insert into _v select 'avisos', to_jsonb(count(*)) from public.incidencias
 where opcion = 'aviso' and persona_id in ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-b000-000000000003');
insert into _v select 'recogidas', to_jsonb(count(*)) from public.incidencias where opcion = 'recogida_atascado';

-- ---------------------------------------------------------------------------
-- 2. El miércoles: «mantener» entre las decisiones, en las dos
-- ---------------------------------------------------------------------------
do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  ahora timestamptz := pg_temp.a('2026-12-16', '09:00');
begin
  perform motor.vencer_atascados(ahora);
  perform pg_temp.comprobar('Propia (Basauri): promoción, al almacén o mantener',
    pg_temp.en_panel(pg_temp.atascado(basauri, 'V2', '4g'), ahora) -> 'atascado' -> 'decisiones'
      = '["promocion", "almacen", "mantener"]'::jsonb
    and pg_temp.en_panel(pg_temp.atascado(basauri, 'BZ1', '4g'), ahora) ->> 'estado' = 'abierta',
    pg_temp.en_panel(pg_temp.atascado(basauri, 'V2', '4g'), ahora)::text);
  perform pg_temp.comprobar('Franquicia (Donosti): promoción, recogida o mantener',
    pg_temp.en_panel(pg_temp.atascado(donosti, 'V2', '10g'), ahora) -> 'atascado' -> 'decisiones'
      = '["promocion", "recogida", "mantener"]'::jsonb,
    pg_temp.en_panel(pg_temp.atascado(donosti, 'V2', '10g'), ahora)::text);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Errores: la decisión que no toca nombra «mantener»; el mismo tope de texto
-- ---------------------------------------------------------------------------
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  v2 uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000001', 'V2', '4g');
  v210 uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000003', 'V2', '10g');
  ahora timestamptz := pg_temp.a('2026-12-16', '09:30');
  r jsonb;
begin
  r := motor.decidir_atascado_de(adm, v2, 'recogida', null, ahora);
  perform pg_temp.comprobar('Propia con «recogida»: DATOS_NO_VALIDOS, «Elige: promoción, al almacén o mantener.»',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and r -> 'error' ->> 'mensaje' = 'Elige: promoción, al almacén o mantener.', r::text);
  r := motor.decidir_atascado_de(adm, v210, 'almacen', null, ahora);
  perform pg_temp.comprobar('Franquicia con «almacen»: DATOS_NO_VALIDOS, «Elige: promoción, recogida o mantener.»',
    pg_temp.err(r) = 'DATOS_NO_VALIDOS' and r -> 'error' ->> 'mensaje' = 'Elige: promoción, recogida o mantener.', r::text);
  perform pg_temp.comprobar('Sin decisión o con otra palabra: DATOS_NO_VALIDOS',
    pg_temp.err(motor.decidir_atascado_de(adm, v2, null, null, ahora)) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(motor.decidir_atascado_de(adm, v2, 'quedarse', null, ahora)) = 'DATOS_NO_VALIDOS');
  perform pg_temp.comprobar('«Mantener» con más de 180 letras: DATOS_NO_VALIDOS, y no decide nada',
    pg_temp.err(motor.decidir_atascado_de(adm, v2, 'mantener', repeat('a', 181), ahora)) = 'DATOS_NO_VALIDOS'
    and (select estado = 'administracion' and decision is null from public.atascados where id = v2));
end $$;

-- ---------------------------------------------------------------------------
-- 4. «Mantener» en una propia, con texto y sin texto
-- ---------------------------------------------------------------------------
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  v2 uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000001', 'V2', '4g');
  bz1 uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000001', 'BZ1', '4g');
  ahora timestamptz := pg_temp.a('2026-12-16', '09:30');
  r jsonb;
  x jsonb;
begin
  r := motor.decidir_atascado_de(adm, v2, 'mantener', '  De momento   déjalas ', ahora);
  x := (select i from jsonb_array_elements(r -> 'incidencias') i where i -> 'atascado' ->> 'id' = v2::text);
  perform pg_temp.comprobar('Con texto: la incidencia se cierra con «Se queda en la tienda: De momento déjalas»',
    x ->> 'estado' = 'cerrada' and x ->> 'nota' = 'Se queda en la tienda: De momento déjalas'
    and x -> 'atascado' ->> 'estado' = 'cerrado' and x -> 'atascado' ->> 'decision' = 'mantener'
    and x -> 'atascado' -> 'decisiones' = '[]'::jsonb
    and x -> 'atascado' ->> 'estado_texto' = 'Se queda en la tienda: De momento déjalas',
    coalesce(x::text, r::text));
  perform pg_temp.comprobar('El atascado queda cerrado, con la decisión, su texto y quién y cuándo',
    (select estado = 'cerrado' and decision = 'mantener' and decision_texto = 'De momento déjalas'
            and decidido_por = adm and decidido_en = ahora and aviso_id is null and recogida_id is null
       from public.atascados where id = v2));
  perform pg_temp.comprobar('Queda en el registro, como las demás decisiones',
    exists (select 1 from public.registro_eventos where tipo = 'atascado_decidido' and persona_id = adm
               and datos ->> 'atascado' = v2::text and datos ->> 'decision' = 'mantener'));

  r := motor.decidir_atascado_de(adm, bz1, 'mantener', null, pg_temp.a('2026-12-16', '09:31'));
  perform pg_temp.comprobar('Sin texto: «Se queda en la tienda»',
    pg_temp.en_panel(bz1, pg_temp.a('2026-12-16', '09:31')) ->> 'nota' = 'Se queda en la tienda'
    and (select estado = 'cerrado' and decision = 'mantener' and decision_texto is null from public.atascados where id = bz1),
    pg_temp.en_panel(bz1, pg_temp.a('2026-12-16', '09:31'))::text);

  r := motor.tienda_hoy_de(basauri, pg_temp.a('2026-12-16', '11:05'));
  perform pg_temp.comprobar('Basauri lo ve en su lista con «Se queda en la tienda» y no como promoción',
    exists (select 1 from jsonb_array_elements(r -> 'atascados') a
             where (a ->> 'id')::uuid = v2 and a ->> 'estado_texto' = 'Se queda en la tienda: De momento déjalas')
    and exists (select 1 from jsonb_array_elements(r -> 'atascados') a
                 where (a ->> 'id')::uuid = bz1 and a ->> 'estado_texto' = 'Se queda en la tienda')
    and not exists (select 1 from jsonb_array_elements(r -> 'promociones') p where (p ->> 'id')::uuid in (v2, bz1)),
    r::text);
end $$;

-- ---------------------------------------------------------------------------
-- 5. «Mantener» en una franquicia, sin texto y con texto
-- ---------------------------------------------------------------------------
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  v210 uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000003', 'V2', '10g');
  crema uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000003', 'CREMA', '');
  ahora timestamptz := pg_temp.a('2026-12-16', '09:40');
  r jsonb;
begin
  perform motor.decidir_atascado_de(adm, v210, 'mantener', null, ahora);
  perform motor.decidir_atascado_de(adm, crema, 'mantener', 'Siempre hay que tener 1', ahora);
  perform pg_temp.comprobar('Las dos de Donosti, cerradas con su nota',
    pg_temp.en_panel(v210, ahora) ->> 'nota' = 'Se queda en la tienda'
    and pg_temp.en_panel(crema, ahora) ->> 'nota' = 'Se queda en la tienda: Siempre hay que tener 1'
    and (select bool_and(estado = 'cerrado' and decision = 'mantener') from public.atascados where id in (v210, crema)));
  r := motor.tienda_hoy_de(donosti, pg_temp.a('2026-12-16', '11:05'));
  perform pg_temp.comprobar('Donosti las ve con «Se queda en la tienda» (no como recogida)',
    exists (select 1 from jsonb_array_elements(r -> 'atascados') a
             where (a ->> 'id')::uuid = v210 and a ->> 'estado_texto' = 'Se queda en la tienda')
    and exists (select 1 from jsonb_array_elements(r -> 'atascados') a
                 where (a ->> 'id')::uuid = crema and a ->> 'estado_texto' = 'Se queda en la tienda: Siempre hay que tener 1'),
    r ->> 'atascados');
end $$;

-- ---------------------------------------------------------------------------
-- 6. Sin aviso a la tienda ni recogida para Eder; ya decidido; desaparece a la semana
-- ---------------------------------------------------------------------------
do $$
declare
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  v2 uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000001', 'V2', '4g');
  crema uuid := pg_temp.atascado('00000000-0000-4000-b000-000000000003', 'CREMA', '');
begin
  perform pg_temp.comprobar('Ningún aviso nuevo a las tiendas',
    (select count(*) from public.incidencias where opcion = 'aviso'
        and persona_id in ('00000000-0000-4000-b000-000000000001', '00000000-0000-4000-b000-000000000003'))
      = (select (v #>> '{}')::int from _v where k = 'avisos'));
  perform pg_temp.comprobar('Ninguna recogida para Eder',
    (select count(*) from public.incidencias where opcion = 'recogida_atascado') = (select (v #>> '{}')::int from _v where k = 'recogidas'));
  perform pg_temp.comprobar('Decidir otra vez (mantener o promoción): ESTADO_NO_VALIDO',
    pg_temp.err(motor.decidir_atascado_de(adm, v2, 'mantener', null, pg_temp.a('2026-12-16', '10:00'))) = 'ESTADO_NO_VALIDO'
    and pg_temp.err(motor.decidir_atascado_de(adm, crema, 'promocion', 'x', pg_temp.a('2026-12-16', '10:00'))) = 'ESTADO_NO_VALIDO'
    and (select decision = 'mantener' and decision_texto = 'De momento déjalas' from public.atascados where id = v2));
  perform pg_temp.comprobar('Sale en la lista de la tienda hasta una semana después de decidirlo, y luego no',
    pg_temp.en_tienda('BASAURI', v2, pg_temp.a('2026-12-23', '11:00')) is not null
    and pg_temp.en_tienda('BASAURI', v2, pg_temp.a('2026-12-24', '11:00')) is null
    and pg_temp.en_tienda('DONOSTI', crema, pg_temp.a('2026-12-24', '11:00')) is null);
  perform pg_temp.comprobar('El panel de la tienda no lo cuenta como abierto',
    not exists (select 1 from jsonb_array_elements(motor.resumen_tienda_de(pg_temp.d('BASAURI'), '2026-12-16', pg_temp.a('2026-12-16', '11:00'))
                                                    -> 'atascados') a where (a ->> 'id')::uuid = v2));
end $$;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
