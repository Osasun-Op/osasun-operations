# OSASUN OPERATIONS — Estado del sistema y decisiones

**Versión:** 1.5 · **Fecha:** 26/10/2026 · **Estado:** diseño aprobado por el propietario. Propuesta técnica de BD (PR #1) revisada. Sin desarrollo iniciado.

---

## 0. Cómo usar este documento

- Es la **fuente de verdad técnica** del proyecto. Todo agente lo lee antes de trabajar.
- Lo aprobado aquí no se cambia por iniciativa propia. Las propuestas se envían al coordinador, el propietario las aprueba y entonces se actualiza este documento.
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
- **Cuentas:** cada persona tiene su usuario. No hay credenciales compartidas. Osasun usa cuentas de Google gratuitas, no Workspace.

---

## 4. Mapa semanal del almacén (punto 2, aprobado)

### Mañana (lunes a viernes)
| Hora | Tarea |
| --- | --- |
| 08:30–~08:45 | Revisión inicial: estado de las tiendas, formulario de incidencias de tiendas (hoja de respuestas) y stock empaquetado. |
| ~08:30–08:45 | Administración publica el reparto en WhatsApp, con la línea `SALE:`. |
| Hasta la salida | 1) Calcular el total de cajas, restar las hechas y producir lo que falta. 2) Preparar las bolsas de cada tienda. 3) Con el tiempo restante, stock del almacén (+35 %). |
| Viernes | 30 minutos de limpieza intensiva de la estación de resinas antes del reparto. |
| Si sale él | Salida a las 10:45 y ruta de unas 2 h. A la vuelta, efectivo frente a la Z y reporte a Administración. |
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

**Viernes:** si hace falta, envío a Gipuzkoa/Durango por la mañana.

### En cualquier momento (eventos)
- **Llega mercancía:** se abre y se comprueba en el momento.
- **Pedido de cliente** (1 o 2 por semana, sobre todo los miércoles): se prepara como el de una tienda y se envía por Nacex.
- **No quedan vapers:** tirada de 50, repartida entre 2 tipos.
- **Falta material:** catálogo (sección 7).
- **Bloqueo:** flujo de problemas (sección 6.6).

### Cola de tiempo libre (por prioridad)
1. **A:** producir para el stock del almacén (R3).
2. **C:** compras y aprovisionamientos pendientes.
3. **D:** orden y limpieza.

La recepción de mercancía no está en la cola: se atiende en el momento en que llega.

### Quién decide
- **Administración:** las cantidades del reparto, quién sale cada día, la aprobación del envío a Gipuzkoa/Durango, el pedido de packaging, la materia prima y las nuevas variedades.
- **Operario:** la ejecución según las reglas, el orden dentro de las listas de producción, las compras online de consumibles y la recepción.

### Indicador de calidad semanal
La limpieza del viernes hecha y los papeles de resinas rectos y cuidados.

---

## 5. Reglas de negocio y de cálculo

> Todos los cálculos son deterministas, se ejecutan en el servidor (Supabase) y tienen pruebas. La IA no calcula nada crítico.
> **La app nunca propone cantidades para las tiendas.** Solo calcula sobre lo que ya ha decidido Administración.

**R1. Reparto y envíos.** Administración publica en WhatsApp:
```
REPARTO dd/mm
SALE: ALMACÉN | YO
BILBAO
1x PRODUCTO FORMATO
...
ALGORTA
...
```
El operario pega el texto en la app. La app:
1. Comprueba cada nombre contra el catálogo (PRINCIPAL). Ignora espacios y mayúsculas.
2. Si algún nombre no existe, avisa antes de calcular.
3. Suma las cajas por producto y formato.
4. Resta las cajas hechas en el almacén.
5. Genera la lista de producción con lo que falta.
6. Organiza la jornada según la línea `SALE:`. Si falta esa línea, se lo pregunta al operario.

- **Tiendas en el texto:** se escriben igual que en la hoja de stock: BILBAO, ALGORTA, DONOSTI, BARAKALDO, RENTERIA, BASAURI, PORTU, GIPUZKOA; Durango como DURANGO o LAUDIO (decisión del propietario, 26/10/2026).
- **Reparto corregido:** si se pega una versión nueva el mismo día, sustituye a la anterior. Se recalcula lo que falta producir sin perder las cajas ya hechas; las bolsas de tiendas que no cambian se conservan y las que cambian se vuelven a comprobar caja a caja (decisión del propietario, 26/10/2026).

