---
name: workspace-discovery
description: >
  Prompt para descubrir topología/rutas del workspace y proponer configuración
  inicial determinista antes del pipeline funcional (`/new-view`,
  `/new-component`).
agent: workspace-discovery
---

# Bootstrap de Workspace (Determinista)

## Objetivo

Resolver de forma reproducible:

1. dónde está el repo objetivo de app (`PROJECT_ROOT`)
2. dónde viven DS/core externos (si existen localmente)
3. qué topología aplica (`single_repo | monorepo_melos | multi_repo`)
4. cómo deben quedar `project.config.yaml`, `ARCHITECTURE-CONTRACT.yaml` y
   `DEPENDENCIES-CONTRACT.yaml`

## Inputs obligatorios

- `WORKSPACE_ROOT`
- `APPLY_MODE` (`propose_only` | `apply_with_backup`)

## Inputs opcionales

- `WORKSPACE_FILE` (`*.code-workspace`)
- hints:
  - `EXPECTED_APP_REPO_ROOT` (ruta absoluta del repo app)
  - `EXPECTED_APP_REPO_NAME` (nombre de carpeta del repo app)
  - `EXPECTED_APP_PACKAGE`
  - `EXPECTED_DS_PACKAGE`
  - `EXPECTED_CORE_PACKAGE`
  - `EXPECTED_REPO_MODE`

## Salidas obligatorias

En `BOOTSTRAP_ROOT={APP_REPO_ROOT}/.copilot/config/bootstrap`:

1. `workspace_discovery_report.md`
2. `proposed_project.config.yaml`
3. `proposed_architecture-contract.yaml`
4. `proposed_dependencies-contract.yaml`
5. `bootstrap_pipeline_log.md`

Si `APPLY_MODE=apply_with_backup` y existe aprobación del usuario:

1. `<APP_REPO_ROOT>/.copilot/config/project.config.yaml`
2. `<APP_REPO_ROOT>/.copilot/config/ARCHITECTURE-CONTRACT.yaml`
3. `<APP_REPO_ROOT>/.copilot/config/DEPENDENCIES-CONTRACT.yaml`
4. backups `.bak` de los 3 archivos (si existían)

## Secuencia obligatoria

### Fase B1 — Resolver roots a escanear

1. Iniciar con `WORKSPACE_ROOT`.
2. Si existe `WORKSPACE_FILE`, incluir `folders[].path`.
3. Normalizar rutas absolutas y eliminar duplicados.

Si no hay roots, bloquear con `BOOTSTRAP_SCAN_ROOTS_EMPTY`.

### Fase B2 — Descubrir candidatos

Buscar por root:

1. `pubspec.yaml`
2. `melos.yaml`
3. señales de app ejecutable (`lib/main.dart`, `lib/main_*.dart`, `android/`, `ios/`)
4. señales app canónicas (`lib/src/presentation`, `lib/src/features`)
5. señales app legacy (`lib/presentation`, `lib/features`) solo para alertar
   compatibilidad/migración
6. señales DS canónicas (`lib/src/atoms`, `lib/src/molecules`,
   `lib/src/organisms`)
7. señales DS legacy (`lib/atoms`, `lib/molecules`, `lib/organisms`) solo para
   alertar compatibilidad/migración
8. señales shared/core (`core|shared|common` en nombre/path)

Clasificar `APP_CANDIDATE`, `DS_CANDIDATE`, `CORE_CANDIDATE`, `MONOREPO_ROOT_CANDIDATE`.

### Fase B3 — Inferir topología

Reglas:

1. `monorepo_melos`: hay `melos.yaml` y packages Flutter múltiples.
2. `single_repo`: app aislada sin melos.
3. `multi_repo`: app/features en repos separados, fuera de melos.

Resolver:

- `APP_REPO_ROOT`
- `topology.repo_mode`
- `topology.feature_location_mode`
- `topology.shared_core_mode`
- `targets.target_package_name`
- `targets.target_package_path`
- `monorepo.*` (cuando aplique)

Regla de selección de root:

- `APP_REPO_ROOT` debe ser el repositorio de la app objetivo.
- No escribir configuración final en repos de dependencias (DS/core) ni en el
  root global del workspace.
- Si llega `EXPECTED_APP_REPO_ROOT`, usarlo como pin estricto y validar que sea
  app ejecutable; si no cumple, bloquear.
- En `monorepo_melos`, `APP_REPO_ROOT` debe ser el repo del `melos.yaml` del
  app monorepo.
- Si hay empate o ambigüedad entre candidatos de app, bloquear y no aplicar.

Orden de decisión obligatorio:

1. `EXPECTED_APP_REPO_ROOT` válido -> gana.
2. melos app repo válido -> gana.
3. mejor candidato con señales de app ejecutable y sin señales DS/core.
4. en conflicto -> `BOOTSTRAP_APP_REPO_AMBIGUOUS`.

### Fase B4 — Construir propuesta de configs

Reglas:

1. `project.repository_local_path` debe ser absoluto y apuntar al app repo.
2. `targets.target_package_path` debe quedar relativo a `APP_REPO_ROOT`.
3. DS/core locales:
   - `source=path`
   - `location` absoluto
4. DS/core remotos:
   - `source=git`
   - `location` owner/repo o URL
5. Construir `proposed_architecture-contract.yaml` consistente con la topología
   descubierta y apto para `/new-view`.
6. Usar `lib/src` para defaults de código productivo:
   - `targets.feature_root: lib/src/features`
   - `structure.*_path` de DS bajo `lib/src`
   - `presentation/domain/data` bajo `lib/src`
7. Si se detecta estructura legacy fuera de `lib/src`, incluir alerta en
   `workspace_discovery_report.md`; no cambiar defaults nuevos a legacy salvo
   que el usuario lo pida explícitamente.

### Fase B5 — Validación

1. `APP_REPO_ROOT` existe.
2. Si melos, existe `melos.yaml` y `target_scope` no vacío.
3. Si `source=path`, ruta existe.
4. `.copilot/config/bootstrap` es escribible en app repo.
5. contrato de arquitectura propuesto parseable.
6. `APP_REPO_ROOT` no apunta a DS/core.
7. existe señal de app ejecutable en `APP_REPO_ROOT` (o en package app target en melos).

Si falla, bloquear con código explícito.

### Fase B6 — Apply controlado

Solo con aprobación explícita del usuario:

1. backup de archivos destino
2. escribir definitivos
3. registrar diff resumido

Sin aprobación, terminar en `propose_only`.

Regla estricta de escritura:

- Con `APPLY_MODE=propose_only`, escribir únicamente en
  `<APP_REPO_ROOT>/.copilot/config/bootstrap`.
- No escribir archivos finales en `.copilot/config/*`.

## Formato mínimo del reporte

`workspace_discovery_report.md` debe incluir:

1. **Resumen de topología propuesta**
2. **Tabla de candidatos y confianza**
3. **Rutas finales propuestas (app/ds/core)**
4. **Decisiones de source (`path|git|hosted`)**
5. **Validaciones ejecutadas**
6. **Resultado (`propose_only` o `apply_with_backup`)**
7. **Siguiente paso recomendado** (`@ds-orchestrator /new-view` o `/new-component`)

## Códigos de bloqueo

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
