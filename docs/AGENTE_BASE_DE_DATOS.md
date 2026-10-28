# Agente de base de datos — Instrucciones

**Versión:** 1.7 · **Fecha:** 26/10/2026 · **Emite:** coordinador del proyecto · **Aprueba:** propietario de Osasun

---

## 1. Rol

Eres el **único agente que diseña y modifica la base de datos** de OSASUN OPERATIONS (Supabase): tablas, permisos, funciones, motor de tareas, cálculos y lectura de Google Sheets.

No haces pantallas. Las pantallas las hace el agente de almacén en Lovable, que **solo consume** las funciones y vistas que tú publicas.

Respondes al **coordinador**. El propietario aprueba. No tomas decisiones de negocio.

## 2. Lee primero, siempre

1. `docs/ESTADO_DEL_SISTEMA.md`: fuente de verdad. Si algo de lo que vas a hacer lo contradice, te detienes y lo comunicas.
2. Este archivo.
3. `docs/ACTUALIZACIONES_MANUAL_ALMACEN.md`: contexto operativo.

## 3. Alcance

| Puedes | No puedes |
| --- | --- |
| Diseñar el modelo de datos, permisos (RLS), funciones, vistas, tareas programadas y lectura de Sheets | Hacer pantallas |
| Escribir pruebas de cálculos y reglas | Tocar producción sin aprobación expresa |
| Proponer cambios en `docs/` mediante PR | Crear cuentas, contratar servicios o generar gastos |
| Pedir aclaraciones al coordinador | Usar el ordenador del propietario: solo trabajas en Claude Code en la web |
| | Guardar claves, tokens o contraseñas en el repositorio |
| | Escribir en Google Sheets (en la V1 solo se lee) |
| | Inventar reglas de negocio no documentadas |

## 4. Forma de trabajar

- **Una tarea activa cada vez.** No abras frentes nuevos.
- Secuencia: **proponer → aprobar → ejecutar → verificar → documentar.**
- Cambios **pequeños, reversibles y verificables**, siempre en una rama con Pull Request. Nunca directamente en `main`.
- **Lo más sencillo que funcione.** Nada de arquitecturas por anticipación.
- Si falta un dato, **lo preguntas**; no lo supones. Lista las preguntas al final de tu entrega.
- Tus resúmenes de entrega van **en lenguaje de negocio**: qué has hecho, qué cambia, qué riesgo hay y qué decisión se necesita.

## 5. Principios técnicos obligatorios

1. **El servidor decide.** Cálculos, permisos, estados y verificaciones viven en Supabase. El navegador solo muestra y solicita.
2. **Permisos en la base de datos** (RLS), no escondiendo botones. El operario no puede ver ni tocar lo de Administración.
3. **Determinista y probado.** Ningún cálculo crítico depende de IA.
4. **Idempotencia.** La jornada se genera una vez al día; los reintentos, las dos pestañas o los cortes de conexión no duplican nada.
5. **Una sola fuente de verdad por dato.** Stock, consumos y catálogo → Google Sheets (solo lectura). Tareas, jornadas y registros → Supabase.
6. **Parametrizar, no duplicar.** Centros de trabajo, usuarios, roles, horarios, plantillas de tareas, marca obligatoria/flexible y modo «necesita aprobación / autónoma» son configuración. El almacén es el primer centro, no un caso especial: la Etapa 2 (tiendas) debe añadirse sin rehacer.
7. **Trazabilidad.** Cada tarea guarda quién, cuándo empezó, cuándo terminó, resultado o motivo.
8. **Si Google Sheets falla,** la app sigue funcionando con las tareas; los cálculos que dependen de Sheets lo indican claramente y no inventan datos.
9. **Dos entornos:** pruebas y producción. Solo pruebas hasta que se apruebe la puesta en marcha.

---

## 6. Cómo recibes el trabajo

- Tu **tarea activa** es la que figure en la sección «Tarea activa» de este archivo, en `main`. Cuando el propietario te escriba «Ejecuta tu tarea activa», lees este archivo actualizado y la ejecutas.
- Las **correcciones** del coordinador a una entrega llegan como **comentarios en tu PR**. Léelos antes de seguir.
- Puedes **consultar** Google Sheets con los conectores de Google, que tienen los permisos completos del propietario. **Nunca escribes con ellos.**
- Al terminar, no hace falta que nadie copie tu resumen: el coordinador lee tu PR directamente.

## Tarea activa

**Tarea 13** (sección 7). Lee antes `ESTADO_DEL_SISTEMA.md` **v1.26**: §5 R1d y §8 «Histórico».

---

## 7. TAREA 13 (activa): peticiones especiales e histórico, en pruebas

