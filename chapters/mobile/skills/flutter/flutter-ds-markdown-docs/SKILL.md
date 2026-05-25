---
name: flutter-ds-markdown-docs
description: >
  Markdown documentation standard for Design System components.
  Use when generating README files for organisms, documenting component
  APIs, writing usage examples, or creating component catalogs.
commands:
  - generate-ds-docs
inputs:
  - name: action
    description: Action to perform (generate, audit). "generate" creates a README.md for a DS component following the standard template, "audit" checks existing documentation for missing sections (API table, tokens, composition, anti-patterns).
    required: true
  - name: target
    description: Path to the DS component directory to document (e.g. lib/ui_system/organisms/product_card/).
    required: true
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Markdown Documentation

## When to Generate

- **Atoms**: normalmente no requieren README separado
- **Molecules**: README if composition logic is non-obvious
- **Organisms**: ALWAYS generate README

## README Template

See [component README template](assets/COMPONENT-README-TEMPLATE.md) for the full starter.

## Required Sections

1. **Title** — Component name with brief description
2. **Usage** — Functional code example (must compile)
3. **API** — Table of parameters with types, required, defaults
4. **Enums** — State, Variant, Size values with descriptions
5. **Tokens** — Table of tokens used by category
6. **Composition** — Tree of sub-components
7. **States** — Behavior per state
8. **Figma** — URL and atomic level
9. **Anti-patterns** — What NOT to do

## Rules

- Comentarios en código (inline/bloque/doc) no son obligatorios
- Separate README is **complementary** for complex components
- ALWAYS include functional usage example (that compiles)
- ALWAYS document tokens used
- ALWAYS document composition (sub-component tree)
- ALWAYS include anti-patterns if any
