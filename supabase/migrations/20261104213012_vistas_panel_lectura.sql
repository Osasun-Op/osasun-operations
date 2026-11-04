-- Tarea 33 · vistas_panel con su política de lectura, como las demás tablas (aviso «RLS Enabled No Policy» de
-- Supabase): cada persona de Administración lee solo lo suyo. Escribir, solo con marcar_tienda_vista(). Solo en pruebas.
--
-- Deshacer: borrar la política lectura de public.vistas_panel y quitar el select a authenticated.

grant select on public.vistas_panel to authenticated;
create policy lectura on public.vistas_panel for select to authenticated
  using ((select motor.es_admin()) and persona_id = (select auth.uid()));
