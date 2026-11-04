# OSASUN OPERATIONS — Contratos entre la base de datos y las pantallas (V1)

**Versión:** 1.20 · **Fecha:** 04/11/2026 · **Autor:** agente de base de datos · **Estado:** aprobado (PR #1 y #2). ✅ = publicado en el proyecto de pruebas (Tareas 2 a 24) y, desde la Tarea 25, también en producción. 🧪 = solo en pruebas: lo de tiendas **no** pasa a producción al fusionar su PR, sino cuando el propietario lo apruebe tras probarlo en Basauri y Portugalete.

> **Cambios en 1.20 (Tarea 29d) — para Lovable: «Calcular» solo con la hoja.** Nada cambia de forma. 🧪 = solo en pruebas.
> 1. **`guardar_reparto`** (§3.14), en el reparto y en el envío: `en_almacen` de cada referencia es **la cifra de la hoja leída al pulsar «Calcular»**, tal cual (`ESTADO_DEL_SISTEMA.md` R1c v1.58). Ya no suma lo producido ni resta lo salido desde el recuento, y el envío ya no aparta el reparto de hoy: `apartado_reparto` es siempre 0. La pantalla no tiene que cambiar nada; si enseña «apartado para el reparto», ya no saldrá.
> 2. **La hoja tiene que estar al día al calcular.** Con 0 en la hoja y sin granel, sale lo de siempre: en el reparto, «quitar o coger de otra tienda» (§3.19); en el envío, `SIN_GRANEL`.
> 3. **No cambia:** el «coge / haz» de los pedidos, la lista del +35 % (`lista_stock`) y las cajas en camino siguen con el almacén ahora (punto 6 de 1.3).
> 4. **`pegar_reparto` ya no existe** (§3.8; **orden del propietario**, 04/11/2026): si alguna pantalla la llamaba todavía, que use `catalogo` + `guardar_reparto`.

> **Cambios en 1.19 (Tarea 31) — para Lovable: productos atascados.** Solo se añade (§3.11, §9.1, §9.2, §9.15 a §9.17 y el apartado nuevo §9.23). 🧪 = solo en pruebas.
> 1. **Tableta, el martes** (§9.23): tarea «Revisa los productos atascados» (`tipo: "atascados"`), por la mañana (Bilbao alterna), en todas las tiendas, franquicias incluidas. Lista de `productos_tienda()` con su formato y − y + (cajas), nota opcional por producto; se guarda con **`revisar_atascados`**. Lista vacía = «Nada atascado esta semana».
> 2. **Tableta, las ofertas:** **`tienda_hoy().ofertas_atascados`**, todo el martes: «Basauri tiene 3 cajas de V2 4g que no se mueven: ¿las quieres?» con el botón **«Las quiero»** (`querer_atascado`). Se lo lleva la primera; a las demás les sale «Ya lo ha pedido [tienda].» y deja de salir.
> 3. **Tableta, lo suyo:** **`tienda_hoy().atascados`** (lo que ha apuntado, con `estado_texto`), **`atascados_pedidos`** (lo que ha pedido a otras) y **`promociones`** (las abiertas, con el botón **«Ya no queda»**, `ya_no_queda`). Los avisos («Prepara N de Y para recogida», «Promoción de …») llegan en `avisos`, como siempre.
> 4. **Panel de Administración:** los atascados llegan a **`incidencias_tiendas()`** como incidencias abiertas (`opcion: "atascado"`) con el objeto **`atascado`** y sus **`decisiones`**: en las propias, al acabar el martes si nadie lo ha pedido («promoción» o «al almacén»); en las franquicias y Durango, en el momento («promoción» o «recogida»). Se decide con **`decidir_atascado`** (la promoción, con el texto que escribe Administración). No usar «Cerrar» para estas.
> 5. **Operario:** la recogida le llega como incidencia abierta (`opcion: "recogida_atascado"`, §3.11), **sin hora y sin tocar el reparto**: «Recoge 3 cajas de V2 4g en Basauri y llévalo a Portugalete». La cierra al entregarlo con `cerrar_incidencia`, como las demás. Si lo ha pedido una tienda que recibe por envío, al cerrarla queda como petición para su siguiente envío (§9.16, `tipo: "atascado"`).

> **Cambios en 1.18 (Tarea 30c) — para Lovable: pedidos de cliente para todas las tiendas (por envío y desde la tableta).** Solo se añade. 🧪 = solo en pruebas.
> 1. **«Pedido de cliente» (almacén y Administración):** la lista de tiendas para «Recoger en tienda» es **`catalogo().tiendas.pedido`** (§3.13): las del reparto y, además, **Donosti y Rentería** (y Durango cuando abra), con `va_en: "reparto" | "envio"`. Las que van por envío esperan al siguiente envío a Gipuzkoa (o a Durango).
> 2. **El pedido** (§3.17) trae `va_en`, `pedido_en_tienda` (si lo apuntó una tienda, cuál) y `pedido_por` (quién estaba en el turno), y `estado_texto` ya dice «Va en el próximo envío a Donosti» / «En el envío del 16/12: por preparar» / «Preparado: va en el envío del 16/12».
> 3. **En el almacén** (§3.2): en «Revisa si toca envío…», **`tarea.aviso`**: «Hay N pedidos de cliente esperando envío a Gipuzkoa» (mostrarlo bien a la vista; `null` en las demás tareas). En el envío, la tarea propia «Hay un pedido de cliente para enviar a [tienda] · [cliente]» (con su «coge / haz», como en el reparto) y la caja aparte «Pedido de cliente · [cliente] · [tienda]».
> 4. **En la tableta** (§9.22): botón **«Pedido de cliente»** en todas las tiendas, franquicias incluidas: nombre del cliente y productos con su formato (con − y +) de **`productos_tienda()`, que ahora trae `formatos`**; se guarda con **`crear_pedido_tienda`**. Es para recoger en esa tienda, nunca por Nacex. **`tienda_hoy().pedidos`**: los pedidos para recoger en la tienda con su `estado_texto`.
> 5. **«Envíos»** (§9.21): cada pedido trae `tienda` (en el envío a Gipuzkoa, Donosti o Rentería).

> **Cambios en 1.17 (Tarea 30b) — para Lovable: «Envíos» y el cierre de caja corto de las franquicias.** Solo se añade (§9.1, §9.14, §9.21). 🧪 = solo en pruebas.
> 1. **Pestaña «Envíos»** arriba, junto a «Avisos», en las tiendas que reciben por envío (hoy **Rentería y Durango**; Donosti no, porque el envío a Gipuzkoa va entero a Rentería, que es quien lo confirma): `tienda_hoy().envios` y, para el número de la pestaña, `tienda_hoy().envios_sin_confirmar`. Enseñar la pestaña solo si hay algo en `envios` o `envios_sin_confirmar > 0`.
> 2. Cada envío sale **desde el día siguiente a prepararlo** (cuando el operario termina «Prepara el envío aprobado», entre semana o el viernes, vaya quien vaya al reparto), con **lo marcado al meterlo en la caja** (como la bolsa) y la hora de preparado (`preparado`). **Sigue ahí hasta confirmarlo** con `confirmar_envio`: «Todo bien» o «Falta algo» (eligiendo qué y cuánto, como la reposición; llega a Administración como incidencia abierta). **Al confirmarlo desaparece en el momento.** No es una tarea con hora.
> 3. **Cierre de caja corto** (Donosti y Rentería): tarea «Cierre de caja» 10 minutos antes de cerrar con un punto `pide: "cierre_caja_corto"`: pedir solo **la Z y el nº de ventas** y llamar a `cerrar_caja({ elemento_id, z, ventas })`. Las propias (Durango incluida) siguen con su «Cierre del día» completo (`pide: "cierre_caja"`).
> 4. `cierres_caja()` trae `efectivo` y `glovo` vacíos (`null`) en los cierres cortos.

> **Cambios en 1.16 (Tarea 30) — para Lovable: incidencias de tienda.** Solo se añade (§9.1 y §9.20). 🧪 = solo en pruebas.
> 1. **Botón «Incidencia»** en la tableta: las opciones de esa tienda vienen en **`tienda_hoy().opciones_incidencia`** (en las propias: «Material de tienda», «Me quedo sin producto», «Descuadre de stock o de caja», «Comentario de cliente» y «Otros»; en Donosti y Rentería, solo «Otros», un cuadro de texto libre). Pintar solo las que vengan. Sin foto ni urgencia.
> 2. **«Material de tienda»** es lo de siempre: `pedir_material` (§9.15). Las demás, **`crear_incidencia_tienda`** (§9.20).
> 3. **«Me quedo sin producto»:** enseñar el botón de **llamar a Administración** (`mi_perfil().telefono_administracion`) y, además, elegir el producto de `productos_tienda()` (nota opcional, por ejemplo el formato): queda apuntado.
> 4. **`tienda_hoy().incidencias`:** las de la tienda abiertas y las cerradas hoy, con `estado_texto` («Abierta» / «Resuelta por Administración: [nota]»).
> 5. **Administración:** llegan a `incidencias_tiendas()` (§9.17) como incidencias abiertas, con su `opcion`, y se cierran con `cerrar_incidencia_tienda`. No hay que cambiar nada.
> 6. El pendiente de §9.11 («Recibe la bolsa» no enseña la lista) ya está en 1.15.

> **Cambios en 1.15 (Tarea 29b) — para Lovable: el aviso de salida solo cuando toca y «Recibe la bolsa» sin lista.** Nada cambia de forma. 🧪 = solo en pruebas.
> 1. **`tarea_activa().aviso_salida`** (§3.2) solo sale antes de que salga el reparto, dentro del turno y con las bolsas de hoy disponibles. Por la tarde, o con el reparto ya fuera, es `null` (el 03/11 salía a las 19:33).
> 2. **`retrasar_salida`** (§3.6): con el reparto ya fuera, `ESTADO_NO_VALIDO` («El reparto ya ha salido.») y no mueve nada. Mostrar el mensaje.
> 3. **«Recibe la bolsa»** (§9.11): la pantalla **no enseña la lista** de lo que trae; solo los dos puntos. La lista se enseña en «Coloca y apunta la reposición» (§9.12). Decisión del propietario (03/11/2026; `ESTADO_DEL_SISTEMA.md` E2-8). La base de datos no cambia: `bolsa` sigue viniendo en las dos.

> **Cambios en 1.14 (Tarea 29) — para Lovable: la ventana de conflicto al crear una tarea de Administración y los avisos del almacén a las tiendas** (`ESTADO_DEL_SISTEMA.md` §6.4 v1.46 y E2-8 v1.47). Solo se añade; lo que ya funciona sigue igual. 🧪 = solo en pruebas.
> 1. **Sin falsa alarma** (§4.1): una tarea **no urgente y sin hora límite** ya no da `CONFLICTO`; se crea y el `encaje` dice cuándo saldrá («Cuando termine lo del reparto, las obligatorias y lo que tiene hora.»).
> 2. **La ventana de conflicto pregunta primero por la tarea nueva** (§4.1): tres botones, «Para mañana» (`{ "accion": "nueva_manana" }`), «Que la haga después» (`{ "accion": "nueva_despues" }`) y «No crearla» (`{ "accion": "no_crear" }`). Mover otra tarea queda aparte, con su nombre bien a la vista («Pasar «X» a mañana»…).
> 3. **Lo del reparto y el envío de hoy no se mueve:** en `obligatorias_en_riesgo`, cada una trae **`se_puede_mover`**; ofrecer mover (`despues`, `manana`, `cancelar`) **solo las que tienen `true`**. Si llega una con `false`, `DATOS_NO_VALIDOS`.
> 4. **Avisos del almacén a las tiendas** (§9.9): el operario también puede mandar avisos con `crear_aviso_tienda` (a una tienda o a todas); para elegir la tienda, **`tiendas()`** (§9.19). Solo mandar: no gestiona personas, días cerrados ni cancela. Cada aviso trae **`de`: «Almacén» o «Administración»**, en la tienda (`tienda_hoy().avisos`) y en `avisos_tiendas()`.
> 5. **Numeración:** la tercera parte de tiendas (incidencias, atascados, panel y resumen del día), que antes se llamaba «Tarea 29», es la **Tarea 30**.
> 6. **Respuestas del propietario en el PR #28** (03/11/2026):
>    - **No se mueve nada de lo que sale hoy** (§4.1): además de lo del reparto, los pedidos de cliente (para la tienda y por Nacex) y lo de Nacex traen `se_puede_mover: false`.
>    - **Bolsas justo después de la producción del reparto** (§3.2): con la producción hecha, solo salen las bolsas (y los pedidos de cliente para la tienda) hasta terminarlas; lo urgente y lo que tiene hora esperan. La salida no sale sin las bolsas.
>    - **`tarea_activa().aviso_salida`** (§3.2): si llega la hora de salida y las bolsas no están, la pantalla muestra el aviso con «Retrasar 15 min» y «Retrasar 30 min» (`retrasar_salida`, §3.6). `null` si no hace falta.
>    - **La bolsa de la tienda** (§9.11): trae lo que el operario ha marcado como metido en ella; lo que no se ha marcado no aparece.
>    - **El operario ve y cancela sus avisos a las tiendas** (§9.9): `avisos_tiendas()` le da los que ha mandado él, y `cancelar_aviso_almacen` cancela solo esos.

> **Cambios en 1.13 (Tarea 28) — para Lovable: la tableta de las tiendas (segunda parte).** Solo se añaden campos y funciones (§9.11 a §9.18); lo de antes no cambia. Corrección: lo de tiendas (🧪) no pasa a producción al fusionar, sino cuando lo apruebe el propietario.
> 1. **«Recibe la bolsa del reparto»** (§9.11): sale sola cuando sale el reparto, en las tiendas con parada, con la hora de salida y **lo que trae la bolsa** (`bolsa`: productos, peticiones y pedidos de cliente). Dos puntos: «Bolsa recibida» (un toque; las demás tiendas lo ven) y «Bolsa de ayer entregada con X € en efectivo» (un toque = X; otra cantidad, con `entregar_efectivo` y el porqué; sin cierre anterior, pide la cantidad).
> 2. **«Coloca y apunta la reposición»** (§9.12): sale al terminar «Recibe la bolsa», con la misma lista. `apuntar_reposicion(tarea_id)` = «Reposición metida, todo bien»; con `faltan` = «Falta algo» (llega a Administración como incidencia abierta).
> 3. **Por dónde va el reparto** (§9.13): `tienda_hoy().reparto` con `texto` listo para mostrar («Ha salido a las 10:50» / «Ha pasado por Basauri a las 11:20 (parada 2 de 3)») y las paradas.
> 4. **Cierre de caja** (§9.14): el «Cierre del día» tiene un punto más, `pide: "cierre_caja"`: Z, nº de ventas, efectivo y Glovo con `cerrar_caja`.
> 5. **Muestras y material** (§9.15): «Revisa las muestras» (jueves por la mañana; también Donosti y Rentería) con la lista de `productos_tienda()`: **solo el producto, sin formato** (al tocarlo cuenta 1; − y + para cambiar la cantidad); material, en cualquier momento, con `pedir_material`. Se ven en `tienda_hoy().peticiones` con su estado («Va en el reparto de hoy»).
> 6. **Pantalla del almacén y de Administración, «Preparar reparto» y «Preparar envío»** (§9.16): al abrirla, `peticiones_tiendas_pendientes(tipo)` y **poner cada `texto` en la casilla de peticiones especiales de su `destino_id`** (se pueden cambiar o quitar). Junto a cada una, **solo para Administración**, un botón **«No va»** (`descartar_peticion_tienda`). `guardar_reparto` no cambia: al guardar, las que van quedan atendidas. Para Eder, nada más.
> 7. **Administración** (§9.17): `cierres_caja`, `incidencias_tiendas` y `cerrar_incidencia_tienda`; y en «Tiendas», la lista de peticiones pendientes (`peticiones_tiendas_pendientes`) con «No va» (`descartar_peticion_tienda`, motivo opcional).
> 8. **Errores nuevos** (§9.18): `FALTAN_DATOS` (con `pide`) y `MOTIVO_OBLIGATORIO` en el efectivo.

> **Cambios en 1.12 (Tarea 27) — para Lovable: la tableta de las tiendas (primera parte).** Solo se añaden cosas: un rol nuevo (`tienda`), funciones nuevas (§9) y un tipo de elemento nuevo (`punto`). Lo del almacén y lo de Administración que ya existía no cambia.
> 1. **Entrar:** cada tienda entra con **su cuenta de Google** (una por tienda). `mi_perfil().rol` es **`"tienda"`** y `centro` es su tienda: la pantalla abre la tableta de la tienda. Una tienda **no puede** usar las funciones del almacén ni las de Administración (`NO_AUTORIZADO`), ni ve sus datos.
> 2. **Pantalla de la tienda (§9.1 a §9.7):** todo sale de **`tienda_hoy()`**: horario, quién está, los nombres para elegir, los avisos de Administración y la lista del día con sus puntos. Al empezar el turno se elige el nombre (`empezar_turno`): ese nombre es el «hecha por» de lo que se marque. Cada tarea de puntos se hace tocando sus puntos (`marcar_punto`); la de cristales, con «Hecho» (`terminar_tarea_tienda`); el vídeo, con `compartir_video`. Los avisos se cierran con `marcar_aviso_leido`. La lista de vídeos de todas las tiendas: `videos_semana()`.
> 3. **Horas orientativas:** cada tarea trae su `hora` («10:50»). Antes de esa hora no se puede marcar (`se_puede_marcar: false`; si se intenta, `TODAVIA_NO`). No hay avisos de retraso. Al cerrar la tienda, lo que quedó sin hacer sale `no_hecha: true` y **no pasa al día siguiente**.
> 4. **Administración (§9.8 y §9.9):** los nombres de cada tienda (`personas_tienda`, `guardar_persona_tienda`), los días cerrados de una tienda o de todas (`marcar_dia_cerrado`, `dias_cerrados`) y los avisos a las tiendas (`crear_aviso_tienda`, `avisos_tiendas`; se cancelan con `cancelar_aviso_almacen`, §3.21).
> 5. **En directo:** la tableta se suscribe a `tareas` y `tarea_elementos` sin filtro (solo recibe lo de su tienda) y, ante cualquier cambio, vuelve a pedir `tienda_hoy()`. Además refresca cada minuto y al volver a la pestaña: las tareas se pueden marcar al llegar su hora sin que cambie nada en la base de datos.
> 6. **Errores nuevos** (§9.10): `TODAVIA_NO`, `SIN_PERSONA`, `YA_COMPARTIDO` y `FECHA_PASADA`. `SIN_JORNADA` también sale en la tienda («Hoy la tienda no abre.»).

> **Cambios en 1.11 (Tarea 25) — para Lovable: ya hay producción.** No cambia ninguna función. §7.1 trae los dos entornos: **pruebas** (donde se prueba todo) y **producción** (la que usarán el almacén y las tiendas), cada uno con su URL y su clave pública. Las dos bases tienen las mismas funciones y responden igual; solo cambian la dirección, la clave y los datos.

> **Cambios en 1.10 (Tarea 24) — para Lovable: quién hizo cada tarea y nada fuera del turno** (`ESTADO_DEL_SISTEMA.md` v1.39). Solo se añade un campo y cambia un comportamiento.
> 1. **`estado_actual().hoy`** (§4.3): cada tarea trae **`hecha_por`**, el nombre de quien la cerró («Prepara el reparto» la cierra quien guarda el reparto, aunque sea Administración). `null` si no está hecha. Para enseñarlo en «Hoy» junto a la hora de fin.
> 2. **`tarea_activa()`** (§3.2): **fuera del turno no sale ninguna tarea** (`tarea: null`, «Ahora no hay nada pendiente»), salvo la que esté **en curso**, que se puede terminar. Al terminarla fuera del turno, `tarea` pasa a `null` y `siguiente` dice lo del siguiente turno. Lo pendiente vuelve a salir al empezar el turno. La pantalla no cambia.
> 3. **Fin del turno** (§3.2, §4.3, §4.4): al acabar cada turno, una tarea **no obligatoria** que quedó en curso (+35 %, compras, «Orden y limpieza», lo de Administración sin hora…) **se pausa sola**: vuelve a `pendiente` con lo hecho guardado. En «Hoy» sale como interrupción con `por: "Fin del turno"` (y `siguio_a_las` al retomarla); en el cierre, con el motivo «Sin terminar: fin del turno». Las obligatorias siguen en curso para terminarlas. **Lo que tenía entre manos se puede terminar** después de la pausa: marcar la referencia (si era la última, la tarea queda hecha) o pulsar «Terminada» funcionan como siempre, pero la tarea no vuelve a ponerse en curso; `tarea_activa().tarea` sigue en `null` hasta el siguiente turno. La pantalla no cambia.

> **Cambios en 1.9 (Tarea 23) — para Lovable: cuatro arreglos tras la prueba del 02/11** (`ESTADO_DEL_SISTEMA.md` v1.38). No cambia la forma de nada; cambian un comportamiento y un orden.
> 1. **`guardar_reparto`** (§3.14): pulsar **«Calcular» con el mismo reparto vuelve a calcular** la producción y las bolsas con la hoja de ese momento, conservando lo hecho y lo decidido (como cualquier modificación). **Ya no existe el aviso `REPARTO_SIN_CAMBIOS`**: la respuesta es la normal (con `sustituye_a`). Repetir la misma petición (mismo `id_cliente`, el mismo toque) sigue devolviendo lo guardado con `REPARTO_YA_GUARDADO`. Cada «Calcular» es una petición nueva: un `id_cliente` nuevo.
> 2. **`estado_actual().hoy`** (§4.3): ahora va **primero lo hecho y lo que está en curso, en el orden en que se empezó**, y después lo pendiente, en el orden de siempre. Los campos son los mismos.
> 3. **`mi_perfil().quien_sale_opciones`** (§3.1): el nombre de Administración es el de la ficha de `administracion_por_defecto` (en pruebas, Asier). Sin cambios para la pantalla.
> 4. **Lo primero de la mañana** (§3.2 `tarea_activa`, §4.1 `crear_tarea_admin`): mientras falten ese día la revisión inicial, «Prepara el reparto», la producción del reparto, las bolsas y la preparación del envío del viernes (las que haya), y antes de que empiece el turno de tarde, no sale ninguna otra tarea, se haya creado ese día o el anterior (Administración, arrastradas, +35 %, compras, incidencias…). Sí entran lo urgente (mercancía, problemas, urgentes de Administración), lo que tiene hora fija, lo de Administración con hora límite y los pedidos de tienda. En los huecos de espera sale «Orden y limpieza». El `encaje` de una tarea de Administración no urgente y sin hora lo dice: «Cuando termine lo del reparto, las obligatorias y lo que tiene hora.».

> **Cambios en 1.8 (Tarea 22) — para Lovable: incidencias nuevas, lista de compras y avisos de Administración** (`ESTADO_DEL_SISTEMA.md` v1.36, §6.6 y §7). Solo se añaden campos y funciones.
> 1. **Botón Incidencia, tres opciones** (§3.11): `comprar` (elige de `compras_lista()` y manda su `compra_id`; «Otra cosa» = sin `compra_id`, con `descripcion`), `varios` (`descripcion`, `quien`, `importancia`) y `bloqueado` (como siempre). `crear_incidencia` gana el parámetro `compra_id` (y `descripcion` ya no es obligatoria con `comprar` de la lista). Las opciones de antes (`llega_mercancia`, `recogida_nacex`, `corregir`, `pedir_comprar`, `pedido_cliente`) ya no se ofrecen en la pantalla, pero se siguen aceptando.
> 2. **Compra por internet:** su tarea («Compra: [nombre]») trae **`enlace`** (nuevo en el objeto tarea, §3.2; `null` en las demás): abrirlo. Al hacerla, la incidencia queda «Pedido, esperando a que llegue». **En una tienda:** «Ve a comprar [nombre] a [sitio]», con la dirección en `porque`; al hacerla, se cierra. **Lo pide Administración** u «otra cosa»: sin tarea, correo en el momento y «Esperando a Administración».
> 3. **Lista de compras** (§3.20): `compras_lista()` (operario y Administración) y `guardar_compra(...)` (solo Administración: añadir, cambiar y quitar = `activo: false`). Para «Lista de compras» del panel.
> 4. **Avisos para el almacén** (§3.21): Administración los crea con `crear_aviso_almacen(id_cliente, fecha, texto, contacto?)` («Aviso para el almacén»: día, texto y, si quiere, un contacto) y los cancela con `cancelar_aviso_almacen(aviso_id)`. Los ve en **`estado_actual().avisos_almacen`**. Al operario, desde su día, le salen arriba en **`tarea_activa().avisos: [{ id, texto, contacto, fecha }]`** y en sus incidencias abiertas («Aviso de Administración»); los cierra con `cerrar_incidencia` como las demás. No son tareas.
> 5. **Botón rojo:** `tarea_activa().incidencias_abiertas` ya cuenta también los avisos (desde su día).

> **Cambios en 1.7 (Tarea 21) — para Lovable: interrupciones, cajas y minutos trabajados en «Hoy»** (`ESTADO_DEL_SISTEMA.md` v1.35, §8 Inicio, punto 4). Solo se añaden campos; nada cambia de forma.
> 1. **`estado_actual().hoy`** (§4.3): cada tarea trae **`interrupciones: [{ a_las, por, siguio_a_las }]`**, en orden: a qué hora la interrumpió otra tarea (con hora o urgente), el título de esa tarea y cuándo siguió (`null` si aún no se ha retomado). Lista vacía si no hubo. Se muestra aunque la tarea siga pendiente: «Interrumpida a las 10:45 por «Salida del reparto»» y, si se retoma, «siguió a las 12:05».
> 2. En las tareas de producción (producción del reparto, +35 % y pedidos de cliente: las que tienen referencias que producir): **`cajas: { hechas, total }`** y **`minutos_trabajados`** (todo el tiempo que la tarea ha estado en marcha, también entre un producto y otro, sin lo que estuvo interrumpida por otra tarea, como la salida y la ruta; si está en curso, hasta ahora; decisión del propietario, 30/10/2026). Para «21 de 43 cajas · 52 min». En las demás tareas, los dos son `null`.
> 3. `iniciada_en`, `terminada_en` y `minutos` (de inicio a fin, con la ruta incluida) siguen igual.

> **Tarea 20 (30/10) — sin cambios para Lovable:** la limpieza de resinas del viernes sale después de preparar el reparto, su producción, los pedidos de cliente (tienda y Nacex), sus bolsas, el envío y el +35 %, y antes de las 12:45; `tarea_activa` la da sola cuando toca. La auditoría avisa si el reparto o el envío aceptado hoy no tiene sus tareas.

> **Tarea 19 (29/10) — sin cambios para Lovable:** nueva función interna `motor.auditoria()` (§5) para las revisiones del coordinador (`docs/AUDITORIA.md`).

> **Tarea 18 (29/10) — sin cambios en los contratos:** las funciones del servidor ya no responden 500 después de guardar cuando llaman a una función de la base de datos que no devuelve nada (`guardar_reparto` era la que lo hacía); la respuesta es la de este documento.

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
  - **Funciones del servidor** (`supabase.functions.invoke('nombre', {...})`): las que leen Sheets (`catalogo`, `guardar_reparto`, `guardar_pedido_cliente` y `lista_stock`; `pegar_reparto` se borró en la Tarea 29d).
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
| `crear_tarea_admin` · `cancelar_tarea` · `estado_actual` | BD | — | ✔ | ✅ Tarea 4 (🧪 Tarea 29: conflictos, §4.1) |
| `historico_dia` · `historico_dias` | BD | — | ✔ | ✅ Tarea 13 |
| `cierre` · `cierres_recientes` | BD | — | ✔ | ✅ Tarea 4 |
| `generar_jornada` · `generar_cierre` · `enviar_correo` | Internas | — | — | ✅ |

Tiendas (Tarea 27, §9; columna «Tienda» = la cuenta de cada tienda):

| Función | Tipo | Tienda | Administración | Estado |
| --- | --- | --- | --- | --- |
| `mi_perfil` | BD | ✔ (`rol: "tienda"`) | ✔ | 🧪 Tarea 27 |
| `tienda_hoy` · `empezar_turno` · `marcar_punto` · `terminar_tarea_tienda` · `compartir_video` · `marcar_aviso_leido` | BD | ✔ | — | 🧪 Tarea 27 |
| `videos_semana` | BD | ✔ | ✔ | 🧪 Tarea 27 |
| `personas_tienda` | BD | ✔ (solo la suya) | ✔ | 🧪 Tarea 27 |
| `guardar_persona_tienda` · `marcar_dia_cerrado` · `dias_cerrados` · `avisos_tiendas` | BD | — | ✔ | 🧪 Tarea 27 |
| `crear_aviso_tienda` · `tiendas` | BD | — (operario ✔, Tarea 29) | ✔ | 🧪 Tareas 27 y 29 |
| `entregar_efectivo` · `cerrar_caja` · `apuntar_reposicion` · `revisar_muestras` · `pedir_material` | BD | ✔ | — | 🧪 Tarea 28 |
| `productos_tienda` | BD | ✔ | ✔ | 🧪 Tarea 28 |
| `peticiones_tiendas_pendientes` | BD | — (operario ✔) | ✔ | 🧪 Tarea 28 |
| `descartar_peticion_tienda` · `cierres_caja` · `incidencias_tiendas` · `cerrar_incidencia_tienda` | BD | — | ✔ | 🧪 Tarea 28 |
| `crear_incidencia_tienda` | BD | ✔ | — | 🧪 Tarea 30 |
| `confirmar_envio` | BD | ✔ | — | 🧪 Tarea 30b |
| `crear_pedido_tienda` | BD | ✔ | — | 🧪 Tarea 30c |
| Todas las del almacén y las de Administración de arriba | — | — (`NO_AUTORIZADO`) | — | 🧪 Tarea 27 |

## 3. Operario

### 3.1 `mi_perfil()` ✅
- **Salida:** `{ id, nombre, rol, centro: {id, nombre} | null, telefono_administracion, quien_sale_opciones }`
- `quien_sale_opciones` ✅ Tarea 8: `[{ "valor": "administracion", "nombre": "…" }, { "valor": "operario", "nombre": "…" }]`, con los nombres de las fichas (Administración y el operario por defecto), para el desplegable «¿Quién sale?». ✅ Tarea 23: la de Administración es la de `administracion_por_defecto` (configuración del entorno); si falta, la primera por orden alfabético, como antes.
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
    "arrastrada_de": null, "iniciada_en": null, "terminada_en": null, "enlace": null,
    "elementos": []
  },
  "siguiente": "Salida del reparto · 10:45",
  "reparto_de_hoy": { "reparto_id": "...", "aceptado_en": "2026-11-03T07:48:00+00:00", "pegado_por": "<persona_id>", "pegado_por_nombre": "Administración", "paradas": [] },
  "incidencias_abiertas": 2,
  "avisos": [ { "id": "...", "texto": "Voy al Casco Viejo y llevo yo la bolsa de Bilbao", "contacto": null, "fecha": "2026-11-03" } ],
  "incidencia_en_curso": { "id": "...", "opcion": "corregir", "descripcion": "...", "estado_texto": "En curso desde las 15:47", "minutos": 10, "...": "(objeto incidencia, §3.11)" },
  "problemas_abiertos": [ { "id": "...", "tarea_id": "...", "tarea": "Revisar el envío", "tipo": "no_encuentro", "descripcion": "...", "estado": "abierto|sin_respuesta", "llamadas": 0, "proxima_llamada_en": null } ]
}
```
- `jornada` es `null` si hoy no trabaja; `tarea` es `null` solo fuera del turno (antes de empezar o entre turnos).
- **Fuera del turno** ✅ Tarea 24: antes de empezar, entre turnos y después del último, `tarea` es `null` aunque quede algo pendiente; solo sigue la tarea **en curso**, para poder terminarla (el recuento de las 12:45 terminado a las 13:04). Lo pendiente vuelve a salir al empezar el siguiente turno. Es la misma comprobación del horario (`horarios`) que usa «Nunca sin tarea».
- **Fin del turno** ✅ Tarea 24 (opción B del propietario): al generarse el cierre del turno, lo **no obligatorio** que quedó en curso pasa a `pendiente`, con lo hecho guardado y una pausa «Fin del turno» a la hora de fin del turno (los minutos trabajados se paran ahí). En el siguiente turno vuelve a salir por su prioridad; al final del día sigue su regla (el +35 % se recalcula, lo de Administración pasa a mañana). Las obligatorias siguen en curso. Fuera del turno, lo que tenía entre manos se puede marcar o terminar (`terminar_elemento`, `terminar_tarea`), pero no vuelve a ponerse en curso.
- **Nunca sin tarea** (v1.17): si dentro del turno no queda nada disponible, se adelantan las tareas fijas de la tarde de ese día (minis el lunes, resinas el martes, control de materiales el jueves) y después «Orden y limpieza», que **no se gasta** (al terminarla vuelve a salir). Lo ligado a su hora (recuento, revisión del envío, Nacex, salida) espera a su hora.
- **Lo primero de la mañana** ✅ Tarea 23: mientras falten ese día la revisión inicial, «Prepara el reparto», la producción del reparto, las bolsas y la preparación del envío del viernes (las que haya), y antes del turno de tarde, solo salen esas, lo urgente (mercancía, problemas, urgentes de Administración), lo que tiene hora fija, lo de Administración con hora límite y los pedidos de tienda. Lo demás (Administración sin hora, arrastradas, +35 %, compras, incidencias, fijas de la tarde) espera; en los huecos sale «Orden y limpieza». (`motor.lo_primero_pendiente`, `motor.va_antes_que_lo_primero`.)
- **Bolsas justo después de la producción** (Tarea 29 🧪, propietario, 03/11/2026): con la producción del reparto hecha y las bolsas sin terminar, solo salen **las bolsas** (y los pedidos de cliente para la tienda, que van en ellas). Lo urgente, lo de Administración con hora y lo que tiene hora fija **esperan a que termine las bolsas**; solo las para un problema que abre el operario. «Salida del reparto» no sale hasta que las bolsas están hechas.
- **`aviso_salida`** (Tarea 29 🧪): si es la hora de salida y las bolsas aún no están (Tarea 29b 🧪: y además el reparto **aún no ha salido**, el operario está **en su turno** y las bolsas de hoy **ya están disponibles**), `{ "texto": "Es la hora de salida (10:45) y las bolsas no están listas: retrasa la salida.", "hora_salida": "10:45", "minutos": [15, 30] }`. Mostrarlo bien a la vista, con un botón por cada valor de `minutos` («Retrasar 15 min», «Retrasar 30 min») que llama a `retrasar_salida` (§3.6). Al retrasar, desaparece hasta la nueva hora. `null` en los demás casos.
- `reparto_de_hoy`: el reparto aceptado hoy (`null` si no hay). Con él, el botón de arriba dice «Modificar reparto» (abre la lista con `reparto_de_hoy_detalle`); sin él, «Preparar reparto».
- `reparto_de_hoy.paradas` ✅ Tarea 16 (R1e): `[{ origen_id, origen, destino_id, destino, producto, formato, cantidad, texto }]`, lo que quien hace la ruta recoge en una tienda para dejarlo en otra («Recoge 2 BZ1 4g en Algorta y déjalas en Portugalete»). Mostrarlo en «Salida del reparto» si sale el operario. Lista vacía si no hay. (También en `estado_actual().reparto_de_hoy`, para el panel si sale Administración.)
- **Al recargar** la pantalla recupera de aquí todo lo abierto: `incidencias_abiertas` (número para «Cerrar incidencias»), `incidencia_en_curso` (la que tiene su tarea en curso, con `minutos`; `null` si no hay) y `problemas_abiertos` (con la tarea bloqueada; el siguiente paso es `problema_llamada` o `resolver_problema`).
- `tarea.enlace` ✅ Tarea 22: el enlace de una compra por internet (tarea «Compra: …»); `null` en las demás.
- `avisos` ✅ Tarea 22: los avisos de Administración abiertos de hoy (o de días pasados sin cerrar), para mostrarlos arriba de la pantalla. Se cierran con `cerrar_incidencia` (también están en `incidencias_abiertas()`). Lista vacía si no hay.
- `tarea.aviso` (Tarea 30c 🧪): en «Revisa si toca envío…», los pedidos de cliente que esperan envío: «Hay 2 pedidos de cliente esperando envío a Gipuzkoa» (varios destinos, separados por « · »). `null` si no hay y en las demás tareas.
- `siguiente`: una línea con lo que viene después. Si antes llega una tarea con hora, se anuncia esa con su hora.
- `pregunta`: reservado; hoy siempre `null`. La pregunta «¿Quién sale hoy?» la devuelve `pegar_reparto` (`FALTA_SALE`).
- `elementos` ✅: `[ { id, tipo, producto, formato, texto, categoria, destino, destino_id, bolsa, cantidad, cantidad_hecha, motivo, orden_sugerido, estado } ]`. En bolsas, agrupar por `destino` (una tienda por pantalla) y, dentro de la tienda, por `bolsa`: «Bolsa de reposición» y, si hay pedidos de cliente, «Pedido de cliente · [cliente]» (Tarea 12; en el envío, «Pedido de cliente · [cliente] · [tienda]», Tarea 30c). **Peticiones especiales** (Tarea 13): `tipo: "peticion"`, con su texto en `texto` (y en `producto`), `cantidad` 1 y `formato` vacío; van en la bolsa de su tienda después de las cajas, para mostrarlas bajo «Además, mete:». En los demás elementos, `texto` es `null`. En las listas de producción, `bolsa` es `null`; en los pedidos de cliente, `motivo` dice «Coge N del almacén» o «Haz N».
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
- **Errores:** `DATOS_NO_VALIDOS` (no es 15 ni 30), `SIN_TAREA` (aún no hay bolsas: falta preparar el reparto), `ESTADO_NO_VALIDO` (las bolsas ya están listas o, desde la Tarea 29b 🧪, «El reparto ya ha salido.»: no mueve ninguna hora), `SIN_JORNADA`.

### 3.7 `registrar_evento(id_cliente, tipo, detalle?)` ✅
`llega_mercancia` (recepción, urgente), `pedido_cliente` (botón «Pedido de cliente»), `no_quedan_vapers` (tirada de vapers). Crea la tarea correspondiente en la jornada de hoy; el `detalle` pasa a ser su «por qué». Administración solo puede registrar `pedido_cliente`, que va a la jornada del operario del almacén.
- **Salida:** `{ "evento_id", "tarea": {...}, "tarea_activa": {...} }` (`tarea_activa` solo al operario). Repetir con el mismo `id_cliente` no duplica.
- **Errores:** `DATOS_NO_VALIDOS`, `NO_AUTORIZADO` (Administración con otro tipo), `SIN_JORNADA`.
- **`pedido_cliente`, obsoleto para las pantallas desde la Tarea 12:** el pedido de cliente se registra con `guardar_pedido_cliente` (§3.16). Sigue funcionando.
- Desde la Tarea 7 la pantalla del operario usa `crear_incidencia` (llega mercancía y pedido de cliente crean esta misma tarea por dentro). `registrar_evento` sigue funcionando igual (lo usa Administración para un pedido de cliente).

### 3.8 `pegar_reparto` (función del servidor) — **borrada en la Tarea 29d, por orden del propietario**
> **Ya no existe** (orden del propietario, 04/11/2026, PR #35): estaba obsoleta desde la Tarea 10 y llevaba su propia copia de la regla antigua del envío. El reparto y el envío se preparan con la lista (`catalogo` + `guardar_reparto`, §3.13 y §3.14). Con ella se han quitado `servidor_anotar_sale` y, en `servidor_preparar`, `reparto_hoy` y `recuento_manana_hecho`. Lo que sigue queda solo como historia. La clave de la tarea del operario «Prepara el reparto» se sigue llamando `pegar_reparto` (no es la función).

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

**`crear_incidencia(id_cliente, opcion, descripcion?, quien?, importancia?, tarea_id?, tipo_problema?, compra_id?)`**

| `opcion` | Texto | `quien` por defecto | `importancia` por defecto |
| --- | --- | --- | --- |
| `llega_mercancia` | Llega mercancía | `operario` | `ahora` |
| `pedido_cliente` | Pedido de cliente (**obsoleta desde la Tarea 12**: usar `guardar_pedido_cliente`, §3.16) | `operario` | `hoy` |
| `pedir_comprar` | Hay que pedir o comprar algo | `operario` (la pantalla ofrece cambiarlo a `administracion` para materia prima y packaging, §7) | `hoy` |
| `recogida_nacex` | Recogida en Nacex | `operario` | `hoy` |
| `corregir` | Corregir, limpiar o solucionar algo | `operario` | `ahora` |
| `bloqueado` | Estoy bloqueado | — | — |
| `comprar` ✅ Tarea 22 | Hay que comprar algo. Con `compra_id` (de `compras_lista()`): por internet → tarea «Compra: [nombre]» con `enlace`; en una tienda → tarea «Ve a comprar [nombre] a [sitio]» con la dirección en `porque`; lo pide Administración → sin tarea. Sin `compra_id` («Otra cosa»): `descripcion` obligatoria, sin tarea. | según la forma de compra (`administracion` sin `compra_id`) | `hoy` |
| `varios` ✅ Tarea 22 | Varios: `descripcion`, `quien` e `importancia`. Tarea «[descripción]» si la hace él. | `operario` | `hoy` |

**Desde la Tarea 22 la pantalla ofrece solo `comprar`, `varios` y `bloqueado`**; las demás opciones se siguen aceptando (histórico y compatibilidad).

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

- **Comprar, al hacer su tarea** ✅ Tarea 22: por internet queda «Pedido, esperando a que llegue» (como `pedir_comprar`); en una tienda, se cierra. Errores nuevos: `DATOS_NO_VALIDOS` si el producto ya no está en la lista o si «Otra cosa» va sin `descripcion`.
- **Aviso de Administración** (`opcion: "aviso"`, solo lo crea Administración, §3.21): sin tarea; `estado_texto` «Aviso de Administración para el DD/MM»; el operario lo cierra como las demás.
- **Recogida de un producto atascado** 🧪 Tarea 31 (`opcion: "recogida_atascado"`, la crea la base de datos, §9.23): sin tarea, sin hora y sin tocar el reparto; `descripcion` «Recoge N cajas de Y en [tienda] y llévalo a [tienda]» (o «al almacén», o «al almacén: va en el siguiente envío a [tienda]»); `estado_texto` «Sin hora: cuando puedas, sin tocar el reparto. Ciérrala al entregarlo». La cierra con `cerrar_incidencia` al entregarlo.

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
    "envio":   [ { "id": "...", "codigo": "GIPUZKOA", "nombre": "Gipuzkoa (envío a Rentería)" }, { "id": "...", "codigo": "DURANGO", "nombre": "Durango" } ],
    "pedido":  [ { "id": "...", "codigo": "BILBAO", "nombre": "Bilbao", "va_en": "reparto" }, "…", { "id": "...", "codigo": "DONOSTI", "nombre": "Donosti", "va_en": "envio" } ]
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
- `tiendas.pedido` (Tarea 30c 🧪): las tiendas para «Recoger en tienda» en «Pedido de cliente» (§3.16): las del reparto en su orden y después las que reciben por envío (Donosti y Rentería; Durango cuando abra), con `va_en`. Sale de la configuración de siempre (`destinos_reparto` y `peticiones_por_envio`).
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
- **Envío** (Tarea 12): *hasta la Tarea 29d*, mientras la hoja aún cuenta en el almacén lo que sale con el reparto (hasta el recuento de la mañana hecho después de terminar las bolsas), aparta también las cajas de los pedidos de tienda de hoy, no solo las del reparto (R1c).
  **Desde la Tarea 29d** (R1c v1.58) no se aparta nada: `en_almacen` es la cifra de la hoja tal cual, en el reparto y en el envío.
- **`texto_whatsapp`:** `REPARTO dd/mm` (o `ENVÍO dd/mm`), `SALE: ALMACÉN` / `SALE: YO` (solo reparto), y por cada tienda una línea en blanco, su código en mayúsculas y `Nx PRODUCTO FORMATO`, con los nombres exactos de la hoja; si la tienda tiene peticiones especiales, después de sus productos una línea `Además: rollos de TPV; muestras de V2` (separadas por «; »). Tiendas en el orden de `catalogo` y productos en el de la hoja. La pantalla lo copia **tal cual** con un botón para pegarlo en WhatsApp: no se abrevia nada.
- **Producto sin granel** (Tarea 16, R1e): las referencias del reparto que hay que hacer y no tienen granel van a la producción con `sin_granel` (§3.2). Lo que decida el operario (§3.19) se conserva al modificar el reparto: lo de otra tienda sigue mientras la tienda lo siga pidiendo (como mucho, lo que pide ahora); lo quitado ya está en la línea, porque «Modificar reparto» la abre con la cantidad nueva. Si lo decidido ya no cubre lo que falta, la referencia vuelve a salir sin resolver. `texto_whatsapp` lleva siempre lo decidido.
- **Reintentos:** repetir con el mismo `id_cliente` devuelve lo ya guardado (con su `texto_whatsapp`), sin volver a leer la hoja ni calcular, con `ya_guardado: true` y `aviso: { codigo: "REPARTO_YA_GUARDADO" }`. Cada vez que se pulsa «Guardar» en una lista nueva o modificada, `id_cliente` nuevo.
- **Avisos (no son errores):** `REPARTO_YA_GUARDADO` (reintento con el mismo `id_cliente`). Desde la Tarea 23 no hay `REPARTO_SIN_CAMBIOS`: el mismo reparto con otro `id_cliente` se vuelve a calcular con la hoja de ahora (sustituye al de antes conservando lo hecho y lo decidido en R1e). Para cambiar solo quién sale, `cambiar_quien_sale` (§3.12).
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
  - **Recoger en una tienda que recibe por envío** (Tarea 30c 🧪; Donosti y Rentería en el envío a Gipuzkoa, Durango en el suyo): `destino_id` de `catalogo().tiendas.pedido` con `va_en: "envio"`. Espera al **siguiente envío** a ese destino (si el de hoy ya está guardado y sin preparar, entra en él al momento); no crea un envío por sí solo. Al guardar el envío: tarea «Hay un pedido de cliente para enviar a [tienda] · [cliente]» (con su «coge / haz», como en el reparto) y caja aparte «Pedido de cliente · [cliente] · [tienda]» en «Prepara el envío aprobado». Sale del almacén con el envío preparado. En la tienda, en «Envíos» (los de Donosti, en los de Rentería).
  - **Nacex:** tarea «Prepara el pedido de cliente (Nacex) · [cliente]» con la lista y los datos de envío en `porque`. De lunes a jueves, por la tarde (después de la revisión y la preparación del envío), antes de las 18:10; el viernes, por la mañana, antes de las 10:45, y lo lleva quien sale de reparto. **Activa Nacex ese día** (recuento a las 17:55 y «Salida a Nacex» a las 18:10; el viernes, «Lleva en el reparto lo que va a Nacex…»). Si ya hay envío, es el mismo viaje. Los pedidos de Nacex **entran hasta las 18:00** de lunes a jueves (el viernes, hasta las 10:45) y mientras la salida a Nacex no esté hecha; si no, van al siguiente día de trabajo. Si por la producción no llega a salir ese día, el operario lo pasa al día siguiente (§3.18); si queda sin hacer, pasa solo, como tarea de Nacex de ese día y con Nacex activado.
  - En las dos, **al salir la tarea** (cuando le toca al operario), cada referencia dice en `motivo` **«Coge N del almacén»** o **«Haz N»** (o las dos cosas: «Coge 2 del almacén y haz 1»). Se calcula en ese momento con el **almacén ahora** (la última lectura de la hoja + lo producido − lo salido desde el recuento), menos lo que aún no ha salido y va antes (reparto, envío y pedidos anteriores, R1c). Al guardar el pedido, `motivo` aún es `null`.
- **Salida:** `{ pedido: (objeto pedido, §3.17), tarea: (la de Nacex; null en tienda), tarea_activa: (solo al operario) }`.
- **Reintentos:** repetir con el mismo `id_cliente` devuelve el mismo pedido, sin leer la hoja, con `ya_guardado: true` y `aviso: { codigo: "PEDIDO_YA_GUARDADO" }`.
- **Errores:** `DATOS_NO_VALIDOS` (sin cliente, sin tienda o tienda que no es del reparto, sin datos de envío en Nacex, entrega no válida, cantidades no válidas o lista vacía), `REFERENCIA_NO_EXISTE` (con cuáles), `SIN_JORNADA`, `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` · `CATALOGO_AMBIGUO`, `NO_AUTORIZADO`.

### 3.17 `pedidos_cliente_abiertos()` ✅ (Tarea 12)
Para el panel de Administración y, si se quiere, para el operario.
- **Salida:** `{ total, pedidos: [objeto pedido, ...] }`, por fecha y orden de llegada. Abiertos = esperando al reparto, por preparar, o preparados que salen hoy o más adelante.
- **Objeto pedido:** `{ id, cliente, entrega: "tienda"|"nacex", entrega_texto ("Recoger en Bilbao" | "Envío por Nacex"), destino_id, destino, datos_envio, lineas: [{ producto, formato, cantidad }], fecha, estado: "esperando_reparto"|"por_preparar"|"preparado"|"cancelado", estado_texto, tarea_id, registrado_en, registrado_por, registrado_por_nombre, va_en, pedido_en_tienda, pedido_por }`.
- **Tarea 30c 🧪:** `va_en`: `"reparto"` o `"envio"` (recoger en tienda; `null` en Nacex). `pedido_en_tienda`: si lo apuntó una tienda desde la tableta, cuál («Basauri»); `pedido_por`: quién estaba en el turno. En los de envío, `estado_texto` dice «Va en el próximo envío a Donosti», «En el envío del 16/12: por preparar» o «Preparado: va en el envío del 16/12».
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

### 3.20 Lista de compras ✅ (Tarea 22)
- **`compras_lista()`** (operario y Administración) → `{ compras: [{ id, nombre, forma: "internet"|"tienda"|"administracion", enlace, sitio, direccion, nota, activo, orden }] }`, solo las activas, en su orden. Para el botón Incidencia → «Hay que comprar algo» y para la pantalla «Lista de compras» del panel.
- **`guardar_compra(nombre, forma, id?, enlace?, sitio?, direccion?, nota?, orden?, activo?)`** (solo Administración) → `{ compra }`. Sin `id`, añade (al final si no se da `orden`); con `id`, cambia. **Quitar = `activo: false`** (no se borra, para el histórico). Por internet exige `enlace` (`http…`); en una tienda, `sitio`. **Errores:** `DATOS_NO_VALIDOS`, `NO_ENCONTRADO`, `NO_AUTORIZADO` (el operario).

### 3.21 Avisos para el almacén ✅ (Tarea 22)
- **`crear_aviso_almacen(id_cliente, fecha, texto, contacto?)`** (solo Administración) → `{ aviso: { id, fecha, texto, contacto, estado, creado_por, cerrado_en, nota } }`. Para el operario por defecto, el día `fecha` (hoy o un día que viene en que trabaje el almacén). No crea tarea. Repetir con el mismo `id_cliente` devuelve el mismo. **Errores:** `DATOS_NO_VALIDOS` (sin texto o fecha pasada), `SIN_JORNADA` (ese día no trabaja el almacén), `NO_AUTORIZADO` (el operario).
- **`cancelar_aviso_almacen(aviso_id)`** (Administración) → `{ aviso }`, cerrado con la nota «Cancelado por Administración». Repetir no cambia nada. Desde la Tarea 29 🧪 el operario la usa solo para sus avisos a las tiendas (§9.9).
- El operario lo ve desde su día en `tarea_activa().avisos` y en `incidencias_abiertas()`, y lo cierra con `cerrar_incidencia`. Consta en el cierre del turno (sin el contacto, que solo está en la base de datos).

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
| `decision_conflicto` | si hay conflicto | Para la tarea nueva (Tarea 29 🧪): `{ "accion": "nueva_manana" }`, `{ "accion": "nueva_despues" }` o `{ "accion": "no_crear" }`. Para mover otra: `{ "cede": "<tarea_id>", "accion": "despues|manana|cancelar" }` (solo las de `se_puede_mover: true`) |

- **No urgente y sin hora límite** ✅ Tarea 23: no sale mientras falte lo primero de la mañana (revisión inicial, «Prepara el reparto», la producción del reparto, las bolsas y la preparación del envío del viernes, las que haya), por la regla general de `tarea_activa` (§3.2), que vale para todas las tareas, no solo las de Administración. Las urgentes y las que tienen hora límite, como siempre.
- **Ventana** (`PLAN_TECNICO.md` §2.4): desde ahora (o el inicio del día elegido) hasta la hora de `antes_de` o, si no hay hora, hasta el final del turno en que empieza.
- Solo hay conflicto si **no cabe y alguna obligatoria que vence en la ventana queda en riesgo** (§6.4). Las que **ya vencieron** sin hacerse no están en riesgo (ya llegan tarde), pero **su duración cuenta** como tiempo ocupado (`vencidas_min`). Si no cabe pero no hay ninguna obligatoria en riesgo, **se crea** y el `encaje` lo avisa («No le da tiempo entera (faltan unos N min): lo que no termine pasa al día siguiente»), con `minutos_que_faltan`.
- **Sin falsa alarma** (Tarea 29 🧪, §6.4, 03/11/2026): una tarea **no urgente y sin hora límite** no da conflicto (espera a lo primero de la mañana, que va siempre antes): se crea y el `encaje` lo dice. El conflicto queda para las urgentes y las que tienen hora límite.
- Con conflicto, no la crea y devuelve `CONFLICTO` con `conflicto: { disponible_min, necesario_min, vencidas_min, minutos_que_faltan, obligatorias_en_riesgo: [{ tarea_id, titulo, vence, duracion_min, se_puede_mover }] }`. **`se_puede_mover`** (Tarea 29 🧪): `false` en lo que sale hoy del almacén, al reparto o a Nacex (producción del reparto, bolsas, salida, preparación del envío, pedidos de cliente para la tienda y por Nacex, «Lleva en el reparto lo que va a Nacex» y la salida a Nacex: el envío a Nacex es tan prioritario como el reparto), que **nunca se pasan a mañana, se dejan para después ni se cancelan**; con ellas, `DATOS_NO_VALIDOS` («… es del reparto o del envío de hoy…»). **La ventana pregunta primero por la tarea nueva** (§6.4) y, aparte, deja mover una de las que tienen `se_puede_mover: true`, diciendo cuál. Administración repite la llamada con `decision_conflicto`:
  - `nueva_manana` (Tarea 29 🧪): la tarea nueva se crea para **el siguiente día de trabajo** de esa persona, igual (urgente y con su hora límite a la misma hora, si las tenía); `decision.fecha` dice el día. Si no tiene ninguno en las dos semanas siguientes, `SIN_JORNADA`.
  - `nueva_despues` (Tarea 29 🧪): la tarea nueva se crea hoy **sin hora límite ni urgencia**: sale después de lo que está en riesgo.
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
Inicio del móvil. Solo lee (no genera nada). **Salida:** `{ ahora, fecha, operario, jornada: { id, sale, hay_envio, estado }, en_curso: tarea con sus elementos, reparto_de_hoy, problemas_abiertos: [...], incidencia_en_curso, incidencias_abiertas: [objeto incidencia, §3.11], arrastradas: [...], hoy: [{ id, titulo, estado, origen, obligatoria, urgente, hora, motivo, iniciada_en, terminada_en, minutos, interrupciones, cajas, minutos_trabajados, hecha_por }], retrasos_salida: [{ a_las, minutos, nueva_hora, sale, aviso }], correos_no_enviados: [{ tipo, asunto, estado: "fallido"|"dudoso", intentos, error, creado_en }], lectura_sheets: { ultima_correcta, ultimo_error } }`. `correos_no_enviados` = cierres o avisos de los últimos 7 días que no se han podido enviar (mostrarlos como aviso). `reparto_de_hoy` ✅ Tarea 9: el reparto aceptado hoy en la jornada del operario por defecto, el mismo objeto que en `tarea_activa` (`null` → «Preparar reparto»; si no, «Modificar reparto»).
- **`hoy`: `hecha_por`** ✅ Tarea 24: el nombre de quien cerró la tarea (la persona del registro «tarea_terminada»; en «Prepara el reparto», quien guardó el reparto). `null` si no está hecha.
- **`hoy`, orden** ✅ Tarea 23: primero lo hecho y lo que está en curso, por cuándo empezó (`iniciada_en`); después lo demás (pendiente, bloqueada, cancelada…), por su hora y su orden, como antes.
- **`hoy`**: `iniciada_en` y `terminada_en` (fecha y hora) y `minutos` ✅ Tarea 15: de inicio a fin; hasta ahora si está en curso; `null` si no ha empezado.
- **`hoy`**: `interrupciones: [{ a_las, por, siguio_a_las }]`, `cajas: { hechas, total }` y `minutos_trabajados` ✅ Tarea 21. `interrupciones`: cada vez que otra tarea (con hora o urgente) entró en un punto de encaje, en orden; `por` = título de la tarea que entró (o «Fin del turno» si se pausó sola al acabar el turno, Tarea 24); `siguio_a_las` = cuando volvió a estar en curso (`null` si aún no). Vacía si no hubo. `cajas` y `minutos_trabajados` solo en las tareas de producción (las que tienen referencias que producir; en las demás, `null`): cajas hechas de las totales, y el tiempo que la tarea ha estado en marcha: de cada vez que empieza o se retoma hasta que entra otra tarea o se termina (si está en curso, hasta ahora). Cuenta también el tiempo entre productos; no cuenta lo que estuvo interrumpida (la salida y la ruta).
- **`avisos_almacen`** ✅ Tarea 22: `[{ id, fecha, texto, contacto, estado, creado_por, cerrado_en, nota }]`, los avisos para el almacén que siguen abiertos (de hoy y de días que vienen), por fecha. Para verlos y cancelarlos (`cancelar_aviso_almacen`). `incidencias_abiertas` solo trae los avisos desde su día.
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
| `motor.auditoria()` · `motor.huella_estructura()` ✅ (Tarea 19) | El coordinador, con el conector (`postgres`); también `service_role`. Nadie con sesión | Solo leen. La auditoría: migraciones, huella de la estructura, RLS, permisos de las funciones, disparadores, tareas programadas, configuración, últimos datos y `avisos` (ver `docs/AUDITORIA.md`). La huella es la de la prueba 00. |
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

### 7.1 Conexión (pruebas y producción)
| Dato | Pruebas (`osasun-pruebas`) | Producción (`osasun-produccion`) |
| --- | --- | --- |
| URL del proyecto | `https://rvypswuoafnjwqdwxjvo.supabase.co` | `https://iqjkysfbtpkukkvfyumf.supabase.co` |
| Clave pública (*publishable*) | `sb_publishable_IKa8qY4SO04BeRe0WWhy-Q_nE2OIwQg` | `sb_publishable_32yrYIfaB8FT6PFMyIw3nQ_u6sJHjVu` |

