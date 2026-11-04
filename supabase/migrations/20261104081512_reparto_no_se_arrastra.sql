-- Tarea 29c · Lo del reparto no se arrastra (04/11/2026, urgente). Solo en pruebas: espera con las de tiendas
-- (AGENTE_BASE_DE_DATOS.md §4).
--   El 03/11 a las 10:28 las bolsas del reparto se pasaron a mañana por error (antes de la Tarea 29, que ya
--   no lo deja hacer) y el 04/11 a las 06:00 se arrastraron a hoy, con el reparto del 03/11 ya salido.
--   1. Datos: se cancela esa copia arrastrada de hoy con el motivo «Del reparto del 03/11, que ya salió»
--      (motor.cancelar_tarea_de, como Administración, queda en el registro). Las bolsas de hoy no se tocan.
--      Si la tarea no existe o ya no está abierta (otro entorno), no hace nada.
--   2. motor.arrastrar no pasa al día siguiente lo del reparto o del envío de un día (motor.es_del_reparto:
--      producción, bolsas, salida, preparación del envío, Nacex), aunque tenga no_terminada = 'arrastrar' o
--      sea ya una copia arrastrada (se mira la tarea de origen con motor.clave_original). Consta como no
--      hecho en su día. Los pedidos de cliente (de tienda y por Nacex) siguen pasando al día siguiente,
--      como dice ESTADO R1b (decisión del propietario, 28/10/2026); queda la duda en el PR.
--
-- Deshacer: volver a crear motor.arrastrar como está en 20261028114125 y borrar motor.clave_original. La
-- tarea cancelada se puede volver a dejar pendiente (estado 'pendiente', motivo_no_hecha null).

-- La clave de la tarea de origen (la de una copia arrastrada es la de la tarea que arrastró).
create or replace function motor.clave_original(p_tarea uuid)
returns text language sql stable set search_path = '' as $$
  with recursive c as (
    select t.id, t.clave, t.tarea_origen_id, 0 as n from public.tareas t where t.id = p_tarea
    union all
    select o.id, o.clave, o.tarea_origen_id, c.n + 1
      from c join public.tareas o on o.id = c.tarea_origen_id
     where c.clave like 'arrastre:%' and c.n < 60)
  select clave from c order by n desc limit 1
$$;

create or replace function motor.arrastrar(p_jornada uuid)
returns void language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_anterior uuid;
  t public.tareas;
  v_id uuid;
  v_pedido uuid;
begin
  select * into j from public.jornadas where id = p_jornada;
  select id into v_anterior from public.jornadas
   where persona_id = j.persona_id and fecha < j.fecha
   order by fecha desc limit 1;
  if v_anterior is null then
    return;
  end if;

  for t in
    select * from public.tareas
    where jornada_id = v_anterior
      and estado in ('pendiente', 'en_curso', 'bloqueada')
      and no_terminada in ('arrastrar', 'sigue_abierta')
    order by orden, creada_en
  loop
    -- Tarea 29c: lo del reparto o del envío de un día no pasa al siguiente (consta como no hecho en
    -- su día), aunque se marcara para arrastrar o ya fuera una copia arrastrada. Los pedidos de cliente
    -- siguen su regla de siempre (ESTADO_DEL_SISTEMA.md R1b).
    if motor.es_del_reparto(motor.clave_original(t.id))
       and split_part(motor.clave_original(t.id), ':', 1) not in ('pedido_tienda', 'pedido_cliente', 'pedido_nacex',
                                                                    'pedido_nacex_viernes') then
      continue;
    end if;
    select id into v_pedido from public.pedidos_cliente where tarea_id = t.id and entrega = 'nacex';
    if v_pedido is not null then
      perform motor.mover_pedido_nacex(v_pedido, j.id, 'Pasa al ' || to_char(j.fecha, 'DD/MM') || ': no se terminó', null);
      continue;
    end if;

    insert into public.tareas (
      jornada_id, clave, origen, plantilla_id, titulo, porque, contenido, obligatoria,
      prioridad_cola, disponible_desde, urgente, duracion_min, no_terminada, orden,
      tarea_origen_id, creada_por)
    values (
      j.id, 'arrastre:' || t.id, t.origen, t.plantilla_id, t.titulo, t.porque, t.contenido, t.obligatoria,
      t.prioridad_cola, motor.inicio_turno(j.persona_id, j.fecha, null), t.urgente, t.duracion_min,
      t.no_terminada, t.orden, t.id, t.creada_por)
    on conflict (jornada_id, clave) do nothing
    returning id into v_id;

    update public.tareas set estado = 'arrastrada' where id = t.id;
    if v_id is not null then
      update public.incidencias set tarea_resolucion_id = v_id where tarea_resolucion_id = t.id;
      update public.pedidos_cliente set tarea_id = v_id where tarea_id = t.id;
      -- La lista pasa con lo hecho; el «coge / haz» de un pedido se vuelve a calcular al salir.
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, destino_id, cantidad,
                                          cantidad_hecha, motivo, orden_sugerido, calculo, estado, terminado_en)
      select v_id, e.tipo, e.lote, e.producto, e.formato, e.categoria, e.destino_id, e.cantidad,
             e.cantidad_hecha, case when e.lote = 'pedido' then null else e.motivo end, e.orden_sugerido,
             case when e.lote = 'pedido' then '{}'::jsonb else e.calculo end,
             case when e.estado = 'hecho' then 'hecho' else 'pendiente' end, e.terminado_en
        from public.tarea_elementos e where e.tarea_id = t.id;
    end if;
    perform motor.registrar('tarea_arrastrada', null, j.id, coalesce(v_id, t.id),
                            jsonb_build_object('desde', t.id));
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Datos: la copia arrastrada de las bolsas del 03/11 (solo si está abierta)
-- ---------------------------------------------------------------------------
do $$
declare
  v_tarea uuid;
  v_admin uuid := motor.administracion_por_defecto();
begin
  select id into v_tarea from public.tareas
   where clave = 'arrastre:6a13b51c-97c5-4ab3-ab53-694052a4ead2' and estado in ('pendiente', 'en_curso', 'bloqueada');
  if v_tarea is null or v_admin is null then
    return;
  end if;
  perform motor.cancelar_tarea_de(v_admin, v_tarea, 'Del reparto del 03/11, que ya salió', now());
end;
$$;

revoke execute on all functions in schema motor from public;
