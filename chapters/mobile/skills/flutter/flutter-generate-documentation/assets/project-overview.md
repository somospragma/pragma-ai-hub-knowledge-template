# pragma-ia-foundations — Visión General

## Visión

Centro de conocimiento compartido que proporciona **skills reutilizables, prompts especializados y definiciones de agentes** para optimizar el trabajo con IA generativa. Habilita a equipos multidisciplinarios (desarrolladores, QA, DevOps, arquitectos) a trabajar con agentes de IA de forma eficiente, con contexto consistente y know-how documentado.

## Objetivos Principales

1. **Reusabilidad:** Centralizar skills y prompts de dominio (backend, frontend, mobile, QA, arquitectura, DevOps) para evitar duplicación
2. **Consistencia:** Mantener estándares compartidos de calidad, nomenclatura y estructura en todos los dominios
3. **Escalabilidad:** Diseñar la base de conocimiento para crecer con nuevos skills sin fricción
4. **Integración Agental:** Optimizar para detección automática y consumo por agentes de IA (Copilot, Kiro, Cursor)
5. **Mantenibilidad:** Documentación completa y procesos claros para contribuciones sin bottlenecks

## Problemas Resueltos

- **Context rot en agentes:** Agentes olvidan contexto entre sesiones → **Solution:** Skills persistentes con keywords para carga automática, AGENTS.md como brújula
- **Reinventar ruedas:** Teams crean skills similares en paralelo → **Solution:** Centralizar en pragma-ia-foundations, reutilizar con referencias
- **Documentación dispersa:** Specs, decisiones, patrones en múltiples lugares → **Solution:** Framework de 7 documentos + templates por dominio
- **Onboarding lento:** Nuevos desarrolladores no conocen el stack de cada área → **Solution:** Specs-driven docs + MCP servers como contexto ejecutable
- **Agentes ejecutan comandos destructivos:** Sin guardrails → **Solution:** AGENTS.md con deny lists, steering files con reglas condicionales

## Principios Arquitectónicos

- **Modularidad:** Cada skill es independiente, con su propio SKILL.md y referencias
- **Agnóstico:** Aplica a múltiples IDEs (Copilot, Kiro, Cursor) y tipos de agentes
- **DRY (Don't Repeat Yourself):** Referencias vs. copia de contenido; documentación única y linkeada
- **Contexto bajo demanda:** Skills cargados solo cuando se necesitan (por keywords)
- **Verificabilidad:** Cada skill tiene evals y referencias validadas

## Audiencia

- **Contribuidores internos:** Equipos que crean skills y prompts
- **Usuarios finales:** Agentes de IA que consumen skills
- **Organizaciones:** Teams externas que reutilizan skills compartidos
- **Mantenedores:** Líderes técnicos que gobiernan calidad y evolución

## Estado Actual

| Componente | Estado | Cobertura |
|-----------|--------|-----------|
| Skills | Activo | 7 dominios + transversal |
| Prompts | Activo | 7 dominios |
| Agents | Activo | Definiciones base |
| CLIs | Activo | Transversal |
| Documentación | En construcción | 0% → objetivo 100% |