El envío a Gipuzkoa/Durango sigue el mismo camino: él propone, Administración aprueba por WhatsApp y él pega la versión final.

**R2. Stock negativo en una tienda** = encargo de cliente pendiente. Hay que llevar esas cajas además de la reposición normal. Es información de contexto para el operario: la app no modifica las cantidades del reparto.

**R3. Stock del almacén (+35 %).** Se usa CONTEO DE CAJAS TOTAL:
- `contador = cajas hechas en todas partes − consumo semanal` (0 significa una semana cubierta).
- `objetivo = +35 % del consumo semanal`.
- `cajas a hacer = objetivo − contador`, si sale positivo, **redondeado hacia arriba** (D1, decidido 26/10/2026).
- La lista se ordena por consumo semanal, de mayor a menor. Es aceptable que las referencias que menos se venden se queden en torno a +20 %.
- **Los minis quedan fuera de esta regla.** El único mini es **MINIBUDS MIX 10g**.
- **Categorías que rotan (Invernadero, Indoor):** se calcula por categoría. Dentro de cada una se aplica FIFO, con un mínimo de 2 variedades de invernadero y 2 de indoor. **El FIFO lo decide el operario:** la app indica las cajas de la categoría y las variedades con granel, y él usa primero el granel más antiguo, que reconoce en el almacén.
- **Sin granel no se produce.** Al operario le aparece la tarea «Avisa a Administración: falta X».

**R4. Aviso del jueves (cobertura a 2 semanas).** En cada producto se compara el total en gramos (almacén más tiendas, de PRINCIPAL) con 2 × la necesidad semanal. Invernadero e Indoor se valoran sumando toda la categoría, porque se compran 2 o 3 variedades a la vez. La app prepara la lista explicando cada aviso. El operario la revisa, comprueba el granel físicamente y la envía a Administración.

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
- **Una tarea con hora** entra al terminar la **referencia o bolsa en curso**, nunca a mitad de un pesaje ni al final de una lista entera. Si empieza tarde, se registra la hora real.
- **Tareas de Administración:**
  - Urgente: entra al terminar lo que tiene entre manos.
  - Con hora límite: va al primer hueco que no ponga en riesgo una obligatoria.
  - Si no cabe sin sacrificar una obligatoria, se avisa a Administración **en el momento de lanzarla** y decide qué cede.
- Nada desaparece en silencio.

### 6.5 Estados y lo no terminado
**Estados:** pendiente · en curso · hecha · bloqueada (con un problema abierto) · arrastrada · cancelada por Administración.

**Lo no terminado:**
- Stock: se recalcula, no se arrastra.
- Compras y recogidas: siguen abiertas hasta que él confirma que ya lo tiene.
- Tareas de Administración: pasan al día siguiente como arrastradas.

### 6.6 Problemas e incidencias
**Botón «Tengo un problema»**, con cinco tipos: falta material · no encuentro algo · no sé cómo hacerlo · algo no funciona · otro.
1. Si la app da una solución directa, la aplica.
2. Si en 1 minuto no está resuelto, **llama a Administración** (botón de llamada en el Pixel).
3. Si no encuentra algo, llama en el momento.
4. Tras la llamada, escribe en una línea la solución acordada. **Regla: ningún problema pasa más de 5 minutos sin una solución definida.**
5. Si no le cogen el teléfono: envía un WhatsApp con el problema, la tarea queda pendiente y pasa a otra.
6. A los 30 minutos sin solución, le vuelve a aparecer la tarea de llamar. Si Administración le llama antes, apunta la solución y lo marca como resuelto.

**Botón «Incidencia»:** para atender algo no previsto por necesidad o urgencia (corregir, limpiar, solucionar) que dure más de 3 minutos. Escribe en una línea qué es y por qué. No necesita aprobación, pero queda registrado.

**«Hacer» fuera del plan no existe:** producir algo que se queda (cajas, stock) solo se hace si está en el plan.

### 6.7 Avisos
- **El operario solo ve tareas:** pendientes, en curso y acabadas. Nunca avisos de tiempo ni de presión. Excepciones, que también son tareas: una tarea nueva durante el reparto le llega al Pixel, y un problema sin resolver reaparece a los 30 minutos.
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

**Estilo:** blanco y negro, sin colores, con inspiración en Apple y Holded. Las referencias se distinguen por tipografía: el formato (4 g / 10 g) grande y en negrita, y la categoría escrita debajo.

