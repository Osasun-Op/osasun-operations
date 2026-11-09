# Coordinador — Dónde trabaja y cómo llegan las tareas

**Versión:** 1.2 · **Fecha:** 09/11/2026 · **Aprueba:** propietario de Osasun

> **Decisión del propietario (07/11/2026):** el coordinador trabaja en el proyecto de Claude **«Desarrollo de software operativo»**. Este archivo ya no contiene sus instrucciones.

## Dónde trabaja

- **En el proyecto de Claude «Desarrollo de software operativo».** Allí están sus instrucciones y el sistema de tickets:
  - `claude/agentes/AGENTE_COORDINADOR.md`: sus instrucciones;
  - `claude/coordinacion/SISTEMA_TICKETS.md`: cómo se organiza el trabajo con tickets (T-XXXX).
- **En este repositorio solo lee** (está sincronizado con el proyecto). No escribe en él ni en Supabase.

## Cómo llegan las tareas

1. **El trabajo se organiza con tickets** (T-XXXX).
2. **Las tareas del agente de base de datos le llegan como encargo copiado por el propietario,** con su número de ticket. Cada tarea nueva lleva su número de ticket junto a su número de tarea.
3. **El agente de base de datos entrega un Pull Request.** Ese PR también pone al día `docs/ESTADO_DEL_SISTEMA.md` cuando cambia una regla (constitución, regla 7).
4. **El coordinador revisa el PR con su descripción.**
5. **Lo fusiona el agente de base de datos, solo con el «sí» expreso del propietario a ese PR,** que lo da después de revisarlo con el coordinador. Antes de fusionar, el agente comprueba que la rama sigue en el commit revisado; después dice el commit que queda en `main`. A mano (el propietario), solo como excepción (decisión del propietario, 09/11/2026).

**Referencias antiguas:** otros documentos citan puntos y notas de la versión 1.0 de este archivo. Por ejemplo, `ESTADO_DEL_SISTEMA.md` E2-8 («puntos 1 a 28») o las notas del 04/11 y del 06/11 en las tareas. Ese texto se lee en el commit `789e0a5`: `git show 789e0a5:docs/AGENTE_COORDINADOR.md`.

## Historial

| Versión | Fecha | Cambio |
| --- | --- | --- |
| 1.0 | 26/10/2026 | Instrucciones del coordinador, con su registro de trabajo («Estado actual y siguiente acción», notas hasta el 06/11/2026). El texto completo queda en el historial de git (último commit con él: `789e0a5`). |
| 1.1 | 07/11/2026 | Decisión del propietario: el coordinador pasa al proyecto de Claude «Desarrollo de software operativo» y en el repositorio solo lee. Este archivo queda como página corta (T-0000). |
| 1.2 | 09/11/2026 | T-0009: quién fusiona: el agente de base de datos, con el «sí» expreso del propietario a ese PR tras revisarlo con el coordinador; a mano, solo como excepción. |
