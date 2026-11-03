-- Tarea 30b · Franquicias y Durango: «Envíos» y cierre de caja corto (ESTADO_DEL_SISTEMA.md E2-8 v1.50,
-- «Qué tienen las franquicias» y Durango). Solo en pruebas: producción espera con las de tiendas
-- (AGENTE_BASE_DE_DATOS.md §4). Reutiliza la bolsa de la Tarea 28 (bolsas_tienda, lo marcado con
-- motor.bolsa_contenido, «Todo bien» / «Falta algo» → incidencia para Administración) y el cierre de
-- caja (cerrar_caja, cierres_caja). Lo del almacén no cambia: solo se lee lo que ya marca el operario.
--   1. «Envíos» (decisiones del propietario en el chat de la tarea, 03/11/2026): la tienda que recibe
--      por envío (configuración recibe_envio por tienda: Rentería → GIPUZKOA, Durango → DURANGO;
--      Donosti no, porque el envío a Gipuzkoa va entero a Rentería, que es quien lo confirma) ve en
--      tienda_hoy().envios cada envío desde el día siguiente a su salida (al empezar o terminar
--      «Salida a Nacex»; el viernes, «Lleva en el reparto lo que va a Nacex»), con lo marcado al
--      meterlo en la caja. No es una tarea con hora: sigue ahí hasta confirmarlo con
--      confirmar_envio(envio_id, faltan?, nota?). «Falta algo» abre una incidencia para Administración
--      (opción falta_envio). Se guarda en bolsas_tienda (sin tarea).
--   2. Cierre de caja corto (Donosti y Rentería): tarea «Cierre de caja» 10 minutos antes de cerrar,
--      con un punto «Cierre de caja en la app: Z y nº de ventas» (pide: cierre_caja_corto). cerrar_caja
--      sin efectivo ni Glovo; se guarda en cierres_caja con esos dos vacíos. Durango y las demás
--      propias siguen con su «Cierre del día» completo.
--
-- Deshacer: borrar public.confirmar_envio, motor.api_confirmar_envio, motor.confirmar_envio_de,
-- motor.envios_tienda_json, motor.preparar_envios_tienda, motor.salida_envio_en, motor.destino_envio,
-- motor.faltan_de_lista y motor.faltan_texto; volver a crear motor.punto_especial, motor.tarea_tienda_json,
-- motor.marcar_punto_de, motor.cerrar_caja_de y motor.apuntar_reposicion_de como están en
-- 20261103091220, motor.tienda_hoy_de como está en 20261103203048 y public.cerrar_caja sin valores por
-- defecto (20261103091220); borrar las filas de bolsas_tienda de los envíos, las plantillas
-- cierre_caja y la clave recibe_envio; volver a poner not null en bolsas_tienda.tarea_id y en
-- cierres_caja.efectivo y glovo (antes, borrar los cierres cortos) y el check incidencias_opcion_check
-- como está en 20261103203048 (antes, las incidencias falta_envio).

-- ---------------------------------------------------------------------------
-- 1. Tablas: solo se relajan columnas y se añade una opción
-- ---------------------------------------------------------------------------
-- Un envío no tiene tarea en la tienda (no es una tarea con hora).
alter table public.bolsas_tienda alter column tarea_id drop not null;
comment on table public.bolsas_tienda is 'Lo que llega a cada tienda: la bolsa del reparto (cuándo salió, cuándo se recibió, el efectivo de ayer y la reposición) y, desde la Tarea 30b, cada envío (sin tarea; se confirma con «Todo bien» o «Falta algo»).';
-- El cierre corto de las franquicias no lleva efectivo ni Glovo.
alter table public.cierres_caja alter column efectivo drop not null;
alter table public.cierres_caja alter column glovo drop not null;
comment on table public.cierres_caja is 'Cierre de caja de cada tienda y día (Z, nº de ventas, efectivo y Glovo). El efectivo es el de la bolsa del día siguiente. En las franquicias, solo la Z y el nº de ventas (efectivo y Glovo vacíos).';

