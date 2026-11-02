-- Prueba 26 · Cuatro arreglos tras la prueba del 02/11 (Tarea 23, ESTADO v1.38):
-- 1. lo primero de la mañana (revisión, preparar el reparto, producción y bolsas) va
--    antes que cualquier otra tarea, salvo lo urgente y lo que va a su hora;
-- 2. «Hoy» en el orden en que se ha hecho; 3. Administración por defecto;
-- 4. «Calcular» con el mismo reparto recalcula con la hoja de ahora.
-- Martes 15/12/2026, sale el operario. Transacción deshecha.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;
delete from public.configuracion where clave = 'administracion_por_defecto';

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.h(p_hora text) returns timestamptz language sql as $$
  select ('2026-12-15 ' || p_hora || '+01')::timestamptz $$;
create function pg_temp.toca(p_hora text) returns text language sql as $$
  select motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', pg_temp.h(p_hora)) -> 'tarea' ->> 'clave' $$;
create function pg_temp.crear(p_id uuid, p_que text, p_cuando jsonb, p_ahora timestamptz, p_urgente boolean default false)
returns jsonb language sql as $$
  select motor.crear_tarea_admin_de('00000000-0000-4000-a000-000000000002', p_id, p_que, null, p_cuando, 10,
                                    p_urgente, 'Prueba', true, null, p_ahora) $$;
-- Una producción con una referencia (como la calcula el servidor) para guardar el reparto.
create function pg_temp.guardar(p_jornada uuid, p_almacen int, p_hora text) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000001', p_jornada, 'reparto', 'REPARTO 15/12', 'h-mismo', '2026-12-15', 'operario', null, '[]',
    jsonb_build_array(jsonb_build_object('producto', 'SLUSH MINTS', 'formato', '10g', 'pedido', 14, 'en_almacen', p_almacen,
                                         'faltan', greatest(14 - p_almacen, 0), 'aviso', null, 'orden', 1),
                      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 5, 'en_almacen', 0,
                                         'faltan', 5, 'aviso', null, 'orden', 2)),
    jsonb_build_array(jsonb_build_object('destino_id', (select id from public.centros_trabajo where codigo = 'BILBAO'),
      'items', jsonb_build_array(jsonb_build_object('producto', 'SLUSH MINTS', 'formato', '10g', 'cantidad', 14, 'orden', 1),
                                 jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 5, 'orden', 2)))),
    true, pg_temp.h(p_hora)) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid;
  r jsonb;
  v_admin uuid;
  v_prod uuid;
  v_hoy text[];
