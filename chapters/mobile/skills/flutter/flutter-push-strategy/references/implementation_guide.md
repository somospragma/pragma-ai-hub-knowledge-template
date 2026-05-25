# Push Notifications — Implementation Guide

See also: `flutter-background-processing` skill for WorkManager and background isolate patterns.

## Overview

This skill covers the complete push notification lifecycle in Flutter:
permission handling, token management, foreground/background/terminated message states,
local notification display, deep link navigation from taps, and topic subscriptions.

The architecture uses a **Strategy pattern** so the push provider (FCM, OneSignal, custom)
can be swapped without touching domain or presentation layers.

## Recommended Stack

- Dart 3.5+ / Flutter 3.24+
- firebase_messaging 14.7.0 (FCM provider)
- onesignal_flutter (OneSignal provider — alternative)
- flutter_local_notifications 17.x
- flutter_bloc 9.1.1
- GetIt 9.2.1 + Injectable 3.0.0
- Freezed 3.2.5 / freezed_annotation 3.1.0
- fpdart 1.2.0
- Mocktail 1.0.5

## Dependencies

```yaml
dependencies:
  firebase_messaging: ^14.7.0
  firebase_core: ^3.6.0
  flutter_local_notifications: ^17.0.0
  flutter_bloc: ^9.1.1
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
  fpdart: ^1.2.0

  # Alternative provider — add only if using OneSignal
  # onesignal_flutter: ^5.x.x

dev_dependencies:
  build_runner: ^2.14.1
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
  mocktail: ^1.0.5
```

## Architecture

```
lib/
├── core/
│   ├── di/
│   │   ├── injection.dart
│   │   └── injection.config.dart
│   └── notifications/
│       └── push_background_handler.dart   # top-level entry points (provider-specific)
├── features/
│   └── push_notifications/
│       ├── domain/
│       │   ├── entities/
│       │   │   ├── push_message.dart
│       │   │   └── push_failure.dart
│       │   ├── repositories/
│       │   │   └── push_notification_repository.dart   # abstract interface class
│       │   └── usecases/
│       │       ├── initialize_push_usecase.dart
│       │       ├── request_permission_usecase.dart
│       │       ├── get_push_token_usecase.dart
│       │       ├── subscribe_to_topic_usecase.dart
│       │       ├── unsubscribe_from_topic_usecase.dart
│       │       └── process_background_message_usecase.dart
│       ├── data/
│       │   ├── datasources/
│       │   │   ├── push_provider.dart              # abstract interface class (Strategy)
│       │   │   ├── fcm_push_provider.dart
│       │   │   └── onesignal_push_provider.dart
│       │   └── repositories/
│       │       └── push_notification_repository_impl.dart
│       └── presentation/
│           └── bloc/
│               ├── notification_bloc.dart
│               ├── notification_event.dart
│               └── notification_state.dart
```

## 1. Domain Layer

### Entities

```dart
// lib/features/push_notifications/domain/entities/push_message.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_message.freezed.dart';

@freezed
class PushMessage with _$PushMessage {
  const factory PushMessage({
    required String id,
    String? title,
    String? body,
    String? imageUrl,
    required Map<String, dynamic> data,
    required PushMessageType type,
    DateTime? sentAt,
  }) = _PushMessage;

  // Normalize FCM RemoteMessage → PushMessage
  factory PushMessage.fromFcm(RemoteMessage message) => PushMessage(
    id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: message.notification?.title,
    body: message.notification?.body,
    imageUrl: message.notification?.android?.imageUrl
        ?? message.notification?.apple?.imageUrl,
    data: message.data,
    type: message.notification == null
        ? PushMessageType.data
        : PushMessageType.notification,
    sentAt: message.sentTime,
  );

  // Normalize OneSignal OSNotification → PushMessage
  factory PushMessage.fromOneSignal(OSNotification notification) => PushMessage(
    id: notification.notificationId,
    title: notification.title,
    body: notification.body,
    imageUrl: notification.bigPicture,
    data: notification.additionalData?.cast<String, dynamic>() ?? {},
    type: PushMessageType.notification,
  );
}

enum PushMessageType { notification, data }
```

