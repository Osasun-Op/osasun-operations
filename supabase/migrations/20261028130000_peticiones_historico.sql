-- Tarea 13 · Peticiones especiales (R1d) e histórico por día (ESTADO v1.26, §5 R1d y §8).
-- 1. Peticiones: texto libre por tienda en el reparto y en el envío. Se guardan
--    con el reparto (repartos.peticiones) y van a la bolsa de su tienda como
--    elementos `peticion` (cantidad 1, se marcan con marcar_cajas). No van a
--    producción ni cuentan como stock. En el texto para WhatsApp, «Además: …».
-- 2. Histórico: historico_dia(fecha) y historico_dias(desde, hasta), solo
--    Administración y solo consulta.

-- ---------------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------------
alter table public.repartos
  add column peticiones jsonb not null default '[]' check (jsonb_typeof(peticiones) = 'array');

alter table public.reparto_lineas drop constraint reparto_lineas_clase_check;
alter table public.reparto_lineas add constraint reparto_lineas_clase_check
  check (clase in ('cabecera', 'sale', 'tienda', 'producto', 'peticion', 'vacia', 'no_reconocida'));

alter table public.tarea_elementos drop constraint tarea_elementos_tipo_check;
alter table public.tarea_elementos add constraint tarea_elementos_tipo_check
  check (tipo in ('referencia_produccion', 'caja_bolsa', 'peticion'));

-- ---------------------------------------------------------------------------
-- Peticiones en las bolsas
-- ---------------------------------------------------------------------------
-- Peticiones con el nombre de la tienda: [{ destino_id, destino, texto }].
create or replace function motor.peticiones_json(p_peticiones jsonb)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('destino_id', c.id, 'destino', c.nombre, 'texto', x ->> 'texto') order by n), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p_peticiones, '[]')) with ordinality a(x, n)
    join public.centros_trabajo c on c.id = (x ->> 'destino_id')::uuid;
$$;

-- Guarda las peticiones del reparto (o envío) aceptado y las pone en la bolsa de
-- su tienda. Lo ya marcado se conserva; lo que ya no está se quita. Repetirlo no
-- cambia nada.
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

-- Elementos de la tarea: las peticiones van en la bolsa de su tienda, después
-- de sus cajas («Además, mete:»), con su texto en `texto`.
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
    'elementos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', e.id, 'tipo', e.tipo, 'producto', e.producto, 'formato', e.formato,
               'texto', case when e.tipo = 'peticion' then e.producto end,
               'categoria', e.categoria, 'destino', c.nombre, 'destino_id', e.destino_id,
               'bolsa', case when e.tipo = 'referencia_produccion' then null
                             when e.lote like 'pedido:%' then 'Pedido de cliente · ' || pc.cliente
                             when e.lote = 'envio' then 'Envío'
                             else 'Bolsa de reposición' end,
               'cantidad', e.cantidad, 'cantidad_hecha', e.cantidad_hecha, 'motivo', e.motivo,
               'orden_sugerido', e.orden_sugerido, 'estado', e.estado)
             order by e.tipo = 'referencia_produccion' desc, c.nombre nulls first, e.lote like 'pedido:%',
                      e.tipo = 'peticion', e.lote, e.orden_sugerido, e.producto, e.formato)
      from public.tarea_elementos e
      left join public.centros_trabajo c on c.id = e.destino_id
      left join public.pedidos_cliente pc on e.lote like 'pedido:%' and pc.id::text = substr(e.lote, 8)
      where e.tarea_id = t.id), '[]'::jsonb))
  from public.tareas t where t.id = p_tarea;
$$;

-- marcar_cajas: también las peticiones (0 o 1). La tienda está completa cuando
-- tiene todas sus cajas y todas sus peticiones.
create or replace function motor.marcar_cajas_de(p_persona uuid, p_elemento uuid, p_cantidad_hecha integer, p_ahora timestamptz)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  e public.tarea_elementos;
  v_error jsonb;
  v_estado text;
  v_tienda_completa boolean;
