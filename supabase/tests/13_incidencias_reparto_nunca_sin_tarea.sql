-- Prueba 13 · Incidencias, reparto y «nunca sin tarea» (Tarea 7, ESTADO v1.17)
-- Reparto pegado por Administración en la jornada del operario por defecto;
-- «Pega el reparto» se cierra sola y, sin reparto, pide motivo; se adelantan las
-- fijas de la tarde y «Orden y limpieza» no se gasta; incidencias con opción,
-- quién e importancia (tarea, cierre solo, compras esperando, correo a
-- Administración, «Estoy bloqueado»), lo que devuelve tarea_activa al recargar,
-- el cierre del turno y los permisos.
-- Lunes 23/11/2026 a jueves 26/11/2026. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- Configuración de la prueba (se deshace al final): operario por defecto y correo ficticios.
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;
update public.configuracion set clave = 'correo_administracion_real' where clave = 'correo_administracion' and centro_id is null;
insert into public.configuracion (clave, centro_id, valor) values ('correo_administracion', null, '"admin@osasun.invalid"');

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
create function pg_temp.h(p_dia date, p_hora text) returns timestamptz language sql as $$
  select (p_dia || ' ' || p_hora || ':00+01')::timestamptz $$;
create function pg_temp.tarea(p_jornada uuid, p_clave text) returns uuid language sql as $$
  select id from public.tareas where jornada_id = p_jornada and clave = p_clave $$;
create function pg_temp.destino(p_codigo text) returns uuid language sql as $$
  select id from public.centros_trabajo where codigo = p_codigo $$;
create function pg_temp.produccion(p_faltan_v2 integer) returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('producto', 'V2', 'formato', '4g', 'pedido', 30, 'en_almacen', 30 - p_faltan_v2, 'faltan', p_faltan_v2, 'aviso', null, 'orden', 1),
    jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'pedido', 9, 'en_almacen', 7, 'faltan', 2, 'aviso', null, 'orden', 3)) $$;
create function pg_temp.bolsas() returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('destino_id', pg_temp.destino('BILBAO'), 'items', jsonb_build_array(
      jsonb_build_object('producto', 'V2', 'formato', '4g', 'cantidad', 30, 'orden', 1),
      jsonb_build_object('producto', 'BZ1', 'formato', '4g', 'cantidad', 9, 'orden', 3)))) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  lun constant date := '2026-11-23';
  mar constant date := '2026-11-24';
  jue constant date := '2026-11-26';
  j uuid;
  j2 uuid;
  j4 uuid;
  r jsonb;
  r2 jsonb;
  v_t uuid;
  v_el uuid;
  v_rep uuid;
  i1 uuid; i2 uuid; i3 uuid; i4 uuid; i5 uuid; i6 uuid; i7 uuid;
  c1 uuid := gen_random_uuid();
  t text;
