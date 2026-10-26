# OSASUN OPERATIONS — Contratos entre la base de datos y las pantallas (propuesta V1)

**Versión:** 0.1 (propuesta, pendiente de aprobación) · **Fecha:** 26/10/2026 · **Autor:** agente de base de datos · **Tarea:** 1

> Esto es lo único que las pantallas (Lovable) pueden usar. Cualquier dato o función nueva se pide al coordinador (§11 de `ESTADO_DEL_SISTEMA.md`).

---

## 1. Reglas comunes

- **Dos tipos de llamada:**
  - **Funciones de base de datos** (`supabase.rpc('nombre', {...})`): todo lo que no necesita Google Sheets.
  - **Funciones del servidor** (`supabase.functions.invoke('nombre', {...})`): las dos que leen Sheets (`pegar_reparto` y `lista_stock`).
- Las pantallas usan **solo la clave pública** y la sesión del usuario. El rol se comprueba dentro de cada función; esconder un botón no da ni quita permisos.
- **Hora:** la decide el servidor. Las pantallas nunca envían «ahora».
- **Respuesta:** JSON. Si hay error: `{ "error": { "codigo": "...", "mensaje": "frase para mostrar" } }`. El mensaje está en castellano y se puede enseñar tal cual.
- **Reintentos:** las funciones que crean algo aceptan `id_cliente` (uuid generado por la pantalla). Repetir la misma llamada devuelve el mismo resultado sin duplicar.
- **Cambios en directo:** las pantallas pueden suscribirse (Supabase Realtime) a `tareas` y `problemas`; la base de datos solo les deja ver lo que su rol puede leer. Así una tarea nueva le aparece al Pixel durante el reparto (§6.7).

### Errores comunes a todas las funciones

| Código | Cuándo |
| --- | --- |
| `NO_AUTENTICADO` | Sin sesión. |
| `NO_AUTORIZADO` | El rol no puede usar esta función o el dato no es suyo. |
| `NO_ENCONTRADO` | El id no existe (o no es visible para ese usuario). |
| `ESTADO_NO_VALIDO` | La acción no tiene sentido en el estado actual (ej. terminar una tarea cancelada). |
| `DATOS_NO_VALIDOS` | Falta un campo obligatorio o tiene un valor no permitido. |

## 2. Resumen

| Función | Tipo | Operario | Administración |
| --- | --- | --- | --- |
| `mi_perfil` | BD | ✔ | ✔ |
| `tarea_activa` | BD | ✔ | — |
| `iniciar_tarea` · `terminar_tarea` · `anotar_motivo` | BD | ✔ | — |
| `iniciar_elemento` · `terminar_elemento` · `marcar_cajas` | BD | ✔ | — |
| `abrir_problema` · `problema_llamada` · `resolver_problema` | BD | ✔ | ✔ (`resolver_problema`) |
| `iniciar_incidencia` · `terminar_incidencia` | BD | ✔ | — |
| `registrar_evento` | BD | ✔ | ✔ |
| `pegar_reparto` | Servidor | ✔ | — |
| `lista_stock` | Servidor | ✔ | ✔ (consulta) |
| `crear_tarea_admin` | BD | — | ✔ |
| `cancelar_tarea` | BD | — | ✔ |
| `estado_actual` | BD | — | ✔ |
| `cierre` · `cierres_recientes` | BD | — | ✔ |
| `generar_jornada` · `generar_cierre` | BD (internas) | — | — (solo tareas programadas) |

## 3. Operario

### 3.1 `mi_perfil()`
- **Salida:** `{ id, nombre, rol, centro: {id, nombre}, telefono_administracion }`
- `telefono_administracion` alimenta el botón de llamada del Pixel.

