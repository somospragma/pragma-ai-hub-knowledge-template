---
name: master-orchestration
description: >
  Prompt maestro para ejecutar el pipeline completo Figma → Flutter DS de forma
  determinista. Usar cuando la entrada del usuario sea una tarea end-to-end
  como `/bootstrap-workspace`, `/new-component`, `/new-view`,
  `/refactor-component` o `/fix-pr-comments` con `@ds-orchestrator`.
agent: ds-orchestrator
---

# Pipeline Maestro (Determinista)

## Objetivo

Ejecutar el pipeline en orden estricto, con gates obligatorios por topología,
arquitectura y contratos, usando una única ruta de artefactos por ejecución.

## Pre-ejecución obligatoria

1. Si workflow=`/bootstrap-workspace`:
   - no exigir `project.config.yaml`.
   - delegar a `@workspace-discovery` con `workspace-discovery.prompt.md`.
   - exigir checkpoint humano para aplicar cambios.
   - al finalizar, recomendar `/new-view` o `/new-component`.
2. Para cualquier otro workflow, leer `PROJECT_CONFIG_BOOT_PATH=.copilot/config/project.config.yaml`.
   - Si falta: `blocked_input` con `CONFIG_PROJECT_CONFIG_MISSING`.
3. Para workflows distintos de `/bootstrap-workspace`, usar
   `PROJECT_CONFIG_BOOT_PATH` solo para obtener `PROJECT_ROOT` y luego fijar
   `PROJECT_CONFIG_PATH={PROJECT_ROOT}/.copilot/config/project.config.yaml`
   como ruta canónica de configuración.
   - Si `PROJECT_CONFIG_PATH` canónica no existe: `blocked_input` con
     `CONFIG_PROJECT_CONFIG_OUTSIDE_APP_REPO`.
4. Para workflows distintos de `/bootstrap-workspace`, resolver constantes:
   - `PROJECT_ROOT = project.repository_local_path` (fallback `"."`)
   - `TOPOLOGY_REPO_MODE = topology.repo_mode` (fallback `single_repo`)
   - `TOPOLOGY_FEATURE_LOCATION_MODE = topology.feature_location_mode` (fallback `lib_only`)
   - `TOPOLOGY_SHARED_CORE_MODE = topology.shared_core_mode` (fallback `none`)
   - `TOPOLOGY_DS_MODE = topology.ds_mode` (fallback `external_ds_package`)
   - `TARGET_PACKAGE_NAME = targets.target_package_name` (fallback `project.package_name`)
   - `TARGET_PACKAGE_PATH = targets.target_package_path` (fallback `"."`)
   - `TARGET_FEATURE_ROOT = targets.feature_root` (fallback `lib/src/features`)
   - `TARGET_ROOT`:
     - `single_repo` -> `{PROJECT_ROOT}`
     - `monorepo_melos` -> `{PROJECT_ROOT}/{TARGET_PACKAGE_PATH}`
     - `multi_repo` -> `{PROJECT_ROOT}`
   - `PIPELINE_ROOT = {TARGET_ROOT}/{pipeline.output_dir}`
   - `PIPELINE_LOG_PATH = {PIPELINE_ROOT}/{pipeline.log_file}`
   - `PIPELINE_SPEC_PATH = {PIPELINE_ROOT}/{pipeline.spec_file}`
   - `WIDGETBOOK_COMPONENTS_ROOT = structure.widgetbook_components_path` (fallback `structure.widgetbook_path`)
   - `WIDGETBOOK_SCREENS_ROOT = structure.widgetbook_screens_path` (fallback `structure.widgetbook_path`)
   - `ARCHITECTURE_MERMAID_PATH = {PROJECT_ROOT}/{architecture.mermaid_doc_path}`
   - `ARCHITECTURE_CONTRACT_PATH = {PROJECT_ROOT}/{architecture.contract_path}`
   - `DEPENDENCIES_CONTRACT_PATH = {PROJECT_ROOT}/{dependencies.contract_path}` (fallback `.copilot/config/DEPENDENCIES-CONTRACT.yaml`)
   - `REQUIRE_ARCHITECTURE_CONTRACT_FOR_NEW_VIEW = architecture.require_contract_for_new_view`
   - `MELOS_ENABLED = monorepo.melos_enabled`
   - `MELOS_ROOT = {PROJECT_ROOT}/{monorepo.melos_root}`
   - `MELOS_TARGET_SCOPE = monorepo.target_scope`
   - `GENERATION_SCOPE = pipeline.generation_scope` (fallback `presentation_only`)
   - `CONTRACTS_POLICY = pipeline.contracts_policy` (fallback `optional`)
   - `DETERMINISTIC_MODE = pipeline.deterministic_mode`
   - `ENFORCE_PHASE_CONTRACTS = pipeline.enforce_phase_contracts`
   - `STOP_ON_MISSING_ARTIFACTS = pipeline.stop_on_missing_artifacts`
