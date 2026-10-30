-- Tarea 22 · Incidencias nuevas, lista de compras y avisos de Administración
-- (ESTADO_DEL_SISTEMA.md v1.36: §6.6 «Incidencias» y §7 «Aprovisionamiento»).
-- Se amplía lo que hay (la tabla `incidencias`, crear_incidencia, el correo en el
-- momento, cerrar_incidencia, incidencias_abiertas y el cierre del turno); no hay
-- un segundo sistema de incidencias ni de avisos.
--   1. Lista de compras (`public.compras`), con su carga inicial (§7).
--   2. crear_incidencia: opción `comprar` (con `compra_id`, o «otra cosa») y `varios`;
--      las de antes se siguen aceptando. Lleva un parámetro más (`compra_id`), así
--      que la función se vuelve a crear con su firma nueva.
--   3. Avisos de Administración para un día: una incidencia del operario por
--      defecto (`opcion = aviso`), sin tarea; desde su día cuenta en sus
--      incidencias abiertas y sale en tarea_activa (`avisos`). El contacto solo
--      está en la base de datos (no va en el correo del cierre).
--
-- Deshacer: volver a crear las funciones como estaban (20261027120100,
-- 20261029140000 y 20261030105121), crear_incidencia con su firma de antes, quitar
-- las funciones nuevas, las columnas compra_id, contacto y creada_por de
-- incidencias, el check de opcion de antes y la tabla compras.

-- ---------------------------------------------------------------------------
-- 1. Lista de compras
-- ---------------------------------------------------------------------------
create table public.compras (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null check (btrim(nombre) <> ''),
  forma       text not null check (forma in ('internet', 'tienda', 'administracion')),
  enlace      text,
  sitio       text,
  direccion   text,
  nota        text,
  activo      boolean not null default true,
  orden       integer not null default 100,
  actualizada_en timestamptz not null default now(),
  actualizada_por uuid references public.personas (id),
  check (forma <> 'internet' or enlace is not null),
  check (forma <> 'tienda' or sitio is not null)
);
comment on table public.compras is
  'Lista de compras (ESTADO §7): cada producto con su forma de compra. Quitar = desactivar (activo = false), para el histórico.';
create index compras_actualizada_por_idx on public.compras (actualizada_por);

revoke all on public.compras from anon, authenticated;
grant select on public.compras to authenticated;
alter table public.compras enable row level security;
create policy lectura on public.compras for select to authenticated
  using ((select motor.es_admin())
         or exists (select 1 from public.personas p where p.id = (select auth.uid()) and p.activo));

insert into public.compras (nombre, forma, enlace, sitio, direccion, nota, orden) values
  ('Bolsas adhesivas pequeñas', 'internet', 'https://www.amazon.es/dp/B077ZQQ8Q5', null, null,
   'Resinas, extractos y flores de 4 g; 8×12 + 3 cm de solapa.', 10),
  ('Bolsas adhesivas grandes', 'internet', 'https://www.amazon.es/dp/B073JN44TZ', null, null,
   'Flores de 10 g; 10×15 + 3 cm de solapa.', 20),
  ('Bolsas para vapers', 'internet', 'https://www.amazon.es/dp/B0B6VFPF7F', null, null,
   'Mylar con sellado térmico, 5×18 cm.', 30),
  ('Hojas de etiquetas adhesivas', 'internet', 'https://www.amazon.es/dp/B004TV40R0', null, null, null, 40),
  ('Agujas luer lock', 'internet', 'https://www.amazon.es/dp/B0DRVVTN1R', null, null, null, 50),
  ('Jeringuillas luer lock', 'internet', 'https://www.amazon.es/dp/B0DFMMMK5V', null, null, 'Seleccionar 50 ml.', 60),
  ('Alcohol', 'tienda', null, 'Cualquier supermercado', null, null, 70),
  ('Papel de cocina', 'tienda', null, 'Cualquier supermercado', null, null, 71),
  ('Papel de horno', 'tienda', null, 'Cualquier supermercado', null, null, 72),
  ('Productos de limpieza', 'tienda', null, 'Cualquier supermercado', null, null, 73),
  ('Guantes de nitrilo', 'tienda', null, 'Arte Sano Tattoo Supplies',
   'C/ San Nicolás de Olabeaga 12 (lonja), 48013 Bilbao', null, 80),
  ('Material de oficina', 'tienda', null, 'Cualquier bazar chino', null, null, 90),
  ('Plástico de burbujas', 'tienda', null, 'Cualquier bazar chino', null, null, 91),
  ('Cinta aislante', 'tienda', null, 'Cualquier bazar chino', null, null, 92),
  ('Rollos de TPV', 'tienda', null, 'Kutxabank', 'Avda. Lehendakari Aguirre 13, Deusto, Bilbao', null, 100),
  ('Bolsas para tienda', 'tienda', null, 'Retif Bilbao', 'C/ Máximo Aguirre 10, 48009 Bilbao', null, 110),
  ('Plástico negro de embalar', 'tienda', null, 'Retif Bilbao', 'C/ Máximo Aguirre 10, 48009 Bilbao', null, 111),
  ('Cajas de packaging', 'administracion', null, 'Imprenta Sprint Digital', null,
   'Avisa y pasa el recuento; Administración dice cuántas pedir.', 120),
  ('Pegatinas de packaging', 'administracion', null, 'Imprenta Sprint Digital', null,
   'Avisa y pasa el recuento; Administración dice cuántas pedir.', 121),
  ('Granel', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 130),
  ('Aceites', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 131),
  ('Cremas', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 132),
  ('Distillate', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 133),
  ('CBDX', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 134),
  ('Kief', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 135),
  ('Terpenos', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 136),
  ('Carcasas de vaper', 'administracion', null, null, null, 'Materia prima: la pide Administración.', 137);

