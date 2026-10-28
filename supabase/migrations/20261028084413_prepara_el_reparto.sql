-- Tarea 10 · La tarea del operario pasa a llamarse «Prepara el reparto» (el
-- reparto ya no se pega, se prepara con una lista). El código sigue siendo
-- `pegar_reparto`. Cambia la plantilla y las tareas aún pendientes.

update public.plantillas_tarea set titulo = 'Prepara el reparto' where codigo = 'pegar_reparto';
update public.tareas set titulo = 'Prepara el reparto'
 where clave = 'pegar_reparto' and estado = 'pendiente' and titulo = 'Pega el reparto de hoy';
