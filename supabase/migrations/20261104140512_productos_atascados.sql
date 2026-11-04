-- Tarea 31 · Productos atascados (ESTADO_DEL_SISTEMA.md E2-8 v1.56 y v1.57, «Atascados» y la regla general de las
-- franquicias; AGENTE_COORDINADOR.md, bloque 1, puntos 15 a 17). Solo en pruebas: producción espera con las de
-- tiendas (AGENTE_BASE_DE_DATOS.md §4). El reparto de Eder no cambia: la recogida es una incidencia sin hora.
--   1. «Revisa los productos atascados», el martes por la mañana (Bilbao alterna), en todas las tiendas: eligen de la
--      lista (productos_tienda(), con formatos) cuántas cajas no se mueven, con nota; o «Nada atascado esta semana».
--   2. Lo atascado en una tienda que lo ofrece (configuración `atascados` = "ofrecer": las propias) sale a todas las
--      demás tiendas, franquicias incluidas, todo el martes, con «Las quiero»; se lo lleva la primera que lo pide.
--   3. Lo atascado en una franquicia (`atascados` = "administracion") va directo a Administración: promoción o
--      recogida (la organiza Administración; la cierra con su nota).
--   4. Si nadie lo pide, al acabar el martes pasa a Administración (incidencia abierta): promoción (aviso a la tienda;
--      sigue abierta hasta «Ya no queda») o al almacén.
--   5. Si hay que moverlo: incidencia abierta para Eder, sin hora («Recoge N de Y en [tienda] y llévalo a …»), y aviso
--      a la tienda que lo tiene («Prepara N de Y para recogida»). Si lo pide una tienda que recibe por envío, Eder lo
--      lleva al almacén y, al cerrar su incidencia, queda como petición de esa tienda para su siguiente envío
--      (decisión del propietario, 04/11/2026).
--
-- Deshacer: borrar public.revisar_atascados, public.querer_atascado, public.ya_no_queda, public.decidir_atascado, sus
-- motor.api_*, motor.revisar_atascados_de, motor.querer_atascado_de, motor.ya_no_queda_de, motor.decidir_atascado_de,
-- motor.atascado_entregado, motor.mover_atascado, motor.avisar_atascado, motor.jornada_recogida,
-- motor.atascado_a_administracion, motor.vencer_atascados, motor.atascado_json, motor.atascados_tienda_json,
-- motor.cajas_texto y motor.atascados_va_a; la tabla atascados; la plantilla revisa_atascados y la clave atascados;
-- volver a crear motor.tarea_tienda_json (20261103211530), motor.incidencia_json y motor.texto_opcion
-- (20261030121241), motor.cerrar_incidencia_de (20261027120100), motor.incidencias_tiendas_de y
-- motor.api_incidencias_tiendas (20261103091220), motor.incidencias_tienda_json (20261103203048) y
-- motor.tienda_hoy_de (20261104110512) como estaban; y los checks de contenido, incidencias.opcion y
-- peticiones_tienda.tipo sin los valores nuevos.

-- ---------------------------------------------------------------------------
-- 1. Contenido, opciones y tipo nuevos (solo se añaden valores)
-- ---------------------------------------------------------------------------
alter table public.plantillas_tarea drop constraint plantillas_tarea_contenido_check;
alter table public.plantillas_tarea add constraint plantillas_tarea_contenido_check
  check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento', 'puntos', 'video',
                       'reposicion', 'muestras', 'atascados'));
alter table public.tareas drop constraint tareas_contenido_check;
alter table public.tareas add constraint tareas_contenido_check
  check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento', 'puntos', 'video',
                       'reposicion', 'muestras', 'atascados'));
alter table public.incidencias drop constraint incidencias_opcion_check;
alter table public.incidencias add constraint incidencias_opcion_check
  check (opcion in ('comprar', 'varios', 'aviso', 'llega_mercancia', 'pedido_cliente', 'pedir_comprar',
                    'recogida_nacex', 'corregir', 'falta_reposicion', 'sin_producto', 'descuadre',
                    'comentario_cliente', 'otros', 'falta_envio', 'atascado', 'recogida_atascado'));
alter table public.peticiones_tienda drop constraint peticiones_tienda_tipo_check;
alter table public.peticiones_tienda add constraint peticiones_tienda_tipo_check
  check (tipo in ('muestra', 'material', 'atascado'));

