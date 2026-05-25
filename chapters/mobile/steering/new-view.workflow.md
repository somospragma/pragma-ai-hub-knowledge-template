---
name: new-view
description: >
  Workflow determinista para crear una vista o pantalla Flutter desde Figma,
  con componentes DS y capa de presentación de app. No usar para crear un
  componente DS aislado.
trigger: "@ds-orchestrator /new-view"
metadata:
  author: Pragma Mobile Chapter
  version: "1.3"
---

# Workflow: Nueva Vista/Pantalla desde Figma

## Prerrequisitos

- URL de Figma con `node-id`.
- HU con criterios de aceptación (texto inline o referencia a archivo Markdown).
- `.copilot/config/project.config.yaml` disponible.
- Si falta configuración confiable de rutas/topología, ejecutar primero
  `@ds-orchestrator /bootstrap-workspace`.
- Contexto resuelto por orquestador:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`
  - `GENERATION_SCOPE`
  - `CONTRACTS_POLICY`
  - `ARCHITECTURE_CONTRACT_PATH`
  - `PIPELINE_SPEC_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.spec_file}`
  - `PIPELINE_LOG_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.log_file}`

## Gates obligatorios

### Gate 0 — Topología

1. Validar `TOPOLOGY_REPO_MODE`.
2. Validar roots (`PROJECT_ROOT`, `TARGET_ROOT`).
3. En `monorepo_melos`, validar `melos.yaml`, scope y package target.

### Gate 0.5 — Ownership del Repo App

1. `project.config.yaml` debe ser el canónico del repo app:
   `{PROJECT_ROOT}/.copilot/config/project.config.yaml`.
2. `PROJECT_ROOT` no puede ser una librería DS/shared/core.
3. Señales mínimas de app:
   - `single_repo | multi_repo`: existe `lib/main.dart` o `lib/main_*.dart`
     o carpeta `android/` o `ios/`.
   - `monorepo_melos`: existe `melos.yaml`, package target válido y package
     objetivo no clasifica como DS/shared/core.
4. Si falla, bloquear con:
   - `CONFIG_PROJECT_CONFIG_OUTSIDE_APP_REPO`
   - `CONFIG_PROJECT_ROOT_POINTS_TO_LIBRARY`
   - `CONFIG_APP_EXECUTABLE_SIGNAL_MISSING`

### Gate 1 — Arquitectura

1. Si `architecture.require_contract_for_new_view=true`, exigir
   `ARCHITECTURE_CONTRACT_PATH`.
2. `ARCHITECTURE.md` es opcional como soporte visual.

### Gate 2 — Política de contratos

1. `optional`: continuar.
2. `generate`: generar contratos mínimos en `§4.C` antes de Fase 3b.
3. `required`: bloquear si faltan contratos domain/data referenciados.

Si falla un gate, terminar con `blocked_input`.

## Inputs del Usuario

```text
@ds-orchestrator /new-view
URL Figma: https://www.figma.com/file/xxx/Screen?node-id=456
HU: [Referencia a la HU o texto de criterios de aceptación]
HU_PATH: [Opcional, ruta Markdown; ej: docs/hus/HU-123.md]
```

## Secuencia Canónica

### FASE 1 — Análisis de Pantalla

**Agente**: `@figma-analyzer`
**Prompt**: `figma-analysis.prompt.md`

Output obligatorio:
- `§1` en `PIPELINE_SPEC_PATH` (incluye `§1.1b` textos literales,
  `§1.1c` constraints/overflow, `§1.4b`, `§1.3b` y `§1.3c` si existen
  anotaciones Development/vectores).
- Registro de fase en `PIPELINE_LOG_PATH`.

---

### FASE 2 — Inventario + DAG Extendido

**Agente**: `@component-planner`
**Prompt**: `atomic-inventory.prompt.md`

Output obligatorio:
- `§2` y `§3` en `PIPELINE_SPEC_PATH`.
- Separación explícita DS vs App.

---

### FASE 2.5 — Arquitectura Técnica

**Agente**: `@component-architect`

Output obligatorio:
- `§4` en `PIPELINE_SPEC_PATH` con arquitectura de vista y `§4.B` de textos
  literales/overflow.

---

### FASE 2.6 — Contratos Mínimos (solo `CONTRACTS_POLICY=generate`)

**Agente**: `@component-architect`

Output obligatorio:
- `§4.C` en `PIPELINE_SPEC_PATH` con contratos mínimos domain/data para
  consumo de presentación (sin implementación).

---

### CHECKPOINT HUMANO (si aplica)

Condición: `pipeline.human_checkpoint: true`.

El orquestador presenta `§1`, `§2-§3`, `§4` y espera aprobación explícita.

---

### FASE 3a — Codegen de Componentes DS

**Agente**: `@widget-developer`

Orden obligatorio: átomos → moléculas → organismos.

---

### FASE 3a.5 — Auditoría de Componentes DS

**Agente**: `@code-auditor`

Loop con `@widget-developer` hasta `pipeline.max_audit_retries`.

---

### FASE 3b — Codegen de Vista App

**Agente**: `@widget-developer`
**Prompt**: `codegen-view.prompt.md`

Output:
- Vista en `structure.views_path`.
- Widgets privados en `structure.view_widgets_path`.

---

### FASE 4a — Tests de Componentes DS

**Agente**: `@test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_WIDGET_TESTS`)

---

### FASE 4b — Golden de Componentes DS

**Agente**: `@golden-test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_GOLDEN_TESTS`)

---

### FASE 4c — Widgetbook de Componentes DS

**Agente**: `@widgetbook-developer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_WIDGETBOOK`)

---

### FASE 4d — Tests de Vista

**Agente**: `@test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=VIEW_WIDGET_TESTS`)

Cobertura mínima:
1. `loading`
2. `empty`
3. `error`
4. `populated`
5. navegación crítica
6. textos literales y mitigación de overflow cuando aplique

---

### FASE 4e — Golden Tests de Vista Completa

**Agente**: `@golden-test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=VIEW_GOLDEN_TESTS`)

Cobertura mínima:
1. `loading`
2. `empty`
3. `error`
4. `populated`
5. `light/dark`
6. viewport compacto si existe riesgo de overflow

---

### FASE 4f — Widgetbook de Pantalla App

**Agente**: `@widgetbook-developer`
**Prompt**: `test-generation.prompt.md` (`MODE=APP_WIDGETBOOK_SCREENS`, `WIDGETBOOK_SCOPE=APP_SCREENS`)

Cobertura mínima:
1. `Default`
2. `Loading`
3. `Empty` (si aplica)
4. `Error` (si aplica)
5. `Populated`

---

### FASE 5 — Entrega

**Agente**: `@delivery-manager`
**Prompt**: `delivery-review.prompt.md`

Debe:
1. validar estructura DS/App en `TARGET_ROOT`
2. actualizar barrel DS solo para componentes DS
3. usar branch prefix:
   - `naming.view_branch_prefix` si existe
   - fallback `naming.branch_prefix`
4. generar `§7` en `PIPELINE_SPEC_PATH`
