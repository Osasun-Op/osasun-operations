-- Tarea 27 · Tiendas, primera parte: acceso, personas, horario, festivos y tareas del día
-- (ESTADO_DEL_SISTEMA.md E2-8; AGENTE_COORDINADOR.md, bloque 1, puntos 1 a 30). En pruebas.
-- Reutiliza el motor: cada tienda entra con su cuenta (cuentas autorizadas, rol `tienda`, con su
-- centro) y tiene su jornada con generar_jornada, sus tareas con plantillas por centro y sus avisos
-- con las incidencias «aviso» de la Tarea 22. Lo del almacén no cambia de comportamiento.
--   1. Rol `tienda`. Una tienda solo usa sus funciones; las del almacén y las de Administración
--      la rechazan (persona_actual(null) pasa a ser «del almacén»; servidor_preparar también).
--   2. Horario de cada tienda: configuración `horario_tienda` por centro (se copia a su ficha al
--      darse de alta). Bilbao: configuración `alternar_semanales` (las semanales cambian de turno
--      según la semana ISO: par por la mañana, impar por la tarde).
--   3. Personas de cada tienda (`personas_tienda`) y quién está en cada turno (`turnos_tienda`).
--   4. Días cerrados (`dias_cerrados`): una tienda o todas; ese día no hay jornada.
--   5. Plantillas de tienda (una por tienda; se activan por tienda con `activa`): con puntos
--      (`puntos`, elementos de tipo `punto`) y con la hora relativa al horario (`hora_desde`,
--      `minutos_desde`, `alterna_turno`). Vídeo de la semana (`videos_tienda`).
--   6. La huella ordena y distingue por centro las filas de configuración y de plantillas.
--   7. Los cierres de turno (correo) siguen siendo solo del almacén.
--
-- Deshacer: borrar las funciones nuevas (motor.*tienda*, motor.dia_cerrado, motor.desde_plantilla,
-- motor.es_tienda y sus public.*), las tablas personas_tienda, turnos_tienda, dias_cerrados y
-- videos_tienda, las plantillas y la configuración de las tiendas, las columnas nuevas de
-- plantillas_tarea; volver a crear motor.persona_actual y motor.api_mi_perfil (20261026175746),
-- motor.insertar_desde_plantilla (20261026185130), motor.generar_jornada y motor.jornada_para
-- (20261026202655), motor.generar_cierres_programados (20261026202909), motor.alta_cuenta_autorizada
-- (20261027093102), public.servidor_preparar y public.servidor_preparar_pedido (20261028160000) y
-- motor.huella_estructura (20261102173657) como estaban; las políticas de configuracion y
-- pedidos_cliente como estaban; y los checks de personas.rol, tarea_elementos.tipo y contenido.

-- ---------------------------------------------------------------------------
-- 1. Rol tienda, elementos «punto» y contenidos de tienda
-- ---------------------------------------------------------------------------
alter table public.personas drop constraint personas_rol_check;
alter table public.personas add constraint personas_rol_check check (rol in ('administracion', 'operario', 'tienda'));
alter table public.tarea_elementos drop constraint tarea_elementos_tipo_check;
alter table public.tarea_elementos add constraint tarea_elementos_tipo_check
  check (tipo in ('referencia_produccion', 'caja_bolsa', 'peticion', 'llamada', 'punto'));
alter table public.plantillas_tarea drop constraint plantillas_tarea_contenido_check;
alter table public.plantillas_tarea add constraint plantillas_tarea_contenido_check
  check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento', 'puntos', 'video'));
alter table public.tareas drop constraint tareas_contenido_check;
alter table public.tareas add constraint tareas_contenido_check
  check (contenido in ('simple', 'produccion_reparto', 'bolsas', 'stock_35', 'recuento', 'puntos', 'video'));

-- Plantillas de tienda: puntos que se tocan uno a uno y hora relativa al horario de la tienda.
alter table public.plantillas_tarea
  add column puntos text[] not null default '{}',
  add column hora_desde text check (hora_desde in ('inicio', 'fin')),
  add column minutos_desde integer not null default 0,
  add column alterna_turno boolean not null default false;
comment on column public.plantillas_tarea.puntos is 'Tienda: puntos de la tarea (elementos de tipo punto); se da por hecha al tocar el último.';
comment on column public.plantillas_tarea.hora_desde is 'Tienda: la tarea sale desde el inicio o el fin de su turno (o del primero/último del día si no tiene turno), más minutos_desde. Null: como siempre (almacén).';
comment on column public.plantillas_tarea.alterna_turno is 'Tienda: si la tienda tiene alternar_semanales, el turno cambia cada semana (ISO par: mañana; impar: tarde).';

create or replace function motor.es_tienda()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.personas p where p.id = auth.uid() and p.activo and p.rol = 'tienda');
$$;

-- persona_actual: sin rol pedido, solo las del almacén; '*' cualquiera (mi_perfil).
create or replace function motor.persona_actual(p_rol_exigido text default null)
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare
  v_rol text;
begin
  if auth.uid() is null then
    return motor.error('NO_AUTENTICADO', 'Tienes que iniciar sesión.');
  end if;
  select rol into v_rol from public.personas where id = auth.uid() and activo;
  -- Sin rol pedido: las del almacén (operario o Administración); una tienda no entra (Tarea 27).
  -- '*': cualquiera con ficha (mi_perfil).
  if v_rol is null
     or (p_rol_exigido is null and v_rol = 'tienda')
     or (p_rol_exigido is not null and p_rol_exigido <> '*' and v_rol <> p_rol_exigido) then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  return null;
end;
$$;

create or replace function motor.api_mi_perfil()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  return motor.mi_perfil_de(auth.uid());
end;
$$;

create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_operario uuid;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
  v_recuento timestamptz;
  v_desde timestamptz;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null or v_rol = 'tienda' then  -- una tienda no usa las funciones del reparto (Tarea 27)
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada := motor.generar_jornada(v_operario, v_fecha);
  end if;
  if v_rol = 'operario' and v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;

  select h.turno into v_turno from public.horarios h
   where h.persona_id = v_operario and h.dia_semana = extract(isodow from v_fecha)
     and motor.en_local(v_fecha, h.hora_inicio) <= p_ahora
   order by h.hora_inicio desc limit 1;
  v_turno := coalesce(v_turno, 'manana');

  select t.id into v_stock from public.tareas t
   where t.jornada_id = v_jornada and t.clave = 'cola_stock'
     and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.lote = v_turno);

  -- La hoja que se lee ahora recoge el último recuento: desde ahí cuentan lo producido y lo salido.
  v_recuento := motor.ultimo_recuento(v_operario, p_ahora);
  v_desde := coalesce(v_recuento, p_ahora);

  return jsonb_build_object(
    'persona_id', p_persona, 'rol', v_rol, 'jornada_id', v_jornada,
    'fecha', v_fecha, 'dia', extract(day from v_fecha)::int, 'mes', extract(month from v_fecha)::int,
    'turno', v_turno,
    'destinos', (select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre,
                                                     'tipo', c.tipo, 'activo', c.activo, 'alias', to_jsonb(c.alias))
                                  order by c.codigo)
                 from public.centros_trabajo c where c.tipo <> 'almacen'),
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas',
                                                         'stock_objetivo_pct', 'stock_excluidos',
                                                         'destinos_reparto')),
    'repartos', jsonb_build_object(
      'reparto', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                  from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'),
      'envio', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'envio' and r.estado = 'aceptado')),
    'reparto_hoy', coalesce((select jsonb_agg(jsonb_build_object('producto', x ->> 'producto',
                                                                 'formato', coalesce(x ->> 'formato', ''),
                                                                 'pedido', (x ->> 'pedido')::int))
                             from public.repartos r, jsonb_array_elements(r.resultado -> 'produccion') x
                             where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'), '[]'::jsonb),
    'recuento_manana_hecho', exists (select 1 from public.tareas t
                                     where t.jornada_id = v_jornada and t.clave = 'recuento_manana' and t.estado = 'hecha'),
    -- R1c: lo que aún no ha salido del almacén (reparto, envío, pedidos) y lo que va en camino a las tiendas.
    'comprometido', motor.comprometido_en(v_jornada, p_ahora),
    -- R1c: lo producido y lo salido desde el último recuento (la hoja aún no lo recoge).
    'almacen', jsonb_build_object(
      'recuento_en', v_recuento,
      'producido', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido'),
      'producido_reparto', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido', true,
                             (select id from public.tareas where jornada_id = v_jornada and clave = 'produccion_reparto')),
      'producido_envio', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'producido', true,
                           (select id from public.tareas where jornada_id = v_jornada
                               and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1)),
      'salido', motor.cajas_movimiento(v_operario, v_desde, p_ahora, 'salido')),
    -- Pedidos de cliente para recoger en tienda que van en el reparto de hoy (en orden de llegada).
    'pedidos_tienda', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'cliente', p.cliente, 'destino_id', p.destino_id,
                                          'lineas', p.lineas) order by p.registrado_en)
        from public.pedidos_cliente p
        left join public.tareas t on t.id = p.tarea_id
       where p.entrega = 'tienda' and t.estado is distinct from 'cancelada'
         and (p.jornada_id = v_jornada or (p.jornada_id is null and p.fecha_objetivo <= v_fecha))), '[]'::jsonb),
    'stock', case when v_stock is null or v_rol <> 'operario' then null else motor.tarea_json(v_stock) end);
