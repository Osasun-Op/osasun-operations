# OSASUN OPERATIONS — Auditoría de solo lectura

**Versión:** 1.5 · **Fecha:** 03/11/2026 · **Autor:** agente de base de datos (Tareas 19, 20, 25, 26, 27 y 28)

Las comprobaciones de cada revisión (lista de revisión de `AGENTE_COORDINADOR.md`), siempre las mismas y en el mismo orden. Nada de esto cambia la base de datos ni los archivos.

## 0. Los dos entornos

| | Pruebas | Producción |
| --- | --- | --- |
| Proyecto | `osasun-pruebas` · `rvypswuoafnjwqdwxjvo` | `osasun-produccion` · `iqjkysfbtpkukkvfyumf` (plan Pro, copias diarias) |
| URL | `https://rvypswuoafnjwqdwxjvo.supabase.co` | `https://iqjkysfbtpkukkvfyumf.supabase.co` |
| Clave pública (*publishable*) | `sb_publishable_IKa8qY4SO04BeRe0WWhy-Q_nE2OIwQg` | `sb_publishable_32yrYIfaB8FT6PFMyIw3nQ_u6sJHjVu` |
| Para qué | Probar cada cambio (pruebas en verde, llamada real, registros) | El almacén y las tiendas. **Solo entra lo aprobado y fusionado en `main`** |
| Datos | Fichas y datos de prueba (`supabase/seed_pruebas.sql`) e histórico de pruebas | Solo lo de partida: configuración del entorno, cuentas autorizadas y lista de compras. Las fichas las crea el primer acceso con Google |
| Pruebas de `supabase/tests/` | Sí | **Nunca** (ni la 22 ni ninguna que escriba) |

Las claves públicas no son secretas (no dan permisos por sí solas). Las claves de servidor y los secretos (`GOOGLE_CUENTA_TECNICA`, `RESEND_API_KEY`) son de cada entorno y solo están en Supabase.

**Propias de cada entorno** (en `public.configuracion`, nunca en una migración ni en el repositorio): `entorno`, `url_proyecto`, `correo_administracion`, `telefono_administracion`, `cuentas_autorizadas`, `operario_por_defecto`, `administracion_por_defecto` y, en pruebas, `cierres_sin_correo`. Todo lo demás de la configuración lo ponen las migraciones y es igual en los dos. La huella deja fuera esas claves (Tarea 26), así que sus 11 apartados se comparan tal cual entre los dos entornos y una base creada solo con las migraciones.

**Tiendas (Tareas 27 y 28; solo en pruebas hasta que el propietario lo apruebe, `AGENTE_BASE_DE_DATOS.md` §4):** cada tienda es una cuenta autorizada más (`rol: "tienda"` y su `centro`, en `cuentas_autorizadas`). Los **nombres de cada tienda** (`personas_tienda`), los **días cerrados** (`dias_cerrados`), los turnos, los vídeos y, desde la Tarea 28, las **bolsas** (`bolsas_tienda`), los **cierres de caja** (`cierres_caja`) y las **muestras y el material** (`peticiones_tienda`) son **datos de cada entorno**: los ponen la app (Administración y las tiendas) o, si el propietario lo pide, el agente de base a base, nunca una migración ni el repositorio, y no cuentan en la huella. El horario de cada tienda (`horario_tienda`), `alternar_semanales`, `pedir_material`, `peticiones_por_envio` y las plantillas de tienda sí los ponen las migraciones: «carga inicial» ordena y distingue por tienda esas filas (desde la Tarea 27).

## 1. La base de datos: `motor.auditoria()`

Con el conector de Supabase (`execute_sql`), que entra como `postgres`, en pruebas y en producción (en producción es lo único que se ejecuta, y solo lee):

```sql
select jsonb_pretty(motor.auditoria());
```

La usa `postgres` (el conector del coordinador). `service_role` tiene el permiso, pero el esquema `motor` no se le abre (decidido por el propietario, 30/10/2026); ni las pantallas ni nadie con sesión la pueden usar.