alter table public.incidencias drop constraint incidencias_opcion_check;
alter table public.incidencias add constraint incidencias_opcion_check
  check (opcion in ('comprar', 'varios', 'aviso', 'llega_mercancia', 'pedido_cliente', 'pedir_comprar',
                    'recogida_nacex', 'corregir', 'falta_reposicion',
                    'sin_producto', 'descuadre', 'comentario_cliente', 'otros', 'falta_envio'));

-- ---------------------------------------------------------------------------
-- 2. Configuración y plantillas
-- ---------------------------------------------------------------------------
-- Qué envío recibe cada tienda (el destino del envío en destinos_reparto). Donosti, ninguno: el envío
-- a Gipuzkoa va entero a Rentería, que lo reparte y lo confirma.
insert into public.configuracion (clave, centro_id, valor)
select 'recibe_envio', c.id, to_jsonb(x.destino)
  from (values ('RENTERIA', 'GIPUZKOA'), ('DURANGO', 'DURANGO')) x(tienda, destino)
  join public.centros_trabajo c on c.codigo = x.tienda
on conflict (clave, centro_id) do nothing;

-- «Cierre de caja» de las franquicias: 10 minutos antes de cerrar (20:20 entre semana; 13:20 el
-- sábado, que no abren por la tarde), con la Z y el nº de ventas. Se activa por tienda.
insert into public.plantillas_tarea (centro_id, codigo, titulo, porque, programacion, dias_semana, turno,
                                     hora_desde, minutos_desde, alterna_turno, contenido, puntos, no_terminada, orden, activa)
select c.id, 'cierre_caja', 'Cierre de caja', 'Para que Administración tenga la Z y el número de ventas del día.',
       'dia_semana', '{1,2,3,4,5,6}'::smallint[], null, 'fin', -10, false, 'puntos',
       array['Cierre de caja en la app: Z y nº de ventas'], 'nada', 90, c.codigo in ('DONOSTI', 'RENTERIA')
  from public.centros_trabajo c where c.tipo = 'tienda';

-- ---------------------------------------------------------------------------
-- 3. Cierre de caja corto
-- ---------------------------------------------------------------------------
create or replace function motor.punto_especial(e public.tarea_elementos)
returns text language sql immutable set search_path = '' as $$
  select coalesce(e.calculo ->> 'especial',
                  case when e.producto = 'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo' then 'cierre_caja'
                       -- Tarea 30b: el cierre corto de las franquicias (Z y nº de ventas).
                       when e.producto = 'Cierre de caja en la app: Z y nº de ventas' then 'cierre_caja_corto' end)
$$;

