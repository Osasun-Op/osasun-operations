# OSASUN OPERATIONS — Modelo de datos (propuesta V1)

**Versión:** 0.1 (propuesta, pendiente de aprobación) · **Fecha:** 26/10/2026 · **Autor:** agente de base de datos · **Tarea:** 1

> Documento de diseño. No hay nada construido. Todo lo que aquí aparece es lo mínimo que necesita la V1 de `ESTADO_DEL_SISTEMA.md` (§12).
> Lo marcado como **«previsto, no implementado»** es V1.1 y solo figura cuando no añade complejidad (un campo vacío, un valor de estado).

---

## 1. Principios del modelo

- **Supabase manda en tareas, jornadas y registros. Google Sheets manda en stock, consumos y catálogo** (§9). Por eso **no hay tabla de productos ni de stock**: el catálogo se lee de PRINCIPAL cada vez que hace falta y se guarda una copia fechada de cada lectura (`lecturas_sheets`) solo para trazabilidad.
- **Genérico desde el día 1:** centros, personas, horarios y plantillas son datos, no código. El almacén es una fila de `centros_trabajo`. Las tiendas también se dan de alta como centros (las necesitamos como destinos del reparto), lo que deja preparada la Etapa 2 sin tablas nuevas.
- **Nadie escribe directamente en las tablas** desde las pantallas. Toda escritura pasa por las funciones de `CONTRATOS.md`. Las tablas tienen RLS activado y solo permisos de lectura donde corresponde.
- **Idempotencia por restricciones únicas**, no por disciplina de las pantallas (ver §5).
- **Horas:** todas las marcas de tiempo son `timestamptz`. La fecha de una jornada es la fecha local de `Europe/Madrid`.

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

13 tablas en total. No hay más.

## 3. Entidades

### 3.1 `centros_trabajo`
Lugares donde se trabaja o a los que se envía.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| nombre | text | «Almacén», «Bilbao», «Durango»… |
| tipo | enum `almacen` · `tienda` | |
| nombre_en_sheets | text | Nombre de la pestaña/columna en `STOCK OSASUN-CLAUDE`. Ej.: Durango → `LAUDIO` (§9: «la app debe tratar LAUDIO como Durango»). |
| alias | text[] | Otras formas en que aparece en el texto del reparto. Ej.: Durango → `{DURANGO, LAUDIO}`. Comparación normalizada (§3 de `REGLAS_CALCULO.md`). |
| activo | bool | |

Carga inicial: Almacén y las tiendas que aparecen en Sheets (BILBAO, ALGORTA, DONOSTI, BARAKALDO, RENTERIA, BASAURI, LAUDIO→Durango, PORTU, GIPUZKOA). Los alias exactos están en las dudas (§7).

### 3.2 `personas`
Una fila por usuario de Supabase Auth. Sin credenciales compartidas (§3).

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK = `auth.users.id` | |
| nombre | text | |
| rol | enum `administracion` · `operario` | Los permisos se deciden con este campo en la base de datos. |
| centro_id | uuid FK → centros_trabajo | Centro en el que trabaja (el operario, el almacén). Administración: nulo = todos. |
| telefono | text | El de Administración se usa para el botón de llamada del Pixel. |
| activo | bool | |

### 3.3 `horarios`
Turnos de cada persona por día de la semana (§3: L–J 08:30–13:00 y 15:30–18:30; V 08:30–13:00).

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| persona_id | FK → personas | |
| dia_semana | smallint 1–7 | 1 = lunes. |
| turno | enum `manana` · `tarde` | |
| hora_inicio, hora_fin | time | |

Único: (persona_id, dia_semana, turno).