begin
  -- ---------------------------------------------------------------- Nunca sin tarea (jueves)
  j4 := motor.generar_jornada(op, jue);
  update public.tareas set estado = 'hecha'
   where jornada_id = j4 and clave not in ('control_materiales', 'cola_orden', 'recuento_manana', 'revisar_envio');
  r := motor.tarea_activa_de(op, pg_temp.h(jue, '11:00'));
  perform pg_temp.comprobar('Nunca sin tarea: el jueves por la mañana, sin nada disponible, se adelanta el control de materiales',
    r -> 'tarea' ->> 'clave' = 'control_materiales', r -> 'tarea' ->> 'clave');
  perform pg_temp.comprobar('…y lo que viene después sigue siendo el recuento de las 12:45 (no se adelanta)',
    r ->> 'siguiente' like 'Recuento de stock%12:45', r ->> 'siguiente');

  -- ---------------------------------------------------------------- Reparto (lunes)
  j := motor.generar_jornada(op, lun);
  r := public.servidor_preparar(adm, pg_temp.h(lun, '08:40'));
  perform pg_temp.comprobar('Administración prepara el reparto en la jornada del operario por defecto',
    r ->> 'rol' = 'administracion' and (r ->> 'jornada_id')::uuid = j and r -> 'error' is null, r::text);
  r := public.servidor_preparar(adm, pg_temp.h('2026-11-28', '10:00'));
  perform pg_temp.comprobar('Sin jornada del operario (sábado), Administración no recibe error (la lista de stock sigue funcionando)',
    r -> 'error' is null and r -> 'jornada_id' = 'null'::jsonb, r::text);

  v_t := pg_temp.tarea(j, 'pegar_reparto');
  perform motor.iniciar_tarea_de(op, v_t, pg_temp.h(lun, '08:46'));
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h(lun, '08:47'));
  perform pg_temp.comprobar('Terminar «Pega el reparto» sin reparto aceptado exige motivo (MOTIVO_OBLIGATORIO)',
    r -> 'error' ->> 'codigo' = 'MOTIVO_OBLIGATORIO', r::text);
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '08:47'));
  perform pg_temp.comprobar('tarea_activa: sin reparto todavía, reparto_de_hoy es null (la pantalla muestra «Pegar reparto»)',
    r ? 'reparto_de_hoy' and r -> 'reparto_de_hoy' = 'null'::jsonb, r -> 'reparto_de_hoy' #>> '{}');

  r := public.servidor_guardar_reparto(adm, j, 'reparto', 'texto de Administración', 'huella-adm-1', lun, 'administracion',
                                       null, '[]', pg_temp.produccion(5), pg_temp.bolsas(), true, pg_temp.h(lun, '08:48'));
  v_rep := (r ->> 'reparto_id')::uuid;
  perform pg_temp.comprobar('Administración pega el reparto: aceptado, con producción y bolsas en la jornada del operario',
    r ->> 'estado' = 'aceptado'
    and (select count(*) from public.tarea_elementos where tarea_id = pg_temp.tarea(j, 'produccion_reparto')) = 2
    and (select count(*) from public.tarea_elementos where tarea_id = pg_temp.tarea(j, 'bolsas')) = 2, r::text);
  perform pg_temp.comprobar('Al pegarlo Administración, la respuesta no trae la tarea activa (no es su jornada)',
    r -> 'tarea_activa' is null or r -> 'tarea_activa' = 'null'::jsonb, r -> 'tarea_activa' #>> '{}');
  perform pg_temp.comprobar('«Pega el reparto» se cierra sola al aceptarse el reparto',
    (select estado = 'hecha' and resultado = 'Reparto preparado por Administración de pruebas' and terminada_en = pg_temp.h(lun, '08:48')
       from public.tareas where id = v_t));
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '08:49'));
  perform pg_temp.comprobar('tarea_activa: reparto_de_hoy con el reparto, cuándo y quién lo pegó (la pantalla muestra «Modificar reparto»)',
    (r -> 'reparto_de_hoy' ->> 'reparto_id')::uuid = v_rep and (r -> 'reparto_de_hoy' ->> 'pegado_por')::uuid = adm
    and (r -> 'reparto_de_hoy' ->> 'aceptado_en')::timestamptz = pg_temp.h(lun, '08:48')
    and r -> 'reparto_de_hoy' ->> 'pegado_por_nombre' is not null, r -> 'reparto_de_hoy' #>> '{}');

  v_el := (select id from public.tarea_elementos where tarea_id = pg_temp.tarea(j, 'produccion_reparto') and producto = 'V2');
  update public.tarea_elementos set cantidad_hecha = 3 where id = v_el;  -- 3 cajas ya hechas
  r := public.servidor_guardar_reparto(adm, j, 'reparto', 'texto corregido', 'huella-adm-2', lun, 'administracion',
                                       null, '[]', pg_temp.produccion(4), pg_temp.bolsas(), true, pg_temp.h(lun, '09:05'));
  perform pg_temp.comprobar('Administración modifica el reparto: lo sustituye y se conserva lo hecho (3 de 4 cajas de V2)',
    (r ->> 'sustituye_a')::uuid = v_rep
    and (select cantidad = 4 and cantidad_hecha = 3 from public.tarea_elementos where id = v_el), r::text);

  -- ---------------------------------------------------------------- Nunca sin tarea (lunes)
  update public.tareas set estado = 'hecha'
   where jornada_id = j and estado in ('pendiente', 'en_curso')
     and clave not in ('minis', 'cola_orden', 'recuento_manana', 'revisar_envio', 'recuento_tarde_envio', 'nacex_salida');
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '11:30'));
  perform pg_temp.comprobar('Nunca sin tarea: sin nada disponible se adelanta la fija de la tarde (minis del lunes), antes que «Orden y limpieza»',
    r -> 'tarea' ->> 'clave' = 'minis', r -> 'tarea' ->> 'clave');
  perform motor.iniciar_tarea_de(op, pg_temp.tarea(j, 'minis'), pg_temp.h(lun, '11:31'));
  r := motor.terminar_tarea_de(op, pg_temp.tarea(j, 'minis'), null, null, pg_temp.h(lun, '12:00'));
  perform pg_temp.comprobar('Después, «Orden y limpieza»',
    r -> 'tarea_activa' -> 'tarea' ->> 'clave' = 'cola_orden', r -> 'tarea_activa' -> 'tarea' ->> 'clave');
  perform motor.iniciar_tarea_de(op, pg_temp.tarea(j, 'cola_orden'), pg_temp.h(lun, '12:01'));
  r := motor.terminar_tarea_de(op, pg_temp.tarea(j, 'cola_orden'), null, null, pg_temp.h(lun, '12:20'));
  perform pg_temp.comprobar('«Orden y limpieza» no se gasta: al terminarla vuelve a estar disponible',
    r -> 'tarea_activa' -> 'tarea' ->> 'clave' like 'cola_orden:%'
    and r -> 'tarea_activa' -> 'tarea' ->> 'titulo' = (select titulo from public.plantillas_tarea where codigo = 'cola_orden')
    and (select count(*) from public.tareas where jornada_id = j and clave like 'cola_orden%' and estado = 'hecha') = 1,
    r -> 'tarea_activa' -> 'tarea' ->> 'clave');
  perform pg_temp.comprobar('Lo ligado a su hora no se adelanta: el recuento sigue esperando a las 12:45',
    r -> 'tarea_activa' ->> 'siguiente' like 'Recuento de stock%12:45'
    and (select estado = 'pendiente' from public.tareas where id = pg_temp.tarea(j, 'recuento_manana')),
    r -> 'tarea_activa' ->> 'siguiente');
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '12:45'));
  perform pg_temp.comprobar('A su hora, el recuento va antes que «Orden y limpieza»', r -> 'tarea' ->> 'clave' = 'recuento_manana',
    r -> 'tarea' ->> 'clave');
  update public.tareas set estado = 'hecha', terminada_en = pg_temp.h(lun, '12:59') where id = pg_temp.tarea(j, 'recuento_manana');
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '13:30'));
  perform pg_temp.comprobar('Entre turnos no se ofrece nada (ni «Orden y limpieza»); lo siguiente es la revisión del envío de las 15:30',
    r -> 'tarea' = 'null'::jsonb and r ->> 'siguiente' like '%15:30', r::text);

  -- ---------------------------------------------------------------- Incidencias (lunes tarde)
  r := motor.crear_incidencia_de(op, c1, 'corregir', E'La selladora\n  no calienta ', null, null, null, null, null, pg_temp.h(lun, '15:40'));
  i1 := (r -> 'incidencia' ->> 'id')::uuid;
  perform pg_temp.comprobar('Corregir, por defecto: la resuelve él, ahora; descripción en una línea',
    r -> 'incidencia' ->> 'quien' = 'operario' and r -> 'incidencia' ->> 'importancia' = 'ahora'
    and r -> 'incidencia' ->> 'estado' = 'abierta' and r -> 'incidencia' ->> 'descripcion' = 'La selladora no calienta', r::text);
  perform pg_temp.comprobar('…crea su tarea: urgente y obligatoria, y pasa al día siguiente si no se hace',
    r -> 'tarea' ->> 'titulo' = 'Corregir: La selladora no calienta' and (r -> 'tarea' ->> 'urgente')::boolean
    and (r -> 'tarea' ->> 'obligatoria')::boolean
    and (select no_terminada = 'arrastrar' from public.tareas where id = (r -> 'tarea' ->> 'id')::uuid), r -> 'tarea' #>> '{}');
  perform pg_temp.comprobar('…y «ahora» va como las urgentes: antes que la revisión del envío de las 15:30',
    r -> 'tarea_activa' -> 'tarea' ->> 'id' = r -> 'tarea' ->> 'id'
    and (r -> 'tarea_activa' ->> 'incidencias_abiertas')::int = 1, r -> 'tarea_activa' -> 'tarea' ->> 'titulo');
  r2 := motor.crear_incidencia_de(op, c1, 'corregir', 'otra cosa', null, null, null, null, null, pg_temp.h(lun, '15:41'));
  perform pg_temp.comprobar('Repetir con el mismo id_cliente devuelve la misma incidencia, sin duplicar la tarea',
    (r2 -> 'incidencia' ->> 'id')::uuid = i1
    and (select count(*) from public.incidencias where persona_id = op and estado <> 'cerrada') = 1
    and (select count(*) from public.tareas where jornada_id = j and clave like 'incidencia:%') = 1, r2::text);

  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'llega_mercancia', 'Cajas de Sprint Digital', null, null, null, null, null, pg_temp.h(lun, '15:42'));
  i2 := (r -> 'incidencia' ->> 'id')::uuid;
  perform pg_temp.comprobar('Llega mercancía, por defecto: él, ahora; es la recepción de siempre (registrar_evento), urgente',
    r -> 'incidencia' ->> 'importancia' = 'ahora' and r -> 'tarea' ->> 'clave' like 'recepcion_mercancia:%'
    and (r -> 'tarea' ->> 'urgente')::boolean and r -> 'tarea' ->> 'porque' = 'Cajas de Sprint Digital'
    and exists (select 1 from public.eventos_jornada where jornada_id = j and tipo = 'llega_mercancia'), r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'pedido_cliente', 'Pedido web 1234', null, null, null, null, null, pg_temp.h(lun, '15:43'));
  i3 := (r -> 'incidencia' ->> 'id')::uuid;
  perform pg_temp.comprobar('Pedido de cliente, por defecto: él, hoy (obligatoria del día, no urgente)',
    r -> 'incidencia' ->> 'importancia' = 'hoy' and r -> 'tarea' ->> 'clave' like 'pedido_cliente:%'
    and (r -> 'tarea' ->> 'obligatoria')::boolean and not (r -> 'tarea' ->> 'urgente')::boolean, r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'recogida_nacex', 'Paquete de Tatto Arte', null, 'cuando_pueda', null, null, null, pg_temp.h(lun, '15:44'));
  i4 := (r -> 'incidencia' ->> 'id')::uuid;
  perform pg_temp.comprobar('Recogida en Nacex «cuando pueda»: a la cola de tiempo libre, sigue abierta de un día a otro',
    r -> 'incidencia' ->> 'importancia' = 'cuando_pueda' and r -> 'tarea' ->> 'titulo' = 'Recogida en Nacex: Paquete de Tatto Arte'
    and not (r -> 'tarea' ->> 'obligatoria')::boolean
    and (select prioridad_cola = 'C' and no_terminada = 'sigue_abierta' from public.tareas where id = (r -> 'tarea' ->> 'id')::uuid), r::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'pedir_comprar', 'Bolsas 8x12', null, null, null, null, null, pg_temp.h(lun, '15:45'));
  i5 := (r -> 'incidencia' ->> 'id')::uuid;
  perform pg_temp.comprobar('Pedir o comprar, por defecto: él, hoy',
    r -> 'incidencia' ->> 'quien' = 'operario' and r -> 'incidencia' ->> 'importancia' = 'hoy'
    and r -> 'tarea' ->> 'titulo' = 'Pedir o comprar: Bolsas 8x12', r::text);

  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'no_quedan_vapers', 'x', null, null, null, null, null, pg_temp.h(lun, '15:46'));
  r2 := motor.crear_incidencia_de(op, gen_random_uuid(), 'corregir', '   ', null, null, null, null, null, pg_temp.h(lun, '15:46'));
  perform pg_temp.comprobar('«No quedan vapers» no es una opción; sin descripción tampoco (DATOS_NO_VALIDOS)',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS' and r2 -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text || r2::text);
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'corregir', 'x', 'jefe', null, null, null, null, pg_temp.h(lun, '15:46'));
  r2 := motor.crear_incidencia_de(op, gen_random_uuid(), 'corregir', 'x', null, 'mañana', null, null, null, pg_temp.h(lun, '15:46'));
  perform pg_temp.comprobar('Quién e importancia no válidos: DATOS_NO_VALIDOS',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS' and r2 -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text || r2::text);

  -- Corregir mide su tiempo de inicio a fin y se cierra sola al hacer la tarea.
  v_t := (select tarea_resolucion_id from public.incidencias where id = i1);
  perform motor.iniciar_tarea_de(op, v_t, pg_temp.h(lun, '15:47'));
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '15:57'));
  perform pg_temp.comprobar('Al recargar: tarea_activa trae la incidencia en curso con su tiempo (10 min) y el número de abiertas (5)',
    (r -> 'incidencia_en_curso' ->> 'id')::uuid = i1 and (r -> 'incidencia_en_curso' ->> 'minutos')::int = 10
    and r -> 'incidencia_en_curso' ->> 'estado_texto' = 'En curso desde las 15:47'
    and (r ->> 'incidencias_abiertas')::int = 5 and jsonb_array_length(r -> 'problemas_abiertos') = 0, r::text);
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h(lun, '15:59'));
  perform pg_temp.comprobar('Hecha su tarea, la incidencia se cierra sola, con su tiempo (12 min)',
    (select estado = 'cerrada' and terminada_en = pg_temp.h(lun, '15:59') and cerrada_por = op from public.incidencias where id = i1)
    and (motor.incidencia_json(i1, pg_temp.h(lun, '16:30')) ->> 'minutos')::int = 12
    and (r -> 'tarea_activa' ->> 'incidencias_abiertas')::int = 4 and r -> 'tarea_activa' -> 'incidencia_en_curso' = 'null'::jsonb,
    motor.incidencia_json(i1, pg_temp.h(lun, '16:30'))::text);

  -- Pedir o comprar: hecha la tarea, queda «pedido, esperando a que llegue» y se cierra a mano.
  v_t := (select tarea_resolucion_id from public.incidencias where id = i5);
  perform motor.iniciar_tarea_de(op, v_t, pg_temp.h(lun, '16:00'));
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h(lun, '16:05'));
  perform pg_temp.comprobar('Compra hecha: la incidencia queda «Pedido, esperando a que llegue» (sigue abierta)',
    (select estado = 'esperando_llegada' and terminada_en is null from public.incidencias where id = i5)
    and motor.incidencia_json(i5, pg_temp.h(lun, '16:05')) ->> 'estado_texto' = 'Pedido, esperando a que llegue'
    and (r -> 'tarea_activa' ->> 'incidencias_abiertas')::int = 4, r -> 'tarea_activa' ->> 'incidencias_abiertas');
  r := motor.cerrar_incidencia_de(op, i5, 'Ya está en el almacén', pg_temp.h(lun, '16:10'));
  perform pg_temp.comprobar('Cerrar incidencia con una línea: queda cerrada con su nota',
    r -> 'incidencia' ->> 'estado' = 'cerrada' and r -> 'incidencia' ->> 'nota' = 'Ya está en el almacén'
    and (r -> 'tarea_activa' ->> 'incidencias_abiertas')::int = 3, r::text);
  r := motor.cerrar_incidencia_de(op, i5, null, pg_temp.h(lun, '16:11'));
  r2 := motor.cerrar_incidencia_de(adm, i4, null, pg_temp.h(lun, '16:11'));
  perform pg_temp.comprobar('Cerrarla otra vez avisa (INCIDENCIA_YA_CERRADA, sin error); la de otro no existe (NO_ENCONTRADO)',
    r -> 'aviso' ->> 'codigo' = 'INCIDENCIA_YA_CERRADA' and r -> 'error' is null
    and r2 -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text || r2::text);
  r := motor.cerrar_incidencia_de(op, i4, null, pg_temp.h(lun, '16:12'));
  perform pg_temp.comprobar('Cerrar una incidencia con su tarea pendiente cancela la tarea (ya no hace falta)',
    r -> 'incidencia' ->> 'estado' = 'cerrada'
    and (select t.estado = 'cancelada' and t.motivo_no_hecha = 'Ya no hace falta: incidencia cerrada'
           from public.tareas t join public.incidencias i on i.tarea_resolucion_id = t.id where i.id = i4), r::text);

  -- La resuelve Administración: sin tarea, correo en el momento y esperando a que él la cierre.
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'pedir_comprar', 'Falta granel de indoor', 'administracion', null, null, null, null, pg_temp.h(lun, '16:15'));
  i6 := (r -> 'incidencia' ->> 'id')::uuid;
  perform pg_temp.comprobar('La resuelve Administración: no crea tarea y queda «Esperando a Administración»',
    r -> 'tarea' = 'null'::jsonb and r -> 'incidencia' ->> 'estado' = 'esperando_administracion'
    and r -> 'incidencia' ->> 'estado_texto' = 'Esperando a Administración'
    and (select tarea_resolucion_id is null from public.incidencias where id = i6), r::text);
  perform pg_temp.comprobar('…y se encola en el momento un correo a Administración',
    exists (select 1 from motor.correos where tipo = 'incidencia' and ref = i6::text));
  r := public.servidor_correo_reclamar('incidencia', i6::text);
  perform pg_temp.comprobar('El correo dice «Incidencia: …» con la opción, la importancia y quién la abrió',
    (r ->> 'enviar')::boolean and r ->> 'asunto' = 'Incidencia: Falta granel de indoor'
    and r ->> 'texto' like 'Hay que pedir o comprar algo · Importancia: hoy%Falta granel de indoor%23/11 a las 16:15%', r::text);
  r := public.servidor_correo_respuesta('incidencia', i6::text, 'rechazado', 'prueba');
  r2 := public.servidor_correo_respuesta('incidencia', i6::text, 'enviado', 'resend:x');
  perform pg_temp.comprobar('Mismo sistema de reintentos: rechazado → reintentar',
    r ->> 'estado' = 'reintentar' and (select estado = 'reintentar' from motor.correos where tipo = 'incidencia' and ref = i6::text), r::text);

  -- Estoy bloqueado: el flujo de problemas de siempre, sobre la tarea en curso.
  perform motor.iniciar_tarea_de(op, pg_temp.tarea(j, 'revisar_envio'), pg_temp.h(lun, '16:20'));
  r := motor.crear_incidencia_de(op, gen_random_uuid(), 'bloqueado', 'No encuentro la hoja de envíos', null, null, null, 'no_encuentro', null, pg_temp.h(lun, '16:21'));
  perform pg_temp.comprobar('Estoy bloqueado: abre un problema en la tarea en curso, que queda bloqueada; «llama ahora»',
    r -> 'incidencia' = 'null'::jsonb and r -> 'problema' ->> 'tipo' = 'no_encuentro' and r ->> 'pasos' = 'Llama a Administración ahora.'
    and (select estado = 'bloqueada' from public.tareas where id = pg_temp.tarea(j, 'revisar_envio')), r::text);
  r2 := motor.crear_incidencia_de(op, gen_random_uuid(), 'bloqueado', 'otra vez', null, null, pg_temp.tarea(j, 'revisar_envio'), null, null, pg_temp.h(lun, '16:22'));
  perform pg_temp.comprobar('PROBLEMA_YA_ABIERTO trae el problema abierto (error.problema)',
    r2 -> 'error' ->> 'codigo' = 'PROBLEMA_YA_ABIERTO' and r2 -> 'error' -> 'problema' ->> 'id' = r -> 'problema' ->> 'id', r2::text);
  r2 := motor.tarea_activa_de(op, pg_temp.h(lun, '16:23'));
  perform pg_temp.comprobar('Al recargar: tarea_activa trae los problemas abiertos con su tarea',
    jsonb_array_length(r2 -> 'problemas_abiertos') = 1
    and r2 -> 'problemas_abiertos' -> 0 ->> 'id' = r -> 'problema' ->> 'id'
    and r2 -> 'problemas_abiertos' -> 0 ->> 'tarea' = (select titulo from public.tareas where id = pg_temp.tarea(j, 'revisar_envio')),
    r2 -> 'problemas_abiertos' #>> '{}');
  perform motor.resolver_problema_de(op, (r -> 'problema' ->> 'id')::uuid, 'Está en la carpeta azul', pg_temp.h(lun, '16:24'));

  -- Cerrar incidencias: la lista con su estado en una frase.
  r := motor.incidencias_abiertas_de(op, pg_temp.h(lun, '16:25'));
  perform pg_temp.comprobar('incidencias_abiertas: las 3 abiertas, cada una con su estado en una frase',
    (r ->> 'total')::int = 3
    and (select jsonb_agg(x ->> 'estado_texto' order by x ->> 'abierta_en') from jsonb_array_elements(r -> 'incidencias') x)
        = '["Va ahora, al terminar lo que tienes entre manos", "Pendiente para hoy", "Esperando a Administración"]'::jsonb, r::text);

  -- Las incidencias de antes siguen funcionando (una sola a la vez, midiendo su tiempo).
  r := motor.iniciar_incidencia_de(op, gen_random_uuid(), 'Limpio la mesa', pg_temp.h(lun, '16:30'));
  i7 := (r ->> 'incidencia_id')::uuid;
  r2 := motor.iniciar_incidencia_de(op, gen_random_uuid(), 'Otra', pg_temp.h(lun, '16:31'));
  perform pg_temp.comprobar('iniciar_incidencia (de antes) convive con las nuevas; INCIDENCIA_YA_ABIERTA trae incidencia_id e incidencia',
    i7 is not null and r2 -> 'error' ->> 'codigo' = 'INCIDENCIA_YA_ABIERTA'
    and (r2 -> 'error' ->> 'incidencia_id')::uuid = i7 and (r2 -> 'error' -> 'incidencia' ->> 'id')::uuid = i7, r::text || r2::text);
  r := motor.tarea_activa_de(op, pg_temp.h(lun, '16:35'));
  perform pg_temp.comprobar('…y aparece como incidencia en curso con su tiempo',
    (r -> 'incidencia_en_curso' ->> 'id')::uuid = i7 and (r -> 'incidencia_en_curso' ->> 'minutos')::int = 5, r -> 'incidencia_en_curso' #>> '{}');
  r := motor.terminar_incidencia_de(op, i7, pg_temp.h(lun, '16:38'));
  perform pg_temp.comprobar('terminar_incidencia la cierra con sus minutos',
    (r ->> 'minutos')::int = 8 and (select estado = 'cerrada' from public.incidencias where id = i7), r::text);

  -- Estado actual de Administración con varias abiertas.
  r := motor.estado_actual_de(pg_temp.h(lun, '16:40'));
  perform pg_temp.comprobar('estado_actual: con varias incidencias abiertas no falla y las lista',
    jsonb_array_length(r -> 'incidencias_abiertas') = 3 and r -> 'incidencia_en_curso' = 'null'::jsonb, r -> 'incidencias_abiertas' #>> '{}');

  -- Cierre del turno de tarde.
  r := motor.contenido_cierre(j, 'tarde', pg_temp.h(lun, '18:30'));
  perform pg_temp.comprobar('El cierre recoge las incidencias del turno, con opción, quién, estado y tiempo',
    jsonb_array_length(r -> 'incidencias') = 7
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
                 where x ->> 'id' = i1::text and x ->> 'estado' = 'cerrada' and (x ->> 'minutos')::int = 12 and x ->> 'fin' = '15:59')
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x
                 where x ->> 'id' = i6::text and x ->> 'quien' = 'administracion'), r -> 'incidencias' #>> '{}');
  t := motor.texto_cierre(r) ->> 'texto';
  perform pg_temp.comprobar('Texto del cierre: cada incidencia en una línea con su hora, tiempo y cierre',
    t like '%INCIDENCIAS%- 15:40 Corregir, limpiar o solucionar algo: La selladora no calienta · 12 min · cerrada a las 15:59%'
    and t like '%- 15:45 Hay que pedir o comprar algo: Bolsas 8x12 · 5 min · cerrada a las 16:10 («Ya está en el almacén»)%'
    and t like '%- 16:15 Hay que pedir o comprar algo: Falta granel de indoor · la resuelve Administración · % min · Esperando a Administración%'
    and t like '%- 16:30 Limpio la mesa · 8 min · cerrada a las 16:38%', t);

  -- Lo que no se hace pasa al día siguiente y, al hacerlo, la incidencia se cierra.
  j2 := motor.generar_jornada(op, mar);
  v_t := (select tarea_resolucion_id from public.incidencias where id = i3);
  perform pg_temp.comprobar('El pedido de cliente sin hacer pasa al martes y la incidencia sigue a su tarea nueva',
    (select jornada_id = j2 and tarea_origen_id is not null from public.tareas where id = v_t), v_t::text);
  r := motor.tarea_activa_de(op, pg_temp.h(mar, '08:31'));
  perform pg_temp.comprobar('Al día siguiente, la incidencia «ahora» que quedó sin hacer sigue siendo urgente',
    r -> 'tarea' ->> 'id' = (select tarea_resolucion_id::text from public.incidencias where id = i2), r -> 'tarea' ->> 'titulo');
  perform motor.iniciar_tarea_de(op, v_t, pg_temp.h(mar, '08:32'));
  r := motor.terminar_tarea_de(op, v_t, null, null, pg_temp.h(mar, '08:50'));
  perform pg_temp.comprobar('…y al hacerla el martes, la incidencia del lunes se cierra sola',
    (select estado = 'cerrada' from public.incidencias where id = i3));
  r := motor.contenido_cierre(j2, 'manana', pg_temp.h(mar, '13:00'));
  perform pg_temp.comprobar('El cierre del martes incluye las que siguen abiertas de otro día y la cerrada ese día',
    exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'id' = i6::text)
    and exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'id' = i3::text)
    and not exists (select 1 from jsonb_array_elements(r -> 'incidencias') x where x ->> 'id' = i1::text),
    r -> 'incidencias' #>> '{}');

  -- Pega el reparto sin reparto, con motivo.
  v_t := pg_temp.tarea(j2, 'pegar_reparto');
  perform motor.iniciar_tarea_de(op, v_t, pg_temp.h(mar, '08:51'));
  r := motor.terminar_tarea_de(op, v_t, null, 'Hoy no hay reparto', pg_temp.h(mar, '08:52'));
  perform pg_temp.comprobar('Sin reparto, «Pega el reparto» se termina con motivo',
    (select estado = 'hecha' and motivo_no_hecha = 'Hoy no hay reparto' from public.tareas where id = v_t), r::text);
end;
$$;

-- Permisos: las funciones nuevas son del operario, con sesión.
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.incidencias_abiertas();
  r2 jsonb := public.cerrar_incidencia(gen_random_uuid(), null);
begin
  perform pg_temp.comprobar('Operario: incidencias_abiertas y cerrar_incidencia (una que no es suya: NO_ENCONTRADO)',
    r ? 'total' and r ? 'incidencias' and r2 -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text || r2::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.crear_incidencia(gen_random_uuid(), 'corregir', 'x');
  r2 jsonb := public.incidencias_abiertas();
begin
  perform pg_temp.comprobar('Administración no crea ni lista incidencias del operario (NO_AUTORIZADO)',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO' and r2 -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text || r2::text);
end;
$$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se puede llamar a ninguna de las funciones nuevas',
    pg_temp.rechazada($q$select public.crear_incidencia(gen_random_uuid(), 'corregir', 'x')$q$)
    and pg_temp.rechazada($q$select public.incidencias_abiertas()$q$)
    and pg_temp.rechazada($q$select public.cerrar_incidencia(gen_random_uuid())$q$));
end;
$$;
reset role;
do $$
begin
  perform pg_temp.comprobar('Nadie escribe directamente en incidencias (solo lectura con RLS)',
    not has_table_privilege('authenticated', 'public.incidencias', 'insert')
    and not has_table_privilege('authenticated', 'public.incidencias', 'update'));
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
