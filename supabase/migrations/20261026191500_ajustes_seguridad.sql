-- Tarea 3 · Ajustes de la revisión de seguridad y rendimiento de Supabase
-- 1. pg_net en el esquema «extensions», no en «public» (aviso extension_in_public).
--    No admite cambiar de esquema: se quita y se vuelve a crear. Solo se pierden
--    las respuestas HTTP guardadas de las pruebas (net._http_response).
-- 2. Política explícita en motor.solicitudes_servidor: ningún usuario la ve; solo
--    la usan las funciones internas (aviso rls_enabled_no_policy).
-- 3. Índices para dos claves foráneas sin índice.

drop extension if exists pg_net;
create extension pg_net with schema extensions;

create policy nadie on motor.solicitudes_servidor for all to authenticated, anon
  using (false) with check (false);

create index on motor.solicitudes_servidor (persona_id);
create index on public.configuracion (centro_id);
