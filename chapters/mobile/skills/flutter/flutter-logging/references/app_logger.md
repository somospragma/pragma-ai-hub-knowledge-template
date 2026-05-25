# AppLogger — Facade and LoggerConfig per Flavor

`lib/core/logging/app_logger.dart` · `lib/core/config/logger_config.dart`

---

## app_logger.dart

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'log_event.dart';
import 'log_level.dart';
import 'log_handler.dart';

/// Public facade — single entry point for all app logging.
///
/// Never import Crashlytics, Sentry, DataDog, or Grafana outside their handlers.
/// Everything goes through here. Uses the Strategy pattern: one active handler,
/// swappable without modifying client code.
abstract final class AppLogger {
  static LogHandler? _handler;
  static LogLevel _minLevel = LogLevel.debug;

  /// Currently active handler — useful for LogSyncWorker.
  static LogHandler? get handler => _handler;

  /// Initialize with the active handler for the current flavor.
  /// Call in main() before runApp().
  static Future<void> initialize({
    required LogHandler handler,
    LogLevel minLevel = LogLevel.debug,
  }) async {
    _handler = handler;
    _minLevel = minLevel;
    await _handler!.initialize();
  }

  /// Switch the handler at runtime (e.g. for A/B testing providers).
  /// Calls dispose() on the previous handler and initialize() on the new one.
  static Future<void> switchHandler(LogHandler newHandler) async {
    await _handler?.dispose();
    _handler = newHandler;
    await _handler!.initialize();
  }

  static Future<void> dispose() async {
    await _handler?.dispose();
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  static Future<void> error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.error,
        category: LogCategory.error,
        message: message,
        error: error,
        stackTrace: stackTrace,
        context: context,
      ));

  static Future<void> fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.fatal,
        category: LogCategory.error,
        message: message,
        error: error,
        stackTrace: stackTrace,
        context: context,
      ));

  static Future<void> info(
    String message, {
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.info,
        category: LogCategory.debug,
        message: message,
        context: context,
      ));

  static Future<void> debug(
    String message, {
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.debug,
        category: LogCategory.debug,
        message: message,
        context: context,
      ));

  static Future<void> navigation({
    required String from,
    required String to,
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.info,
        category: LogCategory.navigation,
        message: 'navigate',
        context: {'from': from, 'to': to, ...context},
      ));

  static Future<void> performance(
    String message, {
    required int durationMs,
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.info,
        category: LogCategory.performance,
        message: message,
        context: {'duration_ms': durationMs, ...context},
      ));

  static Future<void> business(
    String event, {
    Map<String, Object?> context = const {},
  }) =>
      _log(LogEvent(
        level: LogLevel.info,
        category: LogCategory.business,
        message: event,
        context: context,
      ));

  // ─── Internal ───────────────────────────────────────────────────────────────

  static Future<void> _log(LogEvent event) async {
    if (event.level < _minLevel) return;
    if (_handler != null) await _safeLog(_handler!, event);
  }

  /// Logging errors must never crash the app.
  static Future<void> _safeLog(LogHandler handler, LogEvent event) async {
    try {
      await handler.log(event);
    } catch (e, st) {
      // Debug only — avoids infinite loop of logging errors about logging errors
      if (kDebugMode) debugPrint('[AppLogger] ${handler.name} failed: $e\n$st');
    }
  }
}
```

---

## logger_config.dart — active handler per flavor

```dart
import 'package:flutter/foundation.dart';
import '../logging/app_logger.dart';
import '../logging/log_handler.dart';
import '../logging/handlers/console_handler.dart';
import '../logging/handlers/crashlytics_handler.dart';
import '../logging/handlers/sentry_handler.dart';
import '../logging/handlers/datadog_handler.dart';
import '../logging/handlers/grafana_handler.dart';

enum AppFlavor { dev, staging, prod }

/// Logging provider to use in staging/prod.
/// Change here to migrate services — no other file needs to change.
enum LogProvider { crashlytics, sentry, datadog, grafana }

abstract final class LoggerConfig {
  /// Active provider for staging/prod.
  /// → CHANGE HERE to migrate logging services.
  static const LogProvider activeProvider = LogProvider.sentry;

  /// Initializes AppLogger with the correct handler for the flavor.
  /// Call in each flavor's main() before runApp().
  static Future<void> initialize(AppFlavor flavor) async {
    final handler = switch (flavor) {
      // Dev: console only, no noise in external services
      AppFlavor.dev => ConsoleHandler(),

      // Staging/Prod: use the configured provider
      AppFlavor.staging || AppFlavor.prod => _buildHandler(flavor),
    };

    await AppLogger.initialize(
      handler: handler,
      minLevel: flavor == AppFlavor.dev ? LogLevel.debug : LogLevel.info,
    );
  }

  /// Builds the handler based on the active provider.
  static LogHandler _buildHandler(AppFlavor flavor) {
    final env = flavor == AppFlavor.staging ? 'staging' : 'prod';

    return switch (activeProvider) {
      LogProvider.crashlytics => CrashlyticsHandler(),

      LogProvider.sentry => SentryHandler(
          dsn: flavor == AppFlavor.staging
              ? Env.sentryDsnStaging
              : Env.sentryDsnProd,
        ),

      LogProvider.datadog => DataDogHandler(
          clientToken: Env.datadogToken,
          applicationId: Env.datadogAppId,
          env: env,
        ),

      LogProvider.grafana => GrafanaHandler(
          endpoint: Env.grafanaEndpoint,
          labels: {'app': 'my_app', 'env': env},
        ),
    };
  }
}
```

---

## main.dart — complete initialization

```dart
// main_prod.dart (each flavor has its own main)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase only if using Crashlytics
  if (LoggerConfig.activeProvider == LogProvider.crashlytics) {
    await Firebase.initializeApp();
  }

  // Register global error handlers BEFORE runApp
  GlobalErrorHandler.initialize();

  // Initialize logger with prod flavor
  await LoggerConfig.initialize(AppFlavor.prod);

  runZonedGuarded(
    () => runApp(ProviderScope(child: const MyApp())),
    (error, stack) => AppLogger.fatal('unhandled_error', error: error, stackTrace: stack),
  );
}
```
