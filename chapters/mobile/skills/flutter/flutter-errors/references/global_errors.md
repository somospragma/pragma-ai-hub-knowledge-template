# Global Errors — FlutterError + PlatformDispatcher

`lib/core/error/global_error_handler.dart` + `main.dart`

---

## global_error_handler.dart

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract final class GlobalErrorHandler {
  /// Configures all Flutter error hooks.
  /// Call BEFORE runApp() — see main.dart.
  static void initialize() {
    // 1. Synchronous framework errors (layout, rendering, etc.)
    FlutterError.onError = (FlutterErrorDetails details) {
      _handle(
        error: details.exception,
        stackTrace: details.stack,
        context: details.context?.toDescription(),
        isFatal: false,
      );
    };

    // 2. Unhandled async errors in the Flutter zone
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      _handle(
        error: error,
        stackTrace: stackTrace,
        context: 'PlatformDispatcher',
        isFatal: true,
      );
      return true; // true = error handled, do not re-throw
    };
  }

  static void _handle({
    required Object error,
    StackTrace? stackTrace,
    String? context,
    required bool isFatal,
  }) {
    if (kDebugMode) {
      // In debug: display normally in the console
      FlutterError.presentError(FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        context: ErrorDescription(context ?? ''),
      ));
      return;
    }

    // In release: send to monitoring service
    // FirebaseCrashlytics.instance.recordError(
    //   error,
    //   stackTrace,
    //   fatal: isFatal,
    //   information: [context ?? ''],
    // );
    debugPrint('[GlobalError] [$context] $error\n$stackTrace');
  }
}
```

---

## main.dart — complete setup

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'core/error/global_error_handler.dart';

Future<void> main() async {
  // Ensure binding before any operation
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (if applicable)
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  // Register handlers BEFORE runApp
  GlobalErrorHandler.initialize();

  // Wrap in runZonedGuarded to catch async zone errors
  // that PlatformDispatcher may miss in some versions
  runZonedGuarded(
    () => runApp(
      ProviderScope(  // or set BlocObserver if using BLoC only
        child: const MyApp(),
      ),
    ),
    (error, stackTrace) {
      GlobalErrorHandler._handle(
        error: error,
        stackTrace: stackTrace,
        context: 'runZonedGuarded',
        isFatal: true,
      );
    },
  );
}
```

---

## Global BlocObserver (for BLoC projects)

```dart
// lib/core/observers/app_bloc_observer.dart

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    // Errors not caught in event handlers
    debugPrint('[BlocObserver] ${bloc.runtimeType}: $error');
    // FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    if (kDebugMode) {
      debugPrint('[BlocObserver] ${bloc.runtimeType}: ${change.nextState}');
    }
  }
}

// In main.dart:
// Bloc.observer = const AppBlocObserver();
```

---

## Custom ErrorWidget (fallback UI)

```dart
// In main.dart, inside MaterialApp or in main():

// Replaces the red error screen in debug
ErrorWidget.builder = (FlutterErrorDetails details) {
  return Scaffold(
    backgroundColor: Colors.white,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (kDebugMode)
              Text(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    ),
  );
};
```

---

## ProviderObserver for Riverpod (equivalent to BlocObserver)

```dart
// lib/core/observers/app_provider_observer.dart

class AppProviderObserver extends ProviderObserver {
  const AppProviderObserver();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    debugPrint('[ProviderObserver] ${provider.name ?? provider.runtimeType}: $error');
    // FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
}

// In main.dart:
// ProviderScope(
//   observers: [const AppProviderObserver()],
//   child: const MyApp(),
// )
```