begin
  j := motor.generar_jornada(op, '2026-12-15');
  perform prueba.fijar_condicion(j, 'sale', 'operario');

  -- 1. Lo primero de la mañana --------------------------------------------------------------
  r := pg_temp.crear(gen_random_uuid(), 'Pasar las cajas de Slush Mints 4g a la bolsa de granel', '{"tipo": "hoy"}', pg_temp.h('08:00'));
  v_admin := (r ->> 'tarea_id')::uuid;
  perform pg_temp.comprobar('La de Administración no urgente, sin requisito propio (lo decide la regla de la mañana)',
    (select requiere_clave from public.tareas where id = v_admin) is null
    and r ->> 'encaje' like 'Cuando termine lo del reparto%', r::text);
  -- Una tarea de Administración de ayer que pasa a hoy (arrastrada) y otra creada ayer para hoy.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, duracion_min, no_terminada, orden, creada_por)
  values (j, 'arrastre:prueba', 'administracion', 'Pendiente de ayer', pg_temp.h('08:30'), 10, 'arrastrar', 50,
          '00000000-0000-4000-a000-000000000002');
  perform pg_temp.comprobar('08:29 (lo del 02/11): no sale la de Administración ni la de ayer; tampoco nada antes de las 08:30',
    pg_temp.toca('08:29') is null, pg_temp.toca('08:29'));
  perform pg_temp.comprobar('08:31: la revisión inicial', pg_temp.toca('08:31') = 'revision_inicial');
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.h('08:31'), terminada_en = pg_temp.h('08:40')
   where jornada_id = j and clave = 'revision_inicial';
  perform pg_temp.comprobar('08:41, el hueco hasta «Prepara el reparto»: «Orden y limpieza», no el +35 % ni lo de Administración',
    pg_temp.toca('08:41') = 'cola_orden', pg_temp.toca('08:41'));
  perform prueba.fijar_condicion(j, 'llega_mercancia', 'm1');
  perform pg_temp.comprobar('Lo urgente entra igual (llega mercancía)', pg_temp.toca('08:42') = 'recepcion_mercancia:m1');
  update public.tareas set estado = 'hecha' where jornada_id = j and clave = 'recepcion_mercancia:m1';
  perform pg_temp.comprobar('08:46: «Prepara el reparto», no la de Administración', pg_temp.toca('08:46') = 'pegar_reparto');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.h('08:46'), terminada_en = pg_temp.h('08:50')
   where jornada_id = j and clave = 'pegar_reparto';
  perform pg_temp.comprobar('09:00: la producción, no la de Administración', pg_temp.toca('09:00') = 'produccion_reparto');
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.h('09:00'), terminada_en = pg_temp.h('09:40')
   where jornada_id = j and clave = 'produccion_reparto';
  perform pg_temp.comprobar('09:41: las bolsas, no la de Administración', pg_temp.toca('09:41') = 'bolsas');
  update public.tareas set estado = 'hecha', iniciada_en = pg_temp.h('09:41'), terminada_en = pg_temp.h('10:00')
   where jornada_id = j and clave = 'bolsas';
  perform pg_temp.comprobar('10:01: hecho lo primero, sale lo de Administración (antes que el +35 %)',
    pg_temp.toca('10:01') in ((select clave from public.tareas where id = v_admin), 'arrastre:prueba'), pg_temp.toca('10:01'));
  update public.tareas set estado = 'hecha' where jornada_id = j and clave = 'arrastre:prueba';

  r := pg_temp.crear(gen_random_uuid(), 'Mira el pedido de Bilbao', '{"tipo": "hoy"}', pg_temp.h('08:00'), true);
  perform pg_temp.comprobar('Urgente de Administración: entra aunque falte lo primero',
    motor.va_antes_que_lo_primero((select t from public.tareas t where t.id = (r ->> 'tarea_id')::uuid)), r::text);
  r := pg_temp.crear(gen_random_uuid(), 'Llama a la imprenta', '{"tipo": "antes_de", "fecha": "2026-12-15", "hora": "12:00"}', pg_temp.h('08:00'));
  perform pg_temp.comprobar('De Administración con hora límite: como siempre (no espera)',
    (r ->> 'tarea_id') is not null
    and motor.va_antes_que_lo_primero((select t from public.tareas t where t.id = (r ->> 'tarea_id')::uuid)), r::text);
  update public.tareas set estado = 'pendiente' where jornada_id = j and clave = 'bolsas';
  perform pg_temp.comprobar('La regla solo cuenta en la mañana: con las bolsas sin hacer frena a las 10:05, por la tarde ya no',
    motor.lo_primero_pendiente(j, pg_temp.h('10:05')) and not motor.lo_primero_pendiente(j, pg_temp.h('15:30')));
  update public.tareas set estado = 'hecha' where jornada_id = j and clave = 'bolsas';

  -- 2. «Hoy» en el orden en que se ha hecho -------------------------------------------------
  update public.tareas set estado = 'en_curso', iniciada_en = pg_temp.h('10:01') where id = v_admin;
  r := motor.estado_actual_de(pg_temp.h('10:05')) -> 'hoy';
  v_hoy := array(select x ->> 'titulo' from jsonb_array_elements(r) x);
  perform pg_temp.comprobar('Hoy: primero lo hecho y lo que está en curso, por cuándo empezó; después lo pendiente',
    v_hoy[1:5] = array['Revisión inicial: estado de las tiendas, formulario de incidencias y stock empaquetado',
                       'Prepara el reparto', 'Producción del reparto', 'Bolsas listas en la mesa de salida',
                       'Pasar las cajas de Slush Mints 4g a la bolsa de granel']
    -- nada hecho después de lo pendiente, y lo pendiente en el orden de antes (por hora): primero la salida
    and not exists (select 1 from jsonb_array_elements(r) with ordinality a(x, i), jsonb_array_elements(r) with ordinality b(y, k)
                     where i < k and a.x ->> 'estado' not in ('hecha', 'en_curso') and b.y ->> 'estado' in ('hecha', 'en_curso'))
    and (select x ->> 'titulo' from jsonb_array_elements(r) with ordinality a(x, i)
          where x ->> 'estado' not in ('hecha', 'en_curso') order by i limit 1) = 'Salida del reparto',
    array_to_string(v_hoy, ' | '));

  -- 3. Administración por defecto -----------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000009', 'authenticated',
          'authenticated', 'otra.administracion@osasun.invalid', '{}', '{}', now(), now());
  insert into public.personas (id, nombre, rol, centro_id, telefono)
  values ('00000000-0000-4000-a000-000000000009', 'AAA Administración de pruebas', 'administracion', null, '600000009');
  perform pg_temp.comprobar('Sin la clave, como hasta ahora: la primera ficha de Administración por orden alfabético',
    motor.mi_perfil_de(op) -> 'quien_sale_opciones' -> 0 ->> 'nombre' = 'AAA Administración de pruebas',
    motor.mi_perfil_de(op) ->> 'quien_sale_opciones');
  insert into public.configuracion (clave, centro_id, valor) values ('administracion_por_defecto', null, '"00000000-0000-4000-a000-000000000002"');
  perform pg_temp.comprobar('Con administracion_por_defecto: esa ficha, aunque no sea la primera',
    motor.administracion_por_defecto() = '00000000-0000-4000-a000-000000000002'
    and motor.mi_perfil_de(op) -> 'quien_sale_opciones' -> 0 ->> 'nombre'
        = (select nombre from public.personas where id = '00000000-0000-4000-a000-000000000002'),
    motor.mi_perfil_de(op) ->> 'quien_sale_opciones');