```dart
// lib/features/push_notifications/domain/entities/push_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'push_failure.freezed.dart';

@freezed
class PushFailure with _$PushFailure {
  const factory PushFailure.permissionDenied() = PermissionDenied;
  const factory PushFailure.initializationFailed({required String message}) = InitializationFailed;
  const factory PushFailure.tokenFetchFailed({required String message}) = TokenFetchFailed;
  const factory PushFailure.topicSubscriptionFailed({
    required String topic,
    required String message,
  }) = TopicSubscriptionFailed;
  const factory PushFailure.unknown({required String message}) = UnknownPushFailure;
}
```

### Repository Interface

```dart
// lib/features/push_notifications/domain/repositories/push_notification_repository.dart
import 'package:fpdart/fpdart.dart';

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

### Use Cases

```dart
// lib/features/push_notifications/domain/usecases/initialize_push_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class InitializePushUseCase {
  final PushNotificationRepository _repository;
  InitializePushUseCase(this._repository);

  Future<Either<PushFailure, Unit>> call() => _repository.initialize();
}

// lib/features/push_notifications/domain/usecases/request_permission_usecase.dart
@injectable
class RequestPermissionUseCase {
  final PushNotificationRepository _repository;
  RequestPermissionUseCase(this._repository);

  Future<Either<PushFailure, bool>> call() => _repository.requestPermission();
}

// lib/features/push_notifications/domain/usecases/get_push_token_usecase.dart
@injectable
class GetPushTokenUseCase {
  final PushNotificationRepository _repository;
  GetPushTokenUseCase(this._repository);

  Future<Either<PushFailure, String>> call() => _repository.getToken();
}

// lib/features/push_notifications/domain/usecases/subscribe_to_topic_usecase.dart
@injectable
class SubscribeToTopicUseCase {
  final PushNotificationRepository _repository;
  SubscribeToTopicUseCase(this._repository);

  Future<Either<PushFailure, Unit>> call(String topic) =>
      _repository.subscribeToTopic(topic);
}

// lib/features/push_notifications/domain/usecases/unsubscribe_from_topic_usecase.dart
@injectable
class UnsubscribeFromTopicUseCase {
  final PushNotificationRepository _repository;
  UnsubscribeFromTopicUseCase(this._repository);

  Future<Either<PushFailure, Unit>> call(String topic) =>
      _repository.unsubscribeFromTopic(topic);
}

// lib/features/push_notifications/domain/usecases/process_background_message_usecase.dart
// Called from the top-level background handler — runs in a background isolate
@injectable
class ProcessBackgroundMessageUseCase {
  final LocalNotificationService _localNotifications;

  ProcessBackgroundMessageUseCase(this._localNotifications);

  Future<void> call(PushMessage message) async {
    if (message.type == PushMessageType.data) {
      // Silent data message — process without showing notification
      await _handleDataMessage(message.data);
      return;
    }
    await _localNotifications.show(
      title: message.title ?? '',
      body: message.body ?? '',
      data: message.data,
      imageUrl: message.imageUrl,
    );
  }

  Future<void> _handleDataMessage(Map<String, dynamic> data) async {
    // e.g., trigger a sync, update local cache
  }
}
```

## 2. Data Layer — Strategy Pattern

### Strategy Interface

```dart
// lib/features/push_notifications/data/datasources/push_provider.dart
import 'package:fpdart/fpdart.dart';

// Each push provider implements this interface.
// The repository delegates all calls to the injected strategy.
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

### FCM Provider

