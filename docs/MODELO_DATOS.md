# OSASUN OPERATIONS — Modelo de datos (V1)

**Versión:** 0.7 · **Fecha:** 28/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobado (PR #1 y #2). Construidas en pruebas las tablas marcadas con ✅ (Tareas 2 a 10).

> Lo mínimo que necesita la V1 de `ESTADO_DEL_SISTEMA.md` (§12). Lo marcado como **«previsto, no implementado»** es V1.1 y solo figura cuando no añade complejidad.
> ✅ = existe en el proyecto de pruebas (migraciones en `supabase/migrations/`). El resto llega en su tarea.

---

## 1. Principios del modelo

- **Supabase manda en tareas, jornadas y registros. Google Sheets manda en stock, consumos y catálogo** (§9). Por eso **no hay tabla de productos ni de stock**: el catálogo se lee de PRINCIPAL cada vez que hace falta y se guarda una copia fechada de cada lectura (`lecturas_sheets`) solo para trazabilidad.
- **Genérico desde el día 1:** centros, personas, horarios y plantillas son datos, no código. El almacén es una fila de `centros_trabajo`. Las tiendas también se dan de alta como centros (son destinos del reparto), lo que deja preparada la Etapa 2 sin tablas nuevas.
- **Nadie escribe directamente en las tablas** desde las pantallas. Toda escritura pasa por las funciones de `CONTRATOS.md`. Las tablas tienen RLS activado y solo permisos de lectura donde corresponde.
- **Idempotencia por restricciones únicas**, no por disciplina de las pantallas (ver §5).
- **Horas:** todas las marcas de tiempo son `timestamptz`. La fecha de una jornada es la fecha local de `Europe/Madrid`.
- **Tres esquemas:** `public` (tablas y las funciones que publica la API), `motor` (lógica interna; no se publica) y `prueba` (solo para simular en el entorno de pruebas; nadie tiene permiso).

## 2. Mapa de entidades

```
centros_trabajo ─┬─< personas ─< horarios
                 ├─< plantillas_tarea
                 ├─< configuracion (opcional por centro)
                 └─< jornadas ─┬─< tareas ─┬─< tarea_elementos
                               │           ├─< problemas
                               │           └─< incidencias (opcional)
                               ├─< repartos ─< reparto_lineas
                               ├─< eventos_jornada
                               └─< cierres
registro_eventos   (todo lo anterior deja rastro aquí)
lecturas_sheets    (copia fechada de cada lectura de Sheets)
```

## 3. Entidades

### 3.1 `centros_trabajo` ✅
Lugares donde se trabaja o a los que se envía.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| codigo | text único | Identificador estable: `ALMACEN`, `BILBAO`, `GIPUZKOA`… |
| nombre | text | «Almacén», «Bilbao», «Durango»… |
| tipo | `almacen` · `tienda` · `destino` | `destino` = bloque de envío que no es una tienda (GIPUZKOA). |
| nombre_en_sheets | text | Pestaña en `STOCK OSASUN-CLAUDE`. Durango → `LAUDIO`. |
| alias | text[] | Cómo aparece en el texto del reparto. Comparación normalizada (`REGLAS_CALCULO.md` §2.1). |
| activo | bool | |

Carga inicial (decisión del propietario, §5 R1): BILBAO, ALGORTA, DONOSTI, BARAKALDO, RENTERIA, BASAURI, PORTU (Portugalete), cada una con su nombre como alias; **Durango** con alias `DURANGO` y `LAUDIO` (pestaña LAUDIO), **inactiva hasta que abra**; **GIPUZKOA** como destino del envío (pestaña GIPUZKOA, va entero a Rentería por Nacex).

### 3.2 `personas` ✅
Una fila por usuario de Supabase Auth. Sin credenciales compartidas (§3).

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK = `auth.users.id` | |
| nombre | text | |
| rol | `administracion` · `operario` | Los permisos se deciden con este campo en la base de datos. |
| centro_id | FK → centros_trabajo | Centro en el que trabaja. Administración: nulo = todos. |
| telefono | text | El de Administración alimenta el botón de llamada del Pixel. |
| activo | bool | |

### 3.3 `horarios` ✅
Turnos de cada persona por día de la semana (§3: L–J 08:30–13:00 y 15:30–18:30; V 08:30–13:00). Único (persona, día, turno).

| Campo | Tipo | Notas |
| --- | --- | --- |
| persona_id | FK → personas | |
| dia_semana | 1–7 | 1 = lunes. |
| turno | `manana` · `tarde` | |
| hora_inicio, hora_fin | time | |

### 3.4 `plantillas_tarea` ✅
Las tareas del mapa semanal (§4) como configuración. Lista inicial en `PLAN_TECNICO.md` §2.6.

| Campo | Tipo | Notas |
| --- | --- | --- |
| centro_id, codigo | | Único (centro, código). |
| titulo, porque | text | El porqué puede ir vacío en la V1 (su texto es V1.1). |
| programacion | `con_hora` · `dia_semana` · `condicionada` · `cola_libre` | §6.1. |
| dias_semana | smallint[] | |
| turno | `manana` · `tarde` · nulo | Desde cuándo está disponible si no tiene hora. |
| hora_inicio | time | Para `con_hora`. |
| hora_limite | time | «Antes de…». |
| duracion_min | int | Para detectar conflictos (§6.10). |
| condicion | ver abajo | |
| condiciones_extra | text[] | Condiciones de estado que también deben cumplirse (ej. Nacex del viernes: hay envío **y** sale el operario). |
| urgente | bool | Escalón 3 de `tarea_activa` (ej. recepción de mercancía, que se atiende en el momento). |
| requiere_codigo | text | No aparece hasta que esa otra tarea del día esté hecha (ej. el efectivo tras la salida). |
| contenido | `simple` · `produccion_reparto` · `bolsas` · `stock_35` · `recuento` | |
| obligatoria | bool | §6.3. |
| prioridad_cola | `A` · `C` · `D` | Solo cola de tiempo libre. |
| no_terminada | `recalcular` · `sigue_abierta` · `arrastrar` · `nada` | §6.5 (ver §4.6). |
| modo | `autonoma` · `necesita_aprobacion` | §6.9. |
| orden, activa | | |

**Condiciones** (añadir una es una migración):
- **De estado del día** (se evalúan al generar y cuando cambian): `sale_operario`, `sale_administracion`, `hay_envio`, `no_hay_envio`.
- **De algo que pasa** (la tarea se crea cuando pasa): `reparto_pegado`, `envio_pegado`, `llega_mercancia`, `pedido_cliente`, `no_quedan_vapers`.

### 3.5 `jornadas` ✅
Un día de trabajo de una persona. **Único (persona, fecha)**: la jornada se genera una sola vez (§6.2).

| Campo | Tipo | Notas |
| --- | --- | --- |
| persona_id, centro_id, fecha | | |
| sale | `operario` · `administracion` · nulo | De la línea `SALE:`. Nulo = aún no se sabe. |
| hay_envio | bool | Lunes: siempre `true`. Viernes: `true` si el jueves se decidió envío. |
| envio_dia_siguiente | bool | El jueves a las 15:30 se decide el envío del viernes por la mañana (§4). |
| estado | `abierta` · `cerrada` | Pasa a `cerrada` al generarse el cierre de su último turno. |
| generada_en | timestamptz | |
| arrastre_hecho | bool | `false` en una jornada preparada antes de su día (tarea de Administración para otro día): el arrastre se hace al llegar el día (Tarea 4). |

### 3.6 `tareas` ✅
Las tareas concretas de una jornada.

| Campo | Tipo | Notas |
| --- | --- | --- |
| jornada_id, clave | | **Único (jornada, clave)**: clave de idempotencia (§5). |
| origen | `plantilla` · `administracion` · `reparto` · `evento` · `problema` | Una tarea arrastrada conserva su origen. |
| plantilla_id | FK nulo | |
| titulo, porque, contenido, obligatoria, prioridad_cola, orden | | Copiados de la plantilla o escritos por Administración. |
| condicion | text | La de la plantilla (para retirarla si deja de cumplirse). |
| requiere_clave | text | Clave de la tarea del día que debe estar hecha antes. |
| disponible_desde | timestamptz | Su hora, o el inicio de su turno. Antes no aparece. |
| hora_programada | timestamptz | Tareas con hora. |
| hora_limite | timestamptz | «Antes de…». |
| urgente | bool | Tareas de Administración (§6.4). |
| duracion_min | int | Obligatoria en las de Administración (§8, «duración orientativa»); solo sirve para conflictos. |
| no_terminada | | Copiada de la plantilla; las de Administración, `arrastrar`. |
| estado | `pendiente` · `en_curso` · `hecha` · `bloqueada` · `arrastrada` · `cancelada` | §6.5, sin añadir ninguno. |
| retirada_por_condicion | bool | Cancelada porque su condición dejó de cumplirse (ej. ya hay envío: el recuento de las 18:15 se retira). Vuelve si la condición se cumple otra vez. |
| iniciada_en, terminada_en | timestamptz | Hora real. |
| resultado, motivo_no_hecha | text | Para el cierre. |
| tarea_origen_id | FK → tareas | Tarea de la que viene un arrastre. |
| creada_por | FK → personas | Nulo = sistema. |
| id_cliente | uuid único | Para que un reintento al crear no duplique. |
| creada_en | timestamptz | |

Restricciones: único (jornada, clave) · **una sola tarea `en_curso` por jornada** (índice único parcial).

**Tareas de Administración:** filas con `origen = administracion` (no una tabla aparte). La decisión ante un conflicto («qué cede») queda en `registro_eventos`.

`reparto_id` (FK a `repartos`): tareas creadas por el reparto o el envío (Tarea 3).

### 3.7 `tarea_elementos` ✅
Referencias de producción y cajas de cada bolsa.

| Campo | Tipo | Notas |
| --- | --- | --- |
| tarea_id | FK | |
| tipo | `referencia_produccion` · `caja_bolsa` | |
| lote | text | Lista dentro de la tarea: `reparto`, `envio`, o el turno (`manana`/`tarde`) en la de stock. Único (tarea, tipo, lote, destino, producto, formato). |
| producto, formato, categoria | text | Tal como en PRINCIPAL. |
| destino_id | FK → centros_trabajo | Tienda o destino de la bolsa. |
| cantidad, cantidad_hecha | int | `cantidad_hecha` se fija con un valor absoluto (idempotente). |
| motivo | text | Frase de prioridad (R3) o aviso. |
| orden_sugerido | int | El operario decide el orden. |
| calculo | jsonb | Datos usados y `lectura_id`. |
| estado | `pendiente` · `en_curso` · `hecho` | |
| iniciado_en, terminado_en | timestamptz | Base del ritmo de cajas/hora (V1.1, previsto, no implementado). |

### 3.8 `repartos` y `reparto_lineas` ✅
Texto pegado y su interpretación (R1), para el reparto y para el envío.

`repartos`: jornada_id · tipo (`reparto` · `envio`) · texto_original · huella (hash del texto) · fecha_en_texto · sale · estado (`con_errores` · `aceptado` · `sustituido`) · sustituye_a (FK) · lectura_id · resultado (jsonb) · pegado_por · pegado_en · id_cliente (único, Tarea 10). **Un solo aceptado por jornada y tipo**; pegar el mismo texto otra vez devuelve el resultado guardado (huella igual).

Tarea 10 (reparto con lista): `texto_original` es el texto de WhatsApp generado con la lista (el que devuelve `guardar_reparto` como `texto_whatsapp`); `id_cliente` es el de la petición de `guardar_reparto` que lo guardó, para que un reintento devuelva lo mismo sin recalcular.

**Reparto corregido** (decisión del propietario, §5 R1): la versión nueva pasa a `aceptado` y la anterior a `sustituido`. Se recalcula lo que falta producir **sin perder las cajas ya hechas**; las bolsas de tiendas sin cambios se conservan y las que cambian se vuelven a comprobar caja a caja.

`reparto_lineas`: reparto_id · num_linea · texto · clase (`cabecera` · `sale` · `tienda` · `producto` · `vacia` · `no_reconocida`) · destino_id · cantidad · producto · formato · error.

### 3.9 `eventos_jornada` ✅ (Tarea 4, con `registrar_evento`)
Lo que pasa «en cualquier momento» (§4): `llega_mercancia` · `pedido_cliente` · `no_quedan_vapers`. jornada_id · tipo · detalle · tarea_id (la tarea que creó) · registrado_por · registrado_en · id_cliente único. El **pedido de cliente** lo registra quien lo recibe: el operario con su botón o Administración como tarea nueva (§4).

### 3.10 `problemas` ✅ (Tarea 4)
Botón «Tengo un problema» (§6.6): jornada_id · tarea_id · persona_id · tipo (`falta_material` · `no_encuentro` · `no_se_hacerlo` · `no_funciona` · `otro`) · descripcion · estado (`abierto` · `sin_respuesta` · `resuelto`) · abierto_en · llamada_en · llamadas · whatsapp_en · proxima_llamada_en (**WhatsApp + 30 min**, decidido; configurable en `problema_minutos_reaparicion`) · solucion · resuelto_en · resuelto_por · id_cliente. **Un solo problema abierto por tarea** (índice único parcial). La tarea «Llama a Administración» es una tarea de la jornada con origen `problema` y clave `problema:<id>:<n.º de llamada>`.

Previsto, no implementado (V1.1): la «solución directa» para `falta_material` saldrá del catálogo de materiales.

### 3.11 `incidencias` ✅ (Tarea 4)
Botón «Incidencia»: jornada_id · persona_id · tarea_id (la que estaba en curso) · descripcion · iniciada_en · terminada_en (cuándo se cerró) · id_cliente.
**Tarea 7 (§6.6 v1.17):** opcion (`llega_mercancia` · `pedido_cliente` · `pedir_comprar` · `recogida_nacex` · `corregir`; vacía en las de antes) · quien (`operario` | `administracion`) · importancia (`ahora` | `hoy` | `cuando_pueda`) · estado (`abierta` · `esperando_llegada` · `esperando_administracion` · `cerrada`) · tarea_resolucion_id (la tarea creada para resolverla) · nota_cierre · cerrada_por. Puede haber varias abiertas por persona (las de antes, solo una). Un disparador en `tareas` la cierra al hacerse su tarea (las compras pasan a `esperando_llegada`), y lo que se arrastra sigue apuntando a la tarea nueva. «Estoy bloqueado» no crea fila aquí: es un `problema`.

### 3.12 `cierres` ✅ (Tarea 4)
**Uno por turno** (D2): jornada_id · turno · contenido (jsonb congelado) · generado_en · envio_reclamado_en (el envío se reclama una sola vez: nunca dos correos) · enviado_en · canal (**correo**, D3) · error_envio. Único (jornada, turno).
Su correo se sigue en `motor.correos` (§3.16 bis).
Contenido: hecho y resultado; no hecho y motivo; problemas (tiempo y solución); incidencias (tiempo); arrastrados; retrasos de la salida cruzados con las cajas del reparto y las incidencias de la mañana; lo de mañana; los viernes, el indicador de calidad (**solo «limpieza hecha»**; los papeles de resinas quedan fuera de la V1).

### 3.13 `configuracion` ✅
clave · centro_id (nulo = general) · valor jsonb. Único (clave, centro) también con centro nulo.

Claves cargadas en la Tarea 2: `hora_generacion_jornada` ("06:00"), `duracion_min_por_caja` (1), `duracion_min_por_bolsa` (3). Tarea 4: `problema_minutos_reaparicion` (30), `correo_remitente`. Tarea 5: `correo_max_intentos` (3), `correo_minutos_reintento` (5); en pruebas, `cierres_sin_correo` (el operario ficticio desde el 03/11/2026). Solo en cada entorno, nunca en el repositorio: `entorno` ("pruebas"), `url_proyecto`, `correo_administracion` (destino de los cierres y avisos), `cuentas_autorizadas` (quién puede entrar, con su rol, centro y horario), `operario_por_defecto` y `telefono_administracion`. El resto (35 %, redondeo, minis, minutos de problemas, Sheets) llega con su tarea. Tarea 10: `destinos_reparto` = `{ reparto: [BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU], envio: [GIPUZKOA, DURANGO] }` (qué tiendas se eligen al preparar el reparto o el envío y en qué orden, el de las hojas de STOCK OSASUN).

### 3.14 `registro_eventos` ✅
Diario de todo lo que pasa (principio 7). Solo se añade. ocurrido_en · persona_id (nulo = sistema) · jornada_id · tarea_id · tipo · datos.
Tipos en uso: `jornada_generada`, `jornada_preparada`, `tarea_creada`, `tarea_retirada`, `tarea_recuperada`, `tarea_arrastrada`, `tarea_cancelada`, `sale_fijado`, `envio_fijado`, `tarea_iniciada`, `tarea_terminada`, `tarea_pausada`, `motivo_anotado`, `problema_abierto`, `problema_llamada`, `problema_resuelto`, `incidencia_iniciada`, `incidencia_terminada`, `evento_registrado`, `salida_retrasada`, `conflicto_decidido`, `cierre_generado`, `correo_encolado`, `correo_reclamado`, `correo_enviado`, `correo_fallido`.

### 3.15 `lecturas_sheets` ✅
Cada lectura de `STOCK OSASUN-CLAUDE` ya interpretada: leido_en · motivo (`reparto` · `envio` · `stock`) · persona_id · correcto · error · datos. Solo deja constancia de con qué datos se calculó cada cosa.

### 3.16 `motor.solicitudes_servidor` ✅
Solicitudes internas de un solo uso (caducan a los 5 minutos) para llamar a las funciones del servidor desde la base de datos sin claves (pruebas y, en la Tarea 4, tareas programadas). No se publica en la API; RLS con política que no deja ver nada a ningún usuario.

### 3.16 bis `motor.correos` ✅ (Tarea 5)
Un correo por cierre o aviso de retraso: tipo · ref · estado (`pendiente` → `enviando` → `enviado`; si Resend lo rechaza, `reintentar` a los 5 min hasta 3 intentos y después `fallido`; sin respuesta a tiempo, `dudoso`, sin reintento) · intentos · proximo_intento_en · asunto · ultimo_error · enviado_en. Único (tipo, ref): nunca dos correos del mismo cierre. Interna (RLS sin acceso); los fallidos y dudosos se ven en `estado_actual`.

### 3.17 Acceso (Tarea 5) ✅
Solo con Google y solo las cuentas de `cuentas_autorizadas`: el hook de Supabase Auth impide crear el usuario de cualquier otra. Al crearse el usuario de una cuenta autorizada se crea su `personas` (mismo id que el usuario) con su rol, centro y horario.

## 4. Estados

### 4.1 Tarea
```
pendiente ──iniciar──▶ en_curso ──terminar──▶ hecha
   ▲  │                  │  │
   │  │                  │  └─ llega una tarea con hora/urgente al terminar
   │  │                  │     la referencia o la bolsa (tienda) en curso ──▶ pendiente (conserva lo hecho)
   │  │                  └──abrir problema──▶ bloqueada ──resolver──▶ pendiente
   │  ├──cancelar (Administración)──▶ cancelada
   │  └──su condición deja de cumplirse──▶ cancelada (retirada_por_condicion; vuelve si se cumple otra vez)
   └──── al generar el día siguiente, si no_terminada = arrastrar/sigue_abierta ──▶ arrastrada
                                              y se crea una copia en la nueva jornada
```
- `hecha` y `arrastrada` son finales; `cancelada` también, salvo la retirada por condición.
- Solo se termina una tarea en curso. Una tarea con lista queda `hecha` sola cuando todos sus elementos están `hecho`; antes, solo si el operario la termina indicando motivo.

### 4.2 Elemento: `pendiente → en_curso → hecho`. Solo un elemento `en_curso` por tarea.
### 4.3 Problema: `abierto → (sin_respuesta) → resuelto`. «Resuelto» exige una línea de solución.
### 4.4 Jornada: `abierta → cerrada` (al generarse el último cierre del día).
### 4.5 Reparto: `con_errores` (no genera tareas) · `aceptado` · `sustituido` (por una versión corregida).

### 4.6 Lo no terminado (§6.5, decidido)
| Política | Qué pasa al día siguiente | Plantillas |
| --- | --- | --- |
| `arrastrar` | Pasa como arrastrada y consta en el cierre con su motivo | Minis, resinas, control de materiales, limpieza de resinas, recepción, pedido de cliente, vapers, tareas de Administración |
| `sigue_abierta` | Igual, hasta que confirma que lo tiene | Compras y recogidas (V1.1) |
| `recalcular` | No pasa: se vuelve a calcular | Stock (+35 %) |
| `nada` | No pasa: consta en el cierre como no hecha | Ligadas a hora o turno: recuentos, Nacex, salida, efectivo, revisión, reparto del día, bolsas |

## 5. Idempotencia (cómo se garantiza «no duplica nada»)

| Situación | Garantía | Probado |
| --- | --- | --- |
| Generar la jornada dos veces (programada + apertura, dos pestañas) | Único (persona, fecha) + candado por persona y fecha; único (jornada, clave) | ✅ 02, 06 |
| Dos llamadas a la vez | El candado hace esperar a la segunda, que devuelve la misma jornada | ✅ 06 |
| Repetir una condición (SALE:, envío, reparto, evento) | La clave de la tarea es el código (más un sufijo por evento) | ✅ 02 |
| Repetir «crear», «abrir problema», «incidencia», «evento», «retrasar» | `id_cliente` único (y candado al crear una tarea de Administración) | ✅ 09, 10 |
| Generar el cierre de un turno dos veces | Único (jornada, turno) + candado; la tarea programada solo cierra turnos sin cierre | ✅ 10 |
| Enviar el correo de un cierre o aviso dos veces | Se reclama una sola vez (`envio_reclamado_en` o registro `correo_reclamado`) | ✅ 10 |
| Pulsar dos veces «iniciar» o «Terminada» | Cambios condicionados al estado; la segunda devuelve lo ya hecho | ✅ 02 |
| Tocar una caja dos veces | `cantidad_hecha` se fija con un valor absoluto | ✅ 07 |
| Pegar el mismo reparto dos veces | Huella del texto; un solo aceptado por jornada y tipo | ✅ 07 |
| Pedir la lista de stock dos veces en el turno | Un lote por turno; candado por jornada | ✅ 07 |
| Dos tareas activas a la vez | Índice único parcial | ✅ 02 |
| Arrastrar dos veces | Clave `arrastre:<id de la original>` | ✅ 03 |

## 6. Permisos (detalle en `PLAN_TECNICO.md` §5)

| Tabla | Operario | Administración |
| --- | --- | --- |
| centros_trabajo | Lee todos (son los destinos de las bolsas) | Lee todos |
| plantillas_tarea, configuracion | Lee las de su centro (y la configuración general) | Lee todo |
| personas, horarios | Solo los suyos | Lee todo |
| jornadas, tareas (y en sus tareas: elementos, repartos, eventos, problemas, incidencias) | Solo lo de **su** jornada | Lee todo |
| cierres, registro_eventos, lecturas_sheets | Nada | Lee todo |

Escritura directa en tablas: **nadie** (ni operario ni Administración). Sin sesión (`anon`): nada. Probado en las pruebas 04, 08 y 11.

## 7. Dudas del modelo

1. **Durango:** la he dado de alta **inactiva** porque «irá como bloque propio cuando abra». ¿Correcto, o ya aparece en los repartos?
