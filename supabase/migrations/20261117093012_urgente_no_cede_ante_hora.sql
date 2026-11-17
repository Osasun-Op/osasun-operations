-- T-0013 · Tarea 41 · Una urgente no cede ante una tarea con hora (ESTADO_DEL_SISTEMA.md §6.4; decisión del propietario,
-- 17/11/2026). Solo en pruebas: producción espera.
-- El 17/11, «Recoger txabako donde souto» (de Administración, urgente, sin productos, no obligatoria) estaba en curso cuando
-- venció «Revisa stock en Gipuzkoa/Durango y ver si hay que enviar o no» (con hora). motor.pausar_si_toca la pausaba al
-- pedir la tarea activa (lo que entraba tenía escalón 4) y motor.elegir_tarea volvía a elegir la urgente (escalón 3):
-- 9 inicios y 8 pausas entre las 15:39 y las 15:58, hasta que se salió con «Estoy bloqueado» a las 16:06.
--   1. La tarea en curso solo se pausa si lo que entra va delante de ella en el orden de siempre: si su escalón es menor
--      que el que tendría la tarea en curso estando pendiente. Con el mismo escalón, no se pausa.
--   2. Las demás condiciones de la Tarea 37 se quedan igual (no obligatoria y sin referencia empezada, al pedir la tarea
--      activa; lo que entra, de escalón 2 a 4).
--   3. Una sola regla para los dos que la usan (motor.tras_elemento y motor.tarea_activa_de): solo cambia
--      motor.pausar_si_toca. Nada más del motor cambia.
--
-- Deshacer: volver a crear motor.pausar_si_toca como está en 20261106103012.

-- La regla del punto de encaje: si la tarea está en curso y ya toca algo de escalón 2–4 que va delante de ella (Tarea 41),
-- se pausa (vuelve a pendiente con lo hecho) y queda la interrupción con lo que entra. Devuelve si la ha pausado.
create or replace function motor.pausar_si_toca(p_persona uuid, p_tarea uuid, p_ahora timestamptz)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  t public.tareas;
  v_pendiente public.tareas;
  v_otra uuid;
  v_escalon integer;
begin
  select * into t from public.tareas where id = p_tarea;
  if t.estado is distinct from 'en_curso' then
    return false;
  end if;
  v_otra := motor.elegir_tarea(t.jornada_id, p_ahora, p_tarea);
  if v_otra is null then
    return false;
  end if;
  select motor.escalon(o) into v_escalon from public.tareas o where o.id = v_otra;
  -- Tarea 41: solo si lo que entra va delante en el orden de siempre (el escalón que tendría la tarea en curso estando
  -- pendiente). Así una urgente en curso no cede ante una con hora (si no, elegir_tarea la vuelve a elegir: el bucle
  -- del 17/11); sí ante un problema.
  v_pendiente := t;
  v_pendiente.estado := 'pendiente';
  if v_escalon not in (2, 3, 4) or v_escalon >= motor.escalon(v_pendiente) then
    return false;
  end if;
  update public.tareas set estado = 'pendiente' where id = p_tarea;
  perform motor.registrar('tarea_pausada', p_persona, t.jornada_id, p_tarea,
                          jsonb_build_object('a_las', p_ahora, 'entra', v_otra));
  return true;
end;
$$;

revoke execute on all functions in schema motor from public;