```dart
// lib/features/push_notifications/data/datasources/fcm_push_provider.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: PushProvider, env: ['fcm', Environment.prod])
class FcmPushProvider implements PushProvider {
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  FcmPushProvider(this._messaging, this._localNotifications);

  @override
  Future<Either<PushFailure, Unit>> initialize() async {
    try {
      // Create high-importance Android notification channel
      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        importance: Importance.max,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Configure foreground notification presentation (iOS)
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false, // We handle display ourselves via local notifications
        badge: true,
        sound: false,
      );

      // Listen for token refresh and notify server
      _messaging.onTokenRefresh.listen(_onTokenRefresh);

      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.initializationFailed(message: '$e'));
    }
  }

  void _onTokenRefresh(String token) {
    // Token refreshed — update on server
    // Inject a token repository or use case here if needed
  }

  @override
  Future<Either<PushFailure, bool>> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      return Right(granted);
    } catch (e) {
      return Left(PushFailure.unknown(message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, String>> getToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        return Left(PushFailure.tokenFetchFailed(message: 'FCM token is null'));
      }
      return Right(token);
    } catch (e) {
      return Left(PushFailure.tokenFetchFailed(message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, Unit>> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.topicSubscriptionFailed(topic: topic, message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, Unit>> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.topicSubscriptionFailed(topic: topic, message: '$e'));
    }
  }

  @override
  Stream<PushMessage> get onForegroundMessage =>
      FirebaseMessaging.onMessage.map(PushMessage.fromFcm);

  @override
  Stream<PushMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp.map(PushMessage.fromFcm);

  @override
  Future<PushMessage?> getInitialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message != null ? PushMessage.fromFcm(message) : null;
  }
}
```

### OneSignal Provider

```dart
// lib/features/push_notifications/data/datasources/onesignal_push_provider.dart
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';
import 'dart:async';

@Injectable(as: PushProvider, env: ['onesignal'])
class OneSignalPushProvider implements PushProvider {
  final String _appId;

  final _foregroundController = StreamController<PushMessage>.broadcast();
  final _openedAppController = StreamController<PushMessage>.broadcast();

  OneSignalPushProvider(@Named('oneSignalAppId') this._appId);

  @override
  Future<Either<PushFailure, Unit>> initialize() async {
    try {
      OneSignal.initialize(_appId);

      // Foreground: display notification and emit to stream
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        _foregroundController.add(
          PushMessage.fromOneSignal(event.notification),
        );
        event.notification.display();
      });

      // Notification tapped
      OneSignal.Notifications.addClickListener((event) {
        _openedAppController.add(
          PushMessage.fromOneSignal(event.notification),
        );
      });

      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.initializationFailed(message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, bool>> requestPermission() async {
    try {
      final granted = await OneSignal.Notifications.requestPermission(true);
      return Right(granted);
    } catch (e) {
      return Left(PushFailure.unknown(message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, String>> getToken() async {
    try {
      final token = OneSignal.User.pushSubscription.token;
      if (token == null) {
        return Left(PushFailure.tokenFetchFailed(message: 'OneSignal token is null'));
      }
      return Right(token);
    } catch (e) {
      return Left(PushFailure.tokenFetchFailed(message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, Unit>> subscribeToTopic(String topic) async {
    try {
      // OneSignal uses tags instead of topics
      OneSignal.User.addTagWithKey('topic_$topic', 'true');
      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.topicSubscriptionFailed(topic: topic, message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, Unit>> unsubscribeFromTopic(String topic) async {
    try {
      OneSignal.User.removeTag('topic_$topic');
      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.topicSubscriptionFailed(topic: topic, message: '$e'));
    }
  }

  @override
  Stream<PushMessage> get onForegroundMessage => _foregroundController.stream;

  @override
  Stream<PushMessage> get onMessageOpenedApp => _openedAppController.stream;

  @override
  Future<PushMessage?> getInitialMessage() async {
    // OneSignal does not expose a direct equivalent — handle via click listener
    return null;
  }
}
```

### Repository Implementation