La clave pública no es secreta: no da permisos por sí sola; los da la sesión de cada persona. Las dos bases tienen las mismas funciones (`CONTRATOS.md` entero vale para las dos); en producción solo entra lo ya probado en pruebas y fusionado en `main` (`AUDITORIA.md` §5). Se cambia de una a otra solo con la URL y la clave:
```js
import { createClient } from '@supabase/supabase-js'
// Pruebas
export const supabase = createClient('https://rvypswuoafnjwqdwxjvo.supabase.co', 'sb_publishable_IKa8qY4SO04BeRe0WWhy-Q_nE2OIwQg')
// Producción
// export const supabase = createClient('https://iqjkysfbtpkukkvfyumf.supabase.co', 'sb_publishable_32yrYIfaB8FT6PFMyIw3nQ_u6sJHjVu')
```
En producción, las cuentas autorizadas entran con Google igual que en pruebas; su ficha se crea sola la primera vez (§7.2).

### 7.2 Iniciar sesión (solo Google)
- Un único botón «Entrar con Google». No hay registro ni contraseña.
```js
await supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } })
```
- Al volver, la sesión se recoge sola (`supabase.auth.onAuthStateChange`). Después, siempre `supabase.rpc('mi_perfil')` y, según `rol`, la pantalla del operario o la de Administración.
- **Cuenta no autorizada:** Google vuelve a la app con `error_description` en la dirección («Esta cuenta no tiene acceso a Osasun Operations. Pide acceso a Administración.»). Se muestra tal cual, con el botón de entrar.
- Si `mi_perfil` devuelve `NO_AUTORIZADO` (usuario sin ficha): mostrar el mensaje y un botón «Salir» (`supabase.auth.signOut()`).
- Direcciones de vuelta permitidas en pruebas: las previsualizaciones de Lovable (`*.lovable.app`, `*.lovableproject.com`). Otra dirección se pide al coordinador.
- En producción, la Site URL y las direcciones de vuelta las pone el propietario en el panel de Auth de producción (la dirección publicada de la app). Hasta entonces, entrar con Google en producción no funciona.

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

