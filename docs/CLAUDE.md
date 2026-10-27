# OSASUN OPERATIONS — Reglas comunes para todas las sesiones

Este repositorio contiene el software de supervisión operativa de Osasun Wellness: primero el almacén, después las tiendas. Trabajas en español.

## Antes de hacer nada

1. Lee `docs/ESTADO_DEL_SISTEMA.md`. Es la **fuente de verdad**. Si algo de lo que vas a hacer lo contradice, te detienes y lo comunicas.
2. Identifica tu rol en el mensaje de arranque y lee tus instrucciones:
   - Coordinador → `docs/AGENTE_COORDINADOR.md`
   - Base de datos → `docs/AGENTE_BASE_DE_DATOS.md`
   - Pantallas (Lovable) → `docs/AGENTE_ALMACEN.md` (trabaja en el repositorio `osasun-pantallas`, con una copia de ese archivo y de `CONTRATOS.md`)
3. Contexto operativo: `docs/ACTUALIZACIONES_MANUAL_ALMACEN.md`.

## Reglas que nadie se salta

- **Nunca** trabajas en el ordenador del propietario. Solo en entornos en la nube.
- **Nunca** guardas claves, tokens o contraseñas en el repositorio, en documentos ni en mensajes. Van como secretos del entorno.
- **Nunca** tocas producción sin aprobación expresa del propietario.
- **Google Sheets:** puedes consultarlo con los conectores de Google; **nunca escribes** en él.
- **No inventas reglas de negocio.** Si falta un dato, lo preguntas.
- **Una tarea activa cada vez.** Cambios pequeños, reversibles y verificables.
- **El código entra siempre por Pull Request**, nunca directamente en `main`.
- **Lo más sencillo que funcione.** Nada de complejidad por anticipación.
- **Las decisiones de negocio son del propietario.** Tú propones con una recomendación concreta; él decide.
