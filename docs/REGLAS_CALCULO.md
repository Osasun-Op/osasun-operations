# OSASUN OPERATIONS — Reglas de cálculo R1 y R3 (especificación V1)

**Versión:** 0.1 (propuesta, pendiente de aprobación) · **Fecha:** 26/10/2026 · **Autor:** agente de base de datos · **Tarea:** 1

> Especificación exacta de las dos reglas que la V1 calcula con datos de Google Sheets: **R1** (texto del reparto) y **R3** (stock del almacén +35 %).
> Lo aprobado en `ESTADO_DEL_SISTEMA.md` §5 se aplica **sin cambios**. Donde el texto aprobado no basta para que el cálculo sea determinista, se indica **[Pendiente Dn]** con el comportamiento provisional, que se lista en «Propuestas» (§4) y en «Dudas» (§5).
> Todo se calcula en el servidor, con pruebas automáticas. Los casos de prueba de este documento serán esas pruebas.

---

## 1. Datos de entrada (Google Sheets, solo lectura)

Documento `STOCK OSASUN-CLAUDE` (ID `1nPhB7U6FoJcYybChUcGOI3mz-yJAv8NkT3uINuQ6qao`). Estructura comprobada leyendo el documento el 26/10/2026:

| Dato | Dónde |
| --- | --- |
| **Catálogo** (producto y formato) | PRINCIPAL, columna A. Cada producto es un bloque: fila con el nombre y, debajo, una fila por formato (`4g`, `10g`, `2g`, `3g`, `20gr`, `CBD`, `CBDX`…), hasta la fila vacía. Los productos sin formato (FORTE, VAPER, 10% FS…) son una sola fila. |
| **Cajas en el almacén** (por producto y formato) | PRINCIPAL, columna R (`ALMACEN · FIN DIA`) de la fila de formato. |
| **Granel en el almacén** (gramos) | PRINCIPAL, columna R de la fila del nombre del producto. |
| **Contador** (cajas hechas en todas partes − consumo semanal) | CONTEO DE CAJAS TOTAL, columna «CAJAS TOTALES HECHAS» de cada formato. |
| **Consumo semanal** (cajas) | CONTEO DE CAJAS TOTAL, columna «CONSUMO CAJAS SEMANAL». |
| **Categoría de cada producto** | ALMACEN, fila 1: grupos EXTERIOR, INVERNADERO, INDOOR POPS, HIGH TECH, ACEITES Y CREMAS. |
| **Categorías que rotan** | CONTEO DE CAJAS TOTAL, filas «INVERNADERO TOTAL» e «INDOOR TOTAL». |

Números: se aceptan enteros, negativos y decimales con coma (`2,5`). Celda vacía o texto no numérico = **dato no válido** (nunca se convierte en 0 sin avisar).

## 2. R1 — Lectura del texto del reparto

### 2.1 Normalización (§5 R1: «ignora espacios y mayúsculas»)
`norm(x)` = pasar a mayúsculas y **quitar todos los espacios** (incluidos los del principio y del final).
- `norm("V2 ")` = `V2`; `norm("v2 4 g")` = `V24G`; `norm("T BALLS / GELATO DRY")` = `TBALLS/GELATODRY`.
- Clave de catálogo = `norm(producto + formato)`. Ej.: «V2 » + «4g» → `V24G`.
- Al leer el catálogo se comprueba que no haya dos entradas con la misma clave. Si las hay, error `CATALOGO_AMBIGUO` (no se calcula; aviso a Administración).
- **No hay búsqueda aproximada.** Un nombre parecido no vale: es justo el error que la app debe evitar (problema 4 del diagnóstico).

### 2.2 Clasificación de cada línea
Cada línea del texto se clasifica en este orden; la primera regla que encaja decide:

| # | Clase | Regla | Ejemplo |
| --- | --- | --- | --- |
| 1 | `vacia` | Solo espacios. Se ignora. | |
| 2 | `cabecera` | Empieza por `REPARTO` seguido de `dd/mm`. Se guarda la fecha. | `REPARTO 27/10` |
| 3 | `sale` | Empieza por `SALE:` (con o sin espacios). | `SALE: ALMACÉN` |
| 4 | `producto` | `<número> x <nombre>` (la `x` en mayúscula o minúscula, con o sin espacios). | `10x V2 4g` |
| 5 | `tienda` | `norm(línea)` coincide con `norm` de un alias de tienda (`centros_trabajo.alias`). | `BILBAO`, `LAUDIO` |
| 6 | `no_reconocida` | Cualquier otra cosa. | `bilbao lleva lo de ayer` |

