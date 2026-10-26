-- Tarea 2 · Carga inicial: almacén, tiendas y destinos, configuración y
-- plantillas del mapa semanal (PLAN_TECNICO.md §2.6 v0.2).
-- Las personas y sus horarios no van aquí: los usuarios reales se dan de alta
-- por invitación; los de prueba están en supabase/seed_pruebas.sql.

insert into public.centros_trabajo (codigo, nombre, tipo, nombre_en_sheets, alias, activo) values
  ('ALMACEN',    'Almacén',    'almacen', 'ALMACEN',    '{}',                  true),
  ('BILBAO',     'Bilbao',     'tienda',  'BILBAO',     '{BILBAO}',            true),
  ('ALGORTA',    'Algorta',    'tienda',  'ALGORTA',    '{ALGORTA}',           true),
  ('DONOSTI',    'Donosti',    'tienda',  'DONOSTI',    '{DONOSTI}',           true),
  ('BARAKALDO',  'Barakaldo',  'tienda',  'BARAKALDO',  '{BARAKALDO}',         true),
  ('RENTERIA',   'Rentería',   'tienda',  'RENTERIA',   '{RENTERIA}',          true),
  ('BASAURI',    'Basauri',    'tienda',  'BASAURI',    '{BASAURI}',           true),
  ('PORTU',      'Portugalete','tienda',  'PORTU',      '{PORTU}',             true),
  ('DURANGO',    'Durango',    'tienda',  'LAUDIO',     '{DURANGO,LAUDIO}',    false),
  ('GIPUZKOA',   'Gipuzkoa (envío a Rentería)', 'destino', 'GIPUZKOA', '{GIPUZKOA}', true);

insert into public.configuracion (clave, centro_id, valor) values
  ('hora_generacion_jornada', null, '"06:00"'),
  ('duracion_min_por_caja',   null, '1'),
  ('duracion_min_por_bolsa',  null, '3');

-- Plantillas del almacén.
-- no_terminada: «arrastrar» = obligatorias fijas que pasan al día siguiente;
-- «nada» = ligadas a una hora o un turno (solo constan en el cierre);
-- «recalcular» = stock.
insert into public.plantillas_tarea (
  centro_id, codigo, titulo, programacion, dias_semana, turno, hora_inicio, hora_limite,
  duracion_min, condicion, requiere_codigo, contenido, obligatoria, prioridad_cola, no_terminada, orden)
select c.id, v.codigo, v.titulo, v.programacion, v.dias::smallint[], v.turno,
       v.hora_inicio::time, v.hora_limite::time, v.duracion, v.condicion, v.requiere,
       v.contenido, v.obligatoria, v.cola, v.no_terminada, v.orden
