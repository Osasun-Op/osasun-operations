# Agente de base de datos — Instrucciones

**Versión:** 1.7 · **Fecha:** 26/10/2026 · **Emite:** coordinador del proyecto · **Aprueba:** propietario de Osasun

---

## 1. Rol

Eres el **único agente que diseña y modifica la base de datos** de OSASUN OPERATIONS (Supabase): tablas, permisos, funciones, motor de tareas, cálculos y lectura de Google Sheets.

No haces pantallas. Las pantallas las hace el agente de almacén en Lovable, que **solo consume** las funciones y vistas que tú publicas.

Respondes al **coordinador**. El propietario aprueba. No tomas decisiones de negocio.

## 2. Lee primero, siempre (obligatorio, en este orden)

1. **`docs/CONSTITUCION_TECNICA.md`**: las reglas que no se rompen. Manda sobre este archivo.
2. **`docs/ESTADO_DEL_SISTEMA.md`**: las partes que cita tu tarea.
3. **`docs/CONTRATOS.md`**: las funciones que toca tu tarea.
4. Este archivo y tu tarea activa.
5. **El código que ya existe** sobre eso (`grep` en `supabase/`). Si ya hay algo que lo hace, se reutiliza o se sustituye; nunca otro al lado.
6. `docs/ACTUALIZACIONES_MANUAL_ALMACEN.md`, si hace falta contexto operativo.

**Todo PR lleva el apartado «Qué he leído y qué existía ya»** (qué has leído, qué reutilizas, qué sustituyes y qué es nuevo) y la prueba de que **funciona en el proyecto de pruebas**: una llamada real que responde bien y los registros del servidor sin errores nuevos (constitución, regla 9). Sin eso, el coordinador no lo da por revisado.

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

- **Producción (desde el 02/11/2026):** cuando el propietario fusione un PR tuyo con migraciones o funciones del servidor, pásalas a producción siguiendo `docs/AUDITORIA.md` §5 y cuéntalo en un comentario de ese PR. En producción nunca ejecutas pruebas que escriban.
  - **Excepción, tiendas (decisión del propietario, 02/11/2026):** desde la migración `20261102190536_tiendas_primera_parte` (Tarea 27), **producción espera** hasta que el propietario diga que lo de tiendas está probado en Basauri y Portugalete. Producción se queda con 46 migraciones; las siguientes también esperan y se pasan juntas, en orden, cuando él lo apruebe.

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

