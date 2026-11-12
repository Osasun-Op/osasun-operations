-- T-0011 · Tarea 39 · Reposición y envíos: lo que llega de más (ESTADO_DEL_SISTEMA.md E2-8; decisión del propietario,
-- 12/11/2026). Solo en pruebas: espera con las de tiendas.
--   1. apuntar_reposicion (CONTRATOS §9.12) y confirmar_envio (§9.21) aceptan además, sin quitar nada de lo de ahora:
--      - llegado: [{ clave, cantidad }]: por cada línea de productos de la bolsa (o del envío), lo que ha llegado de verdad
--        (0 o más). El servidor lo compara con lo que traía: menos, falta la diferencia; más, sobra la diferencia; igual,
--        nada. Las líneas que no vienen en `llegado`, como siempre (lo que traía).
--      - de_mas: [{ producto, formato, cantidad }]: lo que ha llegado y no está en la lista, comprobado contra
--        productos_tienda() (la misma lista de los atascados).
--      - faltan, igual que hasta ahora (peticiones, pedidos de cliente y quien lo use así).
--   2. Si falta o sobra algo, la incidencia de siempre para Administración (falta_reposicion o falta_envio), con el texto
--      «Falta: … · Sobra: …» (con de dónde venía cada caja, Tarea 38). Si no falta ni sobra nada, «todo bien».
--      Lo que sobra queda guardado en bolsas_tienda.sobran (columna nueva) y sale en bolsa.reposicion.sobran.
--   3. Un solo código para los dos: motor.faltan_de_lista (ahora con llegado y de_mas, y devuelve { faltan, sobran }),
--      motor.faltan_texto y motor.diferencias_texto (nueva: «Falta: … · Sobra: …»).
-- No cambia: «todo bien», el trabajo del operario, las cuentas del almacén, la hoja, las pantallas.
--
-- Deshacer: borrar motor.diferencias_texto; borrar las funciones con la firma nueva (motor.faltan_de_lista(jsonb, jsonb,
-- jsonb, jsonb), motor.apuntar_reposicion_de(uuid, uuid, jsonb, text, timestamptz, jsonb, jsonb),
-- motor.confirmar_envio_de(uuid, uuid, jsonb, text, timestamptz, jsonb, jsonb), motor.api_apuntar_reposicion(uuid, jsonb,
-- text, jsonb, jsonb), motor.api_confirmar_envio(uuid, jsonb, text, jsonb, jsonb), public.apuntar_reposicion(uuid, jsonb,
-- text, jsonb, jsonb) y public.confirmar_envio(uuid, jsonb, text, jsonb, jsonb)) y volver a crearlas como están en
-- 20261111093012 (faltan_de_lista, faltan_texto), 20261103211530 (apuntar_reposicion_de, confirmar_envio_de,
-- api_confirmar_envio, public.confirmar_envio) y 20261103091220 (api_apuntar_reposicion, public.apuntar_reposicion), con
-- sus permisos; motor.bolsa_tienda_json como en 20261104223012; y quitar la columna bolsas_tienda.sobran.

-- ---------------------------------------------------------------------------
-- 1. Lo que sobra, guardado como lo que falta
-- ---------------------------------------------------------------------------
alter table public.bolsas_tienda add column sobran jsonb;
comment on column public.bolsas_tienda.sobran is
  'Tarea 39: lo que ha llegado de más al apuntar la reposición o confirmar el envío ([{ clave, texto, cantidad, traia?, fuera_de_lista? }]).';

-- ---------------------------------------------------------------------------
-- 2. La comprobación, una sola para la reposición y los envíos
-- ---------------------------------------------------------------------------
drop function motor.faltan_de_lista(jsonb, jsonb);

-- Devuelve { faltan, sobran } o el error para enseñar tal cual.
create or replace function motor.faltan_de_lista(p_contenido jsonb, p_faltan jsonb, p_llegado jsonb default null,
                                                 p_de_mas jsonb default null)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v_items jsonb;
  v_faltan jsonb := '[]';
  v_sobran jsonb := '[]';
  v_vistas text[] := '{}';
  v_lista jsonb;
  x jsonb;
  it jsonb;
  p jsonb;
  v_cant integer;
  v_formato text;
  v_texto text;
  v_clave text;
