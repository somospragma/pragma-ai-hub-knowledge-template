---
name: flutter-background-processing
description: >
  Implements background tasks with WorkManager 0.5.x and push message background handling using a Strategy pattern to support multiple providers (FCM, OneSignal, custom), clean architecture, fpdart, and modern Flutter patterns.
commands:
  - setup-background-tasks
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the full background processing setup (WorkManager dispatcher, push background handler, platform config), "audit" checks existing background implementation for missing pragmas, incorrect isolate DI, or platform config gaps.
    required: true
  - name: target
    description: Path to the core/background directory or project root (e.g. lib/core/background/ for implement, . for audit including platform files).
    required: true
  - name: tasks
    description: Comma-separated list of background task types to implement (workmanager, push-background, both). Defaults to both.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Background Processing

See `references/implementation_guide.md` for complete patterns and code examples.

## Quick Reference

This skill provides background processing implementation patterns for Flutter following
clean architecture with modern functional programming. All code examples use:

- Dart 3.5+ / Flutter 3.24+
- workmanager 0.5.x for scheduled background tasks (Android + iOS)
- firebase_messaging 14.7.0 — FCM provider (default)
- onesignal_flutter — OneSignal provider (alternative)
- flutter_bloc 9.1.1 for state management
- GetIt 9.2.1 + Injectable 3.0.0 for dependency injection
- Freezed 3.2.5 for immutable data classes
- fpdart 1.2.0 for functional error handling
- Mocktail 1.0.5 for testing

## Core Features

### 1. WorkManager — Scheduled Background Tasks
- One-off tasks (immediate or deferred)
- Periodic tasks (minimum 15-minute interval)
- Constraints: network, battery, storage
- Input/output data passing
- Task cancellation and status tracking

### 2. Push Notifications — Strategy Pattern
FCM is the default provider, but the architecture supports swapping or combining providers
without touching domain or presentation layers.

| Provider | Package | Notes |
|---|---|---|
| FCM | `firebase_messaging 14.7.0` | Default, Google infrastructure |
| OneSignal | `onesignal_flutter` | Multi-platform dashboard |
| AWS Pinpoint | `amplify_push_notifications_pinpoint` | AWS ecosystem |
| Custom | — | WebSocket / MQTT, full control |

The active provider is selected at build time via `--dart-define=PUSH_PROVIDER=fcm`.

### 3. Clean Architecture Integration
```
Domain (PushMessage entity, PushNotificationRepository interface, UseCases)
  ↓
Data (PushProvider strategy interface → FcmPushProvider / OneSignalPushProvider)
  ↓
Presentation (NotificationBloc — provider-agnostic)
  ↓
Background (top-level entry points — provider-specific, thin wrappers)
```

All dependencies injected via GetIt + Injectable.  
Errors returned as `Either<PushFailure, T>` / `Either<BackgroundFailure, T>` using fpdart.

## Key Constraints

| Concern | Rule |
|---|---|
| WorkManager dispatcher | Must be a top-level `@pragma('vm:entry-point')` function |
| Push background handler | Must be a top-level `@pragma('vm:entry-point')` function — provider-specific signature |
| Background isolate DI | Must call `configureDependencies()` independently — no shared state with main isolate |
| Provider imports | Only the data layer imports provider packages — never domain or presentation |
| iOS periodic tasks | Minimum interval is OS-controlled; WorkManager schedules best-effort |

## Key Implementation Patterns

### WorkManager Dispatcher (top-level)
```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    await configureDependencies();
    final useCase = GetIt.instance<ExecuteBackgroundTaskUseCase>();
    final result = await useCase(BackgroundTaskInput(
      taskName: taskName,
      data: inputData ?? {},
    ));
    return result.fold((_) => false, (_) => true);
  });
}
```

### Push Background Handler (provider-specific, thin)
```dart
// FCM
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await configureDependencies();
  await GetIt.instance<ProcessBackgroundMessageUseCase>()(
    PushMessage.fromFcm(message),
  );
}
```

### Strategy Interface (data layer)
```dart
abstract interface class PushProvider {
  Future<Either<PushFailure, Unit>> initialize();
  Future<Either<PushFailure, bool>> requestPermission();
  Future<Either<PushFailure, String>> getToken();
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> getInitialMessage();
}
```

### Domain Repository
```dart
abstract interface class PushNotificationRepository {
  Future<Either<PushFailure, Unit>> initialize();
  Future<Either<PushFailure, bool>> requestPermission();
  Future<Either<PushFailure, String>> getToken();
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> getInitialMessage();
}
```

## Platform Setup Summary

### Android
- `minSdkVersion 23` required
- Disable WorkManager auto-init in `AndroidManifest.xml`
- Request `RECEIVE_BOOT_COMPLETED` and `POST_NOTIFICATIONS` permissions

### iOS
- Enable **Background Modes**: Background fetch + Remote notifications + Background processing
- Register background task identifiers in `Info.plist`
- Register tasks in `AppDelegate.swift`

## Testing Strategy

- **Unit Tests**: UseCases and Repository logic with Mocktail
- **BLoC Tests**: State transitions with bloc_test — `NotificationBloc` is provider-agnostic
- **Provider Tests**: Test each `PushProvider` implementation independently
- Avoid testing top-level dispatcher/handler directly — test the UseCases they delegate to

## Reference Files

- `references/implementation_guide.md` — Complete implementation with code examples, platform setup, and testing strategies
