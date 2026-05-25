# Golden Testing Reference

Golden tests detect visual regressions by comparing widget screenshots against
reference images. Use them for visually complex custom widgets, not for behaviour.

## Stack

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  # No additional packages required for basic golden tests.
  # alchemist (pub.dev/packages/alchemist) is an optional wrapper for multi-scenario goldens.
```

---

## When to Use

| ✅ Use for | ❌ Do not use for |
|---|---|
| Custom design system components | Behaviour / logic (use widget tests) |
| All visual states of a widget (normal, disabled, loading, error) | Third-party widgets |
| Light and dark theme variants | Animated widgets (too fragile) |
| Overflow / long text edge cases | Widgets with dynamic content |
| Responsive layout breakpoints | |

---

## Folder Structure

```
test/
└── golden/
    ├── goldens/                  # reference images — committed to git
    │   ├── product_card.png
    │   └── custom_button_disabled.png
    ├── failures/                 # diff images on failure — git ignored
    └── product_card_golden_test.dart
```

`.gitignore`:
```
test/golden/failures/
```

---

## Basic Setup

```dart
// test/golden/product_card_golden_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductCard golden tests', () {
    testWidgets('renders correctly in available state', (tester) async {
      tester.view.physicalSize = const Size(400, 250);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ProductCard(
              vm: ProductViewModel(
                id: '1',
                title: 'Blue Widget',
                priceLabel: r'$9.99',
                isAvailable: true,
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(ProductCard),
        matchesGoldenFile('goldens/product_card_available.png'),
      );
    });

    testWidgets('renders correctly in unavailable state', (tester) async {
      tester.view.physicalSize = const Size(400, 250);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ProductCard(
              vm: ProductViewModel(
                id: '1',
                title: 'Blue Widget',
                priceLabel: r'$9.99',
                isAvailable: false,
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(ProductCard),
        matchesGoldenFile('goldens/product_card_unavailable.png'),
      );
    });
  });
}
```

---

## Testing All Visual States

```dart
group('CustomButton golden tests', () {
  Future<void> pumpButton(WidgetTester tester, Widget button) async {
    tester.view.physicalSize = const Size(400, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: button)),
      ),
    );
  }

  testWidgets('default state', (tester) async {
    await pumpButton(
      tester,
      CustomButton(label: 'Confirm', onPressed: () {}),
    );
    await expectLater(
      find.byType(CustomButton),
      matchesGoldenFile('goldens/custom_button_default.png'),
    );
  });

  testWidgets('disabled state', (tester) async {
    await pumpButton(
      tester,
      const CustomButton(label: 'Confirm', onPressed: null),
    );
    await expectLater(
      find.byType(CustomButton),
      matchesGoldenFile('goldens/custom_button_disabled.png'),
    );
  });

  testWidgets('loading state', (tester) async {
    await pumpButton(
      tester,
      CustomButton(label: 'Confirm', isLoading: true, onPressed: () {}),
    );
    await expectLater(
      find.byType(CustomButton),
      matchesGoldenFile('goldens/custom_button_loading.png'),
    );
  });
});
```

---

## Light and Dark Theme

```dart
for (final (name, theme) in [
  ('light', AppTheme.light()),
  ('dark', AppTheme.dark()),
]) {
  testWidgets('ProductCard in $name theme', (tester) async {
    tester.view.physicalSize = const Size(400, 250);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: ProductCard(vm: tProductVm)),
      ),
    );

    await expectLater(
      find.byType(ProductCard),
      matchesGoldenFile('goldens/product_card_$name.png'),
    );
  });
}
```

---

## Responsive Breakpoints

```dart
for (final (label, size) in [
  ('phone', const Size(390, 844)),
  ('tablet', const Size(1024, 768)),
]) {
  testWidgets('Dashboard on $label', (tester) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(MaterialApp(home: const DashboardPage()));
    await tester.pump();

    await expectLater(
      find.byType(DashboardPage),
      matchesGoldenFile('goldens/dashboard_$label.png'),
    );
  });
}
```

---

## Workflow

```bash
# Create / update golden files (run after intentional UI changes)
flutter test --update-goldens test/golden/

# Run golden tests only
flutter test test/golden/

# Run all tests except goldens (faster CI)
flutter test --exclude-tags golden

# Tag golden tests for selective execution
@Tags(['golden'])
void main() { ... }
```

---

## CI Integration

```yaml
# .github/workflows/golden.yml
- name: Run golden tests
  run: flutter test test/golden/

- name: Upload failures on failure
  if: failure()
  uses: actions/upload-artifact@v4
  with:
    name: golden-failures
    path: test/golden/failures/
```

---

## Reviewing Changes

When a golden test fails after an intentional UI change:

1. Check `test/golden/failures/` for the diff image
2. If the change is correct, update the golden: `flutter test --update-goldens`
3. Review with `git diff test/golden/goldens/`
4. Commit the updated golden files

---

## Rules

- Commit golden files to git — they are the source of truth
- Add `test/golden/failures/` to `.gitignore`
- Fix the physical size in every golden test for reproducibility
- Run golden tests on a consistent OS (CI Linux or macOS — pick one and stick to it)
- Do not use golden tests for animated widgets
- Keep golden tests in a separate folder so they can be excluded from fast CI runs