```dart
// lib/features/push_notifications/data/repositories/push_notification_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: PushNotificationRepository)
class PushNotificationRepositoryImpl implements PushNotificationRepository {
  final PushProvider _provider;

  PushNotificationRepositoryImpl(this._provider);

  @override
  Future<Either<PushFailure, Unit>> initialize() => _provider.initialize();

  @override
  Future<Either<PushFailure, bool>> requestPermission() =>
      _provider.requestPermission();

  @override
  Future<Either<PushFailure, String>> getToken() => _provider.getToken();

  @override
  Future<Either<PushFailure, Unit>> subscribeToTopic(String topic) =>
      _provider.subscribeToTopic(topic);

  @override
  Future<Either<PushFailure, Unit>> unsubscribeFromTopic(String topic) =>
      _provider.unsubscribeFromTopic(topic);

  @override
  Stream<PushMessage> get onForegroundMessage => _provider.onForegroundMessage;

  @override
  Stream<PushMessage> get onMessageOpenedApp => _provider.onMessageOpenedApp;

  @override
  Future<PushMessage?> getInitialMessage() => _provider.getInitialMessage();
}
```

## 3. Presentation Layer — NotificationBloc

```dart
// lib/features/push_notifications/presentation/bloc/notification_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';
import 'dart:async';

part 'notification_bloc.freezed.dart';
part 'notification_event.dart';
part 'notification_state.dart';

@injectable
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final InitializePushUseCase _initializeUseCase;
  final RequestPermissionUseCase _permissionUseCase;
  final GetPushTokenUseCase _tokenUseCase;
  final SubscribeToTopicUseCase _subscribeUseCase;
  final UnsubscribeFromTopicUseCase _unsubscribeUseCase;
  final PushNotificationRepository _repository;

  StreamSubscription<PushMessage>? _foregroundSub;
  StreamSubscription<PushMessage>? _openedAppSub;

  NotificationBloc(
    this._initializeUseCase,
    this._permissionUseCase,
    this._tokenUseCase,
    this._subscribeUseCase,
    this._unsubscribeUseCase,
    this._repository,
  ) : super(const NotificationState.initial()) {
    on<InitializeNotificationsEvent>(_onInitialize);
    on<RequestPermissionEvent>(_onRequestPermission);
    on<FetchTokenEvent>(_onFetchToken);
    on<SubscribeToTopicEvent>(_onSubscribeToTopic);
    on<UnsubscribeFromTopicEvent>(_onUnsubscribeFromTopic);
    on<ForegroundMessageReceivedEvent>(_onForegroundMessageReceived);
    on<NotificationTappedEvent>(_onNotificationTapped);
    on<ResetNotificationEvent>(_onReset);
  }

  Future<void> _onInitialize(
    InitializeNotificationsEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _initializeUseCase();

    await result.fold(
      (failure) async => emit(NotificationState.error(_mapFailure(failure))),
      (_) async {
        // Subscribe to foreground messages
        _foregroundSub = _repository.onForegroundMessage.listen(
          (message) => add(NotificationEvent.foregroundMessageReceived(message)),
        );

        // Subscribe to notification taps (background → app opened)
        _openedAppSub = _repository.onMessageOpenedApp.listen(
          (message) => add(NotificationEvent.notificationTapped(message)),
        );

        emit(const NotificationState.initialized());

        // Check if app was launched from a terminated-state notification
        final initialMessage = await _repository.getInitialMessage();
        if (initialMessage != null) {
          add(NotificationEvent.notificationTapped(initialMessage));
        }
      },
    );
  }

  Future<void> _onRequestPermission(
    RequestPermissionEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _permissionUseCase();
    result.fold(
      (failure) => emit(NotificationState.error(_mapFailure(failure))),
      (granted) => emit(granted
          ? const NotificationState.permissionGranted()
          : const NotificationState.permissionDenied()),
    );
  }

  Future<void> _onFetchToken(
    FetchTokenEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _tokenUseCase();
    result.fold(
      (failure) => emit(NotificationState.error(_mapFailure(failure))),
      (token) => emit(NotificationState.tokenReceived(token: token)),
    );
  }

  Future<void> _onSubscribeToTopic(
    SubscribeToTopicEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _subscribeUseCase(event.topic);
    result.fold(
      (failure) => emit(NotificationState.error(_mapFailure(failure))),
      (_) => emit(NotificationState.topicSubscribed(topic: event.topic)),
    );
  }

  Future<void> _onUnsubscribeFromTopic(
    UnsubscribeFromTopicEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _unsubscribeUseCase(event.topic);
    result.fold(
      (failure) => emit(NotificationState.error(_mapFailure(failure))),
      (_) => emit(NotificationState.topicUnsubscribed(topic: event.topic)),
    );
  }

  void _onForegroundMessageReceived(
    ForegroundMessageReceivedEvent event,
    Emitter<NotificationState> emit,
  ) {
    emit(NotificationState.foregroundMessageReceived(message: event.message));
  }

  void _onNotificationTapped(
    NotificationTappedEvent event,
    Emitter<NotificationState> emit,
  ) {
    // Emit the tapped message — the UI layer handles navigation
    // using the message.data payload (e.g., deep link route)
    emit(NotificationState.notificationTapped(message: event.message));
  }

  void _onReset(ResetNotificationEvent event, Emitter<NotificationState> emit) {
    emit(const NotificationState.initial());
  }

  String _mapFailure(PushFailure failure) => failure.when(
    permissionDenied: () => 'Notification permission denied',
    initializationFailed: (message) => 'Initialization failed: $message',
    tokenFetchFailed: (message) => 'Token fetch failed: $message',
    topicSubscriptionFailed: (topic, message) =>
        'Topic "$topic" subscription failed: $message',
    unknown: (message) => 'Unknown error: $message',
  );

  @override
  Future<void> close() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    return super.close();
  }
}

// notification_event.dart
part of 'notification_bloc.dart';

@freezed
class NotificationEvent with _$NotificationEvent {
  const factory NotificationEvent.initialize() = InitializeNotificationsEvent;
  const factory NotificationEvent.requestPermission() = RequestPermissionEvent;
  const factory NotificationEvent.fetchToken() = FetchTokenEvent;
  const factory NotificationEvent.subscribeToTopic(String topic) = SubscribeToTopicEvent;
  const factory NotificationEvent.unsubscribeFromTopic(String topic) = UnsubscribeFromTopicEvent;
  const factory NotificationEvent.foregroundMessageReceived(PushMessage message) = ForegroundMessageReceivedEvent;
  const factory NotificationEvent.notificationTapped(PushMessage message) = NotificationTappedEvent;
  const factory NotificationEvent.reset() = ResetNotificationEvent;
}

// notification_state.dart
part of 'notification_bloc.dart';

@freezed
class NotificationState with _$NotificationState {
  const factory NotificationState.initial() = NotificationInitial;
  const factory NotificationState.initialized() = NotificationInitialized;
  const factory NotificationState.permissionGranted() = NotificationPermissionGranted;
  const factory NotificationState.permissionDenied() = NotificationPermissionDenied;
  const factory NotificationState.tokenReceived({required String token}) = NotificationTokenReceived;
  const factory NotificationState.topicSubscribed({required String topic}) = NotificationTopicSubscribed;
  const factory NotificationState.topicUnsubscribed({required String topic}) = NotificationTopicUnsubscribed;
  const factory NotificationState.foregroundMessageReceived({required PushMessage message}) = NotificationForegroundMessageReceived;
  const factory NotificationState.notificationTapped({required PushMessage message}) = NotificationTapped;
  const factory NotificationState.error(String message) = NotificationError;
}
```

