-- Prueba 30 · Conflictos al crear una tarea de Administración (Tarea 29; ESTADO_DEL_SISTEMA.md §6.4, v1.46)
-- y avisos del almacén a las tiendas (E2-8, v1.47). El caso del 03/11/2026, rehecho el martes 01/12/2026:
-- a las 10:28, con la producción y las bolsas del reparto pendientes, Administración crea «Hay que recoger
-- las cajas de la imprenta». Cuenta y nombres inventados. Transacción deshecha al final.

begin;
-- Aísla la prueba de los datos reales de pruebas (tiendas y jornadas del operario). Se deshace al final.
update public.personas set activo = false where rol = 'tienda';
update public.personas_tienda set activo = false;
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

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
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.crear(p_id uuid, p_que text, p_urgente boolean, p_ahora timestamptz, p_decision jsonb default null,
                              p_confirmar boolean default true)
returns jsonb language sql as $$
  select motor.crear_tarea_admin_de('00000000-0000-4000-a000-000000000002', p_id, p_que, null, '{"tipo": "hoy"}', 60,
                                    p_urgente, 'Prueba', p_confirmar, p_decision, p_ahora) $$;

-- Una cuenta de tienda (inventada) para los avisos.
insert into public.configuracion (clave, centro_id, valor) values ('cuentas_autorizadas', null, '[
  {"correo": "tienda.basauri@osasun.invalid", "nombre": "Basauri", "rol": "tienda", "centro": "BASAURI"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-b000-000000000001', 'authenticated', 'authenticated',
        'tienda.basauri@osasun.invalid', '{"provider": "google", "providers": ["google"]}', '{}', now(), now());

-- El reparto del martes 01/12, como lo guarda guardar_reparto: Bilbao y Portugalete.
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-01');
do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid := motor.generar_jornada(op, '2026-12-01');
begin
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-01 08:30+01', terminada_en = '2026-12-01 08:45+01'
   where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto');
  perform public.servidor_guardar_reparto(
    adm, j, 'reparto', E'REPARTO 01/12\nSALE: ALMACÉN\n\nBILBAO\n20x V2 4g\n\nPORTU\n20x V2 4g', 'h30', '2026-12-01', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 01/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '20x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 20, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 7, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 8, 'texto', '20x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 20, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 40, 'en_almacen', 0, 'faltan', 40, 'aviso', null, 'orden', 1)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1)))),
    true, '2026-12-01 08:50+01');
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada(op, '2026-12-01');
  v_prod public.tareas;
  v_bolsas public.tareas;
  v_bolsas_antes public.tareas;
  r jsonb;
  c uuid := gen_random_uuid();
  v_t uuid;
  v_riesgo jsonb;
