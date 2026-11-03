-- Tarea 29 · Respuestas del propietario en el PR #28 (03/11/2026). Solo en pruebas: espera con las de
-- tiendas (AGENTE_BASE_DE_DATOS.md §4).
--   1. No ceden en un conflicto todas las tareas de lo que sale hoy del almacén, al reparto o a Nacex:
--      producción del reparto, bolsas, salida, pedidos de cliente para la tienda, preparación del
--      envío, pedidos de cliente por Nacex, «Lleva en el reparto lo que va a Nacex» y la salida a Nacex.
--   2. La tienda ve en su bolsa («Recibe la bolsa», la reposición) lo que el operario ha marcado como
--      metido en ella; lo que no se ha marcado no aparece.
--   3. Las bolsas, siempre después de la producción del reparto, sin nada en medio: con la producción
--      hecha y las bolsas sin terminar, solo salen las bolsas (y los pedidos de cliente para la tienda,
--      que van en ellas); lo urgente y lo que tiene hora esperan; solo un problema que abre él lo
--      para. La salida del reparto no sale hasta tener las bolsas. Si llega la hora de salida sin las
--      bolsas, tarea_activa trae `aviso_salida` para retrasarla 15 o 30 min (retrasar_salida).
--   4. El operario ve los avisos a las tiendas que ha mandado y los cancela (solo los suyos).
--
-- Deshacer: volver a crear motor.es_del_reparto (20261103152517), motor.bolsa_contenido
-- (20261103091220), motor.elegir_tarea (20261102153923), motor.tarea_activa_de (20261029140000),
-- motor.api_avisos_tiendas (20261102190536) y motor.api_cancelar_aviso_almacen (20261030121241) como
-- estaban; borrar motor.cancelar_aviso_tienda_de.

-- ---------------------------------------------------------------------------
-- 1. Lo que sale hoy, al reparto o a Nacex, no cede en un conflicto
-- ---------------------------------------------------------------------------
create or replace function motor.es_del_reparto(p_clave text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(split_part(p_clave, ':', 1) in ('produccion_reparto', 'bolsas', 'salida_reparto', 'pedido_tienda',
                                                  'preparar_envio', 'preparar_envio_viernes', 'pedido_cliente',
                                                  'pedido_nacex', 'pedido_nacex_viernes', 'nacex_viernes', 'nacex_salida'),
                  false)
$$;

-- ---------------------------------------------------------------------------
-- 2. Lo que trae la bolsa: lo marcado como metido en ella (tarea de bolsas del reparto)
-- ---------------------------------------------------------------------------
create or replace function motor.bolsa_contenido(p_reparto uuid, p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  with b as (select (r.resultado -> 'tareas' ->> 'bolsas')::uuid as tarea from public.repartos r where r.id = p_reparto),
  e as (select el.tipo, el.lote, el.producto, el.formato, el.orden_sugerido,
               coalesce(nullif(el.cantidad_hecha, 0), case when el.estado = 'hecho' then el.cantidad end, 0) as metidas
          from public.tarea_elementos el, b
         where el.tarea_id = b.tarea and el.destino_id = p_centro and el.tipo in ('caja_bolsa', 'peticion'))
  select jsonb_build_object(
    'productos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'producto:' || x.producto || '|' || x.formato, 'producto', x.producto,
                                          'formato', x.formato, 'cantidad', x.cantidad) order by x.orden, x.producto, x.formato)
        from (select producto, formato, sum(metidas)::int as cantidad, min(orden_sugerido) as orden
                from e where tipo = 'caja_bolsa' and lote not like 'pedido:%' and metidas > 0 group by 1, 2) x), '[]'::jsonb),
    'peticiones', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'peticion:' || e.producto, 'texto', e.producto) order by e.orden_sugerido, e.producto)
        from e where e.tipo = 'peticion' and e.metidas > 0), '[]'::jsonb),
    'pedidos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'pedido:' || p.id, 'pedido_id', p.id, 'cliente', p.cliente, 'lineas', x.lineas)
                       order by p.registrado_en)
        from (select split_part(lote, ':', 2)::uuid as pedido,
                     jsonb_agg(jsonb_build_object('producto', producto, 'formato', formato, 'cantidad', metidas)
                               order by orden_sugerido, producto) as lineas
                from e where tipo = 'caja_bolsa' and lote like 'pedido:%' and metidas > 0 group by 1) x
        join public.pedidos_cliente p on p.id = x.pedido), '[]'::jsonb))
$$;

