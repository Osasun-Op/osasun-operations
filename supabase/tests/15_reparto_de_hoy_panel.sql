-- Prueba 15 · El panel sabe si hoy ya hay reparto (Tarea 9)
-- estado_actual devuelve `reparto_de_hoy`, el mismo objeto que tarea_activa:
-- null sin reparto («Pegar reparto»); con el reparto aceptado, cuál, cuándo y
-- quién lo pegó («Modificar reparto»); al corregirlo, el nuevo.
-- Miércoles 18/11/2026. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.guardar(p_jornada uuid, p_persona uuid, p_huella text, p_ahora timestamptz) returns jsonb language sql as $$
  select public.servidor_guardar_reparto(p_persona, p_jornada, 'reparto', 'BILBAO\n1x V2 4g', p_huella, '2026-11-18',
           'administracion', null, '[]',
           '[{"producto": "V2", "formato": "4g", "pedido": 1, "en_almacen": 1, "faltan": 0, "orden": 1}]',
           jsonb_build_array(jsonb_build_object('destino_id', (select id from public.centros_trabajo where codigo = 'BILBAO'),
             'items', '[{"producto": "V2", "formato": "4g", "cantidad": 1}]'::jsonb)),
           true, p_ahora) $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  r jsonb;
  v_rep uuid;
begin
  j := motor.generar_jornada(op, '2026-11-18');
  r := motor.estado_actual_de('2026-11-18 08:40+01');
  perform pg_temp.comprobar('Sin reparto: estado_actual trae reparto_de_hoy = null (el panel muestra «Pegar reparto»)',
    r ? 'reparto_de_hoy' and r -> 'reparto_de_hoy' = 'null'::jsonb, r -> 'reparto_de_hoy' #>> '{}');

  v_rep := (pg_temp.guardar(j, adm, 'h15-1', '2026-11-18 08:45+01') ->> 'reparto_id')::uuid;
  r := motor.estado_actual_de('2026-11-18 08:50+01');
  perform pg_temp.comprobar('Con el reparto pegado: cuál, cuándo y quién lo pegó (el panel muestra «Modificar reparto»)',
    (r -> 'reparto_de_hoy' ->> 'reparto_id')::uuid = v_rep
    and (r -> 'reparto_de_hoy' ->> 'aceptado_en')::timestamptz = '2026-11-18 08:45+01'
    and (r -> 'reparto_de_hoy' ->> 'pegado_por')::uuid = adm
    and r -> 'reparto_de_hoy' ->> 'pegado_por_nombre' = (select nombre from public.personas where id = adm),
    r -> 'reparto_de_hoy' #>> '{}');
  perform pg_temp.comprobar('Es el mismo objeto que devuelve tarea_activa al operario',
    r -> 'reparto_de_hoy' = motor.tarea_activa_de(op, '2026-11-18 08:50+01') -> 'reparto_de_hoy');

  v_rep := (pg_temp.guardar(j, op, 'h15-2', '2026-11-18 09:10+01') ->> 'reparto_id')::uuid;
  r := motor.estado_actual_de('2026-11-18 09:15+01');
  perform pg_temp.comprobar('Corregido por el operario: el panel ve el reparto nuevo',
    (r -> 'reparto_de_hoy' ->> 'reparto_id')::uuid = v_rep and (r -> 'reparto_de_hoy' ->> 'pegado_por')::uuid = op,
    r -> 'reparto_de_hoy' #>> '{}');
  r := motor.estado_actual_de('2026-11-19 08:40+01');
  perform pg_temp.comprobar('Al día siguiente vuelve a ser null (es el reparto de hoy)',
    r -> 'reparto_de_hoy' = 'null'::jsonb, r -> 'reparto_de_hoy' #>> '{}');
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
