# OSASUN OPERATIONS — Plan técnico de la base de datos (propuesta V1)

**Versión:** 0.1 (propuesta, pendiente de aprobación) · **Fecha:** 26/10/2026 · **Autor:** agente de base de datos · **Tarea:** 1

> Cómo funcionará por dentro lo descrito en `MODELO_DATOS.md`, `CONTRATOS.md` y `REGLAS_CALCULO.md`. Nada está construido.

---

## 1. Piezas (y solo estas)

| Pieza | Para qué |
| --- | --- |
| **Postgres de Supabase** | Tablas, permisos (RLS) y funciones de base de datos: motor de tareas, problemas, incidencias, cierres. |
| **Supabase Auth** | Usuarios (Administración y operario). Altas solo por invitación; registro abierto desactivado. Acceso con correo y contraseña (sin servicios adicionales). |
| **2 funciones del servidor (Edge Functions)** | `pegar_reparto` y `lista_stock`: las únicas que leen Google Sheets. Aplican R1 y R3 (código TypeScript con pruebas). |
| **Tareas programadas (pg_cron)** | Generar la jornada cada mañana y generar/enviar los cierres. |
| **Realtime de Supabase** | Que una tarea nueva aparezca sola en el Chromebook o en el Pixel. |

No hay servidor propio, ni cola de mensajes, ni copia del stock en la base de datos.

## 2. Motor de tareas

### 2.1 Generación diaria
- Tarea programada cada día a las **06:00 (hora de Madrid)** + generación «perezosa» la primera vez que el operario abre la app (`tarea_activa`). Las dos llaman a la misma función, que es **idempotente**: único (persona, fecha) en jornadas y único (jornada, clave) en tareas. Reiniciar, abrir dos pestañas o perder la conexión no duplica nada (§6.2).
- Solo se generan jornadas para los días con turnos en `horarios`.
- Se crean las tareas de las plantillas activas cuyo día coincide y **cuya condición ya se sabe** (ej. `hay_envio` el lunes). Las condicionadas por algo que aún no ha pasado se crean cuando pasa:

| Condición | Se crea cuando… |
| --- | --- |
| `reparto_pegado` | se acepta el reparto (producción y bolsas, con sus elementos). |
| `sale_operario` / `sale_administracion` | se conoce la línea `SALE:` (o el operario responde). |
| `envio_pegado` / `hay_envio` / `no_hay_envio` | se pega el envío aprobado (o, si no, a las 15:30 se da por «sin envío» al terminar la tarea de revisión). |
| `llega_mercancia` · `pedido_cliente` · `no_quedan_vapers` | se registra el evento. |

### 2.2 Arrastres (§6.5)
Al generar la jornada se revisan las tareas no terminadas de la jornada anterior:
- `recalcular` (stock): no se arrastra; se vuelve a calcular.
- `sigue_abierta` (compras y recogidas): la original pasa a `arrastrada` y se crea una copia que sigue hasta que él confirma que lo tiene.
- `arrastrar` (tareas de Administración): igual, marcada como «arrastrada» para el panel y el cierre.
- `nada`: constan en el cierre como no hechas con su motivo (ver duda sobre obligatorias en `MODELO_DATOS.md` §7).

### 2.3 Qué tarea toca ahora (`tarea_activa`)
Regla determinista, en este orden:

1. La tarea **en curso**, si la hay (solo puede haber una).
2. La tarea **«Llama a Administración»** de un problema sin resolver cuya hora de nueva llamada ha llegado (§6.6, 30 minutos).
3. **Urgentes de Administración** pendientes (por hora de creación).
4. **Tareas con hora** ya vencida y pendientes (por hora; desempate: `orden`).
5. Tareas **obligatorias** y **de Administración con hora límite**, por la hora límite más próxima (empate: la obligatoria primero). Las que no tienen hora límite van detrás.
6. **Tareas de Administración «hoy»** sin hora.
7. **Flexibles** de plantilla.
8. **Cola de tiempo libre:** A (stock +35 %), C (compras y aprovisionamientos pendientes), D (orden y limpieza).