create or replace function motor.tarea_tienda_json(p_tarea uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque, 'tipo', t.contenido,
    'hora', motor.hora_texto(t.disponible_desde), 'desde', t.disponible_desde,
    'estado', t.estado,
    'se_puede_marcar', t.estado = 'pendiente' and t.disponible_desde <= p_ahora,
    -- Al cerrar la tienda, lo que no se ha hecho queda como no hecho (no pasa al día siguiente).
    'no_hecha', t.estado = 'pendiente'
                and p_ahora >= (select max(motor.en_local(j.fecha, h.hora_fin)) from public.horarios h
                                 where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)),
    'motivo', t.motivo_no_hecha,
    'terminada_en', t.terminada_en, 'hora_fin', motor.hora_texto(t.terminada_en),
    'hecha_por', case when t.estado in ('hecha', 'cancelada') then (
      select r.datos ->> 'hecha_por' from public.registro_eventos r
       where r.tarea_id = t.id and r.tipo in ('tarea_terminada', 'video_no_pudo') order by r.id desc limit 1) end,
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'texto', e.producto, 'hecho', e.estado = 'hecho',
                                          'hecho_por', e.calculo ->> 'hecho_por', 'a_las', motor.hora_texto(e.terminado_en),
                                          -- Tarea 28: los puntos que piden algo más que un toque.
                                          'pide', case motor.punto_especial(e) when 'efectivo' then 'efectivo'
                                                                               when 'cierre_caja' then 'cierre_caja'
                                                                               -- Tarea 30b: Z y nº de ventas.
                                                                               when 'cierre_caja_corto' then 'cierre_caja_corto' end,
                                          'efectivo_esperado', case when motor.punto_especial(e) = 'efectivo'
                                                                    then (e.calculo ->> 'esperado')::numeric end,
                                          'datos', e.calculo -> 'datos')
                       order by e.orden_sugerido, e.producto)
        from public.tarea_elementos e where e.tarea_id = t.id and e.tipo = 'punto'), '[]'::jsonb),
    'video', (select jsonb_build_object('enlace', v.enlace, 'aprendido', v.aprendido, 'no_pudo', v.no_pudo)
                from public.videos_tienda v where v.tarea_id = t.id),
    -- Tarea 28: lo que trae la bolsa («Recibe la bolsa» y «Coloca y apunta la reposición»).
    'bolsa', case when t.clave in ('recibe_bolsa', 'reposicion') then motor.bolsa_tienda_json(j.centro_id, j.fecha) end,
    -- Tarea 28: lo que se ha pedido en «Revisa las muestras».
    'muestras', case when t.contenido = 'muestras' then coalesce((
      select jsonb_agg(jsonb_build_object('producto', p.producto, 'formato', p.formato, 'cantidad', p.cantidad,
                                          'estado', p.estado) order by p.creada_en, p.id)
        from public.peticiones_tienda p where p.tarea_id = t.id), '[]'::jsonb) end)
  from public.tareas t join public.jornadas j on j.id = t.jornada_id
  where t.id = p_tarea;
$$;