begin
  v_error := motor.comprobar_elemento(p_persona, p_elemento, p_ahora);
  if v_error is not null then
    if exists (select 1 from public.tarea_elementos
               where id = p_elemento and cantidad_hecha = p_cantidad_hecha) then
      return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);  -- repetición
    end if;
    return v_error;
  end if;
  select * into e from public.tarea_elementos where id = p_elemento;
  if e.tipo not in ('caja_bolsa', 'peticion') then
    return motor.error('DATOS_NO_VALIDOS', 'Las cajas se marcan en las bolsas.');
  end if;
  if p_cantidad_hecha is null or p_cantidad_hecha < 0 or p_cantidad_hecha > e.cantidad then
    return motor.error('CANTIDAD_FUERA_DE_RANGO', 'La cantidad debe estar entre 0 y ' || e.cantidad || '.');
  end if;
  if e.cantidad_hecha = p_cantidad_hecha then
    return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);  -- repetición: nada cambia
  end if;

  v_error := motor.asegurar_en_curso(p_persona, e.tarea_id, p_ahora);
  if v_error is not null then return v_error; end if;

  v_estado := case when p_cantidad_hecha = e.cantidad then 'hecho'
                   when p_cantidad_hecha > 0 then 'en_curso' else 'pendiente' end;
  update public.tarea_elementos
     set cantidad_hecha = p_cantidad_hecha, estado = v_estado,
         iniciado_en = coalesce(iniciado_en, p_ahora),
         terminado_en = case when v_estado = 'hecho' then p_ahora end
   where id = p_elemento;
  perform motor.registrar('cajas_marcadas', p_persona, null, e.tarea_id,
                          jsonb_build_object('elemento', p_elemento, 'cajas', p_cantidad_hecha));

  if v_estado = 'hecho' then
    -- Punto de encaje: solo cuando la tienda (o el destino) está completa.
    select not exists (select 1 from public.tarea_elementos
                        where tarea_id = e.tarea_id and tipo in ('caja_bolsa', 'peticion')
                          and destino_id is not distinct from e.destino_id and estado <> 'hecho')
      into v_tienda_completa;
    perform motor.tras_elemento(p_persona, e.tarea_id, v_tienda_completa, p_ahora);
  end if;
  return motor.respuesta_elemento(p_persona, p_elemento, p_ahora);
end;
$$;

-- ---------------------------------------------------------------------------
-- Detalle de un reparto (reparto_de_hoy_detalle e histórico)
-- ---------------------------------------------------------------------------
create or replace function motor.reparto_detalle_json(p_reparto uuid, p_sale text)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'reparto_id', r.id, 'tipo', r.tipo, 'sale', p_sale,
    'aceptado_en', r.pegado_en, 'pegado_por', r.pegado_por,
    'pegado_por_nombre', (select nombre from public.personas where id = r.pegado_por),
    'texto_whatsapp', case when p_sale is null then r.texto_original
                           else regexp_replace(r.texto_original, '^(REPARTO [^\n]*\n)SALE: [^\n]*',
                                               '\1SALE: ' || case p_sale when 'operario' then 'ALMACÉN' else 'YO' end) end,
    'lineas', coalesce((
      select jsonb_agg(jsonb_build_object('destino_id', x.destino_id, 'destino', c.nombre, 'producto', x.producto,
                                          'formato', x.formato, 'cantidad', x.cantidad) order by x.primera)
        from (select l.destino_id, l.producto, coalesce(l.formato, '') as formato, sum(l.cantidad)::int as cantidad,
                     min(l.num_linea) as primera
                from public.reparto_lineas l
               where l.reparto_id = r.id and l.clase = 'producto' and l.error is null
               group by 1, 2, 3) x
        join public.centros_trabajo c on c.id = x.destino_id), '[]'::jsonb),
    'peticiones', motor.peticiones_json(r.peticiones))
  from public.repartos r where r.id = p_reparto;
$$;

create or replace function motor.reparto_de_hoy_detalle_de(p_persona uuid, p_tipo text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_jornada uuid;
  v_reparto uuid;
begin
  if p_tipo is null or p_tipo not in ('reparto', 'envio') then
    return motor.error('DATOS_NO_VALIDOS', 'El tipo es «reparto» o «envio».');
  end if;
  v_jornada := motor.generar_jornada(case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end,
                                     motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no hay jornada en el almacén.');
  end if;
  select id into v_reparto from public.repartos where jornada_id = v_jornada and tipo = p_tipo and estado = 'aceptado';
  if v_reparto is null then
    return jsonb_build_object('reparto', null);
  end if;
  -- Quién sale hoy (puede haber cambiado sin tocar el reparto): manda la jornada.
  return jsonb_build_object('reparto', motor.reparto_detalle_json(v_reparto,
    case when p_tipo = 'reparto' then (select sale from public.jornadas where id = v_jornada) end));
end;
$$;

-- ---------------------------------------------------------------------------
-- Histórico (§8): todo lo de un día del operario por defecto. Solo consulta.
-- ---------------------------------------------------------------------------
create or replace function motor.historico_dia_de(p_fecha date)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  j public.jornadas;
begin
  select * into j from public.jornadas where persona_id = motor.operario_por_defecto() and fecha = p_fecha;
  return jsonb_build_object(
    'fecha', p_fecha,
    'jornada', case when j.id is not null then jsonb_build_object('id', j.id, 'sale', j.sale, 'hay_envio', j.hay_envio,
                                                                  'estado', j.estado) end,
    'reparto', (select motor.reparto_detalle_json(r.id, j.sale) from public.repartos r
                 where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
    'envio', (select motor.reparto_detalle_json(r.id, null) from public.repartos r
               where r.jornada_id = j.id and r.tipo = 'envio' and r.estado = 'aceptado'),
    'pedidos_cliente', coalesce((
      select jsonb_agg(x.o order by x.registrado_en)
        from (select motor.pedido_json(p.id) as o, p.registrado_en from public.pedidos_cliente p) x
       where (x.o ->> 'fecha')::date = p_fecha), '[]'::jsonb),
    'cierres', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'fecha', c.contenido ->> 'fecha', 'turno', c.turno,
                                          'generado_en', c.generado_en, 'enviado_en', c.enviado_en, 'canal', c.canal,
                                          'contenido', c.contenido, 'texto', motor.texto_cierre(c.contenido) ->> 'texto')
                       order by c.turno = 'tarde', c.generado_en)
        from public.cierres c where c.jornada_id = j.id), '[]'::jsonb),
    'tareas', jsonb_build_object(
      'hechas', coalesce((
        select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'resultado', t.resultado, 'hora', t.terminada_en)
                         order by t.terminada_en, t.orden)
          from public.tareas t where t.jornada_id = j.id and t.estado = 'hecha'), '[]'::jsonb),
      'no_hechas', coalesce((
        select jsonb_agg(jsonb_build_object('titulo', t.titulo, 'estado', t.estado, 'motivo', t.motivo_no_hecha,
                                            'pasa_al_dia_siguiente', t.estado = 'arrastrada')
                         order by t.orden, t.creada_en)
          from public.tareas t where t.jornada_id = j.id and t.estado <> 'hecha'), '[]'::jsonb)));
