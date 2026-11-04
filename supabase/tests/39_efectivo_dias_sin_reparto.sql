-- Prueba 39 · El efectivo de los días sin reparto (Tarea 34; ESTADO_DEL_SISTEMA.md E2-8 v1.62, «Recibe la bolsa»).
-- Del viernes 11/12 al lunes 21/12/2026, Basauri y Portugalete. La X de «Bolsa de ayer entregada con X € en efectivo»
-- es la suma de los cierres que aún no han ido en ninguna bolsa entregada: un día; el lunes, viernes y sábado (no hay
-- reparto el sábado); dos días sin reparto; una bolsa sin entregar que pasa a la siguiente; otra cantidad; una tienda
-- sin entregas anteriores (solo el último cierre); sin cierres pendientes. Cuentas y nombres inventados
-- (@osasun.invalid). Transacción deshecha al final.

begin;
-- Aísla la prueba de las cuentas y los nombres reales de las tiendas, de sus bolsas y cierres y de las jornadas del
-- operario. Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
delete from public.bolsas_tienda where centro_id in (select id from public.centros_trabajo where codigo in ('BASAURI', 'PORTU'));
delete from public.cierres_caja where centro_id in (select id from public.centros_trabajo where codigo in ('BASAURI', 'PORTU'));
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.a(p_fecha date, p_hora time) returns timestamptz language sql as $$ select motor.en_local(p_fecha, p_hora) $$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.cuenta(p_codigo text) returns uuid language sql as $$
  select case p_codigo when 'BASAURI' then '00000000-0000-4000-b000-000000000001'::uuid
                       when 'PORTU' then '00000000-0000-4000-b000-000000000002'::uuid end $$;
-- El cierre de caja de ese día (lo que guarda cerrar_caja).
create function pg_temp.cierre(p_codigo text, p_fecha date, p_efectivo numeric) returns void language sql as $$
  insert into public.cierres_caja (centro_id, fecha, z, ventas, efectivo, glovo, nombre)
  values (pg_temp.d(p_codigo), p_fecha, 100, 10, p_efectivo, 0, 'Prueba') $$;
-- El reparto de ese día a Basauri y Portugalete, como lo guarda guardar_reparto; bolsas hechas y sale a las 10:50.
create function pg_temp.reparto(p_fecha date) returns void language plpgsql as $$
declare
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', p_fecha);
begin
  perform public.servidor_guardar_reparto('00000000-0000-4000-a000-000000000002', j, 'reparto',
    E'REPARTO\nSALE: ALMACÉN\n\nBASAURI\n1x V2 4g\n\nPORTU\n1x V2 4g', 'h39-' || p_fecha, p_fecha, 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BASAURI', 'clase', 'tienda', 'destino_id', pg_temp.d('BASAURI')),
      jsonb_build_object('num', 5, 'texto', '1x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BASAURI'),
                         'cantidad', 1, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 7, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 8, 'texto', '1x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 1, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 2, 'en_almacen', 10, 'faltan', 0, 'aviso', null, 'orden', 1)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BASAURI'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 1, 'orden', 1))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 1, 'orden', 1)))),
    true, motor.en_local(p_fecha, '08:40'));
  update public.tareas set estado = 'hecha', iniciada_en = motor.en_local(p_fecha, '09:00'), terminada_en = motor.en_local(p_fecha, '10:40')
   where jornada_id = j and clave in ('produccion_reparto', 'bolsas');
  update public.tareas set estado = 'en_curso', iniciada_en = motor.en_local(p_fecha, '10:50')
   where jornada_id = j and clave = 'salida_reparto';
end; $$;
-- El punto del efectivo de «Recibe la bolsa» de la tienda ese día (la tienda entra en la app a las 10:55).
create function pg_temp.punto(p_codigo text, p_fecha date) returns jsonb language plpgsql as $$
begin
  perform motor.tienda_hoy_de(pg_temp.cuenta(p_codigo), motor.en_local(p_fecha, '10:55'));
  return (select x from jsonb_array_elements(motor.tienda_hoy_de(pg_temp.cuenta(p_codigo), motor.en_local(p_fecha, '10:56')) -> 'tareas') t,
                       jsonb_array_elements(t -> 'puntos') x
           where t ->> 'clave' = 'recibe_bolsa' and x ->> 'pide' = 'efectivo');
