-- Tarea 28 · Tiendas, segunda parte: la bolsa, por dónde va el reparto, el cierre de caja, las
-- muestras y el material (ESTADO_DEL_SISTEMA.md E2-8; AGENTE_COORDINADOR.md, bloque 1, puntos 7 a
-- 10, 12 a 14, 18, 24, 29 a 31). Solo en pruebas: producción espera (AGENTE_BASE_DE_DATOS.md §4).
-- Sigue la Tarea 27 y reutiliza el reparto del día (sus líneas, sus peticiones y sus pedidos de
-- tienda), la lista del día de la tienda con sus puntos y la activación por tienda. Lo del
-- almacén no cambia: el operario prepara, hace las bolsas y sale como siempre, sin pasos nuevos.
--   1. «Recibe la bolsa del reparto» (tiendas con parada): sale cuando sale el reparto, con lo que
--      trae la bolsa y el efectivo del último cierre de caja (`bolsas_tienda`).
--   2. «Coloca y apunta la reposición»: después de «Recibe la bolsa»; «Falta algo» abre una
--      incidencia para Administración (opción `falta_reposicion`).
--   3. Por dónde va el reparto, en tienda_hoy(): la salida y las bolsas recibidas, en el orden de
--      las paradas. La salida: la de «Salida del reparto» del operario; si sale Administración,
--      la hora de salida con las bolsas listas.
--   4. Cierre de caja en el «Cierre del día» (`cierres_caja`): Z, nº de ventas, efectivo y Glovo.
--   5. «Revisa las muestras» (jueves por la mañana; Bilbao alterna) y pedir material: peticiones
--      de la tienda (`peticiones_tienda`) que salen ya puestas al preparar el siguiente reparto (o
--      envío) de esa tienda y quedan atendidas al guardarlo. Única línea que cambia del almacén:
--      servidor_guardar_peticiones las da por atendidas (no cambia lo que hace con las bolsas).
--
-- Deshacer: borrar las funciones nuevas (motor.*bolsa*, motor.salida_reparto_en, motor.paradas_bolsas,
-- motor.jornada_almacen, motor.punto_especial, motor.hacer_punto, motor.euros, motor.efectivo_anterior,
-- motor.crear_reposicion, motor.*peticion*, motor.destino_peticion, motor.productos_tienda_de,
-- motor.revisar_muestras_de, motor.pedir_material_de, motor.entregar_efectivo_de, motor.cerrar_caja_de,
-- motor.apuntar_reposicion_de, motor.cierres_caja_de, motor.incidencias_tiendas_de,
-- motor.cerrar_incidencia_tienda_de, motor.seguimiento_reparto_json y sus motor.api_* y public.*);
-- las tablas bolsas_tienda, cierres_caja y peticiones_tienda; las plantillas recibe_bolsa,
-- reposicion y revisa_muestras y las claves peticiones_por_envio y pedir_material; los puntos de
-- cierre_dia como estaban; volver a crear motor.tarea_tienda_json, motor.tienda_hoy_de y
-- motor.marcar_punto_de (20261102190536) y public.servidor_guardar_peticiones (20261028130000)
-- como estaban; y los checks de contenido e incidencias.opcion.

-- ---------------------------------------------------------------------------
-- 1. Contenidos y opción nuevos (solo se añaden valores)
-- ---------------------------------------------------------------------------
alter table public.plantillas_tarea drop constraint plantillas_tarea_contenido_check;
alter table public.plantillas_tarea add constraint plantillas_tarea_contenido_check
  check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento', 'puntos', 'video',
                       'reposicion', 'muestras'));
alter table public.tareas drop constraint tareas_contenido_check;
alter table public.tareas add constraint tareas_contenido_check
  check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento', 'puntos', 'video',
                       'reposicion', 'muestras'));
alter table public.incidencias drop constraint incidencias_opcion_check;
alter table public.incidencias add constraint incidencias_opcion_check
  check (opcion in ('comprar', 'varios', 'aviso', 'llega_mercancia', 'pedido_cliente', 'pedir_comprar',
                    'recogida_nacex', 'corregir', 'falta_reposicion'));

-- ---------------------------------------------------------------------------
-- 2. Tablas nuevas
-- ---------------------------------------------------------------------------
create table public.bolsas_tienda (
  id                 uuid primary key default gen_random_uuid(),
  centro_id          uuid not null references public.centros_trabajo (id),
  fecha              date not null,
  reparto_id         uuid not null references public.repartos (id),
  tarea_id           uuid not null references public.tareas (id),
  salida_en          timestamptz not null,
  efectivo_esperado  numeric(10, 2),
  efectivo_de        date,
  recibida_en        timestamptz,
  recibida_por       text,
  recibida_persona   uuid references public.personas_tienda (id),
  efectivo_entregado numeric(10, 2),
  efectivo_motivo    text,
  efectivo_en        timestamptz,
  reposicion         text check (reposicion in ('bien', 'falta')),
  reposicion_en      timestamptz,
  reposicion_por     text,
  faltan             jsonb,
  incidencia_id      uuid references public.incidencias (id),
  unique (centro_id, fecha)
);
comment on table public.bolsas_tienda is 'La bolsa del reparto en cada tienda: cuándo salió, cuándo se recibió, el efectivo de ayer y la reposición.';
create index bolsas_tienda_reparto_id_idx on public.bolsas_tienda (reparto_id);
create index bolsas_tienda_tarea_id_idx on public.bolsas_tienda (tarea_id);
create index bolsas_tienda_recibida_persona_idx on public.bolsas_tienda (recibida_persona);
create index bolsas_tienda_incidencia_id_idx on public.bolsas_tienda (incidencia_id);

create table public.cierres_caja (
  id                uuid primary key default gen_random_uuid(),
  centro_id         uuid not null references public.centros_trabajo (id),
  fecha             date not null,
  z                 numeric(10, 2) not null check (z >= 0),
  ventas            integer not null check (ventas >= 0),
  efectivo          numeric(10, 2) not null check (efectivo >= 0),
  glovo             numeric(10, 2) not null check (glovo >= 0),
  tarea_id          uuid references public.tareas (id),
  persona_tienda_id uuid references public.personas_tienda (id),
  nombre            text,
  guardado_en       timestamptz not null default now(),
  unique (centro_id, fecha)
);
comment on table public.cierres_caja is 'Cierre de caja de cada tienda y día (Z, nº de ventas, efectivo y Glovo). El efectivo es el de la bolsa del día siguiente.';
create index cierres_caja_tarea_id_idx on public.cierres_caja (tarea_id);
create index cierres_caja_persona_tienda_id_idx on public.cierres_caja (persona_tienda_id);

create table public.peticiones_tienda (
  id                uuid primary key default gen_random_uuid(),
  centro_id         uuid not null references public.centros_trabajo (id),
  tipo              text not null check (tipo in ('muestra', 'material')),
  detalle           text not null,
  texto             text not null check (char_length(texto) <= 120),
  producto          text,
  formato           text,
  cantidad          integer,
  tarea_id          uuid references public.tareas (id),
  id_cliente        uuid unique,
  persona_tienda_id uuid references public.personas_tienda (id),
  nombre            text,
  creada_en         timestamptz not null default now(),
  estado            text not null default 'pendiente' check (estado in ('pendiente', 'atendida', 'descartada')),
  reparto_id        uuid references public.repartos (id),
  atendida_en       timestamptz,
  motivo            text,
  descartada_por    uuid references public.personas (id)
);
comment on table public.peticiones_tienda is 'Muestras y material que pide una tienda: van como peticiones especiales en su siguiente reparto o envío.';
create index peticiones_tienda_centro_id_idx on public.peticiones_tienda (centro_id);
create index peticiones_tienda_tarea_id_idx on public.peticiones_tienda (tarea_id);
create index peticiones_tienda_persona_tienda_id_idx on public.peticiones_tienda (persona_tienda_id);
create index peticiones_tienda_reparto_id_idx on public.peticiones_tienda (reparto_id);
create index peticiones_tienda_descartada_por_idx on public.peticiones_tienda (descartada_por);

revoke all on public.bolsas_tienda, public.cierres_caja, public.peticiones_tienda from anon, authenticated;
grant select on public.bolsas_tienda, public.cierres_caja, public.peticiones_tienda to authenticated;
alter table public.bolsas_tienda enable row level security;
alter table public.cierres_caja enable row level security;
alter table public.peticiones_tienda enable row level security;
create policy lectura on public.bolsas_tienda for select to authenticated
  using ((select motor.es_admin()) or ((select motor.es_tienda()) and centro_id = (select motor.mi_centro())));
create policy lectura on public.cierres_caja for select to authenticated
  using ((select motor.es_admin()) or ((select motor.es_tienda()) and centro_id = (select motor.mi_centro())));
create policy lectura on public.peticiones_tienda for select to authenticated
  using ((select motor.es_admin()) or ((select motor.es_tienda()) and centro_id = (select motor.mi_centro())));

