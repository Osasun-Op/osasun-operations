-- Prueba 08 · Permisos de las tablas y funciones de la Tarea 3
-- El operario ve sus repartos y elementos, no los de otra persona ni las
-- lecturas de la hoja; nadie escribe directamente; las funciones del servidor
-- solo las puede usar el servidor.

begin;
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;
grant all on _r to authenticated, anon;
grant usage on sequence _r_n_seq to authenticated, anon;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
create function pg_temp.rechazada(p_sql text)
returns boolean language plpgsql as $$
begin
  execute p_sql;
  return false;
exception when insufficient_privilege then
  return true;
end;
$$;
create function pg_temp.como(p_persona uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_persona, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;

-- Datos: el operario de pruebas y otro operario, cada uno con su reparto y su lectura.
insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-a000-000000000003', 'authenticated',
        'authenticated', 'otro.operario@osasun.invalid', '{}', '{}', now(), now());
insert into public.personas (id, nombre, rol, centro_id)
select '00000000-0000-4000-a000-000000000003', 'Otro operario', 'operario', id from public.centros_trabajo where codigo = 'ALMACEN';
insert into public.horarios (persona_id, dia_semana, turno, hora_inicio, hora_fin)
values ('00000000-0000-4000-a000-000000000003', 2, 'manana', '08:30', '13:00');

create temp table _ids on commit drop as
select p.persona,
       public.servidor_guardar_reparto(
         p.persona, motor.generar_jornada(p.persona, '2026-11-03'), 'reparto', 'BILBAO\n1x V2 4g', 'h-' || p.persona,
         null, 'administracion', public.servidor_guardar_lectura(p.persona, 'reparto', true, null, '{}'), '[]',
         '[{"producto": "V2", "formato": "4g", "pedido": 1, "en_almacen": 0, "faltan": 1, "orden": 1}]',
         jsonb_build_array(jsonb_build_object('destino_id', (select id from public.centros_trabajo where codigo = 'BILBAO'),
           'items', '[{"producto": "V2", "formato": "4g", "cantidad": 1}]'::jsonb)),
         true, '2026-11-03 09:00:00+01') as resultado
from (values ('00000000-0000-4000-a000-000000000001'::uuid), ('00000000-0000-4000-a000-000000000003'::uuid)) p(persona);
grant select on _ids to authenticated, anon;

