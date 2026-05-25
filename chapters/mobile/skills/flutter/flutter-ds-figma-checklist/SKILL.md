---
name: flutter-ds-figma-checklist
description: >
  Complete comparison checklist between Flutter implementation and Figma spec.
  Use when auditing visual fidelity, verifying token mapping accuracy,
  checking variant/state coverage, or validating anatomy against Figma layers.
commands:
  - verify-figma-fidelity
inputs:
  - name: action
    description: Action to perform (verify, report). "verify" runs the full checklist against a component comparing implementation to Figma spec, "report" generates a fidelity report with pass/fail per category (colors, typography, spacing, variants, states).
    required: true
  - name: target
    description: Path to the DS component implementation to verify (e.g. lib/ui_system/organisms/product_card/).
    required: true
  - name: figma_url
    description: Figma URL of the reference design to compare against. Required for full verification.
    required: false
metadata:
  author: pragma-ds
  version: "1.2"
  domain: flutter-design-system
---

# Figma Comparison Checklist

## 1. Design Context
- [ ] Figma URL with correct `node-id`
- [ ] `get_design_context` executed before deep analysis
- [ ] Screenshot(s) for visual reference
- [ ] `get_screenshot` captured for each guided change
- [ ] Node metadata extracted (via Figma MCP `get_node` or manual inspection)
- [ ] `get_styles` used to verify published token mappings (if MCP available)
- [ ] MCP status documented: ✅ Acceso directo | ⚠️ Fallback manual
- [ ] Development annotations documented (alerts, estados, reglas especiales)
- [ ] Literal text contract extracted from visible TEXT nodes
- [ ] Layout constraints and overflow-risk matrix extracted or warning recorded

> Consulta skill `flutter-ds-figma-mcp` para detalles de herramientas MCP disponibles.

## 2. Variants & Properties
- [ ] All Figma properties have a Flutter parameter
- [ ] All possible values mapped
- [ ] Defaults match
- [ ] Boolean properties (`show X`) modeled correctly
- [ ] Variant enums have all Figma values
- [ ] Special behaviors from Development annotations modeled explicitly

## 3. Color Tokens
- [ ] Container fill matches Figma token
- [ ] Each text uses correct color token
- [ ] Icons use correct semantic color per variant
- [ ] Borders use correct token
- [ ] Verified in both **light** and **dark**

## 4. Typography
- [ ] Each text uses correct typography token
- [ ] Font size matches
- [ ] Font weight matches (Regular=400, Medium=500, Bold=700)
- [ ] `textAlign` matches
- [ ] `maxLines` and `overflow` if truncation exists
- [ ] Visible text matches Figma literally: casing, accents, punctuation, and line breaks
- [ ] No copy was invented, translated, corrected, summarized, or shortened
- [ ] View states not defined by Figma use standard fallback and are reported

## 5. Spacing & Padding
- [ ] Internal padding (top, right, bottom, left) matches tokens
- [ ] Gap between each child pair matches
- [ ] Symmetric vs asymmetric correct
- [ ] Desktop variant scales padding correctly (if applicable)

## 6. Sizes & Dimensions
- [ ] Icon sizes match spec
- [ ] Component flexible or fixed per Figma
- [ ] Height adapts to content (`MainAxisSize.min`) unless specified
- [ ] Sub-components use corresponding DS widget
- [ ] Horizontal text layouts use `Flexible`/`Expanded` where needed
- [ ] Scroll/SafeArea strategy prevents full-view overflow
- [ ] Missing Figma constraints are warnings when mitigated, not blockers

## 6b. Overflow Safety
- [ ] No `RenderFlex overflow` risk in known compact widths
- [ ] No fixed width/height added without Figma backing
- [ ] `Wrap` or scroll used for groups that can exceed available space
- [ ] `TextOverflow.ellipsis` only when Figma or contract defines truncation
- [ ] Long literal text is preserved; layout adapts instead of shortening copy

## 7. Border Radius
- [ ] Main container radius matches token
- [ ] Internal elements' radius (chips, badges) correct

## 8. Desktop vs Mobile
- [ ] Widget accepts platform parameter (if applicable)
- [ ] Typography scales correctly
- [ ] Padding/spacing scales if Figma indicates
- [ ] Width adapts
- [ ] Tests for both variants
- [ ] Desktop golden tests

See [extended checklist](references/EXTENDED-CHECKLIST.md) for anatomy, states, interaction, modularity, and assets verification.

## Verification Commands

| Check | Command |
|-------|---------|
| Lint | `flutter analyze lib/src/{level}/{component}/` |
| Tests | `flutter test test/{level}/{component}/` |
| Goldens | `flutter test --update-goldens --tags golden` |
| Widgetbook | `dart run build_runner build` |
