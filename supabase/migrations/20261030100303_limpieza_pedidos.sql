-- Tarea 20 (respuesta del propietario, 30/10/2026): la limpieza de resinas del
-- viernes espera también a los pedidos de cliente de ese día (recoger en tienda
-- y Nacex). Esas tareas llevan sufijo (`pedido_tienda:<pedido>`), así que el
-- requisito nombra la plantilla y vale para todas sus tareas del día.
--
-- Deshacer: volver a crear motor.requisitos_hechos como en
-- 20261030095607_limpieza_resinas.sql y quitar de la lista de la plantilla y de
-- las limpiezas pendientes «pedido_tienda» y «pedido_nacex_viernes».

create or replace function motor.requisitos_hechos(p_jornada uuid, p_requiere text)
returns boolean language sql stable set search_path = '' as $$
  select p_requiere is null
      or not exists (select 1 from public.tareas r
                      where r.jornada_id = p_jornada
                        and split_part(r.clave, ':', 1) = any (string_to_array(p_requiere, '+'))
                        and r.estado in ('pendiente', 'en_curso', 'bloqueada'))
$$;

update public.plantillas_tarea
   set requiere_codigo = 'pegar_reparto+produccion_reparto+pedido_tienda+bolsas+preparar_envio_viernes+pedido_nacex_viernes+cola_stock'
 where codigo = 'limpieza_resinas';
update public.tareas
   set requiere_clave = 'pegar_reparto+produccion_reparto+pedido_tienda+bolsas+preparar_envio_viernes+pedido_nacex_viernes+cola_stock'
 where clave = 'limpieza_resinas' and estado = 'pendiente';