5. Para workflows distintos de `/bootstrap-workspace`, crear `PIPELINE_LOG_PATH` y `PIPELINE_SPEC_PATH` si no existen.
6. Para workflows distintos de `/bootstrap-workspace`, aplicar Gate 0 - Topology Gate:
   - Validar `TOPOLOGY_REPO_MODE` en `single_repo | monorepo_melos | multi_repo`.
   - Exigir `PROJECT_ROOT` y `TARGET_ROOT` accesibles.
   - Si `monorepo_melos`: exigir `MELOS_ENABLED=true`, `MELOS_ROOT/melos.yaml`,
     `MELOS_TARGET_SCOPE` y `TARGET_PACKAGE_PATH` válido.
   - Si `TOPOLOGY_SHARED_CORE_MODE=external_core_package`: exigir
     `external_dependencies.shared_core.enabled=true`.
7. Para workflows distintos de `/bootstrap-workspace`, aplicar Gate 0.5 - App Repo Ownership Gate:
   - Exigir `PROJECT_CONFIG_BOOT_PATH` existente.
   - Exigir `PROJECT_CONFIG_PATH` canónica en `{PROJECT_ROOT}/.copilot/config/project.config.yaml`.
   - En `single_repo | multi_repo`: exigir señal de app ejecutable en `PROJECT_ROOT`
     (`lib/main.dart` o `lib/main_*.dart` o `android/` o `ios/`).
   - En `monorepo_melos`: exigir `melos.yaml`, package target válido y vetar package
     objetivo DS/core/shared.
   - Si `PROJECT_ROOT` o `TARGET_PACKAGE_NAME` parecen librería (`design_system`,
     `ui_kit`, `shared`, `core`, `common`) y no hay señal de app ejecutable, bloquear.
   - Usar códigos: `CONFIG_PROJECT_CONFIG_OUTSIDE_APP_REPO`,
     `CONFIG_PROJECT_ROOT_POINTS_TO_LIBRARY`,
     `CONFIG_APP_EXECUTABLE_SIGNAL_MISSING`.
8. Para `/new-view`, aplicar Gate 1 - Architecture Gate:
   - Si `REQUIRE_ARCHITECTURE_CONTRACT_FOR_NEW_VIEW=true`, exigir
     `ARCHITECTURE_CONTRACT_PATH`.
   - Tratar `ARCHITECTURE_MERMAID_PATH` como referencia opcional.
9. Para `/new-view`, aplicar Gate 2 - Contracts Policy Gate:
   - `CONTRACTS_POLICY=optional`: continuar sin bloquear.
   - `CONTRACTS_POLICY=generate`: crear/actualizar contratos mínimos en spec
     antes de `Fase 3b`.
   - `CONTRACTS_POLICY=required`: exigir referencias de contratos domain/data
     existentes antes de `Fase 3b`.
10. Si falla un gate, detener con `blocked_input` y razón explícita.
11. Determinar workflow:
   - `/bootstrap-workspace`
   - `/new-component`
   - `/new-view`
   - `/refactor-component`
   - `/fix-pr-comments`

## Códigos de bloqueo estándar