end;
$$;

-- La huella de la carga inicial no cambia por tener o no la clave.
create temp table _h as select huella from motor.huella_estructura() where apartado = 'carga inicial';
delete from public.configuracion where clave = 'administracion_por_defecto';
select pg_temp.comprobar('administracion_por_defecto no entra en la huella (como operario_por_defecto)',
  (select huella from _h) = (select huella from motor.huella_estructura() where apartado = 'carga inicial'));

-- 4. «Calcular» con el mismo reparto recalcula ------------------------------------------------
do $$
declare
  j uuid := (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001' and fecha = '2026-12-15');
  r jsonb;
  v_prod uuid;
begin
  r := pg_temp.guardar(j, 0, '10:31');
  v_prod := (select id from public.tareas where jornada_id = j and clave = 'produccion_reparto');
  update public.tarea_elementos set cantidad_hecha = 5, estado = 'hecho' where tarea_id = v_prod and producto = 'V2';
  perform pg_temp.comprobar('10:31, con la hoja mal (SLUSH MINTS 10g en 0): faltan 14',
    (select cantidad from public.tarea_elementos where tarea_id = v_prod and producto = 'SLUSH MINTS') = 14, r::text);
  r := pg_temp.guardar(j, 19, '10:44');
  perform pg_temp.comprobar('10:44, el mismo reparto con la hoja corregida (19): se recalcula, ya no hay que hacer SLUSH MINTS',
    r -> 'ya_pegado' is null and (r ->> 'sustituye_a') is not null
    and not exists (select 1 from public.tarea_elementos where tarea_id = v_prod and producto = 'SLUSH MINTS'
                     and tipo = 'referencia_produccion' and cantidad > 0 and estado <> 'hecho'), r::text);
  perform pg_temp.comprobar('… conservando lo hecho (V2: 5 de 5) y con un solo reparto aceptado',
    (select cantidad_hecha = 5 and estado = 'hecho' from public.tarea_elementos where tarea_id = v_prod and producto = 'V2')
    and (select count(*) from public.repartos where jornada_id = j and estado = 'aceptado') = 1);
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
