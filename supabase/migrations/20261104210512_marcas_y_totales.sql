-- Tarea 33 · Marcas en las pestañas del panel y totales de los cierres de caja (ESTADO_DEL_SISTEMA.md E2-8, v1.61 y
-- v1.62: «Cómo queda el panel» y «Marcas en las pestañas»). Solo en pruebas: producción espera con las de tiendas.
-- Sustituye al «resumen del día» (bloque 1, punto 28): no se crea ninguna incidencia ni correo.
--   1. Marcas por centro, solo para Administración, en tiendas().centros:
--      - `rojo`: en una tienda, sus incidencias abiertas de incidencias_tiendas() (los atascados por decidir ya están
--        ahí); en el almacén, los problemas abiertos de estado_actual() (los del botón «Resolver»).
--      - `sin_hacer`: las tareas de la tienda que quedaron sin hacer al cerrar (últimos 7 días) desde la última vez
--        que esa persona de Administración entró en la tienda en el panel (marcar_tienda_vista, tabla vistas_panel).
--      - `sin_abrir`: hoy abre, ha pasado media hora desde que empieza un turno y nadie lo ha empezado.
--   2. cierres_caja() trae `totales` por día: propias (Z, ventas, efectivo y Glovo) y franquicias (Z y ventas), cada
--      una con las tiendas que `faltan`. Franquicia = la tienda con el cierre de caja corto activado (la plantilla
--      `cierre_caja`, Tarea 30b): sale de la configuración, no del nombre (Durango, con el cierre del día, va con las propias).
--   3. La hora de cierre de la tienda (la de «no hecha») pasa a una ayuda, motor.cierre_tienda_en, que usan la lista del
--      día de la tienda, las marcas y los totales: una sola regla.
--
-- Deshacer: borrar public.marcar_tienda_vista, motor.api_marcar_tienda_vista, motor.marcar_tienda_vista_de,
-- motor.marcas_panel_json, motor.totales_cierres_de, motor.cierre_corto y motor.cierre_tienda_en, y la tabla
-- vistas_panel; volver a crear motor.tarea_tienda_json (20261104140512), motor.api_tiendas (20261104190512) y
-- motor.api_cierres_caja (20261103091220) como estaban.

-- ---------------------------------------------------------------------------
-- 1. Ayudas
-- ---------------------------------------------------------------------------
-- La hora a la que cierra la tienda ese día (la última hora de fin de su horario); null si ese día no abre.
create or replace function motor.cierre_tienda_en(p_persona uuid, p_fecha date)
returns timestamptz language sql stable set search_path = '' as $$
  select max(motor.en_local(p_fecha, h.hora_fin)) from public.horarios h
   where h.persona_id = p_persona and h.dia_semana = extract(isodow from p_fecha)
$$;

-- Si la tienda hace el cierre de caja corto (Z y nº de ventas: las franquicias). Por configuración (Tarea 30b).
create or replace function motor.cierre_corto(p_centro uuid)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.plantillas_tarea p where p.centro_id = p_centro and p.codigo = 'cierre_caja' and p.activa)
$$;