end;
$$;

-- Días con algo que ver (para marcar el calendario). Como mucho un año.
create or replace function motor.historico_dias_de(p_desde date, p_hasta date)
returns jsonb language plpgsql stable set search_path = '' as $$
begin
  if p_desde is null or p_hasta is null or p_desde > p_hasta or p_hasta - p_desde > 366 then
    return motor.error('DATOS_NO_VALIDOS', 'Elige un periodo de un año como máximo.');
  end if;
  return jsonb_build_object('dias', coalesce((
    select jsonb_agg(d.o order by d.fecha) from (
      select j.fecha,
             jsonb_build_object(
               'fecha', j.fecha,
               'reparto', exists (select 1 from public.repartos r where r.jornada_id = j.id and r.tipo = 'reparto' and r.estado = 'aceptado'),
               'envio', exists (select 1 from public.repartos r where r.jornada_id = j.id and r.tipo = 'envio' and r.estado = 'aceptado'),
               'pedidos_cliente', (select count(*) from public.pedidos_cliente p
                                    left join public.tareas t on t.id = p.tarea_id
                                   where coalesce(t.jornada_id, p.jornada_id) = j.id
                                      or (p.tarea_id is null and p.jornada_id is null and p.fecha_objetivo = j.fecha)),
               'cierres', (select count(*) from public.cierres c where c.jornada_id = j.id),
               'tareas_hechas', (select count(*) from public.tareas t where t.jornada_id = j.id and t.estado = 'hecha')) as o
        from public.jornadas j
       where j.persona_id = motor.operario_por_defecto() and j.fecha between p_desde and p_hasta) d
   where (d.o ->> 'reparto')::boolean or (d.o ->> 'envio')::boolean or (d.o ->> 'pedidos_cliente')::int > 0
      or (d.o ->> 'cierres')::int > 0 or (d.o ->> 'tareas_hechas')::int > 0), '[]'::jsonb));
end;
$$;

create or replace function motor.api_historico_dia(p_fecha date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  if p_fecha is null then
    return motor.error('DATOS_NO_VALIDOS', 'Elige un día.');
  end if;
  return motor.historico_dia_de(p_fecha);
end; $$;

create or replace function motor.api_historico_dias(p_desde date, p_hasta date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('administracion');
begin
  if v_error is not null then return v_error; end if;
  return motor.historico_dias_de(p_desde, p_hasta);
end; $$;

create or replace function public.historico_dia(fecha date)
returns jsonb language sql set search_path = '' as $$ select motor.api_historico_dia(fecha) $$;
create or replace function public.historico_dias(desde date, hasta date)
returns jsonb language sql set search_path = '' as $$ select motor.api_historico_dias(desde, hasta) $$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema motor from public;
grant execute on function motor.api_historico_dia(date), motor.api_historico_dias(date, date) to authenticated;
revoke execute on function public.historico_dia(date), public.historico_dias(date, date) from public, anon;
grant execute on function public.historico_dia(date), public.historico_dias(date, date) to authenticated;
revoke execute on function public.servidor_guardar_peticiones(uuid, uuid, jsonb, timestamptz) from public, anon, authenticated;
grant execute on function public.servidor_guardar_peticiones(uuid, uuid, jsonb, timestamptz) to service_role;
