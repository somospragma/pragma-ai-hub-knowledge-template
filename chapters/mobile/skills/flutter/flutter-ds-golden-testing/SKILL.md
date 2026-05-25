---
name: flutter-ds-golden-testing
description: >
  Golden testing (visual regression) patterns using Alchemist for Flutter DS.
  Use when creating visual snapshot tests, verifying pixel-perfect rendering,
  or setting up golden tests for light/dark themes and all variants/states.
commands:
  - golden-test-ds
inputs:
  - name: action
    description: Action to perform (generate, update, audit). "generate" creates golden tests for a DS component covering all variants, states, and dark mode, "update" regenerates golden files after intentional visual changes, "audit" checks for missing golden coverage (variants, states, dark mode, sizes).
    required: true
  - name: target
    description: Path to the DS component file or test directory (e.g. lib/ui_system/atoms/button/ds_button.dart for generate, test/ui_system/atoms/button/ for update/audit).
    required: true
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Golden Testing

## Framework: Alchemist

Golden tests validate that a widget's visual rendering doesn't change unexpectedly.

## Required Goldens

1. **All variants grid** — every variant in light mode
2. **All states grid** — every state
3. **Dark mode** — key variants in dark theme
4. **Combination** — at least 1 variant × state combo
5. **Sizes** (if applicable) — grid of all sizes

See [golden test template](assets/golden_test_template.dart.txt) for complete starter code.

## Critical Rules

1. **ALWAYS** wrap widget in `SizedBox` with fixed dimensions for consistent layout
2. **ALWAYS** include light AND dark mode scenarios
3. **ALWAYS** use `ThemeData(extensions: [...])` for theme
4. **ALWAYS** use `@Tags(['golden'])` for CI/CD filtering
5. **ALWAYS** use `GoldenTestGroup` with `children` param (NOT `scenarios`)
6. **NEVER** use variable dimensions — always fixed for reproducibility

## Standard Dimensions

| Context | Width | Notes |
|---------|-------|-------|
| Mobile | 327px | Typical mobile card width |
| Desktop | 610px | Typical desktop card width |
| Grid | 400px | For comparison grids |
| Icon | 48×48px | For icon atoms |

## Golden File Naming

| Type | Format |
|------|--------|
| All variants | `[component]_all_variants` |
| All states | `[component]_all_states` |
| Dark mode | `[component]_dark` |
| Specific | `[component]_[variant]_[state]` |
| Responsive | `[component]_responsive_[breakpoint]` |

## Commands

```bash
# Generate/update goldens
flutter test --update-goldens --tags golden test/[level]/[component]/

# Verify goldens (CI)
flutter test --tags golden test/[level]/[component]/
```

## Pattern: Variant Grid

```dart
goldenTest(
  '{{DS_PREFIX}}Component — all variants',
  fileName: 'component_all_variants',
  builder: () => GoldenTestGroup(
    scenarioConstraints: const BoxConstraints(maxWidth: 400),
    children: [
      for (final variant in Variant.values)
        GoldenTestScenario(
          name: variant.name,
          child: SizedBox(width: 327, height: 48, child: Widget(variant: variant)),
        ),
    ],
  ),
);
```

## Pattern: Dark Mode

```dart
goldenTest(
  '{{DS_PREFIX}}Component — dark',
  fileName: 'component_dark',
  builder: () => GoldenTestGroup(
    children: [
      GoldenTestScenario(
        name: 'dark default',
        child: Theme(
          data: ThemeData(brightness: Brightness.dark, extensions: [/* dark */]),
          child: SizedBox(width: 327, height: 48, child: Widget()),
        ),
      ),
    ],
  ),
);
```
