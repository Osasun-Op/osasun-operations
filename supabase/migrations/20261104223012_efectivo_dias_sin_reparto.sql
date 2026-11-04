-- Tarea 34 · El efectivo de los días sin reparto (ESTADO_DEL_SISTEMA.md E2-8 v1.62, «Recibe la bolsa»). Solo en pruebas:
-- producción espera con las de tiendas. Las franquicias no tienen bolsa ni efectivo: no cambian.
--   1. La X de «Recibe la bolsa» es la suma del efectivo de los cierres de caja de la tienda que todavía no han ido en
--      ninguna bolsa entregada: los posteriores al último cierre ya entregado.
--      - Si el reparto pasa todos los días, es el cierre de ayer. El lunes, el viernes y el sábado (no hay reparto el
--        sábado; decisión del propietario, 04/11/2026: «lunes viernes más sábado siempre»).
--      - Si una bolsa se quedó con el efectivo sin entregar, sus cierres van en la siguiente.
--      - Si la tienda nunca ha entregado una bolsa, solo el último cierre (como hasta ahora).
--      - Con otra cantidad (entregar_efectivo y su motivo), esos cierres quedan entregados y la diferencia no pasa a la
--        siguiente bolsa.
--   2. bolsas_tienda.efectivo_dias guarda los días de los cierres que lleva cada bolsa (efectivo_de sigue siendo el
--      último). El texto: «Bolsa de ayer entregada con 85,50 € en efectivo» con uno; con varios, «Bolsa entregada con
--      180,00 € en efectivo (cierres del 03/11 y 04/11)».
--   3. bolsa.efectivo (tableta y resumen_tienda) trae `dias`.
-- motor.efectivo_anterior (solo el último cierre) se sustituye por motor.efectivo_pendiente.
--
-- Deshacer: volver a crear motor.efectivo_anterior, motor.preparar_bolsa_tienda, motor.bolsa_tienda_json y
-- motor.entregar_efectivo_de como están en 20261103091220; borrar motor.efectivo_pendiente y motor.texto_efectivo y la
-- columna bolsas_tienda.efectivo_dias.

-- ---------------------------------------------------------------------------
-- 1. Los días que lleva cada bolsa
-- ---------------------------------------------------------------------------
alter table public.bolsas_tienda add column efectivo_dias date[];
comment on column public.bolsas_tienda.efectivo_dias is 'Los días de los cierres de caja cuyo efectivo lleva la bolsa (Tarea 34).';
-- Las bolsas que ya había llevaban un solo cierre, el de efectivo_de.
update public.bolsas_tienda set efectivo_dias = array[efectivo_de] where efectivo_de is not null;

-- ---------------------------------------------------------------------------
-- 2. El efectivo que tiene que ir en la bolsa de ese día
-- ---------------------------------------------------------------------------
-- Los cierres de antes de ese día que no han ido en ninguna bolsa entregada: los posteriores al último cierre ya
-- entregado. Si nunca se ha entregado ninguno, solo el último cierre. Sin cierres pendientes, nada (la tienda dice
-- cuánto entrega, como cuando no hay cierre anterior).
create or replace function motor.efectivo_pendiente(p_centro uuid, p_fecha date)
returns table (efectivo numeric, dias date[]) language sql stable set search_path = '' as $$
  with entregado as (
    select max(d) as hasta
      from public.bolsas_tienda b cross join lateral unnest(b.efectivo_dias) d
     where b.centro_id = p_centro and b.efectivo_en is not null and b.fecha < p_fecha),
  pendientes as (
    select k.fecha, k.efectivo from public.cierres_caja k, entregado e
     where k.centro_id = p_centro and k.fecha < p_fecha and k.efectivo is not null
       and (e.hasta is null and k.fecha = (select max(x.fecha) from public.cierres_caja x
                                            where x.centro_id = p_centro and x.fecha < p_fecha and x.efectivo is not null)
            or k.fecha > e.hasta))
  select sum(p.efectivo), array_agg(p.fecha order by p.fecha) from pendientes p having count(*) > 0
$$;

-- El texto del punto: «Bolsa de ayer entregada con 85,50 € en efectivo» (un cierre) o «Bolsa entregada con 180,00 € en
-- efectivo (cierres del 03/11 y 04/11)» (varios).
create or replace function motor.texto_efectivo(p_efectivo numeric, p_dias date[])
returns text language sql immutable set search_path = '' as $$
  select case when coalesce(array_length(p_dias, 1), 0) <= 1
              then 'Bolsa de ayer entregada con ' || motor.euros(p_efectivo) || ' en efectivo'
              else 'Bolsa entregada con ' || motor.euros(p_efectivo) || ' en efectivo (cierres del '
                   || (select string_agg(to_char(d, 'DD/MM'), ', ' order by n) from unnest(p_dias[1:array_length(p_dias, 1) - 1])
                         with ordinality a(d, n))
                   || ' y ' || to_char(p_dias[array_length(p_dias, 1)], 'DD/MM') || ')' end
$$;

-- ---------------------------------------------------------------------------
-- 3. Funciones que se rehacen (solo cambia de dónde sale la X y lo que se guarda y se enseña)
-- ---------------------------------------------------------------------------
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
  v_dias date[];
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
  -- Tarea 34: el efectivo de los cierres que aún no han ido en ninguna bolsa entregada (el lunes, viernes y sábado).
  select a.efectivo, a.dias into v_x, v_dias from motor.efectivo_pendiente(j.centro_id, j.fecha) a;
  v_xf := v_dias[array_upper(v_dias, 1)];
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
                                     else jsonb_build_object('especial', 'efectivo', 'esperado', v_x, 'de_fecha', v_xf,
                                                             'dias', coalesce(to_jsonb(v_dias), '[]'::jsonb)) end,
         producto = case when e.orden_sugerido = 1 then e.producto
                         when v_x is null then 'Bolsa de ayer entregada: di cuánto efectivo'
                         else motor.texto_efectivo(v_x, v_dias) end
   where e.tarea_id = v_tarea and e.tipo = 'punto';
  insert into public.bolsas_tienda (centro_id, fecha, reparto_id, tarea_id, salida_en, efectivo_esperado, efectivo_de,
                                    efectivo_dias)
  values (j.centro_id, j.fecha, v_rep, v_tarea, v_salida, v_x, v_xf, v_dias);
  perform motor.registrar('bolsa_en_camino', p_persona, j.id, v_tarea,
                          jsonb_build_object('reparto', v_rep, 'salida', v_salida, 'efectivo_esperado', v_x,
                                             'efectivo_dias', v_dias));
end;
$$;

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
                         'faltan', coalesce(b.faltan, '[]'::jsonb), 'incidencia_id', b.incidencia_id) end)
    || motor.bolsa_contenido(b.reparto_id, b.centro_id)
  from public.bolsas_tienda b where b.centro_id = p_centro and b.fecha = p_fecha
$$;

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
    return motor.error('MOTIVO_OBLIGATORIO', 'Entregas otra cantidad que la '
                       || case when jsonb_array_length(coalesce(e.calculo -> 'dias', '[]')) > 1 then 'de los cierres'
                               else 'del cierre' end || ' (' || motor.euros(v_esperado)
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

drop function motor.efectivo_anterior(uuid, date);

revoke execute on all functions in schema motor from public;