begin
  select * into v_prod from public.tareas where jornada_id = j and clave = 'produccion_reparto';
  select * into v_bolsas_antes from public.tareas where jornada_id = j and clave = 'bolsas';

  -- 1. Sin falsa alarma: no urgente y sin hora límite (el caso del 03/11).
  r := pg_temp.crear(c, 'Hay que recoger las cajas de la imprenta', false, '2026-12-01 10:28+01', null, false);
  perform pg_temp.comprobar('No urgente y sin hora límite, con la producción y las bolsas pendientes: sin conflicto (solo comprobar)',
    (r ->> 'comprobado')::boolean and r -> 'conflicto' = 'null'::jsonb
    and r ->> 'encaje' like 'Cuando termine lo del reparto, las obligatorias y lo que tiene hora.%', r::text);
  r := pg_temp.crear(c, 'Hay que recoger las cajas de la imprenta', false, '2026-12-01 10:28+01');
  select * into v_bolsas from public.tareas where id = v_bolsas_antes.id;
  perform pg_temp.comprobar('Se crea sin preguntar; la producción y las bolsas siguen igual, hoy',
    (r ->> 'tarea_id') is not null and r -> 'conflicto' = 'null'::jsonb
    and v_bolsas.disponible_desde = v_bolsas_antes.disponible_desde and v_bolsas.hora_limite = v_bolsas_antes.hora_limite
    and v_bolsas.estado = 'pendiente', r::text);
  perform pg_temp.comprobar('Y no sale antes que lo del reparto (lo primero de la mañana)',
    motor.tarea_activa_de(op, '2026-12-01 10:30+01') -> 'tarea' ->> 'id' in (v_prod.id::text, v_bolsas.id::text),
    (motor.tarea_activa_de(op, '2026-12-01 10:30+01') -> 'tarea' ->> 'titulo'));

  -- 2. Urgente: conflicto, y las del reparto no se pueden mover.
  c := gen_random_uuid();
  r := pg_temp.crear(c, 'Llevar unas cajas a Bilbao ya', true, '2026-12-01 10:28+01');
  v_riesgo := r -> 'error' -> 'conflicto' -> 'obligatorias_en_riesgo';
  perform pg_temp.comprobar('Urgente: CONFLICTO; las bolsas y la producción, con se_puede_mover: false',
    r -> 'error' ->> 'codigo' = 'CONFLICTO'
    and v_riesgo @> jsonb_build_array(jsonb_build_object('tarea_id', v_bolsas.id, 'se_puede_mover', false))
    and v_riesgo @> jsonb_build_array(jsonb_build_object('tarea_id', v_prod.id, 'se_puede_mover', false)), r::text);
  perform pg_temp.comprobar('Las demás obligatorias en riesgo sí se pueden mover (se_puede_mover: true)',
    not exists (select 1 from jsonb_array_elements(v_riesgo) x
                 where (x ->> 'se_puede_mover')::boolean is distinct from not motor.es_del_reparto(
                         (select clave from public.tareas where id = (x ->> 'tarea_id')::uuid))), v_riesgo::text);
  r := pg_temp.crear(c, 'Llevar unas cajas a Bilbao ya', true, '2026-12-01 10:28+01',
                     jsonb_build_object('cede', v_bolsas.id, 'accion', 'manana'));
  perform pg_temp.comprobar('Pasar las bolsas a mañana: DATOS_NO_VALIDOS con un mensaje claro; no se crea nada',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and r -> 'error' ->> 'mensaje' like '«Bolsas listas en la mesa de salida» es del reparto o del envío de hoy%'
    and not exists (select 1 from public.tareas where id_cliente = c), r::text);
  r := pg_temp.crear(c, 'Llevar unas cajas a Bilbao ya', true, '2026-12-01 10:28+01',
                     jsonb_build_object('cede', v_prod.id, 'accion', 'cancelar'));
  perform pg_temp.comprobar('Cancelar la producción del reparto, tampoco', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := pg_temp.crear(c, 'Llevar unas cajas a Bilbao ya', true, '2026-12-01 10:28+01',
                     jsonb_build_object('cede', v_bolsas.id, 'accion', 'despues'));
  perform pg_temp.comprobar('Ni dejarlas para después (les quitaría la hora límite)', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);

  -- 3. La tarea nueva, para mañana.
  r := pg_temp.crear(c, 'Llevar unas cajas a Bilbao ya', true, '2026-12-01 10:28+01', '{"accion": "nueva_manana"}', false);
  perform pg_temp.comprobar('«Para mañana» (solo comprobar): dice el día',
    (r ->> 'comprobado')::boolean and r ->> 'encaje' like 'Para el 02/12:%', r::text);
  r := pg_temp.crear(c, 'Llevar unas cajas a Bilbao ya', true, '2026-12-01 10:28+01', '{"accion": "nueva_manana"}');
  v_t := (r ->> 'tarea_id')::uuid;
  select * into v_bolsas from public.tareas where id = v_bolsas_antes.id;
  perform pg_temp.comprobar('nueva_manana: se crea el miércoles 02/12 (su siguiente día de trabajo); las bolsas siguen hoy',
    (select j2.fecha from public.tareas t join public.jornadas j2 on j2.id = t.jornada_id where t.id = v_t) = '2026-12-02'
    and r -> 'decision' ->> 'accion' = 'nueva_manana' and r -> 'decision' ->> 'fecha' = '2026-12-02'
    and v_bolsas.disponible_desde = v_bolsas_antes.disponible_desde and v_bolsas.estado = 'pendiente'
    and exists (select 1 from public.registro_eventos where tipo = 'conflicto_decidido' and datos ->> 'id_cliente' = c::text
                and datos ->> 'accion' = 'nueva_manana'), r::text);
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-01 09:00+01', terminada_en = '2026-12-01 10:38+01'
   where id = v_prod.id;
  perform pg_temp.comprobar('Al terminar la producción, a Eder le salen las bolsas de hoy (el 03/11, pasadas a mañana, le salió la salida)',
    motor.tarea_activa_de(op, '2026-12-01 10:40+01') -> 'tarea' ->> 'id' = v_bolsas.id::text,
    (motor.tarea_activa_de(op, '2026-12-01 10:40+01') -> 'tarea' ->> 'titulo'));

  -- 4. Que la haga después: sin hora límite ni urgencia.
  r := pg_temp.crear(gen_random_uuid(), 'Revisar la impresora', true, '2026-12-01 10:50+01', '{"accion": "nueva_despues"}');
  perform pg_temp.comprobar('nueva_despues: se crea hoy, sin urgencia ni hora límite',
    (r ->> 'tarea_id') is not null
    and (select not urgente and hora_limite is null and jornada_id = j from public.tareas where id = (r ->> 'tarea_id')::uuid), r::text);
  r := pg_temp.crear(gen_random_uuid(), 'Otra urgente', true, '2026-12-01 10:50+01', '{"accion": "no_crear"}');
  perform pg_temp.comprobar('no_crear sigue igual', r ->> 'decision' = 'no_crear' and not (r ->> 'creada')::boolean, r::text);

  -- 5. Lo que sale hoy, al reparto o a Nacex, no cede (respuesta del propietario en el PR #28).
  perform pg_temp.comprobar('No ceden: producción, bolsas, salida, pedidos de cliente (tienda y Nacex), envío y Nacex; el recuento sí',
    motor.es_del_reparto('produccion_reparto') and motor.es_del_reparto('bolsas') and motor.es_del_reparto('salida_reparto')
    and motor.es_del_reparto('pedido_tienda:' || gen_random_uuid()) and motor.es_del_reparto('preparar_envio')
    and motor.es_del_reparto('preparar_envio_viernes') and motor.es_del_reparto('pedido_nacex:' || gen_random_uuid())
    and motor.es_del_reparto('pedido_nacex_viernes:' || gen_random_uuid()) and motor.es_del_reparto('nacex_viernes')
    and motor.es_del_reparto('nacex_salida')
    and not motor.es_del_reparto('recuento_manana') and not motor.es_del_reparto('admin:x'));

  -- 6. Las bolsas, siempre después de la producción: nada en medio; la salida, solo con las bolsas.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, urgente, duracion_min, no_terminada)
  values (j, 'admin:urgente_bolsas', 'administracion', 'Mira el pedido de Bilbao', '2026-12-01 10:41+01', true, 5, 'arrastrar');
  perform pg_temp.comprobar('Con la producción hecha, una urgente espera: siguen las bolsas',
    motor.tarea_activa_de(op, '2026-12-01 10:42+01') -> 'tarea' ->> 'id' = v_bolsas.id::text
    and motor.tarea_activa_de(op, '2026-12-01 10:42+01') -> 'aviso_salida' = 'null'::jsonb,
    (motor.tarea_activa_de(op, '2026-12-01 10:42+01'))::text);
  r := motor.tarea_activa_de(op, '2026-12-01 10:46+01');
  perform pg_temp.comprobar('Llega la hora de salida sin las bolsas: no sale la salida; siguen las bolsas, con el aviso para retrasar 15 o 30 min',
    r -> 'tarea' ->> 'id' = v_bolsas.id::text
    and r -> 'aviso_salida' ->> 'texto' = 'Es la hora de salida (10:45) y las bolsas no están listas: retrasa la salida.'
    and r -> 'aviso_salida' -> 'minutos' = '[15, 30]'::jsonb, r::text);
  r := motor.retrasar_salida_de(op, gen_random_uuid(), 15, '2026-12-01 10:47+01');
  perform pg_temp.comprobar('«Retrasar 15 min»: la salida pasa a las 11:00 y el aviso desaparece hasta esa hora',
    r ->> 'nueva_hora_salida' = '11:00' and r -> 'tarea_activa' -> 'aviso_salida' = 'null'::jsonb
    and r -> 'tarea_activa' -> 'tarea' ->> 'id' = v_bolsas.id::text
    and motor.tarea_activa_de(op, '2026-12-01 11:01+01') -> 'aviso_salida' ->> 'hora_salida' = '11:00', r::text);
  update public.tareas set estado = 'hecha', iniciada_en = '2026-12-01 10:40+01', terminada_en = '2026-12-01 10:55+01'
   where id = v_bolsas.id;
  perform pg_temp.comprobar('Con las bolsas hechas, entra lo que esperaba (la urgente)',
    motor.tarea_activa_de(op, '2026-12-01 10:56+01') -> 'tarea' ->> 'clave' = 'admin:urgente_bolsas'
    and motor.tarea_activa_de(op, '2026-12-01 10:56+01') -> 'aviso_salida' = 'null'::jsonb);
  update public.tareas set estado = 'hecha', terminada_en = '2026-12-01 10:58+01' where jornada_id = j and clave = 'admin:urgente_bolsas';
  perform pg_temp.comprobar('Y a la hora retrasada (11:00), la salida del reparto',
    motor.tarea_activa_de(op, '2026-12-01 11:00+01') -> 'tarea' ->> 'clave' = 'salida_reparto',
    motor.tarea_activa_de(op, '2026-12-01 11:00+01') -> 'tarea' ->> 'titulo');
end;
$$;

-- 5. Avisos del almacén a las tiendas
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario ve las tiendas para elegir a cuál mandar el aviso',
  public.tiendas() -> 'tiendas' @> '[{"codigo": "BASAURI", "nombre": "Basauri"}, {"codigo": "DONOSTI"}]'
  and not public.tiendas() -> 'tiendas' @> '[{"codigo": "DURANGO"}]');
