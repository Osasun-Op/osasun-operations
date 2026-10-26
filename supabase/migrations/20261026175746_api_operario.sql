-- Tarea 2 · Funciones para las pantallas (CONTRATOS.md v0.2)
-- mi_perfil, tarea_activa, iniciar_tarea, terminar_tarea y anotar_motivo.
-- Capa motor.api_*: comprueba quién llama y su rol (SECURITY DEFINER).
-- Capa public.*: lo que publica la API; solo llama a motor.api_* y no tiene
-- privilegios propios. La hora la pone siempre el servidor.

-- Quién llama -----------------------------------------------------------------
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
  if v_rol is null or (p_rol_exigido is not null and v_rol <> p_rol_exigido) then
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
  v_error jsonb := motor.persona_actual(null);
begin
  if v_error is not null then return v_error; end if;
  return motor.mi_perfil_de(auth.uid());
end;
$$;

create or replace function motor.api_tarea_activa()
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.tarea_activa_de(auth.uid(), now());
end;
$$;

create or replace function motor.api_iniciar_tarea(p_tarea_id uuid)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.iniciar_tarea_de(auth.uid(), p_tarea_id, now());
end;
$$;

create or replace function motor.api_terminar_tarea(p_tarea_id uuid, p_resultado text, p_motivo text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.terminar_tarea_de(auth.uid(), p_tarea_id, p_resultado, p_motivo, now());
end;
$$;

create or replace function motor.api_anotar_motivo(p_tarea_id uuid, p_motivo text)
returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_error jsonb := motor.persona_actual('operario');
begin
  if v_error is not null then return v_error; end if;
  return motor.anotar_motivo_de(auth.uid(), p_tarea_id, p_motivo);
end;
$$;

revoke execute on all functions in schema motor from public;
grant execute on function
  motor.es_admin(), motor.mi_centro(),
  motor.api_mi_perfil(), motor.api_tarea_activa(), motor.api_iniciar_tarea(uuid),
  motor.api_terminar_tarea(uuid, text, text), motor.api_anotar_motivo(uuid, text)
to authenticated;

-- Lo que publica la API -------------------------------------------------------
create or replace function public.mi_perfil()
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_mi_perfil() $$;

create or replace function public.tarea_activa()
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_tarea_activa() $$;

create or replace function public.iniciar_tarea(tarea_id uuid)
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_iniciar_tarea(tarea_id) $$;

create or replace function public.terminar_tarea(tarea_id uuid, resultado text default null, motivo text default null)
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_terminar_tarea(tarea_id, resultado, motivo) $$;

create or replace function public.anotar_motivo(tarea_id uuid, motivo text)
returns jsonb
language sql
set search_path = ''
as $$ select motor.api_anotar_motivo(tarea_id, motivo) $$;

revoke execute on function
  public.mi_perfil(), public.tarea_activa(), public.iniciar_tarea(uuid),
  public.terminar_tarea(uuid, text, text), public.anotar_motivo(uuid, text)
from public, anon;
grant execute on function
  public.mi_perfil(), public.tarea_activa(), public.iniciar_tarea(uuid),
  public.terminar_tarea(uuid, text, text), public.anotar_motivo(uuid, text)
to authenticated;

-- Solo entorno de pruebas -----------------------------------------------------
-- Fija una condición del día que todavía no tiene función propia (SALE:, envío,
-- reparto/envío pegado, eventos) para simular la semana. No la usan las
-- pantallas: no se concede a ningún usuario y además exige
-- configuracion.entorno = "pruebas".
create or replace function prueba.fijar_condicion(p_jornada uuid, p_condicion text, p_valor text default null)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if coalesce((select valor #>> '{}' from public.configuracion
               where clave = 'entorno' and centro_id is null), '') <> 'pruebas' then
    raise exception 'prueba.fijar_condicion solo se puede usar en el entorno de pruebas';
  end if;

  case p_condicion
    when 'sale' then
      perform motor.fijar_sale(p_jornada, p_valor);
    when 'hay_envio' then
      perform motor.fijar_envio(p_jornada, p_valor::boolean, null);
    when 'envio_dia_siguiente' then
      perform motor.fijar_envio(p_jornada, null, p_valor::boolean);
    when 'reparto_pegado', 'envio_pegado', 'llega_mercancia', 'pedido_cliente', 'no_quedan_vapers' then
      perform motor.crear_tarea_condicionada(p_jornada, p_condicion, p_valor);
    else
      raise exception 'Condición desconocida: %', p_condicion;
  end case;
end;
$$;

revoke execute on all functions in schema prueba from public;