### Operario
- **Chromebook:**
  - Una sola tarea en el centro, con su porqué en una frase.
  - Tres botones fijos: **Terminada**, **Tengo un problema** e **Incidencia**.
  - Una línea abajo con lo que viene después.
- **Listas de producción:**
  - Aparecen todas las referencias. Él elige una, la termina y la marca, y elige la siguiente.
  - La lista de stock aparece ordenada por prioridad, con el motivo de cada referencia, pero el orden lo decide él.
- **Bolsas (Pixel):** una tienda por pantalla. Toca cada caja al meterla en la bolsa, porque esa es la comprobación.
- **Lenguaje:** frases, no casillas. Por ejemplo: «Indoor: queda para menos de media semana. Avisa a Administración».

### Administración
- **Inicio (móvil):** en qué está el almacén ahora, problemas abiertos, pendientes que se arrastran, tareas de hoy y botón **Nueva tarea**.
- **Nueva tarea:** qué · para quién (almacén por defecto) · cuándo (hoy, un día o antes de una hora) · duración orientativa · urgente (no por defecto) · por qué (opcional).
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
| **GitHub** | Un único repositorio privado, `Osasun-Op/osasun-operations`, con el código y la carpeta `docs`. Conectado a Lovable y a este proyecto (este proyecto solo lee). |
| **Claude Code en la web** | Entorno en la nube del agente de base de datos. Clona el repositorio en una máquina aislada y entrega sus cambios como rama para revisión. Acceso solo a este repositorio. |

**Condiciones obligatorias:**
1. **Dos entornos, pruebas y producción.** Lovable trabaja siempre contra pruebas. A producción solo pasa lo probado.
2. **La lógica crítica vive en Supabase.** Las pantallas solo muestran y solicitan. El navegador no decide permisos, cálculos ni estados críticos.
3. **Google Sheets en solo lectura** mediante la cuenta técnica.
4. **Lovable tiene prohibido crear o cambiar tablas.**
5. **Claves de API (autorizado por el propietario, 26/10/2026):** los agentes del proyecto pueden recibir las claves que necesiten para su trabajo, con estas reglas:
   - Se guardan como **secretos o variables del entorno** donde se usan (entorno en la nube de Claude Code, Supabase, Lovable). Nunca en el repositorio, en documentos ni pegadas en conversaciones.
   - **Una clave por entorno y por uso**, con el mínimo permiso necesario. Las de producción solo se entregan cuando se apruebe la puesta en marcha.
   - **La clave maestra de Supabase (service role) nunca va en las pantallas.** Lovable usa solo la clave pública, y los permisos los aplica la base de datos.
   - Todas son **revocables**. Si una clave se expone, se cambia en el momento.

**Coste estimado:** en torno a 100 € al mes en total (estimación del propietario).

**Descartado:** AppSheet y Apps Script (no permiten llegar a la Etapa 3 sin rehacer, y la lógica sería frágil), otras herramientas low-code (dependencia alta) y un servidor propio (mantenimiento).

---

## 11. Organización de agentes

| Agente | Alcance | Prohibido |
| --- | --- | --- |
| **Coordinador** (sesión de Claude Code en la nube, instrucciones en `docs/AGENTE_COORDINADOR.md`) | Comunicación con el propietario, registro general, este documento, reparto de trabajo, revisión de entregas y PR, contratos entre módulos | Decisiones de negocio. Escribir código o tocar Supabase. |
| **Base de datos** | El único que toca Supabase: tablas, permisos, funciones, motor de tareas, cálculos y lectura de Sheets. Trabaja **siempre en un entorno en la nube**. | Pantallas. Usar el ordenador del propietario. |
| **Almacén (Lovable)** | Pantallas del operario y panel de Administración | Crear o cambiar tablas. Si necesita datos nuevos, lo pide al coordinador. |
| **Tiendas (Lovable)** | Se crea al empezar la Etapa 2 | — |

**Contrato entre módulos:** las pantallas solo usan las funciones y vistas que publica el agente de base de datos. Cualquier dato o función nueva se pide al coordinador, que la encarga al agente de base de datos y actualiza este documento.

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
| E2-1 | Etapa 2: las variedades indoor agrupadas en tiendas hacen que algunas se queden atrás | Para la Etapa 2 |
| E2-2 | Etapa 2: comparar la reposición apuntada por la tienda con lo enviado; si no cuadra, se soluciona o se avisa | Para la Etapa 2 |

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