## 9. Tiendas (Tareas 27 y 28) 🧪

La tableta de las tiendas (`AGENTE_BASE_DE_DATOS.md` Tareas 27 y 28; `ESTADO_DEL_SISTEMA.md` E2-8). Solo en pruebas: pasa a producción cuando el propietario lo apruebe (no al fusionar). La segunda parte (Tarea 28) va de §9.11 a §9.18.

**Cómo funciona:**
- **Una cuenta de Google por tienda** (cuentas autorizadas con `rol: "tienda"` y su tienda; la ficha se crea sola la primera vez, §7.2). `mi_perfil()` devuelve `rol: "tienda"` y `centro: { id, nombre }` de la tienda; con ese rol la pantalla abre la tableta. Durango está inactiva: no tiene cuenta ni tareas.
- **Lo que ve una tienda:** solo lo suyo. Las funciones del almacén (`tarea_activa`, `crear_incidencia`, `catalogo`, `guardar_reparto`…) y las de Administración le responden `NO_AUTORIZADO`, y la base de datos no le deja leer nada de Administración ni de otras tiendas.
- **Horario de cada tienda** (se configura por tienda; hoy): de lunes a viernes, 11:00–13:30 y 17:00–20:30 (Bilbao, tarde 16:30–20:30); sábado, igual, pero cierran a las 19:30, salvo Bilbao (20:30); Donosti y Rentería, el sábado por la tarde cerrado; domingo, nada. Un **día cerrado** (§9.9) no tiene lista.
- **Tareas activadas por tienda.** Las propias tienen todas; las franquicias (Donosti y Rentería), solo los avisos y el vídeo de la semana.

