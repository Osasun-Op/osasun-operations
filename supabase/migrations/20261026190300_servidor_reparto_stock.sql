-- Tarea 3 · Funciones que usan las funciones del servidor pegar_reparto y lista_stock
-- Solo las ejecuta el servidor (rol service_role): ningún usuario puede
-- llamarlas, así que nadie puede guardar un reparto o una lista sin pasar por
-- el cálculo del servidor.
-- También: solicitudes internas de un solo uso (para invocar las funciones del
-- servidor desde la base de datos, sin claves) y, solo en pruebas, prueba.invocar.

create extension if not exists pg_net;

create table motor.solicitudes_servidor (
  id          uuid primary key default gen_random_uuid(),
  persona_id  uuid not null references public.personas (id),
  funcion     text not null,
  creada_en   timestamptz not null default now(),
  usada_en    timestamptz
);
revoke all on motor.solicitudes_servidor from public, anon, authenticated;
alter table motor.solicitudes_servidor enable row level security;  -- sin políticas: solo las funciones internas

-- Contexto para una llamada del servidor ------------------------------------------
create or replace function public.servidor_preparar(p_persona uuid, p_ahora timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_rol text;
  v_jornada uuid;
  v_fecha date := motor.fecha_local(p_ahora);
  v_turno text;
  v_stock uuid;
begin
  select rol into v_rol from public.personas where id = p_persona and activo;
  if v_rol is null then
    return motor.error('NO_AUTORIZADO', 'No tienes permiso para esto.');
  end if;
  if v_rol = 'operario' then
    v_jornada := motor.generar_jornada(p_persona, v_fecha);
    if v_jornada is null then
      return motor.error('SIN_JORNADA', 'Hoy no tienes jornada.');
    end if;
  end if;

  select h.turno into v_turno from public.horarios h
   where h.persona_id = p_persona and h.dia_semana = extract(isodow from v_fecha)
     and motor.en_local(v_fecha, h.hora_inicio) <= p_ahora
   order by h.hora_inicio desc limit 1;
  v_turno := coalesce(v_turno, 'manana');

  select t.id into v_stock from public.tareas t
   where t.jornada_id = v_jornada and t.clave = 'cola_stock'
     and exists (select 1 from public.tarea_elementos e where e.tarea_id = t.id and e.lote = v_turno);

  return jsonb_build_object(
    'persona_id', p_persona, 'rol', v_rol, 'jornada_id', v_jornada,
    'fecha', v_fecha, 'dia', extract(day from v_fecha)::int, 'mes', extract(month from v_fecha)::int,
    'turno', v_turno,
    'destinos', (select jsonb_agg(jsonb_build_object('id', c.id, 'codigo', c.codigo, 'nombre', c.nombre,
                                                     'tipo', c.tipo, 'alias', to_jsonb(c.alias)) order by c.codigo)
                 from public.centros_trabajo c where c.tipo <> 'almacen'),
    'config', (select jsonb_object_agg(k.clave, k.valor) from public.configuracion k
               where k.centro_id is null and k.clave in ('sheets_documento_id', 'sheets_pestanas',
                                                         'stock_objetivo_pct', 'stock_excluidos')),
    'repartos', jsonb_build_object(
      'reparto', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                  from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'reparto' and r.estado = 'aceptado'),
      'envio', (select jsonb_build_object('id', r.id, 'huella', r.huella, 'resultado', r.resultado)
                from public.repartos r where r.jornada_id = v_jornada and r.tipo = 'envio' and r.estado = 'aceptado')),
    'stock', case when v_stock is null then null else motor.tarea_json(v_stock) end);
end;
$$;

-- Canjea una solicitud interna (un solo uso, 5 minutos) -----------------------------
create or replace function public.servidor_canjear_solicitud(p_id uuid, p_funcion text)
returns uuid
language sql security definer
set search_path = ''
as $$
  update motor.solicitudes_servidor set usada_en = now()
   where id = p_id and funcion = p_funcion and usada_en is null and creada_en > now() - interval '5 minutes'
  returning persona_id;
$$;

create or replace function public.servidor_guardar_lectura(
  p_persona uuid, p_motivo text, p_correcto boolean, p_error text, p_datos jsonb)
returns uuid
language sql security definer
set search_path = ''
as $$
  insert into public.lecturas_sheets (persona_id, motivo, correcto, error, datos)
  values (p_persona, p_motivo, p_correcto, p_error, coalesce(p_datos, '{}'::jsonb))
  returning id;
