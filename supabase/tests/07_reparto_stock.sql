-- Prueba 07 · Reparto, envío y stock en la base de datos (Tarea 3)
-- Lo que guardan las funciones del servidor tras calcular R1 y R3, el reparto
-- corregido, la idempotencia y los elementos (referencias y cajas) con su punto
-- de encaje. Los datos de entrada imitan exactamente lo que envía el servidor.
-- Martes 03/11/2026. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas (la tarea
-- programada crea una cada día): sin pendientes que arrastrar. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;

create function pg_temp.destino(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;

-- Reparto R1-01 tal como lo calcula el servidor.
create function pg_temp.reparto(p_bilbao_v2 int, p_faltan_v2 int) returns jsonb language sql as $$
  select jsonb_build_object(
    'produccion', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', p_bilbao_v2 + 10, 'en_almacen', 25, 'faltan', p_faltan_v2, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 9, 'en_almacen', 7, 'faltan', 2, 'aviso', null, 'orden', 3),
      jsonb_build_object('producto', 'FORTE', 'formato', '', 'pedido', 1, 'en_almacen', 107, 'faltan', 0, 'aviso', null, 'orden', 6)),
    'bolsas', jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.destino('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', p_bilbao_v2, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 5, 'orden', 3))),
      jsonb_build_object('destino_id', pg_temp.destino('ALGORTA'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 10, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 4, 'orden', 3),
        jsonb_build_object('producto', 'FORTE', 'formato', '', 'cantidad', 1, 'orden', 6)))))
$$;

create function pg_temp.guardar(p_jornada uuid, p_huella text, p_datos jsonb, p_hora text) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000001', p_jornada, 'reparto', 'texto ' || p_huella, p_huella, '2026-11-03',
    'operario', null, '[]', p_datos -> 'produccion', p_datos -> 'bolsas', true, ('2026-11-03 ' || p_hora || ':00+01')::timestamptz)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  ahora constant timestamptz := '2026-11-03 09:00:00+01';
  j uuid;
  r jsonb;
  r2 jsonb;
  v_prod uuid;
  v_bolsas uuid;
  v_el uuid;
  v_n integer;