### 3.2 `tarea_activa()`
Lo que muestra el Chromebook (y el Pixel). Si la jornada de hoy no existe, la genera (idempotente).
- **Entrada:** ninguna.
- **Salida:**
```json
{
  "jornada": { "id": "...", "fecha": "2026-10-27", "sale": "operario|administracion|null" },
  "pregunta": null,
  "tarea": {
    "id": "...", "titulo": "...", "porque": "...", "estado": "pendiente|en_curso|bloqueada",
    "obligatoria": true, "hora_programada": "...", "hora_limite": "...",
    "contenido": "simple|produccion_reparto|bolsas|stock_35|recuento",
    "elementos": [ { "id": "...", "producto": "V2", "formato": "4g", "categoria": "...", "destino": "Bilbao",
                     "cantidad": 3, "cantidad_hecha": 1, "motivo": "...", "orden_sugerido": 1, "estado": "..." } ]
  },
  "siguiente": "Recuento de stock · 12:45",
  "problemas_abiertos": [ { "id": "...", "tipo": "...", "estado": "...", "proxima_llamada_en": "..." } ]
}
```
- `pregunta`: si la jornada necesita una respuesta antes de seguir (ej. el reparto no traía `SALE:`), viene aquí: `{ "tipo": "sale", "opciones": ["operario","administracion"] }`. Se responde con `pegar_reparto` (campo `sale`).
- La elección de la tarea sigue `PLAN_TECNICO.md` §2.3. **Nunca devuelve avisos de tiempo ni de presión** (§6.7): solo tareas.
- Si no hay nada que hacer en todo el día (fuera de horario), `tarea` es `null`.

### 3.3 `iniciar_tarea(tarea_id)` · `terminar_tarea(tarea_id, resultado?, motivo?)`
- `iniciar_tarea`: pendiente → en_curso. Guarda la hora real.
  - Error `OTRA_TAREA_EN_CURSO` si ya hay otra en curso (devuelve cuál).
- `terminar_tarea`: en_curso → hecha. `resultado` (texto corto, opcional) va al cierre.
  - Si la tarea tiene elementos sin terminar: error `ELEMENTOS_PENDIENTES`, salvo que se mande `motivo` (ej. «sin granel de Yuzu»). Con motivo, la tarea queda `hecha` y los elementos pendientes constan en el cierre como no hechos con ese motivo.
- **Salida (ambas):** la tarea actualizada y la nueva `tarea_activa`.

### 3.4 `anotar_motivo(tarea_id, motivo)`
Para que una tarea que no se va a hacer conste en el cierre con su motivo. No cambia el estado.

### 3.5 `iniciar_elemento(elemento_id)` · `terminar_elemento(elemento_id)` · `marcar_cajas(elemento_id, cantidad_hecha)`
- `iniciar_elemento`: el operario elige la referencia o la tienda (él decide el orden, §8). Inicia también la tarea si estaba pendiente.
- `terminar_elemento`: marca la referencia hecha. **Es el punto de encaje** (§6.4): si hay pendiente una tarea con hora ya vencida o una urgente de Administración, la tarea con lista vuelve a `pendiente` (conservando lo hecho) y la respuesta trae la nueva `tarea_activa`.
- `marcar_cajas`: en las bolsas, fija cuántas cajas de ese elemento lleva metidas (valor absoluto, de 0 a `cantidad`). Al llegar a `cantidad`, el elemento pasa a `hecho`. Una bolsa (tienda) está terminada cuando todos sus elementos lo están; eso también es punto de encaje.
- **Errores:** `CANTIDAD_FUERA_DE_RANGO`, `OTRO_ELEMENTO_EN_CURSO`.

### 3.6 Problemas (§6.6)
| Función | Entrada | Efecto |
| --- | --- | --- |
| `abrir_problema` | `id_cliente, tarea_id, tipo, descripcion` | Crea el problema; la tarea pasa a `bloqueada`. Devuelve los pasos a seguir: «Si en 1 minuto no está resuelto, llama a Administración». |
| `problema_llamada` | `problema_id, contestada (bool)` | `true`: registra la llamada; falta escribir la solución. `false`: registra la llamada y el WhatsApp; estado `sin_respuesta`, `proxima_llamada_en` = ahora + 30 min, y el operario pasa a otra tarea. |
| `resolver_problema` | `problema_id, solucion` | Solución obligatoria (una línea). La tarea vuelve a `pendiente`. También la puede usar Administración si llama ella antes. |

- Cuando llega `proxima_llamada_en` sin solución, `tarea_activa` devuelve la tarea «Llama a Administración: <problema>» (es una tarea, no un aviso, §6.7).
- **Errores:** `SOLUCION_OBLIGATORIA`, `PROBLEMA_YA_RESUELTO` (devuelve el problema, no es fallo).
- Previsto, no implementado (V1.1): para `falta_material`, la salida incluirá la solución del catálogo de materiales.

