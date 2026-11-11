# OSASUN OPERATIONS — Estado del sistema y decisiones

**Versión:** 1.73 · **Fecha:** 11/11/2026 · **Estado:**
- **Almacén:** en uso real en el entorno de pruebas.
- **Tiendas:** en prueba en Basauri, Portugalete y Rentería, en el entorno de pruebas (70 migraciones; la última, Tarea 38, T-0010).
- **Producción:** montada y sin usar, sin lo de tiendas. Espera a que el propietario dé por probado lo de tiendas.
- **Cómo se trabaja desde el 07/11/2026:** con tickets (T-XXXX). Ver §11.

> **Regla (07/11/2026):** cada PR que cambie este documento pone al día esta cabecera (versión, fecha y estado).

---

## 0. Cómo usar este documento

- Es la **fuente de verdad técnica** del proyecto. Todo agente lo lee antes de trabajar.
- Lo aprobado aquí no se cambia por iniciativa propia. Las propuestas se envían al coordinador, el propietario las aprueba y entonces se actualiza este documento.
- **Desde el 07/11/2026** lo actualiza el agente de base de datos en el PR de cada tarea, y el coordinador lo revisa (§11).
- Cada cambio se anota en el **Historial** (sección 15).
- La documentación operativa (manual del almacén y sus actualizaciones) está separada en `ACTUALIZACIONES_MANUAL_ALMACEN.md`.

---

## 1. Visión y etapas

Cada trabajador tiene una app supervisora que le dice qué hacer, le mantiene el foco y registra lo que hace. El propietario lanza tareas desde su panel y recibe un cierre con lo hecho (y su resultado) y lo no hecho (y su motivo).

| Etapa | Contenido |
| --- | --- |
| **1. Almacén** | Supervisor del operario y panel de Administración. Se prueba hasta estar perfectamente integrado. |
| **2. Tiendas** | La misma plataforma para cada persona de cada tienda. Las diferencias entre tiendas se resuelven con configuración, no con apps distintas. |
| **3. Ventas e inteligencia** | Registro tipo TPV (ventas, incidencias, productos nuevos), ventas por tienda, rentabilidad, FIFO entre tiendas y ayuda a decidir qué mover. **Ampliación autorizada por el propietario.** |

**Principio:** una plataforma, múltiples centros de trabajo. Personas, centros y tareas son genéricos desde el primer día. El almacén es el primer centro, no un caso especial.

---

## 2. Diagnóstico (punto 1, aprobado)

**Situación:** la operativa básica funciona. Se buscan mejoras de excelencia.

| # | Problema |
| --- | --- |
| 1 | **Tiempo muerto mal aprovechado:** sin siguiente tarea definida, empaqueta por inercia cajas que no hacen falta. Pasa sobre todo de 11:00 a 13:00 y las tardes de miércoles y jueves. |
| 2 | **Necesidades que no se convierten en acción:** detecta lo que falta pero no lo resuelve, aunque sea su responsabilidad. |
| 3 | **Bloqueos no comunicados:** espera en lugar de avisar. |
| 4 | **Errores de identificación:** confunde cajas de referencias con nombres parecidos. |
| 5 | **Sin registro** de lo hecho, en curso y pendiente. |
| 6 | **Cálculo mecánico manual:** pega el reparto en Claude para sumar cajas. |

**Causa de fondo:** ejecuta sin entender la razón ni el objetivo de cada tarea.

**Objetivos:**
- **Operativo:** que siempre tenga una siguiente tarea útil decidida con datos, que ninguna necesidad quede sin responsable y fecha, que avise al bloquearse y que todo quede registrado.
- **Desarrollo:** que cada tarea explique su porqué, con frases y no con casillas, para que gane criterio y pueda asumir más responsabilidad.

---

## 3. Usuarios y dispositivos

| Usuario | Dispositivos | Uso |
| --- | --- | --- |
| **Administración (propietario)** | Móvil y ordenador | Móvil: lanzar tareas, ver el estado y recibir el cierre. Ordenador: histórico e indicadores. |
| **Operario de almacén** | Chromebook en su mesa (principal) y Google Pixel | Chromebook: tarea activa, siempre visible. Pixel: preparación de bolsas y tareas recibidas durante el reparto. |

- **Horario del operario:** lunes a jueves de 08:30 a 13:00 y de 15:30 a 18:30; viernes de 08:30 a 13:00. Son 34,5 h de un contrato de 35 h, así que hay **30 minutos semanales flexibles** para cuando la vuelta del reparto se alarga.
- **Cuentas:** cada persona tiene su usuario. No hay credenciales compartidas. Osasun usa cuentas de Google gratuitas, no Workspace. **Se entra con la cuenta de Google** de cada persona; solo pueden entrar las cuentas dadas de alta (decisión del propietario, 26/10/2026).

---

## 4. Mapa semanal del almacén (punto 2, aprobado)

### Mañana (lunes a viernes)
| Hora | Tarea |
| --- | --- |
| 08:30–~08:45 | Revisión inicial: estado de las tiendas, formulario de incidencias de tiendas (hoja de respuestas) y stock empaquetado. |
| ~08:30–08:45 | Administración publica el reparto en WhatsApp, con la línea `SALE:`. |
| Hasta la salida | 1) Calcular el total de cajas, restar las hechas y producir lo que falta. 2) Preparar las bolsas de cada tienda. 3) Con el tiempo restante, stock del almacén (+35 %). |
| Viernes | 30 minutos de limpieza intensiva de la estación de resinas. **Cambiado por el propietario el 30/10/2026:** sale en cuanto estén hechas la producción del reparto, las bolsas, el envío (si lo hay) y la producción del +35 %, y **antes del recuento de las 12:45** (ya no «antes del reparto» ni con límite a las 10:45). Lo del reparto y el envío va siempre antes que la limpieza y el orden. También espera a «Prepara el reparto» y a los pedidos de cliente del día (decisiones del propietario en la Tarea 20). Si no da tiempo antes de las 12:45 (por ejemplo, el +35 % sin terminar antes de salir a repartir), pasa al siguiente día de trabajo. **Costumbre:** el envío del viernes se mete en la app a primera hora (o el jueves al decidirlo); si no está metido, la app no sabe que hay envío y la limpieza no lo espera. |
| Si sale él | Salida a las 10:45 y ruta de unas 2 h. A la vuelta, efectivo frente a la Z y reporte a Administración. |
| 10:45 | **Bolsas listas en la mesa de salida.** Las organiza siempre el operario (lo normal es tenerlas hacia las 10:30). Si no llega, pulsa «Retrasar 15 min» o «Retrasar 30 min» y se avisa a quien sale de la nueva hora de salida, para que no llegue antes y espere. Cada retraso queda registrado y el cierre lo cruza con las cajas del reparto y las incidencias de la mañana. La salida suele ser entre las 10:45 y las 11:00 (decisión del propietario, 26/10/2026). |
| Si sale Administración | Bloque libre hasta las 12:45 (cola de tiempo libre). |
| 12:45–13:00 | Recuento de stock y cajas hechas, y actualización de STOCK ALMACÉN DIARIO. |

**Quién hace el reparto:** normalmente Administración de lunes a miércoles. El objetivo es que el operario lo haga jueves y viernes, pero varía cada día. **El efectivo lo cuenta quien hace el reparto.**

### Tarde (lunes a jueves)
| Hora | Tarea |
| --- | --- |
| 15:30 | Revisar si toca envío a Gipuzkoa/Durango: él calcula y propone, Administración decide. El lunes siempre hay envío; el resto de días, según la semana. |
| Lunes | Minis (unos 35, para llevar el miércoles). |
| Martes | Resinas, comprobando antes en PRINCIPAL si ya hay una semana de cobertura. |
| Miércoles y jueves | Sin tarea fija: producir para que el viernes el producto empaquetado esté a tope. |
| Jueves, última hora | Control semanal de materiales y aviso de cobertura a 2 semanas (R4). |
| Cierre con envío | Recuento de 17:55 a 18:10, salida a Nacex a las 18:10 y vuelta hacia las 18:25 para cerrar. |
| Cierre sin envío | Recuento y cierre de 18:15 a 18:30. |

**Viernes:** si hace falta, envío a Gipuzkoa/Durango por la mañana. Se decide el **jueves a las 15:30**, en la misma revisión del envío de ese día (decisión del propietario, 26/10/2026). El envío del viernes se prepara **antes de las 10:45**, junto con las bolsas, y quien sale a repartir lo deja en Nacex de camino. **Reparto y envío el mismo día antes del recuento de la mañana:** al calcular lo que falta para el envío, primero se apartan las cajas del reparto de ese día (decisión del propietario, 26/10/2026).

### En cualquier momento (eventos)
- **Llega mercancía:** se abre y se comprueba en el momento.
- **Pedido de cliente** (1 o 2 por semana, sobre todo los miércoles): se prepara como el de una tienda y se envía por Nacex. Lo mete en la app quien lo recibe: Administración como tarea nueva o el operario con el botón «Pedido de cliente» (decisión del propietario, 26/10/2026).
- **No quedan vapers:** tirada de 50, repartida entre 2 tipos.
- **Falta material:** catálogo (sección 7).
- **Bloqueo:** flujo de problemas (sección 6.6).

### Cola de tiempo libre (por prioridad)
1. **A:** producir para el stock del almacén (R3).
2. **C:** compras y aprovisionamientos pendientes.
3. **D:** orden y limpieza.

La recepción de mercancía no está en la cola: se atiende en el momento en que llega.

**Nunca sin tarea (decisión del propietario, 27/10/2026):** si el operario termina todo lo disponible antes de la siguiente tarea con hora:
1. Primero se **adelantan las tareas fijas de la tarde de ese día** (minis el lunes, resinas el martes, control de materiales el jueves).
2. Después, **«Orden y limpieza»**, que **no se gasta nunca**: vuelve a salir siempre que no haya otra cosa.
3. Lo que va ligado a su hora (recuento, revisión del envío, Nacex, salida) sigue esperando a su hora.

### Quién decide
- **Administración:** las cantidades del reparto, quién sale cada día, la aprobación del envío a Gipuzkoa/Durango, el pedido de packaging, la materia prima y las nuevas variedades.
- **Operario:** la ejecución según las reglas, el orden dentro de las listas de producción, las compras online de consumibles y la recepción.

### Indicador de calidad semanal
La limpieza del viernes hecha (sale de la tarea). Los papeles de resinas rectos y cuidados son una apreciación del propio operario, a modo de reconocimiento, sin comprobación; **queda fuera de la V1** y se retomará cuando todo funcione (decisión del propietario, 26/10/2026).

---

## 5. Reglas de negocio y de cálculo

> Todos los cálculos son deterministas, se ejecutan en el servidor (Supabase) y tienen pruebas. La IA no calcula nada crítico.
> **La app nunca propone cantidades para las tiendas.** Solo calcula sobre lo que ya ha decidido Administración.

**R1. Reparto y envíos** (rediseñado por el propietario el 28/10/2026, tras la primera prueba real: el texto de WhatsApp usa abreviaturas que no coinciden con PRINCIPAL y 36 de 52 líneas no se reconocían).

El reparto **ya no se pega como texto: se prepara en la app**, eligiendo de una lista.
1. **Quién sale:** desplegable con los nombres (Administración u operario).
2. **Tienda:** las tiendas activas o, para el envío, GIPUZKOA (y Durango cuando abra).
3. **Lista de productos de PRINCIPAL** (catálogo leído de la hoja, en solo lectura), agrupada por categoría y con buscador. Cada producto y formato tiene **− cantidad +**. Nadie escribe nombres, así que no puede haber errores de nombre.
4. **Calcular:** la app suma las cajas por producto y formato, resta las del almacén y crea la producción (lo que falta) y las bolsas por tienda. La app **no propone cantidades**: las pone quien prepara el reparto.
5. **Copiar para WhatsApp:** la app genera el texto del reparto con el formato de siempre (`REPARTO dd/mm`, `SALE:`, tienda y `Nx PRODUCTO FORMATO`) para mandarlo al grupo si se quiere.
6. Lo pueden preparar **Administración y el operario**. **Modificar** = abrir el de hoy, cambiar números y volver a calcular: sustituye al anterior y conserva lo ya hecho. La tarea «Prepara el reparto» se cierra sola al calcularse uno; si se pulsa «Terminada» sin reparto, la app pide el motivo.
7. Se puede cambiar quién sale sin tocar el reparto. Si sale el operario, tras «Bolsas listas en la mesa de salida» (10:45) le aparece «Salida del reparto» y, a la vuelta, «Efectivo y reporte».

