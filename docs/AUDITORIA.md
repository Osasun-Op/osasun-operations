# OSASUN OPERATIONS — Auditoría de solo lectura

**Versión:** 1.0 · **Fecha:** 29/10/2026 · **Autor:** agente de base de datos (Tarea 19)

Las comprobaciones de cada revisión (lista de revisión de `AGENTE_COORDINADOR.md`), siempre las mismas y en el mismo orden. Nada de esto cambia la base de datos ni los archivos.

## 1. La base de datos: `motor.auditoria()`

Con el conector de Supabase (`execute_sql`) en el proyecto de pruebas:

```sql
select jsonb_pretty(motor.auditoria());
```

Solo la pueden ejecutar `postgres` (el conector) y `service_role`; ni las pantallas ni nadie con sesión.

| Apartado | Qué trae | Lo normal |
| --- | --- | --- |
| `resumen` / `avisos` | «Sin avisos» o «N avisos», y una frase por cosa rara | **«Sin avisos»** |
| `migraciones` | Cuántas hay y la última | Las mismas que `supabase/migrations/` (cuántos archivos y el último) |
| `huella` | Una cifra por apartado: tablas, restricciones, índices, RLS, permisos, funciones, carga inicial y tarea programada (`motor.huella_estructura()`, la misma que la prueba 00) | Igual que en una base creada solo con las migraciones del repositorio |
| `tablas` | Cada tabla de `public` y `motor`, con RLS y su número de políticas | Todas con RLS |
| `funciones` | Cuántas por esquema; de `public`, las que ejecuta `anon`, las que ejecuta `authenticated` y las `security definer` | `public_anon` vacía; ninguna `servidor_*` en `public_authenticated` |
| `triggers` · `cron` | Disparadores propios y tareas programadas | `alta_persona_autorizada`, `tareas_tras_hecha`; `generar_jornada_diaria`, `generar_cierres_turno`, `reintentar_correos`, activas |
| `configuracion` | Las claves que usan los cálculos, con su valor, y las que falten | `faltan` vacía |
| `datos` | Última lectura correcta de la hoja y último error, correos fallidos de 7 días, si hay jornada hoy | Lectura correcta más reciente que el error; 0 correos fallidos; jornada hoy en día de trabajo |

**Avisos que da:** tabla de `public` sin RLS; función `servidor_*` que pueda ejecutar alguien que no sea `service_role`; función de `public` ejecutable por `anon` (salvo las permitidas, listadas dentro de la función: hoy ninguna); clave de configuración que falte; más de una tarea en curso para la misma persona; más de un reparto (o envío) aceptado en la misma jornada; elementos sin su tarea; lectura de la hoja con error más reciente que la última correcta.

Un aviso no se arregla en la revisión: se encarga.

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

Tienen que estar estas seis, `ACTIVE` y con `verify_jwt: false` (comprueban ellas quién llama), y ninguna más. Son las carpetas de `supabase/functions/` (sin `_compartido`):

`catalogo` · `enviar_correo` · `guardar_pedido_cliente` · `guardar_reparto` · `lista_stock` · `pegar_reparto` (obsoleta, publicada hasta que el coordinador diga quitarla).

## 4. Funciones rehechas en una migración: `scripts/comparar_funciones.py`

```
python3 scripts/comparar_funciones.py supabase/migrations/AAAAMMDDHHMMSS_nombre.sql
```

Por cada función de la migración, su versión anterior en `supabase/migrations/` (mismo nombre y tipos): `· nueva`, `✔ no pierde nada` o `✘ pierde N líneas` con las líneas que ya no están. Una línea cambiada sale como perdida: hay que mirar que lo que hacía siga en la versión nueva. Sale con 1 si alguna pierde líneas. Solo lee archivos.
