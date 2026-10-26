-- Tarea 2 · Estructura base
-- Tablas: centros_trabajo, personas, horarios, plantillas_tarea, configuracion,
-- jornadas, tareas y registro_eventos (MODELO_DATOS.md v0.2).
-- Los esquemas «motor» (lógica interna) y «prueba» (solo entorno de pruebas)
-- no se publican en la API.

create schema if not exists motor;
create schema if not exists prueba;

-- Centros de trabajo y destinos del reparto ---------------------------------
create table public.centros_trabajo (
  id                uuid primary key default gen_random_uuid(),
  codigo            text not null unique,
  nombre            text not null,
  tipo              text not null check (tipo in ('almacen', 'tienda', 'destino')),
  nombre_en_sheets  text,
  alias             text[] not null default '{}',
  activo            boolean not null default true
);
comment on table public.centros_trabajo is 'Almacén, tiendas y destinos del reparto/envío. El almacén es un centro más.';

-- Personas (una por usuario de Supabase Auth) -------------------------------
create table public.personas (
  id         uuid primary key references auth.users (id) on delete cascade,
  nombre     text not null,
  rol        text not null check (rol in ('administracion', 'operario')),
  centro_id  uuid references public.centros_trabajo (id),
  telefono   text,
  activo     boolean not null default true
);
create index on public.personas (centro_id);

-- Turnos de cada persona por día de la semana (1 = lunes) -------------------
create table public.horarios (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references public.personas (id) on delete cascade,
  dia_semana   smallint not null check (dia_semana between 1 and 7),
  turno        text not null check (turno in ('manana', 'tarde')),
  hora_inicio  time not null,
  hora_fin     time not null,
  check (hora_fin > hora_inicio),
  unique (persona_id, dia_semana, turno)
);

-- Plantillas de tarea (el mapa semanal como configuración) -----------------
create table public.plantillas_tarea (
  id               uuid primary key default gen_random_uuid(),
  centro_id        uuid not null references public.centros_trabajo (id),
  codigo           text not null,
  titulo           text not null,
  porque           text,
  programacion     text not null check (programacion in ('con_hora', 'dia_semana', 'condicionada', 'cola_libre')),
  dias_semana      smallint[] not null default '{}',
  turno            text check (turno in ('manana', 'tarde')),
  hora_inicio      time,
  hora_limite      time,
  duracion_min     integer check (duracion_min > 0),
  condicion        text check (condicion in (
                     'sale_operario', 'sale_administracion', 'hay_envio', 'no_hay_envio',
                     'reparto_pegado', 'envio_pegado',
                     'llega_mercancia', 'pedido_cliente', 'no_quedan_vapers')),
  requiere_codigo  text,
  contenido        text not null default 'simple'
                     check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento')),
  obligatoria      boolean not null default false,
  prioridad_cola   text check (prioridad_cola in ('A', 'C', 'D')),
  no_terminada     text not null default 'nada'
                     check (no_terminada in ('recalcular', 'sigue_abierta', 'arrastrar', 'nada')),
  modo             text not null default 'autonoma' check (modo in ('autonoma', 'necesita_aprobacion')),
  orden            integer not null default 100,
  activa           boolean not null default true,
  unique (centro_id, codigo),
  check (programacion <> 'con_hora' or hora_inicio is not null),
  check (programacion <> 'cola_libre' or prioridad_cola is not null)
);

-- Configuración ajustable sin código ----------------------------------------
create table public.configuracion (
  id         uuid primary key default gen_random_uuid(),
  clave      text not null,
  centro_id  uuid references public.centros_trabajo (id),
  valor      jsonb not null,
  unique nulls not distinct (clave, centro_id)
);

-- Jornadas: un día de trabajo de una persona --------------------------------
create table public.jornadas (
  id                    uuid primary key default gen_random_uuid(),
  persona_id            uuid not null references public.personas (id),
  centro_id             uuid not null references public.centros_trabajo (id),
  fecha                 date not null,
  sale                  text check (sale in ('operario', 'administracion')),
  hay_envio             boolean not null default false,
  envio_dia_siguiente   boolean not null default false,
  estado                text not null default 'abierta' check (estado in ('abierta', 'cerrada')),
  generada_en           timestamptz not null default now(),
  unique (persona_id, fecha)
);
create index on public.jornadas (centro_id);

-- Tareas del día -----------------------------------------------------------
create table public.tareas (
  id                      uuid primary key default gen_random_uuid(),
  jornada_id              uuid not null references public.jornadas (id) on delete cascade,
  clave                   text not null,
  origen                  text not null check (origen in ('plantilla', 'administracion', 'reparto', 'evento', 'problema')),
  plantilla_id            uuid references public.plantillas_tarea (id),
  titulo                  text not null,
  porque                  text,
  contenido               text not null default 'simple'
                            check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento')),
  obligatoria             boolean not null default false,
  prioridad_cola          text check (prioridad_cola in ('A', 'C', 'D')),
  condicion               text,
  requiere_clave          text,
  disponible_desde        timestamptz not null,
  hora_programada         timestamptz,
  hora_limite             timestamptz,
  urgente                 boolean not null default false,
  duracion_min            integer check (duracion_min > 0),
  no_terminada            text not null default 'nada'
                            check (no_terminada in ('recalcular', 'sigue_abierta', 'arrastrar', 'nada')),
  orden                   integer not null default 100,
  estado                  text not null default 'pendiente'
                            check (estado in ('pendiente', 'en_curso', 'hecha', 'bloqueada', 'arrastrada', 'cancelada')),
  retirada_por_condicion  boolean not null default false,
  iniciada_en             timestamptz,
  terminada_en            timestamptz,
  resultado               text,
  motivo_no_hecha         text,
  tarea_origen_id         uuid references public.tareas (id),
  creada_por              uuid references public.personas (id),
  id_cliente              uuid unique,
  creada_en               timestamptz not null default now(),
  unique (jornada_id, clave)
);
-- Una sola tarea en curso por jornada (dos pestañas no pueden tener dos activas).
create unique index tareas_una_en_curso on public.tareas (jornada_id) where estado = 'en_curso';
create index on public.tareas (plantilla_id);
create index on public.tareas (tarea_origen_id);
create index on public.tareas (creada_por);

-- Registro de eventos (solo se añade) ---------------------------------------
create table public.registro_eventos (
  id           bigint generated always as identity primary key,
  ocurrido_en  timestamptz not null default now(),
  persona_id   uuid references public.personas (id),
  jornada_id   uuid references public.jornadas (id) on delete cascade,
  tarea_id     uuid references public.tareas (id) on delete cascade,
  tipo         text not null,
  datos        jsonb not null default '{}'
);
create index on public.registro_eventos (jornada_id);
create index on public.registro_eventos (tarea_id);
create index on public.registro_eventos (persona_id);
