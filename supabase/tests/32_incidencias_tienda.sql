-- Prueba 32 · Incidencias de tienda (Tarea 30; ESTADO_DEL_SISTEMA.md E2-8 v1.50). El miércoles 16/12/2026,
-- en Basauri (propia) y Donosti (franquicia): las opciones de cada tienda, «Me quedo sin producto» con el
-- producto, descuadre, comentario de cliente y otros (con texto), que llegan a Administración como
-- incidencia abierta y se cierran; lo que ve la tienda; la franquicia, solo texto libre (por
-- configuración); permisos; y que el almacén sigue igual.
-- Cuentas y nombres inventados (@osasun.invalid). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas en pruebas. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
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
create function pg_temp.a(p_hora time) returns timestamptz language sql as $$ select motor.en_local('2026-12-16', p_hora) $$;
create function pg_temp.a2(p_hora time) returns timestamptz language sql as $$ select motor.en_local('2026-12-17', p_hora) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.crear(p_tienda uuid, p_opcion text, p_texto text, p_producto text, p_hora time,
                              p_id uuid default gen_random_uuid())
returns jsonb language sql as $$
  select motor.crear_incidencia_tienda_de(p_tienda, p_id, p_opcion, p_texto, p_producto, pg_temp.a(p_hora)) $$;
create function pg_temp.err(r jsonb) returns text language sql as $$ select r -> 'error' ->> 'codigo' $$;

-- Cuentas de tienda (inventadas) y sus personas.
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
-- La última lectura de la hoja (la lista de productos de productos_tienda).
insert into public.lecturas_sheets (leido_en, motivo, correcto, datos) values ('2026-12-16 08:00+01', 'stock', true, '{
  "productos": [
    {"nombre": "V2", "orden": 1, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "10"}]},
    {"nombre": "BZ1", "orden": 2, "conTiendas": false, "formatos": [{"formato": "4g", "almacen": "5"}]}],
  "categorias": {"V2": "Indoor", "BZ1": "Invernadero"}, "conteo": [], "variedades": {"INDOOR": [], "INVERNADERO": []}}');

-- El almacén antes de nada: la pantalla de Eder y el panel, para compararlos al final.
insert into _v values
  ('tarea_activa', motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a('11:30'))),
  ('incidencias_operario', motor.incidencias_abiertas_de('00000000-0000-4000-a000-000000000001', pg_temp.a('11:30'))),
  ('estado_actual', motor.estado_actual_de(pg_temp.a('11:30')) -> 'incidencias_abiertas');

do $$
declare
  basauri constant uuid := '00000000-0000-4000-b000-000000000001';
  donosti constant uuid := '00000000-0000-4000-b000-000000000003';
  admin constant uuid := '00000000-0000-4000-a000-000000000002';
  r jsonb;
  c uuid := gen_random_uuid();
  v_id uuid;
