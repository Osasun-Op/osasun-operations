-- Prueba 14 · «¿Quién sale?» (Tarea 8, ESTADO v1.20 §5 R1)
-- Cambiar quién sale sin volver a pegar el reparto (operario y Administración),
-- los nombres del desplegable en mi_perfil, la anotación cuando el desplegable y
-- la línea SALE: no coinciden y el orden si sale el operario: bolsas listas →
-- salida del reparto (10:45) → efectivo y reporte a la vuelta.
-- Martes 17/11/2026. Transacción deshecha al final.

begin;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
-- El operario de pruebas es el operario por defecto dentro de la prueba (se deshace al final).
insert into public.configuracion (clave, centro_id, valor) values ('operario_por_defecto', null, '"00000000-0000-4000-a000-000000000001"')
on conflict (clave, centro_id) do update set valor = excluded.valor;

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
create function pg_temp.h(p_hora text) returns timestamptz language sql as $$
  select ('2026-11-17 ' || p_hora || ':00+01')::timestamptz $$;
create function pg_temp.estado(p_jornada uuid, p_clave text) returns text language sql as $$
  select estado from public.tareas where jornada_id = p_jornada and clave = p_clave $$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  adm constant uuid := '00000000-0000-4000-a000-000000000002';
  j uuid;
  r jsonb;
  r2 jsonb;
  v_rep uuid;
