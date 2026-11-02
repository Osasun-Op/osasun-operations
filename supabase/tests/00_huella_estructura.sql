-- Prueba 00 · Huella de la estructura
-- Resume en una sola cifra por apartado (md5) todo lo que definen las
-- migraciones: tablas y columnas, restricciones, índices, políticas RLS,
-- permisos sobre tablas y funciones, y el texto de cada función.
-- Se ejecuta en pruebas y en una base creada solo con supabase/migrations: si
-- las huellas coinciden, la estructura de pruebas es exactamente la del repositorio.
-- La cuenta está en motor.huella_estructura() (Tarea 19), la misma que usa
-- motor.auditoria(). Solo lee; no cambia nada.
-- «Carga inicial» no cuenta las claves de configuración propias de cada entorno
-- (docs/AUDITORIA.md §0; url_proyecto y cierres_sin_correo desde la Tarea 26): los
-- 11 apartados tienen que dar lo mismo en pruebas, en producción y en la base
-- creada solo con las migraciones, sin ninguna consulta aparte.

select apartado, huella from motor.huella_estructura();