-- ---------------------------------------------------------------------------
-- 2. La lista del día de la tienda, con la ayuda (devuelve lo mismo que antes)
-- ---------------------------------------------------------------------------
create or replace function motor.tarea_tienda_json(p_tarea uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque, 'tipo', t.contenido,
    'hora', motor.hora_texto(t.disponible_desde), 'desde', t.disponible_desde,
    'estado', t.estado,
    'se_puede_marcar', t.estado = 'pendiente' and t.disponible_desde <= p_ahora,
    -- Al cerrar la tienda, lo que no se ha hecho queda como no hecho (no pasa al día siguiente).
    -- Tarea 33: la hora de cierre, con la ayuda que usan también las marcas del panel y los cierres de caja.
    'no_hecha', t.estado = 'pendiente' and p_ahora >= motor.cierre_tienda_en(j.persona_id, j.fecha),
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
                                                                               when 'cierre_caja' then 'cierre_caja'
                                                                               -- Tarea 30b: Z y nº de ventas.
                                                                               when 'cierre_caja_corto' then 'cierre_caja_corto' end,
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
        from public.peticiones_tienda p where p.tarea_id = t.id), '[]'::jsonb) end,
    -- Tarea 31: lo que se ha apuntado en «Revisa los productos atascados», con su estado.
    'atascados', case when t.contenido = 'atascados' then coalesce((
      select jsonb_agg(motor.atascado_json(a.id, 'tiene', p_ahora) order by a.creada_en, a.producto)
        from public.atascados a where a.tarea_id = t.id), '[]'::jsonb) end)
  from public.tareas t join public.jornadas j on j.id = t.jornada_id
  where t.id = p_tarea;
$$;

-- ---------------------------------------------------------------------------
-- 3. Cuándo ha entrado cada persona de Administración en cada centro del panel
-- ---------------------------------------------------------------------------
create table public.vistas_panel (
  persona_id uuid not null references public.personas (id),
  centro_id  uuid not null references public.centros_trabajo (id),
  visto_en   timestamptz not null,
  primary key (persona_id, centro_id)
);
comment on table public.vistas_panel is 'Cuándo entró cada persona de Administración en cada centro del panel (quita su «N sin hacer»). Tarea 33.';
create index vistas_panel_centro_id_idx on public.vistas_panel (centro_id);
revoke all on public.vistas_panel from anon, authenticated;
alter table public.vistas_panel enable row level security;