-- ---------------------------------------------------------------------------
-- 2. Lo atascado en cada tienda
-- ---------------------------------------------------------------------------
create table public.atascados (
  id                 uuid primary key default gen_random_uuid(),
  centro_id          uuid not null references public.centros_trabajo (id),
  fecha              date not null,
  tarea_id           uuid references public.tareas (id),
  producto           text not null,
  formato            text not null default '',
  cantidad           integer not null check (cantidad between 1 and 99),
  nota               text,
  persona_tienda_id  uuid references public.personas_tienda (id),
  nombre             text,
  creada_en          timestamptz not null default now(),
  -- ofrecido (a las demás tiendas, su martes) · administracion (decide Administración) · promocion (hasta «Ya no
  -- queda») · por_recoger (incidencia de Eder abierta) · entregado · terminado (ya no queda) · cerrado (Administración)
  estado             text not null default 'ofrecido'
                     check (estado in ('ofrecido', 'administracion', 'promocion', 'por_recoger', 'entregado',
                                       'terminado', 'cerrado')),
  pedido_por         uuid references public.centros_trabajo (id),
  pedido_por_persona uuid references public.personas_tienda (id),
  pedido_por_nombre  text,
  pedido_en          timestamptz,
  incidencia_id      uuid references public.incidencias (id),
  decision           text check (decision in ('promocion', 'almacen', 'recogida')),
  decision_texto     text,
  decidido_por       uuid references public.personas (id),
  decidido_en        timestamptz,
  recogida_id        uuid references public.incidencias (id),
  aviso_id           uuid references public.incidencias (id),
  peticion_id        uuid references public.peticiones_tienda (id),
  terminado_en       timestamptz,
  terminado_por      text
);
comment on table public.atascados is 'Cajas que no se mueven en una tienda (la revisión del martes): se ofrecen a las demás, o decide Administración (promoción, al almacén o recogida). Tarea 31.';
create index atascados_centro_id_idx on public.atascados (centro_id);
create index atascados_estado_fecha_idx on public.atascados (estado, fecha);
create index atascados_tarea_id_idx on public.atascados (tarea_id);
create index atascados_persona_tienda_id_idx on public.atascados (persona_tienda_id);
create index atascados_pedido_por_idx on public.atascados (pedido_por);
create index atascados_pedido_por_persona_idx on public.atascados (pedido_por_persona);
create index atascados_incidencia_id_idx on public.atascados (incidencia_id);
create index atascados_decidido_por_idx on public.atascados (decidido_por);
create index atascados_recogida_id_idx on public.atascados (recogida_id);
create index atascados_aviso_id_idx on public.atascados (aviso_id);
create index atascados_peticion_id_idx on public.atascados (peticion_id);
revoke all on public.atascados from anon, authenticated;
grant select on public.atascados to authenticated;
alter table public.atascados enable row level security;
create policy lectura on public.atascados for select to authenticated
  using ((select motor.es_admin())
         or ((select motor.es_tienda()) and (centro_id = (select motor.mi_centro()) or pedido_por = (select motor.mi_centro()))));

-- ---------------------------------------------------------------------------
-- 3. Configuración y plantilla
-- ---------------------------------------------------------------------------
-- Adónde va lo atascado de cada tienda: "ofrecer" (a las demás tiendas; las propias) o "administracion" (directo a
-- Administración; Donosti y Rentería). Por tienda, como las demás activaciones.
insert into public.configuracion (clave, centro_id, valor)
select 'atascados', c.id, to_jsonb(case when c.codigo in ('DONOSTI', 'RENTERIA') then 'administracion' else 'ofrecer' end)
  from public.centros_trabajo c where c.tipo = 'tienda';

-- «Revisa los productos atascados», el martes por la mañana (Bilbao alterna), en todas las tiendas.
insert into public.plantillas_tarea (centro_id, codigo, titulo, porque, programacion, dias_semana, turno,
                                     hora_desde, minutos_desde, alterna_turno, contenido, puntos, no_terminada, orden, activa)
select c.id, 'revisa_atascados', 'Revisa los productos atascados',
       'Elige cuántas cajas de cada producto no se mueven, para que vayan a otra tienda, a una promoción o al almacén.',
       'dia_semana', '{2}'::smallint[], 'manana', 'inicio', 0, true, 'atascados', '{}'::text[], 'nada', 55, true
  from public.centros_trabajo c where c.tipo = 'tienda';