- `BOOTSTRAP_WORKSPACE_ROOT_MISSING`
- `BOOTSTRAP_SCAN_ROOTS_EMPTY`
- `BOOTSTRAP_APP_REPO_NOT_RESOLVED`
- `BOOTSTRAP_APP_REPO_AMBIGUOUS`
- `BOOTSTRAP_APP_REPO_MISMATCH_HINT`
- `BOOTSTRAP_APP_REPO_POINTS_TO_LIBRARY`
- `BOOTSTRAP_APP_PACKAGE_NOT_FOUND`
- `BOOTSTRAP_TOPOLOGY_AMBIGUOUS`
- `BOOTSTRAP_MELOS_INVALID`
- `BOOTSTRAP_PROPOSAL_ROOT_UNWRITABLE`
- `BOOTSTRAP_ARCH_CONTRACT_PROPOSAL_INVALID`
- `BOOTSTRAP_PATH_DEPENDENCY_MISSING`
- `BOOTSTRAP_APPLY_NOT_APPROVED`
- `CONFIG_PROJECT_CONFIG_MISSING`
- `CONFIG_PROJECT_ROOT_MISSING`
- `CONFIG_TOPOLOGY_INVALID`
- `CONFIG_MELOS_ROOT_MISSING`
- `CONFIG_TARGET_PACKAGE_MISSING`
- `CONFIG_EXTERNAL_CORE_REQUIRED_MISSING`
- `CONFIG_ARCH_CONTRACT_MISSING`
- `CONFIG_CONTRACTS_POLICY_UNSATISFIED`
- `CONFIG_PROJECT_CONFIG_OUTSIDE_APP_REPO`
- `CONFIG_PROJECT_ROOT_POINTS_TO_LIBRARY`
- `CONFIG_APP_EXECUTABLE_SIGNAL_MISSING`

## Contrato de orquestación

- No avanzar de fase sin validar output obligatorio de la fase previa.
- Si una fase devuelve `blocked_input`, detener pipeline inmediatamente.
- Registrar cada fase en `PIPELINE_LOG_PATH`.
- Actualizar `pipeline_state` en `PIPELINE_SPEC_PATH` tras cada fase.
- Si una fase es condicional (`si aplica`), registrar `skipped` con razón.
- Mantener handoffs silenciosos y completos.

## Flujo por workflow

### A) `/bootstrap-workspace`

1. Fase B1 → `@workspace-discovery` (`workspace-discovery.prompt.md`) con `APPLY_MODE=propose_only`.
   - generar propuestas en `<APP_REPO_ROOT>/.copilot/config/bootstrap` para:
     `project.config.yaml`, `ARCHITECTURE-CONTRACT.yaml`,
     `DEPENDENCIES-CONTRACT.yaml`.
2. Checkpoint humano obligatorio:
   "He generado la propuesta de configuración del workspace. ¿Apruebas aplicar los cambios con backup?"
3. Si usuario aprueba:
   - Fase B2 → `@workspace-discovery` (`workspace-discovery.prompt.md`) con `APPLY_MODE=apply_with_backup`.
   - Fase B3 → validación post-apply.
4. Si usuario no aprueba:
   - finalizar en modo `propose_only`.

### B) `/new-component`

1. Fase 1 → `@figma-analyzer` (`figma-analysis.prompt.md`) → escribe `§1` (incluye `§1.3b` y `§1.3c` si hay anotaciones Development/vectores).
2. Fase 2 → `@component-planner` (`atomic-inventory.prompt.md`) → escribe `§2` y `§3`.
3. Fase 2.5 → `@component-architect` → escribe `§4`.
4. Checkpoint humano (si `pipeline.human_checkpoint = true`).
5. Fase 3 → `@widget-developer` (`codegen-atom/molecule/organism`) → código DS.
6. Fase 3.5 → `@code-auditor` → escribe `§5` (loop hasta `pipeline.max_audit_retries`).
7. Fase 4a → `@test-engineer` (`MODE=DS_WIDGET_TESTS`).
8. Fase 4b → `@golden-test-engineer` (`MODE=DS_GOLDEN_TESTS`).
9. Fase 4c → `@widgetbook-developer` (`MODE=DS_WIDGETBOOK`).
10. Fase 5 → `@delivery-manager` (`delivery-review.prompt.md`) → escribe `§7`.

### C) `/new-view`

