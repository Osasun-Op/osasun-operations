-- T-0014 · Tarea 42 · Atascados: «Mantener» en la tienda (decisión del propietario, 18/11/2026). Solo en pruebas:
-- producción espera con las de tiendas (AGENTE_BASE_DE_DATOS.md §4).
--   Con un atascado, Administración solo podía elegir «Promoción» o «Al almacén» (franquicias y Durango: «Promoción» o
--   «Recogida»). Si lo ponía como promoción para dejarlo en la tienda, a la tienda le quedaba abierto hasta «Ya no queda».
--   1. decidir_atascado acepta además "mantener", igual en todas las tiendas: texto opcional (180 letras), el atascado
--      queda cerrado con la decisión, su texto y quién y cuándo; la incidencia se cierra con «Se queda en la tienda»
--      («: texto» si lo hay); sin aviso a la tienda; el registro, como las demás decisiones.
--   2. motor.atascado_json: "mantener" en `decisiones` (propias: promoción, almacén, mantener; franquicias: promoción,
--      recogida, mantener) y `estado_texto` «Se queda en la tienda» («: texto» si lo hay). Como lo demás cerrado,
--      deja de salir en la tienda a la semana (motor.atascados_tienda_json, sin cambios).
--   3. Datos, solo en pruebas (`entorno` = "pruebas"): las dos del 18/11 que se pusieron como promoción y son
--      «mantener» (Basauri, 3 SPRAY BUCAL; Barakaldo, 1 ICE O LATOR 10g) pasan a «mantener» con el mismo texto; su aviso,
--      si sigue sin leer, se cancela, y la nota de su incidencia queda como la de «mantener». Las de EGUZKI de
--      Portugalete y Rentería no se tocan. En otro entorno, o si ya no están como promoción, no hace nada.
--
-- Deshacer: volver a crear motor.atascado_json y motor.decidir_atascado_de como están en 20261104140512 y el check de
-- atascados.decision sin "mantener" (antes, pasar a mano a "promocion" o "cerrado" los que tengan "mantener"). Los
-- datos del punto 3 se pueden devolver con estado = 'promocion', decision = 'promocion', la nota «Promoción: …» y el
-- aviso abierto otra vez (estado 'abierta', terminada_en, cerrada_por y nota_cierre a null).

-- ---------------------------------------------------------------------------
-- 1. La decisión nueva (solo se añade el valor)
-- ---------------------------------------------------------------------------
alter table public.atascados drop constraint atascados_decision_check;
alter table public.atascados add constraint atascados_decision_check
  check (decision in ('promocion', 'almacen', 'recogida', 'mantener'));

