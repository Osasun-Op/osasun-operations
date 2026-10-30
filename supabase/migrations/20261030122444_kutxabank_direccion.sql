-- Tarea 22 (corrección del propietario, 30/10/2026): la dirección de Kutxabank
-- (rollos de TPV) es el número 151, en San Inazio, 48015 Bilbao.
--
-- Deshacer: volver a poner 'Avda. Lehendakari Aguirre 13, Deusto, Bilbao'.

update public.compras
   set direccion = 'Avda. Lehendakari Aguirre 151, San Inazio, 48015 Bilbao', actualizada_en = now()
 where nombre = 'Rollos de TPV' and sitio = 'Kutxabank';