-- ---------------------------------------------------------------------------
-- 4. Ayudas
-- ---------------------------------------------------------------------------
create or replace function motor.atascados_va_a(p_centro uuid)
returns text language sql stable set search_path = '' as $$
  select coalesce((select k.valor #>> '{}' from public.configuracion k where k.clave = 'atascados' and k.centro_id = p_centro),
                  'ofrecer')
$$;

-- «3 cajas de V2 4g», «1 caja de CREMA».
create or replace function motor.cajas_texto(p_cantidad integer, p_producto text, p_formato text)
returns text language sql immutable set search_path = '' as $$
  select p_cantidad || case when p_cantidad = 1 then ' caja de ' else ' cajas de ' end
         || btrim(p_producto || ' ' || coalesce(p_formato, ''))
$$;

-- La jornada del almacén para una recogida: hoy si trabaja; si no, su siguiente día de trabajo (como los avisos).
create or replace function motor.jornada_recogida(p_ahora timestamptz, out jornada uuid, out desde timestamptz)
language plpgsql set search_path = '' as $$
declare
  v_op uuid := motor.operario_por_defecto();
  v_hoy date := motor.fecha_local(p_ahora);
  d date;
begin
  if v_op is null then
    return;
  end if;
  for d in select g::date from generate_series(v_hoy, v_hoy + 7, interval '1 day') g loop
    jornada := motor.jornada_para(v_op, d, p_ahora);
    if jornada is not null then
      desde := case when d = v_hoy then p_ahora
                    else coalesce(motor.inicio_turno(v_op, d, null), motor.en_local(d, '00:00')) end;
      return;
    end if;
  end loop;
end;
$$;

-- Un aviso a la tienda (crear_aviso_tienda de siempre): hoy o, si hoy no abre, su siguiente día. Devuelve su id.
create or replace function motor.avisar_atascado(p_creador uuid, p_centro uuid, p_clave text, p_texto text, p_ahora timestamptz)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_hoy date := motor.fecha_local(p_ahora);
  d date;
  r jsonb;
begin
  for d in select g::date from generate_series(v_hoy, v_hoy + 7, interval '1 day') g loop
    r := motor.crear_aviso_tienda_de(p_creador, md5(p_clave)::uuid, d, p_texto, p_centro, p_ahora);
    if not r ? 'error' then
      return (r -> 'avisos' -> 0 ->> 'id')::uuid;
    end if;
    exit when r -> 'error' ->> 'codigo' <> 'SIN_JORNADA';
  end loop;
  return null;
end;
$$;

-- Lo atascado llega a Administración: incidencia abierta de la tienda, como las demás incidencias de tienda.
create or replace function motor.atascado_a_administracion(p_id uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  a public.atascados;
  j public.jornadas;
  v_inc uuid;
begin
  select * into a from public.atascados where id = p_id for update;
  if a.id is null or a.incidencia_id is not null then
    return;
  end if;
  select jo.* into j from public.tareas t join public.jornadas jo on jo.id = t.jornada_id where t.id = a.tarea_id;
  insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, quien, estado, creada_por)
  values (j.id, j.persona_id,
          'Atascado: ' || motor.cajas_texto(a.cantidad, a.producto, a.formato)
          || case when a.estado = 'ofrecido' then ', nadie lo ha pedido' else '' end
          || coalesce('. ' || a.nota, '') || coalesce(' (' || a.nombre || ')', ''),
          p_ahora, md5('atascado:' || a.id)::uuid, 'atascado', 'administracion', 'abierta', j.persona_id)
  on conflict (id_cliente) do nothing
  returning id into v_inc;
  if v_inc is null then
    select id into v_inc from public.incidencias where id_cliente = md5('atascado:' || a.id)::uuid;
  end if;
  update public.atascados set estado = 'administracion', incidencia_id = v_inc where id = a.id;
  perform motor.registrar('atascado_a_administracion', null, j.id, a.tarea_id,
                          jsonb_build_object('atascado', a.id, 'incidencia', v_inc, 'a_las', p_ahora));
end;
$$;

-- Al acabar su martes, lo ofrecido que nadie ha pedido pasa a Administración. Se hace al leer (tienda_hoy,
-- incidencias_tiendas y decidir_atascado), como la bolsa de la tienda.
create or replace function motor.vencer_atascados(p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  v_id uuid;
begin
  for v_id in select a.id from public.atascados a
               where a.estado = 'ofrecido' and a.fecha < motor.fecha_local(p_ahora)
               order by a.creada_en for update skip locked loop
    perform motor.atascado_a_administracion(v_id, p_ahora);
  end loop;
end;
$$;

-- Hay que moverlo (lo pide otra tienda o va al almacén): incidencia sin hora para Eder y aviso a la tienda que lo tiene.
create or replace function motor.mover_atascado(p_id uuid, p_por uuid, p_jornada uuid, p_desde timestamptz, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  a public.atascados;
  v_tienda text;
  v_destino text;
  v_inc uuid;
  v_aviso uuid;
  v_creador uuid;
begin
  select * into a from public.atascados where id = p_id;
  select nombre into v_tienda from public.centros_trabajo where id = a.centro_id;
  v_destino := case
    when a.pedido_por is null then 'al almacén'
    when (select d.tipo from motor.destino_peticion(a.pedido_por) d) = 'envio'
      then 'al almacén: va en el siguiente envío a ' || (select nombre from public.centros_trabajo where id = a.pedido_por)
    else 'a ' || (select nombre from public.centros_trabajo where id = a.pedido_por) end;
  insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, quien, estado, creada_por)
  select p_jornada, j.persona_id,
         'Recoge ' || motor.cajas_texto(a.cantidad, a.producto, a.formato) || ' en ' || v_tienda || ' y llévalo ' || v_destino,
         p_desde, md5('atascado:' || a.id || ':recogida')::uuid, 'recogida_atascado', 'operario', 'abierta', p_por
    from public.jornadas j where j.id = p_jornada
  on conflict (id_cliente) do nothing
  returning id into v_inc;
  -- El aviso viene de quien lo decide: Administración, o el almacén si lo ha pedido otra tienda.
  v_creador := case when (select rol from public.personas where id = p_por) = 'administracion' then p_por
                    else motor.operario_por_defecto() end;
  v_aviso := motor.avisar_atascado(v_creador, a.centro_id, 'atascado:' || a.id || ':aviso',
                                   'Prepara ' || motor.cajas_texto(a.cantidad, a.producto, a.formato) || ' para recogida',
                                   p_ahora);
  update public.atascados set estado = 'por_recoger', recogida_id = coalesce(v_inc, recogida_id), aviso_id = v_aviso
   where id = a.id;
  perform motor.registrar('atascado_recogida', p_por, p_jornada, null,
                          jsonb_build_object('atascado', a.id, 'incidencia', v_inc, 'a_las', p_ahora));
end;
$$;

-- Eder cierra su recogida: entregado. Si lo pidió una tienda que recibe por envío, queda como petición de esa tienda
-- para su siguiente envío (decisión del propietario, 04/11/2026), como las muestras y el material.
create or replace function motor.atascado_entregado(p_incidencia uuid, p_persona uuid, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  a public.atascados;
  d record;
  v_pet uuid;
begin
  select * into a from public.atascados where recogida_id = p_incidencia for update;
  if a.id is null or a.estado <> 'por_recoger' then
    return;
  end if;
  if a.pedido_por is not null then
    select x.tipo, x.prefijo into d from motor.destino_peticion(a.pedido_por) x;
    if d.tipo = 'envio' then
      insert into public.peticiones_tienda (centro_id, tipo, detalle, texto, producto, formato, cantidad, id_cliente,
                                            persona_tienda_id, nombre, creada_en)
      values (a.pedido_por, 'atascado', motor.cajas_texto(a.cantidad, a.producto, a.formato),
              left(coalesce(d.prefijo, '') || 'Atascado de ' || (select nombre from public.centros_trabajo where id = a.centro_id)
                   || ': ' || motor.cajas_texto(a.cantidad, a.producto, a.formato), 120),
              a.producto, a.formato, a.cantidad, md5('atascado:' || a.id || ':peticion')::uuid,
              a.pedido_por_persona, a.pedido_por_nombre, p_ahora)
      on conflict (id_cliente) do nothing
      returning id into v_pet;
    end if;
  end if;
  update public.atascados set estado = 'entregado', terminado_en = p_ahora, peticion_id = coalesce(v_pet, peticion_id)
   where id = a.id;
  perform motor.registrar('atascado_entregado', p_persona, null, null,
                          jsonb_build_object('atascado', a.id, 'peticion', v_pet, 'a_las', p_ahora));
end;
$$;

-- Cómo lo ve cada uno: 'tiene' (la tienda que lo tiene), 'pide' (la que lo ha pedido) o 'admin'.
create or replace function motor.atascado_json(p_id uuid, p_vista text, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', a.id, 'tienda_id', a.centro_id, 'tienda', c.nombre, 'fecha', a.fecha,
    'producto', a.producto, 'formato', a.formato, 'cantidad', a.cantidad,
    'texto', motor.cajas_texto(a.cantidad, a.producto, a.formato), 'nota', a.nota, 'por', a.nombre,
    'estado', x.estado,
    'estado_texto', case p_vista
      when 'pide' then case x.estado
        when 'por_recoger' then 'Lo has pedido: el almacén lo recoge en ' || c.nombre
                                || case when dp.tipo = 'envio' then ' y va en tu siguiente envío' else ' y te lo trae' end
        when 'entregado' then case when pt.id is not null then motor.peticion_tienda_json(pt, p_ahora) ->> 'estado_texto'
                                   else 'Entregado el ' || to_char(motor.fecha_local(a.terminado_en), 'DD/MM') end
        else 'Lo has pedido' end
      else case x.estado
        when 'ofrecido' then 'Ofrecido a las demás tiendas hasta el cierre del ' || to_char(a.fecha, 'DD/MM')
        when 'administracion' then case when motor.atascados_va_a(a.centro_id) = 'ofrecer'
                                        then 'Nadie lo ha pedido: decide Administración' else 'Decide Administración' end
        when 'promocion' then 'En promoción: ' || a.decision_texto
        when 'por_recoger' then case when a.pedido_por is not null then 'Lo quiere ' || pc.nombre || ': prepáralo para recogida'
                                     else 'Al almacén: prepáralo para recogida' end
        when 'entregado' then 'Recogido el ' || to_char(motor.fecha_local(a.terminado_en), 'DD/MM')
                              || ' a las ' || motor.hora_texto(a.terminado_en)
        when 'terminado' then 'Promoción terminada: ya no queda'
        else case when a.decision = 'recogida' then 'Recogida: la organiza Administración' || coalesce(' (' || a.decision_texto || ')', '')
                  else 'Cerrado por Administración' || coalesce(': ' || i.nota_cierre, '') end end end,
    'pedido_por', pc.nombre, 'pedido_por_nombre', a.pedido_por_nombre,
    'promocion', case when a.decision = 'promocion' then a.decision_texto end,
    'decision', a.decision,
    -- Lo que Administración puede decidir mientras está con ella.
    'decisiones', case when x.estado = 'administracion'
                       then case when motor.atascados_va_a(a.centro_id) = 'ofrecer' then '["promocion", "almacen"]'::jsonb
                                 else '["promocion", "recogida"]'::jsonb end
                       else '[]'::jsonb end)
  from public.atascados a
  join public.centros_trabajo c on c.id = a.centro_id
  left join public.centros_trabajo pc on pc.id = a.pedido_por
  left join public.incidencias i on i.id = a.incidencia_id
  left join public.peticiones_tienda pt on pt.id = a.peticion_id
  left join lateral motor.destino_peticion(a.pedido_por) dp on a.pedido_por is not null
  -- Si Administración la cierra sin decidir (cerrar_incidencia_tienda), queda cerrado.
  cross join lateral (select case when a.estado = 'administracion' and i.estado = 'cerrada' then 'cerrado'
                                  else a.estado end as estado) x
  where a.id = p_id
$$;

-- Lo de la tableta: lo suyo, las ofertas de las demás (su martes), lo que ha pedido y sus promociones abiertas.
create or replace function motor.atascados_tienda_json(p_centro uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'atascados', coalesce((
      select jsonb_agg(motor.atascado_json(a.id, 'tiene', p_ahora) order by a.creada_en desc, a.producto)
        from public.atascados a
       where a.centro_id = p_centro
         and (a.estado in ('ofrecido', 'administracion', 'promocion', 'por_recoger')
              or coalesce(a.terminado_en, a.decidido_en, a.creada_en) >= motor.en_local(motor.fecha_local(p_ahora) - 7, '00:00'))),
      '[]'::jsonb),
    'ofertas_atascados', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'tienda_id', a.centro_id, 'tienda', c.nombre,
               'producto', a.producto, 'formato', a.formato, 'cantidad', a.cantidad, 'nota', a.nota,
               'texto', c.nombre || ' tiene ' || motor.cajas_texto(a.cantidad, a.producto, a.formato)
                        || case when a.cantidad = 1 then ' que no se mueve: ¿la quieres?'
                                else ' que no se mueven: ¿las quieres?' end)
               order by a.creada_en, a.producto)
        from public.atascados a join public.centros_trabajo c on c.id = a.centro_id
       where a.estado = 'ofrecido' and a.fecha = motor.fecha_local(p_ahora) and a.centro_id <> p_centro
         and motor.atascados_va_a(a.centro_id) = 'ofrecer'), '[]'::jsonb),
    'atascados_pedidos', coalesce((
      select jsonb_agg(motor.atascado_json(a.id, 'pide', p_ahora) order by a.pedido_en desc)
        from public.atascados a
       where a.pedido_por = p_centro
         and (a.estado = 'por_recoger' or a.pedido_en >= motor.en_local(motor.fecha_local(p_ahora) - 7, '00:00'))),
      '[]'::jsonb),
    'promociones', coalesce((
      select jsonb_agg(jsonb_build_object('id', a.id, 'producto', a.producto, 'formato', a.formato, 'cantidad', a.cantidad,
                                          'texto', motor.cajas_texto(a.cantidad, a.producto, a.formato),
                                          'promocion', a.decision_texto, 'desde', motor.fecha_local(a.decidido_en))
                       order by a.decidido_en)
        from public.atascados a where a.centro_id = p_centro and a.estado = 'promocion'), '[]'::jsonb))
