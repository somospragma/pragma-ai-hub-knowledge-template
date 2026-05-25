---
name: flutter-ds-component-template
description: >
  Base templates for creating Flutter Design System components by atomic level.
  Use when generating new atom, molecule, or organism widget code.
  Provides starter code structure with proper anatomy, tokens, and patterns.
commands:
  - scaffold-ds-component
inputs:
  - name: level
    description: Atomic level of the component to scaffold (atom, molecule, organism). Determines the template, dependency rules, and complexity expectations.
    required: true
  - name: target
    description: Path where the component will be created (e.g. lib/ui_system/atoms/badge/ or lib/ui_system/organisms/product_card/).
    required: true
  - name: name
    description: Name of the component (e.g. Badge, ProductCard, SearchBar). Will be prefixed with the DS prefix automatically.
    required: true
metadata:
  author: pragma-ds
  version: "1.2"
  domain: flutter-design-system
---

# Component Templates

## When to Use

- **Atom**: Use [atom template](assets/atom_template.dart.txt) for indivisible components
- **Molecule**: Use [molecule template](assets/molecule_template.dart.txt) for 2+ atom compositions
- **Organism**: Use [organism template](assets/organism_template.dart.txt) for complete UI sections

## Atom Rules

- No DS widget dependencies — purely standalone
- Resolves its own colors/tokens per state and variant
- Prefix: `{{DS_PREFIX}}` + name
- Constructor: `const`, `super.key`, required params first, callbacks last
- Build delegates to `_build*` methods per state
- Resolvers `_resolve*` for token lookup per variant/state

## Molecule Rules

- **IMPORT and USE** atoms from DS — never recreate functionality
- **DELEGATE** visual properties to child atoms
- **PROPAGATE** states to child atoms
- **PARAMETERS** are data (`String title`), NOT widgets (`Widget header`)
- **SPACINGS** between children use tokens
- **TEXT** values come from the Figma literal text contract; do not rewrite copy
- **OVERFLOW** in horizontal layouts is mitigated with `Flexible`/`Expanded` or
  `Wrap` when allowed by the contract

## Organism Rules

- Compose **molecules + atoms** into complete sections
- Use **Material** for elevation and surface
- **Multiple callbacks** (one per user action)
- Implement **responsiveness** with `LayoutBuilder`
- **Complete skeleton** in loading (not just parts)
- Directly fulfills **HU acceptance criteria**
- Preserve Figma literal texts and do not add extra UX/copy
- Use scroll/SafeArea/flexible constraints to avoid overflow in full sections

## Template Structure

Every template follows this internal order:

1. Imports (package imports, grouped)
2. Widget class
   - 2a. Const constructor
   - 2b. Final properties with explicit names
   - 2c. Computed getters
   - 2d. `build()` → switch by state
   - 2e. `_build*` private methods
   - 2f. `_resolve*` private methods
3. Enums (State, Variant, Size)
4. Private helper classes (if needed)
5. Comments only in fundamental exceptions (non-obvious rationale)