begin
  select coalesce(jsonb_agg(y), '[]') into v_items from (
    select jsonb_build_object('clave', c ->> 'clave', 'texto', trim((c ->> 'producto') || ' ' || (c ->> 'formato')),
                              'maximo', (c ->> 'cantidad')::int, 'producto', true)
           -- Tarea 38: si trae cajas de otra tienda, de dónde venía cada una («traía 3: 2 del almacén y 1 de Algorta»).
           || case when c ? 'de' then jsonb_build_object('traia', motor.texto_de((c ->> 'cantidad')::int, c -> 'de'))
                   else '{}'::jsonb end as y
      from jsonb_array_elements(p_contenido -> 'productos') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', c ->> 'texto', 'maximo', 1, 'producto', false)
      from jsonb_array_elements(p_contenido -> 'peticiones') c
    union all
    select jsonb_build_object('clave', c ->> 'clave', 'texto', 'Pedido de ' || (c ->> 'cliente'), 'maximo', 1, 'producto', false)
      from jsonb_array_elements(p_contenido -> 'pedidos') c) s;
  if p_faltan is not null and jsonb_typeof(p_faltan) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.');
  end if;
  if p_llegado is not null and jsonb_typeof(p_llegado) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Pon lo que ha llegado de cada caja de la lista.');
  end if;
  if p_de_mas is not null and jsonb_typeof(p_de_mas) <> 'array' then
    return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista de productos lo que ha llegado y no estaba.');
  end if;

  -- Lo que falta, elegido de la lista (como hasta ahora).
  for x in select * from jsonb_array_elements(coalesce(p_faltan, '[]')) loop
    select i into it from jsonb_array_elements(v_items) i where i ->> 'clave' = x ->> 'clave';
    if it is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista lo que falta.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    if (x ->> 'clave') = any (v_vistas) then
      return motor.error('DATOS_NO_VALIDOS', 'Cada cosa, una sola vez.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_vistas := v_vistas || (x ->> 'clave');
    v_cant := case when x ? 'cantidad' and jsonb_typeof(x -> 'cantidad') = 'number' then (x ->> 'cantidad')::numeric::int
                   when x ? 'cantidad' then -1 else (it ->> 'maximo')::int end;
    if v_cant < 1 or v_cant > (it ->> 'maximo')::int or (x ? 'cantidad' and (x ->> 'cantidad')::numeric <> v_cant) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas faltan de ' || (it ->> 'texto') || ': de 1 a ' || (it ->> 'maximo') || '.',
                         jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_faltan := v_faltan || (jsonb_build_object('clave', it ->> 'clave', 'texto', it ->> 'texto', 'cantidad', v_cant)
                             || case when it ? 'traia' then jsonb_build_object('traia', it -> 'traia') else '{}'::jsonb end);
  end loop;

  -- Tarea 39: lo que ha llegado de verdad de cada caja de la lista; el servidor saca si falta o sobra.
  for x in select * from jsonb_array_elements(coalesce(p_llegado, '[]')) loop
    select i into it from jsonb_array_elements(v_items) i where i ->> 'clave' = x ->> 'clave' and (i ->> 'producto')::boolean;
    if it is null then
      return motor.error('DATOS_NO_VALIDOS', 'Pon lo que ha llegado de cada caja de la lista.',
                         jsonb_build_object('clave', x ->> 'clave'));
    end if;
    if (x ->> 'clave') = any (v_vistas) then
      return motor.error('DATOS_NO_VALIDOS', 'Cada cosa, una sola vez.', jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_vistas := v_vistas || (x ->> 'clave');
    if jsonb_typeof(x -> 'cantidad') is distinct from 'number'
       or (x ->> 'cantidad')::numeric not between 0 and 9999
       or (x ->> 'cantidad')::numeric <> trunc((x ->> 'cantidad')::numeric) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas han llegado de ' || (it ->> 'texto') || ': un número entero, 0 o más.',
                         jsonb_build_object('clave', x ->> 'clave'));
    end if;
    v_cant := (x ->> 'cantidad')::numeric::int - (it ->> 'maximo')::int;
    if v_cant < 0 then
      v_faltan := v_faltan || (jsonb_build_object('clave', it ->> 'clave', 'texto', it ->> 'texto', 'cantidad', -v_cant)
                               || case when it ? 'traia' then jsonb_build_object('traia', it -> 'traia') else '{}'::jsonb end);
    elsif v_cant > 0 then
      v_sobran := v_sobran || (jsonb_build_object('clave', it ->> 'clave', 'texto', it ->> 'texto', 'cantidad', v_cant)
                               || case when it ? 'traia' then jsonb_build_object('traia', it -> 'traia') else '{}'::jsonb end);
    end if;
  end loop;

  -- Tarea 39: lo que ha llegado y no está en la lista, de la lista de productos (la de los atascados).
  if jsonb_array_length(coalesce(p_de_mas, '[]')) > 0 then
    v_lista := coalesce(motor.productos_tienda_de() -> 'productos', '[]'::jsonb);
  end if;
  for x in select * from jsonb_array_elements(coalesce(p_de_mas, '[]')) loop
    v_formato := coalesce(x ->> 'formato', '');
    select l into p from jsonb_array_elements(v_lista) l
     where l ->> 'producto' = x ->> 'producto' and l -> 'formatos' ? v_formato;
    if p is null then
      return motor.error('DATOS_NO_VALIDOS', 'Elige de la lista: «' || btrim(coalesce(x ->> 'producto', '') || ' ' || v_formato)
                                             || '» no está.',
                         jsonb_build_object('producto', x ->> 'producto', 'formato', x ->> 'formato'));
    end if;
    v_texto := btrim((p ->> 'producto') || ' ' || v_formato);
    v_clave := 'producto:' || (p ->> 'producto') || '|' || v_formato;
    if exists (select 1 from jsonb_array_elements(v_items) i where i ->> 'clave' = v_clave) then
      return motor.error('DATOS_NO_VALIDOS', v_texto || ' ya está en la lista: pon ahí lo que ha llegado.',
                         jsonb_build_object('producto', p ->> 'producto', 'formato', v_formato));
    end if;
    if ('de_mas:' || v_clave) = any (v_vistas) then
      return motor.error('DATOS_NO_VALIDOS', 'Cada producto, una sola vez.',
                         jsonb_build_object('producto', p ->> 'producto', 'formato', v_formato));
    end if;
    v_vistas := v_vistas || ('de_mas:' || v_clave);
    if x ? 'cantidad' and (jsonb_typeof(x -> 'cantidad') is distinct from 'number'
                           or (x ->> 'cantidad')::numeric not between 1 and 99
                           or (x ->> 'cantidad')::numeric <> trunc((x ->> 'cantidad')::numeric)) then
      return motor.error('DATOS_NO_VALIDOS', 'Cuántas cajas de ' || v_texto || ': de 1 a 99.',
                         jsonb_build_object('producto', p ->> 'producto', 'formato', v_formato));
    end if;
    v_sobran := v_sobran || jsonb_build_object('clave', 'de_mas:' || (p ->> 'producto') || '|' || v_formato, 'texto', v_texto,
                                               'cantidad', coalesce((x ->> 'cantidad')::numeric::int, 1),
                                               'fuera_de_lista', true);
  end loop;
  return jsonb_build_object('faltan', v_faltan, 'sobran', v_sobran);
end;
$$;

create or replace function motor.faltan_texto(p_faltan jsonb)
returns text language sql immutable set search_path = '' as $$
  select string_agg(case when (f ->> 'cantidad')::int > 1 or (f ->> 'clave') like 'producto:%'
                              or (f ->> 'clave') like 'de_mas:%'
                         then (f ->> 'cantidad') || 'x ' else '' end || (f ->> 'texto')
                    || coalesce(' (' || (f ->> 'traia') || ')', '')
                    -- Tarea 39: lo que ha llegado y no estaba en la lista.
                    || case when (f ->> 'fuera_de_lista')::boolean then ' (no estaba en la lista)' else '' end, '; ')
    from jsonb_array_elements(p_faltan) f
$$;

-- «Falta: … · Sobra: …», solo con lo que haya.
create or replace function motor.diferencias_texto(p_faltan jsonb, p_sobran jsonb)
returns text language sql immutable set search_path = '' as $$
  select nullif(concat_ws(' · ', 'Falta: ' || motor.faltan_texto(coalesce(p_faltan, '[]')),
                                 'Sobra: ' || motor.faltan_texto(coalesce(p_sobran, '[]'))), '')
$$;

-- ---------------------------------------------------------------------------
-- 3. «Coloca y apunta la reposición»
-- ---------------------------------------------------------------------------
drop function motor.apuntar_reposicion_de(uuid, uuid, jsonb, text, timestamptz);

create or replace function motor.apuntar_reposicion_de(p_persona uuid, p_tarea uuid, p_faltan jsonb, p_nota text,
                                                       p_ahora timestamptz, p_llegado jsonb default null,
                                                       p_de_mas jsonb default null)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_error jsonb := motor.tarea_tienda_marcable(p_persona, p_tarea, 'reposicion', p_ahora);
  t public.tareas;
  j public.jornadas;
  b public.bolsas_tienda;
  tt public.turnos_tienda;
  v_contenido jsonb;
  v_dif jsonb;
  v_faltan jsonb;
  v_sobran jsonb;
  v_hay boolean;
  v_nota text := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '');
  v_incidencia uuid;
