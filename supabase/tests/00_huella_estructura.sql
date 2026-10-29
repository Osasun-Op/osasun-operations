-- Prueba 00 · Huella de la estructura
-- Resume en una sola cifra por apartado (md5) todo lo que definen las
-- migraciones: tablas y columnas, restricciones, índices, políticas RLS,
-- permisos sobre tablas y funciones, y el texto de cada función.
-- Se ejecuta en pruebas y en una base creada solo con supabase/migrations: si
-- las huellas coinciden, la estructura de pruebas es exactamente la del repositorio.
-- La cuenta está en motor.huella_estructura() (Tarea 19), la misma que usa
-- motor.auditoria(). Solo lee; no cambia nada.

select apartado, huella from motor.huella_estructura();