select pg_temp.comprobar('El operario manda avisos a una tienda',
  jsonb_array_length(public.crear_aviso_tienda(gen_random_uuid(), current_date,
                       'Meted en la bolsa de mañana las cajas vacías', (select id from public.centros_trabajo where codigo = 'BASAURI')) -> 'avisos') = 1
  and jsonb_array_length(public.crear_aviso_tienda(gen_random_uuid(), current_date,
                       'Preparad los expositores para recogerlos', (select id from public.centros_trabajo where codigo = 'BASAURI')) -> 'avisos') = 1);
select pg_temp.comprobar('No gestiona personas ni días cerrados',
  public.guardar_persona_tienda('X') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.marcar_dia_cerrado(current_date + 30) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
select pg_temp.comprobar('Ve los avisos que ha mandado él (y solo esos)',
  jsonb_array_length(public.avisos_tiendas() -> 'avisos') = 2
  and not exists (select 1 from jsonb_array_elements(public.avisos_tiendas() -> 'avisos') x where x ->> 'de' <> 'Almacén'));
select pg_temp.comprobar('Cancela uno suyo: queda «Cancelado por el almacén»',
  public.cancelar_aviso_almacen((select (x ->> 'id')::uuid from jsonb_array_elements(public.avisos_tiendas() -> 'avisos') x
                                  where x ->> 'texto' = 'Meted en la bolsa de mañana las cajas vacías')) -> 'aviso' ->> 'nota' = 'Cancelado por el almacén'
  and public.cancelar_aviso_almacen(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');  -- Administración
select pg_temp.comprobar('Administración también manda (a todas)',
  public.crear_aviso_tienda(gen_random_uuid(), current_date, 'Mañana llega la cartelería nueva') -> 'avisos' @> '[{"tienda": "Basauri"}]');
select pg_temp.comprobar('Administración los ve con quién lo mandó («Almacén» o «Administración»)',
  public.avisos_tiendas() -> 'avisos' @> '[{"texto": "Preparad los expositores para recogerlos", "de": "Almacén", "creado_por": "Operario de pruebas"}]'
  and public.avisos_tiendas() -> 'avisos' @> '[{"texto": "Mañana llega la cartelería nueva", "de": "Administración"}]');
select pg_temp.comprobar('Y los puede cancelar (también los del almacén)',
  public.cancelar_aviso_almacen((select (x ->> 'id')::uuid from jsonb_array_elements(public.avisos_tiendas() -> 'avisos') x
                                  where x ->> 'texto' = 'Preparad los expositores para recogerlos')) ? 'aviso');
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000001');  -- operario
select pg_temp.comprobar('El operario no cancela los de Administración',
  public.cancelar_aviso_almacen((select i.id from public.incidencias i where i.descripcion = 'Mañana llega la cartelería nueva'
                                  and i.persona_id = '00000000-0000-4000-b000-000000000001')) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.como('00000000-0000-4000-b000-000000000001');  -- la tienda
select pg_temp.comprobar('En la tienda, cada aviso dice de quién viene',
  public.tienda_hoy() -> 'avisos' @> '[{"texto": "Mañana llega la cartelería nueva", "de": "Administración"}]'
  and not public.tienda_hoy() -> 'avisos' @> '[{"de": "Almacén"}]');  -- el del almacén se canceló
select pg_temp.comprobar('La tienda no manda avisos ni ve la lista de tiendas',
  public.crear_aviso_tienda(gen_random_uuid(), current_date, 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
  and public.tiendas() -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
reset role;
select pg_temp.comprobar('Sin sesión, nada',
  not has_function_privilege('anon', 'public.tiendas()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.crear_aviso_tienda(uuid, date, text, uuid)', 'EXECUTE'));

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