-- ---------------------------------------------------------------------------
-- 4. Las marcas
-- ---------------------------------------------------------------------------
-- { "<centro_id>": { rojo, sin_hacer, sin_abrir, texto } } para esa persona de Administración.
create or replace function motor.marcas_panel_json(p_admin uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with hoy as (select motor.fecha_local(p_ahora) as f),
  cen as (select (x ->> 'id')::uuid as id, x ->> 'tipo' as tipo from jsonb_array_elements(motor.centros_panel_json()) x),
  -- Las incidencias abiertas de cada tienda, las mismas de incidencias_tiendas() (con los atascados por decidir).
  inc as (select (x ->> 'tienda_id')::uuid as centro, count(*)::int as n
            from jsonb_array_elements(motor.incidencias_tiendas_de(p_ahora) -> 'incidencias') x
           where x ->> 'estado' <> 'cerrada' group by 1),
  m as (
    select c.id, c.tipo,
           case when c.tipo = 'almacen' then jsonb_array_length(motor.estado_actual_de(p_ahora) -> 'problemas_abiertos')
                else coalesce(inc.n, 0) end as rojo,
           case when c.tipo = 'almacen' or pe.id is null then 0 else (
             select count(*)::int
               from public.jornadas j join public.tareas t on t.jornada_id = j.id
              where j.persona_id = pe.id and j.fecha between (select f from hoy) - 7 and (select f from hoy)
                and t.estado = 'pendiente' and not t.retirada_por_condicion
                and motor.cierre_tienda_en(j.persona_id, j.fecha) <= p_ahora
                and motor.cierre_tienda_en(j.persona_id, j.fecha) > coalesce(v.visto_en, '-infinity'::timestamptz)) end
             as sin_hacer,
           c.tipo = 'tienda' and pe.id is not null and not motor.dia_cerrado(c.id, (select f from hoy))
             and exists (select 1 from public.horarios h
                          where h.persona_id = pe.id and h.dia_semana = extract(isodow from (select f from hoy))
                            and p_ahora >= motor.en_local((select f from hoy), h.hora_inicio) + interval '30 minutes'
                            and not exists (select 1 from public.turnos_tienda x join public.jornadas j on j.id = x.jornada_id
                                             where j.persona_id = pe.id and j.fecha = (select f from hoy) and x.turno = h.turno))
             as sin_abrir
      from cen c
      left join inc on inc.centro = c.id
      left join lateral (select p.id from public.personas p
                          where p.centro_id = c.id and p.rol = 'tienda' and p.activo order by p.id limit 1) pe on c.tipo = 'tienda'
      left join public.vistas_panel v on v.persona_id = p_admin and v.centro_id = c.id)
  select coalesce(jsonb_object_agg(m.id, jsonb_build_object(
           'rojo', m.rojo, 'sin_hacer', m.sin_hacer, 'sin_abrir', coalesce(m.sin_abrir, false),
           -- Lo que se pinta junto al nombre: «●2 · 3 sin hacer · sin abrir» (null si no hay nada).
           'texto', nullif(concat_ws(' · ', case when m.rojo > 0 then '●' || m.rojo end,
                                           case when m.sin_hacer > 0 then m.sin_hacer || ' sin hacer' end,
                                           case when m.sin_abrir then 'sin abrir' end), ''))), '{}'::jsonb)
    from m
$$;

-- Administración entra en un centro del panel: se quita su «N sin hacer» (solo para esa persona).
create or replace function motor.marcar_tienda_vista_de(p_admin uuid, p_centro uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from public.centros_trabajo where id = p_centro and activo and tipo in ('tienda', 'almacen')) then
    return motor.error('NO_ENCONTRADO', 'Ese centro no existe.');
  end if;
  insert into public.vistas_panel (persona_id, centro_id, visto_en) values (p_admin, p_centro, p_ahora)
  on conflict (persona_id, centro_id) do update set visto_en = greatest(public.vistas_panel.visto_en, excluded.visto_en);
  return jsonb_build_object('centro_id', p_centro, 'marcas', motor.marcas_panel_json(p_admin, p_ahora) -> (p_centro::text));
end;
$$;

create or replace function motor.api_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_error jsonb := motor.persona_actual('*');
  v_marcas jsonb;
begin
  if v_error is not null then return v_error; end if;
  if motor.es_tienda() then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  -- Tarea 33: las marcas de las pestañas, solo para Administración (el operario ve lo de siempre). Lo ofrecido el
  -- martes que nadie ha pedido pasa antes a Administración, como en incidencias_tiendas().
  if motor.es_admin() then
    perform motor.vencer_atascados(now());
    v_marcas := motor.marcas_panel_json(auth.uid(), now());
  end if;
  return jsonb_build_object('tiendas', coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre) order by c.nombre)
      from public.centros_trabajo c where c.tipo = 'tienda' and c.activo), '[]'::jsonb),
    -- Tarea 32: el selector del panel (el almacén y las tiendas, en el orden de la ruta).
    'centros', case when v_marcas is null then motor.centros_panel_json() else (
      select jsonb_agg(x || jsonb_build_object('marcas', v_marcas -> (x ->> 'id')) order by n)
        from jsonb_array_elements(motor.centros_panel_json()) with ordinality a(x, n)) end);
end; $$;