begin
  -- 1. Qué opciones tiene cada tienda.
  r := motor.tienda_hoy_de(basauri, pg_temp.a('10:50'));
  perform pg_temp.comprobar('Basauri (propia): las cinco opciones, «Material de tienda» con pedir_material',
    (select jsonb_agg(x ->> 'opcion') from jsonb_array_elements(r -> 'opciones_incidencia') x)
      = '["material", "sin_producto", "descuadre", "comentario_cliente", "otros"]'::jsonb
    and r -> 'opciones_incidencia' -> 0 = '{"opcion": "material", "texto": "Material de tienda", "pide": "texto", "llama": "pedir_material"}'::jsonb
    and r -> 'opciones_incidencia' -> 1 = '{"opcion": "sin_producto", "texto": "Me quedo sin producto", "pide": "producto", "llama": "crear_incidencia_tienda"}'::jsonb
    and r -> 'incidencias' = '[]'::jsonb, r::text);
  perform pg_temp.comprobar('Donosti (franquicia): solo texto libre («Otros»)',
    motor.tienda_hoy_de(donosti, pg_temp.a('10:50')) -> 'opciones_incidencia'
      = '[{"opcion": "otros", "texto": "Otros", "pide": "texto", "llama": "crear_incidencia_tienda"}]'::jsonb);
  perform pg_temp.comprobar('El botón de llamar a Administración: el teléfono de mi_perfil, también para la tienda',
    motor.mi_perfil_de(basauri) ? 'telefono_administracion');

  -- 2. Sin nadie en el turno, pide primero quién está.
  perform pg_temp.comprobar('Sin nadie en el turno: SIN_PERSONA, sin crear nada',
    pg_temp.err(pg_temp.crear(basauri, 'otros', 'La puerta no cierra bien', null, '10:55')) = 'SIN_PERSONA'
    and not exists (select 1 from public.incidencias where persona_id = basauri));
  perform motor.empezar_turno_tienda_de(basauri, '00000000-0000-4000-c000-000000000001', pg_temp.a('10:55'));
  perform motor.empezar_turno_tienda_de(donosti, '00000000-0000-4000-c000-000000000004', pg_temp.a('10:55'));

  -- 3. Me quedo sin producto: el producto de la lista y nota opcional.
  perform pg_temp.comprobar('Sin producto: el producto tiene que ser de la lista',
    pg_temp.err(pg_temp.crear(basauri, 'sin_producto', null, null, '11:10')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(pg_temp.crear(basauri, 'sin_producto', null, 'NO EXISTE', '11:10')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(pg_temp.crear(basauri, 'sin_producto', repeat('x', 201), 'V2', '11:10')) = 'DATOS_NO_VALIDOS');
  r := pg_temp.crear(basauri, 'sin_producto', 'Del de 4g', 'V2', '11:10', c);
  perform pg_temp.comprobar('Sin producto: queda apuntado con el producto, la nota y quién está',
    r -> 'incidencias' -> 0 ->> 'texto' = 'Sin producto: V2. Del de 4g (Ane Prueba)'
    and r -> 'incidencias' -> 0 ->> 'opcion' = 'sin_producto' and r -> 'incidencias' -> 0 ->> 'a_las' = '11:10'
    and r -> 'incidencias' -> 0 ->> 'estado' = 'abierta' and r -> 'incidencias' -> 0 ->> 'estado_texto' = 'Abierta', r::text);
  r := pg_temp.crear(basauri, 'sin_producto', 'Del de 4g', 'V2', '11:11', c);
  perform pg_temp.comprobar('Repetir con el mismo id_cliente no la duplica',
    jsonb_array_length(r -> 'incidencias') = 1
    and (select count(*) from public.incidencias where persona_id = basauri and opcion = 'sin_producto') = 1);
  r := pg_temp.crear(basauri, 'sin_producto', null, 'BZ1', '11:12');
  perform pg_temp.comprobar('Sin producto, sin nota',
    r -> 'incidencias' -> 0 ->> 'texto' = 'Sin producto: BZ1 (Ane Prueba)', r::text);

  -- 4. Descuadre, comentario de cliente y otros: texto obligatorio, una o dos líneas.
  perform pg_temp.comprobar('Descuadre, comentario y otros: sin texto o demasiado largo, DATOS_NO_VALIDOS',
    pg_temp.err(pg_temp.crear(basauri, 'descuadre', '   ', null, '11:20')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(pg_temp.crear(basauri, 'comentario_cliente', null, null, '11:20')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(pg_temp.crear(basauri, 'otros', repeat('x', 301), null, '11:20')) = 'DATOS_NO_VALIDOS');
  perform pg_temp.comprobar('Opción que no existe (o el material, que va por pedir_material): DATOS_NO_VALIDOS',
    pg_temp.err(pg_temp.crear(basauri, 'material', 'Rollos', null, '11:20')) = 'DATOS_NO_VALIDOS'
    and pg_temp.err(pg_temp.crear(basauri, 'urgente', 'x', null, '11:20')) = 'DATOS_NO_VALIDOS');
  perform pg_temp.crear(basauri, 'descuadre', 'Faltan  5 €   en la caja', null, '11:25');
  perform pg_temp.crear(basauri, 'comentario_cliente', 'Un cliente pide el V2 en 10g', null, '11:30');
  r := pg_temp.crear(basauri, 'otros', 'La puerta no cierra bien', null, '11:35');
  perform pg_temp.comprobar('Descuadre, comentario de cliente y otros: con su texto y quién está, abiertas',
    (select jsonb_agg(x ->> 'texto' order by x ->> 'a_las') from jsonb_array_elements(r -> 'incidencias') x) = jsonb_build_array(
      'Sin producto: V2. Del de 4g (Ane Prueba)', 'Sin producto: BZ1 (Ane Prueba)',
      'Descuadre de stock o de caja: Faltan 5 € en la caja (Ane Prueba)',
      'Comentario de cliente: Un cliente pide el V2 en 10g (Ane Prueba)', 'La puerta no cierra bien (Ane Prueba)')
    and not exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'estado' <> 'abierta'), r::text);
  perform pg_temp.comprobar('Sin foto ni urgencia: para Administración, abiertas, sin importancia',
    not exists (select 1 from public.incidencias where persona_id = basauri
                 and (quien <> 'administracion' or estado <> 'abierta' or importancia is not null or tarea_id is not null))
    and (select count(*) from public.incidencias where persona_id = basauri) = 5);

  -- 5. La franquicia: solo texto libre (por configuración).
  perform pg_temp.comprobar('Donosti: descuadre y sin producto, NO_AUTORIZADO',
    pg_temp.err(pg_temp.crear(donosti, 'descuadre', 'Faltan 5 €', null, '11:40')) = 'NO_AUTORIZADO'
    and pg_temp.err(pg_temp.crear(donosti, 'sin_producto', null, 'V2', '11:40')) = 'NO_AUTORIZADO');
  r := pg_temp.crear(donosti, 'otros', 'El expositor ha llegado roto', null, '11:45');
  perform pg_temp.comprobar('Donosti: el texto libre llega como incidencia abierta',
    r -> 'incidencias' -> 0 ->> 'texto' = 'El expositor ha llegado roto (Nora Prueba)' and r -> 'incidencias' -> 0 ->> 'opcion' = 'otros', r::text);
  update public.configuracion set valor = '["otros", "descuadre"]' where clave = 'incidencias_tienda' and centro_id = pg_temp.d('DONOSTI');
  perform pg_temp.comprobar('Activar una opción a una franquicia es configuración, no código',
    jsonb_array_length(motor.tienda_hoy_de(donosti, pg_temp.a('11:50')) -> 'opciones_incidencia') = 2
    and pg_temp.crear(donosti, 'descuadre', 'Faltan 5 €', null, '11:50') ? 'incidencias');
  update public.configuracion set valor = '["otros"]' where clave = 'incidencias_tienda' and centro_id = pg_temp.d('DONOSTI');

  -- 6. Administración las ve y las cierra; la tienda ve el estado.
  r := motor.incidencias_tiendas_de(pg_temp.a('12:00'));
  perform pg_temp.comprobar('Administración las ve en incidencias_tiendas(), abiertas, con la tienda y la opción',
    (select count(*) from jsonb_array_elements(r -> 'incidencias') x where x ->> 'tienda' = 'Basauri' and x ->> 'estado' = 'abierta') = 5
    and (select count(*) from jsonb_array_elements(r -> 'incidencias') x where x ->> 'tienda' = 'Donosti') = 2
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
                 where x ->> 'opcion' = 'sin_producto' and x ->> 'texto' = 'Sin producto: V2. Del de 4g (Ane Prueba)'), r::text);
  select id into v_id from public.incidencias where id_cliente = c;
  perform motor.cerrar_incidencia_tienda_de(admin, v_id, 'Va en el reparto de mañana', pg_temp.a('12:30'));
  select id into v_id from public.incidencias where persona_id = basauri and opcion = 'otros';
  perform motor.cerrar_incidencia_tienda_de(admin, v_id, null, pg_temp.a('12:31'));
  r := motor.tienda_hoy_de(basauri, pg_temp.a('12:35'));
  perform pg_temp.comprobar('La tienda ve las cerradas hoy: «Resuelta por Administración: [nota]», después de las abiertas',
    r -> 'incidencias' -> 3 ->> 'estado' = 'cerrada' and r -> 'incidencias' -> 4 ->> 'estado' = 'cerrada'
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
                 where x ->> 'estado_texto' = 'Resuelta por Administración: Va en el reparto de mañana')
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'estado_texto' = 'Resuelta por Administración')
    and r -> 'incidencias' -> 0 ->> 'estado_texto' = 'Abierta', r::text);
  r := motor.tienda_hoy_de(basauri, pg_temp.a2('11:00'));
  perform pg_temp.comprobar('Al día siguiente, solo las que siguen abiertas',
    jsonb_array_length(r -> 'incidencias') = 3
    and not exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'estado' = 'cerrada'), r::text);
  perform pg_temp.comprobar('Los avisos de Administración siguen aparte (no salen en incidencias)',
    not exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'opcion' = 'aviso'));
