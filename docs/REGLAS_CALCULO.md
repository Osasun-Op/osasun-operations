# OSASUN OPERATIONS — Reglas de cálculo R1 y R3 (especificación V1)

**Versión:** 0.3 · **Fecha:** 26/10/2026 · **Autor:** agente de base de datos · **Estado:** aprobada (PR #1). Construida en la Tarea 3: `supabase/functions/_compartido/r1.ts` y `r3.ts`, con sus pruebas (`*_test.ts`).

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

## 4. Propuestas pendientes (no aprobadas)

| # | Propuesta | Estado |
| --- | --- | --- |
| P-R3a | Limitar la lista a lo que permite el granel (`granel ÷ gramos del formato`) y avisar a Administración por la diferencia. | Para más adelante (coordinador, 26/10/2026). |

## 5. Dudas

1. **Cabecera del envío a Gipuzkoa/Durango:** ¿empieza por `REPARTO dd/mm`, por `ENVÍO dd/mm` o no lleva cabecera? (Construido así: se acepta `REPARTO` o `ENVÍO`/`ENVIO`, o ninguna.)
2. **Envío del viernes y reparto a la vez:** los dos restan las mismas cajas del almacén de PRINCIPAL (la hoja no cambia hasta el recuento). Si en una caja del almacén se cuenta para las dos cosas, la producción saldría corta. ¿Se calcula el envío descontando lo ya pedido en el reparto del día?