-- ---------------------------------------------------------------------------
-- 3. Configuración y plantillas de tienda
-- ---------------------------------------------------------------------------
-- Donosti y Rentería no van en el reparto: les llega por el envío a Gipuzkoa (ESTADO §5, destinos).
insert into public.configuracion (clave, centro_id, valor)
values ('peticiones_por_envio', null, '{"DONOSTI": "GIPUZKOA", "RENTERIA": "GIPUZKOA"}');
-- Pedir material desde la tablet: se activa por tienda (franquicias, no en esta tarea).
insert into public.configuracion (clave, centro_id, valor)
select 'pedir_material', c.id, to_jsonb(c.codigo not in ('DONOSTI', 'RENTERIA'))
  from public.centros_trabajo c where c.tipo = 'tienda';

-- «Recibe la bolsa» y «Coloca y apunta la reposición» no salen con el día (sin días): las crea el
-- motor cuando sale el reparto y cuando se recibe la bolsa. «Revisa las muestras», el jueves por
-- la mañana (Bilbao alterna), también en las franquicias.
insert into public.plantillas_tarea (centro_id, codigo, titulo, porque, programacion, dias_semana, turno,
                                     hora_desde, minutos_desde, alterna_turno, contenido, puntos, no_terminada, orden, activa)
select c.id, x.codigo, x.titulo, x.porque, x.programacion, x.dias, x.turno, x.hora_desde, 0, x.alterna,
       x.contenido, x.puntos, 'nada', x.orden,
       x.codigo = 'revisa_muestras' or c.codigo not in ('DONOSTI', 'RENTERIA')
  from public.centros_trabajo c,
  (values
    ('recibe_bolsa', 'Recibe la bolsa del reparto', 'Para que conste a qué hora llega la bolsa y el efectivo de ayer.',
     'condicionada', '{}'::smallint[], null, null, false, 'puntos',
     array['Bolsa recibida', 'Bolsa de ayer entregada con el efectivo'], 15),
    ('reposicion', 'Coloca y apunta la reposición',
     'Mete la reposición en la plantilla y comprueba que ha llegado todo lo de la lista.',
     'condicionada', '{}'::smallint[], null, null, false, 'reposicion', '{}'::text[], 16),
    ('revisa_muestras', 'Revisa las muestras',
     'Comprueba que las muestras están en buen estado y elige qué hay que traer nuevo: irá en el siguiente reparto (o envío).',
     'dia_semana', '{4}'::smallint[], 'manana', 'inicio', true, 'muestras', '{}'::text[], 55)
  ) x(codigo, titulo, porque, programacion, dias, turno, hora_desde, alterna, contenido, puntos, orden)
 where c.tipo = 'tienda';

-- Cierre del día: el cierre de caja, el primero de los puntos de dinero.
update public.plantillas_tarea p
   set puntos = array['Ventas del día en la plantilla (todo en verde)', 'Suelo fregado',
                      'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo',
                      'Efectivo contado y en la bolsa para mañana', 'Incidencias de la tarde registradas']
  from public.centros_trabajo c
 where c.id = p.centro_id and c.tipo = 'tienda' and p.codigo = 'cierre_dia';

-- ---------------------------------------------------------------------------
-- 4. Ayudas
-- ---------------------------------------------------------------------------
create or replace function motor.euros(p_cantidad numeric)
returns text language sql immutable set search_path = '' as $$
  select replace(to_char(p_cantidad, 'FM999999990.00'), '.', ',') || ' €'
$$;

-- Los puntos que piden algo más que un toque.
create or replace function motor.punto_especial(e public.tarea_elementos)
returns text language sql immutable set search_path = '' as $$
  select coalesce(e.calculo ->> 'especial',
                  case when e.producto = 'Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo' then 'cierre_caja' end)
$$;

-- La jornada del almacén de ese día (la del operario por defecto), sin crearla.
create or replace function motor.jornada_almacen(p_fecha date)
returns uuid language sql stable set search_path = '' as $$
  select j.id from public.jornadas j where j.persona_id = motor.operario_por_defecto() and j.fecha = p_fecha
$$;

-- Cuándo ha salido el reparto, sin que quien reparte haga nada nuevo: si sale el operario, al
-- empezar su «Salida del reparto»; si sale Administración, a la hora de salida con las bolsas listas.
create or replace function motor.salida_reparto_en(p_jornada uuid, p_ahora timestamptz)
returns timestamptz language sql stable set search_path = '' as $$
  select case
           when s.id is not null and s.estado in ('en_curso', 'hecha')
                and coalesce(s.iniciada_en, s.terminada_en) <= p_ahora
             then coalesce(s.iniciada_en, s.terminada_en)
           when j.sale = 'administracion' and b.estado = 'hecha'
                and greatest(b.terminada_en, coalesce(b.hora_limite, b.terminada_en)) <= p_ahora
             then greatest(b.terminada_en, coalesce(b.hora_limite, b.terminada_en))
         end
    from public.jornadas j
    left join lateral (select * from public.tareas t where t.jornada_id = j.id and t.clave = 'salida_reparto'
                          and not t.retirada_por_condicion limit 1) s on true
    left join lateral (select * from public.tareas t where t.jornada_id = j.id and t.clave = 'bolsas' limit 1) b on true
   where j.id = p_jornada
$$;

-- Las paradas del reparto: las tiendas que llevan algo (productos, peticiones o pedidos de
-- cliente), en el orden de las paradas (configuración destinos_reparto).
create or replace function motor.paradas_bolsas(p_reparto uuid)
returns table (centro_id uuid, codigo text, nombre text, orden integer)
language sql stable set search_path = '' as $$
  with d as (
    select (x ->> 'destino_id')::uuid as id
      from jsonb_array_elements(motor.reparto_detalle_json(p_reparto, null) -> 'lineas') x
    union
    select (x ->> 'destino_id')::uuid from public.repartos r, jsonb_array_elements(r.peticiones) x where r.id = p_reparto
    union
    select p.destino_id from public.pedidos_cliente p where p.reparto_id = p_reparto and p.entrega = 'tienda'),
  o as (
    select a.codigo, a.n from public.configuracion k,
           jsonb_array_elements_text(k.valor -> 'reparto') with ordinality a(codigo, n)
     where k.clave = 'destinos_reparto' and k.centro_id is null)
  select c.id, c.codigo, c.nombre, (row_number() over (order by coalesce(o.n, 99), c.nombre))::int
    from d join public.centros_trabajo c on c.id = d.id left join o on o.codigo = c.codigo
$$;

-- Lo que trae la bolsa de una tienda en un reparto. Cada cosa con su `clave` (para «Falta algo»).
create or replace function motor.bolsa_contenido(p_reparto uuid, p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  with det as (select motor.reparto_detalle_json(p_reparto, null) as d)
  select jsonb_build_object(
    'productos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'producto:' || (x ->> 'producto') || '|' || (x ->> 'formato'),
                                          'producto', x ->> 'producto', 'formato', x ->> 'formato',
                                          'cantidad', (x ->> 'cantidad')::int)
                       || case when x ? 'de' then jsonb_build_object('de', x -> 'de') else '{}'::jsonb end
                       order by n)
        from det, jsonb_array_elements(det.d -> 'lineas') with ordinality a(x, n)
       where (x ->> 'destino_id')::uuid = p_centro), '[]'::jsonb),
    'peticiones', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'peticion:' || (x ->> 'texto'), 'texto', x ->> 'texto') order by n)
        from det, jsonb_array_elements(det.d -> 'peticiones') with ordinality a(x, n)
       where (x ->> 'destino_id')::uuid = p_centro), '[]'::jsonb),
    'pedidos', coalesce((
      select jsonb_agg(jsonb_build_object('clave', 'pedido:' || p.id, 'pedido_id', p.id, 'cliente', p.cliente,
                                          'lineas', p.lineas) order by p.registrado_en)
        from public.pedidos_cliente p
       where p.reparto_id = p_reparto and p.entrega = 'tienda' and p.destino_id = p_centro), '[]'::jsonb))
$$;

create or replace function motor.efectivo_anterior(p_centro uuid, p_fecha date)
returns table (efectivo numeric, fecha date) language sql stable set search_path = '' as $$
  select k.efectivo, k.fecha from public.cierres_caja k
   where k.centro_id = p_centro and k.fecha < p_fecha order by k.fecha desc limit 1
$$;

-- La bolsa de la tienda ese día, con lo que trae.
create or replace function motor.bolsa_tienda_json(p_centro uuid, p_fecha date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'reparto_id', b.reparto_id, 'fecha', b.fecha, 'salida', motor.hora_texto(b.salida_en),
    'recibida_a_las', motor.hora_texto(b.recibida_en), 'recibida_por', b.recibida_por,
    'efectivo', jsonb_build_object('esperado', b.efectivo_esperado, 'de_fecha', b.efectivo_de,
                                   'entregado', b.efectivo_entregado, 'motivo', b.efectivo_motivo),
    'reposicion', case when b.reposicion is not null then
      jsonb_build_object('resultado', b.reposicion, 'a_las', motor.hora_texto(b.reposicion_en), 'por', b.reposicion_por,
                         'faltan', coalesce(b.faltan, '[]'::jsonb), 'incidencia_id', b.incidencia_id) end)
    || motor.bolsa_contenido(b.reparto_id, b.centro_id)
  from public.bolsas_tienda b where b.centro_id = p_centro and b.fecha = p_fecha