-- ---------------------------------------------------------------------------
-- 5. Totales de los cierres de caja por día
-- ---------------------------------------------------------------------------
-- Para cada día: propias (Z, ventas, efectivo y Glovo) y franquicias (Z y ventas), cada una con las tiendas que
-- `faltan`: las que abrían ese día (con su horario y sin día cerrado) y no tienen cierre; hoy, solo las que ya han
-- pasado su hora de cierre.
create or replace function motor.totales_cierres_de(p_desde date, p_hasta date, p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with t as (
    select c.id, c.nombre, motor.cierre_corto(c.id) as corto,
           (select p.id from public.personas p where p.centro_id = c.id and p.rol = 'tienda' and p.activo order by p.id limit 1) as pe
      from public.centros_trabajo c
     where c.tipo = 'tienda' and c.activo and (p_centro is null or c.id = p_centro)),
  d as (select g::date as f from generate_series(p_desde, p_hasta, interval '1 day') g),
  -- Las tiendas que abrían cada día y si ya tenían que haber cerrado.
  abre as (
    select d.f, t.id, t.nombre, t.corto, motor.cierre_tienda_en(t.pe, d.f) as cierra_en
      from d cross join t
     where t.pe is not null and motor.cierre_tienda_en(t.pe, d.f) is not null and not motor.dia_cerrado(t.id, d.f)),
  k as (select k.*, t.corto from public.cierres_caja k join t on t.id = k.centro_id where k.fecha between p_desde and p_hasta)
  select coalesce(jsonb_agg(jsonb_build_object(
           'fecha', d.f,
           'propias', jsonb_build_object(
             'z', coalesce((select sum(k.z) from k where k.fecha = d.f and not k.corto), 0),
             'ventas', coalesce((select sum(k.ventas) from k where k.fecha = d.f and not k.corto), 0),
             'efectivo', coalesce((select sum(k.efectivo) from k where k.fecha = d.f and not k.corto), 0),
             'glovo', coalesce((select sum(k.glovo) from k where k.fecha = d.f and not k.corto), 0),
             'cierres', (select count(*) from k where k.fecha = d.f and not k.corto),
             'faltan', coalesce((select jsonb_agg(jsonb_build_object('tienda_id', a.id, 'tienda', a.nombre) order by a.nombre)
                                   from abre a where a.f = d.f and not a.corto and a.cierra_en <= p_ahora
                                    and not exists (select 1 from k where k.centro_id = a.id and k.fecha = d.f)), '[]'::jsonb)),
           'franquicias', jsonb_build_object(
             'z', coalesce((select sum(k.z) from k where k.fecha = d.f and k.corto), 0),
             'ventas', coalesce((select sum(k.ventas) from k where k.fecha = d.f and k.corto), 0),
             'cierres', (select count(*) from k where k.fecha = d.f and k.corto),
             'faltan', coalesce((select jsonb_agg(jsonb_build_object('tienda_id', a.id, 'tienda', a.nombre) order by a.nombre)
                                   from abre a where a.f = d.f and a.corto and a.cierra_en <= p_ahora
                                    and not exists (select 1 from k where k.centro_id = a.id and k.fecha = d.f)), '[]'::jsonb)))
           order by d.f desc), '[]'::jsonb)
    from d
   where exists (select 1 from abre a where a.f = d.f) or exists (select 1 from k where k.fecha = d.f)
$$;

create or replace function motor.api_cierres_caja(p_desde date, p_hasta date, p_tienda_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_error jsonb := motor.persona_actual('administracion');
  v_desde date := coalesce(p_desde, motor.fecha_local(now()) - 7);
  v_hasta date := coalesce(p_hasta, motor.fecha_local(now()));
begin
  if v_error is not null then return v_error; end if;
  -- Tarea 33: con los totales de cada día (propias y franquicias por separado, con las que faltan).
  return motor.cierres_caja_de(v_desde, v_hasta, p_tienda_id)
         || jsonb_build_object('totales', motor.totales_cierres_de(v_desde, v_hasta, p_tienda_id, now()));
end; $$;

-- ---------------------------------------------------------------------------
-- 6. Entrada de la API
-- ---------------------------------------------------------------------------
create or replace function motor.api_marcar_tienda_vista(p_tienda_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.marcar_tienda_vista_de(auth.uid(), p_tienda_id, now());
end; $$;

create or replace function public.marcar_tienda_vista(tienda_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_marcar_tienda_vista(tienda_id) $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_marcar_tienda_vista(uuid), motor.api_tiendas(), motor.api_cierres_caja(date, date, uuid)
  to authenticated;
revoke execute on function public.marcar_tienda_vista(uuid) from public, anon;
grant execute on function public.marcar_tienda_vista(uuid) to authenticated;
