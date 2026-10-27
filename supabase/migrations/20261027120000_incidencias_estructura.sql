-- Tarea 7 · Incidencias (ESTADO_DEL_SISTEMA.md v1.17, §6.6): parte de estructura
-- que quita o cambia algo. La ejecuta el propietario en el SQL Editor de
-- Supabase (el conector pide una confirmación que no le llega).
--
-- 1. Ya puede haber varias incidencias abiertas a la vez (unas esperando a
--    Administración, otras a que llegue lo pedido): fuera el índice que solo
--    dejaba una.
-- 2. Nuevo tipo de correo: «Incidencia: …», que se envía a Administración en el
--    momento, con el mismo sistema de reintentos.

drop index if exists public.incidencias_una_abierta;

alter table motor.correos drop constraint if exists correos_tipo_check;
alter table motor.correos add constraint correos_tipo_check check (tipo in ('cierre', 'retraso', 'incidencia'));