$$;

-- ---------------------------------------------------------------------------
-- 5. La tienda: el martes, «Las quiero» y «Ya no queda»
-- ---------------------------------------------------------------------------
create or replace function motor.revisar_atascados_de(p_persona uuid, p_tarea uuid, p_atascados jsonb, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'atascados', p_ahora);
  t public.tareas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_lista jsonb := coalesce(motor.productos_tienda_de() -> 'productos', '[]'::jsonb);
  v_elegidos jsonb := '[]';
  v_va_a text;
  x jsonb;
  p jsonb;
  v_formato text;
  v_nota text;
  v_id uuid;
begin
  if v_error is not null then
    return v_error;
  end if;
  if p_atascados is not null and jsonb_typeof(p_atascados) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista qué productos no se mueven.');
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_atascados, '[]')) loop
    v_formato := coalesce(x ->> 'formato', '');
    select l into p from jsonb_array_elements(v_lista) l
     where l ->> 'producto' = x ->> 'producto' and l -> 'formatos' ? v_formato;
    if p is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista: «' || btrim(coalesce(x ->> 'producto', '') || ' ' || v_formato)
                                             || '» no está.',
                         jsonb_build_object('producto', x ->> 'producto', 'formato', x ->> 'formato'));
    end if;
    if x ? 'cantidad' and (jsonb_typeof(x -> 'cantidad') is distinct from 'number'
                           or (x ->> 'cantidad')::numeric not between 1 and 99
                           or (x ->> 'cantidad')::numeric <> trunc((x ->> 'cantidad')::numeric)) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas cajas de ' || btrim((p ->> 'producto') || ' ' || v_formato) || ': de 1 a 99.');
    end if;
    v_nota := nullif(btrim(regexp_replace(coalesce(x ->> 'nota', ''), '\s+', ' ', 'g')), '');
    if length(v_nota) > 200 then
      return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
    end if;
    if exists (select 1 from jsonb_array_elements(v_elegidos) e
                where e ->> 'producto' = p ->> 'producto' and e ->> 'formato' = v_formato) then
      return motor.error('DATOS_NO_VALIDOS', 'Cada producto, una sola vez.');
    end if;
    v_elegidos := v_elegidos || jsonb_build_object('producto', p ->> 'producto', 'formato', v_formato,
                                                   'cantidad', coalesce((x ->> 'cantidad')::numeric::int, 1), 'nota', v_nota);
  end loop;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  tt := motor.en_turno_tienda(j.id);
  v_va_a := motor.atascados_va_a(j.centro_id);
  for p in select * from jsonb_array_elements(v_elegidos) loop
    insert into public.atascados (centro_id, fecha, tarea_id, producto, formato, cantidad, nota, persona_tienda_id, nombre,
                                  creada_en, estado)
    values (j.centro_id, j.fecha, t.id, p ->> 'producto', p ->> 'formato', (p ->> 'cantidad')::int, p ->> 'nota',
            tt.persona_tienda_id, tt.nombre, p_ahora, case when v_va_a = 'ofrecer' then 'ofrecido' else 'administracion' end)
    returning id into v_id;
    -- Franquicias: no se ofrece; va directo a Administración.
    if v_va_a <> 'ofrecer' then
      perform motor.atascado_a_administracion(v_id, p_ahora);
    end if;
  end loop;
  perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha',
            case when jsonb_array_length(v_elegidos) = 0 then 'Nada atascado esta semana'
                 else 'Atascados: ' || jsonb_array_length(v_elegidos) end,
            null, 'tarea_terminada', p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