1. Gate de arquitectura y política de contratos.
2. Fase 1 → `@figma-analyzer` (`figma-analysis.prompt.md`) → `§1` + `§1.4b` + `§1.3b` + `§1.3c` (si hay anotaciones Development/vectores).
3. Fase 2 → `@component-planner` (`atomic-inventory.prompt.md`) → `§2` + `§3` (DS vs App).
4. Fase 2.5 → `@component-architect` → `§4` (incluye arquitectura de vista).
5. Fase 2.6 (solo `CONTRACTS_POLICY=generate`) → `@component-architect` agrega contratos mínimos en `§4.C`.
6. Checkpoint humano (si aplica).
7. Fase 3a → `@widget-developer` (`codegen-atom/molecule/organism`) → componentes DS.
8. Fase 3a.5 → `@code-auditor` → audita DS (`§5`).
9. Fase 3b → `@widget-developer` (`codegen-view.prompt.md`) → vista app.
10. Fase 4a → `@test-engineer` (`MODE=DS_WIDGET_TESTS`).
11. Fase 4b → `@golden-test-engineer` (`MODE=DS_GOLDEN_TESTS`).
12. Fase 4c → `@widgetbook-developer` (`MODE=DS_WIDGETBOOK`).
13. Fase 4d → `@test-engineer` (`MODE=VIEW_WIDGET_TESTS`).
14. Fase 4e → `@golden-test-engineer` (`MODE=VIEW_GOLDEN_TESTS`).
15. Fase 4f → `@widgetbook-developer` (`MODE=APP_WIDGETBOOK_SCREENS`, `WIDGETBOOK_SCOPE=APP_SCREENS`).
16. Fase 5 → `@delivery-manager` (`delivery-review.prompt.md`) → `§7`.

### D) `/refactor-component`

1. Fase 1 → `@component-planner` → escribe `§2` y `§3` (impacto + plan).
2. Fase 2 → `@component-architect` → escribe `§4`.
3. Checkpoint humano (si aplica).
4. Fase 3 → `@widget-developer` → aplica refactor.
5. Fase 3.5 → `@code-auditor` → escribe `§5`.
6. Fase 4a → `@test-engineer` (`MODE=DS_WIDGET_TESTS`).
7. Fase 4b → `@golden-test-engineer` (`MODE=DS_GOLDEN_TESTS`) si impacto visual.
8. Fase 5 → `@delivery-manager` → escribe `§7`.

### E) `/fix-pr-comments`

1. Fase 1 → `@component-planner` → requiere comentarios PR; escribe plan en `§2`.
2. Fase 2 → `@widget-developer` → aplica correcciones de código.
3. Fase 3 → `@code-auditor` → cobertura comentario→cambio en `§5`.
4. Fase 4a → `@test-engineer` (`MODE=DS_WIDGET_TESTS`) si impacto funcional.
5. Fase 4b → `@golden-test-engineer` (`MODE=DS_GOLDEN_TESTS`) si impacto visual.
6. Fase 5 → `@delivery-manager` → `§7`.

## Checkpoint humano

Cuando aplique en workflows funcionales (`/new-component`, `/new-view`, `/refactor-component`), presentar:

1. `§1` análisis.
2. `§2`/`§3` inventario + DAG.
3. `§4` plan técnico.

Pregunta exacta:

"He completado análisis, inventario y plan técnico. ¿Apruebas continuar a implementación?"

No continuar hasta recibir aprobación explícita.

Para `/bootstrap-workspace`, usar solo la pregunta de apply de bootstrap y no
pedir aprobación sobre `§1..§4`.

## Handoff estándar (obligatorio)

Cada delegación incluye:

- `workflow`
- `phase_id` y `phase_name`
- `mode` (si el prompt de fase es multi-modo)
- `scope` (si el agente de fase lo requiere)
- `project_root`
- `topology` (`repo_mode`, `feature_location_mode`, `shared_core_mode`, `ds_mode`)
- `target` (`package_name`, `package_path`, `target_root`, `feature_root`)
- `execution_context` (`melos_enabled`, `melos_root`, `target_scope`)
- `contracts_context` (`generation_scope`, `contracts_policy`)
- `architecture_refs` (`ARCHITECTURE_CONTRACT_PATH`, `ARCHITECTURE_MERMAID_PATH` opcional)
- `workspace_context` (`workspace_root`, `workspace_file`, `apply_mode`, `expected_app_repo_root`, `expected_app_repo_name`, `expected_app_package`, `expected_ds_package`, `expected_core_package`, `expected_repo_mode`) para `/bootstrap-workspace`
- `input_refs`
- `expected_output`
- `output_paths` (`PIPELINE_SPEC_PATH`, `PIPELINE_LOG_PATH`)

Si falta alguno obligatorio para el workflow actual, no delegar.

## Reglas

- No programar ni auditar directamente; siempre delegar.
- Incluir `project_root` y `target_root` en todos los handoffs.
- En `/new-view`, incluir siempre `architecture_refs`.
- Si hay error o bloqueo, registrar en bitácora y detener.
