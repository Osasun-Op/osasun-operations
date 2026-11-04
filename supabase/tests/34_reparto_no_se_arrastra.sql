-- Prueba 34 · Lo del reparto no se arrastra (Tarea 29c). El caso del 03/11 → 04/11, rehecho el martes 01/12/2026:
-- las bolsas se pasaron a mañana por error (no_terminada = 'arrastrar', disponible desde mañana); al generarse
-- el miércoles 02/12 no aparecen. Lo demás se sigue arrastrando igual: lo de Administración, las fijas
-- obligatorias y los pedidos de cliente (regla R1b). Y una copia ya arrastrada de unas bolsas no pasa otra vez.
-- Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;
-- Ninguna jornada suya después del 01/12 (para que el 02/12 se genere ahora y arrastre del 01/12).
delete from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001' and fecha > '2026-12-01';

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.d(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;

-- El reparto del martes 01/12, como lo guarda guardar_reparto: Bilbao.
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
    adm, j, 'reparto', E'REPARTO 01/12\nSALE: ALMACÉN\n\nBILBAO\n20x V2 4g', 'h34', '2026-12-01', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 01/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '20x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 20, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 20, 'en_almacen', 15, 'faltan', 5, 'aviso', null, 'orden', 1)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 20, 'orden', 1)))),
    true, '2026-12-01 08:50+01');
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-01');
  v_bolsas uuid;
  v_prod uuid;
begin
  select id into v_bolsas from public.tareas where jornada_id = j and clave = 'bolsas';
  select id into v_prod from public.tareas where jornada_id = j and clave = 'produccion_reparto';
  -- Lo que hizo «pasar a mañana» el 03/11 (antes de la Tarea 29): las bolsas, para arrastrar y desde mañana.
  update public.tareas set no_terminada = 'arrastrar', disponible_desde = '2026-12-02 00:00+01', hora_limite = null
   where id = v_bolsas;
  update public.tareas set no_terminada = 'arrastrar' where id = v_prod;
  -- Y lo que sí tiene que pasar: una de Administración, una fija obligatoria y un pedido de cliente para la tienda.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, duracion_min, no_terminada, obligatoria)
  values (j, 'admin:imprenta', 'administracion', 'Hay que recoger las cajas de la imprenta', '2026-12-01 10:28+01', 30, 'arrastrar', false),
         (j, 'minis_prueba', 'plantilla', 'Minis (prueba)', '2026-12-01 15:30+01', 60, 'arrastrar', true),
         (j, 'pedido_tienda:prueba', 'reparto', 'Prepara el pedido de cliente (prueba)', '2026-12-01 09:00+01', 10, 'arrastrar', true);
  -- Una copia ya arrastrada de unas bolsas (como la de hoy en pruebas), pendiente el 01/12.
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, duracion_min, no_terminada, tarea_origen_id)
  values (j, 'arrastre:' || v_bolsas, 'reparto', 'Bolsas listas en la mesa de salida', '2026-12-01 08:30+01', 20, 'arrastrar', v_bolsas);
  perform pg_temp.comprobar('La clave de origen de una copia arrastrada es la de la tarea que arrastró',
    motor.clave_original((select id from public.tareas where jornada_id = j and clave = 'arrastre:' || v_bolsas)) = 'bolsas'
    and motor.clave_original(v_bolsas) = 'bolsas');
end;
$$;

-- El miércoles 02/12 se genera (y arrastra lo del martes): en otra sentencia, antes de leer sus tareas.
select motor.generar_jornada('00000000-0000-4000-a000-000000000001', '2026-12-02');

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j1 uuid := motor.generar_jornada(op, '2026-12-01');
  j2 uuid := motor.generar_jornada(op, '2026-12-02');
  v_bolsas uuid;
  r jsonb;
begin
  select id into v_bolsas from public.tareas where jornada_id = j1 and clave = 'bolsas';
  perform pg_temp.comprobar('El caso del 03/11: las bolsas pasadas a mañana no aparecen al día siguiente',
    not exists (select 1 from public.tareas where jornada_id = j2 and tarea_origen_id = v_bolsas)
    and not exists (select 1 from public.tareas where jornada_id = j2 and motor.clave_original(id) = 'bolsas' and clave <> 'bolsas'),
    (select string_agg(clave, ', ') from public.tareas where jornada_id = j2 and clave like 'arrastre:%'));
  perform pg_temp.comprobar('… ni la producción del reparto; constan como no hechas en su día (pendientes, no arrastradas)',
    (select estado from public.tareas where id = v_bolsas) = 'pendiente'
    and (select estado from public.tareas where jornada_id = j1 and clave = 'produccion_reparto') = 'pendiente'
    and not exists (select 1 from public.tareas t join public.tareas o on o.id = t.tarea_origen_id
                     where t.jornada_id = j2 and o.clave = 'produccion_reparto'));
  perform pg_temp.comprobar('Una copia ya arrastrada de unas bolsas no pasa otra vez',
    (select estado from public.tareas where jornada_id = j1 and clave = 'arrastre:' || v_bolsas) = 'pendiente'
    and not exists (select 1 from public.tareas t join public.tareas o on o.id = t.tarea_origen_id
                     where t.jornada_id = j2 and o.clave = 'arrastre:' || v_bolsas));
  perform pg_temp.comprobar('Lo demás se sigue arrastrando: Administración, la fija obligatoria y el pedido de cliente',
    (select count(*) from public.tareas t join public.tareas o on o.id = t.tarea_origen_id
      where t.jornada_id = j2 and o.jornada_id = j1 and o.clave in ('admin:imprenta', 'minis_prueba', 'pedido_tienda:prueba')) = 3
    and (select count(*) from public.tareas where jornada_id = j1 and clave in ('admin:imprenta', 'minis_prueba', 'pedido_tienda:prueba')
           and estado = 'arrastrada') = 3);
  r := motor.tarea_activa_de(op, '2026-12-02 08:35+01');
  perform pg_temp.comprobar('El 02/12, a Eder no le sale ninguna bolsa de ayer',
    coalesce(r -> 'tarea' ->> 'titulo', '') <> 'Bolsas listas en la mesa de salida', r::text);
end;
$$;

select n, prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