$$;

-- Cierra o reabre una tarea con lista según sus elementos --------------------------
create or replace function motor.ajustar_estado_lista(p_persona uuid, p_tarea uuid, p_sin_nada text, p_ahora timestamptz)
returns void
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_hay boolean;
  v_pendientes boolean;
begin
  select * into t from public.tareas where id = p_tarea;
  select exists (select 1 from public.tarea_elementos where tarea_id = p_tarea),
         exists (select 1 from public.tarea_elementos where tarea_id = p_tarea and estado <> 'hecho')
    into v_hay, v_pendientes;
  if not v_pendientes and t.estado in ('pendiente', 'en_curso') then
    update public.tareas set estado = 'hecha', terminada_en = p_ahora,
           resultado = case when v_hay then 'Todo hecho' else p_sin_nada end
     where id = p_tarea;
    perform motor.registrar('tarea_terminada', p_persona, t.jornada_id, p_tarea,
                            jsonb_build_object('a_las', p_ahora, 'por', 'nada pendiente en la lista'));
  elsif v_pendientes and t.estado = 'hecha' then
    update public.tareas set estado = 'pendiente', terminada_en = null, resultado = null where id = p_tarea;
    perform motor.registrar('tarea_reabierta', p_persona, t.jornada_id, p_tarea, jsonb_build_object('a_las', p_ahora));
  end if;
end;
$$;