**A. Peticiones especiales (R1d):**
1. `guardar_reparto` acepta `peticiones: [{ destino_id, texto }]`, una línea por petición (texto libre, de 120 caracteres como máximo). Se guardan con el reparto o el envío y se conservan al modificarlo, como las líneas. Las vacías se ignoran.
2. **No van a producción ni cuentan como stock.** En la tarea de bolsas (y en la del envío), cada petición es un elemento de la bolsa de su tienda, de un tipo nuevo (por ejemplo, `peticion`), con `cantidad` 1 y el texto en `producto` o en un campo `texto`. Se marca con `marcar_cajas` (0 o 1). La bolsa (y la tarea) no se da por terminada hasta marcarlas todas.
3. `texto_whatsapp`: por cada tienda con peticiones, una línea «Además: …» después de sus productos.
4. `reparto_de_hoy_detalle` devuelve también `peticiones`.

**B. Histórico (§8):**
5. **`historico_dia(fecha)`** (solo Administración): todo lo de ese día del operario por defecto. Incluye `reparto` y `envio` (con el mismo objeto que `reparto_de_hoy_detalle`, con líneas, peticiones y `texto_whatsapp`), `pedidos_cliente` (los de ese día, objeto de §3.17), `cierres` (los de ese día, con su contenido y su texto) y un resumen de tareas (hechas y no hechas). Solo consulta. Una fecha sin jornada devuelve todo vacío, sin error.
6. `historico_dias(desde, hasta)` (opcional, si es sencillo): qué días tienen datos, para marcarlos en el calendario.

**C.** Pruebas de las dos partes; `CONTRATOS.md` a la 1.2, con su nota de cambios. Todo en verde y pruebas coincidiendo con el repositorio.