$$;

-- Por dónde va el reparto, para una tienda con parada (null si hoy no tiene).
create or replace function motor.seguimiento_reparto_json(p_centro uuid, p_fecha date, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_alm uuid := motor.jornada_almacen(p_fecha);
  v_rep uuid;
  v_salida timestamptz;
  v_paradas jsonb;
  v_ultima jsonb;
  v_total integer;
begin
  select id into v_rep from public.repartos where jornada_id = v_alm and tipo = 'reparto' and estado = 'aceptado';
  if v_rep is null or not exists (select 1 from motor.paradas_bolsas(v_rep) where centro_id = p_centro) then
    return null;
  end if;
  v_salida := motor.salida_reparto_en(v_alm, p_ahora);
  select jsonb_agg(jsonb_build_object('tienda_id', x.centro_id, 'tienda', x.nombre, 'parada', x.orden,
                                      'pasado_a_las', motor.hora_texto(b.recibida_en)) order by x.orden),
         count(*)
    into v_paradas, v_total
    from motor.paradas_bolsas(v_rep) x
    left join public.bolsas_tienda b on b.centro_id = x.centro_id and b.fecha = p_fecha and b.recibida_en <= p_ahora;
  select jsonb_build_object('tienda', x.nombre, 'a_las', motor.hora_texto(b.recibida_en), 'parada', x.orden)
    into v_ultima
    from motor.paradas_bolsas(v_rep) x
    join public.bolsas_tienda b on b.centro_id = x.centro_id and b.fecha = p_fecha and b.recibida_en <= p_ahora
   order by b.recibida_en desc limit 1;
  return jsonb_build_object(
    'salido', v_salida is not null, 'salida', motor.hora_texto(v_salida),
    'paradas', v_paradas, 'total', v_total,
    'tu_parada', (select x.orden from motor.paradas_bolsas(v_rep) x where x.centro_id = p_centro),
    'ultima', v_ultima,
    'texto', case when v_salida is null then null
                  when v_ultima is null then 'Ha salido a las ' || motor.hora_texto(v_salida)
                  else 'Ha pasado por ' || (v_ultima ->> 'tienda') || ' a las ' || (v_ultima ->> 'a_las')
                       || ' (parada ' || (v_ultima ->> 'parada') || ' de ' || v_total || ')' end);
end;
$$;

-- Cuando sale el reparto, la tienda con parada tiene su «Recibe la bolsa» (una vez al día).
create or replace function motor.preparar_bolsa_tienda(p_persona uuid, p_jornada uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_plantilla uuid;
  v_alm uuid;
  v_rep uuid;
  v_salida timestamptz;
  v_tarea uuid;
  v_x numeric;
  v_xf date;
begin
  if p_jornada is null then
    return;
  end if;
  select * into j from public.jornadas where id = p_jornada;
  if exists (select 1 from public.bolsas_tienda where centro_id = j.centro_id and fecha = j.fecha) then
    return;
  end if;
  select id into v_plantilla from public.plantillas_tarea where centro_id = j.centro_id and codigo = 'recibe_bolsa' and activa;
  v_alm := motor.jornada_almacen(j.fecha);
  select id into v_rep from public.repartos where jornada_id = v_alm and tipo = 'reparto' and estado = 'aceptado';
  if v_plantilla is null or v_rep is null then
    return;
  end if;
  v_salida := motor.salida_reparto_en(v_alm, p_ahora);
  if v_salida is null or not exists (select 1 from motor.paradas_bolsas(v_rep) where centro_id = j.centro_id) then
    return;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bolsa_tienda:' || j.centro_id || ':' || j.fecha, 0));
  if exists (select 1 from public.bolsas_tienda where centro_id = j.centro_id and fecha = j.fecha) then
    return;
  end if;
  select a.efectivo, a.fecha into v_x, v_xf from motor.efectivo_anterior(j.centro_id, j.fecha) a;
  v_tarea := motor.insertar_desde_plantilla(j.id, v_plantilla, 'recibe_bolsa', 'reparto');
  if v_tarea is null then
    return;
  end if;
  update public.tareas
     set disponible_desde = v_salida,
         porque = 'El reparto ha salido a las ' || motor.hora_texto(v_salida) || '. ' || porque
   where id = v_tarea;
  update public.tarea_elementos e
     set calculo = e.calculo || case when e.orden_sugerido = 1 then '{"especial": "bolsa_recibida"}'::jsonb
                                     else jsonb_build_object('especial', 'efectivo', 'esperado', v_x, 'de_fecha', v_xf) end,
         producto = case when e.orden_sugerido = 1 then e.producto
                         when v_x is null then 'Bolsa de ayer entregada: di cuánto efectivo'
                         else 'Bolsa de ayer entregada con ' || motor.euros(v_x) || ' en efectivo' end
   where e.tarea_id = v_tarea and e.tipo = 'punto';
  insert into public.bolsas_tienda (centro_id, fecha, reparto_id, tarea_id, salida_en, efectivo_esperado, efectivo_de)
  values (j.centro_id, j.fecha, v_rep, v_tarea, v_salida, v_x, v_xf);
  perform motor.registrar('bolsa_en_camino', p_persona, j.id, v_tarea,
                          jsonb_build_object('reparto', v_rep, 'salida', v_salida, 'efectivo_esperado', v_x));
end;
$$;

-- Después de «Recibe la bolsa», «Coloca y apunta la reposición».
create or replace function motor.crear_reposicion(p_tarea_bolsa uuid, p_ahora timestamptz)
returns uuid language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_plantilla uuid;
  v_id uuid;
begin
  select jo.* into j from public.jornadas jo join public.tareas t on t.jornada_id = jo.id where t.id = p_tarea_bolsa;
  select id into v_plantilla from public.plantillas_tarea where centro_id = j.centro_id and codigo = 'reposicion' and activa;
  if v_plantilla is null then
    return null;
  end if;
  v_id := motor.insertar_desde_plantilla(j.id, v_plantilla, 'reposicion', 'reparto');
  update public.tareas set disponible_desde = p_ahora where id = v_id;
  return v_id;
end;
$$;

-- Marca un punto (con lo que haya apuntado, si pide algo). Con el último, la tarea queda hecha;
-- «Bolsa recibida» deja constancia de la hora (la ven las demás tiendas).
create or replace function motor.hacer_punto(p_persona uuid, p_elemento uuid, p_datos jsonb, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  t public.tareas;
  tt public.turnos_tienda;
begin
  select * into e from public.tarea_elementos where id = p_elemento;
  select * into t from public.tareas where id = e.tarea_id;
  tt := motor.en_turno_tienda(t.jornada_id);
  update public.tarea_elementos
     set estado = 'hecho', cantidad_hecha = cantidad, iniciado_en = coalesce(iniciado_en, p_ahora), terminado_en = p_ahora,
         calculo = calculo || jsonb_build_object('hecho_por', tt.nombre, 'persona_tienda', tt.persona_tienda_id)
                   || case when p_datos is not null then jsonb_build_object('datos', p_datos) else '{}'::jsonb end
   where id = e.id;
  update public.tareas set iniciada_en = coalesce(iniciada_en, p_ahora) where id = t.id;
  if motor.punto_especial(e) = 'bolsa_recibida' then
    update public.bolsas_tienda
       set recibida_en = p_ahora, recibida_por = tt.nombre, recibida_persona = tt.persona_tienda_id
     where tarea_id = t.id;
    perform motor.registrar('bolsa_recibida', p_persona, t.jornada_id, t.id,
                            jsonb_build_object('a_las', p_ahora, 'recibida_por', tt.nombre));
  end if;
  if not exists (select 1 from public.tarea_elementos where tarea_id = t.id and tipo = 'punto' and estado <> 'hecho') then
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', null, null, 'tarea_terminada', p_ahora);
    if t.clave = 'recibe_bolsa' then
      perform motor.crear_reposicion(t.id, p_ahora);
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Peticiones de la tienda (muestras y material) y el siguiente reparto o envío
-- ---------------------------------------------------------------------------
-- En qué reparto o envío van las peticiones de una tienda: la suya si está en destinos_reparto;
-- las franquicias, en el envío a Gipuzkoa (peticiones_por_envio), con el nombre de la tienda delante.
create or replace function motor.destino_peticion(p_centro uuid)
returns table (tipo text, destino_id uuid, prefijo text)
language sql stable set search_path = '' as $$
  with c as (select * from public.centros_trabajo where id = p_centro),
  dr as (select coalesce((select valor from public.configuracion where clave = 'destinos_reparto' and centro_id is null), '{}') as v),
  pe as (select coalesce((select valor from public.configuracion where clave = 'peticiones_por_envio' and centro_id is null), '{}') as v)
  select case when dr.v -> 'reparto' ? c.codigo then 'reparto'
              when dr.v -> 'envio' ? c.codigo or pe.v ? c.codigo then 'envio' end,
         case when dr.v -> 'reparto' ? c.codigo or dr.v -> 'envio' ? c.codigo then c.id
              else (select x.id from public.centros_trabajo x where x.codigo = pe.v ->> c.codigo) end,
         case when dr.v -> 'reparto' ? c.codigo or dr.v -> 'envio' ? c.codigo then '' else c.nombre || ' · ' end
    from c, dr, pe
$$;

create or replace function motor.peticion_tienda_json(p public.peticiones_tienda, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'tipo', p.tipo, 'detalle', p.detalle, 'texto', p.texto, 'estado', p.estado,
    'pedida_por', p.nombre, 'fecha', motor.fecha_local(p.creada_en), 'a_las', motor.hora_texto(p.creada_en),
    'estado_texto', case p.estado
      when 'pendiente' then 'Pendiente: irá en el siguiente ' || case d.tipo when 'envio' then 'envío' else 'reparto' end
      when 'atendida' then 'Va en el ' || case r.tipo when 'envio' then 'envío' else 'reparto' end || ' '
                           || case jr.fecha when motor.fecha_local(p_ahora) then 'de hoy'
                                            when motor.fecha_local(p_ahora) + 1 then 'de mañana'
                                            else 'del ' || to_char(jr.fecha, 'DD/MM') end
      else 'No va: ' || coalesce(p.motivo, 'lo ha quitado Administración') end)
  from (select 1) uno
  left join lateral motor.destino_peticion(p.centro_id) d on true
  left join public.repartos r on r.id = p.reparto_id
  left join public.jornadas jr on jr.id = r.jornada_id
$$;

-- Las de la tienda: las pendientes y las de la última semana.
create or replace function motor.peticiones_tienda_json(p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(motor.peticion_tienda_json(p, p_ahora) order by p.creada_en desc, p.id), '[]'::jsonb)
    from public.peticiones_tienda p
   where p.centro_id = p_centro
     and (p.estado = 'pendiente' or p.creada_en >= motor.en_local(motor.fecha_local(p_ahora) - 7, '00:00'))
$$;

-- Para preparar el reparto (o el envío): las pendientes de las tiendas que van en él, con la
-- línea que se pone en la casilla de peticiones especiales de su destino.
create or replace function motor.peticiones_pendientes_de(p_tipo text)
returns jsonb language sql stable set search_path = '' as $$
  with o as (
    select a.codigo, a.n from public.configuracion k,
           jsonb_array_elements_text(k.valor -> coalesce(p_tipo, 'reparto')) with ordinality a(codigo, n)
     where k.clave = 'destinos_reparto' and k.centro_id is null)
  select jsonb_build_object('peticiones', coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'destino_id', d.destino_id, 'destino', dc.nombre, 'tienda_id', p.centro_id, 'tienda', c.nombre,
           'tipo', p.tipo, 'texto', p.texto, 'detalle', p.detalle, 'pedida_por', p.nombre, 'creada_en', p.creada_en)
           order by coalesce(o.n, 99), c.nombre, p.creada_en), '[]'::jsonb))
    from public.peticiones_tienda p
    join public.centros_trabajo c on c.id = p.centro_id
    cross join lateral motor.destino_peticion(p.centro_id) d
    join public.centros_trabajo dc on dc.id = d.destino_id
    left join o on o.codigo = dc.codigo
   where p.estado = 'pendiente' and d.tipo = coalesce(p_tipo, 'reparto')
