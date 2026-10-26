-- Prueba 06 · Dos llamadas a la vez (criterio «Duplicados», §13)
-- Paso 1 de 4. Crea una persona temporal (ficticia) para no tocar otros datos.
-- Después se lanzan A y B a la vez (B unos segundos después de A) y por último
-- la limpieza, que deja la base como estaba y lo comprueba.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-0000000000c1', 'authenticated',
        'authenticated', 'concurrencia@osasun.invalid', '{}', '{}', now(), now());
insert into public.personas (id, nombre, rol, centro_id)
select '00000000-0000-4000-a000-0000000000c1', 'Prueba de concurrencia', 'operario', id
from public.centros_trabajo where codigo = 'ALMACEN';
insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
values ('00000000-0000-4000-a000-0000000000c1', 2, 'manana', '08:30', '13:00');
select 'preparado' as paso;
