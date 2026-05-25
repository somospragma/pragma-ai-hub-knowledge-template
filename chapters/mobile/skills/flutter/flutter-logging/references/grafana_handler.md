# GrafanaHandler — Grafana Faro

`handlers/grafana_handler.dart`

## Dependencies

**REQUIRED before adding any package:**

1. Check pub.dev for the latest stable version:
   - [`faro`](https://pub.dev/packages/faro)

2. Install — *the user must run these commands manually (do NOT auto-run):*

```bash
flutter pub add faro
```

> Requires `apiKey` and `collectorUrl` from **Grafana Cloud → Faro → Setup**.
> Faro initialization is done in `main()`, not in the handler.

```dart
import 'dart:io';
import 'package:faro/faro.dart';
import '../log_event.dart';
import '../log_handler.dart';
import '../log_level.dart' as log_level;

/// Sends logs to Grafana Faro.
/// IMPORTANT: Faro requires special initialization in main() — see below.
final class GrafanaFaroHandler implements LogHandler {
  const GrafanaFaroHandler({
    required this.appName,
    required this.appVersion,
    required this.appEnv,
    required this.apiKey,
    required this.collectorUrl,
    this.collectorHeaders = const {},
  });

  final String appName;
  final String appVersion;
  final String appEnv;
  final String apiKey;
  final String collectorUrl;
  final Map<String, String> collectorHeaders;

  @override
  String get name => 'grafana_faro';

  @override
  Future<void> initialize() async {
    // Faro is initialized in main() with its own runApp wrapper — see integration section
  }

  @override
  Future<void> log(LogEvent event) async {
    switch (event.category) {
      case LogCategory.error:
        Faro().pushError(
          type: event.error?.runtimeType.toString() ?? 'Exception',
          value: event.message,
          stacktrace: event.stackTrace,
          context: _stringifyContext(event.context),
        );

      case LogCategory.navigation:
        Faro().pushEvent(
          'navigation',
          attributes: {
            'from': event.context['from']?.toString() ?? '',
            'to': event.context['to']?.toString() ?? '',
          },
        );

      case LogCategory.performance:
        Faro().pushMeasurement(
          {'duration_ms': event.context['duration_ms'] ?? 0, ...event.context},
          event.message,
        );

      case LogCategory.business:
        Faro().pushEvent(event.message, attributes: _stringifyContext(event.context));

      default:
        Faro().pushLog(event.message, level: _faroLevel(event.level));
    }
  }

  @override
  Future<void> dispose() async {}

  LogLevel _faroLevel(log_level.LogLevel level) => switch (level) {
    log_level.LogLevel.debug   => LogLevel.debug,
    log_level.LogLevel.info    => LogLevel.info,
    log_level.LogLevel.warning => LogLevel.warn,
    log_level.LogLevel.error   => LogLevel.error,
    log_level.LogLevel.fatal   => LogLevel.error,
  };

  Map<String, String> _stringifyContext(Map<String, Object?> ctx) =>
      ctx.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}
```

---

## Measuring event duration

To measure the duration of specific operations, Faro provides methods to mark start and end:

```dart
// Mark the start of an operation
Faro().markEventStart('api_call', 'fetch_user_profile');

// ... operation code ...

// Mark the end and send the measurement
Faro().markEventEnd('api_call', 'fetch_user_profile', attributes: {
  'user_id': '123',
  'endpoint': '/api/users/profile',
});
```

### Usage from AppLogger

```dart
/// Extension for measuring operation duration with Faro.
extension GrafanaPerformanceTracking on GrafanaFaroHandler {
  void startTracking(String key, String name) {
    Faro().markEventStart(key, name);
  }

  void endTracking(String key, String name, {Map<String, Object?> context = const {}}) {
    Faro().markEventEnd(key, name, attributes: _stringifyContext(context));
  }

  Map<String, String> _stringifyContext(Map<String, Object?> ctx) =>
      ctx.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}
```

### Example usage in a datasource

```dart
Future<User> fetchUserProfile(String userId) async {
  final handler = AppLogger.handler as GrafanaFaroHandler?;
  handler?.startTracking('api', 'fetch_user_profile');

  try {
    final response = await _client.get('/users/$userId');
    return User.fromJson(response.data);
  } finally {
    handler?.endTracking('api', 'fetch_user_profile', context: {'user_id': userId});
  }
}
```

---

## Custom Session Attributes (Optional)

> This section is optional. The mandatory configuration is in [Initialization in main.dart](#initialization-in-maindart-for-grafana-faro).
> `sessionAttributes` are useful only when you need to segment data or add custom metadata.

Add custom attributes to all session data. These are combined with automatically
collected attributes (SDK version, Dart version, device info, etc.):

```dart
Faro().runApp(
  optionsConfiguration: FaroConfig(
    appName: Env.appName,
    appVersion: Env.appVersion,
    appEnv: 'prod',
    apiKey: Env.faroApiKey,
    collectorUrl: Env.faroCollectorUrl,
    sessionAttributes: {
      'team': 'mobile',
      'department': 'engineering',
      'environment': 'production',
      'cost_center': 1234,    // int — preserved for numeric queries
      'is_beta_user': true,   // bool — preserved as boolean
    },
  ),
  appRunner: () => runApp(const MyApp()),
);
```

### Type handling

Session attributes support typed values (`String`, `int`, `double`, `bool`):

| Context | Behaviour |
|---|---|
| **Faro session** (`meta.session.attributes`) | Values converted to String per the Faro protocol |
| **Span resources** (`resource.attributes`) | Types preserved (`int`, `double`, `bool`, `String`), enabling numeric queries and filtering in trace backends |

---

## Initialization in `main.dart` for Grafana Faro

Faro requires wrapping `runApp()` with its own runner:

```dart
// main_prod.dart (when activeProvider == LogProvider.grafana)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable HTTP tracking
  HttpOverrides.global = FaroHttpOverrides(HttpOverrides.current);

  // Register global error handlers
  GlobalErrorHandler.initialize();

  // Faro wraps runApp with its own configuration
  Faro().runApp(
    optionsConfiguration: FaroConfig(
      appName: Env.appName,
      appVersion: Env.appVersion,
      appEnv: 'prod',
      apiKey: Env.faroApiKey,
      collectorUrl: Env.faroCollectorUrl,
      collectorHeaders: {
        // Custom headers if needed
      },
    ),
    appRunner: () async {
      // Initialize logger AFTER Faro
      await LoggerConfig.initialize(AppFlavor.prod);

      runApp(
        DefaultAssetBundle(
          bundle: FaroAssetBundle(),
          child: FaroUserInteractionWidget(child: const MyApp()),
        ),
      );
    },
  );
}
```
