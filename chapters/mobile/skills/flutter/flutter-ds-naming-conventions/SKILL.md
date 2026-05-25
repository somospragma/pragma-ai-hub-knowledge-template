---
name: flutter-ds-naming-conventions
description: >
  Official naming conventions for the Flutter Design System.
  Use when creating files, classes, enums, variables, branches, commits,
  golden test outputs, or mapping Figma names to Dart identifiers.
commands:
  - check-ds-naming
inputs:
  - name: action
    description: Action to perform (audit, resolve). "audit" checks existing DS files for naming violations (wrong prefix, incorrect casing, mismatched file/class names), "resolve" maps a Figma component name to the correct Dart class, file, and enum names.
    required: true
  - name: target
    description: Path to the DS directory or file to audit (e.g. lib/ui_system/ for audit), or the Figma component name to resolve (e.g. "Card / Product" for resolve).
    required: true
metadata:
  author: pragma-ds
  version: "1.2"
  domain: flutter-design-system
---

# Naming Conventions

> **Scope**: Este skill cubre convenciones de nomenclatura **específicas del Design System** (prefijo DS, mapeo Figma→Dart, branches DS, goldens). Para el estándar general de código Dart/Flutter (nomenclatura general, imports, estilo, analysis_options) → ver skill `flutter-dart-coding-standard`.

## Files

| Type | Convention | Example |
|------|-----------|---------|
| Widget | `snake_case.dart` | `ds_button.dart` |
| Widget test | `*_test.dart` | `ds_button_test.dart` |
| Golden test | `*_golden_test.dart` | `ds_button_golden_test.dart` |
| Widgetbook story | `*_use_case.dart` | `ds_button_use_case.dart` |
| Token | `*_tokens.dart` | `spacing_tokens.dart` |
| Theme | `{{ds_prefix_snake}}_*.dart` | `ds_theme.dart` |
| Private part | `_[name].dart` | `_product_card_header.dart` |

## Classes

| Type | Convention | Example |
|------|-----------|---------|
| Atom | `{{DS_PREFIX}}PascalCase` | `{{DS_PREFIX}}Button` |
| Molecule | `{{DS_PREFIX}}PascalCase` | `{{DS_PREFIX}}CardHeader` |
| Organism | `{{DS_PREFIX}}PascalCase` | `{{DS_PREFIX}}ProductCard` |
| State enum | `[Widget]State` | `{{DS_PREFIX}}ButtonState` |
| Variant enum | `[Widget]Variant` | `{{DS_PREFIX}}BadgeVariant` |
| Size enum | `[Widget]Size` | `{{DS_PREFIX}}ButtonSize` |

## Variables & Parameters

| Type | Convention | Example |
|------|-----------|---------|
| Widget param | `camelCase` | `labelText`, `isEnabled` |
| Callback (no arg) | `on` + `PascalCase` | `onPressed`, `onDismiss` |
| Callback (with arg) | `on` + `PascalCase` + `Changed` | `onValueChanged` |
| Private variable | `_camelCase` | `_isHovered` |
| Token constant | static `camelCase` | `spacingMd` |

## Enum Values

| Type | Convention | Example |
|------|-----------|---------|
| State | `camelCase` | `default_`, `disabled`, `loading` |
| Variant | `camelCase` | `primary`, `secondary`, `outlined` |
| Size | Abbreviated | `sm`, `md`, `lg` |

> `default` is reserved in Dart — use `default_` for the default state.

## Branches & Commits

See [full naming reference](references/NAMING-REFERENCE.md) for branches, commits, golden file names, and Figma→Dart mapping.

### Branches
- DS pipeline: `{naming.branch_prefix}[slug]` (default: `feat/ds-[slug]`)
- View/App (`/new-view`): `{naming.view_branch_prefix}[slug]` (default: `feat/app-[slug]`)

### Commits (Conventional Commits)
- `feat: add {{DS_PREFIX}}Badge atom component`
- `test: add widget and golden tests for Badge`
- `docs: add widgetbook stories for Badge`
- `fix: Badge color token in disabled state`

## Figma → Dart Mapping

| Figma Name | Dart Name |
|-----------|-----------|
| `Card / Product` | `{{DS_PREFIX}}ProductCard` (organism) |
| `Badge` | `{{DS_PREFIX}}Badge` (atom) |
| `Button / Primary / Medium` | `{{DS_PREFIX}}Button(variant: .primary, size: .md)` |
