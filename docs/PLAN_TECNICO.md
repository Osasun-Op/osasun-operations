# OSASUN OPERATIONS — Plan técnico de la base de datos (V1)

**Versión:** 0.5 · **Fecha:** 27/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobado (PR #1 y #2). En pruebas: estructura base, permisos y jornada automática (Tarea 2); reparto, stock y lectura de la hoja (Tarea 3); problemas, incidencias, tareas de Administración, retraso de la salida y cierre por correo (Tarea 4); acceso con Google y tiempo real (Tarea 5).

> Cómo funciona por dentro lo descrito en `MODELO_DATOS.md`, `CONTRATOS.md` y `REGLAS_CALCULO.md`.

---

## 1. Piezas (y solo estas)

| Pieza | Para qué | Estado |
| --- | --- | --- |
| **Postgres de Supabase** | Tablas, permisos (RLS) y funciones: motor de tareas, problemas, incidencias, cierres. | ✅ base (Tarea 2) |
| **Supabase Auth** | Usuarios (Administración y operario), **solo con Google** y solo las cuentas de `cuentas_autorizadas` (hook «Before User Created»); al entrar por primera vez se da de alta su persona. | ✅ Tarea 5 |
| **3 funciones del servidor (Edge Functions)** | `pegar_reparto` y `lista_stock`: las únicas que leen Google Sheets (R1 y R3). La lectura (`google.ts`, `hoja.ts`) está separada del cálculo (`r1.ts`, `r3.ts`). `enviar_correo`: envía cierres y avisos con Resend (`correo.ts`). | ✅ Tareas 3 y 4 |
| **Tareas programadas (pg_cron)** | Generar la jornada a las 06:00 y los cierres de cada turno. | ✅ jornada (Tarea 2) y cierres (Tarea 4) |
| **Correo (Resend, plan gratuito)** | Cierres por turno y aviso de retraso de la salida (D3). La base de datos pide el envío por `pg_net` a `enviar_correo` con una solicitud interna de un solo uso; la clave `RESEND_API_KEY` es un secreto de las funciones del servidor y el destino (`correo_administracion`) está en la configuración del entorno. | ✅ Tarea 4 |
| **Realtime de Supabase** | Que una tarea nueva aparezca sola en el Chromebook o el Pixel: `tareas` y `tarea_elementos` publicadas. | ✅ Tarea 5 |

No hay servidor propio, ni cola de mensajes, ni copia del stock en la base de datos.

### Esquemas
- `public`: las tablas y las funciones que publica la API (`mi_perfil`, `tarea_activa`…). Las públicas no tienen privilegios propios: solo llaman a `motor.api_*`.
- `motor`: la lógica. `motor.api_*` comprueba quién llama y su rol; el resto (generar, elegir, arrastrar…) no se concede a nadie. No se publica en la API.
- `prueba`: `prueba.fijar_condicion`, para simular la semana. No se concede a nadie y además exige `configuracion.entorno = "pruebas"`.

Todas las funciones del motor reciben la hora como parámetro: así las pruebas simulan cualquier día y hora. Las públicas pasan siempre la hora del servidor.

## 2. Motor de tareas

### 2.1 Generación diaria ✅
- **Tarea programada a las 06:00 de Madrid** (`generar_jornada_diaria`). pg_cron trabaja en UTC: se lanza a las 04:00 y 05:00 UTC y solo actúa la ejecución que cae a las 06:00 en Madrid (verano o invierno).
- **Generación «perezosa»**: si el operario abre la app antes, `tarea_activa` la genera. Las dos llaman a la misma función, que es **idempotente**: candado por persona y fecha + único (persona, fecha) + único (jornada, clave). Dos llamadas a la vez: la segunda espera y devuelve la misma jornada (probado).
- Solo hay jornada los días con turnos en `horarios`.
- Al generar: 1) se arrastra lo pendiente del último día trabajado (§2.2); 2) se crean las tareas de las plantillas del día cuya condición ya se cumple.
- **Envío:** el lunes la jornada nace con envío. El viernes nace con envío si el jueves se marcó «envío mañana» (`envio_dia_siguiente`).
- **Condiciones de estado** (quién sale, si hay envío): se evalúan al generar y cada vez que cambian. Si una deja de cumplirse, sus tareas pendientes se **retiran** (canceladas, con motivo «Ya no aplica: …» y registro); si vuelve a cumplirse, se recuperan. Nada desaparece en silencio.
- **Condiciones de algo que pasa** (reparto o envío pegado, mercancía, pedido de cliente, vapers): la tarea se crea cuando pasa. Hasta que existan sus funciones (Tarea 3), en pruebas se simula con `prueba.fijar_condicion`.

