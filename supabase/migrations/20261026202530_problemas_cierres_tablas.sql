-- Tarea 4 · Tablas: problemas, incidencias, eventos_jornada y cierres
-- (MODELO_DATOS.md §3.9–3.12). RLS y solo lectura; las escriben las funciones.

create table public.problemas (
  id                  uuid primary key default gen_random_uuid(),
  jornada_id          uuid not null references public.jornadas (id) on delete cascade,
  tarea_id            uuid not null references public.tareas (id) on delete cascade,
  persona_id          uuid not null references public.personas (id),
  tipo                text not null check (tipo in ('falta_material', 'no_encuentro', 'no_se_hacerlo', 'no_funciona', 'otro')),
  descripcion         text not null,
  estado              text not null default 'abierto' check (estado in ('abierto', 'sin_respuesta', 'resuelto')),
  abierto_en          timestamptz not null,
  llamada_en          timestamptz,
  llamadas            integer not null default 0,
  whatsapp_en         timestamptz,
  proxima_llamada_en  timestamptz,
  solucion            text,
  resuelto_en         timestamptz,
  resuelto_por        uuid references public.personas (id),
  id_cliente          uuid unique
);
-- Un solo problema abierto por tarea.
create unique index problemas_uno_abierto on public.problemas (tarea_id) where estado <> 'resuelto';
create index on public.problemas (jornada_id);
create index on public.problemas (persona_id);
create index on public.problemas (resuelto_por);

create table public.incidencias (
  id            uuid primary key default gen_random_uuid(),
  jornada_id    uuid not null references public.jornadas (id) on delete cascade,
  persona_id    uuid not null references public.personas (id),
  tarea_id      uuid references public.tareas (id) on delete set null,
  descripcion   text not null,
  iniciada_en   timestamptz not null,
  terminada_en  timestamptz,
  id_cliente    uuid unique
);
-- Una sola incidencia abierta por persona.
create unique index incidencias_una_abierta on public.incidencias (persona_id) where terminada_en is null;
create index on public.incidencias (jornada_id);
create index on public.incidencias (tarea_id);

create table public.eventos_jornada (
  id              uuid primary key default gen_random_uuid(),
  jornada_id      uuid not null references public.jornadas (id) on delete cascade,
  tipo            text not null check (tipo in ('llega_mercancia', 'pedido_cliente', 'no_quedan_vapers')),
  detalle         text,
  tarea_id        uuid references public.tareas (id) on delete set null,
  registrado_por  uuid not null references public.personas (id),
  registrado_en   timestamptz not null,
  id_cliente      uuid unique
);
create index on public.eventos_jornada (jornada_id);
create index on public.eventos_jornada (tarea_id);
create index on public.eventos_jornada (registrado_por);

create table public.cierres (
  id                  uuid primary key default gen_random_uuid(),
  jornada_id          uuid not null references public.jornadas (id) on delete cascade,
  turno               text not null check (turno in ('manana', 'tarde')),
  contenido           jsonb not null,
  generado_en         timestamptz not null,
  envio_reclamado_en  timestamptz,
  enviado_en          timestamptz,
  canal               text,
  error_envio         text,
  unique (jornada_id, turno)
);

-- Jornadas creadas antes de su día (tareas de Administración para otro día):
-- el arrastre se hace al llegar el día, no al crearla.
alter table public.jornadas add column arrastre_hecho boolean not null default true;

-- Permisos ----------------------------------------------------------------------
revoke all on public.problemas, public.incidencias, public.eventos_jornada, public.cierres from anon, authenticated;
grant select on public.problemas, public.incidencias, public.eventos_jornada, public.cierres to authenticated;

alter table public.problemas       enable row level security;
alter table public.incidencias     enable row level security;
alter table public.eventos_jornada enable row level security;
alter table public.cierres         enable row level security;

create policy lectura on public.problemas for select to authenticated
  using ((select motor.es_admin())
         or jornada_id in (select j.id from public.jornadas j where j.persona_id = (select auth.uid())));
create policy lectura on public.incidencias for select to authenticated
  using ((select motor.es_admin())
         or jornada_id in (select j.id from public.jornadas j where j.persona_id = (select auth.uid())));
create policy lectura on public.eventos_jornada for select to authenticated
  using ((select motor.es_admin())
         or jornada_id in (select j.id from public.jornadas j where j.persona_id = (select auth.uid())));
-- Los cierres son solo de Administración.
create policy lectura on public.cierres for select to authenticated
  using ((select motor.es_admin()));

insert into public.configuracion (clave, centro_id, valor) values
  ('problema_minutos_reaparicion', null, '30'),
  ('correo_remitente', null, '"Osasun Operations <onboarding@resend.dev>"');
-- El correo de destino de Administración (correo_administracion) se guarda solo
-- en la configuración de cada entorno, nunca en el repositorio.