Las tareas bloqueadas (con problema abierto) se saltan. «Lo que viene después» es el resultado de aplicar la misma regla sin la tarea actual.

**Punto de encaje (§6.4):** una tarea con hora o urgente **nunca interrumpe** a mitad de una referencia, pesaje o bolsa. Solo se evalúa al terminar un elemento (referencia de producción o bolsa completa de una tienda) o una tarea. Si toca cambiar, la tarea con lista vuelve a `pendiente` conservando lo hecho. Si empieza tarde, la hora real queda registrada (`iniciada_en`).

### 2.4 Conflictos al crear una tarea de Administración (§6.4)
Al crear (o al comprobar antes de crear):
```
ventana     = desde ahora (o el inicio del día elegido) hasta la hora límite (o el final del turno/jornada)
disponible  = minutos de turno dentro de la ventana − bloques fijos (salida del reparto, Nacex)
necesario   = Σ duración de las obligatorias pendientes que vencen dentro de la ventana + duración de la nueva tarea
conflicto   = necesario > disponible
```
- Sin conflicto: se crea y se informa del encaje previsto.
- Con conflicto: **no se crea**; se muestra mientras se rellena (no es un aviso posterior) qué obligatorias quedan en riesgo. Administración elige qué cede (pasar después, a mañana o cancelar) o no la crea. La decisión queda en el registro. Nada desaparece en silencio.
- **Necesita duraciones**: las de recuento (15 min), salida del reparto (~2 h), limpieza del viernes (30 min) y Nacex vienen del mapa (§4). Las de producción, bolsas y la tarea nueva no están definidas → decisión 4 (§8).

### 2.5 Problemas (§6.6)
- Abrir un problema bloquea la tarea; el operario sigue con la siguiente.
- «No contestan» fija `proxima_llamada_en = ahora + 30 min`. A esa hora `tarea_activa` devuelve la tarea de volver a llamar (en el siguiente punto de encaje).
- La regla de 5 minutos se mide (abierto → solución) y aparece en el cierre con el tiempo de cada problema. La app no muestra cuentas atrás al operario (§6.7).

### 2.6 Plantillas iniciales (carga de la V1, del mapa semanal §4)
Obligatoria/flexible según la tabla de §6.3; lo que no aparece en ella va como flexible. Todo es ajustable sin código.

| Código | Días | Hora / límite | Condición | Obligatoria |
| --- | --- | --- | --- | --- |
| `revision_inicial` | L–V | 08:30 | — | No |
| `pegar_reparto` | L–V | 08:45 | — | Sí (parte de «producción y bolsas del reparto») |
| `produccion_reparto` | L–V | antes de la salida | reparto_pegado | Sí |
| `bolsas` | L–V | antes de la salida | reparto_pegado | Sí |
| `limpieza_resinas` (30 min) | V | antes de la salida | — | Sí |
| `salida_reparto` | L–V | 10:45 | sale_operario | Sí |
| `efectivo_reporte` | L–V | al volver | sale_operario | Sí |
| `recuento_manana` (15 min) | L–V | 12:45 | — | Sí |
| `revisar_envio` | L–J | 15:30 | — | No |
| `revisar_envio_viernes` | V | mañana (hora por definir) | — | No |
| `minis` | L | tarde | — | Sí |
| `resinas` (comprobar antes PRINCIPAL, R8) | M | tarde | — | Sí |
| `control_materiales` | J | última hora, antes del recuento | — | Sí |
| `preparar_envio` | L–V | antes de 18:10 | envio_pegado | Sí |
| `nacex_salida` | L–J | 18:10 | hay_envio | Sí |
| `recuento_tarde_envio` (15 min) | L–J | 17:55 | hay_envio | Sí |
| `recuento_tarde` (15 min) | L–J | 18:15 | no_hay_envio | Sí |
| `recepcion_mercancia` | — | en el momento | llega_mercancia | Sí |
| `pedido_cliente` | — | — | pedido_cliente | Sí |
| `tirada_vapers` (50, 2 tipos) | — | — | no_quedan_vapers | No |
| `cola_stock` (A) | L–V | — | cola_libre | No |
| `cola_compras` (C) | L–V | — | cola_libre | No |
| `cola_orden_limpieza` (D) | L–V | — | cola_libre | No |