end; $$;
-- La tienda entrega el efectivo (sin cantidad: lo esperado).
create function pg_temp.entregar(p_codigo text, p_fecha date, p_cantidad numeric default null, p_motivo text default null)
returns jsonb language sql as $$
  select motor.entregar_efectivo_de(pg_temp.cuenta(p_codigo), (pg_temp.punto(p_codigo, p_fecha) ->> 'id')::uuid, p_cantidad, p_motivo,
                                    motor.en_local(p_fecha, '11:00')) $$;
create function pg_temp.dias(p_codigo text, p_fecha date) returns date[] language sql as $$
  select efectivo_dias from public.bolsas_tienda where centro_id = pg_temp.d(p_codigo) and fecha = p_fecha $$;

-- Cuentas de tienda (inventadas) y sus personas.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"},
  {"correo": "tienda.portu@osasun.invalid", "nombre": "Portugalete", "rol": "tienda", "centro": "PORTU"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select '00000000-0000-0000-0000-000000000000', x.id::uuid, 'authenticated', 'authenticated', x.correo,
       '{"provider": "google", "providers": ["google"]}', '{}', now(), now()
  from (values ('00000000-0000-4000-b000-000000000001', 'tienda.basauri@osasun.invalid'),
               ('00000000-0000-4000-b000-000000000002', 'tienda.portu@osasun.invalid')) x(id, correo);
insert into public.personas_tienda (id, centro_id, nombre, cuando, turno) values
  ('00000000-0000-4000-c000-000000000001', pg_temp.d('BASAURI'), 'Ane Prueba', 'siempre', null),
  ('00000000-0000-4000-c000-000000000002', pg_temp.d('PORTU'), 'Leire Prueba', 'siempre', null);
-- Las jornadas de las tiendas y del almacén de esos días (aparte, antes de leer sus tareas), y quién está en la tienda.
select motor.generar_jornada(x.p, x.f)
  from (values ('00000000-0000-4000-b000-000000000001'::uuid), ('00000000-0000-4000-b000-000000000002'),
               ('00000000-0000-4000-a000-000000000001')) p(p)
  cross join (values ('2026-12-11'::date), ('2026-12-14'), ('2026-12-15'), ('2026-12-16'), ('2026-12-17'), ('2026-12-18'),
                     ('2026-12-21')) f(f)
  cross join lateral (select p.p, f.f) x;
select motor.empezar_turno_tienda_de(x.cuenta, x.persona, motor.en_local(f.f, '10:50'))
  from (values ('00000000-0000-4000-b000-000000000001'::uuid, '00000000-0000-4000-c000-000000000001'::uuid),
               ('00000000-0000-4000-b000-000000000002', '00000000-0000-4000-c000-000000000002')) x(cuenta, persona)
  cross join (values ('2026-12-11'::date), ('2026-12-14'), ('2026-12-15'), ('2026-12-17'), ('2026-12-18'), ('2026-12-21')) f(f);

-- ---------------------------------------------------------------------------
-- 1. Una tienda sin entregas anteriores: solo el último cierre
-- ---------------------------------------------------------------------------
select pg_temp.cierre('BASAURI', '2026-12-11', 40);
select pg_temp.cierre('BASAURI', '2026-12-12', 50);
select pg_temp.cierre('PORTU', '2026-12-10', 5);
select pg_temp.reparto('2026-12-11');
do $$
declare p jsonb := pg_temp.punto('PORTU', '2026-12-11');
begin
  perform pg_temp.comprobar('Portugalete, sin entregas anteriores: solo el último cierre (como hasta ahora)',
    p ->> 'texto' = 'Bolsa de ayer entregada con 5,00 € en efectivo' and (p ->> 'efectivo_esperado')::numeric = 5
    and pg_temp.dias('PORTU', '2026-12-11') = array['2026-12-10'::date], p::text);
  perform pg_temp.entregar('PORTU', '2026-12-11');
end $$;
select pg_temp.reparto('2026-12-14');
do $$
declare p jsonb := pg_temp.punto('BASAURI', '2026-12-14');
begin
  perform pg_temp.comprobar('Basauri, la primera vez: solo el último cierre (el sábado, 50 €), no lo de antes',
    p ->> 'texto' = 'Bolsa de ayer entregada con 50,00 € en efectivo' and (p ->> 'efectivo_esperado')::numeric = 50
    and pg_temp.dias('BASAURI', '2026-12-14') = array['2026-12-12'::date], p::text);
  perform pg_temp.entregar('BASAURI', '2026-12-14');
  perform pg_temp.comprobar('Entregado: queda en la bolsa con sus días',
    (select efectivo_entregado = 50 and efectivo_en is not null from public.bolsas_tienda
      where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-14'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. El lunes, el viernes y el sábado (Portugalete)
-- ---------------------------------------------------------------------------
select pg_temp.cierre('PORTU', '2026-12-11', 30);
select pg_temp.cierre('PORTU', '2026-12-12', 35);
do $$
declare p jsonb := pg_temp.punto('PORTU', '2026-12-14');
  r jsonb;
begin
  perform pg_temp.comprobar('Lunes: el viernes y el sábado (no hay reparto el sábado), 65 €',
    p ->> 'texto' = 'Bolsa entregada con 65,00 € en efectivo (cierres del 11/12 y 12/12)'
    and (p ->> 'efectivo_esperado')::numeric = 65 and pg_temp.dias('PORTU', '2026-12-14') = array['2026-12-11', '2026-12-12']::date[], p::text);
  r := motor.tienda_hoy_de(pg_temp.cuenta('PORTU'), pg_temp.a('2026-12-14', '10:57'));
  perform pg_temp.comprobar('La bolsa (tableta y panel) trae los días, con esperado = la suma',
    (select t -> 'bolsa' -> 'efectivo' from jsonb_array_elements(r -> 'tareas') t where t ->> 'clave' = 'recibe_bolsa')
      @> '{"esperado": 65, "dias": ["2026-12-11", "2026-12-12"]}'::jsonb
    and motor.resumen_tienda_de(pg_temp.d('PORTU'), '2026-12-14', pg_temp.a('2026-12-14', '11:30')) -> 'bolsa' -> 'efectivo'
      @> '{"esperado": 65, "dias": ["2026-12-11", "2026-12-12"]}'::jsonb, r::text);
  perform pg_temp.entregar('PORTU', '2026-12-14');
end $$;

-- ---------------------------------------------------------------------------
-- 3. Un día y dos días sin reparto (Basauri), con otra cantidad
-- ---------------------------------------------------------------------------
select pg_temp.cierre('BASAURI', '2026-12-14', 60);
select pg_temp.reparto('2026-12-15');
do $$
declare p jsonb := pg_temp.punto('BASAURI', '2026-12-15');
begin
  perform pg_temp.comprobar('Un día: el cierre de ayer (60 €)',
    p ->> 'texto' = 'Bolsa de ayer entregada con 60,00 € en efectivo' and pg_temp.dias('BASAURI', '2026-12-15') = array['2026-12-14'::date], p::text);
  perform pg_temp.entregar('BASAURI', '2026-12-15');
  perform pg_temp.comprobar('Portugalete, sin cierre ayer (todo lo anterior ya entregado): dice cuánto entrega',
    pg_temp.punto('PORTU', '2026-12-15') ->> 'texto' = 'Bolsa de ayer entregada: di cuánto efectivo'
    and pg_temp.punto('PORTU', '2026-12-15') -> 'efectivo_esperado' = 'null'::jsonb
    and pg_temp.dias('PORTU', '2026-12-15') is null);
end $$;
select pg_temp.cierre('BASAURI', '2026-12-15', 70);
select pg_temp.cierre('BASAURI', '2026-12-16', 80);  -- el miércoles no pasa el reparto
select pg_temp.reparto('2026-12-17');
do $$
declare p jsonb := pg_temp.punto('BASAURI', '2026-12-17');
  r jsonb;
begin
  perform pg_temp.comprobar('Dos días sin reparto: los dos cierres (150 €)',
    p ->> 'texto' = 'Bolsa entregada con 150,00 € en efectivo (cierres del 15/12 y 16/12)'
    and (p ->> 'efectivo_esperado')::numeric = 150, p::text);
  r := pg_temp.entregar('BASAURI', '2026-12-17', 145, null);
  perform pg_temp.comprobar('Otra cantidad sin motivo: MOTIVO_OBLIGATORIO («que la de los cierres»)',
    r -> 'error' ->> 'codigo' = 'MOTIVO_OBLIGATORIO' and r -> 'error' ->> 'mensaje' like 'Entregas otra cantidad que la de los cierres (150,00 €)%', r::text);
  r := pg_temp.entregar('BASAURI', '2026-12-17', 145, 'Monedas para cambio');
  perform pg_temp.comprobar('Con el motivo: esos cierres quedan entregados',
    (select efectivo_entregado = 145 and efectivo_motivo = 'Monedas para cambio' from public.bolsas_tienda
      where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-17'), r::text);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Una bolsa sin entregar pasa a la siguiente (y la diferencia de antes, no)
-- ---------------------------------------------------------------------------
select pg_temp.cierre('BASAURI', '2026-12-17', 90);
select pg_temp.reparto('2026-12-18');
do $$
declare p jsonb := pg_temp.punto('BASAURI', '2026-12-18');
begin
  perform pg_temp.comprobar('El viernes: el cierre del jueves (90 €); los 5 € de diferencia del jueves no pasan',
    p ->> 'texto' = 'Bolsa de ayer entregada con 90,00 € en efectivo' and (p ->> 'efectivo_esperado')::numeric = 90, p::text);
  -- Esa bolsa se queda con el efectivo sin entregar (la tarea queda sin hacer).
end $$;
select pg_temp.cierre('BASAURI', '2026-12-18', 100);
select pg_temp.cierre('BASAURI', '2026-12-19', 110);
select pg_temp.reparto('2026-12-21');
do $$
declare p jsonb := pg_temp.punto('BASAURI', '2026-12-21');
begin
  perform pg_temp.comprobar('El lunes: lo del jueves sin entregar, más el viernes y el sábado (300 €)',
    p ->> 'texto' = 'Bolsa entregada con 300,00 € en efectivo (cierres del 17/12, 18/12 y 19/12)'
    and (p ->> 'efectivo_esperado')::numeric = 300
    and pg_temp.dias('BASAURI', '2026-12-21') = array['2026-12-17', '2026-12-18', '2026-12-19']::date[], p::text);
  perform pg_temp.entregar('BASAURI', '2026-12-21');
  perform pg_temp.comprobar('Y queda entregado',
    (select efectivo_entregado = 300 from public.bolsas_tienda where centro_id = pg_temp.d('BASAURI') and fecha = '2026-12-21'));
end $$;

-- ---------------------------------------------------------------------------
-- 5. Lo de siempre sigue igual
-- ---------------------------------------------------------------------------
select pg_temp.comprobar('La función de antes (solo el último cierre) ya no existe: hay una sola regla',
  to_regprocedure('motor.efectivo_anterior(uuid, date)') is null);
select pg_temp.comprobar('El texto con un cierre y con varios',
  motor.texto_efectivo(85.5, array['2026-11-03'::date]) = 'Bolsa de ayer entregada con 85,50 € en efectivo'
  and motor.texto_efectivo(180, array['2026-11-03', '2026-11-04']::date[]) = 'Bolsa entregada con 180,00 € en efectivo (cierres del 03/11 y 04/11)');

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