- **Destinos** (decisión del propietario, 28/10/2026): **reparto** a BILBAO, ALGORTA, BARAKALDO, BASAURI y PORTU; **envío** a GIPUZKOA y DURANGO. Donosti y Rentería no van en el reparto: les llega por el envío a Gipuzkoa. El orden es el de las pestañas de STOCK OSASUN. Están en la configuración (`destinos_reparto`).
- **Envío a Gipuzkoa/Durango:** el mismo camino, con tipo «envío». Lo propone el operario, Administración lo aprueba y el operario lo prepara en la app. Un solo bloque GIPUZKOA (pestaña GIPUZKOA de la hoja) va entero a Rentería por Nacex, y allí la persona de Rentería lo reparte entre Donosti y Rentería. Donosti y Rentería son las únicas tiendas en franquicia. Durango, cuando abra, irá como bloque propio. Si el envío se prepara antes del recuento de la mañana del mismo día que un reparto, primero se apartan las cajas del reparto.
- **Ya no aplica:** pegar texto, la línea `SALE:` obligatoria y la normalización de nombres escritos.

**R1e. Producto sin granel en el reparto: quitarlo o cogerlo de otra tienda** (decisión del propietario, 29/10/2026, tras la prueba en el almacén: se pidió un producto que no había en el almacén ni se podía hacer, y nadie se enteró).
- Quien prepara el reparto pone las cantidades **sin mirar el almacén**: el reparto tiene en cuenta que hay otras tiendas. **De dónde sale cada cosa lo decide el almacén.**
- **En la tarea «Producción del reparto»**, cuando el operario elige un producto que hay que hacer y **no tiene granel**, le sale el aviso con dos opciones:
  - **Quitarlo** del reparto (lo habrá hablado antes con Administración);
  - **Cogerlo de otra tienda**: elige de qué tienda, viendo cuántas tiene cada una según la hoja.
- **En «Bolsas listas en la mesa de salida»**, en la bolsa de la tienda que recibe, le sale: **«Avisa a [tienda] para que prepare N [producto formato] para su retirada»** (hasta el 11/11/2026, «Llama a…»). Lo marca al llamar (como las peticiones especiales) y esa bolsa no se da por terminada sin marcarlo. Esas cajas no van en la bolsa.
- **Cajas de otra tienda** (propietario, 11/11/2026; T-0010 · Tarea 38): la tienda de origen recibe un aviso en su tablet **en el momento en que el operario prepara la bolsa y marca esa línea**, no antes (por si hay que modificar algo): «Prepara N [producto formato] para [destino]: lo recoge hoy el reparto». Y la tienda que recibe **ve esas cajas en la lista de su bolsa**, en la línea de su producto, con de dónde vienen («3 (1 de Algorta)»). Igual para todas las tiendas. El operario no tiene ningún paso nuevo: es el mismo toque.
- **La parada sale siempre a quien hace la ruta:** «Recoge N [producto] en [tienda] y déjalas en [tienda]». Si sale el operario, en su «Salida del reparto»; si sale Administración, como aviso en su panel (no es una tarea).
- **Va en el texto para WhatsApp** («2x BZ1 4g (de Algorta)»). Como la decisión se toma en la producción, si el texto ya se ha mandado hay que volver a copiarlo.
- Las cuentas no cambian: las cajas solo pasan de una tienda a otra (en camino: −N en la que da y +N en la que recibe, con la misma hora que el reparto).
- **En el envío a Gipuzkoa/Durango es distinto** (decisión del propietario, 29/10/2026): se comprueba **al preparar el envío**, no en la producción, porque no hay ruta que pase por otra tienda antes de Nacex. Al pulsar «Calcular», si algo hay que hacerlo y no tiene granel, la app **no guarda** y lo dice («SOUR DIESEL 4g: pides 5, en el almacén hay 3 cajas y no hay granel para hacer las otras 2»), con dos botones: **«Dejarlo en 3»** (lo que hay) o **«Quitarlo»**. Después se vuelve a calcular. En el envío no existe «cogerlo de otra tienda».
- **Que el operario sepa quién sale** (misma fecha): en las tareas del reparto (producción y bolsas) pone arriba «Hoy sales tú» u «Hoy sale [nombre]», y se actualiza si cambia.

**R1d. Peticiones especiales** (decisión del propietario, 28/10/2026). En «Preparar reparto» y «Preparar envío», cada tienda tiene una casilla **«Peticiones especiales para [tienda]»**: una petición por línea (rollos de TPV, muestras, cajas vacías…). **No cuentan como stock ni van a producción.** En las bolsas aparecen como **«Además, mete:»**, una por una para tocarlas, y la bolsa no se da por terminada hasta tocarlas todas. También salen en el texto para WhatsApp. Si algo no está en el almacén, el operario lo avisa con Incidencia → «Hay que pedir o comprar algo».

**R1b. Pedidos de cliente** (decisión del propietario, 28/10/2026). Quien recibe el pedido (Administración u operario) pulsa **«Pedido de cliente»**, apunta las cajas con **la misma lista** (− y +) y elige **cómo se entrega**:
- **Recoger en tienda** (elige la tienda): el pedido se añade **al siguiente reparto de esa tienda**. Si el de hoy aún no está calculado, entra en él; si ya está calculado o ha salido, en el siguiente. Las cajas que falten van a la producción.
  - Va en una **bolsa aparte**: en el Pixel, la tienda tiene su «Bolsa de reposición» y además «Pedido de cliente · [nombre]».
  - Para que no se olvide, el operario tiene **una tarea propia, «Hay un pedido de cliente para dejar en [tienda]»**, que aparece **en cuanto termina la producción del reparto oficial** y se hace entonces, no al preparar las bolsas antes de salir.
