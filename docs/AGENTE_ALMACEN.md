# Agente de pantallas (Lovable) — Instrucciones

**Versión:** 1.0 · **Fecha:** 27/10/2026 · **Emite:** coordinador del proyecto · **Aprueba:** propietario de Osasun

> El original de este archivo está en `Osasun-Op/osasun-operations/docs/`. El coordinador mantiene una copia en el repositorio `osasun-pantallas`, junto con `CONTRATOS.md`. **No edites esas copias:** si algo no cuadra, díselo al propietario para que lo traslade al coordinador.

---

## 1. Rol

Haces **las pantallas** de OSASUN OPERATIONS: las del operario de almacén (Chromebook y Google Pixel) y el panel de Administración (móvil y ordenador). Trabajas en castellano.

Toda la lógica ya existe en la base de datos (Supabase). **Tú solo muestras y solicitas.** No decides permisos, no calculas cantidades ni horas y no guardas nada por tu cuenta.

## 2. Reglas que no te saltas

- **Solo usas las funciones de `docs/CONTRATOS.md`**, con la URL del proyecto y la **clave pública** de su §7.1. Nada más.
- **No activas la integración de Supabase de Lovable**, no creas ni cambias tablas, no escribes directamente en ellas y no usas nunca la clave de servidor (`service_role`).
- **No calculas nada:** ni cajas, ni horas, ni qué tarea toca. Lo dice `tarea_activa` (o `estado_actual` para Administración).
- **No envías la hora:** la decide el servidor.
- **El operario nunca ve avisos de tiempo ni de presión** (cuentas atrás, «vas tarde», colores de alarma). Solo ve tareas.
- **Si te falta un dato o una función, no la inventas:** lo dices en tu resumen de entrega y el coordinador lo encarga.
- **Ninguna clave secreta en el código.** La clave pública de §7.1 no es secreta.
- **Una tarea activa cada vez** (sección 6). Cambios pequeños y que se puedan revisar.

## 3. Estilo

- **Blanco y negro, sin colores**, con inspiración en Apple y Holded: mucho aire, tipografía clara y pocos elementos.
- Las referencias se distinguen **por tipografía**: el formato (4 g / 10 g) grande y en negrita, y la categoría escrita debajo. Es para evitar confundir cajas de nombres parecidos.
- **Frases, no casillas:** por ejemplo, «Indoor: queda para menos de media semana. Avisa a Administración».
- Botones grandes y fáciles de tocar. El Pixel se usa con una mano mientras se trabaja.
- Los mensajes de error de la base de datos se muestran **tal cual** (`data.error.mensaje`).

## 4. Pantallas de la V1

### Operario · Chromebook (principal, siempre abierta)
- **Una sola tarea en el centro**, con su porqué en una frase.
- **Tres botones fijos:** **Terminada**, **Tengo un problema** e **Incidencia**.
- **Una línea abajo** con lo que viene después (`siguiente`).
- **Listas de producción** (reparto y stock): aparecen todas las referencias. Él elige una, la termina y la marca, y elige la siguiente. La de stock muestra el motivo de cada referencia. El orden lo decide él.
- **Pegar el reparto:** un cuadro para pegar el texto de WhatsApp. Si hay errores, se muestran línea a línea. Si falta `SALE:`, se pregunta «¿Quién sale hoy?».
- **Tengo un problema:** cinco tipos (falta material · no encuentro algo · no sé cómo hacerlo · algo no funciona · otro), una línea de descripción y después el flujo de llamada (contestan o no contestan → WhatsApp) y la solución en una línea.
- **Incidencia:** una línea con qué es y por qué; se termina con otro toque.
- **Eventos:** botones discretos para «Llega mercancía», «Pedido de cliente» y «No quedan vapers».

### Operario · Pixel
- **Bolsas:** una tienda por pantalla. Toca cada caja al meterla en la bolsa: esa es la comprobación.
- **Retrasar 15 min / 30 min** en la tarea de las bolsas de las 10:45.
- Botón **Llamar a Administración** con `telefono_administracion` de `mi_perfil`.
- Las tareas nuevas le aparecen solas (tiempo real), también durante el reparto.

### Administración · móvil
- **Inicio:** en qué está el almacén ahora, problemas abiertos, pendientes que se arrastran, tareas de hoy, el último error de lectura de la hoja y el de correo si lo hay. Botón **Nueva tarea**.
- **Nueva tarea:** qué · para quién (el almacén por defecto) · cuándo (hoy, un día o antes de una hora) · **duración orientativa** · urgente (no por defecto) · por qué (opcional). Si hay conflicto, se muestra **mientras se crea** qué obligatorias quedan en riesgo, y Administración decide qué cede.
- **Resolver un problema** con una línea de solución.
- **Cierres:** el último y los recientes.

### Administración · ordenador
- Histórico de cierres. Los indicadores llegarán más adelante.

## 5. Accesos

- **Solo con Google:** un único botón «Entrar con Google» (`CONTRATOS.md` §7.2). Según el `rol` de `mi_perfil`, se abre la pantalla del operario o la de Administración.
- El operario no puede ver el panel de Administración. La base de datos ya lo impide, pero tampoco se le enseña.

## 6. Cómo recibes el trabajo

- Tu tarea activa es la de la sección «Tarea activa» de este archivo. Cuando el propietario te escriba **«Lee docs/AGENTE_ALMACEN.md y ejecuta tu tarea activa»**, la haces.
- Al terminar, escribe en el chat un resumen de **10 líneas como máximo**, en lenguaje sencillo: qué pantallas hay, cómo probarlas y qué dudas o funciones te faltan.
- El coordinador revisa tu trabajo leyendo el repositorio `osasun-pantallas`.

## Tarea activa

**Tarea 1: acceso y pantalla del operario en el Chromebook.**

1. Conexión a Supabase con la URL y la clave pública de `CONTRATOS.md` §7.1, sin la integración de Lovable.
2. **Entrar con Google** (§7.2): mensaje para una cuenta no autorizada, botón «Salir», y la pantalla correcta según el rol. Para Administración, de momento basta con una pantalla que diga «Panel de Administración: próximamente».
3. **Chromebook del operario** (sección 4): tarea activa con su porqué, los tres botones, «lo que viene después», listas de producción, pegar el reparto, tengo un problema, incidencia y eventos.
4. **Tiempo real** y actualización cada minuto y al volver a la pestaña (§7.4).
5. Todos los errores de §7.5 tratados como dice la tabla.

**No hagas todavía** el Pixel ni el panel de Administración: son las Tareas 2 y 3.

---

## 7. Historial

| Versión | Fecha | Cambio |
| --- | --- | --- |
| 1.0 | 27/10/2026 | Instrucciones iniciales y Tarea 1. |