Si sale Administración, el tiempo hasta las 12:45 queda para la cola de tiempo libre (sin tarea especial).

## 3. Lectura de Google Sheets

### 3.1 Acceso
- **Cuenta de servicio** de Google Cloud con permiso **Lector** solo sobre `STOCK OSASUN-CLAUDE`, alcance `spreadsheets.readonly`. No puede escribir aunque el código lo intentara. Revocable quitándola de «Compartir».
- Su clave se guarda como **secreto de Supabase** (nunca en el repositorio), una por entorno (§10, condición 5).

### 3.2 Pestañas confirmadas (lectura del 26/10/2026)
Título real del documento: **`STOCK OSASUN-CLAUDE`** (con guion). Pestañas:

| Pestaña | Uso en la V1 | Observación |
| --- | --- | --- |
| `PRINCIPAL` | Catálogo, cajas en almacén (col. R), granel (col. R, fila del producto) | Formato por bloques; «V2 » con espacio final. |
| `CONTEO DE CAJAS TOTAL` | Contador y consumo (R3) | Grupos EXTERIOR, INVERNADERO, INDOOR, HIGH TECH, CBDX. |
| `ALMACEN` | Categoría de cada producto | Sin tilde. El grupo se llama «INDOOR POPS». |
| `STOCK ALMACEN DIARIO` | No se lee en la V1 | **Sin tilde.** No tiene fecha: R5 (V1.1) necesitará otra forma de saber si se actualizó (fecha de modificación del archivo o una celda con la fecha). |
| `VENTAS SKU`, `TOTAL GENERAL`, `COMPARATIVO MEDIA TIENDAS` | No se leen | |
| `BILBAO`, `ALGORTA`, `DONOSTI`, `BARAKALDO`, `RENTERIA`, `BASAURI`, `LAUDIO`, `PORTU`, `GIPUZKOA` | No se leen en la V1 | Dan los nombres de las tiendas. `LAUDIO` = Durango. |

Los nombres se guardan en `configuracion`, no en el código. Pido al coordinador que actualice §9 de `ESTADO_DEL_SISTEMA.md` con esta tabla (no lo cambio yo).

### 3.3 Cuándo se lee
- Al pegar el reparto o el envío (R1).
- Al pedir la lista de stock, una vez por turno (R3).
- Nada más: no hay lecturas periódicas. Una sola llamada por vez (lectura en bloque de las 3 pestañas), muy por debajo de los límites gratuitos de Google.

### 3.4 Si falla
- Se espera como máximo 10 s y se reintenta una vez.
- Si sigue fallando: el cálculo **no se hace** y la pantalla dice por qué (`SHEETS_NO_DISPONIBLE`). Las tareas, problemas, incidencias y cierres siguen funcionando (principio 8). No se usan datos viejos ni inventados.
- Si la hoja ha cambiado de forma (pestaña renombrada, columnas movidas, encabezados distintos): `ESTRUCTURA_SHEETS_CAMBIADA`. La lectura se hace **buscando encabezados y nombres**, no celdas fijas, para que añadir una fila de producto no rompa nada.
- Cada lectura (correcta o no) queda en `lecturas_sheets` y el panel de Administración muestra el último error.

## 4. Entornos y forma de trabajo