### 3.4 `plantillas_tarea`
Las tareas del mapa semanal (§4) convertidas en configuración. De aquí sale la jornada de cada día.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| centro_id | FK | |
| codigo | text único | Identificador estable: `recuento_manana`, `minis`, `nacex_salida`… |
| titulo | text | Lo que ve el operario. |
| porque | text | Una frase (§8). Puede estar vacía en la V1; el texto definitivo es V1.1. |
| programacion | enum `con_hora` · `dia_semana` · `condicionada` · `cola_libre` | Tipos de §6.1. Las «lanzadas por Administración» no tienen plantilla. |
| dias_semana | smallint[] | Días en que aplica. |
| turno | enum `manana` · `tarde` | |
| hora_inicio | time nulo | Para `con_hora`. |
| hora_limite | time nulo | «Antes de…» (ej. producción antes de la salida, Nacex antes de 18:10). |
| duracion_min | int nulo | Duración prevista, para detectar conflictos (§6.4). Ej.: recuento 15. |
| condicion | enum nulo | `sale_operario` · `sale_administracion` · `hay_envio` · `no_hay_envio` · `reparto_pegado` · `envio_pegado` · `llega_mercancia` · `pedido_cliente` · `no_quedan_vapers`. Solo estos valores; añadir uno es una migración. |
| contenido | enum | `simple` · `produccion_reparto` · `bolsas` · `stock_35` · `recuento`. Indica si la tarea lleva elementos y cómo se calculan. |
| obligatoria | bool | §6.3: es un ajuste de cada tarea. |
| prioridad_cola | enum nulo `A` · `C` · `D` | Solo para `cola_libre` (§4, cola de tiempo libre). |
| no_terminada | enum `recalcular` · `sigue_abierta` · `arrastrar` · `nada` | §6.5. Stock = `recalcular`; compras/recogidas = `sigue_abierta`; ver duda §7 para las obligatorias. |
| modo | enum `autonoma` · `necesita_aprobacion` | §6.9. En la V1 las aprobaciones siguen por WhatsApp; el campo solo deja preparado el cambio a «las hace él solo». |
| orden | int | Desempate entre tareas del mismo momento. |
| activa | bool | |

La lista inicial de plantillas está en `PLAN_TECNICO.md` §2.6.

### 3.5 `jornadas`
Un día de trabajo de una persona.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| persona_id, centro_id | FK | |
| fecha | date | Fecha local. |
| sale | enum nulo `operario` · `administracion` | De la línea `SALE:` (R1). Nulo = aún no se sabe. |
| hay_envio | bool | Envío a Gipuzkoa/Durango aprobado ese día. El lunes empieza a `true` (§4: «el lunes siempre hay envío»). |
| estado | enum `abierta` · `cerrada` | |
| generada_en | timestamptz | |

**Único: (persona_id, fecha).** Es la garantía de que la jornada se genera una sola vez (§6.2).

### 3.6 `tareas`
Las tareas concretas de una jornada, vengan de una plantilla, de Administración o de un evento.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| jornada_id | FK | |
| clave | text | Clave de idempotencia dentro de la jornada (ver §5). |
| origen | enum `plantilla` · `administracion` · `reparto` · `evento` · `problema` · `arrastre` | |
| plantilla_id | FK nulo | |
| titulo, porque | text | Copiados de la plantilla o escritos por Administración. |
| contenido | enum | Igual que en la plantilla. |
| obligatoria | bool | |
| prioridad_cola | enum nulo | |
| hora_programada | timestamptz nulo | Tareas con hora. |
| hora_limite | timestamptz nulo | «Antes de…». |
| urgente | bool | Solo tareas de Administración (§6.4). |
| duracion_min | int nulo | |
| estado | enum | `pendiente` · `en_curso` · `hecha` · `bloqueada` · `arrastrada` · `cancelada` (§6.5, sin añadir ninguno). |
| iniciada_en, terminada_en | timestamptz nulo | Hora real (§6.4: «si empieza tarde, se registra la hora real»). |
| resultado | text nulo | Lo hecho y su resultado, para el cierre. |
| motivo_no_hecha | text nulo | Para el cierre. |
| tarea_origen_id | FK → tareas nulo | Tarea de la que viene un arrastre. |
| reparto_id | FK nulo | Tareas generadas por un reparto/envío. |
| creada_por | FK → personas nulo | Nulo = sistema. |
| id_cliente | uuid nulo, único | Lo manda la pantalla al crear una tarea de Administración: un reintento no duplica. |
| creada_en | timestamptz | |