create or replace function motor.compra_json(c public.compras)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'nombre', c.nombre, 'forma', c.forma, 'enlace', c.enlace, 'sitio', c.sitio,
                            'direccion', c.direccion, 'nota', c.nota, 'activo', c.activo, 'orden', c.orden)
$$;

create or replace function motor.compras_lista_de()
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('compras', coalesce(jsonb_agg(motor.compra_json(c) order by c.orden, c.nombre), '[]'::jsonb))
  from public.compras c where c.activo
$$;

-- Añadir (sin id), cambiar (con id) o quitar (activo = false) un producto de la lista.
create or replace function motor.guardar_compra_de(
  p_persona uuid, p_id uuid, p_nombre text, p_forma text, p_enlace text, p_sitio text, p_direccion text,
  p_nota text, p_orden integer, p_activo boolean)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_nombre text := nullif(btrim(p_nombre), '');
  v_enlace text := nullif(btrim(p_enlace), '');
  v_sitio text := nullif(btrim(p_sitio), '');
  c public.compras;
begin
  if p_id is not null then
    select * into c from public.compras where id = p_id;
    if c.id is null then
      return motor.error('NO_ENCONTRADO', 'Ese producto no está en la lista de compras.');
    end if;
  end if;
  if v_nombre is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el nombre del producto.');
  end if;
  if p_forma is null or p_forma not in ('internet', 'tienda', 'administracion') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige cómo se compra: por internet, en una tienda o lo pide Administración.');
  end if;
  if p_forma = 'internet' and (v_enlace is null or v_enlace !~* '^https?://') then
    return motor.error('DATOS_NO_VALIDOS', 'Pega el enlace de la compra por internet.');
  end if;
  if p_forma = 'tienda' and v_sitio is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe en qué tienda se compra.');
  end if;
  if p_id is null then
    insert into public.compras (nombre, forma, enlace, sitio, direccion, nota, activo, orden, actualizada_en, actualizada_por)
    values (v_nombre, p_forma, v_enlace, v_sitio, nullif(btrim(p_direccion), ''), nullif(btrim(p_nota), ''),
            coalesce(p_activo, true),
            coalesce(p_orden, (select coalesce(max(orden), 0) + 10 from public.compras)), now(), p_persona)
    returning * into c;
  else
    update public.compras
       set nombre = v_nombre, forma = p_forma, enlace = v_enlace, sitio = v_sitio,
           direccion = nullif(btrim(p_direccion), ''), nota = nullif(btrim(p_nota), ''),
           activo = coalesce(p_activo, activo), orden = coalesce(p_orden, orden),
           actualizada_en = now(), actualizada_por = p_persona
     where id = p_id
    returning * into c;
  end if;
  perform motor.registrar('compra_guardada', p_persona, null, null,
                          jsonb_build_object('compra', c.id, 'nombre', c.nombre, 'activo', c.activo));
  return jsonb_build_object('compra', motor.compra_json(c));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Incidencias: comprar y varios; avisos de Administración
-- ---------------------------------------------------------------------------
alter table public.incidencias drop constraint incidencias_opcion_check;
alter table public.incidencias add constraint incidencias_opcion_check check (opcion in (
  'comprar', 'varios', 'aviso',
  'llega_mercancia', 'pedido_cliente', 'pedir_comprar', 'recogida_nacex', 'corregir'));
