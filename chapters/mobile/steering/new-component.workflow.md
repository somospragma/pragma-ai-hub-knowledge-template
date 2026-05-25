---
name: new-component
description: >
  Workflow determinista para crear un nuevo componente del Design System desde
  Figma. Usar cuando el usuario pide un componente nuevo con URL de Figma y HU.
  No usar para crear pantalla completa o refactor sin diseño nuevo.
trigger: "@ds-orchestrator /new-component"
metadata:
  author: Pragma Mobile Chapter
  version: "1.2"
---

# Workflow: Nuevo Componente desde Figma

## Prerrequisitos

- URL del componente en Figma con `node-id`.
- Historia de Usuario (HU) con criterios de aceptación (texto inline o
  referencia a archivo Markdown).
- `.copilot/config/project.config.yaml` válido.
- Si falta configuración confiable de rutas/topología, ejecutar primero
  `@ds-orchestrator /bootstrap-workspace`.
- Contexto resuelto por orquestador:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`
  - `PIPELINE_SPEC_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.spec_file}`
  - `PIPELINE_LOG_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.log_file}`

## Gate de Topología (obligatorio)

1. `TOPOLOGY_REPO_MODE` válido (`single_repo | monorepo_melos | multi_repo`).
2. `PROJECT_ROOT` y `TARGET_ROOT` accesibles.
3. Si `monorepo_melos`: `melos_enabled=true`, `melos_root/melos.yaml`,
   `target_scope` y `target_package_path` existentes.

Si falla cualquier validación, terminar con `blocked_input`.

## Gate de Ownership del Repo App (obligatorio)

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

## Inputs del Usuario

```text
@ds-orchestrator /new-component
URL Figma: https://www.figma.com/file/xxx/Component?node-id=123
HU: [Referencia a la HU o texto de criterios de aceptación]
HU_PATH: [Opcional, ruta Markdown; ej: docs/hus/HU-123.md]
```

## Secuencia de Ejecución

### FASE 1 — Análisis de Diseño

**Agente**: `@figma-analyzer`
**Prompt**: `figma-analysis.prompt.md`

Output obligatorio: `§1` en `PIPELINE_SPEC_PATH` (incluye `§1.1b` textos
literales, `§1.1c` constraints/overflow, `§1.3b` y `§1.3c` si existen
anotaciones Development/vectores).

---

### FASE 2 — Spec + Inventario + DAG

**Agente**: `@component-planner`
**Prompt**: `atomic-inventory.prompt.md`

Output obligatorio: `§2` y `§3` en `PIPELINE_SPEC_PATH`.

---

### FASE 2.5 — Arquitectura Técnica

**Agente**: `@component-architect`

Output obligatorio: `§4` en `PIPELINE_SPEC_PATH` con `§4.B` de textos
literales/overflow.

---

### CHECKPOINT HUMANO

Condición: `pipeline.human_checkpoint: true`.

Presentar al desarrollador:
1. `§1` análisis.
2. `§2-§3` inventario + DAG.
3. `§4` plan técnico.

Esperar aprobación explícita para continuar.

---

### FASE 3 — Generación de Código DS

**Agente**: `@widget-developer`
**Prompts**: `codegen-atom.prompt.md`, `codegen-molecule.prompt.md`, `codegen-organism.prompt.md`

Orden obligatorio: átomos → moléculas → organismos.

Output: archivos `.dart` en el scope de `TARGET_ROOT`.

---

### FASE 3.5 — Auditoría de Calidad

**Agente**: `@code-auditor`

Loop con `@widget-developer` hasta `pipeline.max_audit_retries`.

Output obligatorio: `§5` en `PIPELINE_SPEC_PATH`.

---

### FASE 4a — Widget Tests DS

**Agente**: `@test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_WIDGET_TESTS`)

---

### FASE 4b — Golden Tests DS

**Agente**: `@golden-test-engineer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_GOLDEN_TESTS`)

---

### FASE 4c — Widgetbook DS

**Agente**: `@widgetbook-developer`
**Prompt**: `test-generation.prompt.md` (`MODE=DS_WIDGETBOOK`)

---

### FASE 5 — Entrega

**Agente**: `@delivery-manager`
**Prompt**: `delivery-review.prompt.md`

Output obligatorio: `§7` en `PIPELINE_SPEC_PATH`.

## Reglas

- No generar artefactos fuera de `TARGET_ROOT`.
- No saltar fases obligatorias.
- Registrar cada fase en `PIPELINE_LOG_PATH`.
- Si una fase no aplica, usar `skipped` con razón explícita.