| Condición | Se crea o cambia cuando… |
| --- | --- |
| `reparto_pegado` | se acepta el reparto (producción y bolsas). |
| `sale_operario` / `sale_administracion` | se conoce la línea `SALE:` (o el operario responde). |
| `hay_envio` / `no_hay_envio` | se aprueba el envío (se pega la versión final). |
| `envio_pegado` | se pega el envío aprobado (prepararlo). |
| `llega_mercancia` · `pedido_cliente` · `no_quedan_vapers` | se registra el evento. |

### 2.2 Arrastres (§6.5, decidido) ✅
Al generar la jornada se revisan las tareas no terminadas (pendiente, en curso o bloqueada) del último día trabajado:
- `arrastrar` (obligatorias fijas: minis, resinas, control de materiales, limpieza de resinas; recepción, pedido de cliente, vapers; tareas de Administración) y `sigue_abierta` (compras y recogidas): la original pasa a `arrastrada` y se crea una copia en el nuevo día, disponible desde el primer turno, sin hora. Conserva su origen y quién la creó.
- `recalcular` (stock): no se arrastra; se vuelve a calcular.
- `nada` (ligadas a una hora o un turno: recuentos, Nacex, salida, efectivo, revisión, reparto y bolsas del día): no pasan; constan en el cierre como no hechas.
- Una copia que tampoco se hace vuelve a pasar al siguiente día trabajado (salta el fin de semana).

### 2.3 Qué tarea toca ahora (`tarea_activa`) ✅
Solo tareas disponibles (su hora o su turno ya ha llegado), no bloqueadas y con su requisito hecho. Orden:

1. La tarea **en curso** (solo puede haber una).
2. **«Llama a Administración»** por un problema sin resolver cuya nueva llamada ha llegado (§6.6).
3. **Urgentes**: de Administración o por plantilla (la recepción de mercancía, que se atiende en el momento). Entre urgentes, por orden de llegada.
4. **Tareas con hora** ya vencida (la más temprana primero).
5. **Obligatorias y de Administración con hora límite**, por la hora límite más próxima (empate: la obligatoria). Las obligatorias sin hora límite van detrás.
6. **De Administración «hoy»** sin hora.
7. **Flexibles** de plantilla (ej. tirada de vapers).
8. **Cola de tiempo libre:** A (stock +35 %), C (compras), D (orden y limpieza).

Desempates: `orden` de la plantilla y hora de creación. **«Lo que viene después»**: lo que tocaría sin la tarea actual; pero si antes llega una tarea con hora (o el siguiente turno), se anuncia esa con su hora.

**Punto de encaje (§6.4):** una tarea con hora o urgente **nunca interrumpe** a mitad de una referencia o de una bolsa. Se evalúa al terminar un elemento (referencia de producción, o **bolsa completa de una tienda**, decidido) o una tarea (Tarea 3).

