# OSASUN OPERATIONS — Constitución técnica

**Versión:** 1.1 · **Fecha:** 07/11/2026 · **Aprueba:** propietario de Osasun

Reglas que **ningún agente puede romper**. Son pocas a propósito. Los demás documentos las citan; no las repiten. Si una instrucción o tarea las contradice, manda esta constitución: te detienes y lo dices.

## Las reglas

1. **Fuentes de verdad.** La hoja STOCK OSASUN manda en el stock, los consumos y el catálogo, y la app **solo la lee**. Supabase manda en todo lo demás (tareas, repartos, pedidos, registros y cierres).
2. **Los cálculos se hacen en el servidor.** Dan siempre el mismo resultado y tienen pruebas. La IA no calcula nada importante y la app nunca propone cantidades para las tiendas.
3. **Las pantallas solo muestran y piden.** Solo usan las funciones de `CONTRATOS.md`, con la clave pública. No calculan, no escriben directamente en las tablas y no deciden permisos.
4. **Cada uno, lo suyo.** El agente de base de datos se ocupa de la estructura, las funciones y los cálculos; Lovable, de las pantallas; el coordinador revisa, encarga y documenta; el propietario decide. Nadie hace el trabajo de otro.
5. **Una sola fuente por cosa.** Antes de crear algo, se busca si ya existe. Si existe, se reutiliza o se sustituye: **nunca se hace otro al lado**.
6. **Lo que usan las pantallas no cambia de forma sin preguntar.** Solo se añaden campos. Cada cambio sube la versión de `CONTRATOS.md` con su nota.
7. **Todo entra por Pull Request** y se fusiona solo con la aprobación expresa del propietario. Sin excepciones: también `ESTADO_DEL_SISTEMA.md`, que el agente de base de datos pone al día en el PR de cada tarea.
8. **La base de datos solo cambia con migraciones del repositorio.** La de pruebas tiene siempre las mismas migraciones que el repositorio. Cada PR dice cómo deshacer su cambio. Producción no se toca sin aprobación expresa.
9. **«Terminado» significa que funciona en el proyecto de pruebas:** las pruebas en verde, **una llamada real que responde bien** y **los registros del servidor sin errores nuevos**. Que pasen las pruebas no basta.
10. **Las reglas de negocio son del propietario.** Si falta un dato, se pregunta, no se inventa. Cada decisión queda en `ESTADO_DEL_SISTEMA.md` con su fecha.
11. **Documentos al día después de cada cambio:** el estado si cambia una regla, los contratos si cambia una función y las instrucciones si cambia una tarea.
12. **Seguridad.** Nunca claves, contraseñas ni datos personales (clientes, teléfonos, correos) en el repositorio, los documentos o los PR. Nunca se trabaja en el ordenador del propietario: solo en la nube.
13. **Lo más sencillo que funcione.** Una tarea activa cada vez, cambios pequeños y nada por si acaso. Una herramienta nueva se crea solo cuando la misma tarea ya se repite.

## Leer antes de actuar (obligatorio, siempre en este orden)

1. Esta constitución.
2. `docs/ESTADO_DEL_SISTEMA.md`: las partes que toca la tarea.
3. `docs/CONTRATOS.md`: las funciones que toca la tarea.
4. El código que ya existe sobre eso (buscar antes de escribir).
5. Actuar.

Cada Pull Request lleva un apartado **«Qué he leído y qué existía ya»**: qué ha leído, qué reutiliza, qué sustituye y qué es nuevo. Un PR sin ese apartado no se da por revisado.

## Historial

| Versión | Fecha | Cambio |
| --- | --- | --- |
| 1.0 | 29/10/2026 | Primera versión, tras el fallo de `guardar_reparto` (respondía con error aunque guardaba, y nadie lo vio durante un día). |
| 1.1 | 07/11/2026 | Regla 7: deja de existir la excepción de los documentos de decisiones que mantenía el coordinador; todo entra por PR, también `ESTADO_DEL_SISTEMA.md` (decisión del propietario, T-0000). |
