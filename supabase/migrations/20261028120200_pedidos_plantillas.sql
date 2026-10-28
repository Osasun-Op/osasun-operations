-- Tarea 12 · Pedidos de cliente (ESTADO_DEL_SISTEMA.md v1.24, §5 R1b).
-- Se ejecuta en el SQL Editor (cambia restricciones y una función con DELETE).
-- 1. Restricciones: las tareas condicionadas «pedido_tienda» y «pedido_nacex», y
--    las lecturas de la hoja para un pedido («pedido»).
-- 2. Plantillas de las tareas de los pedidos de cliente:
--    · «Hay un pedido de cliente para dejar en [tienda]»: aparece al terminar la
--      producción del reparto (requiere produccion_reparto), antes de las bolsas.
--    · «Prepara el pedido de cliente (Nacex)»: de lunes a jueves por la tarde,
--      después de la revisión y la preparación del envío (antes de las 18:10);
--      el viernes, por la mañana, antes de las 10:45 (sale con el reparto).
--    Las dos con su lista («coge / haz») y, si no se terminan, pasan al día siguiente.
-- 3. «Prepara el reparto» dice quién lo preparó por su nombre («Reparto preparado
--    por Asier»), no por su rol. Solo cambia ese texto; el resto de
--    servidor_guardar_reparto es el de la migración 20261028120100.

alter table public.plantillas_tarea drop constraint plantillas_tarea_condicion_check;
alter table public.plantillas_tarea add constraint plantillas_tarea_condicion_check check (condicion in (
  'sale_operario', 'sale_administracion', 'hay_envio', 'no_hay_envio',
  'reparto_pegado', 'envio_pegado',
  'llega_mercancia', 'pedido_cliente', 'no_quedan_vapers',
  'pedido_tienda', 'pedido_nacex'));
alter table public.lecturas_sheets drop constraint lecturas_sheets_motivo_check;
alter table public.lecturas_sheets add constraint lecturas_sheets_motivo_check
  check (motivo in ('reparto', 'envio', 'stock', 'pedido'));

insert into public.plantillas_tarea (
  centro_id, codigo, titulo, programacion, dias_semana, turno, hora_inicio, hora_limite,
  duracion_min, condicion, requiere_codigo, contenido, obligatoria, prioridad_cola, no_terminada, orden)
select c.id, v.codigo, v.titulo, 'condicionada', v.dias::smallint[], v.turno, null, v.hora_limite::time,
       null, v.condicion, v.requiere, 'produccion_reparto', true, null, 'arrastrar', v.orden
from public.centros_trabajo c,
(values
  ('pedido_tienda', 'Hay un pedido de cliente para dejar en la tienda', '{1,2,3,4,5}', 'manana', '10:45',
   'pedido_tienda', 'produccion_reparto', 35),
  ('pedido_nacex', 'Prepara el pedido de cliente (Nacex)', '{1,2,3,4}', 'tarde', '18:10',
   'pedido_nacex', null, 45),
  ('pedido_nacex_viernes', 'Prepara el pedido de cliente (Nacex)', '{5}', 'manana', '10:45',
   'pedido_nacex', null, 59)
) as v(codigo, titulo, dias, turno, hora_limite, condicion, requiere, orden)
where c.codigo = 'ALMACEN';