| Apartado | Qué trae | Lo normal |
| --- | --- | --- |
| `resumen` / `avisos` | «Sin avisos» o «N avisos», y una frase por cosa rara | **«Sin avisos»** |
| `migraciones` | Cuántas hay y la última | Las mismas que `supabase/migrations/` (cuántos archivos y el último) |
| `huella` | Una cifra por apartado: tablas, restricciones, índices, RLS, permisos, funciones, carga inicial y tarea programada (`motor.huella_estructura()`, la misma que la prueba 00) | Los 11 apartados iguales en pruebas, en producción y en una base creada solo con las migraciones del repositorio. «Carga inicial» no cuenta las claves propias de cada entorno (§0) |
| `tablas` | Cada tabla de `public` y `motor`, con RLS y su número de políticas | Todas con RLS |
| `funciones` | Cuántas por esquema; de `public`, las que ejecuta `anon`, las que ejecuta `authenticated` y las `security definer` | `public_anon` vacía; ninguna `servidor_*` en `public_authenticated` |
| `triggers` · `cron` | Disparadores propios y tareas programadas | `alta_persona_autorizada`, `tareas_tras_hecha`; `generar_jornada_diaria`, `generar_cierres_turno`, `reintentar_correos`, activas en producción (en pruebas, apagadas desde el día del cambio). `generar_jornada_diaria` hace también la jornada de cada tienda con cuenta (si no, la hace `tienda_hoy` al entrar); `generar_cierres_turno` es solo del almacén (Tarea 27). 🧪 En pruebas, desde la Tarea 35, `generar_cierres_turno` pasa a ser `cerrar_turnos_olvidados` (`5 22,23 * * *`: solo cierra los turnos de ayer sin cerrar) |
| `configuracion` | Las claves que usan los cálculos, con su valor, y las que falten | `faltan` vacía |
| `datos` | Última lectura correcta de la hoja y último error, correos fallidos de 7 días, si hay jornada hoy | Lectura correcta más reciente que el error; 0 correos fallidos; jornada hoy en día de trabajo (en producción, desde que el operario ha entrado por primera vez) |

**Avisos que da:** tabla de `public` sin RLS; función `servidor_*` que pueda ejecutar alguien que no sea `service_role`; función de `public` ejecutable por `anon` (salvo las permitidas, listadas dentro de la función: hoy ninguna); clave de configuración que falte; más de una tarea en curso para la misma persona; más de un reparto (o envío) aceptado en la misma jornada; reparto aceptado hoy sin su tarea de producción o de bolsas, o envío sin su tarea de preparación (Tarea 20); elementos sin su tarea; lectura de la hoja con error más reciente que la última correcta.

Un aviso no se arregla en la revisión: se encarga.

**La prueba `supabase/tests/22_auditoria.sql` nunca se ejecuta en producción:** prepara casos raros (quita un índice y una restricción) dentro de una transacción. En producción solo se ejecuta la auditoría.

## 2. Los registros del servidor (`query_logs`)

Respuestas 500 y excepciones de las funciones del servidor, agrupadas por función. Sin fechas, son las últimas 24 h. **Lo normal: ninguna fila**; si hay filas, mirar que `ultima_500` y `ultima_excepcion` sean anteriores al cambio que se revisa.

```sql
select funcion,
       countIf(tipo = '500') as respuestas_500,
       maxIf(timestamp, tipo = '500') as ultima_500,
       countIf(tipo = 'excepcion') as excepciones,
       maxIf(timestamp, tipo = 'excepcion') as ultima_excepcion,
       argMaxIf(mensaje, timestamp, tipo = 'excepcion') as ultimo_mensaje
from (
  select timestamp, '500' as tipo, regexp_extract(event_message, '/functions/v1/([a-z_]+)', 1) as funcion, '' as mensaje
  from logs where source = 'function_edge_logs' and event_message like '% | 5__ | %'
  union all
  select timestamp, 'excepcion' as tipo,
         coalesce(nullIf(regexp_extract(event_message, '/source/([a-z_]+)/index', 1), ''), log_attributes['function_id']) as funcion,
         substring(event_message, 1, 120) as mensaje
  from logs where source = 'function_logs' and log_attributes['level'] = 'error'
)
group by funcion
order by respuestas_500 + excepciones desc, funcion
```