-- Guarda un reparto o envío ya calculado por el servidor (R1) ------------------------
-- Con errores: lo guarda como «con_errores» (para el registro) y no crea nada.
-- Aceptado: crea o actualiza las tareas y sus elementos. Si ya había uno
-- aceptado hoy, lo sustituye conservando lo hecho (§5 R1).
create or replace function public.servidor_guardar_reparto(
  p_persona uuid, p_jornada uuid, p_tipo text, p_texto text, p_huella text, p_fecha_texto date,
  p_sale text, p_lectura uuid, p_lineas jsonb, p_produccion jsonb, p_bolsas jsonb, p_aceptado boolean,
  p_ahora timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  r0 public.repartos;
  v_id uuid;
  v_cond text := case when p_tipo = 'reparto' then 'reparto_pegado' else 'envio_pegado' end;
  v_prod uuid;
  v_bolsas uuid;
  v_destino uuid;
  v_antes jsonb;
  v_despues jsonb;
  v_bolsas_resultado jsonb := '[]';
  v_min_caja integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                  where clave = 'duracion_min_por_caja' and centro_id is null), 1);
  v_min_bolsa integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                   where clave = 'duracion_min_por_bolsa' and centro_id is null), 3);
  v_dur_prod integer;
  v_dur_bolsas integer;
  v_resultado jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('reparto:' || p_jornada || ':' || p_tipo, 0));

  if not p_aceptado then
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado, lectura_id, pegado_por)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'con_errores', p_lectura, p_persona)
    returning id into v_id;
  else
    select * into r0 from public.repartos where jornada_id = p_jornada and tipo = p_tipo and estado = 'aceptado';
    if r0.huella = p_huella then
      return r0.resultado || jsonb_build_object('ya_pegado', true);
    end if;
    if r0.id is not null then
      update public.repartos set estado = 'sustituido' where id = r0.id;
    end if;
    insert into public.repartos (jornada_id, tipo, texto_original, huella, fecha_en_texto, sale, estado,
                                 sustituye_a, lectura_id, pegado_por)
    values (p_jornada, p_tipo, p_texto, p_huella, p_fecha_texto, p_sale, 'aceptado', r0.id, p_lectura, p_persona)
    returning id into v_id;
  end if;

  insert into public.reparto_lineas (reparto_id, num_linea, texto, clase, destino_id, cantidad, producto, formato, error, mensaje)
  select v_id, (l ->> 'num')::int, l ->> 'texto', l ->> 'clase', (l ->> 'destino_id')::uuid, (l ->> 'cantidad')::int,
         l ->> 'producto', l ->> 'formato', l ->> 'error', l ->> 'mensaje'
  from jsonb_array_elements(coalesce(p_lineas, '[]')) l;

  if not p_aceptado then
    perform motor.registrar('reparto_con_errores', p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo));
    return jsonb_build_object('reparto_id', v_id, 'estado', 'con_errores');
  end if;

  -- Tareas del reparto o del envío
  if p_tipo = 'reparto' then
    perform motor.fijar_sale(p_jornada, p_sale);
  else
    perform motor.fijar_envio(p_jornada, true, null);
  end if;
  perform motor.crear_tarea_condicionada(p_jornada, v_cond);
  if p_tipo = 'reparto' then
    select id into v_prod from public.tareas where jornada_id = p_jornada and clave = 'produccion_reparto';
    select id into v_bolsas from public.tareas where jornada_id = p_jornada and clave = 'bolsas';
  else
    select id into v_prod from public.tareas where jornada_id = p_jornada
       and clave in ('preparar_envio', 'preparar_envio_viernes') order by clave limit 1;
    v_bolsas := v_prod;
  end if;
  if v_prod is null or v_bolsas is null then
    raise exception 'No hay tarea para el % de hoy', p_tipo;
  end if;
  update public.tareas set reparto_id = v_id where id in (v_prod, v_bolsas);

  -- Producción: lo que falta. Se conservan las cajas ya hechas.
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, cantidad, motivo, orden_sugerido, calculo)
  select v_prod, 'referencia_produccion', p_tipo, x ->> 'producto', coalesce(x ->> 'formato', ''),
         (x ->> 'faltan')::int, x ->> 'aviso', coalesce((x ->> 'orden')::int, 0), x || jsonb_build_object('lectura_id', p_lectura)
  from jsonb_array_elements(coalesce(p_produccion, '[]')) x
  where (x ->> 'faltan')::int > 0
  on conflict (tarea_id, tipo, lote, destino_id, producto, formato) do update
     set cantidad = excluded.cantidad, motivo = excluded.motivo, orden_sugerido = excluded.orden_sugerido,
         calculo = excluded.calculo,
         estado = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad then 'hecho'
                       when public.tarea_elementos.estado = 'hecho' then 'pendiente'
                       else public.tarea_elementos.estado end,
         terminado_en = case when public.tarea_elementos.cantidad_hecha >= excluded.cantidad
                             then coalesce(public.tarea_elementos.terminado_en, p_ahora) end;

  -- Referencias que ya no hacen falta: sin nada hecho se quitan; con algo hecho se cierran.
  delete from public.tarea_elementos e
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha = 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);
  update public.tarea_elementos e
     set cantidad = e.cantidad_hecha, estado = 'hecho', terminado_en = coalesce(e.terminado_en, p_ahora),
         motivo = 'Ya no hace falta con el reparto corregido'
   where e.tarea_id = v_prod and e.tipo = 'referencia_produccion' and e.lote = p_tipo and e.cantidad_hecha > 0
     and not exists (select 1 from jsonb_array_elements(coalesce(p_produccion, '[]')) x
                     where (x ->> 'faltan')::int > 0 and x ->> 'producto' = e.producto
                       and coalesce(x ->> 'formato', '') = e.formato);

  -- Bolsas: las tiendas sin cambios se conservan; las que cambian se vuelven a
  -- comprobar caja a caja; las que ya no están se quitan.
  for v_destino in
    select distinct d from (
      select e.destino_id as d from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo
      union
      select (b ->> 'destino_id')::uuid from jsonb_array_elements(coalesce(p_bolsas, '[]')) b) s
  loop
    select jsonb_agg(jsonb_build_array(e.producto, e.formato, e.cantidad) order by e.producto, e.formato)
      into v_antes from public.tarea_elementos e
     where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
    select jsonb_agg(jsonb_build_array(i ->> 'producto', coalesce(i ->> 'formato', ''), (i ->> 'cantidad')::int)
                     order by i ->> 'producto', coalesce(i ->> 'formato', ''))
      into v_despues
      from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
     where (b ->> 'destino_id')::uuid = v_destino;

    if v_antes is distinct from v_despues then
      delete from public.tarea_elementos e
       where e.tarea_id = v_bolsas and e.tipo = 'caja_bolsa' and e.lote = p_tipo and e.destino_id = v_destino;
      insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, destino_id, cantidad, orden_sugerido)
      select v_bolsas, 'caja_bolsa', p_tipo, i ->> 'producto', coalesce(i ->> 'formato', ''), v_destino,
             (i ->> 'cantidad')::int, coalesce((i ->> 'orden')::int, 0)
        from jsonb_array_elements(coalesce(p_bolsas, '[]')) b, jsonb_array_elements(b -> 'items') i
       where (b ->> 'destino_id')::uuid = v_destino;
    end if;
    if v_despues is not null then
      v_bolsas_resultado := v_bolsas_resultado || jsonb_build_object(
        'destino_id', v_destino,
        'destino', (select nombre from public.centros_trabajo where id = v_destino),
        'cajas', (select sum((x ->> 2)::int) from jsonb_array_elements(v_despues) x),
        'cambia', r0.id is not null and v_antes is distinct from v_despues);
    end if;
  end loop;

  -- Duraciones de referencia (§6.10): 1 min por caja que falta, 3 min por tienda.
  select coalesce(sum((x ->> 'faltan')::int), 0) * v_min_caja into v_dur_prod
    from jsonb_array_elements(coalesce(p_produccion, '[]')) x where (x ->> 'faltan')::int > 0;
  v_dur_bolsas := jsonb_array_length(v_bolsas_resultado) * v_min_bolsa;
  if v_prod = v_bolsas then
    update public.tareas set duracion_min = nullif(v_dur_prod + v_dur_bolsas, 0) where id = v_prod;
  else
    update public.tareas set duracion_min = nullif(v_dur_prod, 0) where id = v_prod;
    update public.tareas set duracion_min = nullif(v_dur_bolsas, 0) where id = v_bolsas;
  end if;

  perform motor.ajustar_estado_lista(p_persona, v_prod, 'No falta producir nada: todo está hecho en el almacén', p_ahora);
  if v_bolsas <> v_prod then
    perform motor.ajustar_estado_lista(p_persona, v_bolsas, 'Sin bolsas', p_ahora);
  end if;

  v_resultado := jsonb_build_object(
    'reparto_id', v_id, 'estado', 'aceptado', 'tipo', p_tipo, 'sale', p_sale, 'sustituye_a', r0.id,
    'produccion', coalesce(p_produccion, '[]'), 'bolsas', v_bolsas_resultado,
    'tareas', jsonb_build_object('produccion', v_prod, 'bolsas', v_bolsas),
    'datos_leidos_en', (select leido_en from public.lecturas_sheets where id = p_lectura));
  update public.repartos set resultado = v_resultado where id = v_id;
  perform motor.registrar(case when r0.id is null then 'reparto_aceptado' else 'reparto_sustituido' end,
                          p_persona, p_jornada, null, jsonb_build_object('reparto', v_id, 'tipo', p_tipo, 'anterior', r0.id));
  return v_resultado || jsonb_build_object('tarea_activa', motor.tarea_activa_de(p_persona, p_ahora));