| Entorno | Qué es | Quién lo usa |
| --- | --- | --- |
| **Pruebas** | Proyecto Supabase `osasun-pruebas` con datos de prueba | Agente de base de datos y Lovable (siempre) |
| **Producción** | Proyecto Supabase `osasun-produccion` | Solo tras aprobar la puesta en marcha |

- Todo cambio de base de datos es una **migración** en el repositorio (`supabase/migrations`), revisada por PR y aplicada primero en pruebas. A producción solo pasa la misma migración ya probada.
- Pruebas automáticas en el repositorio: R1 y R3 (los casos de `REGLAS_CALCULO.md`) y el motor (estados, idempotencia, permisos, conflictos, arrastres), con una semana simulada de lunes a viernes.
- Pruebas puede leer el `STOCK OSASUN-CLAUDE` real (solo lectura, sin riesgo) para la semana en paralelo; las pruebas automáticas usan copias fijas de los datos.

## 5. Permisos

- **RLS activado en todas las tablas.** Lectura según `MODELO_DATOS.md` §6.
- **Nadie escribe directamente en tablas**: se retiran los permisos de insertar, modificar y borrar a los usuarios. Toda escritura pasa por funciones que comprueban el rol al empezar.
- **El operario no puede ver ni usar el panel**: las funciones de Administración devuelven `NO_AUTORIZADO` y las tablas de cierres y registro no le son visibles. Se prueba con su propio usuario.
- **Lovable usa solo la clave pública**. La clave maestra (service role) solo existe como secreto de las funciones del servidor.
- Usuarios: el agente de base de datos da de alta a las dos personas por invitación, con la aprobación del propietario. Registro abierto desactivado.

## 6. Copias de seguridad

- **Producción en plan Pro:** copia diaria automática con 7 días de retención.
- La estructura está entera en el repositorio (migraciones), así que se puede reconstruir desde cero.
- Antes de la puesta en marcha se hace **una prueba de restauración** en pruebas.
- El stock no necesita copia: está en Google Sheets.

## 7. Coste estimado de Supabase

| Concepto | Coste |
| --- | --- |
| Hasta la puesta en marcha (solo pruebas, plan gratuito) | 0 € |
| Producción: plan Pro (incluye la copia diaria y el cómputo de un proyecto pequeño) | ~25 $/mes |
| Pruebas en la misma organización tras la puesta en marcha | ~10 $/mes más (o 0 € si se deja en plan gratuito, que se pausa tras una semana sin uso) |
| Cuenta de servicio de Google y API de Sheets | 0 € |
| **Total** | **~25–35 $/mes (~23–33 €)**, dentro de los ~100 €/mes previstos |

Precios públicos según lo que conozco; se confirman en la web de Supabase en el momento de contratar. No contrato nada: lo hace el propietario.

## 8. Decisiones que necesito del propietario (imprescindibles)

| # | Decisión | Mi propuesta |
| --- | --- | --- |
| 1 | **D1 — Redondeo de R3** | Hacia arriba (garantiza el +35 %). |
| 2 | **D2 — Cierre** | Uno al terminar la jornada (18:30 L–J, 13:00 V). La tabla admite los dos, se puede cambiar. |
| 3 | **D3 — Canal del cierre** | Correo a la cuenta de Administración (servicio de envío con plan gratuito; requiere crear esa cuenta) o notificación de la app instalada en el móvil (sin servicio extra, pero hay que instalarla como app). Necesito saber qué móvil usa Administración. |
| 4 | **Duraciones para detectar conflictos** | Que Administración dé un tiempo aproximado de producción del reparto y bolsas, y un tiempo por defecto para sus tareas (propongo 15 min). Alternativa en «Propuestas»: añadir «cuánto lleva» (opcional) a Nueva tarea. |
| 5 | **Cuentas** | Que el propietario cree (o autorice crear) el proyecto Supabase de pruebas (gratuito) y la cuenta de servicio de Google, y me dé sus claves como secretos del entorno. Yo no creo cuentas. |

