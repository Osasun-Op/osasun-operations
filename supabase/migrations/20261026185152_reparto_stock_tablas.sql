-- Tarea 3 · Tablas de reparto y stock (MODELO_DATOS.md v0.2 §3.7, §3.8, §3.15)
-- lecturas_sheets, repartos, reparto_lineas y tarea_elementos. RLS y solo
-- lectura, como el resto: las escriben las funciones del servidor.

-- Cada lectura de STOCK OSASUN-CLAUDE, ya interpretada ------------------------
create table public.lecturas_sheets (
  id          uuid primary key default gen_random_uuid(),
  leido_en    timestamptz not null default now(),
  motivo      text not null check (motivo in ('reparto', 'envio', 'stock')),
  persona_id  uuid references public.personas (id),
  correcto    boolean not null,
  error       text,
  datos       jsonb not null default '{}'
);
create index on public.lecturas_sheets (persona_id);

-- Texto pegado del reparto o del envío ----------------------------------------
create table public.repartos (
  id              uuid primary key default gen_random_uuid(),
  jornada_id      uuid not null references public.jornadas (id) on delete cascade,
  tipo            text not null check (tipo in ('reparto', 'envio')),
  texto_original  text not null,
  huella          text not null,
  fecha_en_texto  date,
  sale            text check (sale in ('operario', 'administracion')),
  estado          text not null check (estado in ('con_errores', 'aceptado', 'sustituido')),
  sustituye_a     uuid references public.repartos (id),
  lectura_id      uuid references public.lecturas_sheets (id),
  resultado       jsonb not null default '{}',
  pegado_por      uuid references public.personas (id),
  pegado_en       timestamptz not null default now()
);
-- Un solo reparto (y un solo envío) aceptado por jornada; el anterior queda «sustituido».
create unique index repartos_uno_aceptado on public.repartos (jornada_id, tipo) where estado = 'aceptado';
create index on public.repartos (jornada_id);
create index on public.repartos (sustituye_a);
create index on public.repartos (lectura_id);
create index on public.repartos (pegado_por);

create table public.reparto_lineas (
  id          uuid primary key default gen_random_uuid(),
  reparto_id  uuid not null references public.repartos (id) on delete cascade,
  num_linea   integer not null,
  texto       text not null,
  clase       text not null check (clase in ('cabecera', 'sale', 'tienda', 'producto', 'vacia', 'no_reconocida')),
  destino_id  uuid references public.centros_trabajo (id),
  cantidad    integer,
  producto    text,
  formato     text,
  error       text,
  mensaje     text,
  unique (reparto_id, num_linea)
);
create index on public.reparto_lineas (destino_id);

alter table public.tareas add column reparto_id uuid references public.repartos (id);
create index on public.tareas (reparto_id);

-- Elementos de una tarea: referencias a producir y cajas de cada bolsa -------
-- «lote» separa listas que conviven en una tarea: el reparto o el envío, o el
-- turno en la lista de stock (que se recalcula cada turno).
create table public.tarea_elementos (
  id              uuid primary key default gen_random_uuid(),
  tarea_id        uuid not null references public.tareas (id) on delete cascade,
  tipo            text not null check (tipo in ('referencia_produccion', 'caja_bolsa')),
  lote            text not null default '',
  producto        text not null,
  formato         text not null default '',
  categoria       text,
  destino_id      uuid references public.centros_trabajo (id),
  cantidad        integer not null check (cantidad >= 0),
  cantidad_hecha  integer not null default 0 check (cantidad_hecha >= 0),
  motivo          text,
  orden_sugerido  integer not null default 0,
  calculo         jsonb not null default '{}',
  estado          text not null default 'pendiente' check (estado in ('pendiente', 'en_curso', 'hecho')),
  iniciado_en     timestamptz,
  terminado_en    timestamptz,
  unique nulls not distinct (tarea_id, tipo, lote, destino_id, producto, formato)
);
-- Una sola referencia en curso por tarea.
create unique index tarea_elementos_una_en_curso on public.tarea_elementos (tarea_id)
  where estado = 'en_curso' and tipo = 'referencia_produccion';
create index on public.tarea_elementos (destino_id);

-- Permisos ----------------------------------------------------------------------
revoke all on public.lecturas_sheets, public.repartos, public.reparto_lineas, public.tarea_elementos
  from anon, authenticated;
grant select on public.lecturas_sheets, public.repartos, public.reparto_lineas, public.tarea_elementos
  to authenticated;

alter table public.lecturas_sheets enable row level security;
alter table public.repartos        enable row level security;
alter table public.reparto_lineas  enable row level security;
alter table public.tarea_elementos enable row level security;

create policy lectura on public.lecturas_sheets for select to authenticated
  using ((select motor.es_admin()));

create policy lectura on public.repartos for select to authenticated
  using (
    (select motor.es_admin())
    or jornada_id in (select j.id from public.jornadas j where j.persona_id = (select auth.uid()))
  );

create policy lectura on public.reparto_lineas for select to authenticated
  using (
    (select motor.es_admin())
    or reparto_id in (select r.id from public.repartos r
                      join public.jornadas j on j.id = r.jornada_id
                      where j.persona_id = (select auth.uid()))
  );

create policy lectura on public.tarea_elementos for select to authenticated
  using (
    (select motor.es_admin())
    or tarea_id in (select t.id from public.tareas t
                    join public.jornadas j on j.id = t.jornada_id
                    where j.persona_id = (select auth.uid()))
  );

-- Configuración de la lectura y del cálculo -------------------------------------
insert into public.configuracion (clave, centro_id, valor) values
  ('sheets_documento_id', null, '"1nPhB7U6FoJcYybChUcGOI3mz-yJAv8NkT3uINuQ6qao"'),
  ('sheets_pestanas', null, '{"principal": "PRINCIPAL", "conteo": "CONTEO DE CAJAS TOTAL", "almacen": "ALMACEN"}'),
  ('stock_objetivo_pct', null, '35'),
  ('stock_excluidos', null,
   '[{"producto": "MINIBUDS MIX", "formato": "10g", "motivo": "Minis: fuera de la regla del +35 %"},
     {"producto": "VAPER", "formato": "", "motivo": "Vapers: los rige R7"}]');
