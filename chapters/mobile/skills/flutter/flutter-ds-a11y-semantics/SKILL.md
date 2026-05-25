---
name: flutter-ds-a11y-semantics
description: >
  Accessibility and semantics rules for Design System components.
  Use when implementing interactive widgets, adding semantic labels,
  handling images, communicating states to screen readers, or writing
  accessibility tests.
commands:
  - audit-a11y
inputs:
  - name: action
    description: Action to perform (audit, fix). "audit" checks DS components for missing semantics labels, insufficient touch areas, decorative images without excludeFromSemantics, or missing state communication, "fix" applies accessibility corrections to identified issues.
    required: true
  - name: target
    description: Path to the DS component file or directory to audit (e.g. lib/ui_system/atoms/button/ for specific component, lib/ui_system/ for full audit).
    required: true
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Accessibility & Semantics

## Principles

1. Every interactive element must have a **Semantics label**
2. Decorative images must be **excluded** from semantics
3. Colors must not be the **only** state indicator
4. Minimum contrast **4.5:1** for normal text, **3:1** for large text
5. Minimum touch area **48×48** logical pixels

## Interactive Elements

```dart
// ✅ Explicit semantics
Semantics(
  button: true,
  label: 'Add to cart',
  child: InkWell(onTap: onAddToCart, child: /* visual */),
)

// ✅ Material widgets (automatic semantics)
ElevatedButton(onPressed: onAddToCart, child: Text('Add to cart'))
```

## Images

```dart
// ✅ Informative image
Image.network(url, semanticLabel: 'Product photo: $productName')

// ✅ Decorative image
Image.asset('assets/bg.png', excludeFromSemantics: true)

// ✅ Decorative icon
Icon(Icons.chevron_right, semanticLabel: null)
```

## State Communication

```dart
Semantics(
  enabled: state != ComponentState.disabled,
  label: _semanticLabel,
  child: /* widget */,
)

String get _semanticLabel {
  final base = 'Product card: $productName';
  return switch (state) {
    ComponentState.loading => '$base, loading',
    ComponentState.error => '$base, error',
    ComponentState.disabled => '$base, disabled',
    _ => base,
  };
}
```

## Touch Area

```dart
SizedBox(
  width: 48,
  height: 48,
  child: IconButton(onPressed: onAction, icon: Icon(Icons.close)),
)
```

## Testing

```dart
testWidgets('should have correct semantics', (tester) async {
  await tester.pumpApp(const Widget(label: 'Test'));
  final semantics = tester.getSemantics(find.byType(Widget));
  expect(semantics.label, contains('Test'));
});

testWidgets('should communicate disabled state', (tester) async {
  await tester.pumpApp(const Widget(state: State.disabled));
  final semantics = tester.getSemantics(find.byType(Widget));
  expect(semantics.hasFlag(SemanticsFlag.isEnabled), isFalse);
});
```

## Checklist

- [ ] Interactive elements have `Semantics` label
- [ ] Decorative images have `excludeFromSemantics: true`
- [ ] Disabled state communicated semantically
- [ ] Touch areas ≥ 48×48 logical pixels
- [ ] Color contrast meets standards
- [ ] Accessibility tests included