alter table public.incidencias
  add column compra_id uuid references public.compras (id),
  add column contacto text,
  add column creada_por uuid references public.personas (id);
comment on column public.incidencias.compra_id is 'Lo que hay que comprar, de la lista de compras (opción comprar).';
comment on column public.incidencias.contacto is 'Aviso de Administración: contacto (dato personal; no sale en el correo).';
comment on column public.incidencias.creada_por is 'Aviso de Administración: quién lo creó.';
comment on column public.incidencias.iniciada_en is 'Cuándo se abrió. Un aviso para otro día: el comienzo del turno de ese día.';
create index incidencias_compra_id_idx on public.incidencias (compra_id);
create index incidencias_creada_por_idx on public.incidencias (creada_por);

-- «Guantes de nitrilo» → «guantes de nitrilo»; «TPV» se queda igual (en el título de la tarea).
create or replace function motor.minuscula_inicial(p_texto text)
returns text language sql immutable set search_path = '' as $$
  select case when p_texto is null or upper(left(p_texto, 2)) = left(p_texto, 2) then p_texto
              else lower(left(p_texto, 1)) || substr(p_texto, 2) end
$$;

-- Al hacer su tarea, una compra (por internet, o «pedir o comprar» de antes) queda
-- «pedido, esperando a que llegue»; el resto se cierra.
create or replace function motor.espera_llegada(p_opcion text, p_compra uuid)
returns boolean language sql stable set search_path = '' as $$
  select p_opcion = 'pedir_comprar'
      or (p_opcion = 'comprar' and exists (select 1 from public.compras c where c.id = p_compra and c.forma = 'internet'))
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
    else 'Incidencia' end;
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

create or replace function motor.seguimiento_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'incidencias_abiertas', (select count(*) from public.incidencias i
                              where i.persona_id = p_persona and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora)::int,
    -- Avisos de Administración de hoy (o de días pasados sin cerrar), arriba de la pantalla.
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'texto', i.descripcion, 'contacto', i.contacto,
                                          'fecha', motor.fecha_local(i.iniciada_en)) order by i.iniciada_en)
        from public.incidencias i
       where i.persona_id = p_persona and i.opcion = 'aviso' and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'incidencia_en_curso', (
      select motor.incidencia_json(i.id, p_ahora)
        from public.incidencias i left join public.tareas t on t.id = i.tarea_resolucion_id
       where i.persona_id = p_persona and i.estado = 'abierta' and (t.estado = 'en_curso' or i.opcion is null)
       order by i.iniciada_en desc limit 1),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.persona_id = p_persona and p.estado <> 'resuelto'), '[]'::jsonb));
$$;

create or replace function motor.incidencias_abiertas_de(p_persona uuid, p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'total', count(*)::int,
    'incidencias', coalesce(jsonb_agg(motor.incidencia_json(i.id, p_ahora) order by i.iniciada_en), '[]'::jsonb))
  from public.incidencias i
  where i.persona_id = p_persona and i.estado <> 'cerrada' and i.iniciada_en <= p_ahora;  -- un aviso, desde su día
$$;

create or replace function motor.tras_tarea_hecha()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_persona uuid := (select persona_id from public.jornadas where id = new.jornada_id);
  v_cuando timestamptz := coalesce(new.terminada_en, now());
  i public.incidencias;
  p public.plantillas_tarea;
begin
  for i in
    update public.incidencias
       set estado = case when motor.espera_llegada(opcion, compra_id) then 'esperando_llegada' else 'cerrada' end,
           terminada_en = case when motor.espera_llegada(opcion, compra_id) then null else v_cuando end,
           cerrada_por = case when motor.espera_llegada(opcion, compra_id) then null else v_persona end
     where tarea_resolucion_id = new.id and estado = 'abierta'
    returning *
  loop
    perform motor.registrar(case when i.estado = 'cerrada' then 'incidencia_cerrada' else 'incidencia_pedida' end,
                            v_persona, new.jornada_id, new.id,
                            jsonb_build_object('incidencia', i.id, 'por', 'tarea hecha', 'a_las', v_cuando));
  end loop;

  if new.prioridad_cola = 'D' and new.plantilla_id is not null then
    select * into p from public.plantillas_tarea where id = new.plantilla_id;
    perform motor.insertar_desde_plantilla(new.jornada_id, p.id, p.codigo || ':' || new.id, 'plantilla');
  end if;
  return null;
end;
$$;