**Tareas de Administración:** son filas de `tareas` con `origen = administracion` (no una tabla aparte). Llevan `urgente`, `hora_limite` u `hora_programada`, `porque` opcional y `creada_por`. La decisión tomada ante un conflicto («qué cede») se guarda en `registro_eventos`.

Restricciones:
- Único (jornada_id, clave).
- **Una sola tarea `en_curso` por jornada** (índice único parcial). Dos pestañas no pueden tener dos tareas activas.

### 3.7 `tarea_elementos`
Las piezas de una tarea con lista: referencias de producción y cajas de cada bolsa.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| tarea_id | FK | |
| tipo | enum `referencia_produccion` · `caja_bolsa` | |
| producto, formato | text | Tal como están en PRINCIPAL (el formato puede ir vacío en productos sin formato). |
| categoria | text nulo | Invernadero, Indoor… (para R3 por categoría). |
| destino_id | FK → centros_trabajo nulo | Tienda de la bolsa. |
| cantidad | int | Cajas a hacer o a meter. |
| cantidad_hecha | int | Cajas hechas o metidas. Se fija con un valor absoluto, nunca se suma (idempotente). |
| motivo | text nulo | Frase de prioridad (R3) o aviso (ej. «sin granel»). |
| orden_sugerido | int | El operario elige el orden; esto solo es la sugerencia (§8). |
| calculo | jsonb | Datos usados en el cálculo (pedido, en almacén, consumo, contador…) y la `lectura_id`. Permite comprobar cada número. |
| estado | enum `pendiente` · `en_curso` · `hecho` | |
| iniciado_en, terminado_en | timestamptz nulo | Base del ritmo de cajas/hora (V1.1, previsto, no implementado: no requiere nada más). |

### 3.8 `repartos` y `reparto_lineas`
El texto pegado y su interpretación (R1). Sirve tanto para el reparto de la mañana como para el envío a Gipuzkoa/Durango.

`repartos`

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| jornada_id | FK | |
| tipo | enum `reparto` · `envio` | |
| texto_original | text | Íntegro, tal cual se pegó. |
| huella | text | Hash del texto normalizado: pegar dos veces lo mismo no duplica. |
| fecha_en_texto | date nulo | De la línea `REPARTO dd/mm`. |
| sale | enum nulo | De la línea `SALE:` o de la respuesta del operario. |
| estado | enum `con_errores` · `aceptado` · `sustituido` | |
| lectura_id | FK → lecturas_sheets | Datos de Sheets con los que se calculó. |
| pegado_por, pegado_en | | |

Único: (jornada_id, tipo, huella).

`reparto_lineas`

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| reparto_id | FK | |
| num_linea | int | Línea del texto original. |
| texto | text | Línea original. |
| clase | enum `cabecera` · `sale` · `tienda` · `producto` · `vacia` · `no_reconocida` | |
| destino_id | FK nulo | Tienda bajo la que está la línea. |
| cantidad | int nulo | |
| producto, formato | text nulo | Nombre del catálogo reconocido. |
| error | text nulo | Código de error de `REGLAS_CALCULO.md` §2.6. |

### 3.9 `eventos_jornada`
Lo que pasa «en cualquier momento» (§4) y activa tareas condicionadas: llega mercancía, pedido de cliente, no quedan vapers.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| jornada_id | FK | |
| tipo | enum `llega_mercancia` · `pedido_cliente` · `no_quedan_vapers` | |
| detalle | text | Una línea. |
| registrado_por, registrado_en | | |
| id_cliente | uuid único | Reintentos sin duplicar. |