## 4. Deep Link Navigation from Notification Tap

When a notification is tapped, `message.data` carries the route payload.
The BLoC emits `NotificationState.notificationTapped` and the UI layer
(or a listener in the router) handles navigation.

```dart
// lib/core/notifications/notification_navigation_listener.dart
// Place this as a BlocListener at the root of the widget tree,
// above MaterialApp.router, so it can navigate from any state.

class NotificationNavigationListener extends StatelessWidget {
  final Widget child;
  const NotificationNavigationListener({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return BlocListener<NotificationBloc, NotificationState>(
      listenWhen: (_, current) => current is NotificationTapped,
      listener: (context, state) {
        if (state is NotificationTapped) {
          _handleNavigation(context, state.message);
        }
      },
      child: child,
    );
  }

  void _handleNavigation(BuildContext context, PushMessage message) {
    final route = message.data['route'] as String?;
    final id = message.data['id'] as String?;

    if (route == null) return;

    // Use go_router — see flutter-deep-link-strategy skill for full patterns
    final router = GoRouter.of(context);

    switch (route) {
      case 'product':
        router.go('/product/$id');
      case 'profile':
        router.go('/profile/$id');
      case 'order':
        router.go('/order/$id');
      default:
        router.go('/home');
    }
  }
}

// Usage in main widget tree:
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<NotificationBloc>()
        ..add(const NotificationEvent.initialize()),
      child: NotificationNavigationListener(
        child: MaterialApp.router(
          routerConfig: GetIt.instance<AppRouter>().router,
        ),
      ),
    );
  }
}
```

