---
name: delivery-review
description: >
  Prompt para la fase final de entrega. Usar cuando implementación y testing
  ya terminaron y toca preparar documentación, estructura, branch/PR y reporte
  final con contexto de topología.
agent: delivery-manager
---

# Entrega y Revisión Final

## Skills de referencia

- flutter-ds-folder-structure
- flutter-ds-naming-conventions
- flutter-ds-markdown-docs
- flutter-ds-lint-rules
- flutter-commit-conventions
- flutter-changelog-management

## Contexto mínimo obligatorio

1. `workflow`.
2. `project_root`.
3. `topology`.
4. `target`.
5. `execution_context`.
6. `PIPELINE_SPEC_PATH`.
7. `PIPELINE_LOG_PATH`.

Si falta contexto, devolver `blocked_input`.

## INSTRUCCIÓN

Tras completar testing, preparar la entrega final del componente o vista.

## PROCESO

### 1. Revisión de estructura

- Verificar ubicación de archivos contra `flutter-ds-folder-structure`.
- Confirmar que el código productivo nuevo/modificado vive bajo `lib/src`,
  excepto entrypoints `lib/main*.dart` y barrels públicos `lib/<package>.dart`.
- Validar naming conventions.
- Validar barrel files.
- Validar que consumidores externos usan barrels públicos y no
  `package:<package>/src/...`.
- En `/new-view`, no exportar vistas en barrel DS.

### 2. Validación de scope

- Confirmar que cambios pertenecen al `target.target_root`.
- En `monorepo_melos`, confirmar que no se modifican paquetes fuera de
  `target.package_path`.

### 3. Documentación

- Verificar política de comentarios en código:
  - sin comentarios inline/bloque/Dartdoc por defecto
  - excepciones solo si son fundamentales y justificadas
- Generar README cuando aplique.

### 4. Branch y commits

- Branch DS: `naming.branch_prefix`.
- Branch vista: `naming.view_branch_prefix` (fallback `naming.branch_prefix`).
- Commits con Conventional Commits.

### 5. PR

Incluir:
- HU
- Figma
- inventario de archivos
- resumen de tests
- checklist DoD

### 6. Reporte §7

```markdown
## §7 Reporte de Entrega

### Contexto de Ejecución
- **Repo mode**: ...
- **Target package**: ...
- **Target root**: ...
- **Melos scope**: ...

### Resumen
- **Branch**: ...
- **PR**: ...
- **Archivos creados/modificados**: ...
- **Tests**: ...
- **Auditoría**: ...

### Criterios de Aceptación
- [x] ...
```

## Verificación final (topology-aware)

### `single_repo` o `multi_repo`

```bash
flutter analyze
flutter test
flutter test --tags golden
dart run build_runner build --delete-conflicting-outputs
```

### `monorepo_melos`

```bash
melos exec --scope={target_scope} -- flutter analyze
melos exec --scope={target_scope} -- flutter test
melos exec --scope={target_scope} -- flutter test --tags golden
melos exec --scope={target_scope} -- dart run build_runner build --delete-conflicting-outputs
```