create or replace function motor.aviso_json(p_incidencia uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('id', i.id, 'fecha', motor.fecha_local(i.iniciada_en), 'texto', i.descripcion,
                            'contacto', i.contacto, 'estado', i.estado, 'creado_por', p.nombre, 'cerrado_en', i.terminada_en,
                            'nota', i.nota_cierre)
  from public.incidencias i left join public.personas p on p.id = i.creada_por
  where i.id = p_incidencia and i.opcion = 'aviso'
$$;

-- Aviso para el almacén (Administración): una incidencia del operario por defecto
-- para ese día, sin tarea. Hoy o un día que viene en que trabaje el almacén.
create or replace function motor.crear_aviso_almacen_de(
  p_persona uuid, p_id_cliente uuid, p_fecha date, p_texto text, p_contacto text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_texto text := nullif(btrim(regexp_replace(coalesce(p_texto, ''), '\s+', ' ', 'g')), '');
  v_op uuid := motor.operario_por_defecto();
  v_hoy date := motor.fecha_local(p_ahora);
  v_jornada uuid;
  v_id uuid;
begin
  select id into v_id from public.incidencias where id_cliente = p_id_cliente and opcion = 'aviso';
  if v_id is not null then
    return jsonb_build_object('aviso', motor.aviso_json(v_id));
  end if;
  if p_id_cliente is null or v_texto is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe el aviso.');
  end if;
  if p_fecha is null or p_fecha < v_hoy then
    return motor.error('DATOS_NO_VALIDOS', 'El aviso tiene que ser para hoy o para un día que viene.');
  end if;
  v_jornada := case when v_op is not null then motor.jornada_para(v_op, p_fecha, p_ahora) end;
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Ese día no trabaja el almacén.');
  end if;
  insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, estado,
                                  contacto, creada_por)
  values (v_jornada, v_op, v_texto,
          case when p_fecha = v_hoy then p_ahora else coalesce(motor.inicio_turno(v_op, p_fecha, null), motor.en_local(p_fecha, '00:00')) end,
          p_id_cliente, 'aviso', 'abierta', nullif(btrim(p_contacto), ''), p_persona)
  returning id into v_id;
  perform motor.registrar('aviso_creado', p_persona, v_jornada, null,
                          jsonb_build_object('incidencia', v_id, 'fecha', p_fecha, 'a_las', p_ahora));
  return jsonb_build_object('aviso', motor.aviso_json(v_id));
end;
$$;

-- Administración cancela un aviso que ya no hace falta (queda cerrado, con su nota).
create or replace function motor.cancelar_aviso_almacen_de(p_persona uuid, p_aviso uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  i public.incidencias;
begin
  select * into i from public.incidencias where id = p_aviso and opcion = 'aviso' for update;
  if i.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese aviso no existe.');
  end if;
  if i.estado <> 'cerrada' then
    update public.incidencias
       set estado = 'cerrada', terminada_en = p_ahora, cerrada_por = p_persona, nota_cierre = 'Cancelado por Administración'
     where id = i.id;
    perform motor.registrar('aviso_cancelado', p_persona, i.jornada_id, null,
                            jsonb_build_object('incidencia', i.id, 'a_las', p_ahora));
  end if;
  return jsonb_build_object('aviso', motor.aviso_json(i.id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Funciones para las pantallas
-- ---------------------------------------------------------------------------
drop function public.crear_incidencia(uuid, text, text, text, text, uuid, text);
drop function motor.api_crear_incidencia(uuid, text, text, text, text, uuid, text);
drop function motor.crear_incidencia_de(uuid, uuid, text, text, text, text, uuid, text, timestamptz);

create function motor.crear_incidencia_de(
  p_persona uuid, p_id_cliente uuid, p_opcion text, p_descripcion text, p_quien text, p_importancia text,
  p_tarea uuid, p_tipo_problema text, p_compra uuid, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_desc text := nullif(btrim(regexp_replace(coalesce(p_descripcion, ''), '\s+', ' ', 'g')), '');
  v_quien text := coalesce(p_quien, 'operario');
  v_imp text := coalesce(p_importancia, case when p_opcion in ('llega_mercancia', 'corregir') then 'ahora' else 'hoy' end);
  v_jornada uuid;
  v_id uuid;
  c public.compras;
  v_tarea uuid;
  v_evento jsonb;
begin
  select id into v_id from public.incidencias where id_cliente = p_id_cliente and persona_id = p_persona;
  if v_id is not null then
    return jsonb_build_object('incidencia', motor.incidencia_json(v_id, p_ahora),
                              'tarea', motor.tarea_json((select tarea_resolucion_id from public.incidencias where id = v_id)),
                              'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
  end if;
  if p_opcion is null
     or p_opcion not in ('comprar', 'varios', 'bloqueado',
                         'llega_mercancia', 'pedido_cliente', 'pedir_comprar', 'recogida_nacex', 'corregir') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige qué pasa.');
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
  end if;

  -- «Estoy bloqueado»: el flujo de problemas, sobre la tarea en curso (o la que le toca).
  if p_opcion = 'bloqueado' then
    v_tarea := coalesce(p_tarea,
                        (select id from public.tareas where jornada_id = v_jornada and estado = 'en_curso'),
                        motor.elegir_tarea(v_jornada, p_ahora, null));
    if v_tarea is null then
      return motor.error('SIN_TAREA', 'No tienes ninguna tarea abierta que se haya bloqueado.');
    end if;
    v_evento := motor.abrir_problema_de(p_persona, p_id_cliente, v_tarea, coalesce(p_tipo_problema, 'otro'), v_desc, p_ahora);
    return case when v_evento ? 'error' then v_evento else jsonb_build_object('incidencia', null) || v_evento end;
  end if;

  -- Hay que comprar algo (§6.6 y §7): de la lista de compras, según cómo se compra;
  -- «otra cosa» (sin compra_id), una línea y correo a Administración.
  if p_opcion = 'comprar' then
    if p_compra is not null then
      select * into c from public.compras where id = p_compra and activo;
      if c.id is null then
        return motor.error('DATOS_NO_VALIDOS', 'Ese producto ya no está en la lista de compras.');
      end if;
      v_desc := c.nombre || coalesce(': ' || v_desc, '');
    end if;
    v_quien := case when c.forma in ('internet', 'tienda') then 'operario' else 'administracion' end;
  end if;
  if v_desc is null then
    return motor.error('DATOS_NO_VALIDOS', 'Escribe en una línea qué pasa.');
  end if;
  if v_quien not in ('operario', 'administracion') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige quién la resuelve.');
  end if;
  if v_imp not in ('ahora', 'hoy', 'cuando_pueda') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige la importancia.');
  end if;

  v_id := gen_random_uuid();
  if v_quien = 'operario' then
    -- Llega mercancía y pedido de cliente: la tarea de siempre (registrar_evento).
    if p_opcion in ('llega_mercancia', 'pedido_cliente') then
      v_evento := motor.registrar_evento_de(p_persona, p_id_cliente, p_opcion, v_desc, p_ahora);
      if v_evento ? 'error' then
        return v_evento;
      end if;
      v_tarea := (v_evento -> 'tarea' ->> 'id')::uuid;
    end if;
    if v_tarea is null then
      insert into public.tareas (jornada_id, clave, origen, titulo, porque, disponible_desde, no_terminada, orden, creada_por)
      values (v_jornada, 'incidencia:' || v_id, 'evento',
              case when p_opcion = 'comprar' and c.forma = 'internet' then 'Compra: ' || c.nombre
                   when p_opcion = 'comprar' then 'Ve a comprar ' || motor.minuscula_inicial(c.nombre)
                                                  || ' a ' || case when c.sitio ilike 'cualquier %'
                                                                   then motor.minuscula_inicial(c.sitio) else c.sitio end
                   when p_opcion = 'varios' then v_desc
                   else case p_opcion when 'pedir_comprar' then 'Pedir o comprar: '
                                      when 'recogida_nacex' then 'Recogida en Nacex: '
                                      when 'llega_mercancia' then 'Llega mercancía: '
                                      when 'pedido_cliente' then 'Pedido de cliente: '
                                      else 'Corregir: ' end || v_desc end,
              case when p_opcion = 'comprar' and c.forma = 'tienda' then c.direccion end,
              p_ahora, 'arrastrar', 35, p_persona)
      returning id into v_tarea;
      perform motor.registrar('tarea_creada', p_persona, v_jornada, v_tarea,
                              jsonb_build_object('clave', 'incidencia:' || v_id, 'origen', 'evento'));
    end if;
    -- Ahora: como las urgentes. Hoy: obligatoria del día. Cuando pueda: cola de tiempo libre.
    update public.tareas
       set urgente = v_imp = 'ahora',
           obligatoria = v_imp <> 'cuando_pueda',
           prioridad_cola = case when v_imp = 'cuando_pueda' then 'C' end,
           no_terminada = case when v_imp = 'cuando_pueda' then 'sigue_abierta' else 'arrastrar' end
     where id = v_tarea;
  end if;

  insert into public.incidencias (id, jornada_id, persona_id, tarea_id, descripcion, iniciada_en, id_cliente,
                                  opcion, quien, importancia, estado, tarea_resolucion_id, compra_id)
  values (v_id, v_jornada, p_persona,
          (select id from public.tareas where jornada_id = v_jornada and estado = 'en_curso'),
          v_desc, p_ahora, p_id_cliente, p_opcion, v_quien, v_imp,
          case when v_quien = 'administracion' then 'esperando_administracion' else 'abierta' end, v_tarea, c.id);
  perform motor.registrar('incidencia_creada', p_persona, v_jornada, v_tarea,
                          jsonb_build_object('incidencia', v_id, 'opcion', p_opcion, 'quien', v_quien, 'importancia', v_imp));
  if v_quien = 'administracion' then
    perform motor.encolar_correo('incidencia', v_id::text);
  end if;

  return jsonb_build_object('incidencia', motor.incidencia_json(v_id, p_ahora),
                            'tarea', motor.tarea_json(v_tarea),
                            'tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

create or replace function motor.tarea_json(p_tarea uuid)
returns jsonb
language sql stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'clave', t.clave, 'titulo', t.titulo, 'porque', t.porque,
    'estado', t.estado, 'origen', t.origen, 'obligatoria', t.obligatoria,
    'urgente', t.urgente, 'contenido', t.contenido,
    'hora_programada', t.hora_programada, 'hora_limite', t.hora_limite,
    'duracion_min', t.duracion_min, 'arrastrada_de', t.tarea_origen_id,
    'iniciada_en', t.iniciada_en, 'terminada_en', t.terminada_en,
    -- Compra por internet (Tarea 22): el enlace de la lista de compras.
    'enlace', (select c.enlace from public.incidencias i join public.compras c on c.id = i.compra_id
                where i.tarea_resolucion_id = t.id and c.forma = 'internet' limit 1),
    'elementos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'tipo', e.tipo, 'producto', e.producto, 'formato', e.formato,
               'texto', case when e.tipo in ('peticion', 'llamada') then e.producto end,
               'categoria', e.categoria, 'destino', c.nombre, 'destino_id', e.destino_id,
               'bolsa', case when e.tipo = 'referencia_produccion' then null
                             when e.lote like 'pedido:%' then 'Pedido de cliente · ' || pc.cliente
                             when e.lote = 'envio' then 'Envío'
                             else 'Bolsa de reposición' end,
               'cantidad', e.cantidad, 'cantidad_hecha', e.cantidad_hecha, 'motivo', e.motivo,
               'orden_sugerido', e.orden_sugerido, 'estado', e.estado)
             -- R1e: referencia sin granel, con quién la recibe, quién tiene y lo decidido.
             || case when e.tipo = 'referencia_produccion' and coalesce((e.calculo ->> 'sin_granel')::boolean, false)
                     then jsonb_build_object('sin_granel', true, 'para', coalesce(e.calculo -> 'para', '[]'::jsonb),
                                             'tiendas_con_stock', coalesce(e.calculo -> 'tiendas_con_stock', '[]'::jsonb),
                                             'resuelto', coalesce((e.calculo ->> 'resuelto')::boolean, false),
                                             'decisiones', motor.decisiones_json(e.calculo -> 'decisiones'))
                     else '{}'::jsonb end
             order by e.tipo = 'referencia_produccion' desc, c.nombre nulls first, e.lote like 'pedido:%',
                      e.tipo in ('peticion', 'llamada'), e.tipo = 'llamada', e.lote, e.orden_sugerido, e.producto, e.formato)
      from public.tarea_elementos e
      left join public.centros_trabajo c on c.id = e.destino_id
      left join public.pedidos_cliente pc on e.lote like 'pedido:%' and pc.id::text = substr(e.lote, 8)
      where e.tarea_id = t.id), '[]'::jsonb))
  from public.tareas t where t.id = p_tarea;
$$;

create or replace function motor.estado_actual_de(p_ahora timestamptz)
returns jsonb language sql stable set search_path = '' as $$
  with op as (select id, nombre from public.personas where id = motor.operario_por_defecto()),
  j as (select jo.* from public.jornadas jo join op on op.id = jo.persona_id where jo.fecha = motor.fecha_local(p_ahora))
  select jsonb_build_object(
    'ahora', motor.hora_texto(p_ahora),
    'fecha', motor.fecha_local(p_ahora),
    'operario', (select jsonb_build_object('id', op.id, 'nombre', op.nombre) from op),
    'jornada', (select jsonb_build_object('id', j.id, 'sale', j.sale, 'hay_envio', j.hay_envio, 'estado', j.estado) from j),
    'en_curso', (select motor.tarea_json(t.id) from public.tareas t join j on j.id = t.jornada_id where t.estado = 'en_curso'),
    'reparto_de_hoy', (
      select jsonb_build_object('reparto_id', r.id, 'aceptado_en', r.pegado_en,
                                'pegado_por', r.pegado_por, 'pegado_por_nombre', pe.nombre,
                                'paradas', motor.paradas_reparto(j.id))
        from public.repartos r join j on j.id = r.jornada_id
        left join public.personas pe on pe.id = r.pegado_por
       where r.tipo = 'reparto' and r.estado = 'aceptado'),
    'problemas_abiertos', coalesce((
      select jsonb_agg(motor.problema_json(p.id) || jsonb_build_object('tarea', t.titulo) order by p.abierto_en)
        from public.problemas p join public.tareas t on t.id = p.tarea_id
       where p.estado <> 'resuelto' and p.persona_id = (select id from op)), '[]'::jsonb),
    'incidencia_en_curso', motor.seguimiento_de((select id from op), p_ahora) -> 'incidencia_en_curso',
    'incidencias_abiertas', coalesce((
      select jsonb_agg(motor.incidencia_json(i.id, p_ahora) order by i.iniciada_en)
        from public.incidencias i where i.persona_id = (select id from op) and i.estado <> 'cerrada'
                                    and i.iniciada_en <= p_ahora), '[]'::jsonb),
    'arrastradas', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado) order by t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id where t.tarea_origen_id is not null), '[]'::jsonb),
    'hoy', coalesce((
      select jsonb_agg(jsonb_build_object('id', t.id, 'titulo', t.titulo, 'estado', t.estado, 'origen', t.origen,
                                          'obligatoria', t.obligatoria, 'urgente', t.urgente,
                                          'hora', motor.hora_texto(coalesce(t.hora_programada, t.hora_limite)),
                                          'motivo', t.motivo_no_hecha,
                                          'iniciada_en', t.iniciada_en, 'terminada_en', t.terminada_en,
                                          'minutos', motor.minutos_tarea(t, p_ahora),
                                          'interrupciones', motor.interrupciones_tarea(t.id),
                                          'cajas', motor.cajas_tarea(t.id),
                                          'minutos_trabajados', motor.minutos_trabajados(t.id, p_ahora))
                       order by coalesce(t.hora_programada, t.hora_limite) nulls last, t.orden, t.creada_en)
        from public.tareas t join j on j.id = t.jornada_id
       where not t.retirada_por_condicion and t.origen <> 'problema'), '[]'::jsonb),
    -- Avisos para el almacén que siguen abiertos (de hoy y de días que vienen), para verlos y cancelarlos.
    'avisos_almacen', coalesce((
      select jsonb_agg(motor.aviso_json(i.id) order by i.iniciada_en)
        from public.incidencias i
       where i.opcion = 'aviso' and i.estado <> 'cerrada' and i.persona_id = (select id from op)), '[]'::jsonb),
    'retrasos_salida', coalesce((
      select jsonb_agg(jsonb_build_object('a_las', motor.hora_texto((r.datos ->> 'a_las')::timestamptz),
                                          'minutos', (r.datos ->> 'minutos')::int, 'nueva_hora', r.datos ->> 'nueva_hora',
                                          'sale', r.datos ->> 'sale', 'aviso', r.datos ->> 'aviso') order by r.id)
        from public.registro_eventos r join j on j.id = r.jornada_id where r.tipo = 'salida_retrasada'), '[]'::jsonb),
    'correos_no_enviados', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', m.tipo, 'asunto', m.asunto, 'estado', m.estado, 'intentos', m.intentos,
                                          'error', m.ultimo_error, 'creado_en', m.creado_en) order by m.id desc)
        from motor.correos m
       where m.estado in ('fallido', 'dudoso') and m.creado_en >= p_ahora - interval '7 days'), '[]'::jsonb),
    -- «Orden y limpieza» de hoy: cuántas se han empezado y cuántos minutos en total.
    'tiempo_libre', (
      select jsonb_build_object('veces', count(*),
                                'minutos', coalesce(round(sum(extract(epoch from
                                  coalesce(t.terminada_en, case when t.estado = 'en_curso' then p_ahora end) - t.iniciada_en)) / 60), 0)::int)
        from public.tareas t join j on j.id = t.jornada_id
        join public.plantillas_tarea p on p.id = t.plantilla_id
       where p.codigo = 'cola_orden' and t.iniciada_en is not null),
    -- R4: productos con menos de 2 semanas, de la última lectura de la hoja que la trae.
    'cobertura_baja', coalesce((
      select jsonb_build_object('datos_leidos_en', l.leido_en, 'productos', coalesce(l.cobertura -> 'productos', '[]'::jsonb),
                                'avisos', coalesce(l.cobertura -> 'avisos', '[]'::jsonb))
        from public.lecturas_sheets l where l.correcto and l.cobertura is not null and l.leido_en <= p_ahora
       order by l.leido_en desc limit 1),
      jsonb_build_object('datos_leidos_en', null, 'productos', '[]'::jsonb, 'avisos', '[]'::jsonb)),
    'lectura_sheets', jsonb_build_object(
      'ultima_correcta', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo)
                            from public.lecturas_sheets l where l.correcto order by l.leido_en desc limit 1),
      'ultimo_error', (select jsonb_build_object('leido_en', l.leido_en, 'motivo', l.motivo, 'error', l.error)
                         from public.lecturas_sheets l where not l.correcto
                          and l.leido_en > coalesce((select max(k.leido_en) from public.lecturas_sheets k where k.correcto), '-infinity')
                         order by l.leido_en desc limit 1)));