end;
$$;

create or replace function public.servidor_preparar_pedido(
  p_persona uuid, p_id_cliente uuid, p_entrega text, p_destino uuid, p_ahora timestamptz default now())
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_operario uuid;
  v_hoy date := motor.fecha_local(p_ahora);
  v_jornada_hoy uuid;
  v_fecha date;
  v_jornada uuid;
  v_reparto uuid;
  v_previo uuid;
begin
  if v_rol is null or v_rol = 'tienda' then  -- una tienda no usa las funciones del reparto (Tarea 27)
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  select id into v_previo from public.pedidos_cliente where id_cliente = p_id_cliente;
  if v_previo is not null then
    return jsonb_build_object('previo', motor.pedido_json(v_previo));
  end if;
  if p_entrega is null or p_entrega not in ('tienda', 'nacex') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige cómo se entrega: recoger en tienda o envío por Nacex.');
  end if;
  if p_entrega = 'tienda' and not exists (
       select 1 from public.centros_trabajo c, public.configuracion k,
                     jsonb_array_elements_text(k.valor -> 'reparto') x
        where k.clave = 'destinos_reparto' and k.centro_id is null and c.id = p_destino and c.codigo = x) then
    return motor.error('DATOS_NO_VALIDOS', 'Elige una de las tiendas del reparto.');
  end if;

  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  if v_operario is not null then
    v_jornada_hoy := motor.generar_jornada(v_operario, v_hoy);
  end if;
  if p_entrega = 'tienda' then
    -- Hoy, mientras el reparto no haya salido (bolsas listas). Sin reparto todavía,
    -- mientras «Prepara el reparto» siga abierta: el pedido activa el reparto.
    select r.id into v_reparto from public.repartos r
     where r.jornada_id = v_jornada_hoy and r.tipo = 'reparto' and r.estado = 'aceptado';
    if v_jornada_hoy is not null
       and not exists (select 1 from public.tareas t
                        where t.jornada_id = v_jornada_hoy and t.clave = 'bolsas' and t.estado = 'hecha')
       and (v_reparto is not null
            or exists (select 1 from public.tareas t
                        where t.jornada_id = v_jornada_hoy and t.clave = 'pegar_reparto'
                          and t.estado in ('pendiente', 'en_curso', 'bloqueada'))) then
      v_fecha := v_hoy;
    elsif v_operario is not null then
      v_fecha := motor.siguiente_dia_trabajo(v_operario, v_hoy);
      v_reparto := null;
    end if;
  elsif v_jornada_hoy is not null
        and p_ahora < motor.en_local(v_hoy, case when extract(isodow from v_hoy) = 5 then time '10:45' else time '18:00' end)
        and not exists (select 1 from public.tareas t
                         where t.jornada_id = v_jornada_hoy and t.clave in ('nacex_salida', 'nacex_viernes')
                           and t.estado = 'hecha') then
    v_fecha := v_hoy;
    v_jornada := v_jornada_hoy;
  elsif v_operario is not null then
    v_fecha := motor.siguiente_dia_trabajo(v_operario, v_hoy);
    v_jornada := motor.jornada_para(v_operario, v_fecha, p_ahora);
  end if;
  if v_fecha is null or (p_entrega = 'nacex' and v_jornada is null) then
    return motor.error('SIN_JORNADA', 'No encuentro el próximo día de trabajo del almacén.');
  end if;

  return jsonb_build_object(
    'rol', v_rol, 'fecha', v_fecha, 'jornada_id', v_jornada,
    -- Recoger en tienda con el reparto de hoy ya guardado: entra en él al momento.
    'reparto_id', v_reparto,
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas')),
    'comprometido', motor.comprometido_en(coalesce(v_jornada, v_jornada_hoy), p_ahora));
end;
$$;

-- Lo que una tienda no ve: la configuración general (cuentas, correos) y los pedidos de cliente.
drop policy lectura on public.configuracion;
create policy lectura on public.configuracion for select to authenticated
  using ((centro_id is null and not (select motor.es_tienda()))
         or centro_id = (select motor.mi_centro()) or (select motor.es_admin()));
drop policy lectura on public.pedidos_cliente;
create policy lectura on public.pedidos_cliente for select to authenticated
  using ((select motor.es_admin())
         or exists (select 1 from public.personas p where p.id = (select auth.uid()) and p.activo and p.rol <> 'tienda'));

-- Los cierres de turno (con su correo) siguen siendo solo del almacén.
create or replace function motor.generar_cierres_programados(p_ahora timestamptz)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select j.id, h.turno
      from public.jornadas j
      join public.personas p on p.id = j.persona_id and p.activo and p.rol <> 'tienda'
      join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
     where j.fecha = motor.fecha_local(p_ahora)
       and motor.en_local(j.fecha, h.hora_fin) <= p_ahora
       and not exists (select 1 from public.cierres c where c.jornada_id = j.id and c.turno = h.turno)
     order by h.hora_inicio
  loop
    perform motor.generar_cierre(r.id, r.turno, p_ahora);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Horario de cada tienda (configuración por centro) y alta de su cuenta
-- ---------------------------------------------------------------------------
insert into public.configuracion (clave, centro_id, valor)
select 'horario_tienda', c.id, case
    when c.codigo = 'BILBAO' then '[{"dias": [1, 2, 3, 4, 5, 6], "turno": "manana", "inicio": "11:00", "fin": "13:30"},
                                   {"dias": [1, 2, 3, 4, 5, 6], "turno": "tarde", "inicio": "16:30", "fin": "20:30"}]'
    when c.codigo in ('DONOSTI', 'RENTERIA') then '[{"dias": [1, 2, 3, 4, 5, 6], "turno": "manana", "inicio": "11:00", "fin": "13:30"},
                                   {"dias": [1, 2, 3, 4, 5], "turno": "tarde", "inicio": "17:00", "fin": "20:30"}]'
    else '[{"dias": [1, 2, 3, 4, 5, 6], "turno": "manana", "inicio": "11:00", "fin": "13:30"},
           {"dias": [1, 2, 3, 4, 5], "turno": "tarde", "inicio": "17:00", "fin": "20:30"},
           {"dias": [6], "turno": "tarde", "inicio": "17:00", "fin": "19:30"}]' end::jsonb
  from public.centros_trabajo c where c.tipo = 'tienda';
insert into public.configuracion (clave, centro_id, valor)
select 'alternar_semanales', c.id, 'true' from public.centros_trabajo c where c.codigo = 'BILBAO';

-- Copia el horario de su tienda a la ficha de la cuenta de tienda (al darse de alta, o si cambia).
create or replace function motor.aplicar_horario_tienda(p_persona uuid)
returns integer language plpgsql set search_path = '' as $$
declare
  v_centro uuid := (select centro_id from public.personas where id = p_persona and rol = 'tienda');
  h jsonb;
  d integer;
  n integer := 0;
begin
  if v_centro is null then
    return 0;
  end if;
  delete from public.horarios where persona_id = p_persona;
  for h in select * from jsonb_array_elements(coalesce((select valor from public.configuracion
                                                         where clave = 'horario_tienda' and centro_id = v_centro), '[]')) loop
    for d in select (jsonb_array_elements_text(h -> 'dias'))::int loop
      insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
      values (p_persona, d, h ->> 'turno', (h ->> 'inicio')::time, (h ->> 'fin')::time);
      n := n + 1;
    end loop;
  end loop;
  return n;
end;
$$;