## 5. Background Handler Entry Point

```dart
// lib/core/notifications/push_background_handler.dart
// Provider-specific top-level functions.
// Keep these thin — delegate immediately to ProcessBackgroundMessageUseCase.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get_it/get_it.dart';
import '../di/injection.dart';
import '../../firebase_options.dart';

// FCM background handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await configureDependencies();

  final useCase = GetIt.instance<ProcessBackgroundMessageUseCase>();
  await useCase(PushMessage.fromFcm(message));
}

// OneSignal background handler (if using OneSignal)
// @pragma('vm:entry-point')
// void oneSignalBackgroundHandler(OSNotificationReceivedEvent event) {
//   configureDependencies().then((_) async {
//     final useCase = GetIt.instance<ProcessBackgroundMessageUseCase>();
//     await useCase(PushMessage.fromOneSignal(event.notification));
//     event.complete(event.notification);
//   });
// }
```

## 6. App Initialization

```dart
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'core/notifications/push_background_handler.dart';
import 'core/di/injection.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Select provider at build time: flutter run --dart-define=PUSH_PROVIDER=fcm
  const pushProvider = String.fromEnvironment('PUSH_PROVIDER', defaultValue: 'fcm');

  if (pushProvider == 'fcm') {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Must be registered before runApp — top-level function required
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  // OneSignal is initialized inside OneSignalPushProvider.initialize()
  // No global setup needed here for OneSignal

  await configureDependencies();
  runApp(const MyApp());
}
```

## 7. Dependency Injection

```dart
// lib/core/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async => getIt.init();
```

```dart
// lib/core/di/push_provider_module.dart
// Resolves the active PushProvider strategy at runtime based on dart-define.
import 'package:injectable/injectable.dart';

@module
abstract class PushProviderModule {
  @singleton
  PushProvider pushProvider(
    FcmPushProvider fcm,
    OneSignalPushProvider oneSignal,
  ) {
    const provider = String.fromEnvironment('PUSH_PROVIDER', defaultValue: 'fcm');
    return switch (provider) {
      'onesignal' => oneSignal,
      _ => fcm,
    };
  }
}

// Firebase module — registers FirebaseMessaging as a singleton
@module
abstract class FirebaseModule {
  @singleton
  FirebaseMessaging get messaging => FirebaseMessaging.instance;
}
```

## 8. Platform Configuration