begin
  if v_error is not null then
    return v_error;
  end if;
  select * into t from public.tareas where id = p_tarea;
  select * into j from public.jornadas where id = t.jornada_id;
  select * into b from public.bolsas_tienda where centro_id = j.centro_id and fecha = j.fecha;
  tt := motor.en_turno_tienda(j.id);
  v_contenido := motor.bolsa_contenido(b.reparto_id, b.centro_id);
  -- Lo que falta o sobra, con la lista (Tarea 30b: la misma comprobación que en «Envíos»; Tarea 39: también lo de más).
  v_dif := motor.faltan_de_lista(v_contenido, p_faltan, p_llegado, p_de_mas);
  if v_dif ? 'error' then
    return v_dif;
  end if;
  v_faltan := v_dif -> 'faltan';
  v_sobran := v_dif -> 'sobran';
  v_hay := jsonb_array_length(v_faltan) + jsonb_array_length(v_sobran) > 0;
  if v_nota is not null and length(v_nota) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
  end if;

  if not v_hay then
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Reposición metida, todo bien', null, 'tarea_terminada', p_ahora);
  else
    insert into public.incidencias (jornada_id, persona_id, tarea_id, descripcion, iniciada_en, id_cliente, opcion, quien,
                                    estado, creada_por)
    values (j.id, p_persona, t.id,
            'Bolsa del reparto del ' || to_char(j.fecha, 'DD/MM') || '. ' || motor.diferencias_texto(v_faltan, v_sobran)
              || coalesce('. ' || v_nota, '') || coalesce(' (' || tt.nombre || ')', ''),
            p_ahora, md5('falta_reposicion:' || b.id)::uuid, 'falta_reposicion', 'administracion', 'abierta', p_persona)
    on conflict (id_cliente) do nothing
    returning id into v_incidencia;
    perform motor.cerrar_tarea_tienda(p_persona, t.id, 'hecha', 'Falta o sobra algo', null, 'tarea_terminada', p_ahora);
    perform motor.registrar('falta_reposicion', p_persona, j.id, t.id,
                            jsonb_build_object('incidencia', v_incidencia, 'faltan', v_faltan, 'sobran', v_sobran,
                                               'nota', v_nota, 'a_las', p_ahora));
  end if;
  update public.bolsas_tienda
     set reposicion = case when v_hay then 'falta' else 'bien' end,
         reposicion_en = p_ahora, reposicion_por = tt.nombre, faltan = v_faltan, sobran = v_sobran,
         incidencia_id = v_incidencia
   where id = b.id;
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

