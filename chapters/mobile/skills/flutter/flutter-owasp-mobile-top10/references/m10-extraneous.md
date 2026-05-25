# M10 — Extraneous Functionality

This category covers debugging code, backdoors, and functionality not intended for production.

---

## Check M10-A: Debug features and endpoints

**ID:** `M10-A-DEBUG-FEATURES`
**Objective:** Detect debug routes, menus, or functionality accessible in production.
**Scope:** `lib/**.dart`

**Method:** Lexical + semantic search
**Insecure patterns:**

```dart
// PATTERN 1: Debug routes
final routes = {
  '/': (context) => HomeScreen(),
  '/profile': (context) => ProfileScreen(),
  '/debug': (context) => DebugScreen(),   // ❌ Debug route
  '/test': (context) => TestScreen(),     // ❌ Test route
  '/dev': (context) => DevToolsScreen(),  // ❌ Dev tools
};

// PATTERN 2: Dev menu always enabled
class AppSettings {
  static const bool enableDevMenu = true;  // ❌ DANGER
}

// PATTERN 3: Authentication bypass
Future<bool> login(String email, String password) async {
  // ❌❌ EXTREME DANGER — Backdoor
  if (email == 'admin@dev.com' && password == 'dev123') {
    return true;
  }
  return await _authenticateWithServer(email, password);
}

// PATTERN 4: Debug logging without conditional
void processPayment(Payment payment) {
  print('Processing payment: ${payment.toJson()}');  // ❌ No kDebugMode guard
  _submitPayment(payment);
}

// PATTERN 5: Secret gesture to open debug panel (always available)
Widget build(BuildContext context) {
  return GestureDetector(
    onLongPress: () {
      // ❌ Always available — should be debug only
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => DebugPanel(),
      ));
    },
    child: MyApp(),
  );
}
```

**Lexical search:**
```bash
# Debug/test/dev routes
grep -rE "['\"]/(debug|test|dev|admin|backdoor)['\"]" lib/ --exclude-dir=test

# Dev menu always enabled
grep -r "enableDevMenu\s*=\s*true" lib/

# Auth bypass
grep -r "bypassAuth\|skipAuth\|devLogin" lib/

# Debug panels without kDebugMode guard
grep -r "DebugPanel\|DebugScreen\|DevTools" lib/ | grep -v "kDebugMode"
```

**Criteria:**
- ❌ **Fail:** Routes `/debug`, `/test`, `/dev` accessible in production
- ❌ **Fail:** Authentication bypass or backdoors
- ⚠️ **Warning:** Dev menu without `kDebugMode` guard
- ✅ **Pass:** Debug functionality only available in debug builds

**Severity:** `HIGH`
**Automation:** 🟢 High (80%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Conditional routes based on build mode
import 'package:flutter/foundation.dart';

class AppRoutes {
  static Map<String, WidgetBuilder> getRoutes() {
    final routes = <String, WidgetBuilder>{
      '/': (_) => const HomeScreen(),
      '/profile': (_) => const ProfileScreen(),
      '/settings': (_) => const SettingsScreen(),
    };

    // ✅ Debug routes only in debug mode
    if (kDebugMode) {
      routes.addAll({
        '/debug': (_) => const DebugScreen(),
        '/test': (_) => const TestScreen(),
      });
    }

    return routes;
  }
}
```

```dart
// ✅ SOLUTION 2: Dev menu protected by build mode
class DevMenu extends StatelessWidget {
  static bool get isAvailable => kDebugMode;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return FloatingActionButton(
      onPressed: () => _showDevPanel(context),
      child: const Icon(Icons.developer_mode),
    );
  }

  void _showDevPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const DevPanelContent(),
    );
  }
}
```

```dart
// ✅ SOLUTION 3: Remove backdoors completely
// ❌ NEVER do this
Future<bool> login(String email, String password) async {
  if (email == 'admin@dev.com' && password == 'dev123') {
    return true;  // ❌❌ BACKDOOR
  }
  return await _authenticateWithServer(email, password);
}

// ✅ Always authenticate with the server
Future<bool> login(String email, String password) async {
  return await _authenticateWithServer(email, password);
}
```

```dart
// ✅ SOLUTION 4: go_router with conditional debug routes
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    // ✅ Debug routes only in debug mode
    if (kDebugMode)
      GoRoute(path: '/debug', builder: (_, __) => const DebugScreen()),
  ],
);
```

---

## Check M10-B: Dev packages in dependencies

**ID:** `M10-B-DEV-DEPENDENCIES`
**Objective:** Verify that testing packages are not in `dependencies` (only in `dev_dependencies`).
**Scope:** `pubspec.yaml`

**Method:** Lexical search
**Pattern:**

```yaml
# ❌ BAD — Test packages in dependencies
dependencies:
  flutter:
    sdk: flutter
  mocktail: ^1.0.5      # ❌ Should be in dev_dependencies
  bloc_test: ^9.1.7     # ❌ Should be in dev_dependencies
  flutter_test:         # ❌ Should be in dev_dependencies
    sdk: flutter