### Android — AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application ...>

        <!-- FCM default notification channel (Android 8+) -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="high_importance_channel" />

        <!-- FCM default notification icon -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_notification" />

        <!-- FCM default notification color -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_color"
            android:resource="@color/notification_color" />

    </application>
</manifest>
```

### iOS — Info.plist

```xml
<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
</array>

<!-- Disable Firebase method swizzling if using other notification plugins -->
<!-- <key>FirebaseAppDelegateProxyEnabled</key> -->
<!-- <false/> -->
```

### iOS — AppDelegate.swift (if method swizzling is disabled)

```swift
import UIKit
import Flutter
import FirebaseMessaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Required when FirebaseAppDelegateProxyEnabled = false
    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
```

## 9. Testing Strategy

### Unit Tests — UseCase

```dart
// test/features/push_notifications/domain/usecases/request_permission_usecase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockPushNotificationRepository extends Mock
    implements PushNotificationRepository {}

void main() {
  late RequestPermissionUseCase useCase;
  late MockPushNotificationRepository mockRepository;

  setUp(() {
    mockRepository = MockPushNotificationRepository();
    useCase = RequestPermissionUseCase(mockRepository);
  });

  group('RequestPermissionUseCase', () {
    test('returns true when permission is granted', () async {
      when(() => mockRepository.requestPermission())
          .thenAnswer((_) async => const Right(true));

      final result = await useCase();

      expect(result, const Right(true));
      verify(() => mockRepository.requestPermission()).called(1);
    });

    test('returns false when permission is denied', () async {
      when(() => mockRepository.requestPermission())
          .thenAnswer((_) async => const Right(false));

      final result = await useCase();

      expect(result, const Right(false));
    });

    test('returns failure when an error occurs', () async {
      const failure = PushFailure.unknown(message: 'Platform error');
      when(() => mockRepository.requestPermission())
          .thenAnswer((_) async => const Left(failure));

      final result = await useCase();

      expect(result, const Left(failure));
    });
  });
}
```

### BLoC Tests

```dart
// test/features/push_notifications/presentation/bloc/notification_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockInitializePushUseCase extends Mock implements InitializePushUseCase {}
class MockRequestPermissionUseCase extends Mock implements RequestPermissionUseCase {}
class MockGetPushTokenUseCase extends Mock implements GetPushTokenUseCase {}
class MockSubscribeToTopicUseCase extends Mock implements SubscribeToTopicUseCase {}
class MockUnsubscribeFromTopicUseCase extends Mock implements UnsubscribeFromTopicUseCase {}
class MockPushNotificationRepository extends Mock implements PushNotificationRepository {}