drop function motor.api_apuntar_reposicion(uuid, jsonb, text);
create or replace function motor.api_apuntar_reposicion(p_tarea_id uuid, p_faltan jsonb, p_nota text, p_llegado jsonb,
                                                        p_de_mas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.apuntar_reposicion_de(auth.uid(), p_tarea_id, p_faltan, p_nota, now(), p_llegado, p_de_mas);
end; $$;

drop function public.apuntar_reposicion(uuid, jsonb, text);
create or replace function public.apuntar_reposicion(tarea_id uuid, faltan jsonb default null, nota text default null,
                                                     llegado jsonb default null, de_mas jsonb default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_apuntar_reposicion(tarea_id, faltan, nota, llegado, de_mas) $$;

-- ---------------------------------------------------------------------------
-- 4. «Envíos»
-- ---------------------------------------------------------------------------
drop function motor.confirmar_envio_de(uuid, uuid, jsonb, text, timestamptz);

create or replace function motor.confirmar_envio_de(p_persona uuid, p_envio uuid, p_faltan jsonb, p_nota text,
                                                    p_ahora timestamptz, p_llegado jsonb default null,
                                                    p_de_mas jsonb default null)
returns jsonb language plpgsql set search_path = '' as $$
declare
  pe public.personas;
  b public.bolsas_tienda;
  v_jornada uuid;
  tt public.turnos_tienda;
  v_dif jsonb;
  v_faltan jsonb;
  v_sobran jsonb;
  v_hay boolean;
  v_nota text := nullif(btrim(regexp_replace(coalesce(p_nota, ''), '\s+', ' ', 'g')), '');
  v_incidencia uuid;
begin
  select * into pe from public.personas where id = p_persona;
  select bt.* into b from public.bolsas_tienda bt join public.repartos r on r.id = bt.reparto_id and r.tipo = 'envio'
   where bt.id = p_envio and bt.centro_id = pe.centro_id for update of bt;
  if b.id is null then
    return motor.error('NO_ENCONTRADO', 'Ese envío no existe.');
  end if;
  if b.reposicion is not null then
    return motor.error('ESTADO_NO_VALIDO', 'Ese envío ya está confirmado.', jsonb_build_object('resultado', b.reposicion));
  end if;
  v_jornada := motor.generar_jornada(p_persona, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy la tienda no abre.');
  end if;
  tt := motor.en_turno_tienda(v_jornada);
  if tt.id is null then
    return motor.error('SIN_PERSONA', 'Elige primero quién está en la tienda.');
  end if;
  v_dif := motor.faltan_de_lista(motor.bolsa_contenido(b.reparto_id, motor.destino_envio(b.centro_id)), p_faltan,
                                 p_llegado, p_de_mas);
  if v_dif ? 'error' then
    return v_dif;
  end if;
  v_faltan := v_dif -> 'faltan';
  v_sobran := v_dif -> 'sobran';
  v_hay := jsonb_array_length(v_faltan) + jsonb_array_length(v_sobran) > 0;
  if v_nota is not null and length(v_nota) > 200 then
    return motor.error('DATOS_NO_VALIDOS', 'La nota, en una línea (200 letras como máximo).');
  end if;

  if v_hay then
    insert into public.incidencias (jornada_id, persona_id, descripcion, iniciada_en, id_cliente, opcion, quien, estado, creada_por)
    values (v_jornada, p_persona,
            'Envío del ' || to_char(b.fecha, 'DD/MM') || '. ' || motor.diferencias_texto(v_faltan, v_sobran)
              || coalesce('. ' || v_nota, '') || ' (' || tt.nombre || ')',
            p_ahora, md5('falta_envio:' || b.id)::uuid, 'falta_envio', 'administracion', 'abierta', p_persona)
    on conflict (id_cliente) do nothing
    returning id into v_incidencia;
  end if;
  update public.bolsas_tienda
     set reposicion = case when v_hay then 'falta' else 'bien' end,
         reposicion_en = p_ahora, reposicion_por = tt.nombre, faltan = v_faltan, sobran = v_sobran,
         incidencia_id = v_incidencia
   where id = b.id;
  perform motor.registrar('envio_confirmado', p_persona, v_jornada, null,
                          jsonb_build_object('envio', b.id, 'reparto', b.reparto_id, 'faltan', v_faltan, 'sobran', v_sobran,
                                             'nota', v_nota, 'incidencia', v_incidencia, 'por', tt.nombre, 'a_las', p_ahora));
  return motor.tienda_hoy_de(p_persona, p_ahora);
end;
$$;

drop function motor.api_confirmar_envio(uuid, jsonb, text);
create or replace function motor.api_confirmar_envio(p_envio_id uuid, p_faltan jsonb, p_nota text, p_llegado jsonb,
                                                     p_de_mas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual('tienda');
begin
  if v_error is not null then return v_error; end if;
  return motor.confirmar_envio_de(auth.uid(), p_envio_id, p_faltan, p_nota, now(), p_llegado, p_de_mas);
end; $$;

drop function public.confirmar_envio(uuid, jsonb, text);
create or replace function public.confirmar_envio(envio_id uuid, faltan jsonb default null, nota text default null,
                                                  llegado jsonb default null, de_mas jsonb default null)
returns jsonb language sql set search_path = '' as $$
  select motor.api_confirmar_envio(envio_id, faltan, nota, llegado, de_mas) $$;

-- ---------------------------------------------------------------------------
-- 5. Lo que ve la tienda después: bolsa.reposicion.sobran
-- ---------------------------------------------------------------------------
create or replace function motor.bolsa_tienda_json(p_centro uuid, p_fecha date)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'reparto_id', b.reparto_id, 'fecha', b.fecha, 'salida', motor.hora_texto(b.salida_en),
    'recibida_a_las', motor.hora_texto(b.recibida_en), 'recibida_por', b.recibida_por,
    'efectivo', jsonb_build_object('esperado', b.efectivo_esperado, 'de_fecha', b.efectivo_de,
                                   'entregado', b.efectivo_entregado, 'motivo', b.efectivo_motivo,
                                   -- Tarea 34: los días de los cierres que lleva (esperado = su suma).
                                   'dias', coalesce(to_jsonb(b.efectivo_dias), '[]'::jsonb)),
    'reposicion', case when b.reposicion is not null then
      jsonb_build_object('resultado', b.reposicion, 'a_las', motor.hora_texto(b.reposicion_en), 'por', b.reposicion_por,
                         'faltan', coalesce(b.faltan, '[]'::jsonb),
                         -- Tarea 39: lo que ha llegado de más.
                         'sobran', coalesce(b.sobran, '[]'::jsonb),
                         'incidencia_id', b.incidencia_id) end)
    || motor.bolsa_contenido(b.reparto_id, b.centro_id)
  from public.bolsas_tienda b where b.centro_id = p_centro and b.fecha = p_fecha
$$;

-- ---------------------------------------------------------------------------
-- 6. Permisos (como antes: la pantalla, solo con su cuenta)
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema motor from public;
grant execute on function motor.api_apuntar_reposicion(uuid, jsonb, text, jsonb, jsonb),
                          motor.api_confirmar_envio(uuid, jsonb, text, jsonb, jsonb) to authenticated;
revoke execute on function public.apuntar_reposicion(uuid, jsonb, text, jsonb, jsonb),
                           public.confirmar_envio(uuid, jsonb, text, jsonb, jsonb) from public, anon;
grant execute on function public.apuntar_reposicion(uuid, jsonb, text, jsonb, jsonb),
                          public.confirmar_envio(uuid, jsonb, text, jsonb, jsonb) to authenticated;
