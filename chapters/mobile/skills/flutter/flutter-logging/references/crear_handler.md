# Adding a New Handler

To add a new service (e.g. Amplitude, Mixpanel), follow these steps:

---

## Step 1: Add dependencies

```bash
flutter pub add amplitude_flutter
flutter pub upgrade --major-versions amplitude_flutter
flutter pub outdated
```

---

## Step 2: Implement the handler

```dart
// handlers/amplitude_handler.dart
final class AmplitudeHandler implements LogHandler {
  const AmplitudeHandler({required this.apiKey});
  final String apiKey;

  @override String get name => 'amplitude';

  @override Future<void> initialize() async { /* SDK setup */ }

  @override
  Future<void> log(LogEvent event) async {
    // Each handler decides which categories to process.
    // Amplitude typically only wants business events.
    if (event.category != LogCategory.business) return;
    // ... send event to Amplitude
  }

  @override Future<void> dispose() async {}
}
```

---

## Step 3: Add to the `LogProvider` enum

In `logger_config.dart`:

```dart
enum LogProvider { crashlytics, sentry, datadog, grafana, amplitude }
```

---

## Step 4: Add a case in `_buildHandler()`

```dart
LogProvider.amplitude => AmplitudeHandler(apiKey: Env.amplitudeKey),
```

---

## Step 5: Set the active provider

```dart
static const LogProvider activeProvider = LogProvider.amplitude;
```

> **Switching providers = changing one line.** Client code (`AppLogger.error()`, etc.) does not change.
