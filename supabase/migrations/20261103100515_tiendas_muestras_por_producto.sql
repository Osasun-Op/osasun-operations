-- Tarea 28 · Ajustes del propietario (03/11/2026, PR #27). Solo en pruebas: producción espera
-- (AGENTE_BASE_DE_DATOS.md §4).
--   1. Las muestras se piden por producto, sin formato (son ~1 g, no un formato de venta): la lista
--      de productos_tienda() trae cada producto una vez; al tocarlo cuenta 1 y con − y + se cambia
--      la cantidad. En la casilla del reparto: «Muestra: V2» o «Muestra: V2 x2».
--   2. Administración descarta una petición de tienda con el motivo opcional (sin motivo, la tienda
--      ve «No va: lo ha quitado Administración»).
-- Deshacer: volver a crear motor.productos_tienda_de, motor.revisar_muestras_de y
-- motor.descartar_peticion_tienda_de como en 20261103091220_tiendas_segunda_parte.sql.

-- La lista para las muestras: cada producto de la última lectura correcta de la hoja, una vez, en
-- el orden de la hoja (los que tienen formatos o cajas en las tiendas).
create or replace function motor.productos_tienda_de()
returns jsonb language sql stable set search_path = '' as $$
  with l as (select datos, leido_en from public.lecturas_sheets
              where correcto and jsonb_typeof(datos -> 'productos') = 'array' order by leido_en desc limit 1),
  x as (
    select distinct on (upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')))
           btrim(p ->> 'nombre') as producto,
           coalesce(l.datos -> 'categorias' ->> upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')), 'Otros') as categoria,
           (p ->> 'orden')::int as orden
      from l, jsonb_array_elements(l.datos -> 'productos') p
     where jsonb_array_length(coalesce(p -> 'formatos', '[]')) > 0 or coalesce((p ->> 'conTiendas')::boolean, false)
     order by upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')), (p ->> 'orden')::int)
  select jsonb_build_object(
    'productos', coalesce((select jsonb_agg(jsonb_build_object('clave', x.producto, 'producto', x.producto,
                                                               'categoria', x.categoria) order by x.orden, x.producto)
                             from x), '[]'::jsonb),
    'leidos_en', (select leido_en from l))
$$;

-- «Revisa las muestras»: los productos que hay que traer nuevos ([{ producto, cantidad? }],
-- cantidad 1 si no se dice, de 1 a 99), o nada.
create or replace function motor.revisar_muestras_de(p_persona uuid, p_tarea uuid, p_muestras jsonb, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'muestras', p_ahora);
  t public.tareas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_lista jsonb := motor.productos_tienda_de() -> 'productos';
  v_prefijo text;
  v_elegidas jsonb := '[]';
  x jsonb;
  p jsonb;
  v_cantidad integer;
  v_detalle text;
begin
  if v_error is not null then
    return v_error;
  end if;
  if p_muestras is not null and jsonb_typeof(p_muestras) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista qué muestras hay que traer.');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_muestras, '[]')) loop
    select l into p from jsonb_array_elements(v_lista) l
     where upper(regexp_replace(l ->> 'producto', '\s+', '', 'g'))
           = upper(regexp_replace(coalesce(x ->> 'producto', ''), '\s+', '', 'g'));
    if p is null then
      return motor.error('DATOS_NO_VALIDOS', 'Ese producto no está en la lista.', jsonb_build_object('producto', x ->> 'producto'));
    end if;
    if x ? 'cantidad' and (jsonb_typeof(x -> 'cantidad') is distinct from 'number'
                           or (x ->> 'cantidad')::numeric not between 1 and 99
                           or (x ->> 'cantidad')::numeric <> trunc((x ->> 'cantidad')::numeric)) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas muestras de ' || (p ->> 'producto') || ': de 1 a 99.');
    end if;
    if exists (select 1 from jsonb_array_elements(v_elegidas) e where e ->> 'clave' = p ->> 'clave') then
      return motor.error('DATOS_NO_VALIDOS', 'Cada producto, una sola vez.');
    end if;
    v_elegidas := v_elegidas || (p || jsonb_build_object('cantidad', coalesce((x ->> 'cantidad')::int, 1)));
  end loop;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  tt := motor.en_turno_tienda(j.id);
  select d.prefijo into v_prefijo from motor.destino_peticion(j.centro_id) d;
  for p in select * from jsonb_array_elements(v_elegidas) loop
    v_cantidad := (p ->> 'cantidad')::int;
    v_detalle := (p ->> 'producto') || case when v_cantidad > 1 then ' x' || v_cantidad else '' end;
    insert into public.peticiones_tienda (centro_id, tipo, detalle, texto, producto, formato, cantidad, tarea_id,
                                          persona_tienda_id, nombre, creada_en)
    values (j.centro_id, 'muestra', v_detalle, left(coalesce(v_prefijo, '') || 'Muestra: ' || v_detalle, 120),
            p ->> 'producto', '', v_cantidad, t.id, tt.persona_tienda_id, tt.nombre, p_ahora);
  end loop;
  perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha',
            case when jsonb_array_length(v_elegidas) = 0 then 'Muestras bien: nada que traer'
                 else 'Muestras para traer: ' || jsonb_array_length(v_elegidas) end,
            null, 'tarea_terminada', p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- Descartar una petición pendiente de una tienda («No va»): el motivo es opcional.
create or replace function motor.descartar_peticion_tienda_de(p_admin uuid, p_id uuid, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  p public.peticiones_tienda;
  v_motivo text := nullif(btrim(regexp_replace(coalesce(p_motivo, ''), '\s+', ' ', 'g')), '');
begin
  select * into p from public.peticiones_tienda where id = p_id for update;
  if p.id is null then
    return motor.error('NO_ENCONTRADO', 'Esa petición no existe.');
  end if;
  if p.estado <> 'pendiente' then
    return motor.error('ESTADO_NO_VALIDO', 'Esa petición ya no está pendiente.', jsonb_build_object('estado', p.estado));
  end if;
  if v_motivo is not null and length(v_motivo) > 120 then
    return motor.error('DATOS_NO_VALIDOS', 'El motivo, en una línea (120 letras como máximo): la tienda lo verá.');
  end if;
  update public.peticiones_tienda
     set estado = 'descartada', motivo = v_motivo, descartada_por = p_admin, atendida_en = p_ahora
   where id = p.id;
  perform motor.registrar('peticion_tienda_descartada', p_admin, null, null,
                          jsonb_build_object('peticion', p.id, 'motivo', v_motivo));
  return jsonb_build_object('peticion', (select motor.peticion_tienda_json(x, p_ahora) from public.peticiones_tienda x where x.id = p.id));
end;
$$;

revoke execute on function motor.productos_tienda_de(), motor.revisar_muestras_de(uuid, uuid, jsonb, timestamptz),
  motor.descartar_peticion_tienda_de(uuid, uuid, text, timestamptz) from public;
