---
name: flutter-ds-testing-patterns
description: >
  Widget testing patterns for Flutter Design System components.
  Use when writing widget tests, setting up test helpers, or verifying
  component behavior across states, variants, interactions, and accessibility.
commands:
  - test-ds-component
inputs:
  - name: action
    description: Action to perform (generate, audit). "generate" creates widget tests for a DS component covering all states, variants, and interactions, "audit" checks existing tests for missing coverage (states, variants, accessibility, null callbacks).
    required: true
  - name: target
    description: Path to the DS component file or test file (e.g. lib/ui_system/atoms/button/ds_button.dart for generate, test/ui_system/atoms/button/ for audit).
    required: true
  - name: component_name
    description: Name of the component to test (e.g. DsButton, DsCard). Required when action is "generate" and cannot be inferred from target path.
    required: false
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Testing Patterns

> **Scope**: Este skill cubre patrones de testing **específicos para componentes del Design System** (pumpApp, estados, variantes, golden, widgetbook). Para fundamentos generales de testing Flutter (unit, widget, integration, mocking, AAA) → ver skill `flutter-testing`.

## Mount Helper

The project must have a `pumpApp` helper (per `project.config.yaml`):

```dart
// test/helpers/pump_app.dart
extension PumpApp on WidgetTester {
  Future<void> pumpApp(Widget widget) async {
    await pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [/* light theme extension */]),
        home: Scaffold(body: widget),
      ),
    );
  }
}
```

## Required Test Sections

Every widget test must include these groups:

1. **Basic rendering** — minimum params + all params
2. **States** — one test per state enum value
3. **Variants** — one test per variant enum value
4. **Interactions** — callback invoked, null-safe, disabled guard
5. **Defaults** — verify default values
6. **Accessibility** — semantics

See [test template](assets/widget_test_template.dart.txt) for complete starter code.

## Conventions

- **AAA pattern**: Arrange-Act-Assert in ALL tests (Pragma mandatory)
- **Names**: `should [verb] when [condition]`
- **Independence**: each test stands alone
- **Helper**: always use `pumpApp` to mount widgets
- **Find**: `find.byType()` for render verification
- **Disabled**: verify `Opacity(0.5)` + `IgnorePointer` + callback not invoked
- **Loading**: verify absence of real content
- **Null-safe**: test callbacks with `null` (must not crash)
- **Coverage**: all states × variants × interactions

## Key Patterns

### Disabled State
```dart
testWidgets('should not invoke callback when disabled', (tester) async {
  var pressed = false;
  await tester.pumpApp(Widget(state: .disabled, onPressed: () => pressed = true));
  await tester.tap(find.byType(Widget));
  expect(pressed, isFalse);
});
```

### Null Callback
```dart
testWidgets('should not crash when callback is null', (tester) async {
  await tester.pumpApp(const Widget(label: 'Test'));
  await tester.tap(find.byType(Widget));
  // No exception = pass
});
```

### Variant Loop
```dart
for (final variant in WidgetVariant.values) {
  testWidgets('should render ${variant.name}', (tester) async {
    await tester.pumpApp(Widget(variant: variant));
    expect(find.byType(Widget), findsOneWidget);
  });
}
```