### 9.1 `tienda_hoy()` 🧪
Todo lo de la tableta para hoy, de una vez. Si la jornada de hoy no existe, la crea (como `tarea_activa`). `empezar_turno`, `marcar_punto`, `terminar_tarea_tienda`, `compartir_video` y `marcar_aviso_leido` devuelven también esto, ya actualizado: pintarlo directamente.
- **En directo:** suscribirse a `tareas` y `tarea_elementos` sin filtro (la tienda solo recibe lo suyo, §7.4) y volver a pedir `tienda_hoy()`; además, refrescar cada minuto y al volver a la pestaña.
- **Salida:**
```json
{
  "tienda": { "id": "…", "codigo": "BILBAO", "nombre": "Bilbao" },
  "fecha": "2026-11-02", "ahora": "16:25",
  "abierta_hoy": true, "cerrado": false,
  "horario": [ { "turno": "manana", "inicio": "11:00", "fin": "13:30" }, { "turno": "tarde", "inicio": "16:30", "fin": "20:30" } ],
  "turno": "tarde",
  "en_turno": { "persona_id": "…", "nombre": "…", "turno": "tarde", "desde": "16:21" },
  "personas": [ { "id": "…", "nombre": "…", "cuando": "siempre", "turno": "tarde", "sugerida": true } ],
  "avisos": [ { "id": "…", "texto": "…", "fecha": "2026-11-02" } ],
  "tareas": [ /* objeto tarea de la tienda, §9.2 */ ]
}
```
- `abierta_hoy: false` → hoy no abre (domingo o día cerrado; `cerrado: true` si lo ha marcado Administración): mostrar «Hoy la tienda está cerrada» y nada más.
- `turno`: `manana`, `tarde` o `null` (fuera de los dos; cuenta desde 1 hora antes de empezar hasta media hora después de acabar).
- `en_turno`: quién está ahora (el último nombre elegido hoy); `null` si nadie ha empezado. **Si es `null`, o su `turno` no es el `turno` de ahora, la pantalla pide primero «¿Quién eres?»** con `personas` y llama a `empezar_turno`.
- `personas`: los nombres de la tienda; primero los que trabajan hoy y en ese turno (`sugerida: true`). Se pueden elegir todos.
- `avisos`: los avisos de Administración sin leer (los de hoy y los de días anteriores que no se leyeron). **Se enseñan al entrar** (antes de la lista); cada uno con «Leído» (`marcar_aviso_leido`). Desde la Tarea 29 cada uno trae **`de`**: «Almacén» o «Administración» (mostrarlo: «Aviso del almacén»).
- `tareas`: la lista del día, por hora.
- **Tarea 28:** `reparto` (por dónde va, §9.13), `peticiones` (muestras y material, §9.15) y `pedir_material` (si la tienda puede pedir material, §9.15).
- **Tarea 30:** `incidencias` y `opciones_incidencia` (§9.20).
- **Tarea 30b:** `envios` y `envios_sin_confirmar` (§9.21).
- **Tarea 30c:** `pedidos` (§9.22).
- **Tarea 31:** `atascados`, `ofertas_atascados`, `atascados_pedidos` y `promociones` (§9.23).

