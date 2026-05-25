# Core Models — LogEvent, LogLevel, LogHandler

`lib/core/logging/log_level.dart` · `log_event.dart` · `log_handler.dart`

---

## log_level.dart

```dart
/// Severity levels — from lowest to highest impact.
/// The level determines which handlers receive the event (see LoggerConfig).
enum LogLevel {
  debug,    // Dev only: detailed execution traces
  info,     // Normal flow: initialization, configuration
  warning,  // Unexpected but recoverable situations
  error,    // Handled failures: domain Failure, network errors
  fatal;    // Unrecoverable crashes — always sent to Crashlytics + Sentry

  bool operator >=(LogLevel other) => index >= other.index;
}
```

---

## log_event.dart

```dart
import 'log_level.dart';

/// Structured log event — the unit of information that travels
/// from the call site to each handler. Immutable and serializable.
final class LogEvent {
  const LogEvent({
    required this.level,
    required this.category,
    required this.message,
    this.context = const {},
    this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Severity level
  final LogLevel level;

  /// Semantic category — used to route to specific handlers
  final LogCategory category;

  /// Short, readable message in snake_case: 'checkout_failed', 'api_latency'
  final String message;

  /// Structured data: product_id, endpoint, duration_ms, etc.
  final Map<String, Object?> context;

  /// Error and stack only for level >= error
  final Object? error;
  final StackTrace? stackTrace;

  final DateTime timestamp;

  Map<String, Object?> toJson() => {
    'level': level.name,
    'category': category.name,
    'message': message,
    'context': context,
    'timestamp': timestamp.toIso8601String(),
    if (error != null) 'error': error.toString(),
  };
}

/// Semantic category — enables routing and filtering in dashboards.
enum LogCategory {
  error,        // Errors and crashes → Crashlytics, Sentry
  navigation,   // Screen transitions → all active handlers
  performance,  // Latency, duration → DataDog, Grafana
  business,     // Business events → DataDog, Grafana
  debug,        // Development traces → ConsoleHandler only
}
```

---

## log_handler.dart — Strategy Interface

```dart
import 'log_event.dart';

/// Contract that every handler must implement.
/// Each external service (Crashlytics, Sentry, DataDog, Grafana)
/// is a concrete Strategy of this interface.
abstract interface class LogHandler {
  /// Handler name — used in diagnostic logs and configuration.
  String get name;

  /// Initializes the connection with the external service.
  /// Call in LoggerConfig.initialize() before runApp().
  Future<void> initialize();

  /// Sends the event to the service. Does not throw exceptions —
  /// logging errors must never crash the app.
  Future<void> log(LogEvent event);

  /// Releases resources when the app closes.
  Future<void> dispose();
}
```

---

## Category handling per handler

Each handler decides internally how to process each category based on the
service's capabilities. `AppLogger` dispatches all events to the active
handler — it is the handler's responsibility to filter or transform them.

| Category | Typical behaviour |
|---|---|
| `error` / `fatal` | All handlers process it (crash reports, exceptions) |
| `navigation` | Breadcrumbs in Crashlytics/Sentry, events in DataDog/Grafana |
| `performance` | Latency metrics — some handlers ignore it (e.g. Crashlytics) |
| `business` | Business events — ideal for DataDog/Grafana, ignored by Crashlytics |
| `debug` | Only relevant for ConsoleHandler in development |

> Each handler implements its own logic in `log(LogEvent event)` to decide
> what to do with each category. See the individual handler references for examples.
