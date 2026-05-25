---
name: fix-pr-comments
description: >
  Workflow determinista para corregir comentarios de Pull Request de forma
  trazable. Usar cuando ya existe feedback concreto.
trigger: "@ds-orchestrator /fix-pr-comments [PR-URL]"
metadata:
  author: Pragma Mobile Chapter
  version: "1.2"
---

# Workflow: Corregir Comentarios de PR

## Prerrequisitos

- URL del PR.
- Comentarios accesibles por conversación, archivo exportado o integración.
- `.copilot/config/project.config.yaml` válido.
- Contexto resuelto por orquestador:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`
  - `PIPELINE_SPEC_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.spec_file}`
  - `PIPELINE_LOG_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.log_file}`

Si no hay comentarios accesibles, terminar con `blocked_input`.

## Gate de Topología

1. Validar `TOPOLOGY_REPO_MODE`.
2. Validar roots (`PROJECT_ROOT`, `TARGET_ROOT`).
3. En `monorepo_melos`, validar `melos.yaml`, scope y package target.

## Secuencia Canónica

### FASE 1 — Analizar comentarios y armar plan

**Agente**: `@component-planner`

Pasos:
1. Clasificar comentarios por tipo: `[VISUAL]`, `[LÓGICA]`, `[DOCS]`, `[TESTS]`, `[STYLE]`.
2. Mapear comentario → archivo/área afectada.
3. Crear plan priorizado.

Output obligatorio: plan en `PIPELINE_SPEC_PATH`.

---

### FASE 2 — Aplicar correcciones de código

**Agente**: `@widget-developer`

Cobertura de categorías:
- `[VISUAL]`, `[LÓGICA]`, `[STYLE]` → Fase 2
- `[TESTS]` → Fase 4a/4b
- `[DOCS]` → Fase 5

---

### FASE 3 — Auditoría de cobertura de comentarios

**Agente**: `@code-auditor`

- Verificar matriz comentario→corrección.
- Si falta cobertura, loop con `@widget-developer`.
- Escribir reporte en `§5`.

---

### FASE 4a — Actualizar Widget Tests (si impacto funcional)

**Agente**: `@test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_WIDGET_TESTS`)

---

### FASE 4b — Actualizar Golden Tests (si impacto visual)

**Agente**: `@golden-test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_GOLDEN_TESTS`)

---

### FASE 5 — Entrega

**Agente**: `@delivery-manager`

- Aplicar correcciones `[DOCS]` del plan.
- Commits por tipo de corrección.
- Resumen de cobertura de comentarios.
- Verificación final topology-aware.

Output obligatorio: `§7` en `PIPELINE_SPEC_PATH` + bitácora.