# ✅ GOOD
dependencies:
  flutter:
    sdk: flutter
  dio: ^5.9.2
  flutter_bloc: ^9.1.1

dev_dependencies:
  flutter_test:         # ✅ Correct
    sdk: flutter
  mocktail: ^1.0.5      # ✅ Correct
  bloc_test: ^9.1.7     # ✅ Correct
  build_runner: ^2.14.1 # ✅ Correct
```

**Lexical search:**
```bash
grep -A100 "^dependencies:" pubspec.yaml | grep -B1 "^dev_dependencies:" | \
  grep -E "(flutter_test|mocktail|bloc_test|fake_async|build_runner):"
```

**Criteria:**
- ⚠️ **Warning:** Test packages in `dependencies`
- ✅ **Pass:** Test packages only in `dev_dependencies`

**Severity:** `MEDIUM`
**Automation:** 🟢 High (100%)

**Remediation:**

```yaml
# ✅ Correct pubspec.yaml structure
name: my_app
description: Production mobile app

dependencies:
  flutter:
    sdk: flutter
  # Production dependencies only
  flutter_secure_storage: ^10.0.0
  flutter_bloc: ^9.1.1
  dio: ^5.9.2
  get_it: ^9.2.1
  injectable: ^3.0.0
  fpdart: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  # All development and testing dependencies
  mocktail: ^1.0.5
  bloc_test: ^9.1.7
  build_runner: ^2.14.1
  injectable_generator: ^3.0.2
  freezed: ^3.2.5
  flutter_lints: ^5.0.0
```

---

## Check M10-C: Unconditional debug code

**ID:** `M10-C-UNCONDITIONAL-DEBUG`
**Objective:** Detect `print()` and `debugPrint()` without `kDebugMode` guard.
**Scope:** `lib/**.dart`

**Method:** Lexical search
**Patterns:**

```dart
// PATTERN 1: print() without conditional
void fetchData() async {
  print('Fetching data...');          // ⚠️ Runs in production
  final data = await api.getData();
  print('Data received: $data');      // ⚠️ May contain sensitive data
}

// PATTERN 2: debugPrint() without conditional
void processPayment(Payment payment) {
  debugPrint('Processing: ${payment.toJson()}');  // ⚠️ Runs in production
}
```

**Lexical search:**
```bash
# print() without kDebugMode
grep -rE "^\s*print\(" lib/ | grep -v "kDebugMode"

# debugPrint() without kDebugMode
grep -r "debugPrint" lib/ | grep -v "kDebugMode"
```

**Criteria:**
- ⚠️ **Warning:** `print()` or `debugPrint()` without `kDebugMode`
- ✅ **Pass:** All logging is conditional or removed in release

**Severity:** `LOW`
**Automation:** 🟢 High (95%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Conditional wrapper
import 'package:flutter/foundation.dart';

void log(String message) {
  if (kDebugMode) print(message);
}

void fetchData() async {
  log('Fetching data...');  // ✅ Debug only
  final data = await api.getData();
  log('Data received');     // ✅ Debug only, no data content
}
```

```dart
// ✅ SOLUTION 2: Logger package with level based on build mode
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

final logger = Logger(
  level: kReleaseMode ? Level.error : Level.debug,
  printer: PrettyPrinter(
    methodCount: kDebugMode ? 2 : 0,
    errorMethodCount: 8,
    printTime: true,
  ),
);

void fetchData() async {
  logger.d('Fetching data...');  // ✅ Not shown in release
  final data = await api.getData();
  logger.i('Data received');     // ✅ Not shown in release
}
```

```dart
// ✅ SOLUTION 3: Remove logs via ProGuard (Android)
// proguard-rules.pro
// -assumenosideeffects class android.util.Log {
//     public static *** d(...);
//     public static *** v(...);
//     public static *** i(...);
// }
```

---

## M10 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M10-A | HIGH | 🟢 80% | Medium |
| M10-B | MEDIUM | 🟢 100% | Low |
| M10-C | LOW | 🟢 95% | Low |

**Total checks:** 3 | **Critical:** 0 | **High:** 1 | **Medium:** 1 | **Low:** 1

**Last updated:** April 2026 | **Version:** 2.0
