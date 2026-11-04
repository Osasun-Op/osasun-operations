# OSASUN OPERATIONS — Reglas de cálculo R1, R3 y R4 (especificación V1)

**Versión:** 1.3 · **Fecha:** 04/11/2026 · **Autor:** agente de base de datos · **Estado:** aprobada (PR #1). Construida en la Tarea 3: `supabase/functions/_compartido/r1.ts` y `r3.ts`, con sus pruebas (`*_test.ts`). Tarea 4: el envío pegado antes del recuento descuenta el reparto del día (§2.5, R1-22 a R1-24). Tarea 8: el desplegable «¿Quién sale?» manda sobre `SALE:` (§2.3, R1-25 a R1-27). Tarea 10: el reparto se prepara con una lista (§2.9, L-01 a L-09). Tarea 12: pedidos de cliente «coge / haz» al salir la tarea, cajas en camino (salida = bolsas listas) y Nacex hasta las 18:00 (§2.10 y §3.9, P-01 a P-08, C-01 a C-09, R3-21 a R3-23). Tarea 13: peticiones especiales, «Además: …» (§2.9 punto 5, R1-28, R1-29 y L-10). Tarea 14: almacén ahora, cajas en camino con hora y pedidos de tienda que activan el reparto (§2.10, A-01 a A-11, R1-30, R3-24 a R3-27). Tarea 15: el mini se llama MINI 10g (§3.3) y R4, productos con menos de 2 semanas (§4, `r4.ts`, R4-01 a R4-08). Tarea 16: producto sin granel en el reparto (§2.11, `sin_granel.ts`, R1e-01 a R1e-09). Tarea 17: envío sin granel (§2.11, E-01 a E-07). Tarea 29d: «Calcular» del reparto y del envío, solo con la hoja (R1c v1.58; §2.5, §2.10 y §2.11, A-03, A-05, C-06, E-05 y H-01 a H-02).

> Especificación exacta de las reglas que la V1 calcula con datos de Google Sheets: **R1** (texto del reparto), **R3** (stock del almacén +35 %) y **R4** (cobertura a 2 semanas).
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
| **Total y necesidad semanal** (R4) | PRINCIPAL, columnas «LO QUE HAY EN TOTAL» (T) y «1 SEMANA NECESIDADES» (U) de la fila del nombre del producto. Se buscan por su encabezado. |
| **Cajas de cada tienda** (R1e) | PRINCIPAL: cada tienda tiene su nombre en la fila 1 y sus cajas en la columna de la izquierda («FIN DIA», o «TOTAL» en Durango y Portu), en la fila de cada formato (o en la del nombre si no tiene formato). |
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
- **«Calcular» del reparto y del envío: solo la hoja** (`ESTADO_DEL_SISTEMA.md` R1c v1.58, Tarea 29d; **sustituye** a lo que sigue): `en_almacen` es la cifra de la hoja leída al calcular, tal cual. Ni lo producido o salido desde el recuento ni lo apartado de otro reparto, envío o pedido: `apartado_reparto` es siempre 0 en `guardar_reparto`.
- *Antes de la Tarea 29d* — **Envío pegado antes del recuento de la mañana del mismo día** (decidido en el PR #3, `ESTADO_DEL_SISTEMA.md` v1.11): la hoja aún no refleja las cajas del reparto aceptado ese día, así que primero se apartan: `disponible = max(0, en_almacen − pedido en el reparto de hoy)` y `faltan = max(0, pedido − disponible)`. Se devuelve `apartado_reparto` por referencia. Desde la Tarea 14 se aparta lo que aún no ha salido (bolsas sin terminar); lo que ya ha salido se resta como salido del almacén ahora (§2.10). El reparto nunca descuenta.
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
| R1-28 | `BILBAO` · `2x V2 4g` · `Además: rollos de TPV; muestras` · `ALGORTA` · `ademas: cajas vacías` | Aceptado. Las líneas «Además:» son peticiones de su tienda (clase `peticion`): no cuentan para producción ni bolsas. |
| R1-29 | `Además: rollos` antes de ninguna tienda; `Además:` vacío | `LINEA_NO_RECONOCIDA` en las dos. |
| R1-30 | Reparto sin productos (`SALE: ALMACÉN` y nada más); y lo mismo llevando pedidos de cliente (Tarea 14) | `REPARTO_VACIO`; con pedidos, aceptado sin producción ni bolsas. |

### 2.9 Reparto con lista (Tarea 10, `ESTADO_DEL_SISTEMA.md` v1.21)
El texto ya no se pega: se elige cada referencia de una lista (`lista.ts`). R1 no cambia; la lista se convierte en el texto de siempre y se calcula con R1.
1. **Catálogo:** una referencia por producto y formato de PRINCIPAL (y los productos sin formato), en el orden de la hoja. Clave estable `producto|formato`. Categoría: el grupo de la pestaña ALMACEN; si no está, «Otros».
2. **Validación** contra la hoja leída al guardar: referencia que ya no está → `REFERENCIA_NO_EXISTE` (dice cuáles); tienda que no vale para el tipo (reparto: BILBAO, ALGORTA, BARAKALDO, BASAURI, PORTU; envío: GIPUZKOA, DURANGO; Donosti y Rentería son solo de consulta), cantidad no entera o negativa, o lista vacía → `DATOS_NO_VALIDOS`. Cantidad 0 se ignora; la misma referencia en la misma tienda se suma.
3. **Texto:** `REPARTO dd/mm` (o `ENVÍO dd/mm`), `SALE: ALMACÉN|YO` (solo reparto), y por tienda una línea en blanco, su código y `Nx PRODUCTO FORMATO` con los nombres exactos de la hoja. Tiendas en el orden de las hojas de tienda de STOCK OSASUN (configuración `destinos_reparto`); productos en el orden de la hoja. Se copia tal cual con un botón: no se abrevia.
4. **Cálculo:** R1 sobre ese texto, con la fecha de hoy y el desplegable «¿Quién sale?» (§2.3). Mismo cálculo (§2.5), misma sustitución (§2.6) y mismo apartado del envío antes del recuento.
5. **Peticiones especiales** (Tarea 13, `ESTADO_DEL_SISTEMA.md` v1.26, R1d): texto libre por tienda (rollos de TPV, muestras, cajas vacías…), una por línea, 120 letras como máximo; las vacías se ignoran y la misma en la misma tienda (sin contar mayúsculas) cuenta una vez. En el texto, tras los productos de su tienda, una línea `Además: …` con todas, separadas por «; ». R1 la reconoce y la ignora: **no cuentan como stock ni van a producción**. Van a la bolsa de su tienda, una a una para tocarlas.

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
| L-10 | Peticiones: Portu «Rollos de TPV»; Bilbao « muestras de V2 », «   » y «MUESTRAS DE V2»; Bilbao con 6 MINI 10g | `BILBAO` · `6x MINI 10g` · `Además: muestras de V2` · `PORTU` · `Además: Rollos de TPV` (Portu solo con peticiones). Más de 120 letras o tienda que no vale → `DATOS_NO_VALIDOS`. La producción y las bolsas son las mismas que sin peticiones. |

### 2.10 Pedidos de cliente, almacén ahora y cajas en camino (Tareas 12 y 14, `ESTADO_DEL_SISTEMA.md` v1.27, R1b y R1c)
**Almacén ahora (R1c, rehecha en la Tarea 14).** La hoja solo cambia con los recuentos y con el «FIN DE DÍA» de cada tienda. Entre medias la app lleva su propia cuenta, **solo en sus cálculos y nunca en la hoja**. Hay una sola fuente: `motor.movimientos_almacen` y `motor.en_camino_en`, que usan todos (`servidor_preparar`, «coge / haz», `lista_stock`, `estado_actual`).
- **«Calcular» del reparto y del envío no usa el almacén ahora** (R1c v1.58, Tarea 29d): usa la cifra de la hoja tal cual (§2.5). El almacén ahora sigue para el «coge / haz» de los pedidos, la lista del +35 % y las cajas en camino.
- **Almacén ahora** = hoja del almacén + lo producido y marcado desde el último recuento − lo que ha salido desde ese recuento.
  - **Producido:** referencias de producción terminadas (del reparto, del envío, de los pedidos y de la lista del +35 %). De un pedido, solo lo que había que hacer («haz»).
  - **Salido:** las bolsas listas (reparto y pedidos de tienda), el envío preparado y los pedidos de Nacex preparados.
- **Cada recuento** (12:45; 17:55 o 18:15) pone el almacén al día: la hoja leída después ya lo recoge, y lo producido y lo salido vuelven a contar desde él. Cada cálculo usa la última lectura de la hoja y cuenta desde el recuento que esa lectura ya recoge.
- **Cajas de todas partes** (lista del +35 %, §3.9) = almacén ahora + lo que dicen las tiendas en la hoja + **lo que va en camino** a cada tienda:
  - el reparto en coche (y los pedidos para recoger en tienda), desde las bolsas listas **hasta las 23:30** de ese día;
  - el envío a Gipuzkoa o Durango, desde que está preparado **hasta las 11:59 del día siguiente**, todos los días.
  - El recuento no las borra. Las horas están en `configuracion` (`en_camino_reparto_hasta`, `en_camino_envio_hasta`).
  - El envío en camino cuenta **solo para su tienda, nunca para el almacén** (decisión del propietario, 28/10/2026).
- **Pedidos de cliente por Nacex:** salen del stock. Se restan del almacén y no se suman a ninguna tienda.
- **Antes del recuento no se cuenta dos veces:** lo que ha salido sigue en la hoja del almacén hasta el recuento, pero se resta como salido; a la vez se suma en camino a su tienda.
- **Lo comprometido** (`motor.pendiente_salir`) es lo que aún no ha salido: el reparto hasta las bolsas listas, el envío hasta prepararlo y los pedidos. Se aparta para lo que va después: el envío aparta el reparto y los pedidos de tienda de hoy (§2.5); el pedido aparta lo oficial y los pedidos anteriores.
- Se usa en el reparto (también el primero del día: a las 8:30 da lo mismo que la hoja; decidido por el propietario, 28/10/2026), al modificarlo, en el envío, en el «coge / haz» y en la lista del +35 %. Al recalcular un reparto o un envío no se suma lo producido para él mismo, que ya cuenta como hecho en sus elementos.

**Coge / haz** (`motor.calcular_pedido`). Cada referencia de un pedido de cliente dice «Coge N del almacén» o «Haz N» (o las dos: «Coge 2 del almacén y haz 1»). **Se calcula al salir la tarea de prepararlo** (cuando le toca al operario; decidido por el propietario, 28/10/2026), no al guardar el pedido:
- `queda = máx(0, almacén ahora − lo que aún no ha salido y va antes que él)` (almacén vacío, negativo o con texto en PRINCIPAL: 0; con decimales, la parte entera, como en R1).
- `coge = mín(pedido, queda)`; `haz = pedido − coge`.
- **Primero lo oficial y después el pedido:** «antes» es el reparto y el envío de ese día y los pedidos (de tienda o de Nacex) que llegaron antes que él.
- La producción del reparto **no cambia**: solo lleva las cajas del reparto oficial. Lo que haya que hacer para el pedido está en su propia tarea («Haz N»).
- Si la tarea pasa al día siguiente (a mano o sin terminar), se vuelve a calcular al salir ese día.

**Un pedido para recoger en tienda activa el reparto** (decisión del propietario, 28/10/2026, Tarea 14):
- Entra en el reparto de hoy mientras **las bolsas no estén listas**. Si aún no hay reparto, mientras «Prepara el reparto» siga abierta. Si no, va al siguiente día de trabajo.
- Si el reparto de hoy ya está guardado, entra en él al momento, con su tarea y su bolsa aparte.
- Con un pedido esperando, «Prepara el reparto» **no se cierra sin reparto** (ni con motivo): hay que prepararlo, aunque sea **solo con el pedido**. Un reparto sin productos vale solo si lleva pedidos de cliente.
- En «Preparar reparto», los pedidos salen **marcados y fijos** en su tienda («Pedido de Ane a tienda de Bilbao»).

**Nacex: hasta cuándo entra un pedido** (decidido por el propietario, 28/10/2026): de lunes a jueves, **hasta las 18:00** (el viernes, hasta las 10:45) y mientras la salida a Nacex no esté hecha; si no, al siguiente día de trabajo. Si por la producción no llega a salir ese día, el operario lo pasa al día siguiente (`aplazar_pedido_nacex`); si queda sin hacer, pasa solo. En los dos casos va como tarea de Nacex de ese día, con su lista y Nacex activado.

**Desfase aceptado** (decisión del propietario, 28/10/2026): si una tienda rellena su «FIN DE DÍA» antes de las 23:30, esas cajas cuentan dos veces hasta esa hora (en la tienda y en camino) y la lista del +35 % puede pedir un poco menos de lo justo. Lo mismo con el envío hasta las 11:59 del día siguiente. En la etapa 2, la tienda confirmará «bolsa recibida» (E2-2).

| # | Entrada | Resultado esperado |
| --- | --- | --- |
| A-01 | 12:45: almacén 5 y tienda 3 en la hoja, más 3 del reparto en camino | Cajas de todas partes: **11**. |
| A-02 | 17:55: almacén 8 y Gipuzkoa 4 en la hoja, más 4 en la caja de Nacex | **16**. |
| A-03 | El hueco: a las 09:30 se hacen 6 BZ1 4g (con 4 en la hoja); a las 11:00 se modifica el reparto pidiendo 5 más | Desde la Tarea 29d, con la hoja: en el almacén 4, **falta 1** (antes, almacén ahora 10 y ninguna). |
| A-04 | Antes del recuento: la hoja aún cuenta 3 cajas que ya salieron con las bolsas (almacén 8 y tienda 3 en la hoja) | 8 + 3 − 3 salidas + 3 en camino = **11** (no 14). |
| A-05 | Lo producido para el propio reparto | No cambia la cifra de la hoja; lo hecho se conserva en sus elementos al volver a calcular. |
| A-06 | Cada recuento (mañana y tarde) | Pone a cero lo producido y lo salido; lo que va en camino sigue. |
| A-07 | Reparto con bolsas listas a las 10:45 | En camino a su tienda hasta las 23:30 (a las 23:31, ya no). |
| A-08 | Envío del miércoles preparado a las 16:30 | En camino a Gipuzkoa hasta el jueves a las 11:59 (a las 12:00, ya no). |
| A-09 | Pedido de Nacex de 2 (coge 1, haz 1) preparado | Salido 2, producido 1; no va en camino a ninguna tienda. |
| A-10 | Pedido de tienda con el reparto guardado y las bolsas sin terminar; con las bolsas listas | Entra en el de hoy; al siguiente día de trabajo. |
| A-11 | Pedido de tienda sin reparto y «Prepara el reparto» abierta | Para hoy; «Prepara el reparto» no se cierra sin reparto; reparto solo con el pedido. |
| P-01 | Martes: hoja V2 4g 30, reparto 20; al terminar la producción sale el pedido de tienda (3 V2 4g) | «Coge 3 del almacén» (quedan 10). |
| P-02 | El mismo martes, 13:00: pedido de Nacex (4 V2 4g); con la hoja de las 08:30 (30) han salido 29 con las bolsas (reparto 24 y pedidos de tienda 3 + 2) | Queda 1: «Coge 1 del almacén y haz 3». |
| P-03 | Almacén vacío, negativo, con texto o referencia que ya no está; decimales | «Haz N»; con «2,5», 2 cajas. |
| P-04 | Con la hoja del recuento de las 12:50 (hecho antes de las bolsas: aún las contaba, 30): sale Nacex de Miren (4) y después el de Koldo (1, llegó después) | Miren: «Coge 1 del almacén y haz 3». Koldo: «Haz 1». |
| P-05 | Frases | «Coge 2 del almacén», «Haz 3», «Coge 1 del almacén y haz 1». |
| P-06 | Al guardar el pedido | `motivo` aún `null`: se calcula al salir la tarea. |
| P-07 | Nacex el martes a las 18:05; el viernes a las 11:00 | Al miércoles; al lunes. Con Nacex activado ese día. |
| P-08 | Pasar a mañana el pedido de Nacex de Koldo («Producción tarde»); Miren queda sin hacer | Los dos, en la tarde del miércoles con su lista y Nacex activado; la tarea del martes, «Pasa al 25/11: …». |
| C-01 | Antes de las bolsas: reparto 24 V2 4g, pedidos de tienda 3 y 2, dos pedidos de Nacex (4 y 1) | Comprometido: todo; en camino: nada. |
| C-02 | Recuento hecho pero bolsas sin terminar | El reparto y los pedidos de tienda siguen comprometidos. |
| C-03 | Bolsas listas | Reparto y pedidos de tienda: salidos y en camino a su tienda (Bilbao 27, Portugalete 2). Nacex sigue en el almacén. |
| C-04 | Al día siguiente | El reparto de ayer ya no va en camino. |
| C-05 | Viernes: envío 6 y pedido de Nacex 2 preparados | En camino: Gipuzkoa 6. El pedido de Nacex, no (sale del stock). |
| C-06 | Envío con reparto 20 y pedido de tienda 6 sin salir (V2 4g 30 en la hoja) | Desde la Tarea 29d, no se aparta nada: 30 (antes, apartadas 26 y quedaban 4). Con las bolsas ya listas (25 salidas), tampoco se restan: 30. |
| H-01 | 29d · El 04/11: la hoja dice 0; se produjeron 2 el día anterior sin recuento marcado; se piden 2 | En el almacén 0: **hay que producir 2** (antes, la cuenta propia daba 2 y ninguna). |
| H-02 | Lo mismo sin granel | Reparto: a la producción como sin granel (quitar o coger de otra tienda, R1e). Envío: `SIN_GRANEL`. |

A-01, A-02 y A-04 son R3-24 a R3-26; A-03, A-05, H-01 y H-02, en `reparto_lista_test.ts`; A-06 a A-11 y C-01 a C-05, en `supabase/tests/19_almacen_ahora.sql` y `17_pedidos_cliente.sql`; P-01 a P-08, en la 17; C-06, en `reparto_lista_test.ts`.

### 2.11 Producto sin granel en el reparto (Tarea 16, `ESTADO_DEL_SISTEMA.md` v1.30, R1e)

Quien prepara el reparto no mira el almacén: **de dónde sale cada cosa lo decide el almacén, en la producción.**

**Detectarlo** (`_compartido/sin_granel.ts`, al guardar el reparto; el envío no):
- Una referencia de la producción del reparto que hay que hacer (`faltan > 0`) y cuyo producto tiene **granel ≤ 0** en PRINCIPAL (el mismo criterio que «sin granel no se produce» de R3, variedad por variedad) lleva `sin_granel: true`. Un granel vacío o no numérico no se marca (R3 ya lo avisa).
- `para`: las tiendas del reparto que la reciben, con lo que pide cada una y lo que le falta. Lo que hay en el almacén se lo llevan las primeras tiendas del reparto, en su orden.
- `tiendas_con_stock`: las demás tiendas del reparto con cajas de esa referencia según sus columnas de PRINCIPAL (solo las que tienen alguna). Se usa lo que ya se lee al calcular.

**Decidir** (`resolver_sin_granel`, el operario, una decisión por tienda de `para`): `quitar` u `otra_tienda` (con la tienda de origen) y la cantidad (de 1 a lo que pide esa tienda). Entre todas suman lo que falta. Las decisiones se guardan en la referencia y **todo lo demás sale de ellas** (una sola fuente):
- la referencia queda hecha sin producir;
- **quitar:** la bolsa de esa tienda lleva menos y la línea del reparto baja (o desaparece);
- **otra tienda:** esas cajas no se producen ni van en la bolsa. En la bolsa de la tienda que recibe, «Llama a [origen] para que prepare N [producto formato] para su retirada» (se marca como una petición). La parada «Recoge N [producto formato] en [origen] y déjalas en [destino]» sale a quien hace la ruta;
- **texto para WhatsApp:** lo quitado ya no sale; lo de otra tienda, en una línea propia: «2x BZ1 4g (de Algorta)». Si a la tienda le queda algo del almacén, va en otra línea («1x BZ1 4g»). Una tienda sin nada se quita;
- **cuentas (R1c):** lo quitado o de otra tienda no está pendiente de salir del almacén ni sale de él. Lo de otra tienda va en camino desde «bolsas listas» hasta las 23:30, como el reparto: −N en la que da y +N en la que recibe (en total, igual).

**Modificar el reparto:**
- lo de otra tienda se conserva mientras la tienda lo siga pidiendo (como mucho, lo que pide ahora);
- lo quitado no se conserva como decisión, porque ya está en la línea: «Modificar reparto» la abre con la cantidad nueva;
- si lo decidido ya no cubre lo que falta, la referencia vuelve a salir sin resolver (y la parada y el aviso de llamada se quitan hasta decidir otra vez).

| # | Datos | Resultado |
| --- | --- | --- |
| R1e-01 | BZ1 4g sin granel; Bilbao pide 3 y Portu 2; 1 en el almacén; Algorta 4, Barakaldo 0, Basauri −2 en PRINCIPAL | `sin_granel`; `para`: Bilbao 2 (de 3), Portu 2; `tiendas_con_stock`: Algorta 4 |
| R1e-02 | V2 con granel | No se marca: se hace como siempre |
| R1e-03 | BZ1 sin granel, pero lo hay en el almacén | No se marca (no hay que hacer nada) |
| R1e-04 | Granel vacío | No se marca |
| R1e-05 | Producto sin formato (FORTE) | Las cajas de las tiendas, de la fila del nombre |
| R1e-06 | BZ1: Bilbao 3, Portu 2, nada en el almacén. Bilbao quitar 3; Portu, 2 de Algorta | Referencia hecha sin producir; bolsa de Bilbao sin BZ1; la de Portu, sin cajas de BZ1 y con «Llama a Algorta para que prepare 2 BZ1 4g para su retirada»; parada «Recoge 2 BZ1 4g en Algorta y déjalas en Portugalete» |
| R1e-07 | Después, se modifica: Bilbao ya sin BZ1 y Portu pide 3 | Lo de Algorta (2) no cubre 3 → vuelve a salir sin resolver. Si Portu vuelve a 2, la decisión vale otra vez |
| R1e-08 | WhatsApp de R1e-06 | «BILBAO / 2x V2 4g» (sin BZ1) y «PORTU / 2x BZ1 4g (de Algorta)» |
| R1e-09 | Bolsas listas a las 10:45 | En camino a las 12:00: Bilbao +2 V2, Portu +2 BZ1, Algorta −2 BZ1; a las 23:45, nada. BZ1 no sale del almacén |

**En el envío** (Tarea 17, `ESTADO_DEL_SISTEMA.md` v1.31): no hay ruta que pase por otra tienda, así que se comprueba **al calcular**, no en la producción. Con la misma cuenta que decide lo que falta (desde la Tarea 29d, la cifra de la hoja tal cual), si una referencia hay que hacerla y su producto tiene granel ≤ 0, **no se guarda nada** y el error `SIN_GRANEL` dice, por destino, lo pedido y lo que hay (lo máximo que se puede mandar). Las cajas se las llevan los primeros destinos, en su orden (`sinGranelEnvio`, `sin_granel.ts`). La pantalla ofrece «Dejarlo en N» o «Quitarlo» y vuelve a calcular.

| # | Datos | Resultado |
| --- | --- | --- |
| E-01 | Envío: 5 BZ1 4g a Gipuzkoa; 0 en el almacén, con granel | Se guarda como siempre (hacer 5) |
| E-02 | Lo mismo, sin granel | `SIN_GRANEL`: «BZ1 4g: pides 5, en el almacén no hay cajas y no hay granel para hacerlas.» (`hay` 0). No se guarda nada |
| E-03 | 3 en el almacén, sin granel | «BZ1 4g: pides 5, en el almacén hay 3 cajas y no hay granel para hacer las otras 2.» (`hay` 3) |
| E-04 | Gipuzkoa 4 y Durango 3; 5 en el almacén, sin granel | Gipuzkoa se lleva 4; Durango: «pides 3, en el almacén hay 1 caja y no hay granel para hacer las otras 2.» |
| E-05 | Viernes: 6 en el almacén, 4 para el reparto de hoy sin salir; el envío pide 3, sin granel | Desde la Tarea 29d no se aparta lo del reparto: hay 6 y se guarda (antes, «pides 3, en el almacén hay 2 cajas…»). |
| E-06 | Tras `SIN_GRANEL`, el mismo `id_cliente` con «Dejarlo en 3» | Se guarda normal |
| E-07 | El reparto (no el envío) sin granel | Sin cambios: va a la producción (R1e-06) |

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
- **Minis: fuera.** El único mini es **MINI 10g**: así se llama en PRINCIPAL, en CONTEO DE CAJAS TOTAL y en las tiendas (corregido el 29/10/2026; antes ponía «MINIBUDS MIX» y el mini salía en la lista).
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
| R3-07 | MINI 10g: consumo 33, contador −7 | **Excluido** (mini) aunque saldrían 19 |
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
| R3-24 | 12:45: V2 4g, consumo 40; hoja 8 (almacén 5 y tienda 3); 3 del reparto en camino | Contador +11 → **3 cajas** («Tienes +11 (con 3 en camino a las tiendas)…»). |
| R3-25 | 17:55: consumo 60; hoja 12 (almacén 8 y Gipuzkoa 4); 4 en la caja de Nacex | Contador +16 → **5 cajas**. |
| R3-26 | Antes del recuento: hoja 11 (aún cuenta las 3 que salieron); 3 salidas y 3 en camino | Contador +11 (no 14) → **3 cajas**, sin explicación (se compensan). |
| R3-27 | Hoja 8; 6 hechas desde el recuento; 2 salidas en un pedido de Nacex | Contador +12 → **2 cajas** («(con 6 hechas desde el recuento y sin 2 que ya han salido)»). |

### 3.9 Cajas de todas partes (R1c, rehecha en la Tarea 14)
El contador de CONTEO DE CAJAS TOTAL se corrige con los movimientos desde el último recuento: **+ lo hecho − lo salido + lo que va en camino** a las tiendas (el reparto hasta las 23:30; el envío hasta las 11:59 del día siguiente). Un pedido de Nacex sale y no va a ninguna tienda: resta. Las variedades de Invernadero e Indoor suman al total de su categoría del mismo formato. Así la lista del +35 % no pide cajas que ya existen. El motivo lo explica: «(con 6 hechas desde el recuento y 5 en camino a las tiendas)»; antes del recuento, lo salido y lo que va en camino se compensan y no se nombran. Regla completa en §2.10.

## 4. R4 — Cobertura a 2 semanas (Tarea 15, `ESTADO_DEL_SISTEMA.md` v1.29)

Una sola cuenta (`supabase/functions/_compartido/r4.ts`, `calcularCobertura`) para el panel de Administración («Productos con menos de 2 semanas», siempre a la vista) y, cuando se construya, para el aviso del jueves.

### 4.1 Cuenta
- Por producto: **«LO QUE HAY EN TOTAL»** frente a **2 × «1 SEMANA NECESIDADES»**, de la fila del nombre en PRINCIPAL. Solo sale si `total < 2 × necesidad` (justo 2 semanas no sale).
- `semanas = total ÷ necesidad`, con un decimal, hacia abajo.
- **Invernadero e Indoor:** una fila por categoría («Invernadero», «Indoor»), sumando el total y la necesidad de todas sus variedades (las de la pestaña ALMACEN, como en R3).
- **La hoja tal cual:** sin «almacén ahora» ni cajas en camino. Producir o mandar a una tienda no cambia el total; solo las ventas, que la hoja recoge con el FIN DE DÍA.
- El total viene por producto, no por formato: `formato` es siempre `""`.

### 4.2 Qué entra y qué no
- Los productos que se reparten (los del catálogo: con formatos o con datos de tiendas). La materia prima (DISTILLATE…) no cuenta.
- **Fuera:** los de `stock_excluidos` (MINI y VAPER), por nombre de producto, y lo que tiene **necesidad 0**.
- **Dato vacío, no numérico o negativo** (total o necesidad): no se inventa. Va a un aviso («No puedo calcular X en PRINCIPAL (…)»). Si es una variedad, el aviso es de toda su categoría.
- Sin las columnas en PRINCIPAL: un solo aviso. El reparto y el stock siguen igual.

### 4.3 Dónde se calcula y cuándo
Cada vez que el servidor lee la hoja para el reparto, el envío o la lista de stock (varias veces al día), calcula R4 y lo guarda con esa lectura (`lecturas_sheets.cobertura`). `estado_actual().cobertura_baja` enseña la última, con su hora (`datos_leidos_en`). **No se lee la hoja al abrir el panel.** Las lecturas de los pedidos de cliente no la traen.

### 4.4 Casos de prueba (`r4_test.ts`)
| # | Datos | Resultado |
| --- | --- | --- |
| R4-01 | BZ1: total 701, necesidad 300 | Por encima (701 ≥ 600): **no sale** |
| R4-02 | KUSH WATERHASH: 302, necesidad 219 | Por debajo (302 < 438): **sale, 1,3 semanas** («Hay 302 en total y se necesitan 219 a la semana: da para 1,3 semanas.») |
| R4-03 | ICE O LATOR: 198, necesidad 99 | Justo 2 semanas: **no sale** |
| R4-04 | Invernadero: Slush 662/68,5, Royal Berry 306/28, Grapefruit 4/105,5 | Por categoría: 972 ≥ 404, **no sale** aunque Grapefruit solo tenga 4. Con 100, 50 y 4: 154 < 404 → **«Invernadero», 0,7 semanas** |
| R4-05 | MINI 10/305, VAPER 1/7, SUGAR 0/0 | **Excluidos** (mini y vaper) y necesidad 0: nada |
| R4-06 | CBD DRY sin total; TXABAKO SUST con total −40; una variedad de Indoor con necesidad «x» | **Avisos**, ninguno en la lista (el de Indoor, de toda la categoría) |
| R4-07 | Varios por debajo y una materia prima | De menos a más semanas; la materia prima no cuenta |
| R4-08 | Extracto real de la hoja | Columnas por su encabezado; sin ellas, un solo aviso |

## 5. Propuestas pendientes (no aprobadas)

| # | Propuesta | Estado |
| --- | --- | --- |
| P-R3a | Limitar la lista a lo que permite el granel (`granel ÷ gramos del formato`) y avisar a Administración por la diferencia. | Para más adelante (coordinador, 26/10/2026). |

## 6. Dudas

1. **Cabecera del envío a Gipuzkoa/Durango:** ¿empieza por `REPARTO dd/mm`, por `ENVÍO dd/mm` o no lleva cabecera? (Construido así: se acepta `REPARTO` o `ENVÍO`/`ENVIO`, o ninguna.)
2. **Envío del viernes y reparto a la vez:** los dos restan las mismas cajas del almacén de PRINCIPAL (la hoja no cambia hasta el recuento). Si en una caja del almacén se cuenta para las dos cosas, la producción saldría corta. ¿Se calcula el envío descontando lo ya pedido en el reparto del día?