$$;

-- Al guardar las peticiones del reparto (o envío): las de las tiendas que van en él quedan atendidas
-- (con ese reparto). Si se modifica el reparto, se vuelven a mirar con el nuevo; las que se han quitado
-- de la casilla vuelven a pendientes.
create or replace function motor.atender_peticiones_tienda(p_reparto uuid, p_lista jsonb, p_ahora timestamptz)
returns integer language plpgsql set search_path = '' as $$
declare
  r public.repartos;
  v_n integer;
begin
  select * into r from public.repartos where id = p_reparto;
  update public.peticiones_tienda
     set estado = 'pendiente', reparto_id = null, atendida_en = null
   where estado = 'atendida'
     and reparto_id in (select x.id from public.repartos x where x.jornada_id = r.jornada_id and x.tipo = r.tipo);
  update public.peticiones_tienda p
     set estado = 'atendida', reparto_id = r.id, atendida_en = p_ahora
   where p.estado = 'pendiente'
     and exists (select 1 from motor.destino_peticion(p.centro_id) d, jsonb_array_elements(coalesce(p_lista, '[]')) x
                  where d.tipo = r.tipo and (x ->> 'destino_id')::uuid = d.destino_id
                    and upper(x ->> 'texto') = upper(p.texto));
  get diagnostics v_n = row_count;
  if v_n > 0 then
    perform motor.registrar('peticiones_tienda_atendidas', null, r.jornada_id, null,
                            jsonb_build_object('reparto', r.id, 'atendidas', v_n));
  end if;
  return v_n;
end;
$$;

-- La lista de productos para las muestras: la de la última lectura correcta de la hoja (la del
-- último reparto, envío o lista de stock), como en el reparto.
create or replace function motor.productos_tienda_de()
returns jsonb language sql stable set search_path = '' as $$
  with l as (select datos, leido_en from public.lecturas_sheets
              where correcto and jsonb_typeof(datos -> 'productos') = 'array' order by leido_en desc limit 1),
  x as (
    select distinct on (upper(regexp_replace(y.producto || y.formato, '\s+', '', 'g'))) y.*
      from (select btrim(p ->> 'nombre') as producto, f ->> 'formato' as formato,
                   coalesce(l.datos -> 'categorias' ->> upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')), 'Otros') as categoria,
                   (p ->> 'orden')::int * 100 + n::int - 1 as orden
              from l, jsonb_array_elements(l.datos -> 'productos') p,
                   jsonb_array_elements(coalesce(p -> 'formatos', '[]')) with ordinality a(f, n)
            union all
            select btrim(p ->> 'nombre'), '',
                   coalesce(l.datos -> 'categorias' ->> upper(regexp_replace(p ->> 'nombre', '\s+', '', 'g')), 'Otros'),
                   (p ->> 'orden')::int * 100
              from l, jsonb_array_elements(l.datos -> 'productos') p
             where jsonb_array_length(coalesce(p -> 'formatos', '[]')) = 0 and coalesce((p ->> 'conTiendas')::boolean, false)) y
     order by upper(regexp_replace(y.producto || y.formato, '\s+', '', 'g')), y.orden)
  select jsonb_build_object(
    'productos', coalesce((select jsonb_agg(jsonb_build_object('clave', x.producto || '|' || x.formato, 'producto', x.producto,
                                                               'formato', x.formato, 'categoria', x.categoria) order by x.orden)
                             from x), '[]'::jsonb),
    'leidos_en', (select leido_en from l))
$$;

-- ---------------------------------------------------------------------------
-- 6. El día de la tienda: la lista y tienda_hoy() con la bolsa, el reparto y las peticiones
-- ---------------------------------------------------------------------------
create or replace function motor.tarea_tienda_json(p_tarea uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque, 'tipo', t.contenido,
    'hora', motor.hora_texto(t.disponible_desde), 'desde', t.disponible_desde,
    'estado', t.estado,
    'se_puede_marcar', t.estado = 'pendiente' and t.disponible_desde <= p_ahora,
    -- Al cerrar la tienda, lo que no se ha hecho queda como no hecho (no pasa al día siguiente).
    'no_hecha', t.estado = 'pendiente'
                and p_ahora >= (select max(motor.en_local(j.fecha, h.hora_fin)) from public.horarios h
                                 where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)),
    'motivo', t.motivo_no_hecha,
    'terminada_en', t.terminada_en, 'hora_fin', motor.hora_texto(t.terminada_en),
    'hecha_por', case when t.estado in ('hecha', 'cancelada') then (
      select r.datos ->> 'hecha_por' from public.registro_eventos r
       where r.tarea_id = t.id and r.tipo in ('tarea_terminada', 'video_no_pudo') order by r.id desc limit 1) end,
    'puntos', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'texto', e.producto, 'hecho', e.estado = 'hecho',
                                          'hecho_por', e.calculo ->> 'hecho_por', 'a_las', motor.hora_texto(e.terminado_en),
                                          -- Tarea 28: los puntos que piden algo más que un toque.
                                          'pide', case motor.punto_especial(e) when 'efectivo' then 'efectivo'
                                                                               when 'cierre_caja' then 'cierre_caja' end,
                                          'efectivo_esperado', case when motor.punto_especial(e) = 'efectivo'
                                                                    then (e.calculo ->> 'esperado')::numeric end,
                                          'datos', e.calculo -> 'datos')
                       order by e.orden_sugerido, e.producto)
        from public.tarea_elementos e where e.tarea_id = t.id and e.tipo = 'punto'), '[]'::jsonb),
    'video', (select jsonb_build_object('enlace', v.enlace, 'aprendido', v.aprendido, 'no_pudo', v.no_pudo)
                from public.videos_tienda v where v.tarea_id = t.id),
    -- Tarea 28: lo que trae la bolsa («Recibe la bolsa» y «Coloca y apunta la reposición»).
    'bolsa', case when t.clave in ('recibe_bolsa', 'reposicion') then motor.bolsa_tienda_json(j.centro_id, j.fecha) end,
    -- Tarea 28: lo que se ha pedido en «Revisa las muestras».
    'muestras', case when t.contenido = 'muestras' then coalesce((
      select jsonb_agg(jsonb_build_object('producto', p.producto, 'formato', p.formato, 'cantidad', p.cantidad,
                                          'estado', p.estado) order by p.creada_en, p.id)
        from public.peticiones_tienda p where p.tarea_id = t.id), '[]'::jsonb) end)
  from public.tareas t join public.jornadas j on j.id = t.jornada_id
  where t.id = p_tarea;
