-- Prueba 18 · Peticiones especiales e histórico (Tarea 13, ESTADO v1.26 §5 R1d y §8).
-- Lo que la base de datos hace para `guardar_reparto` con peticiones: se guardan
-- con el reparto, van a la bolsa de su tienda («Además, mete:») sin tocar la
-- producción, se marcan con marcar_cajas y la bolsa no termina sin ellas; se
-- conservan al modificar; también en el envío; reparto_de_hoy_detalle las
-- devuelve. Histórico: historico_dia (reparto, envío, pedidos, cierres y
-- tareas), un día sin jornada, historico_dias y permisos. El texto «Además: …»
-- y la validación están en _compartido/lista_test.ts, r1_test.ts y
-- reparto_lista_test.ts. Miércoles 02/12/2026. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.rechazada(p_sql text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
end;
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
create function pg_temp.p(p_codigo text, p_texto text) returns jsonb language sql as $$
  select jsonb_build_object('destino_id', pg_temp.d(p_codigo), 'texto', p_texto) $$;
-- Lo que guarda la función del servidor guardar_reparto: Bilbao (V2 y BZ1) y
-- Portu (V2), con la línea «Además: …» de Bilbao (clase `peticion`).
create function pg_temp.guardar(p_jornada uuid, p_huella text, p_ademas text, p_ahora timestamptz)
returns jsonb language sql as $$
  select public.servidor_guardar_reparto(
    '00000000-0000-4000-a000-000000000002', p_jornada, 'reparto',
    E'REPARTO 02/12\nSALE: ALMACÉN\n\nBILBAO\n3x V2 4g\n1x BZ1 4g\nAdemás: ' || p_ademas || E'\n\nPORTU\n2x V2 4g',
    p_huella, '2026-12-02', 'operario', null,
    jsonb_build_array(
      jsonb_build_object('num', 1, 'texto', 'REPARTO 02/12', 'clase', 'cabecera'),
      jsonb_build_object('num', 2, 'texto', 'SALE: ALMACÉN', 'clase', 'sale', 'sale', 'operario'),
      jsonb_build_object('num', 4, 'texto', 'BILBAO', 'clase', 'tienda', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 5, 'texto', '3x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 3, 'producto', 'V2', 'formato', '4g'),
      jsonb_build_object('num', 6, 'texto', '1x BZ1 4g', 'clase', 'producto', 'destino_id', pg_temp.d('BILBAO'),
                         'cantidad', 1, 'producto', 'BZ1', 'formato', '4g'),
      jsonb_build_object('num', 7, 'texto', 'Además: ' || p_ademas, 'clase', 'peticion', 'destino_id', pg_temp.d('BILBAO')),
      jsonb_build_object('num', 9, 'texto', 'PORTU', 'clase', 'tienda', 'destino_id', pg_temp.d('PORTU')),
      jsonb_build_object('num', 10, 'texto', '2x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('PORTU'),
                         'cantidad', 2, 'producto', 'V2', 'formato', '4g')),
    jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 5, 'en_almacen', 3, 'faltan', 2, 'aviso', null, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 1, 'en_almacen', 5, 'faltan', 0, 'aviso', null, 'orden', 3)),
    jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 3, 'orden', 1),
        jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 1, 'orden', 3))),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'items', jsonb_build_array(
        jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 2, 'orden', 1)))),
    true, p_ahora) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  ahora constant timestamptz := '2026-12-02 09:30+01';
  j uuid;
  r jsonb;
  v_rep uuid;
  v_rep2 uuid;
  v_prod uuid;
  v_bolsas uuid;
  v_env uuid;
  v_el uuid;
  e public.tarea_elementos;
