-- Prueba 06 · Paso 4 de 4. Borra la persona temporal y todo lo suyo, y
-- comprueba que no queda nada.
delete from public.jornadas where persona_id = '00000000-0000-4000-a000-0000000000c1';
delete from public.personas where id = '00000000-0000-4000-a000-0000000000c1';
delete from auth.users where id = '00000000-0000-4000-a000-0000000000c1';
select case when not exists (select 1 from public.jornadas where persona_id = '00000000-0000-4000-a000-0000000000c1')
             and not exists (select 1 from public.personas where id = '00000000-0000-4000-a000-0000000000c1')
            then 'OK: base como estaba' else 'FALLO: quedan datos' end as limpieza;