### 9.2 Objeto tarea de la tienda 🧪
```json
{
  "id": "…", "clave": "apertura_manana", "titulo": "Apertura de la mañana", "porque": "…",
  "tipo": "puntos", "hora": "10:50", "desde": "2026-11-02T09:50:00Z",
  "estado": "pendiente", "se_puede_marcar": true, "no_hecha": false, "motivo": null,
  "terminada_en": null, "hora_fin": null, "hecha_por": null,
  "puntos": [ { "id": "…", "texto": "Fichar en Woffu", "hecho": false, "hecho_por": null, "a_las": null } ],
  "video": null
}
```
- **`tipo`:** `puntos` (se hace tocando sus puntos uno a uno, §9.4; con el último queda hecha), `simple` («Hecho», §9.5) o `video` (§9.6).
- **Tarea 28:** `tipo` también `reposicion` (§9.12) y `muestras` (§9.15). Cada punto trae además `pide` (`null`, `"efectivo"` o `"cierre_caja"`), `efectivo_esperado` (solo en el del efectivo) y `datos` (lo apuntado). La tarea trae `bolsa` («Recibe la bolsa» y la reposición, §9.11) y `muestras` («Revisa las muestras»); en las demás, `null`.
- **`hora`:** orientativa. Antes de esa hora, `se_puede_marcar: false` (mostrarla en gris con «desde las 10:50»). No hay avisos de retraso.
- **`estado`:** `pendiente`, `hecha` o `cancelada` (el vídeo con «Hoy no he podido», o la tienda cerrada ese día: `motivo`). `hecha_por` y `hora_fin` dicen quién y a qué hora; cada punto, igual (`hecho_por`, `a_las`).
- **`no_hecha: true`:** la tienda ya ha cerrado y quedó sin hacer. Queda así; **no pasa al día siguiente**.
- **`video`** (solo en `tipo: video`, cuando ya se ha hecho): `{ enlace, aprendido, no_pudo }`.
- **Las tareas** (decididas por el propietario; el horario de cada tienda manda):