create or replace function motor.alta_cuenta_autorizada(p_usuario uuid, p_correo text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  e jsonb := motor.cuenta_autorizada(p_correo);
  v_centro uuid;
  h jsonb;
  d integer;
begin
  if e is null or exists (select 1 from public.personas where id = p_usuario) then
    return null;
  end if;
  select id into v_centro from public.centros_trabajo where codigo = coalesce(e ->> 'centro', 'ALMACEN');
  insert into public.personas (id, nombre, rol, centro_id, telefono)
  values (p_usuario, coalesce(nullif(btrim(e ->> 'nombre'), ''), 'Sin nombre'), e ->> 'rol',
          case when e ->> 'rol' in ('operario', 'tienda') then v_centro end, nullif(btrim(e ->> 'telefono'), ''));
  -- Tienda (Tarea 27): el horario de su tienda, de la configuración.
  if e ->> 'rol' = 'tienda' and e -> 'horario' is null then
    perform motor.aplicar_horario_tienda(p_usuario);
  end if;
  for h in select * from jsonb_array_elements(coalesce(e -> 'horario', '[]'::jsonb)) loop
    for d in select (jsonb_array_elements_text(h -> 'dias'))::int loop
      insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
      values (p_usuario, d, h ->> 'turno', (h ->> 'inicio')::time, (h ->> 'fin')::time)
      on conflict (persona_id, dia_semana, turno) do nothing;
    end loop;
  end loop;
  if e ->> 'rol' = 'operario' and coalesce((e ->> 'por_defecto')::boolean, false) then
    insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, to_jsonb(p_usuario::text))
    on conflict (clave, centro_id) do update set valor = excluded.valor;
  end if;
  perform motor.registrar('persona_dada_de_alta', null, null, null,
                          jsonb_build_object('persona', p_usuario, 'rol', e ->> 'rol'));
  return p_usuario;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Personas de cada tienda y quién está en cada turno
-- ---------------------------------------------------------------------------
create table public.personas_tienda (
  id          uuid primary key default gen_random_uuid(),
  centro_id   uuid not null references public.centros_trabajo (id),
  nombre      text not null check (btrim(nombre) <> ''),
  cuando      text not null default 'siempre' check (cuando in ('siempre', 'entre_semana', 'sabados')),
  turno       text check (turno in ('manana', 'tarde')),
  activo      boolean not null default true,
  creada_en   timestamptz not null default now(),
  actualizada_por uuid references public.personas (id)
);
comment on table public.personas_tienda is 'Quién trabaja en cada tienda (nombre y cuándo). Datos personales: nunca en el repositorio.';
create index personas_tienda_centro_id_idx on public.personas_tienda (centro_id);
create index personas_tienda_actualizada_por_idx on public.personas_tienda (actualizada_por);

create table public.turnos_tienda (
  id                uuid primary key default gen_random_uuid(),
  jornada_id        uuid not null references public.jornadas (id),
  turno             text check (turno in ('manana', 'tarde')),
  persona_tienda_id uuid not null references public.personas_tienda (id),
  nombre            text not null,
  empezado_en       timestamptz not null default now()
);
comment on table public.turnos_tienda is 'Quién está en la tienda: la persona que eligen al empezar el turno (es el «hecha por»).';
create index turnos_tienda_jornada_id_idx on public.turnos_tienda (jornada_id);
create index turnos_tienda_persona_tienda_id_idx on public.turnos_tienda (persona_tienda_id);

-- ---------------------------------------------------------------------------
-- 4. Días cerrados (festivos): una tienda o todas
-- ---------------------------------------------------------------------------
create table public.dias_cerrados (
  id         uuid primary key default gen_random_uuid(),
  fecha      date not null,
  centro_id  uuid references public.centros_trabajo (id),   -- null: todas las tiendas
  motivo     text,
  creado_por uuid references public.personas (id),
  creado_en  timestamptz not null default now(),
  unique nulls not distinct (fecha, centro_id)
);
comment on table public.dias_cerrados is 'Días en que una tienda (o todas, centro_id null) está cerrada: no hay jornada ni tareas. No afecta al almacén.';
create index dias_cerrados_centro_id_idx on public.dias_cerrados (centro_id);
create index dias_cerrados_creado_por_idx on public.dias_cerrados (creado_por);

create or replace function motor.dia_cerrado(p_centro uuid, p_fecha date)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.centros_trabajo c
                  where c.id = p_centro and c.tipo = 'tienda')
     and exists (select 1 from public.dias_cerrados d
                  where d.fecha = p_fecha and (d.centro_id is null or d.centro_id = p_centro));
$$;

-- ---------------------------------------------------------------------------
-- 5. Vídeo de la semana
-- ---------------------------------------------------------------------------
create table public.videos_tienda (
  id                uuid primary key default gen_random_uuid(),
  tarea_id          uuid not null unique references public.tareas (id),
  centro_id         uuid not null references public.centros_trabajo (id),
  persona_tienda_id uuid references public.personas_tienda (id),
  nombre            text,
  fecha             date not null,
  semana            date not null,             -- lunes de la semana
  enlace            text check (enlace is null or enlace ~* '^https?://'),
  aprendido         text,
  no_pudo           boolean not null default false,
  creado_en         timestamptz not null default now(),
  check (no_pudo or (enlace is not null and aprendido is not null))
);
comment on table public.videos_tienda is 'Vídeo de la semana de cada tienda: enlace de YouTube y lo aprendido, o «Hoy no he podido».';
create index videos_tienda_centro_id_idx on public.videos_tienda (centro_id);
create index videos_tienda_persona_tienda_id_idx on public.videos_tienda (persona_tienda_id);

-- Permisos de las tablas nuevas: solo lectura con sesión, y cada tienda lo suyo.
revoke all on public.personas_tienda, public.turnos_tienda, public.dias_cerrados, public.videos_tienda from anon, authenticated;
grant select on public.personas_tienda, public.turnos_tienda, public.dias_cerrados, public.videos_tienda to authenticated;
alter table public.personas_tienda enable row level security;
alter table public.turnos_tienda enable row level security;
alter table public.dias_cerrados enable row level security;
alter table public.videos_tienda enable row level security;
create policy lectura on public.personas_tienda for select to authenticated
  using ((select motor.es_admin()) or (centro_id = (select motor.mi_centro()) and (select motor.es_tienda())));
create policy lectura on public.turnos_tienda for select to authenticated
  using ((select motor.es_admin())
         or jornada_id in (select j.id from public.jornadas j where j.persona_id = (select auth.uid())));
create policy lectura on public.dias_cerrados for select to authenticated
  using ((select motor.es_admin()) or ((select motor.es_tienda()) and (centro_id is null or centro_id = (select motor.mi_centro()))));
create policy lectura on public.videos_tienda for select to authenticated
  using ((select motor.es_admin()) or (select motor.es_tienda()));

create or replace function motor.generar_jornada(p_persona uuid, p_fecha date)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_centro uuid;
  v_envio_ayer boolean;
  v_arrastre_hecho boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('jornada:' || p_persona || ':' || p_fecha, 0));

  select envio_dia_siguiente into v_envio_ayer
    from public.jornadas where persona_id = p_persona and fecha = p_fecha - 1;

  select id, arrastre_hecho into v_id, v_arrastre_hecho
    from public.jornadas where persona_id = p_persona and fecha = p_fecha;
  if v_id is not null then
    if not v_arrastre_hecho then
      update public.jornadas
         set arrastre_hecho = true, hay_envio = hay_envio or coalesce(v_envio_ayer, false)
       where id = v_id;
      perform motor.registrar('jornada_generada', null, v_id, null, '{"preparada_antes": true}');
      perform motor.arrastrar(v_id);
      perform motor.generar_tareas(v_id);
    end if;
    return v_id;
  end if;

  select centro_id into v_centro from public.personas where id = p_persona and activo;
  if v_centro is null
     or not exists (select 1 from public.horarios
                    where persona_id = p_persona and dia_semana = extract(isodow from p_fecha))
     or motor.dia_cerrado(v_centro, p_fecha) then  -- tienda cerrada ese día (Tarea 27)
    return null;
  end if;

  insert into public.jornadas (persona_id, centro_id, fecha, hay_envio)
  values (p_persona, v_centro, p_fecha,
          extract(isodow from p_fecha) = 1 or coalesce(v_envio_ayer, false))  -- el lunes siempre hay envío
  on conflict (persona_id, fecha) do nothing
  returning id into v_id;

  if v_id is null then
    select id into v_id from public.jornadas where persona_id = p_persona and fecha = p_fecha;
    return v_id;
  end if;

  perform motor.registrar('jornada_generada', null, v_id, null, '{}');
  perform motor.arrastrar(v_id);
  perform motor.generar_tareas(v_id);
  return v_id;
end;
$$;