create or replace function motor.querer_atascado_de(p_persona uuid, p_id uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  a public.atascados;
  v_jornada uuid;
  tt public.turnos_tienda;
  r record;
begin
  select * into pe from public.personas where id = p_persona;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  -- La primera que lo pide se lo lleva: las demás esperan a que termine y ya no lo encuentran ofrecido.
  select * into a from public.atascados where id = p_id for update;
  if a.id is null or a.centro_id = pe.centro_id or motor.atascados_va_a(a.centro_id) <> 'ofrecer' then
    return motor.error('NO_ENCONTRADO', 'Esa oferta no existe.');
  end if;
  if a.pedido_por = pe.centro_id then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  if a.estado <> 'ofrecido' or a.fecha <> motor.fecha_local(p_ahora) then
    return motor.error('ESTADO_NO_VALIDO',
                       case when a.pedido_por is not null
                            then 'Ya lo ha pedido ' || (select nombre from public.centros_trabajo where id = a.pedido_por) || '.'
                            else 'Esta oferta ya ha terminado.' end);
  end if;
  select * into r from motor.jornada_recogida(p_ahora);
  if r.jornada is null then
    return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
  end if;
  update public.atascados
     set pedido_por = pe.centro_id, pedido_por_persona = tt.persona_tienda_id, pedido_por_nombre = tt.nombre, pedido_en = p_ahora
   where id = a.id;
  perform motor.mover_atascado(a.id, p_persona, r.jornada, r.desde, p_ahora);
  perform motor.registrar('atascado_pedido', p_persona, v_jornada, null,
                          jsonb_build_object('atascado', a.id, 'por', tt.nombre, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

create or replace function motor.ya_no_queda_de(p_persona uuid, p_id uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  a public.atascados;
  v_jornada uuid;
  tt public.turnos_tienda;
begin
  select * into pe from public.personas where id = p_persona;
  select * into a from public.atascados where id = p_id and centro_id = pe.centro_id for update;
  if a.id is null or a.decision is distinct from 'promocion' then
    return motor.error('NO_ENCONTRADO', 'Esa promoción no existe.');
  end if;
  if a.estado <> 'promocion' then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  update public.atascados set estado = 'terminado', terminado_en = p_ahora, terminado_por = tt.nombre where id = a.id;
  perform motor.registrar('promocion_terminada', p_persona, v_jornada, null,
                          jsonb_build_object('atascado', a.id, 'por', tt.nombre, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Administración decide
-- ---------------------------------------------------------------------------
-- promocion (con su texto: aviso a la tienda y abierta hasta «Ya no queda») · almacen (propias: recogida de Eder) ·
-- recogida (franquicias: la organiza Administración; se cierra con su nota). La incidencia queda cerrada con la decisión.
create or replace function motor.decidir_atascado_de(p_admin uuid, p_id uuid, p_decision text, p_texto text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  a public.atascados;
  i public.incidencias;
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
  v_ofrece boolean;
  v_nota text;
  r record;
begin
  perform motor.vencer_atascados(p_ahora);
  select * into a from public.atascados where id = p_id for update;
  if a.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese atascado no existe.');
  end if;
  select * into i from public.incidencias where id = a.incidencia_id;
  if a.estado <> 'administracion' or i.estado = 'cerrada' then
    return motor.error('ESTADO_NO_VALIDO', 'Este atascado ya está decidido.');
  end if;
  v_ofrece := motor.atascados_va_a(a.centro_id) = 'ofrecer';
  if p_decision is null or p_decision not in ('promocion', case when v_ofrece then 'almacen' else 'recogida' end) then
    return motor.error('DATOS_NO_VALIDOS', case when v_ofrece then 'Elige: promoción o al almacén.'
                                                else 'Elige: promoción o recogida.' end);
  end if;
  if length(v_texto) > 180 then
    return motor.error('DATOS_NO_VALIDOS', 'En una línea (180 letras como máximo).');
  end if;
  if p_decision = 'promocion' then
    if v_texto is null then
      return motor.error('DATOS_NO_VALIDOS', 'Escribe la promoción.');
    end if;
    update public.atascados
       set estado = 'promocion', decision = 'promocion', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora,
           aviso_id = motor.avisar_atascado(p_admin, a.centro_id, 'atascado:' || a.id || ':promocion',
                                            'Promoción de ' || motor.cajas_texto(a.cantidad, a.producto, a.formato) || ': ' || v_texto,
                                            p_ahora)
     where id = a.id;
    v_nota := 'Promoción: ' || v_texto;
  elsif p_decision = 'almacen' then
    select * into r from motor.jornada_recogida(p_ahora);
    if r.jornada is null then
      return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
    end if;
    update public.atascados set decision = 'almacen', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora
     where id = a.id;
    perform motor.mover_atascado(a.id, p_admin, r.jornada, r.desde, p_ahora);
    v_nota := 'Al almacén' || coalesce(': ' || v_texto, '');
  else
    update public.atascados
       set estado = 'cerrado', decision = 'recogida', decision_texto = v_texto, decidido_por = p_admin, decidido_en = p_ahora
     where id = a.id;
    v_nota := 'Recogida' || coalesce(': ' || v_texto, '');
  end if;
  perform motor.cerrar_incidencia_tienda_de(p_admin, i.id, v_nota, p_ahora);
  perform motor.registrar('atascado_decidido', p_admin, i.jornada_id, null,
                          jsonb_build_object('atascado', a.id, 'decision', p_decision, 'a_las', p_ahora));
  return motor.incidencias_tiendas_de(p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Funciones que se rehacen (solo se añade lo de los atascados)
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

create or replace function motor.incidencia_json(p_incidencia uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', i.id, 'opcion', i.opcion, 'opcion_texto', motor.texto_opcion(i.opcion),
    'descripcion', i.descripcion, 'quien', i.quien, 'importancia', i.importancia,
    'estado', i.estado,
    'estado_texto', case
      when i.estado = 'cerrada' then 'Cerrada a las ' || motor.hora_texto(i.terminada_en)
      when i.estado = 'esperando_llegada' then 'Pedido, esperando a que llegue'
      when i.estado = 'esperando_administracion' then 'Esperando a Administración'
      when i.opcion = 'aviso' then 'Aviso de Administración para el ' || to_char(motor.fecha_local(i.iniciada_en), 'DD/MM')
      -- Tarea 31: la recogida de un atascado no tiene hora ni toca el reparto.
      when i.opcion = 'recogida_atascado' then 'Sin hora: cuando puedas, sin tocar el reparto. Ciérrala al entregarlo'
      when t.id is null then 'En curso desde las ' || motor.hora_texto(i.iniciada_en)
      when t.estado = 'en_curso' then 'En curso desde las ' || motor.hora_texto(t.iniciada_en)
      when t.estado = 'bloqueada' then 'Bloqueada por un problema'
      when t.estado = 'cancelada' then 'Su tarea se ha cancelado: ciérrala si ya está resuelta'
      when i.importancia = 'ahora' then 'Va ahora, al terminar lo que tienes entre manos'
      when i.importancia = 'hoy' then 'Pendiente para hoy'
      else 'En tu cola de tiempo libre' end,
    'abierta_en', i.iniciada_en, 'desde', motor.hora_texto(i.iniciada_en), 'fecha', motor.fecha_local(i.iniciada_en),
    'cerrada_en', i.terminada_en, 'nota', i.nota_cierre, 'tarea_id', i.tarea_resolucion_id, 'compra_id', i.compra_id,
    'minutos', round(extract(epoch from case
        when t.iniciada_en is not null then coalesce(t.terminada_en, p_ahora) - t.iniciada_en
        when t.id is not null then null
        else coalesce(i.terminada_en, p_ahora) - i.iniciada_en end) / 60)::int)
  from public.incidencias i
  left join public.tareas t on t.id = i.tarea_resolucion_id
  where i.id = p_incidencia;
$$;

create or replace function motor.texto_opcion(p_opcion text)
returns text language sql immutable set search_path = '' as $$
  select case p_opcion
    when 'llega_mercancia' then 'Llega mercancía'
    when 'pedido_cliente' then 'Pedido de cliente'
    when 'pedir_comprar' then 'Hay que pedir o comprar algo'
    when 'recogida_nacex' then 'Recogida en Nacex'
    when 'corregir' then 'Corregir, limpiar o solucionar algo'
    when 'bloqueado' then 'Estoy bloqueado'
    when 'comprar' then 'Hay que comprar algo'
    when 'varios' then 'Varios'
    when 'aviso' then 'Aviso de Administración'
    -- Tarea 31.
    when 'recogida_atascado' then 'Recoger un producto atascado'
    when 'atascado' then 'Producto atascado'
    else 'Incidencia' end;
$$;

create or replace function motor.cerrar_incidencia_de(p_persona uuid, p_incidencia uuid, p_nota text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
  t public.tareas;
begin
  select * into i from public.incidencias where id = p_incidencia for update;
  if i.id is null or i.persona_id is distinct from p_persona then
    return motor.error('NO_ENCONTRADO', 'Esa incidencia no existe.');
  end if;
  if i.estado = 'cerrada' then
    return jsonb_build_object('incidencia', motor.incidencia_json(i.id, p_ahora),
                              'aviso', jsonb_build_object('codigo', 'INCIDENCIA_YA_CERRADA', 'mensaje', 'Esta incidencia ya estaba cerrada.'),
                              'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;

  -- Su tarea, si sigue abierta, ya no hace falta.
  select * into t from public.tareas where id = i.tarea_resolucion_id;
  if t.estado in ('pendiente', 'en_curso', 'bloqueada') then
    perform motor.cancelar_tarea_de(p_persona, t.id, 'Ya no hace falta: incidencia cerrada', p_ahora);
    update public.tareas set terminada_en = p_ahora where id = t.id and iniciada_en is not null and terminada_en is null;
  end if;

  update public.incidencias
     set estado = 'cerrada', terminada_en = p_ahora, cerrada_por = p_persona,
         nota_cierre = nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '')
   where id = i.id;
  perform motor.registrar('incidencia_cerrada', p_persona, i.jornada_id, i.tarea_resolucion_id,
                          jsonb_build_object('incidencia', i.id, 'por', 'a mano', 'a_las', p_ahora));
  -- Tarea 31: la recogida de un atascado, entregada (y, si va a una tienda por envío, en su siguiente envío).
  if i.opcion = 'recogida_atascado' then
    perform motor.atascado_entregado(i.id, p_persona, p_ahora);
  end if;
  return jsonb_build_object('incidencia', motor.incidencia_json(i.id, p_ahora),
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.incidencias_tiendas_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('incidencias', coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'tienda_id', c.id, 'tienda', c.nombre, 'opcion', i.opcion, 'texto', i.descripcion,
           'fecha', motor.fecha_local(i.iniciada_en), 'a_las', motor.hora_texto(i.iniciada_en), 'estado', i.estado,
           'cerrada_en', i.terminada_en, 'nota', i.nota_cierre,
           -- Tarea 31: el atascado, con lo que se puede decidir (decidir_atascado).
           'atascado', (select motor.atascado_json(a.id, 'admin', p_ahora) from public.atascados a where a.incidencia_id = i.id))
           order by (i.estado = 'cerrada'), i.iniciada_en desc), '[]'::jsonb))
    from public.incidencias i
    join public.personas p on p.id = i.persona_id and p.rol = 'tienda'
    join public.centros_trabajo c on c.id = p.centro_id
   where i.opcion is distinct from 'aviso'
     and (i.estado <> 'cerrada' or i.terminada_en >= motor.en_local(motor.fecha_local(p_ahora) - 7, '00:00'))
$$;

create or replace function motor.api_incidencias_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  -- Tarea 31: lo ofrecido el martes que nadie ha pedido llega aquí al acabar el día.
  perform motor.vencer_atascados(now());
  return motor.incidencias_tiendas_de(now());
end; $$;

-- La tienda ve sus atascados en `atascados` (con su estado), no también en sus incidencias.
create or replace function motor.incidencias_tienda_json(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'opcion', i.opcion, 'texto', i.descripcion,
           'fecha', motor.fecha_local(i.iniciada_en), 'a_las', motor.hora_texto(i.iniciada_en),
           'estado', case when i.estado = 'cerrada' then 'cerrada' else 'abierta' end,
           'estado_texto', case when i.estado = 'cerrada'
                                then 'Resuelta por Administración' || coalesce(': ' || i.nota_cierre, '')
                                else 'Abierta' end)
           order by (i.estado = 'cerrada'), i.iniciada_en desc), '[]'::jsonb)
    from public.incidencias i
   where i.persona_id = p_persona and i.opcion is distinct from 'aviso' and i.iniciada_en <= p_ahora
     and i.opcion is distinct from 'atascado'
     and (i.estado <> 'cerrada' or motor.fecha_local(i.terminada_en) = motor.fecha_local(p_ahora))
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
  v_atascados jsonb;
begin
  select * into pe from public.personas where id = p_persona;
  select * into c from public.centros_trabajo where id = pe.centro_id;
  v_jornada := motor.generar_jornada(p_persona, v_hoy);
  -- Tarea 28: si ha salido el reparto y trae bolsa para esta tienda, «Recibe la bolsa».
  perform motor.preparar_bolsa_tienda(p_persona, v_jornada, p_ahora);
  -- Tarea 30b: las tiendas que reciben por envío, los envíos que les han salido.
  perform motor.preparar_envios_tienda(p_persona, p_ahora);
  -- Tarea 31: lo ofrecido el martes que nadie ha pedido pasa a Administración.
  perform motor.vencer_atascados(p_ahora);
  v_atascados := motor.atascados_tienda_json(c.id, p_ahora);
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
      select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'fecha', motor.fecha_local(i.iniciada_en),
                                          -- Tarea 29: de quién viene («Almacén» o «Administración»).
                                          'de', case when a.rol = 'operario' then 'Almacén' else 'Administración' end)
                       order by i.iniciada_en)
        from public.incidencias i left join public.personas a on a.id = i.creada_por
       where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'tareas', coalesce((
      select jsonb_agg(motor.tarea_tienda_json(t.id, p_ahora) order by t.disponible_desde, t.orden, t.creada_en)
        from public.tareas t where t.jornada_id = v_jornada and not t.retirada_por_condicion), '[]'::jsonb),
    -- Tarea 28: por dónde va el reparto, las peticiones (muestras y material) y si puede pedir material.
    'reparto', motor.seguimiento_reparto_json(c.id, v_hoy, p_ahora),
    'peticiones', motor.peticiones_tienda_json(c.id, p_ahora),
    'pedir_material', coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                                 where k.clave = 'pedir_material' and k.centro_id = c.id), false),
    -- Tarea 30: las incidencias de la tienda (abiertas y cerradas hoy) y qué opciones tiene.
    'incidencias', motor.incidencias_tienda_json(p_persona, p_ahora),
    'opciones_incidencia', motor.opciones_incidencia_json(c.id),
    -- Tarea 30b: «Envíos» (tiendas que reciben por envío) y cuántos quedan sin confirmar.
    'envios', motor.envios_tienda_json(c.id, p_ahora),
    'envios_sin_confirmar', (select count(*)::int from public.bolsas_tienda b join public.repartos r on r.id = b.reparto_id
                              where b.centro_id = c.id and r.tipo = 'envio' and b.reposicion is null),
    -- Tarea 30c: los pedidos de cliente para recoger en la tienda, con su estado.
    'pedidos', motor.pedidos_de_tienda_json(c.id, p_ahora),
    -- Tarea 31: lo atascado de la tienda, las ofertas de las demás («Las quiero»), lo que ha pedido y sus promociones
    -- abiertas («Ya no queda»).
    'atascados', v_atascados -> 'atascados',
    'ofertas_atascados', v_atascados -> 'ofertas_atascados',
    'atascados_pedidos', v_atascados -> 'atascados_pedidos',
    'promociones', v_atascados -> 'promociones');
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Entradas de la API
-- ---------------------------------------------------------------------------
create or replace function motor.api_revisar_atascados(p_tarea_id uuid, p_atascados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.revisar_atascados_de(auth.uid(), p_tarea_id, p_atascados, now());
end; $$;

create or replace function motor.api_querer_atascado(p_atascado_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.querer_atascado_de(auth.uid(), p_atascado_id, now());
end; $$;

create or replace function motor.api_ya_no_queda(p_atascado_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.ya_no_queda_de(auth.uid(), p_atascado_id, now());
end; $$;

create or replace function motor.api_decidir_atascado(p_atascado_id uuid, p_decision text, p_texto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.decidir_atascado_de(auth.uid(), p_atascado_id, p_decision, p_texto, now());
end; $$;

create or replace function public.revisar_atascados(tarea_id uuid, atascados jsonb default '[]')
returns jsonb language sql set search_path = '' as $$ select motor.api_revisar_atascados(tarea_id, atascados) $$;
create or replace function public.querer_atascado(atascado_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_querer_atascado(atascado_id) $$;
create or replace function public.ya_no_queda(atascado_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_ya_no_queda(atascado_id) $$;
create or replace function public.decidir_atascado(atascado_id uuid, decision text, texto text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_decidir_atascado(atascado_id, decision, texto) $$;

revoke execute on all functions in schema motor from public;
grant execute on function motor.api_revisar_atascados(uuid, jsonb), motor.api_querer_atascado(uuid),
  motor.api_ya_no_queda(uuid), motor.api_decidir_atascado(uuid, text, text) to authenticated;
revoke execute on function public.revisar_atascados(uuid, jsonb), public.querer_atascado(uuid), public.ya_no_queda(uuid),
  public.decidir_atascado(uuid, text, text) from public, anon;
grant execute on function public.revisar_atascados(uuid, jsonb), public.querer_atascado(uuid), public.ya_no_queda(uuid),
  public.decidir_atascado(uuid, text, text) to authenticated;
