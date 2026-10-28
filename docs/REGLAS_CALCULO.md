# OSASUN OPERATIONS — Reglas de cálculo R1 y R3 (especificación V1)

**Versión:** 0.7 · **Fecha:** 28/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobada (PR #1). Construida en la Tarea 3: `supabase/functions/_compartido/r1.ts` y `r3.ts`, con sus pruebas (`*_test.ts`). Tarea 4: el envío pegado antes del recuento descuenta el reparto del día (§2.5, R1-22 a R1-24). Tarea 8: el desplegable «¿Quién sale?» manda sobre `SALE:` (§2.3, R1-25 a R1-27). Tarea 10: el reparto se prepara con una lista (§2.9, L-01 a L-09). Tarea 12: pedidos de cliente «coge / haz» al salir la tarea, cajas en camino (salida = bolsas listas) y Nacex hasta las 18:00 (§2.10 y §3.9, P-01 a P-08, C-01 a C-09, R3-21 a R3-23).

> Especificación exacta de las dos reglas que la V1 calcula con datos de Google Sheets: **R1** (texto del reparto) y **R3** (stock del almacén +35 %).
> Lo aprobado en `ESTADO_DEL_SISTEMA.md` §5 se aplica **sin cambios**; donde hacía falta precisar, se indica la decisión y su fecha.
> Todo se calcula en el servidor, con pruebas automáticas. Los casos de este documento serán esas pruebas.

---

## 1. Datos de entrada (Google Sheets, solo lectura)

Documento `STOCK OSASUN-CLAUDE` (ID `1nPhB7U6FoJcYybChUcGOI3mz-yJAv8NkT3uINuQ6qao`):

| Dato | Dónde |
| --- | --- |
| **Catálogo** (producto y formato) | PRINCIPAL, columna A. Cada producto es un bloque: fila con el nombre y, debajo, una fila por formato (`4g`, `10g`, `2g`, `3g`, `20gr`, `CBD`, `CBDX`…), hasta la fila vacía. Los productos sin formato (FORTE, VAPER, 10% FS…) son una sola fila. |
| **Cajas en el almacén** | PRINCIPAL, columna R (`ALMACEN · FIN DIA`) de la fila de formato. |
| **Granel en el almacén** (gramos) | PRINCIPAL, columna R de la fila del nombre del producto. |
| **Contador** (hechas − consumo semanal) | CONTEO DE CAJAS TOTAL, columna «CAJAS TOTALES HECHAS». |
| **Consumo semanal** (cajas) | CONTEO DE CAJAS TOTAL, columna «CONSUMO CAJAS SEMANAL». |
| **Categoría de cada producto** | ALMACEN, fila 1: EXTERIOR, INVERNADERO, INDOOR POPS, HIGH TECH, ACEITES Y CREMAS. |
| **Categorías que rotan** | CONTEO DE CAJAS TOTAL, filas «INVERNADERO TOTAL» e «INDOOR TOTAL». |
| **Envío a Gipuzkoa** | Se calcula con la pestaña GIPUZKOA (va entero a Rentería). |

Números: enteros, negativos y decimales con coma (`2,5`). Celda vacía o texto no numérico = **dato no válido** (nunca se convierte en 0 sin avisar).

## 2. R1 — Lectura del texto del reparto

### 2.1 Normalización (§5 R1: «ignora espacios y mayúsculas»)
`norm(x)` = mayúsculas y **sin ningún espacio**.
- `norm("V2 ")` = `V2`; `norm("v2 4 g")` = `V24G`; `norm("T BALLS / GELATO DRY")` = `TBALLS/GELATODRY`.
- Clave de catálogo = `norm(producto + formato)`. Si dos entradas dan la misma clave → `CATALOGO_AMBIGUO` (no se calcula; aviso a Administración).
- **No hay búsqueda aproximada ni tabla de equivalencias** (P-R1c rechazada: los nombres se limpian en PRINCIPAL, P2).

### 2.2 Clasificación de cada línea (la primera regla que encaja decide)

| # | Clase | Regla | Ejemplo |
| --- | --- | --- | --- |
| 1 | `vacia` | Solo espacios. Se ignora. | |
| 2 | `cabecera` | `REPARTO dd/mm`. Se guarda la fecha. | `REPARTO 27/10` |
| 3 | `sale` | Empieza por `SALE:` (con o sin espacios). | `SALE: ALMACÉN` |
| 4 | `producto` | `<número> x <nombre>` (`x` mayúscula o minúscula, con o sin espacios). | `10x V2 4g` |
| 5 | `tienda` | `norm(línea)` coincide con un alias de `centros_trabajo`. | `BILBAO`, `LAUDIO` |
| 6 | `no_reconocida` | Cualquier otra cosa. | `bilbao lleva lo de ayer` |

**Tiendas** (decisión del propietario, 26/10/2026): se escriben igual que en la hoja: BILBAO, ALGORTA, DONOSTI, BARAKALDO, RENTERIA, BASAURI, PORTU, GIPUZKOA; Durango como DURANGO o LAUDIO.

**Fecha** (P-R1b aprobada): si la fecha de `REPARTO dd/mm` no es hoy → `FECHA_NO_ES_HOY`; se calcula solo si el operario lo confirma.

### 2.3 Línea `SALE:`
| Valor (tras `norm`) | Resultado |
| --- | --- |
| `ALMACÉN` o `ALMACEN` (P-R1a aprobada) | Sale el operario. |
| `YO` | Sale Administración. |
| Falta la línea u otro valor | `FALTA_SALE`: la app pregunta «¿Quién sale hoy?». |
| Dos líneas `SALE:` distintas | `SALE_CONTRADICTORIA`. |

**Desplegable «¿Quién sale?» (v1.20):** si la pantalla manda `sale`, **manda sobre la línea `SALE:`**, que pasa a ser opcional. Si no coinciden (o hay dos `SALE:` distintas), no es un error: se acepta con lo del desplegable y queda anotado en el registro (`sale_distinto_del_texto`). Sin desplegable, todo sigue como en la tabla.

En el envío (`tipo = envio`) la línea `SALE:` no se usa.

### 2.4 Líneas de producto
- `cantidad`: entero ≥ 1. `0x` o negativo → `CANTIDAD_NO_VALIDA`.
- `norm(nombre)` debe coincidir con **exactamente una** clave del catálogo; si no → `PRODUCTO_DESCONOCIDO`.
- Debe haber una tienda antes; si no → `PRODUCTO_SIN_TIENDA`.
- La misma referencia repetida en la misma tienda se suma.

### 2.5 Cálculo (§5 R1, pasos 3 a 5)
Solo si **no hay ningún error**: con errores **no se calcula** hasta corregir el texto (decidido, D-R1c).
```
pedido(p, f)     = Σ cantidades de (p, f) en todas las tiendas del texto
en_almacen(p, f) = PRINCIPAL!R de la fila de formato
faltan(p, f)     = max(0, pedido − en_almacen)
```
- `en_almacen` vacío o negativo → **cuenta como 0, con aviso** en la línea (decidido, D-R1b).
- **Envío pegado antes del recuento de la mañana del mismo día** (decidido en el PR #3, `ESTADO_DEL_SISTEMA.md` v1.11): la hoja aún no refleja las cajas del reparto aceptado ese día, así que primero se apartan: `disponible = max(0, en_almacen − pedido en el reparto de hoy)` y `faltan = max(0, pedido − disponible)`. Se devuelve `apartado_reparto` por referencia. Después del recuento (tarea «Recuento» de la mañana hecha; desde la Tarea 12, hecha después de terminar las bolsas, §2.10) no se descuenta nada: la hoja ya lo refleja. El reparto nunca descuenta.
- Lista de producción = referencias con `faltan > 0`; orden sugerido, el del catálogo. El operario elige el orden.
- Bolsas = una por tienda (o destino) con sus referencias y cantidades del texto.
- Duración prevista de la producción = cajas que faltan × 1 min; de las bolsas = tiendas × 3 min (§6.10).
- La app **no cambia ninguna cantidad** del reparto (§5).

### 2.6 Reparto corregido (decisión del propietario, 26/10/2026)
Si se pega una versión nueva el mismo día, **sustituye** a la anterior:
- Producción: se recalcula lo que falta **sin perder las cajas ya hechas** (las hechas de cada referencia se mantienen; si ahora faltan menos de las hechas, la referencia queda hecha).
- Bolsas: las de tiendas **sin cambios** se conservan tal cual; las de tiendas que **cambian** se vuelven a comprobar caja a caja (su recuento vuelve a 0). Las tiendas que desaparecen se quitan, y las nuevas se añaden.
- Queda registrado qué versión sustituyó a cuál.

### 2.7 Errores
| Código | Bloquea | Mensaje al operario |
| --- | --- | --- |
| `LINEA_NO_RECONOCIDA` | Sí | «Línea N: no entiendo "…". Corrígela o pregunta a Administración.» |
| `PRODUCTO_DESCONOCIDO` | Sí | «Línea N: "…" no está en el catálogo.» |
| `PRODUCTO_SIN_TIENDA` | Sí | «Línea N: falta la tienda antes de esta línea.» |
| `CANTIDAD_NO_VALIDA` | Sí | «Línea N: la cantidad debe ser 1 o más.» |
| `SALE_CONTRADICTORIA` | Sí | «Hay dos líneas SALE: distintas.» |
| `REPARTO_VACIO` | Sí | «No hay ninguna línea de producto.» |
| `FALTA_SALE` | Hasta responder | «¿Quién sale hoy?» |
| `FECHA_NO_ES_HOY` | Hasta confirmar | «Este reparto es del dd/mm. ¿Seguro que es el de hoy?» |
| `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` · `CATALOGO_AMBIGUO` | Sí | No se calcula nada (principio 8). |

Se devuelven **todos** los errores a la vez.

### 2.8 Casos de prueba de R1

Catálogo de prueba (extracto real de PRINCIPAL; «en almacén» inventado para la prueba):

| Producto (tal cual en Sheets) | Formato | En almacén |
| --- | --- | --- |
| `V2 ` (con espacio final) | 4g | 25 |
| `V2 ` | 10g | 10 |
| BZ1 | 4g | 7 |
| T BALLS / GELATO DRY | 2g | 0 |
| KRUSH | 20gr | 0 |
| FORTE | (sin formato) | 107 |

Destinos: BILBAO, ALGORTA, DURANGO (alias `DURANGO`, `LAUDIO`), GIPUZKOA. Hoy = 27/10.

| # | Entrada | Resultado esperado |
| --- | --- | --- |
| R1-01 | `REPARTO 27/10` · `SALE: ALMACÉN` · `BILBAO` · `20x V2 4g` · `5x BZ1 4g` · `ALGORTA` · `10x V2 4g` · `4x BZ1 4g` · `1x FORTE` | Aceptado. Sale el operario. Producción: V2 4g 30−25 → **5**; BZ1 4g 9−7 → **2**; FORTE no aparece. Bolsas: Bilbao (20 V2 4g, 5 BZ1 4g), Algorta (10 V2 4g, 4 BZ1 4g, 1 FORTE). |
| R1-02 | `bilbao` · `  3 X  t balls / gelato dry 2G ` · `1x v2 4 g` · `SALE: YO` | Aceptado. Sale Administración. T BALLS / GELATO DRY 2g faltan 3; V2 4g faltan 0. |
| R1-03 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 5g` | `PRODUCTO_DESCONOCIDO` (línea 3). No se crea nada. |
| R1-04 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 4g` · `lo de ayer también` | `LINEA_NO_RECONOCIDA` (línea 4). |
| R1-05 | `SALE: ALMACÉN` · `2x V2 4g` · `BILBAO` | `PRODUCTO_SIN_TIENDA` (línea 2). |
| R1-06 | `BILBAO` · `2x V2 4g` (sin `SALE:`) | `FALTA_SALE`. Repetido con `sale = administracion` → aceptado. |
| R1-07 | `SALE: ALMACÉN` · `DURANGO` · `2x V2 4g` · `LAUDIO` · `1x V2 4g` | Aceptado. Una sola bolsa para Durango con 3 V2 4g. |
| R1-08 | `SALE: ALMACÉN` · `BILBAO` · `0x V2 4g` | `CANTIDAD_NO_VALIDA`. |
| R1-09 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 4g` · `3x V2 4g` | Aceptado. Bilbao V2 4g = 5. |
| R1-10 | El texto de R1-01 pegado dos veces | La segunda: `REPARTO_YA_PEGADO`, mismo resultado, nada duplicado. |
| R1-11 | Texto de R1-01 con Sheets sin respuesta | `SHEETS_NO_DISPONIBLE`. No se crea nada. |
| R1-12 | `SALE: ALMACÉN` · `SALE: YO` · `BILBAO` · `1x V2 4g` | `SALE_CONTRADICTORIA`. |
| R1-13 | `SALE: ALMACÉN` · `BILBAO` · `1x KRUSH 20gr` / `1x KRUSH 20g` | El primero, aceptado. El segundo, `PRODUCTO_DESCONOCIDO` (no hay equivalencias). |
| R1-14 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 4g` · `1x XX 4g` · `hola` | Los dos errores a la vez (líneas 4 y 5). |
| R1-15 | `SALE: ALMACÉN` · (vacías) · `BILBAO` · (vacía) · `2x V2 4g` | Aceptado; las vacías se ignoran. |
| R1-16 | `SALE: ALMACÉN` | `REPARTO_VACIO`. |
| R1-17 | `SALE: almacen` · `BILBAO` · `1x V2 4g` | Aceptado: sale el operario (sin tilde). |
| R1-18 | `REPARTO 26/10` · `SALE: YO` · `BILBAO` · `1x V2 4g` | `FECHA_NO_ES_HOY`. Repetido con `confirmar_fecha` → aceptado. |
| R1-19 | `SALE: ALMACÉN` · `BILBAO` · `1x LORANAT` con almacén vacío en PRINCIPAL | Aceptado; LORANAT faltan 1, con aviso «dato de almacén vacío en PRINCIPAL». |
| R1-20 | Envío: `GIPUZKOA` · `4x V2 4g` | Aceptado como envío; una bolsa «Gipuzkoa (envío a Rentería)»; `SALE:` no se pide. |
| R1-21 | Reparto R1-01 aceptado, las 5 V2 4g hechas y bolsa de Algorta completa; se pega una versión con Bilbao 22x V2 4g | Sustituye al anterior. V2 4g: faltan 7, hechas 5 (se conservan; quedan 2). Bolsa de Algorta se conserva completa; la de Bilbao vuelve a 0 para comprobarla. |
| R1-22 | Envío antes del recuento: `GIPUZKOA` · `8x V2 4g` · `1x BZ1 4g`; hoy el reparto pidió V2 4g 20 y BZ1 4g 9; en la hoja V2 4g 25, BZ1 4g 7 | V2 4g: apartadas 20, disponible 5, faltan 3. BZ1 4g: disponible 0, falta 1. |
| R1-23 | Envío después del recuento: `GIPUZKOA` · `8x V2 4g` (hoja V2 4g 25) | No se descuenta: disponible 25, faltan 0. |
| R1-24 | Reparto `SALE: YO` · `BILBAO` · `8x V2 4g` aunque se le pase un apartado de 20 | El reparto nunca descuenta: apartado 0, faltan 0. |
| R1-25 | `SALE: ALMACÉN` · `BILBAO` · `1x V2 4g` con desplegable `administracion` | Aceptado. Sale Administración (manda el desplegable); el texto decía el operario y queda anotado. |
| R1-26 | `SALE: ALMACÉN` · `SALE: YO` · `BILBAO` · `1x V2 4g` con desplegable `operario` | Aceptado, sin `SALE_CONTRADICTORIA`. Sale el operario. |
| R1-27 | `BILBAO` · `1x V2 4g` sin desplegable; y `SALE: YO` · … sin desplegable | `FALTA_SALE`; y aceptado con Administración (manda el texto). |

### 2.9 Reparto con lista (Tarea 10, `ESTADO_DEL_SISTEMA.md` v1.21)
El texto ya no se pega: se elige cada referencia de una lista (`lista.ts`). R1 no cambia; la lista se convierte en el texto de siempre y se calcula con R1.
1. **Catálogo:** una referencia por producto y formato de PRINCIPAL (y los productos sin formato), en el orden de la hoja. Clave estable `producto|formato`. Categoría: el grupo de la pestaña ALMACEN; si no está, «Otros».
2. **Validación** contra la hoja leída al guardar: referencia que ya no está → `REFERENCIA_NO_EXISTE` (dice cuáles); tienda que no vale para el tipo (reparto: BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU; envío: GIPUZKOA, DURANGO; Donosti y Rentería son solo de consulta), cantidad no entera o negativa, o lista vacía → `DATOS_NO_VALIDOS`. Cantidad 0 se ignora; la misma referencia en la misma tienda se suma.
3. **Texto:** `REPARTO dd/mm` (o `ENVÍO dd/mm`), `SALE: ALMACÉN|YO` (solo reparto), y por tienda una línea en blanco, su código y `Nx PRODUCTO FORMATO` con los nombres exactos de la hoja. Tiendas en el orden de las hojas de tienda de STOCK OSASUN (configuración `destinos_reparto`); productos en el orden de la hoja. Se copia tal cual con un botón: no se abrevia.
4. **Cálculo:** R1 sobre ese texto, con la fecha de hoy y el desplegable «¿Quién sale?» (§2.3). Mismo cálculo (§2.5), misma sustitución (§2.6) y mismo apartado del envío antes del recuento.

| # | Entrada | Resultado esperado |
| --- | --- | --- |
| L-01 | Catálogo del extracto de PRINCIPAL | Una referencia por producto y formato, en el orden de la hoja, con su categoría. |
| L-02 | Producto que no está en ALMACEN | Categoría «Otros». |
| L-03 | Línea con `GELATO 4g` (no está en la hoja) | `REFERENCIA_NO_EXISTE` con `GELATO 4g`. |
| L-04 | Tienda de otro tipo, cantidad −1 o lista vacía | `DATOS_NO_VALIDOS`. |
| L-05 | Contadores a 0, la misma referencia dos veces, tiendas desordenadas | Los 0 no cuentan, las repetidas se suman y queda ordenado por tienda y por la hoja. |
| L-06 | Reparto del 03/11 con `sale = operario`: Bilbao 6 MINI 10g y 3 20% FS (sin formato), Portu 2 BZ1 4g; y envío de 4 V2 4g | `REPARTO 03/11` · `SALE: ALMACÉN` · (vacía) · `BILBAO` · `6x MINI 10g` · `3x 20% FS` · (vacía) · `PORTU` · `2x BZ1 4g`; y `ENVÍO 03/11` · (vacía) · `GIPUZKOA` · `4x V2 4g`. |
| L-07 | El reparto real del 28/10 (el que dio 36 de 52 `PRODUCTO_DESCONOCIDO` al pegarlo), rehecho con la lista y la hoja de ese día | Se reconoce entero. Faltan solo INDOOR PR RELAX 4g (2), INDOOR PR AFRU 4g (4), ROYAL BERRY 4g (3) y CBD DRY 4g (5); 20 referencias en producción; bolsas Bilbao 6 referencias / 21 cajas, Algorta 7 / 21, Barakaldo 6 / 16, Basauri 13 / 61, Portugalete 6 / 15. |
| L-08 | Envío `GIPUZKOA 8x V2 4g` antes del recuento; hoy el reparto pidió 25 V2 4g | Se apartan las 25: faltan 3 (como R1-22). |
| L-09 | Envío a Durango y Gipuzkoa (`guardar_reparto`) | `ENVÍO dd/mm` · `GIPUZKOA` … · `DURANGO` …, en ese orden; Donosti, Rentería, Gipuzkoa o Durango en el reparto → `DATOS_NO_VALIDOS`. |

### 2.10 Pedidos de cliente y cajas en camino (Tarea 12, `ESTADO_DEL_SISTEMA.md` v1.24, R1b y R1c)
**Coge / haz** (`motor.calcular_pedido`). Cada referencia de un pedido de cliente dice «Coge N del almacén» o «Haz N» (o las dos: «Coge 2 del almacén y haz 1»). **Se calcula al salir la tarea de prepararlo** (cuando le toca al operario; decidido por el propietario, 28/10/2026), no al guardar el pedido:
- La hoja es la **última lectura correcta** (de cualquier motivo: reparto, envío, pedido o stock), y lo comprometido se mira **tal como estaba la hoja en ese momento** (columna 2 de la tabla de abajo).
- `queda = máx(0, almacén de la hoja − comprometido antes que él que la hoja aún contaba)` (almacén vacío, negativo o con texto en PRINCIPAL: 0; con decimales, la parte entera, como en R1).
- `coge = mín(pedido, queda)`; `haz = pedido − coge`.
- **Primero lo oficial y después el pedido:** «antes» es el reparto y el envío de ese día y los pedidos (de tienda o de Nacex) que llegaron antes que él.
- La producción del reparto **no cambia**: solo lleva las cajas del reparto oficial. Lo que haya que hacer para el pedido está en su propia tarea («Haz N»).
- Si la tarea pasa al día siguiente (a mano o sin terminar), se vuelve a calcular al salir ese día.

**Cajas en camino (R1c)** (`motor.comprometido` y `motor.hoja_sin_reparto`). La hoja no refleja en el momento lo que sale: el almacén baja con el recuento de cada turno y la tienda lo apunta en su «FIN DE DÍA». La app lo corrige en sus cálculos, **nunca en la hoja**.
- **Salida** (decidido por el propietario, 28/10/2026): cuando el almacén termina **las bolsas** (las termina siempre él, salga quien salga); el viernes, además, el **envío preparado**.
- **La hoja deja de contarlo en el almacén** con el recuento de la mañana hecho **después** de la salida. Si el recuento se hace antes de terminar las bolsas, la hoja lo sigue contando hasta el día siguiente.

| Lo comprometido hoy | La hoja lo cuenta en el almacén… | Después va «en camino» |
| --- | --- | --- |
| Reparto y pedidos de tienda (salen con el reparto) | hasta el recuento de la mañana hecho después de terminar las bolsas | desde ese recuento hasta la mañana siguiente |
| Envío y pedidos de Nacex del viernes (salen con el reparto) | hasta el recuento de la mañana hecho después de terminar las bolsas y el envío | desde ese recuento hasta la mañana siguiente |
| Envío y pedidos de Nacex de lunes a jueves (salen a las 18:10, después del recuento de las 17:55) | todo el día | — (la lista del +35 % de la tarde se hace antes) |

- **Lo que queda en el almacén** para el envío y los pedidos del mismo día = hoja − lo comprometido que la hoja aún cuenta (columna 2). Es la regla de siempre del envío antes del recuento (§2.5, R1-22), que ahora aparta también los pedidos de tienda de ese día.
- **R3 (+35 %):** el contador sube por las cajas en camino (columna 3), que el recuento ya ha quitado del almacén y la tienda aún no ha apuntado (§3.9).

**Nacex: hasta cuándo entra un pedido** (decidido por el propietario, 28/10/2026): de lunes a jueves, **hasta las 18:00** (el viernes, hasta las 10:45) y mientras la salida a Nacex no esté hecha; si no, al siguiente día de trabajo. Si por la producción no llega a salir ese día, el operario lo pasa al día siguiente (`aplazar_pedido_nacex`); si queda sin hacer, pasa solo. En los dos casos va como tarea de Nacex de ese día, con su lista y Nacex activado.

**Desfase aceptado** (decisión del propietario, 28/10/2026): si una tienda rellena su «FIN DE DÍA» a mediodía, por la tarde esas cajas cuentan dos veces (en la tienda y en camino) y la lista del +35 % puede pedir un poco menos de lo justo; se corrige solo al día siguiente. Tampoco se cuentan en camino, a la mañana siguiente, el envío y los pedidos de Nacex que salieron la tarde anterior (la regla los da por llegados a la mañana siguiente). En la etapa 2, la tienda confirmará «bolsa recibida» (E2-2).

| # | Entrada | Resultado esperado |
| --- | --- | --- |
| P-01 | Martes: hoja V2 4g 30, reparto 20; al terminar la producción sale el pedido de tienda (3 V2 4g) | «Coge 3 del almacén» (quedan 10). |
| P-02 | El mismo martes: pedido de Nacex (4 V2 4g), con la hoja de antes del recuento (30) y reparto 24 y pedido de tienda 3 | Queda 3: «Coge 3 del almacén y haz 1». |
| P-03 | Almacén vacío, negativo, con texto o referencia que ya no está; decimales | «Haz N»; con «2,5», 2 cajas. |
| P-04 | Después del recuento (hoja V2 4g 3; el reparto ya no cuenta): sale Nacex de Miren (4) y después el de Koldo (1, llegó después) | Miren: «Coge 3 del almacén y haz 1». Koldo: «Haz 1». |
| P-05 | Frases | «Coge 2 del almacén», «Haz 3», «Coge 1 del almacén y haz 1». |
| P-06 | Al guardar el pedido | `motivo` aún `null`: se calcula al salir la tarea. |
| P-07 | Nacex el martes a las 18:05; el viernes a las 11:00 | Al miércoles; al lunes. Con Nacex activado ese día. |
| P-08 | Pasar a mañana el pedido de Nacex de Koldo («Producción tarde»); Miren queda sin hacer | Los dos, en la tarde del miércoles con su lista y Nacex activado; la tarea del martes, «Pasa al 25/11: …». |
| C-01 | Martes, antes del recuento: reparto 24 V2 4g, pedido de tienda 3, dos pedidos de Nacex (4 y 1) | Comprometido: reparto 24, pedidos de tienda 3, Nacex 4 + 1; en camino: nada. |
| C-02 | El mismo martes: recuento de la mañana hecho (12:50) pero bolsas sin terminar; o bolsas terminadas después del recuento | Reparto y pedido de tienda siguen en el almacén; nada en camino. |
| C-03 | Bolsas terminadas (10:40) y recuento después (12:50) | Reparto y pedido de tienda: en camino (24 + 3). Nacex sigue contando en el almacén (4 + 1). |
| C-04 | Al día siguiente | Nada en camino. |
| C-05 | Viernes: envío 6 y pedido de Nacex 2 (salen con el reparto), envío preparado y recuento después | En camino: 6 + 2; el envío y Nacex ya no cuentan en el almacén. |
| C-06 | Envío antes del recuento con reparto 20 y pedido de tienda 6 (V2 4g 30 en la hoja) | Apartadas 26: quedan 4. |
| C-07 | R3: V2 4g, consumo 74, contador de la hoja +20, 5 en camino | Contador +25 → 1 caja (sin la corrección, 6). |
| C-08 | R3: 10 INDOOR PR RELAX 4g en camino | Suman al «INDOOR TOTAL» 4g: 35 cajas en vez de 45. |
| C-09 | R3 sin cajas en camino | La lista de siempre. |

P-01 a P-08 y C-01 a C-05 están en `supabase/tests/17_pedidos_cliente.sql`; C-06, en `reparto_lista_test.ts`; C-07 a C-09 son R3-21 a R3-23.

## 3. R3 — Stock del almacén (+35 %)

### 3.1 Fórmula (§5 R3, sin cambios)
```
contador  = «CAJAS TOTALES HECHAS»      (0 = una semana cubierta)
consumo   = «CONSUMO CAJAS SEMANAL»
objetivo  = 0,35 × consumo
cajas     = objetivo − contador         → solo si sale positivo
```

### 3.2 Redondeo: **hacia arriba** (D1, decidido 26/10/2026)
```
cajas = ⌈ (35 × consumo − 100 × contador) / 100 ⌉   si es > 0; si no, la referencia no aparece
```
Con enteros (o decimal exacto si el consumo trae decimales).

### 3.3 Qué entra y qué no
- **Minis: fuera.** El único mini es **MINIBUDS MIX 10g** (decidido).
- **Vapers: fuera de R3**; los rige R7 (decidido).
- **Invernadero e Indoor:** por categoría, con las filas «INVERNADERO TOTAL» e «INDOOR TOTAL» (una referencia por categoría y formato).
- **FIFO lo decide el operario** (decidido): la app indica las cajas de la categoría, las variedades con granel (en el orden de PRINCIPAL) y la frase «Usa primero el granel más antiguo (FIFO). Mínimo 2 variedades de invernadero y 2 de indoor».

### 3.4 Sin granel no se produce (§5 R3)
- Producto normal: si `cajas > 0` y el granel es 0 o menos → no entra en la lista y aparece la tarea **«Avisa a Administración: falta X»**.
- Categoría que rota: granel = suma de sus variedades. Si es 0 → «Avisa a Administración: falta Invernadero».
- Si hay granel pero no da para todas las cajas: **se lista igual** (decidido; P-R3a queda para más adelante).

### 3.5 Orden y motivo
- **Consumo semanal de mayor a menor**; empate: orden en la hoja (columnas de izquierda a derecha, filas de arriba abajo).
- Motivo: «Se venden 74 cajas a la semana. Tienes +25 y el objetivo es +26. Haz 1.»
- Es aceptable que las que menos se venden queden en torno a +20 %: no cambia el cálculo.

### 3.6 Datos no válidos
- Contador o consumo vacío o no numérico → esa referencia no se calcula y aparece en `avisos`. El resto sí.
- Pestaña o columnas no encontradas → `ESTRUCTURA_SHEETS_CAMBIADA`: no hay lista.

### 3.7 Cuándo se calcula
Una vez por turno (al pedirse la lista por primera vez en el turno), y se guarda con la lectura usada. Sheets solo cambia con el recuento de final de turno. Lo no hecho no se arrastra: se recalcula (§6.5).

### 3.8 Casos de prueba de R3

| # | Datos | Resultado esperado |
| --- | --- | --- |
| R3-01 | **V2 4g**: consumo 74, contador +25, granel 730 | 25,9 − 25 = 0,9 → **1 caja** |
| R3-02 | **Indoor 4g**: consumo 51, contador −27, granel Indoor 700 | 17,85 + 27 = 44,85 → **45 cajas** |
| R3-03 | ICE O LATOR 4g: consumo 17, contador 27 | −21,05 → **no aparece** |
| R3-04 | consumo 20, contador 7 | 0 → **no aparece** |
| R3-05 | consumo 0, contador −3 | **3 cajas** |
| R3-06 | TROPICANA 2025 10g: consumo 36, contador 3, granel 1136 | 9,6 → **10 cajas** |
| R3-07 | MINIBUDS MIX 10g: consumo 33, contador −7 | **Excluido** (mini) aunque saldrían 19 |
| R3-08 | Producto X 4g: consumo 10, contador 0, granel 0 | No aparece. «Avisa a Administración: falta X» |
| R3-09 | Invernadero 4g: consumo 45, contador 17 | **no aparece** |
| R3-10 | Invernadero 10g: consumo 12, contador 0; granel Slush Mints 380, Royal Berry 127, Grapefruit 0 | **5 cajas**; motivo con «Slush Mints, Royal Berry» y la frase de FIFO |
| R3-11 | Indoor 4g con granel Relax 0 y Afru 0 | No aparece. «Avisa a Administración: falta Indoor» |
| R3-12 | A (consumo 52, primera en la hoja), B (73), C (52), todas con cajas | Orden: B, A, C |
| R3-13 | Consumo `""` en una referencia | No se calcula; aviso «dato vacío». Las demás sí |
| R3-14 | Consumo `2,5`, contador 0 | 0,875 → **1 caja** |
| R3-15 | Falta la pestaña CONTEO DE CAJAS TOTAL | `ESTRUCTURA_SHEETS_CAMBIADA` |
| R3-16 | Sheets no responde | `SHEETS_NO_DISPONIBLE`; el resto de tareas sigue |
| R3-17 | Pedir la lista dos veces en el mismo turno | Misma lista, sin duplicar |
| R3-18 | consumo 10, contador 3,2 | 0,3 → **1** (hacia arriba) |
| R3-19 | VAPER: consumo 9, contador −5 | **Excluido** (R7) |
| R3-20 | Producto Y 4g: consumo 40, contador 0, granel 8 g (da para 2 cajas) | **14 cajas** (se lista igual) |
| R3-21 | V2 4g: consumo 74, contador de la hoja +20, 5 cajas en camino (R1c) | Contador +25: **1 caja** («Tienes +25 (con 5 en camino a las tiendas)…»). |
| R3-22 | 10 INDOOR PR RELAX 4g en camino; INDOOR TOTAL 4g: consumo 51, contador −27 | Suman al total de la categoría y formato: −17 → **35 cajas** (10g, sin cambios). |
| R3-23 | Sin cajas en camino | La lista de siempre. |

### 3.9 Cajas en camino (R1c, Tarea 12)
Desde el recuento de la mañana hecho después de la salida (bolsas listas; el viernes, también el envío preparado), lo que ha salido hoy hacia las tiendas (reparto, pedidos de tienda y, el viernes, envío y pedidos de Nacex) se suma al contador de su referencia hasta la mañana siguiente; las variedades de Invernadero e Indoor, al total de su categoría del mismo formato. Así la lista del +35 % de la tarde no pide cajas que ya existen y van de camino. Regla completa y desfase aceptado en §2.10.

## 4. Propuestas pendientes (no aprobadas)

| # | Propuesta | Estado |
| --- | --- | --- |
| P-R3a | Limitar la lista a lo que permite el granel (`granel ÷ gramos del formato`) y avisar a Administración por la diferencia. | Para más adelante (coordinador, 26/10/2026). |

## 5. Dudas

1. **Cabecera del envío a Gipuzkoa/Durango:** ¿empieza por `REPARTO dd/mm`, por `ENVÍO dd/mm` o no lleva cabecera? (Construido así: se acepta `REPARTO` o `ENVÍO`/`ENVIO`, o ninguna.)
2. **Envío del viernes y reparto a la vez:** los dos restan las mismas cajas del almacén de PRINCIPAL (la hoja no cambia hasta el recuento). Si en una caja del almacén se cuenta para las dos cosas, la producción saldría corta. ¿Se calcula el envío descontando lo ya pedido en el reparto del día?