### 2.3 Línea `SALE:`
| Valor (tras `norm`) | Resultado |
| --- | --- |
| `ALMACÉN` | Sale el operario. |
| `YO` | Sale Administración. |
| Falta la línea u otro valor | `FALTA_SALE`: la app pregunta al operario «¿Quién sale hoy?» (§5 R1, paso 6). |
| Dos líneas `SALE:` con valores distintos | Error `SALE_CONTRADICTORIA`. |

Para el envío a Gipuzkoa/Durango (`tipo = envio`) la línea `SALE:` no se usa.

### 2.4 Líneas de producto
- `cantidad`: entero ≥ 1. `0x` o negativo → `CANTIDAD_NO_VALIDA`.
- `nombre`: `norm(nombre)` debe coincidir con **exactamente una** clave del catálogo. Si no hay ninguna → `PRODUCTO_DESCONOCIDO`.
- Debe haber una tienda antes. Si no → `PRODUCTO_SIN_TIENDA`.
- La misma referencia repetida en la misma tienda se suma.

### 2.5 Cálculo (§5 R1, pasos 3 a 5)
Solo si **no hay ningún error** (paso 2: «avisa antes de calcular»):

```
pedido(p, f)     = Σ cantidades de (p, f) en todas las tiendas del texto
en_almacen(p, f) = PRINCIPAL!R de la fila de formato
faltan(p, f)     = max(0, pedido − en_almacen)
```
- Lista de producción = referencias con `faltan > 0`. Orden sugerido: el del catálogo (PRINCIPAL). El operario elige el orden real.
- Bolsas = una por tienda con sus referencias y cantidades del texto.
- `en_almacen` vacío o negativo → **[Pendiente D-R1b]** provisional: se cuenta como 0 y la línea lleva el aviso «dato de almacén vacío/negativo en PRINCIPAL».
- La app **no cambia ninguna cantidad** del reparto (§5).

### 2.6 Errores
| Código | Bloquea | Mensaje al operario |
| --- | --- | --- |
| `LINEA_NO_RECONOCIDA` | Sí | «Línea N: no entiendo "…". Corrígela o pregunta a Administración.» |
| `PRODUCTO_DESCONOCIDO` | Sí | «Línea N: "…" no está en el catálogo.» |
| `PRODUCTO_SIN_TIENDA` | Sí | «Línea N: falta la tienda antes de esta línea.» |
| `CANTIDAD_NO_VALIDA` | Sí | «Línea N: la cantidad debe ser 1 o más.» |
| `SALE_CONTRADICTORIA` | Sí | «Hay dos líneas SALE: distintas.» |
| `REPARTO_VACIO` | Sí | «No hay ninguna línea de producto.» |
| `FALTA_SALE` | Hasta responder | «¿Quién sale hoy?» |
| `SHEETS_NO_DISPONIBLE` · `ESTRUCTURA_SHEETS_CAMBIADA` · `CATALOGO_AMBIGUO` | Sí | No se calcula nada (principio 8). |

Se devuelven **todos** los errores a la vez, no solo el primero.

### 2.7 Casos de prueba de R1

Catálogo de prueba (extracto real de PRINCIPAL; «en almacén» inventado para la prueba):

| Producto (tal cual en Sheets) | Formato | En almacén |
| --- | --- | --- |
| `V2 ` (con espacio final) | 4g | 25 |
| `V2 ` | 10g | 10 |
| BZ1 | 4g | 7 |
| T BALLS / GELATO DRY | 2g | 0 |
| KRUSH | 20gr | 0 |
| FORTE | (sin formato) | 107 |

Tiendas: BILBAO, ALGORTA, LAUDIO (alias de Durango: `DURANGO`, `LAUDIO`).

