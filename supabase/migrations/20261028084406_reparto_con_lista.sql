-- Tarea 10 · El reparto se prepara con una lista (ESTADO_DEL_SISTEMA.md v1.21, §5 R1).
-- Las funciones del servidor `catalogo` y `guardar_reparto` hacen el trabajo
-- (lectura de la hoja, R1); aquí, lo que necesitan de la base de datos:
-- 1. Reintentos de guardar_reparto: cada reparto guarda el `id_cliente` de la
--    petición que lo creó; repetirla devuelve lo guardado.
-- 2. servidor_preparar dice qué tiendas están activas.
-- 3. reparto_de_hoy_detalle(tipo): el reparto (o envío) de hoy, línea a línea,
--    para abrirlo y modificarlo, con su texto para WhatsApp y quién sale.
-- 4. «Prepara el reparto» sin reparto: el mensaje ya no habla de pegar.

alter table public.repartos add column id_cliente uuid;
create unique index repartos_id_cliente_key on public.repartos (id_cliente);
comment on column public.repartos.id_cliente is 'Petición de guardar_reparto que lo creó (reintentos).';
comment on column public.repartos.texto_original is 'Texto pegado (pegar_reparto) o texto para WhatsApp generado con la lista (guardar_reparto).';

create or replace function public.servidor_reparto_por_id_cliente(p_id_cliente uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select r.resultado || jsonb_build_object('texto_whatsapp', r.texto_original)
    from public.repartos r where r.id_cliente = p_id_cliente;
$$;

create or replace function public.servidor_reparto_anotar_id_cliente(p_reparto uuid, p_id_cliente uuid)
returns void language sql security definer set search_path = '' as $$
  update public.repartos set id_cliente = p_id_cliente
   where id = p_reparto and id_cliente is null
     and not exists (select 1 from public.repartos o where o.id_cliente = p_id_cliente);
$$;

revoke execute on function public.servidor_reparto_por_id_cliente(uuid), public.servidor_reparto_anotar_id_cliente(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.servidor_reparto_por_id_cliente(uuid), public.servidor_reparto_anotar_id_cliente(uuid, uuid)
  to service_role;

-- ---------------------------------------------------------------------------
-- servidor_preparar: con `activo` en cada destino
-- ---------------------------------------------------------------------------
create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_operario uuid;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada := motor.generar_jornada(v_operario, v_fecha);
  end if;
  if v_rol = 'operario' and v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;

  select h.turno into v_turno from public.horarios h
   where h.persona_id = v_operario and h.dia_semana = extract(isodow from v_fecha)
     and motor.en_local(v_fecha, h.hora_inicio) <= p_ahora
   order by h.hora_inicio desc limit 1;
  v_turno := coalesce(v_turno, 'manana');

  select t.id into v_stock from public.tareas t
   where t.jornada_id = v_jornada and t.clave = 'cola_stock'
     and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.lote = v_turno);

  return jsonb_build_object(
    'persona_id', p_persona, 'rol', v_rol, 'jornada_id', v_jornada,
    'fecha', v_fecha, 'dia', extract(day from v_fecha)::int, 'mes', extract(month from v_fecha)::int,
    'turno', v_turno,
    'destinos', (select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre,
                                                     'tipo', c.tipo, 'activo', c.activo, 'alias', to_jsonb(c.alias))
                                  order by c.codigo)
                 from public.centros_trabajo c where c.tipo <> 'almacen'),
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas',
                                                         'stock_objetivo_pct', 'stock_excluidos')),
    'repartos', jsonb_build_object(
      'reparto', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                  from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'),
      'envio', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'envio' and r.estado = 'aceptado')),
    -- Para el envío: cajas pedidas en el reparto aceptado hoy y si ya se hizo el recuento de la mañana.
    'reparto_hoy', coalesce((select jsonb_agg(jsonb_build_object('producto', x ->> 'producto',
                                                                 'formato', coalesce(x ->> 'formato', ''),
                                                                 'pedido', (x ->> 'pedido')::int))
                             from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                             where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'), '[]'::jsonb),
    'recuento_manana_hecho', exists (select 1 from public.tareas t
                                     where t.jornada_id = v_jornada and t.clave = 'recuento_manana' and t.estado = 'hecha'),
    'stock', case when v_stock is null or v_rol <> 'operario' then null else motor.tarea_json(v_stock) end);
end;
$$;

-- ---------------------------------------------------------------------------
-- reparto_de_hoy_detalle(tipo): para abrir el reparto de hoy y modificarlo
-- ---------------------------------------------------------------------------
create or replace function motor.reparto_de_hoy_detalle_de(p_persona uuid, p_tipo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_jornada uuid;
  v_sale text;
  r public.repartos;
begin
  if p_tipo is null or p_tipo not in ('reparto', 'envio') then
    return motor.error('DATOS_NO_VALIDOS', 'El tipo es «reparto» o «envio».');
  end if;
  v_jornada := motor.generar_jornada(case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end,
                                     motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no hay jornada en el almacén.');
  end if;
  select * into r from public.repartos where jornada_id = v_jornada and tipo = p_tipo and estado = 'aceptado';
  if r.id is null then
    return jsonb_build_object('reparto', null);
  end if;
  -- Quién sale hoy (puede haber cambiado sin tocar el reparto): manda la jornada.
  v_sale := case when p_tipo = 'reparto' then (select sale from public.jornadas where id = v_jornada) end;
  return jsonb_build_object('reparto', jsonb_build_object(
    'reparto_id', r.id, 'tipo', r.tipo, 'sale', v_sale,
    'aceptado_en', r.pegado_en, 'pegado_por', r.pegado_por,
    'pegado_por_nombre', (select nombre from public.personas where id = r.pegado_por),
    'texto_whatsapp', case when v_sale is null then r.texto_original
                           else regexp_replace(r.texto_original, '^(REPARTO [^\n]*\n)SALE: [^\n]*',
                                               '\1SALE: ' || case v_sale when 'operario' then 'ALMACÉN' else 'YO' end) end,
    'lineas', coalesce((
      select jsonb_agg(jsonb_build_object('destino_id', x.destino_id, 'destino', c.nombre, 'producto', x.producto,
                                          'formato', x.formato, 'cantidad', x.cantidad) order by x.primera)
        from (select l.destino_id, l.producto, coalesce(l.formato, '') as formato, sum(l.cantidad)::int as cantidad,
                     min(l.num_linea) as primera
                from public.reparto_lineas l
               where l.reparto_id = r.id and l.clase = 'producto' and l.error is null
               group by 1, 2, 3) x
        join public.centros_trabajo c on c.id = x.destino_id), '[]'::jsonb)));
end;
$$;

create or replace function motor.api_reparto_de_hoy_detalle(p_tipo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.reparto_de_hoy_detalle_de(auth.uid(), p_tipo, now());
end; $$;

create or replace function public.reparto_de_hoy_detalle(tipo text default 'reparto')
returns jsonb language sql set search_path = '' as $$ select motor.api_reparto_de_hoy_detalle(tipo) $$;

-- ---------------------------------------------------------------------------
-- «Prepara el reparto» sin reparto aceptado: solo con motivo.
-- ---------------------------------------------------------------------------
create or replace function motor.terminar_tarea_de(p_persona uuid, p_tarea uuid, p_resultado text, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  t public.tareas;
  j public.jornadas;
  v_pendientes integer;
begin
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  if t.id is null or j.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado = 'hecha' then
    return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if t.estado <> 'en_curso' then
    return motor.error('ESTADO_NO_VALIDO', 'Solo se puede terminar una tarea en curso.', jsonb_build_object('estado', t.estado));
  end if;
  select count(*) into v_pendientes from public.tarea_elementos where tarea_id = t.id and estado <> 'hecho';
  if v_pendientes > 0 and nullif(btrim(p_motivo), '') is null then
    return motor.error('ELEMENTOS_PENDIENTES', 'Quedan ' || v_pendientes || ' sin hacer. Escribe el motivo para terminarla así.',
                       jsonb_build_object('pendientes', v_pendientes));
  end if;
  if t.clave = 'pegar_reparto' and nullif(btrim(p_motivo), '') is null
     and not exists (select 1 from public.repartos r where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado') then
    return motor.error('MOTIVO_OBLIGATORIO', 'Todavía no hay reparto. Prepáralo, o escribe el motivo para terminarla así.');
  end if;

  update public.tareas
     set estado = 'hecha', terminada_en = p_ahora,
         resultado = nullif(btrim(p_resultado), ''),
         motivo_no_hecha = coalesce(nullif(btrim(p_motivo), ''), motivo_no_hecha)
   where id = t.id and estado = 'en_curso';
  update public.tarea_elementos set estado = 'pendiente' where tarea_id = t.id and estado = 'en_curso';
  perform motor.registrar('tarea_terminada', p_persona, j.id, t.id,
                          jsonb_build_object('a_las', p_ahora, 'resultado', p_resultado,
                                             'motivo', p_motivo, 'pendientes', v_pendientes));
  return jsonb_build_object('tarea', motor.tarea_json(t.id), 'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_reparto_de_hoy_detalle(text) to authenticated;
revoke execute on function public.reparto_de_hoy_detalle(text) from public, anon;
grant execute on function public.reparto_de_hoy_detalle(text) to authenticated;
