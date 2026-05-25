---
name: refactor-component
description: >
  Workflow determinista para refactorizar un componente DS existente. Usar
  cuando el usuario pide cambios sobre implementación ya materializada.
trigger: "@ds-orchestrator /refactor-component [path]"
metadata:
  author: Pragma Mobile Chapter
  version: "1.2"
---

# Workflow: Refactorizar Componente

## Prerrequisitos

- Path del componente a refactorizar.
- Descripción del refactor (qué cambiar y por qué).
- `.copilot/config/project.config.yaml` válido.
- Contexto resuelto por orquestador:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`
  - `PIPELINE_SPEC_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.spec_file}`
  - `PIPELINE_LOG_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.log_file}`

## Gate de Topología

1. Validar `TOPOLOGY_REPO_MODE`.
2. Validar `PROJECT_ROOT` y `TARGET_ROOT`.
3. En `monorepo_melos`, validar `melos.yaml`, scope y package target.

Si falla, terminar con `blocked_input`.

## Inputs del Usuario

```text
@ds-orchestrator /refactor-component lib/src/organisms/cards/product_card.dart
Descripción: Extraer el header en una molécula separada y agregar soporte para variante "compact".
```

## Secuencia de Ejecución

### FASE 1 — Análisis del Componente Actual

**Agente**: `@component-planner`

Output obligatorio: `§2` y `§3` en `PIPELINE_SPEC_PATH`.

---

### FASE 2 — Plan Técnico de Refactor

**Agente**: `@component-architect`

Output obligatorio: `§4` en `PIPELINE_SPEC_PATH`.

---

### CHECKPOINT HUMANO (si habilitado)

Presentar:
1. análisis de impacto
2. plan de cambios
3. breaking changes (si los hay)

---

### FASE 3 — Aplicar Cambios

**Agente**: `@widget-developer`

Reglas:
- Mantener compatibilidad hacia atrás cuando sea viable.
- Si hay APIs en transición, usar `@Deprecated`.
- Restringir cambios al scope de `TARGET_ROOT`.

---

### FASE 3.5 — Auditoría

**Agente**: `@code-auditor`

Output obligatorio: `§5` en `PIPELINE_SPEC_PATH`.

---

### FASE 4a — Actualizar Widget Tests

**Agente**: `@test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_WIDGET_TESTS`)

---

### FASE 4b — Actualizar Golden Tests (si impacto visual)

**Agente**: `@golden-test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_GOLDEN_TESTS`)

---

### FASE 5 — Entrega

**Agente**: `@delivery-manager`

Output obligatorio: `§7` en `PIPELINE_SPEC_PATH`.

## Verificación (topology-aware)

- `single_repo` o `multi_repo`:
  - `flutter analyze`
  - `flutter test`
  - `flutter test --tags golden`
- `monorepo_melos`:
  - `melos exec --scope={monorepo.target_scope} -- flutter analyze`
  - `melos exec --scope={monorepo.target_scope} -- flutter test`
  - `melos exec --scope={monorepo.target_scope} -- flutter test --tags golden`
