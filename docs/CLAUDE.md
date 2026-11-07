# OSASUN OPERATIONS — Reglas comunes para todas las sesiones

Este repositorio contiene el software de supervisión operativa de Osasun Wellness: primero el almacén, después las tiendas. Trabajas en español.

## Antes de hacer nada (obligatorio, en este orden)

1. **`docs/CONSTITUCION_TECNICA.md`**: las reglas que nadie se salta. Si algo las contradice, te detienes y lo comunicas.
2. **`docs/ESTADO_DEL_SISTEMA.md`**: la fuente de verdad del negocio, en las partes que toca tu tarea.
3. **`docs/CONTRATOS.md`**: las funciones que toca tu tarea.
4. **Tus instrucciones**, según el rol del mensaje de arranque:
   - Coordinador → sus instrucciones están en el proyecto de Claude «Desarrollo de software operativo» (`claude/agentes/AGENTE_COORDINADOR.md`). En este repositorio solo lee (ver `docs/AGENTE_COORDINADOR.md`).
   - Base de datos → `docs/AGENTE_BASE_DE_DATOS.md`
   - Pantallas (Lovable) → sus instrucciones están en el proyecto de Claude y en el Knowledge de Lovable. Ya no usan `docs/AGENTE_ALMACEN.md` (obsoleto desde el 07/11/2026).
5. **El código que ya existe** sobre lo que vas a tocar: buscar antes de escribir.
6. Contexto operativo, si hace falta: `docs/ACTUALIZACIONES_MANUAL_ALMACEN.md`.

Las reglas comunes están en la constitución; aquí no se repiten.
