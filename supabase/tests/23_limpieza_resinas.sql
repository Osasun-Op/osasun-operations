-- Prueba 23 · La limpieza de resinas del viernes va después de lo del reparto,
-- los pedidos de cliente, el envío y el +35 %, y antes del recuento de las 12:45 (Tarea 20, ESTADO v1.33
-- §4 «Viernes»). Reutiliza el requisito de las tareas (`requiere_clave`), ahora
-- con una lista. Viernes 06/11 y 13/11/2026, sale el operario. Transacción deshecha.

begin;
-- Tarea 35: estas pruebas son de antes de «Empezar turno». Aquí el turno está abierto de su hora de inicio a la de fin,
-- como si el operario lo empezara y lo terminara a su hora (solo dentro de esta transacción, que se deshace). La 40
-- prueba los botones.
create or replace function motor.en_turno(p_jornada uuid, p_ahora timestamptz)
returns boolean language sql stable set search_path = '' as $$
  select exists (select 1 from public.jornadas j
                   join public.horarios h on h.persona_id = j.persona_id and h.dia_semana = extract(isodow from j.fecha)
                  where j.id = p_jornada
                    and p_ahora >= motor.en_local(j.fecha, h.hora_inicio)
                    and p_ahora < motor.en_local(j.fecha, h.hora_fin))
$$;
-- Aísla la prueba de las jornadas reales del operario de pruebas. Se deshace al final.
update public.tareas set estado = 'hecha'
 where estado in ('pendiente', 'en_curso', 'bloqueada')
   and jornada_id in (select id from public.jornadas where persona_id = '00000000-0000-4000-a000-000000000001');
create temp table _r (n serial, prueba text, ok boolean, detalle text) on commit drop;

create function pg_temp.comprobar(p_prueba text, p_ok boolean, p_detalle text default null)
returns void language sql as $$
  insert into _r (prueba, ok, detalle) values (p_prueba, coalesce(p_ok, false), case when p_ok then null else p_detalle end)
$$;
-- Qué tarea le sale al operario a una hora del día.
create function pg_temp.toca(p_prueba text, p_cuando timestamptz, p_clave text)
returns void language plpgsql as $$
declare
  r jsonb := motor.tarea_activa_de('00000000-0000-4000-a000-000000000001', p_cuando);
begin
  perform pg_temp.comprobar(p_prueba, r -> 'tarea' ->> 'clave' is not distinct from p_clave,
    'esperada: ' || coalesce(p_clave, '(ninguna)') || ' · obtenida: ' || coalesce(r -> 'tarea' ->> 'clave', '(ninguna)'));
end;
$$;
create function pg_temp.hecha(p_jornada uuid, p_claves text[])
returns void language sql as $$
  update public.tareas set estado = 'hecha', terminada_en = now() where jornada_id = p_jornada and clave = any (p_claves)
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid;
  t public.tareas;