### 3.10 `problemas`
Botón «Tengo un problema» (§6.6).

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| jornada_id, tarea_id | FK | La tarea pasa a `bloqueada` mientras el problema está abierto. |
| tipo | enum `falta_material` · `no_encuentro` · `no_se_hacerlo` · `no_funciona` · `otro` | |
| descripcion | text | |
| estado | enum `abierto` · `sin_respuesta` · `resuelto` | `sin_respuesta` = llamó, no le cogieron y envió WhatsApp. |
| abierto_en | timestamptz | |
| llamada_en | timestamptz nulo | |
| whatsapp_en | timestamptz nulo | |
| proxima_llamada_en | timestamptz nulo | `whatsapp_en + 30 min` (configurable). Cuando se alcanza, vuelve a aparecer la tarea de llamar. |
| solucion | text nulo | Una línea. Obligatoria para resolver. |
| resuelto_en | timestamptz nulo | |
| id_cliente | uuid único | |

Previsto, no implementado (V1.1): la «solución directa» de la app para `falta_material` saldrá del catálogo de materiales.

### 3.11 `incidencias`
Botón «Incidencia» (§6.6): imprevisto de más de 3 minutos.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| jornada_id | FK | |
| tarea_id | FK nulo | Tarea que estaba en curso. |
| descripcion | text | Qué es y por qué, en una línea. |
| iniciada_en, terminada_en | timestamptz | |
| id_cliente | uuid único | |

### 3.12 `cierres`
El resumen que llega al móvil de Administración.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| jornada_id | FK | |
| turno | enum nulo | Nulo = cierre del día completo. Permite cualquiera de las dos opciones de la decisión D2 sin cambiar la tabla. |
| contenido | jsonb | Copia congelada: hecho y resultado, no hecho y motivo, problemas (tiempo y solución), incidencias (tiempo), arrastrados, lo de mañana y, el viernes, el indicador de calidad. |
| generado_en | timestamptz | |
| enviado_en | timestamptz nulo | |
| canal | text nulo | Según D3. |

Único: (jornada_id, turno).

### 3.13 `configuracion`
Valores ajustables sin tocar código.

| Campo | Tipo | Notas |
| --- | --- | --- |
| clave | text | |
| centro_id | FK nulo | Nulo = general. |
| valor | jsonb | |

Claves de la V1: `stock_objetivo_pct` (35), `redondeo_stock` (según D1), `problema_minutos_llamar` (1), `problema_minutos_solucion` (5), `problema_minutos_reaparicion` (30), `incidencia_minutos_minimos` (3), `sheets_documento_id`, `sheets_pestanas` (nombres confirmados, ver `PLAN_TECNICO.md` §3.2), `hora_generacion_jornada`, `minis_excluidos` (referencias fuera de R3).

Único: (clave, centro_id).

### 3.14 `registro_eventos`
Diario de todo lo que pasa (trazabilidad, principio 7). Solo se añade; nunca se modifica ni se borra.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | bigint PK | |
| ocurrido_en | timestamptz | |
| persona_id | FK nulo | Nulo = sistema (tareas programadas). |
| jornada_id, tarea_id | FK nulo | |
| tipo | text | `tarea_iniciada`, `tarea_terminada`, `elemento_terminado`, `tarea_desplazada`, `conflicto_decidido`, `reparto_pegado`, `lectura_sheets_fallida`… |
| datos | jsonb | Antes/después y parámetros. |

### 3.15 `lecturas_sheets`
Cada lectura de `STOCK OSASUN-CLAUDE`, ya interpretada.

| Campo | Tipo | Notas |
| --- | --- | --- |
| id | uuid PK | |
| leido_en | timestamptz | |
| motivo | text | `reparto`, `stock_35`… |
| correcto | bool | |
| error | text nulo | Qué falló (red, permiso, estructura de la hoja cambiada…). |
| datos | jsonb | Catálogo, cajas en almacén, granel, contador y consumo por referencia y categoría. |

No es una copia del stock para trabajar con ella: solo deja constancia de con qué datos se calculó cada cosa.

## 4. Estados