create or replace function motor.jornada_para(p_persona uuid, p_fecha date, p_ahora timestamptz)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_centro uuid;
begin
  if p_fecha <= motor.fecha_local(p_ahora) then
    return motor.generar_jornada(p_persona, p_fecha);
  end if;
  perform pg_advisory_xact_lock(hashtextextended('jornada:' || p_persona || ':' || p_fecha, 0));
  select id into v_id from public.jornadas where persona_id = p_persona and fecha = p_fecha;
  if v_id is not null then
    return v_id;
  end if;
  select centro_id into v_centro from public.personas where id = p_persona and activo;
  if v_centro is null
     or not exists (select 1 from public.horarios
                    where persona_id = p_persona and dia_semana = extract(isodow from p_fecha))
     or motor.dia_cerrado(v_centro, p_fecha) then  -- tienda cerrada ese día (Tarea 27)
    return null;
  end if;
  insert into public.jornadas (persona_id, centro_id, fecha, hay_envio, arrastre_hecho)
  values (p_persona, v_centro, p_fecha, extract(isodow from p_fecha) = 1, false)
  returning id into v_id;
  perform motor.registrar('jornada_preparada', null, v_id, null, '{}');
  perform motor.generar_tareas(v_id);
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Plantillas de tienda: hora relativa al horario y puntos
-- ---------------------------------------------------------------------------
-- Desde cuándo sale una tarea de plantilla. Sin hora_desde, como siempre (almacén). Con hora_desde
-- (tiendas): inicio o fin de su turno (o del primero / último del día) + minutos_desde; null si ese
-- día no hay ese turno (no se crea).
create or replace function motor.desde_plantilla(p_jornada uuid, p_plantilla uuid)
returns timestamptz language sql stable set search_path = '' as $$
  with j as (select * from public.jornadas where id = p_jornada),
  p as (select * from public.plantillas_tarea where id = p_plantilla),
  t as (select case when p.alterna_turno
                         and coalesce((select (k.valor #>> '{}')::boolean from public.configuracion k
                                        where k.clave = 'alternar_semanales' and k.centro_id = j.centro_id), false)
                    then case when extract(week from j.fecha)::int % 2 = 0 then 'manana' else 'tarde' end
                    else p.turno end as turno
          from j, p)
  select case when p.hora_desde is null then
           coalesce(motor.en_local(j.fecha, p.hora_inicio),
                    motor.inicio_turno(j.persona_id, j.fecha, p.turno),
                    motor.inicio_turno(j.persona_id, j.fecha, null))
         else (select motor.en_local(j.fecha, case when p.hora_desde = 'inicio' then h.hora_inicio else h.hora_fin end)
                      + make_interval(mins => p.minutos_desde)
                 from public.horarios h
                where h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                  and (t.turno is null or h.turno = t.turno)
                order by case when p.hora_desde = 'inicio' then h.hora_inicio end,
                         case when p.hora_desde = 'fin' then h.hora_fin end desc
                limit 1) end
  from j, p, t;
$$;

create or replace function motor.insertar_desde_plantilla(
  p_jornada uuid, p_plantilla uuid, p_clave text, p_origen text)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
  v_desde timestamptz := motor.desde_plantilla(p_jornada, p_plantilla);
begin
  if v_desde is null then
    return null;  -- tienda: ese día no hay ese turno (p. ej. el sábado por la tarde de una franquicia)
  end if;
  insert into public.tareas (
    jornada_id, clave, origen, plantilla_id, titulo, porque, contenido, obligatoria, urgente,
    prioridad_cola, condicion, requiere_clave, disponible_desde, hora_programada,
    hora_limite, duracion_min, no_terminada, orden)
  select
    j.id, p_clave, p_origen, p.id, p.titulo, p.porque, p.contenido, p.obligatoria, p.urgente,
    p.prioridad_cola, array_to_string(array_prepend(p.condicion, p.condiciones_extra), '+'), p.requiere_codigo,
    v_desde,
    motor.en_local(j.fecha, p.hora_inicio),
    motor.en_local(j.fecha, p.hora_limite),
    p.duracion_min, p.no_terminada, p.orden
  from public.jornadas j, public.plantillas_tarea p
  where j.id = p_jornada and p.id = p_plantilla
  on conflict (jornada_id, clave) do nothing
  returning id into v_id;

  if v_id is not null then
    -- Tienda: los puntos de la tarea, para tocarlos uno a uno.
    insert into public.tarea_elementos (tarea_id, tipo, producto, cantidad, orden_sugerido)
    select v_id, 'punto', x.texto, 1, x.n
      from public.plantillas_tarea p, unnest(p.puntos) with ordinality x(texto, n)
     where p.id = p_plantilla;
    perform motor.registrar('tarea_creada', null, p_jornada, v_id,
                            jsonb_build_object('clave', p_clave, 'origen', p_origen));
  end if;
  return v_id;
end;
$$;

-- Las tareas de cada tienda (una plantilla por tienda; se activan por tienda con «activa»).
-- Propias: todo. Franquicias (Donosti, Rentería): solo el vídeo de la semana.
insert into public.plantillas_tarea (centro_id, codigo, titulo, porque, programacion, dias_semana, turno,
                                     hora_desde, minutos_desde, alterna_turno, contenido, puntos, no_terminada, orden, activa)
select c.id, x.codigo, x.titulo, x.porque, 'dia_semana', x.dias, x.turno, x.hora_desde, x.minutos, x.alterna,
       x.contenido, x.puntos, 'nada', x.orden,
       x.codigo = 'video_semana' or c.codigo not in ('DONOSTI', 'RENTERIA')
  from public.centros_trabajo c,
  (values
    ('apertura_manana', 'Apertura de la mañana', 'Para abrir la tienda a su hora y lista.',
     '{1,2,3,4,5,6}'::smallint[], 'manana', 'inicio', -10, false, 'puntos',
     array['Fichar en Woffu', 'Abrir', 'Cartelería', 'Glovo', 'Barrido y puesta a punto'], 10),
    ('cierre_manana', 'Cierre de la mañana', 'Para dejar la mañana cuadrada.',
     '{1,2,3,4,5,6}'::smallint[], 'manana', 'fin', -10, false, 'puntos',
     array['Ventas y stock de la plantilla al día (todo en verde)', 'Incidencias del turno registradas'], 20),
    ('apertura_tarde', 'Apertura de la tarde', 'Para abrir la tienda a su hora.',
     '{1,2,3,4,5,6}'::smallint[], 'tarde', 'inicio', -10, false, 'puntos',
     array['Fichar', 'Abrir', 'Cartelería', 'Glovo'], 30),
    ('cierre_dia', 'Cierre del día', 'Para cerrar con todo cuadrado y listo para mañana.',
     '{1,2,3,4,5,6}'::smallint[], null, 'fin', -10, false, 'puntos',
     array['Ventas del día en la plantilla (todo en verde)', 'Suelo fregado', 'Efectivo contado y en la bolsa para mañana',
           'Incidencias de la tarde registradas'], 90),
    ('limpieza_cristales', 'Limpieza de cristales', 'Para que la tienda se vea bien desde fuera.',
     '{4}'::smallint[], 'tarde', 'inicio', 0, true, 'simple', '{}'::text[], 50),
    ('video_semana', 'Vídeo de la semana',
     'Busca y mira un vídeo sobre nuestro sector: cannabis y CBD, cultivos y variedades, extracciones o la cultura cannábica. También sobre los ingredientes de nuestra crema, lo que se te ocurra pero tiene que estar relacionado con lo que vendemos. Pega el enlace de YouTube y escribe en una línea qué has aprendido. Quedará en la lista de vídeos que ven todas las tiendas, para recomendarlo a compañeros y clientes.',
     '{5}'::smallint[], 'manana', 'inicio', 0, true, 'video', '{}'::text[], 60)
  ) x(codigo, titulo, porque, dias, turno, hora_desde, minutos, alterna, contenido, puntos, orden)
 where c.tipo = 'tienda';

-- La huella: las filas de configuración y de plantillas, por centro (ahora hay de cada tienda).
create or replace function motor.huella_estructura()
returns table (apartado text, huella text)
language sql stable
security definer
-- `public` en la ruta: los nombres de las tablas de public salen sin esquema, como en la prueba 00 de siempre.
set search_path = public
as $$
with
esquemas as (select unnest(array['public', 'motor', 'prueba']) as nspname),
columnas as (
  select string_agg(format('%s.%s.%s %s %s %s', c.table_schema, c.table_name, c.column_name, c.data_type,
                           c.is_nullable, coalesce(c.column_default, '')), E'\n'
                    order by c.table_schema, c.table_name, c.ordinal_position) as t
  from information_schema.columns c where c.table_schema in (select nspname from esquemas)),
restricciones as (
  select string_agg(format('%s %s %s', r.conrelid::regclass, r.conname, pg_get_constraintdef(r.oid)), E'\n'
                    order by r.conrelid::regclass::text, r.conname) as t
  from pg_constraint r join pg_namespace n on n.oid = r.connamespace
  where n.nspname in (select nspname from esquemas)),
indices as (
  select string_agg(indexdef, E'\n' order by schemaname, tablename, indexname) as t
  from pg_indexes where schemaname in (select nspname from esquemas)),
politicas as (
  select string_agg(format('%s.%s %s %s %s %s', schemaname, tablename, policyname, cmd, roles::text, qual), E'\n'
                    order by schemaname, tablename, policyname) as t
  from pg_policies where schemaname in (select nspname from esquemas)),
rls as (
  select string_agg(format('%s %s', c.oid::regclass, c.relrowsecurity), E'\n' order by c.oid::regclass::text) as t
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in (select nspname from esquemas) and c.relkind = 'r'),
permisos_tablas as (
  select string_agg(format('%s.%s %s %s', table_schema, table_name, grantee, privilege_type), E'\n'
                    order by table_schema, table_name, grantee, privilege_type) as t
  from information_schema.role_table_grants
  where table_schema in (select nspname from esquemas) and grantee in ('anon', 'authenticated')),
funciones as (
  select string_agg(format('%s.%s(%s) definer=%s config=%s src=%s', n.nspname, p.proname,
                           pg_get_function_identity_arguments(p.oid), p.prosecdef, p.proconfig::text, md5(p.prosrc)), E'\n'
                    order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) as t
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in (select nspname from esquemas)),
permisos_funciones as (
  select string_agg(format('%s.%s(%s) %s %s', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
                           r.rolname, has_function_privilege(r.oid, p.oid, 'EXECUTE')), E'\n'
                    order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid), r.rolname) as t
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join pg_roles r
  where n.nspname in (select nspname from esquemas) and r.rolname in ('anon', 'authenticated')),