create or replace function public.servidor_guardar_reparto(
  p_persona uuid, p_jornada uuid, p_tipo text, p_texto text, p_huella text, p_fecha_texto date, p_sale text,
  p_lectura uuid, p_lineas jsonb, p_produccion jsonb, p_bolsas jsonb, p_aceptado boolean, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r0 public.repartos;
  v_id uuid;
  v_cond text := case when p_tipo = 'reparto' then 'reparto_pegado' else 'envio_pegado' end;
  v_prod uuid;
  v_bolsas uuid;
  v_destino uuid;
  v_antes jsonb;
  v_despues jsonb;
  v_bolsas_resultado jsonb := '[]';
  v_min_caja integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                  where clave = 'duracion_min_por_caja' and centro_id is null), 1);
  v_min_bolsa integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                   where clave = 'duracion_min_por_bolsa' and centro_id is null), 3);
  v_dur_prod integer;
  v_dur_bolsas integer;
  v_resultado jsonb;
  v_es_suya boolean := p_persona = (select persona_id from public.jornadas where id = p_jornada);
  v_pegar uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('reparto:' || p_jornada || ':' || p_tipo, 0));

  if not p_aceptado then
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'con_errores', p_lectura, p_persona, p_ahora)
    returning id into v_id;
  else
    select * into r0 from public.repartos where jornada_id = p_jornada and tipo = p_tipo and estado = 'aceptado';
    if r0.huella = p_huella then
      return r0.resultado || jsonb_build_object('ya_pegado', true);
    end if;
    if r0.id is not null then
      update public.repartos set estado = 'sustituido' where id = r0.id;
    end if;
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado,
                                 sustituye_a, lectura_id, pegado_por, pegado_en)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'aceptado', r0.id, p_lectura, p_persona, p_ahora)
    returning id into v_id;
  end if;

  insert into public.reparto_lineas (reparto_id, num_linea, texto, clase, destino_id, cantidad, producto, formato, error, mensaje)
  select v_id, (l ->> 'num')::int, l ->> 'texto', l ->> 'clase', (l ->> 'destino_id')::uuid, (l ->> 'cantidad')::int,
         l ->> 'producto', l ->> 'formato', l ->> 'error', l ->> 'mensaje'
  from jsonb_array_elements(coalesce(p_lineas, '[]')) l;

  if not p_aceptado then
    perform motor.registrar('reparto_con_errores', p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo));
    return jsonb_build_object('reparto_id', v_id, 'estado', 'con_errores');
  end if;

  -- Tareas del reparto o del envío
  if p_tipo = 'reparto' then
    perform motor.fijar_sale(p_jornada, p_sale);
  else
    perform motor.fijar_envio(p_jornada, true, null);
  end if;
  perform motor.crear_tarea_condicionada(p_jornada, v_cond);
  if p_tipo = 'reparto' then
    select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
    select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';
  else
    select id into v_prod from public.tareas where jornada_id = p_jornada
       and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1;
    v_bolsas := v_prod;
  end if;
  if v_prod is null or v_bolsas is null then
    raise exception 'No hay tarea para el % de hoy', p_tipo;
  end if;
  update public.tareas set reparto_id = v_id where id in (v_prod, v_bolsas);

  -- Producción: lo que falta. Se conservan las cajas ya hechas.
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, motivo, orden_sugerido, calculo)
  select v_prod, 'referencia_produccion', p_tipo, x ->> 'producto', coalesce(x ->> 'formato', ''),
         (x ->> 'faltan')::int, x ->> 'aviso', coalesce((x ->> 'orden')::int, 0), x || jsonb_build_object('lectura_id', p_lectura)
  from jsonb_array_elements(coalesce(p_produccion, '[]')) x
  where (x ->> 'faltan')::int > 0
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set cantidad = excluded.cantidad, motivo = excluded.motivo, orden_sugerido = excluded.orden_sugerido,
         calculo = excluded.calculo,
         estado = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad then 'hecho'
                       when public.tarea_elementos.estado = 'hecho' then 'pendiente'
                       else public.tarea_elementos.estado end,
         terminado_en = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad
                             then coalesce(public.tarea_elementos.terminado_en, p_ahora) end;

  -- Referencias que ya no hacen falta: sin nada hecho se quitan; con algo hecho se cierran.
  delete from public.tarea_elementos e
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha = 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);
  update public.tarea_elementos e
     set cantidad = e.cantidad_hecha, estado = 'hecho', terminado_en = coalesce(e.terminado_en, p_ahora),
         motivo = 'Ya no hace falta con el reparto corregido'
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha > 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);

  -- Bolsas: las tiendas sin cambios se conservan; las que cambian se vuelven a
  -- comprobar caja a caja; las que ya no están se quitan.
  for v_destino in
    select distinct d from (
      select e.destino_id as d from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo
      union
      select (b ->> 'destino_id')::uuid from jsonb_array_elements(coalesce(p_bolsas, '[]')) b) s
  loop
    select jsonb_agg(jsonb_build_array(e.producto, e.formato, e.cantidad) order by e.producto, e.formato)
      into v_antes from public.tarea_elementos e
     where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
    select jsonb_agg(jsonb_build_array(i ->> 'producto', coalesce(i ->> 'formato', ''), (i ->> 'cantidad')::int)
                     order by i ->> 'producto', coalesce(i ->> 'formato', ''))
      into v_despues
      from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
     where (b ->> 'destino_id')::uuid = v_destino;

    if v_antes is distinct from v_despues then
      delete from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
      select v_bolsas, 'caja_bolsa', p_tipo, i ->> 'producto', coalesce(i ->> 'formato', ''), v_destino,
             (i ->> 'cantidad')::int, coalesce((i ->> 'orden')::int, 0)
        from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
       where (b ->> 'destino_id')::uuid = v_destino;
    end if;
    if v_despues is not null then
      v_bolsas_resultado := v_bolsas_resultado || jsonb_build_object(
        'destino_id', v_destino,
        'destino', (select nombre from public.centros_trabajo where id = v_destino),
        'cajas', (select sum((x ->> 2)::int) from jsonb_array_elements(v_despues) x),
        'cambia', r0.id is not null and v_antes is distinct from v_despues);
    end if;
  end loop;

  -- Duraciones de referencia (§6.10): 1 min por caja que falta, 3 min por tienda.
  select coalesce(sum((x ->> 'faltan')::int), 0) * v_min_caja into v_dur_prod
    from jsonb_array_elements(coalesce(p_produccion, '[]')) x where (x ->> 'faltan')::int > 0;
  v_dur_bolsas := jsonb_array_length(v_bolsas_resultado) * v_min_bolsa;
  if v_prod = v_bolsas then
    update public.tareas set duracion_min = nullif(v_dur_prod + v_dur_bolsas, 0) where id = v_prod;
  else
    update public.tareas set duracion_min = nullif(v_dur_prod, 0) where id = v_prod;
    update public.tareas set duracion_min = nullif(v_dur_bolsas, 0) where id = v_bolsas;
  end if;

  perform motor.ajustar_estado_lista(p_persona, v_prod, 'No falta producir nada: todo está hecho en el almacén', p_ahora);
  if v_bolsas <> v_prod then
    perform motor.ajustar_estado_lista(p_persona, v_bolsas, 'Sin bolsas', p_ahora);
  end if;

  -- «Prepara el reparto» queda hecha al aceptarse el reparto, lo prepare quien lo prepare.
  if p_tipo = 'reparto' then
    for v_pegar in
      update public.tareas
         set estado = 'hecha', iniciada_en = coalesce(iniciada_en, p_ahora), terminada_en = p_ahora,
             resultado = case when v_es_suya then 'Reparto preparado'
                              else 'Reparto preparado por ' || coalesce((select nombre from public.personas where id = p_persona),
                                                                        'Administración') end
       where jornada_id = p_jornada and clave = 'pegar_reparto' and estado in ('pendiente', 'en_curso')
      returning id
    loop
      perform motor.registrar('tarea_terminada', p_persona, p_jornada, v_pegar,
                              jsonb_build_object('a_las', p_ahora, 'por', 'reparto aceptado'));
    end loop;
  end if;

  v_resultado := jsonb_build_object(
    'reparto_id', v_id, 'estado', 'aceptado', 'tipo', p_tipo, 'sale', p_sale, 'sustituye_a', r0.id,
    'produccion', coalesce(p_produccion, '[]'), 'bolsas', v_bolsas_resultado,
    'tareas', jsonb_build_object('produccion', v_prod, 'bolsas', v_bolsas),
    'datos_leidos_en', (select leido_en from public.lecturas_sheets where id = p_lectura));
  update public.repartos set resultado = v_resultado where id = v_id;
  perform motor.registrar(case when r0.id is null then 'reparto_aceptado' else 'reparto_sustituido' end,
                          p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo, 'anterior', r0.id));
  return v_resultado || jsonb_build_object('tarea_activa',
                                           case when v_es_suya then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;
