---
name: flutter-push-strategy
description: >
  Implements push notifications with a Strategy pattern supporting multiple providers (FCM, OneSignal, custom). Covers permission handling, token management, foreground/ background/terminated states, topic subscriptions, and deep link navigation from notifications. Uses clean architecture, fpdart, and modern Flutter patterns.
commands:
  - setup-push-notification
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the full push notification setup with provider pattern, "audit" checks existing push implementation for missing lifecycle handlers, permission issues, or architecture violations.
    required: true
  - name: target
    description: Path to the feature or core directory where push notifications will be integrated (e.g. lib/features/notifications/ or lib/core/push/).
    required: true
  - name: provider
    description: Push notification provider to use (fcm, onesignal, aws-pinpoint, custom). Defaults to fcm.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Push Notifications Strategy

See `references/implementation_guide.md` for complete patterns and code examples.

## Quick Reference

This skill provides push notification implementation patterns for Flutter following
clean architecture with a Strategy pattern for provider flexibility. All code uses:

- Dart 3.5+ / Flutter 3.24+
- firebase_messaging 14.7.0 — FCM provider (default)
- onesignal_flutter — OneSignal provider (alternative)
- flutter_local_notifications 17.x — local notification display
- flutter_bloc 9.1.1 for state management
- GetIt 9.2.1 + Injectable 3.0.0 for dependency injection
- Freezed 3.2.5 / freezed_annotation 3.1.0 for immutable data classes
- fpdart 1.2.0 for functional error handling
- Mocktail 1.0.5 for testing

## Core Features

### 1. Provider Strategy Pattern
FCM is the default, but the architecture isolates provider-specific code in the data layer.
Domain and presentation layers only know about `PushMessage` — never about FCM or OneSignal.

| Provider | Package | Notes |
|---|---|---|
| FCM | `firebase_messaging 14.7.0` | Default, Google infrastructure |
| OneSignal | `onesignal_flutter` | Multi-platform dashboard, wraps FCM/APNs |
| AWS Pinpoint | `amplify_push_notifications_pinpoint` | AWS ecosystem |
| Custom | — | WebSocket / MQTT, full control |

Provider selected at build time: `--dart-define=PUSH_PROVIDER=fcm`

### 2. Full Push Lifecycle
- Permission request (iOS + Android 13+)
- Token registration and refresh handling
- Foreground message display (local notification)
- Background message processing (top-level handler)
- Terminated state — app opened from notification
- Deep link navigation triggered by notification tap
- Topic subscription / unsubscription

### 3. Clean Architecture Integration
```
Domain (PushMessage, PushNotificationRepository interface, UseCases)
  ↓
Data (PushProvider strategy → FcmPushProvider / OneSignalPushProvider)
  ↓
Presentation (NotificationBloc — provider-agnostic)
```

Errors returned as `Either<PushFailure, T>` using fpdart.

## Key Constraints

| Concern | Rule |
|---|---|
| Provider imports | Only the data layer imports provider packages |
| Background handler | Must be a top-level `@pragma('vm:entry-point')` function |
| Background isolate DI | Must call `configureDependencies()` independently |
| `PushMessage` normalization | Each provider normalizes its format at the data source boundary |
| iOS permissions | Must request at the right moment in the UX flow — not on app launch |
| Token storage | Always persist the token server-side on refresh |

## Key Implementation Patterns

### Strategy Interface (data layer)
```dart
abstract interface class PushProvider {
  Future<Either<PushFailure, Unit>> initialize();
  Future<Either<PushFailure, bool>> requestPermission();
  Future<Either<PushFailure, String>> getToken();
  Future<Either<PushFailure, Unit>> subscribeToTopic(String topic);
  Future<Either<PushFailure, Unit>> unsubscribeFromTopic(String topic);
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
  Future<Either<PushFailure, Unit>> subscribeToTopic(String topic);
  Future<Either<PushFailure, Unit>> unsubscribeFromTopic(String topic);
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> getInitialMessage();
}
```

### Provider-Agnostic PushMessage Entity
```dart
@freezed
class PushMessage with _$PushMessage {
  const factory PushMessage({
    required String id,
    String? title,
    String? body,
    required Map<String, dynamic> data,
    required PushMessageType type,
    DateTime? sentAt,
  }) = _PushMessage;

  // Each provider has its own factory constructor
  factory PushMessage.fromFcm(RemoteMessage m) => ...;
  factory PushMessage.fromOneSignal(OSNotification n) => ...;
}
```

### NotificationBloc (provider-agnostic)
```dart
@injectable
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final PushNotificationRepository _repository;
  // Listens to onForegroundMessage and onMessageOpenedApp streams
  // Handles permission, token, topic subscription, and navigation
}
```

## Message Handling Matrix

| App State | Notification message | Data-only message |
|---|---|---|
| Foreground | `onForegroundMessage` stream → show local notification | `onForegroundMessage` stream → process silently |
| Background | System tray (auto) + background handler | Background handler only |
| Terminated | System tray (auto) + background handler | Background handler only |
| Tapped (background) | `onMessageOpenedApp` stream → navigate | — |
| Tapped (terminated) | `getInitialMessage()` → navigate | — |

> This matrix applies to FCM. Other providers have equivalent concepts normalized by their `PushProvider` implementation.

## Testing Strategy

- **Unit Tests**: UseCases and Repository logic with Mocktail
- **BLoC Tests**: State transitions with bloc_test — fully provider-agnostic
- **Provider Tests**: Test each `PushProvider` implementation independently
- Do not test background top-level handlers directly — test the UseCases they delegate to

## Reference Files

- `references/implementation_guide.md` — Complete implementation with code examples, platform setup, and testing strategies