begin
  -- Nombres del desplegable
  r := motor.mi_perfil_de(op);
  perform pg_temp.comprobar('mi_perfil: opciones del desplegable con los nombres (Administración y operario por defecto)',
    r -> 'quien_sale_opciones' = jsonb_build_array(
      jsonb_build_object('valor', 'administracion', 'nombre',
        (select nombre from public.personas where rol = 'administracion' and activo order by nombre, id limit 1)),
      jsonb_build_object('valor', 'operario', 'nombre', 'Operario de pruebas')), r::text);
  perform pg_temp.comprobar('mi_perfil de Administración trae las mismas opciones',
    motor.mi_perfil_de(adm) -> 'quien_sale_opciones' = r -> 'quien_sale_opciones');

  -- Cambiar quién sale sin volver a pegar
  r := motor.cambiar_quien_sale_de(op, 'nadie', pg_temp.h('08:40'));
  perform pg_temp.comprobar('Valor no válido: DATOS_NO_VALIDOS', r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
  r := motor.cambiar_quien_sale_de(op, 'operario', '2026-11-21 10:00+01');
  perform pg_temp.comprobar('Sábado (sin jornada): SIN_JORNADA', r -> 'error' ->> 'codigo' = 'SIN_JORNADA', r::text);

  j := motor.generar_jornada(op, '2026-11-17');
  r := motor.cambiar_quien_sale_de(op, 'operario', pg_temp.h('08:40'));
  perform pg_temp.comprobar('El operario dice que sale él: aparecen «Salida del reparto» y «Efectivo y reporte»',
    (r ->> 'cambiado')::boolean and r -> 'antes' = 'null'::jsonb
    and (select sale from public.jornadas where id = j) = 'operario'
    and pg_temp.estado(j, 'salida_reparto') = 'pendiente' and pg_temp.estado(j, 'efectivo_reporte') = 'pendiente'
    and r -> 'tarea_activa' ? 'tarea', r::text);
  r := motor.cambiar_quien_sale_de(op, 'operario', pg_temp.h('08:41'));
  perform pg_temp.comprobar('Repetirlo no cambia nada (idempotente) ni lo anota dos veces',
    not (r ->> 'cambiado')::boolean
    and (select count(*) from public.registro_eventos where jornada_id = j and tipo = 'quien_sale_cambiado') = 1, r::text);
  r := motor.cambiar_quien_sale_de(adm, 'administracion', pg_temp.h('08:50'));
  perform pg_temp.comprobar('Administración cambia a «sale Administración»: salida y efectivo se retiran; queda anotado quién lo cambió',
    (r ->> 'cambiado')::boolean and r ->> 'antes' = 'operario'
    and pg_temp.estado(j, 'salida_reparto') = 'cancelada' and pg_temp.estado(j, 'efectivo_reporte') = 'cancelada'
    and r -> 'tarea_activa' = 'null'::jsonb
    and exists (select 1 from public.registro_eventos where jornada_id = j and tipo = 'quien_sale_cambiado'
                and persona_id = adm and datos ->> 'sale' = 'administracion'), r::text);
  r := motor.cambiar_quien_sale_de(adm, 'operario', pg_temp.h('08:55'));
  perform pg_temp.comprobar('Y vuelta a «sale el operario»: salida y efectivo se recuperan',
    pg_temp.estado(j, 'salida_reparto') = 'pendiente' and pg_temp.estado(j, 'efectivo_reporte') = 'pendiente', r::text);

  -- Reparto pegado con el desplegable (sale el operario) y orden de la mañana
  r := public.servidor_guardar_reparto(adm, j, 'reparto', 'BILBAO\n1x V2 4g', 'huella-14', '2026-11-17', 'operario', null, '[]',
         '[{"producto": "V2", "formato": "4g", "pedido": 1, "en_almacen": 1, "faltan": 0, "orden": 1}]',
         jsonb_build_array(jsonb_build_object('destino_id', (select id from public.centros_trabajo where codigo = 'BILBAO'),
           'items', '[{"producto": "V2", "formato": "4g", "cantidad": 1}]'::jsonb)),
         true, pg_temp.h('09:00'));
  v_rep := (r ->> 'reparto_id')::uuid;
  -- Tarea 29d: servidor_anotar_sale (la diferencia entre el desplegable y la línea SALE: del texto pegado) se ha
  -- borrado con pegar_reparto (orden del propietario, 04/11/2026).
  perform pg_temp.comprobar('Tarea 29d: servidor_anotar_sale ya no existe (pegar_reparto borrada)',
    v_rep is not null and to_regprocedure('public.servidor_anotar_sale(uuid, uuid, text, text)') is null);

  update public.tareas set estado = 'hecha'
   where jornada_id = j and clave not in ('bolsas', 'salida_reparto', 'efectivo_reporte', 'recuento_manana',
                                          'revisar_envio', 'resinas', 'recuento_tarde', 'cola_orden');
  r := motor.tarea_activa_de(op, pg_temp.h('10:30'));
  perform pg_temp.comprobar('Antes de las 10:45: «Bolsas listas en la mesa de salida»',
    r -> 'tarea' ->> 'clave' = 'bolsas', r -> 'tarea' ->> 'clave');
  perform motor.marcar_cajas_de(op, (select e.id from public.tarea_elementos e join public.tareas t on t.id = e.tarea_id
                                      where t.jornada_id = j and t.clave = 'bolsas' limit 1), 1, pg_temp.h('10:35'));
  r := motor.tarea_activa_de(op, pg_temp.h('10:40'));
  perform pg_temp.comprobar('Bolsas listas: lo siguiente es «Salida del reparto · 10:45» y el efectivo aún no aparece',
    pg_temp.estado(j, 'bolsas') = 'hecha' and r ->> 'siguiente' = 'Salida del reparto · 10:45'
    and r -> 'tarea' ->> 'clave' is distinct from 'efectivo_reporte', r::text);
  r := motor.tarea_activa_de(op, pg_temp.h('10:45'));
  perform pg_temp.comprobar('A las 10:45 toca «Salida del reparto»', r -> 'tarea' ->> 'clave' = 'salida_reparto', r -> 'tarea' ->> 'clave');
  perform motor.iniciar_tarea_de(op, (select id from public.tareas where jornada_id = j and clave = 'salida_reparto'), pg_temp.h('10:46'));
  r := motor.cambiar_quien_sale_de(adm, 'administracion', pg_temp.h('11:00'));
  r2 := motor.cambiar_quien_sale_de(adm, 'operario', pg_temp.h('11:00'));
  perform pg_temp.comprobar('Con la salida ya empezada no se cambia quién sale (ESTADO_NO_VALIDO); repetir lo mismo sí responde',
    r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO' and not (r2 ->> 'cambiado')::boolean
    and (select sale from public.jornadas where id = j) = 'operario', r::text);
  r := motor.terminar_tarea_de(op, (select id from public.tareas where jornada_id = j and clave = 'salida_reparto'), null, null, pg_temp.h('12:30'));
  perform pg_temp.comprobar('A la vuelta, «Efectivo y reporte»',
    r -> 'tarea_activa' -> 'tarea' ->> 'clave' = 'efectivo_reporte', r -> 'tarea_activa' -> 'tarea' ->> 'clave');
  r := motor.cambiar_quien_sale_de(adm, 'administracion', pg_temp.h('12:31'));
  perform pg_temp.comprobar('Con la salida hecha tampoco: ESTADO_NO_VALIDO', r -> 'error' ->> 'codigo' = 'ESTADO_NO_VALIDO', r::text);
end;
$$;

-- Permisos
select pg_temp.como('00000000-0000-4000-a000-000000000001');
do $$
declare
  r jsonb := public.cambiar_quien_sale('x');
  r2 jsonb := public.mi_perfil();
begin
  perform pg_temp.comprobar('Operario: puede usar cambiar_quien_sale y mi_perfil trae las opciones',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS' and jsonb_array_length(r2 -> 'quien_sale_opciones') = 2, r::text || r2::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-000000000002');
do $$
declare
  r jsonb := public.cambiar_quien_sale('x');
begin
  perform pg_temp.comprobar('Administración: también puede usar cambiar_quien_sale',
    r -> 'error' ->> 'codigo' = 'DATOS_NO_VALIDOS', r::text);
end;
$$;
reset role;
select pg_temp.como('00000000-0000-4000-a000-0000000000ff');
do $$
declare
  r jsonb := public.cambiar_quien_sale('operario');
begin
  perform pg_temp.comprobar('Usuario sin ficha: NO_AUTORIZADO', r -> 'error' ->> 'codigo' = 'NO_AUTORIZADO', r::text);
end;
$$;
reset role;
select set_config('request.jwt.claims', '', true);
set local role anon;
do $$
begin
  perform pg_temp.comprobar('Sin sesión no se puede cambiar quién sale',
    pg_temp.rechazada($q$select public.cambiar_quien_sale('operario')$q$));
end;
$$;
reset role;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