| Tarea | Días | Desde | Puntos |
| --- | --- | --- | --- |
| Apertura de la mañana | L–S | 10 min antes de abrir (10:50) | Fichar en Woffu · Abrir · Cartelería · Glovo · Barrido y puesta a punto |
| Cierre de la mañana | L–S | 10 min antes de cerrar (13:20) | Ventas y stock de la plantilla al día (todo en verde) · Incidencias del turno registradas |
| Apertura de la tarde | L–S, si hay tarde | 10 min antes (16:50; Bilbao 16:20) | Fichar · Abrir · Cartelería · Glovo |
| Cierre del día | L–S | 10 min antes del cierre del día | Ventas del día en la plantilla (todo en verde) · Suelo fregado · **Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo** (Tarea 28, §9.14) · Efectivo contado y en la bolsa para mañana · Incidencias de la tarde registradas |
| Limpieza de cristales | jueves, tarde | al abrir la tarde | — («Hecho») |
| Vídeo de la semana | viernes, mañana (y el sábado, §9.6) | al abrir la mañana | — (enlace y una línea) |
| Recibe la bolsa del reparto (Tarea 28) | cuando sale el reparto, si trae bolsa para la tienda | la hora de salida | Bolsa recibida · Bolsa de ayer entregada con X € en efectivo (§9.11) |
| Coloca y apunta la reposición (Tarea 28) | al terminar «Recibe la bolsa» | en ese momento | — (§9.12) |
| Revisa las muestras (Tarea 28) | jueves, mañana | al abrir la mañana | — (§9.15) |
| Revisa los productos atascados (Tarea 31) | martes, mañana | al abrir la mañana | — (§9.23) |

  En **Bilbao** las semanales (cristales, vídeo, muestras y atascados) cambian de turno cada semana: semana ISO **par**, por la mañana; **impar**, por la tarde. Donosti y Rentería: el vídeo, las muestras y los atascados.

### 9.3 `empezar_turno(persona_id)` 🧪
Al empezar el turno, la persona toca su nombre (de `tienda_hoy().personas`). Desde ese momento es quien está (`en_turno`) y lo que se marque queda a su nombre. Se puede cambiar en cualquier momento (otra persona entra): vuelve a llamarse con el otro nombre.
- **Salida:** `tienda_hoy()` actualizado.
- **Errores:** `SIN_JORNADA` («Hoy la tienda no abre.»), `NO_ENCONTRADO` (el nombre no es de esta tienda o se ha quitado).
- El **sábado**, si a esa persona aún no le ha salido el vídeo esa semana, le aparece en la lista (§9.6).

### 9.4 `marcar_punto(elemento_id)` 🧪
Tocar un punto de una tarea `puntos` (`tareas[].puntos[].id`). Con el último, la tarea queda `hecha`. Tocar uno ya hecho no hace nada (devuelve lo mismo).
- **Salida:** `tienda_hoy()` actualizado.
- **Errores:** `NO_ENCONTRADO`, `ESTADO_NO_VALIDO` (la tarea ya está cerrada), `TODAVIA_NO` («Esta tarea es desde las 16:50.»), `SIN_PERSONA` («Elige primero quién está en la tienda.»: pedir el nombre y repetir).

### 9.5 `terminar_tarea_tienda(tarea_id)` 🧪
«Hecho» de una tarea `simple` (la limpieza de cristales). **Salida** y **errores**: como §9.4.

### 9.6 Vídeo de la semana: `compartir_video(tarea_id, enlace?, aprendido?, no_he_podido?)` · `videos_semana(limite?)` 🧪
- **El texto** de la tarea (`porque`) es el aprobado por el propietario; se muestra entero.
- **Compartir:** `compartir_video({ tarea_id, enlace, aprendido })`: `enlace` de YouTube (`youtube.com/watch?v=…`, `youtu.be/…`, `shorts/…`) y `aprendido`, una línea (200 letras como máximo). La tarea queda `hecha` y el vídeo entra en la lista.
- **«Hoy no he podido»:** `compartir_video({ tarea_id, no_he_podido: true })`. La tarea queda `cancelada` (no hecha) y no pasa al día siguiente.
- **Un vídeo por persona y semana** (la que está en `en_turno`): si ya compartió uno esa semana, `YA_COMPARTIDO`. **El sábado** le sale a quien trabaje si esa semana no ha compartido ni ha dicho «Hoy no he podido».
- **Errores:** los de §9.4, más `DATOS_NO_VALIDOS` (falta el enlace, no es de YouTube o falta la línea) y `YA_COMPARTIDO`.
- **`videos_semana(limite?)`** (tiendas y Administración; 50 por defecto, 200 como máximo): `{ videos: [{ id, enlace, aprendido, tienda, persona, fecha }] }`, los más nuevos primero. La lista la ven todas las tiendas. Los «Hoy no he podido» no salen.

### 9.7 Avisos de Administración en la tienda: `marcar_aviso_leido(aviso_id)` 🧪
Cierra el aviso (`tienda_hoy().avisos[].id`) y anota quién lo leyó (el de `en_turno`). Leerlo dos veces no hace nada. **Salida:** `tienda_hoy()` actualizado. **Error:** `NO_ENCONTRADO`.

### 9.8 Administración: personas de las tiendas · `personas_tienda(tienda_id?)` · `guardar_persona_tienda(nombre, tienda_id?, id?, cuando?, turno?, activo?)` 🧪
- **`personas_tienda(tienda_id?)`:** `{ personas: [{ id, tienda_id, tienda, nombre, cuando, turno, activo }] }`, por tienda y nombre; sin `tienda_id`, las de todas. (Una tienda también puede llamarla: solo ve las suyas.)
- **`guardar_persona_tienda`** (solo Administración):
  - **Añadir:** sin `id`, con `nombre` (40 letras como máximo) y `tienda_id`.
  - **Cambiar:** con `id` y los datos nuevos (el `nombre` siempre).
  - **Quitar:** con `id`, `nombre` y `activo: false`. Deja de salir en la tienda; lo que hizo sigue a su nombre.
  - `cuando`: `siempre` (por defecto), `entre_semana` o `sabados`. `turno`: `manana`, `tarde` o `null` (los dos). Solo sirven para poner su nombre el primero en la tienda (`sugerida`).
  - **Salida:** `{ persona: { … } }`. **Errores:** `NO_ENCONTRADO`, `DATOS_NO_VALIDOS` («Elige la tienda.», el nombre, `cuando` o `turno` no válidos).
- `tienda_id` de cada tienda: el de `personas_tienda()`.

### 9.9 Administración: días cerrados y avisos a las tiendas 🧪
- **`marcar_dia_cerrado(fecha, tienda_id?, cerrado?, motivo?)`:** festivos y cierres. Sin `tienda_id`, **todas las tiendas**. `cerrado: false` lo quita. Ese día la tienda no tiene lista; si la lista ya estaba hecha (el mismo día), lo pendiente queda `cancelada` con el motivo «Tienda cerrada ese día» (y vuelve si se quita).
  - **Salida:** `{ dias: [{ fecha, tienda_id, tienda, motivo }] }`, de hoy a un año («Todas las tiendas» cuando `tienda_id` es `null`).
  - **Errores:** `FECHA_PASADA` («Elige hoy o un día que viene.»), `DATOS_NO_VALIDOS`.
- **`dias_cerrados(desde?, hasta?)`:** la misma lista (por defecto, de hoy a un año).
- **`crear_aviso_tienda(id_cliente, fecha, texto, tienda_id?)`:** un aviso para una tienda o, sin `tienda_id`, para todas, para ese día (hoy o uno que viene). A la tienda le sale al entrar (§9.1). Repetir con el mismo `id_cliente` no lo duplica. **Desde la Tarea 29 también el operario** (en el almacén: «Aviso a una tienda», para que metan algo en una bolsa, preparen algo…): solo mandar; la tienda se elige con `tiendas()` (§9.19).
  - **Salida:** `{ avisos: [aviso], sin_aviso: [{ tienda, motivo }] }`. `sin_aviso`: las tiendas que no lo reciben («Todavía no ha entrado con su cuenta» o «Ese día no abre»).
  - **Errores:** `DATOS_NO_VALIDOS` (falta el texto, fecha pasada, tienda no válida), `SIN_JORNADA` (para una sola tienda que no puede recibirlo; `error.sin_aviso` dice por qué).
- **`avisos_tiendas()`:** `{ avisos: [{ id, fecha, texto, tienda_id, tienda, estado, leido, cerrado_en, nota, creado_por, de }] }`, de la última semana y los que vienen, los más nuevos primero. `nota` dice quién lo leyó («Leído por …»); `creado_por`, el nombre de quien lo mandó, y `de` (Tarea 29), «Almacén» o «Administración». Administración los ve todos; **el operario, solo los que ha mandado él** (Tarea 29 🧪).
- **Cancelar un aviso:** `cancelar_aviso_almacen(aviso_id)` (§3.21), la misma de los avisos del almacén. Administración, todos (también los que manda el almacén). **El operario, solo los suyos a las tiendas** (Tarea 29 🧪), con la nota «Cancelado por el almacén»; uno que no ha mandado él da `NO_AUTORIZADO` («Solo puedes cancelar los avisos a las tiendas que has mandado tú.»).

### 9.10 Errores nuevos 🧪
| Código | Qué hace la pantalla |
| --- | --- |
| `TODAVIA_NO` | Mostrar el mensaje («Esta tarea es desde las …»). Con `se_puede_marcar` no debería salir. |
| `SIN_PERSONA` | Pedir «¿Quién eres?» (`personas`), llamar a `empezar_turno` y repetir lo que se iba a marcar. |
| `YA_COMPARTIDO` | Mostrar el mensaje; ofrecer «Hoy no he podido» o dejarlo. |
| `FECHA_PASADA` | Mostrar junto a la fecha y dejar corregir. |
| `SIN_JORNADA` | En la tienda: «Hoy la tienda no abre.». En `crear_aviso_tienda`: mostrar el mensaje. |

### 9.11 «Recibe la bolsa del reparto» 🧪 (Tarea 28)
Sale sola en `tienda_hoy().tareas` **cuando sale el reparto**, en las tiendas que llevan algo en él (productos, peticiones o pedidos de cliente). Las franquicias no la tienen. Una al día.
- **Cuándo sale el reparto** (sin que quien reparte haga nada nuevo): si sale el operario, cuando empieza su «Salida del reparto»; si sale Administración, a la hora de salida (10:45, o la retrasada) con las bolsas listas.
- `hora` = la hora de salida; `porque` empieza por «El reparto ha salido a las HH:MM.».
- **La pantalla de «Recibe la bolsa» no enseña la lista** de lo que trae (propietario, 03/11/2026; `ESTADO_DEL_SISTEMA.md` E2-8): solo los dos puntos de abajo. La lista sale en «Coloca y apunta la reposición» (§9.12). `bolsa` viene igual en las dos tareas; aquí no se muestra.
- **`bolsa`** (en esta tarea y en la de reposición): lo que trae la bolsa, para ver si falta algo. Desde la Tarea 29 🧪 (propietario, 03/11/2026) es **lo que el operario ha marcado como metido en la bolsa** de esa tienda (cajas, peticiones y pedidos de cliente); lo que no se ha marcado no aparece:
```json
{
  "reparto_id": "…", "fecha": "2026-12-18", "salida": "10:50", "recibida_a_las": null, "recibida_por": null,
  "efectivo": { "esperado": 85.50, "de_fecha": "2026-12-17", "entregado": null, "motivo": null },
  "productos": [ { "clave": "producto:V2|4g", "producto": "V2", "formato": "4g", "cantidad": 3 } ],
  "peticiones": [ { "clave": "peticion:Muestra: V2 x2", "texto": "Muestra: V2 x2" } ],
  "pedidos": [ { "clave": "pedido:…", "pedido_id": "…", "cliente": "…", "lineas": [ { "producto": "BZ1", "formato": "4g", "cantidad": 1 } ] } ],
  "reposicion": null
}
```
  Desde la Tarea 29 ya no trae `de` (lo que viene de otra tienda no va en la bolsa del almacén).
- **Dos puntos** (`puntos`):
  1. **«Bolsa recibida»**: un toque con `marcar_punto`. La bolsa consta como recibida a esa hora, por quien está (`recibida_a_las`, `recibida_por`), y las demás tiendas lo ven (§9.13).
  2. **«Bolsa de ayer entregada con X € en efectivo»** (`pide: "efectivo"`, `efectivo_esperado: X`): X es el efectivo del último cierre de caja de la tienda (§9.14).
     - **Un toque** (`marcar_punto`) = entrega X.
     - **Otra cantidad:** `entregar_efectivo({ elemento_id, cantidad, motivo })`, con el porqué (por ejemplo, «Monedas para cambio»). Sin porqué: `MOTIVO_OBLIGATORIO`.
     - **Sin cierre anterior** (`efectivo_esperado: null`, texto «Bolsa de ayer entregada: di cuánto efectivo»): hay que decir la cantidad; un toque responde `FALTAN_DATOS` con `pide: "efectivo"`.
- Con los dos puntos, la tarea queda hecha y sale «Coloca y apunta la reposición».
- **`entregar_efectivo(elemento_id, cantidad?, motivo?)`:** euros con dos decimales como máximo; `motivo`, una línea (200 letras). **Salida:** `tienda_hoy()` actualizado. **Errores:** `NO_ENCONTRADO`, `TODAVIA_NO`, `SIN_PERSONA`, `ESTADO_NO_VALIDO`, `FALTAN_DATOS`, `MOTIVO_OBLIGATORIO`, `DATOS_NO_VALIDOS`.