-- ---------------------------------------------------------------------------
-- 3. Las bolsas, siempre después de la producción del reparto
-- ---------------------------------------------------------------------------
create or replace function motor.elegir_tarea(p_jornada uuid, p_ahora timestamptz, p_excluir uuid default null)
returns uuid language plpgsql stable set search_path = '' as $$
declare
  v_id uuid;
  -- Lo primero de la mañana (Tarea 23): mientras falte, no sale nada más que lo urgente,
  -- lo que va a su hora y lo que forma parte de ello.
  v_primero boolean := motor.lo_primero_pendiente(p_jornada, p_ahora);
  v_en_turno boolean;
  -- Tarea 29: las bolsas del reparto sin terminar. Con la producción hecha, solo salen ellas.
  v_bolsas public.tareas;
  v_solo_bolsas boolean;
begin
  -- Fuera de su turno (Tarea 24), ninguna tarea nueva: solo la que tiene en curso, para terminarla.
  v_en_turno := motor.en_turno(p_jornada, p_ahora);
  select * into v_bolsas from public.tareas b
   where b.jornada_id = p_jornada and b.clave = 'bolsas' and b.estado in ('pendiente', 'en_curso', 'bloqueada') limit 1;
  v_solo_bolsas := v_bolsas.id is not null and v_bolsas.disponible_desde <= p_ahora
                   and motor.requisitos_hechos(p_jornada, 'produccion_reparto');

  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada
    and t.id is distinct from p_excluir
    and (t.estado = 'en_curso'
         or (v_en_turno
             and t.estado = 'pendiente'
             and t.disponible_desde <= p_ahora
             and t.prioridad_cola is distinct from 'D'
             and motor.requisitos_hechos(t.jornada_id, t.requiere_clave)
             and (not v_primero or motor.va_antes_que_lo_primero(t))
             -- Tarea 29: la salida del reparto, solo con las bolsas hechas; y con la producción
             -- hecha, nada entre ella y las bolsas (salvo un problema que abre él).
             and (v_bolsas.id is null or t.clave is distinct from 'salida_reparto')
             and (not v_solo_bolsas or t.origen = 'problema'
                  or split_part(t.clave, ':', 1) in ('bolsas', 'pedido_tienda'))))
  order by motor.escalon(t),
           case when motor.escalon(t) = 3 then t.creada_en end,
           case t.prioridad_cola when 'A' then 1 when 'C' then 2 when 'D' then 3 end nulls first,
           t.hora_programada nulls last,
           t.hora_limite nulls last,
           t.obligatoria desc,
           t.orden,
           t.creada_en,
           t.id
  limit 1;
  if v_id is not null or not v_en_turno or v_solo_bolsas then
    return v_id;
  end if;

  select t.id into v_id
  from public.tareas t
  join public.plantillas_tarea p on p.id = t.plantilla_id
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and p.programacion = 'dia_semana' and p.turno = 'tarde' and p.hora_inicio is null
    and t.requiere_clave is null
    and not v_primero
  order by t.hora_limite nulls last, t.orden, t.creada_en, t.id
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  select t.id into v_id
  from public.tareas t
  where t.jornada_id = p_jornada and t.id is distinct from p_excluir and t.estado = 'pendiente'
    and t.prioridad_cola = 'D' and t.disponible_desde <= p_ahora
  order by t.orden, t.creada_en, t.id
  limit 1;
  return v_id;
end;
$$;

