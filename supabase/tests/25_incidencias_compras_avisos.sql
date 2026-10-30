-- Prueba 25 · Incidencias nuevas, lista de compras y avisos de Administración
-- (Tarea 22, ESTADO v1.36 §6.6 y §7; CONTRATOS §3.11, §3.20 y §3.21). Lunes
-- 14/12/2026 (y martes 15/12 para el aviso de otro día). Transacción deshecha.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
update public.incidencias set estado = 'cerrada', terminada_en = coalesce(terminada_en, now())
 where persona_id = '00000000-0000-4000-a000-000000000001' and estado <> 'cerrada';
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
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.h(p_dia text, p_hora text) returns timestamptz language sql as $$
  select ('2026-12-' || p_dia || ' ' || p_hora || '+01')::timestamptz $$;
create function pg_temp.compra(p_nombre text) returns uuid language sql as $$
  select id from public.compras where nombre = p_nombre $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  r jsonb;
  t jsonb;
  v_inc uuid;
  v_aviso uuid;
  v_futuro uuid;
  v_correos int := (select count(*) from motor.correos where tipo = 'incidencia');
begin
  -- 1. Lista de compras -------------------------------------------------------------------
  r := motor.compras_lista_de();
  perform pg_temp.comprobar('Lista de compras: 27 productos activos, en su orden, sin gasolina ni paquetes',
    jsonb_array_length(r -> 'compras') = 27 and r -> 'compras' -> 0 ->> 'nombre' = 'Bolsas adhesivas pequeñas'
    and not exists (select 1 from jsonb_array_elements(r -> 'compras') x where x ->> 'nombre' ilike any (array['%gasolina%', '%paquete%'])),
    r::text);
  perform pg_temp.comprobar('Cada forma con lo suyo: internet con enlace, tienda con sitio (y dirección si la hay), Administración',
    (select count(*) from public.compras where forma = 'internet' and enlace like 'https://www.amazon.es/dp/%') = 6
    and (select direccion from public.compras where nombre = 'Guantes de nitrilo') = 'C/ San Nicolás de Olabeaga 12 (lonja), 48013 Bilbao'
    and (select sitio from public.compras where nombre = 'Rollos de TPV') = 'Kutxabank'
    and (select sitio from public.compras where nombre = 'Alcohol') = 'Cualquier supermercado'
    and (select direccion from public.compras where nombre = 'Alcohol') is null
    and (select forma from public.compras where nombre = 'Granel') = 'administracion');

  r := motor.guardar_compra_de(adm, null, 'Cinta de carrocero', 'tienda', null, 'Cualquier bazar chino', null, null, null, null);
  perform pg_temp.comprobar('Administración añade un producto (al final de la lista)',
    r -> 'compra' ->> 'nombre' = 'Cinta de carrocero' and (r -> 'compra' ->> 'orden')::int > 137, r::text);
  r := motor.guardar_compra_de(adm, (r -> 'compra' ->> 'id')::uuid, 'Cinta de carrocero', 'internet', null, null, null, null, null, null);
  perform pg_temp.comprobar('Por internet sin enlace: no se guarda', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.guardar_compra_de(adm, pg_temp.compra('Cinta de carrocero'), 'Cinta de carrocero', 'tienda', null,
                               'Cualquier bazar chino', null, null, null, false);
  perform pg_temp.comprobar('Quitar es desactivar: deja de salir en la lista, pero sigue en la tabla',
    r -> 'compra' ->> 'activo' = 'false'
    and not exists (select 1 from jsonb_array_elements(motor.compras_lista_de() -> 'compras') x where x ->> 'nombre' = 'Cinta de carrocero')
    and pg_temp.compra('Cinta de carrocero') is not null, r::text);

  -- 2. Hay que comprar algo ---------------------------------------------------------------
  j := motor.generar_jornada(op, '2026-12-14');
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', null, null, null, null, null,
                                 pg_temp.compra('Bolsas adhesivas pequeñas'), pg_temp.h('14', '09:00'));
  t := r -> 'tarea';
  perform pg_temp.comprobar('Por internet: tarea «Compra: …» con su enlace; la hace él; para hoy',
    t ->> 'titulo' = 'Compra: Bolsas adhesivas pequeñas' and t ->> 'enlace' = 'https://www.amazon.es/dp/B077ZQQ8Q5'
    and r -> 'incidencia' ->> 'quien' = 'operario' and r -> 'incidencia' ->> 'importancia' = 'hoy'
    and r -> 'incidencia' ->> 'opcion_texto' = 'Hay que comprar algo'
    and (r -> 'incidencia' ->> 'compra_id')::uuid = pg_temp.compra('Bolsas adhesivas pequeñas'), r::text);
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.h('14', '09:10') where id = (t ->> 'id')::uuid;
  perform pg_temp.comprobar('Por internet: al hacerla, «Pedido, esperando a que llegue»',
    (select estado from public.incidencias where id = (r -> 'incidencia' ->> 'id')::uuid) = 'esperando_llegada');

  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', null, null, 'ahora', null, null,
                                 pg_temp.compra('Guantes de nitrilo'), pg_temp.h('14', '09:15'));
  t := r -> 'tarea';
  perform pg_temp.comprobar('En una tienda: «Ve a comprar … a [sitio]» con la dirección; la importancia la puede cambiar',
    t ->> 'titulo' = 'Ve a comprar guantes de nitrilo a Arte Sano Tattoo Supplies'
    and t ->> 'porque' = 'C/ San Nicolás de Olabeaga 12 (lonja), 48013 Bilbao' and t -> 'enlace' = 'null'
    and (t ->> 'urgente')::boolean, r::text);
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.h('14', '09:40') where id = (t ->> 'id')::uuid;
  perform pg_temp.comprobar('En una tienda: al hacerla, la incidencia se cierra',
    (select estado from public.incidencias where id = (r -> 'incidencia' ->> 'id')::uuid) = 'cerrada');
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', null, null, null, null, null,
                                 pg_temp.compra('Alcohol'), pg_temp.h('14', '09:41'));
  perform pg_temp.comprobar('«Cualquier supermercado»: sin dirección',
    r -> 'tarea' ->> 'titulo' = 'Ve a comprar alcohol a cualquier supermercado' and r -> 'tarea' -> 'porque' = 'null', r::text);

  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', 'quedan dos bolsas', null, null, null, null,
                                 pg_temp.compra('Granel'), pg_temp.h('14', '09:45'));
  perform pg_temp.comprobar('Lo pide Administración: sin tarea, «Esperando a Administración» y correo en el momento',
    r -> 'tarea' = 'null' and r -> 'incidencia' ->> 'estado' = 'esperando_administracion'
    and r -> 'incidencia' ->> 'descripcion' = 'Granel: quedan dos bolsas'
    and exists (select 1 from motor.correos where tipo = 'incidencia' and ref = r -> 'incidencia' ->> 'id'), r::text);

  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', 'Pilas para la báscula', null, null, null, null, null,
                                 pg_temp.h('14', '09:50'));
  perform pg_temp.comprobar('«Otra cosa»: una línea, correo y «Esperando a Administración»',
    r -> 'tarea' = 'null' and r -> 'incidencia' ->> 'estado' = 'esperando_administracion'
    and r -> 'incidencia' ->> 'quien' = 'administracion'
    and exists (select 1 from motor.correos where tipo = 'incidencia' and ref = r -> 'incidencia' ->> 'id'), r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', '  ', null, null, null, null, null, pg_temp.h('14', '09:51'));
  perform pg_temp.comprobar('«Otra cosa» sin escribir nada: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'comprar', null, null, null, null, null,
                                 pg_temp.compra('Cinta de carrocero'), pg_temp.h('14', '09:52'));
  perform pg_temp.comprobar('Un producto quitado de la lista no se puede pedir', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);

  -- 3. Varios -------------------------------------------------------------------------
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'varios', 'Llevar las cajas vacías a reciclar', 'operario', 'cuando_pueda',
                                 null, null, null, pg_temp.h('14', '10:00'));
  perform pg_temp.comprobar('Varios, lo hace él: tarea «[descripción]» en su cola de tiempo libre',
    r -> 'tarea' ->> 'titulo' = 'Llevar las cajas vacías a reciclar' and r -> 'incidencia' ->> 'opcion_texto' = 'Varios'
    and (select prioridad_cola from public.tareas where id = (r -> 'tarea' ->> 'id')::uuid) = 'C', r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'varios', 'La puerta del almacén no cierra bien', 'administracion', null,
                                 null, null, null, pg_temp.h('14', '10:05'));
  perform pg_temp.comprobar('Varios, Administración: correo y «Esperando a Administración»',
    r -> 'tarea' = 'null' and r -> 'incidencia' ->> 'estado' = 'esperando_administracion'
    and exists (select 1 from motor.correos where tipo = 'incidencia' and ref = r -> 'incidencia' ->> 'id'), r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'corregir', 'La selladora no calienta', null, null, null, null, null,
                                 pg_temp.h('14', '10:06'));
  perform pg_temp.comprobar('Las opciones de antes se siguen aceptando (corregir)',
    r -> 'tarea' ->> 'titulo' = 'Corregir: La selladora no calienta', r::text);
  perform pg_temp.comprobar('Correos de incidencia: los 3 que van a Administración (Granel, otra cosa, varios)',
    (select count(*) from motor.correos where tipo = 'incidencia') = v_correos + 3);

  -- 4. Avisos de Administración ------------------------------------------------------------
  r := motor.crear_aviso_almacen_de(adm, gen_random_uuid(), '2026-12-14', 'Voy al Casco Viejo y llevo yo la bolsa de Bilbao', null,
                                    pg_temp.h('14', '10:10'));
  v_aviso := (r -> 'aviso' ->> 'id')::uuid;
  r := motor.crear_aviso_almacen_de(adm, gen_random_uuid(), '2026-12-15', 'Un paquete está en reparto', 'Repartidor: 600 000 000',
                                    pg_temp.h('14', '10:11'));
  v_futuro := (r -> 'aviso' ->> 'id')::uuid;
  perform pg_temp.comprobar('Aviso de otro día: con su fecha y su contacto',
    r -> 'aviso' ->> 'fecha' = '2026-12-15' and r -> 'aviso' ->> 'contacto' = 'Repartidor: 600 000 000', r::text);
  perform pg_temp.comprobar('Avisos: no crean tarea',
    not exists (select 1 from public.incidencias where id in (v_aviso, v_futuro) and tarea_resolucion_id is not null));

  r := motor.tarea_activa_de(op, pg_temp.h('14', '10:12'));
  perform pg_temp.comprobar('El de hoy sale arriba en tarea_activa (avisos) y cuenta en sus incidencias; el de mañana, no',
    r -> 'avisos' = jsonb_build_array(jsonb_build_object('id', v_aviso, 'texto', 'Voy al Casco Viejo y llevo yo la bolsa de Bilbao',
                                                         'contacto', null, 'fecha', '2026-12-14'))
    and exists (select 1 from jsonb_array_elements(motor.incidencias_abiertas_de(op, pg_temp.h('14', '10:12')) -> 'incidencias') x
                 where x ->> 'id' = v_aviso::text and x ->> 'opcion_texto' = 'Aviso de Administración')
    and not exists (select 1 from jsonb_array_elements(motor.incidencias_abiertas_de(op, pg_temp.h('14', '10:12')) -> 'incidencias') x
                     where x ->> 'id' = v_futuro::text), r ->> 'avisos');
  r := motor.estado_actual_de(pg_temp.h('14', '10:12'));
  perform pg_temp.comprobar('Administración ve sus avisos abiertos, los de hoy y los de días que vienen',
    (select array_agg(x ->> 'id' order by x ->> 'fecha') from jsonb_array_elements(r -> 'avisos_almacen') x)
      = array[v_aviso::text, v_futuro::text], r ->> 'avisos_almacen');

  r := motor.tarea_activa_de(op, pg_temp.h('15', '08:35'));
  perform pg_temp.comprobar('El martes sale el de su día (con el contacto) y sigue el de ayer, que no se cerró',
    jsonb_array_length(r -> 'avisos') = 2 and r -> 'avisos' -> 1 ->> 'contacto' = 'Repartidor: 600 000 000', r ->> 'avisos');

  r := motor.cerrar_incidencia_de(op, v_aviso, 'Visto', pg_temp.h('14', '11:00'));
  perform pg_temp.comprobar('El operario cierra el aviso como las demás incidencias',
    r -> 'incidencia' ->> 'estado' = 'cerrada' and r -> 'tarea_activa' -> 'avisos' = '[]', r::text);
  r := motor.contenido_cierre(j, 'manana', pg_temp.h('14', '13:00'));
  perform pg_temp.comprobar('Consta en el cierre del turno, sin el contacto',
    exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'id' = v_aviso::text)
    and motor.texto_cierre(r) ->> 'texto' like '%Aviso de Administración: Voy al Casco Viejo%'
    and motor.texto_cierre(r) ->> 'texto' not like '%600 000 000%', motor.texto_cierre(r) ->> 'texto');
  r := motor.cancelar_aviso_almacen_de(adm, v_futuro, pg_temp.h('14', '12:00'));
  perform pg_temp.comprobar('Administración cancela el de mañana: queda cerrado y ya no sale',
    r -> 'aviso' ->> 'estado' = 'cerrada' and r -> 'aviso' ->> 'nota' = 'Cancelado por Administración'
    and motor.tarea_activa_de(op, pg_temp.h('15', '08:35')) -> 'avisos' = '[]', r::text);

  r := motor.crear_aviso_almacen_de(adm, gen_random_uuid(), '2026-12-11', 'Para el viernes pasado', null, pg_temp.h('14', '12:01'));
  perform pg_temp.comprobar('Un aviso para un día pasado no vale', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.crear_aviso_almacen_de(adm, gen_random_uuid(), '2026-12-19', 'Sábado', null, pg_temp.h('14', '12:02'));
  perform pg_temp.comprobar('Un aviso para un día que no trabaja el almacén: SIN_JORNADA', r -> 'error' ->> 'codigo' = 'SIN_JORNADA', r::text);
end;
$$;

-- 5. Permisos ----------------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
begin
  perform pg_temp.comprobar('El operario ve la lista de compras',
    jsonb_array_length(public.compras_lista() -> 'compras') = 27);
  perform pg_temp.comprobar('El operario no puede cambiar la lista (NO_AUTORIZADO)',
    public.guardar_compra('Algo', 'tienda', sitio => 'Bazar') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
  perform pg_temp.comprobar('El operario no puede crear avisos ni cancelarlos (NO_AUTORIZADO)',
    public.crear_aviso_almacen(gen_random_uuid(), current_date, 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO'
    and public.cancelar_aviso_almacen(gen_random_uuid()) -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
begin
  perform pg_temp.comprobar('Administración ve la lista y la puede cambiar; no crea incidencias del operario',
    jsonb_array_length(public.compras_lista() -> 'compras') = 27
    and public.guardar_compra('Algo', 'tienda', sitio => 'Bazar') -> 'compra' ->> 'nombre' = 'Algo'
    and public.crear_incidencia(gen_random_uuid(), 'varios', 'x') -> 'error' ->> 'codigo' = 'NO_AUTORIZADO');
end;
$$;
reset role;
set local role anon;
select pg_temp.comprobar('Sin sesión no se puede usar nada',
  not has_function_privilege('anon', 'public.compras_lista()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.crear_aviso_almacen(uuid, date, text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.crear_incidencia(uuid, text, text, text, text, uuid, text, uuid)', 'EXECUTE'));
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