### 4.1 Tarea
```
pendiente ──iniciar──▶ en_curso ──terminar──▶ hecha
   ▲  │                  │  │
   │  │                  │  └─ llega una tarea con hora/urgente al terminar
   │  │                  │     la referencia o bolsa en curso ──▶ pendiente (conserva lo hecho)
   │  │                  └──abrir problema──▶ bloqueada ──resolver──▶ pendiente
   │  └──cancelar (solo Administración)──▶ cancelada
   └──── (al día siguiente, si no_terminada = arrastrar/sigue_abierta) ──▶ arrastrada
                                              y se crea una copia en la nueva jornada
```
- `hecha`, `cancelada` y `arrastrada` son finales.
- Una tarea con lista no se da por `hecha` hasta que todos sus elementos están `hecho`, salvo que el operario la termine indicando motivo (ver `CONTRATOS.md` §3.3).

### 4.2 Elemento: `pendiente → en_curso → hecho`. Solo un elemento `en_curso` por tarea.

### 4.3 Problema: `abierto → (sin_respuesta) → resuelto`. «Resuelto» exige una línea de solución.

### 4.4 Jornada: `abierta → cerrada` (al generarse el último cierre del día).

### 4.5 Reparto: `con_errores` (no genera tareas) · `aceptado` (genera tareas) · `sustituido` (ver duda §7).

## 5. Idempotencia (cómo se garantiza «no duplica nada»)

| Situación | Garantía |
| --- | --- |
| Generar la jornada dos veces (tarea programada + primera apertura, dos pestañas) | Único (persona_id, fecha) en `jornadas` y (jornada_id, clave) en `tareas`. La clave de una tarea de plantilla es su `codigo`. |
| Pegar el mismo reparto dos veces | Único (jornada_id, tipo, huella) en `repartos`. Las tareas que genera tienen clave `reparto:<id>:produccion` y `reparto:<id>:bolsas`. |
| Repetir «crear tarea», «abrir problema», «incidencia» por un corte de red | `id_cliente` único generado por la pantalla. |
| Pulsar dos veces «Terminada» o «iniciar» | Cambios de estado condicionados al estado actual; la segunda llamada devuelve el estado ya alcanzado sin error. |
| Tocar una caja dos veces | `cantidad_hecha` se fija con el valor absoluto que manda la pantalla. |
| Dos tareas activas a la vez | Índice único parcial: una sola `en_curso` por jornada. |

## 6. Permisos (resumen; detalle en `PLAN_TECNICO.md` §5)

| Tabla | Operario | Administración |
| --- | --- | --- |
| centros_trabajo, plantillas_tarea, horarios, configuracion | Lee lo de su centro | Lee todo |
| jornadas, tareas, tarea_elementos, repartos, reparto_lineas, eventos_jornada, problemas, incidencias | Lee solo lo de **su** jornada | Lee todo |
| cierres, registro_eventos, lecturas_sheets | Nada | Lee todo |
| personas | Solo su propia fila | Lee todo |

Escritura directa en tablas: **nadie** (ni operario ni Administración). Solo mediante funciones. La clave maestra solo la usan las funciones del servidor.

## 7. Dudas del modelo

1. **Alias de tiendas en el texto del reparto:** ¿cómo escribe Administración cada tienda? (ej. «PORTU» o «PORTUGALETE», «DONOSTI» o «SAN SEBASTIÁN», «DURANGO» o «LAUDIO»). Necesito la lista exacta.
2. **Destinos del envío a Gipuzkoa/Durango:** ¿el texto lleva cabeceras DONOSTI, RENTERIA, GIPUZKOA y DURANGO, o solo «GIPUZKOA» y «DURANGO»? ¿Qué es la pestaña GIPUZKOA de Sheets respecto a DONOSTI y RENTERIA?
3. **Tareas obligatorias de plantilla que no se terminan** (ej. minis del lunes): §6.5 no lo dice. ¿Se arrastran al día siguiente o solo constan en el cierre como no hechas?
4. **Volver a pegar un reparto distinto el mismo día** (Administración lo corrige): ¿se sustituye el anterior? Si ya hay bolsas empezadas, ¿qué pasa con lo hecho?
5. **Pedido de cliente:** ¿lo registra el operario (evento) o lo lanza Administración como tarea?
