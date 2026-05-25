---
name: flutter-logging
description: >
  Advanced logging skill for Flutter with Dart 3.3+, using the Strategy pattern (GoF) to swap logging handlers (Firebase Crashlytics, Sentry, DataDog, Grafana Faro) without changing client code. Includes a central Logger as the single facade, severity levels, navigation logging, performance metrics, and business events, separated by flavor (dev/staging/prod). Use this skill whenever the user mentions logging, logs, monitoring, Crashlytics, Sentry, DataDog, Grafana, production errors, analytics, API metrics, navigation traces, business events, or wants to configure observability in Flutter. Also applies when the user wants to switch logging services, add a new handler, or decouple logging from a specific provider.
commands:
  - setup-logging
inputs:
  - name: action
    description: Action to perform (implement, add-handler, audit). "implement" generates the full logging architecture (facade, handler interface, config per flavor), "add-handler" adds a new handler for a specific provider, "audit" checks existing logging for direct provider imports, missing structured context, or bare print statements.
    required: true
  - name: target
    description: Path to the core/logging directory or project root (e.g. lib/core/logging/ for implement, lib/ for audit).
    required: true
  - name: provider
    description: Logging provider to implement (crashlytics, sentry, datadog, grafana, console). Required when action is "add-handler".
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Flutter Advanced Logging

Defines the rules and best practices for implementing logging in Flutter applications.

## Design Principles

- **Client code never knows the handler.** `AppLogger` is the only facade — no widget, BLoC, or use case imports Crashlytics, Sentry, or DataDog directly. This allows switching or combining services without touching business logic.
- **Each service is a swappable Strategy.** `LogHandler` defines the contract; `CrashlyticsHandler`, `SentryHandler`, `DataDogHandler`, and `GrafanaHandler` implement it. The Logger maintains **a single active handler** — switching providers is as simple as changing one line in `LoggerConfig`.
- **The environment determines which handler is active.** Dev uses `ConsoleHandler`. Staging and Prod use the chosen provider (Crashlytics, Sentry, DataDog, or Grafana). This decision lives in the configuration layer (`LoggerConfig`), not in the Logger.
- **Logs have semantic type.** A `LogEvent` is not just a String — it carries a level, category (`error`, `navigation`, `performance`, `business`), structured context, and a timestamp. The active handler decides how to process each category based on the service's capabilities.

---

## Project File Structure

```
lib/
├── core/
│   └── logging/
│       ├── app_logger.dart           ← Public facade — single entry point
│       ├── log_event.dart            ← Structured event model
│       ├── log_level.dart            ← Enum: debug, info, warning, error, fatal
│       ├── log_handler.dart          ← Strategy interface (contract for each handler)
│       ├── handlers/
│       │   ├── console_handler.dart     ← Dev: pretty-print to console
│       │   ├── crashlytics_handler.dart ← Firebase Crashlytics
│       │   ├── sentry_handler.dart      ← Sentry
│       │   ├── datadog_handler.dart     ← DataDog
│       │   └── grafana_handler.dart     ← Grafana Faro (HTTP)
├── core/
│   └── config/
│       └── logger_config.dart        ← Which handler is active per flavor
│
└── features/[feature]/
    ├── presentation/
    │   ├── providers/                ← Riverpod: log from Notifiers
    │   └── bloc/                     ← BLoC: log from event handlers
    └── data/datasources/             ← Log network latency and errors
```

---

## Log Flow: from call site to service

```
AppLogger.error() / .info() / .navigation() / .performance()
        ↓  builds structured LogEvent
[Active LogHandler per LoggerConfig]
        ↓  ConsoleHandler (dev) | CrashlyticsHandler | SentryHandler | DataDogHandler | GrafanaHandler
```

---

## Reference Files

Read the corresponding file before generating code for that area:

| What to implement | Reference |
|---|---|
| `LogEvent`, `LogLevel`, `LogHandler` interface (Strategy) | `references/core_models.md` |
| `AppLogger` facade + `LoggerConfig` per flavor | `references/app_logger.md` |
| `ConsoleHandler`, `CrashlyticsHandler`, `SentryHandler`, `DataDogHandler`, `GrafanaHandler` | `references/console_handler.md`, `references/crashlytics_handler.md`, `references/sentry_handler.md`, `references/datadog_handler.md`, `references/grafana_handler.md` |
| Logging from Riverpod, BLoC, datasources, and navigation | `references/integration.md` |
| Adding a new handler for a different service | `references/crear_handler.md` |

---

## Basic Usage from Any Layer

```dart
// Error with structured context (routed to Crashlytics + Sentry)
AppLogger.error(
  'checkout_failed',
  context: {'product_id': id, 'amount': total},
  error: failure,
  stackTrace: stackTrace,
);

// Business event (routed to DataDog + Grafana)
AppLogger.business('purchase_completed', context: {'revenue': 99.9});

// Performance metric (API latency)
AppLogger.performance('api_latency', durationMs: elapsed, context: {'endpoint': '/orders'});

// Navigation (routed to all active handlers)
AppLogger.navigation(from: 'HomeScreen', to: 'CheckoutScreen');
```

---

## Pre-delivery Checklist

- [ ] No widget, BLoC, or use case imports Crashlytics, Sentry, DataDog, or Grafana directly
- [ ] All logs go through `AppLogger` — never bare `debugPrint` or `print` in production
- [ ] **Dependencies always on the latest stable version from pub.dev:**
  1. Before adding any package, check https://pub.dev/packages/<package> to identify the **latest stable published version** (ignore prereleases/dev).
  2. **NEVER auto-run** dependency installation commands. The AI must **show the commands to the user** for manual execution. This prevents installing outdated versions from the AI's cache.
  3. Add with `flutter pub add <package>`.
  4. Run `flutter pub upgrade --major-versions <package>` to allow major version jumps.
  5. Validate with `flutter pub outdated` that the installed version matches the latest stable on pub.dev.
  6. If `pub outdated` shows a version lower than what is published on pub.dev, adjust `environment.sdk` in `pubspec.yaml` or resolve constraint conflicts to reach the most recent version.
- [ ] Use absolute imports with `package:` — never relative imports (`import '../..'`)
- [ ] `LoggerConfig` defines the active handler per flavor — no scattered `if (kDebugMode)` checks
- [ ] Each `LogHandler` implements `dispose()` to release resources when the app closes
- [ ] Error logs always include `error` and `stackTrace` — never just the message
- [ ] Business events use consistent snake_case keys — makes dashboards easier to build
- [ ] In dev, `ConsoleHandler` is active — external services do not receive development noise
- [ ] Switching providers requires only modifying `LoggerConfig.handler` — no other file changes
