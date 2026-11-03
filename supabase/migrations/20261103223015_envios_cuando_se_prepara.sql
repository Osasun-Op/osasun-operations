-- Tarea 30b · Respuestas del propietario en el PR (03/11/2026). Solo en pruebas: espera con las de tiendas
-- (AGENTE_BASE_DE_DATOS.md §4). Solo cambia lo de «Envíos» de 20261103211530; el almacén no cambia.
--   1. El envío cuenta en cuanto está preparado y metido en la caja: cuando el operario termina
--      «Prepara el envío aprobado» (entre semana o el viernes), vaya quien vaya al reparto. Antes se
--      esperaba a «Salida a Nacex» o, el viernes, a «Lleva en el reparto lo que va a Nacex», que no existe
--      cuando sale Administración. La tienda lo ve desde el día siguiente, como antes. En «Envíos», la
--      hora es la de preparado (`preparado`, en lugar de `salida`).
--   2. Al confirmarlo («Todo bien» o «Falta algo») desaparece de «Envíos» en el momento (antes seguía
--      hasta el final del día). Siguen saliendo los de la última semana sin confirmar.
--
-- Deshacer: volver a crear motor.preparar_envios_tienda y motor.envios_tienda_json y la función
-- motor.salida_envio_en como están en 20261103211530, y borrar motor.envio_preparado_en.

-- Cuándo quedó preparado el envío (la tarea del envío terminada): null si aún no.
create or replace function motor.envio_preparado_en(p_tarea uuid, p_ahora timestamptz)
returns timestamptz language sql stable set search_path = '' as $$
  select t.terminada_en from public.tareas t
   where t.id = p_tarea and t.estado = 'hecha' and t.terminada_en <= p_ahora
$$;

-- Apunta los envíos preparados para la tienda (de la última semana, hasta ayer): uno por envío.
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
    select r.id as reparto_id, j.fecha,
           motor.envio_preparado_en((r.resultado -> 'tareas' ->> 'bolsas')::uuid, p_ahora) as preparado
      from public.repartos r join public.jornadas j on j.id = r.jornada_id
     where r.tipo = 'envio' and r.estado = 'aceptado' and j.fecha >= v_hoy - 7 and j.fecha < v_hoy
       and exists (select 1 from public.tarea_elementos e
                    where e.tarea_id = (r.resultado -> 'tareas' ->> 'bolsas')::uuid and e.destino_id = v_destino
                      and e.tipo in ('caja_bolsa', 'peticion'))
       and not exists (select 1 from public.bolsas_tienda b where b.centro_id = pe.centro_id and b.fecha = j.fecha)
     order by j.fecha
  loop
    continue when x.preparado is null;
    perform pg_advisory_xact_lock(hashtextextended('bolsa_tienda:' || pe.centro_id || ':' || x.fecha, 0));
    -- salida_en guarda, en los envíos, la hora en que quedó preparado.
    insert into public.bolsas_tienda (centro_id, fecha, reparto_id, tarea_id, salida_en)
    values (pe.centro_id, x.fecha, x.reparto_id, null, x.preparado)
    on conflict (centro_id, fecha) do nothing;
    if found then
      perform motor.registrar('envio_en_camino', p_persona, null, null,
                              jsonb_build_object('reparto', x.reparto_id, 'fecha', x.fecha, 'preparado', x.preparado));
    end if;
  end loop;
end;
$$;

-- «Envíos» de la tienda: los que quedan por confirmar, los más antiguos primero.
create or replace function motor.envios_tienda_json(p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', b.id, 'reparto_id', b.reparto_id, 'fecha', b.fecha, 'preparado', motor.hora_texto(b.salida_en),
             'destino', d.nombre)
           || motor.bolsa_contenido(b.reparto_id, d.id)
           order by b.fecha), '[]'::jsonb)
    from public.bolsas_tienda b
    join public.repartos r on r.id = b.reparto_id and r.tipo = 'envio'
    join public.centros_trabajo d on d.id = motor.destino_envio(b.centro_id)
   where b.centro_id = p_centro and b.reposicion is null
$$;

drop function motor.salida_envio_en(uuid, timestamptz);

revoke execute on all functions in schema motor from public;