end;
$$;

-- El almacén igual: a Eder no le sale nada.
select pg_temp.comprobar('El almacén sigue igual: la pantalla de Eder, sus incidencias y el panel',
  motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.a('11:30')) = (select v from _v where k = 'tarea_activa')
  and motor.incidencias_abiertas_de('00000000-0000-4000-a000-000000000001', pg_temp.a('11:30')) = (select v from _v where k = 'incidencias_operario')
  and motor.estado_actual_de(pg_temp.a('11:30')) -> 'incidencias_abiertas' = (select v from _v where k = 'estado_actual'));

-- Permisos
select pg_temp.como('00000000-0000-4000-b000-000000000001');  -- Basauri
select pg_temp.comprobar('La tienda la usa (la opción se comprueba: DATOS_NO_VALIDOS, no NO_AUTORIZADO)',
  public.crear_incidencia_tienda(gen_random_uuid(), 'x') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
  and (select count(*) from public.incidencias where opcion in ('descuadre', 'otros')
         and persona_id <> '00000000-0000-4000-b000-000000000001') = 0);
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario no la usa',
  public.crear_incidencia_tienda(gen_random_uuid(), 'otros', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('Administración no la usa; las ve con incidencias_tiendas()',
  public.crear_incidencia_tienda(gen_random_uuid(), 'otros', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.incidencias_tiendas() ? 'incidencias');
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.crear_incidencia_tienda(uuid, text, text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'motor.api_crear_incidencia_tienda(uuid, text, text, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'motor.crear_incidencia_tienda_de(uuid, uuid, text, text, text, timestamptz)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
