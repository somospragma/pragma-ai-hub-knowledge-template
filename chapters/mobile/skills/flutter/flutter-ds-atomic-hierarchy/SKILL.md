---
name: flutter-ds-atomic-hierarchy
description: >
  Atomic Design classification rules and hierarchy for the Design System.
  Use when classifying components as atoms, molecules, or organisms,
  deciding composition strategy, or building dependency graphs (DAG).
commands:
  - classify-component
inputs:
  - name: action
    description: Action to perform (classify, decompose, audit-dag). "classify" determines the atomic level of a component based on its dependencies, "decompose" breaks a complex component into atoms/molecules/organisms, "audit-dag" checks the dependency graph for violations (organism importing organism, molecule importing molecule).
    required: true
  - name: target
    description: Path to the component file or Figma component name to classify/decompose (e.g. lib/ui_system/organisms/product_card/ for audit-dag, "ProductCard" for classify/decompose).
    required: true
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Atomic Hierarchy

## Principle

Atomic Design organizes UI components in increasing complexity:
**Atoms → Molecules → Organisms**

## Classification Criteria

### Atom
- **Does not contain** other DS widgets as dependencies
- Maps to **one visual concept** (button, badge, text, icon, input)
- Is **indivisible** in the DS context
- Has its **own internal state** (default, disabled, loading, etc.)
- Resolves **its own colors/tokens** per state and variant
- **Prefix**: `{{DS_PREFIX}}` + name

### Molecule
- Composes **2+ atoms** into a functional unit
- **Imports and uses** DS atoms (never recreates them)
- **Delegates** visual properties to child atoms
- **Propagates** states to child atoms
- Adds **layout** (Row, Column, Stack) to organize atoms
- **Descriptive name** without mandatory prefix

### Organism
- Composes **molecules + atoms** into a complete UI section
- Typically a **surface** (card, form, navigation bar)
- Uses **Material** for elevation and surface
- Most **parameterizable** level (many callbacks and data)
- Directly fulfills **HU acceptance criteria**
- Considers **responsiveness** (LayoutBuilder, constraints)

## Decision Tree

```
Contains other DS widgets?
├── NO → ATOM
│   Single visual concept?
│   ├── YES → ✅ Atom confirmed
│   └── NO → Evaluate decomposition
│
└── YES → Only composes atoms?
    ├── YES → MOLECULE
    │   Groups 2+ atoms in a function?
    │   ├── YES → ✅ Molecule confirmed
    │   └── NO → Probably atom with decoration
    │
    └── NO → Composes molecules (+ atoms)?
        ├── YES → ORGANISM
        │   Complete UI section?
        │   ├── YES → ✅ Organism confirmed
        │   └── NO → Could be complex molecule
        │
        └── NO → Evaluate decomposition
```

## Composition Rules

### Strict Bottom-Up
1. **First** create atoms with no dependencies
2. **Then** create molecules that compose atoms
3. **Finally** create organisms that compose molecules + atoms

### Dependencies
- An **atom** does NOT import other DS widgets
- A **molecule** ONLY imports atoms
- An **organism** imports molecules AND/OR atoms
- **FORBIDDEN** to import organisms inside other organisms

### Reuse Strategy
- `reuse`: existing compatible component → import directly
- `separate`: new independent widget → own file and pipeline
- `inline`: private helper widget → `_name.dart` file in parent folder

## Example

```
ProductCard (Organism)
├── CardHeader (Molecule)
│   ├── {{DS_PREFIX}}Image (Atom) → reuse
│   ├── {{DS_PREFIX}}Badge (Atom) → reuse
│   └── {{DS_PREFIX}}Text (Atom) → reuse
├── CardBody (Molecule)
│   ├── {{DS_PREFIX}}Text (Atom) → reuse
│   └── PriceTag (Atom) → 🆕 separate
└── CardActions (Molecule)
    ├── {{DS_PREFIX}}Button (Atom) → reuse
    └── {{DS_PREFIX}}IconButton (Atom) → reuse
```