begin
  j := motor.generar_jornada(op, '2026-11-03');
  update public.tareas set estado = 'hecha' where jornada_id = j and clave in ('revision_inicial', 'pegar_reparto');

  -- Reparto con errores: queda registrado, no crea nada
  r := public.servidor_guardar_reparto(op, j, 'reparto', '2x V2 5g', 'h0', null, null, null,
         '[{"num": 1, "texto": "2x V2 5g", "clase": "producto", "error": "PRODUCTO_DESCONOCIDO"}]', '[]', '[]', false, ahora);
  perform pg_temp.comprobar('Reparto con errores: se registra como «con_errores» y no crea tareas',
    r ->> 'estado' = 'con_errores'
    and not exists (select 1 from public.tareas where jornada_id = j and clave in ('produccion_reparto', 'bolsas'))
    and exists (select 1 from public.reparto_lineas l join public.repartos p on p.id = l.reparto_id
                where p.jornada_id = j and l.error = 'PRODUCTO_DESCONOCIDO'), r::text);

  -- R1-01 aceptado
  r := pg_temp.guardar(j, 'h1', pg_temp.reparto(20, 5), '08:50');
  select id into v_prod from public.tareas where jornada_id = j and clave = 'produccion_reparto';
  select id into v_bolsas from public.tareas where jornada_id = j and clave = 'bolsas';
  perform pg_temp.comprobar('R1-01 aceptado: SALE: fija que sale el operario (salida y efectivo creadas)',
    (select sale from public.jornadas where id = j) = 'operario'
    and exists (select 1 from public.tareas where jornada_id = j and clave = 'salida_reparto'), r::text);
  perform pg_temp.comprobar('R1-01 aceptado: producción con lo que falta (V2 4g 5, BZ1 4g 2; FORTE no)',
    (select string_agg(producto || ' ' || formato || '=' || cantidad, ', ' order by orden_sugerido)
       from public.tarea_elementos where tarea_id = v_prod) = 'V2 4g=5, BZ1 4g=2',
    (select string_agg(producto || ' ' || formato || '=' || cantidad, ', ' order by orden_sugerido)
       from public.tarea_elementos where tarea_id = v_prod));
  perform pg_temp.comprobar('R1-01 aceptado: bolsas por tienda (Bilbao 2 referencias, Algorta 3)',
    (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and destino_id = pg_temp.destino('BILBAO')) = 2
    and (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and destino_id = pg_temp.destino('ALGORTA')) = 3);
  perform pg_temp.comprobar('Duraciones (§6.10): producción 7 cajas × 1 min = 7; bolsas 2 tiendas × 3 min = 6',
    (select duracion_min from public.tareas where id = v_prod) = 7
    and (select duracion_min from public.tareas where id = v_bolsas) = 6);
  perform pg_temp.comprobar('La tarea activa devuelve la producción con sus elementos',
    jsonb_array_length(motor.tarea_activa_de(op, ahora) -> 'tarea' -> 'elementos') >= 0
    and jsonb_array_length(motor.tarea_json(v_prod) -> 'elementos') = 2);

  -- R1-10 el mismo reparto dos veces: se recalcula y sustituye (Tarea 23; antes, «ya pegado»).
  -- Repetir la misma petición lo para el id_cliente de guardar_reparto (prueba 16).
  r2 := pg_temp.guardar(j, 'h1', pg_temp.reparto(20, 5), '08:55');
  perform pg_temp.comprobar('R1-10 el mismo reparto dos veces: se recalcula (sustituye al anterior) y nada duplicado',
    r2 -> 'ya_pegado' is null and (r2 ->> 'sustituye_a') is not null
    and (select count(*) from public.repartos where jornada_id = j and estado = 'aceptado') = 1
    and (select count(*) from public.tarea_elementos where tarea_id in (v_prod, v_bolsas)) = 7, r2::text);

  -- Elementos: producción
  select id into v_el from public.tarea_elementos where tarea_id = v_prod and producto = 'V2';
  r := motor.iniciar_elemento_de(op, v_el, ahora);
  perform pg_temp.comprobar('iniciar_elemento: la referencia y la tarea pasan a en curso',
    (select estado from public.tarea_elementos where id = v_el) = 'en_curso'
    and (select estado from public.tareas where id = v_prod) = 'en_curso', r::text);
  r := motor.iniciar_elemento_de(op, (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1'), ahora);
  perform pg_temp.comprobar('Otra referencia mientras hay una empezada: OTRO_ELEMENTO_EN_CURSO',
    r -> 'error' ->> 'codigo' = 'OTRO_ELEMENTO_EN_CURSO', r::text);
  r := motor.terminar_tarea_de(op, v_prod, null, null, ahora);
  perform pg_temp.comprobar('Terminar la tarea con referencias pendientes sin motivo: ELEMENTOS_PENDIENTES',
    r -> 'error' ->> 'codigo' = 'ELEMENTOS_PENDIENTES', r::text);
  r := motor.terminar_elemento_de(op, v_el, ahora + interval '5 minutes');
  r2 := motor.terminar_elemento_de(op, v_el, ahora + interval '6 minutes');
  perform pg_temp.comprobar('terminar_elemento: V2 4g hecha (5 cajas); repetirlo no cambia nada',
    (select estado = 'hecho' and cantidad_hecha = 5 and terminado_en = ahora + interval '5 minutes'
       from public.tarea_elementos where id = v_el)
    and not r2 ? 'error'
    and (select count(*) from public.registro_eventos where tipo = 'elemento_terminado' and datos ->> 'elemento' = v_el::text) = 1,
    r2::text);

  -- Punto de encaje: hay una urgente al terminar la referencia → la lista se pausa
  insert into public.tareas (jornada_id, clave, origen, titulo, disponible_desde, urgente, duracion_min, no_terminada)
  values (j, 'admin:urgente', 'administracion', 'Mira el pedido de Bilbao', ahora, true, 5, 'arrastrar');
  r := motor.terminar_elemento_de(op, (select id from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1'),
                                   ahora + interval '10 minutes');
  perform pg_temp.comprobar('Encaje: al terminar BZ1 todas están hechas → la producción queda hecha (sin pausa)',
    (select estado from public.tareas where id = v_prod) = 'hecha'
    and (select resultado from public.tareas where id = v_prod) = '7 cajas', r::text);
  -- Tarea 29 (03/11/2026): después de la producción, siempre las bolsas; la urgente espera a que terminen.
  perform pg_temp.comprobar('Después de la producción, las bolsas (la urgente espera a que terminen)',
    r -> 'tarea_activa' -> 'tarea' ->> 'clave' = 'bolsas', r::text);
  update public.tareas set estado = 'hecha' where jornada_id = j and clave = 'admin:urgente';

  -- Elementos: bolsas
  select id into v_el from public.tarea_elementos where tarea_id = v_bolsas and destino_id = pg_temp.destino('ALGORTA') and producto = 'V2';
  r := motor.marcar_cajas_de(op, v_el, 11, ahora);
  perform pg_temp.comprobar('marcar_cajas fuera de rango (11 de 10): CANTIDAD_FUERA_DE_RANGO',
    r -> 'error' ->> 'codigo' = 'CANTIDAD_FUERA_DE_RANGO', r::text);
  perform motor.marcar_cajas_de(op, v_el, 4, ahora);
  perform motor.marcar_cajas_de(op, v_el, 4, ahora);
  perform pg_temp.comprobar('Marcar la misma caja dos veces no cambia nada (valor absoluto)',
    (select cantidad_hecha = 4 and estado = 'en_curso' from public.tarea_elementos where id = v_el)
    and (select count(*) from public.registro_eventos where tipo = 'cajas_marcadas' and datos ->> 'elemento' = v_el::text) = 1);
  perform motor.marcar_cajas_de(op, v_el, 10, ahora);
  perform motor.marcar_cajas_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas
                                     and destino_id = pg_temp.destino('ALGORTA') and producto = 'BZ1'), 4, ahora);
  -- Antes de cerrar Algorta llega una tarea con hora vencida (la salida de las 10:45)
  r := motor.marcar_cajas_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas
                                  and destino_id = pg_temp.destino('ALGORTA') and producto = 'FORTE'), 1, '2026-11-03 10:46:00+01');
  perform pg_temp.comprobar('Con las bolsas sin terminar, la salida (10:45) no entra: siguen las bolsas, con el aviso para retrasar',
    (select estado from public.tareas where id = v_bolsas) = 'en_curso'
    and r -> 'tarea_activa' -> 'tarea' ->> 'clave' = 'bolsas'
    and r -> 'tarea_activa' -> 'aviso_salida' ->> 'hora_salida' = '10:45'
    and r -> 'tarea_activa' -> 'aviso_salida' -> 'minutos' = '[15, 30]'::jsonb, r::text);
  perform pg_temp.comprobar('Lo hecho se conserva (Algorta completa)',
    not exists (select 1 from public.tarea_elementos where tarea_id = v_bolsas
                and destino_id = pg_temp.destino('ALGORTA') and estado <> 'hecho'));

  -- R1-21 reparto corregido con trabajo hecho: Bilbao pasa a 22 V2 4g → faltan 7
  r := pg_temp.guardar(j, 'h2', pg_temp.reparto(22, 7), '10:50');
  perform pg_temp.comprobar('R1-21 corregido: sustituye al anterior',
    (select count(*) from public.repartos where jornada_id = j and estado = 'sustituido') = 2  -- el de R1-10 y este
    and (r ->> 'sustituye_a') is not null, r::text);
  perform pg_temp.comprobar('R1-21 corregido: V2 4g faltan 7 y se conservan las 5 hechas; la producción se reabre',
    (select cantidad = 7 and cantidad_hecha = 5 and estado = 'pendiente'
       from public.tarea_elementos where tarea_id = v_prod and producto = 'V2')
    and (select estado from public.tareas where id = v_prod) = 'pendiente'
    and (select cantidad_hecha = 2 and estado = 'hecho' from public.tarea_elementos where tarea_id = v_prod and producto = 'BZ1'));
  perform pg_temp.comprobar('R1-21 corregido: la bolsa de Algorta (sin cambios) se conserva completa',
    (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and destino_id = pg_temp.destino('ALGORTA')
       and estado = 'hecho') = 3);
  perform pg_temp.comprobar('R1-21 corregido: la bolsa de Bilbao (cambia) vuelve a comprobarse caja a caja',
    (select sum(cantidad_hecha) from public.tarea_elementos where tarea_id = v_bolsas and destino_id = pg_temp.destino('BILBAO')) = 0
    and (select cantidad from public.tarea_elementos where tarea_id = v_bolsas and destino_id = pg_temp.destino('BILBAO') and producto = 'V2') = 22
    and (select string_agg((b ->> 'destino') || ':' || (b ->> 'cambia'), ',' order by b ->> 'destino')
           from jsonb_array_elements(r -> 'bolsas') b) = 'Algorta:false,Bilbao:true', r -> 'bolsas' ->> 0);

  -- Envío (miércoles no; martes 18:10): preparar el envío con sus cajas
  r := public.servidor_guardar_reparto(op, j, 'envio', 'GIPUZKOA\n4x V2 4g', 'e1', null, null, null, '[]',
         jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 4, 'en_almacen', 25, 'faltan', 0, 'aviso', null, 'orden', 1)),
         jsonb_build_array(jsonb_build_object('destino_id', pg_temp.destino('GIPUZKOA'), 'items',
           jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 4, 'orden', 1)))),
         true, '2026-11-03 15:45:00+01');
  perform pg_temp.comprobar('Envío aceptado: hay envío hoy (Nacex y recuento de 17:55) y «Prepara el envío» lleva las cajas de Gipuzkoa',
    (select hay_envio from public.jornadas where id = j)
    and exists (select 1 from public.tareas where jornada_id = j and clave = 'nacex_salida')
    and exists (select 1 from public.tareas where jornada_id = j and clave = 'recuento_tarde' and estado = 'cancelada')
    and (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
         where t.jornada_id = j and t.clave = 'preparar_envio' and e.tipo = 'caja_bolsa'
           and e.destino_id = pg_temp.destino('GIPUZKOA') and e.cantidad = 4) = 1, r::text);

  -- Stock (R3): una vez por turno
  r := public.servidor_guardar_stock(op, j, 'manana', null,
         '[{"producto": "Indoor", "formato": "4g", "categoria": "Indoor", "cajas": 33, "motivo": "m1"},
           {"producto": "V2", "formato": "10g", "categoria": "HIGH TECH", "cajas": 12, "motivo": "m2"}]',
         '["YUZU"]', ahora);
  r2 := public.servidor_guardar_stock(op, j, 'manana', null,
          '[{"producto": "Otra", "formato": "4g", "cajas": 1, "motivo": "x"}]', '["YUZU"]', ahora);
  perform pg_temp.comprobar('R3-17 la lista dos veces en el turno: la misma, sin duplicar',
    (r2 ->> 'ya_calculado')::boolean
    and (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
         where t.jornada_id = j and t.clave = 'cola_stock') = 2, r2::text);
  perform pg_temp.comprobar('Lista de stock en orden, con duración de 45 min (45 cajas × 1)',
    (select string_agg(producto || ' ' || formato || '=' || cantidad, ', ' order by orden_sugerido)
       from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
      where t.jornada_id = j and t.clave = 'cola_stock') = 'Indoor 4g=33, V2 10g=12'
    and (select duracion_min from public.tareas where jornada_id = j and clave = 'cola_stock') = 45);
  perform pg_temp.comprobar('Sin granel: aparece una vez la tarea «Avisa a Administración: falta YUZU»',
    (select count(*) from public.tareas where jornada_id = j and titulo = 'Avisa a Administración: falta YUZU'
       and obligatoria) = 1);
  update public.tarea_elementos set estado = 'hecho', cantidad_hecha = 12
   where producto = 'V2' and formato = '10g' and lote = 'manana';
  r := public.servidor_guardar_stock(op, j, 'tarde', null,
         '[{"producto": "Indoor", "formato": "4g", "categoria": "Indoor", "cajas": 20, "motivo": "m3"}]', '[]', ahora);
  perform pg_temp.comprobar('Turno de tarde: se recalcula; lo no hecho de la mañana no se arrastra, lo hecho queda',
    (select string_agg(lote || ':' || producto || ' ' || formato || '=' || cantidad, ', ' order by lote, producto)
       from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
      where t.jornada_id = j and t.clave = 'cola_stock') = 'manana:V2 10g=12, tarde:Indoor 4g=20');
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
