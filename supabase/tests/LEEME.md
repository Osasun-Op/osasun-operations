# Pruebas automáticas de la base de datos

Se ejecutan contra el proyecto de **pruebas** (`osasun-pruebas`), con el conector de Supabase (`execute_sql`) o con `psql` y la cadena de conexión guardada como secreto del entorno (nunca en el repositorio).

| Archivo | Qué comprueba | Deja la base como estaba |
| --- | --- | --- |
| `00_huella_estructura.sql` | Una huella (md5) por apartado de la estructura: tablas, restricciones, índices, RLS, permisos, funciones, carga inicial y tarea programada. Debe dar lo mismo en pruebas que en una base creada solo con `supabase/migrations/`. | Solo lee |
| `01_semana_simulada.sql` | Lunes a viernes con y sin envío y con salida del operario o de Administración: cada tarea el día y a la hora correctos. Generación programada a las 06:00 (invierno y verano). | Transacción deshecha |
| `02_idempotencia.sql` | Generar, repetir condiciones, iniciar y terminar dos veces no duplica nada; errores de estado. | Transacción deshecha |
| `03_arrastres.sql` | Qué pasa al día siguiente y qué no (§6.5). | Transacción deshecha |
| `04_permisos.sql` | Operario, Administración, usuario sin ficha y sin sesión: qué ven y qué no pueden hacer. | Transacción deshecha |
| `05_orden_tarea_activa.sql` | Un caso por cada escalón de la regla de `tarea_activa`. | Transacción deshecha |
| `07_reparto_stock.sql` | Lo que guardan las funciones del servidor: reparto aceptado y con errores, el mismo reparto dos veces, reparto corregido conservando lo hecho, envío, lista de stock una vez por turno, referencias y cajas con su punto de encaje. | Transacción deshecha |
| `08_permisos_reparto_stock.sql` | Permisos de las tablas y funciones de la Tarea 3 y solicitudes internas de un solo uso. | Transacción deshecha |
| `06_concurrencia_1..4` | Dos llamadas a la vez a la generación: 1 preparar → 2 (A) y 3 (B) **a la vez** → 4 limpieza. | La limpieza lo borra y lo comprueba |

Cada prueba devuelve una fila por comprobación con `OK` o `FALLO` (y el detalle si falla).

## Ensayo local (opcional)

Para depurar antes de tocar pruebas se puede crear una base local con PostgreSQL, una imitación mínima de Supabase (roles `anon`/`authenticated`, `auth.users`, `auth.uid()` y `cron.schedule`) y las migraciones en orden, quitando la línea `create extension if not exists pg_cron;`.

## Pruebas unitarias del cálculo (sin base de datos ni red)

`supabase/functions/_compartido/*_test.ts`: todos los casos R1 y R3 de `docs/REGLAS_CALCULO.md`, la lectura de las pestañas con un extracto real de la hoja y la lectura con una Google simulada (hoja no disponible, pestaña renombrada, alcance de solo lectura). Se ejecutan con `deno test supabase/functions/_compartido/`.

Las pruebas de base de datos empiezan marcando como hechas (dentro de la transacción) las tareas pendientes de las jornadas reales del operario de pruebas, para no depender de lo que haya generado la tarea programada.