### 3.7 Incidencias
- `iniciar_incidencia(id_cliente, descripcion)` → `{ incidencia_id }`. Descripción obligatoria (qué y por qué, una línea). No necesita aprobación. Guarda la tarea que estaba en curso.
- `terminar_incidencia(incidencia_id)` → guarda la hora de fin.
- Error: `INCIDENCIA_YA_ABIERTA` (solo una a la vez).

### 3.8 `registrar_evento(id_cliente, tipo, detalle)`
Para lo que pasa «en cualquier momento» (§4): `llega_mercancia`, `pedido_cliente`, `no_quedan_vapers`. Crea la tarea condicionada correspondiente (recepción, pedido de cliente, tirada de vapers) con su obligatoriedad de plantilla.
- **Salida:** la tarea creada y la nueva `tarea_activa`.

### 3.9 `pegar_reparto` (función del servidor)
- **Entrada:** `{ texto, tipo: "reparto"|"envio", sale?: "operario"|"administracion" }`
- **Proceso:** lee Sheets, interpreta el texto según `REGLAS_CALCULO.md` §2 y, si no hay errores, crea las tareas «Producción del reparto» y «Bolsas» con sus elementos.
- **Salida correcta:**
```json
{
  "reparto_id": "...", "estado": "aceptado", "sale": "operario",
  "produccion": [ { "producto": "V2", "formato": "4g", "pedido": 12, "en_almacen": 9, "faltan": 3 } ],
  "bolsas": [ { "tienda": "Bilbao", "cajas": 14 } ],
  "datos_leidos_en": "2026-10-27T08:47:12+01:00"
}
```
- **Salidas con problema** (no se crea ninguna tarea):

| Código | Significado |
| --- | --- |
| `REPARTO_CON_ERRORES` | Hay líneas que no se reconocen o nombres que no existen. Devuelve `lineas: [{num, texto, error, mensaje}]`. El operario corrige (o pregunta) y vuelve a pegar. |
| `FALTA_SALE` | No hay línea `SALE:` válida. La pantalla pregunta «¿Quién sale hoy?» y repite la llamada con `sale`. |
| `SHEETS_NO_DISPONIBLE` | No se ha podido leer Sheets. No se calcula nada. Mensaje: «No puedo leer el stock ahora. Vuelve a intentarlo en un minuto; si sigue, avisa a Administración». |
| `ESTRUCTURA_SHEETS_CAMBIADA` | La hoja no tiene la forma esperada. No se calcula nada. |
| `REPARTO_YA_PEGADO` | Mismo texto ya aceptado hoy: devuelve el resultado anterior (no es fallo). |

### 3.10 `lista_stock` (función del servidor)
Lista de producción para el stock del almacén (R3, cola de tiempo libre A).
- **Entrada:** ninguna.
- **Salida:** la tarea «Stock del almacén» con sus elementos ordenados por prioridad y el motivo de cada uno, más `avisos` (ej. «Avisa a Administración: falta granel de Yuzu») y `datos_leidos_en`.
- Se calcula **una vez por turno** (ver `REGLAS_CALCULO.md` §3.7). Lo no hecho no se arrastra: se recalcula (§6.5).
- **Errores:** `SHEETS_NO_DISPONIBLE`, `ESTRUCTURA_SHEETS_CAMBIADA` (la tarea queda sin lista y lo dice claramente; el resto de la app sigue funcionando).

## 4. Administración

### 4.1 `crear_tarea_admin`
- **Entrada:**

| Campo | Obligatorio | Notas |
| --- | --- | --- |
| `id_cliente` | sí | |
| `que` | sí | Título. |
| `para_quien` | no | Persona; por defecto, el operario del almacén. |
| `cuando` | sí | `{ "tipo": "hoy" }` · `{ "tipo": "dia", "fecha": "..." }` · `{ "tipo": "antes_de", "fecha": "...", "hora": "11:30" }` |
| `urgente` | no | `false` por defecto. |
| `porque` | no | |
| `confirmar` | no | `false` = solo comprobar conflicto. |
| `decision_conflicto` | si hay conflicto | `{ "cede": "<tarea_id>", "accion": "despues|manana|cancelar" }` o `{ "accion": "no_crear" }` |

