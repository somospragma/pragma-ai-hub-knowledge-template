---
name: bootstrap-workspace
description: >
  Workflow de arranque para descubrir topología/rutas del workspace y preparar
  `project.config.yaml` + `ARCHITECTURE-CONTRACT.yaml` +
  `DEPENDENCIES-CONTRACT.yaml` antes de ejecutar `/new-view` o
  `/new-component`.
trigger: "@ds-orchestrator /bootstrap-workspace"
metadata:
  author: Pragma Mobile Chapter
  version: "1.2"
---

# Workflow: Bootstrap de Workspace

## Cuándo usarlo

Usar este workflow cuando:

1. la app, el DS y/o el core viven en rutas físicas distintas
2. existe monorepo Melos o multi-repo y aún no hay configuración confiable
3. el usuario quiere evitar ambigüedad antes de crear una vista/componente

## Prerrequisitos

- `WORKSPACE_ROOT` accesible.
- Opcional: archivo `*.code-workspace` del VSCode workspace.
- Opcional: hints de nombres esperados (app, DS, core).
- Recomendado en workspaces multi-repo: `EXPECTED_APP_REPO_ROOT` para fijar
  explícitamente el repo app donde debe crearse `.copilot/config`.

## Inputs de usuario (ejemplo)

```text
@ds-orchestrator /bootstrap-workspace
WORKSPACE_ROOT: /Users/usuario/dev/mobile-workspace
WORKSPACE_FILE: /Users/usuario/dev/mobile-workspace/mobile.code-workspace
EXPECTED_APP_REPO_ROOT: /Users/usuario/dev/mobile-workspace/my-app-monorepo
EXPECTED_APP_PACKAGE: my_app
EXPECTED_DS_PACKAGE: design_system
APPLY_MODE: propose_only
```

## Secuencia canónica

### FASE B1 — Discovery + Propuesta

**Agente**: `@workspace-discovery`
**Prompt**: `workspace-discovery.prompt.md`

Output obligatorio en `<APP_REPO_ROOT>/.copilot/config/bootstrap`:

1. `workspace_discovery_report.md`
2. `proposed_project.config.yaml`
3. `proposed_architecture-contract.yaml`
4. `proposed_dependencies-contract.yaml`
5. `bootstrap_pipeline_log.md`

---

### CHECKPOINT HUMANO (obligatorio)

El orquestador presenta:

1. topología propuesta
2. rutas app/ds/core propuestas
3. diferencias clave contra configuración actual (si existe)
4. confirmación explícita de que `APP_REPO_ROOT` no es DS/shared/core

Pregunta exacta:

"He generado la propuesta de configuración del workspace. ¿Apruebas aplicar los cambios con backup?"

Sin aprobación explícita, finalizar en `propose_only`.
En este modo, no se deben escribir archivos finales fuera de
`<APP_REPO_ROOT>/.copilot/config/bootstrap`.

---

### FASE B2 — Apply con backup (si aprobado)

**Agente**: `@workspace-discovery`
**Prompt**: `workspace-discovery.prompt.md` con `APPLY_MODE=apply_with_backup`

Output obligatorio:

1. `<APP_REPO_ROOT>/.copilot/config/project.config.yaml`
2. `<APP_REPO_ROOT>/.copilot/config/ARCHITECTURE-CONTRACT.yaml`
3. `<APP_REPO_ROOT>/.copilot/config/DEPENDENCIES-CONTRACT.yaml`
4. backups `.bak` en los 3 archivos (si existían)

---

### FASE B3 — Validación post-bootstrap

**Agente**: `@workspace-discovery`

Validaciones:

1. `project.repository_local_path` existe
2. en modo melos: `melos.yaml` + `target_scope`
3. DS/core en `source=path` existen
4. existe `<APP_REPO_ROOT>/.copilot/config/ARCHITECTURE-CONTRACT.yaml` final
5. existe `<APP_REPO_ROOT>/.copilot/config/DEPENDENCIES-CONTRACT.yaml` final
6. se puede crear `<APP_REPO_ROOT>/.copilot/flow_result`

Si falla, terminar con `blocked_input` y código explícito.

## Resultado esperado

Si B1-B3 son exitosas:

1. el proyecto queda listo para `/new-view` o `/new-component`
2. la configuración deja de depender del `cwd`
3. el pipeline principal opera con rutas deterministas

## Reglas

- No sobreescribir archivos sin backup.
- No inferir rutas de baja confianza sin aprobación humana.
- Si el root resuelto apunta a una librería DS/shared/core, bloquear con código
  explícito y no aplicar.
- No ejecutar `/new-view` ni `/new-component` si bootstrap quedó en `blocked_input`.