- **Envío por Nacex** (se pegan los datos de envío tal cual: nombre, dirección, teléfono…): al operario le entra **«Prepara el pedido de cliente»**, con la lista y los datos de envío bien escritos, y se activa **«Llevar a Nacex»** ese día. De lunes a jueves, recuento a las 17:55 y salida a las 18:10; el viernes, antes de las 10:45, y lo deja quien sale de reparto. Si ese día ya hay envío a Gipuzkoa o a Durango, va en el mismo viaje.
- **Recoger en una tienda que recibe por envío** (decisión del propietario, 03/11/2026): **Donosti, Rentería y Durango** también se pueden elegir. El pedido va **en el siguiente envío** a esa tienda (Gipuzkoa para Donosti y Rentería; Durango para Durango), como caja aparte «Pedido de cliente · [cliente] · [tienda]», que el operario marca al preparar el envío, y **con su tarea propia, como en el reparto** («Hay un pedido de cliente para enviar a [tienda] · [cliente]», con su «coge / haz»; propietario, 04/11/2026, PR #33). No crea un envío por sí solo. Mientras no haya envío, espera; en «Revisa si toca envío…» (15:30) el operario ve «Hay N pedidos de cliente esperando envío a [destino]», para tenerlo en cuenta. En la tienda sale en su pestaña «Envíos» con lo demás (los de Donosti, en la de Rentería, que recibe el envío a Gipuzkoa).
- Los datos del cliente solo se guardan en la base de datos de la app (los ve el personal con cuenta). Nunca en el repositorio.
- **Orden del día** (decisión del propietario, 28/10/2026): primero lo oficial y después el pedido.
  - **Recoger en tienda:** primero «Producción del reparto», solo con las cajas del reparto oficial. Al terminarla, «Pedido de cliente para [tienda] · [cliente]».
  - **Nacex:** por la tarde, primero la revisión y la preparación del envío a Gipuzkoa (si se decide). Después, «Prepara el pedido de cliente (Nacex)».
  - En las dos, la tarea del pedido dice para cada referencia **«Coge N del almacén»** (si quedan cajas hechas después de apartar las del reparto o el envío) o **«Haz N»**.

- **Detalles decididos por el propietario en la Tarea 12 (28/10/2026):**
  - El reparto **«ha salido»** cuando el almacén termina las bolsas (el viernes, también el envío preparado).
  - Los pedidos de Nacex entran en el viaje del día si se apuntan **hasta las 18:00** de lunes a jueves (el viernes, hasta las 10:45); si no, van al siguiente día de trabajo. Si por la producción no llega, el operario puede **pasarlo a mañana** (con un motivo opcional), y lo que queda sin hacer pasa solo.
  - El «coge / haz» se calcula **cuando le toca la tarea del pedido**, con la última lectura de la hoja.
  - Un pedido de tienda que no se hace el día de su reparto pasa al día siguiente como tarea, pero no vuelve a entrar solo en el siguiente reparto.

**R1c. Cuenta del almacén y cajas en camino** (decisiones del propietario, 28/10/2026; sustituye a la versión anterior). La hoja solo cambia con los recuentos y con el «FIN DE DÍA» de cada tienda. Por eso la app lleva su propia cuenta entre medias, **solo en sus cálculos y sin escribir nunca en la hoja**:
- **Almacén ahora** = el último recuento (de la hoja) + lo que el operario ha producido y marcado desde ese recuento − lo que ha salido desde ese recuento (bolsas listas, envíos preparados, pedidos).
- **Cada recuento de fin de turno** (12:45; 17:55 o 18:15) pone al día **solo el almacén**: al marcarlo hecho, la app vuelve a leer la hoja y pone a cero lo producido y lo salido.
- **Cajas en camino** (se suman a su tienda, porque la tienda aún no las ha apuntado):
  - **reparto en coche a Bizkaia** (incluidos los pedidos para recoger en tienda): desde que las bolsas están listas **hasta las 23:30 de ese día**;
  - **envío por Nacex a Gipuzkoa o Durango:** desde que está preparado **hasta las 11:59 del día siguiente**.
  - El recuento no las borra.
- **Pedidos de cliente por Nacex:** las cajas se restan del almacén y **salen del stock** (no se suman a ninguna tienda).
- **«Calcular» del reparto y del envío: solo la hoja** (decisión del propietario, 04/11/2026; **sustituye** a «el reparto de primera hora usa también almacén ahora», Tarea 14). Al pulsar «Calcular», la app lee la hoja en ese momento y calcula con la cifra de almacén que pone, **sin sumar ni restar nada por su cuenta** (ni lo producido o salido desde el recuento, ni lo apartado de otro reparto, envío o pedido). La hoja tiene que estar al día al calcular. Motivo: el 04/11 la cuenta propia de la app sumó lo producido el 03/11 (recuentos del 03/11 sin marcar en la app y bolsas del 03/11 sin marcar) y dio por hechas cajas que no había (INDOOR PR RELAX 4g, KUSH WATERHASH 10g, SUGAR CBDX, T BALLS 4g, INDOOR PR AFRU 10g). «Almacén ahora» sigue para lo demás (el «coge / haz» de los pedidos, las cajas en camino).
- **Un pedido para recoger en tienda activa el reparto** (decisión del propietario en la Tarea 14):
  - entra en el reparto de hoy mientras las bolsas no estén listas; si el reparto ya está guardado, entra al momento;
  - «Prepara el reparto» no se puede cerrar sin reparto si hay un pedido esperando;
  - se puede guardar un reparto que solo lleve pedidos;
  - en «Preparar reparto», los pedidos salen marcados y fijos en su tienda;
  - si «Prepara el reparto» ya se cerró sin reparto (sin pedidos esperando entonces), un pedido apuntado después va al siguiente día de trabajo.
- Se usa en: modificar el reparto durante el día, el envío, el «coge / haz» de los pedidos y la lista del +35 % (cajas de todas partes = hoja + lo producido desde el último recuento + lo que va de camino − los pedidos de Nacex).
- **Etapa 2:** cuando la tienda confirme en su pantalla «bolsa recibida», las cajas dejarán de estar en camino en ese momento (ver E2-2).


**Principio (propietario, 28/10/2026): la lista de productos con − y + es la pieza central para el personal.** Se construye una sola vez y se reutiliza: reparto, envío, pedidos de cliente y, en las siguientes etapas, reposiciones y ventas en las tiendas.

**R2. Stock negativo en una tienda** = encargo de cliente pendiente. Hay que llevar esas cajas además de la reposición normal. Es información de contexto para el operario: la app no modifica las cantidades del reparto.

**R3. Stock del almacén (+35 %).** Se usa CONTEO DE CAJAS TOTAL:
- `contador = cajas hechas en todas partes − consumo semanal` (0 significa una semana cubierta).
- `objetivo = +35 % del consumo semanal`.
- `cajas a hacer = objetivo − contador`, si sale positivo, **redondeado hacia arriba** (D1, decidido 26/10/2026).
- La lista se ordena por consumo semanal, de mayor a menor. Es aceptable que las referencias que menos se venden se queden en torno a +20 %.
- **Los minis quedan fuera de esta regla.** El único mini es **MINI 10g** (así se llama en toda la hoja; corregido el 29/10/2026, antes ponía «MINIBUDS MIX»). Se hacen el lunes por la tarde, unos 35 (R9).
- **Categorías que rotan (Invernadero, Indoor):** se calcula por categoría. Dentro de cada una se aplica FIFO, con un mínimo de 2 variedades de invernadero y 2 de indoor. **El FIFO lo decide el operario:** la app indica las cajas de la categoría y las variedades con granel, y él usa primero el granel más antiguo, que reconoce en el almacén.
- **Sin granel no se produce.** Al operario le aparece la tarea «Avisa a Administración: falta X».

**R4. Aviso del jueves (cobertura a 2 semanas).** En cada producto se compara el total en gramos (almacén más tiendas, de PRINCIPAL) con 2 × la necesidad semanal. Invernadero e Indoor se valoran sumando toda la categoría, porque se compran 2 o 3 variedades a la vez. La app prepara la lista explicando cada aviso. El operario la revisa, comprueba el granel físicamente y la envía a Administración.
- **En el panel de Administración, siempre a la vista** (decisión del propietario, 29/10/2026): la misma cuenta, con «LO QUE HAY EN TOTAL» de PRINCIPAL frente a 2 × «1 SEMANA NECESIDADES». **Solo salen los productos por debajo.** Se usa la hoja tal cual: producir o mandar a una tienda no cambia el total; solo lo cambian las ventas, que la hoja recoge con el FIN DE DÍA. Una sola cuenta para el panel y para el aviso del jueves.

**R5. Verificación del recuento.** La app comprueba si STOCK ALMACÉN DIARIO se ha actualizado ese día. Si no, la tarea aparece como «declarado, no verificado».

**R6. Promociones** (el operario debe conocerlas y entenderlas):
- Lunes: 4 g de regalo con la compra de un pack de 14 g.
- Miércoles: 10 g de minibuds por cada 40 € de compra.

**R7. Vapers:** cuando no queda ninguno en el almacén, tirada de 50 repartida entre 2 tipos.

**R8. Resinas (martes):** producción base de Mazar V2 1,4 kg, Mazar 700 g, Ice 500 g y Waterhash 500 g. Antes se comprueba en PRINCIPAL. Si ya hay una semana de cobertura aproximadamente, la tanda se ajusta o no se repite.

**R9. Minis:** unos 35 por semana, hechos el lunes por la tarde y llevados a las tiendas el miércoles.

---

## 6. Motor de tareas (punto 5, aprobado)

### 6.1 Tipos de tarea
Con hora · del día de la semana · condicionadas (por un evento o un dato) · lanzadas por Administración · cola de tiempo libre.

### 6.2 Generación
La jornada se genera **una sola vez al día**. Reiniciar, abrir dos pestañas o perder la conexión **no duplica** ninguna tarea.

### 6.3 Obligatorias y flexibles
Es **un ajuste de cada tarea, no algo programado**. Se puede cambiar tras las pruebas.

| Obligatorias | Flexibles |
| --- | --- |
| Producción y bolsas del reparto antes de la salida · Recuento al final de cada turno · Envío por Nacex aprobado, antes de las 18:10 · Efectivo y reporte, si reparte él · Pedidos de clientes · Recepción de mercancía · Minis (lunes), resinas (martes, si toca), control de materiales (jueves) y limpieza de la estación de resinas (viernes) | Producción para el stock del almacén · Compras dentro de su fecha · Orden y limpieza general |

### 6.4 Encaje y prioridad
- **Una tarea con hora** entra al terminar la **referencia o bolsa en curso**, nunca a mitad de un pesaje ni al final de una lista entera. Si empieza tarde, se registra la hora real. **Si en ese momento no hay ninguna referencia empezada** (entre dos referencias de una tarea no obligatoria, como el +35 %, o en una tarea no obligatoria sin referencias, como «Orden y limpieza»), **entra en cuanto llega su hora**: lo que tenía en curso se pausa con lo hecho y vuelve a salir después (propietario, 06/11/2026: ese día la salida no saltó porque Eder terminó una referencia del +35 % a las 10:43 y no marcó otra hasta las 12:22). **Hecho en pruebas (Tarea 37, PR #41):** igual que al terminar una referencia, entra todo lo de los escalones 2 a 4: lo que tiene hora, **lo urgente** (Administración urgente, incidencia «ahora», mercancía) y **volver a llamar por un problema**. Lo obligatorio en curso no se pausa. Caso raro, dicho al propietario al revisar el PR y fusionado sin cambios: si a las 08:45 Eder sigue con la revisión inicial y el reparto aún no está guardado, la revisión se pausa y sale «Prepara el reparto» (no ha pasado ningún día desde el 27/10).
- **Las bolsas, justo después de la producción del reparto, sin nada en medio** (decisión del propietario, 03/11/2026): con la producción hecha y las bolsas sin terminar, solo salen las bolsas (y los pedidos de cliente para la tienda, que van en ellas). **Lo urgente y lo que tiene hora esperan a que terminen las bolsas**; solo entra un problema que abra el propio operario. **La salida del reparto no sale hasta que las bolsas están hechas**; si llega la hora de salida sin ellas, se le ofrece «Retrasar 15 min» / «Retrasar 30 min».
- **Lo primero de la mañana** (decisión del propietario, 02/11/2026; sustituye a la regla solo para tareas de Administración): la revisión inicial, «Prepara el reparto», la producción del reparto, las bolsas y, el viernes, la preparación del envío van **siempre antes que cualquier otra tarea**, venga de donde venga (Administración, arrastradas, +35 %, compras, incidencias). Siguen entrando lo urgente (Administración urgente, incidencia «ahora», mercancía), volver a llamar por un problema, lo que va a su hora (salida, Nacex, recuento), las de Administración con hora límite y los pedidos para recoger en tienda. En los huecos de espera, «Orden y limpieza». Solo por la mañana. Por la tarde, el envío ya va primero cuando está pegado; mientras se espera la decisión de Administración puede salir la fija del día (el propietario lo da por bueno).
- **Fuera del turno, ninguna tarea** (02/11/2026): tampoco lo urgente; espera al siguiente turno. Lo **obligatorio** que esté en curso se puede terminar pasada la hora (el recuento de las 12:45). Lo **no obligatorio** en curso (+35 %, compras, orden y limpieza, tareas de Administración sin hora) **se pausa solo al acabar el turno**, conserva lo hecho y vuelve a salir en el siguiente; en «Hoy» consta «interrumpida por fin del turno» y, si no se termina en el día, el cierre dice «Sin terminar: fin del turno». En «Hoy», cada tarea hecha dice **quién la hizo**.
- **El turno lo abre y lo cierra el operario** (propietario, 04/11/2026; Tarea 35, en curso; sustituye a la hora de fin del punto anterior): al llegar, **«Empezar turno»** (mañana y tarde); antes, ninguna tarea. El turno dura **hasta «Fin de turno»**: pasada su hora le siguen saliendo **las obligatorias** que no ha hecho (el recuento) y lo que tenga en curso; **lo no obligatorio espera al siguiente turno**; sin nada obligatorio, «Has terminado. Pulsa «Fin de turno»». **El cierre por correo sale al pulsar «Fin de turno»**; si se olvida, el turno se cierra solo al empezar el siguiente (o a medianoche) y el cierre dice que no lo cerró. Es la base para que después el «Fin de turno» llegue a las tiendas y para **fichar** (primero como control interno junto a Woffu). Sale del 04/11, 18:30: el Chromebook se durmió y, al despertarlo pasada su hora, Eder ya no tuvo «Recuento de stock y cierre». **Concretado con el agente (propietario, 04/11/2026, PR #39):** se puede empezar antes de la hora; empezar la tarde cierra sola la mañana; «Fin de turno» con obligatorias sin hacer, con confirmación (constan como no hechas); **el recuento no se puede dejar sin hacer**: «Fin de turno» lo pide en ese momento, aunque no sea su hora, para que la app vuelva a leer la hoja; un turno que no se empezó también tiene su cierre («No empezó el turno»); un turno que se cierra solo sin recuento no cuenta como recuento.
- **«Calcular» siempre recalcula** con la hoja del momento (02/11/2026): si se corrige la hoja, basta con volver a calcular; cada cálculo deja el anterior como «sustituido».
  - Urgente: entra al terminar lo que tiene entre manos.
  - Con hora límite: va al primer hueco que no ponga en riesgo una obligatoria.
  - Si no cabe sin sacrificar una obligatoria, se avisa a Administración **en el momento de lanzarla** y decide qué cede.
  - **Conflictos al crear una tarea de Administración** (decisión del propietario, 03/11/2026, tras pasar por error las bolsas a mañana): una tarea **no urgente y sin hora límite** no da conflicto con lo primero de la mañana (espera su turno por esa regla): se crea sin preguntar. **Lo que sale hoy, al reparto o a Nacex, nunca se puede pasar a mañana, dejar para después ni cancelar** desde la ventana de conflicto: producción del reparto, bolsas, salida, pedidos de cliente (para la tienda y por Nacex), preparación del envío, «Lleva en el reparto lo que va a Nacex» y la salida a Nacex («el envío a Nacex es envío a un cliente o a las tiendas: igual de importante», 03/11/2026). Cuando sí hay conflicto, la ventana pregunta **primero por la tarea nueva**: «Para mañana», «Que la haga después» o «No crearla»; mover otra tarea queda aparte y dice claramente cuál se mueve.
- Nada desaparece en silencio.

### 6.5 Estados y lo no terminado
**Estados:** pendiente · en curso · hecha · bloqueada (con un problema abierto) · arrastrada · cancelada por Administración.

**Lo no terminado:**
- Stock: se recalcula, no se arrastra.
- Compras y recogidas: siguen abiertas hasta que él confirma que ya lo tiene.
- Tareas de Administración: pasan al día siguiente como arrastradas.
- **Tareas fijas obligatorias** (minis, resinas, control de materiales, limpieza de resinas…): pasan al día siguiente como arrastradas y constan en el cierre con su motivo. Las ligadas a una hora o un turno (recuento, Nacex, salida del reparto, efectivo) no se arrastran: constan en el cierre como no hechas (decisión del propietario, 26/10/2026).
- **Lo del reparto y del envío de un día nunca pasa al día siguiente** (decisión del propietario, 04/11/2026, Tarea 29c): producción del reparto, bolsas, salida, preparación del envío y Nacex; si no se hacen, constan como no hechas en su día. **Los pedidos de cliente sí pasan** al día siguiente, como dice R1b, para que no se pierda ninguno.

### 6.6 Problemas e incidencias
**Botón «Tengo un problema»**, con cinco tipos: falta material · no encuentro algo · no sé cómo hacerlo · algo no funciona · otro.
1. Si la app da una solución directa, la aplica.
2. Si en 1 minuto no está resuelto, **llama a Administración** (botón de llamada en el Pixel).
3. Si no encuentra algo, llama en el momento.
4. Tras la llamada, escribe en una línea la solución acordada. **Regla: ningún problema pasa más de 5 minutos sin una solución definida.**
5. Si no le cogen el teléfono: envía un WhatsApp con el problema, la tarea queda pendiente y pasa a otra.
6. A los 30 minutos sin solución, le vuelve a aparecer la tarea de llamar. Si Administración le llama antes, apunta la solución y lo marca como resuelto.

**Incidencias (rediseño del propietario, 30/10/2026; sustituye a la tabla de abajo).** Hay dos vías:
- **Las que abre el operario** (botón Incidencia), con **tres opciones**:
  1. **Hay que comprar algo:** elige el producto de la **lista de compras** (§7). Según cómo se compra: **por internet** → tarea con el enlace (al hacerla queda «pedido, esperando a que llegue»); **en una tienda** → tarea «Ve a comprar X a [sitio]», con la dirección (al hacerla, se cierra); **lo pide Administración** → correo en el momento y «esperando a Administración». «Otra cosa» (lo que no está en la lista): una línea y correo a Administración.
  2. **Varios:** escribe lo que pasa → quién lo hace (él o Administración) → cuándo (ahora, hoy o cuando pueda) → Guardar. Sin subopciones (llega mercancía, Nacex, corregir… entran aquí).
  3. **Estoy bloqueado:** como siempre (el flujo de problemas de arriba).
  - «Pedido de cliente» ya no está en Incidencia: tiene su propio botón.
- **Los avisos de Administración para un día concreto** (lo que no depende solo de nosotros: «voy al Casco Viejo y llevo yo la bolsa de Bilbao», «un paquete está en reparto: contacto del repartidor»). Administración los crea en su panel («Aviso para el almacén»: día, texto y, si quiere, un contacto). Ese día le sale al operario arriba de la pantalla y queda abierto en sus incidencias hasta que lo cierra. No es una tarea; si además hay que hacer algo, se usa «Nueva tarea». Consta en el cierre.
- **Botón rojo:** mientras el operario tenga incidencias sin cerrar (suyas o avisos), al lado de «Cerrar incidencias» sale un botón rojo con el número.
- Lo que Administración encarga para hacer ya va por «Nueva tarea», como siempre.

**Modelo anterior** (decisión del propietario, 27/10/2026; sustituido el 30/10/2026 por lo de arriba). Cuando el operario se da cuenta de algo, pulsa **Incidencia**, elige qué pasa y escribe una línea:

| Opción | Quién la resuelve por defecto | Importancia por defecto |
| --- | --- | --- |
| Llega mercancía | Él | Ahora |
| Pedido de cliente | Él | Hoy |
| Hay que pedir o comprar algo | Él (consumibles) · Administración (materia prima y packaging, §7) | Hoy |
| Recogida en Nacex | Él | Hoy |
| Corregir, limpiar o solucionar algo | Él | Ahora |
| Estoy bloqueado | — | Es el flujo de problemas de arriba (la tarea se bloquea, llamar en 1 minuto, WhatsApp, volver a llamar a los 30 minutos) |

Él puede cambiar el «quién» y la importancia.
- **La resuelve él:** se convierte en una tarea según su importancia. **Ahora** entra al terminar la referencia o la bolsa en curso; **Hoy** va al primer hueco del día; **Cuando pueda** va a su cola de tiempo libre. Cuando hace la tarea, la incidencia se cierra sola. **Excepción:** si es una compra, al hacer la tarea queda «pedido, esperando a que llegue» y se cierra cuando el material está en el almacén.
- **La resuelve Administración:** a Administración **le llega un correo en el momento**. Queda «esperando a Administración» hasta que él la cierra, cuando Administración confirma que está resuelta o cuando el producto ya está en el almacén.
- **Cerrar incidencias** (botón de arriba, con el número de las abiertas): lista sus incidencias abiertas con su estado. Para cerrarlas escribe una línea opcional (por ejemplo, «Ya está en el almacén»).
- Cada incidencia queda registrada con su hora, su tiempo y su cierre, y aparece en el cierre del turno.
- «No quedan vapers» no es una opción: es un caso puntual y entra por «Hay que pedir o comprar algo» o por «Corregir, limpiar o solucionar algo».

**Botón «Tengo un problema»:** desaparece como botón. Es la opción «Estoy bloqueado» de Incidencia.

**«Hacer» fuera del plan no existe:** producir algo que se queda (cajas, stock) solo se hace si está en el plan.

### 6.7 Avisos
- **El operario solo ve tareas:** pendientes, en curso y acabadas. Nunca avisos de tiempo ni de presión. Excepciones, que también son tareas: una tarea nueva durante el reparto le llega al Pixel, y un problema sin resolver reaparece a los 30 minutos.
- **Excepción aprobada:** el retraso de la salida del reparto (botones de las 10:45) avisa en el momento a quien sale. Si sale Administración, le llega un correo corto («Salida retrasada a las HH:MM») y lo ve en la pantalla de inicio del panel (decisión del propietario, 26/10/2026).
- **Administración solo recibe el cierre:** uno por turno (13:00 y 18:30 de lunes a jueves; 13:00 el viernes), **por correo** (D2 y D3, decididos 26/10/2026). La advertencia de conflicto al lanzar una tarea no es un aviso: se ve mientras se crea.

### 6.8 Métricas
- Hora de inicio y fin de cada tarea.
- Ritmo de empaquetado: cajas por hora frente a su media (V1.1).

### 6.10 Duraciones de referencia (para avisar de conflictos)
- **Producción:** ~1 minuto por caja. La duración de la producción del reparto se calcula con las cajas que faltan.
- **Bolsas:** ~3 minutos por tienda. Más de 3 minutos indica que se ha olvidado algo.
- **Tareas de Administración:** Administración indica una duración orientativa al lanzarla. Solo sirve para detectar conflictos; la tarea termina cuando el operario la marca.
- Del mapa: recuento 15 min, limpieza de resinas 30 min, ruta del reparto ~2 h.

### 6.9 Aprobación que se convierte en autonomía
Las tareas de tipo «él propone, Administración aprueba» (envío a Gipuzkoa/Durango, pedido de packaging) pueden pasar a «las hace él solo» con un ajuste.

---

## 7. Aprovisionamiento

> **Lista de compras en la base de datos** (decisión del propietario, 30/10/2026): cada producto con su forma de compra (**por internet**, con enlace · **en una tienda**, con sitio y dirección · **lo pide Administración**). Administración la mantiene desde su panel (añadir, cambiar, quitar). Se carga de entrada con la tabla de abajo, con estos sitios (aprobados el 30/10/2026): supermercado y bazar chino, cualquiera; guantes de nitrilo en **Arte Sano Tattoo Supplies** (San Nicolás de Olabeaga 12, 48013 Bilbao; es la «Tatto Arte» de la tabla); rollos de TPV en **Kutxabank** (Avda. Lehendakari Aguirre 151, San Inazio, 48015 Bilbao; corregido por el propietario); **Retif Bilbao** en Máximo Aguirre 10, 48009. **La gasolina sale de la lista** (se ve conduciendo; no hace falta incidencia). La lista de compras va ya a la base de datos; el stock y el catálogo de productos siguen en la hoja hasta el final del proyecto.

**Regla:** cuando falta algo, se elige en el catálogo y la app da la solución en el momento. **La tarea no se cierra hasta que confirma que ya lo tiene en el almacén.** Toda mercancía se abre y se comprueba al llegar.

| Material | Dónde | Responsable |
| --- | --- | --- |
| Bolsas adhesivas pequeñas (resinas, extractos y flores de 4 g; 8×12 + 3 cm de solapa) | https://www.amazon.es/dp/B077ZQQ8Q5 | Operario: compra en el momento si lleva menos de 3 minutos; si no, al día siguiente |
| Bolsas adhesivas grandes (flores de 10 g; 10×15 + 3 cm de solapa) | https://www.amazon.es/dp/B073JN44TZ | Operario |
| Bolsas para vapers (mylar con sellado térmico, 5×18 cm) | https://www.amazon.es/dp/B0B6VFPF7F | Operario |
| Hojas de etiquetas adhesivas | https://www.amazon.es/dp/B004TV40R0 | Operario |
| Agujas luer lock | https://www.amazon.es/dp/B0DRVVTN1R | Operario |
| Jeringuillas luer lock (seleccionar 50 ml) | https://www.amazon.es/dp/B0DFMMMK5V | Operario |
| Alcohol, papel de cocina, papel de horno y limpieza | Supermercado | Operario |
| Guantes de nitrilo | Tatto Arte | Operario |
| Material de oficina, plástico de burbujas y cinta aislante | Bazar junto a la oficina | Operario |
| Rollos de TPV | Kutxabank, junto a la oficina | Operario |
| Gasolina | Gasolinera | Operario |
| Bolsas para tienda y plástico negro de embalar | Retif Bilbao | Operario o Administración, según el tiempo de cada uno |
| Cajas y pegatinas de packaging | Imprenta Sprint Digital | El operario avisa y pasa el recuento → Administración dice cuántas pedir → el operario pide y recoge |
| Paquetes y recogidas | Nacex Deusto | Quien provoca la recogida la da de alta. Recoge el primero que pase por Nacex. Sigue abierta hasta que llega al almacén. |
| Granel, aceites, cremas, distillate, CBDX, kief, terpenos y carcasas de vaper | Materia prima | Al operario le aparece la tarea «Avisa a Administración». Pide Administración. |

---

## 8. Interfaces (punto 4, aprobado)

**Estilo:** blanco y negro, con inspiración en Apple y Holded. **Color solo de forma puntual, para lo que tiene que llamar la atención** (decisión del propietario, 30/10/2026); de momento, únicamente el botón rojo con el número de incidencias sin cerrar del operario. **Excepciones para los avisos que necesitan más visibilidad** (decisión del propietario, 09/11/2026): el rojo vale también para los avisos urgentes que piden una decisión; de momento, el aviso de salida sin bolsas del operario (franja fija arriba y en rojo, hecha en Lovable el 09/11, T-0008). No se usa para presionar con el tiempo. **Marca (27/10/2026):** logotipo «ŌSASUN», isotipo «Ō» (favicon e icono) y tipografía geométrica cercana a la del lema. Las formas de colores de la marca solo se usan como acento en la pantalla de entrada; las pantallas de trabajo siguen siendo monocromas. Las referencias se distinguen por tipografía: el formato (4 g / 10 g) grande y en negrita, y la categoría escrita debajo.

### Operario
- **Chromebook:**
  - Una sola tarea en el centro, con su porqué en una frase.
  - **Abajo, dos botones:** el de la tarea (**Empezar** o **Terminada**) e **Incidencia** (§6.6).
  - **Arriba:** **Pegar reparto**, que pasa a **Modificar reparto** cuando ya hay uno, y **Cerrar incidencias** (§6.6).
  - Cambiar de dispositivo (Chromebook o Pixel) no altera nada: todo vive en el servidor.
  - Una línea abajo con lo que viene después.
- **Listas de producción:**
  - Aparecen todas las referencias. Él elige una, la termina y la marca, y elige la siguiente.
  - La lista de stock aparece ordenada por prioridad, con el motivo de cada referencia, pero el orden lo decide él.
- **Bolsas (Pixel):** una tienda por pantalla. Toca cada caja al meterla en la bolsa, porque esa es la comprobación. **Sin botón «Terminada»** (decisión del propietario, 30/10/2026): solo «Empezar» mientras no ha empezado; la tarea se cierra sola al marcar la última caja (y las peticiones y llamadas) y sale el aviso **«Bolsas listas para salida»**. Si falta una caja de verdad, Incidencia o corregir el reparto.
- **Lenguaje:** frases, no casillas. Por ejemplo: «Indoor: queda para menos de media semana. Avisa a Administración».

### Administración
- **Histórico** (decisión del propietario, 28/10/2026): con un calendario, cualquier día pasado. Muestra el reparto y el envío (quién salió, tiendas, cajas, peticiones especiales y «Copiar para WhatsApp»), los pedidos de cliente y los cierres de ese día. Solo consulta.
- **Inicio** (orden confirmado por el propietario, 29/10/2026), de arriba abajo:
  1. **Ahora:** en qué está el operario.
  2. **Avisos:** problemas e incidencias abiertas.
  3. **Productos con menos de 2 semanas** (R4): solo los que estén por debajo.
  4. **Hoy:** cada tarea con su hora de inicio, su hora de fin y los minutos que ha tardado. **Interrupciones** (decisión del propietario, 30/10/2026): si una tarea se interrumpe por otra (con hora o urgente), se ve aunque siga pendiente: «interrumpida a las 10:45 por «Salida del reparto»» y, si se retoma, «siguió a las 12:05»; todas, en orden. **En las tareas de producción** (reparto, +35 % y pedidos de cliente): «21 de 43 cajas · 31 min trabajados», donde los minutos son la suma de lo que ha tardado en cada producto, sin contar interrupciones ni la ruta.
  5. **Tiempo libre:** cuántas veces y cuántos minutos de «Orden y limpieza» (señal de que le sobra tiempo).
  6. **Pedidos de cliente.**
  7. **Arrastradas y cierres.**
  8. **Hoja y correos:** solo si hay algún error.
  - Abajo, los botones: Preparar/Modificar reparto, Preparar envío, Pedido de cliente y **Nueva tarea**.
  - **No se muestra «Almacén ahora»** (cuenta entre recuentos y cajas en camino): no le aporta al propietario. La app la sigue usando en sus cálculos (R1c). Lo que va en camino a Gipuzkoa o Durango se verá en la pantalla de esas tiendas (etapa 2).
- **Nueva tarea:** qué · para quién (almacén por defecto) · cuándo (hoy, un día o antes de una hora) · duración orientativa · urgente (no por defecto) · por qué (opcional). **Un solo botón, «Crear»** (decisión del propietario, 30/10/2026): si cabe, se crea de una vez y sale «Tarea creada»; solo si choca con una obligatoria se enseña qué cede. (El 30/10 una tarea no se creó porque el paso «Continuar» solo comprobaba.)
- **Cierre:** llega al móvil. Contiene lo hecho con su resultado, lo no hecho con su motivo, los problemas (tiempo y solución), las incidencias (tiempo), los pendientes arrastrados y lo que toca mañana. Los viernes, además, el indicador de calidad.
- **Ordenador:** histórico e indicadores.
- **Aprobaciones:** en la V1 siguen por WhatsApp.

---

## 9. Datos e integraciones

### Fuente de verdad (V1)
| Dato | Manda |
| --- | --- |
| Stock, consumos, catálogo de productos y variedades | **Google Sheets** (`STOCK OSASUN-CLAUDE`). La app **solo lee**. |
| Tareas, jornadas, registros, problemas, incidencias y cierres | **Supabase** |

### Documento `STOCK OSASUN-CLAUDE`
ID `1nPhB7U6FoJcYybChUcGOI3mz-yJAv8NkT3uINuQ6qao`

| Hoja | Contenido |
| --- | --- |
| PRINCIPAL | Cajas por tienda y almacén, peso total, granel del almacén y consumo semanal. **Catálogo maestro:** los nombres se cambian aquí y se propagan al resto. |
| VENTAS SKU | Unidades vendidas por tienda y producto en las últimas 4 semanas, con su media. |
| STOCK ALMACÉN DIARIO | Recuento del operario al cierre. Alimenta PRINCIPAL. |
| CONTEO DE CAJAS TOTAL | Cajas hechas en todas partes menos el consumo semanal. |
| Una hoja por tienda | Stock y consumo medio. Invernadero va por categoría, con las variedades debajo. |
| ALMACÉN · total en gramos · comparativa entre tiendas | Consulta y análisis. |

Notas:
- **Laudio ha cerrado y se sustituye por Durango.** En Sheets se mantiene el nombre LAUDIO por ahora; la app debe tratar LAUDIO como Durango.
- Los nombres exactos de las pestañas los confirma el agente de base de datos leyendo el documento.

**Acceso:** una cuenta técnica de Google (cuenta de servicio) con permiso **solo de lectura** sobre este documento. Se puede revocar en cualquier momento.

### Plantillas de ventas de las tiendas (no se leen en la V1)
`PLANTILLA VENTAS DIARIO` de Bilbao, Algorta, Barakaldo, Basauri y Portugalete.
- Funcionan como un TPV manual: reposición, inicio, ventas, total y fin por producto y día (lunes a sábado); Z, número de ventas, efectivo y Glovo por día; registro de tickets con regalos; pestañas SEMANA PASADA y FACTURACIÓN MENSUAL.
- La **tienda** apunta la reposición al recibir la bolsa.
- Son la base de datos de referencia para diseñar el TPV de la Etapa 3.

### Nombres reales verificados (agente de base de datos, Tarea 1)
- El título real del documento es **«STOCK OSASUN-CLAUDE»**, con guion.
- La pestaña real es **«STOCK ALMACEN DIARIO»**, sin tilde, y **no registra fecha**. Afecta a la verificación del recuento (R5, V1.1); se resolverá al llegar a la V1.1. En este documento, «STOCK ALMACÉN DIARIO» se refiere a esa pestaña.

- Pestañas que usa la V1: `PRINCIPAL` (catálogo, cajas y granel del almacén en la columna R), `CONTEO DE CAJAS TOTAL` (la columna «CAJAS TOTALES HECHAS» ya es el contador: hechas − consumo; incluye «INVERNADERO TOTAL» e «INDOOR TOTAL») y `ALMACEN` (categorías; el grupo indoor se llama «INDOOR POPS»). Las pestañas de tienda no se leen en la V1.

### Nombres irregulares detectados
«V2 » con espacio final · Krush en «20gr» · «T BALLS / GELATO DRY» (dos productos en una fila). Comprobado por el coordinador el 26/10/2026: los formatos de T BALLS (2g/4g) y KRUSH (20gr) **ya coinciden** entre PRINCIPAL y CONTEO DE CAJAS TOTAL. La app normaliza espacios y mayúsculas. La limpieza se hace en PRINCIPAL cuando Administración lo decida.

### Consulta de Sheets por los agentes
Los agentes pueden **consultar** Sheets con los conectores de Google de la cuenta de Claude del propietario, que tienen sus permisos completos. **Nunca escriben con ellos.** La app usa siempre la cuenta técnica de solo lectura.

---

## 10. Arquitectura (puntos 6 y 7, aprobados)

| Componente | Función |
| --- | --- |
| **Supabase** | Base de datos central, usuarios, permisos (en el servidor), lógica crítica (cálculos y motor), tareas programadas (generar la jornada, enviar el cierre) y lectura de Sheets. |
| **Lovable** | Pantallas: las del operario y el panel de Administración. |
| **GitHub** | Dos repositorios privados (decisión del propietario, 27/10/2026): `Osasun-Op/osasun-operations`, la **fuente de verdad** (base de datos, funciones del servidor y `docs`), y `Osasun-Op/osasun-pantallas`, creado por Lovable **solo para las pantallas** (Lovable no puede trabajar sobre un repositorio que ya existe). |
| **Claude Code en la web** | Entorno en la nube del agente de base de datos. Clona el repositorio en una máquina aislada y entrega sus cambios como rama para revisión. Acceso solo a este repositorio. |

**Condiciones obligatorias:**
1. **Dos entornos, pruebas y producción.** Lovable trabaja siempre contra pruebas. A producción solo pasa lo probado.
2. **La lógica crítica vive en Supabase.** Las pantallas solo muestran y solicitan. El navegador no decide permisos, cálculos ni estados críticos.
3. **Google Sheets en solo lectura** mediante la cuenta técnica.
4. **Lovable tiene prohibido crear o cambiar tablas.** No se activa la integración de Supabase en Lovable: Lovable solo recibe la URL del proyecto y la **clave pública**, y usa únicamente las funciones de `CONTRATOS.md` (decisión del propietario, 27/10/2026).
5. **Claves de API (autorizado por el propietario, 26/10/2026):** los agentes del proyecto pueden recibir las claves que necesiten para su trabajo, con estas reglas:
   - Se guardan como **secretos o variables del entorno** donde se usan (entorno en la nube de Claude Code, Supabase, Lovable). Nunca en el repositorio, en documentos ni pegadas en conversaciones.
   - **Una clave por entorno y por uso**, con el mínimo permiso necesario. Las de producción solo se entregan cuando se apruebe la puesta en marcha.
   - **La clave maestra de Supabase (service role) nunca va en las pantallas.** Lovable usa solo la clave pública, y los permisos los aplica la base de datos.
   - Todas son **revocables**. Si una clave se expone, se cambia en el momento.

**Coste estimado:** en torno a 100 € al mes en total (estimación del propietario). Contratado a 27/10/2026: **Lovable Pro** (unos 25 $ al mes). Supabase, Google Cloud y Resend siguen en sus planes gratuitos mientras estemos en pruebas.

**Descartado:** AppSheet y Apps Script (no permiten llegar a la Etapa 3 sin rehacer, y la lógica sería frágil), otras herramientas low-code (dependencia alta) y un servidor propio (mantenimiento).

---

## 11. Organización de agentes

| Agente | Alcance | Prohibido |
| --- | --- | --- |
| **Coordinador** (desde el 07/11/2026, en el proyecto de Claude «Desarrollo de software operativo»; sus instrucciones y el sistema de tickets están allí, en `claude/agentes/AGENTE_COORDINADOR.md` y `claude/coordinacion/SISTEMA_TICKETS.md`) | Comunicación con el propietario, reparto de trabajo con tickets, revisión de los PR con su descripción y contratos entre módulos. En este repositorio solo lee | Decisiones de negocio. Escribir código. Escribir en este repositorio o en Supabase. |
| **Base de datos** | El único que toca Supabase: tablas, permisos, funciones, motor de tareas, cálculos y lectura de Sheets. Trabaja **siempre en un entorno en la nube**. | Pantallas. Usar el ordenador del propietario. |
| **Pantallas del almacén** (desde el 07/11/2026, en el proyecto de Claude «Desarrollo de software operativo»; instrucciones en `claude/agentes/`) | Pantallas del operario: Chromebook y Pixel | Crear o cambiar tablas. Si necesita datos nuevos, lo pide al coordinador. |
| **Pantallas de la tienda** (ídem) | La tablet de las tiendas | Crear o cambiar tablas. Si necesita datos nuevos, lo pide al coordinador. |
| **Pantallas del panel de Administración** (ídem) | El panel de Administración | Crear o cambiar tablas. Si necesita datos nuevos, lo pide al coordinador. |

**Los tres agentes de pantallas** dan órdenes a un solo proyecto de Lovable, una orden a la vez y con la aprobación del propietario (decisión del propietario, 07/11/2026).

**Contrato entre módulos:** las pantallas solo usan las funciones y vistas que publica el agente de base de datos. Cualquier dato o función nueva se pide al coordinador, que la encarga al agente de base de datos.

**Cómo se trabaja desde el 07/11/2026** (decisión del propietario):
1. **El trabajo se organiza con tickets** (T-XXXX).
2. **Las tareas del agente de base de datos le llegan como encargo copiado por el propietario,** con su número de ticket.
3. **El agente entrega un PR.** El PR pone al día también este documento (y su cabecera) cuando cambia una regla.
4. **El coordinador lo revisa con la descripción del PR.**
5. **Lo fusiona el agente de base de datos, solo con el «sí» expreso del propietario a ese PR,** que lo da después de revisarlo con el coordinador. Antes de fusionar, el agente comprueba que la rama sigue en el commit revisado; después dice el commit que queda en `main`. A mano (el propietario), solo como excepción (decisión del propietario, 09/11/2026).

Todo entra por PR, también este documento (constitución, regla 7). Las instrucciones de las pantallas (Lovable) están en el proyecto de Claude y en el Knowledge de Lovable.

---

## 12. Alcance (punto 8, aprobado)

| Versión | Incluye |
| --- | --- |
| **V1 (MVP)** | Usuarios (Administración y operario) · Jornada automática según el mapa, con obligatorias y flexibles · Pantalla de tarea activa con Terminada, Tengo un problema e Incidencia · Nueva tarea desde el panel (urgente, con hora y aviso de conflicto) · **Lectura de Sheets:** reparto pegado (R1) y stock +35 % (R3) · Listas de producción en las que él elige el orden · Bolsas en el móvil, tocando cada caja · Horas, estados y tareas arrastradas · Cierre al móvil |
| **V1.1** | Aviso del jueves (R4) · Verificación del recuento (R5) · Catálogo de materiales con enlaces y tareas abiertas hasta confirmar · Recogidas en Nacex · Ritmo de cajas por hora · Promociones y el porqué de cada tarea |
| **Después** | Etapa 2 · Escritura en Sheets · Etapa 3 |

---

## 13. Pruebas y aceptación (punto 9, aprobado)

**Fases:**
1. Entorno de pruebas con datos de prueba. El agente de base de datos prueba y el coordinador revisa.
2. Una semana real en paralelo (lunes a viernes). Administración compara los números de la app con su propio cálculo. Si algo falla, se corrige y se repite.
3. Puesta en marcha solo si se cumplen todos los criterios.

| Área | Se acepta si… |
| --- | --- |
| Jornada | En una semana simulada (días con y sin envío, reparto suyo y de Administración), cada tarea aparece el día y a la hora correctos |
| Duplicados | Reiniciar, abrir dos pestañas o perder la conexión no duplica nada |
| Reparto | En 5 repartos reales, la suma y lo que falta coinciden exactamente con el cálculo de Administración |
| Stock (+35 %) | La lista coincide con el cálculo manual de un día, en el orden correcto |
| Tareas de Administración | La urgente entra al terminar la referencia en curso. La que no cabe avisa al lanzarla. |
| Problemas | Funciona el flujo de 5 minutos y la reaparición a los 30 minutos |
| Cierre | Llega al móvil con datos correctos |
| Permisos | El operario no puede ver ni tocar el panel. La cuenta técnica solo lee Sheets. |
| Dispositivos | Funciona en el Chromebook y en el Pixel |
| Uso real | El operario completa una jornada sin ayuda tras una explicación corta |

---

## 14. Decisiones abiertas y pendientes

| # | Tema | Estado |
| --- | --- | --- |
| D1 | Redondeo de las cajas a hacer en R3 | **Decidido:** hacia arriba |
| D2 | Cierre: uno al terminar la jornada o uno por turno | **Decidido:** uno por turno |
| D3 | Canal del cierre al móvil | **Decidido:** correo |
| D4 | Confirmar si las tiradas de vapers siguen repartidas entre 2 tipos | Por confirmar |
| D5 | Comprobar si los avisos por correo del formulario de incidencias de tiendas le llegan al operario | Por comprobar |
| P1 | Limpieza de Drive: carpetas ordenadas, archivar copias y «ERROR PLANTILLA…» | Pendiente, fuera de la V1 |
| P2 | Limpieza de nombres irregulares en PRINCIPAL («V2 », «20gr», «T BALLS / GELATO DRY») | Pendiente |
| P3 | Cuenta de GitHub de Osasun y repositorio privado `Osasun-Op/osasun-operations` | Hecho: creado y conectado al proyecto (lectura) |
| P4 | Proyecto Supabase de pruebas | Hecho (26/10/2026): ref `rvypswuoafnjwqdwxjvo`, región Irlanda (eu-west-1). Acceso de los agentes mediante el conector de Supabase de Claude, sin claves pegadas. Renombrar a «osasun-pruebas». Antes de crear producción se decide cómo se separa su acceso. |
| P5 | Cuenta técnica de Google (solo lectura) | Hecho (26/10/2026): `osasun-lector-sheets@osasun-operations.iam.gserviceaccount.com`, permiso Lector sobre `STOCK OSASUN-CLAUDE`, comprobado por el coordinador. Proyecto de Google Cloud `osasun-operations` con Google Sheets API activada. La clave se creará al programar la lectura y se guardará como secreto de Supabase. |
| P6 | La hoja `STOCK OSASUN-CLAUDE` tiene activado «cualquier persona con el enlace puede ver» | **Decidido (26/10/2026):** se mantiene así hasta terminar la Etapa 3; entonces se revisa |
| E2-1 | Etapa 2: las variedades indoor agrupadas en tiendas hacen que algunas se queden atrás | Para la Etapa 2 |
| E2-2 | Etapa 2: comparar la reposición apuntada por la tienda con lo enviado; si no cuadra, se soluciona o se avisa | Para la Etapa 2 |
| E2-3 | Etapa 2: pedido de cliente con las tiendas conectadas. Al apuntarlo, la app mira si hay en el almacén o en alguna tienda; si no hay en ningún sitio, no se puede hacer. Si no hay en el almacén, sale para preparar cogiéndolo de otra tienda (reutilizar R1e, Tarea 16). Hasta entonces, los pedidos de cliente se quedan como están (decisión del propietario, 29/10/2026). | Para la Etapa 2 |
| E2-4 | **Visión de la app de tiendas** (propietario, 01/11/2026). (1) Al abrir la app, **todas las tareas del día en una lista**, cada una con su hora orientativa; **no se pueden marcar antes de esa hora**. (2) **Avisos** de almacén o Administración: al entrar, se leen y se marcan como leídos (siempre al entrar). (3) **Semanales:** revisar muestras (que estén en buen estado); **revisar productos atascados** (avisar de lo que se queda atrás: otra tienda lo pide, almacén lo recoge o se hace una promoción; queda como incidencia abierta hasta tener respuesta y meterlo en la bolsa de recogida o promocionarlo); limpieza de cristales y similares. Diferencia con el almacén: la tienda ve la lista entera, no una sola tarea. Reutilizar lo que ya existe (avisos de Administración, incidencias, «coger de otra tienda» de R1e, el motor de tareas por centro). | Para la Etapa 2 |
| E2-5 | **Operativa diaria de las tiendas** (propietario, 01/11/2026). Tiendas propias: Bilbao, Algorta, Barakaldo, Basauri, Portugalete y Durango (pronto); **Donosti y Rentería son franquicias: su panel no tiene tareas**. **Mañana:** fichar (hoy con Woffu; en el futuro, con la app), abrir, Glovo, cartel fuera, leer las comunicaciones, poner a punto. Durante la mañana llega el reparto (Eder o Administración avisan por teléfono antes de llegar): la tienda sale a por la bolsa de reposición y entrega **la bolsa del día anterior con la Z impresa y el efectivo** (lo cuenta el almacén). **Estaría bien que la tienda vea cuándo ha salido el reparto y por dónde va.** La reposición se coloca y se apunta (hoy, columna «Reposición» de su hoja; hasta que no rellenan «Fin de día», STOCK OSASUN no se actualiza). Durante el turno apuntan cada venta; al cierre de turno, el «Fin de día» contado tiene que cuadrar (todo en verde). **Tarde:** lo mismo sin reposición; al cierre comprueban que cuadran cuaderno, hoja y Z, separan el efectivo y lo meten en la bolsa para el día siguiente. **Glovo:** se cobra en su máquina; descuenta stock y se apunta, pero no cuenta en la Z ni en el efectivo (su facturación va aparte). Checklist orientativo de mañana y tarde en `AGENTE_COORDINADOR.md` (01/11/2026). Objetivo: excelencia, seguimiento e interrelación de las tiendas como marca; la app irá sustituyendo las hojas. | Para la Etapa 2 |
| E2-6 | **Datos de las tiendas y salida de las hojas** (propietario, 02/11/2026). Hoy: cada tienda rellena su plantilla «VENTAS Y STOCK»; un script de Google (en «CONTROL SEMANAL STOCK - CLAUDE») copia cada hora a su control semanal y el fin de día a STOCK OSASUN (PRINCIPAL), y cada domingo vuelca los totales a «EVOLUCIÓN VENTAS» y reinicia las plantillas. El **control semanal** es el histórico de ventas por día y tienda; la **evolución** es el histórico semanal en gramos por categoría y tienda (desde 2024). Laudio ya se ha cambiado por **Durango** en las plantillas y hojas. **Donosti y Rentería son de cesión pero operan como franquicias** (no son propias: sin tareas). **Objetivo: dejar atrás las hojas y las automatizaciones frágiles; todo pasará al software y a la base de datos**, con los datos claros (ventas por día, evolución semanal) y la operativa diaria de tiendas, almacén y Administración conectada. **Paso intermedio aceptado:** las tiendas apuntan en la app y la app escribe en la plantilla de cada tienda (las mismas columnas que hoy), para que el script siga moviendo lo demás mientras dure la transición; nunca directamente en PRINCIPAL (el script lo sobrescribiría). **Reposición** (propietario, 04/11/2026): hoy la tienda apunta la reposición en su plantilla y llega a la hoja con el «FIN DE DÍA» (con la tarea, pasará a ser al cierre del turno); **lo óptimo es que, cuando la tienda confirma en la app «Reposición metida, todo bien» (o «Falta algo», sin lo que falta), el stock de la tienda quede actualizado en ese momento** (en el paso intermedio, la app apunta la reposición en la plantilla de la tienda). Hasta entonces, la app cuenta esas cajas como «en camino» a la tienda hasta las 23:30 (R1c). | Para la Etapa 2 |
| E2-7 | **Dos entornos** (decisión del propietario, 02/11/2026): **producción** (`osasun-produccion`, plan Pro con copias de seguridad diarias), la que usan el almacén y las tiendas, donde solo entra lo aprobado; **pruebas** (`osasun-pruebas`), donde el agente prueba. Producción empieza limpia (opción A): solo cuentas autorizadas, configuración y lista de compras; el histórico de pruebas se queda allí como archivo. **Más adelante se importará el histórico real** de las hojas del propietario (control semanal y evolución). Los dos entornos **leen la misma hoja STOCK OSASUN** (solo leer: no se molestan). Cuando llegue el puente del bloque 2, **solo producción escribirá en las hojas reales**; pruebas nunca. El cambio de Eder y Administración a producción se hace cualquier día, en cuanto esté montada. **Producción montada el 02/11/2026** (Tareas 25 y 26). **Hasta el cambio** (cuando lo decida el propietario, en fin de semana): se sigue trabajando en pruebas, y **todo lo que se apruebe, se pruebe y funcione bien se pasa a producción** al fusionarlo (`AUDITORIA.md` §5), para que el día del cambio no quede nada pendiente. **Excepción, tiendas:** lo de tiendas se prueba primero en pruebas (Basauri y Portugalete) y no pasa a producción hasta que el propietario lo apruebe; desde la Tarea 27 producción espera (46 migraciones) y lo siguiente se pasa junto, en orden. | En curso |
| E2-8 | **Bloque 1 de tiendas: operativa diaria en la app** (propietario, 02/11/2026; detalle punto a punto en `AGENTE_COORDINADOR.md`, puntos 1 a 28). **Sentido:** la app de tienda es control y guía; lo importante son las ventas y que las tiendas se relacionen y aprendan. **Tiendas:** Bilbao, Algorta, Barakaldo, Basauri y Portugalete (Durango, cuando abra). **Donosti y Rentería (franquicias): regla general (propietario, 04/11/2026): se tratan como tiendas propias en todos los aspectos.** Solo cambian dos cosas: (1) **la logística**: donde una propia usa el reparto, ellas usan el envío; (2) **las tareas del día a día de su gente** las gestionan ellas. Las diferencias concretas que siguen son las que ha decidido el propietario y encajan en esas dos (apuntan en STOCK OSASUN y forman parte del stock y la operativa de producto). **Cada tarea se activa por tienda**: todo se construye igual para todas y, si hay que quitar o esconder algo a una tienda, se hace por configuración. **Qué tienen las franquicias** (propietario, 03/11/2026): avisos de Administración y del almacén, vídeo de la semana, muestras (jueves) y atascados (martes), igual que las propias; **incidencias**: un solo cuadro de texto libre (sin descuadres ni «sin producto»), que llega a Administración como incidencia abierta; **«Envíos»** en lugar de «Recibe la bolsa»: una pestaña «Envíos» arriba, junto a «Avisos», con lo que les llega (lo marcado al meterlo en la caja). **El envío cuenta cuando se termina «Prepara el envío aprobado»** (vaya quien vaya al reparto, también el viernes) y **se ve desde el día siguiente**; como no se sabe cuándo llega, no es una tarea con hora: queda ahí, con un número, hasta que la confirman con «Todo bien» o «Falta algo» (eligiendo qué; llega a Administración como incidencia abierta); al confirmarlo desaparece; se ven los de los últimos 7 días. **El envío a Gipuzkoa lo ve y lo confirma solo Rentería**, que lo reparte con Donosti (el envío se calcula con las dos tiendas juntas); **Donosti no tiene «Envíos»** (propietario, 03/11/2026, PR #31); **cierre de caja** solo con la Z y el número de ventas (sin efectivo ni Glovo), en una tarea «Cierre de caja» 10 minutos antes de cerrar (20:20 entre semana; 13:20 el sábado, que cierran por la tarde). **No tienen:** pedir material (se encargan ellos), aperturas, cierres de turno, cristales, bolsa del reparto ni «por dónde va el reparto». **Durango** (cuando abra) es **tienda propia** con todo lo de las propias; la única diferencia es que recibe por **envío** en vez de bolsa del reparto, así que tiene la pestaña «Envíos» en lugar de «Recibe la bolsa». Esto sustituye a «franquicias sin tareas» de E2-5 y E2-6. **Prueba en Basauri y Portugalete**, en **tablet** tipo Galaxy Tab A8 (pantallas táctiles, horizontal y vertical). **Horario:** L–V 11:00–13:30 y 17:00–20:30 (Bilbao, tarde desde las 16:30); sábados igual pero cierran a las 19:30, salvo Bilbao (20:30 todos los días); las franquicias, igual, pero cierran el sábado por la tarde. Domingos, nada. **Festivos:** Administración marca «cerrado» un día para una tienda o para todas; si no marca, día normal. **Acceso:** cuenta de Gmail de cada tienda; al empezar el turno, la persona elige su nombre de la lista de la tienda (queda como «hecha por»); Administración añade y quita nombres. **Lista del día:** la tienda ve todas sus tareas con hora orientativa; no se marcan antes de su hora; **sin avisos ni rojo por retraso** (hay gente entrando y saliendo): se marcan al hacerlas, y lo que no se hace queda como no hecho al final del día. Avisos de Administración al entrar, que se marcan como leídos; **el almacén también puede mandar avisos a las tiendas** (03/11/2026): ve y cancela los suyos, no los de Administración; Administración ve y cancela todos. **Diarias:** apertura de mañana desde las 10:50 (una tarea con puntos: fichar en Woffu, abrir, cartelería, Glovo, barrido y puesta a punto); apertura de tarde igual desde 10 minutos antes (fichar, abrir, cartelería, Glovo); «Recibe la bolsa» al salir el reparto (solo bolsa recibida + «bolsa de ayer entregada con X € en efectivo», X = efectivo del cierre de caja anterior, o la cantidad y el motivo; sin lista; **si el reparto no ha pasado algún día por la tienda, X es la suma del efectivo de todos los cierres que aún no se han entregado** (propietario, 04/11/2026); **el lunes, siempre el del viernes más el del sábado**, porque el sábado no hay reparto (propietario, 04/11/2026, PR #38); si un sábado se recoge algo, la tienda lo pone con «otra cantidad» y su motivo) y después «Coloca y apunta la reposición» con la lista de lo que trae («todo bien» o «falta algo»); **lo que trae es lo que el almacén ha marcado como metido en la bolsa** (03/11/2026); **las cajas que vienen de otra tienda (R1e) salen en la lista de la que recibe, en la línea de su producto, desde que el operario marca «Avisa a [origen]…», y la tienda de origen recibe un aviso en ese momento** (propietario, 11/11/2026; Tarea 38); las demás tiendas ven por dónde va el reparto; cierre de la mañana desde las 13:20 (plantilla al día y en verde, incidencias registradas); cierre del día desde 10 minutos antes de cerrar (plantilla en verde, suelo fregado, **cierre de caja en la app: Z, nº de ventas, efectivo y Glovo**, efectivo en la bolsa, incidencias registradas). **Semanales** (por la mañana; en Bilbao, alternando mañana y tarde por semanas): martes, productos atascados; jueves, revisar muestras (y elegir qué traer nuevo) y, por la tarde, **«Limpieza semanal: cristales, polvo y baños»** (un toque, sin casillas: la limpieza no se controla; propietario, 04/11/2026); viernes, **vídeo de la semana** (texto aprobado: sobre cannabis y CBD, cultivos y variedades, extracciones, cultura cannábica o ingredientes de la crema; enlace de YouTube y una línea de lo aprendido; queda en una lista que ven todas las tiendas; el sábado sale a quien trabaje si no ha compartido esa semana, **como tarea de su lista a la hora de abrir de su turno (11:00 por la mañana; 17:00 por la tarde, Bilbao 16:30), después de la apertura**: lo primero es siempre fichar, Glovo y carteles (propietario, 04/11/2026); cada persona, como mucho uno por semana; «Hoy no he podido» la cierra sin enlace y no pasa al día siguiente). **Atascados:** eligen de la lista cuántas cajas no se mueven (incidencia abierta); se pregunta a **todas** las demás tiendas, franquicias incluidas, todo el martes («Las quiero»; se lo lleva la primera que lo pide); si nadie, Administración decide el miércoles por la mañana (promoción o almacén; la promoción se cierra cuando la tienda pulsa «Ya no queda»); si hay que moverlo, incidencia abierta para Eder sin tocar el reparto y aviso a la tienda que lo tiene. **Franquicias** (propietario, 04/11/2026; operan igual, solo que lo del reparto les va por envío): si una franquicia **pide** un atascado de otra tienda, Eder lo recoge y lo lleva al almacén, y va **en el siguiente envío a esa franquicia**, sea cuando sea; si una franquicia **tiene** un atascado, **no se ofrece a las demás: va directo a Administración**, que decide promoción o recogida (la recogida la organiza Administración y, cuando llegue, le manda a Eder una tarea o un aviso). **Durango, igual** (recibe por envío; PR #34). **El texto de la promoción lo escribe Administración.** Cuando lo pide una tienda que recibe por envío, la petición para su siguiente envío **se crea al cerrar Eder la recogida** (ya está en el almacén). Lo que nadie pide pasa a Administración al abrir la app el miércoles. **Incidencias de tienda** (sin foto ni urgencia; en las franquicias, solo texto libre, ver arriba): material de tienda → siguiente reparto; me quedo sin producto → llamar a Administración y queda apuntado con el producto (incidencia abierta para Administración; 03/11/2026); descuadre de stock o caja, comentario de cliente y otros (con texto) → Administración, incidencia abierta con aviso en la app. Las muestras, en su tarea del jueves; «a deber» sigue en negativo en la plantilla; cualquier otra necesidad de cliente, como **pedido de cliente creado por la propia tienda** (mismo cauce que hoy; **solo para recoger en su tienda**, nunca por Nacex; todas las tiendas, franquicias incluidas; 04/11/2026). **Panel de Administración:** lista de centros (tiendas y almacén); al tocar uno, resumen de ahora: quién está, tareas hechas y pendientes, bolsa, incidencias abiertas y cierre de caja. Las franquicias salen con lo que tengan activado. Solo informa: cada cosa llega sola a quien toca. **Cómo queda el panel** (propietario, 04/11/2026): arriba, **pestañas** con los centros (Almacén y cada tienda), cada una con su dashboard. **Menú «Tiendas»:** Personas, Incidencias, Cierres de caja, Días cerrados y Vídeos. **Cierres de caja:** en el dashboard de cada tienda y, en el menú, todos juntos con un **total por día**: las tiendas propias por un lado (Z, ventas, efectivo y Glovo) y las franquicias por otro (Donosti y Rentería: Z y ventas); si una tienda no ha cerrado ese día, «Falta [tienda]». **Las peticiones de las tiendas** (muestras y material) **salen del menú**: siguen llegando solas a «Preparar reparto» / «Preparar envío» (con «No va») y a la bolsa de Eder. **Avisos unificados:** un solo botón «Avisos» abajo (sustituye a «Aviso para el almacén» y a «Avisos» del menú «Tiendas»): para el almacén, una tienda o todas, el día y, solo para el almacén, un contacto; ahí se ven los mandados, con «Leído» y «Cancelar». **Marcas en las pestañas** (propietario, 04/11/2026): un **círculo rojo con número** = lo que tiene que resolver Administración (en una tienda, sus incidencias abiertas y los atascados por decidir; en el almacén, los problemas abiertos del botón «Resolver»), que se quita al cerrarlo o decidirlo; **«N sin hacer»**, en texto y sin color = las tareas que la tienda dejó sin hacer al cerrar, **hasta que Administración entra en esa tienda**; **«sin abrir»**, en texto y sin color = media hora después de la apertura sin nadie en turno (sirve también para un festivo sin marcar). Si hay varias, juntas: «Basauri ●2 · 3 sin hacer». Sustituyen al aviso del «Resumen del día». **Concretado con el agente (propietario, 04/11/2026, PR #37):** «sin abrir» sale solo mientras dura ese turno (se quita al empezarlo alguien o al acabar el turno); «N sin hacer» cuenta los últimos 7 días; en los totales de cierres, «Falta [tienda]» también en los días anteriores a que la tienda usara la app (solo pasa en pruebas: producción empieza de cero). **Resumen del día:** ~~al cerrar, aviso en la app solo si alguna tienda ha dejado tareas sin hacer~~ → sustituido por las **marcas en las pestañas** (propietario, 04/11/2026; ver «Cómo queda el panel»). **Se encarga en tres tareas de BD**: (1) acceso, personas, horario, festivos, lista del día, aperturas, cierres, cristales y vídeo; (2) bolsa, seguimiento del reparto, cierre de caja, muestras y material de tienda; (3) incidencias de tienda, atascados, panel y resumen del día. | En curso: Tareas 27 y 28 hechas en pruebas (PR #26 y #27) |
| E3-1 | Después de la etapa 2: **previsión del reparto** (la app propone, Administración decide; exige cambiar la regla «la app nunca propone cantidades»). Datos: el historial de repartos y envíos de la app, las ventas diarias de la etapa 2 y el **histórico del propietario en sus hojas de Google** (ventas por día y tienda de meses, y evolución de ventas por producto y tienda de años), que se importará entonces. No hace falta guardar copias diarias antes (decisión del propietario, 30/10/2026). | Después de la etapa 2 |

---

## 15. Historial

| Versión | Fecha | Cambio |
| --- | --- | --- |
| 1.0 | 26/10/2026 | Diseño de los puntos 1 a 9 aprobado por el propietario. Documento creado. |
| 1.1 | 26/10/2026 | Repositorio creado y conectado. El agente de base de datos trabajará en Claude Code en la web. |
| 1.2 | 26/10/2026 | El propietario autoriza dar claves de API a los agentes. Añadidas las reglas de custodia de claves (§10, condición 5). |
| 1.3 | 26/10/2026 | Nombres reales de la hoja verificados por el agente de BD (§9). Regla de consulta de Sheets por los agentes. El coordinador pasa a una sesión de Claude Code en la nube con acceso directo al repositorio. |
| 1.4 | 26/10/2026 | Revisión del PR #1. Decididos D1 (redondeo hacia arriba), D2 (cierre por turno) y D3 (correo). Duraciones de referencia (§6.10) y duración orientativa en Nueva tarea. Tiendas en el reparto, reparto corregido, minis y FIFO (§5). Pestañas de la V1 y formatos de T BALLS/KRUSH comprobados (§9). |
| 1.5 | 26/10/2026 | Proyecto Supabase de pruebas creado y conectado mediante el conector de Claude (P4). |
| 1.6 | 26/10/2026 | Cuenta técnica de Google creada y comprobada (P5). Acceso público por enlace a la hoja de stock (P6): se mantiene hasta terminar la Etapa 3. |
| 1.7 | 26/10/2026 | Dudas secundarias del PR #1: destinos del envío, obligatorias no terminadas, pedidos de cliente y bolsas a las 10:45 con aviso de retraso. |
| 1.8 | 26/10/2026 | Papeles de resinas fuera de la V1. PR #1 aprobado y fusionado: `MODELO_DATOS.md`, `CONTRATOS.md`, `REGLAS_CALCULO.md` y `PLAN_TECNICO.md` son la base técnica (los ajusta la Tarea 2). Tarea 2 encargada. |
| 1.9 | 26/10/2026 | Revisión de la Tarea 2 (PR #2). Acceso con cuenta de Google. Envío del viernes antes de las 10:45. |
| 1.10 | 26/10/2026 | PR #2 aprobado y fusionado: estructura base y jornada automática en pruebas. Tarea 3 encargada. |
| 1.11 | 26/10/2026 | Revisión de la Tarea 3 (PR #3). El envío descuenta el reparto del mismo día antes del recuento. |
| 1.12 | 26/10/2026 | PR #3 aprobado y fusionado: reparto y stock con lectura de Sheets, en pruebas. Tarea 4 encargada. Servicio de correo: Resend (plan gratuito). |
| 1.13 | 27/10/2026 | PR #4 aprobado y fusionado: motor completo en pruebas. Pantallas en un repositorio aparte de Lovable, sin integración de Supabase (solo clave pública). Tarea 5 encargada (acceso con Google). |
| 1.14 | 27/10/2026 | PR #5 aprobado y fusionado: acceso solo con Google y lista de cuentas autorizadas en pruebas. Instrucciones del agente de pantallas (`AGENTE_ALMACEN.md`). |
| 1.15 | 27/10/2026 | Primera prueba real de la pantalla del operario. Nunca sin tarea: se adelantan las fijas de la tarde y «Orden y limpieza» no se gasta. «Pega el reparto» se cierra al aceptarse un reparto. |
| 1.16 | 27/10/2026 | Botón «Incidencia» con las situaciones generales del manual; nuevo botón «Cerrar tarea» para lo pedido sin recoger y lo que se ha quedado atrás (§6.6 y §8). |
| 1.17 | 27/10/2026 | Nuevo modelo de incidencias (quién la resuelve, importancia, correo a Administración, «Cerrar incidencias»); «Tengo un problema» pasa a ser «Estoy bloqueado»; dos botones abajo; el reparto lo puede pegar también Administración y hay «Modificar reparto». |
| 1.18 | 27/10/2026 | El propietario contrata Lovable Pro (el plan gratuito se quedó sin créditos en la Tarea 2 de pantallas). |
| 1.19 | 27/10/2026 | Marca de Osasun aplicada a las pantallas (logotipo, isotipo y tipografía); las formas de colores solo en la pantalla de entrada. Tarea 2 de Lovable terminada. |
| 1.20 | 27/10/2026 | Desplegable «¿Quién sale?» al pegar el reparto (manda sobre `SALE:`). Se adelanta el panel de Administración para poder probar el sistema completo. |
| 1.21 | 28/10/2026 | Prueba real en el almacén: el texto del WhatsApp no coincide con los nombres de PRINCIPAL (36 de 52 líneas). **R1 rediseñada:** el reparto se prepara en la app con una lista de productos de PRINCIPAL y contadores − y +; se quita pegar texto; «Copiar para WhatsApp». |
| 1.22 | 28/10/2026 | Destinos del reparto y del envío fijados (Tarea 10). |
| 1.23 | 28/10/2026 | Pedidos de cliente con la lista (recoger en tienda en bolsa aparte con su tarea, o envío por Nacex). La lista con − y + es la pieza central reutilizable. |
| 1.24 | 28/10/2026 | Orden de los pedidos (primero lo oficial; «coge / haz»). R1c: cajas en camino del almacén a las tiendas hasta la mañana siguiente, solo en los cálculos de la app. |
| 1.25 | 28/10/2026 | Detalles de los pedidos de cliente decididos en la Tarea 12 (salida = bolsas listas, Nacex hasta las 18:00, pasar a mañana, «coge / haz» al salir la tarea). |
| 1.26 | 28/10/2026 | Peticiones especiales en el reparto y el envío (R1d). Histórico por día en el panel de Administración. |
| 1.27 | 28/10/2026 | R1c rehecha: cuenta del almacén entre recuentos (lo producido suma), el recuento pone al día solo el almacén y las cajas en camino tienen hora fija (reparto hasta las 23:30, Nacex hasta las 11:59 del día siguiente); los pedidos por Nacex salen del stock. |
| 1.28 | 28/10/2026 | Decisiones del propietario en la Tarea 14: el pedido de tienda activa el reparto de hoy; el reparto de primera hora usa «almacén ahora». |
| 1.29 | 29/10/2026 | Tras la prueba en el almacén: el mini se llama «MINI 10g» en la hoja; nuevo Inicio del panel de Administración (menos de 2 semanas siempre a la vista, horas y minutos de cada tarea, tiempo de «Orden y limpieza», sin «Almacén ahora»). |
| 1.30 | 29/10/2026 | R1e: producto sin granel en el reparto (quitarlo o cogerlo de otra tienda, aviso de llamada en las bolsas, parada para quien hace la ruta y línea en WhatsApp); «Hoy sales tú / Hoy sale [nombre]» en las tareas del reparto. |
| 1.31 | 29/10/2026 | R1e en el envío: se comprueba al pulsar «Calcular» en «Preparar envío» (no guarda; «Dejarlo en N» o «Quitarlo»). |
| 1.32 | 29/10/2026 | Constitución técnica (`docs/CONSTITUCION_TECNICA.md`): reglas que no se rompen, lectura obligatoria antes de actuar y «terminado» = funciona en el proyecto de pruebas, con registros sin errores. |
| 1.33 | 30/10/2026 | Tras la prueba del viernes: bolsas sin «Terminada» y aviso «Bolsas listas para salida»; «Nueva tarea» con un solo botón «Crear»; limpieza de resinas después del reparto, las bolsas, el envío y el +35 %, antes del recuento de las 12:45. |
| 1.34 | 30/10/2026 | Tarea 20: la limpieza de resinas espera también a «Prepara el reparto» y a los pedidos de cliente; si no cabe antes de las 12:45, pasa al siguiente día; el envío del viernes se mete a primera hora. |
| 1.35 | 30/10/2026 | «Hoy» del panel: interrupciones de cada tarea (a qué hora y por qué tarea, y cuándo siguió) y, en las de producción, cajas hechas de las totales y minutos trabajados. |
| 1.36 | 30/10/2026 | Incidencias rediseñadas: tres opciones (comprar con la lista de compras · Varios · Estoy bloqueado), avisos de Administración para un día concreto y botón rojo con las incidencias sin cerrar; lista de compras en la base de datos; color solo puntual. |
| 1.37 | 01/11/2026 | E2-4: visión de la app de tiendas (lista de tareas del día con hora orientativa, avisos que se marcan como leídos al entrar, semanales de muestras, productos atascados y limpieza). |
| 1.38 | 02/11/2026 | Tras la prueba del 02/11: tareas de Administración no urgentes después de lo del reparto; «Hoy» en el orden en que se hicieron; Asier como Administración por defecto; «Calcular» siempre recalcula con la hoja del momento; «Hecho» para cerrar una incidencia. |
| 1.39 | 02/11/2026 | Tarea 23: regla «lo primero de la mañana» para todas las tareas; «Calcular» siempre recalcula; Asier como Administración por defecto; «Hoy» en el orden en que se hizo. |
| 1.40 | 02/11/2026 | E2-6: cómo se mueven hoy los datos de las tiendas (plantillas, script, control semanal, evolución), Durango en lugar de Laudio, Donosti y Rentería como franquicias, y el objetivo de pasar todo al software con un paso intermedio escribiendo en la plantilla de cada tienda. |
| 1.41 | 02/11/2026 | Tarea 24: «hecha por» en «Hoy»; fuera del turno ninguna tarea; lo no obligatorio se pausa solo al acabar el turno. |
| 1.42 | 02/11/2026 | E2-7: dos entornos, producción (Pro) y pruebas; producción empieza limpia; el histórico real de las hojas se importará más adelante. |
| 1.43 | 02/11/2026 | E2-7: producción montada; hasta el cambio, lo aprobado y probado pasa a producción al fusionarlo. |
| 1.44 | 02/11/2026 | E2-8: bloque 1 de tiendas definido (operativa diaria en la app, prueba en Basauri y Portugalete con tablet). |
| 1.45 | 02/11/2026 | E2-7: lo de tiendas no pasa a producción hasta probarlo; producción espera desde la Tarea 27. |
| 1.46 | 03/11/2026 | §6.4: conflictos al crear tareas de Administración (sin falsa alarma con lo de la mañana, el reparto de hoy no se mueve, la ventana pregunta primero por la tarea nueva). |
| 1.47 | 03/11/2026 | E2-8: el almacén también puede mandar avisos a las tiendas. |
| 1.48 | 03/11/2026 | §6.4: las bolsas justo después de la producción, sin nada en medio; la salida solo con las bolsas hechas; lo que sale hoy al reparto o a Nacex no se mueve en un conflicto. E2-8: la bolsa de la tienda es lo marcado; la lista solo en la reposición; el almacén ve y cancela sus avisos. |
| 1.49 | 03/11/2026 | E2-8: criterio del propietario: todo se construye igual para todas las tiendas, franquicias incluidas, y luego se quita o esconde por tienda si hace falta; las incidencias, en todas. |
| 1.50 | 03/11/2026 | E2-8: qué tienen las franquicias (incidencia de texto libre, pestaña «Envíos» para confirmar lo que llega, cierre de caja con Z y nº de ventas; sin material, aperturas, cierres ni cristales) y Durango como tienda propia que recibe por envío. |
| 1.51 | 03/11/2026 | R1b: pedidos de cliente para recoger en Donosti, Rentería y Durango, en el siguiente envío; aviso en «Revisa si toca envío…». |
| 1.52 | 03/11/2026 | E2-8: «Envíos» cuenta al preparar el envío y se ve desde el día siguiente (7 días); el de Gipuzkoa lo confirma solo Rentería; Donosti sin «Envíos». |
| 1.53 | 04/11/2026 | §6.5: lo del reparto y del envío no pasa nunca al día siguiente; los pedidos de cliente sí. |
| 1.54 | 04/11/2026 | E2-8: los pedidos que crea la tienda, solo para recoger en su tienda (nunca Nacex), en todas las tiendas. |
| 1.55 | 04/11/2026 | R1b: el pedido que va por envío tiene su tarea propia del operario, como en el reparto. |
| 1.56 | 04/11/2026 | E2-8: atascados: la primera tienda que lo pide se lo lleva; «Ya no queda» cierra la promoción; las franquicias piden y lo reciben por envío; lo atascado en una franquicia va directo a Administración. |
| 1.57 | 04/11/2026 | E2-8: regla general de las franquicias: como tiendas propias en todo, salvo la logística (envío en vez de reparto) y las tareas del día a día de su gente. |
| 1.58 | 04/11/2026 | R1c: «Calcular» del reparto y del envío usa solo la cifra de la hoja, sin la cuenta propia de la app. |
| 1.59 | 04/11/2026 | E2-8, atascados: Durango directo a Administración; texto de la promoción de Administración; la petición del envío al cerrar la recogida. |
| 1.60 | 04/11/2026 | E2-6: al confirmar la reposición en la app, el stock de la tienda debe quedar actualizado en ese momento (objetivo; en el paso intermedio, la app apunta la reposición en la plantilla). |
| 1.61 | 04/11/2026 | E2-8, panel de Administración: pestañas por centro; menú «Tiendas» con Personas, Incidencias, Cierres de caja (total por día, propias y franquicias por separado), Días cerrados y Vídeos; las peticiones salen del menú; avisos al almacén y a las tiendas en un solo botón «Avisos». |
| 1.62 | 04/11/2026 | E2-8: marcas en las pestañas del panel (rojo con número, «N sin hacer» hasta que Administración entra, «sin abrir»), en lugar del aviso del resumen del día; efectivo de «Recibe la bolsa»: suma de los cierres aún no entregados si el reparto no ha pasado algún día. |
| 1.63 | 04/11/2026 | E2-8, marcas (PR #37): «sin abrir» solo mientras dura el turno; «sin hacer», últimos 7 días; «Falta [tienda]» también antes de usar la app (solo en pruebas). |
| 1.64 | 04/11/2026 | E2-8, «Recibe la bolsa» (PR #38): el lunes, el efectivo del viernes más el del sábado (el sábado no hay reparto). |
| 1.65 | 04/11/2026 | §6.4: el turno del operario va de «Empezar turno» a «Fin de turno»; pasada su hora, solo lo obligatorio; el cierre, al pulsar «Fin de turno» (Tarea 35). Base para el «Fin de turno» de las tiendas y para fichar. |
| 1.66 | 04/11/2026 | §6.4 (PR #39): empezar antes de la hora; la tarde cierra la mañana; Fin de turno con confirmación; el recuento, obligatorio antes de cerrar; cierre también sin empezar. |
| 1.67 | 04/11/2026 | E2-8: «Limpieza de cristales» pasa a «Limpieza semanal: cristales, polvo y baños»; el vídeo del sábado, a la hora de abrir del turno de quien empieza, después de la apertura (Tarea 36). |
| 1.68 | 06/11/2026 | §6.4: lo que tiene hora entra también cuando no hay ninguna referencia empezada (entre dos referencias o en una tarea no obligatoria sin referencias), en cuanto llega su hora (Tarea 37). |
| 1.69 | 06/11/2026 | §6.4: Tarea 37 hecha en pruebas (PR #41): sobre una no obligatoria sin referencia empezada entran también lo urgente y volver a llamar por un problema (escalones 2–4); caso raro de la revisión inicial a las 08:45. |
| 1.70 | 07/11/2026 | Cabecera al día (almacén en uso real en pruebas; tiendas en prueba en Basauri, Portugalete y Rentería; producción montada sin usar). Decisión del propietario (T-0000): el coordinador pasa al proyecto de Claude «Desarrollo de software operativo» y en el repositorio solo lee; el trabajo va con tickets; el encargo lo copia el propietario, el coordinador revisa el PR y el propietario lo fusiona; este documento lo actualiza el agente de base de datos en el PR de cada tarea (§0 y §11). Regla nueva: cada PR que cambie este documento pone al día la cabecera. |
| 1.71 | 07/11/2026 | §11 (T-0002): las filas «Almacén (Lovable)» y «Tiendas (Lovable)» pasan a ser los tres agentes de pantallas del proyecto de Claude «Desarrollo de software operativo» (almacén, tienda y panel de Administración), que dan órdenes a un solo proyecto de Lovable, una a la vez y con la aprobación del propietario. No cambia ninguna regla. |
| 1.72 | 09/11/2026 | Dos decisiones del propietario (T-0009): (1) §11, quién fusiona: el agente de base de datos, solo con el «sí» expreso del propietario a ese PR, que lo da después de revisarlo con el coordinador; antes comprueba que la rama sigue en el commit revisado y después dice el commit de `main`; a mano, solo como excepción. (2) §8, Estilo: el rojo vale también para los avisos urgentes que piden una decisión; de momento, el aviso de salida sin bolsas del operario (franja fija arriba, en rojo; Lovable, 09/11, T-0008). |
| 1.73 | 11/11/2026 | R1e y E2-8 (T-0010 · Tarea 38): cajas de otra tienda. La línea del operario pasa a «Avisa a [origen]…»; al marcarla, la tienda de origen recibe un aviso («Prepara N … para [destino]: lo recoge hoy el reparto»); la que recibe ve esas cajas en la lista de su bolsa, en la línea de su producto. Igual para todas las tiendas. Cabecera al día. |