permisos_esquemas as (
  select string_agg(format('%s %s %s', e.nspname, r.rolname, has_schema_privilege(r.oid, e.nspname, 'USAGE')), E'\n'
                    order by e.nspname, r.rolname) as t
  from esquemas e cross join pg_roles r where r.rolname in ('anon', 'authenticated')),
carga as (
  select md5(
    (select string_agg(format('%s %s %s %s %s %s', codigo, nombre, tipo, nombre_en_sheets, alias::text, activo), E'\n' order by codigo) from public.centros_trabajo)
    || (select string_agg(format('%s %s %s', k.clave, coalesce(c.codigo, ''), k.valor::text), E'\n' order by k.clave, c.codigo nulls first)
          from public.configuracion k left join public.centros_trabajo c on c.id = k.centro_id  -- por centro (Tarea 27)
        where clave not in ('entorno', 'correo_administracion', 'cuentas_autorizadas',
                            'operario_por_defecto', 'administracion_por_defecto', 'telefono_administracion',
                            'url_proyecto', 'cierres_sin_correo'))  -- propias de cada entorno (AUDITORIA.md §0)
    || (select string_agg(row(c.codigo, p.codigo, p.titulo, p.programacion, p.dias_semana, p.turno, p.hora_inicio, p.hora_limite,
                              p.duracion_min, p.condicion, p.requiere_codigo, p.contenido, p.obligatoria, p.prioridad_cola,
                              p.no_terminada, p.modo, p.orden, p.activa, p.puntos, p.hora_desde, p.minutos_desde,
                              p.alterna_turno)::text, E'\n' order by p.codigo, c.codigo)
        from public.plantillas_tarea p join public.centros_trabajo c on c.id = p.centro_id)) as h)
select 'tablas y columnas', md5(t) from columnas
union all select 'restricciones', md5(t) from restricciones
union all select 'índices', md5(t) from indices
union all select 'políticas RLS', md5(t) from politicas
union all select 'RLS activado', md5(t) from rls
union all select 'permisos sobre tablas', md5(coalesce(t, '')) from permisos_tablas
union all select 'funciones', md5(t) from funciones
union all select 'permisos sobre funciones', md5(t) from permisos_funciones
union all select 'permisos sobre esquemas', md5(t) from permisos_esquemas
union all select 'carga inicial', h from carga
union all select 'generación programada', md5(coalesce((select string_agg(jobname || ' ' || schedule || ' ' || command, E'\n' order by jobname)
                                                       from cron.job), ''))
$$;

-- ---------------------------------------------------------------------------
-- 7. El día de la tienda (tablet)
-- ---------------------------------------------------------------------------
-- Turno de la tienda a esa hora: el que está en curso (desde una hora antes de abrir hasta media
-- hora después de cerrar); null si no hay ninguno.
create or replace function motor.turno_tienda_ahora(p_persona uuid, p_ahora timestamptz)
returns text language sql stable set search_path = '' as $$
  select h.turno from public.horarios h
   where h.persona_id = p_persona and h.dia_semana = extract(isodow from motor.fecha_local(p_ahora))
     and p_ahora >= motor.en_local(motor.fecha_local(p_ahora), h.hora_inicio) - interval '60 minutes'
     and p_ahora < motor.en_local(motor.fecha_local(p_ahora), h.hora_fin) + interval '30 minutes'
   order by h.hora_inicio desc limit 1;
$$;

-- Quién está ahora en la tienda (el último que eligió su nombre en esa jornada).
create or replace function motor.en_turno_tienda(p_jornada uuid)
returns public.turnos_tienda language sql stable set search_path = '' as $$
  select * from public.turnos_tienda where jornada_id = p_jornada order by empezado_en desc, id desc limit 1;
$$;

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
                                          'hecho_por', e.calculo ->> 'hecho_por', 'a_las', motor.hora_texto(e.terminado_en))
                       order by e.orden_sugerido, e.producto)
        from public.tarea_elementos e where e.tarea_id = t.id and e.tipo = 'punto'), '[]'::jsonb),
    'video', (select jsonb_build_object('enlace', v.enlace, 'aprendido', v.aprendido, 'no_pudo', v.no_pudo)
                from public.videos_tienda v where v.tarea_id = t.id))
  from public.tareas t join public.jornadas j on j.id = t.jornada_id
  where t.id = p_tarea;
$$;

create or replace function motor.aviso_tienda_json(p_incidencia uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', i.id, 'fecha', motor.fecha_local(i.iniciada_en), 'texto', i.descripcion,
                            'tienda_id', c.id, 'tienda', c.nombre, 'estado', i.estado,
                            'leido', i.estado = 'cerrada' and i.nota_cierre like 'Leído%', 'cerrado_en', i.terminada_en,
                            'nota', i.nota_cierre, 'creado_por', a.nombre)
  from public.incidencias i
  join public.personas p on p.id = i.persona_id
  join public.centros_trabajo c on c.id = p.centro_id
  left join public.personas a on a.id = i.creada_por
  where i.id = p_incidencia and i.opcion = 'aviso';
$$;

-- tienda_hoy(): todo lo de la tienda para hoy, de una vez.
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
        from public.tareas t where t.jornada_id = v_jornada and not t.retirada_por_condicion), '[]'::jsonb));
end;
$$;

-- Sábado: el vídeo de la semana sale a quien trabaje si esa persona no ha compartido (ni ha dicho
-- «Hoy no he podido») esa semana. Uno por persona.
create or replace function motor.video_sabado(p_jornada uuid, p_persona_tienda uuid, p_ahora timestamptz)
returns uuid language plpgsql set search_path = '' as $$
declare
  j public.jornadas;
  v_plantilla uuid;
  v_id uuid;
begin
  select * into j from public.jornadas where id = p_jornada;
  select id into v_plantilla from public.plantillas_tarea
   where centro_id = j.centro_id and codigo = 'video_semana' and activa;
  if v_plantilla is null or extract(isodow from j.fecha) <> 6
     or exists (select 1 from public.videos_tienda v
                 where v.persona_tienda_id = p_persona_tienda and v.semana = date_trunc('week', j.fecha)::date) then
    return null;
  end if;
  v_id := motor.insertar_desde_plantilla(j.id, v_plantilla, 'video_semana:' || p_persona_tienda, 'plantilla');
  -- Sale ya, a quien acaba de empezar.
  update public.tareas set disponible_desde = least(disponible_desde, p_ahora) where id = v_id;
  return v_id;
end;
$$;