| # | Entrada | Resultado esperado |
| --- | --- | --- |
| R1-01 | `REPARTO 27/10` · `SALE: ALMACÉN` · `BILBAO` · `20x V2 4g` · `5x BZ1 4g` · `ALGORTA` · `10x V2 4g` · `4x BZ1 4g` · `1x FORTE` | Aceptado. Sale el operario. Producción: V2 4g pedido 30, almacén 25 → **5**; BZ1 4g pedido 9, almacén 7 → **2**; FORTE 1 vs 107 → no aparece. Bolsas: Bilbao (20 V2 4g, 5 BZ1 4g), Algorta (10 V2 4g, 4 BZ1 4g, 1 FORTE). |
| R1-02 | `bilbao` · `  3 X  t balls / gelato dry 2G ` · `1x v2 4 g` · `SALE: YO` | Aceptado (mayúsculas y espacios ignorados). Sale Administración. T BALLS / GELATO DRY 2g: 3 → faltan 3. V2 4g: 1 → faltan 0. |
| R1-03 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 5g` | `PRODUCTO_DESCONOCIDO` en línea 3. No se crea nada. |
| R1-04 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 4g` · `lo de ayer también` | `LINEA_NO_RECONOCIDA` en línea 4. No se crea nada. |
| R1-05 | `SALE: ALMACÉN` · `2x V2 4g` · `BILBAO` | `PRODUCTO_SIN_TIENDA` en línea 2. |
| R1-06 | `BILBAO` · `2x V2 4g` (sin `SALE:`) | `FALTA_SALE`. Repetido con `sale = administracion` → aceptado. |
| R1-07 | `SALE: ALMACÉN` · `DURANGO` · `2x V2 4g` · `LAUDIO` · `1x V2 4g` | Aceptado. Una sola bolsa para Durango con 3 V2 4g. |
| R1-08 | `SALE: ALMACÉN` · `BILBAO` · `0x V2 4g` | `CANTIDAD_NO_VALIDA`. |
| R1-09 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 4g` · `3x V2 4g` | Aceptado. Bilbao V2 4g = 5. |
| R1-10 | El texto de R1-01 pegado dos veces | La segunda devuelve `REPARTO_YA_PEGADO` con el mismo resultado. Una sola tarea de producción y una de bolsas. |
| R1-11 | Texto de R1-01 con Sheets sin respuesta | `SHEETS_NO_DISPONIBLE`. No se crea nada. |
| R1-12 | `SALE: ALMACÉN` · `SALE: YO` · `BILBAO` · `1x V2 4g` | `SALE_CONTRADICTORIA`. |
| R1-13 | `SALE: ALMACÉN` · `BILBAO` · `1x KRUSH 20gr` / `1x KRUSH 20g` | El primero, aceptado. El segundo, `PRODUCTO_DESCONOCIDO` (ver Propuesta P-R1c). |
| R1-14 | `SALE: ALMACÉN` · `BILBAO` · `2x V2 4g` · `1x XX 4g` · `hola` | Devuelve los dos errores a la vez (líneas 4 y 5). |
| R1-15 | `SALE: ALMACÉN` · (líneas vacías) · `BILBAO` · (vacía) · `2x V2 4g` | Aceptado; las vacías se ignoran. |
| R1-16 | `SALE: ALMACÉN` | `REPARTO_VACIO`. |

## 3. R3 — Stock del almacén (+35 %)

### 3.1 Fórmula (§5 R3, sin cambios)
Para cada referencia (producto + formato) de CONTEO DE CAJAS TOTAL:
```
contador  = «CAJAS TOTALES HECHAS»      (0 = una semana cubierta)
consumo   = «CONSUMO CAJAS SEMANAL»
objetivo  = 0,35 × consumo
cajas     = objetivo − contador         → solo si sale positivo
```
El 35 % sale de `configuracion.stock_objetivo_pct`.

### 3.2 Redondeo (decisión abierta D1) — propuesta: **hacia arriba**
```
cajas = ⌈ (35 × consumo − 100 × contador) / 100 ⌉   si es > 0; si no, la referencia no aparece
```
Se calcula con enteros (o decimal exacto si el consumo trae decimales) para no tener errores de coma flotante.
- **Por qué hacia arriba:** garantiza llegar al +35 %. Redondear al más cercano dejaría referencias por debajo del objetivo (ej. faltan 0,3 cajas → 0 cajas).
- Con los dos ejemplos obligatorios, ambos redondeos dan lo mismo; difieren cuando la parte decimal es menor que 0,5.

### 3.3 Qué entra y qué no
- **Minis: fuera** (§5 R3). Se excluyen las referencias de `configuracion.minis_excluidos`. **[Pendiente D-R3a]** provisional: `MINIBUDS MIX 10g`.
- **Categorías que rotan (Invernadero, Indoor):** se calcula **por categoría** con las filas «INVERNADERO TOTAL» e «INDOOR TOTAL» (una referencia por categoría y formato, ej. «Indoor 4 g»). Las variedades sueltas de esas categorías no se calculan por separado.
- **FIFO y mínimo de 2 variedades** (§5 R3): la lista muestra, junto a la categoría, las variedades con granel en el orden de PRINCIPAL y la frase «Usa primero el granel más antiguo (FIFO). Mínimo 2 variedades de invernadero y 2 de indoor». **[Pendiente D-R3b]**: Sheets no tiene fechas de entrada del granel, así que la app no puede decidir el FIFO por sí sola.
- **Vapers:** tienen su propia regla (R7). **[Pendiente D-R3c]** provisional: fuera de R3.

### 3.4 Sin granel no se produce (§5 R3)
- Producto normal: si `cajas > 0` y el granel (PRINCIPAL!R, fila del producto) es 0 o menor → no se añade a la lista y se crea la tarea **«Avisa a Administración: falta X»**.
- Categoría que rota: granel = suma del granel de sus variedades. Si es 0 → «Avisa a Administración: falta Invernadero».
- **[Pendiente D-R3d]**: si hay granel pero no da para todas las cajas, la regla aprobada no dice nada. Provisional: se lista igual (el operario lo verá al pesar y abrirá un problema «falta material»).

### 3.5 Orden y motivo
- Orden: **consumo semanal de mayor a menor**. Empate: orden de aparición en la hoja (columnas de izquierda a derecha, filas de arriba abajo). Es determinista.
- Motivo (frase, §8): «Se venden 74 cajas a la semana. Tienes +25 y el objetivo es +26. Haz 1.» (el objetivo se muestra redondeado hacia arriba).
- Es aceptable que las referencias que menos se venden se queden en torno a +20 % (§5 R3): no cambia el cálculo; el operario puede no llegar a las últimas.

### 3.6 Datos no válidos
- Contador o consumo vacío o no numérico en una referencia → esa referencia no se calcula y aparece en `avisos`: «No puedo calcular X: dato vacío en CONTEO DE CAJAS TOTAL». El resto sí se calcula.
- Pestaña o columnas no encontradas → `ESTRUCTURA_SHEETS_CAMBIADA`: no hay lista. La tarea lo dice claramente.

### 3.7 Cuándo se calcula
Una vez por turno (al pedirse la lista por primera vez en el turno) y se guarda como elementos de la tarea, con la lectura usada. Motivo: Sheets solo cambia con el recuento de final de turno; recalcular a mitad de turno volvería a pedir cajas ya hechas. Lo no hecho no se arrastra: el turno siguiente se recalcula (§6.5).

### 3.8 Casos de prueba de R3

| # | Datos | Resultado esperado |
| --- | --- | --- |
| R3-01 | **V2 4g**: consumo 74, contador +25, granel 730 | objetivo 25,9 → 25,9 − 25 = 0,9 → **1 caja** |
| R3-02 | **Indoor 4g**: consumo 51, contador −27, granel Indoor 700 | objetivo 17,85 → 17,85 + 27 = 44,85 → **45 cajas** |
| R3-03 | ICE O LATOR 4g: consumo 17, contador 27 | objetivo 5,95 → −21,05 → **no aparece** |
| R3-04 | consumo 20, contador 7 | objetivo 7 → 0 → **no aparece** |
| R3-05 | consumo 0, contador −3 | objetivo 0 → **3 cajas** |
| R3-06 | TROPICANA 2025 10g: consumo 36, contador 3, granel 1136 | 12,6 − 3 = 9,6 → **10 cajas** |
| R3-07 | MINIBUDS MIX 10g: consumo 33, contador −7 | **Excluido** (minis) aunque saldrían 19 |
| R3-08 | Producto X 4g: consumo 10, contador 0, granel 0 | No aparece. Tarea «Avisa a Administración: falta X» |
| R3-09 | Invernadero 4g: consumo 45, contador 17 | 15,75 − 17 → **no aparece** |
| R3-10 | Invernadero 10g: consumo 12, contador 0, variedades con granel: Slush Mints 380, Royal Berry 127, Grapefruit 0 | 4,2 → **5 cajas**. Motivo con «Slush Mints, Royal Berry» y la frase de FIFO |
| R3-11 | Indoor 4g con granel Relax 0 y Afru 0 | No aparece. «Avisa a Administración: falta Indoor» |
| R3-12 | Referencias A (consumo 52, primera en la hoja), B (73) y C (52), todas con cajas a hacer | Orden: B, A, C |
| R3-13 | Consumo `""` en una referencia | Esa no se calcula; aviso «dato vacío». Las demás sí |
| R3-14 | Consumo `2,5`, contador 0 | 0,875 → **1 caja** |
| R3-15 | Falta la pestaña CONTEO DE CAJAS TOTAL | `ESTRUCTURA_SHEETS_CAMBIADA`, sin lista |
| R3-16 | Sheets no responde | `SHEETS_NO_DISPONIBLE`, sin lista; el resto de tareas sigue |
| R3-17 | Pedir la lista dos veces en el mismo turno | Misma lista (misma lectura), sin duplicar elementos |
| R3-18 | Redondeo: consumo 10, contador 3 | 3,5 − 3 = 0,5 → **1** (hacia arriba). Con «al más cercano» también 1; con consumo 10, contador 3,2 sería 0,3 → 1 (arriba) frente a 0 (cercano) |

## 4. Propuestas (no aprobadas; no se aplican hasta que se aprueben)

| # | Propuesta | Motivo |
| --- | --- | --- |
| P-R1a | Aceptar también `SALE: ALMACEN` (sin tilde). | En móvil es fácil escribirlo sin tilde. La regla aprobada solo ignora espacios y mayúsculas. |
| P-R1b | Si la fecha de `REPARTO dd/mm` no es hoy, pedir confirmación antes de calcular. | Evita calcular con el reparto de ayer pegado por error. |
| P-R1c | Tabla de equivalencias de nombres en la configuración (ej. `KRUSH 20g` = `KRUSH 20gr`), mantenida por Administración. | Los nombres irregulares de §9 («20gr», «V2 ») se resuelven sin búsqueda aproximada. Alternativa: limpiar PRINCIPAL (P2). |
| P-R3a | Calcular cuántas cajas permite el granel (`granel ÷ gramos del formato`) y limitar la lista a eso, con aviso a Administración por la diferencia. | Hoy solo se detecta granel 0. |

## 5. Dudas

1. **D1 — Redondeo:** propongo hacia arriba (§3.2).
2. **D-R1a — Cabecera del envío a Gipuzkoa/Durango:** ¿empieza por `REPARTO`, por `ENVÍO` o no lleva cabecera? ¿Qué tiendas lleva?
3. **D-R1b — Almacén vacío o negativo en PRINCIPAL** al calcular lo que falta: ¿contarlo como 0 con aviso (provisional) o bloquear?
4. **D-R1c — Errores en el texto:** la regla dice «avisa antes de calcular». He interpretado que **no se calcula** hasta corregir el texto. ¿O se calcula lo correcto y se avisa del resto?
5. **D-R3a — Minis:** ¿son exactamente `MINIBUDS MIX 10g`? ¿Hay más referencias que excluir?
6. **D-R3b — FIFO dentro de Invernadero e Indoor:** ¿cómo sabe el operario cuál es el granel más antiguo? ¿Debe la app proponer en qué variedades repartir las cajas, o basta con mostrarlas y que él decida? ¿El «mínimo de 2 variedades» es un mínimo a producir o a tener en tiendas?
7. **D-R3c — Vapers:** ¿quedan fuera de R3 (porque los rige R7)?
8. **D-R3d — Granel insuficiente** (hay, pero no para todas las cajas): ¿qué hace la app? (ver P-R3a).
9. **Diferencias de formato entre pestañas** detectadas al leer el documento: T BALLS / GELATO DRY tiene `2g`/`4g` en PRINCIPAL y `2g`/`10g` en CONTEO DE CAJAS TOTAL; KRUSH tiene `20gr` en PRINCIPAL y `10g` en CONTEO. ¿Cuál es el correcto? Hasta aclararlo, esas referencias saldrán con aviso «no coincide con PRINCIPAL».
