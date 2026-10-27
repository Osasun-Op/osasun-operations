-- Tarea 8 · «¿Quién sale?» (ESTADO_DEL_SISTEMA.md v1.20, §5 R1).
-- 1. Al pegar el reparto, el desplegable manda sobre la línea SALE: (lo decide la
--    función del servidor, R1); si el texto decía otra cosa, la función del
--    servidor lo anota en el registro (`servidor_anotar_sale`).
-- 2. cambiar_quien_sale(sale): cambiar quién sale sin volver a pegar el reparto,
--    para el operario y para Administración, sobre la jornada de hoy del
--    operario (el operario por defecto, si llama Administración).
-- 3. mi_perfil devuelve los nombres para el desplegable.

-- ---------------------------------------------------------------------------
-- Cambiar quién sale
-- ---------------------------------------------------------------------------
create or replace function motor.cambiar_quien_sale_de(p_persona uuid, p_sale text, p_ahora timestamptz)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_rol text := (select rol from public.personas where id = p_persona and activo);
  v_operario uuid;
  v_jornada uuid;
  v_antes text;
begin
  if p_sale is null or p_sale not in ('operario', 'administracion') then
    return motor.error('DATOS_NO_VALIDOS', 'Elige quién sale.');
  end if;
  v_operario := case when v_rol = 'operario' then p_persona else motor.operario_por_defecto() end;
  v_jornada := motor.generar_jornada(v_operario, motor.fecha_local(p_ahora));
  if v_jornada is null then
    return motor.error('SIN_JORNADA', 'Hoy no hay jornada en el almacén.');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('sale:' || v_jornada, 0));
  select sale into v_antes from public.jornadas where id = v_jornada;
  if v_antes is distinct from p_sale
     and exists (select 1 from public.tareas where jornada_id = v_jornada and clave = 'salida_reparto'
                 and estado in ('en_curso', 'hecha')) then
    return motor.error('ESTADO_NO_VALIDO', 'La salida del reparto ya ha empezado: ya no se puede cambiar quién sale.');
  end if;

  if v_antes is distinct from p_sale then
    perform motor.fijar_sale(v_jornada, p_sale);
    perform motor.registrar('quien_sale_cambiado', p_persona, v_jornada, null,
                            jsonb_build_object('antes', v_antes, 'sale', p_sale, 'a_las', p_ahora));
  end if;
  return jsonb_build_object(
    'sale', p_sale, 'antes', v_antes, 'cambiado', v_antes is distinct from p_sale,
    'tareas', coalesce((select jsonb_agg(jsonb_build_object('clave', t.clave, 'titulo', t.titulo, 'estado', t.estado)
                                         order by t.orden)
                          from public.tareas t
                         where t.jornada_id = v_jornada and t.clave in ('salida_reparto', 'efectivo_reporte')), '[]'::jsonb),
    'tarea_activa', case when v_rol = 'operario' then motor.tarea_activa_de(p_persona, p_ahora) end);
end;
$$;

create or replace function motor.api_cambiar_quien_sale(p_sale text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.cambiar_quien_sale_de(auth.uid(), p_sale, now());
end; $$;

create or replace function public.cambiar_quien_sale(sale text)
returns jsonb language sql set search_path = '' as $$ select motor.api_cambiar_quien_sale(sale) $$;

-- ---------------------------------------------------------------------------
-- mi_perfil: nombres para el desplegable «¿Quién sale?»
-- ---------------------------------------------------------------------------
create or replace function motor.mi_perfil_de(p_persona uuid)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'nombre', p.nombre, 'rol', p.rol,
    'centro', case when c.id is null then null else jsonb_build_object('id', c.id, 'nombre', c.nombre) end,
    'telefono_administracion', coalesce(
      (select valor #>> '{}' from public.configuracion where clave = 'telefono_administracion' and centro_id is null),
      (select a.telefono from public.personas a
        where a.rol = 'administracion' and a.activo and a.telefono is not null
        order by a.nombre limit 1)),
    'quien_sale_opciones', jsonb_build_array(
      jsonb_build_object('valor', 'administracion',
                         'nombre', coalesce((select a.nombre from public.personas a
                                              where a.rol = 'administracion' and a.activo
                                              order by a.nombre, a.id limit 1), 'Administración')),
      jsonb_build_object('valor', 'operario',
                         'nombre', coalesce((select o.nombre from public.personas o where o.id = motor.operario_por_defecto()),
                                            'Operario'))))
  from public.personas p
  left join public.centros_trabajo c on c.id = p.centro_id
  where p.id = p_persona;
$$;

-- ---------------------------------------------------------------------------
-- Al pegar el reparto: si el desplegable y la línea SALE: no coinciden, se anota
-- (solo la función del servidor, después de guardar el reparto aceptado).
-- ---------------------------------------------------------------------------
create or replace function public.servidor_anotar_sale(p_persona uuid, p_reparto uuid, p_sale_texto text, p_sale_elegido text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  r public.repartos;
begin
  select * into r from public.repartos where id = p_reparto;
  if r.id is null or p_sale_texto is null or p_sale_texto = p_sale_elegido then
    return;
  end if;
  perform motor.registrar('sale_distinto_del_texto', p_persona, r.jornada_id, null,
                          jsonb_build_object('reparto', r.id, 'sale_texto', p_sale_texto, 'sale_elegido', p_sale_elegido));
end;
$$;

revoke execute on function public.servidor_anotar_sale(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.servidor_anotar_sale(uuid, uuid, text, text) to service_role;
revoke execute on all functions in schema motor from public;
grant execute on function motor.api_cambiar_quien_sale(text) to authenticated;
revoke execute on function public.cambiar_quien_sale(text) from public, anon;
grant execute on function public.cambiar_quien_sale(text) to authenticated;