$$;

create or replace function motor.tienda_hoy_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  v_dia integer := extract(isodow from v_hoy);
  pe public.personas;
  c public.centros_trabajo;
  v_jornada uuid;
  v_turno text;
  tt public.turnos_tienda;
begin
  select * into pe from public.personas where id = p_persona;
  select * into c from public.centros_trabajo where id = pe.centro_id;
  v_jornada := motor.generar_jornada(p_persona, v_hoy);
  -- Tarea 28: si ha salido el reparto y trae bolsa para esta tienda, «Recibe la bolsa».
  perform motor.preparar_bolsa_tienda(p_persona, v_jornada, p_ahora);
  v_turno := motor.turno_tienda_ahora(p_persona, p_ahora);
  tt := motor.en_turno_tienda(v_jornada);
  return jsonb_build_object(
    'tienda', jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre),
    'fecha', v_hoy,
    'ahora', motor.hora_texto(p_ahora),
    'abierta_hoy', v_jornada is not null,
    'cerrado', motor.dia_cerrado(c.id, v_hoy),
    'horario', coalesce((select jsonb_agg(jsonb_build_object('turno', h.turno, 'inicio', to_char(h.hora_inicio, 'HH24:MI'),
                                                             'fin', to_char(h.hora_fin, 'HH24:MI')) order by h.hora_inicio)
                           from public.horarios h where h.persona_id = p_persona and h.dia_semana = v_dia), '[]'::jsonb),
    'turno', v_turno,
    'en_turno', case when tt.id is not null then
      jsonb_build_object('persona_id', tt.persona_tienda_id, 'nombre', tt.nombre, 'turno', tt.turno,
                         'desde', motor.hora_texto(tt.empezado_en)) end,
    'personas', coalesce((
      select jsonb_agg(x.o order by x.sugerida desc, x.nombre)
        from (select pt.nombre,
                     (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                     and (pt.turno is null or v_turno is null or pt.turno = v_turno) as sugerida,
                     jsonb_build_object('id', pt.id, 'nombre', pt.nombre, 'cuando', pt.cuando, 'turno', pt.turno,
                       'sugerida', (pt.cuando = 'siempre' or (pt.cuando = 'entre_semana' and v_dia <= 5) or (pt.cuando = 'sabados' and v_dia = 6))
                                   and (pt.turno is null or v_turno is null or pt.turno = v_turno)) as o
                from public.personas_tienda pt where pt.centro_id = c.id and pt.activo) x), '[]'::jsonb),
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'fecha', motor.fecha_local(i.iniciada_en))
                       order by i.iniciada_en)
        from public.incidencias i
       where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'tareas', coalesce((
      select jsonb_agg(motor.tarea_tienda_json(t.id, p_ahora) order by t.disponible_desde, t.orden, t.creada_en)
        from public.tareas t where t.jornada_id = v_jornada and not t.retirada_por_condicion), '[]'::jsonb),
    -- Tarea 28: por dónde va el reparto, las peticiones (muestras y material) y si puede pedir material.
    'reparto', motor.seguimiento_reparto_json(c.id, v_hoy, p_ahora),
    'peticiones', motor.peticiones_tienda_json(c.id, p_ahora),
    'pedir_material', coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                                 where k.clave = 'pedir_material' and k.centro_id = c.id), false));
end;
$$;

