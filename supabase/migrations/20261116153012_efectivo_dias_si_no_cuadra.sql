-- T-0012 · Tarea 40 · Respuesta del propietario a la duda 3 del PR #48 (16/11/2026): cuando el efectivo no cuadra, la línea
-- lleva también los días de los cierres, igual que cuando cuadra:
--   «· Portugalete: 80,00 € (cierres del 13/11 y 14/11); sus cierres dicen 95,00 €. Motivo: «Monedas para cambio»»
--   «· Basauri: 80,00 € (cierre del 15/11); su cierre dice 95,00 €. Motivo: «…»»
-- Solo cambia motor.efectivo_tiendas_texto (20261116093012). Lo demás de la Tarea 40, igual. Solo en pruebas.
--
-- Deshacer: volver a crear motor.efectivo_tiendas_texto como en 20261116093012.

-- «Efectivo apuntado por cada tienda:» y una línea por tienda con parada en el reparto de ese día, en el orden de la ruta:
-- «· Basauri: 120,00 € (cierre del 15/11)», «· Portugalete: 80,00 € (cierres del 13/11 y 14/11); sus cierres dicen
-- 95,00 €. Motivo: «…»», «· Bilbao: todavía no ha apuntado la bolsa de ayer», «· Bilbao: 150,00 € (sin cierre de caja en
-- la app)» o «· Algorta: sin datos en la app (todavía no la usa)». null si ese día no hay reparto con paradas.
create or replace function motor.efectivo_tiendas_texto(p_jornada uuid)
returns text language sql stable set search_path = '' as $$
  with r as (select r.id, j.fecha from public.jornadas j
               join public.repartos r on r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'
              where j.id = p_jornada limit 1),
  l as (
    select p.orden, '· ' || p.nombre || ': ' ||
           case
             when not exists (select 1 from public.personas pe where pe.centro_id = p.centro_id and pe.rol = 'tienda' and pe.activo)
               then 'sin datos en la app (todavía no la usa)'
             when b.efectivo_en is null then 'todavía no ha apuntado la bolsa de ayer'
             when b.efectivo_esperado is null then motor.euros(b.efectivo_entregado) || ' (sin cierre de caja en la app)'
             else motor.euros(b.efectivo_entregado) || ' (' || d.dias || ')'
                  -- Decisión del propietario (16/11/2026): si no cuadra, también con los días de los cierres.
                  || case when b.efectivo_entregado = b.efectivo_esperado then ''
                          else '; ' || case when d.n > 1 then 'sus cierres dicen ' else 'su cierre dice ' end
                               || motor.euros(b.efectivo_esperado) || coalesce('. Motivo: «' || b.efectivo_motivo || '»', '') end
           end as texto
      from r
      cross join lateral motor.paradas_bolsas(r.id) p
      left join public.bolsas_tienda b on b.centro_id = p.centro_id and b.fecha = r.fecha and b.reparto_id = r.id
      cross join lateral (
        select coalesce(array_length(b.efectivo_dias, 1), 0) as n,
               case when coalesce(array_length(b.efectivo_dias, 1), 0) <= 1
                    then 'cierre del ' || to_char(coalesce(b.efectivo_dias[1], b.efectivo_de), 'DD/MM')
                    else 'cierres del '
                         || (select string_agg(to_char(x, 'DD/MM'), ', ' order by k)
                               from unnest(b.efectivo_dias[1:array_length(b.efectivo_dias, 1) - 1]) with ordinality a(x, k))
                         || ' y ' || to_char(b.efectivo_dias[array_length(b.efectivo_dias, 1)], 'DD/MM') end as dias) d)
  select 'Efectivo apuntado por cada tienda:' || E'\n' || string_agg(l.texto, E'\n' order by l.orden)
    from l having count(*) > 0
$$;

revoke execute on all functions in schema motor from public;