(Las excepciones capturadas a propósito también salen, por ejemplo si falla guardar la cobertura: el reparto sigue, pero el registro lo enseña.)

## 3. Las funciones del servidor desplegadas (`list_edge_functions`)

Tienen que estar estas cinco, `ACTIVE` y con `verify_jwt: false` (comprueban ellas quién llama), y ninguna más. Son las carpetas de `supabase/functions/` (sin `_compartido`):

`catalogo` · `enviar_correo` · `guardar_pedido_cliente` · `guardar_reparto` · `lista_stock`.

`pegar_reparto` se borró en la Tarea 29d (orden del propietario, 04/11/2026): si aún sale publicada en un proyecto, hay que borrarla de él.

## 4. Funciones rehechas en una migración: `scripts/comparar_funciones.py`

```
python3 scripts/comparar_funciones.py supabase/migrations/AAAAMMDDHHMMSS_nombre.sql
```

Por cada función de la migración, su versión anterior en `supabase/migrations/` (mismo nombre y tipos): `· nueva`, `✔ no pierde nada` o `✘ pierde N líneas` con las líneas que ya no están. Una línea cambiada sale como perdida: hay que mirar que lo que hacía siga en la versión nueva. Sale con 1 si alguna pierde líneas. Solo lee archivos.

## 5. Pasar un cambio aprobado de pruebas a producción

Solo lo que está **fusionado en `main`**, y en el mismo orden. Lo hace el agente de base de datos cuando el coordinador lo encarga (aprobación del propietario).

1. **Migraciones nuevas**, una a una y en orden: `apply_migration` en producción con el contenido **exacto** del archivo de `supabase/migrations/`. El conector apunta su propia versión (la hora de ese momento): justo después se cambia por la del archivo,
   ```sql
   update supabase_migrations.schema_migrations set version = 'AAAAMMDDHHMMSS' where name = 'nombre';
   ```
   y se comprueba que lo guardado es el archivo: `md5(array_to_string(statements, ''))` igual al md5 del archivo sin los saltos de línea del final (`printf %s "$(cat archivo)" | md5sum`). `list_migrations` tiene que dar las mismas versiones y nombres que la carpeta.
2. **Funciones del servidor que cambian:** `deploy_edge_function` en producción con los mismos archivos que en `main` (el `index.ts` y lo que importa de `_compartido/`, sin las pruebas) y `verify_jwt: false`. Se comprueba con `get_edge_function` que cada archivo es igual al del repositorio.
3. **Configuración propia del entorno:** una migración no la toca (es de cada entorno). Si un cambio necesita una clave nueva de ese tipo, el PR lo dice y se pone a mano en cada entorno, sin datos personales en el PR, y la misma migración la añade a las que `motor.huella_estructura()` deja fuera en «carga inicial» (y a la prueba 22).
4. **Comprobaciones, solo de lectura:** `motor.auditoria()` «Sin avisos» y con las migraciones del repositorio; la huella igual en los 11 apartados a la de una base creada solo con las migraciones (sin `seed_pruebas.sql`) y a la del otro entorno.
   Después, los registros (punto 2) y `list_edge_functions` (punto 3). **En producción no se ejecuta ninguna prueba de `supabase/tests/`.**
5. **Deshacer:** como dice el PR del cambio (cada migración lleva su «Deshacer»), con una migración nueva que pasa primero por pruebas. Producción tiene además copia de seguridad diaria (plan Pro).
6. El PR o el comentario de la entrega dice qué migraciones y funciones se han pasado y el resultado de las comprobaciones.
