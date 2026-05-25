---
name: test-generation
description: >
  Prompt compartido para generar validación de componentes DS o vistas app en
  modo determinista, con reglas de ejecución topology-aware.
---

# Generación de Testing (Determinista por Modo)

## Skills de referencia

- flutter-ds-testing-patterns
- flutter-ds-golden-testing
- flutter-ds-widgetbook
- flutter-ds-theming-tokens
- flutter-ds-folder-structure

## MODO OBLIGATORIO

Antes de ejecutar, el orquestador debe definir `MODE` y el agente debe respetarlo.

| Agente | MODE permitido | Entregables |
|---|---|---|
| `@test-engineer` | `DS_WIDGET_TESTS` | Solo `*_test.dart` de componentes DS |
| `@test-engineer` | `VIEW_WIDGET_TESTS` | Solo tests de vista app (`loading/empty/error/populated` + navegación) |
| `@golden-test-engineer` | `DS_GOLDEN_TESTS` | Solo `*_golden_test.dart` de componentes DS |
| `@golden-test-engineer` | `VIEW_GOLDEN_TESTS` | Solo `*_view_golden_test.dart` de vistas completas |
| `@widgetbook-developer` | `DS_WIDGETBOOK` | Solo `*_use_case.dart` de componentes DS |
| `@widgetbook-developer` | `APP_WIDGETBOOK_SCREENS` | Solo `*_use_case.dart` de pantallas app |

Si `MODE` no está definido o no corresponde al agente actual, detener con `blocked_input`.

## Contexto obligatorio de topología

El handoff debe incluir:

- `topology.repo_mode`
- `target.target_root`
- `execution_context.melos_enabled`
- `execution_context.melos_root`
- `execution_context.target_scope`

Si falta alguno, detener con `blocked_input`.

## Command Resolver (obligatorio)

### `single_repo`

- Ejecutar comandos en `target.target_root`.
- Comandos:
  - `flutter test`
  - `flutter test --update-goldens --tags golden`
  - `dart run build_runner build --delete-conflicting-outputs`

### `monorepo_melos`

- Ejecutar comandos desde `execution_context.melos_root`.
- Exigir `execution_context.melos_enabled=true`.
- Exigir `execution_context.target_scope` no vacío.
- Comandos:
  - `melos exec --scope={target_scope} -- flutter test`
  - `melos exec --scope={target_scope} -- flutter test --update-goldens --tags golden`
  - `melos exec --scope={target_scope} -- dart run build_runner build --delete-conflicting-outputs`

### `multi_repo`

- Ejecutar comandos en `target.target_root` del repo feature activo.
- Comandos iguales a `single_repo`.

## REGLA CRÍTICA DE ALCANCE

- Generar únicamente artefactos del `MODE` recibido.
- No crear archivos de otros modos.
- Reportar en `§6` solo subsección del modo ejecutado.
- No agregar comentarios inline/bloque/Dartdoc en archivos generados, salvo
  caso fundamental no deducible del código.

## INPUTS QUE RECIBIRÁS

1. `MODE`.
2. Código fuente componente/vista.
3. Estados soportados.
4. Variantes soportadas (si aplica).
5. `§1` de Figma (si aplica).
6. Contexto de topología.
7. `§4.B` de textos y overflow, obligatorio para artefactos generados desde
   `/new-component` o `/new-view`.

## MODE: `DS_WIDGET_TESTS` (solo `@test-engineer`)

### Cobertura mínima

1. Renderizado básico.
2. Estados.
3. Variantes.
4. Interacciones.
5. Defaults.
6. Accesibilidad.
7. Textos literales y mitigación anti-overflow cuando aplique.

### Output

1. `[componente]_test.dart`.
2. Sub-sección de `§6` con comando ejecutado y resultado.

## MODE: `VIEW_WIDGET_TESTS` (solo `@test-engineer`)

### Cobertura mínima

1. `loading`
2. `empty`
3. `error`
4. `populated`
5. navegación crítica
6. ausencia de overflow en constraints principales y compactos cuando aplique

### Reglas

- No generar golden tests en este modo.
- No generar widgetbook en este modo.
- Archivo: `[view]_view_test.dart`.

### Output

1. `test/presentation/views/[view]/[view]_view_test.dart`.
2. Sub-sección en `§6`.

## MODE: `DS_GOLDEN_TESTS` (solo `@golden-test-engineer`)

### Goldens obligatorios

1. Grid de variantes (light).
2. Grid de estados.
3. Dark mode.
4. Combinación variante × estado.
5. Tamaños (si aplica).
6. Width compacto si `§4.B` reporta riesgo de overflow.

### Output

1. `[componente]_golden_test.dart`.
2. Sub-sección en `§6` con comando y resultado.

## MODE: `VIEW_GOLDEN_TESTS` (solo `@golden-test-engineer`)

### Goldens obligatorios de vista completa

1. `loading`
2. `empty`
3. `error`
4. `populated`
5. tema `light` y `dark`
6. viewport compacto si `§4.B` reporta riesgo de overflow

### Reglas

- Archivo: `[view]_view_golden_test.dart`.
- Capturar pantalla completa (Scaffold + secciones principales), no widgets
  privados aislados.
- Usar wrappers/mocks de estado para estabilizar resultados.
- Alinear constraints al target de diseño principal (ej: mobile portrait).
- Si hay riesgos de overflow, incluir un escenario compacto adicional y reportar
  si la mitigación depende de constraints inferidos.

### Output

1. `test/presentation/views/[view]/[view]_view_golden_test.dart`.
2. Sub-sección en `§6` con comando y resultado.

## MODE: `DS_WIDGETBOOK` (solo `@widgetbook-developer`)

### Stories obligatorias

1. Overview (si aplica).
2. Playground.
3. States.
4. All variants (si aplica).

### Reglas

- Definir `WIDGETBOOK_SCOPE=DS_COMPONENTS`.
- Resolver `WIDGETBOOK_COMPONENTS_ROOT`.

### Output

1. `[componente]_use_case.dart`.
2. Sub-sección en `§6`.

## MODE: `APP_WIDGETBOOK_SCREENS` (solo `@widgetbook-developer`)

### Cobertura mínima

1. `Default`
2. `Loading`
3. `Empty` (si aplica)
4. `Error` (si aplica)
5. `Populated`

### Reglas

- Definir `WIDGETBOOK_SCOPE=APP_SCREENS`.
- Resolver `WIDGETBOOK_SCREENS_ROOT`.
- No crear widgetbook de componentes DS en este modo.
- Usar textos literales de Figma como valores iniciales de knobs/mocks; no
  inventar copy para hacer más realista el ejemplo.

### Output

1. `[screen]_use_case.dart`.
2. Sub-sección en `§6`.

## Formato de reporte en `§6`

```markdown
## §6 Reporte de Testing

### [MODE ejecutado]
- **Archivo(s)**: ...
- **Comando**: ...
- **Passed**: ...
- **Failed**: ...
- **Resultado**: ...
```