create or replace function motor.marcar_punto_de(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
begin
  select el.* into e from public.tarea_elementos el
    join public.tareas tr on tr.id = el.tarea_id join public.jornadas j on j.id = tr.jornada_id
   where el.id = p_elemento and el.tipo = 'punto' and j.persona_id = p_persona;
  if e.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese punto no existe.');
  end if;
  if e.estado = 'hecho' then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  v_error := motor.tarea_tienda_marcable(p_persona, e.tarea_id, 'puntos', p_ahora);
  if v_error is not null then
    return v_error;
  end if;
  if motor.punto_especial(e) = 'cierre_caja' then
    return motor.error('FALTAN_DATOS', 'Apunta el cierre de caja: Z, número de ventas, efectivo y Glovo.',
                       jsonb_build_object('pide', 'cierre_caja'));
  elsif motor.punto_especial(e) = 'cierre_caja_corto' then
    -- Tarea 30b: el cierre corto de las franquicias.
    return motor.error('FALTAN_DATOS', 'Apunta el cierre de caja: Z y número de ventas.',
                       jsonb_build_object('pide', 'cierre_caja_corto'));
  elsif motor.punto_especial(e) = 'efectivo' then
    return motor.entregar_efectivo_de(p_persona, p_elemento, null, null, p_ahora);
  end if;
  perform motor.hacer_punto(p_persona, e.id, null, p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

create or replace function motor.cerrar_caja_de(p_persona uuid, p_elemento uuid, p_z numeric, p_ventas integer,
                                                p_efectivo numeric, p_glovo numeric, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  t public.tareas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_error jsonb;
  v_datos jsonb;
begin
  select el.* into e from public.tarea_elementos el
    join public.tareas tr on tr.id = el.tarea_id join public.jornadas jo on jo.id = tr.jornada_id
   where el.id = p_elemento and el.tipo = 'punto' and jo.persona_id = p_persona;
  if e.id is null or coalesce(motor.punto_especial(e), '') not in ('cierre_caja', 'cierre_caja_corto') then
    return motor.error('NO_ENCONTRADO', 'Ese punto no existe.');
  end if;
  v_error := motor.tarea_tienda_marcable(p_persona, e.tarea_id, 'puntos', p_ahora);
  if v_error is not null then
    return v_error;
  end if;
  -- Tarea 30b: el cierre corto (franquicias) solo lleva la Z y el nº de ventas.
  if motor.punto_especial(e) = 'cierre_caja_corto' then
    p_efectivo := null;
    p_glovo := null;
    if p_z is null or p_ventas is null then
      return motor.error('DATOS_NO_VALIDOS', 'Apunta la Z y el número de ventas.');
    end if;
  elsif p_z is null or p_ventas is null or p_efectivo is null or p_glovo is null then
    return motor.error('DATOS_NO_VALIDOS', 'Apunta la Z, el número de ventas, el efectivo y Glovo (0 si no hay).');
  end if;
  if least(p_z, p_efectivo, p_glovo) < 0 or greatest(p_z, p_efectivo, p_glovo) >= 1000000
     or p_z <> round(p_z, 2) or p_efectivo <> round(p_efectivo, 2) or p_glovo <> round(p_glovo, 2)
     or p_ventas < 0 or p_ventas >= 100000 then
    return motor.error('DATOS_NO_VALIDOS', 'Algún número no es válido: euros con dos decimales como máximo y ventas en número entero.');
  end if;
  select * into t from public.tareas where id = e.tarea_id;
  select * into j from public.jornadas where id = t.jornada_id;
  tt := motor.en_turno_tienda(j.id);
  v_datos := jsonb_build_object('z', p_z, 'ventas', p_ventas, 'efectivo', p_efectivo, 'glovo', p_glovo);
  insert into public.cierres_caja (centro_id, fecha, z, ventas, efectivo, glovo, tarea_id, persona_tienda_id, nombre, guardado_en)
  values (j.centro_id, j.fecha, p_z, p_ventas, p_efectivo, p_glovo, t.id, tt.persona_tienda_id, tt.nombre, p_ahora)
  on conflict (centro_id, fecha) do update
    set z = excluded.z, ventas = excluded.ventas, efectivo = excluded.efectivo, glovo = excluded.glovo,
        persona_tienda_id = excluded.persona_tienda_id, nombre = excluded.nombre, guardado_en = excluded.guardado_en;
  perform motor.registrar('cierre_caja_guardado', p_persona, j.id, t.id, v_datos || jsonb_build_object('a_las', p_ahora, 'por', tt.nombre));
  if e.estado = 'hecho' then
    update public.tarea_elementos set calculo = calculo || jsonb_build_object('datos', v_datos) where id = e.id;
  else
    perform motor.hacer_punto(p_persona, e.id, v_datos, p_ahora);
  end if;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Lo que falta, elegido de la lista (compartido por la reposición y los envíos)
-- ---------------------------------------------------------------------------
-- Lo que falta, elegido de la lista de lo que traía (bolsa o envío): cada producto (hasta su
-- cantidad), cada petición y cada pedido (1). Devuelve la lista o el error. Antes estaba dentro de
-- motor.apuntar_reposicion_de (Tarea 28); ahora la usan también los envíos.
create or replace function motor.faltan_de_lista(p_contenido jsonb, p_faltan jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_items jsonb;
  v_faltan jsonb := '[]';
  x jsonb;
  it jsonb;
  v_cant integer;
begin
  select coalesce(jsonb_agg(y), '[]') into v_items from (
    select jsonb_build_object('clave', c ->> 'clave', 'texto', trim((c ->> 'producto') || ' ' || (c ->> 'formato')),
                              'maximo', (c ->> 'cantidad')::int, 'producto', true) as y
      from jsonb_array_elements(p_contenido -> 'productos') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', c ->> 'texto', 'maximo', 1, 'producto', false)
      from jsonb_array_elements(p_contenido -> 'peticiones') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', 'Pedido de ' || (c ->> 'cliente'), 'maximo', 1, 'producto', false)
      from jsonb_array_elements(p_contenido -> 'pedidos') c) s;
  if p_faltan is not null and jsonb_typeof(p_faltan) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_faltan, '[]')) loop
    select i into it from jsonb_array_elements(v_items) i where i ->> 'clave' = x ->> 'clave';
    if it is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    if exists (select 1 from jsonb_array_elements(v_faltan) f where f ->> 'clave' = x ->> 'clave') then
      return motor.error('DATOS_NO_VALIDOS', 'Cada cosa, una sola vez.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_cant := case when x ? 'cantidad' and jsonb_typeof(x -> 'cantidad') = 'number' then (x ->> 'cantidad')::numeric::int
                   when x ? 'cantidad' then -1 else (it ->> 'maximo')::int end;
    if v_cant < 1 or v_cant > (it ->> 'maximo')::int or (x ? 'cantidad' and (x ->> 'cantidad')::numeric <> v_cant) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas faltan de ' || (it ->> 'texto') || ': de 1 a ' || (it ->> 'maximo') || '.',
                         jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_faltan := v_faltan || jsonb_build_object('clave', it ->> 'clave', 'texto', it ->> 'texto', 'cantidad', v_cant);
  end loop;
  return v_faltan;
end;
$$;

-- «1x V2 4g; Material: Rollos de TPV»: el texto de lo que falta para la incidencia.
create or replace function motor.faltan_texto(p_faltan jsonb)
returns text language sql immutable set search_path = '' as $$
  select string_agg(case when (f ->> 'cantidad')::int > 1 or (f ->> 'clave') like 'producto:%'
                         then (f ->> 'cantidad') || 'x ' else '' end || (f ->> 'texto'), '; ')
    from jsonb_array_elements(p_faltan) f
$$;

create or replace function motor.apuntar_reposicion_de(p_persona uuid, p_tarea uuid, p_faltan jsonb, p_nota text,
                                                       p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'reposicion', p_ahora);
  t public.tareas;
  j public.jornadas;
  b public.bolsas_tienda;
  tt public.turnos_tienda;
  v_contenido jsonb;
  v_faltan jsonb;
  v_nota text := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '');
  v_incidencia uuid;
begin
  if v_error is not null then
    return v_error;
  end if;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  select * into b from public.bolsas_tienda where centro_id = j.centro_id and fecha = j.fecha;
  tt := motor.en_turno_tienda(j.id);
  v_contenido := motor.bolsa_contenido(b.reparto_id, b.centro_id);
  -- Lo que podía faltar, elegido de la lista (Tarea 30b: la misma comprobación que en «Envíos»).
  v_faltan := motor.faltan_de_lista(v_contenido, p_faltan);
  if v_faltan ? 'error' then
    return v_faltan;
  end if;
  if v_nota is not null and length(v_nota) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
  end if;

  if jsonb_array_length(v_faltan) = 0 then
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Reposición metida, todo bien', null, 'tarea_terminada', p_ahora);
  else
    insert into public.incidencias (jornada_id, persona_id, tarea_id, descripcion, iniciada_en, id_cliente, opcion, quien,
                                    estado, creada_por)
    values (j.id, p_persona, t.id,
            'Falta en la bolsa del reparto del ' || to_char(j.fecha, 'DD/MM') || ': ' || motor.faltan_texto(v_faltan)
              || coalesce('. ' || v_nota, '') || coalesce(' (' || tt.nombre || ')', ''),
            p_ahora, md5('falta_reposicion:' || b.id)::uuid, 'falta_reposicion', 'administracion', 'abierta', p_persona)
    on conflict (id_cliente) do nothing
    returning id into v_incidencia;
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Falta algo', null, 'tarea_terminada', p_ahora);
    perform motor.registrar('falta_reposicion', p_persona, j.id, t.id,
                            jsonb_build_object('incidencia', v_incidencia, 'faltan', v_faltan, 'nota', v_nota, 'a_las', p_ahora));
  end if;
  update public.bolsas_tienda
     set reposicion = case when jsonb_array_length(v_faltan) = 0 then 'bien' else 'falta' end,
         reposicion_en = p_ahora, reposicion_por = tt.nombre, faltan = v_faltan, incidencia_id = v_incidencia
   where id = b.id;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. «Envíos»
-- ---------------------------------------------------------------------------
-- Cuándo ha salido el envío de esa jornada del almacén: al empezar (o terminar) «Salida a Nacex» o, el
-- viernes, «Lleva en el reparto lo que va a Nacex».
create or replace function motor.salida_envio_en(p_jornada uuid, p_ahora timestamptz)
returns timestamptz language sql stable set search_path = '' as $$
  select min(coalesce(t.iniciada_en, t.terminada_en))
    from public.tareas t
   where t.jornada_id = p_jornada and t.clave in ('nacex_salida', 'nacex_viernes') and t.estado in ('en_curso', 'hecha')
     and not t.retirada_por_condicion and coalesce(t.iniciada_en, t.terminada_en) <= p_ahora
$$;

-- El centro de destino del envío que recibe la tienda (null si no recibe por envío).
create or replace function motor.destino_envio(p_centro uuid)
returns uuid language sql stable set search_path = '' as $$
  select d.id from public.configuracion k join public.centros_trabajo d on d.codigo = k.valor #>> '{}'
   where k.clave = 'recibe_envio' and k.centro_id = p_centro
$$;

-- Apunta los envíos que han salido hacia la tienda (de la última semana, hasta ayer): uno por envío.
create or replace function motor.preparar_envios_tienda(p_persona uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  v_destino uuid;
  v_hoy date := motor.fecha_local(p_ahora);
  x record;
begin
  select * into pe from public.personas where id = p_persona;
  v_destino := motor.destino_envio(pe.centro_id);
  if v_destino is null then
    return;
  end if;
  for x in
    select r.id as reparto_id, j.fecha, j.id as jornada_id, motor.salida_envio_en(j.id, p_ahora) as salida
      from public.repartos r join public.jornadas j on j.id = r.jornada_id
     where r.tipo = 'envio' and r.estado = 'aceptado' and j.fecha >= v_hoy - 7 and j.fecha < v_hoy
       and exists (select 1 from public.tarea_elementos e
                    where e.tarea_id = (r.resultado -> 'tareas' ->> 'bolsas')::uuid and e.destino_id = v_destino
                      and e.tipo in ('caja_bolsa', 'peticion'))
       and not exists (select 1 from public.bolsas_tienda b where b.centro_id = pe.centro_id and b.fecha = j.fecha)
     order by j.fecha
  loop
    continue when x.salida is null;
    perform pg_advisory_xact_lock(hashtextextended('bolsa_tienda:' || pe.centro_id || ':' || x.fecha, 0));
    insert into public.bolsas_tienda (centro_id, fecha, reparto_id, tarea_id, salida_en)
    values (pe.centro_id, x.fecha, x.reparto_id, null, x.salida)
    on conflict (centro_id, fecha) do nothing;
    if found then
      perform motor.registrar('envio_en_camino', p_persona, null, null,
                              jsonb_build_object('reparto', x.reparto_id, 'fecha', x.fecha, 'salida', x.salida));
    end if;
  end loop;
end;
$$;

-- «Envíos» de la tienda: los que quedan por confirmar (los más antiguos primero) y los confirmados hoy.
create or replace function motor.envios_tienda_json(p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', b.id, 'reparto_id', b.reparto_id, 'fecha', b.fecha, 'salida', motor.hora_texto(b.salida_en),
             'destino', d.nombre,
             'confirmado', case when b.reposicion is not null then
               jsonb_build_object('resultado', b.reposicion, 'a_las', motor.hora_texto(b.reposicion_en), 'por', b.reposicion_por,
                                  'faltan', coalesce(b.faltan, '[]'::jsonb), 'incidencia_id', b.incidencia_id) end)
           || motor.bolsa_contenido(b.reparto_id, d.id)
           order by (b.reposicion is not null), b.fecha), '[]'::jsonb)
    from public.bolsas_tienda b
    join public.repartos r on r.id = b.reparto_id and r.tipo = 'envio'
    join public.centros_trabajo d on d.id = motor.destino_envio(b.centro_id)
   where b.centro_id = p_centro
     and (b.reposicion is null or motor.fecha_local(b.reposicion_en) = motor.fecha_local(p_ahora))
$$;

-- «Todo bien» (sin faltan) o «Falta algo» (eligiendo qué y cuánto), que abre una incidencia para
-- Administración, como la reposición.
create or replace function motor.confirmar_envio_de(p_persona uuid, p_envio uuid, p_faltan jsonb, p_nota text,
                                                    p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  b public.bolsas_tienda;
  v_jornada uuid;
  tt public.turnos_tienda;
  v_faltan jsonb;
  v_nota text := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '');
  v_incidencia uuid;
begin
  select * into pe from public.personas where id = p_persona;
  select bt.* into b from public.bolsas_tienda bt join public.repartos r on r.id = bt.reparto_id and r.tipo = 'envio'
   where bt.id = p_envio and bt.centro_id = pe.centro_id for update of bt;
  if b.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese envío no existe.');
  end if;
  if b.reposicion is not null then
    return motor.error('ESTADO_NO_VALIDO', 'Ese envío ya está confirmado.', jsonb_build_object('resultado', b.reposicion));
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  v_faltan := motor.faltan_de_lista(motor.bolsa_contenido(b.reparto_id, motor.destino_envio(b.centro_id)), p_faltan);
  if v_faltan ? 'error' then
    return v_faltan;
  end if;
  if v_nota is not null and length(v_nota) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
  end if;

  if jsonb_array_length(v_faltan) > 0 then
    insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, quien, estado, creada_por)
    values (v_jornada, p_persona,
            'Falta en el envío del ' || to_char(b.fecha, 'DD/MM') || ': ' || motor.faltan_texto(v_faltan)
              || coalesce('. ' || v_nota, '') || ' (' || tt.nombre || ')',
            p_ahora, md5('falta_envio:' || b.id)::uuid, 'falta_envio', 'administracion', 'abierta', p_persona)
    on conflict (id_cliente) do nothing
    returning id into v_incidencia;
  end if;
  update public.bolsas_tienda
     set reposicion = case when jsonb_array_length(v_faltan) = 0 then 'bien' else 'falta' end,
         reposicion_en = p_ahora, reposicion_por = tt.nombre, faltan = v_faltan, incidencia_id = v_incidencia
   where id = b.id;
  perform motor.registrar('envio_confirmado', p_persona, v_jornada, null,
                          jsonb_build_object('envio', b.id, 'reparto', b.reparto_id, 'faltan', v_faltan, 'nota', v_nota,
                                             'incidencia', v_incidencia, 'por', tt.nombre, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. tienda_hoy(): envios y envios_sin_confirmar (solo se añaden campos)
-- ---------------------------------------------------------------------------
create or replace function motor.tienda_hoy_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_dia integer := extract(isodow from v_hoy);
  pe public.personas;
  c public.centros_trabajo;
  v_jornada uuid;
  v_turno text;
  tt public.turnos_tienda;
begin
  select * into pe from public.personas where id = p_persona;
  select * into c from public.centros_trabajo where id = pe.centro_id;
  v_jornada := motor.generar_jornada(p_persona, v_hoy);
  -- Tarea 28: si ha salido el reparto y trae bolsa para esta tienda, «Recibe la bolsa».
  perform motor.preparar_bolsa_tienda(p_persona, v_jornada, p_ahora);
  -- Tarea 30b: las tiendas que reciben por envío, los envíos que les han salido.
  perform motor.preparar_envios_tienda(p_persona, p_ahora);
  v_turno := motor.turno_tienda_ahora(p_persona, p_ahora);
  tt := motor.en_turno_tienda(v_jornada);
  return jsonb_build_object(
    'tienda', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre),
    'fecha', v_hoy,
    'ahora', motor.hora_texto(p_ahora),
    'abierta_hoy', v_jornada is not null,
    'cerrado', motor.dia_cerrado(c.id, v_hoy),
    'horario', coalesce((select jsonb_agg(jsonb_build_object('turno', h.turno, 'inicio', to_char(h.hora_inicio, 'HH24:MI'),
                                                             'fin', to_char(h.hora_fin, 'HH24:MI')) order by h.hora_inicio)
                           from public.horarios h where h.persona_id = p_persona and h.dia_semana = v_dia), '[]'::jsonb),
    'turno', v_turno,
    'en_turno', case when tt.id is not null then
      jsonb_build_object('persona_id', tt.persona_tienda_id, 'nombre', tt.nombre, 'turno', tt.turno,
                         'desde', motor.hora_texto(tt.empezado_en)) end,
    'personas', coalesce((
      select jsonb_agg(x.o order by x.sugerida desc, x.nombre)
        from (select pt.nombre,
                     (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                     and (pt.turno is null or v_turno is null or pt.turno = v_turno) as sugerida,
                     jsonb_build_object('id', pt.id, 'nombre', pt.nombre, 'cuando', pt.cuando, 'turno', pt.turno,
                       'sugerida', (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                                   and (pt.turno is null or v_turno is null or pt.turno = v_turno)) as o
                from public.personas_tienda pt where pt.centro_id = c.id and pt.activo) x), '[]'::jsonb),
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'fecha', motor.fecha_local(i.iniciada_en),
                                          -- Tarea 29: de quién viene («Almacén» o «Administración»).
                                          'de', case when a.rol = 'operario' then 'Almacén' else 'Administración' end)
                       order by i.iniciada_en)
        from public.incidencias i left join public.personas a on a.id = i.creada_por
       where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'tareas', coalesce((
      select jsonb_agg(motor.tarea_tienda_json(t.id, p_ahora) order by t.disponible_desde, t.orden, t.creada_en)
        from public.tareas t where t.jornada_id = v_jornada and not t.retirada_por_condicion), '[]'::jsonb),
    -- Tarea 28: por dónde va el reparto, las peticiones (muestras y material) y si puede pedir material.
    'reparto', motor.seguimiento_reparto_json(c.id, v_hoy, p_ahora),
    'peticiones', motor.peticiones_tienda_json(c.id, p_ahora),
    'pedir_material', coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                                 where k.clave = 'pedir_material' and k.centro_id = c.id), false),
    -- Tarea 30: las incidencias de la tienda (abiertas y cerradas hoy) y qué opciones tiene.
    'incidencias', motor.incidencias_tienda_json(p_persona, p_ahora),
    'opciones_incidencia', motor.opciones_incidencia_json(c.id),
    -- Tarea 30b: «Envíos» (tiendas que reciben por envío) y cuántos quedan sin confirmar.
    'envios', motor.envios_tienda_json(c.id, p_ahora),
    'envios_sin_confirmar', (select count(*)::int from public.bolsas_tienda b join public.repartos r on r.id = b.reparto_id
                              where b.centro_id = c.id and r.tipo = 'envio' and b.reposicion is null));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Para la pantalla
-- ---------------------------------------------------------------------------
create or replace function motor.api_confirmar_envio(p_envio_id uuid, p_faltan jsonb, p_nota text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.confirmar_envio_de(auth.uid(), p_envio_id, p_faltan, p_nota, now());
end; $$;

create or replace function public.confirmar_envio(envio_id uuid, faltan jsonb default null, nota text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_confirmar_envio(envio_id, faltan, nota) $$;

-- cerrar_caja: el efectivo y Glovo pasan a ser opcionales (el cierre corto no los lleva).
create or replace function public.cerrar_caja(elemento_id uuid, z numeric, ventas integer, efectivo numeric default null,
                                              glovo numeric default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_cerrar_caja(elemento_id, z, ventas, efectivo, glovo) $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_confirmar_envio(uuid, jsonb, text) to authenticated;
revoke execute on function public.confirmar_envio(uuid, jsonb, text) from public, anon;
grant execute on function public.confirmar_envio(uuid, jsonb, text) to authenticated;