-- OPERARIO ------------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb;
begin
  perform pg_temp.comprobar('Operario: ve su reparto y sus líneas, no los de otra persona',
    (select count(*) from public.repartos r join public.jornadas j on j.id = r.jornada_id
      where j.fecha = '2026-11-03') = 1
    and (select count(*) from public.repartos r join public.jornadas j on j.id = r.jornada_id
         where j.persona_id <> auth.uid()) = 0);
  perform pg_temp.comprobar('Operario: ve solo los elementos de sus tareas',
    (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
      join public.jornadas j on j.id = t.jornada_id where j.fecha = '2026-11-03') = 2
    and (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
      join public.jornadas j on j.id = t.jornada_id where j.persona_id <> auth.uid()) = 0);
  perform pg_temp.comprobar('Operario: no ve las lecturas de la hoja (son de Administración)',
    (select count(*) from public.lecturas_sheets) = 0);
  perform pg_temp.comprobar('Operario: no escribe directamente en repartos, líneas, elementos ni lecturas',
    pg_temp.rechazada($q$insert into public.repartos (jornada_id, tipo, texto_original, huella, estado)
                        select id, 'reparto', 'x', 'x', 'aceptado' from public.jornadas limit 1$q$)
    and pg_temp.rechazada($q$update public.tarea_elementos set cantidad_hecha = cantidad$q$)
    and pg_temp.rechazada($q$delete from public.reparto_lineas$q$)
    and pg_temp.rechazada($q$insert into public.lecturas_sheets (motivo, correcto) values ('stock', true)$q$));
  perform pg_temp.comprobar('Operario: no puede usar las funciones del servidor (guardar reparto o stock, preparar, canjear)',
    pg_temp.rechazada($q$select public.servidor_guardar_stock(auth.uid(), gen_random_uuid(), 'manana', null, '[]', '[]')$q$)
    and pg_temp.rechazada($q$select public.servidor_preparar(auth.uid())$q$)
    and pg_temp.rechazada($q$select public.servidor_canjear_solicitud(gen_random_uuid(), 'lista_stock')$q$)
    and pg_temp.rechazada($q$select public.servidor_guardar_lectura(auth.uid(), 'stock', true, null, '{}')$q$)
    and pg_temp.rechazada($q$select public.servidor_guardar_reparto(auth.uid(), gen_random_uuid(), 'reparto', 'x', 'x', null,
                                       null, null, '[]', '[]', '[]', true)$q$));
  perform pg_temp.comprobar('Operario: no puede usar las funciones internas de elementos ni la de pruebas',
    pg_temp.rechazada($q$select motor.marcar_cajas_de(auth.uid(), gen_random_uuid(), 1, now())$q$)
    and pg_temp.rechazada($q$select prueba.invocar('lista_stock', auth.uid())$q$));

  r := public.marcar_cajas(gen_random_uuid(), 1);
  perform pg_temp.comprobar('Operario: marcar_cajas de un elemento que no es suyo: NO_ENCONTRADO',
    r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
end;
$$;
reset role;

-- Elemento del otro operario, buscado sin restricciones, y probado como el operario de pruebas.
create temp table _otro on commit drop as
  select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
  join public.jornadas j on j.id = t.jornada_id where j.persona_id = '00000000-0000-4000-a000-000000000003' limit 1;
grant select on _otro to authenticated;
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.iniciar_elemento((select id from _otro));
  r2 jsonb := public.terminar_elemento((select id from _otro));
begin
  perform pg_temp.comprobar('Operario: no puede iniciar ni terminar un elemento de otra persona (NO_ENCONTRADO)',
    r -> 'error' ->> 'codigo' = 'NO_ENCONTRADO' and r2 -> 'error' ->> 'codigo' = 'NO_ENCONTRADO', r::text);
end;
$$;
reset role;

-- ADMINISTRACIÓN --------------------------------------------------------------
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.marcar_cajas(gen_random_uuid(), 1);
begin
  perform pg_temp.comprobar('Administración: ve todos los repartos, elementos y lecturas',
    (select count(*) from public.repartos r join public.jornadas j on j.id = r.jornada_id where j.fecha = '2026-11-03') = 2
    and (select count(*) from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
         join public.jornadas j on j.id = t.jornada_id where j.fecha = '2026-11-03') = 4
    and (select count(*) from public.lecturas_sheets) >= 2);
  perform pg_temp.comprobar('Administración: marcar cajas es del operario (NO_AUTORIZADO)',
    r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text);
end;
$$;
reset role;

-- SIN SESIÓN ----------------------------------------------------------------------
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión: ni tablas nuevas ni funciones nuevas',
    pg_temp.rechazada($q$select count(*) from public.tarea_elementos$q$)
    and pg_temp.rechazada($q$select count(*) from public.repartos$q$)
    and pg_temp.rechazada($q$select public.marcar_cajas(gen_random_uuid(), 1)$q$)
    and pg_temp.rechazada($q$select public.servidor_preparar(gen_random_uuid())$q$));
end;
$$;
reset role;

-- SERVIDOR: solicitudes internas de un solo uso --------------------------------------
do $$
declare
  v_id uuid;
begin
  insert into motor.solicitudes_servidor (persona_id, funcion)
  values ('00000000-0000-4000-a000-000000000001', 'lista_stock') returning id into v_id;
  perform pg_temp.comprobar('Solicitud interna: sirve una sola vez y solo para su función',
    public.servidor_canjear_solicitud(v_id, 'pegar_reparto') is null
    and public.servidor_canjear_solicitud(v_id, 'lista_stock') = '00000000-0000-4000-a000-000000000001'
    and public.servidor_canjear_solicitud(v_id, 'lista_stock') is null);
  update motor.solicitudes_servidor set usada_en = null, creada_en = now() - interval '6 minutes' where id = v_id;
  perform pg_temp.comprobar('Solicitud interna: caduca a los 5 minutos',
    public.servidor_canjear_solicitud(v_id, 'lista_stock') is null);
  update public.configuracion set valor = '"produccion"' where clave = 'entorno' and centro_id is null;
  begin
    perform prueba.invocar('lista_stock', '00000000-0000-4000-a000-000000000001');
    perform pg_temp.comprobar('prueba.invocar se niega fuera del entorno de pruebas', false, 'no se negó');
  exception when raise_exception then
    perform pg_temp.comprobar('prueba.invocar se niega fuera del entorno de pruebas', true);
  end;
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