-- ---------------------------------------------------------------------------
-- 2. El objeto atascado (solo cambian `decisiones` y el texto del cerrado con «mantener»)
-- ---------------------------------------------------------------------------
create or replace function motor.atascado_json(p_id uuid, p_vista text, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', a.id, 'tienda_id', a.centro_id, 'tienda', c.nombre, 'fecha', a.fecha,
    'producto', a.producto, 'formato', a.formato, 'cantidad', a.cantidad,
    'texto', motor.cajas_texto(a.cantidad, a.producto, a.formato), 'nota', a.nota, 'por', a.nombre,
    'estado', x.estado,
    'estado_texto', case p_vista
      when 'pide' then case x.estado
        when 'por_recoger' then 'Lo has pedido: el almacén lo recoge en ' || c.nombre
                                || case when dp.tipo = 'envio' then ' y va en tu siguiente envío' else ' y te lo trae' end
        when 'entregado' then case when pt.id is not null then motor.peticion_tienda_json(pt, p_ahora) ->> 'estado_texto'
                                   else 'Entregado el ' || to_char(motor.fecha_local(a.terminado_en), 'DD/MM') end
        else 'Lo has pedido' end
      else case x.estado
        when 'ofrecido' then 'Ofrecido a las demás tiendas hasta el cierre del ' || to_char(a.fecha, 'DD/MM')
        when 'administracion' then case when motor.atascados_va_a(a.centro_id) = 'ofrecer'
                                        then 'Nadie lo ha pedido: decide Administración' else 'Decide Administración' end
        when 'promocion' then 'En promoción: ' || a.decision_texto
        when 'por_recoger' then case when a.pedido_por is not null then 'Lo quiere ' || pc.nombre || ': prepáralo para recogida'
                                     else 'Al almacén: prepáralo para recogida' end
        when 'entregado' then 'Recogido el ' || to_char(motor.fecha_local(a.terminado_en), 'DD/MM')
                              || ' a las ' || motor.hora_texto(a.terminado_en)
        when 'terminado' then 'Promoción terminada: ya no queda'
        else case when a.decision = 'recogida' then 'Recogida: la organiza Administración' || coalesce(' (' || a.decision_texto || ')', '')
                  -- T-0014: se queda en la tienda.
                  when a.decision = 'mantener' then 'Se queda en la tienda' || coalesce(': ' || a.decision_texto, '')
                  else 'Cerrado por Administración' || coalesce(': ' || i.nota_cierre, '') end end end,
    'pedido_por', pc.nombre, 'pedido_por_nombre', a.pedido_por_nombre,
    'promocion', case when a.decision = 'promocion' then a.decision_texto end,
    'decision', a.decision,
    -- Lo que Administración puede decidir mientras está con ella (T-0014: también «mantener», en todas).
    'decisiones', case when x.estado = 'administracion'
                       then case when motor.atascados_va_a(a.centro_id) = 'ofrecer' then '["promocion", "almacen", "mantener"]'::jsonb
                                 else '["promocion", "recogida", "mantener"]'::jsonb end
                       else '[]'::jsonb end)
  from public.atascados a
  join public.centros_trabajo c on c.id = a.centro_id
  left join public.centros_trabajo pc on pc.id = a.pedido_por
  left join public.incidencias i on i.id = a.incidencia_id
  left join public.peticiones_tienda pt on pt.id = a.peticion_id
  left join lateral motor.destino_peticion(a.pedido_por) dp on a.pedido_por is not null
  -- Si Administración la cierra sin decidir (cerrar_incidencia_tienda), queda cerrado.
  cross join lateral (select case when a.estado = 'administracion' and i.estado = 'cerrada' then 'cerrado'
                                  else a.estado end as estado) x
  where a.id = p_id
$$;