- **Proceso:** comprueba si cabe (ver `PLAN_TECNICO.md` §2.4).
  - Si cabe y `confirmar = true`: la crea.
  - Si **no cabe**: no la crea y devuelve `CONFLICTO` con las obligatorias en riesgo. Administración decide qué cede y repite con `decision_conflicto`. Nada desaparece en silencio: la decisión queda en el registro.
- **Salida:** `{ tarea_id, encaje: "al terminar lo que tiene entre manos" | "hueco previsto hacia 11:05", conflicto: null }`
- **Errores:** `CONFLICTO` (con `{ obligatorias_en_riesgo: [...], minutos_que_faltan }`), `FECHA_PASADA`.

### 4.2 `cancelar_tarea(tarea_id, motivo)`
Pasa la tarea a `cancelada`. Si estaba en curso, el operario recibe la siguiente. Motivo obligatorio.

### 4.3 `estado_actual()`
Pantalla de inicio del móvil (§8).
- **Salida:**
```json
{
  "ahora": { "persona": "...", "tarea": "...", "desde": "...", "elemento": "V2 4g" },
  "problemas_abiertos": [ { "id": "...", "tipo": "...", "tarea": "...", "abierto_hace_min": 7, "estado": "sin_respuesta" } ],
  "incidencia_en_curso": null,
  "arrastradas": [ ... ],
  "hoy": [ { "id": "...", "titulo": "...", "estado": "...", "hora": "...", "obligatoria": true, "origen": "..." } ],
  "lecturas_sheets": { "ultima_correcta": "...", "ultimo_error": null }
}
```

### 4.4 `cierre(cierre_id)` · `cierres_recientes(limite)`
- **Salida de `cierre`:**
```json
{
  "fecha": "...", "turno": null,
  "hecho": [ { "tarea": "...", "inicio": "...", "fin": "...", "resultado": "..." } ],
  "no_hecho": [ { "tarea": "...", "motivo": "..." } ],
  "problemas": [ { "tipo": "...", "minutos": 4, "solucion": "..." } ],
  "incidencias": [ { "descripcion": "...", "minutos": 12 } ],
  "arrastrados": [ ... ],
  "manana": [ { "titulo": "...", "hora": "..." } ],
  "calidad": { "limpieza_viernes": true }
}
```
`calidad` solo aparece los viernes (ver duda 3 sobre los papeles de resinas).

## 5. Internas (no las llaman las pantallas)

| Función | Quién la llama | Qué hace |
| --- | --- | --- |
| `generar_jornada(persona_id, fecha)` | Tarea programada diaria y `tarea_activa` | Crea la jornada y las tareas del día desde las plantillas. Idempotente. |
| `generar_cierre(jornada_id, turno)` | Tarea programada al final de turno o de jornada (según D2) | Congela el cierre y lo envía por el canal de D3. Idempotente. |

## 6. Trazabilidad con las pantallas de §8

| Pantalla (§8) | Funciones |
| --- | --- |
| Chromebook: una tarea, su porqué, Terminada / Tengo un problema / Incidencia, «lo que viene después» | `tarea_activa`, `terminar_tarea`, `abrir_problema`, `iniciar_incidencia` |
| Listas de producción (él elige el orden) | `tarea_activa` (elementos), `iniciar_elemento`, `terminar_elemento`, `lista_stock` |
| Bolsas en el Pixel (una tienda por pantalla, toca cada caja) | `tarea_activa` (elementos con `destino`), `marcar_cajas` |
| Pegar el reparto | `pegar_reparto` |
| Inicio de Administración (móvil) | `estado_actual` |
| Nueva tarea (qué, para quién, cuándo, urgente, por qué) | `crear_tarea_admin` |
| Cierre al móvil | `cierre` |

## 7. Dudas

1. **Interrumpir una lista para una tarea con hora:** propongo que el punto de encaje sea «terminar referencia» en producción y «terminar bolsa (tienda)» en bolsas, como dice §6.4. ¿Correcto que en bolsas se espere a cerrar la tienda entera y no cada caja?
2. **Ver la lista de stock desde Administración:** la incluyo como consulta. Si no se quiere, se quita.
3. **Indicador de calidad del viernes:** «limpieza hecha» sale de la tarea. «Papeles de resinas rectos y cuidados» ¿quién lo declara y cómo (el operario al cerrar, Administración al revisar)?