-- Tocar un punto. Los que piden algo (el efectivo de ayer, el cierre de caja) tienen su función;
-- el del efectivo, con un toque, da por buena la cantidad del último cierre de caja.
create or replace function motor.marcar_punto_de(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
begin
  select el.* into e from public.tarea_elementos el
    join public.tareas tr on tr.id = el.tarea_id join public.jornadas j on j.id = tr.jornada_id
   where el.id = p_elemento and el.tipo = 'punto' and j.persona_id = p_persona;
  if e.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese punto no existe.');
  end if;
  if e.estado = 'hecho' then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  v_error := motor.tarea_tienda_marcable(p_persona, e.tarea_id, 'puntos', p_ahora);
  if v_error is not null then
    return v_error;
  end if;
  if motor.punto_especial(e) = 'cierre_caja' then
    return motor.error('FALTAN_DATOS', 'Apunta el cierre de caja: Z, número de ventas, efectivo y Glovo.',
                       jsonb_build_object('pide', 'cierre_caja'));
  elsif motor.punto_especial(e) = 'efectivo' then
    return motor.entregar_efectivo_de(p_persona, p_elemento, null, null, p_ahora);
  end if;
  perform motor.hacer_punto(p_persona, e.id, null, p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- «Bolsa de ayer entregada con X €»: sin cantidad, X (la del último cierre de caja); con otra
-- cantidad, también el porqué. Sin cierre anterior, la cantidad.
create or replace function motor.entregar_efectivo_de(p_persona uuid, p_elemento uuid, p_cantidad numeric, p_motivo text,
                                                      p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  v_esperado numeric;
  v_cantidad numeric;
  v_motivo text := nullif(btrim(regexp_replace(coalesce(p_motivo, ''), '\s+', ' ', 'g')), '');
begin
  select el.* into e from public.tarea_elementos el
    join public.tareas tr on tr.id = el.tarea_id join public.jornadas j on j.id = tr.jornada_id
   where el.id = p_elemento and el.tipo = 'punto' and j.persona_id = p_persona;
  if e.id is null or motor.punto_especial(e) is distinct from 'efectivo' then
    return motor.error('NO_ENCONTRADO', 'Ese punto no existe.');
  end if;
  if e.estado = 'hecho' then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  v_error := motor.tarea_tienda_marcable(p_persona, e.tarea_id, 'puntos', p_ahora);
  if v_error is not null then
    return v_error;
  end if;
  v_esperado := (e.calculo ->> 'esperado')::numeric;
  v_cantidad := coalesce(p_cantidad, v_esperado);
  if v_cantidad is null then
    return motor.error('FALTAN_DATOS', 'Di cuánto efectivo entregas en la bolsa de ayer.', jsonb_build_object('pide', 'efectivo'));
  end if;
  if v_cantidad < 0 or v_cantidad >= 100000 or v_cantidad <> round(v_cantidad, 2) then
    return motor.error('DATOS_NO_VALIDOS', 'La cantidad de efectivo no es válida (en euros, con dos decimales como máximo).');
  end if;
  if v_esperado is not null and v_cantidad <> v_esperado and v_motivo is null then
    return motor.error('MOTIVO_OBLIGATORIO', 'Entregas otra cantidad que la del cierre (' || motor.euros(v_esperado)
                       || '): di por qué (por ejemplo, monedas para cambio).');
  end if;
  if v_motivo is not null and length(v_motivo) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'El porqué, en una línea (200 letras como máximo).');
  end if;
  update public.bolsas_tienda
     set efectivo_entregado = v_cantidad, efectivo_motivo = v_motivo, efectivo_en = p_ahora
   where tarea_id = e.tarea_id;
  perform motor.hacer_punto(p_persona, e.id,
                            jsonb_build_object('entregado', v_cantidad, 'esperado', v_esperado, 'motivo', v_motivo), p_ahora);
  perform motor.registrar('efectivo_entregado', p_persona, (select jornada_id from public.tareas where id = e.tarea_id), e.tarea_id,
                          jsonb_build_object('entregado', v_cantidad, 'esperado', v_esperado, 'motivo', v_motivo, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- Cierre de caja (punto del «Cierre del día»). Se puede corregir mientras la tarea siga abierta.
create or replace function motor.cerrar_caja_de(p_persona uuid, p_elemento uuid, p_z numeric, p_ventas integer,
                                                p_efectivo numeric, p_glovo numeric, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  t public.tareas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_error jsonb;
  v_datos jsonb;
begin
  select el.* into e from public.tarea_elementos el
    join public.tareas tr on tr.id = el.tarea_id join public.jornadas jo on jo.id = tr.jornada_id
   where el.id = p_elemento and el.tipo = 'punto' and jo.persona_id = p_persona;
  if e.id is null or motor.punto_especial(e) is distinct from 'cierre_caja' then
    return motor.error('NO_ENCONTRADO', 'Ese punto no existe.');
  end if;
  v_error := motor.tarea_tienda_marcable(p_persona, e.tarea_id, 'puntos', p_ahora);
  if v_error is not null then
    return v_error;
  end if;
  if p_z is null or p_ventas is null or p_efectivo is null or p_glovo is null then
    return motor.error('DATOS_NO_VALIDOS', 'Apunta la Z, el número de ventas, el efectivo y Glovo (0 si no hay).');
  end if;
  if least(p_z, p_efectivo, p_glovo) < 0 or greatest(p_z, p_efectivo, p_glovo) >= 1000000
     or p_z <> round(p_z, 2) or p_efectivo <> round(p_efectivo, 2) or p_glovo <> round(p_glovo, 2)
     or p_ventas < 0 or p_ventas >= 100000 then
    return motor.error('DATOS_NO_VALIDOS', 'Algún número no es válido: euros con dos decimales como máximo y ventas en número entero.');
  end if;
  select * into t from public.tareas where id = e.tarea_id;
  select * into j from public.jornadas where id = t.jornada_id;
  tt := motor.en_turno_tienda(j.id);
  v_datos := jsonb_build_object('z', p_z, 'ventas', p_ventas, 'efectivo', p_efectivo, 'glovo', p_glovo);
  insert into public.cierres_caja (centro_id, fecha, z, ventas, efectivo, glovo, tarea_id, persona_tienda_id, nombre, guardado_en)
  values (j.centro_id, j.fecha, p_z, p_ventas, p_efectivo, p_glovo, t.id, tt.persona_tienda_id, tt.nombre, p_ahora)
  on conflict (centro_id, fecha) do update
    set z = excluded.z, ventas = excluded.ventas, efectivo = excluded.efectivo, glovo = excluded.glovo,
        persona_tienda_id = excluded.persona_tienda_id, nombre = excluded.nombre, guardado_en = excluded.guardado_en;
  perform motor.registrar('cierre_caja_guardado', p_persona, j.id, t.id, v_datos || jsonb_build_object('a_las', p_ahora, 'por', tt.nombre));
  if e.estado = 'hecho' then
    update public.tarea_elementos set calculo = calculo || jsonb_build_object('datos', v_datos) where id = e.id;
  else
    perform motor.hacer_punto(p_persona, e.id, v_datos, p_ahora);
  end if;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- «Coloca y apunta la reposición»: todo bien (sin `faltan`) o «Falta algo», que abre una incidencia
-- para Administración (decide si fue un error de la bolsa o va en el siguiente reparto).
create or replace function motor.apuntar_reposicion_de(p_persona uuid, p_tarea uuid, p_faltan jsonb, p_nota text,
                                                       p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'reposicion', p_ahora);
  t public.tareas;
  j public.jornadas;
  b public.bolsas_tienda;
  tt public.turnos_tienda;
  v_contenido jsonb;
  v_items jsonb;
  v_faltan jsonb := '[]';
  v_nota text := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '');
  v_incidencia uuid;
  x jsonb;
  it jsonb;
  v_cant integer;
begin
  if v_error is not null then
    return v_error;
  end if;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  select * into b from public.bolsas_tienda where centro_id = j.centro_id and fecha = j.fecha;
  tt := motor.en_turno_tienda(j.id);
  v_contenido := motor.bolsa_contenido(b.reparto_id, b.centro_id);
  -- Lo que podía faltar: cada producto (hasta su cantidad), cada petición y cada pedido (1).
  select coalesce(jsonb_agg(y), '[]') into v_items from (
    select jsonb_build_object('clave', c ->> 'clave', 'texto', trim((c ->> 'producto') || ' ' || (c ->> 'formato')),
                              'maximo', (c ->> 'cantidad')::int, 'producto', true) as y
      from jsonb_array_elements(v_contenido -> 'productos') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', c ->> 'texto', 'maximo', 1, 'producto', false)
      from jsonb_array_elements(v_contenido -> 'peticiones') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', 'Pedido de ' || (c ->> 'cliente'), 'maximo', 1, 'producto', false)
      from jsonb_array_elements(v_contenido -> 'pedidos') c) s;
  if p_faltan is not null and jsonb_typeof(p_faltan) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_faltan, '[]')) loop
    select i into it from jsonb_array_elements(v_items) i where i ->> 'clave' = x ->> 'clave';
    if it is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    if exists (select 1 from jsonb_array_elements(v_faltan) f where f ->> 'clave' = x ->> 'clave') then
      return motor.error('DATOS_NO_VALIDOS', 'Cada cosa, una sola vez.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_cant := case when x ? 'cantidad' and jsonb_typeof(x -> 'cantidad') = 'number' then (x ->> 'cantidad')::numeric::int
                   when x ? 'cantidad' then -1 else (it ->> 'maximo')::int end;
    if v_cant < 1 or v_cant > (it ->> 'maximo')::int or (x ? 'cantidad' and (x ->> 'cantidad')::numeric <> v_cant) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas faltan de ' || (it ->> 'texto') || ': de 1 a ' || (it ->> 'maximo') || '.',
                         jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_faltan := v_faltan || jsonb_build_object('clave', it ->> 'clave', 'texto', it ->> 'texto', 'cantidad', v_cant);
  end loop;
  if v_nota is not null and length(v_nota) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
  end if;

  if jsonb_array_length(v_faltan) = 0 then
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Reposición metida, todo bien', null, 'tarea_terminada', p_ahora);
  else
    insert into public.incidencias (jornada_id, persona_id, tarea_id, descripcion, iniciada_en, id_cliente, opcion, quien,
                                    estado, creada_por)
    values (j.id, p_persona, t.id,
            'Falta en la bolsa del reparto del ' || to_char(j.fecha, 'DD/MM') || ': '
              || (select string_agg(case when (f ->> 'cantidad')::int > 1 or (f ->> 'clave') like 'producto:%'
                                         then (f ->> 'cantidad') || 'x ' else '' end || (f ->> 'texto'), '; ')
                    from jsonb_array_elements(v_faltan) f)
              || coalesce('. ' || v_nota, '') || coalesce(' (' || tt.nombre || ')', ''),
            p_ahora, md5('falta_reposicion:' || b.id)::uuid, 'falta_reposicion', 'administracion', 'abierta', p_persona)
    on conflict (id_cliente) do nothing
    returning id into v_incidencia;
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Falta algo', null, 'tarea_terminada', p_ahora);
    perform motor.registrar('falta_reposicion', p_persona, j.id, t.id,
                            jsonb_build_object('incidencia', v_incidencia, 'faltan', v_faltan, 'nota', v_nota, 'a_las', p_ahora));
  end if;
  update public.bolsas_tienda
     set reposicion = case when jsonb_array_length(v_faltan) = 0 then 'bien' else 'falta' end,
         reposicion_en = p_ahora, reposicion_por = tt.nombre, faltan = v_faltan, incidencia_id = v_incidencia
   where id = b.id;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- «Revisa las muestras»: lo que hay que traer nuevo (de la lista de productos, con cantidad), o
-- nada. Cada una, una petición de la tienda para su siguiente reparto (o envío).
create or replace function motor.revisar_muestras_de(p_persona uuid, p_tarea uuid, p_muestras jsonb, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'muestras', p_ahora);
  t public.tareas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_lista jsonb := motor.productos_tienda_de() -> 'productos';
  v_prefijo text;
  v_elegidas jsonb := '[]';
  x jsonb;
  p jsonb;
  v_detalle text;
begin
  if v_error is not null then
    return v_error;
  end if;
  if p_muestras is not null and jsonb_typeof(p_muestras) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista qué muestras hay que traer.');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_muestras, '[]')) loop
    select l into p from jsonb_array_elements(v_lista) l
     where upper(regexp_replace((l ->> 'producto') || (l ->> 'formato'), '\s+', '', 'g'))
           = upper(regexp_replace(coalesce(x ->> 'producto', '') || coalesce(x ->> 'formato', ''), '\s+', '', 'g'));
    if p is null then
      return motor.error('DATOS_NO_VALIDOS', 'Ese producto no está en la lista.',
                         jsonb_build_object('producto', x ->> 'producto', 'formato', x ->> 'formato'));
    end if;
    if jsonb_typeof(x -> 'cantidad') is distinct from 'number' or (x ->> 'cantidad')::numeric not between 1 and 99
       or (x ->> 'cantidad')::numeric <> trunc((x ->> 'cantidad')::numeric) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas de ' || trim((p ->> 'producto') || ' ' || (p ->> 'formato')) || ': de 1 a 99.');
    end if;
    if exists (select 1 from jsonb_array_elements(v_elegidas) e where e ->> 'clave' = p ->> 'clave') then
      return motor.error('DATOS_NO_VALIDOS', 'Cada producto, una sola vez.');
    end if;
    v_elegidas := v_elegidas || (p || jsonb_build_object('cantidad', (x ->> 'cantidad')::int));
  end loop;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  tt := motor.en_turno_tienda(j.id);
  select d.prefijo into v_prefijo from motor.destino_peticion(j.centro_id) d;
  for p in select * from jsonb_array_elements(v_elegidas) loop
    v_detalle := (p ->> 'cantidad') || 'x ' || trim((p ->> 'producto') || ' ' || (p ->> 'formato'));
    insert into public.peticiones_tienda (centro_id, tipo, detalle, texto, producto, formato, cantidad, tarea_id,
                                          persona_tienda_id, nombre, creada_en)
    values (j.centro_id, 'muestra', v_detalle, left(coalesce(v_prefijo, '') || 'Muestra: ' || v_detalle, 120),
            p ->> 'producto', p ->> 'formato', (p ->> 'cantidad')::int, t.id, tt.persona_tienda_id, tt.nombre, p_ahora);
  end loop;
  perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha',
            case when jsonb_array_length(v_elegidas) = 0 then 'Muestras bien: nada que traer'
                 else 'Muestras para traer: ' || jsonb_array_length(v_elegidas) end,
            null, 'tarea_terminada', p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- Pedir material de tienda (bolsas, rollos de TPV…), en cualquier momento.
create or replace function motor.pedir_material_de(p_persona uuid, p_id_cliente uuid, p_texto text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  v_jornada uuid;
  tt public.turnos_tienda;
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
  v_prefijo text;
begin
  select * into pe from public.personas where id = p_persona;
  if not coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                    where k.clave = 'pedir_material' and k.centro_id = pe.centro_id), false) then
    return motor.error('NO_AUTORIZADO', 'Esta tienda no pide material desde aquí.');
  end if;
  if p_id_cliente is null or v_texto is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe qué material hace falta.');
  end if;
  if exists (select 1 from public.peticiones_tienda where id_cliente = p_id_cliente) then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  if length(v_texto) > 80 then
    return motor.error('DATOS_NO_VALIDOS', 'El material, en pocas palabras (80 letras como máximo).');
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  select d.prefijo into v_prefijo from motor.destino_peticion(pe.centro_id) d;
  insert into public.peticiones_tienda (centro_id, tipo, detalle, texto, id_cliente, persona_tienda_id, nombre, creada_en)
  values (pe.centro_id, 'material', v_texto, left(coalesce(v_prefijo, '') || 'Material: ' || v_texto, 120), p_id_cliente,
          tt.persona_tienda_id, tt.nombre, p_ahora)
  on conflict (id_cliente) do nothing;
  perform motor.registrar('material_pedido', p_persona, v_jornada, null, jsonb_build_object('texto', v_texto, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Administración: peticiones, cierres de caja e incidencias de las tiendas
-- ---------------------------------------------------------------------------
create or replace function motor.descartar_peticion_tienda_de(p_admin uuid, p_id uuid, p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  p public.peticiones_tienda;
  v_motivo text := nullif(btrim(regexp_replace(coalesce(p_motivo, ''), '\s+', ' ', 'g')), '');
begin
  select * into p from public.peticiones_tienda where id = p_id for update;
  if p.id is null then
    return motor.error('NO_ENCONTRADO', 'Esa petición no existe.');
  end if;
  if p.estado <> 'pendiente' then
    return motor.error('ESTADO_NO_VALIDO', 'Esa petición ya no está pendiente.', jsonb_build_object('estado', p.estado));
  end if;
  if v_motivo is null or length(v_motivo) > 120 then
    return motor.error('DATOS_NO_VALIDOS', 'Di por qué no va (120 letras como máximo): la tienda lo verá.');
  end if;
  update public.peticiones_tienda
     set estado = 'descartada', motivo = v_motivo, descartada_por = p_admin, atendida_en = p_ahora
   where id = p.id;
  perform motor.registrar('peticion_tienda_descartada', p_admin, null, null,
                          jsonb_build_object('peticion', p.id, 'motivo', v_motivo));
  return jsonb_build_object('peticion', (select motor.peticion_tienda_json(x, p_ahora) from public.peticiones_tienda x where x.id = p.id));
end;
$$;

create or replace function motor.cierres_caja_de(p_desde date, p_hasta date, p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('cierres', coalesce(jsonb_agg(jsonb_build_object(
           'fecha', k.fecha, 'tienda_id', k.centro_id, 'tienda', c.nombre, 'z', k.z, 'ventas', k.ventas,
           'efectivo', k.efectivo, 'glovo', k.glovo, 'por', k.nombre, 'guardado_en', k.guardado_en)
           order by k.fecha desc, c.nombre), '[]'::jsonb))
    from public.cierres_caja k join public.centros_trabajo c on c.id = k.centro_id
   where k.fecha between p_desde and p_hasta and (p_centro is null or k.centro_id = p_centro)
$$;

-- Las incidencias de las tiendas para Administración (hoy, «Falta algo»): las abiertas y las
-- cerradas de la última semana. Los avisos de Administración no van aquí (avisos_tiendas).
create or replace function motor.incidencias_tiendas_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('incidencias', coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'tienda_id', c.id, 'tienda', c.nombre, 'opcion', i.opcion, 'texto', i.descripcion,
           'fecha', motor.fecha_local(i.iniciada_en), 'a_las', motor.hora_texto(i.iniciada_en), 'estado', i.estado,
           'cerrada_en', i.terminada_en, 'nota', i.nota_cierre)
           order by (i.estado = 'cerrada'), i.iniciada_en desc), '[]'::jsonb))
    from public.incidencias i
    join public.personas p on p.id = i.persona_id and p.rol = 'tienda'
    join public.centros_trabajo c on c.id = p.centro_id
   where i.opcion is distinct from 'aviso'
     and (i.estado <> 'cerrada' or i.terminada_en >= motor.en_local(motor.fecha_local(p_ahora) - 7, '00:00'))
$$;

create or replace function motor.cerrar_incidencia_tienda_de(p_admin uuid, p_id uuid, p_nota text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
  v_nota text := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '');
begin
  select inc.* into i from public.incidencias inc join public.personas p on p.id = inc.persona_id and p.rol = 'tienda'
   where inc.id = p_id and inc.opcion is distinct from 'aviso' for update of inc;
  if i.id is null then
    return motor.error('NO_ENCONTRADO', 'Esa incidencia no existe.');
  end if;
  if v_nota is not null and length(v_nota) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
  end if;
  if i.estado <> 'cerrada' then
    update public.incidencias
       set estado = 'cerrada', terminada_en = p_ahora, cerrada_por = p_admin, nota_cierre = v_nota
     where id = i.id;
    perform motor.registrar('incidencia_cerrada', p_admin, i.jornada_id, i.tarea_id,
                            jsonb_build_object('incidencia', i.id, 'por', 'administracion', 'a_las', p_ahora));
  end if;
  return motor.incidencias_tiendas_de(p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Almacén: al guardar las peticiones especiales del reparto (o envío), las de las tiendas que
--    van en él quedan atendidas. Lo demás de la función no cambia.
-- ---------------------------------------------------------------------------
create or replace function public.servidor_guardar_peticiones(p_persona uuid, p_reparto uuid, p_peticiones jsonb,
                                                              p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  r public.repartos;
  v_lista jsonb;
  v_prod uuid;
  v_bolsas uuid;
  v_quitadas integer;
  v_nuevas integer;
begin
  select * into r from public.repartos where id = p_reparto;
  if r.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese reparto no existe.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('reparto:' || r.jornada_id || ':' || r.tipo, 0));
  select * into r from public.repartos where id = p_reparto;
  if r.estado <> 'aceptado' then
    -- Ya lo ha sustituido otro: ese lleva sus propias peticiones.
    return jsonb_build_object('peticiones', motor.peticiones_json(r.peticiones));
  end if;

  if exists (select 1 from jsonb_array_elements(coalesce(p_peticiones, '[]')) x
              where char_length(btrim(x ->> 'texto')) > 120) then
    return motor.error('DATOS_NO_VALIDOS', 'Cada petición especial, 120 letras como máximo.');
  end if;
  -- Sin vacías y sin repetir en la misma tienda, en el orden recibido.
  select coalesce(jsonb_agg(jsonb_build_object('destino_id', d.destino_id, 'texto', d.texto) order by d.n), '[]')
    into v_lista
    from (select distinct on (s.destino_id, upper(s.texto)) s.destino_id, s.texto, s.n
            from (select (x ->> 'destino_id')::uuid as destino_id,
                         btrim(regexp_replace(coalesce(x ->> 'texto', ''), '\s+', ' ', 'g')) as texto, n
                    from jsonb_array_elements(coalesce(p_peticiones, '[]')) with ordinality a(x, n)) s
           where s.texto <> '' and s.destino_id is not null
           order by s.destino_id, upper(s.texto), s.n) d;

  update public.repartos
     set peticiones = v_lista,
         resultado = resultado || jsonb_build_object('peticiones', motor.peticiones_json(v_lista))
   where id = r.id;
  -- Tarea 28: las peticiones de las tiendas (muestras y material) que van en él, atendidas.
  perform motor.atender_peticiones_tienda(r.id, v_lista, p_ahora);

  v_prod := (r.resultado -> 'tareas' ->> 'produccion')::uuid;
  v_bolsas := (r.resultado -> 'tareas' ->> 'bolsas')::uuid;
  if v_bolsas is null then
    return jsonb_build_object('peticiones', motor.peticiones_json(v_lista));
  end if;

  delete from public.tarea_elementos e
   where e.tarea_id = v_bolsas and e.tipo = 'peticion' and e.lote = r.tipo
     and not exists (select 1 from jsonb_array_elements(v_lista) x
                      where (x ->> 'destino_id')::uuid = e.destino_id and x ->> 'texto' = e.producto);
  get diagnostics v_quitadas = row_count;
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
  select v_bolsas, 'peticion', r.tipo, x ->> 'texto', '', (x ->> 'destino_id')::uuid, 1, n::int
    from jsonb_array_elements(v_lista) with ordinality a(x, n)
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do nothing;
  get diagnostics v_nuevas = row_count;
  update public.tarea_elementos e
     set orden_sugerido = a.n::int
    from jsonb_array_elements(v_lista) with ordinality a(x, n)
   where e.tarea_id = v_bolsas and e.tipo = 'peticion' and e.lote = r.tipo
     and e.destino_id = (a.x ->> 'destino_id')::uuid and e.producto = a.x ->> 'texto' and e.orden_sugerido <> a.n;

  -- Solo si cambia algo: una petición nueva vuelve a abrir la bolsa ya terminada.
  if v_quitadas + v_nuevas > 0 then
    perform motor.ajustar_estado_lista(p_persona, v_bolsas,
              case when v_bolsas = v_prod then 'No falta producir nada: todo está hecho en el almacén' else 'Sin bolsas' end,
              p_ahora);
    perform motor.registrar('peticiones_guardadas', p_persona, r.jornada_id, v_bolsas,
                            jsonb_build_object('reparto', r.id, 'peticiones', jsonb_array_length(v_lista),
                                               'nuevas', v_nuevas, 'quitadas', v_quitadas));
  end if;
  return jsonb_build_object('peticiones', motor.peticiones_json(v_lista));
end;
$$;
revoke execute on function public.servidor_guardar_peticiones(uuid, uuid, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.servidor_guardar_peticiones(uuid, uuid, jsonb, timestamptz) to service_role;

-- ---------------------------------------------------------------------------
-- 9. Funciones para las pantallas
-- ---------------------------------------------------------------------------
create or replace function motor.api_entregar_efectivo(p_elemento_id uuid, p_cantidad numeric, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.entregar_efectivo_de(auth.uid(), p_elemento_id, p_cantidad, p_motivo, now());
end; $$;

create or replace function motor.api_cerrar_caja(p_elemento_id uuid, p_z numeric, p_ventas integer, p_efectivo numeric,
                                                 p_glovo numeric)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.cerrar_caja_de(auth.uid(), p_elemento_id, p_z, p_ventas, p_efectivo, p_glovo, now());
end; $$;

create or replace function motor.api_apuntar_reposicion(p_tarea_id uuid, p_faltan jsonb, p_nota text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.apuntar_reposicion_de(auth.uid(), p_tarea_id, p_faltan, p_nota, now());
end; $$;

create or replace function motor.api_productos_tienda()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if not (motor.es_tienda() or motor.es_admin()) then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  return motor.productos_tienda_de();
end; $$;

create or replace function motor.api_revisar_muestras(p_tarea_id uuid, p_muestras jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.revisar_muestras_de(auth.uid(), p_tarea_id, p_muestras, now());
end; $$;

create or replace function motor.api_pedir_material(p_id_cliente uuid, p_texto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.pedir_material_de(auth.uid(), p_id_cliente, p_texto, now());
end; $$;

-- Para «Preparar reparto» / «Preparar envío»: el operario y Administración.
create or replace function motor.api_peticiones_tiendas_pendientes(p_tipo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if motor.es_tienda() then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  if coalesce(p_tipo, 'reparto') not in ('reparto', 'envio') then
    return motor.error('DATOS_NO_VALIDOS', 'El tipo es «reparto» o «envio».');
  end if;
  return motor.peticiones_pendientes_de(coalesce(p_tipo, 'reparto'));
end; $$;

create or replace function motor.api_descartar_peticion_tienda(p_peticion_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.descartar_peticion_tienda_de(auth.uid(), p_peticion_id, p_motivo, now());
end; $$;

create or replace function motor.api_cierres_caja(p_desde date, p_hasta date, p_tienda_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.cierres_caja_de(coalesce(p_desde, motor.fecha_local(now()) - 7),
                               coalesce(p_hasta, motor.fecha_local(now())), p_tienda_id);
end; $$;

create or replace function motor.api_incidencias_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.incidencias_tiendas_de(now());
end; $$;

create or replace function motor.api_cerrar_incidencia_tienda(p_incidencia_id uuid, p_nota text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.cerrar_incidencia_tienda_de(auth.uid(), p_incidencia_id, p_nota, now());
end; $$;

create or replace function public.entregar_efectivo(elemento_id uuid, cantidad numeric default null, motivo text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_entregar_efectivo(elemento_id, cantidad, motivo) $$;
create or replace function public.cerrar_caja(elemento_id uuid, z numeric, ventas integer, efectivo numeric, glovo numeric)
returns jsonb language sql set search_path = '' as $$ select motor.api_cerrar_caja(elemento_id, z, ventas, efectivo, glovo) $$;
create or replace function public.apuntar_reposicion(tarea_id uuid, faltan jsonb default null, nota text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_apuntar_reposicion(tarea_id, faltan, nota) $$;
create or replace function public.productos_tienda()
returns jsonb language sql set search_path = '' as $$ select motor.api_productos_tienda() $$;
create or replace function public.revisar_muestras(tarea_id uuid, muestras jsonb default '[]')
returns jsonb language sql set search_path = '' as $$ select motor.api_revisar_muestras(tarea_id, muestras) $$;
create or replace function public.pedir_material(id_cliente uuid, texto text)
returns jsonb language sql set search_path = '' as $$ select motor.api_pedir_material(id_cliente, texto) $$;
create or replace function public.peticiones_tiendas_pendientes(tipo text default 'reparto')
returns jsonb language sql set search_path = '' as $$ select motor.api_peticiones_tiendas_pendientes(tipo) $$;
create or replace function public.descartar_peticion_tienda(peticion_id uuid, motivo text)
returns jsonb language sql set search_path = '' as $$ select motor.api_descartar_peticion_tienda(peticion_id, motivo) $$;
create or replace function public.cierres_caja(desde date default null, hasta date default null, tienda_id uuid default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_cierres_caja(desde, hasta, tienda_id) $$;
create or replace function public.incidencias_tiendas()
returns jsonb language sql set search_path = '' as $$ select motor.api_incidencias_tiendas() $$;
create or replace function public.cerrar_incidencia_tienda(incidencia_id uuid, nota text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_cerrar_incidencia_tienda(incidencia_id, nota) $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.api_entregar_efectivo(uuid, numeric, text), motor.api_cerrar_caja(uuid, numeric, integer, numeric, numeric),
  motor.api_apuntar_reposicion(uuid, jsonb, text), motor.api_productos_tienda(), motor.api_revisar_muestras(uuid, jsonb),
  motor.api_pedir_material(uuid, text), motor.api_peticiones_tiendas_pendientes(text),
  motor.api_descartar_peticion_tienda(uuid, text), motor.api_cierres_caja(date, date, uuid),
  motor.api_incidencias_tiendas(), motor.api_cerrar_incidencia_tienda(uuid, text)
to authenticated;
revoke execute on function
  public.entregar_efectivo(uuid, numeric, text), public.cerrar_caja(uuid, numeric, integer, numeric, numeric),
  public.apuntar_reposicion(uuid, jsonb, text), public.productos_tienda(), public.revisar_muestras(uuid, jsonb),
  public.pedir_material(uuid, text), public.peticiones_tiendas_pendientes(text),
  public.descartar_peticion_tienda(uuid, text), public.cierres_caja(date, date, uuid),
  public.incidencias_tiendas(), public.cerrar_incidencia_tienda(uuid, text)
from public, anon;
grant execute on function
  public.entregar_efectivo(uuid, numeric, text), public.cerrar_caja(uuid, numeric, integer, numeric, numeric),
  public.apuntar_reposicion(uuid, jsonb, text), public.productos_tienda(), public.revisar_muestras(uuid, jsonb),
  public.pedir_material(uuid, text), public.peticiones_tiendas_pendientes(text),
  public.descartar_peticion_tienda(uuid, text), public.cierres_caja(date, date, uuid),
  public.incidencias_tiendas(), public.cerrar_incidencia_tienda(uuid, text)
to authenticated;