from public.centros_trabajo c,
(values
  -- Mañana (lunes a viernes)
  ('revision_inicial', 'Revisión inicial: estado de las tiendas, formulario de incidencias y stock empaquetado',
     'con_hora', '{1,2,3,4,5}', 'manana', '08:30', null, 15, null, null, 'simple', false, null, 'nada', 10),
  ('pegar_reparto', 'Pega el reparto de hoy',
     'con_hora', '{1,2,3,4,5}', 'manana', '08:45', null, 5, null, null, 'simple', true, null, 'nada', 20),
  ('limpieza_resinas', 'Limpieza intensiva de la estación de resinas',
     'dia_semana', '{5}', 'manana', null, '10:45', 30, null, null, 'simple', true, null, 'arrastrar', 25),
  ('produccion_reparto', 'Producción del reparto',
     'condicionada', '{1,2,3,4,5}', 'manana', null, '10:45', null, 'reparto_pegado', null, 'produccion_reparto', true, null, 'nada', 30),
  ('bolsas', 'Bolsas listas en la mesa de salida',
     'condicionada', '{1,2,3,4,5}', 'manana', null, '10:45', null, 'reparto_pegado', null, 'bolsas', true, null, 'nada', 40),
  ('salida_reparto', 'Salida del reparto',
     'con_hora', '{1,2,3,4,5}', 'manana', '10:45', null, 120, 'sale_operario', null, 'simple', true, null, 'nada', 50),
  ('efectivo_reporte', 'Efectivo frente a la Z y reporte a Administración',
     'condicionada', '{1,2,3,4,5}', 'manana', null, null, null, 'sale_operario', 'salida_reparto', 'simple', true, null, 'nada', 55),
  ('nacex_viernes', 'Envío a Gipuzkoa/Durango por Nacex',
     'dia_semana', '{5}', 'manana', null, null, null, 'hay_envio', null, 'simple', true, null, 'nada', 60),
  ('preparar_envio_viernes', 'Prepara el envío aprobado',
     'condicionada', '{5}', 'manana', null, null, null, 'envio_pegado', null, 'simple', true, null, 'nada', 58),
  ('recuento_manana', 'Recuento de stock y cajas hechas, y actualización de STOCK ALMACEN DIARIO',
     'con_hora', '{1,2,3,4,5}', 'manana', '12:45', '13:00', 15, null, null, 'recuento', true, null, 'nada', 90),
  -- Tarde (lunes a jueves)
  ('revisar_envio', 'Revisa si toca envío a Gipuzkoa/Durango y propónselo a Administración',
     'con_hora', '{1,2,3,4}', 'tarde', '15:30', null, null, null, null, 'simple', false, null, 'nada', 10),
  ('minis', 'Minis (unos 35, para llevar el miércoles)',
     'dia_semana', '{1}', 'tarde', null, null, 35, null, null, 'simple', true, null, 'arrastrar', 20),
  ('resinas', 'Resinas: comprueba antes en PRINCIPAL si ya hay una semana de cobertura',
     'dia_semana', '{2}', 'tarde', null, null, null, null, null, 'simple', true, null, 'arrastrar', 20),
  ('control_materiales', 'Control semanal de materiales y aviso de cobertura a 2 semanas',
     'dia_semana', '{4}', 'tarde', null, '17:55', null, null, null, 'simple', true, null, 'arrastrar', 30),
  ('preparar_envio', 'Prepara el envío aprobado',
     'condicionada', '{1,2,3,4}', 'tarde', null, '18:10', null, 'envio_pegado', null, 'simple', true, null, 'nada', 40),
  ('recuento_tarde_envio', 'Recuento de stock y cajas hechas',
     'con_hora', '{1,2,3,4}', 'tarde', '17:55', '18:10', 15, 'hay_envio', null, 'recuento', true, null, 'nada', 80),
  ('nacex_salida', 'Salida a Nacex con el envío (vuelta hacia las 18:25 para cerrar)',
     'con_hora', '{1,2,3,4}', 'tarde', '18:10', null, 15, 'hay_envio', null, 'simple', true, null, 'nada', 85),
  ('recuento_tarde', 'Recuento de stock y cierre',
     'con_hora', '{1,2,3,4}', 'tarde', '18:15', '18:30', 15, 'no_hay_envio', null, 'recuento', true, null, 'nada', 90),
  -- En cualquier momento (eventos)
  ('recepcion_mercancia', 'Abre y comprueba la mercancía que ha llegado',
     'condicionada', '{1,2,3,4,5}', null, null, null, null, 'llega_mercancia', null, 'simple', true, null, 'arrastrar', 15),
  ('pedido_cliente', 'Prepara el pedido de cliente y envíalo por Nacex',
     'condicionada', '{1,2,3,4,5}', null, null, null, null, 'pedido_cliente', null, 'simple', true, null, 'arrastrar', 35),
  ('tirada_vapers', 'Tirada de vapers: 50, repartidos entre 2 tipos',
     'condicionada', '{1,2,3,4,5}', null, null, null, null, 'no_quedan_vapers', null, 'simple', false, null, 'arrastrar', 50),
  -- Cola de tiempo libre
  ('cola_stock', 'Producción para el stock del almacén (+35 %)',
     'cola_libre', '{1,2,3,4,5}', null, null, null, null, null, null, 'stock_35', false, 'A', 'recalcular', 100),
  ('cola_compras', 'Compras y aprovisionamientos pendientes',
     'cola_libre', '{1,2,3,4,5}', null, null, null, null, null, null, 'simple', false, 'C', 'nada', 110),
  ('cola_orden', 'Orden y limpieza',
     'cola_libre', '{1,2,3,4,5}', null, null, null, null, null, null, 'simple', false, 'D', 'nada', 120)
) as v(codigo, titulo, programacion, dias, turno, hora_inicio, hora_limite, duracion, condicion, requiere,
       contenido, obligatoria, cola, no_terminada, orden)
where c.codigo = 'ALMACEN';
