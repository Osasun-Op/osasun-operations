-- Tarea 30 · Incidencias de tienda (ESTADO_DEL_SISTEMA.md E2-8 v1.50; AGENTE_COORDINADOR.md, bloque 1,
-- puntos 18 y 24). Solo en pruebas: producción espera con las de tiendas (AGENTE_BASE_DE_DATOS.md §4).
-- Reutiliza lo que ya existe: la tabla incidencias con quien = administracion (como falta_reposicion,
-- Tarea 28), incidencias_tiendas() y cerrar_incidencia_tienda() para Administración, pedir_material()
-- para el material de tienda, productos_tienda() para elegir el producto y la activación por tienda
-- (configuración, como pedir_material). Lo del almacén no cambia.
--   1. crear_incidencia_tienda(id_cliente, opcion, texto?, producto?): «Me quedo sin producto»
--      (sin_producto, con el producto y nota opcional), «Descuadre de stock o de caja» (descuadre),
--      «Comentario de cliente» (comentario_cliente) y «Otros» (otros), con texto. Sin foto ni urgencia.
--      Queda abierta para Administración, con el nombre de quien está en el turno.
--   2. Qué opciones tiene cada tienda: configuración incidencias_tienda por tienda. Las propias,
--      las cuatro; Donosti y Rentería (franquicias), solo «Otros» (texto libre).
--   3. tienda_hoy(): `incidencias` (las abiertas y las cerradas hoy, con su estado) y
--      `opciones_incidencia` (las de la tienda, con «Material de tienda» si pide material).
--
-- Deshacer: borrar public.crear_incidencia_tienda, motor.api_crear_incidencia_tienda,
-- motor.crear_incidencia_tienda_de, motor.opciones_incidencia_json y motor.incidencias_tienda_json;
-- borrar la clave incidencias_tienda de configuracion; volver a crear motor.tienda_hoy_de como está
-- en 20261103152517 y el check incidencias_opcion_check como está en 20261103091220 (antes, borrar o
-- cambiar las incidencias con las opciones nuevas).

-- ---------------------------------------------------------------------------
-- 1. Opciones nuevas (solo se añaden valores)
-- ---------------------------------------------------------------------------
alter table public.incidencias drop constraint incidencias_opcion_check;
alter table public.incidencias add constraint incidencias_opcion_check
  check (opcion in ('comprar', 'varios', 'aviso', 'llega_mercancia', 'pedido_cliente', 'pedir_comprar',
                    'recogida_nacex', 'corregir', 'falta_reposicion',
                    'sin_producto', 'descuadre', 'comentario_cliente', 'otros'));

-- ---------------------------------------------------------------------------
-- 2. Qué opciones tiene cada tienda (configuración, no código)
-- ---------------------------------------------------------------------------
-- Las propias, las cuatro; las franquicias (Donosti y Rentería), solo texto libre («Otros»).
insert into public.configuracion (clave, centro_id, valor)
select 'incidencias_tienda', c.id,
       case when c.codigo in ('DONOSTI', 'RENTERIA') then '["otros"]'::jsonb
            else '["sin_producto", "descuadre", "comentario_cliente", "otros"]'::jsonb end
  from public.centros_trabajo c where c.tipo = 'tienda'
