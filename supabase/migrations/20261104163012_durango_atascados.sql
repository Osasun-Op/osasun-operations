-- Tarea 31 (decisión del propietario, 04/11/2026, PR #34): lo atascado en Durango va directo a Administración, como en
-- las franquicias (promoción o recogida), porque Durango recibe por envío. Solo cambia su configuración `atascados`.
-- Solo en pruebas: producción espera con las de tiendas.
--
-- Deshacer: volver a poner `"ofrecer"` en la clave `atascados` de Durango.
update public.configuracion k
   set valor = '"administracion"'
  from public.centros_trabajo c
 where c.id = k.centro_id and c.codigo = 'DURANGO' and k.clave = 'atascados';