### 9.12 «Coloca y apunta la reposición» · `apuntar_reposicion(tarea_id, faltan?, nota?)` 🧪 (Tarea 28)
Sale al terminar «Recibe la bolsa» (`tipo: "reposicion"`), con la misma `bolsa` (lo que tenía que llegar).
- **«Reposición metida, todo bien»:** `apuntar_reposicion({ tarea_id })`.
- **«Falta algo»:** `apuntar_reposicion({ tarea_id, faltan: [{ clave, cantidad? }], nota? })`, eligiendo de la lista (`clave` de `bolsa.productos`, `bolsa.peticiones` o `bolsa.pedidos`) y cuántas (de 1 a lo que traía; sin `cantidad`, todas). `nota`, una línea (200 letras).
  - Llega a **Administración como incidencia abierta** (§9.17, `incidencias_tiendas`), que la cierra al resolverla. **A Eder no le sale nada.**
- En los dos casos la tarea queda hecha y `bolsa.reposicion` dice `{ resultado: "bien" | "falta", a_las, por, faltan, incidencia_id }`.
- **Salida:** `tienda_hoy()` actualizado. **Errores:** `NO_ENCONTRADO`, `ESTADO_NO_VALIDO` (ya apuntada), `SIN_PERSONA`, `DATOS_NO_VALIDOS` («Elige de la lista lo que falta.», cantidad fuera de rango, repetida).

### 9.13 Por dónde va el reparto: `tienda_hoy().reparto` 🧪 (Tarea 28)
`null` si hoy la tienda no tiene parada en el reparto. Si la tiene:
```json
{
  "salido": true, "salida": "10:50",
  "texto": "Ha pasado por Basauri a las 11:20 (parada 2 de 3)",
  "paradas": [ { "tienda_id": "…", "tienda": "Bilbao", "parada": 1, "pasado_a_las": null },
               { "tienda_id": "…", "tienda": "Basauri", "parada": 2, "pasado_a_las": "11:20" } ],
  "total": 3, "tu_parada": 3,
  "ultima": { "tienda": "Basauri", "a_las": "11:20", "parada": 2 }
}
```
- Antes de salir: `salido: false` y `texto: null`. Al salir: «Ha salido a las HH:MM». Cada vez que una tienda marca «Bolsa recibida»: «Ha pasado por [tienda] a las HH:MM (parada N de M)». Mostrar `texto` tal cual.
- Las paradas van en el orden del reparto (BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU), solo las que llevan algo ese día.

### 9.14 Cierre de caja: `cerrar_caja(elemento_id, z, ventas, efectivo?, glovo?)` 🧪 (Tarea 28)
En el «Cierre del día», el punto «Cierre de caja en la app: Z, nº de ventas, efectivo y Glovo» trae `pide: "cierre_caja"`. No se marca con un toque (`FALTAN_DATOS`, `pide: "cierre_caja"`): se apunta con `cerrar_caja`.
- `z`, `efectivo` y `glovo` en euros (dos decimales como máximo; Glovo 0 si no hay); `ventas`, el número de ventas (entero).
- Se guarda por tienda y día; **el efectivo es la X de la bolsa del día siguiente** (§9.11). Se puede corregir (volver a llamar) mientras el «Cierre del día» siga abierto. El punto queda hecho, con sus datos en `datos`.
- **Salida:** `tienda_hoy()` actualizado. **Errores:** `NO_ENCONTRADO`, `TODAVIA_NO`, `SIN_PERSONA`, `ESTADO_NO_VALIDO`, `DATOS_NO_VALIDOS`.
- **Cierre corto de las franquicias** (Tarea 30b 🧪, Donosti y Rentería): tarea **«Cierre de caja»** (`clave: "cierre_caja"`) 10 minutos antes de cerrar (20:20 entre semana; 13:20 el sábado, que no abren por la tarde), con un solo punto «Cierre de caja en la app: Z y nº de ventas», `pide: "cierre_caja_corto"`. Un toque da `FALTAN_DATOS` con `pide: "cierre_caja_corto"`. Se apunta con **`cerrar_caja({ elemento_id, z, ventas })`**: sin efectivo ni Glovo (si llegan, no se guardan). En `cierres_caja()` salen con `efectivo` y `glovo` a `null`. Las propias (Durango incluida) siguen pidiendo los cuatro.

### 9.15 Muestras y material: `productos_tienda()` · `revisar_muestras(tarea_id, muestras?)` · `pedir_material(id_cliente, texto)` 🧪 (Tarea 28)
- **«Revisa las muestras»** (`tipo: "muestras"`): jueves por la mañana (en Bilbao alterna por semanas, como las demás semanales); también en Donosti y Rentería. Comprobar que están en buen estado y elegir qué hay que traer nuevo.
  - **Las muestras se piden por producto, sin formato** (son de ~1 g; decisión del propietario, 03/11/2026).
  - **`productos_tienda()`:** `{ productos: [{ clave, producto, categoria, formatos }], leidos_en }` (`formatos`, Tarea 30c: los de la hoja, `[""]` si no tiene; las muestras no lo usan), cada producto una vez, de la última lectura de la hoja (la del último reparto, envío o lista de stock), en el orden de la hoja.
  - **Elegir:** tocar el producto = 1; con − y + se cambia la cantidad (de 1 a 99).
  - **`revisar_muestras({ tarea_id, muestras: [{ producto, cantidad? }] })`**: sin `cantidad`, 1. Lista vacía = están bien y no hace falta nada. La tarea queda hecha; lo elegido sale en `muestras` de la tarea (`{ producto, formato: "", cantidad, estado }`).
  - En la casilla del reparto llega como «Muestra: V2» o, con más de una, «Muestra: V2 x2».
- **Pedir material de tienda** (bolsas, rollos de TPV…), en cualquier momento: **`pedir_material({ id_cliente, texto })`** (80 letras). Solo si `tienda_hoy().pedir_material` es `true` (en esta tarea, no en las franquicias). Hay que haber elegido quién está (`SIN_PERSONA`).
- **`tienda_hoy().peticiones`:** las muestras y el material de la tienda (pendientes y los de la última semana): `[{ id, tipo: "muestra" | "material" | "atascado", detalle, texto, estado, estado_texto, pedida_por, fecha, a_las }]` (`"atascado"`, Tarea 31: lo que ha pedido a otra tienda y le llega por envío, §9.23). Mostrar `estado_texto`: «Pendiente: irá en el siguiente reparto» (o «envío»), «Va en el reparto de hoy / de mañana / del 18/12» o «No va: [motivo]».
- **Salida** (`revisar_muestras`, `pedir_material`): `tienda_hoy()` actualizado. **Errores:** `NO_ENCONTRADO`, `TODAVIA_NO`, `SIN_PERSONA`, `ESTADO_NO_VALIDO`, `SIN_JORNADA`, `NO_AUTORIZADO` (material en una franquicia), `DATOS_NO_VALIDOS` (producto que no está en la lista, cantidad, producto repetido, texto).

### 9.16 «Preparar reparto» y «Preparar envío»: `peticiones_tiendas_pendientes(tipo?)` 🧪 (Tarea 28)
Para la pantalla que ya existe (operario y Administración). Las muestras y el material de las tiendas van en su **siguiente reparto o envío como peticiones especiales** (R1d), ya puestos:
- Al abrir «Preparar reparto» (`tipo: "reparto"`, por defecto) o «Preparar envío» (`"envio"`), llamar a `peticiones_tiendas_pendientes(tipo)`: `{ peticiones: [{ id, destino_id, destino, tienda_id, tienda, tipo, texto, detalle, pedida_por, creada_en }] }`.
- **Poner cada `texto` como una línea más en la casilla «Peticiones especiales para [destino]» de su `destino_id`.** Las de Donosti y Rentería van en la casilla de **Gipuzkoa** (envío), con el nombre de la tienda delante («Donosti · Muestra: BZ1»). Desde la Tarea 31, también `tipo: "atascado"` («Rentería · Atascado de Basauri: 3 cajas de V2 4g»: lo ha recogido Eder y está en el almacén); se ponen igual.
- `guardar_reparto` **no cambia**: al guardarlo, las líneas que siguen igual (sin contar mayúsculas) quedan **atendidas** con ese reparto (la tienda ve «Va en el reparto de hoy»). Las que se han quitado o cambiado **siguen pendientes** y vuelven a salir la próxima vez (decisión del propietario, 03/11/2026: así ninguna se pierde sin que nadie lo decida).
- **Botón «No va»** (solo si quien prepara es Administración), junto a cada línea que viene de una tienda: `descartar_peticion_tienda({ peticion_id: id })`, con `motivo` opcional. La petición deja de salir y la tienda ve «No va: [motivo]» (sin motivo, «No va: lo ha quitado Administración»). Quitar la línea de la casilla al pulsarlo. Para mandar otra cosa (por ejemplo, 1 en vez de 2): «No va» en la original y escribir la nueva en la casilla. El operario no tiene el botón: deja las líneas como vienen.
- Nada cambia en las bolsas ni en la salida: en las bolsas salen como cualquier petición especial («Además, mete:»).

### 9.17 Administración: `cierres_caja` · `incidencias_tiendas` · `cerrar_incidencia_tienda` · `descartar_peticion_tienda` 🧪 (Tarea 28)
- **`cierres_caja(desde?, hasta?, tienda_id?)`:** `{ cierres: [{ fecha, tienda_id, tienda, z, ventas, efectivo, glovo, por, guardado_en }] }`, los más nuevos primero (por defecto, la última semana). Lectura preparada para el panel (Tarea 30).
- **`incidencias_tiendas()`:** `{ incidencias: [{ id, tienda_id, tienda, opcion, texto, fecha, a_las, estado, cerrada_en, nota }] }`: las abiertas primero y las cerradas de la última semana. `opcion`: `"falta_reposicion"` (Tarea 28); desde la Tarea 30, `"sin_producto"`, `"descuadre"`, `"comentario_cliente"` y `"otros"` (§9.20); y desde la Tarea 30b, `"falta_envio"` (§9.21); y desde la Tarea 31, `"atascado"`, con el objeto `atascado` (§9.23; `null` en las demás). Por ejemplo, `"falta_reposicion"` («Falta en la bolsa del reparto del 18/12: 1x V2 4g; Material: Rollos de TPV. La caja venía abierta (Nombre)»). Es el aviso en la app: mostrarlas en el panel.
- **`cerrar_incidencia_tienda(incidencia_id, nota?)`:** la cierra al resolverla (`nota`, una línea). **Salida:** `incidencias_tiendas()`. **Errores:** `NO_ENCONTRADO`, `DATOS_NO_VALIDOS`.
- **`descartar_peticion_tienda(peticion_id, motivo?)`** («No va»): quitar una muestra o un material pendiente que no va a ir. `motivo` opcional (una línea, 120 letras); la tienda ve «No va: [motivo]» o, sin motivo, «No va: lo ha quitado Administración». **Salida:** `{ peticion: {…} }`. **Errores:** `NO_ENCONTRADO`, `ESTADO_NO_VALIDO` (ya atendida o descartada), `DATOS_NO_VALIDOS` (motivo demasiado largo).
- **Dónde:** en «Preparar reparto» / «Preparar envío» (§9.16) y en el panel, sección «Tiendas»: una lista de **peticiones pendientes** de todas las tiendas (`peticiones_tiendas_pendientes('reparto')` y `('envio')`) con el botón «No va» en cada una, para quitarlas sin abrir el reparto.

### 9.18 Errores nuevos (Tarea 28) 🧪
| Código | Qué hace la pantalla |
| --- | --- |
| `FALTAN_DATOS` | `error.pide` dice qué: `"efectivo"` → pedir la cantidad y llamar a `entregar_efectivo`; `"cierre_caja"` → pedir Z, nº de ventas, efectivo y Glovo y llamar a `cerrar_caja`; `"cierre_caja_corto"` (Tarea 30b) → pedir Z y nº de ventas y llamar a `cerrar_caja` sin efectivo ni Glovo. |
| `MOTIVO_OBLIGATORIO` | En el efectivo: pedir el porqué de la otra cantidad y repetir `entregar_efectivo` con `motivo`. |

### 9.19 `tiendas()` 🧪 (Tarea 29)
Las tiendas activas, para elegir a cuál mandar un aviso (Administración y el operario; una tienda, `NO_AUTORIZADO`): `{ tiendas: [{ id, codigo, nombre }] }`, por nombre. Con «Todas» se manda sin `tienda_id`.

### 9.20 Incidencias de tienda: `crear_incidencia_tienda(id_cliente, opcion, texto?, producto?)` 🧪 (Tarea 30)
Botón «Incidencia» de la tableta, en cualquier momento (`ESTADO_DEL_SISTEMA.md` E2-8). Sin foto ni urgencia. Todas llegan a **Administración como incidencia abierta** (§9.17). **A Eder no le sale nada.**
- **`tienda_hoy().opciones_incidencia`:** las opciones de esa tienda, en orden: `[{ opcion, texto, pide, llama }]`. Se activan por tienda en la configuración (`incidencias_tienda`; el material, `pedir_material`), no en el código.
  - Propias: `material` («Material de tienda», `llama: "pedir_material"`), `sin_producto` («Me quedo sin producto», `pide: "producto"`), `descuadre` («Descuadre de stock o de caja»), `comentario_cliente` («Comentario de cliente») y `otros` («Otros»). Las cuatro últimas, `llama: "crear_incidencia_tienda"`.
  - Franquicias (Donosti y Rentería): solo `otros`, un cuadro de texto libre.
  - `pide`: `"texto"` (cuadro para escribir) o `"producto"` (elegir de `productos_tienda()`).