Además, las **dudas de negocio** listadas en `MODELO_DATOS.md` §7, `CONTRATOS.md` §7 y `REGLAS_CALCULO.md` §5. Las imprescindibles para empezar a construir son: tiendas y su forma de escribirse en el reparto, minis, FIFO en Invernadero/Indoor y qué pasa al volver a pegar un reparto.

**Otras dudas del motor:**
- Cuando sale Administración, ¿a qué hora sale? (marca la hora límite de producción y bolsas).
- Envío a Gipuzkoa/Durango el viernes por la mañana: ¿a qué hora se revisa?
- Problema sin respuesta: ¿los 30 minutos cuentan desde el WhatsApp o desde que se abrió el problema? (provisional: desde el WhatsApp).
- Días festivos o ausencias: ¿cómo los indica Administración? (provisional: sin jornada si no hay turnos; fuera de la V1 salvo que se pida).

## 9. Riesgos

| Riesgo | Efecto | Medida |
| --- | --- | --- |
| Cambia la forma de la hoja (filas, nombres, pestañas) | Cálculos que fallan | Lectura por encabezados; validación de estructura; error claro, nunca datos inventados. |
| Nombres irregulares en PRINCIPAL (§9, P2) | Repartos rechazados | Errores por línea; propuesta P-R1c; limpieza P2. |
| Sheets sin actualizar (recuento no hecho) | Listas con datos de ayer | Se muestra la hora de los datos; R5 en la V1.1. |
| Duraciones desconocidas | Aviso de conflicto impreciso | Decisión 4; ajustar tras la semana en paralelo. |
| Diferencias de formato entre pestañas (T BALLS, KRUSH) | Referencias con aviso | Duda 9 de `REGLAS_CALCULO.md`. |
| Clave de la cuenta técnica expuesta | Lectura del stock por terceros (no escritura) | Secreto del entorno; revocable al momento. |
| Plan gratuito pausado en producción | App parada | Producción en plan Pro. |

## 10. Trazabilidad con los criterios de aceptación (§13)

| Criterio | Dónde está en el diseño |
| --- | --- |
| Jornada (cada tarea el día y la hora correctos) | Plantillas (§2.6), generación (§2.1), regla de selección (§2.3); prueba de semana simulada (§4). |
| Duplicados | Restricciones únicas e `id_cliente` (`MODELO_DATOS.md` §5); generación idempotente (§2.1). |
| Reparto (5 repartos reales) | R1 (`REGLAS_CALCULO.md` §2), casos R1-01…16; `repartos.texto_original` + `lecturas_sheets` para comparar cada número. |
| Stock (+35 %) | R3 (`REGLAS_CALCULO.md` §3), casos R3-01…18, orden por consumo (§3.5). |
| Tareas de Administración | Punto de encaje (§2.3) y conflicto al lanzar (§2.4); `crear_tarea_admin`. |
| Problemas (5 min y 30 min) | §2.5; `problemas` con tiempos; `abrir_problema`, `problema_llamada`, `resolver_problema`. |
| Cierre | `cierres` + `generar_cierre`; canal según D3. |
| Permisos | §5: RLS, sin escritura directa, funciones con comprobación de rol; cuenta de servicio de solo lectura (§3.1). |
| Dispositivos | Mismas funciones para Chromebook y Pixel; Realtime para tareas nuevas. Las pantallas son de Lovable. |
| Uso real | Contratos simples (una tarea activa, tres botones); depende de las pantallas. |

## 11. Propuestas (no aprobadas)

| # | Propuesta | Motivo |
| --- | --- | --- |
| P-T1 | Añadir a «Nueva tarea» un campo opcional «cuánto lleva». | Mejora la detección de conflictos sin adivinar. |
| P-T2 | Las de `REGLAS_CALCULO.md` §4 (P-R1a, P-R1b, P-R1c, P-R3a). | |