-- ---------------------------------------------------------------------------
-- 3. Administración decide (solo se añade «mantener»)
-- ---------------------------------------------------------------------------
-- promocion (con su texto: aviso a la tienda y abierta hasta «Ya no queda») · almacen (propias: recogida de Eder) ·
-- recogida (franquicias: la organiza Administración; se cierra con su nota) · mantener (todas: se queda en la tienda,
-- sin aviso). La incidencia queda cerrada con la decisión.
create or replace function motor.decidir_atascado_de(p_admin uuid, p_id uuid, p_decision text, p_texto text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  a public.atascados;
  i public.incidencias;
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
  v_ofrece boolean;
  v_nota text;
  r record;
begin
  perform motor.vencer_atascados(p_ahora);
  select * into a from public.atascados where id = p_id for update;
  if a.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese atascado no existe.');
  end if;
  select * into i from public.incidencias where id = a.incidencia_id;
  if a.estado <> 'administracion' or i.estado = 'cerrada' then
    return motor.error('ESTADO_NO_VALIDO', 'Este atascado ya está decidido.');
  end if;
  v_ofrece := motor.atascados_va_a(a.centro_id) = 'ofrecer';
  if p_decision is null
     or p_decision not in ('promocion', case when v_ofrece then 'almacen' else 'recogida' end, 'mantener') then
    return motor.error('DATOS_NO_VALIDOS', case when v_ofrece then 'Elige: promoción, al almacén o mantener.'
                                                else 'Elige: promoción, recogida o mantener.' end);
  end if;
  if length(v_texto) > 180 then
    return motor.error('DATOS_NO_VALIDOS', 'En una línea (180 letras como máximo).');
  end if;
  if p_decision = 'promocion' then
    if v_texto is null then
      return motor.error('DATOS_NO_VALIDOS', 'Escribe la promoción.');
    end if;
    update public.atascados
       set estado = 'promocion', decision = 'promocion', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora,
           aviso_id = motor.avisar_atascado(p_admin, a.centro_id, 'atascado:' || a.id || ':promocion',
                                            'Promoción de ' || motor.cajas_texto(a.cantidad, a.producto, a.formato) || ': ' || v_texto,
                                            p_ahora)
     where id = a.id;
    v_nota := 'Promoción: ' || v_texto;
  elsif p_decision = 'almacen' then
    select * into r from motor.jornada_recogida(p_ahora);
    if r.jornada is null then
      return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
    end if;
    update public.atascados set decision = 'almacen', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora
     where id = a.id;
    perform motor.mover_atascado(a.id, p_admin, r.jornada, r.desde, p_ahora);
    v_nota := 'Al almacén' || coalesce(': ' || v_texto, '');
  elsif p_decision = 'mantener' then
    -- T-0014: se queda en la tienda. Sin aviso: la tienda lo ve en su lista («Se queda en la tienda»).
    update public.atascados
       set estado = 'cerrado', decision = 'mantener', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora
     where id = a.id;
    v_nota := 'Se queda en la tienda' || coalesce(': ' || v_texto, '');
  else
    update public.atascados
       set estado = 'cerrado', decision = 'recogida', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora
     where id = a.id;
    v_nota := 'Recogida' || coalesce(': ' || v_texto, '');
  end if;
  perform motor.cerrar_incidencia_tienda_de(p_admin, i.id, v_nota, p_ahora);
  perform motor.registrar('atascado_decidido', p_admin, i.jornada_id, null,
                          jsonb_build_object('atascado', a.id, 'decision', p_decision, 'a_las', p_ahora));
  return motor.incidencias_tiendas_de(p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Datos, solo en pruebas: las dos del 18/11 que son «mantener»
-- ---------------------------------------------------------------------------
do $$
declare
  a public.atascados;
  av public.incidencias;
  v_ahora timestamptz := now();
begin
  if coalesce((select valor #>> '{}' from public.configuracion where clave = 'entorno' and centro_id is null), '') <> 'pruebas' then
    return;
  end if;
  for a in select x.* from public.atascados x
            where x.id in ('0a362adf-bb52-440b-8d07-7f57b03efe69',   -- Basauri, 3 SPRAY BUCAL («De momento dejalas»)
                           '8d057ab4-0be4-46ec-8252-6a4096515a5e')   -- Barakaldo, 1 ICE O LATOR 10g
              and x.estado = 'promocion' and x.decision = 'promocion'
            for update loop
    update public.atascados set estado = 'cerrado', decision = 'mantener' where id = a.id;
    update public.incidencias set nota_cierre = 'Se queda en la tienda' || coalesce(': ' || a.decision_texto, '')
     where id = a.incidencia_id;
    -- El aviso de la promoción, si sigue sin leer, se cancela (como cancela Administración sus avisos).
    select * into av from public.incidencias where id = a.aviso_id and opcion = 'aviso' and estado <> 'cerrada' for update;
    if av.id is not null then
      update public.incidencias
         set estado = 'cerrada', terminada_en = v_ahora, cerrada_por = a.decidido_por, nota_cierre = 'Cancelado por Administración'
       where id = av.id;
      perform motor.registrar('aviso_cancelado', a.decidido_por, av.jornada_id, null,
                              jsonb_build_object('incidencia', av.id, 'a_las', v_ahora));
    end if;
    perform motor.registrar('atascado_decidido', a.decidido_por,
                            (select jornada_id from public.incidencias where id = a.incidencia_id), null,
                            jsonb_build_object('atascado', a.id, 'decision', 'mantener', 'antes', 'promocion',
                                               'corregido', 'T-0014', 'a_las', v_ahora));
  end loop;
end;
$$;

revoke execute on all functions in schema motor from public;
