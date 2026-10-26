# OSASUN OPERATIONS — Contratos entre la base de datos y las pantallas (V1)

**Versión:** 0.3 · **Fecha:** 26/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobado (PR #1 y #2). ✅ = publicado en el proyecto de pruebas (Tareas 2 y 3).

> Esto es lo único que las pantallas (Lovable) pueden usar. Cualquier dato o función nueva se pide al coordinador (§11 de `ESTADO_DEL_SISTEMA.md`).

---

## 1. Reglas comunes

- **Dos tipos de llamada:**
  - **Funciones de base de datos** (`supabase.rpc('nombre', {...})`): todo lo que no necesita Google Sheets.
  - **Funciones del servidor** (`supabase.functions.invoke('nombre', {...})`): las que leen Sheets (`pegar_reparto` y `lista_stock`).
- Los **nombres de los parámetros** son los de este documento (ej. `supabase.rpc('iniciar_tarea', { tarea_id })`).
- Las pantallas usan **solo la clave pública** y la sesión del usuario. El rol se comprueba dentro de cada función; esconder un botón no da ni quita permisos.
- **Hora:** la decide el servidor. Las pantallas nunca envían «ahora».
- **Respuesta:** JSON. Si hay error: `{ "error": { "codigo": "...", "mensaje": "frase para mostrar" } }`. El mensaje está en castellano y se puede enseñar tal cual.
- **Reintentos:** las funciones que crean algo aceptan `id_cliente` (uuid generado por la pantalla). Repetir la misma llamada devuelve el mismo resultado sin duplicar.
- **Cambios en directo:** las pantallas pueden suscribirse (Supabase Realtime) a `tareas`; la base de datos solo les deja ver lo que su rol puede leer. Así una tarea nueva le aparece al Pixel durante el reparto (§6.7). Se activa en la tarea en que se haga la primera pantalla que lo necesite.

### Errores comunes a todas las funciones

| Código | Cuándo |
| --- | --- |
| `NO_AUTENTICADO` | Sin sesión. (Sin sesión, la API ni siquiera deja llamar a las funciones.) |
| `NO_AUTORIZADO` | El rol no puede usar esta función, o el usuario no tiene ficha de persona activa. |
| `NO_ENCONTRADO` | El id no existe o no es de ese usuario. |
| `ESTADO_NO_VALIDO` | La acción no tiene sentido en el estado actual (ej. terminar una tarea que no está en curso). |
| `DATOS_NO_VALIDOS` | Falta un campo obligatorio o tiene un valor no permitido. |

## 2. Resumen

| Función | Tipo | Operario | Administración | Estado |
| --- | --- | --- | --- | --- |
| `mi_perfil` | BD | ✔ | ✔ | ✅ Tarea 2 |
| `tarea_activa` | BD | ✔ | — | ✅ Tarea 2 |
| `iniciar_tarea` · `terminar_tarea` · `anotar_motivo` | BD | ✔ | — | ✅ Tarea 2 |
| `iniciar_elemento` · `terminar_elemento` · `marcar_cajas` | BD | ✔ | — | ✅ Tarea 3 |
| `pegar_reparto` · `lista_stock` | Servidor | ✔ | ✔ (`lista_stock`, consulta) | ✅ Tarea 3 |
| `retrasar_salida` | BD | ✔ | — | Pendiente (no estaba en la Tarea 3) |
| `registrar_evento` | BD | ✔ | ✔ | Pendiente (no estaba en la Tarea 3) |
| `abrir_problema` · `problema_llamada` · `resolver_problema` | BD | ✔ | ✔ (`resolver_problema`) | Tarea 4 |
| `iniciar_incidencia` · `terminar_incidencia` | BD | ✔ | — | Tarea 4 |
| `crear_tarea_admin` · `cancelar_tarea` · `estado_actual` | BD | — | ✔ | Tarea 4 |
| `cierre` · `cierres_recientes` | BD | — | ✔ | Tarea 4 |
| `generar_jornada` · `generar_cierre` | Internas | — | — | `generar_jornada` ✅ |

## 3. Operario

### 3.1 `mi_perfil()` ✅
- **Salida:** `{ id, nombre, rol, centro: {id, nombre} | null, telefono_administracion }`
- `telefono_administracion` alimenta el botón de llamada del Pixel.

### 3.2 `tarea_activa()` ✅
Lo que muestra el Chromebook (y el Pixel). Si la jornada de hoy no existe, la genera (idempotente).
- **Entrada:** ninguna.
- **Salida:**
```json
{
  "jornada": { "id": "...", "fecha": "2026-11-03", "sale": "operario|administracion|null", "hay_envio": false },
  "pregunta": null,
  "tarea": {
    "id": "...", "clave": "produccion_reparto", "titulo": "...", "porque": null,
    "estado": "pendiente|en_curso", "origen": "plantilla|administracion|reparto|evento|problema",
    "obligatoria": true, "urgente": false, "contenido": "simple|produccion_reparto|bolsas|stock_35|recuento",
    "hora_programada": null, "hora_limite": "2026-11-03T09:45:00+00:00", "duracion_min": null,
    "arrastrada_de": null, "iniciada_en": null, "terminada_en": null,
    "elementos": []
  },
  "siguiente": "Salida del reparto · 10:45"
}
```
- `jornada` es `null` si hoy no trabaja; `tarea` es `null` si ahora no hay nada que hacer (antes del turno, entre turnos).
- `siguiente`: una línea con lo que viene después. Si antes llega una tarea con hora, se anuncia esa con su hora.
- `pregunta`: reservado; hoy siempre `null`. La pregunta «¿Quién sale hoy?» la devuelve `pegar_reparto` (`FALTA_SALE`).
- `elementos` ✅: `[ { id, tipo, producto, formato, categoria, destino, destino_id, cantidad, cantidad_hecha, motivo, orden_sugerido, estado } ]`. En bolsas, agrupar por `destino` (una tienda por pantalla).
- La elección sigue `PLAN_TECNICO.md` §2.3. **Nunca devuelve avisos de tiempo ni de presión** (§6.7): solo tareas.
- Solo para el operario: Administración recibe `NO_AUTORIZADO`.

### 3.3 `iniciar_tarea(tarea_id)` · `terminar_tarea(tarea_id, resultado?, motivo?)` ✅
- `iniciar_tarea`: pendiente → en_curso. Guarda la hora real. Solo tareas de hoy.
  - Repetirla sobre la misma tarea no es error: devuelve la tarea en curso con la hora de la primera vez.
  - `OTRA_TAREA_EN_CURSO` si hay otra en curso (devuelve cuál en `tarea_en_curso`).
- `terminar_tarea`: en_curso → hecha. `resultado` (texto corto, opcional) va al cierre.
  - Repetirla no es error: devuelve la tarea con su primer final.
  - `ESTADO_NO_VALIDO` si no está en curso.
  - Si la tarea tiene elementos sin terminar: `ELEMENTOS_PENDIENTES` (con `pendientes`), salvo que se mande `motivo`. ✅
  - Una tarea con lista se cierra sola cuando se termina su último elemento; no hace falta pulsar «Terminada».
- **Salida (ambas):** `{ "tarea": {...}, "tarea_activa": {...} }` (la nueva respuesta de `tarea_activa`).

### 3.4 `anotar_motivo(tarea_id, motivo)` ✅
Para que una tarea que no se va a hacer conste en el cierre con su motivo. No cambia el estado. `DATOS_NO_VALIDOS` si el motivo está vacío; `ESTADO_NO_VALIDO` si la tarea ya está cerrada. **Salida:** `{ "tarea": {...} }`.

### 3.5 `iniciar_elemento(elemento_id)` · `terminar_elemento(elemento_id)` · `marcar_cajas(elemento_id, cantidad_hecha)` ✅
- `iniciar_elemento`: el operario elige la referencia o la tienda (él decide el orden, §8). Inicia también la tarea si estaba pendiente.
- `terminar_elemento`: **punto de encaje** (§6.4). En producción, al terminar cada referencia; **en bolsas, al terminar la tienda entera** (decidido). Si hay pendiente una tarea con hora ya vencida o una urgente, la tarea con lista vuelve a `pendiente` (conservando lo hecho) y la respuesta trae la nueva `tarea_activa`.
- `marcar_cajas`: en las bolsas, fija cuántas cajas lleva metidas (valor absoluto, de 0 a `cantidad`).
- `terminar_elemento` es para referencias de producción; en bolsas se usa `marcar_cajas` (si no: `DATOS_NO_VALIDOS`).
- Repetir cualquiera de las tres no es error: devuelve el estado ya alcanzado.
- **Salida:** `{ "elemento": { id, estado, cantidad, cantidad_hecha }, "tarea_activa": {...} }`.
- **Errores:** `CANTIDAD_FUERA_DE_RANGO`, `OTRO_ELEMENTO_EN_CURSO`, `OTRA_TAREA_EN_CURSO`, `NO_ENCONTRADO`, `ESTADO_NO_VALIDO`.

### 3.6 `retrasar_salida(minutos)` — pendiente
Botones «Retrasar 15 min» y «Retrasar 30 min» de la tarea de bolsas (bolsas listas en la mesa de salida a las 10:45, §4).
- **Entrada:** `minutos` (15 o 30) e `id_cliente`.
- **Efecto:** mueve la hora límite de las bolsas y la hora de salida, avisa en el momento a quien sale de la nueva hora (si es Administración, correo corto «Salida retrasada a las HH:MM» y aviso en `estado_actual`), y lo registra. El cierre lo cruza con las cajas del reparto y las incidencias de la mañana.
- **Salida:** `{ "nueva_hora_salida": "11:00", "tarea_activa": {...} }`.

### 3.7 `registrar_evento(id_cliente, tipo, detalle)` — pendiente
`llega_mercancia`, `pedido_cliente` (botón «Pedido de cliente»; Administración también puede crearlo como tarea), `no_quedan_vapers`. Crea la tarea correspondiente. **Salida:** la tarea creada y la nueva `tarea_activa`.

### 3.8 `pegar_reparto` (función del servidor) ✅
- **Entrada:** `{ texto, tipo: "reparto"|"envio", sale?: "operario"|"administracion", confirmar_fecha?: true }`
- **Proceso:** lee Sheets, interpreta el texto según `REGLAS_CALCULO.md` §2 y, si no hay errores, crea o actualiza las tareas «Producción del reparto» y «Bolsas» con sus elementos. Si ya había un reparto aceptado hoy, lo sustituye conservando lo hecho (§5 R1).
- **Salida correcta:**
```json
{
  "reparto_id": "...", "estado": "aceptado", "sale": "operario", "sustituye_a": null,
  "produccion": [ { "producto": "V2", "formato": "4g", "pedido": 12, "en_almacen": 9, "faltan": 3, "aviso": null } ],
  "bolsas": [ { "destino": "Bilbao", "cajas": 14, "cambia": false } ],
  "datos_leidos_en": "2026-11-03T08:47:12+01:00"
}
```
- **Salidas con problema** (no se crea ninguna tarea):

| Código | Significado |
| --- | --- |
| `REPARTO_CON_ERRORES` | Líneas que no se reconocen o nombres que no existen. Devuelve `lineas: [{num, texto, error, mensaje}]`. No se calcula nada hasta corregir el texto. |
| `FALTA_SALE` | No hay línea `SALE:` válida. La pantalla pregunta «¿Quién sale hoy?» y repite con `sale`. |
| `FECHA_NO_ES_HOY` | La fecha de `REPARTO dd/mm` no es hoy. La pantalla pide confirmación y repite con `confirmar_fecha: true`. |
| `SHEETS_NO_DISPONIBLE` | No se ha podido leer Sheets. No se calcula nada. |
| `ESTRUCTURA_SHEETS_CAMBIADA` | La hoja no tiene la forma esperada. No se calcula nada. |
| `REPARTO_YA_PEGADO` | Mismo texto ya aceptado hoy: **no es un error**; devuelve el resultado anterior con `ya_pegado: true` y `aviso: { codigo: "REPARTO_YA_PEGADO" }`. |
| `CATALOGO_AMBIGUO` | Hay nombres repetidos en PRINCIPAL. No se calcula nada. |
| `ERROR_INTERNO` | Fallo inesperado del servidor (HTTP 500). |

### 3.9 `lista_stock` (función del servidor) ✅
Lista de producción para el stock del almacén (R3, cola A). Se calcula una vez por turno.
- **Salida (operario):** `{ tarea, ya_calculado, lote, faltas, avisos, excluidos, datos_leidos_en }`. `faltas` = productos sin granel (se crea la tarea «Avisa a Administración: falta X»); `avisos` = datos que no se han podido calcular; `excluidos` = minis y vapers.
- **Salida (Administración, consulta):** `{ lista, faltas, avisos, excluidos, datos_leidos_en }`, sin guardar nada.
- **Errores:** `SHEETS_NO_DISPONIBLE`, `ESTRUCTURA_SHEETS_CAMBIADA`, `SIN_TAREA`, `SIN_JORNADA`.

**Quién llama a las funciones del servidor:** la sesión del usuario (cabecera `Authorization`, como hace `supabase.functions.invoke`) o una solicitud interna de un solo uso creada por la base de datos (cabecera `x-solicitud`). Las funciones comprueban la sesión ellas mismas.

### 3.10 Problemas e incidencias — Tarea 4
| Función | Entrada | Efecto |
| --- | --- | --- |
| `abrir_problema` | `id_cliente, tarea_id, tipo, descripcion` | La tarea pasa a `bloqueada`. Devuelve los pasos: «Si en 1 minuto no está resuelto, llama a Administración». |
| `problema_llamada` | `problema_id, contestada` | `false`: registra la llamada y el WhatsApp; vuelve a aparecer «Llama a Administración» **30 min después del WhatsApp**. |
| `resolver_problema` | `problema_id, solucion` | Solución obligatoria (una línea). La tarea vuelve a `pendiente`. También Administración. |
| `iniciar_incidencia` · `terminar_incidencia` | `id_cliente, descripcion` · `incidencia_id` | Qué y por qué en una línea; sin aprobación; queda registrada con su tiempo. |

## 4. Administración — Tarea 4

### 4.1 `crear_tarea_admin`
| Campo | Obligatorio | Notas |
| --- | --- | --- |
| `id_cliente` | sí | |
| `que` | sí | Título. |
| `para_quien` | no | Por defecto, el operario del almacén. |
| `cuando` | sí | `{ "tipo": "hoy" }` · `{ "tipo": "dia", "fecha": "..." }` · `{ "tipo": "antes_de", "fecha": "...", "hora": "11:30" }` |
| `duracion_min` | **sí** | Duración orientativa (§8). Solo sirve para detectar conflictos; la tarea termina cuando el operario la marca. |
| `urgente` | no | `false` por defecto. |
| `porque` | no | |
| `confirmar` | no | `false` = solo comprobar conflicto. |
| `decision_conflicto` | si hay conflicto | `{ "cede": "<tarea_id>", "accion": "despues|manana|cancelar" }` o `{ "accion": "no_crear" }` |

- Si **no cabe**, no la crea y devuelve `CONFLICTO` con las obligatorias en riesgo; Administración decide qué cede. La decisión queda en el registro.
- **Salida:** `{ tarea_id, encaje: "...", conflicto: null }`. **Errores:** `CONFLICTO`, `FECHA_PASADA`.

### 4.2 `cancelar_tarea(tarea_id, motivo)`
Pasa la tarea a `cancelada`. Motivo obligatorio.

### 4.3 `estado_actual()`
Inicio del móvil: en qué está el almacén ahora, problemas abiertos, incidencia en curso, arrastradas, tareas de hoy, **retrasos de la salida** y estado de la última lectura de Sheets.

### 4.4 `cierre(cierre_id)` · `cierres_recientes(limite)`
Cierre **por turno** (13:00 y 18:30 de lunes a jueves; 13:00 el viernes), enviado **por correo**. Contenido: `MODELO_DATOS.md` §3.12. `calidad` solo los viernes y solo `{ "limpieza_viernes": true|false }`.

## 5. Internas (no las llaman las pantallas)

| Función | Quién la llama | Qué hace |
| --- | --- | --- |
| `motor.generar_jornada(persona, fecha)` ✅ | Tarea programada de las 06:00 y `tarea_activa` | Crea la jornada, arrastra lo pendiente y crea las tareas del día. Idempotente. |
| `motor.generar_cierre(jornada, turno)` | Tarea programada al final de cada turno | Congela el cierre y lo envía por correo. Idempotente. |
| `prueba.fijar_condicion(jornada, condicion, valor)` ✅ | Solo las pruebas, solo en el entorno de pruebas | Simula `SALE:`, envío y eventos hasta que tengan su función real. Nadie tiene permiso para usarla. |
| `prueba.invocar(funcion, persona, cuerpo)` ✅ | Solo las pruebas, solo en el entorno de pruebas | Llama a una función del servidor desde la base de datos con una solicitud interna. |
| `servidor_preparar` · `servidor_guardar_lectura` · `servidor_guardar_reparto` · `servidor_guardar_stock` · `servidor_canjear_solicitud` ✅ | Solo las funciones del servidor (rol `service_role`) | Guardan lo que el servidor ha calculado. Ningún usuario puede llamarlas: nadie guarda un reparto o una lista sin pasar por el cálculo. |

## 6. Trazabilidad con las pantallas de §8

| Pantalla (§8) | Funciones |
| --- | --- |
| Chromebook: una tarea, su porqué, Terminada / Tengo un problema / Incidencia, «lo que viene después» | `tarea_activa`, `iniciar_tarea`, `terminar_tarea`, `abrir_problema`, `iniciar_incidencia` |
| Listas de producción (él elige el orden) | `tarea_activa` (elementos), `iniciar_elemento`, `terminar_elemento`, `lista_stock` |
| Bolsas en el Pixel (una tienda por pantalla, toca cada caja; retrasar 15/30 min) | `tarea_activa`, `marcar_cajas`, `retrasar_salida` |
| Pegar el reparto | `pegar_reparto` |
| Inicio de Administración (móvil) | `estado_actual` |
| Nueva tarea (qué, para quién, cuándo, duración, urgente, por qué) | `crear_tarea_admin` |
| Cierre | `cierre` (y correo) |

## 7. Dudas

1. **Ver la lista de stock desde Administración:** la incluyo como consulta. Si no se quiere, se quita.