create or replace function motor.tarea_activa_de(p_persona uuid, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
as $$
declare
  v_jornada uuid;
  j public.jornadas;
  v_tarea uuid;
  v_sig uuid;
  v_prox uuid;
  s public.tareas;
begin
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return jsonb_build_object('jornada', null, 'pregunta', null, 'tarea', null, 'siguiente', null, 'reparto_de_hoy', null,
                              'aviso_salida', null)
           || motor.seguimiento_de(p_persona, p_ahora);
  end if;
  select * into j from public.jornadas where id = v_jornada;

  v_tarea := motor.elegir_tarea(v_jornada, p_ahora, null);
  -- Pedido de cliente: «coge / haz» al salir su tarea (una sola vez).
  if v_tarea is not null
     and exists (select 1 from public.pedidos_cliente where tarea_id = v_tarea)
     and not exists (select 1 from public.tarea_elementos where tarea_id = v_tarea and calculo ? 'calculado_en') then
    perform motor.calcular_pedido(v_tarea, p_ahora);
  end if;
  -- «Lo que viene después»: lo que tocaría sin la tarea actual; pero si antes
  -- llega una tarea con hora (o el siguiente turno), se muestra esa.
  v_sig := motor.elegir_tarea(v_jornada, p_ahora, v_tarea);
  select t.id into v_prox from public.tareas t
   where t.jornada_id = v_jornada and t.estado = 'pendiente'
     and t.disponible_desde > p_ahora and t.id is distinct from v_tarea
   order by t.disponible_desde, t.orden limit 1;
  if v_prox is not null
     and (v_sig is null
          or (select motor.escalon(t) > 4 from public.tareas t where t.id = v_sig)) then
    v_sig := v_prox;
  end if;
  select * into s from public.tareas where id = v_sig;

  return jsonb_build_object(
    'jornada', jsonb_build_object('id', j.id, 'fecha', j.fecha, 'sale', j.sale, 'hay_envio', j.hay_envio),
    'pregunta', null,
    'tarea', motor.tarea_json(v_tarea),
    'siguiente', case when v_sig is null then null else
      s.titulo || coalesce(' · ' || motor.hora_texto(coalesce(s.hora_programada,
                    case when s.disponible_desde > p_ahora then s.disponible_desde end)), '') end,
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r left join public.personas pe on pe.id = r.pegado_por
       where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
    -- Tarea 29: ha llegado la hora de salida y las bolsas no están: retrasar 15 o 30 min (retrasar_salida).
    'aviso_salida', (
      select jsonb_build_object('texto', 'Es la hora de salida (' || motor.hora_texto(b.hora_limite)
                                         || ') y las bolsas no están listas: retrasa la salida.',
                                'hora_salida', motor.hora_texto(b.hora_limite), 'minutos', '[15, 30]'::jsonb)
        from public.tareas b
       where b.jornada_id = j.id and b.clave = 'bolsas' and b.estado in ('pendiente', 'en_curso', 'bloqueada')
         and b.hora_limite is not null and b.hora_limite <= p_ahora
       limit 1))
    || motor.seguimiento_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. El operario ve y cancela los avisos a las tiendas que ha mandado
-- ---------------------------------------------------------------------------
create or replace function motor.cancelar_aviso_tienda_de(p_persona uuid, p_aviso uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
begin
  select inc.* into i from public.incidencias inc join public.personas p on p.id = inc.persona_id and p.rol = 'tienda'
   where inc.id = p_aviso and inc.opcion = 'aviso' and inc.creada_por = p_persona for update of inc;
  if i.id is null then
    return motor.error('NO_AUTORIZADO', 'Solo puedes cancelar los avisos a las tiendas que has mandado tú.');
  end if;
  if i.estado <> 'cerrada' then
    update public.incidencias
       set estado = 'cerrada', terminada_en = p_ahora, cerrada_por = p_persona, nota_cierre = 'Cancelado por el almacén'
     where id = i.id;
    perform motor.registrar('aviso_cancelado', p_persona, i.jornada_id, null,
                            jsonb_build_object('incidencia', i.id, 'a_las', p_ahora));
  end if;
  return jsonb_build_object('aviso', motor.aviso_tienda_json(i.id));
end;
$$;

create or replace function motor.api_avisos_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if motor.es_admin() then
    return motor.avisos_tiendas_de(now());
  elsif exists (select 1 from public.personas where id = auth.uid() and activo and rol = 'operario') then
    -- Tarea 29: el operario, los que ha mandado él.
    return jsonb_build_object('avisos', coalesce((
      select jsonb_agg(motor.aviso_tienda_json(i.id) order by i.iniciada_en desc)
        from public.incidencias i join public.personas p on p.id = i.persona_id and p.rol = 'tienda'
       where i.opcion = 'aviso' and i.creada_por = auth.uid()
         and i.iniciada_en >= motor.en_local(motor.fecha_local(now()) - 7, '00:00')), '[]'::jsonb));
  end if;
  return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
end; $$;

create or replace function motor.api_cancelar_aviso_almacen(p_aviso_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if motor.es_admin() then
    return motor.cancelar_aviso_almacen_de(auth.uid(), p_aviso_id, now());
  elsif exists (select 1 from public.personas where id = auth.uid() and activo and rol = 'operario') then
    -- Tarea 29: el operario, solo los avisos a las tiendas que ha mandado él.
    return motor.cancelar_aviso_tienda_de(auth.uid(), p_aviso_id, now());
  end if;
  return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
end; $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_avisos_tiendas(), motor.api_cancelar_aviso_almacen(uuid) to authenticated;
