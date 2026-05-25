# CrashlyticsHandler — Firebase Crashlytics

`handlers/crashlytics_handler.dart`

## Dependencies

**REQUIRED before adding any package:**

1. Check pub.dev for the latest stable version:
   - [`firebase_crashlytics`](https://pub.dev/packages/firebase_crashlytics)
   - [`firebase_core`](https://pub.dev/packages/firebase_core)

2. Install — *the user must run these commands manually (do NOT auto-run):*

```bash
flutter pub add firebase_crashlytics firebase_core
```

> Requires additional setup: `flutterfire configure` and adding `google-services.json` (Android) / `GoogleService-Info.plist` (iOS).

```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../log_event.dart';
import '../log_handler.dart';

/// Sends errors and fatals to Firebase Crashlytics.
/// Navigation events are recorded as breadcrumbs (custom keys).
final class CrashlyticsHandler implements LogHandler {
  @override
  String get name => 'crashlytics';

  @override
  Future<void> initialize() async {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(true);
  }

  @override
  Future<void> log(LogEvent event) async {
    // Add context as custom keys for each report
    event.context.forEach((key, value) {
      FirebaseCrashlytics.instance.setCustomKey(key, value?.toString() ?? '');
    });

    switch (event.category) {
      case LogCategory.error:
        await FirebaseCrashlytics.instance.recordError(
          event.error ?? event.message,
          event.stackTrace,
          reason: event.message,
          fatal: event.level == LogLevel.fatal,
          information: [event.context.toString()],
        );

      case LogCategory.navigation:
        // Navigation breadcrumb — helps reconstruct the flow before a crash
        FirebaseCrashlytics.instance.log(
          'NAV: ${event.context['from']} → ${event.context['to']}',
        );

      default:
        FirebaseCrashlytics.instance.log(
          '[${event.level.name}] ${event.message}',
        );
    }
  }

  @override
  Future<void> dispose() async {}
}
```

---

## Handling fatal Flutter errors

To capture all unhandled errors (synchronous and asynchronous), configure the global
handlers in `main()`:

```dart
import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Option 1: Simplified — passes all fatal errors directly
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Option 2: With access to errorDetails — useful if you need custom logic
  // FlutterError.onError = (errorDetails) {
  //   FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
  // };

  // Capture async errors not handled by the Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const MyApp());
}
```

### Important notes

- **`FlutterError.onError`** — Captures synchronous errors from the Flutter framework (widgets, rendering, etc.)
- **`PlatformDispatcher.instance.onError`** — Captures unhandled async errors (Futures, Isolates, etc.)
- Both must be configured **before** `runApp()` to ensure full coverage
- `recordFlutterFatalError` automatically marks the error as fatal and extracts the stack trace from `FlutterErrorDetails`