$$;

create or replace function motor.api_crear_incidencia(
  p_id_cliente uuid, p_opcion text, p_descripcion text, p_quien text, p_importancia text, p_tarea_id uuid,
  p_tipo_problema text, p_compra_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_incidencia_de(auth.uid(), p_id_cliente, p_opcion, p_descripcion, p_quien, p_importancia,
                                   p_tarea_id, p_tipo_problema, p_compra_id, now());
end; $$;

create or replace function motor.api_compras_lista()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual();
begin
  if v_error is not null then return v_error; end if;
  return motor.compras_lista_de();
end; $$;

create or replace function motor.api_guardar_compra(
  p_id uuid, p_nombre text, p_forma text, p_enlace text, p_sitio text, p_direccion text, p_nota text,
  p_orden integer, p_activo boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.guardar_compra_de(auth.uid(), p_id, p_nombre, p_forma, p_enlace, p_sitio, p_direccion, p_nota, p_orden, p_activo);
end; $$;

create or replace function motor.api_crear_aviso_almacen(p_id_cliente uuid, p_fecha date, p_texto text, p_contacto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.crear_aviso_almacen_de(auth.uid(), p_id_cliente, p_fecha, p_texto, p_contacto, now());
end; $$;

create or replace function motor.api_cancelar_aviso_almacen(p_aviso_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.cancelar_aviso_almacen_de(auth.uid(), p_aviso_id, now());
end; $$;

create function public.crear_incidencia(
  id_cliente uuid, opcion text, descripcion text default null, quien text default null, importancia text default null,
  tarea_id uuid default null, tipo_problema text default null, compra_id uuid default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_crear_incidencia(id_cliente, opcion, descripcion, quien, importancia, tarea_id, tipo_problema, compra_id) $$;
create or replace function public.compras_lista()
returns jsonb language sql set search_path = '' as $$ select motor.api_compras_lista() $$;
create or replace function public.guardar_compra(
  nombre text, forma text, id uuid default null, enlace text default null, sitio text default null,
  direccion text default null, nota text default null, orden integer default null, activo boolean default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_guardar_compra(id, nombre, forma, enlace, sitio, direccion, nota, orden, activo) $$;
create or replace function public.crear_aviso_almacen(id_cliente uuid, fecha date, texto text, contacto text default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_crear_aviso_almacen(id_cliente, fecha, texto, contacto) $$;
create or replace function public.cancelar_aviso_almacen(aviso_id uuid)
returns jsonb language sql set search_path = '' as $$ select motor.api_cancelar_aviso_almacen(aviso_id) $$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.api_crear_incidencia(uuid, text, text, text, text, uuid, text, uuid), motor.api_compras_lista(),
  motor.api_guardar_compra(uuid, text, text, text, text, text, text, integer, boolean),
  motor.api_crear_aviso_almacen(uuid, date, text, text), motor.api_cancelar_aviso_almacen(uuid)
to authenticated;
revoke execute on function
  public.crear_incidencia(uuid, text, text, text, text, uuid, text, uuid), public.compras_lista(),
  public.guardar_compra(text, text, uuid, text, text, text, text, integer, boolean),
  public.crear_aviso_almacen(uuid, date, text, text), public.cancelar_aviso_almacen(uuid)
from public, anon;
grant execute on function
  public.crear_incidencia(uuid, text, text, text, text, uuid, text, uuid), public.compras_lista(),
  public.guardar_compra(text, text, uuid, text, text, text, text, integer, boolean),
  public.crear_aviso_almacen(uuid, date, text, text), public.cancelar_aviso_almacen(uuid)
to authenticated;
