# OSASUN OPERATIONS — Contratos entre la base de datos y las pantallas (V1)

**Versión:** 0.5 · **Fecha:** 27/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobado (PR #1 y #2). ✅ = publicado en el proyecto de pruebas (Tareas 2 a 5).

> Esto es lo único que las pantallas (Lovable) pueden usar. Cualquier dato o función nueva se pide al coordinador (§11 de `ESTADO_DEL_SISTEMA.md`).
> **Para empezar las pantallas: §7 «Guía para las pantallas»** (conexión, inicio de sesión con Google, cómo llamar a cada función, tiempo real y errores).

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
- **Cambios en directo:** las pantallas se suscriben (Supabase Realtime) a `tareas` y `tarea_elementos` ✅; la base de datos solo les deja ver lo que su rol puede leer. Así una tarea nueva le aparece al Pixel durante el reparto (§6.7). Detalle en §7.4.

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
| `retrasar_salida` | BD | ✔ | — | ✅ Tarea 4 |
| `registrar_evento` | BD | ✔ | ✔ (solo `pedido_cliente`) | ✅ Tarea 4 |
| `abrir_problema` · `problema_llamada` · `resolver_problema` | BD | ✔ | ✔ (`resolver_problema`) | ✅ Tarea 4 |
| `iniciar_incidencia` · `terminar_incidencia` | BD | ✔ | — | ✅ Tarea 4 |
| `crear_tarea_admin` · `cancelar_tarea` · `estado_actual` | BD | — | ✔ | ✅ Tarea 4 |
| `cierre` · `cierres_recientes` | BD | — | ✔ | ✅ Tarea 4 |
| `generar_jornada` · `generar_cierre` · `enviar_correo` | Internas | — | — | ✅ |

## 3. Operario

### 3.1 `mi_perfil()` ✅
- **Salida:** `{ id, nombre, rol, centro: {id, nombre} | null, telefono_administracion }`
- `telefono_administracion` alimenta el botón de llamada del Pixel (sale de la configuración del entorno; si no está, del teléfono de la ficha de Administración).
- Sin ficha de persona (cuenta que entró sin estar autorizada): `NO_AUTORIZADO`.

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

### 3.6 `retrasar_salida(id_cliente, minutos)` ✅
Botones «Retrasar 15 min» y «Retrasar 30 min» de la tarea de bolsas (bolsas listas en la mesa de salida a las 10:45, §4).
- **Entrada:** `minutos` (15 o 30) e `id_cliente`.
- **Efecto:** suma los minutos a la hora límite de las bolsas, de la producción del reparto y del envío del viernes, y a la hora de la salida (y de Nacex el viernes). Se puede retrasar varias veces (cada vez desde la última hora). Queda registrado. Si sale Administración, se le envía en el momento un correo «Salida retrasada a las HH:MM» y se ve en `estado_actual`. El cierre de la mañana lo cruza con las cajas del reparto y las incidencias de la mañana.
- **Salida:** `{ "nueva_hora_salida": "11:00", "minutos": 15, "aviso": "correo"|"sin_aviso", "tarea_activa": {...} }`. Repetir con el mismo `id_cliente` devuelve lo mismo sin mover nada.
- **Errores:** `DATOS_NO_VALIDOS` (no es 15 ni 30), `SIN_TAREA` (aún no hay bolsas: falta pegar el reparto), `ESTADO_NO_VALIDO` (las bolsas ya están listas), `SIN_JORNADA`.

### 3.7 `registrar_evento(id_cliente, tipo, detalle?)` ✅
`llega_mercancia` (recepción, urgente), `pedido_cliente` (botón «Pedido de cliente»), `no_quedan_vapers` (tirada de vapers). Crea la tarea correspondiente en la jornada de hoy; el `detalle` pasa a ser su «por qué». Administración solo puede registrar `pedido_cliente`, que va a la jornada del operario del almacén.
- **Salida:** `{ "evento_id", "tarea": {...}, "tarea_activa": {...} }` (`tarea_activa` solo al operario). Repetir con el mismo `id_cliente` no duplica.
- **Errores:** `DATOS_NO_VALIDOS`, `NO_AUTORIZADO` (Administración con otro tipo), `SIN_JORNADA`.

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

### 3.10 Problemas e incidencias ✅
| Función | Entrada | Efecto |
| --- | --- | --- |
| `abrir_problema` | `id_cliente, tarea_id, tipo, descripcion` | `tipo`: `falta_material` · `no_encuentro` · `no_se_hacerlo` · `no_funciona` · `otro`. La tarea pasa a `bloqueada` y el operario sigue con la siguiente. Devuelve `{ problema, pasos, tarea_activa }`; `pasos`: «Si en 1 minuto no está resuelto, llama a Administración.» (con `no_encuentro`: «Llama a Administración ahora.»). |
| `problema_llamada` | `problema_id, contestada` | `true`: pide escribir la solución. `false`: registra la llamada y el WhatsApp; **30 min después del WhatsApp** aparece la tarea «Llama a Administración: …» (escalón 2). Cada llamada deja hecha la anterior. |
| `resolver_problema` | `problema_id, solucion` | Solución obligatoria (una línea). La tarea vuelve a `pendiente` y se retira la llamada pendiente. También Administración, para cualquier problema. Devuelve `{ problema }` con `minutos_hasta_solucion`. |
| `iniciar_incidencia` · `terminar_incidencia` | `id_cliente, descripcion` · `incidencia_id` | Qué y por qué en una línea; sin aprobación; guarda la tarea que estaba en curso y queda registrada con su tiempo (`minutos`). Una sola abierta a la vez. |

**Errores:** `PROBLEMA_YA_ABIERTO` (la tarea ya tiene uno), `SOLUCION_OBLIGATORIA`, `INCIDENCIA_YA_ABIERTA`, `DATOS_NO_VALIDOS`, `NO_ENCONTRADO` (no es suyo), `ESTADO_NO_VALIDO` (la tarea no está abierta hoy). Resolver o llamar sobre un problema ya resuelto devuelve `aviso: PROBLEMA_YA_RESUELTO`, sin error.

## 4. Administración ✅ (Tarea 4)

### 4.1 `crear_tarea_admin` ✅
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

- **Ventana** (`PLAN_TECNICO.md` §2.4): desde ahora (o el inicio del día elegido) hasta la hora de `antes_de` o, si no hay hora, hasta el final del turno en que empieza.
- Solo hay conflicto si **no cabe y alguna obligatoria que vence en la ventana queda en riesgo** (§6.4). Si no cabe pero no hay ninguna obligatoria en riesgo, **se crea** y el `encaje` lo avisa («No le da tiempo entera (faltan unos N min): lo que no termine pasa al día siguiente»), con `minutos_que_faltan`.
- Con conflicto, no la crea y devuelve `CONFLICTO` con `conflicto: { disponible_min, necesario_min, minutos_que_faltan, obligatorias_en_riesgo: [{ tarea_id, titulo, vence, duracion_min }] }`. Administración repite la llamada con `decision_conflicto`:
  - `despues`: la que cede pierde su hora límite (se hace después de la nueva).
  - `manana`: la que cede deja de salir hoy y pasa al día siguiente como arrastrada.
  - `cancelar`: la que cede queda cancelada con su motivo.
  - `no_crear`: no se crea nada.
  La decisión queda en el registro (`conflicto_decidido`).
- `confirmar: false` solo comprueba: `{ tarea_id: null, comprobado: true, encaje, conflicto }` (o el error `CONFLICTO`).
- Una tarea para otro día prepara la jornada de ese día; lo pendiente se arrastra igualmente al llegar el día.
- **Salida:** `{ tarea_id, tarea, encaje: "...", conflicto: null|{...}, minutos_que_faltan, decision }`. Repetir con el mismo `id_cliente` devuelve la misma tarea (`ya_creada: true`).
- **Errores:** `CONFLICTO`, `FECHA_PASADA` (día u hora pasados, o su jornada de hoy ya terminó), `SIN_JORNADA` (ese día no trabaja), `DATOS_NO_VALIDOS` (sin duración, sin qué, «cuando» o decisión no válidos), `NO_ENCONTRADO` (`para_quien`).

### 4.2 `cancelar_tarea(tarea_id, motivo)` ✅
Pasa la tarea a `cancelada` con su motivo (obligatorio) y retira la llamada pendiente si tenía un problema abierto. **Salida:** `{ tarea }`. Ya cancelada: `aviso: YA_CANCELADA`. **Errores:** `DATOS_NO_VALIDOS`, `NO_ENCONTRADO`, `ESTADO_NO_VALIDO` (ya hecha o arrastrada).

### 4.3 `estado_actual()` ✅
Inicio del móvil. Solo lee (no genera nada). **Salida:** `{ ahora, fecha, operario, jornada: { id, sale, hay_envio, estado }, en_curso: tarea con sus elementos, problemas_abiertos: [...], incidencia_en_curso, arrastradas: [...], hoy: [{ id, titulo, estado, origen, obligatoria, urgente, hora, motivo }], retrasos_salida: [{ a_las, minutos, nueva_hora, sale, aviso }], correos_no_enviados: [{ tipo, asunto, estado: "fallido"|"dudoso", intentos, error, creado_en }], lectura_sheets: { ultima_correcta, ultimo_error } }`. `correos_no_enviados` = cierres o avisos de los últimos 7 días que no se han podido enviar (mostrarlos como aviso).

### 4.4 `cierre(cierre_id)` · `cierres_recientes(limite)` ✅
Cierre **por turno** (13:00 y 18:30 de lunes a jueves; 13:00 el viernes, según el horario), generado solo y enviado **por correo**, una sola vez.
- `cierre` → `{ id, fecha, turno, generado_en, enviado_en, canal, contenido, texto }` (`texto` = el del correo).
- `cierres_recientes(limite = 10, máx. 50)` → `{ cierres: [{ id, fecha, turno, generado_en, enviado_en, hechas, sin_hacer, problemas, incidencias }] }`.
- **Contenido** (`MODELO_DATOS.md` §3.12): `hecho` [{ titulo, resultado, hora }] · `no_hecho` [{ titulo, estado, motivo, pasa_a_manana }] (obligatorias y de Administración de ese turno; las de todo el día, en el último) · `problemas` [{ tarea, descripcion, abierto, minutos, mas_de_5_min, solucion, estado, llamadas }] · `incidencias` [{ descripcion, inicio, fin, minutos }] · `arrastrados` { llegaron (primer turno), pasan_a_manana (último turno) } · `retrasos_salida` y `cruce_retrasos` { cajas_reparto, cajas_a_producir, cajas_producidas, tiendas, incidencias_manana, minutos_incidencias_manana } (turno de mañana, si hubo retraso) · `siguiente` (lo que queda para la tarde, o lo que toca el próximo día de trabajo) · `calidad` solo el viernes y solo `{ "limpieza_viernes": true|false }`.

## 5. Internas (no las llaman las pantallas)

| Función | Quién la llama | Qué hace |
| --- | --- | --- |
| `motor.generar_jornada(persona, fecha)` ✅ | Tarea programada de las 06:00 y `tarea_activa` | Crea la jornada, arrastra lo pendiente y crea las tareas del día. Idempotente. |
| `motor.generar_cierre(jornada, turno, ahora)` ✅ | Tarea programada `generar_cierres_turno` (a y media y en punto de 11, 12, 16 y 17 UTC, lunes a viernes: cubre las 13:00 y las 18:30 de Madrid en verano e invierno) | Congela el cierre, cierra la jornada tras el último turno y pide el correo. Idempotente. |
| `enviar_correo` (función del servidor) ✅ | Solo la base de datos, con solicitud interna de un solo uso (`x-solicitud`); las pantallas no pueden | Reclama el envío (`servidor_correo_reclamar`), lo manda con Resend (secreto `RESEND_API_KEY`) y anota la respuesta (`servidor_correo_respuesta`): enviado; **rechazado** (Resend respondió con un error) → se reintenta a los 5 min, hasta 3 intentos; **dudoso** (sin respuesta a tiempo) → no se reintenta. El fallo final sale en `estado_actual`. |
| `motor.reintentar_correos(ahora)` ✅ | Tarea programada `reintentar_correos`, cada minuto | Vuelve a pedir los correos rechazados cuya espera de 5 min ha pasado. |
| `hook_antes_de_crear_usuario(event)` ✅ | Supabase Auth, antes de crear un usuario (hook «Before User Created») | Solo deja crear el usuario si su correo está en `cuentas_autorizadas` (configuración del entorno). Si no: error 403 «Esta cuenta no tiene acceso a Osasun Operations. Pide acceso a Administración.» |
| `motor.tras_crear_usuario` (disparador en `auth.users`) ✅ | Al crearse el usuario | Da de alta su persona con el rol, el centro y el horario de la lista. Nunca impide el alta. |
| `prueba.fijar_condicion(jornada, condicion, valor)` ✅ | Solo las pruebas, solo en el entorno de pruebas | Simula `SALE:`, envío y eventos hasta que tengan su función real. Nadie tiene permiso para usarla. |
| `prueba.invocar(funcion, persona, cuerpo)` ✅ | Solo las pruebas, solo en el entorno de pruebas | Llama a una función del servidor desde la base de datos con una solicitud interna. |
| `servidor_preparar` · `servidor_guardar_lectura` · `servidor_guardar_reparto` · `servidor_guardar_stock` · `servidor_canjear_solicitud` · `servidor_correo_reclamar` · `servidor_correo_respuesta` (y `servidor_correo_resultado`, de la Tarea 4) ✅ | Solo las funciones del servidor (rol `service_role`) | Guardan lo que el servidor ha calculado. Ningún usuario puede llamarlas: nadie guarda un reparto o una lista sin pasar por el cálculo. |

## 6. Trazabilidad con las pantallas de §8

| Pantalla (§8) | Funciones |
| --- | --- |
| Chromebook: una tarea, su porqué, Terminada / Tengo un problema / Incidencia, «lo que viene después» | `tarea_activa`, `iniciar_tarea`, `terminar_tarea`, `abrir_problema`, `iniciar_incidencia` |
| Listas de producción (él elige el orden) | `tarea_activa` (elementos), `iniciar_elemento`, `terminar_elemento`, `lista_stock` |
| Bolsas en el Pixel (una tienda por pantalla, toca cada caja; retrasar 15/30 min) | `tarea_activa`, `marcar_cajas`, `retrasar_salida` |
| Botones «Llega mercancía», «Pedido de cliente», «No quedan vapers» | `registrar_evento` |
| Tengo un problema (llamar, no contestan, solución) | `abrir_problema`, `problema_llamada`, `resolver_problema` |
| Pegar el reparto | `pegar_reparto` |
| Inicio de Administración (móvil) | `estado_actual` |
| Nueva tarea (qué, para quién, cuándo, duración, urgente, por qué) | `crear_tarea_admin` |
| Cierre | `cierre` (y correo) |

## 7. Guía para las pantallas (Lovable) ✅

Las pantallas están en otro repositorio (`osasun-pantallas`) y **no usan la integración de Supabase de Lovable**: solo la URL del proyecto y la clave pública, y **solo las funciones de este documento**. No crean ni cambian tablas, no escriben en ellas (la base de datos lo rechaza), no calculan nada y no envían la hora.

### 7.1 Conexión (proyecto de **pruebas**)
| Dato | Valor |
| --- | --- |
| URL del proyecto | `https://rvypswuoafnjwqdwxjvo.supabase.co` |
| Clave pública (*publishable*) | `sb_publishable_IKa8qY4SO04BeRe0WWhy-Q_nE2OIwQg` |

La clave pública no es secreta: no da permisos por sí sola; los da la sesión de cada persona. Producción tendrá otra URL y otra clave.
```js
import { createClient } from '@supabase/supabase-js'
export const supabase = createClient('https://rvypswuoafnjwqdwxjvo.supabase.co', 'sb_publishable_IKa8qY4SO04BeRe0WWhy-Q_nE2OIwQg')
```

### 7.2 Iniciar sesión (solo Google)
- Un único botón «Entrar con Google». No hay registro ni contraseña.
```js
await supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } })
```
- Al volver, la sesión se recoge sola (`supabase.auth.onAuthStateChange`). Después, siempre `supabase.rpc('mi_perfil')` y, según `rol`, la pantalla del operario o la de Administración.
- **Cuenta no autorizada:** Google vuelve a la app con `error_description` en la dirección («Esta cuenta no tiene acceso a Osasun Operations. Pide acceso a Administración.»). Se muestra tal cual, con el botón de entrar.
- Si `mi_perfil` devuelve `NO_AUTORIZADO` (usuario sin ficha): mostrar el mensaje y un botón «Salir» (`supabase.auth.signOut()`).
- Direcciones de vuelta permitidas en pruebas: las previsualizaciones de Lovable (`*.lovable.app`, `*.lovableproject.com`). Otra dirección se pide al coordinador.

### 7.3 Llamar a las funciones
- **Base de datos:** `const { data, error } = await supabase.rpc('nombre', { parametros })`, con los nombres de parámetro de este documento. Ej.: `supabase.rpc('terminar_tarea', { tarea_id, resultado: 'Hecho' })`.
- **Servidor** (`pegar_reparto`, `lista_stock`): `const { data, error } = await supabase.functions.invoke('pegar_reparto', { body: { texto, tipo: 'reparto' } })`. La sesión va sola.
- **Cómo leer la respuesta:**
  1. `error` (de Supabase): sin conexión o fallo del servidor → «No hay conexión. Vuelve a intentarlo.» y permitir reintentar. Si la sesión ha caducado (`error.code` `42501` o HTTP 401), volver a «Entrar con Google».
  2. `data.error`: respuesta de negocio → mostrar **`data.error.mensaje` tal cual** (§7.5).
  3. `data.aviso`: no es un error (ej. «Este reparto ya estaba pegado») → mostrarlo como información.
  4. Si no, `data` es el resultado (casi siempre trae la nueva `tarea_activa`: pintarla directamente).
- **`id_cliente`:** las que crean algo lo piden. Generarlo con `crypto.randomUUID()` al pulsar el botón y **reutilizar el mismo** si se reintenta esa misma acción; así nunca se duplica.
- **Horas:** los campos con fecha y hora (`*_en`, `hora_programada`, `hora_limite`…) llegan en ISO (UTC); se muestran en hora de Madrid: `new Date(v).toLocaleTimeString('es-ES', { timeZone: 'Europe/Madrid', hour: '2-digit', minute: '2-digit' })`. Los que ya son texto «HH:MM» (`hora`, `a_las`, `nueva_hora`, `nueva_hora_salida`, `vence`, `siguiente`) se muestran tal cual.
- **Nada de cálculos ni avisos de tiempo en la pantalla** (§6.7): lo que hay que hacer lo dice `tarea_activa`.

### 7.4 En directo (Realtime)
Publicadas: `tareas` y `tarea_elementos`. Cada persona solo recibe los cambios que puede leer. Ante cualquier cambio, **volver a pedir la función** (`tarea_activa` o `estado_actual`); la pantalla no recalcula nada.
```js
supabase.channel('jornada')
  .on('postgres_changes', { event: '*', schema: 'public', table: 'tareas', filter: `jornada_id=eq.${jornadaId}` }, refrescar)
  .on('postgres_changes', { event: '*', schema: 'public', table: 'tarea_elementos' }, refrescar)
  .subscribe()
```
- **Operario (Chromebook y Pixel):** `jornadaId` = `tarea_activa().jornada.id`. Así lo que marca el Pixel (cajas) se ve en el Chromebook y una tarea nueva aparece sola.
- **Administración:** suscribirse a `tareas` sin filtro y refrescar `estado_actual()`.
- **Además, refrescar cada minuto y al volver a la pestaña:** las tareas con hora (y «Llama a Administración» a los 30 min) aparecen al llegar su hora, sin que cambie nada en la base de datos.

### 7.5 Mensajes de error
Todos se muestran tal cual (`data.error.mensaje`). Los que piden algo más a la pantalla:

| Código | Qué hace la pantalla |
| --- | --- |
| `NO_AUTENTICADO` | Volver a «Entrar con Google». |
| `NO_AUTORIZADO` | Mostrar el mensaje; si viene de `mi_perfil`, botón «Salir». |
| `FALTA_SALE` | Preguntar «¿Quién sale hoy?» (`opciones`) y repetir `pegar_reparto` con `sale`. |
| `FECHA_NO_ES_HOY` | Pedir confirmación y repetir con `confirmar_fecha: true`. |
| `REPARTO_CON_ERRORES` | Mostrar `lineas` (número de línea y mensaje) para corregir el texto. |
| `CONFLICTO` | Mostrar `conflicto.obligatorias_en_riesgo` y los minutos que faltan; Administración elige qué cede (o no crear) y se repite `crear_tarea_admin` con `decision_conflicto` y `confirmar: true`. |
| `PROBLEMA_YA_ABIERTO` · `INCIDENCIA_YA_ABIERTA` | Mostrar el abierto (`problema` / `incidencia_id`) en vez de crear otro. |
| `SOLUCION_OBLIGATORIA` · `DATOS_NO_VALIDOS` · `CANTIDAD_FUERA_DE_RANGO` | Mostrar junto al campo y dejar corregir. |
| `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` | Mostrar el mensaje; el resto de la app sigue funcionando. |
| Cualquier otro | Mostrar el mensaje. |

## 8. Dudas

1. **Ver la lista de stock desde Administración:** la incluyo como consulta. Si no se quiere, se quita.