create or replace function motor.empezar_turno_tienda_de(p_persona uuid, p_persona_tienda uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_jornada uuid := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  pt public.personas_tienda;
  tt public.turnos_tienda;
  v_turno text := motor.turno_tienda_ahora(p_persona, p_ahora);
begin
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  select * into pt from public.personas_tienda
   where id = p_persona_tienda and activo and centro_id = (select centro_id from public.personas where id = p_persona);
  if pt.id is null then
    return motor.error('NO_ENCONTRADO', 'Esa persona no está en la lista de la tienda.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null or tt.persona_tienda_id <> pt.id or tt.turno is distinct from v_turno then
    insert into public.turnos_tienda (jornada_id, turno, persona_tienda_id, nombre, empezado_en)
    values (v_jornada, v_turno, pt.id, pt.nombre, p_ahora);
    perform motor.registrar('turno_tienda_empezado', p_persona, v_jornada, null,
                            jsonb_build_object('persona_tienda', pt.id, 'nombre', pt.nombre, 'turno', v_turno, 'a_las', p_ahora));
  end if;
  perform motor.video_sabado(v_jornada, pt.id, p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- Comprobaciones comunes antes de marcar algo de una tarea de la tienda.
create or replace function motor.tarea_tienda_marcable(p_persona uuid, p_tarea uuid, p_contenido text, p_ahora timestamptz)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  t public.tareas;
  v_ok boolean;
begin
  select tr.* into t from public.tareas tr join public.jornadas j on j.id = tr.jornada_id
   where tr.id = p_tarea and j.persona_id = p_persona;
  if t.id is null or (p_contenido is not null and t.contenido <> p_contenido) then
    return motor.error('NO_ENCONTRADO', 'Esa tarea no existe.');
  end if;
  if t.estado not in ('pendiente', 'en_curso') then
    return motor.error('ESTADO_NO_VALIDO', 'Esta tarea ya está cerrada.', jsonb_build_object('estado', t.estado));
  end if;
  if t.disponible_desde > p_ahora then
    return motor.error('TODAVIA_NO', 'Esta tarea es desde las ' || motor.hora_texto(t.disponible_desde) || '.');
  end if;
  v_ok := (motor.en_turno_tienda(t.jornada_id)).id is not null;
  if not v_ok then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  return null;
end;
$$;

create or replace function motor.cerrar_tarea_tienda(p_persona uuid, p_tarea uuid, p_estado text, p_resultado text,
                                                     p_motivo text, p_evento text, p_ahora timestamptz)
returns void language plpgsql set search_path = '' as $$
declare
  t public.tareas;
  tt public.turnos_tienda;
begin
  select * into t from public.tareas where id = p_tarea;
  tt := motor.en_turno_tienda(t.jornada_id);
  update public.tareas
     set estado = p_estado, iniciada_en = coalesce(iniciada_en, p_ahora), terminada_en = p_ahora,
         resultado = p_resultado, motivo_no_hecha = p_motivo
   where id = p_tarea;
  perform motor.registrar(p_evento, p_persona, t.jornada_id, p_tarea,
                          jsonb_build_object('a_las', p_ahora, 'hecha_por', tt.nombre, 'persona_tienda', tt.persona_tienda_id));
end;
$$;

-- Tocar un punto de una tarea; con el último, la tarea queda hecha.
create or replace function motor.marcar_punto_de(p_persona uuid, p_elemento uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  tt public.turnos_tienda;
  t public.tareas;
begin
  select el.* into e from public.tarea_elementos el
    join public.tareas tr on tr.id = el.tarea_id join public.jornadas j on j.id = tr.jornada_id
   where el.id = p_elemento and el.tipo = 'punto' and j.persona_id = p_persona;
  if e.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese punto no existe.');
  end if;
  select * into t from public.tareas where id = e.tarea_id;
  if e.estado = 'hecho' then
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  v_error := motor.tarea_tienda_marcable(p_persona, e.tarea_id, 'puntos', p_ahora);
  if v_error is not null then
    return v_error;
  end if;
  tt := motor.en_turno_tienda(t.jornada_id);
  update public.tarea_elementos
     set estado = 'hecho', cantidad_hecha = cantidad, iniciado_en = coalesce(iniciado_en, p_ahora), terminado_en = p_ahora,
         calculo = calculo || jsonb_build_object('hecho_por', tt.nombre, 'persona_tienda', tt.persona_tienda_id)
   where id = e.id;
  update public.tareas set iniciada_en = coalesce(iniciada_en, p_ahora) where id = t.id;
  if not exists (select 1 from public.tarea_elementos where tarea_id = t.id and tipo = 'punto' and estado <> 'hecho') then
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', null, null, 'tarea_terminada', p_ahora);
  end if;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- Una tarea sin puntos (la limpieza de cristales): «Hecho».
create or replace function motor.terminar_tarea_tienda_de(p_persona uuid, p_tarea uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'simple', p_ahora);
begin
  if v_error is not null then
    return v_error;
  end if;
  perform motor.cerrar_tarea_tienda(p_persona, p_tarea, 'hecha', null, null, 'tarea_terminada', p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- Vídeo de la semana: enlace de YouTube y una línea de lo aprendido, o «Hoy no he podido».
create or replace function motor.compartir_video_de(p_persona uuid, p_tarea uuid, p_enlace text, p_aprendido text,
                                                    p_no_pude boolean, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'video', p_ahora);
  t public.tareas;
  j public.jornadas;
  tt public.turnos_tienda;
  v_enlace text := nullif(btrim(p_enlace), '');
  v_aprendido text := nullif(btrim(regexp_replace(coalesce(p_aprendido, ''), '\s+', ' ', 'g')), '');
  v_semana date;
begin
  if v_error is not null then
    return v_error;
  end if;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  tt := motor.en_turno_tienda(j.id);
  v_semana := date_trunc('week', j.fecha)::date;
  if coalesce(p_no_pude, false) then
    insert into public.videos_tienda (tarea_id, centro_id, persona_tienda_id, nombre, fecha, semana, no_pudo)
    values (t.id, j.centro_id, tt.persona_tienda_id, tt.nombre, j.fecha, v_semana, true);
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'cancelada', null, 'Hoy no he podido', 'video_no_pudo', p_ahora);
    return motor.tienda_hoy_de(p_persona, p_ahora);
  end if;
  if v_enlace is null
     or v_enlace !~* '^https?://(www\.|m\.|music\.)?(youtube\.com/(watch\?([^#]*&)?v=|shorts/|live/|embed/)|youtu\.be/)[A-Za-z0-9_-]{6,}' then
    return motor.error('DATOS_NO_VALIDOS', 'Pega el enlace del vídeo de YouTube.');
  end if;
  if v_aprendido is null or length(v_aprendido) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe en una línea (200 letras como máximo) qué has aprendido.');
  end if;
  if exists (select 1 from public.videos_tienda v
              where v.persona_tienda_id = tt.persona_tienda_id and v.semana = v_semana and not v.no_pudo) then
    return motor.error('YA_COMPARTIDO', tt.nombre || ' ya ha compartido un vídeo esta semana.');
  end if;
  insert into public.videos_tienda (tarea_id, centro_id, persona_tienda_id, nombre, fecha, semana, enlace, aprendido)
  values (t.id, j.centro_id, tt.persona_tienda_id, tt.nombre, j.fecha, v_semana, v_enlace, v_aprendido);
  perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Vídeo compartido', null, 'tarea_terminada', p_ahora);
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- La lista de vídeos que ven todas las tiendas (y Administración), los más nuevos primero.
create or replace function motor.videos_semana_de(p_limite integer)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('videos', coalesce(jsonb_agg(x.o order by x.fecha desc, x.creado_en desc), '[]'::jsonb))
  from (select v.fecha, v.creado_en,
               jsonb_build_object('id', v.id, 'enlace', v.enlace, 'aprendido', v.aprendido, 'tienda', c.nombre,
                                  'persona', v.nombre, 'fecha', v.fecha) as o
          from public.videos_tienda v join public.centros_trabajo c on c.id = v.centro_id
         where not v.no_pudo
         order by v.fecha desc, v.creado_en desc
         limit least(greatest(coalesce(p_limite, 50), 1), 200)) x;
$$;

-- El aviso, leído: se cierra (queda quién lo leyó).
create or replace function motor.marcar_aviso_leido_de(p_persona uuid, p_aviso uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
  tt public.turnos_tienda;
begin
  select * into i from public.incidencias where id = p_aviso and opcion = 'aviso' and persona_id = p_persona for update;
  if i.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese aviso no existe.');
  end if;
  if i.estado <> 'cerrada' then
    tt := motor.en_turno_tienda((select id from public.jornadas where persona_id = p_persona
                                  and fecha = motor.fecha_local(p_ahora)));
    update public.incidencias
       set estado = 'cerrada', terminada_en = p_ahora, cerrada_por = p_persona,
           nota_cierre = 'Leído' || coalesce(' por ' || tt.nombre, '')
     where id = i.id;
    perform motor.registrar('aviso_leido', p_persona, i.jornada_id, null,
                            jsonb_build_object('incidencia', i.id, 'a_las', p_ahora, 'leido_por', tt.nombre));
  end if;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Administración: personas de las tiendas, días cerrados y avisos a las tiendas
-- ---------------------------------------------------------------------------
create or replace function motor.persona_tienda_json(pt public.personas_tienda)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', pt.id, 'tienda_id', pt.centro_id,
                            'tienda', (select nombre from public.centros_trabajo where id = pt.centro_id),
                            'nombre', pt.nombre, 'cuando', pt.cuando, 'turno', pt.turno, 'activo', pt.activo)
$$;

create or replace function motor.personas_tienda_de(p_centro uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('personas', coalesce(jsonb_agg(motor.persona_tienda_json(pt) order by c.nombre, pt.nombre), '[]'::jsonb))
  from public.personas_tienda pt join public.centros_trabajo c on c.id = pt.centro_id
  where (p_centro is null or pt.centro_id = p_centro) and pt.activo;
$$;

-- Añadir (sin id), cambiar (con id) o quitar (activo = false) un nombre de una tienda.
create or replace function motor.guardar_persona_tienda_de(p_admin uuid, p_id uuid, p_centro uuid, p_nombre text,
                                                           p_cuando text, p_turno text, p_activo boolean)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pt public.personas_tienda;
  v_nombre text := nullif(btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g')), '');
begin
  if p_id is not null then
    select * into pt from public.personas_tienda where id = p_id;
    if pt.id is null then
      return motor.error('NO_ENCONTRADO', 'Esa persona no está en ninguna tienda.');
    end if;
  end if;
  if not exists (select 1 from public.centros_trabajo where id = coalesce(p_centro, pt.centro_id) and tipo = 'tienda') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige la tienda.');
  end if;
  if v_nombre is null or length(v_nombre) > 40 then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el nombre (40 letras como máximo).');
  end if;
  if coalesce(p_cuando, 'siempre') not in ('siempre', 'entre_semana', 'sabados') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige cuándo trabaja: siempre, entre semana o los sábados.');
  end if;
  if p_turno is not null and p_turno not in ('manana', 'tarde') then
    return motor.error('DATOS_NO_VALIDOS', 'El turno es «manana» o «tarde».');
  end if;
  if p_id is null then
    insert into public.personas_tienda (centro_id, nombre, cuando, turno, activo, actualizada_por)
    values (p_centro, v_nombre, coalesce(p_cuando, 'siempre'), p_turno, coalesce(p_activo, true), p_admin)
    returning * into pt;
  else
    update public.personas_tienda
       set centro_id = coalesce(p_centro, centro_id), nombre = v_nombre, cuando = coalesce(p_cuando, cuando),
           turno = p_turno, activo = coalesce(p_activo, activo), actualizada_por = p_admin
     where id = p_id
    returning * into pt;
  end if;
  perform motor.registrar('persona_tienda_guardada', p_admin, null, null,
                          jsonb_build_object('persona_tienda', pt.id, 'tienda', pt.centro_id, 'activo', pt.activo));
  return jsonb_build_object('persona', motor.persona_tienda_json(pt));
end;
$$;

create or replace function motor.dias_cerrados_de(p_desde date, p_hasta date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('dias', coalesce(jsonb_agg(jsonb_build_object(
           'fecha', d.fecha, 'tienda_id', d.centro_id, 'tienda', coalesce(c.nombre, 'Todas las tiendas'), 'motivo', d.motivo)
           order by d.fecha, c.nombre nulls first), '[]'::jsonb))
  from public.dias_cerrados d left join public.centros_trabajo c on c.id = d.centro_id
  where d.fecha between p_desde and p_hasta;
$$;

-- Marcar (o quitar) un día cerrado para una tienda o para todas (centro null). Si la jornada de ese
-- día ya estaba hecha, sus tareas pendientes se cancelan (y vuelven si se quita).
create or replace function motor.marcar_dia_cerrado_de(p_admin uuid, p_fecha date, p_centro uuid, p_cerrado boolean,
                                                       p_motivo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_id uuid;
begin
  if p_fecha is null or p_fecha < motor.fecha_local(p_ahora) then
    return motor.error('FECHA_PASADA', 'Elige hoy o un día que viene.');
  end if;
  if p_centro is not null and not exists (select 1 from public.centros_trabajo where id = p_centro and tipo = 'tienda') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige una tienda (o ninguna, para todas).');
  end if;
  if coalesce(p_cerrado, true) then
    insert into public.dias_cerrados (fecha, centro_id, motivo, creado_por)
    values (p_fecha, p_centro, nullif(btrim(p_motivo), ''), p_admin)
    on conflict (fecha, centro_id) do update set motivo = excluded.motivo;
    update public.tareas t set estado = 'cancelada', motivo_no_hecha = 'Tienda cerrada ese día'
      from public.jornadas j join public.personas p on p.id = j.persona_id and p.rol = 'tienda'
     where t.jornada_id = j.id and j.fecha = p_fecha and (p_centro is null or j.centro_id = p_centro)
       and t.estado = 'pendiente';
    perform motor.registrar('dia_cerrado', p_admin, null, null, jsonb_build_object('fecha', p_fecha, 'tienda', p_centro));
  else
    delete from public.dias_cerrados where fecha = p_fecha and centro_id is not distinct from p_centro;
    update public.tareas t set estado = 'pendiente', motivo_no_hecha = null
      from public.jornadas j join public.personas p on p.id = j.persona_id and p.rol = 'tienda'
     where t.jornada_id = j.id and j.fecha = p_fecha and (p_centro is null or j.centro_id = p_centro)
       and t.estado = 'cancelada' and t.motivo_no_hecha = 'Tienda cerrada ese día'
       and not motor.dia_cerrado(j.centro_id, p_fecha);
    perform motor.registrar('dia_abierto', p_admin, null, null, jsonb_build_object('fecha', p_fecha, 'tienda', p_centro));
  end if;
  return motor.dias_cerrados_de(motor.fecha_local(p_ahora), motor.fecha_local(p_ahora) + 366);
end;
$$;

-- Aviso de Administración para una tienda o para todas (centro null): una incidencia «aviso» de
-- la cuenta de cada tienda, para ese día (Tarea 22). Las tiendas cerradas ese día no lo reciben.
create or replace function motor.crear_aviso_tienda_de(p_admin uuid, p_id_cliente uuid, p_fecha date, p_texto text,
                                                       p_centro uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
  v_hoy date := motor.fecha_local(p_ahora);
  r record;
  v_cli uuid;
  v_id uuid;
  v_jornada uuid;
  v_avisos jsonb := '[]';
  v_sin jsonb := '[]';
begin
  if p_id_cliente is null or v_texto is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el aviso.');
  end if;
  if p_fecha is null or p_fecha < v_hoy then
    return motor.error('DATOS_NO_VALIDOS', 'El aviso tiene que ser para hoy o para un día que viene.');
  end if;
  if p_centro is not null and not exists (select 1 from public.centros_trabajo where id = p_centro and tipo = 'tienda') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige una tienda (o ninguna, para todas).');
  end if;
  for r in
    select c.id as centro, c.nombre, p.id as persona
      from public.centros_trabajo c
      left join public.personas p on p.centro_id = c.id and p.rol = 'tienda' and p.activo
     where c.tipo = 'tienda' and c.activo and (p_centro is null or c.id = p_centro)
     order by c.nombre
  loop
    if r.persona is null then
      v_sin := v_sin || jsonb_build_object('tienda', r.nombre, 'motivo', 'Todavía no ha entrado con su cuenta');
      continue;
    end if;
    v_cli := md5(p_id_cliente::text || ':' || r.persona)::uuid;
    select id into v_id from public.incidencias where id_cliente = v_cli;
    if v_id is null then
      v_jornada := motor.jornada_para(r.persona, p_fecha, p_ahora);
      if v_jornada is null then
        v_sin := v_sin || jsonb_build_object('tienda', r.nombre, 'motivo', 'Ese día no abre');
        continue;
      end if;
      insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, estado, creada_por)
      values (v_jornada, r.persona, v_texto,
              case when p_fecha = v_hoy then p_ahora
                   else coalesce(motor.inicio_turno(r.persona, p_fecha, null), motor.en_local(p_fecha, '00:00')) end,
              v_cli, 'aviso', 'abierta', p_admin)
      returning id into v_id;
      perform motor.registrar('aviso_creado', p_admin, v_jornada, null,
                              jsonb_build_object('incidencia', v_id, 'fecha', p_fecha, 'a_las', p_ahora, 'tienda', r.centro));
    end if;
    v_avisos := v_avisos || motor.aviso_tienda_json(v_id);
  end loop;
  if p_centro is not null and jsonb_array_length(v_avisos) = 0 then
    return motor.error('SIN_JORNADA', 'Esa tienda no puede recibir el aviso: ' || (v_sin -> 0 ->> 'motivo') || '.',
                       jsonb_build_object('sin_aviso', v_sin));
  end if;
  return jsonb_build_object('avisos', v_avisos, 'sin_aviso', v_sin);
end;
$$;

-- Avisos a las tiendas de la última semana y los que vienen (leídos o no), para verlos y cancelarlos.
create or replace function motor.avisos_tiendas_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('avisos', coalesce(jsonb_agg(motor.aviso_tienda_json(i.id) order by i.iniciada_en desc), '[]'::jsonb))
  from public.incidencias i join public.personas p on p.id = i.persona_id and p.rol = 'tienda'
  where i.opcion = 'aviso' and i.iniciada_en >= motor.en_local(motor.fecha_local(p_ahora) - 7, '00:00');
$$;

-- ---------------------------------------------------------------------------
-- 9. Funciones para las pantallas
-- ---------------------------------------------------------------------------
create or replace function motor.api_tienda_hoy()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.tienda_hoy_de(auth.uid(), now());
end; $$;

create or replace function motor.api_empezar_turno(p_persona_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.empezar_turno_tienda_de(auth.uid(), p_persona_id, now());
end; $$;

create or replace function motor.api_marcar_punto(p_elemento_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.marcar_punto_de(auth.uid(), p_elemento_id, now());
end; $$;

create or replace function motor.api_terminar_tarea_tienda(p_tarea_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.terminar_tarea_tienda_de(auth.uid(), p_tarea_id, now());
end; $$;

create or replace function motor.api_compartir_video(p_tarea_id uuid, p_enlace text, p_aprendido text, p_no_he_podido boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.compartir_video_de(auth.uid(), p_tarea_id, p_enlace, p_aprendido, p_no_he_podido, now());
end; $$;

create or replace function motor.api_marcar_aviso_leido(p_aviso_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.marcar_aviso_leido_de(auth.uid(), p_aviso_id, now());
end; $$;

create or replace function motor.api_videos_semana(p_limite integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if not (motor.es_tienda() or motor.es_admin()) then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  return motor.videos_semana_de(p_limite);
end; $$;

create or replace function motor.api_personas_tienda(p_tienda_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('*');
begin
  if v_error is not null then return v_error; end if;
  if motor.es_admin() then
    return motor.personas_tienda_de(p_tienda_id);
  elsif motor.es_tienda() then
    return motor.personas_tienda_de(motor.mi_centro());
  end if;
  return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
end; $$;

create or replace function motor.api_guardar_persona_tienda(p_id uuid, p_tienda_id uuid, p_nombre text, p_cuando text,
                                                            p_turno text, p_activo boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.guardar_persona_tienda_de(auth.uid(), p_id, p_tienda_id, p_nombre, p_cuando, p_turno, p_activo);
end; $$;

create or replace function motor.api_marcar_dia_cerrado(p_fecha date, p_tienda_id uuid, p_cerrado boolean, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.marcar_dia_cerrado_de(auth.uid(), p_fecha, p_tienda_id, p_cerrado, p_motivo, now());
end; $$;

create or replace function motor.api_dias_cerrados(p_desde date, p_hasta date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.dias_cerrados_de(coalesce(p_desde, motor.fecha_local(now())),
                                coalesce(p_hasta, coalesce(p_desde, motor.fecha_local(now())) + 366));
end; $$;

create or replace function motor.api_crear_aviso_tienda(p_id_cliente uuid, p_fecha date, p_texto text, p_tienda_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_aviso_tienda_de(auth.uid(), p_id_cliente, p_fecha, p_texto, p_tienda_id, now());
end; $$;

create or replace function motor.api_avisos_tiendas()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.avisos_tiendas_de(now());
end; $$;

create or replace function public.tienda_hoy()
returns jsonb language sql set search_path = '' as $$ select motor.api_tienda_hoy() $$;
create or replace function public.empezar_turno(persona_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_empezar_turno(persona_id) $$;
create or replace function public.marcar_punto(elemento_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_marcar_punto(elemento_id) $$;
create or replace function public.terminar_tarea_tienda(tarea_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_terminar_tarea_tienda(tarea_id) $$;
create or replace function public.compartir_video(tarea_id uuid, enlace text default null, aprendido text default null,
                                                  no_he_podido boolean default false)
returns jsonb language sql set search_path = '' as $$
  select motor.api_compartir_video(tarea_id, enlace, aprendido, no_he_podido) $$;
create or replace function public.marcar_aviso_leido(aviso_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_marcar_aviso_leido(aviso_id) $$;
create or replace function public.videos_semana(limite integer default 50)
returns jsonb language sql set search_path = '' as $$ select motor.api_videos_semana(limite) $$;
create or replace function public.personas_tienda(tienda_id uuid default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_personas_tienda(tienda_id) $$;
create or replace function public.guardar_persona_tienda(nombre text, tienda_id uuid default null, id uuid default null,
                                                         cuando text default null, turno text default null,
                                                         activo boolean default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_guardar_persona_tienda(id, tienda_id, nombre, cuando, turno, activo) $$;
create or replace function public.marcar_dia_cerrado(fecha date, tienda_id uuid default null, cerrado boolean default true,
                                                     motivo text default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_marcar_dia_cerrado(fecha, tienda_id, cerrado, motivo) $$;
create or replace function public.dias_cerrados(desde date default null, hasta date default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_dias_cerrados(desde, hasta) $$;
create or replace function public.crear_aviso_tienda(id_cliente uuid, fecha date, texto text, tienda_id uuid default null)
returns jsonb language sql set search_path = '' as $$ select motor.api_crear_aviso_tienda(id_cliente, fecha, texto, tienda_id) $$;
create or replace function public.avisos_tiendas()
returns jsonb language sql set search_path = '' as $$ select motor.api_avisos_tiendas() $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.api_tienda_hoy(), motor.api_empezar_turno(uuid), motor.api_marcar_punto(uuid), motor.api_terminar_tarea_tienda(uuid),
  motor.api_compartir_video(uuid, text, text, boolean), motor.api_marcar_aviso_leido(uuid), motor.api_videos_semana(integer),
  motor.api_personas_tienda(uuid), motor.api_guardar_persona_tienda(uuid, uuid, text, text, text, boolean),
  motor.api_marcar_dia_cerrado(date, uuid, boolean, text), motor.api_dias_cerrados(date, date),
  motor.api_crear_aviso_tienda(uuid, date, text, uuid), motor.api_avisos_tiendas(),
  motor.es_tienda()   -- la usan las políticas RLS, como es_admin y mi_centro
to authenticated;
revoke execute on function
  public.tienda_hoy(), public.empezar_turno(uuid), public.marcar_punto(uuid), public.terminar_tarea_tienda(uuid),
  public.compartir_video(uuid, text, text, boolean), public.marcar_aviso_leido(uuid), public.videos_semana(integer),
  public.personas_tienda(uuid), public.guardar_persona_tienda(text, uuid, uuid, text, text, boolean),
  public.marcar_dia_cerrado(date, uuid, boolean, text), public.dias_cerrados(date, date),
  public.crear_aviso_tienda(uuid, date, text, uuid), public.avisos_tiendas()
from public, anon;
grant execute on function
  public.tienda_hoy(), public.empezar_turno(uuid), public.marcar_punto(uuid), public.terminar_tarea_tienda(uuid),
  public.compartir_video(uuid, text, text, boolean), public.marcar_aviso_leido(uuid), public.videos_semana(integer),
  public.personas_tienda(uuid), public.guardar_persona_tienda(text, uuid, uuid, text, text, boolean),
  public.marcar_dia_cerrado(date, uuid, boolean, text), public.dias_cerrados(date, date),
  public.crear_aviso_tienda(uuid, date, text, uuid), public.avisos_tiendas()
to authenticated;
