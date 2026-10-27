# Agente de base de datos — Instrucciones

**Versión:** 1.6 · **Fecha:** 26/10/2026 · **Emite:** coordinador del proyecto · **Aprueba:** propietario de Osasun

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

**Tarea 6** (sección 7). Empieza leyendo el comentario del coordinador en el PR #5.

---

## 7. TAREA 6 (activa): ajustes de la revisión del PR #5, en pruebas

1. **Teléfono de Administración:** el propietario te lo da en tu sesión. Guárdalo en `telefono_administracion` de pruebas, fuera del repositorio y del PR.
2. **Conflicto:** las obligatorias pendientes que ya han vencido no cuentan como «en riesgo», pero su duración sí se resta del tiempo disponible. Añade su prueba en `10_admin_conflictos_cierres.sql`.
3. **Petición de las pantallas** (revisión de la Tarea 1 de Lovable): `tarea_activa` debe devolver también `incidencia_abierta` (`{ incidencia_id, descripcion, iniciada_en }` o null) y `problemas_abiertos` (`[{ problema_id, tarea_id, tipo, descripcion, estado, proxima_llamada_en }]`). Así la pantalla no pierde una incidencia o un problema abierto al recargar o al cambiar de dispositivo (Chromebook o Pixel). Confirma en `CONTRATOS.md` qué campos devuelven `PROBLEMA_YA_ABIERTO` e `INCIDENCIA_YA_ABIERTA`.
4. Si `CONTRATOS.md` cambia, súbele la versión: el coordinador copia ese archivo al repositorio de las pantallas.
5. Todas las pruebas pasan y pruebas coincide con el repositorio.

**Entrega:** Pull Request **«Tarea 6 — Ajustes de la revisión del PR #5»**, con un resumen corto y la salida de las pruebas.

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