on conflict (clave, centro_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Ayudas para tienda_hoy()
-- ---------------------------------------------------------------------------
-- Las opciones de la tienda, en el orden de la pantalla. «Material de tienda» es pedir_material.
create or replace function motor.opciones_incidencia_json(p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  with k as (select valor from public.configuracion where clave = 'incidencias_tienda' and centro_id = p_centro),
  o (opcion, texto, pide, llama, orden) as (values
    ('material', 'Material de tienda', 'texto', 'pedir_material', 1),
    ('sin_producto', 'Me quedo sin producto', 'producto', 'crear_incidencia_tienda', 2),
    ('descuadre', 'Descuadre de stock o de caja', 'texto', 'crear_incidencia_tienda', 3),
    ('comentario_cliente', 'Comentario de cliente', 'texto', 'crear_incidencia_tienda', 4),
    ('otros', 'Otros', 'texto', 'crear_incidencia_tienda', 5))
  select coalesce(jsonb_agg(jsonb_build_object('opcion', o.opcion, 'texto', o.texto, 'pide', o.pide, 'llama', o.llama)
                            order by o.orden), '[]'::jsonb)
    from o
   where case when o.opcion = 'material'
              then coalesce((select (c.valor #>> '{}')::boolean from public.configuracion c
                              where c.clave = 'pedir_material' and c.centro_id = p_centro), false)
              else coalesce((select k.valor ? o.opcion from k), false) end
$$;

-- Las incidencias de la tienda: las abiertas y las cerradas hoy (los avisos van aparte).
create or replace function motor.incidencias_tienda_json(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'opcion', i.opcion, 'texto', i.descripcion,
           'fecha', motor.fecha_local(i.iniciada_en), 'a_las', motor.hora_texto(i.iniciada_en),
           'estado', case when i.estado = 'cerrada' then 'cerrada' else 'abierta' end,
           'estado_texto', case when i.estado = 'cerrada'
                                then 'Resuelta por Administración' || coalesce(': ' || i.nota_cierre, '')
                                else 'Abierta' end)
           order by (i.estado = 'cerrada'), i.iniciada_en desc), '[]'::jsonb)
    from public.incidencias i
   where i.persona_id = p_persona and i.opcion is distinct from 'aviso' and i.iniciada_en <= p_ahora
     and (i.estado <> 'cerrada' or motor.fecha_local(i.terminada_en) = motor.fecha_local(p_ahora))
$$;

-- ---------------------------------------------------------------------------
-- 4. Crear una incidencia de tienda
-- ---------------------------------------------------------------------------
create or replace function motor.crear_incidencia_tienda_de(p_persona uuid, p_id_cliente uuid, p_opcion text, p_texto text,
                                                            p_producto text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  v_jornada uuid;
  tt public.turnos_tienda;
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
  v_producto text;
  v_descripcion text;
begin
  select * into pe from public.personas where id = p_persona;
  if p_id_cliente is null or p_opcion is null
     or p_opcion not in ('sin_producto', 'descuadre', 'comentario_cliente', 'otros') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige una opción de la lista.');
  end if;
  if not coalesce((select k.valor ? p_opcion from public.configuracion k
                    where k.clave = 'incidencias_tienda' and k.centro_id = pe.centro_id), false) then
    return motor.error('NO_AUTORIZADO', 'Esta tienda no tiene esa opción.');
  end if;
  -- Repetir con el mismo id_cliente no la duplica.
  if exists (select 1 from public.incidencias where id_cliente = p_id_cliente) then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  if p_opcion = 'sin_producto' then
    select x ->> 'producto' into v_producto
      from jsonb_array_elements(motor.productos_tienda_de() -> 'productos') x
     where x ->> 'clave' = btrim(coalesce(p_producto, ''));
    if v_producto is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige el producto de la lista.');
    end if;
    if v_texto is not null and length(v_texto) > 200 then
      return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
    end if;
  elsif v_texto is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe qué ha pasado.');
  elsif length(v_texto) > 300 then
    return motor.error('DATOS_NO_VALIDOS', 'En una o dos líneas (300 letras como máximo).');
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;

  v_descripcion := case p_opcion
                     when 'sin_producto' then 'Sin producto: ' || v_producto || coalesce('. ' || v_texto, '')
                     when 'descuadre' then 'Descuadre de stock o de caja: ' || v_texto
                     when 'comentario_cliente' then 'Comentario de cliente: ' || v_texto
                     else v_texto end
                   || ' (' || tt.nombre || ')';
  insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, quien, estado, creada_por)
  values (v_jornada, p_persona, v_descripcion, p_ahora, p_id_cliente, p_opcion, 'administracion', 'abierta', p_persona)
  on conflict (id_cliente) do nothing;
  perform motor.registrar('incidencia_tienda', p_persona, v_jornada, null,
                          jsonb_build_object('opcion', p_opcion, 'producto', v_producto, 'por', tt.nombre, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. tienda_hoy(): las incidencias de la tienda y sus opciones (solo se añaden campos)
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
    'opciones_incidencia', motor.opciones_incidencia_json(c.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Para la pantalla
-- ---------------------------------------------------------------------------
create or replace function motor.api_crear_incidencia_tienda(p_id_cliente uuid, p_opcion text, p_texto text, p_producto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_incidencia_tienda_de(auth.uid(), p_id_cliente, p_opcion, p_texto, p_producto, now());
end; $$;

create or replace function public.crear_incidencia_tienda(id_cliente uuid, opcion text, texto text default null,
                                                          producto text default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_crear_incidencia_tienda(id_cliente, opcion, texto, producto) $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_crear_incidencia_tienda(uuid, text, text, text) to authenticated;
revoke execute on function public.crear_incidencia_tienda(uuid, text, text, text) from public, anon;
grant execute on function public.crear_incidencia_tienda(uuid, text, text, text) to authenticated;
