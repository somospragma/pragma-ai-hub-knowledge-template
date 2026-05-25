---
name: flutter-ds-widgetbook
description: >
  Widgetbook patterns for interactive documentation of Design System components
  and app screens in canonical `/new-view`. Use when creating or updating
  use cases, knobs, code preview, and build_runner generation with deterministic
  scope selection.
commands:
  - setup-widgetbook
inputs:
  - name: action
    description: Action to perform (implement, add-use-case, audit). "implement" generates the Widgetbook project structure and configuration, "add-use-case" creates use cases for a specific component or screen, "audit" checks existing use cases for missing states, knobs without labelBuilder, or missing code preview.
    required: true
  - name: target
    description: Path to the component or screen to document (e.g. lib/ui_system/atoms/button/ for DS components, lib/features/product/presentation/pages/ for app screens).
    required: true
  - name: scope
    description: Widgetbook scope (ds-components, app-screens). Determines the output location and use case structure.
    required: true
metadata:
  author: pragma-ds
  version: "2.4"
  domain: flutter-design-system
---

# Widgetbook Patterns (Deterministic Scope)

## Scope obligatorio (con fallback canónico)

Antes de generar use cases, definir `WIDGETBOOK_SCOPE`:

- `DS_COMPONENTS` → componentes del Design System
- `APP_SCREENS` → pantallas/vistas de app

Si no llega `WIDGETBOOK_SCOPE`:

- en flujo canónico DS (`MODE=DS_WIDGETBOOK`), usar `DS_COMPONENTS` por defecto.
- en modo pantallas (`MODE=APP_WIDGETBOOK_SCREENS`), usar `APP_SCREENS` por defecto.

## Resolución de rutas (desde config)

Leer `project.config.yaml`:

- `WIDGETBOOK_COMPONENTS_ROOT = structure.widgetbook_components_path`
  (fallback `structure.widgetbook_path`)
- `WIDGETBOOK_SCREENS_ROOT = structure.widgetbook_screens_path`
  (fallback `structure.widgetbook_path`)

En este ecosistema ambos pueden apuntar a la misma ruta base (recomendado por
default), pero deben resolverse explícitamente.

## Tabla de scope

| Scope | Qué documenta | Ubicación esperada |
|---|---|---|
| `DS_COMPONENTS` | Atoms, molecules, organisms | `{WIDGETBOOK_COMPONENTS_ROOT}/atoms|molecules|organisms/[sub]/` |
| `APP_SCREENS` | Pantallas de app con estado y mocks | `{WIDGETBOOK_SCREENS_ROOT}/features/[feature]/[screen]/` |

## Regla de precedencia en este pipeline

- En `/new-component`, usar `DS_COMPONENTS`.
- En `/new-view`, usar ambos scopes en fases distintas:
  - `DS_COMPONENTS` en la fase `DS_WIDGETBOOK`.
  - `APP_SCREENS` en la fase `APP_WIDGETBOOK_SCREENS`.
- Si el usuario lo vuelve a pedir explícitamente, no duplicar artefactos canónicos.

## Required Use Cases por scope

### A) `DS_COMPONENTS`
Archivo: `[componente]_use_case.dart`

1. `Overview` (opcional si componente simple)
2. `Playground` (obligatorio)
3. Estados relevantes (`loading`, `disabled`, `error`) como knobs o use cases fijos
4. `All Variants` (obligatorio cuando existe enum de variantes)

### B) `APP_SCREENS`
Archivo: `[screen]_use_case.dart`

1. `Default`
2. `Loading`
3. `Empty` (si aplica)
4. `Error` (si aplica)
5. Variantes de negocio adicionales (si aplica: `prefilled`, `validation_error`, etc.)

Para pantallas, usar wrappers/mocks y evitar navegación real.

## Knobs

| Dart Type | Knob | Regla |
|---|---|---|
| `String` | `context.knobs.string()` | valores de dominio reales |
| `bool` | `context.knobs.boolean()` | |
| `enum` | `context.knobs.list()` | siempre con `labelBuilder` |
| `double` | `context.knobs.double.slider()` | min/max razonables |
| `int` | `context.knobs.int.slider()` | min/max razonables |
| `Color` | sin knob | viene del theme/tokens |
| `VoidCallback?` | boolean + ternary | `enabled ? () => developer.log('...') : null` |

> Cuando uses `developer.log(...)` en snippets, importar
> `dart:developer` como `developer`.

## Code Preview

Cada use case debe incluir `context.setCodePreview(...)`.

## Reglas obligatorias

- ALWAYS incluir `labelBuilder` en knobs enum/list.
- ALWAYS usar textos literales de Figma en knobs/mocks cuando existan.
- Si Figma no define el valor, usar datos del dominio real y marcarlos como
  ejemplo; no inventar copy de interfaz.
- NEVER agregar knobs para colores.
- ALWAYS usar `developer.log(...)` en callbacks de ejemplo (no `print`).
- NEVER usar `part '*.g.dart'` en archivos `*.use_case.dart`.
- ALWAYS ejecutar `dart analyze` antes de `build_runner`.
- Para `APP_SCREENS`, ALWAYS usar mocks/providers de prueba y no navegación real.

## Comandos

```bash
# Analizar DS
dart analyze {WIDGETBOOK_COMPONENTS_ROOT}/atoms {WIDGETBOOK_COMPONENTS_ROOT}/molecules {WIDGETBOOK_COMPONENTS_ROOT}/organisms

# Analizar pantallas (si se usa APP_SCREENS)
dart analyze {WIDGETBOOK_SCREENS_ROOT}/features

# Generar archivos de widgetbook
dart run build_runner build --delete-conflicting-outputs
```

## Checklist

- [ ] `WIDGETBOOK_SCOPE` definido (`DS_COMPONENTS` o `APP_SCREENS`)
- [ ] Archivo `*_use_case.dart` en ruta correcta para el scope
- [ ] Cobertura de estados relevantes
- [ ] `context.setCodePreview(...)` presente
- [ ] `labelBuilder` en knobs enum/list
- [ ] Sin `print`, usar `developer.log`
- [ ] `dart analyze` limpio
- [ ] `build_runner` ejecutado

## Referencias

| Topic | File |
|---|---|
| Setup | `references/setup.md` |
| Project structure | `references/project_structure.md` |
| Features guide | `references/features_guide.md` |
| Variants guide | `references/variants_guide.md` |
| Mocks | `references/mocks.md` |
| Knobs reference | `assets/knobs_reference.md` |
| Coverage audit | `references/coverage_audit.md` |
