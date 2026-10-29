# OSASUN OPERATIONS — Contratos entre la base de datos y las pantallas (V1)

**Versión:** 1.6 · **Fecha:** 29/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobado (PR #1 y #2). ✅ = publicado en el proyecto de pruebas (Tareas 2 a 17).

> **Cambios en 1.6 (Tarea 17) — para Lovable: envío sin granel** (`ESTADO_DEL_SISTEMA.md` v1.31, §5 R1e, el punto del envío).
> 1. **`guardar_reparto` con `tipo: "envio"`** (§3.14), al pulsar «Calcular» en «Preparar envío» o «Modificar envío»: si algo hay que hacerlo y no tiene granel, **no se guarda nada** y responde el error nuevo **`SIN_GRANEL`**, con `mensaje` (una línea por referencia) y `referencias: [{ destino_id, destino, producto, formato, pedido, hay, mensaje }]`.
> 2. La pantalla muestra cada referencia con su `mensaje` («SOUR DIESEL 4g: pides 5, en el almacén hay 3 cajas y no hay granel para hacer las otras 2.») y dos botones: **«Dejarlo en N»** (pone esa línea en `hay`) o **«Quitarlo»** (la pone a 0). Si `hay` es 0, solo «Quitarlo». Después vuelve a calcular (puede ser con el mismo `id_cliente`: no se había guardado nada).
> 3. El reparto no cambia (sigue con R1e en la producción, versión 1.5). En el envío no existe «cogerlo de otra tienda».

> **Cambios en 1.5 (Tarea 16) — para Lovable: producto sin granel en el reparto** (`ESTADO_DEL_SISTEMA.md` v1.30, §5 R1e). Solo se añaden campos y una función.
> 1. **«Producción del reparto»** (`tarea_activa`, §3.2): una referencia que hay que hacer y no tiene granel trae `sin_granel: true`, `para` (las tiendas que la reciben y cuántas les faltan), `tiendas_con_stock` (las demás tiendas del reparto con cajas, según PRINCIPAL), `resuelto` y `decisiones`. Al elegirla, en vez de «Haz N», el aviso con dos opciones por tienda: **Quitarlo** o **Cogerlo de otra tienda** (elegir la tienda, viendo cuántas tiene cada una).
> 2. **`resolver_sin_granel(elemento_id, decisiones)`** (nueva, §3.19, operario): guarda la decisión. La referencia queda hecha sin producir y la tarea sigue como siempre.
> 3. **Bolsas** (§3.2 y §3.5): en la tienda que recibe de otra tienda, un elemento nuevo **`tipo: "llamada"`** con su `texto` («Llama a Algorta para que prepare 2 BZ1 4g para su retirada»). Se muestra y se marca como una petición especial (`marcar_cajas` con 1 o 0); la tienda no está completa sin él. Lo quitado o de otra tienda ya no va en la bolsa.
> 4. **`reparto_de_hoy`** (en `tarea_activa` y en `estado_actual`) trae **`paradas: [{ origen, destino, producto, formato, cantidad, texto }]`** con «Recoge 2 BZ1 4g en Algorta y déjalas en Portugalete»: en «Salida del reparto» si sale el operario y en el panel si sale Administración. No es una tarea.
> 5. **Texto para WhatsApp** (`guardar_reparto`, `reparto_de_hoy_detalle` e histórico): lo quitado ya no sale y lo de otra tienda dice «2x BZ1 4g (de Algorta)». Si ya se había copiado, hay que volver a copiarlo. En `reparto_de_hoy_detalle.lineas`, lo quitado ya no cuenta y lo de otra tienda trae `de: [{ origen_id, origen, cantidad }]`.
> 6. «Hoy sales tú / Hoy sale [nombre]» en las tareas del reparto: ya está en `tarea_activa().jornada.sale`, con los nombres de `mi_perfil().quien_sale_opciones`. No hace falta nada nuevo.


> **Cambios en 1.4 (Tarea 15) — para Lovable: Inicio de Administración tras la prueba en el almacén** (`ESTADO_DEL_SISTEMA.md` v1.29, §5 R3 y R4, §8). Solo se añaden campos; nada cambia de forma.
> 1. **`estado_actual().hoy`** (§4.3): cada tarea trae también **`iniciada_en`**, **`terminada_en`** y **`minutos`** (de inicio a fin; hasta ahora si está en curso; `null` si no ha empezado). Para «Hoy» con hora de inicio, hora de fin y minutos.
> 2. **`estado_actual().tiempo_libre`** (nuevo): `{ veces, minutos }` de «Orden y limpieza» hoy (la que está en curso cuenta hasta ahora). Para el bloque «Tiempo libre».
> 3. **`estado_actual().cobertura_baja`** (nuevo, R4): `{ datos_leidos_en, productos: [{ producto, formato, total, necesidad_semana, semanas, motivo }], avisos }`, **solo** los productos con menos de 2 semanas, de menos a más semanas. Para «Productos con menos de 2 semanas», siempre a la vista; si `productos` está vacío, no hay ninguno por debajo. Viene de la última lectura de la hoja del reparto, el envío o la lista de stock (`datos_leidos_en`): abrir el panel no lee la hoja.
> 4. **`almacen_ahora`** sigue en `estado_actual`, pero el panel ya no lo muestra (decisión del propietario, 29/10/2026).
> 5. **`lista_stock`** (§3.9): el mini (**MINI 10g**) ya no sale en la lista; aparece en `excluidos`.


> **Cambios en 1.3 (Tarea 14) — para Lovable: almacén ahora y pedidos de tienda que activan el reparto** (`ESTADO_DEL_SISTEMA.md` v1.27, §5 R1c; decisión del propietario del 28/10/2026).
> 1. **`estado_actual`** (§4.3) trae un bloque nuevo, **`almacen_ahora`**, solo para mostrar: la hora del último recuento, la de la última lectura de la hoja, por referencia con movimiento desde el recuento `hoja`, `producido`, `salido` y `ahora`, y lo que va `en_camino` a cada tienda.
> 2. **`catalogo`** (§3.13) trae **`pedidos_cliente`**: los pedidos para recoger en tienda que van en el reparto de hoy. En «Preparar reparto» se muestran **marcados y fijos** en su tienda, con su `texto` («Pedido de Ane a tienda de Bilbao») y sus cajas; no se pueden quitar.
> 3. **`guardar_reparto`** (§3.14): si hay pedidos de tienda esperando, el reparto se puede guardar **sin productos** (solo con los pedidos). Sin pedidos, sigue haciendo falta al menos un producto.
> 4. **`terminar_tarea`** (§3.3): «Prepara el reparto» con un pedido de tienda esperando **no se cierra sin reparto**, ni con motivo: error nuevo **`PEDIDO_ESPERANDO_REPARTO`** (mostrar el mensaje y llevar a «Preparar reparto»).
> 5. **`guardar_pedido_cliente`** (§3.16): un pedido para recoger en tienda entra en el reparto de hoy mientras las bolsas no estén listas; si el reparto ya está guardado, entra al momento (sale con `estado: "por_preparar"` y su tarea aparece ya). La forma de la respuesta no cambia.
> 6. Los cálculos del reparto, el envío, el «coge / haz» y la lista del +35 % usan el **almacén ahora** (hoja + lo producido − lo salido desde el recuento) y las cajas en camino con hora (reparto hasta las 23:30, envío hasta las 11:59 del día siguiente). Las respuestas no cambian de forma; en `lista_stock`, el `motivo` explica lo hecho desde el recuento y lo que va en camino.


> **Cambios en 1.2 (Tarea 13) — para Lovable: peticiones especiales e histórico** (`ESTADO_DEL_SISTEMA.md` v1.26, §5 R1d y §8).
> 1. **Peticiones especiales en `guardar_reparto`** (§3.14): campo nuevo `peticiones: [{ destino_id, texto }]`, una por línea de la casilla «Peticiones especiales para [tienda]» (texto libre, 120 letras como máximo; las vacías se ignoran). Vale para el reparto y para el envío. La respuesta trae `peticiones` y el `texto_whatsapp` lleva «Además: …» tras los productos de cada tienda.
> 2. **En las bolsas** (§3.2): cada petición es un elemento con `tipo: "peticion"`, `texto` y `cantidad` 1, en la bolsa de su tienda después de las cajas. Mostrarlas bajo **«Además, mete:»**, una por una para tocarlas; se marcan con **`marcar_cajas(elemento_id, 1)`** (o 0 para desmarcar). La bolsa no se termina hasta tocarlas todas.
> 3. **`reparto_de_hoy_detalle`** (§3.15) devuelve también `peticiones`, para abrir «Modificar reparto» con las casillas rellenas.
> 4. **Histórico** (§4.5, solo Administración): **`historico_dia(fecha)`** (reparto y envío con quién salió, tiendas, cajas, peticiones y texto para WhatsApp; pedidos de cliente; cierres; tareas hechas y no hechas) e **`historico_dias(desde, hasta)`** (qué días tienen algo, para marcar el calendario). Solo consulta.


> **Cambios en 1.1 (Tarea 12) — para Lovable: pedidos de cliente con la lista** (`ESTADO_DEL_SISTEMA.md` v1.24, §5 R1b y R1c).
> 1. **`guardar_pedido_cliente(id_cliente, lineas, entrega, destino_id?, cliente, datos_envio?)`** (función del servidor, §3.16; operario y Administración): botón **«Pedido de cliente»**, con **la misma lista** que el reparto (`catalogo`, sin tienda en cada línea) y cómo se entrega: **recoger en tienda** (una de `catalogo().tiendas.reparto`) o **envío por Nacex** (se pegan los datos de envío tal cual).
> 2. **`pedidos_cliente_abiertos()`** (base de datos, §3.17; operario y Administración): los pedidos que siguen abiertos, con cliente, entrega, estado y fecha.
> 3. Recoger en tienda: va en el **siguiente reparto** y `guardar_reparto` lo asigna solo (§3.14, campo `pedidos_cliente`). En las bolsas, la tienda tiene **«Bolsa de reposición»** y aparte **«Pedido de cliente · [cliente]»**: cada elemento de bolsas trae el campo nuevo **`bolsa`** (§3.2). El operario tiene la tarea «Hay un pedido de cliente para dejar en [tienda] · [cliente]» **al terminar la producción del reparto**.
> 4. Nacex: el operario tiene «Prepara el pedido de cliente (Nacex) · [cliente]», con los **datos de envío en `porque`** (varias líneas: mostrarlas tal cual) y la lista. Entran hasta las **18:00** (el viernes, hasta las 10:45); después, al siguiente día de trabajo.
> 5. **«Coge / haz» al salir la tarea:** cuando al operario le sale la tarea del pedido (de tienda o de Nacex), cada referencia dice en `motivo` **«Coge N del almacén»** o **«Haz N»** (o las dos), calculado en ese momento con la última lectura de la hoja.
> 6. **`aplazar_pedido_nacex(pedido_id, motivo?)`** (base de datos, §3.18; operario y Administración): si por la producción un pedido de Nacex no llega a salir ese día, se pasa al día siguiente (botón en la tarea). Si queda sin hacer, pasa solo.
> 7. La opción `pedido_cliente` de `crear_incidencia` y `registrar_evento('pedido_cliente')` quedan **obsoletas para las pantallas** (siguen funcionando).
> 8. «Prepara el reparto» dice quién lo preparó por su nombre: «Reparto preparado por Asier».

> **Cambios en 1.0 (Tarea 10) — para Lovable: el reparto se prepara con una lista, ya no se pega texto** (`ESTADO_DEL_SISTEMA.md` v1.21, §5 R1).
> 1. **`catalogo()`** (función del servidor, §3.13): tiendas del reparto (Bilbao, Algorta, Barakaldo, Basauri, Portu) y del envío (Gipuzkoa, Durango), en ese orden, y las referencias de PRINCIPAL (producto + formato) en el orden de la hoja, con su categoría. Para montar la lista.
> 2. **`guardar_reparto(id_cliente, tipo, sale?, lineas)`** (función del servidor, §3.14): guarda el reparto o el envío preparado con la lista. Mismo cálculo y misma sustitución que antes; devuelve además `texto_whatsapp`, que la pantalla copia **tal cual** con un botón para pegarlo en el grupo (sin abreviar).
> 3. **`reparto_de_hoy_detalle(tipo)`** (base de datos, §3.15): las líneas del reparto (o envío) de hoy, para abrir «Modificar reparto» con la lista ya rellena, con su `texto_whatsapp` y quién sale.
> 4. La tarea del operario se llama **«Prepara el reparto»** (la clave sigue siendo `pegar_reparto`) y se cierra sola al guardarse un reparto, con el resultado «Reparto preparado» o «Reparto preparado por Administración».
> 5. **`pegar_reparto` queda obsoleta** (§3.8): sigue funcionando, pero las pantallas ya no la usan.

> **Cambios en 0.9 (Tarea 9) — para Lovable:** `estado_actual` trae también `reparto_de_hoy` (el mismo objeto que `tarea_activa`: `{ reparto_id, aceptado_en, pegado_por, pegado_por_nombre }` o `null`), para que el panel de Administración muestre «Pegar reparto» o «Modificar reparto». Nada más cambia.

> **Cambios en 0.8 (Tarea 8) — para Lovable:**
> 1. **Desplegable «¿Quién sale?» al pegar el reparto:** se manda en `pegar_reparto` como `sale` (`"operario"` | `"administracion"`) y **manda sobre la línea `SALE:`** del texto, que pasa a ser opcional. Si no coinciden, no es un error (queda anotado). Sin desplegable ni `SALE:`, sigue `FALTA_SALE`.
> 2. **Nueva función `cambiar_quien_sale(sale)`** (operario y Administración): cambia quién sale hoy sin volver a pegar el reparto. Si el mismo texto ya estaba pegado (`REPARTO_YA_PEGADO`) y solo cambia el desplegable, la pantalla llama a esta función.
> 3. **`mi_perfil`** trae `quien_sale_opciones: [{ valor: "administracion", nombre }, { valor: "operario", nombre }]` para rellenar el desplegable con los nombres.

> **Cambios en 0.7 (Tarea 7) — para Lovable:**
> 1. **Incidencias nuevas** (§3.11): `crear_incidencia(id_cliente, opcion, descripcion, quien?, importancia?, tarea_id?, tipo_problema?)`, `incidencias_abiertas()` y `cerrar_incidencia(incidencia_id, nota?)`. Botón **Incidencia** con seis opciones; «Estoy bloqueado» (`opcion: "bloqueado"`) es el flujo de problemas de siempre y sustituye al botón «Tengo un problema». Botón **Cerrar incidencias** con el número de abiertas.
> 2. **`tarea_activa`** trae además `reparto_de_hoy` (para «Pegar reparto» / «Modificar reparto»), `incidencias_abiertas` (número), `incidencia_en_curso` y `problemas_abiertos`: al recargar, la pantalla recupera todo de ahí (§3.2).
> 3. **`pegar_reparto`** también desde Administración (va a la jornada del operario por defecto). «Pega el reparto» se cierra sola al aceptarse el reparto; terminarla sin reparto pide motivo (`MOTIVO_OBLIGATORIO`).
> 4. **Nunca sin tarea:** si no queda nada, `tarea_activa` adelanta las fijas de la tarde y después «Orden y limpieza», que no se gasta. `tarea` solo es `null` fuera del turno.
> 5. `estado_actual` trae `incidencias_abiertas`; el cierre trae las incidencias con opción, quién, estado y tiempo.
> 6. `iniciar_incidencia` / `terminar_incidencia` y `registrar_evento` siguen funcionando igual, pero la pantalla nueva del operario usa `crear_incidencia`.

> **Cambios en 0.6 (Tarea 6):** en `crear_tarea_admin`, las obligatorias que ya han vencido sin hacerse ocupan tiempo (se restan del disponible) aunque no estén «en riesgo»; el objeto `conflicto` trae además `vencidas_min`. Nada más cambia para las pantallas.

> Esto es lo único que las pantallas (Lovable) pueden usar. Cualquier dato o función nueva se pide al coordinador (§11 de `ESTADO_DEL_SISTEMA.md`).
> **Para empezar las pantallas: §7 «Guía para las pantallas»** (conexión, inicio de sesión con Google, cómo llamar a cada función, tiempo real y errores).

---

## 1. Reglas comunes

- **Dos tipos de llamada:**
  - **Funciones de base de datos** (`supabase.rpc('nombre', {...})`): todo lo que no necesita Google Sheets.
  - **Funciones del servidor** (`supabase.functions.invoke('nombre', {...})`): las que leen Sheets (`catalogo`, `guardar_reparto`, `guardar_pedido_cliente` y `lista_stock`; `pegar_reparto`, obsoleta).
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
| `resolver_sin_granel` | BD | ✔ | — | ✅ Tarea 16 |
| `catalogo` · `guardar_reparto` | Servidor | ✔ | ✔ | ✅ Tarea 10 |
| `reparto_de_hoy_detalle` | BD | ✔ | ✔ | ✅ Tarea 10 |
| `lista_stock` | Servidor | ✔ | ✔ (consulta) | ✅ Tarea 3 |
| `pegar_reparto` (**obsoleta**, la sustituye `guardar_reparto`) | Servidor | ✔ | ✔ | ✅ Tarea 3 y 7 |
| `retrasar_salida` | BD | ✔ | — | ✅ Tarea 4 |
| `cambiar_quien_sale` | BD | ✔ | ✔ | ✅ Tarea 8 |
| `registrar_evento` | BD | ✔ | ✔ (solo `pedido_cliente`, obsoleto desde la Tarea 12) | ✅ Tarea 4 |
| `abrir_problema` · `problema_llamada` · `resolver_problema` | BD | ✔ | ✔ (`resolver_problema`) | ✅ Tarea 4 |
| `crear_incidencia` · `incidencias_abiertas` · `cerrar_incidencia` | BD | ✔ | — | ✅ Tarea 7 |
| `guardar_pedido_cliente` | Servidor | ✔ | ✔ | ✅ Tarea 12 |
| `pedidos_cliente_abiertos` · `aplazar_pedido_nacex` | BD | ✔ | ✔ | ✅ Tarea 12 |
| `iniciar_incidencia` · `terminar_incidencia` (las de antes) | BD | ✔ | — | ✅ Tarea 4 |
| `crear_tarea_admin` · `cancelar_tarea` · `estado_actual` | BD | — | ✔ | ✅ Tarea 4 |
| `historico_dia` · `historico_dias` | BD | — | ✔ | ✅ Tarea 13 |
| `cierre` · `cierres_recientes` | BD | — | ✔ | ✅ Tarea 4 |
| `generar_jornada` · `generar_cierre` · `enviar_correo` | Internas | — | — | ✅ |

## 3. Operario

### 3.1 `mi_perfil()` ✅
- **Salida:** `{ id, nombre, rol, centro: {id, nombre} | null, telefono_administracion, quien_sale_opciones }`
- `quien_sale_opciones` ✅ Tarea 8: `[{ "valor": "administracion", "nombre": "…" }, { "valor": "operario", "nombre": "…" }]`, con los nombres de las fichas (Administración y el operario por defecto), para el desplegable «¿Quién sale?».
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
  "siguiente": "Salida del reparto · 10:45",
  "reparto_de_hoy": { "reparto_id": "...", "aceptado_en": "2026-11-03T07:48:00+00:00", "pegado_por": "<persona_id>", "pegado_por_nombre": "Administración", "paradas": [] },
  "incidencias_abiertas": 2,
  "incidencia_en_curso": { "id": "...", "opcion": "corregir", "descripcion": "...", "estado_texto": "En curso desde las 15:47", "minutos": 10, "...": "(objeto incidencia, §3.11)" },
  "problemas_abiertos": [ { "id": "...", "tarea_id": "...", "tarea": "Revisar el envío", "tipo": "no_encuentro", "descripcion": "...", "estado": "abierto|sin_respuesta", "llamadas": 0, "proxima_llamada_en": null } ]
}
```
- `jornada` es `null` si hoy no trabaja; `tarea` es `null` solo fuera del turno (antes de empezar o entre turnos).
- **Nunca sin tarea** (v1.17): si dentro del turno no queda nada disponible, se adelantan las tareas fijas de la tarde de ese día (minis el lunes, resinas el martes, control de materiales el jueves) y después «Orden y limpieza», que **no se gasta** (al terminarla vuelve a salir). Lo ligado a su hora (recuento, revisión del envío, Nacex, salida) espera a su hora.
- `reparto_de_hoy`: el reparto aceptado hoy (`null` si no hay). Con él, el botón de arriba dice «Modificar reparto» (abre la lista con `reparto_de_hoy_detalle`); sin él, «Preparar reparto».
- `reparto_de_hoy.paradas` ✅ Tarea 16 (R1e): `[{ origen_id, origen, destino_id, destino, producto, formato, cantidad, texto }]`, lo que quien hace la ruta recoge en una tienda para dejarlo en otra («Recoge 2 BZ1 4g en Algorta y déjalas en Portugalete»). Mostrarlo en «Salida del reparto» si sale el operario. Lista vacía si no hay. (También en `estado_actual().reparto_de_hoy`, para el panel si sale Administración.)
- **Al recargar** la pantalla recupera de aquí todo lo abierto: `incidencias_abiertas` (número para «Cerrar incidencias»), `incidencia_en_curso` (la que tiene su tarea en curso, con `minutos`; `null` si no hay) y `problemas_abiertos` (con la tarea bloqueada; el siguiente paso es `problema_llamada` o `resolver_problema`).
- `siguiente`: una línea con lo que viene después. Si antes llega una tarea con hora, se anuncia esa con su hora.
- `pregunta`: reservado; hoy siempre `null`. La pregunta «¿Quién sale hoy?» la devuelve `pegar_reparto` (`FALTA_SALE`).
- `elementos` ✅: `[ { id, tipo, producto, formato, texto, categoria, destino, destino_id, bolsa, cantidad, cantidad_hecha, motivo, orden_sugerido, estado } ]`. En bolsas, agrupar por `destino` (una tienda por pantalla) y, dentro de la tienda, por `bolsa`: «Bolsa de reposición» y, si hay pedidos de cliente, «Pedido de cliente · [cliente]» (Tarea 12). **Peticiones especiales** (Tarea 13): `tipo: "peticion"`, con su texto en `texto` (y en `producto`), `cantidad` 1 y `formato` vacío; van en la bolsa de su tienda después de las cajas, para mostrarlas bajo «Además, mete:». En los demás elementos, `texto` es `null`. En las listas de producción, `bolsa` es `null`; en los pedidos de cliente, `motivo` dice «Coge N del almacén» o «Haz N».
  - **Aviso de llamada** (Tarea 16, R1e): `tipo: "llamada"`, en la bolsa de reposición de la tienda que recibe algo de otra tienda, con su `texto` («Llama a Algorta para que prepare 2 BZ1 4g para su retirada») y `cantidad` 1. Se muestra y se marca como una petición especial; la tienda no está completa sin él.
  - **Referencia sin granel** (Tarea 16, R1e), solo en «Producción del reparto»: además trae `sin_granel: true`, `para: [{ destino_id, destino, pedido, faltan }]` (las tiendas que la reciben; lo que hay en el almacén se lo llevan las primeras del reparto), `tiendas_con_stock: [{ destino_id, destino, cajas }]` (las demás tiendas del reparto con cajas de esa referencia en PRINCIPAL), `resuelto` y `decisiones: [{ destino_id, destino, accion, origen_id, origen, cantidad }]`. Sin resolver, al elegirla sale el aviso «No hay granel» con las dos opciones por tienda (§3.19). Resuelta, queda `estado: "hecho"`, `cantidad` 0 y `motivo` «No se produce: 3 se quitan de Bilbao; 2 para Portugalete de Algorta.».
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
  - «Prepara el reparto» se cierra sola al guardarse un reparto (lo prepare quien lo prepare). Terminarla sin reparto exige `motivo`: si no, `MOTIVO_OBLIGATORIO`. ✅ Tarea 7 y 10
  - Con un pedido para recoger en tienda esperando, no se puede terminar sin reparto, ni con motivo: `PEDIDO_ESPERANDO_REPARTO` («Hay un pedido de cliente para recoger en Bilbao (Ane). Prepara el reparto, aunque sea solo con el pedido.»), con el pedido en `error.pedido` (§3.17). ✅ Tarea 14
  - Una tarea con lista se cierra sola cuando se termina su último elemento; no hace falta pulsar «Terminada».
- **Salida (ambas):** `{ "tarea": {...}, "tarea_activa": {...} }` (la nueva respuesta de `tarea_activa`).

### 3.4 `anotar_motivo(tarea_id, motivo)` ✅
Para que una tarea que no se va a hacer conste en el cierre con su motivo. No cambia el estado. `DATOS_NO_VALIDOS` si el motivo está vacío; `ESTADO_NO_VALIDO` si la tarea ya está cerrada. **Salida:** `{ "tarea": {...} }`.

### 3.5 `iniciar_elemento(elemento_id)` · `terminar_elemento(elemento_id)` · `marcar_cajas(elemento_id, cantidad_hecha)` ✅
- `iniciar_elemento`: el operario elige la referencia o la tienda (él decide el orden, §8). Inicia también la tarea si estaba pendiente.
- `terminar_elemento`: **punto de encaje** (§6.4). En producción, al terminar cada referencia; **en bolsas, al terminar la tienda entera** (decidido). Si hay pendiente una tarea con hora ya vencida o una urgente, la tarea con lista vuelve a `pendiente` (conservando lo hecho) y la respuesta trae la nueva `tarea_activa`.
- `marcar_cajas`: en las bolsas, fija cuántas cajas lleva metidas (valor absoluto, de 0 a `cantidad`). Una petición especial (Tarea 13) o un aviso de llamada (Tarea 16) se marca igual, con 1 (hecho) o 0; la tienda no está completa, ni la bolsa terminada, hasta tocarlos todos.
- `terminar_elemento` es para referencias de producción; en bolsas se usa `marcar_cajas` (si no: `DATOS_NO_VALIDOS`).
- Repetir cualquiera de las tres no es error: devuelve el estado ya alcanzado.
- **Salida:** `{ "elemento": { id, estado, cantidad, cantidad_hecha }, "tarea_activa": {...} }`.
- **Errores:** `CANTIDAD_FUERA_DE_RANGO`, `OTRO_ELEMENTO_EN_CURSO`, `OTRA_TAREA_EN_CURSO`, `NO_ENCONTRADO`, `ESTADO_NO_VALIDO`.

### 3.6 `retrasar_salida(id_cliente, minutos)` ✅
Botones «Retrasar 15 min» y «Retrasar 30 min» de la tarea de bolsas (bolsas listas en la mesa de salida a las 10:45, §4).
- **Entrada:** `minutos` (15 o 30) e `id_cliente`.
- **Efecto:** suma los minutos a la hora límite de las bolsas, de la producción del reparto, del envío del viernes y de los pedidos de cliente que salen con el reparto (Tarea 12), y a la hora de la salida (y de Nacex el viernes). Se puede retrasar varias veces (cada vez desde la última hora). Queda registrado. Si sale Administración, se le envía en el momento un correo «Salida retrasada a las HH:MM» y se ve en `estado_actual`. El cierre de la mañana lo cruza con las cajas del reparto y las incidencias de la mañana.
- **Salida:** `{ "nueva_hora_salida": "11:00", "minutos": 15, "aviso": "correo"|"sin_aviso", "tarea_activa": {...} }`. Repetir con el mismo `id_cliente` devuelve lo mismo sin mover nada.
- **Errores:** `DATOS_NO_VALIDOS` (no es 15 ni 30), `SIN_TAREA` (aún no hay bolsas: falta preparar el reparto), `ESTADO_NO_VALIDO` (las bolsas ya están listas), `SIN_JORNADA`.

### 3.7 `registrar_evento(id_cliente, tipo, detalle?)` ✅
`llega_mercancia` (recepción, urgente), `pedido_cliente` (botón «Pedido de cliente»), `no_quedan_vapers` (tirada de vapers). Crea la tarea correspondiente en la jornada de hoy; el `detalle` pasa a ser su «por qué». Administración solo puede registrar `pedido_cliente`, que va a la jornada del operario del almacén.
- **Salida:** `{ "evento_id", "tarea": {...}, "tarea_activa": {...} }` (`tarea_activa` solo al operario). Repetir con el mismo `id_cliente` no duplica.
- **Errores:** `DATOS_NO_VALIDOS`, `NO_AUTORIZADO` (Administración con otro tipo), `SIN_JORNADA`.
- **`pedido_cliente`, obsoleto para las pantallas desde la Tarea 12:** el pedido de cliente se registra con `guardar_pedido_cliente` (§3.16). Sigue funcionando.
- Desde la Tarea 7 la pantalla del operario usa `crear_incidencia` (llega mercancía y pedido de cliente crean esta misma tarea por dentro). `registrar_evento` sigue funcionando igual (lo usa Administración para un pedido de cliente).

### 3.8 `pegar_reparto` (función del servidor) ✅ — **obsoleta desde la Tarea 10**
> Sigue publicada y funcionando, pero las pantallas ya no la usan: el reparto se prepara con la lista (`catalogo` + `guardar_reparto`, §3.13 y §3.14). Se quitará cuando lo decida el coordinador.

- **Entrada:** `{ texto, tipo: "reparto"|"envio", sale?: "operario"|"administracion", confirmar_fecha?: true }`
- **`sale` = desplegable «¿Quién sale?»** ✅ Tarea 8: si llega, **manda sobre la línea `SALE:`** del texto (que pasa a ser opcional). Si el texto dice otra cosa, o trae dos `SALE:` distintas, no es un error: se acepta con lo del desplegable y queda anotado en el registro (`sale_distinto_del_texto`). Sin `sale` y sin `SALE:` → `FALTA_SALE`. Sin desplegable, dos `SALE:` distintas siguen siendo `REPARTO_CON_ERRORES` (`SALE_CONTRADICTORIA`).
- Si el mismo texto ya estaba pegado, responde `REPARTO_YA_PEGADO` y **no cambia quién sale**: para eso, `cambiar_quien_sale` (§3.12).
- **Proceso:** lee Sheets, interpreta el texto según `REGLAS_CALCULO.md` §2 y, si no hay errores, crea o actualiza las tareas «Producción del reparto» y «Bolsas» con sus elementos. Si ya había un reparto aceptado hoy, lo sustituye conservando lo hecho (§5 R1).
- **Quién:** el operario o **Administración** (Tarea 7). Si lo pega Administración, va a la jornada del operario por defecto, con el mismo cálculo y la misma sustitución; la respuesta no trae `tarea_activa`. Sin jornada del operario ese día: `SIN_JORNADA`.
- Al aceptarse un reparto, la tarea «Prepara el reparto» queda hecha («Reparto preparado» si lo prepara el operario, o «Reparto preparado por [nombre]», p. ej. «Reparto preparado por Asier», desde la Tarea 12; antes de la Tarea 10, «Reparto pegado»).
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
- **Salida (operario):** `{ tarea, ya_calculado, lote, faltas, avisos, excluidos, datos_leidos_en }`. `faltas` = productos sin granel (se crea la tarea «Avisa a Administración: falta X»); `avisos` = datos que no se han podido calcular; `excluidos` = minis (MINI 10g) y vapers.
- **Salida (Administración, consulta):** `{ lista, faltas, avisos, excluidos, datos_leidos_en }`, sin guardar nada.
- **Cajas de todas partes** (R1c, rehecha en la Tarea 14): el contador suma lo hecho desde el último recuento, resta lo que ha salido del almacén (los pedidos de Nacex salen del stock) y suma lo que va en camino a las tiendas (el reparto hasta las 23:30; el envío hasta las 11:59 del día siguiente). El elemento dice en `en_camino` las cajas en camino que la hoja aún no cuenta, y el `motivo` lo explica («Tienes +25 (con 6 hechas desde el recuento y 5 en camino a las tiendas)…»).
- **Errores:** `SHEETS_NO_DISPONIBLE`, `ESTRUCTURA_SHEETS_CAMBIADA`, `SIN_TAREA`, `SIN_JORNADA`.

**Quién llama a las funciones del servidor:** la sesión del usuario (cabecera `Authorization`, como hace `supabase.functions.invoke`) o una solicitud interna de un solo uso creada por la base de datos (cabecera `x-solicitud`). Las funciones comprueban la sesión ellas mismas.

### 3.10 Problemas e incidencias ✅
| Función | Entrada | Efecto |
| --- | --- | --- |
| `abrir_problema` | `id_cliente, tarea_id, tipo, descripcion` | `tipo`: `falta_material` · `no_encuentro` · `no_se_hacerlo` · `no_funciona` · `otro`. La tarea pasa a `bloqueada` y el operario sigue con la siguiente. Devuelve `{ problema, pasos, tarea_activa }`; `pasos`: «Si en 1 minuto no está resuelto, llama a Administración.» (con `no_encuentro`: «Llama a Administración ahora.»). |
| `problema_llamada` | `problema_id, contestada` | `true`: pide escribir la solución. `false`: registra la llamada y el WhatsApp; **30 min después del WhatsApp** aparece la tarea «Llama a Administración: …» (escalón 2). Cada llamada deja hecha la anterior. |
| `resolver_problema` | `problema_id, solucion` | Solución obligatoria (una línea). La tarea vuelve a `pendiente` y se retira la llamada pendiente. También Administración, para cualquier problema. Devuelve `{ problema }` con `minutos_hasta_solucion`. |
| `iniciar_incidencia` · `terminar_incidencia` (las de antes) | `id_cliente, descripcion` · `incidencia_id` | Qué y por qué en una línea; guarda la tarea que estaba en curso y queda registrada con su tiempo (`minutos`). Una sola de estas abierta a la vez. Siguen funcionando, pero la pantalla nueva usa §3.11. |

**Errores:** `PROBLEMA_YA_ABIERTO` (la tarea ya tiene uno), `SOLUCION_OBLIGATORIA`, `INCIDENCIA_YA_ABIERTA`, `DATOS_NO_VALIDOS`, `NO_ENCONTRADO` (no es suyo), `ESTADO_NO_VALIDO` (la tarea no está abierta hoy). Resolver o llamar sobre un problema ya resuelto devuelve `aviso: PROBLEMA_YA_RESUELTO`, sin error.

**Campos de los errores de «ya abierto»** (confirmados en la Tarea 7):
- `PROBLEMA_YA_ABIERTO` → `{ error: { codigo, mensaje, problema: { id, tarea_id, tipo, descripcion, estado, abierto_en, llamadas, whatsapp_en, proxima_llamada_en, solucion, resuelto_en, minutos_hasta_solucion } } }`. La pantalla muestra ese problema y sigue su flujo (`problema_llamada` / `resolver_problema`).
- `INCIDENCIA_YA_ABIERTA` (solo `iniciar_incidencia`, la de antes) → `{ error: { codigo, mensaje, incidencia_id, incidencia: {...objeto de §3.11} } }`. Con el modelo nuevo puede haber varias incidencias abiertas, así que `crear_incidencia` nunca devuelve este error.

### 3.11 Incidencias (modelo nuevo, Tarea 7) ✅
Botón **Incidencia**: el operario elige qué pasa, escribe una línea y puede cambiar quién la resuelve y la importancia (§6.6).

**`crear_incidencia(id_cliente, opcion, descripcion, quien?, importancia?, tarea_id?, tipo_problema?)`**

| `opcion` | Texto | `quien` por defecto | `importancia` por defecto |
| --- | --- | --- | --- |
| `llega_mercancia` | Llega mercancía | `operario` | `ahora` |
| `pedido_cliente` | Pedido de cliente (**obsoleta desde la Tarea 12**: usar `guardar_pedido_cliente`, §3.16) | `operario` | `hoy` |
| `pedir_comprar` | Hay que pedir o comprar algo | `operario` (la pantalla ofrece cambiarlo a `administracion` para materia prima y packaging, §7) | `hoy` |
| `recogida_nacex` | Recogida en Nacex | `operario` | `hoy` |
| `corregir` | Corregir, limpiar o solucionar algo | `operario` | `ahora` |
| `bloqueado` | Estoy bloqueado | — | — |

- `quien`: `operario` | `administracion`. `importancia`: `ahora` | `hoy` | `cuando_pueda`. `descripcion`: una línea (los saltos de línea se juntan).
- **La resuelve él** (`quien: operario`): se crea su tarea. `ahora` entra como las urgentes (al terminar la referencia o la bolsa en curso); `hoy` es obligatoria del día; `cuando_pueda` va a su cola de tiempo libre. Lo que no se hace pasa al día siguiente con su incidencia. Llega mercancía y pedido de cliente crean la tarea de siempre («Recepción de mercancía», «Pedido de cliente»); el resto, «Pedir o comprar: …», «Recogida en Nacex: …» o «Corregir: …». **Al hacer la tarea, la incidencia se cierra sola**, salvo `pedir_comprar`, que queda «Pedido, esperando a que llegue» y se cierra a mano.
- **La resuelve Administración** (`quien: administracion`): no crea tarea; se le envía **en el momento** un correo «Incidencia: …» (mismo sistema y reintentos que el cierre). Queda «Esperando a Administración» hasta que él la cierra.
- **`bloqueado`**: es `abrir_problema` sobre `tarea_id` (por defecto, la tarea en curso o la que le toca), con `tipo_problema` (`falta_material` · `no_encuentro` · `no_se_hacerlo` · `no_funciona` · `otro`; por defecto `otro`). Devuelve lo mismo que `abrir_problema` (`problema`, `pasos`, `tarea_activa`) con `incidencia: null`; después sigue con `problema_llamada` y `resolver_problema`. Sin ninguna tarea abierta: `SIN_TAREA`.
- **Salida:** `{ incidencia, tarea (null si la resuelve Administración), tarea_activa }`. Repetir con el mismo `id_cliente` devuelve la misma incidencia.
- **Errores:** `DATOS_NO_VALIDOS` (opción, descripción, quién o importancia no válidos), `SIN_JORNADA`, `SIN_TAREA`, `PROBLEMA_YA_ABIERTO` (con `bloqueado`).

**Objeto incidencia:** `{ id, opcion, opcion_texto, descripcion, quien, importancia, estado: "abierta"|"esperando_llegada"|"esperando_administracion"|"cerrada", estado_texto, abierta_en, desde ("HH:MM"), fecha, cerrada_en, nota, tarea_id, minutos }`.
- `estado_texto` es la frase para mostrar: «Va ahora, al terminar lo que tienes entre manos», «Pendiente para hoy», «En tu cola de tiempo libre», «En curso desde las HH:MM», «Bloqueada por un problema», «Pedido, esperando a que llegue», «Esperando a Administración», «Su tarea se ha cancelado: ciérrala si ya está resuelta», «Cerrada a las HH:MM».
- `minutos`: el tiempo de su tarea, de inicio a fin (o hasta ahora si está en curso; `null` si aún no se ha empezado). Si no tiene tarea (la resuelve Administración), desde que se abrió hasta que se cierra.

**`incidencias_abiertas()`** → `{ total, incidencias: [objeto incidencia, ...] }`, las suyas sin cerrar (de cualquier día), de la más antigua a la más nueva. Para la pantalla «Cerrar incidencias».

**`cerrar_incidencia(incidencia_id, nota?)`** → `{ incidencia, tarea_activa }`. `nota`: una línea opcional (ej. «Ya está en el almacén»). Si su tarea seguía abierta, se cancela («Ya no hace falta: incidencia cerrada»). Ya cerrada: `aviso: INCIDENCIA_YA_CERRADA`, sin error. De otro: `NO_ENCONTRADO`.

Solo el operario: Administración recibe `NO_AUTORIZADO`. Cada incidencia queda registrada con su hora, su tiempo y su cierre, y sale en el cierre del turno (§4.4).

### 3.12 `cambiar_quien_sale(sale)` ✅ (Tarea 8)
Cambia quién sale hoy sin volver a pegar el reparto. Para el operario (su jornada) y para Administración (la jornada de hoy del operario por defecto).
- **Entrada:** `sale`: `"operario"` | `"administracion"`.
- **Efecto:** si sale el operario, aparecen «Salida del reparto» (10:45, después de «Bolsas listas en la mesa de salida») y, a la vuelta, «Efectivo y reporte»; si sale Administración, esas dos se retiran (con su motivo). Queda anotado quién lo cambió (`quien_sale_cambiado`). Repetirlo con el mismo valor no cambia nada (`cambiado: false`).
- **Salida:** `{ sale, antes, cambiado, tareas: [{ clave, titulo, estado }] (salida y efectivo), tarea_activa (solo al operario) }`.
- **Errores:** `DATOS_NO_VALIDOS` (valor no válido), `SIN_JORNADA`, `ESTADO_NO_VALIDO` (la salida ya ha empezado o está hecha).

### 3.13 `catalogo` (función del servidor) ✅ (Tarea 10)
Lo que se puede elegir al preparar el reparto o el envío. Solo lee (la hoja y la base de datos); no guarda nada.
- **Quién:** el operario y Administración.
- **Entrada:** ninguna.
- **Salida:**
```json
{
  "tiendas": {
    "reparto": [ { "id": "...", "codigo": "BILBAO", "nombre": "Bilbao" }, { "id": "...", "codigo": "ALGORTA", "nombre": "Algorta" }, "…" ],
    "envio":   [ { "id": "...", "codigo": "GIPUZKOA", "nombre": "Gipuzkoa (envío a Rentería)" }, { "id": "...", "codigo": "DURANGO", "nombre": "Durango" } ]
  },
  "productos": [
    { "clave": "V2|4g", "producto": "V2", "formato": "4g", "categoria": "INVERNADERO", "orden": 2300 },
    { "clave": "SUGAR|CBD", "producto": "SUGAR", "formato": "CBD", "categoria": "HIGH TECH", "orden": 5100 }
  ],
  "pedidos_cliente": [
    { "id": "...", "cliente": "Ane", "destino_id": "...", "destino": "Bilbao", "texto": "Pedido de Ane a tienda de Bilbao",
      "lineas": [ { "producto": "V2", "formato": "4g", "cantidad": 3 } ] }
  ],
  "datos_leidos_en": "2026-11-03T07:47:12.000Z"
}
```
- `pedidos_cliente` (Tarea 14): los pedidos para recoger en tienda que van en el reparto de hoy (los que esperan y los que ya van en él). En «Preparar reparto» y «Modificar reparto» se muestran **marcados y fijos** en su tienda, con su `texto`; la pantalla no los manda en `lineas`: `guardar_reparto` los añade solo. Lista vacía si no hay.
- `tiendas.reparto`: BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU. `tiendas.envio`: GIPUZKOA, DURANGO. **En el orden de las hojas de tienda de STOCK OSASUN** (decisión del propietario, 28/10). Donosti y Rentería no salen: sus hojas son solo de consulta. La lista y el orden están en la configuración (`destinos_reparto`), así que se pueden cambiar sin tocar las pantallas.
- `productos`: una referencia por producto y formato de PRINCIPAL (y los productos sin formato, con `formato: ""`), **en el orden de la hoja**. `clave` (`producto|formato`) es estable mientras no cambie el nombre en la hoja: sirve para la lista y para los contadores. `categoria`: el grupo de la pestaña ALMACEN; si el producto no está allí, `"Otros"`.
- **Errores:** `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` (los mismos de siempre), `CATALOGO_AMBIGUO`, `NO_AUTORIZADO`.

### 3.14 `guardar_reparto` (función del servidor) ✅ (Tarea 10)
Guarda el reparto (o el envío) preparado con la lista. **Sustituye a `pegar_reparto`** para las pantallas.
- **Quién:** el operario o Administración (va a la jornada del operario por defecto, como antes).
- **Entrada:**
```json
{
  "id_cliente": "<uuid>",
  "tipo": "reparto",
  "sale": "operario",
  "lineas": [ { "destino_id": "<id de catalogo().tiendas>", "producto": "V2", "formato": "4g", "cantidad": 5 } ],
  "peticiones": [ { "destino_id": "<id de catalogo().tiendas>", "texto": "Rollos de TPV" } ]
}
```
- `tipo`: `"reparto"` (por defecto) o `"envio"`. `sale` (`"operario"` | `"administracion"`) **es obligatorio en el reparto** (desplegable «¿Quién sale?»); en el envío no se usa.
- `lineas`: `producto` y `formato` tal como los da `catalogo`; `destino_id`, una tienda de `catalogo().tiendas.reparto` (reparto) o `.envio` (envío). `cantidad`: entero; **0 se ignora** (contador sin tocar); la misma referencia repetida en la misma tienda se suma.
- `peticiones` (opcional, Tarea 13, R1d): una por línea de la casilla «Peticiones especiales para [tienda]», con la misma tienda que las líneas (`catalogo().tiendas.reparto` o `.envio`). Texto libre de **120 letras como máximo**; los espacios de más se quitan, las vacías se ignoran y la misma petición repetida en la misma tienda cuenta una vez. Una tienda puede llevar solo peticiones, pero la lista necesita al menos un producto.
- **Reparto solo con pedidos** (Tarea 14): si hay pedidos de tienda esperando (`catalogo().pedidos_cliente`), `lineas` puede ir vacía: el reparto se guarda solo con los pedidos (sin producción) y sale como cualquier reparto (bolsas, salida, efectivo si sale el operario). Sin pedidos, hace falta al menos un producto.
- **Proceso:** vuelve a leer la hoja y **comprueba cada referencia** contra lo leído en ese momento. Con la lista escribe el texto de WhatsApp de siempre y lo calcula con R1 (`REGLAS_CALCULO.md` §2): **el mismo cálculo y la misma sustitución que al pegarlo** (si ya había reparto hoy, lo sustituye conservando lo hecho; el envío antes del recuento aparta las cajas del reparto). Crea o actualiza «Producción del reparto» y «Bolsas», y «Prepara el reparto» queda hecha.
- **Salida correcta:** la misma que `pegar_reparto` (§3.8) más `texto_whatsapp`:
```json
{
  "reparto_id": "...", "estado": "aceptado", "tipo": "reparto", "sale": "operario", "sustituye_a": null,
  "produccion": [ { "producto": "V2", "formato": "4g", "pedido": 12, "en_almacen": 9, "faltan": 3, "aviso": null } ],
  "bolsas": [ { "destino": "Bilbao", "cajas": 14, "cambia": false } ],
  "datos_leidos_en": "...",
  "tarea_activa": { "...": "solo si lo guarda el operario" },
  "texto_whatsapp": "REPARTO 03/11\nSALE: ALMACÉN\n\nBILBAO\n12x V2 4g\n\nPORTU\n2x V2 4g",
  "pedidos_cliente": [ { "...": "objeto pedido (§3.17) de los pedidos para recoger en tienda que van en este reparto" } ],
  "peticiones": [ { "destino_id": "...", "destino": "Bilbao", "texto": "Rollos de TPV" } ]
}
```
- **Peticiones especiales** (Tarea 13): se guardan con el reparto (o el envío) y van a la bolsa de su tienda (§3.2). **No van a producción ni cuentan como stock.** Al modificar, las que siguen igual conservan si ya estaban metidas, las quitadas desaparecen y una nueva vuelve a abrir la bolsa si ya estaba terminada. Vienen en `peticiones`, con el nombre de la tienda (lista vacía si no hay). Si algo no está en el almacén, el operario lo avisa con Incidencia → «Hay que pedir o comprar algo».
- **Pedidos de cliente para recoger en tienda** (Tarea 12): los que esperan al reparto de hoy entran solos al guardarlo (también al modificarlo, sin duplicarse). No cambian la producción del reparto: cada uno tiene su tarea, después de la producción, con «coge / haz» calculado al salir la tarea (después de lo oficial), y su bolsa aparte en la tienda. Vienen en `pedidos_cliente` (lista vacía si no hay).
- **Envío** (Tarea 12): mientras la hoja aún cuenta en el almacén lo que sale con el reparto (hasta el recuento de la mañana hecho después de terminar las bolsas), aparta también las cajas de los pedidos de tienda de hoy, no solo las del reparto (R1c).
- **`texto_whatsapp`:** `REPARTO dd/mm` (o `ENVÍO dd/mm`), `SALE: ALMACÉN` / `SALE: YO` (solo reparto), y por cada tienda una línea en blanco, su código en mayúsculas y `Nx PRODUCTO FORMATO`, con los nombres exactos de la hoja; si la tienda tiene peticiones especiales, después de sus productos una línea `Además: rollos de TPV; muestras de V2` (separadas por «; »). Tiendas en el orden de `catalogo` y productos en el de la hoja. La pantalla lo copia **tal cual** con un botón para pegarlo en WhatsApp: no se abrevia nada.
- **Producto sin granel** (Tarea 16, R1e): las referencias del reparto que hay que hacer y no tienen granel van a la producción con `sin_granel` (§3.2). Lo que decida el operario (§3.19) se conserva al modificar el reparto: lo de otra tienda sigue mientras la tienda lo siga pidiendo (como mucho, lo que pide ahora); lo quitado ya está en la línea, porque «Modificar reparto» la abre con la cantidad nueva. Si lo decidido ya no cubre lo que falta, la referencia vuelve a salir sin resolver. `texto_whatsapp` lleva siempre lo decidido.
- **Reintentos:** repetir con el mismo `id_cliente` devuelve lo ya guardado (con su `texto_whatsapp`), sin volver a leer la hoja ni calcular, con `ya_guardado: true` y `aviso: { codigo: "REPARTO_YA_GUARDADO" }`. Cada vez que se pulsa «Guardar» en una lista nueva o modificada, `id_cliente` nuevo.
- **Avisos (no son errores):** `REPARTO_YA_GUARDADO` (reintento) y `REPARTO_SIN_CAMBIOS` («El reparto de hoy ya era este: no cambia nada»; devuelve lo de antes con `ya_pegado: true`). Para cambiar solo quién sale, `cambiar_quien_sale` (§3.12).
- **Errores** (no se guarda nada):

| Código | Significado |
| --- | --- |
| `REFERENCIA_NO_EXISTE` | Alguna referencia ya no está en la hoja. Dice cuáles en el mensaje y en `referencias: [{ producto, formato }]`. La pantalla vuelve a pedir `catalogo` y deja quitarla. |
| `FALTA_SALE` | Reparto sin `sale`. Con el desplegable siempre relleno no aparece. |
| `DATOS_NO_VALIDOS` | Sin `id_cliente` o `tipo` no válido, cantidad no entera o negativa, tienda que no vale para ese tipo, lista vacía, o petición especial de más de 120 letras o de una tienda que no vale. |
| `SIN_JORNADA` | Hoy no hay jornada del operario. |
| `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` · `CATALOGO_AMBIGUO` | Como siempre. No se calcula nada. |
| `SIN_GRANEL` | Solo envío (Tarea 17, R1e): algo hay que hacerlo y no tiene granel. `mensaje`: una línea por referencia; `referencias: [{ destino_id, destino, producto, formato, pedido, hay, mensaje }]`, con lo pedido para ese destino y lo máximo que se puede mandar con las cajas que hay (si dos destinos piden lo mismo, las cajas se las llevan los primeros, en su orden). La pantalla ofrece «Dejarlo en `hay`» o «Quitarlo» y vuelve a calcular. |
| `REPARTO_NO_CALCULADO` | No debería pasar: la lista era válida pero R1 no la acepta. Avisar a Administración. |
| `NO_AUTORIZADO` · `ERROR_INTERNO` | Como siempre. |

### 3.15 `reparto_de_hoy_detalle(tipo)` ✅ (Tarea 10)
Las líneas del reparto (o del envío) de hoy, para abrir «Modificar reparto» con la lista rellena y para volver a copiar el texto de WhatsApp.
- **Quién:** el operario (su jornada) y Administración (la jornada de hoy del operario por defecto).
- **Entrada:** `tipo`: `"reparto"` (por defecto) o `"envio"`.
- **Salida:** `{ "reparto": null }` si hoy no hay; si no:
```json
{
  "reparto": {
    "reparto_id": "...", "tipo": "reparto", "sale": "operario",
    "aceptado_en": "...", "pegado_por": "<persona_id>", "pegado_por_nombre": "Administración",
    "texto_whatsapp": "REPARTO 03/11\nSALE: ALMACÉN\n\nBILBAO\n12x V2 4g",
    "lineas": [ { "destino_id": "...", "destino": "Bilbao", "producto": "V2", "formato": "4g", "cantidad": 12 } ],
    "peticiones": [ { "destino_id": "...", "destino": "Bilbao", "texto": "Rollos de TPV" } ]
  }
}
```
- **Producto sin granel** (Tarea 16, R1e): en `lineas`, lo quitado ya no cuenta (la línea baja o desaparece) y lo que viene de otra tienda sigue en su línea con `de: [{ origen_id, origen, cantidad }]`. `texto_whatsapp` lo dice: «2x BZ1 4g (de Algorta)».
- `sale` es quién sale **ahora** (si se cambió con `cambiar_quien_sale`, el texto también lo dice). En el envío, `sale` es `null`.
- `peticiones` (Tarea 13): las peticiones especiales guardadas, para rellenar las casillas al modificar (lista vacía si no hay).
- **Errores:** `DATOS_NO_VALIDOS` (tipo no válido), `SIN_JORNADA`, `NO_AUTORIZADO`.

### 3.16 `guardar_pedido_cliente` (función del servidor) ✅ (Tarea 12)
Botón **«Pedido de cliente»**: las cajas con la misma lista que el reparto y cómo se entrega (`ESTADO_DEL_SISTEMA.md` §5 R1b).
- **Quién:** el operario o Administración (va a la jornada del operario por defecto).
- **Entrada:**
```json
{
  "id_cliente": "<uuid>",
  "cliente": "Ane",
  "entrega": "tienda",
  "destino_id": "<id de catalogo().tiendas.reparto>",
  "datos_envio": null,
  "lineas": [ { "producto": "V2", "formato": "4g", "cantidad": 2 } ]
}
```
- `cliente`: nombre corto, obligatorio (60 letras como máximo). `entrega`: `"tienda"` (recoger en tienda; `destino_id` obligatorio, una tienda del reparto) o `"nacex"` (envío por Nacex; `datos_envio` obligatorio: el texto pegado tal cual, con sus saltos de línea). `lineas`: como en `guardar_reparto` pero **sin tienda**; 0 se ignora, repetidas se suman.
- **Proceso:** lee la hoja y comprueba cada referencia (como `guardar_reparto`).
  - **Recoger en tienda** (Tarea 14: el pedido activa el reparto): va en el reparto de hoy mientras **las bolsas no estén listas** (si aún no hay reparto, mientras «Prepara el reparto» siga abierta); si no, en el del siguiente día de trabajo. Si el reparto de hoy ya está guardado, **entra en él al momento**; si no, entra al guardarlo (§3.14), aunque sea solo con el pedido. En los dos casos: tarea «Hay un pedido de cliente para dejar en [tienda] · [cliente]» (aparece **al terminar la producción del reparto**, antes de las bolsas, con la misma hora límite) y bolsa aparte «Pedido de cliente · [cliente]».
  - **Nacex:** tarea «Prepara el pedido de cliente (Nacex) · [cliente]» con la lista y los datos de envío en `porque`. De lunes a jueves, por la tarde (después de la revisión y la preparación del envío), antes de las 18:10; el viernes, por la mañana, antes de las 10:45, y lo lleva quien sale de reparto. **Activa Nacex ese día** (recuento a las 17:55 y «Salida a Nacex» a las 18:10; el viernes, «Lleva en el reparto lo que va a Nacex…»). Si ya hay envío, es el mismo viaje. Los pedidos de Nacex **entran hasta las 18:00** de lunes a jueves (el viernes, hasta las 10:45) y mientras la salida a Nacex no esté hecha; si no, van al siguiente día de trabajo. Si por la producción no llega a salir ese día, el operario lo pasa al día siguiente (§3.18); si queda sin hacer, pasa solo, como tarea de Nacex de ese día y con Nacex activado.
  - En las dos, **al salir la tarea** (cuando le toca al operario), cada referencia dice en `motivo` **«Coge N del almacén»** o **«Haz N»** (o las dos cosas: «Coge 2 del almacén y haz 1»). Se calcula en ese momento con el **almacén ahora** (la última lectura de la hoja + lo producido − lo salido desde el recuento), menos lo que aún no ha salido y va antes (reparto, envío y pedidos anteriores, R1c). Al guardar el pedido, `motivo` aún es `null`.
- **Salida:** `{ pedido: (objeto pedido, §3.17), tarea: (la de Nacex; null en tienda), tarea_activa: (solo al operario) }`.
- **Reintentos:** repetir con el mismo `id_cliente` devuelve el mismo pedido, sin leer la hoja, con `ya_guardado: true` y `aviso: { codigo: "PEDIDO_YA_GUARDADO" }`.
- **Errores:** `DATOS_NO_VALIDOS` (sin cliente, sin tienda o tienda que no es del reparto, sin datos de envío en Nacex, entrega no válida, cantidades no válidas o lista vacía), `REFERENCIA_NO_EXISTE` (con cuáles), `SIN_JORNADA`, `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` · `CATALOGO_AMBIGUO`, `NO_AUTORIZADO`.

### 3.17 `pedidos_cliente_abiertos()` ✅ (Tarea 12)
Para el panel de Administración y, si se quiere, para el operario.
- **Salida:** `{ total, pedidos: [objeto pedido, ...] }`, por fecha y orden de llegada. Abiertos = esperando al reparto, por preparar, o preparados que salen hoy o más adelante.
- **Objeto pedido:** `{ id, cliente, entrega: "tienda"|"nacex", entrega_texto ("Recoger en Bilbao" | "Envío por Nacex"), destino_id, destino, datos_envio, lineas: [{ producto, formato, cantidad }], fecha, estado: "esperando_reparto"|"por_preparar"|"preparado"|"cancelado", estado_texto, tarea_id, registrado_en, registrado_por, registrado_por_nombre }`.
- `fecha`: el día del reparto que lo lleva o de la salida a Nacex. `estado_texto`, para mostrar: «Va en el próximo reparto a Bilbao (desde el 25/11)», «En el reparto del 24/11: por preparar», «Por preparar: sale a Nacex el 24/11», «Preparado: va en el reparto del 24/11», «Preparado: sale a Nacex el 24/11», «Cancelado».
- Los datos de envío solo los ve el personal (cualquier persona con ficha). Sin ficha: `NO_AUTORIZADO`.

### 3.18 `aplazar_pedido_nacex(pedido_id, motivo?)` ✅ (Tarea 12)
Botón en la tarea «Prepara el pedido de cliente (Nacex)»: si por la producción el pedido no llega a salir ese día, pasa al siguiente día de trabajo (decidido por el propietario, 28/10).
- **Quién:** el operario (sus pedidos) o Administración.
- `motivo`: opcional (decidido por el propietario, 28/10).
- **Efecto:** la tarea de ese día queda «arrastrada» con el motivo «Pasa al 25/11: [motivo]»; el siguiente día de trabajo tiene su tarea de Nacex (por la tarde; el viernes, por la mañana) con la misma lista, y **Nacex activado** ese día. El «coge / haz» se vuelve a calcular al salir la tarea.
- **Salida:** `{ pedido: (objeto pedido, §3.17, con la nueva fecha), tarea_activa: (solo al operario) }`.
- **Errores:** `NO_ENCONTRADO` (no existe o no es suyo), `DATOS_NO_VALIDOS` (no es de Nacex), `ESTADO_NO_VALIDO` (ya preparado o cancelado), `SIN_JORNADA`, `NO_AUTORIZADO`.

### 3.19 `resolver_sin_granel(elemento_id, decisiones)` ✅ (Tarea 16)
En «Producción del reparto», una referencia que hay que hacer y **no tiene granel** (`sin_granel: true`, §3.2): el operario decide, tienda por tienda, si se quita o se coge de otra tienda (`ESTADO_DEL_SISTEMA.md` §5 R1e).
- **Quién:** el operario (su producción del reparto, abierta hoy).
- **Entrada:** `decisiones: [{ destino_id, accion: "quitar" | "otra_tienda", origen_id?, cantidad }]`, **una por tienda** de `para`. `cantidad`: entero, de 1 a lo que pide esa tienda (`para[].pedido`). `origen_id`, solo en `otra_tienda`: otra tienda del reparto (lo normal, una de `tiendas_con_stock`). **Entre todas suman lo que falta** (`cantidad` de la referencia).
- **Efecto:**
  - la referencia queda hecha sin producir (`cantidad` 0) y la producción sigue como siempre; queda anotado quién y cuándo;
  - **quitar:** la bolsa de esa tienda lleva menos (y la línea del reparto baja);
  - **otra_tienda:** esas cajas no se producen ni van en la bolsa. En la bolsa de la tienda que recibe sale el aviso de llamada (`tipo: "llamada"`), en `reparto_de_hoy.paradas` la parada para quien hace la ruta y, en el texto para WhatsApp, «2x BZ1 4g (de Algorta)»;
  - cuentas (R1c): lo quitado o de otra tienda no sale del almacén. Lo de otra tienda va en camino desde «bolsas listas» hasta las 23:30, como el reparto: −N en la que da y +N en la que recibe.
- Repetir lo mismo no es un error (aunque la producción ya esté hecha). Una vez resuelta y cerrada la producción, otra decisión da `ESTADO_NO_VALIDO`.
- **Salida:** `{ "elemento": { id, estado, cantidad, cantidad_hecha }, "tarea_activa": {...} }`, como `terminar_elemento`.
- **Errores:** `DATOS_NO_VALIDOS` (no está sin granel; una tienda que no la recibe o repetida; acción, cantidad u origen no válidos; no suman lo que falta, con `faltan` y `suman`), `NO_ENCONTRADO`, `ESTADO_NO_VALIDO`, `OTRA_TAREA_EN_CURSO`, `NO_AUTORIZADO` (Administración).

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
- Solo hay conflicto si **no cabe y alguna obligatoria que vence en la ventana queda en riesgo** (§6.4). Las que **ya vencieron** sin hacerse no están en riesgo (ya llegan tarde), pero **su duración cuenta** como tiempo ocupado (`vencidas_min`). Si no cabe pero no hay ninguna obligatoria en riesgo, **se crea** y el `encaje` lo avisa («No le da tiempo entera (faltan unos N min): lo que no termine pasa al día siguiente»), con `minutos_que_faltan`.
- Con conflicto, no la crea y devuelve `CONFLICTO` con `conflicto: { disponible_min, necesario_min, vencidas_min, minutos_que_faltan, obligatorias_en_riesgo: [{ tarea_id, titulo, vence, duracion_min }] }`. Administración repite la llamada con `decision_conflicto`:
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
Inicio del móvil. Solo lee (no genera nada). **Salida:** `{ ahora, fecha, operario, jornada: { id, sale, hay_envio, estado }, en_curso: tarea con sus elementos, reparto_de_hoy, problemas_abiertos: [...], incidencia_en_curso, incidencias_abiertas: [objeto incidencia, §3.11], arrastradas: [...], hoy: [{ id, titulo, estado, origen, obligatoria, urgente, hora, motivo, iniciada_en, terminada_en, minutos }], retrasos_salida: [{ a_las, minutos, nueva_hora, sale, aviso }], correos_no_enviados: [{ tipo, asunto, estado: "fallido"|"dudoso", intentos, error, creado_en }], lectura_sheets: { ultima_correcta, ultimo_error } }`. `correos_no_enviados` = cierres o avisos de los últimos 7 días que no se han podido enviar (mostrarlos como aviso). `reparto_de_hoy` ✅ Tarea 9: el reparto aceptado hoy en la jornada del operario por defecto, el mismo objeto que en `tarea_activa` (`null` → «Preparar reparto»; si no, «Modificar reparto»).
- **`hoy`**: `iniciada_en` y `terminada_en` (fecha y hora) y `minutos` ✅ Tarea 15: de inicio a fin; hasta ahora si está en curso; `null` si no ha empezado.
- **`tiempo_libre`** ✅ Tarea 15: `{ veces, minutos }`. Las tareas «Orden y limpieza» de hoy que se han empezado y sus minutos en total (la que está en curso, hasta ahora). Sin jornada: `{ veces: 0, minutos: 0 }`.
- **`cobertura_baja`** ✅ Tarea 15 (R4, `REGLAS_CALCULO.md` §4): `{ datos_leidos_en, productos: [{ producto, formato, total, necesidad_semana, semanas, motivo }], avisos: [texto] }`. Solo los productos por debajo de 2 semanas («LO QUE HAY EN TOTAL» de PRINCIPAL frente a 2 × «1 SEMANA NECESIDADES»), de menos a más semanas; Invernadero e Indoor, una fila por categoría; `formato` siempre `""` (la hoja da el total por producto). Sin minis, vapers ni lo que tiene necesidad 0. `avisos`: datos de la hoja que no se han podido calcular. Lo calcula el servidor cada vez que lee la hoja para el reparto, el envío o la lista de stock, y lo guarda con esa lectura; aquí sale la última, con su hora (`datos_leidos_en`). Si aún no hay ninguna: `{ datos_leidos_en: null, productos: [], avisos: [] }`.
- **`almacen_ahora`** ✅ Tarea 14 (solo para mostrar; desde la v1.29 el panel no lo muestra, pero sigue aquí): `{ recuento_en, datos_leidos_en, referencias: [{ producto, formato, hoja, producido, salido, ahora }], en_camino: [{ destino_id, destino, producto, formato, cantidad }] }`. `recuento_en`: el último recuento que recoge la hoja leída (`datos_leidos_en`). `referencias`: las que han tenido movimiento desde ese recuento; `ahora = hoja + producido − salido`. `en_camino`: lo que va a cada tienda (el reparto hasta las 23:30; el envío hasta las 11:59 del día siguiente).

### 4.4 `cierre(cierre_id)` · `cierres_recientes(limite)` ✅
Cierre **por turno** (13:00 y 18:30 de lunes a jueves; 13:00 el viernes, según el horario), generado solo y enviado **por correo**, una sola vez.
- `cierre` → `{ id, fecha, turno, generado_en, enviado_en, canal, contenido, texto }` (`texto` = el del correo).
- `cierres_recientes(limite = 10, máx. 50)` → `{ cierres: [{ id, fecha, turno, generado_en, enviado_en, hechas, sin_hacer, problemas, incidencias }] }`.
- **Contenido** (`MODELO_DATOS.md` §3.12): `hecho` [{ titulo, resultado, hora }] · `no_hecho` [{ titulo, estado, motivo, pasa_a_manana }] (obligatorias y de Administración de ese turno; las de todo el día, en el último) · `problemas` [{ tarea, descripcion, abierto, minutos, mas_de_5_min, solucion, estado, llamadas }] · `incidencias` [objeto incidencia (§3.11) + { tarea, inicio, fin }] (las abiertas o cerradas en el turno y las que siguen abiertas de otros días) · `arrastrados` { llegaron (primer turno), pasan_a_manana (último turno) } · `retrasos_salida` y `cruce_retrasos` { cajas_reparto, cajas_a_producir, cajas_producidas, tiendas, incidencias_manana, minutos_incidencias_manana } (turno de mañana, si hubo retraso) · `siguiente` (lo que queda para la tarde, o lo que toca el próximo día de trabajo) · `calidad` solo el viernes y solo `{ "limpieza_viernes": true|false }`.

### 4.5 `historico_dia(fecha)` · `historico_dias(desde, hasta)` ✅ (Tarea 13)
Pantalla **Histórico** de Administración (`ESTADO_DEL_SISTEMA.md` §8): con un calendario, cualquier día. **Solo consulta**; siempre del operario por defecto.
- **`historico_dia(fecha)`** → `{ fecha, jornada, reparto, envio, pedidos_cliente, cierres, tareas }`:
  - `jornada`: `{ id, sale, hay_envio, estado }` o `null` si ese día no hubo jornada.
  - `reparto` y `envio`: el mismo objeto que `reparto_de_hoy_detalle` (§3.15: quién salió, líneas por tienda, `peticiones` y `texto_whatsapp` para «Copiar para WhatsApp»), o `null`.
  - `pedidos_cliente`: los de ese día (objeto pedido, §3.17; su `fecha` es la del reparto que los lleva o la de la salida a Nacex).
  - `cierres`: los de ese día, como `cierre` (§4.4): `{ id, fecha, turno, generado_en, enviado_en, canal, contenido, texto }`.
  - `tareas`: `{ hechas: [{ titulo, resultado, hora }], no_hechas: [{ titulo, estado, motivo, pasa_al_dia_siguiente }] }`.
  - Un día sin jornada devuelve todo vacío (`null` y listas vacías), sin error.
- **`historico_dias(desde, hasta)`** → `{ dias: [{ fecha, reparto, envio, pedidos_cliente, cierres, tareas_hechas }] }`: solo los días con algo (reparto, envío, pedidos, cierres o tareas hechas), para marcarlos en el calendario. Como mucho un año.
- **Errores:** `NO_AUTORIZADO` (el operario no lo usa), `DATOS_NO_VALIDOS` (sin fecha; periodo al revés o de más de un año).

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
| `servidor_preparar` · `servidor_guardar_lectura` · `servidor_guardar_reparto` · `servidor_reparto_por_id_cliente` · `servidor_reparto_anotar_id_cliente` (Tarea 10) · `servidor_preparar_pedido` · `servidor_guardar_pedido_cliente` · `servidor_asignar_pedidos` (Tarea 12) · `servidor_guardar_peticiones` (Tarea 13) · `servidor_guardar_cobertura` (Tarea 15) · `servidor_guardar_stock` · `servidor_canjear_solicitud` · `servidor_correo_reclamar` · `servidor_correo_respuesta` (y `servidor_correo_resultado`, de la Tarea 4) ✅ | Solo las funciones del servidor (rol `service_role`) | Guardan lo que el servidor ha calculado. Ningún usuario puede llamarlas: nadie guarda un reparto o una lista sin pasar por el cálculo. |

## 6. Trazabilidad con las pantallas de §8

| Pantalla (§8) | Funciones |
| --- | --- |
| Chromebook: una tarea, su porqué, abajo Empezar/Terminada e Incidencia, «lo que viene después» | `tarea_activa`, `iniciar_tarea`, `terminar_tarea`, `crear_incidencia` |
| Chromebook, arriba: «Preparar reparto» / «Modificar reparto» y «Cerrar incidencias» (con el número) | `tarea_activa` (`reparto_de_hoy`, `incidencias_abiertas`), `incidencias_abiertas`, `cerrar_incidencia` |
| Listas de producción (él elige el orden) | `tarea_activa` (elementos), `iniciar_elemento`, `terminar_elemento`, `lista_stock` |
| «Producción del reparto»: referencia sin granel → «Quitarlo» o «Cogerlo de otra tienda» | `tarea_activa` (elementos con `sin_granel`), `resolver_sin_granel` |
| «Salida del reparto» (o el panel, si sale Administración): paradas «Recoge N … en … y déjalas en …» | `tarea_activa` / `estado_actual` (`reparto_de_hoy.paradas`) |
| Bolsas en el Pixel (una tienda por pantalla, con su bolsa de reposición, «Además, mete:» con las peticiones especiales y las bolsas de pedidos de cliente; toca cada caja y cada petición; retrasar 15/30 min) | `tarea_activa` (elementos con `bolsa`; peticiones con `tipo: "peticion"`; avisos de llamada con `tipo: "llamada"`), `marcar_cajas`, `retrasar_salida` |
| Incidencia: llega mercancía, pedir o comprar, recogida en Nacex, corregir | `crear_incidencia` |
| «Pedido de cliente» (operario o Administración): la lista, recoger en tienda o Nacex, y los pedidos abiertos | `catalogo`, `guardar_pedido_cliente`, `pedidos_cliente_abiertos` |
| Tarea «Prepara el pedido de cliente (Nacex)»: «Pasar a mañana» | `aplazar_pedido_nacex` |
| Incidencia → Estoy bloqueado (llamar, no contestan, solución) | `crear_incidencia` (`bloqueado`) o `abrir_problema`, `problema_llamada`, `resolver_problema` |
| Preparar o modificar el reparto o el envío con la lista (operario o Administración), con el desplegable «¿Quién sale?», las casillas «Peticiones especiales para [tienda]» y el texto para WhatsApp | `catalogo`, `reparto_de_hoy_detalle`, `guardar_reparto`, `mi_perfil` (`quien_sale_opciones`), `cambiar_quien_sale` |
| Inicio de Administración (móvil): ahora, avisos, productos con menos de 2 semanas, hoy con horas y minutos, tiempo libre, pedidos de cliente, arrastradas y cierres; «Preparar reparto» / «Modificar reparto» | `estado_actual` (`en_curso`, `problemas_abiertos`, `incidencias_abiertas`, `cobertura_baja`, `hoy`, `tiempo_libre`, `arrastradas`, `reparto_de_hoy`), `pedidos_cliente_abiertos`, `cierres_recientes`, `catalogo`, `reparto_de_hoy_detalle`, `guardar_reparto` |
| Nueva tarea (qué, para quién, cuándo, duración, urgente, por qué) | `crear_tarea_admin` |
| Cierre | `cierre` (y correo) |
| Histórico (Administración): calendario y un día (reparto y envío con «Copiar para WhatsApp», pedidos de cliente, cierres) | `historico_dias`, `historico_dia` |

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
- **Servidor** (`catalogo`, `guardar_reparto`, `lista_stock`): `const { data, error } = await supabase.functions.invoke('guardar_reparto', { body: { id_cliente, tipo: 'reparto', sale, lineas } })`. La sesión va sola.
- **Cómo leer la respuesta:**
  1. `error` (de Supabase): sin conexión o fallo del servidor → «No hay conexión. Vuelve a intentarlo.» y permitir reintentar. Si la sesión ha caducado (`error.code` `42501` o HTTP 401), volver a «Entrar con Google».
  2. `data.error`: respuesta de negocio → mostrar **`data.error.mensaje` tal cual** (§7.5).
  3. `data.aviso`: no es un error (ej. «Este reparto ya estaba guardado») → mostrarlo como información.
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
| `PEDIDO_YA_GUARDADO` (aviso) | No es un error: el pedido ya estaba guardado; mostrarlo. |
| `FALTA_SALE` | Preguntar «¿Quién sale hoy?» (`opciones`) y repetir `guardar_reparto` con `sale`. Con el desplegable siempre relleno no aparece. |
| `REFERENCIA_NO_EXISTE` | Volver a pedir `catalogo`, marcar las referencias de `error.referencias` y dejar quitarlas antes de guardar. |
| `SIN_GRANEL` | Solo en el envío: cada referencia de `referencias` con su `mensaje` y los botones «Dejarlo en N» (`hay`) y «Quitarlo»; después, volver a calcular. |
| `REPARTO_NO_CALCULADO` | Mostrar el mensaje (avisar a Administración). |
| `FECHA_NO_ES_HOY` · `REPARTO_CON_ERRORES` | Solo `pegar_reparto` (obsoleta). |
| `CONFLICTO` | Mostrar `conflicto.obligatorias_en_riesgo` y los minutos que faltan; Administración elige qué cede (o no crear) y se repite `crear_tarea_admin` con `decision_conflicto` y `confirmar: true`. |
| `PROBLEMA_YA_ABIERTO` · `INCIDENCIA_YA_ABIERTA` | Mostrar el abierto en vez de crear otro: `error.problema` (objeto problema) / `error.incidencia_id` y `error.incidencia` (§3.10). |
| `MOTIVO_OBLIGATORIO` | «Prepara el reparto» sin reparto: ofrecer «Preparar reparto» o escribir el motivo y repetir `terminar_tarea` con `motivo`. |
| `PEDIDO_ESPERANDO_REPARTO` | «Prepara el reparto» con un pedido de tienda esperando: mostrar el mensaje y llevar a «Preparar reparto» (con el pedido ya marcado). No se puede cerrar con motivo. |
| `SIN_TAREA` | Mostrar el mensaje (ej. «Estoy bloqueado» sin ninguna tarea abierta). |
| `SOLUCION_OBLIGATORIA` · `DATOS_NO_VALIDOS` · `CANTIDAD_FUERA_DE_RANGO` | Mostrar junto al campo y dejar corregir. |
| `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` | Mostrar el mensaje; el resto de la app sigue funcionando. |
| Cualquier otro | Mostrar el mensaje. |

## 8. Dudas

1. **Ver la lista de stock desde Administración:** la incluyo como consulta. Si no se quiere, se quita.
2. **Tarea 7 · «Pedir o comprar»:** por defecto lo resuelve él; la pantalla ofrece cambiarlo a Administración (materia prima y packaging). La base de datos no distingue el material.
3. **Tarea 7 · «Cuando pueda»:** la tarea va a la cola de tiempo libre como compras y aprovisionamientos (C), antes de «Orden y limpieza», para que no quede detrás de una tarea que no se gasta.
4. **Tarea 7 · «Estoy bloqueado»:** no crea una incidencia aparte; es el problema de siempre (sale en `problemas_abiertos` y en PROBLEMAS del cierre), para no contarlo dos veces.
5. **Tarea 7 · Nunca sin tarea:** solo dentro del turno; entre turnos (13:00–15:30) `tarea` es `null` y `siguiente` dice lo que viene.
6. **Tarea 10 · Solo cambia quién sale:** si la lista no cambia y solo cambia el desplegable, la pantalla llama a `cambiar_quien_sale` (si llama a `guardar_reparto`, se recalcula y se sustituye el reparto con lo mismo, conservando lo hecho).
7. **Tarea 10 · Tiendas y orden** (decidido por el propietario, 28/10): reparto BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU; envío GIPUZKOA, DURANGO; en el orden de las hojas de STOCK OSASUN. Donosti y Rentería, solo de consulta.
8. **Tarea 10 · `pegar_reparto`:** se deja publicada (obsoleta) hasta que el coordinador diga quitarla.
9. **Tarea 12 · Un pedido de tienda que no se hace el día de su reparto:** su tarea pasa al día siguiente con su lista, pero no vuelve a entrar sola en el reparto siguiente (la bolsa era del reparto de ese día).
10. **Tarea 12 · Nacex:** los títulos de las tareas de Nacex dicen ahora «envío o pedido de cliente», porque Nacex también se activa solo por un pedido.
11. **Tarea 13 · Varias peticiones de una tienda en el texto para WhatsApp:** van en una sola línea «Además: …», separadas por «; » (no por comas, porque una petición puede llevar comas: «Cajas vacías, 3»).
12. **Tarea 13 · Peticiones repetidas:** la misma petición dos veces en la misma tienda (sin contar mayúsculas) cuenta una vez; para pedir más, se escribe en el texto («Rollos de TPV x2»).
13. **Tarea 13 · Pedidos de cliente del histórico:** los del día del reparto que los lleva o de la salida a Nacex (no los del día en que se apuntaron).
14. **Tarea 13 · Solo peticiones, sin productos** (decidido por el propietario, 28/10): no se guarda un reparto ni un envío solo con peticiones especiales. Las peticiones van en el siguiente reparto que salga o en una visita. Más adelante, las tiendas tendrán un botón para cerrar sus peticiones especiales.
15. **Tarea 14 · Un pedido de tienda activa el reparto** (decidido por el propietario, 28/10): si «Prepara el reparto» ya se cerró sin reparto (sin pedidos esperando entonces), un pedido apuntado después va al siguiente día de trabajo.
16. **Tarea 14 · Primer reparto del día** (decidido por el propietario, 28/10): también con el almacén ahora; a primera hora da lo mismo que la hoja.
17. **Tarea 15 · R4 por producto** (decidido por el propietario, 29/10): cada fila es un producto entero (`formato: ""`), porque la hoja da el total y la necesidad por producto y así sirve para organizar el pedido a proveedores. Los excluidos (MINI, VAPER) se quitan por su nombre.
18. **Tarea 15 · Total negativo en PRINCIPAL** (decidido por el propietario, 29/10; hoy, TXABAKO SUST con −40): es un dato raro y va a `avisos`, no a la lista.
19. **Tarea 15 · De cuándo es la cobertura:** de la última lectura del reparto, el envío o la lista de stock (varias al día; las ventas solo cambian con el FIN DE DÍA). Las lecturas de los pedidos de cliente no la calculan.
20. **Tarea 16 · De dónde salen las cajas de las otras tiendas:** de sus columnas en PRINCIPAL (FIN DIA de cada tienda, que viene de su pestaña). Es lo que ya se lee al calcular: no se lee ninguna pestaña de tienda.
21. **Tarea 16 · Lo que hay en el almacén, para qué tienda** (decidido por el propietario, 29/10): si hay algunas cajas pero no todas, se las llevan las primeras tiendas del reparto (en su orden) y `para` dice cuántas le faltan a cada una. El operario puede repartir la decisión de otra forma (como mucho, lo que pide cada tienda).
22. **Tarea 16 · Quién decide** (decidido por el propietario, 29/10): solo el operario, en su producción (como el resto de su lista). Administración no tiene esta función.
23. **Tarea 16 · Cambiar lo decidido** (decidido por el propietario, 29/10): con la producción ya cerrada no se puede; repetir lo mismo sí. Para cambiarlo, se modifica el reparto.
24. **Tarea 17 · Dónde va la lista de `SIN_GRANEL`:** en `error.referencias`, como en `REFERENCIA_NO_EXISTE` (los datos del error van junto a `codigo` y `mensaje`).