void main() {
  late NotificationBloc bloc;
  late MockInitializePushUseCase mockInitialize;
  late MockRequestPermissionUseCase mockPermission;
  late MockGetPushTokenUseCase mockToken;
  late MockSubscribeToTopicUseCase mockSubscribe;
  late MockUnsubscribeFromTopicUseCase mockUnsubscribe;
  late MockPushNotificationRepository mockRepository;

  setUp(() {
    mockInitialize = MockInitializePushUseCase();
    mockPermission = MockRequestPermissionUseCase();
    mockToken = MockGetPushTokenUseCase();
    mockSubscribe = MockSubscribeToTopicUseCase();
    mockUnsubscribe = MockUnsubscribeFromTopicUseCase();
    mockRepository = MockPushNotificationRepository();

    when(() => mockRepository.onForegroundMessage)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockRepository.onMessageOpenedApp)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockRepository.getInitialMessage())
        .thenAnswer((_) async => null);

    bloc = NotificationBloc(
      mockInitialize,
      mockPermission,
      mockToken,
      mockSubscribe,
      mockUnsubscribe,
      mockRepository,
    );
  });

  tearDown(() => bloc.close());

  group('NotificationBloc', () {
    blocTest<NotificationBloc, NotificationState>(
      'emits [initialized] when initialization succeeds',
      build: () {
        when(() => mockInitialize()).thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(const NotificationEvent.initialize()),
      expect: () => [const NotificationState.initialized()],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [error] when initialization fails',
      build: () {
        when(() => mockInitialize()).thenAnswer(
          (_) async => const Left(
            PushFailure.initializationFailed(message: 'Firebase not configured'),
          ),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(const NotificationEvent.initialize()),
      expect: () => [
        const NotificationState.error(
          'Initialization failed: Firebase not configured',
        ),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [permissionGranted] when permission is granted',
      build: () {
        when(() => mockPermission()).thenAnswer((_) async => const Right(true));
        return bloc;
      },
      act: (bloc) => bloc.add(const NotificationEvent.requestPermission()),
      expect: () => [const NotificationState.permissionGranted()],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [permissionDenied] when permission is denied',
      build: () {
        when(() => mockPermission()).thenAnswer((_) async => const Right(false));
        return bloc;
      },
      act: (bloc) => bloc.add(const NotificationEvent.requestPermission()),
      expect: () => [const NotificationState.permissionDenied()],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [tokenReceived] with token string',
      build: () {
        when(() => mockToken())
            .thenAnswer((_) async => const Right('fcm-token-abc123'));
        return bloc;
      },
      act: (bloc) => bloc.add(const NotificationEvent.fetchToken()),
      expect: () => [
        const NotificationState.tokenReceived(token: 'fcm-token-abc123'),
      ],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [topicSubscribed] when subscribing to a topic',
      build: () {
        when(() => mockSubscribe('news'))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(const NotificationEvent.subscribeToTopic('news')),
      expect: () => [const NotificationState.topicSubscribed(topic: 'news')],
    );

    blocTest<NotificationBloc, NotificationState>(
      'emits [notificationTapped] when a notification is tapped',
      build: () => bloc,
      act: (bloc) => bloc.add(NotificationEvent.notificationTapped(
        const PushMessage(
          id: 'msg-1',
          title: 'Hello',
          body: 'World',
          data: {'route': 'product', 'id': '42'},
          type: PushMessageType.notification,
        ),
      )),
      expect: () => [
        NotificationState.notificationTapped(
          message: const PushMessage(
            id: 'msg-1',
            title: 'Hello',
            body: 'World',
            data: {'route': 'product', 'id': '42'},
            type: PushMessageType.notification,
          ),
        ),
      ],
    );
  });
}
```

## 10. Best Practices

### Permission
- Never request permission on app launch — wait for a meaningful moment in the UX
- On iOS, the system dialog can only be shown once; guide users to Settings if denied
- On Android 13+, `POST_NOTIFICATIONS` must be requested at runtime

### Token Management
- Always send the token to your backend after `initialize()` and on `onTokenRefresh`
- Tokens can change — handle refresh by re-registering with the server
- Delete the token on logout: `FirebaseMessaging.instance.deleteToken()`

### Provider Strategy
- Domain and presentation layers must never import provider-specific packages
- Normalize provider messages into `PushMessage` at the data source boundary
- Use `dart-define` to select the provider at build time without code changes
- If the project uses multiple providers simultaneously, resolve per platform inside `PushProviderModule`

### Notification Data Payload
- Always include a `route` key in the data payload for navigation
- Keep payloads small — fetch full content from the API after navigation
- Use consistent key names across all notification types

### Message Handling Matrix

| App State | Notification message | Data-only message |
|---|---|---|
| Foreground | `onForegroundMessage` → show local notification | `onForegroundMessage` → process silently |
| Background | System tray (auto) + background handler | Background handler only |
| Terminated | System tray (auto) + background handler | Background handler only |
| Tapped (background) | `onMessageOpenedApp` → navigate | — |
| Tapped (terminated) | `getInitialMessage()` → navigate | — |

> This matrix applies to FCM. Other providers have equivalent concepts normalized by their `PushProvider` implementation.