**Entrega:** Pull Request **«Tarea 13 — Peticiones especiales e histórico»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7. TAREA 12 (fusionada en el PR #11): nombre del propietario y pedidos de cliente con la lista, en pruebas

**A. Nombre (era la Tarea 11):** el propietario aparece como **«Asier»**: en su ficha (`personas.nombre`) y en su entrada de `cuentas_autorizadas` de pruebas, para que un alta nueva no lo deshaga. Son datos del entorno: no van al repositorio. Las frases que se refieren a la persona usan su nombre («Reparto preparado por Asier»); las que hablan del rol («Avisa a Administración») se quedan igual.

**B. Pedidos de cliente (§5 R1b):**
1. **`guardar_pedido_cliente(id_cliente, lineas: [{ producto, formato, cantidad }], entrega: "tienda"|"nacex", destino_id?, cliente, datos_envio?)`** (función del servidor; operario y Administración). Valida las referencias contra `catalogo` como `guardar_reparto`. `cliente`: nombre corto, obligatorio. `destino_id`: obligatorio si es `tienda` (una de `catalogo().tiendas.reparto`). `datos_envio`: texto libre, obligatorio si es `nacex`.
2. **Recoger en tienda:** el pedido queda pendiente para esa tienda y **se suma al siguiente reparto calculado** (el de hoy si aún no está calculado; si no, el del siguiente día de trabajo): suma a la producción y crea una **bolsa aparte** «Pedido de cliente · [cliente]» en esa tienda, además de la bolsa de reposición. Crea también la tarea **«Hay un pedido de cliente para dejar en [tienda]»**, con su lista, **que aparece en cuanto termina la producción del reparto** (no antes) y se hace entonces. Al recalcular o modificar el reparto, los pedidos pendientes se mantienen.
3. **Envío por Nacex:** crea **«Prepara el pedido de cliente»**, con la lista y los `datos_envio` en su porqué o detalle, bien legibles, y **activa Nacex ese día** igual que `hay_envio`: lunes a jueves, recuento a las 17:55 y «Salida a Nacex» a las 18:10; el viernes, antes de las 10:45, y lo lleva quien sale de reparto. Si ya hay envío, es el mismo viaje (sin duplicar tareas). Si las cajas no están, suman a la producción de ese día.
4. **`pedidos_cliente_abiertos()`** para el panel (y, si te sirve, para el operario): cliente, entrega, tienda o Nacex, estado y fecha. Los datos de envío solo para el personal (RLS).
5. La incidencia «Pedido de cliente» (`crear_incidencia`, opción `pedido_cliente`) y `registrar_evento('pedido_cliente')` quedan **obsoletas para las pantallas**: el pedido se registra con esta función. No borres nada.
5b. **Orden y «coge / haz»** (v1.24, R1b): la tarea del pedido para tienda aparece al terminar «Producción del reparto». La de Nacex va después de la revisión y la preparación del envío de la tarde. En sus elementos, cada referencia dice «Coge N del almacén» o «Haz N», según lo que quede en el almacén tras apartar el reparto o el envío del día, con la corrección de R1c.
5c. **Cajas en camino (R1c):** lo que sale en el reparto (salida hecha) o en un envío se resta del almacén y se suma a la tienda de destino como «en camino» hasta la mañana siguiente, **solo en los cálculos** (nunca se escribe en la hoja). Úsalo para lo que queda en el almacén (pedidos y envío del mismo día) y en `lista_stock` (R3: el contador sube por las cajas en camino que el recuento ya ha quitado del almacén y la tienda aún no ha apuntado). Deja la regla escrita en `REGLAS_CALCULO.md`, con sus casos de prueba, y documenta el desfase aceptado.
6. Pruebas: los dos tipos de entrega; «coge / haz»; cajas en camino (mismo día y día siguiente); el pedido de tienda entra en el reparto de hoy o en el siguiente; bolsa aparte; la tarea aparece tras la producción; Nacex se activa una sola vez aunque haya envío; idempotencia; permisos; referencias inexistentes.
7. `CONTRATOS.md` a la 1.1, con su nota de cambios. Todo en verde y pruebas coincidiendo con el repositorio.

**Entrega:** Pull Request **«Tarea 12 — Pedidos de cliente con la lista»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 10 (fusionada en el PR #10): el reparto se prepara con una lista, en pruebas

**Contexto:** en la prueba real del 28/10 se pegó el reparto de WhatsApp (reparto `8585eede-…` en pruebas) y 36 de 52 líneas dieron `PRODUCTO_DESCONOCIDO` por abreviaturas («bz1 4gr», «ind relax», «berry4», «mini», «*PORTU*»…). El propietario decide que **ya no se pegue texto**: el reparto se prepara en la app eligiendo productos de PRINCIPAL con contadores.

1. **`catalogo()`** (función del servidor, lee la hoja en solo lectura): las tiendas activas para reparto y envío (con su nombre) y los productos de PRINCIPAL con sus formatos, en el orden de la hoja y con su categoría (pestaña ALMACEN; los que no tengan categoría van en «Otros»). Cada referencia lleva una clave estable (producto + formato). Mismos errores si la hoja falla. Para el operario y para Administración.
2. **`guardar_reparto(id_cliente, tipo, sale?, lineas: [{ destino_id, producto, formato, cantidad }])`** (función del servidor): valida cada referencia contra el catálogo leído en ese momento (si una ya no existe: `REFERENCIA_NO_EXISTE`, con cuál) y hace **el mismo cálculo y la misma sustitución que hoy hace `pegar_reparto`** (lo que falta, bolsas por tienda, conservar lo hecho, reglas del envío), reutilizando su código. `sale` obligatorio en tipo reparto. Guarda también un `texto_whatsapp` generado (formato: `REPARTO dd/mm`, `SALE: ALMACÉN|YO`, tienda en mayúsculas, `Nx PRODUCTO FORMATO`) y lo devuelve.
3. **`reparto_de_hoy_detalle(tipo)`**: las líneas del reparto (o envío) aceptado hoy, para abrirlo y modificarlo con los contadores en sus valores, más `texto_whatsapp` y quién sale.
4. La tarea del operario pasa a llamarse **«Prepara el reparto»** (código `pegar_reparto` se puede mantener) y se cierra sola al guardarse un reparto.
5. `pegar_reparto` deja de usarse en las pantallas. Déjalo en su sitio (no lo borres), marcado como obsoleto en `CONTRATOS.md`.
6. Pruebas: el reparto real del 28/10, rehecho con estas líneas, da producción y bolsas coherentes; idempotencia por `id_cliente`; modificar conserva lo hecho; referencia inexistente; permisos (operario y Administración); hoja no disponible.
7. `CONTRATOS.md` a la 1.0, con la nota de cambios. Todo en verde y pruebas coincidiendo con el repositorio.

**Entrega:** Pull Request **«Tarea 10 — Reparto con lista»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7. TAREA 9 (fusionada en el PR #9): el panel sabe si hay reparto, en pruebas

1. `estado_actual` devuelve también `reparto_de_hoy` (el mismo objeto que `tarea_activa`), para que el panel de Administración muestre «Pegar reparto» o «Modificar reparto».
2. `CONTRATOS.md` a la 0.9, con su nota de cambios. Prueba en verde; pruebas coincidiendo con el repositorio.

**Entrega:** Pull Request **«Tarea 9 — Reparto de hoy en el panel»**, con un resumen corto y la salida de las pruebas.

---

## 7.0 TAREA 8 (fusionada en el PR #8): «¿Quién sale?» al pegar el reparto, en pruebas

1. **`pegar_reparto`:** si llega `sale` (el desplegable de la pantalla), **manda sobre la línea `SALE:`** del texto. No se da `SALE_CONTRADICTORIA` por esa diferencia; se anota en `registro_eventos`. Sin `sale` y sin `SALE:`, sigue `FALTA_SALE`.
2. **Cambiar quién sale sin volver a pegar:** nueva función `cambiar_quien_sale(sale)`, para el operario y para Administración, sobre la jornada de hoy del operario por defecto. Usa `motor.fijar_sale` (retira o recupera «Salida del reparto» y «Efectivo y reporte» como ya hace). Idempotente. `ESTADO_NO_VALIDO` si la salida ya está hecha.
3. **Nombres para el desplegable:** `mi_perfil` devuelve también `quien_sale_opciones: [{ valor: "administracion", nombre }, { valor: "operario", nombre }]`, con los nombres de las fichas (persona de Administración y operario por defecto).
4. Comprueba que el orden ya es el decidido: si sale el operario, tras «Bolsas listas en la mesa de salida» (10:45) toca «Salida del reparto» y a la vuelta «Efectivo y reporte». Añade una prueba.
5. `CONTRATOS.md` a la 0.8, con su nota de cambios. Todas las pruebas en verde y pruebas coincidiendo con el repositorio.

**Entrega:** Pull Request **«Tarea 8 — Quién sale»**, con un resumen corto y la salida de las pruebas.

---

## 7. TAREA 7 (fusionada en el PR #7): incidencias, reparto y «nunca sin tarea», en pruebas

Sale de la primera prueba real del propietario y de Eder. Lee antes `ESTADO_DEL_SISTEMA.md` **v1.17**: §4 («Nunca sin tarea»), §5 R1 y §6.6 («Incidencias»). Si algo no encaja con lo ya construido, propón la forma más simple antes de rehacer nada.

1. **Reparto:**
   - `pegar_reparto` lo puede usar también **Administración**, y entonces va a la jornada del operario por defecto. Mismo cálculo, misma sustitución conservando lo hecho.
   - «Pega el reparto» se cierra sola al aceptarse un reparto. `terminar_tarea` sobre ella sin reparto aceptado exige `motivo` (`MOTIVO_OBLIGATORIO`).
   - `tarea_activa` dice si hoy ya hay un reparto aceptado (`reparto_de_hoy: { reparto_id, aceptado_en, pegado_por } | null`), para que la pantalla muestre «Pegar reparto» o «Modificar reparto».
2. **Nunca sin tarea:** si no queda nada disponible antes de la siguiente tarea con hora, primero las fijas de la tarde de ese día (plantillas `dia_semana` del turno de tarde sin hora) y después «Orden y limpieza», que **no se gasta** (vuelve a estar disponible al terminarla). Recuento, revisión del envío, Nacex y salida no se adelantan.
3. **Incidencias (nuevo modelo, §6.6):**
   - Una incidencia lleva `opcion` (`llega_mercancia` · `pedido_cliente` · `pedir_comprar` · `recogida_nacex` · `corregir` · `bloqueado`), `descripcion` (una línea), `quien` (`operario` | `administracion`) e `importancia` (`ahora` | `hoy` | `cuando_pueda`), con los valores por defecto de la tabla de §6.6.
   - **Del operario:** crea su tarea. `ahora` va como las urgentes (al terminar la referencia o la bolsa en curso); `hoy` es obligatoria del día; `cuando_pueda` va a la cola libre. Al hacer la tarea, la incidencia se cierra sola, **salvo `pedir_comprar`**, que pasa a «pedido, esperando a que llegue» y se cierra a mano.
   - **De Administración:** no crea tarea. Envía al momento un correo a Administración («Incidencia: …»), con el mismo sistema de correo y reintentos. Queda «esperando a Administración» hasta que el operario la cierra.
   - `bloqueado` es el flujo de problemas actual (`abrir_problema` y los siguientes); se puede seguir llamando igual.
   - `corregir` sigue midiendo su tiempo (de inicio a fin), como la incidencia actual.
   - Funciones: crear incidencia (una sola función con `id_cliente`), `incidencias_abiertas()` (para «Cerrar incidencias», con su estado en una frase) y `cerrar_incidencia(incidencia_id, nota?)`. Reutiliza lo que ya existe (`registrar_evento`, `incidencias`, `problemas`) si encaja, sin duplicar tablas.
   - Las incidencias entran en el cierre del turno.
4. **Que no se olviden al recargar:** `tarea_activa` devuelve también `incidencias_abiertas` (número), la incidencia en curso con tiempo si la hay y los `problemas_abiertos`. Confirma en `CONTRATOS.md` los campos de `PROBLEMA_YA_ABIERTO` e `INCIDENCIA_YA_ABIERTA`.
5. `CONTRATOS.md` a la 0.7, con una nota de cambios al principio (el coordinador la traslada a Lovable).
6. Pruebas de todo lo anterior, todas en verde, y pruebas coincidiendo con el repositorio.

**Entrega:** Pull Request **«Tarea 7 — Incidencias, reparto y nunca sin tarea»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 6 (fusionada en el PR #6): teléfono de Administración y conflicto con obligatorias vencidas

---

## 7.1 TAREA 5 (fusionada en el PR #5): acceso con Google y preparación para las pantallas, en pruebas


**Objetivo:** que en pruebas solo puedan entrar, con su cuenta de Google, las personas dadas de alta, y que Lovable tenga todo lo necesario para hacer las pantallas sin tocar la base de datos.

### Contexto
- **Las pantallas van en otro repositorio** (`osasun-pantallas`, creado por Lovable), **sin integración de Supabase**: Lovable solo tendrá la URL del proyecto y la clave pública. Todo lo que necesiten las pantallas tiene que estar en `CONTRATOS.md`.
- El **cliente de Google** (OAuth) lo crea el propietario con la guía del coordinador, y él mismo escribe el ID y el secreto en Supabase (Authentication → Providers → Google). Tú no los ves ni los pides.

### Pasos
1. **Correcciones del PR #4** (comentario del coordinador): se crea la tarea de Administración cuando no hay ninguna obligatoria en riesgo, y el correo se reintenta solo si Resend lo rechaza (3 intentos, separados 5 minutos), con el fallo final visible en `estado_actual`. Cada una con sus pruebas.
2. **Acceso:**
   - Solo con Google; el registro con correo y contraseña, desactivado.
   - Una **lista de cuentas autorizadas** (en `configuracion` de pruebas, no en el repositorio), aplicada por la base de datos: una cuenta que no esté en la lista no crea usuario. Puede servir un *hook* de autenticación u otro mecanismo gratuito equivalente.
   - Direcciones de vuelta permitidas para las previsualizaciones de Lovable (`*.lovable.app` y `*.lovableproject.com`).
3. **Personas reales en pruebas:** pide al propietario, **en tu sesión**, los correos de Google de Administración y del operario. Dalos de alta en pruebas con su rol, su centro y el horario del operario. Los correos no van al repositorio ni al PR.
   - El propietario ya ha entrado una vez con su cuenta de Google en pruebas (comprobando la configuración), así que puede que ya exista su usuario en `auth.users`. Revísalo y vincúlalo a su persona; no lo dupliques.
4. **Correos de pruebas:** el 03/11/2026 apaga los cierres del operario ficticio (el propietario ya habrá visto el formato). Déjalo programado o documentado para hacerlo ese día.
5. **`CONTRATOS.md` listo para Lovable:** añade una sección «Guía para las pantallas» que diga cómo iniciar sesión con Google, cómo llamar a cada función (`rpc` y `functions.invoke`), qué hay que actualizar en directo (Realtime) y los mensajes de error que se muestran tal cual. La URL del proyecto y la clave pública (que no es secreta) van ahí.
6. **Pruebas automáticas:** la lista de autorizados (entra un correo autorizado y uno no autorizado no puede), las correcciones del paso 1 y todas las anteriores sin romper.
7. **Avisos de seguridad** de Supabase: ninguno, salvo el de contraseñas, si sigue apareciendo con el acceso por contraseña desactivado; explica por qué.

### Entrega
- Pull Request titulado **«Tarea 5 — Acceso con Google y guía para pantallas (pruebas)»**.
- Descripción: un resumen de **10 líneas como máximo** en lenguaje de negocio, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 4 (fusionada en el PR #4): problemas, incidencias, tareas de Administración, retraso de la salida y cierre por correo, en pruebas


**Objetivo:** completar en pruebas todo el motor de la V1 que no depende de las pantallas, de modo que la base de datos cumpla los criterios de §13 «Tareas de Administración», «Problemas» y «Cierre».

### Entorno y accesos
- Solo pruebas: ref **`rvypswuoafnjwqdwxjvo`**. Mismas prohibiciones que en las tareas anteriores.
- **Correo:** servicio **Resend**, en plan gratuito. Su clave va como secreto de las funciones del servidor (`RESEND_API_KEY`) y la escribe el propietario en el panel, cuando tú la pidas con la herramienta de secretos. Sin dominio propio, Resend solo envía al correo con el que se creó la cuenta, y en la V1 basta con eso.
- El **correo de destino** de Administración va en `configuracion` del proyecto de pruebas, **no en el repositorio**.

### Pasos
1. **Del PR #3:** el envío pegado antes del recuento de la mañana descuenta el reparto aceptado ese día (comentario del coordinador), con sus pruebas.
2. **Migraciones:** `problemas`, `incidencias`, `eventos_jornada` y `cierres` (`MODELO_DATOS.md`), con RLS y sin escritura directa.
3. **Problemas e incidencias** (`CONTRATOS.md` §3.6 y §3.7): `abrir_problema`, `problema_llamada`, `resolver_problema` (también para Administración), `iniciar_incidencia` y `terminar_incidencia`. Tiene que funcionar la reaparición de «Llama a Administración» a los 30 minutos desde el WhatsApp.
4. **Eventos:** `registrar_evento` (llega mercancía, pedido de cliente, no quedan vapers), que crea la tarea condicionada. Administración también puede registrar un pedido de cliente.
5. **Tareas de Administración:** `crear_tarea_admin`, con la **duración orientativa obligatoria** y la detección de conflicto (`PLAN_TECNICO.md` §2.4, con las duraciones de `ESTADO_DEL_SISTEMA.md` §6.10); `cancelar_tarea` y `estado_actual`.
6. **Retraso de la salida:** `retrasar_salida(minutos)` con 15 o 30 minutos, sobre la tarea de las bolsas de las 10:45. Queda registrado y, si sale Administración, se le avisa en el momento por correo («Salida retrasada a las HH:MM») y se muestra en `estado_actual`.
7. **Cierre por turno** (D2): se genera solo a las 13:00 y a las 18:30 de lunes a jueves, y a las 13:00 el viernes, en hora de Madrid. Contenido de `ESTADO_DEL_SISTEMA.md` §8 «Cierre», más los retrasos de la salida cruzados con las cajas del reparto y las incidencias de la mañana. El viernes, el indicador de calidad es solo «limpieza hecha». Se envía por correo (D3) y se consulta con `cierre` y `cierres_recientes`. Es idempotente: nunca se envían dos correos del mismo cierre.
8. **Pruebas automáticas:**
   - Flujo de problemas: abrir, llamar, sin respuesta, reaparición a los 30 minutos y solución obligatoria.
   - Incidencias.
   - Las urgentes entran al terminar la referencia en curso.
   - Conflicto al crear una tarea, con la decisión «qué cede» registrada.
   - Retraso de la salida.
   - Cierre de cada turno con datos correctos y una sola vez.
   - Permisos: el operario no ve cierres ni puede usar funciones de Administración.
9. **Prueba real:** envía **un** cierre y **un** aviso de retraso de prueba al correo de Administración, y deja constancia en el PR (asunto y hora, sin datos sensibles).
10. **Avisos de seguridad** de Supabase: ninguno nuevo.

### Criterios de aceptación
- Todas las pruebas pasan, y en el PR se ve la salida.
- Pruebas coincide exactamente con el repositorio.
- Ninguna clave ni correo personal en el repositorio ni en el PR.

### Entrega
- Pull Request titulado **«Tarea 4 — Problemas, tareas de Administración y cierre (pruebas)»**.
- Descripción: un resumen de **10 líneas como máximo** en lenguaje de negocio, la salida de las pruebas y las dudas.

---

## 7.1b TAREA 3 (fusionada en el PR #3): reparto y stock, leyendo la hoja, en pruebas


**Objetivo:** que en pruebas funcionen **pegar el reparto** (R1) y la **lista de stock +35 %** (R3), leyendo `STOCK OSASUN-CLAUDE` en solo lectura con la cuenta técnica, y que el operario pueda ir marcando referencias y cajas. Sin problemas, incidencias, tareas de Administración ni cierres: eso es la Tarea 4.

### Entorno y accesos
- Solo pruebas: ref **`rvypswuoafnjwqdwxjvo`**, con el conector de Supabase. Mismas prohibiciones que en la Tarea 2.
- **Clave de la cuenta técnica** (`osasun-lector-sheets@osasun-operations.iam.gserviceaccount.com`, permiso Lector ya comprobado): pídela como secreto de las funciones del servidor con la herramienta de secretos del conector (el propietario escribe el valor en el panel de Supabase; nunca pasa por el chat ni por el repositorio). Antes de pedirla, avisa en tu sesión de que el propietario debe tener preparado el archivo de clave. El coordinador le guía para crearlo.
- Alcance de Google: **solo `spreadsheets.readonly`**. Nunca escribes en Sheets.

### Pasos
1. **Correcciones del PR #2:** recepción de mercancía en el escalón 3, duración de los minis a nulo, envío del viernes antes de las 10:45 (comentario del coordinador). Cada una con su prueba.
2. **Migraciones:** `tarea_elementos`, `repartos`, `reparto_lineas` y `lecturas_sheets` (`MODELO_DATOS.md` v0.2), con RLS y sin escritura directa, como en la Tarea 2.
3. **Funciones del servidor** `pegar_reparto` y `lista_stock` (`CONTRATOS.md` §3.9 y §3.10). Leen la hoja por encabezados y nombres, no por celdas fijas, y guardan cada lectura en `lecturas_sheets`. El cálculo de R1 y R3 se hace en código separado de la lectura, para poder probarlo sin la hoja.
4. **Reparto corregido** (decisión del propietario): la versión nueva sustituye a la anterior y se conserva lo hecho (`ESTADO_DEL_SISTEMA.md` §5 R1).
5. **Funciones de BD:** `iniciar_elemento`, `terminar_elemento` y `marcar_cajas`, con el punto de encaje (al terminar una referencia o una tienda entera). La duración de la producción del reparto = cajas que faltan × 1 min, y la de las bolsas = 3 min por tienda (`ESTADO_DEL_SISTEMA.md` §6.10).
6. **Pruebas automáticas:**
   - Todos los casos R1 y R3 de `REGLAS_CALCULO.md` como pruebas unitarias, con datos fijos.
   - Hoja no disponible y estructura cambiada.
   - Idempotencia: el mismo reparto dos veces, la lista dos veces en el turno y marcar la misma caja dos veces.
   - Reparto corregido con trabajo ya hecho.
   - Permisos de las tablas nuevas.
7. **Prueba con la hoja real:** una ejecución de `lista_stock` en pruebas con los datos de hoy. Pega en el PR la lista resultante (referencia, consumo, contador, cajas y motivo) para que el propietario la compare con su propio cálculo.
8. **Avisos de seguridad** de Supabase: ninguno nuevo.

### Criterios de aceptación
- Todas las pruebas pasan, y en el PR se ve la salida.
- Pruebas coincide exactamente con las migraciones y las funciones del repositorio.
- La hoja solo se lee: el alcance de la cuenta es de solo lectura.
- Ninguna clave en el repositorio ni en el PR.

### Entrega
- Pull Request titulado **«Tarea 3 — Reparto y stock (lectura de Sheets, pruebas)»**.
- Descripción: un resumen de **10 líneas como máximo** en lenguaje de negocio, la salida de las pruebas, la lista de stock real del paso 7 y las dudas.

---

## 7.2 TAREA 2 (fusionada en el PR #2): estructura base y jornada automática, en pruebas


**Objetivo:** que en el proyecto de **pruebas** exista la base de datos mínima y que la **jornada del operario se genere sola** cada día con las tareas correctas, sin duplicados y con los permisos bien puestos. Sin Google Sheets, sin repartos, sin problemas y sin cierres: eso llega en las Tareas 3 y 4.

### Entorno
- Solo el proyecto Supabase de pruebas: ref **`rvypswuoafnjwqdwxjvo`** (eu-west-1). Accedes con el **conector de Supabase** de la cuenta de Claude del propietario. No necesitas ni pides claves.
- **Prohibido:** cualquier otro proyecto, crear proyectos o ramas de Supabase (tienen coste), cambiar el plan o la facturación, leer Google Sheets desde Supabase y crear usuarios reales.

### Pasos
1. **Planos al día.** Incorpora a `MODELO_DATOS.md`, `CONTRATOS.md`, `REGLAS_CALCULO.md` y `PLAN_TECNICO.md` (versión 0.2) las correcciones y decisiones del comentario del coordinador en el PR #1. Quita las dudas ya resueltas.
2. **Migraciones** en `supabase/migrations/`, en el repositorio. Aplica cada una a pruebas **después** de escribirla en el repositorio, nunca al revés. Solo las tablas que necesita esta tarea: `centros_trabajo`, `personas`, `horarios`, `plantillas_tarea`, `configuracion`, `jornadas`, `tareas` y `registro_eventos`. El resto llega en su tarea.
3. **Permisos:** RLS en todas las tablas, ninguna escritura directa y funciones que comprueban el rol, según `MODELO_DATOS.md` §6 y `PLAN_TECNICO.md` §5.
4. **Funciones:** `generar_jornada` (con los arrastres de §6.5 ya decididos), `tarea_activa` (regla de `PLAN_TECNICO.md` §2.3), `iniciar_tarea`, `terminar_tarea`, `anotar_motivo` y `mi_perfil`. Para las tareas condicionadas que aún no tienen función propia (`SALE:`, envío, eventos), añade **una función de prueba**, solo usable en pruebas, que fije la condición. Está para simular la semana, no la usarán las pantallas.
5. **Carga inicial:** el almacén y las tiendas con sus alias; los horarios del operario; las plantillas de `PLAN_TECNICO.md` §2.6, corregidas (bolsas a las 10:45 con retraso, Nacex del viernes, duraciones de §6.10); y la configuración. **Usuarios de prueba** con correos ficticios: un operario y una administración.
6. **Generación programada** cada día a las 06:00, hora de Madrid.
7. **Pruebas automáticas** en el repositorio, repetibles, que se ejecuten contra pruebas y dejen la base como estaba:
   - **Semana simulada de lunes a viernes:** días con y sin envío, días en que sale el operario y días en que sale Administración. Cada tarea aparece el día y a la hora correctos (criterio «Jornada» de §13).
   - **Idempotencia:** generar dos veces, dos llamadas a la vez e iniciar o terminar dos veces no duplican nada.
   - **Arrastres:** una obligatoria de plantilla no terminada pasa al día siguiente; una ligada a hora o turno no pasa.
   - **Permisos:** el operario no ve la jornada de otra persona, no escribe directamente en ninguna tabla y no puede usar funciones de Administración.
   - **Orden de `tarea_activa`:** un caso por cada escalón de la regla.
8. **Revisión de seguridad:** ejecuta los avisos de seguridad y rendimiento de Supabase. Al entregar no debe quedar ninguno de seguridad.

### Criterios de aceptación
- Todas las pruebas pasan, y en el PR se ve la salida de la ejecución.
- La estructura de pruebas coincide exactamente con las migraciones del repositorio.
- Nada fuera del alcance de esta tarea.
- Ninguna clave en el repositorio.

### Entrega
- Pull Request titulado **«Tarea 2 — Estructura base y jornada automática (pruebas)»**.
- Descripción del PR: un resumen de **10 líneas como máximo** en lenguaje de negocio, la salida de las pruebas y las dudas, si las hay.

---

## 7.3 TAREA 1 (fusionada en el PR #1): propuesta técnica de la V1

**Objetivo:** diseñar, sin construir, todo lo que la base de datos necesita para la V1 descrita en `ESTADO_DEL_SISTEMA.md` (§12, V1).

**En esta tarea no ejecutas nada en Supabase, no creas proyectos ni cuentas y no escribes código de producción.** Solo documentos.

### Entregables (un único Pull Request)

| Archivo | Contenido |
| --- | --- |
| `docs/MODELO_DATOS.md` | Entidades, campos clave, relaciones y estados. Debe cubrir: centros de trabajo, usuarios y roles, plantillas de tareas (con hora, por día de la semana, condicionadas), jornadas, tareas del día, elementos de una tarea (referencias de producción, cajas de cada bolsa), repartos (texto original y líneas interpretadas), tareas de Administración, problemas, incidencias, registro de eventos, configuración y cierres de turno. Marca lo que sea V1.1 como «previsto, no implementado», solo si no añade complejidad. |
| `docs/CONTRATOS.md` | Funciones y vistas que publicarás para las pantallas, cada una con entradas, salidas, errores y qué rol puede usarla. Mínimo: tarea activa, iniciar/terminar tarea o elemento, abrir/resolver problema, registrar incidencia, pegar reparto, crear tarea de Administración (con detección de conflicto), estado actual para el panel, cierre de turno. |
| `docs/REGLAS_CALCULO.md` | Especificación exacta, con casos de prueba (normales y de error), de: **R1** (lectura del texto del reparto: formato, normalización de nombres, líneas no reconocidas, falta de `SALE:`) y **R3** (+35 %, orden por consumo, categorías rotativas, sin granel). Incluye al menos estos ejemplos: V2 4 g, consumo 74, contador +25 → 1 caja; Indoor 4 g, consumo 51, contador −27 → 45 cajas. Propón el redondeo (decisión abierta D1). |
| `docs/PLAN_TECNICO.md` | Motor de tareas (generación diaria, encaje de tareas con hora, urgentes y con hora límite, arrastres), lectura de Sheets (cuenta de servicio de solo lectura, cuándo se lee, qué pasa si falla), entornos, permisos, copias de seguridad, coste estimado de Supabase, riesgos y **decisiones que necesitas del propietario** (solo las imprescindibles). |

### Criterios de aceptación de la Tarea 1

- Cubre **toda la V1** y nada más que la V1 (salvo lo marcado como previsto).
- Cada criterio de aceptación de `ESTADO_DEL_SISTEMA.md` §13 se puede trazar a una parte del diseño.
- Las reglas de §5 a §7 de `ESTADO_DEL_SISTEMA.md` están reflejadas sin cambios. Si propones una mejora, va en una sección aparte titulada «Propuestas», nunca mezclada con lo aprobado.
- Es lo más simple posible: sin tablas, servicios ni capas que la V1 no necesite.
- Las dudas están listadas al final, no resueltas por suposición.

### Entrega

- Pull Request titulado **«Tarea 1 — Propuesta técnica base de datos»**.
- En la descripción del PR: un resumen de **10 líneas como máximo** en lenguaje de negocio y la lista de decisiones que necesitas.
- El propietario pasará ese resumen al coordinador para su revisión. **No empiezas la Tarea 2 hasta recibir la aprobación.**

---

## 8. Historial

| Versión | Fecha | Cambio |
| --- | --- | --- |
| 1.0 | 26/10/2026 | Instrucciones iniciales y Tarea 1. |
| 1.1 | 26/10/2026 | Tarea 1 entregada (PR #1). Nuevo sistema de «Tarea activa» y comentarios en PR. Regla de consulta de Sheets. |
| 1.2 | 26/10/2026 | Tarea 1 aprobada y fusionada. Tarea 2 activa: estructura base y jornada automática en pruebas. |
| 1.3 | 26/10/2026 | Tarea 2 aprobada y fusionada. Tarea 3 activa: reparto y stock con lectura de Sheets, en pruebas. |
| 1.4 | 26/10/2026 | Tarea 3 aprobada y fusionada. Tarea 4 activa: problemas, incidencias, tareas de Administración, retraso de la salida y cierre por correo. |
| 1.5 | 27/10/2026 | Tarea 4 aprobada y fusionada. Tarea 5 activa: acceso con Google y guía para las pantallas. |
| 1.6 | 27/10/2026 | Tarea 5 aprobada y fusionada. Tarea 6 activa: ajustes de la revisión. |
| 1.7 | 27/10/2026 | Tarea 6 fusionada. Tarea 7 activa: ajustes de la primera prueba real (nunca sin tarea, «Pega el reparto», Incidencia y Cerrar tarea). |
| 1.8 | 27/10/2026 | Tarea 7 fusionada. Sin tarea activa. |
| 1.9 | 27/10/2026 | Tarea 8 activa: «¿Quién sale?» al pegar el reparto. |
| 1.10 | 27/10/2026 | Tarea 8 fusionada. Tarea 9 activa: `reparto_de_hoy` en `estado_actual`. |
| 1.11 | 27/10/2026 | Tarea 9 fusionada. Sin tarea activa. |
| 1.12 | 28/10/2026 | Tarea 10 activa: reparto con lista (R1 rediseñada tras la prueba real). |
| 1.13 | 28/10/2026 | Tarea 10 fusionada. Tarea 11 activa: nombre «Asier». |
| 1.14 | 28/10/2026 | La Tarea 11 (sin empezar) se integra en la Tarea 12: nombre «Asier» y pedidos de cliente con la lista. |
| 1.15 | 28/10/2026 | Tarea 12 fusionada. Sin tarea activa. |
| 1.16 | 28/10/2026 | Tarea 13 activa: peticiones especiales e histórico. |