end;
$$;

-- Guarda la lista de stock calculada por el servidor (R3), una vez por turno ------------
create or replace function public.servidor_guardar_stock(
  p_persona uuid, p_jornada uuid, p_lote text, p_lectura uuid, p_lista jsonb, p_faltas jsonb,
  p_ahora timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_tarea uuid;
  v_falta text;
  v_id uuid;
  v_min_caja integer := coalesce((select (valor #>> '{}')::int from public.configuracion
                                  where clave = 'duracion_min_por_caja' and centro_id is null), 1);
begin
  perform pg_advisory_xact_lock(hashtextextended('stock:' || p_jornada, 0));
  select id into v_tarea from public.tareas where jornada_id = p_jornada and clave = 'cola_stock';
  if v_tarea is null then
    return motor.error('SIN_TAREA', 'Hoy no hay tarea de stock.');
  end if;
  if exists (select 1 from public.tarea_elementos where tarea_id = v_tarea and lote = p_lote) then
    return jsonb_build_object('tarea', motor.tarea_json(v_tarea), 'ya_calculado', true);
  end if;

  -- Lo no hecho del turno anterior no se arrastra: se recalcula (§6.5).
  delete from public.tarea_elementos where tarea_id = v_tarea and lote <> p_lote and estado <> 'hecho';
  insert into public.tarea_elementos (tarea_id, tipo, lote, producto, formato, categoria, cantidad, motivo,
                                      orden_sugerido, calculo)
  select v_tarea, 'referencia_produccion', p_lote, x ->> 'producto', coalesce(x ->> 'formato', ''), x ->> 'categoria',
         (x ->> 'cajas')::int, x ->> 'motivo', n::int, x || jsonb_build_object('lectura_id', p_lectura)
  from jsonb_array_elements(coalesce(p_lista, '[]')) with ordinality as l(x, n);

  -- «Sin granel no se produce»: la tarea «Avisa a Administración: falta X».
  for v_falta in select jsonb_array_elements_text(coalesce(p_faltas, '[]')) loop
    v_id := null;
    insert into public.tareas (jornada_id, clave, origen, titulo, obligatoria, disponible_desde, duracion_min, no_terminada, orden)
    values (p_jornada, 'avisa_falta:' || upper(regexp_replace(v_falta, '\s', '', 'g')), 'evento',
            'Avisa a Administración: falta ' || v_falta, true, p_ahora, 2, 'nada', 60)
    on conflict (jornada_id, clave) do nothing
    returning id into v_id;
    if v_id is not null then
      perform motor.registrar('tarea_creada', null, p_jornada, v_id, jsonb_build_object('por', 'sin granel', 'falta', v_falta));
    end if;
  end loop;

  update public.tareas
     set duracion_min = nullif((select coalesce(sum((x ->> 'cajas')::int), 0) * v_min_caja
                                from jsonb_array_elements(coalesce(p_lista, '[]')) x), 0)
   where id = v_tarea;
  perform motor.ajustar_estado_lista(p_persona, v_tarea, 'Stock al día: no hace falta producir', p_ahora);
  perform motor.registrar('stock_calculado', p_persona, p_jornada, v_tarea,
                          jsonb_build_object('lote', p_lote, 'lectura', p_lectura, 'referencias', jsonb_array_length(coalesce(p_lista, '[]'))));
  return jsonb_build_object('tarea', motor.tarea_json(v_tarea), 'ya_calculado', false);
end;
$$;

revoke execute on function
  public.servidor_preparar(uuid, timestamptz), public.servidor_canjear_solicitud(uuid, text),
  public.servidor_guardar_lectura(uuid, text, boolean, text, jsonb),
  public.servidor_guardar_reparto(uuid, uuid, text, text, text, date, text, uuid, jsonb, jsonb, jsonb, boolean, timestamptz),
  public.servidor_guardar_stock(uuid, uuid, text, uuid, jsonb, jsonb, timestamptz)
from public, anon, authenticated;
grant execute on function
  public.servidor_preparar(uuid, timestamptz), public.servidor_canjear_solicitud(uuid, text),
  public.servidor_guardar_lectura(uuid, text, boolean, text, jsonb),
  public.servidor_guardar_reparto(uuid, uuid, text, text, text, date, text, uuid, jsonb, jsonb, jsonb, boolean, timestamptz),
  public.servidor_guardar_stock(uuid, uuid, text, uuid, jsonb, jsonb, timestamptz)
to service_role;
revoke execute on all functions in schema motor from public;
grant execute on function
  motor.es_admin(), motor.mi_centro(),
  motor.api_mi_perfil(), motor.api_tarea_activa(), motor.api_iniciar_tarea(uuid),
  motor.api_terminar_tarea(uuid, text, text), motor.api_anotar_motivo(uuid, text),
  motor.api_iniciar_elemento(uuid), motor.api_terminar_elemento(uuid), motor.api_marcar_cajas(uuid, integer)
to authenticated;

-- Solo entorno de pruebas: invocar una función del servidor desde la base de datos -------
-- Crea una solicitud de un solo uso para esa persona y llama a la función por
-- HTTP (pg_net). La respuesta queda en net._http_response con el id devuelto.
create or replace function prueba.invocar(p_funcion text, p_persona uuid, p_cuerpo jsonb default '{}')
returns bigint
language plpgsql
set search_path = ''
as $$
declare
  v_solicitud uuid;
  v_url text := (select valor #>> '{}' from public.configuracion where clave = 'url_proyecto' and centro_id is null);
begin
  if coalesce((select valor #>> '{}' from public.configuracion
               where clave = 'entorno' and centro_id is null), '') <> 'pruebas' then
    raise exception 'prueba.invocar solo se puede usar en el entorno de pruebas';
  end if;
  insert into motor.solicitudes_servidor (persona_id, funcion) values (p_persona, p_funcion) returning id into v_solicitud;
  return net.http_post(
    url := v_url || '/functions/v1/' || p_funcion,
    body := coalesce(p_cuerpo, '{}'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-solicitud', v_solicitud::text),
    timeout_milliseconds := 30000);
end;
$$;
revoke execute on all functions in schema prueba from public;
