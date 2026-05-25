# Integration Testing Reference

Integration tests validate complete user flows end-to-end, from UI to all services.
They are slow but cover what unit and widget tests cannot: real navigation, real state
persistence, and multi-screen interactions.

## Stack

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
```

---

## When to Use

| ✅ Use for | ❌ Do not use for |
|---|---|
| Critical user flows (login, checkout, onboarding) | Visual styling (use golden tests) |
| Multi-screen navigation | Isolated logic (use unit tests) |
| Data persistence across screens | Single widget behaviour (use widget tests) |
| Network error recovery flows | |
| Offline / reconnect behaviour | |

---

## Folder Structure

```
integration_test/
├── app_test.dart               # smoke test
├── flows/
│   ├── login_flow_test.dart
│   ├── product_list_flow_test.dart
│   └── checkout_flow_test.dart
└── helpers/
    ├── app_driver.dart         # shared setup helpers
    └── test_data.dart
```

---

## Required Setup: IntegrationTestWidgetsFlutterBinding

**Always call this first.** Without it, tests fail on real devices and Firebase Test Lab.

```dart
// integration_test/app_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App smoke test', () {
    testWidgets('app starts and shows home screen', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
    });
  });
}
```

| Context | Binding | Command |
|---|---|---|
| Emulator / desktop | `flutter_test` | `flutter test integration_test/` |
| Real device | `IntegrationTestWidgetsFlutterBinding` | `flutter drive --target=integration_test/app_test.dart` |
| Firebase Test Lab | `IntegrationTestWidgetsFlutterBinding` | Firebase CLI |

---

## Login Flow

```dart
// integration_test/flows/login_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Login Flow', () {
    testWidgets('navigates to home on valid credentials', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);

      await tester.enterText(find.byKey(const Key('email_field')), 'user@example.com');
      await tester.enterText(find.byKey(const Key('password_field')), 'password123');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('shows error on invalid credentials', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('email_field')), 'wrong@example.com');
      await tester.enterText(find.byKey(const Key('password_field')), 'wrong');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Invalid credentials'), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
    });

    testWidgets('shows loading indicator while authenticating', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('email_field')), 'user@example.com');
      await tester.enterText(find.byKey(const Key('password_field')), 'password123');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pump(); // one frame — loading visible

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 3));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
```

---

## List → Detail Flow

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Product List Flow', () {
    testWidgets('taps product and navigates to detail', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ProductListTile), findsWidgets);

      await tester.tap(find.byKey(const Key('product-tile-1')).first);
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailPage), findsOneWidget);
      expect(find.text('Widget'), findsOneWidget);
    });

    testWidgets('back navigation returns to list', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byKey(const Key('product-tile-1')).first);
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(ProductListPage), findsOneWidget);
    });
  });
}
```

---

## Checkout Flow

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Checkout Flow', () {
    testWidgets('completes purchase with valid payment', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Add to cart
      await tester.tap(find.byKey(const Key('add-product-1')));
      await tester.pump();

      // Open cart
      await tester.tap(find.byKey(const Key('cart_button')));
      await tester.pumpAndSettle();

      expect(find.text('Widget'), findsOneWidget);

      // Checkout
      await tester.tap(find.byKey(const Key('checkout_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('address_field')),
        '123 Main St',
      );
      await tester.tap(find.byKey(const Key('confirm_order_button')));
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(find.byType(OrderConfirmationPage), findsOneWidget);
    });
  });
}
```

---

## Shared Helpers

```dart
// integration_test/helpers/app_driver.dart
Future<void> launchApp(WidgetTester tester) async {
  app.main();
  await tester.pumpAndSettle();
}

Future<void> login(WidgetTester tester, {
  String email = 'user@example.com',
  String password = 'password123',
}) async {
  await tester.enterText(find.byKey(const Key('email_field')), email);
  await tester.enterText(find.byKey(const Key('password_field')), password);
  await tester.tap(find.byKey(const Key('login_button')));
  await tester.pumpAndSettle(const Duration(seconds: 3));
}
```

---

## Running Integration Tests

```bash
# Emulator / desktop
flutter test integration_test/

# Specific flow
flutter test integration_test/flows/login_flow_test.dart

# Real device
flutter drive --target=integration_test/app_test.dart

# With extended timeout
flutter test integration_test/ --timeout=120s
```

---

## Rules

- Always call `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` first
- Limit to the top 5–10 critical user flows — they are expensive to maintain
- Use `pumpAndSettle(Duration(...))` with a generous timeout for network calls
- Extract shared setup into helpers to avoid duplication
- Tests must be independent — no shared state between test cases
- Use staging/mock backend, never production
