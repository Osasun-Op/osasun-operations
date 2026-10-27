-- Datos SOLO para el proyecto de pruebas (osasun-pruebas). Nunca en producción.
-- Dos usuarios ficticios sin contraseña (no pueden iniciar sesión), sus
-- personas y el horario del operario (ESTADO_DEL_SISTEMA.md §3).
-- Se puede ejecutar varias veces.

insert into public.configuracion (clave, centro_id, valor)
values ('entorno', null, '"pruebas"'),
       ('url_proyecto', null, '"https://rvypswuoafnjwqdwxjvo.supabase.co"')  -- dirección pública del proyecto de pruebas (no es una clave)
on conflict (clave, centro_id) do update set valor = excluded.valor;

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000001', 'authenticated', 'authenticated',
   'operario.pruebas@osasun.invalid', '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000002', 'authenticated', 'authenticated',
   'administracion.pruebas@osasun.invalid', '{"provider":"email","providers":["email"]}', '{}', now(), now())
on conflict (id) do nothing;

insert into public.personas (id, nombre, rol, centro_id, telefono)
select '00000000-0000-4000-a000-000000000001', 'Operario de pruebas', 'operario', c.id, null
from public.centros_trabajo c where c.codigo = 'ALMACEN'
on conflict (id) do nothing;

insert into public.personas (id, nombre, rol, centro_id, telefono)
values ('00000000-0000-4000-a000-000000000002', 'Administración de pruebas', 'administracion', null, '+34 600 000 000')
on conflict (id) do nothing;

insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
select '00000000-0000-4000-a000-000000000001', d, t.turno, t.inicio::time, t.fin::time
from generate_series(1, 5) d,
     (values ('manana', '08:30', '13:00'), ('tarde', '15:30', '18:30')) t(turno, inicio, fin)
where not (d = 5 and t.turno = 'tarde')
on conflict (persona_id, dia_semana, turno) do nothing;

-- Desde el 03/11/2026 los cierres del operario ficticio se generan pero no se
-- envían por correo (el propietario ya habrá visto el formato; Tarea 5).
insert into public.configuracion (clave, centro_id, valor)
values ('cierres_sin_correo', null, '[{"persona": "00000000-0000-4000-a000-000000000001", "desde": "2026-11-03"}]')
on conflict (clave, centro_id) do update set valor = excluded.valor;