Ninguna. La Tarea 32 está fusionada (PR #36). Queda de tiendas la **Tarea 33** (resumen del día), que preparará el coordinador.

---

## 7.0 TAREA 29b (fusionada en el PR #29; solo en pruebas, producción espera): el aviso de salida solo cuando toca, en pruebas

**Qué pasa (03/11/2026, 19:33):** a Eder le sale `aviso_salida` («Es la hora de salida (10:45) y las bolsas no están listas…») por la tarde. `tarea_activa_de` (Tarea 29, migración `20261103175352`) solo mira que las bolsas estén sin hacer y que haya pasado su hora límite. Hoy las bolsas siguen `pendiente` (se pasaron a mañana por error a las 10:28, `disponible_desde` = mañana) aunque el reparto salió a las 10:48. Arreglo pequeño, solo esto:

1. `aviso_salida` solo si **todo** esto se cumple: el reparto de hoy **aún no ha salido** (la «Salida del reparto» del operario no ha empezado ni terminado; si sale Administración, la misma señal de «ha salido» de la Tarea 28), el operario está **en su turno** (`motor.en_turno`), las bolsas son de hoy y **ya están disponibles** (`disponible_desde <= ahora`) y ha pasado su hora límite. En cualquier otro caso, `null`.
2. **`retrasar_salida`**: si el reparto ya ha salido, `ESTADO_NO_VALIDO` («El reparto ya ha salido.») sin mover ninguna hora.
3. **Prueba** con el caso de hoy (bolsas pendientes con `disponible_desde` mañana, salida hecha a las 10:48, a las 19:33 → `aviso_salida: null`, y `retrasar_salida` → `ESTADO_NO_VALIDO`), más el caso normal (10:46, bolsas sin hacer, sin salir → el aviso sale).
4. **Solo en pruebas; producción espera** (excepción de tiendas). De paso, el pendiente de `CONTRATOS.md` §9.11 (la pantalla de «Recibe la bolsa» no enseña la lista), si te cabe en el mismo PR.

**Entrega:** PR **«Tarea 29b — Aviso de salida solo cuando toca»**, con «Qué he leído y qué existía ya», pruebas en verde, una llamada real, registros sin errores y cómo deshacer.

---

## 7.0 TAREA 29c (fusionada en el PR #32; solo en pruebas, producción espera): quitar las bolsas de ayer arrastradas y que lo del reparto nunca se arrastre, en pruebas

**Qué pasa (04/11/2026):** las bolsas del 03/11 que se pasaron a mañana por error (conflicto de las 10:28, `cede` = bolsas, `manana`; tarea `6a13b51c-97c5-4ab3-ab53-694052a4ead2`) se han **arrastrado a hoy** a las 06:00 (`arrastre:6a13b51c…`, 46 elementos). El reparto del 03/11 ya salió. Hoy Eder tiene dos «Bolsas listas en la mesa de salida»: la de hoy (`bolsas`, 52 elementos) y la arrastrada, que sobra. Arreglo pequeño, solo esto:

1. **Datos de pruebas:** cancelar la tarea arrastrada de hoy (`clave = 'arrastre:6a13b51c-97c5-4ab3-ab53-694052a4ead2'`) con el motivo «Del reparto del 03/11, que ya salió», con una migración de datos o una función ya existente, y que quede en el registro. No tocar la de hoy (`bolsas`).
2. **Que no vuelva a pasar:** `motor.arrastrar` **nunca** pasa al día siguiente las tareas del reparto o del envío de un día (las de `motor.es_del_reparto`: producción, bolsas, salida, pedidos de cliente del reparto, preparación del envío, Nacex), aunque tengan `no_terminada = 'arrastrar'`; constan como no hechas en su día. Revisa también si la decisión `manana` de la Tarea 29 deja alguna puerta abierta.
3. **Prueba** con el caso del 03/11 → 04/11 (bolsas pasadas a mañana: al día siguiente no aparecen) y que lo demás se sigue arrastrando igual (las de Administración, las fijas obligatorias).
4. **Solo en pruebas; producción espera.**

**Entrega:** PR **«Tarea 29c — Lo del reparto no se arrastra»**, con «Qué he leído y qué existía ya», pruebas en verde, registros sin errores y cómo deshacer.

---

## 7.0 TAREA 32 (fusionada en el PR #36; solo en pruebas, producción espera): el panel de Administración por centro, en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` E2-8 («Panel de Administración») y `AGENTE_COORDINADOR.md`, bloque 1, punto 23 y nota del 03/11 («Panel (Tarea 32)»). Reutiliza: `estado_actual()` (almacén), `tienda_hoy_de` y sus piezas (tareas con puntos y «hecha por», `en_turno`, bolsa, envíos, incidencias, atascados, peticiones, pedidos), `cierres_caja()`, `incidencias_tiendas()` y `tiendas()`. **Nada al lado:** lo que ya calcula la tableta se lee igual para Administración. Solo en pruebas; producción espera.

1. **Selector de centros** para el panel: el almacén y las tiendas activas, en el orden de la ruta (Almacén · Bilbao · Algorta · Barakaldo · Basauri · Portugalete · Donosti · Rentería; Durango cuando abra). Amplía `tiendas()` o una función nueva, sin duplicar.
2. **Resumen de una tienda para Administración** (`resumen_tienda(tienda_id, fecha?)`, hoy por defecto), **solo de lectura**: no crea la jornada ni tareas, no pasa atascados a Administración ni toca nada (lo que la tableta hace al abrirse, aquí no). Con lo mismo que ve la tienda:
   - quién está ahora (`en_turno`) y quién ha estado hoy;
   - las tareas del día con su hora, estado, «hecha por» y hora de fin (las no hechas, como no hechas);
   - la bolsa del reparto (recibida, efectivo entregado o el motivo, reposición «todo bien» / «falta algo») o, en las que reciben por envío, sus envíos sin confirmar;
   - incidencias abiertas de la tienda (incluidos atascados), avisos sin leer, peticiones pendientes y pedidos de cliente abiertos;
   - el cierre de caja del día (o el último).
   Si el centro no abre ese día, dilo.
3. **El almacén** sigue con `estado_actual()` tal cual: el panel lo elige en el selector y no cambia.
4. **Contratos** con nota para Lovable (el selector y la vista de una tienda con las mismas secciones que el almacén donde se pueda). Las ventas, con el bloque 2.

**Entrega:** PR **«Tarea 32 — Panel por centro»**, con «Qué he leído y qué existía ya», pruebas en verde (que el resumen no cambia nada en la base de datos), una llamada real, registros sin errores y cómo deshacer. No se pasa a producción.

---

## 7.0 TAREA 29d (fusionada en el PR #35; solo en pruebas, producción espera): «Calcular» del reparto y del envío, solo con la hoja, en pruebas

**Qué pasó (04/11/2026):** al calcular el reparto a las 08:28, la hoja decía INDOOR PR RELAX 4g = 0 en el almacén, pero `en_almacen` salió 2: la cuenta propia de la app (R1c, `ajusteAlmacen` / `aplicarAjuste` en `_compartido/almacen.ts`) sumó lo producido el 03/11 desde el último recuento marcado (02/11 18:43) sin restar las bolsas del 03/11 (no se marcaron). Igual con KUSH WATERHASH 10g, SUGAR CBDX, T BALLS / GELATO DRY 4g e INDOOR PR AFRU 10g. Nueva regla del propietario: `ESTADO_DEL_SISTEMA.md` §5 R1c (v1.58).

1. **«Calcular» del reparto y del envío** (`guardar_reparto` y lo que use `catalogo` para ese cálculo): la cifra de almacén es **la de la hoja leída en ese momento, tal cual**. Sin sumar ni restar nada: ni lo producido o salido desde el recuento, ni lo apartado de otro reparto, envío o pedido (`apartadoReparto`, comprometido). Si ves otro ajuste en ese cálculo, quítalo también y dilo en el PR.
2. **Lo demás de R1c no cambia:** el «coge / haz» de los pedidos de cliente y las cajas en camino siguen con «almacén ahora». Dilo en el PR si algo más dependía del cálculo del reparto.
3. **Sin granel (R1e)** sigue igual, ahora con la cifra real de la hoja: si la hoja dice 0 y no hay granel, sale el aviso de siempre (quitar o coger de otra tienda).
4. **Pruebas** con el caso del 04/11 (hoja 0, producido el día anterior sin recuento marcado → hay que producir 2, o aviso sin granel), Deno y SQL. Despliega `guardar_reparto` y `catalogo` **solo en pruebas**.
5. **Solo en pruebas; producción espera.**

**Entrega:** PR **«Tarea 29d — Calcular solo con la hoja»**, con «Qué he leído y qué existía ya», pruebas en verde, una llamada real (un cálculo sin guardar), registros sin errores y cómo deshacer.

---

## 7.0 TAREA 31 (fusionada en el PR #34; solo en pruebas, producción espera): productos atascados, en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` E2-8, «Atascados» (v1.56) y la **regla general de las franquicias** (v1.57: como tiendas propias en todo, salvo la logística por envío y las tareas del día a día de su gente), y `AGENTE_COORDINADOR.md`, bloque 1, puntos 15 a 17. Reutiliza: la lista del día de la tienda y la alternancia de Bilbao (Tarea 27), `productos_tienda()` con formatos (Tarea 30c), las incidencias para Administración (`incidencias_tiendas`, `cerrar_incidencia_tienda`), los avisos a tiendas (Tarea 27/29), las incidencias del operario y el siguiente envío de una franquicia (Tareas 30b/30c). Solo en pruebas; producción espera. **El reparto de Eder no cambia.**

1. **Martes por la mañana** (Bilbao alterna; en todas las tiendas, franquicias incluidas): «Revisa los productos atascados»: eligen de la lista (− y +) cuántas cajas no se mueven, con nota opcional; o «Nada atascado esta semana».
2. **Atascado en una tienda propia:** se pregunta a **todas** las demás tiendas, franquicias incluidas, todo el martes: «[Tienda] tiene N cajas de Y que no se mueven: ¿las quieres?», con «Las quiero». **Se lo lleva la primera que lo pide** y deja de salir a las demás.
3. **Atascado en una franquicia:** no se ofrece a las demás; **va directo a Administración** (incidencia abierta) para decidir promoción o recogida. Si decide recogida, la cierra con su nota: la recogida la organiza Administración y, cuando llegue, manda a Eder una tarea o un aviso (lo que ya existe).
4. **Si nadie lo pide** (propias), al cerrar el martes llega a Administración (incidencia abierta) para decidir **el miércoles por la mañana**: **promoción** (aviso a la tienda; la promoción queda abierta para la tienda hasta que pulsa «Ya no queda») o **al almacén**.
5. **Si hay que moverlo** (otra tienda lo pide o va al almacén): incidencia abierta para Eder, sin hora y sin tocar el reparto: «Recoge N de Y en [tienda] y llévalo a [tienda o almacén]»; la cierra al entregarlo. La tienda que lo tiene recibe el aviso «Prepara N de Y para recogida». **Si lo pide una franquicia:** Eder lo recoge y lo lleva al almacén, y va **en el siguiente envío a esa franquicia** (como una petición o un pedido del envío), sea cuando sea.
6. **Contratos** con nota para Lovable (tableta: la tarea del martes, las ofertas con «Las quiero», la promoción con «Ya no queda»; panel: lo que decide Administración; operario: sus incidencias de recogida).

**Entrega:** PR **«Tarea 31 — Productos atascados»**, con «Qué he leído y qué existía ya», pruebas en verde (el almacén y el reparto igual), una llamada real, registros sin errores y cómo deshacer. No se pasa a producción.

---

## 7.0 TAREA 30c (fusionada en el PR #33; solo en pruebas, producción espera): pedidos de cliente para todas las tiendas (por envío y desde la tableta), en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` §5 R1b (v1.51, «Recoger en una tienda que recibe por envío»). Reutiliza `guardar_pedido_cliente`, la caja aparte «Pedido de cliente» de las bolsas, la preparación del envío y la pestaña «Envíos» de la Tarea 30b. **El reparto y los pedidos de siempre no cambian.** Solo en pruebas; producción espera.

1. **`guardar_pedido_cliente` con `entrega: "tienda"`** acepta también Donosti, Rentería y Durango (las tiendas que reciben por envío; por configuración, no por código).
2. **Va en el siguiente envío** a esa tienda (Gipuzkoa para Donosti y Rentería; Durango para Durango): caja aparte «Pedido de cliente · [cliente] · [tienda]» en la preparación del envío, que el operario marca como las demás. Mientras no haya envío, el pedido espera.
3. **Aviso en «Revisa si toca envío…»** (15:30): «Hay N pedidos de cliente esperando envío a [destino]».
4. **En la tienda:** el pedido sale en `envios` (Tarea 30b) con lo demás que llega. **Los de Donosti van en el envío a Gipuzkoa y salen en «Envíos» de Rentería**, que es quien lo recibe y confirma (decisión del propietario en el PR #31); el texto de la caja dice para qué tienda es.
5. **Las tiendas crean sus pedidos desde la tableta** (decisión del propietario, bloque 1 punto 20; confirmado el 04/11/2026): todas, franquicias incluidas. Apuntan el nombre del cliente y los productos con su formato (la misma lista, con − y +, que el reparto; sin que la tableta llame a Google: usa la última lectura de la hoja, como `productos_tienda`, pero con formatos). Queda con el nombre de quien está en el turno.
   - **Solo para recoger en su propia tienda** (`entrega: "tienda"`, `destino` = la tienda que lo pide); **nunca por Nacex** (eso sigue siendo de Administración y del operario).
   - Las propias lo reciben en el reparto y Donosti, Rentería y Durango en el envío (puntos 1 a 4), por el mismo camino que los pedidos de siempre (R1b).
   - Hoy la tienda no puede usar las funciones de pedidos (Tarea 27): se le abre solo esto, sin darle acceso al catálogo ni a lo del almacén.
   - Administración los ve en sus pedidos de siempre, con qué tienda lo ha pedido; la tienda ve los suyos y su estado.
6. **Contratos:** §3.16 y lo nuevo de la tableta, con nota para Lovable (la lista de tiendas de «Pedido de cliente» y el botón de la tableta).

**Entrega:** PR **«Tarea 30c — Pedidos de cliente por envío»**, con «Qué he leído y qué existía ya», pruebas en verde (el reparto y los pedidos de siempre igual), una llamada real, registros sin errores y cómo deshacer. No se pasa a producción.

---

## 7.0 TAREA 30 (fusionada en el PR #30; solo en pruebas, producción espera): incidencias de tienda, en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` E2-8 («Incidencias de tienda») y `AGENTE_COORDINADOR.md`, bloque 1, puntos 18 y 24. Es la primera de cuatro tareas pequeñas de la tercera parte de tiendas (30 incidencias · 31 atascados · 32 panel con selector · 33 resumen del día). **Solo en pruebas; producción espera.** Reutiliza lo que ya existe: la tabla `incidencias` con `quien: administracion` (como `falta_reposicion`, Tarea 28), `incidencias_tiendas()` y `cerrar_incidencia_tienda()`, `pedir_material()` y el teléfono de `mi_perfil`. Nada al lado.

1. **Cinco opciones**, sin foto ni urgencia, con «hecha por» de quien está en el turno:
   - **Material de tienda** → es lo mismo que `pedir_material` (Tarea 28): no se crea nada nuevo, la pantalla llama a esa función.
   - **Me quedo sin producto** → la pantalla enseña el botón de llamar a Administración (`telefono_administracion`) y **además queda apuntado** (decisión del propietario, 03/11/2026): la tienda elige el producto de `productos_tienda()` (nota opcional, por ejemplo el formato) y se crea una incidencia **abierta para Administración** «Sin producto: [producto]», que sale en `incidencias_tiendas()`. Así queda constancia de qué se acaba en tienda.
   - **Descuadre de stock o de caja**, **Comentario de cliente** y **Otros** → incidencia **abierta para Administración**, con texto obligatorio (una línea o dos) y aviso en la app: sale en `incidencias_tiendas()` y se cierra con `cerrar_incidencia_tienda()`. Opciones nuevas del check, solo añadiendo.
2. **Franquicias** (decisión del propietario, 03/11/2026): las incidencias se construyen igual para todas, pero en Donosti y Rentería **solo está la opción de texto libre** (lo que en las propias es «Otros»): llega a Administración como incidencia abierta. Las demás opciones, desactivadas para ellas por configuración por tienda (no código), como `pedir_material`.
3. **`tienda_hoy()`**: las incidencias de la tienda abiertas y las cerradas de hoy, con su estado («Abierta» / «Resuelta por Administración: [nota]»).
4. **Contratos:** la función nueva y lo de `tienda_hoy()`, con nota para Lovable. De paso, el pendiente de §9.11 (la pantalla de «Recibe la bolsa» no enseña la lista).

**Entrega:** PR **«Tarea 30 — Incidencias de tienda»**, con «Qué he leído y qué existía ya», pruebas en verde (el almacén igual), una llamada real, registros sin errores y cómo deshacer. **No se pasa a producción.**

---

## 7.0 TAREA 30b (fusionada en el PR #31; solo en pruebas, producción espera): franquicias — «Envíos» y cierre de caja, en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` E2-8, «Qué tienen las franquicias» (v1.50). Reutiliza la reposición de la Tarea 28 (lista de lo marcado, «Todo bien» / «Falta algo» → incidencia para Administración) y el cierre de caja (`cerrar_caja`, `cierres_caja`). Solo en pruebas; producción espera.

1. **«Envíos» para las tiendas que reciben por envío** (configuración por tienda; hoy Donosti y Rentería, y **Durango**, que es tienda propia pero recibe por envío en vez de bolsa): al día siguiente de guardar y sacar el envío que las lleva, `tienda_hoy()` trae `envios` con lo que les llega (lo **marcado** al meterlo en la caja, como `bolsa` en la Tarea 29). **No es una tarea con hora**: sigue ahí hasta que la confirman con «Todo bien» o «Falta algo» (eligiendo qué y cuánto; llega a Administración como incidencia abierta, como la reposición). Para ellas no hay «Recibe la bolsa» ni reposición. `tienda_hoy()` trae también cuántos envíos hay sin confirmar (para el número de la pestaña).
2. **Cierre de caja de las franquicias** (solo Donosti y Rentería; **Durango es tienda propia y mantiene su «Cierre del día» completo** con Z, nº de ventas, efectivo y Glovo): tarea «Cierre de caja» 10 minutos antes de cerrar (20:20 entre semana; 13:20 el sábado, que cierran por la tarde), con **solo la Z y el número de ventas** (sin efectivo ni Glovo). Se guarda en `cierres_caja` igual que las propias.
3. **Contratos:** `envios` en `tienda_hoy()`, la función de confirmar y el cierre corto, con nota para Lovable.

**Entrega:** PR **«Tarea 30b — Franquicias: envíos y cierre de caja»**, con «Qué he leído y qué existía ya», pruebas en verde (el almacén y las tiendas propias igual), una llamada real, registros sin errores y cómo deshacer. No se pasa a producción.

---

## 7.0 TAREA 29 (fusionada en el PR #28; solo en pruebas, producción espera): conflictos al crear una tarea de Administración y avisos del almacén a las tiendas, en pruebas

**Qué pasó (03/11/2026):** a las 10:28 Administración creó «Hay que recoger las cajas de la imprenta» (no urgente, sin hora límite). `crear_tarea_admin` devolvió `CONFLICTO` con las bolsas y la producción del reparto en riesgo, y en la ventana se eligió `{ cede: bolsas, accion: "manana" }` queriendo pasar a mañana **la tarea nueva**. Las bolsas dejaron de salir (`disponible_desde` = mañana 00:00), y al terminar la producción a las 10:48 a Eder le salió directamente la salida. Regla nueva en `ESTADO_DEL_SISTEMA.md` §6.4 (v1.46).

1. **Sin falsa alarma:** una tarea **no urgente y sin hora límite** no puede poner en riesgo lo primero de la mañana (§6.4: espera a que termine). En ese caso no hay conflicto: se crea y el `encaje` dice cuándo saldrá. El conflicto sigue para las urgentes y las que tienen hora límite.
2. **El reparto y el envío de hoy no se mueven:** la producción del reparto, las bolsas, la salida y la preparación del envío de hoy **no pueden ser `cede`** con `manana` ni `cancelar` (ni `despues`, si les quita la hora límite). Si llega, `DATOS_NO_VALIDOS` con un mensaje claro. En `obligatorias_en_riesgo`, cada una trae `se_puede_mover: true|false` para que la pantalla solo ofrezca las que sí.
3. **Opciones para la tarea nueva** en `decision_conflicto`, solo añadiendo: `{ "accion": "nueva_manana" }` (se crea para el siguiente día de trabajo de esa persona; si no lo hay, `SIN_JORNADA`) y `{ "accion": "nueva_despues" }` (se crea sin hora límite y sin urgencia, para después de lo que está en riesgo). `no_crear` sigue igual.
4. **Prueba** con el caso del 03/11 (no urgente a las 10:28 con producción y bolsas pendientes → se crea sin conflicto; una urgente → conflicto, las bolsas con `se_puede_mover: false`, `nueva_manana` la crea mañana y las bolsas siguen hoy). El almacén, igual en todo lo demás.
5. **Contratos:** §4.1 con las opciones nuevas y `se_puede_mover`, con nota para Lovable.
6. **Producción:** esta migración va detrás de la de tiendas (47), así que **espera** con ellas (excepción de tiendas, sección 4); producción no se usa aún. Dilo en el PR.
7. **Avisos del almacén a las tiendas** (decisión del propietario, 03/11/2026): el operario también puede **mandar avisos** a una tienda o a todas, igual que Administración (para que metan algo en una bolsa, preparen algo…). Reutiliza `crear_aviso_tienda` y los avisos de la Tarea 27: no se hace nada al lado. Solo **mandar**: no gestiona personas, días cerrados ni nada más del panel. En la tienda, el aviso dice de quién viene («Almacén» o «Administración»); Administración los ve en `avisos_tiendas()` con quién lo mandó y los puede cancelar. Contratos con nota para Lovable.
8. **Numeración:** la tercera parte de tiendas (incidencias, atascados, panel y resumen del día), que las Tareas 27 y 28 llaman «Tarea 29», pasa a ser la **Tarea 30**.

**Entrega:** Pull Request **«Tarea 29 — Conflictos al crear tareas de Administración y avisos del almacén»**, con «Qué he leído y qué existía ya», pruebas en verde, una llamada real, registros sin errores nuevos y cómo deshacer.

---

## 7.0 TAREA 28 (fusionada en el PR #27; solo en pruebas, producción espera): tiendas, segunda parte — la bolsa, por dónde va el reparto, el cierre de caja, las muestras y el material, en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` **E2-8** y `AGENTE_COORDINADOR.md`, bloque 1 (puntos 7 a 10, 12 a 14, 18, 24, 29 y 30). Sigue la Tarea 27 (PR #26): mismas reglas. **Solo en pruebas; producción espera** (excepción de tiendas, sección 4). **El almacén no puede cambiar**: lo que hoy hace Eder (preparar, bolsas, salida, ruta) sigue igual y sin pasos nuevos para él. Reutiliza lo que existe: el reparto y el envío del día, sus bolsas y paradas, las **peticiones especiales** (R1d, Tarea 13), los puntos y la lista del día de la tienda (Tarea 27) y la activación por tienda.

1. **«Recibe la bolsa»** (tiendas con parada en el reparto de hoy): sale **cuando sale el reparto**, con la hora de salida. Enseña lo que trae la bolsa de esa tienda (productos, peticiones y pedidos de cliente), para poder ver si falta algo. Puntos:
   - «Bolsa recibida»;
   - «Bolsa de ayer entregada con X € en efectivo», con **X = el efectivo del último cierre de caja de esa tienda** (punto 4); si entregan otra cantidad, dicen cuál y por qué (por ejemplo, monedas para cambio). Si no hay cierre anterior, piden la cantidad.
   Al hacerla, la bolsa consta como recibida a esa hora.
2. **«Coloca y apunta la reposición»**: sale después de «Recibe la bolsa», con la lista de lo que tenía que llegar. Dos salidas: **«Reposición metida, todo bien»** o **«Falta algo»** (elegir qué de la lista y cuánto). Lo que falta llega a **Administración, como incidencia abierta con aviso en la app** (decisión del propietario, 02/11/2026), que la cierra al resolverla; a Eder no le sale nada.
3. **Por dónde va el reparto:** sin que quien reparte haga nada. Al salir, todas las tiendas con parada ven «Ha salido a las HH:MM»; cada vez que una tienda marca «Bolsa recibida», las demás ven «Ha pasado por [tienda] a las HH:MM» y en qué lugar de la ruta van (el orden de las paradas del reparto). Va en `tienda_hoy()`.
4. **Cierre de caja** en el «Cierre del día» (un punto más, el primero de los de dinero): **Z, número de ventas, efectivo y Glovo**. Se guarda por tienda y día; el efectivo es la X del día siguiente (punto 1). Administración lo verá en su panel (Tarea 29); deja la función de lectura preparada.
5. **«Revisa las muestras»** (jueves por la mañana; en Bilbao alterna por semanas como las demás semanales): comprobar que están en buen estado y **elegir qué hay que traer nuevo** (de la lista de productos, con cantidad, como en el reparto). Activada también en **Donosti y Rentería**.
6. **Pedir material de tienda** (bolsas, rollos de TPV…): texto libre, en cualquier momento (la tienda lo pide desde su pantalla; en la Tarea 29 también desde las incidencias).
7. **Muestras y material van al siguiente reparto o envío de esa tienda como peticiones especiales** (R1d): quedan pendientes y, al preparar el siguiente reparto (o envío) que lleve esa tienda, salen **ya puestas** en su casilla de peticiones, para que Administración las vea y las pueda cambiar. Al guardarlo, quedan atendidas y la tienda lo ve («Va en el reparto de mañana»). **No cambia nada en las bolsas ni en la salida** de Eder: las peticiones ya existen.
8. **Franquicias:** en esta tarea solo las muestras (punto 5) y sus peticiones (punto 7); no tienen «Recibe la bolsa», reposición ni cierre de caja.
9. **Contratos:** funciones nuevas o campos nuevos de `tienda_hoy()`, solo añadiendo. Corrige de paso la nota de §9 y la leyenda 🧪 de `CONTRATOS.md`: lo de tiendas **no** pasa a producción al fusionar, sino cuando el propietario lo apruebe.

**Entrega:** Pull Request **«Tarea 28 — Tiendas: bolsa, cierre de caja, muestras y material»**, con «Qué he leído y qué existía ya», pruebas en verde (incluida una prueba de que el almacén sigue igual: preparar, bolsas, salida y peticiones de siempre), una llamada real, registros sin errores nuevos y cómo deshacer. **No se pasa a producción.**

---

## 7.0 TAREA 27 (fusionada en el PR #26; solo en pruebas, producción espera): tiendas, primera parte — acceso, personas, horario y tareas del día, en pruebas

**Contexto:** `ESTADO_DEL_SISTEMA.md` **E2-8** (bloque 1 de tiendas), con el detalle punto a punto en `AGENTE_COORDINADOR.md` (puntos 1 a 28). Es la primera de tres tareas; aquí **no** entran la bolsa, el seguimiento del reparto, el cierre de caja, las muestras, el material, las incidencias de tienda, los atascados, el panel ni el resumen del día (Tareas 28 y 29). **Reutiliza** el motor que ya existe (centros, plantillas por centro, jornadas, tareas con elementos, «hecha por», avisos de Administración, acceso con Google y cuentas autorizadas): nada al lado. Si para las tiendas hay que cambiar cómo funciona algo del almacén, te detienes y lo preguntas: **el almacén no puede cambiar**.

1. **Acceso de tienda:** cada tienda entra con **su cuenta de Gmail** (cuentas autorizadas, con su centro). Rol nuevo de tienda: solo ve lo suyo y no ve nada de Administración. **Todas las tiendas son iguales de base**, franquicias incluidas (Donosti y Rentería apuntan en STOCK OSASUN y forman parte del stock y la operativa de producto); Durango, inactiva hasta que abra.
   - **Cada tarea se activa por tienda** (configuración, no código), para que Administración pueda activar o quitar cosas más adelante. En esta tarea: tiendas propias, todo lo de esta tarea; **franquicias, solo los avisos de Administración y el vídeo de la semana** (los atascados y las muestras, que también tendrán, van en las Tareas 28 y 29).
2. **Personas de cada tienda:** una lista de nombres por tienda, con cuándo trabajan (entre semana, sábados; en Bilbao, mañana o tarde). **Al empezar el turno**, la tienda elige el nombre de quien está; ese nombre es el «hecha por» de lo que se haga en el turno. Administración añade y quita nombres (funciones para su panel).
3. **Horario por tienda:** L–V 11:00–13:30 y 17:00–20:30; Bilbao, tarde 16:30–20:30. Sábados igual, pero cierran a las 19:30, salvo Bilbao (20:30). Donosti y Rentería, igual, pero el sábado por la tarde cierran. Domingos, nada. Configurable por tienda, no fijo en el código.
4. **Festivos:** Administración marca un día «cerrado» para una tienda o para todas (y lo quita); ese día no se genera nada. Si no marca nada, día normal.
5. **El día de la tienda:** la tienda ve **todas** sus tareas del día en una lista, cada una con su hora orientativa (no una sola tarea como el almacén). **No se pueden marcar antes de su hora.** **Sin avisos ni estados de retraso.** Lo que no se ha hecho al cerrar queda como **no hecho** (no pasa al día siguiente). **Avisos de Administración** para una tienda o para todas: salen al entrar y se marcan como leídos (reutiliza los avisos de la Tarea 22).
6. **Tareas diarias** (una tarea con sus puntos, que se tocan uno a uno; se da por hecha al tocar el último):
   - **Apertura de la mañana**, desde las 10:50: fichar en Woffu · abrir · cartelería · Glovo · barrido y puesta a punto.
   - **Apertura de la tarde**, desde 10 minutos antes de abrir (16:50; Bilbao 16:20): fichar · abrir · cartelería · Glovo.
   - **Cierre de la mañana**, desde las 13:20: ventas y stock de la plantilla al día (todo en verde) · incidencias del turno registradas.
   - **Cierre del día**, desde 10 minutos antes de cerrar (20:20; sábados 19:20; Bilbao siempre 20:20): ventas del día en la plantilla (todo en verde) · suelo fregado · efectivo contado y en la bolsa para mañana · incidencias de la tarde registradas. (El cierre de caja en la app se añade en la Tarea 28.)
7. **Semanales de esta tarea:** **limpieza de cristales** el jueves por la tarde y **vídeo de la semana** el viernes por la mañana. En **Bilbao**, todas las semanales alternan por semanas entre el turno de mañana y el de tarde (di en el PR qué regla usas, por ejemplo semana par/impar).
8. **Vídeo de la semana**, con este texto aprobado por el propietario: «Busca y mira un vídeo sobre nuestro sector: cannabis y CBD, cultivos y variedades, extracciones o la cultura cannábica. También sobre los ingredientes de nuestra crema, lo que se te ocurra pero tiene que estar relacionado con lo que vendemos. Pega el enlace de YouTube y escribe en una línea qué has aprendido. Quedará en la lista de vídeos que ven todas las tiendas, para recomendarlo a compañeros y clientes.»
   - Se termina con un **enlace de YouTube** (se comprueba que lo es) y **una línea** de lo aprendido, o con **«Hoy no he podido»**, que la cierra sin enlace y no pasa al día siguiente.
   - **Sábado:** sale a quien trabaje ese día si **esa persona** no ha compartido vídeo esa semana. Cada persona, como mucho uno por semana. Si la persona del viernes no pudo, el sábado no le vuelve a salir a ella.
   - **Lista de vídeos:** la ven todas las tiendas (y Administración): enlace, lo aprendido, tienda, persona y fecha, los más nuevos primero.
9. **Contratos:** las funciones nuevas para las pantallas de la tablet y para Administración van en `CONTRATOS.md` (versión nueva con nota para Lovable). Solo se añade: lo del almacén no cambia de forma.
10. **Datos de pruebas:** los nombres de las personas y las cuentas de Gmail de las tiendas son datos personales: te los da el propietario en el mensaje de encargo y los cargas en pruebas **de base a base**, nunca en el repositorio, en las migraciones ni en el PR. Para las pruebas automáticas, nombres inventados.

**Entrega:** Pull Request **«Tarea 27 — Tiendas: acceso, personas y tareas del día»**, con «Qué he leído y qué existía ya», pruebas en verde (incluida una prueba de que el almacén sigue igual), una llamada real que responde bien, registros sin errores nuevos y cómo deshacer. Al fusionarlo, a producción según `AUDITORIA.md` §5.

---

## 7. TAREA 26 (fusionada en el PR #25; falta el punto 3, producción): la huella sin las claves de cada entorno y `catalogo` igual en los dos

**Contexto:** respuestas del propietario a las dudas del PR #24 (02/11/2026).

1. **Huella:** una migración pequeña que añade `url_proyecto` y `cierres_sin_correo` a las claves que `motor.huella_estructura()` deja fuera en «carga inicial», igual que `entorno` o `cuentas_autorizadas`. Así los 11 apartados se comparan directamente entre pruebas, producción y una base creada solo con las migraciones. Ajusta la prueba 00 y `AUDITORIA.md` (la fila de `huella` y el punto 5.4) para que no haga falta la consulta aparte. Lleva su «Deshacer».
2. **`catalogo` en pruebas:** vuelve a desplegarla desde `main`, para que los dos entornos tengan los mismos archivos. Compruébalo con `get_edge_function`, archivo a archivo.
3. **Producción:** la migración entra en producción **solo después de que el propietario fusione el PR**, siguiendo `AUDITORIA.md` §5 (misma versión, md5, comprobaciones de solo lectura). Lo cuentas en un comentario del PR: migraciones pasadas, auditoría «Sin avisos» y huella igual en los 11 apartados en los dos entornos.
4. **Se queda como está** (decisión del propietario): los correos que salgan desde pruebas después del día del cambio (solo saldrían si alguien prueba algo a mano) y los 5 índices de `pedidos_cliente` (más adelante).

**Entrega:** Pull Request **«Tarea 26 — Huella sin claves del entorno»**, con «Qué he leído y qué existía ya», pruebas en verde, auditoría de pruebas y registros sin errores nuevos.

---

## 7.0 TAREA 25 (fusionada en el PR #24): montar producción

**Contexto (decisión del propietario, 02/11/2026):** se separan los entornos. **Producción** = proyecto `osasun-produccion` (`iqjkysfbtpkukkvfyumf`, eu-west-1, plan Pro), el que usarán el almacén y las tiendas. **Pruebas** = `osasun-pruebas` (`rvypswuoafnjwqdwxjvo`), donde pruebas tus cambios. El propietario ya ha puesto en producción los secretos `GOOGLE_CUENTA_TECNICA` y `RESEND_API_KEY`. **En producción solo entra lo aprobado y fusionado en `main`.**

1. **Estructura:** aplica en producción **todas** las migraciones de `supabase/migrations/`, en orden y con las mismas versiones. Nada que no esté en `main`.
2. **Funciones del servidor:** despliega en producción las mismas que en pruebas, con la misma configuración (`verify_jwt` incluido).
3. **Datos de partida** (opción A del propietario: solo lo necesario; el histórico de pruebas **no** se pasa):
   - la configuración propia del entorno (la que la huella deja fuera: operario y Administración por defecto, teléfono, correos de destino, etc.), copiada de pruebas **sin** fichas ni datos de prueba;
   - `cuentas_autorizadas` de las personas reales (Asier y Eder), copiadas de pruebas (son datos personales: de base a base, **nunca** al repositorio ni al PR);
   - la lista de compras tal como está hoy en pruebas (con los cambios del propietario).
   - Las fichas de persona se crean solas al entrar por primera vez con Google (hook); las claves que apuntan a una ficha (`operario_por_defecto`, `administracion_por_defecto`) se rellenan después del primer acceso: déjalo preparado y explícalo en el PR.
4. **Comprobaciones, solo de lectura en producción:** `motor.auditoria()` («Sin avisos», mismas migraciones que el repositorio) y la huella de la prueba 00 igual a la de una base creada solo con las migraciones. **No ejecutes en producción ninguna prueba que escriba** (ni la 22 ni las demás).
5. **Prepara, sin hacerlo todavía, el día del cambio:** qué hay que apagar en pruebas para que no mande correos al propietario ni genere cierres duplicados (las tareas programadas). Escríbelo en el PR; se hará cuando el propietario diga el día.
6. **Fuera de tu alcance** (lo hace el propietario con la guía del coordinador): el proveedor de Google en Auth de producción, activar el hook «Before User Created», la Site URL y las direcciones de vuelta. Dilo en el PR si encuentras algo más que haga falta en el panel.
7. `docs/AUDITORIA.md` y `CONTRATOS.md` §7.1: añade los dos entornos (URL y clave pública de producción) y cómo se pasa un cambio aprobado de pruebas a producción.

**Entrega:** Pull Request **«Tarea 25 — Producción montada»**, con «Qué he leído y qué existía ya», la auditoría de producción, lo que falta en el panel y el plan del día del cambio.

---

## 7.0 TAREA 24 (fusionada en el PR #23): quién hizo cada tarea y nada fuera del turno, en pruebas

Dos puntos aprobados por el propietario el 02/11. El 1 es el punto 5 de la Tarea 23, que no entró en el PR #22.

1. En `estado_actual().hoy`, por tarea hecha, **`hecha_por`** (nombre de la persona). El caso que lo pide: «Prepara el reparto» se cierra sola cuando alguien guarda el reparto; el 02/11 la cerró Asier desde su cuenta a las 08:27 y en el panel no se veía. **Reutiliza** lo que ya se guarda (`repartos.pegado_por`, `registro_eventos.persona_id` de `tarea_terminada`); no añadas un registro nuevo. Solo se añade el campo (`null` en las no hechas).
2. **Fuera de su turno, ninguna tarea** (aprobado por el propietario el 02/11). El 02/11 el operario terminó el recuento de la mañana a las 13:04 (su turno acaba a las 13:00) y le salió «Producción para el stock (+35 %)». Hoy `motor.elegir_tarea` solo mira el horario en la parte de «nunca sin tarea». **Reutiliza esa misma comprobación del horario** (`horarios`, turno en curso) para toda la elección: fuera de su turno, `tarea_activa().tarea` es `null` («Ahora no hay nada pendiente»), salvo la tarea que tenga **en curso**, que la puede terminar. Lo pendiente vuelve a salir al empezar el siguiente turno. Es lo que ya dice `CONTRATOS.md` §3.2 («`tarea` es `null` solo fuera del turno»).
3. Pruebas: la del 02/11 («Prepara el reparto» hecha por Asier; una tarea normal, por Eder); recuento terminado a las 13:04 → sin tarea hasta las 15:30; una tarea en curso a las 13:00 se puede terminar; las pruebas del orden del día (01, 05, 13, 26) siguen en verde. `CONTRATOS.md` a la 1.10, con su nota para Lovable. Lista de `docs/AUDITORIA.md` pasada en pruebas.

**Entrega:** Pull Request **«Tarea 24 — Quién hizo cada tarea y nada fuera del turno»**, con «Qué he leído y qué existía ya», la lista de `AUDITORIA.md` y las dudas.

---

## 7.0 TAREA 23 (fusionada en el PR #22; el punto 5 pasa a la Tarea 24): cinco arreglos tras la prueba del 02/11, en pruebas

Aprobados por el propietario el 02/11/2026. **Reutiliza** lo que ya existe en cada punto; nada nuevo al lado.

1. **Tareas de Administración no urgentes, después de lo del reparto.** El 02/11, «Pasar las cajas de Slush Mints 4g a la bolsa de granel» (Administración, para hoy, sin hora, no urgente, `orden` 50) le salió a las 08:29, antes de la revisión inicial (08:30), la producción y las bolsas. Regla: una tarea de Administración **no urgente y sin hora límite** no sale mientras falten, ese día, la revisión inicial, «Prepara el reparto», la producción del reparto, las bolsas y la preparación del envío del viernes (las que haya). **Usa el requisito de la Tarea 20** (`requiere_clave` + `motor.requisitos_hechos`) al crearla en `crear_tarea_admin`. Las urgentes y las que tienen hora límite no cambian.
2. **«Hoy» en el orden en que se han hecho.** En `estado_actual().hoy`: primero las tareas hechas y la que está en curso, por `iniciada_en`; después las pendientes, en el orden de ahora. Solo cambia el orden; los campos son los mismos.
3. **Administración por defecto.** `mi_perfil().quien_sale_opciones` (y donde se elija «la ficha de Administración», como `telefono_administracion`) coge hoy la primera ficha de Administración por orden alfabético, y sale «Administración de pruebas» en vez de «Asier». Haz como con el operario: una clave de configuración `administracion_por_defecto` (igual que `operario_por_defecto`), con la ficha de Asier en pruebas, y úsala; si falta, como ahora. La ficha de pruebas se queda para las pruebas.
4. **«Calcular» siempre recalcula con la hoja de ese momento.** El 02/11 a las 10:31 la hoja tenía SLUSH MINTS 10g en 0 (mal colocado) y la producción pasó a «faltan 14, sin granel». A las 10:44 el propietario lo corrigió (19 cajas, 370 g) y pulsó «Calcular» con el mismo reparto: `guardar_reparto` leyó la hoja nueva (lectura `689498c6…`), pero por la **huella** (mismo texto) respondió `REPARTO_SIN_CAMBIOS` y no rehízo la producción. Cambio: la protección contra duplicados queda **solo por `id_cliente`** (el mismo toque repetido); un «Calcular» nuevo con el mismo reparto **recalcula** la producción y las bolsas con la lectura nueva, conservando lo hecho y las decisiones de R1e, como cualquier modificación. Explica en el PR qué pruebas cambian a propósito (las de `REPARTO_SIN_CAMBIOS` / `ya_pegado`).
5. **Quién hizo la tarea** (añadido por el propietario el 02/11). En `estado_actual().hoy`, por tarea hecha, **`hecha_por`** (nombre). El caso que lo pide: «Prepara el reparto» se cierra sola cuando alguien guarda el reparto; el 02/11 la cerró Asier desde su cuenta a las 08:27 y no se veía. Reutiliza lo que ya se guarda (`repartos.pegado_por`, `registro_eventos.persona_id` de `tarea_terminada`); no añadas un registro nuevo. Solo se añade el campo.
6. Pruebas de los cinco puntos; `CONTRATOS.md` a la 1.9 con su nota (cambia el comportamiento del punto 4, el orden del punto 2 y se añade `hecha_por`). Lista de `docs/AUDITORIA.md` pasada en pruebas.

**Entrega:** Pull Request **«Tarea 23 — Arreglos tras la prueba del 02/11»**, con «Qué he leído y qué existía ya», la lista de `AUDITORIA.md` y las dudas.

---

## 7.0 TAREA 22 (fusionada en el PR #21): incidencias nuevas, lista de compras y avisos de Administración, en pruebas

**Qué existe ya y hay que reutilizar** (constitución, regla 5): `crear_incidencia` y su tabla (opciones, quién, importancia, estados, «Pedido, esperando a que llegue», «Esperando a Administración»), la creación de tareas desde una incidencia, el correo en el momento a Administración (`motor.correos`), `cerrar_incidencia`, `incidencias_abiertas` y su número en `tarea_activa`, el cierre del turno. **Se amplía lo que hay; no se hace un segundo sistema de incidencias ni de avisos.**

1. **Lista de compras** (tabla nueva, p. ej. `public.compras`): nombre, forma (`internet` | `tienda` | `administracion`), enlace (internet), sitio y dirección (tienda), nota, activo y orden. Carga inicial con la tabla de `ESTADO` §7 (sin «Paquetes y recogidas», que ya no es una compra, **ni la gasolina**, que se quita): Amazon → `internet`; imprenta y materia prima → `administracion`; `tienda`, con estos sitios (aprobados por el propietario, 30/10/2026):
     - Alcohol, papel de cocina, papel de horno y limpieza → «Cualquier supermercado» (sin dirección);
     - Guantes de nitrilo → «Arte Sano Tattoo Supplies», C/ San Nicolás de Olabeaga 12 (lonja), 48013 Bilbao;
     - Material de oficina, plástico de burbujas y cinta aislante → «Cualquier bazar chino» (sin dirección);
     - Rollos de TPV → «Kutxabank», Avda. Lehendakari Aguirre 151, San Inazio, 48015 Bilbao (corregido por el propietario);
     - Bolsas para tienda y plástico negro de embalar → «Retif Bilbao», C/ Máximo Aguirre 10, 48009 Bilbao.
     Si una fila no encaja, pregúntalo en el PR.
   - `compras_lista()` (operario y Administración): las activas, en su orden.
   - `guardar_compra(...)` (solo Administración): añadir, cambiar y quitar (quitar = desactivar, para no romper el histórico).
2. **`crear_incidencia`, opción `comprar`** con `compra_id` (o «otra cosa» con texto):
   - `internet`: tarea «Compra: [nombre]» con su **enlace** (añade `enlace` al objeto tarea de `tarea_activa`, §3.2); al hacerla, «Pedido, esperando a que llegue» (como `pedir_comprar`).
   - `tienda`: tarea «Ve a comprar [nombre] a [sitio]» con la dirección; al hacerla, la incidencia se cierra.
   - `administracion` u «otra cosa»: sin tarea, correo en el momento y «Esperando a Administración».
   - La importancia por defecto, «hoy»; el operario la puede cambiar como ahora.
3. **Opción `varios`:** descripción + quién (`operario` | `administracion`) + importancia → tarea «[descripción]» o correo, como el camino genérico que ya existe. Las opciones `llega_mercancia`, `recogida_nacex`, `corregir`, `pedir_comprar` y `pedido_cliente` dejan de ofrecerse en la pantalla, pero **siguen aceptándose** (histórico y compatibilidad); `bloqueado` no cambia.
4. **Avisos de Administración para un día:** `crear_aviso_almacen(id_cliente, fecha, texto, contacto?)` (solo Administración; fecha hoy o futura). Es una incidencia del operario por defecto, con origen Administración, que **no crea tarea**:
   - desde su fecha cuenta en `incidencias_abiertas` y sale en `tarea_activa` como `avisos: [{ id, texto, contacto, fecha }]` (los abiertos con fecha ≤ hoy);
   - el operario la cierra con `cerrar_incidencia` como las demás;
   - Administración ve sus avisos pendientes (en `estado_actual`) y puede cancelarlos;
   - consta en el cierre del turno.
   - El contacto es dato personal: solo en la base de datos (constitución, regla 12).
5. Solo se añaden campos y funciones (regla 6). `CONTRATOS.md` a la 1.8, con su nota para Lovable.
6. Pruebas: cada forma de compra, «otra cosa», varios con él y con Administración, aviso de hoy y aviso futuro (no cuenta hasta su día), cierre del aviso, permisos (el operario no puede crear avisos ni cambiar la lista). Lista de `docs/AUDITORIA.md` pasada en pruebas y llamadas reales en el PR.

**Entrega:** Pull Request **«Tarea 22 — Incidencias nuevas, lista de compras y avisos»**, con «Qué he leído y qué existía ya», la lista de `AUDITORIA.md` y las dudas.

---

## 7.0 TAREA 21 (fusionada en el PR #20): interrupciones, cajas y minutos trabajados en «Hoy», en pruebas

**Por qué:** el 30/10 la lista del +35 % empezó a las 09:54, a las 10:45 entró «Salida del reparto» y volvió a `pendiente` con 3 de 6 productos. En el panel no se ve que se interrumpió, ni cuántas cajas lleva, y los minutos (de inicio a fin) contarán las 2 h de ruta.

**Qué existe ya y hay que reutilizar** (no hagas otro registro al lado): `motor.tras_elemento` ya registra **`tarea_pausada`** en `registro_eventos` con `a_las` y `entra` (la tarea que entra). Los elementos ya guardan `iniciado_en`, `terminado_en` y `cantidad_hecha`; la tarea, `resultado` («N cajas») al cerrarse. Mira también cómo se retoma una tarea pendiente que ya tenía `iniciada_en` (`iniciar_tarea` / `iniciar_elemento`) y si eso ya deja rastro; si no, registra **la reanudación** en `registro_eventos` con el mismo estilo.

1. En `estado_actual().hoy`, por tarea, añade:
   - **`interrupciones: [{ a_las, por, siguio_a_las }]`** — `por` es el título de la tarea que entró; `siguio_a_las` es `null` si aún no se ha retomado. Lista vacía si no hubo.
   - En las tareas de producción (las que tienen elementos `referencia_produccion`: producción del reparto, +35 % y pedidos de cliente): **`cajas: { hechas, total }`** y **`minutos_trabajados`** = suma, por elemento, de `terminado_en − iniciado_en` (el que esté en curso, hasta ahora), sin contar el tiempo interrumpido. En las demás, `null`.
   - Los campos de antes (`iniciada_en`, `terminada_en`, `minutos`) no cambian.
2. Solo se añaden campos (constitución, regla 6). `CONTRATOS.md` a la 1.7, con su nota para Lovable.
3. Pruebas: la del 30/10 (+35 %, 3 de 6, interrumpida por la salida, retomada después) da sus interrupciones, «21 de 43» y los minutos sin la ruta; una tarea sin interrupciones da lista vacía; una tarea que no es de producción da `cajas` y `minutos_trabajados` a `null`.
4. Lista de `docs/AUDITORIA.md` pasada en pruebas (auditoría «Sin avisos», registros sin errores nuevos) y una llamada real a `estado_actual` en pruebas con el resultado del 30/10 en el PR.

**Entrega:** Pull Request **«Tarea 21 — Interrupciones, cajas y minutos trabajados»**, con «Qué he leído y qué existía ya», la lista de `AUDITORIA.md` y las dudas.

---

## 7.0 TAREA 20 (fusionada en el PR #19): la limpieza de resinas, después de lo del reparto y del +35 %; retoques de la auditoría

**Qué pasó el 30/10/2026:** «Limpieza intensiva de la estación de resinas» (`limpieza_resinas`, obligatoria, `hora_limite` 10:45, `orden` 25) le salió al operario a las 08:35, **antes** de «Producción del reparto» (`orden` 30). Decisión del propietario: lo del reparto y el envío va siempre antes que la limpieza y el orden.

1. **Regla nueva:** `limpieza_resinas` no está disponible mientras, ese día, falte alguna de estas tareas: producción del reparto, bolsas, preparación del envío (si lo hay) y **producción para el stock (+35 %, `cola_stock`)**. En cuanto estén hechas (o no las haya ese día), sale **en el siguiente punto de encaje**, sin esperar a ninguna hora.
2. **Hora límite:** antes del recuento de las 12:45 (no las 10:45). Si a esa hora no se ha podido hacer, se comporta como las demás fijas obligatorias (pasa como arrastrada, con su motivo en el cierre).
3. **Dónde:** **busca primero** cómo decide hoy el motor el orden y la disponibilidad (`motor` de la elección de tarea, «Nunca sin tarea», `retirada_por_condicion`, condiciones de plantilla) y **reutiliza** ese mecanismo; no hagas una segunda forma de bloquear tareas. Cambia la plantilla (`carga_inicial`: `limpieza_resinas`) con una migración nueva.
4. «Orden y limpieza» (`cola_orden`) ya va la última: comprueba que sigue así.
5. **Retoques de la auditoría (dudas del PR #18, aprobadas por el propietario):**
   - aviso nuevo en `motor.auditoria()`: reparto o envío aceptado hoy sin su tarea de producción o de bolsas;
   - en `docs/AUDITORIA.md`, que la usa `postgres` (el conector del coordinador); `motor` no se abre a `service_role`;
   - en `docs/AUDITORIA.md` y en el LEEME de las pruebas: **la prueba 22 nunca se ejecuta en producción** (la auditoría sí).
6. Pruebas: el viernes con reparto, envío y +35 %, la limpieza sale después de todo y antes de las 12:45; un viernes sin reparto, sale en cuanto quepa; lo demás del orden del día no cambia (pruebas 01 y 05 en verde). `CONTRATOS.md` solo historial (no cambia nada de lo que usan las pantallas).

**Entrega:** Pull Request **«Tarea 20 — Limpieza de resinas al final y retoques de la auditoría»**, con «Qué he leído y qué existía ya», la lista de comprobación de `AUDITORIA.md` pasada en pruebas (auditoría + registros) y las dudas.

---

## 7.0 TAREA 19 (fusionada en el PR #18): auditoría de solo lectura para el coordinador, en pruebas

El coordinador repite en cada PR las mismas comprobaciones con consultas sueltas. Esta tarea las convierte en **una sola llamada que siempre devuelve lo mismo**, para que no dependa de acordarse (constitución, regla 13). **Solo lee: no cambia nada.**

**Qué existe ya y hay que reutilizar** (no hagas otro al lado): `supabase/tests/00_huella_estructura.sql` ya calcula una huella por apartado (tablas, restricciones, índices, RLS, permisos, funciones, carga inicial y tarea programada). La auditoría la usa (mueve la lógica a la función y que la prueba 00 llame a la función, para que haya una sola versión).

1. **`motor.auditoria()`** → `jsonb`, `stable`, sin escrituras. Solo la pueden ejecutar `postgres` y `service_role` (nada de `anon` ni `authenticated`). Devuelve:
   - `generado_en`;
   - `migraciones`: cuántas hay y la última (de `supabase_migrations.schema_migrations`);
   - `huella`: las mismas cifras por apartado que la prueba 00 (para compararlas con una base creada solo con las migraciones);
   - `tablas`: por tabla de `public` y `motor`, si tiene RLS y cuántas políticas;
   - `funciones`: cuántas por esquema; y, de `public`, cuáles puede ejecutar `anon`, cuáles `authenticated` y cuáles son `security definer`;
   - `triggers` y tareas programadas (`cron`);
   - `configuracion`: las claves de `public.configuracion` que usan los cálculos, con su valor (ninguna es secreta), y las que falten;
   - `datos`: última lectura correcta de la hoja y último error, correos fallidos de los últimos 7 días, si existe la jornada de hoy;
   - **`avisos`**: lista de frases con lo que esté raro. Al menos: tabla sin RLS en `public`; función `servidor_*` que pueda ejecutar alguien que no sea `service_role`; función de `public` ejecutable por `anon` (salvo las que lo necesiten, que se listan como permitidas en la propia función); clave de configuración que falte; más de una tarea en curso para la misma persona; más de un reparto (o envío) aceptado en la misma jornada; elementos sin su tarea; lectura de la hoja con error más reciente que la última correcta.
   - `resumen`: «Sin avisos» o «N avisos».
2. **`docs/AUDITORIA.md`** (corto): cómo se usa y qué es lo normal. Incluye además, para lo que no se ve desde SQL:
   - la consulta fija de **registros del servidor** para `query_logs` (respuestas 500 y excepciones de las funciones en las últimas 24 h, agrupadas por función);
   - la lista de **funciones del servidor** que deben estar desplegadas (para compararla con `list_edge_functions`);
   - un **script de comparación de funciones rehechas** en el repositorio (por ejemplo `scripts/comparar_funciones.py`): dada una migración nueva, enseña por cada función rehecha qué líneas pierde frente a su versión anterior en `supabase/migrations/`. Solo lee archivos.
3. Pruebas: la 00 sigue dando lo mismo; una prueba nueva de la auditoría (en una base sana da «Sin avisos»; con un caso raro preparado dentro de una transacción que se deshace, da el aviso correspondiente); permisos (`authenticated` no puede ejecutarla).
4. Ejecútala en pruebas y pega en el PR el resultado entero. Si sale algún aviso real, **no lo arregles en esta tarea**: lístalo en el PR para que el coordinador decida.

**Entrega:** Pull Request **«Tarea 19 — Auditoría de solo lectura»**, con «Qué he leído y qué existía ya», el resultado de la auditoría en pruebas, la consulta de registros y las dudas.

---

## 7.0 TAREA 18 (fusionada en el PR #17): `guardar_reparto` responde 500 aunque guarda

**Qué pasa** (registros de las funciones, desde el 28/10/2026 a las 09:46, justo después de la Tarea 10): casi todos los `POST guardar_reparto` que guardan bien terminan en **500** («Algo ha fallado en el servidor») con `SyntaxError: Unexpected end of JSON input` en `_compartido/servidor.ts` (`rpc`, `await r.json()`), llamado desde `reparto_lista.ts` en `servidor_reparto_anotar_id_cliente`. Esa función devuelve `void` y la base de datos responde **sin cuerpo**, así que `r.json()` falla **después** de haber guardado: el reparto o el envío quedan guardados (y con `id_cliente`), pero la pantalla ve el error y no enseña «¡Hecho!» ni el texto para WhatsApp. Lo mismo pasa con `servidor_guardar_cobertura` (`r4.ts`): ahí el error se captura y solo ensucia el registro. Repartos afectados en pruebas: 28/10 a las 09:46, 09:58, 12:30 y 14:15; 29/10 a las 07:30, 07:32, 10:36 y 14:14 (el envío), y los reintentos de las 14:55–14:57.

1. Arregla `rpc` en `_compartido/servidor.ts` para que una respuesta correcta **sin cuerpo** (vacía o 204) devuelva `null` en vez de fallar. Una sola corrección para todas las llamadas; no toques cada sitio.
2. Revisa que ninguna otra llamada dependa de que las funciones `void` devuelvan algo (`servidor_anotar_sale`, `servidor_reparto_anotar_id_cliente`, `servidor_guardar_cobertura`).
3. **Prueba que lo cubra** con una respuesta real sin cuerpo (no un stub que devuelva `null`): por qué no lo detectaron las pruebas de la Tarea 10, y que no vuelva a pasar. Si puedes, una prueba contra el proyecto de pruebas que llame a `guardar_reparto` y espere 200.
4. Despliega en pruebas `guardar_reparto`, `lista_stock` y las demás funciones que usen `servidor.ts`, y comprueba en los registros que el siguiente guardado da 200.
5. No cambies nada más. `CONTRATOS.md` no cambia (solo una línea en su historial).

**Entrega:** Pull Request **«Tarea 18 — rpc con respuestas sin cuerpo»**, con un resumen corto, la salida de las pruebas y el registro del 200.

---

## 7.0 TAREA 17 (fusionada en el PR #16): envío sin granel, se comprueba al calcular, en pruebas

En el envío no hay «cogerlo de otra tienda»: se comprueba **al guardar el envío**, antes de que llegue nada a la producción.

1. En `guardar_reparto` con `tipo: "envio"` (preparar y modificar): con la misma cuenta que ya decide lo que falta por producir (almacén ahora, apartando antes lo del reparto como hasta ahora), si una referencia hay que hacerla y su producto tiene **granel ≤ 0** (el mismo criterio que R3 y la Tarea 16), **no se guarda nada** y se responde un error nuevo **`SIN_GRANEL`**, con un mensaje y `detalle.referencias: [{ destino_id, destino, producto, formato, pedido, hay }]`: lo que se ha pedido para ese destino y lo máximo que se puede mandar con las cajas que hay (si hay dos destinos con la misma referencia, las cajas se las llevan los primeros, en su orden, como en la Tarea 16). Mensaje por referencia: «SOUR DIESEL 4g: pides 5, en el almacén hay 3 cajas y no hay granel para hacer las otras 2.»
2. Con todo cubierto (o con granel), el envío se guarda exactamente como ahora. El reparto **no cambia** (sigue con R1e en la producción, Tarea 16).
3. No rompas lo que funciona: reparto, pedidos de cliente, peticiones especiales, histórico y lista de stock igual. Reintentar con el mismo `id_cliente` tras un `SIN_GRANEL` y con las líneas corregidas debe guardar normal.
4. Casos en `REGLAS_CALCULO.md` (envío con granel; sin granel con 0 cajas; sin granel con algunas cajas; dos destinos; viernes con reparto el mismo día) y pruebas en verde. `CONTRATOS.md` a la 1.6, con su nota para Lovable (la pantalla mostrará cada aviso con «Dejarlo en N» o «Quitarlo» y se vuelve a calcular).

**Entrega:** Pull Request **«Tarea 17 — Envío sin granel»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 16 (fusionada en el PR #15): producto sin granel en el reparto (quitarlo o cogerlo de otra tienda), en pruebas

Hoy, si el reparto pide algo que no hay en el almacén ni tiene granel, la producción le dice al operario «haz N» y no puede. R1e lo resuelve **en la producción**, no al preparar el reparto: quien prepara el reparto no mira el almacén y el almacén decide de dónde sale cada cosa.

1. **Detectarlo.** Al crear (o rehacer) la producción del reparto, cada elemento que haya que hacer y cuyo producto tenga **granel ≤ 0** en PRINCIPAL (el mismo criterio que «sin granel no se produce» de R3, variedad por variedad) lleva `sin_granel: true`. Para ayudar a elegir, añade `para`: las tiendas del reparto que reciben ese producto y cuántas cajas le faltan a cada una, y `tiendas_con_stock`: las demás tiendas del reparto (`destinos_reparto.reparto`) con las cajas que tienen de esa referencia según su pestaña de la hoja (solo las que tengan alguna). Solo se lee lo que ya se lee al calcular; no se lee la hoja de nuevo.
2. **Decidir** (operario, en la tarea «Producción del reparto»): una función nueva, por ejemplo `resolver_sin_granel(elemento_id, decisiones)`, con una decisión por tienda que recibe: `quitar` o `otra_tienda` (con la tienda de origen) y la cantidad. Entre todas suman lo que falta. Al guardarse, el elemento queda resuelto (no hay que hacerlo) y la tarea sigue como siempre. Es idempotente y queda registrado quién lo decide y cuándo.
   - **quitar:** baja esa cantidad en la línea del reparto de esa tienda (la bolsa lleva menos). Lo habrá hablado con Administración: no hace falta avisar.
   - **otra_tienda:** esas cajas **no se producen ni van en la bolsa**. En la bolsa de la tienda que recibe aparece un elemento nuevo (`tipo: "llamada"`) con el texto «Llama a [origen] para que prepare N [producto formato] para su retirada», que se marca como las peticiones especiales (`marcar_cajas` con 1 o 0); la tienda no está completa sin marcarlo.
3. **La parada para quien hace la ruta.** En el objeto `reparto_de_hoy` (el de `tarea_activa` y `estado_actual`), añade `paradas: [{ origen, destino, producto, formato, cantidad, texto }]` con «Recoge N [producto formato] en [origen] y déjalas en [destino]». Las pantallas lo enseñan en «Salida del reparto» si sale el operario y en el panel si sale Administración. No crees tareas nuevas para nadie.
4. **Texto para WhatsApp** (`guardar_reparto` y `reparto_de_hoy_detalle`): la línea de la tienda que recibe dice «2x BZ1 4g (de Algorta)»; lo quitado ya no sale (o sale con la cantidad nueva).
5. **Cuentas (R1c, una sola fuente):** las cajas de otra tienda no salen del almacén. En camino, desde «bolsas listas» hasta las 23:30 como el reparto: −N en la tienda de origen y +N en la que recibe (en total, igual). Hazlo dentro de `motor.en_camino_en`/`motor.almacen_ahora_de`, sin una segunda cuenta.
6. **Modificar el reparto** conserva las decisiones de las líneas que siguen (como conserva lo hecho); si la línea desaparece o baja por debajo de lo decidido, la decisión se ajusta o se va, y explícalo en el PR.
7. **No rompas lo que funciona:** reparto, envío, pedidos de cliente, peticiones especiales, bolsas, histórico, lista de stock y «almacén ahora» no cambian de forma; solo se añaden campos. Si para hacerlo hiciera falta cambiar algo que ya usan las pantallas, **para y pregunta**.
8. Escribe R1e en `REGLAS_CALCULO.md` con casos: sin granel con dos tiendas que reciben (una quitar y otra de otra tienda), con granel (no sale el aviso), modificar después de decidir, la línea de WhatsApp y la cuenta de en camino. Todas las pruebas en verde; `CONTRATOS.md` a la 1.5, con su nota de cambios para Lovable.

**Entrega:** Pull Request **«Tarea 16 — Producto sin granel en el reparto»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 15 (fusionada en el PR #14): panel de Administración tras la prueba en el almacén, en pruebas

1. **Minis (R3).** En `configuracion.stock_excluidos`, el producto es **`MINI`** (formato `10g`), no `MINIBUDS MIX`: en la hoja real se llama «MINI» en PRINCIPAL, en CONTEO DE CAJAS TOTAL y en las tiendas. Hoy sale en la lista del +35 % («MINI · 10g · Haz 16») y no debe salir. Cambia también los datos de prueba que usen «MINIBUDS MIX» para que se parezcan a la hoja real, y añade una prueba: con «MINI 10g» en CONTEO, no sale en la lista y aparece en `excluidos`.
2. **Hoy con horas.** En `estado_actual().hoy`, añade a cada tarea `iniciada_en`, `terminada_en` y `minutos` (de inicio a fin; hasta ahora si está en curso; `null` si no ha empezado). La tabla ya guarda las horas: solo hay que enviarlas.
3. **Tiempo libre.** En `estado_actual`, un bloque nuevo `tiempo_libre = { veces, minutos }` con las tareas «Orden y limpieza» (`cola_orden`) de hoy: cuántas se han empezado y los minutos en total (la que está en curso, hasta ahora).
4. **Menos de 2 semanas (R4), siempre a la vista.** En `estado_actual`, un bloque nuevo `cobertura_baja = { datos_leidos_en, productos: [{ producto, formato, total, necesidad_semana, semanas }] }`, con **solo** los productos por debajo de 2 semanas.
   - La cuenta: «LO QUE HAY EN TOTAL» de PRINCIPAL frente a 2 × «1 SEMANA NECESIDADES». Invernadero e Indoor, sumando toda la categoría (una fila por categoría).
   - Con la hoja tal cual, sin «almacén ahora» ni cajas en camino: producir o mandar a una tienda no cambia el total.
   - Fuera: minis y vapers (los de `stock_excluidos`) y lo que tenga necesidad 0. Un dato vacío o raro no se inventa: va a un aviso.
   - **Una sola cuenta:** hazla como pieza propia (como `calcularStock` en `_compartido/r3.ts`), para que la use también el aviso del jueves cuando se construya. No la dupliques.
   - `estado_actual` solo lee la base de datos. Si para esto hace falta guardar la última lectura de PRINCIPAL o leer la hoja de otra forma, usa lo que ya existe para leerla (`_compartido/hoja.ts`) y explica en el PR qué has elegido. Si hiciera falta leer la hoja cada vez que se abre el panel, **para y pregunta**.
5. **No rompas lo que funciona.** `almacen_ahora` se queda en `estado_actual` (la pantalla dejará de mostrarlo, pero no lo quites). Lo demás de `estado_actual`, `tarea_activa`, `catalogo` y `lista_stock` no cambia de forma: solo se añaden campos.
6. Escribe la R4 en `REGLAS_CALCULO.md` con casos de prueba (uno por encima, uno por debajo, Invernadero por categoría, uno excluido y uno con dato vacío). Todas las pruebas en verde; `CONTRATOS.md` a la 1.4, con su nota de cambios.

**Entrega:** Pull Request **«Tarea 15 — Panel de Administración: minis, horas, tiempo libre y menos de 2 semanas»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 14 (fusionada en el PR #13): cuenta del almacén entre recuentos y cajas en camino con hora, en pruebas

Sustituye a la versión anterior de R1c, la de «en camino hasta la mañana siguiente», que construiste en la Tarea 12.

1. **Almacén ahora** = la última lectura de la hoja tomada en un recuento + lo producido y marcado desde ese recuento (elementos de producción del reparto, del envío, de los pedidos y de la lista del +35 %) − lo que ha salido desde ese recuento (bolsas listas, envíos preparados, pedidos de Nacex preparados).
2. **Al marcar como hecha una tarea de recuento** (`contenido = recuento`), la app vuelve a leer la hoja (o la marca para leerla en el siguiente cálculo) y pone a cero lo producido y lo salido de ese almacén.
3. **Cajas en camino**, sumadas a su tienda solo en los cálculos: reparto en coche (y pedidos para recoger en tienda) desde «bolsas listas» **hasta las 23:30 de ese día**; envío por Nacex a Gipuzkoa o Durango desde que está preparado **hasta las 11:59 del día siguiente**. El recuento no las borra. Las horas, en `configuracion`.
4. **Pedidos de cliente por Nacex:** salen del stock (se restan del almacén y no se suman a ninguna tienda).
5. **El reparto de primera hora** sigue calculándose solo con lo que dice el almacén en la hoja (como ahora).
6. Úsalo en: modificar el reparto durante el día, el envío, el «coge / haz» de los pedidos y `lista_stock` (R3: el contador suma lo producido desde el recuento y lo que va en camino, y resta los pedidos de Nacex).
7. Que el panel pueda enseñarlo: añade a `estado_actual` un bloque `almacen_ahora` con el último recuento leído (hora) y, por referencia con movimiento hoy, `hoja`, `producido`, `salido` y `ahora`. Es solo informativo.
8. Escribe la regla en `REGLAS_CALCULO.md` con los ejemplos del propietario como casos de prueba:
   - 12:45: almacén 5 y tienda 3 en la hoja, más 3 de reparto en camino → **11**;
   - 17:55: almacén 8 y Gipuzkoa 4 en la hoja, más 4 en la caja de Nacex → **16**;
   - y el del hueco: a las 09:30 se producen 6 de BZ1 4g con 4 en la hoja; a las 11:00 se modifica el reparto pidiendo 5 más → **no hay que hacer ninguna**.
9. **Sustituye, no añadas al lado** (revisión del coordinador, 28/10/2026). La versión anterior de R1c está en `motor.hoja_sin_reparto`, `motor.comprometido_en` y `motor.comprometido` (migración `20261028114125_pedidos_revision`), en `cajasEnCamino` y `calcularStock` (`_compartido/r3.ts`), en `lista_stock` y en `_compartido/reparto_lista.ts`. Tiene que quedar **una sola fuente** de «almacén ahora» y «en camino», usada por todos. Diferencias concretas que hay que corregir:
   - hoy solo se mira la jornada de hoy → el envío por Nacex sigue en camino **hasta las 11:59 del día siguiente**, así que hay que mirar también el envío de ayer;
   - de lunes a jueves el envío no cuenta como en camino (solo el viernes) → cuenta **siempre** desde que está preparado;
   - el viernes, los pedidos de Nacex se suman en camino → **salen del stock** y no se suman a ninguna tienda;
   - solo se tiene en cuenta `recuento_manana` → **cada recuento** (mañana y tarde) pone el almacén al día;
   - no se suma lo producido entre recuentos → **se suma**.
10. **No rompas lo que funciona:** el reparto de primera hora, los pedidos (tienda y Nacex, «coge / haz», pasar a mañana), las peticiones especiales, el histórico y las salidas que usan las pantallas (`tarea_activa`, `estado_actual`, `catalogo`, `guardar_reparto`, `guardar_pedido_cliente`, `lista_stock`) **no cambian de forma**. Solo se añade `almacen_ahora`. Si alguna prueba existente (sobre todo la 17 y R3-21 a R3-23) comprobaba el comportamiento anterior, cámbiala **a propósito** y explica en el PR qué prueba cambia y por qué. Si para hacerlo bien hiciera falta cambiar algo que usan las pantallas, **para y pregunta** antes.
11. Todas las pruebas en verde; `CONTRATOS.md` a la 1.3, con su nota de cambios.

**Entrega:** Pull Request **«Tarea 14 — Cuenta del almacén y cajas en camino»**, con un resumen de 10 líneas como máximo, la salida de las pruebas y las dudas.

---

## 7.0 TAREA 13 (fusionada en el PR #12): peticiones especiales e histórico

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
| 1.17 | 28/10/2026 | Tarea 13 fusionada. Tarea 14 activa: cuenta del almacén y cajas en camino con hora. |
| 1.18 | 28/10/2026 | Tarea 14 fusionada (PR #13). Sin tarea activa. |
| 1.19 | 29/10/2026 | Tarea 15 activa: minis, horas de las tareas, tiempo libre y menos de 2 semanas en el panel. |
| 1.20 | 29/10/2026 | Tarea 15 fusionada (PR #14). Sin tarea activa. |
| 1.21 | 29/10/2026 | Tarea 16 activa: producto sin granel en el reparto (R1e). |
| 1.22 | 29/10/2026 | Tarea 16 fusionada (PR #15). Sin tarea activa. |
| 1.23 | 29/10/2026 | Tarea 17 activa: envío sin granel (R1e, al calcular). |
| 1.24 | 29/10/2026 | Tarea 17 fusionada (PR #16). Sin tarea activa. |
| 1.25 | 29/10/2026 | Tarea 18 activa (urgente): `guardar_reparto` da 500 aunque guarda (respuestas sin cuerpo). |
| 1.26 | 29/10/2026 | Tarea 18 fusionada (PR #17). Constitución técnica: lectura obligatoria y apartado «Qué he leído y qué existía ya». Tarea 19 activa: auditoría de solo lectura. |
| 1.27 | 30/10/2026 | Tarea 19 fusionada (PR #18). Tarea 20 activa: limpieza de resinas al final y retoques de la auditoría. |
| 1.28 | 30/10/2026 | Tarea 20 fusionada (PR #19). Sin tarea activa. |
| 1.29 | 30/10/2026 | Tarea 21 activa: interrupciones, cajas y minutos trabajados en «Hoy». |
| 1.30 | 30/10/2026 | Tarea 21 fusionada (PR #20). Sin tarea activa. |
| 1.31 | 30/10/2026 | Tarea 22 activa: incidencias nuevas, lista de compras y avisos de Administración. |
| 1.32 | 30/10/2026 | Tarea 22 fusionada (PR #21). Sin tarea activa. |
| 1.33 | 02/11/2026 | Tarea 23 activa: cuatro arreglos tras la prueba del 02/11. |
| 1.34 | 02/11/2026 | Tarea 23 fusionada (PR #22, con la regla «lo primero de la mañana»). Tarea 24 activa: quién hizo cada tarea. |
| 1.35 | 02/11/2026 | Tarea 24 fusionada (PR #23): «hecha por», nada fuera del turno y pausa sola al acabar el turno. Sin tarea activa. |
| 1.36 | 02/11/2026 | Tarea 25 activa: montar producción. |
| 1.37 | 02/11/2026 | Tarea 25 fusionada (PR #24): producción montada. Tarea 26 activa: huella sin las claves de cada entorno y `catalogo` igual en los dos. |
| 1.38 | 02/11/2026 | Tarea 26 fusionada (PR #25). Falta pasar la migración a producción (punto 3). |
| 1.39 | 02/11/2026 | Tarea 27 activa (tiendas, primera parte), aprobada por el propietario. |
| 1.40 | 02/11/2026 | Tarea 27 fusionada (PR #26). Lo de tiendas no pasa a producción hasta que el propietario lo apruebe tras probarlo. Sin tarea activa. |
| 1.41 | 02/11/2026 | Tarea 28 activa (tiendas, segunda parte), aprobada por el propietario. |
| 1.42 | 03/11/2026 | Tarea 29 preparada (conflictos al crear tareas de Administración, tras las bolsas pasadas a mañana por error); se encarga al terminar la 28. La tercera parte de tiendas pasa a ser la Tarea 30. |
| 1.43 | 03/11/2026 | Tarea 28 fusionada (PR #27), solo en pruebas. Tarea 29 con un punto más: avisos del almacén a las tiendas. |
| 1.44 | 03/11/2026 | Tarea 29 fusionada (PR #28), solo en pruebas. Sin tarea activa. |
| 1.45 | 03/11/2026 | Tarea 30 preparada (incidencias de tienda); la tercera parte de tiendas queda en 30 incidencias · 31 atascados · 32 panel · 33 resumen del día. |
| 1.46 | 03/11/2026 | Tarea 29b activa (aviso de salida solo cuando toca), antes de la 30. |
| 1.47 | 03/11/2026 | Tarea 30 ajustada (franquicias: solo incidencia de texto libre). Tarea 30b preparada (franquicias y Durango: «Envíos» y cierre de caja corto). |
| 1.48 | 03/11/2026 | Tarea 29b fusionada (PR #29), solo en pruebas; el pendiente de §9.11 ya está hecho. Sin tarea activa. |
| 1.49 | 03/11/2026 | Tarea 30 activa (incidencias de tienda), aprobada por el propietario. |
| 1.50 | 03/11/2026 | Tarea 30 fusionada (PR #30), solo en pruebas. Sin tarea activa. |
| 1.51 | 03/11/2026 | Tarea 30c preparada (pedidos de cliente para recoger en Donosti, Rentería y Durango, por envío). |
| 1.52 | 03/11/2026 | Tarea 30b activa (aprobada por el propietario): Durango mantiene su cierre del día completo; el número de envíos sin confirmar en `tienda_hoy()`. |
| 1.53 | 03/11/2026 | Tarea 30b fusionada (PR #31), solo en pruebas. Tarea 30c ajustada: los pedidos de Donosti salen en «Envíos» de Rentería. Sin tarea activa. |
| 1.54 | 04/11/2026 | Tarea 29c activa (urgente): bolsas del 03/11 arrastradas a hoy; lo del reparto nunca se arrastra. |
| 1.55 | 04/11/2026 | Tarea 29c fusionada (PR #32), solo en pruebas. Sin tarea activa. |
| 1.56 | 04/11/2026 | Tarea 30c activa: pedidos por envío (Donosti, Rentería, Durango) y pedidos creados por la propia tienda, solo para recoger en su tienda. |
| 1.57 | 04/11/2026 | Tarea 30c fusionada (PR #33), solo en pruebas. Sin tarea activa. |
| 1.58 | 04/11/2026 | Tarea 31 preparada (productos atascados), pendiente de aprobación. |
| 1.59 | 04/11/2026 | Tarea 31 activa (productos atascados), aprobada por el propietario. |
| 1.60 | 04/11/2026 | Tarea 29d activa (urgente): «Calcular» solo con la hoja. Tarea 31 entregada (PR #34), en revisión. |
| 1.61 | 04/11/2026 | Tarea 31 fusionada (PR #34), solo en pruebas. Activa: 29d. |
| 1.62 | 04/11/2026 | Tarea 29d fusionada (PR #35), solo en pruebas; `pegar_reparto` borrada del código (falta borrarla del panel de Supabase). Sin tarea activa. |
| 1.63 | 04/11/2026 | Tarea 32 preparada (panel de Administración por centro), pendiente de aprobación. |
| 1.64 | 04/11/2026 | Tarea 32 activa (panel por centro), aprobada por el propietario. |
| 1.65 | 04/11/2026 | Tarea 32 fusionada (PR #36), solo en pruebas. Sin tarea activa. |