begin
  -- Plantilla: requisito, hora límite y lo que pasa si no se hace.
  perform pg_temp.comprobar('Plantilla: después de preparar el reparto, su producción, los pedidos de cliente, sus bolsas, el envío y el +35 %; límite 12:45; se arrastra',
    exists (select 1 from public.plantillas_tarea where codigo = 'limpieza_resinas'
             and requiere_codigo = 'pegar_reparto+produccion_reparto+pedido_tienda+bolsas+preparar_envio_viernes+pedido_nacex_viernes+cola_stock'
             and hora_limite = '12:45' and obligatoria and no_terminada = 'arrastrar'));

  -- VIERNES 06/11 · con reparto, envío y +35 % -------------------------------------------
  j := motor.generar_jornada(op, '2026-11-06');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform prueba.fijar_condicion(j, 'hay_envio', 'true');
  select * into t from public.tareas where jornada_id = j and clave = 'limpieza_resinas';
  perform pg_temp.comprobar('La tarea del día: con su requisito y hora límite 12:45 (no 10:45)',
    t.requiere_clave = 'pegar_reparto+produccion_reparto+pedido_tienda+bolsas+preparar_envio_viernes+pedido_nacex_viernes+cola_stock'
    and t.hora_limite = '2026-11-06 12:45+01', t.hora_limite::text);

  perform pg_temp.toca('08:31: la revisión inicial', '2026-11-06 08:31+01', 'revision_inicial');
  perform pg_temp.hecha(j, array['revision_inicial']);
  perform pg_temp.comprobar('08:35 (lo que pasó el 30/10): con el reparto sin preparar, no sale la limpieza',
    (motor.tarea_activa_de(op, '2026-11-06 08:35+01') -> 'tarea' ->> 'clave') is distinct from 'limpieza_resinas');
  perform pg_temp.toca('08:46: prepara el reparto', '2026-11-06 08:46+01', 'pegar_reparto');
  perform prueba.fijar_condicion(j, 'reparto_pegado');
  perform prueba.fijar_condicion(j, 'envio_pegado');
  perform pg_temp.hecha(j, array['pegar_reparto']);
  perform pg_temp.toca('09:00: la producción del reparto, no la limpieza', '2026-11-06 09:00+01', 'produccion_reparto');
  perform pg_temp.hecha(j, array['produccion_reparto']);
  perform pg_temp.toca('09:30: las bolsas, no la limpieza', '2026-11-06 09:30+01', 'bolsas');
  perform pg_temp.hecha(j, array['bolsas']);
  perform pg_temp.toca('09:45: la preparación del envío, no la limpieza', '2026-11-06 09:45+01', 'preparar_envio_viernes');
  perform pg_temp.hecha(j, array['preparar_envio_viernes']);
  -- Pedidos de cliente del viernes (respuesta del propietario, 30/10): para recoger en tienda y por Nacex.
  perform motor.crear_tarea_condicionada(j, 'pedido_tienda', 'p1');
  perform motor.crear_tarea_condicionada(j, 'pedido_nacex', 'p2');
  perform pg_temp.comprobar('09:50: con dos pedidos de cliente por preparar, la limpieza espera',
    (motor.tarea_activa_de(op, '2026-11-06 09:50+01') -> 'tarea' ->> 'clave') in ('pedido_tienda:p1', 'pedido_nacex_viernes:p2'),
    motor.tarea_activa_de(op, '2026-11-06 09:50+01') -> 'tarea' ->> 'clave');
  perform pg_temp.hecha(j, array['pedido_tienda:p1']);
  perform pg_temp.toca('09:55: hecho el de la tienda, el de Nacex, no la limpieza', '2026-11-06 09:55+01', 'pedido_nacex_viernes:p2');
  perform pg_temp.hecha(j, array['pedido_nacex_viernes:p2']);
  perform pg_temp.toca('10:00: el +35 %, no la limpieza', '2026-11-06 10:00+01', 'cola_stock');
  perform pg_temp.hecha(j, array['cola_stock']);
  perform pg_temp.toca('10:20: hecho todo eso, la limpieza en el siguiente punto de encaje (antes que compras y orden)',
    '2026-11-06 10:20+01', 'limpieza_resinas');
  perform pg_temp.comprobar('10:46: la salida (y el envío a Nacex) va a su hora, delante de la limpieza',
    (motor.tarea_activa_de(op, '2026-11-06 10:46+01') -> 'tarea' ->> 'clave') in ('nacex_viernes', 'salida_reparto'));
  perform pg_temp.hecha(j, array['salida_reparto', 'nacex_viernes', 'efectivo_reporte', 'limpieza_resinas']);
  perform pg_temp.comprobar('Al final, «Orden y limpieza» sigue siendo lo último (después de compras)',
    (motor.tarea_activa_de(op, '2026-11-06 12:00+01') -> 'tarea' ->> 'clave') in ('cola_compras', 'cola_orden')
    and (select count(*) from public.tareas where jornada_id = j and prioridad_cola = 'D' and estado = 'pendiente') >= 1);

  -- VIERNES 13/11 · sin reparto ----------------------------------------------------------
  update public.tareas set estado = 'hecha' where jornada_id = j and estado in ('pendiente', 'en_curso', 'bloqueada');
  j := motor.generar_jornada(op, '2026-11-13');
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform pg_temp.hecha(j, array['revision_inicial']);
  perform pg_temp.comprobar('Sin reparto: mientras «Prepara el reparto» siga abierta, la limpieza espera',
    (motor.tarea_activa_de(op, '2026-11-13 08:40+01') -> 'tarea' ->> 'clave') is distinct from 'limpieza_resinas');
  update public.tareas set estado = 'hecha', motivo_no_hecha = 'Hoy no hay reparto' where jornada_id = j and clave = 'pegar_reparto';
  perform pg_temp.toca('Sin reparto: primero el +35 %', '2026-11-13 08:50+01', 'cola_stock');
  perform pg_temp.hecha(j, array['cola_stock']);
  perform pg_temp.toca('Sin reparto: hecho el +35 %, la limpieza sale en cuanto cabe', '2026-11-13 09:05+01', 'limpieza_resinas');
  perform pg_temp.comprobar('Sin reparto: no hay producción, bolsas ni envío, y no hacen esperar',
    not exists (select 1 from public.tareas where jornada_id = j
                 and clave in ('produccion_reparto', 'bolsas', 'preparar_envio_viernes')));
end;
$$;

do $$
declare
  op constant uuid := '00000000-0000-4000-a000-000000000001';
  j uuid := motor.generar_jornada(op, '2026-11-03');
begin
  -- El requisito de siempre sigue igual (prueba 05): el efectivo, tras la salida.
  perform prueba.fijar_condicion(j, 'sale', 'operario');
  perform pg_temp.comprobar('El efectivo sigue sin salir mientras la salida está por hacer',
    not motor.requisitos_hechos(j, 'salida_reparto')
    and (select requiere_clave from public.tareas where jornada_id = j and clave = 'efectivo_reporte') = 'salida_reparto');
  perform pg_temp.hecha(j, array['salida_reparto']);
  perform pg_temp.comprobar('… y sale en cuanto la salida está hecha', motor.requisitos_hechos(j, 'salida_reparto'));
end;
$$;

select prueba, case when ok then 'OK' else 'FALLO' end as resultado, detalle from _r order by n;
rollback;