### 2.4 Conflictos al crear una tarea de Administración (§6.4) ✅ Tarea 4
```
ventana     = desde ahora (o el inicio del día elegido) hasta la hora límite (o el final del turno)
disponible  = minutos de turno en la ventana − bloques fijos (ruta del reparto ~2 h, Nacex)
necesario   = Σ duración de las obligatorias pendientes que vencen en la ventana + duración de la nueva
conflicto   = necesario > disponible
```
Cómo está hecho (`motor.conflicto`, `motor.duracion_estimada`):
- «Final del turno» = el del turno en que empieza la ventana. Los bloques fijos son las tareas pendientes de salida del reparto y Nacex con su hora y duración (solo lo que cae dentro de la ventana).
- «Vencen en la ventana» = obligatorias y de Administración pendientes, en curso o bloqueadas cuya hora límite (o su hora) cae dentro de la ventana. Las que no tienen hora no cuentan.
- Duración de cada una: producción y lista de stock = cajas que faltan de sus referencias × 1 min; bolsas = tiendas pendientes × 3 min; el resto, su duración (sin duración, 0).
- Solo cuentan las que vencen **dentro** de la ventana (las ya vencidas no se ponen en riesgo).
- **Solo hay conflicto si queda en riesgo alguna obligatoria** (§6.4, corrección del PR #4). Si no cabe pero no hay obligatorias en riesgo, se crea y se avisa en el encaje de los minutos que faltan; lo que no termine pasa al día siguiente.
- Decisiones: `despues` (la que cede pierde su hora límite), `manana` (deja de salir hoy y se arrastra), `cancelar`, `no_crear`; todas en el registro (`conflicto_decidido`).
**Duraciones** (§6.10, decidido): producción = cajas que faltan × 1 min; bolsas = 3 min por tienda; recuento 15 min; limpieza de resinas 30 min; ruta del reparto ~2 h; tareas de Administración: la **duración orientativa obligatoria** que pone Administración al crearla.
Con conflicto, la tarea no se crea: Administración ve, mientras la crea, qué obligatorias quedan en riesgo y decide qué cede. La decisión queda en el registro.

### 2.5 Problemas (§6.6) ✅ Tarea 4
- Abrir un problema bloquea la tarea; el operario sigue con la siguiente.
- «No contestan» → WhatsApp → **a los 30 minutos del WhatsApp** (decidido) vuelve a aparecer «Llama a Administración» (escalón 2).
- La regla de los 5 minutos se mide (abierto → solución) y sale en el cierre (`mas_de_5_min`). La app no muestra cuentas atrás al operario (§6.7).
- Las urgentes (de Administración o la recepción de mercancía) entran al terminar la referencia o la tienda en curso (punto de encaje, Tarea 3), por orden de llegada.

### 2.5 bis Cierre por turno (D2, D3) ✅ Tarea 4
- La tarea programada `generar_cierres_turno` se lanza a y media y en punto de 11, 12, 16 y 17 UTC de lunes a viernes; `motor.generar_cierres_programados` cierra los turnos de hoy cuyo horario ya ha terminado y aún no tienen cierre (13:00 y 18:30 de lunes a jueves, 13:00 el viernes, en verano e invierno). Si una ejecución falla, la siguiente lo recupera.
- `motor.generar_cierre` congela el contenido (`CONTRATOS.md` §4.4), cierra la jornada tras el último turno y pide el correo. Único (jornada, turno): nunca hay dos cierres del mismo turno.
- Correo (`motor.correos`): `enviar_correo` reclama cada intento una sola vez. Si Resend responde con un error (no aceptó el correo), se reintenta a los 5 min (tarea programada `reintentar_correos`, cada minuto), hasta 3 intentos; si no responde a tiempo (dudoso), no se reintenta para no enviarlo dos veces. El fallo final queda en `error_envio` y en `estado_actual` (corrección del PR #4).
- Turno de cada tarea: el de su plantilla; si no tiene, por su hora (antes o después del inicio de la tarde); sin hora, cuenta en el último cierre del día.

### 2.6 Plantillas cargadas (Tarea 2, del mapa semanal §4) ✅
Obligatoria/flexible según §6.3; lo que no aparece allí va como flexible. Todo se ajusta sin código.

| Código | Días | Hora · límite | Condición | Oblig. | No terminada |
| --- | --- | --- | --- | --- | --- |
| `revision_inicial` (15 min) | L–V | 08:30 | — | No | nada |
| `pegar_reparto` (5 min) | L–V | 08:45 | — | Sí | nada |
| `limpieza_resinas` (30 min) | V | antes de 10:45 | — | Sí | arrastrar |
| `produccion_reparto` | L–V | antes de 10:45 | reparto_pegado | Sí | nada |
| `bolsas` (bolsas listas en la mesa de salida; retraso 15/30 min en Tarea 3) | L–V | antes de 10:45 | reparto_pegado | Sí | nada |
| `salida_reparto` (~2 h) | L–V | 10:45 | sale_operario | Sí | nada |
| `efectivo_reporte` (tras la salida) | L–V | — | sale_operario | Sí | nada |
| `preparar_envio_viernes` (con sus cajas) | V | antes de 10:45 | envio_pegado | Sí | nada |
| `nacex_viernes` (lo lleva quien sale, de camino) | V | 10:45 | hay_envio + sale_operario | Sí | nada |
| `recuento_manana` (15 min) | L–V | 12:45 · 13:00 | — | Sí | nada |
| `revisar_envio` (el jueves decide también el viernes) | L–J | 15:30 | — | No | nada |
| `minis` (duración por conocer) | L | tarde | — | Sí | arrastrar |
| `resinas` (comprobar antes PRINCIPAL, R8) | M | tarde | — | Sí | arrastrar |
| `control_materiales` | J | tarde · antes de 17:55 | — | Sí | arrastrar |
| `preparar_envio` | L–J | tarde · antes de 18:10 | envio_pegado | Sí | nada |
| `recuento_tarde_envio` (15 min) | L–J | 17:55 · 18:10 | hay_envio | Sí | nada |
| `nacex_salida` (vuelta ~18:25) | L–J | 18:10 | hay_envio | Sí | nada |
| `recuento_tarde` (15 min) | L–J | 18:15 · 18:30 | no_hay_envio | Sí | nada |
| `recepcion_mercancia` (urgente: escalón 3) | L–V | en el momento | llega_mercancia | Sí | arrastrar |
| `pedido_cliente` | L–V | — | pedido_cliente | Sí | arrastrar |
| `tirada_vapers` (50, 2 tipos) | L–V | — | no_quedan_vapers | No | arrastrar |
| `cola_stock` (A) | L–V | — | cola libre | No | recalcular |
| `cola_compras` (C) | L–V | — | cola libre | No | nada |
| `cola_orden` (D) | L–V | — | cola libre | No | nada |

Si sale Administración, el tiempo hasta las 12:45 queda para la cola de tiempo libre (sin tarea especial).

### 2.7 Retraso de la salida (§4, decidido) ✅ Tarea 4
La tarea de bolsas (a las 10:45 en la mesa de salida) tiene los botones «Retrasar 15 min» y «Retrasar 30 min» (`retrasar_salida`). Cada retraso mueve la hora límite de bolsas, producción del reparto y envío del viernes, y la hora de la salida (y Nacex del viernes); queda registrado (`salida_retrasada`); si sale Administración se le envía en el momento el correo «Salida retrasada a las HH:MM» y se ve en `estado_actual`; el cierre de la mañana lo cruza con las cajas del reparto y las incidencias de la mañana.

## 3. Lectura de Google Sheets ✅ (Tarea 3)

### 3.1 Acceso
- **Cuenta de servicio** `osasun-lector-sheets@osasun-operations.iam.gserviceaccount.com` con permiso **Lector** solo sobre `STOCK OSASUN-CLAUDE` (creada y comprobada, P5), alcance `spreadsheets.readonly`.
- Su clave está guardada como **secreto de las funciones del servidor** en pruebas: `GOOGLE_CUENTA_TECNICA` (la escribió el propietario en el panel; nunca pasa por el chat ni por el repositorio).

### 3.2 Pestañas (confirmadas, §9)
`PRINCIPAL` (catálogo, cajas y granel en la columna R), `CONTEO DE CAJAS TOTAL` (contador y consumo; «INVERNADERO TOTAL» e «INDOOR TOTAL»), `ALMACEN` (categorías; grupo «INDOOR POPS») y `GIPUZKOA` (envío). `STOCK ALMACEN DIARIO` (sin tilde, sin fecha) no se lee en la V1. Los nombres se guardan en `configuracion`.

### 3.3 Cuándo se lee
Al pegar el reparto o el envío (R1) y al pedir la lista de stock, una vez por turno (R3). Nada más.

### 3.4 Si falla
Máximo 10 s y un reintento. Si sigue fallando, el cálculo **no se hace** y la pantalla dice por qué; el resto de la app sigue funcionando (principio 8). Si la hoja cambió de forma: `ESTRUCTURA_SHEETS_CAMBIADA`. La lectura busca encabezados y nombres, no celdas fijas. Cada lectura queda en `lecturas_sheets`.

## 4. Entornos y forma de trabajar

| Entorno | Qué es | Quién lo usa |
| --- | --- | --- |
| **Pruebas** | Proyecto Supabase `osasun-pruebas` (ref `rvypswuoafnjwqdwxjvo`, Irlanda), con 2 usuarios ficticios | Agente de base de datos (por el conector de Supabase, sin claves) y Lovable |
| **Producción** | Se crea cuando se apruebe la puesta en marcha | — |

- **Migraciones** en `supabase/migrations/`: se escriben en el repositorio y **después** se aplican a pruebas. El nombre de cada archivo lleva la versión con la que Supabase la registró, para que coincidan.
- Las migraciones que el conector marca como destructivas (borran algo) piden una confirmación que no llega a la app del propietario. Esas las ejecuta el propietario en el editor SQL de Supabase con el archivo del repositorio; después el agente las anota en el historial y comprueba la huella (prueba 00).
- **Datos solo de pruebas** en `supabase/seed_pruebas.sql` (usuarios ficticios, horario del operario, `entorno = pruebas`). Nunca en producción.
- **Pruebas automáticas** en `supabase/tests/` (ver `supabase/tests/LEEME.md`). Cada una corre dentro de una transacción que se deshace al final: la base queda como estaba. La 00 compara la «huella» de la estructura de pruebas con la de una base creada solo con las migraciones.

## 5. Permisos ✅

- **RLS activado en todas las tablas.** Una política de lectura por tabla (`MODELO_DATOS.md` §6). **Ninguna política de escritura.**
- **Nadie escribe directamente en tablas**: `anon` y `authenticated` no tienen permisos de insertar, modificar ni borrar. Toda escritura pasa por funciones `SECURITY DEFINER` del esquema `motor` que comprueban quién llama y su rol.
- `anon` (sin sesión) no puede leer ninguna tabla ni usar ninguna función.
- Lo que nace después (tablas o funciones nuevas) nace cerrado: los privilegios por defecto están retirados.
- Todas las funciones fijan `search_path` vacío.
- **Lovable usa solo la clave pública**. La clave maestra solo existe como secreto de las funciones del servidor.
- **Acceso (Tarea 5):** solo Google (correo y contraseña desactivados en Supabase Auth). El hook `hook_antes_de_crear_usuario` (solo lo puede usar `supabase_auth_admin`) rechaza cualquier cuenta que no esté en `cuentas_autorizadas`; quien no tiene ficha de persona no puede usar nada (`NO_AUTORIZADO`) ni ve ninguna fila.
- Probado con cada rol en las pruebas 04, 08, 11 y 12 (operario, Administración, usuario sin ficha, cuenta no autorizada y sin sesión).

## 6. Copias de seguridad
- **Producción en plan Pro:** copia diaria automática con 7 días de retención.
- La estructura está entera en el repositorio (migraciones): se puede reconstruir desde cero.
- Antes de la puesta en marcha, una prueba de restauración en pruebas.
- El stock no necesita copia: está en Google Sheets.

## 7. Coste estimado de Supabase

| Concepto | Coste |
| --- | --- |
| Hasta la puesta en marcha (solo pruebas, plan gratuito) | 0 € |
| Producción: plan Pro | ~25 $/mes |
| Pruebas en la misma organización tras la puesta en marcha | ~10 $/mes más (o 0 € en plan gratuito, que se pausa tras una semana sin uso) |
| Cuenta de servicio de Google y API de Sheets | 0 € |
| **Total** | **~25–35 $/mes (~23–33 €)** |

Precios a confirmar en la web de Supabase al contratar. No contrato nada.

## 8. Decisiones tomadas (revisión del PR #1, 26/10/2026)

| Tema | Decisión |
| --- | --- |
| D1 Redondeo R3 | Hacia arriba |
| D2 Cierre | Uno por turno |
| D3 Canal | Correo |
| Duraciones | §2.4 (§6.10 de `ESTADO_DEL_SISTEMA.md`); duración orientativa obligatoria en las tareas de Administración (P-T1) |
| Tiendas y envío | Como en la hoja; Durango = DURANGO o LAUDIO; envío en un bloque GIPUZKOA que va a Rentería |
| Minis · FIFO · vapers | Solo MINIBUDS MIX 10g · lo decide el operario · fuera de R3 |
| Reparto corregido | Sustituye y conserva lo hecho (`REGLAS_CALCULO.md` §2.6) |
| Obligatorias no terminadas | Se arrastran, salvo las ligadas a hora o turno |
| Pedido de cliente | Lo mete quien lo recibe |
| Bolsas a las 10:45 | Con «Retrasar 15/30 min» y aviso a quien sale |
| Indicador del viernes | Solo «limpieza hecha» |
| Encaje en bolsas · 30 min del problema | Al terminar la tienda · desde el WhatsApp |
| P-R1a · P-R1b · P-R1c · P-R3a | Aprobada · aprobada · rechazada · más adelante |

## 9. Riesgos

| Riesgo | Efecto | Medida |
| --- | --- | --- |
| Cambia la forma de la hoja | Cálculos que fallan | Lectura por encabezados; validación; error claro, nunca datos inventados. |
| Nombres irregulares en PRINCIPAL (P2) | Repartos rechazados | Errores por línea; limpieza P2. |
| Sheets sin actualizar (recuento no hecho) | Listas con datos de ayer | Se muestra la hora de los datos; R5 en la V1.1. |
| Duraciones aproximadas | Aviso de conflicto impreciso | Ajustar tras la semana en paralelo. |
| Clave de la cuenta técnica expuesta | Lectura del stock por terceros (no escritura) | Secreto del entorno; revocable al momento. |
| Plan gratuito pausado en producción | App parada | Producción en plan Pro. |
| Contraseñas filtradas (aviso de seguridad de Supabase Auth) | Un usuario podría elegir una contraseña conocida | La protección solo existe en el plan Pro: activarla en producción (o entrar sin contraseña). Decisión pendiente. |

## 10. Trazabilidad con los criterios de aceptación (§13)

| Criterio | Dónde está | Probado |
| --- | --- | --- |
| Jornada | Plantillas (§2.6), generación (§2.1), elección (§2.3) | ✅ 01 (semana simulada), 05 |
| Duplicados | Restricciones únicas, candado, `id_cliente` | ✅ 02, 06 |
| Reparto | R1 (`REGLAS_CALCULO.md` §2), casos R1-01…24 | ✅ unitarias R1 y 07; reparto real con la hoja; envío antes del recuento ✅ 09 |
| Stock (+35 %) | R3 (§3), casos R3-01…20 | ✅ unitarias R3 y 07; lista real del 26/10 en el PR #3 |
| Tareas de Administración | Encaje (§2.3), conflicto (§2.4) | ✅ 05, 10 |
| Problemas | §2.5 | ✅ 05, 09 |
| Cierre | §2.5 bis, `cierres` + correo | ✅ 10; envío real en el PR de la Tarea 4 |
| Permisos | §5 | ✅ 04, 08, 11, 12 (acceso) |
| Dispositivos · Uso real | Mismas funciones para Chromebook y Pixel; pantallas de Lovable | Con las pantallas |

## 11. Propuestas

Ninguna pendiente en este documento.