begin
  j := motor.generar_jornada(op, '2026-12-02');
  r := pg_temp.guardar(j, 'h18-a', 'Rollos de TPV; muestras de V2', '2026-12-02 08:40+01');
  v_rep := (r ->> 'reparto_id')::uuid;
  v_prod := (r -> 'tareas' ->> 'produccion')::uuid;
  v_bolsas := (r -> 'tareas' ->> 'bolsas')::uuid;
  perform pg_temp.comprobar('La línea «Además: …» se guarda con el reparto como petición de su tienda',
    exists (select 1 from public.reparto_lineas where reparto_id = v_rep and clase = 'peticion'
             and destino_id = pg_temp.d('BILBAO') and texto = 'Además: Rollos de TPV; muestras de V2'), r::text);

  r := public.servidor_guardar_peticiones(adm, v_rep, jsonb_build_array(
         pg_temp.p('BILBAO', 'Rollos de TPV'), pg_temp.p('BILBAO', '  muestras   de V2 '), pg_temp.p('BILBAO', ''),
         pg_temp.p('PORTU', 'Cajas vacías'), pg_temp.p('BILBAO', 'ROLLOS DE TPV')), '2026-12-02 08:40+01');
  perform pg_temp.comprobar('Peticiones guardadas con el reparto, sin vacías ni repetidas, con el nombre de la tienda',
    r -> 'peticiones' = jsonb_build_array(
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'destino', 'Bilbao', 'texto', 'Rollos de TPV'),
      jsonb_build_object('destino_id', pg_temp.d('BILBAO'), 'destino', 'Bilbao', 'texto', 'muestras de V2'),
      jsonb_build_object('destino_id', pg_temp.d('PORTU'), 'destino', 'Portugalete', 'texto', 'Cajas vacías'))
    and (select jsonb_array_length(peticiones) = 3 and resultado -> 'peticiones' = r -> 'peticiones'
           from public.repartos where id = v_rep), r::text);
  perform pg_temp.comprobar('Van a la bolsa de su tienda (una cada una, cantidad 1); la producción no cambia',
    (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'peticion' and cantidad = 1
        and lote = 'reparto' and estado = 'pendiente') = 3
    and not exists (select 1 from public.tarea_elementos where tarea_id = v_prod and tipo <> 'referencia_produccion')
    and (select sum(cantidad) from public.tarea_elementos where tarea_id = v_prod) = 2);
  r := motor.tarea_json(v_bolsas) -> 'elementos';
  perform pg_temp.comprobar('En las bolsas, después de las cajas de su tienda, con su texto («Además, mete:»)',
    (select jsonb_agg(jsonb_build_array(x ->> 'destino', x ->> 'tipo', coalesce(x ->> 'texto', x ->> 'producto'), x ->> 'bolsa') order by n)
       from jsonb_array_elements(r) with ordinality a(x, n))
    = '[["Bilbao", "caja_bolsa", "V2", "Bolsa de reposición"], ["Bilbao", "caja_bolsa", "BZ1", "Bolsa de reposición"],
        ["Bilbao", "peticion", "Rollos de TPV", "Bolsa de reposición"], ["Bilbao", "peticion", "muestras de V2", "Bolsa de reposición"],
        ["Portugalete", "caja_bolsa", "V2", "Bolsa de reposición"], ["Portugalete", "peticion", "Cajas vacías", "Bolsa de reposición"]]'::jsonb,
    r::text);

  perform public.servidor_guardar_peticiones(adm, v_rep, jsonb_build_array(
         pg_temp.p('BILBAO', 'Rollos de TPV'), pg_temp.p('BILBAO', 'muestras de V2'), pg_temp.p('PORTU', 'Cajas vacías')),
         '2026-12-02 08:41+01');
  perform pg_temp.comprobar('Repetirlo no cambia nada',
    (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'peticion') = 3
    and (select count(*) from public.registro_eventos where tipo = 'peticiones_guardadas' and tarea_id = v_bolsas) = 1);

  r := motor.reparto_de_hoy_detalle_de(op, 'reparto', '2026-12-02 08:45+01') -> 'reparto';
  perform pg_temp.comprobar('reparto_de_hoy_detalle devuelve las peticiones y el texto con «Además: …»',
    jsonb_array_length(r -> 'peticiones') = 3 and r -> 'peticiones' -> 2 ->> 'texto' = 'Cajas vacías'
    and r ->> 'texto_whatsapp' like '%1x BZ1 4g' || E'\n' || 'Además: Rollos de TPV; muestras de V2%'
    and jsonb_array_length(r -> 'lineas') = 3, r::text);

  -- Marcar en las bolsas
  update public.tareas set estado = 'hecha' where jornada_id = j and id <> v_bolsas and estado in ('pendiente', 'en_curso');
  for e in select * from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'caja_bolsa' loop
    perform motor.marcar_cajas_de(op, e.id, e.cantidad, ahora);
  end loop;
  perform pg_temp.comprobar('Con todas las cajas pero sin las peticiones, la bolsa no está terminada',
    (select estado from public.tareas where id = v_bolsas) = 'en_curso'
    and motor.terminar_tarea_de(op, v_bolsas, null, null, ahora) -> 'error' ->> 'codigo' = 'ELEMENTOS_PENDIENTES'
    and (motor.terminar_tarea_de(op, v_bolsas, null, null, ahora) -> 'error' ->> 'pendientes')::int = 3);
  v_el := (select id from public.tarea_elementos where tarea_id = v_bolsas and producto = 'Rollos de TPV');
  r := motor.marcar_cajas_de(op, v_el, 2, ahora);
  perform pg_temp.comprobar('Una petición se marca con 0 o 1 (2: CANTIDAD_FUERA_DE_RANGO); no se «termina» como una referencia',
    r -> 'error' ->> 'codigo' = 'CANTIDAD_FUERA_DE_RANGO'
    and motor.terminar_elemento_de(op, v_el, ahora) -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  perform motor.marcar_cajas_de(op, v_el, 1, ahora);
  perform motor.marcar_cajas_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas and producto = 'muestras de V2'), 1, ahora);
  perform pg_temp.comprobar('Petición marcada: hecha; la bolsa sigue abierta mientras quede una (Portu)',
    (select estado = 'hecho' and cantidad_hecha = 1 from public.tarea_elementos where id = v_el)
    and (select estado from public.tareas where id = v_bolsas) = 'en_curso');
  perform motor.marcar_cajas_de(op, (select id from public.tarea_elementos where tarea_id = v_bolsas and producto = 'Cajas vacías'), 1, ahora);
  perform pg_temp.comprobar('Con todo marcado (cajas y peticiones), la bolsa queda hecha',
    (select estado from public.tareas where id = v_bolsas) = 'hecha');

  -- Modificar el reparto: se conservan las marcadas, se quitan las que ya no están y una nueva reabre la bolsa
  r := pg_temp.guardar(j, 'h18-b', 'Rollos de TPV', '2026-12-02 10:00+01');
  v_rep2 := (r ->> 'reparto_id')::uuid;
  r := public.servidor_guardar_peticiones(adm, v_rep2, jsonb_build_array(
         pg_temp.p('BILBAO', 'Rollos de TPV'), pg_temp.p('PORTU', 'Cajas vacías'), pg_temp.p('PORTU', 'Bolsas de papel')),
         '2026-12-02 10:00+01');
  perform pg_temp.comprobar('Al modificar: las marcadas se conservan, la quitada desaparece y la nueva reabre la bolsa',
    (select estado from public.repartos where id = v_rep) = 'sustituido'
    and (select sustituye_a from public.repartos where id = v_rep2) = v_rep
    and (select jsonb_object_agg(producto, estado) from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'peticion')
        = '{"Rollos de TPV": "hecho", "Cajas vacías": "hecho", "Bolsas de papel": "pendiente"}'::jsonb
    and (select estado from public.tareas where id = v_bolsas) = 'pendiente'
    and (select jsonb_array_length(peticiones) from public.repartos where id = v_rep2) = 3, r::text);
  perform public.servidor_guardar_peticiones(adm, v_rep, '[]', '2026-12-02 10:01+01');
  perform pg_temp.comprobar('Las peticiones de un reparto ya sustituido no tocan la bolsa',
    (select count(*) from public.tarea_elementos where tarea_id = v_bolsas and tipo = 'peticion') = 3);
  perform pg_temp.comprobar('Más de 120 letras: DATOS_NO_VALIDOS',
    public.servidor_guardar_peticiones(adm, v_rep2, jsonb_build_array(pg_temp.p('BILBAO', repeat('x', 121))), ahora)
      -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS');

  -- Envío: la petición va en la tarea del envío
  r := public.servidor_guardar_reparto(adm, j, 'envio', E'ENVÍO 02/12\n\nGIPUZKOA\n4x V2 4g\nAdemás: Folletos', 'h18-envio',
         '2026-12-02', null, null,
         jsonb_build_array(jsonb_build_object('num', 3, 'texto', 'GIPUZKOA', 'clase', 'tienda', 'destino_id', pg_temp.d('GIPUZKOA')),
                           jsonb_build_object('num', 4, 'texto', '4x V2 4g', 'clase', 'producto', 'destino_id', pg_temp.d('GIPUZKOA'),
                                              'cantidad', 4, 'producto', 'V2', 'formato', '4g'),
                           jsonb_build_object('num', 5, 'texto', 'Además: Folletos', 'clase', 'peticion', 'destino_id', pg_temp.d('GIPUZKOA'))),
         jsonb_build_array(jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 4, 'en_almacen', 4, 'faltan', 0, 'aviso', null, 'orden', 1)),
         jsonb_build_array(jsonb_build_object('destino_id', pg_temp.d('GIPUZKOA'), 'items', jsonb_build_array(
           jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 4, 'orden', 1)))),
         true, '2026-12-02 15:40+01');
  v_env := (r -> 'tareas' ->> 'bolsas')::uuid;
  perform public.servidor_guardar_peticiones(adm, (r ->> 'reparto_id')::uuid, jsonb_build_array(pg_temp.p('GIPUZKOA', 'Folletos')),
                                             '2026-12-02 15:40+01');
  perform pg_temp.comprobar('Envío: la petición va en la tarea del envío, en la bolsa «Envío»',
    (select x ->> 'bolsa' = 'Envío' and x ->> 'texto' = 'Folletos'
       from jsonb_array_elements(motor.tarea_json(v_env) -> 'elementos') x where x ->> 'tipo' = 'peticion'), r::text);

  -- Histórico
  insert into public.pedidos_cliente (id_cliente, cliente, entrega, destino_id, lineas, fecha_objetivo, jornada_id,
                                      registrado_por, registrado_en)
  values (gen_random_uuid(), 'Ane', 'tienda', pg_temp.d('BILBAO'), '[{"producto": "V2", "formato": "4g", "cantidad": 1}]',
          '2026-12-02', j, adm, '2026-12-02 09:00+01');
  perform motor.generar_cierre(j, 'manana', '2026-12-02 13:00+01');
  r := motor.historico_dia_de('2026-12-02');
  perform pg_temp.comprobar('historico_dia: reparto (quién sale, líneas, peticiones y texto) y envío del día',
    r -> 'jornada' ->> 'sale' = 'operario'
    and r -> 'reparto' ->> 'reparto_id' = v_rep2::text and r -> 'reparto' ->> 'sale' = 'operario'
    and jsonb_array_length(r -> 'reparto' -> 'peticiones') = 3 and jsonb_array_length(r -> 'reparto' -> 'lineas') = 3
    and r -> 'reparto' ->> 'texto_whatsapp' like '%SALE: ALMACÉN%Además: Rollos de TPV%'
    and r -> 'envio' -> 'peticiones' -> 0 ->> 'texto' = 'Folletos' and r -> 'envio' ->> 'sale' is null, r::text);
  perform pg_temp.comprobar('historico_dia: pedidos de cliente, cierres (con su texto) y tareas hechas y no hechas',
    jsonb_array_length(r -> 'pedidos_cliente') = 1 and r -> 'pedidos_cliente' -> 0 ->> 'cliente' = 'Ane'
    and jsonb_array_length(r -> 'cierres') = 1 and r -> 'cierres' -> 0 ->> 'turno' = 'manana'
    and length(r -> 'cierres' -> 0 ->> 'texto') > 0 and r -> 'cierres' -> 0 -> 'contenido' ? 'hecho'
    and exists (select 1 from jsonb_array_elements(r -> 'tareas' -> 'hechas') x where x ->> 'titulo' = 'Prepara el reparto')
    and exists (select 1 from jsonb_array_elements(r -> 'tareas' -> 'no_hechas') x
                 where x ->> 'estado' = 'pendiente' and x ->> 'titulo' like 'Bolsas%'), r::text);
  r := motor.historico_dia_de('2026-12-05');
  perform pg_temp.comprobar('Un día sin jornada (sábado): todo vacío, sin error',
    r = jsonb_build_object('fecha', '2026-12-05', 'jornada', null, 'reparto', null, 'envio', null,
                           'pedidos_cliente', '[]'::jsonb, 'cierres', '[]'::jsonb,
                           'tareas', jsonb_build_object('hechas', '[]'::jsonb, 'no_hechas', '[]'::jsonb)), r::text);
  perform motor.generar_jornada(op, '2026-12-03');
  r := motor.historico_dias_de('2026-11-30', '2026-12-06');
  perform pg_temp.comprobar('historico_dias: solo los días con algo (el jueves aún vacío no sale)',
    r -> 'dias' = jsonb_build_array(jsonb_build_object('fecha', '2026-12-02', 'reparto', true, 'envio', true,
                                                       'pedidos_cliente', 1, 'cierres', 1,
                                                       'tareas_hechas', (r -> 'dias' -> 0 -> 'tareas_hechas')::int))
    and (r -> 'dias' -> 0 ->> 'tareas_hechas')::int > 0, r::text);
  perform pg_temp.comprobar('historico_dias: periodo al revés o de más de un año → DATOS_NO_VALIDOS',
    motor.historico_dias_de('2026-12-06', '2026-12-01') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS'
    and motor.historico_dias_de('2025-01-01', '2026-12-01') -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS');
end;
$$;

-- Permisos ------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
begin
  perform pg_temp.comprobar('Operario: el histórico es solo de Administración; servidor_guardar_peticiones, de nadie',
    public.historico_dia('2026-12-02') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.historico_dias('2026-12-01', '2026-12-06') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and pg_temp.rechazada($q$select public.servidor_guardar_peticiones(gen_random_uuid(), gen_random_uuid(), '[]')$q$));
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.historico_dia('2026-12-02');
begin
  perform pg_temp.comprobar('Administración: historico_dia e historico_dias',
    r -> 'reparto' ->> 'tipo' = 'reparto' and jsonb_array_length(public.historico_dias('2026-12-01', '2026-12-06') -> 'dias') = 1
    and public.historico_dia(null) -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
end;
$$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se usa el histórico',
    pg_temp.rechazada($q$select public.historico_dia('2026-12-02')$q$)
    and pg_temp.rechazada($q$select public.historico_dias('2026-12-01', '2026-12-06')$q$));
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