- **«Me quedo sin producto»:** botón de **llamar a Administración** (`mi_perfil().telefono_administracion`) y, además, `crear_incidencia_tienda({ id_cliente, opcion: "sin_producto", producto, texto? })`. `producto` = la `clave` de `productos_tienda()`; `texto`, nota opcional en una línea (200 letras; por ejemplo, el formato). Queda «Sin producto: V2. Del de 4g (Nombre)».
- **Descuadre, comentario de cliente y otros:** `crear_incidencia_tienda({ id_cliente, opcion, texto })`, texto obligatorio en una o dos líneas (300 letras). Queda «Descuadre de stock o de caja: …», «Comentario de cliente: …» o el texto tal cual (otros), con el nombre de quien está en el turno.
- Hay que haber elegido quién está (`SIN_PERSONA`). Repetir con el mismo `id_cliente` no la duplica.
- **`tienda_hoy().incidencias`:** las de la tienda abiertas y las cerradas hoy (las abiertas primero): `[{ id, opcion, texto, fecha, a_las, estado: "abierta" | "cerrada", estado_texto }]`. Mostrar `estado_texto`: «Abierta» o «Resuelta por Administración: [nota]» (sin nota, «Resuelta por Administración»). Incluye la de «Falta algo» de la reposición. Los avisos van aparte (`avisos`).
- **Salida:** `tienda_hoy()` actualizado. **Errores:** `DATOS_NO_VALIDOS` (opción que no existe, producto que no está en la lista, sin texto, demasiado largo), `NO_AUTORIZADO` (la tienda no tiene esa opción; el operario y Administración), `SIN_PERSONA`, `SIN_JORNADA` (hoy la tienda no abre).

### 9.21 «Envíos»: `tienda_hoy().envios` · `confirmar_envio(envio_id, faltan?, nota?)` 🧪 (Tarea 30b)
Para las tiendas que **reciben por envío** en lugar de bolsa del reparto (configuración `recibe_envio` por tienda: hoy **Rentería**, que recibe el envío a Gipuzkoa entero y lo reparte con Donosti, y **Durango**, con el suyo; decisión del propietario, 03/11/2026). Para ellas no hay «Recibe la bolsa» ni reposición. **A Eder no le sale nada nuevo:** se usa lo que ya marca al preparar el envío.
- **Cuándo sale:** desde el **día siguiente** a prepararlo, es decir, cuando el operario termina «Prepara el envío aprobado» (todo metido en la caja), entre semana por la tarde o el viernes por la mañana, **vaya quien vaya al reparto** (propietario, 03/11/2026). **No es una tarea con hora:** sigue en `envios` hasta que se confirma; **al confirmarlo desaparece en el momento**. Se miran los envíos de la última semana sin confirmar.
- **`tienda_hoy().envios`:** los que quedan por confirmar, los más antiguos primero:
```json
[ {
  "id": "…", "reparto_id": "…", "fecha": "2026-12-16", "preparado": "17:00", "destino": "Gipuzkoa (envío a Rentería)",
  "productos": [ { "clave": "producto:V2|4g", "producto": "V2", "formato": "4g", "cantidad": 3 } ],
  "peticiones": [ { "clave": "peticion:Donosti · Muestra: V2", "texto": "Donosti · Muestra: V2" } ],
  "pedidos": []
} ]
```
  Cada pedido de `pedidos` trae además `tienda` (Tarea 30c: en el envío a Gipuzkoa, Donosti o Rentería). `preparado`: la hora a la que se terminó de preparar (mostrar «Preparado a las 17:00»). Lo que trae es **lo marcado al meterlo en la caja** (como `bolsa`, §9.11): lo que no se ha marcado no aparece. El envío a Gipuzkoa es uno para las dos tiendas, calculado con lo que hay en Donosti y Rentería juntas.
- **`tienda_hoy().envios_sin_confirmar`:** cuántos quedan por confirmar (el número de la pestaña).
- **«Todo bien»:** `confirmar_envio({ envio_id })`.
- **«Falta algo»:** `confirmar_envio({ envio_id, faltan: [{ clave, cantidad? }], nota? })`, como en la reposición (§9.12): `clave` de `productos`, `peticiones` o `pedidos`, de 1 a lo que traía (sin `cantidad`, todas); `nota`, una línea (200 letras). Llega a **Administración como incidencia abierta** (`incidencias_tiendas()`, `opcion: "falta_envio"`, «Falta en el envío del 16/12: 1x V2 4g. La caja venía abierta (Nombre)»), y la tienda la ve en `tienda_hoy().incidencias`.
- Hay que haber elegido quién está (`SIN_PERSONA`).
- **Salida:** `tienda_hoy()` actualizado. **Errores:** `NO_ENCONTRADO` (no es un envío de esta tienda), `ESTADO_NO_VALIDO` («Ese envío ya está confirmado.»), `DATOS_NO_VALIDOS` (algo que no está en la lista, cantidad, nota larga), `SIN_PERSONA`, `SIN_JORNADA`; el operario y Administración, `NO_AUTORIZADO`.

### 9.22 Pedidos de cliente desde la tableta: `crear_pedido_tienda(id_cliente, cliente, lineas)` · `tienda_hoy().pedidos` 🧪 (Tarea 30c)
Botón **«Pedido de cliente»** en todas las tiendas, franquicias incluidas (decisión del propietario, bloque 1 punto 20; 04/11/2026). Solo **para recoger en esa misma tienda**; nunca por Nacex (eso sigue siendo de Administración y del almacén).
- **La lista:** `productos_tienda()` (§9.15), con `formatos`: elegir producto y formato y la cantidad con − y +. Es la última lectura de la hoja: la tableta no llama a Google.
- **`crear_pedido_tienda({ id_cliente, cliente, lineas: [{ producto, formato, cantidad }] })`:** `cliente`, nombre corto (60 letras); `formato` uno de los de ese producto (`""` si no tiene); `cantidad` de 1 a 99 (0 no cuenta; repetidos se suman). Queda con el nombre de quien está en el turno (`SIN_PERSONA` si no hay nadie). Repetir con el mismo `id_cliente` no lo duplica.
- **Después, el camino de siempre** (§3.16): las propias lo reciben en el reparto (hoy si las bolsas aún no están hechas; si no, en el siguiente), con su tarea en el almacén y su bolsa aparte; Donosti, Rentería y Durango, en el siguiente envío (§9.21). Administración lo ve en `pedidos_cliente_abiertos()` con `pedido_en_tienda` y `pedido_por`.
- **`tienda_hoy().pedidos`:** los pedidos para recoger en la tienda (los que ha apuntado ella y los de Administración), los que esperan o están por preparar y los preparados hasta su día: objeto pedido (§3.17) sin `datos_envio`. Mostrar `cliente`, `lineas` y `estado_texto`.
- **Salida:** `tienda_hoy()` actualizado. **Errores:** `DATOS_NO_VALIDOS` (sin cliente, producto o formato que no está en la lista, cantidad, lista vacía), `SIN_PERSONA`, `SIN_JORNADA` (hoy la tienda no abre o no hay día de trabajo del almacén), `NO_AUTORIZADO` (el operario, Administración o una tienda sin reparto ni envío).

### 9.23 Productos atascados: `revisar_atascados` · `querer_atascado` · `ya_no_queda` · `decidir_atascado` 🧪 (Tarea 31)
Decisión del propietario (`ESTADO_DEL_SISTEMA.md` E2-8 v1.56 y v1.57; 04/11/2026). Lo atascado se ofrece primero a las demás tiendas; si nadie lo quiere (o es de una franquicia), decide Administración. **El reparto de Eder no cambia.**
- **«Revisa los productos atascados»** (`tipo: "atascados"`): martes por la mañana (en Bilbao alterna por semanas), en todas las tiendas, franquicias incluidas. Lista de `productos_tienda()` (§9.15) **con formato**: tocar el producto y formato = 1 caja; con − y + se cambia (de 1 a 99); nota opcional por producto (200 letras).
  - **`revisar_atascados({ tarea_id, atascados: [{ producto, formato, cantidad?, nota? }] })`:** `formato` uno de los de ese producto (`""` si no tiene); sin `cantidad`, 1. **Lista vacía = «Nada atascado esta semana».** La tarea queda hecha; lo apuntado sale en `atascados` de la tarea (objeto atascado).
  - **Errores:** `NO_ENCONTRADO`, `TODAVIA_NO`, `SIN_PERSONA`, `ESTADO_NO_VALIDO`, `DATOS_NO_VALIDOS` (producto o formato que no está en la lista, cantidad, repetido, nota larga).
- **Objeto atascado:** `{ id, tienda_id, tienda, fecha, producto, formato, cantidad, texto ("3 cajas de V2 4g"), nota, por, estado, estado_texto, pedido_por, pedido_por_nombre, promocion, decision, decisiones }`. Mostrar `texto`, `nota` y `estado_texto`.
  - `estado`: `ofrecido` (a las demás tiendas, su martes) · `administracion` (decide Administración) · `promocion` · `por_recoger` (Eder lo va a recoger) · `entregado` · `terminado` (ya no queda) · `cerrado` (Administración: recogida, o cerrada sin decidir).
  - `estado_texto` en la tienda que lo tiene: «Ofrecido a las demás tiendas hasta el cierre del 15/12», «Lo quiere Portugalete: prepáralo para recogida», «Nadie lo ha pedido: decide Administración», «En promoción: …», «Al almacén: prepáralo para recogida», «Recogido el 16/12 a las 10:30», «Promoción terminada: ya no queda», «Recogida: la organiza Administración (…)»…
- **`tienda_hoy()`:**
  - **`atascados`:** lo de la tienda (lo abierto y lo de la última semana).
  - **`ofertas_atascados`:** lo de las demás tiendas, **solo su martes**: `[{ id, tienda_id, tienda, producto, formato, cantidad, nota, texto }]`, con `texto` «Basauri tiene 3 cajas de V2 4g que no se mueven: ¿las quieres?» (con 1, «… 1 caja de CREMA que no se mueve: ¿la quieres?»). Botón **«Las quiero»** → **`querer_atascado({ atascado_id: id })`**. Lo de las franquicias y Durango no se ofrece.
  - **`atascados_pedidos`:** lo que la tienda ha pedido (objeto atascado; `estado_texto` «Lo has pedido: el almacén lo recoge en Basauri y te lo trae» o «… y va en tu siguiente envío»; después, «Entregado el 16/12» o el de su petición del envío: «Pendiente: irá en el siguiente envío», «Va en el envío de hoy»).
  - **`promociones`:** las promociones abiertas de la tienda: `[{ id, producto, formato, cantidad, texto, promocion, desde }]`. Botón **«Ya no queda»** → **`ya_no_queda({ atascado_id: id })`**.
  - **Avisos** (en `avisos`, como siempre): «Prepara 3 cajas de V2 4g para recogida» (`de: "Almacén"` si lo ha pedido otra tienda; `"Administración"` si va al almacén) y «Promoción de 1 caja de CREMA: [texto de Administración]».
- **`querer_atascado`:** **se lo lleva la primera que lo pide.** Lo deja de ver el resto; a Eder le llega la recogida (§3.11) y a la tienda que lo tiene, el aviso. Repetirlo desde la misma tienda no hace nada nuevo. **Salida:** `tienda_hoy()` actualizado. **Errores:** `ESTADO_NO_VALIDO` («Ya lo ha pedido [tienda].» o «Esta oferta ya ha terminado.»: mostrar el mensaje), `NO_ENCONTRADO` (su propia oferta o una que no existe), `SIN_PERSONA`, `SIN_JORNADA`.
- **`ya_no_queda`:** cierra la promoción (con quien está en el turno). **Salida:** `tienda_hoy()` actualizado. **Errores:** `NO_ENCONTRADO`, `SIN_PERSONA`, `SIN_JORNADA`.
- **Panel de Administración:** en `incidencias_tiendas()` (§9.17), las de `opcion: "atascado"` traen `atascado` (objeto atascado con `decisiones`). Lo de las propias llega **al acabar su martes** si nadie lo ha pedido (para decidir el miércoles por la mañana); lo de las franquicias y Durango, en el momento. Mientras `decisiones` no esté vacío, enseñar sus botones (en lugar de «Cerrar»):
  - **`decidir_atascado({ atascado_id, decision, texto? })`**, `decision`:
    - `"promocion"` (todas): **`texto` obligatorio**, lo escribe Administración (180 letras). La tienda recibe el aviso y la promoción sigue abierta hasta «Ya no queda».
    - `"almacen"` (propias): Eder lo recoge y lo lleva al almacén (`texto` opcional).
    - `"recogida"` (franquicias y Durango): la organiza Administración; se cierra con su nota (`texto` opcional). Cuando llegue, Administración manda a Eder un aviso o una tarea, como siempre (§3.21, §4.1).
  - La incidencia queda cerrada con la decisión («Promoción: …», «Al almacén», «Recogida: …»). **Salida:** `incidencias_tiendas()`. **Errores:** `ESTADO_NO_VALIDO` (ya decidido), `DATOS_NO_VALIDOS` (decisión que no toca o promoción sin texto), `NO_ENCONTRADO`, `SIN_JORNADA`.
- **Operario:** sus recogidas en `incidencias_abiertas()` (§3.11). Al cerrarla, el atascado queda entregado; si lo ha pedido una tienda que recibe por envío (Donosti, Rentería, Durango), queda como petición de esa tienda para **su siguiente envío** (decisión del propietario, 04/11/2026; §9.16).
- **Configuración** (por tienda, clave `atascados`): `"ofrecer"` o `"administracion"` (Donosti, Rentería y Durango, que recibe por envío; decisión del propietario, 04/11/2026).
