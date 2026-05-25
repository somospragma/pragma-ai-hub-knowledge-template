# Background Processing — Implementation Guide

See also: `flutter-app-lifecycle-management` skill for foundational patterns.

## Overview

This skill covers background processing in Flutter using two complementary mechanisms:

1. **WorkManager** — scheduled/deferred tasks that run even when the app is closed
2. **Push message background handler** — reacts to incoming push messages in the background

Both require **top-level functions** with `@pragma('vm:entry-point')` and independent
DI initialization, since they run in a separate Dart isolate.

### Push Provider Options

FCM (Firebase Cloud Messaging) is the most common push provider, but not the only one.
The architecture uses a **Strategy pattern** so the provider can be swapped or combined
without touching domain or presentation layers.

| Provider | Package | Notes |
|---|---|---|
| Firebase Cloud Messaging (FCM) | `firebase_messaging 14.7.0` | Most common, Google infrastructure |
| OneSignal | `onesignal_flutter` | Multi-platform dashboard, wraps FCM/APNs |
| AWS SNS / Pinpoint | `amplify_push_notifications_pinpoint` | AWS ecosystem |
| Custom WebSocket / MQTT | — | Full control, no third-party dependency |

> Regardless of provider, the domain layer always works with the same `PushMessage`
> entity. Only the data source changes.

## Recommended Stack

- Dart 3.5+ / Flutter 3.24+
- workmanager 0.5.x
- firebase_messaging 14.7.0
- flutter_bloc 9.1.1
- GetIt 9.2.1 + Injectable 3.0.0
- Freezed 3.2.5 / freezed_annotation 3.1.0
- fpdart 1.2.0
- Mocktail 1.0.5

## Dependencies

```yaml
dependencies:
  workmanager: ^0.5.2
  firebase_messaging: ^14.7.0
  firebase_core: ^3.6.0
  flutter_bloc: ^9.1.1
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
  fpdart: ^1.2.0
  flutter_local_notifications: ^17.0.0

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
│   │   ├── injection.dart              # configureDependencies()
│   │   └── injection.config.dart       # generated
│   └── background/
│       ├── workmanager_dispatcher.dart # top-level callbackDispatcher
│       └── push_background_handler.dart # top-level pushBackgroundHandler (provider-agnostic)
├── features/
│   ├── push_notifications/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── push_message.dart           # provider-agnostic message entity
│   │   │   │   └── push_failure.dart
│   │   │   ├── repositories/
│   │   │   │   └── push_notification_repository.dart  # abstract interface class
│   │   │   └── usecases/
│   │   │       ├── initialize_push_usecase.dart
│   │   │       ├── request_permission_usecase.dart
│   │   │       └── process_background_message_usecase.dart
│   │   └── data/
│   │       ├── repositories/
│   │       │   └── push_notification_repository_impl.dart
│   │       └── datasources/
│   │           ├── push_provider.dart          # abstract interface class (Strategy)
│   │           ├── fcm_push_provider.dart      # FCM implementation
│   │           ├── onesignal_push_provider.dart # OneSignal implementation
│   │           └── custom_push_provider.dart   # Custom/WebSocket implementation
│   └── background_task/
│       ├── domain/
│       │   ├── entities/
│       │   │   ├── background_task_config.dart
│       │   │   └── background_task_failure.dart
│       │   ├── repositories/
│       │   │   └── background_task_repository.dart
│       │   └── usecases/
│       │       ├── schedule_background_task_usecase.dart
│       │       ├── cancel_background_task_usecase.dart
│       │       └── execute_background_task_usecase.dart
│       ├── data/
│       │   ├── repositories/
│       │   │   └── background_task_repository_impl.dart
│       │   └── datasources/
│       │       └── workmanager_data_source.dart
│       └── presentation/
│           └── bloc/
│               ├── background_task_bloc.dart
│               ├── background_task_event.dart
│               └── background_task_state.dart
```

## 1. Entry Points (top-level functions)

These must live outside any class and be annotated with `@pragma('vm:entry-point')`
so the Dart AOT compiler does not tree-shake them.

```dart
// lib/core/background/workmanager_dispatcher.dart
import 'package:workmanager/workmanager.dart';
import 'package:get_it/get_it.dart';
import '../di/injection.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Re-initialize DI — background isolate has no shared state with main isolate
    await configureDependencies();

    final useCase = GetIt.instance<ExecuteBackgroundTaskUseCase>();
    final result = await useCase(BackgroundTaskInput(
      taskName: taskName,
      data: inputData ?? {},
    ));

    // WorkManager expects true = success, false = retry
    return result.fold(
      (failure) {
        // Log failure — do not throw, return false to trigger retry
        return false;
      },
      (_) => true,
    );
  });
}
```

```dart
// lib/core/background/push_background_handler.dart
// Provider-agnostic background handler entry point.
// The top-level function signature depends on the provider (see section 6),
// but it always delegates to ProcessBackgroundMessageUseCase.
import 'package:get_it/get_it.dart';
import '../di/injection.dart';

// FCM variant — used when firebase_messaging is the provider
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await configureDependencies();

  final useCase = GetIt.instance<ProcessBackgroundMessageUseCase>();
  // Normalize FCM RemoteMessage → domain PushMessage
  await useCase(PushMessage.fromFcm(message));
}

// OneSignal variant — used when onesignal_flutter is the provider
// OSNotificationReceivedEvent is the OneSignal equivalent of RemoteMessage
@pragma('vm:entry-point')
void oneSignalBackgroundHandler(OSNotificationReceivedEvent event) {
  // OneSignal background handler is synchronous — heavy work must be fire-and-forget
  configureDependencies().then((_) async {
    final useCase = GetIt.instance<ProcessBackgroundMessageUseCase>();
    await useCase(PushMessage.fromOneSignal(event.notification));
    event.complete(event.notification); // required to dismiss the notification
  });
}
```

## 2. App Initialization (main.dart)

```dart
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'core/background/push_background_handler.dart';
import 'core/background/workmanager_dispatcher.dart';
import 'core/di/injection.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Push provider initialization ---
  // Only initialize the active provider. Use dart-define to select at build time:
  // flutter run --dart-define=PUSH_PROVIDER=fcm
  const pushProvider = String.fromEnvironment('PUSH_PROVIDER', defaultValue: 'fcm');

  if (pushProvider == 'fcm') {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // FCM background handler must be registered before runApp
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } else if (pushProvider == 'onesignal') {
    // OneSignal background handler is registered inside OneSignalPushProvider.initialize()
    // No global registration needed here
  }

  // Initialize WorkManager — provider-independent
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  await configureDependencies();

  runApp(const MyApp());
}
```

## 3. Domain Layer

```dart
// lib/features/background_task/domain/entities/background_task_config.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'background_task_config.freezed.dart';

@freezed
class BackgroundTaskConfig with _$BackgroundTaskConfig {
  const factory BackgroundTaskConfig({
    required String taskId,
    required String taskName,
    Duration? initialDelay,
    Duration? frequency,           // null = one-off task
    Map<String, dynamic>? inputData,
    BackgroundTaskConstraints? constraints,
  }) = _BackgroundTaskConfig;
}

@freezed
class BackgroundTaskConstraints with _$BackgroundTaskConstraints {
  const factory BackgroundTaskConstraints({
    @Default(NetworkType.connected) NetworkType networkType,
    @Default(false) bool requiresBatteryNotLow,
    @Default(false) bool requiresCharging,
    @Default(false) bool requiresDeviceIdle,
    @Default(false) bool requiresStorageNotLow,
  }) = _BackgroundTaskConstraints;
}

@freezed
class BackgroundTaskInput with _$BackgroundTaskInput {
  const factory BackgroundTaskInput({
    required String taskName,
    required Map<String, dynamic> data,
  }) = _BackgroundTaskInput;
}

enum NetworkType { connected, metered, notRequired, notRoaming, unmetered }
```

```dart
// lib/features/background_task/domain/entities/background_task_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'background_task_failure.freezed.dart';

@freezed
class BackgroundFailure with _$BackgroundFailure {
  const factory BackgroundFailure.schedulingFailed({
    required String message,
  }) = SchedulingFailed;

  const factory BackgroundFailure.executionFailed({
    required String taskName,
    required String message,
  }) = ExecutionFailed;

  const factory BackgroundFailure.cancellationFailed({
    required String taskId,
    required String message,
  }) = CancellationFailed;

  const factory BackgroundFailure.notificationFailed({
    required String message,
  }) = NotificationFailed;

  const factory BackgroundFailure.unknown({
    required String message,
  }) = UnknownBackgroundFailure;
}
```

```dart
// lib/features/background_task/domain/repositories/background_task_repository.dart
import 'package:fpdart/fpdart.dart';

abstract interface class BackgroundTaskRepository {
  Future<Either<BackgroundFailure, Unit>> scheduleOneOffTask(BackgroundTaskConfig config);
  Future<Either<BackgroundFailure, Unit>> schedulePeriodicTask(BackgroundTaskConfig config);
  Future<Either<BackgroundFailure, Unit>> cancelTask(String taskId);
  Future<Either<BackgroundFailure, Unit>> cancelAllTasks();
}
```

```dart
// lib/features/background_task/domain/usecases/schedule_background_task_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class ScheduleBackgroundTaskUseCase {
  final BackgroundTaskRepository _repository;

  ScheduleBackgroundTaskUseCase(this._repository);

  Future<Either<BackgroundFailure, Unit>> call(BackgroundTaskConfig config) async {
    if (config.frequency != null) {
      return _repository.schedulePeriodicTask(config);
    }
    return _repository.scheduleOneOffTask(config);
  }
}

// lib/features/background_task/domain/usecases/cancel_background_task_usecase.dart
@injectable
class CancelBackgroundTaskUseCase {
  final BackgroundTaskRepository _repository;

  CancelBackgroundTaskUseCase(this._repository);

  Future<Either<BackgroundFailure, Unit>> call(String taskId) async {
    return _repository.cancelTask(taskId);
  }
}

// lib/features/background_task/domain/usecases/execute_background_task_usecase.dart
// Called from the WorkManager dispatcher — runs in background isolate
@injectable
class ExecuteBackgroundTaskUseCase {
  // Inject whatever data sync / processing services are needed
  final SyncDataRepository _syncRepository;

  ExecuteBackgroundTaskUseCase(this._syncRepository);

  Future<Either<BackgroundFailure, Unit>> call(BackgroundTaskInput input) async {
    return switch (input.taskName) {
      BackgroundTaskNames.syncData => _syncRepository.syncAll(),
      BackgroundTaskNames.cleanCache => _syncRepository.cleanCache(),
      _ => Left(BackgroundFailure.executionFailed(
          taskName: input.taskName,
          message: 'Unknown task: ${input.taskName}',
        )),
    };
  }
}

// lib/features/background_task/domain/usecases/process_background_message_usecase.dart
// Called from the FCM background handler — runs in background isolate
@injectable
class ProcessBackgroundMessageUseCase {
  final NotificationRepository _notificationRepository;

  ProcessBackgroundMessageUseCase(this._notificationRepository);

  Future<void> call(RemoteMessage message) async {
    // Data-only messages: process silently
    if (message.notification == null) {
      await _handleDataMessage(message.data);
      return;
    }
    // Notification messages: show local notification
    await _notificationRepository.showLocalNotification(
      title: message.notification!.title ?? '',
      body: message.notification!.body ?? '',
      data: message.data,
    );
  }

  Future<void> _handleDataMessage(Map<String, dynamic> data) async {
    // Handle silent data messages (e.g., trigger sync, update cache)
  }
}

// Task name constants — shared between scheduler and dispatcher
abstract final class BackgroundTaskNames {
  static const syncData = 'syncDataTask';
  static const cleanCache = 'cleanCacheTask';
}
```

## 4. Data Layer

```dart
// lib/features/background_task/data/repositories/background_task_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: BackgroundTaskRepository)
class BackgroundTaskRepositoryImpl implements BackgroundTaskRepository {
  final WorkmanagerDataSource _dataSource;

  BackgroundTaskRepositoryImpl(this._dataSource);

  @override
  Future<Either<BackgroundFailure, Unit>> scheduleOneOffTask(
    BackgroundTaskConfig config,
  ) async {
    try {
      await _dataSource.registerOneOffTask(config);
      return const Right(unit);
    } catch (e) {
      return Left(BackgroundFailure.schedulingFailed(
        message: 'Failed to schedule one-off task "${config.taskName}": $e',
      ));
    }
  }

  @override
  Future<Either<BackgroundFailure, Unit>> schedulePeriodicTask(
    BackgroundTaskConfig config,
  ) async {
    try {
      await _dataSource.registerPeriodicTask(config);
      return const Right(unit);
    } catch (e) {
      return Left(BackgroundFailure.schedulingFailed(
        message: 'Failed to schedule periodic task "${config.taskName}": $e',
      ));
    }
  }

  @override
  Future<Either<BackgroundFailure, Unit>> cancelTask(String taskId) async {
    try {
      await _dataSource.cancelByUniqueName(taskId);
      return const Right(unit);
    } catch (e) {
      return Left(BackgroundFailure.cancellationFailed(
        taskId: taskId,
        message: 'Failed to cancel task "$taskId": $e',
      ));
    }
  }

  @override
  Future<Either<BackgroundFailure, Unit>> cancelAllTasks() async {
    try {
      await _dataSource.cancelAll();
      return const Right(unit);
    } catch (e) {
      return Left(BackgroundFailure.cancellationFailed(
        taskId: 'all',
        message: 'Failed to cancel all tasks: $e',
      ));
    }
  }
}
```

```dart
// lib/features/background_task/data/datasources/workmanager_data_source.dart
import 'package:injectable/injectable.dart';
import 'package:workmanager/workmanager.dart';

@injectable
class WorkmanagerDataSource {
  Future<void> registerOneOffTask(BackgroundTaskConfig config) async {
    await Workmanager().registerOneOffTask(
      config.taskId,
      config.taskName,
      initialDelay: config.initialDelay ?? Duration.zero,
      inputData: config.inputData,
      constraints: _mapConstraints(config.constraints),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  Future<void> registerPeriodicTask(BackgroundTaskConfig config) async {
    assert(config.frequency != null, 'frequency is required for periodic tasks');

    await Workmanager().registerPeriodicTask(
      config.taskId,
      config.taskName,
      frequency: config.frequency,
      initialDelay: config.initialDelay ?? Duration.zero,
      inputData: config.inputData,
      constraints: _mapConstraints(config.constraints),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  Future<void> cancelByUniqueName(String taskId) async {
    await Workmanager().cancelByUniqueName(taskId);
  }

  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }

  Constraints? _mapConstraints(BackgroundTaskConstraints? c) {
    if (c == null) return null;
    return Constraints(
      networkType: _mapNetworkType(c.networkType),
      requiresBatteryNotLow: c.requiresBatteryNotLow,
      requiresCharging: c.requiresCharging,
      requiresDeviceIdle: c.requiresDeviceIdle,
      requiresStorageNotLow: c.requiresStorageNotLow,
    );
  }

  NetworkType _mapNetworkType(NetworkType type) => switch (type) {
    NetworkType.connected => NetworkType.connected,
    NetworkType.metered => NetworkType.metered,
    NetworkType.notRequired => NetworkType.not_required,
    NetworkType.notRoaming => NetworkType.not_roaming,
    NetworkType.unmetered => NetworkType.unmetered,
  };
}
```

## 5. BLoC Implementation

```dart
// lib/features/background_task/presentation/bloc/background_task_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';

part 'background_task_bloc.freezed.dart';
part 'background_task_event.dart';
part 'background_task_state.dart';

@injectable
class BackgroundTaskBloc extends Bloc<BackgroundTaskEvent, BackgroundTaskState> {
  final ScheduleBackgroundTaskUseCase _scheduleUseCase;
  final CancelBackgroundTaskUseCase _cancelUseCase;

  BackgroundTaskBloc(this._scheduleUseCase, this._cancelUseCase)
      : super(const BackgroundTaskState.initial()) {
    on<ScheduleTaskEvent>(_onScheduleTask);
    on<CancelTaskEvent>(_onCancelTask);
    on<ResetEvent>(_onReset);
  }

  Future<void> _onScheduleTask(
    ScheduleTaskEvent event,
    Emitter<BackgroundTaskState> emit,
  ) async {
    emit(const BackgroundTaskState.loading());

    final result = await _scheduleUseCase(event.config);

    result.fold(
      (failure) => emit(BackgroundTaskState.error(_mapFailure(failure))),
      (_) => emit(BackgroundTaskState.scheduled(taskId: event.config.taskId)),
    );
  }

  Future<void> _onCancelTask(
    CancelTaskEvent event,
    Emitter<BackgroundTaskState> emit,
  ) async {
    emit(const BackgroundTaskState.loading());

    final result = await _cancelUseCase(event.taskId);

    result.fold(
      (failure) => emit(BackgroundTaskState.error(_mapFailure(failure))),
      (_) => emit(BackgroundTaskState.cancelled(taskId: event.taskId)),
    );
  }

  void _onReset(ResetEvent event, Emitter<BackgroundTaskState> emit) {
    emit(const BackgroundTaskState.initial());
  }

  String _mapFailure(BackgroundFailure failure) => failure.when(
    schedulingFailed: (message) => 'Scheduling failed: $message',
    executionFailed: (taskName, message) => 'Task "$taskName" failed: $message',
    cancellationFailed: (taskId, message) => 'Cancel failed for "$taskId": $message',
    notificationFailed: (message) => 'Notification failed: $message',
    unknown: (message) => 'Unknown error: $message',
  );
}

// background_task_event.dart
part of 'background_task_bloc.dart';

@freezed
class BackgroundTaskEvent with _$BackgroundTaskEvent {
  const factory BackgroundTaskEvent.scheduleTask(BackgroundTaskConfig config) = ScheduleTaskEvent;
  const factory BackgroundTaskEvent.cancelTask(String taskId) = CancelTaskEvent;
  const factory BackgroundTaskEvent.reset() = ResetEvent;
}

// background_task_state.dart
part of 'background_task_bloc.dart';

@freezed
class BackgroundTaskState with _$BackgroundTaskState {
  const factory BackgroundTaskState.initial() = BackgroundTaskInitial;
  const factory BackgroundTaskState.loading() = BackgroundTaskLoading;
  const factory BackgroundTaskState.scheduled({required String taskId}) = BackgroundTaskScheduled;
  const factory BackgroundTaskState.cancelled({required String taskId}) = BackgroundTaskCancelled;
  const factory BackgroundTaskState.error(String message) = BackgroundTaskError;
}
```

## 6. Push Provider Strategy Pattern

The Strategy pattern isolates provider-specific code in the data layer.
The domain and presentation layers only know about `PushMessage` and `PushNotificationRepository`.

### 6.1 Domain — Provider-Agnostic Entities

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
    required Map<String, dynamic> data,
    required PushMessageType type,
    DateTime? sentAt,
  }) = _PushMessage;

  // Factory constructors normalize each provider's format into PushMessage
  factory PushMessage.fromFcm(RemoteMessage message) => PushMessage(
    id: message.messageId ?? DateTime.now().toIso8601String(),
    title: message.notification?.title,
    body: message.notification?.body,
    data: message.data,
    type: message.notification == null
        ? PushMessageType.data
        : PushMessageType.notification,
    sentAt: message.sentTime,
  );

  factory PushMessage.fromOneSignal(OSNotification notification) => PushMessage(
    id: notification.notificationId,
    title: notification.title,
    body: notification.body,
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
  const factory PushFailure.unknown({required String message}) = UnknownPushFailure;
}
```

```dart
// lib/features/push_notifications/domain/repositories/push_notification_repository.dart
import 'package:fpdart/fpdart.dart';

abstract interface class PushNotificationRepository {
  Future<Either<PushFailure, Unit>> initialize();
  Future<Either<PushFailure, bool>> requestPermission();
  Future<Either<PushFailure, String>> getToken();
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> getInitialMessage();
}
```

### 6.2 Data — Strategy Interface

```dart
// lib/features/push_notifications/data/datasources/push_provider.dart
import 'package:fpdart/fpdart.dart';

// Strategy interface — each provider implements this
abstract interface class PushProvider {
  Future<Either<PushFailure, Unit>> initialize();
  Future<Either<PushFailure, bool>> requestPermission();
  Future<Either<PushFailure, String>> getToken();
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> getInitialMessage();
}
```

### 6.3 FCM Provider Implementation

```dart
// lib/features/push_notifications/data/datasources/fcm_push_provider.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: PushProvider, env: ['fcm'])
class FcmPushProvider implements PushProvider {
  final FirebaseMessaging _messaging;

  FcmPushProvider(this._messaging);

  @override
  Future<Either<PushFailure, Unit>> initialize() async {
    try {
      // FCM is initialized via Firebase.initializeApp() in main.dart
      // Register background handler there — not here
      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.initializationFailed(message: '$e'));
    }
  }

  @override
  Future<Either<PushFailure, bool>> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
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
        return Left(PushFailure.tokenFetchFailed(message: 'Token is null'));
      }
      return Right(token);
    } catch (e) {
      return Left(PushFailure.tokenFetchFailed(message: '$e'));
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

### 6.4 OneSignal Provider Implementation

```dart
// lib/features/push_notifications/data/datasources/onesignal_push_provider.dart
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: PushProvider, env: ['onesignal'])
class OneSignalPushProvider implements PushProvider {
  final String _appId;

  OneSignalPushProvider(@Named('oneSignalAppId') this._appId);

  @override
  Future<Either<PushFailure, Unit>> initialize() async {
    try {
      OneSignal.initialize(_appId);
      // Register background handler (set in main.dart or here)
      OneSignal.Notifications.addForegroundWillDisplayListener(_onForeground);
      return const Right(unit);
    } catch (e) {
      return Left(PushFailure.initializationFailed(message: '$e'));
    }
  }

  void _onForeground(OSNotificationWillDisplayEvent event) {
    // Display the notification — can be suppressed for data-only handling
    event.notification.display();
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
      final pushToken = OneSignal.User.pushSubscription.token;
      if (pushToken == null) {
        return Left(PushFailure.tokenFetchFailed(message: 'OneSignal token is null'));
      }
      return Right(pushToken);
    } catch (e) {
      return Left(PushFailure.tokenFetchFailed(message: '$e'));
    }
  }

  @override
  Stream<PushMessage> get onForegroundMessage =>
      // OneSignal uses listeners, not streams — bridge with StreamController
      _foregroundController.stream;

  final _foregroundController = StreamController<PushMessage>.broadcast();

  @override
  Stream<PushMessage> get onMessageOpenedApp => _openedAppController.stream;

  final _openedAppController = StreamController<PushMessage>.broadcast();

  @override
  Future<PushMessage?> getInitialMessage() async {
    // OneSignal does not have a direct equivalent — check launch options if needed
    return null;
  }
}
```

### 6.5 Repository Implementation (delegates to strategy)

```dart
// lib/features/push_notifications/data/repositories/push_notification_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: PushNotificationRepository)
class PushNotificationRepositoryImpl implements PushNotificationRepository {
  // Inject the active strategy — resolved by DI environment or named registration
  final PushProvider _provider;

  PushNotificationRepositoryImpl(this._provider);

  @override
  Future<Either<PushFailure, Unit>> initialize() => _provider.initialize();

  @override
  Future<Either<PushFailure, bool>> requestPermission() => _provider.requestPermission();

  @override
  Future<Either<PushFailure, String>> getToken() => _provider.getToken();

  @override
  Stream<PushMessage> get onForegroundMessage => _provider.onForegroundMessage;

  @override
  Stream<PushMessage> get onMessageOpenedApp => _provider.onMessageOpenedApp;

  @override
  Future<PushMessage?> getInitialMessage() => _provider.getInitialMessage();
}
```

### 6.6 Notification BLoC (provider-agnostic)

```dart
// lib/features/push_notifications/presentation/bloc/notification_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';

part 'notification_bloc.freezed.dart';
part 'notification_event.dart';
part 'notification_state.dart';

@injectable
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final PushNotificationRepository _repository;
  StreamSubscription<PushMessage>? _foregroundSub;
  StreamSubscription<PushMessage>? _openedAppSub;

  NotificationBloc(this._repository) : super(const NotificationState.initial()) {
    on<InitializeNotificationsEvent>(_onInitialize);
    on<RequestPermissionEvent>(_onRequestPermission);
    on<MessageReceivedEvent>(_onMessageReceived);
    on<AppOpenedFromNotificationEvent>(_onAppOpenedFromNotification);
    on<ResetNotificationEvent>(_onReset);
  }

  Future<void> _onInitialize(
    InitializeNotificationsEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _repository.initialize();

    result.fold(
      (failure) => emit(NotificationState.error(_mapFailure(failure))),
      (_) {
        _foregroundSub = _repository.onForegroundMessage.listen(
          (message) => add(NotificationEvent.messageReceived(message)),
        );
        _openedAppSub = _repository.onMessageOpenedApp.listen(
          (message) => add(NotificationEvent.appOpenedFromNotification(message)),
        );
        emit(const NotificationState.initialized());
      },
    );

    // Check for initial message (app opened from terminated via notification)
    final initialMessage = await _repository.getInitialMessage();
    if (initialMessage != null) {
      add(NotificationEvent.appOpenedFromNotification(initialMessage));
    }
  }

  Future<void> _onRequestPermission(
    RequestPermissionEvent event,
    Emitter<NotificationState> emit,
  ) async {
    final result = await _repository.requestPermission();
    result.fold(
      (failure) => emit(NotificationState.error(_mapFailure(failure))),
      (granted) => emit(granted
          ? const NotificationState.permissionGranted()
          : const NotificationState.permissionDenied()),
    );
  }

  void _onMessageReceived(
    MessageReceivedEvent event,
    Emitter<NotificationState> emit,
  ) {
    emit(NotificationState.messageReceived(message: event.message));
  }

  void _onAppOpenedFromNotification(
    AppOpenedFromNotificationEvent event,
    Emitter<NotificationState> emit,
  ) {
    emit(NotificationState.openedFromNotification(message: event.message));
  }

  void _onReset(ResetNotificationEvent event, Emitter<NotificationState> emit) {
    emit(const NotificationState.initial());
  }

  String _mapFailure(PushFailure failure) => failure.when(
    permissionDenied: () => 'Notification permission denied',
    initializationFailed: (message) => 'Initialization failed: $message',
    tokenFetchFailed: (message) => 'Token fetch failed: $message',
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
  const factory NotificationEvent.messageReceived(PushMessage message) = MessageReceivedEvent;
  const factory NotificationEvent.appOpenedFromNotification(PushMessage message) = AppOpenedFromNotificationEvent;
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
  const factory NotificationState.messageReceived({required PushMessage message}) = NotificationMessageReceived;
  const factory NotificationState.openedFromNotification({required PushMessage message}) = NotificationOpenedFromNotification;
  const factory NotificationState.error(String message) = NotificationError;
}
```

### 6.7 Switching Providers via DI

```dart
// lib/core/di/injection.dart
// Register the active provider using Injectable environments
// or a named registration resolved at runtime.

@module
abstract class PushProviderModule {
  // Option A: compile-time environment flag
  // Run: flutter run --dart-define=PUSH_PROVIDER=fcm
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
```

## 7. Platform Configuration

### Android — AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Required for WorkManager to reschedule tasks after reboot -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <!-- Required for FCM -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application ...>

        <!-- Disable WorkManager auto-init to control initialization manually -->
        <provider
            android:name="androidx.startup.InitializationProvider"
            android:authorities="${applicationId}.androidx-startup"
            android:exported="false"
            tools:node="merge">
            <meta-data
                android:name="androidx.work.WorkManagerInitializer"
                android:value="androidx.startup"
                tools:node="remove" />
        </provider>

        <!-- FCM default notification channel -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="high_importance_channel" />

        <!-- FCM default notification icon -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_notification" />

    </application>
</manifest>
```

### Android — build.gradle (app level)

```groovy
android {
    defaultConfig {
        minSdkVersion 23  // Required by WorkManager
    }
}
```

### iOS — Info.plist

```xml
<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
    <string>processing</string>
</array>

<!-- WorkManager background task identifiers -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>syncDataTask</string>
    <string>cleanCacheTask</string>
</array>
```

### iOS — AppDelegate.swift

```swift
import UIKit
import Flutter
import workmanager

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        // Register WorkManager background tasks
        UIApplication.shared.setMinimumBackgroundFetchInterval(
            TimeInterval(60 * 15) // 15 minutes minimum
        )
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "syncDataTask")
        WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "cleanCacheTask")
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

## 8. Dependency Injection

```dart
// lib/core/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async => getIt.init();
```

> **Important:** `configureDependencies()` is called both in `main()` (main isolate)
> and inside `callbackDispatcher` / `firebaseMessagingBackgroundHandler` (background isolate).
> Each isolate has its own GetIt instance — there is no shared state between them.

```dart
// Example: registering FirebaseMessaging as a singleton
@module
abstract class FirebaseModule {
  @singleton
  FirebaseMessaging get messaging => FirebaseMessaging.instance;
}
```

## 9. Testing Strategy

### Unit Tests — UseCase

```dart
// test/features/background_task/domain/usecases/schedule_background_task_usecase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockBackgroundTaskRepository extends Mock implements BackgroundTaskRepository {}

void main() {
  late ScheduleBackgroundTaskUseCase useCase;
  late MockBackgroundTaskRepository mockRepository;

  setUp(() {
    mockRepository = MockBackgroundTaskRepository();
    useCase = ScheduleBackgroundTaskUseCase(mockRepository);
  });

  group('ScheduleBackgroundTaskUseCase', () {
    const config = BackgroundTaskConfig(
      taskId: 'sync-001',
      taskName: BackgroundTaskNames.syncData,
    );

    test('calls scheduleOneOffTask when frequency is null', () async {
      when(() => mockRepository.scheduleOneOffTask(config))
          .thenAnswer((_) async => const Right(unit));

      final result = await useCase(config);

      expect(result, const Right(unit));
      verify(() => mockRepository.scheduleOneOffTask(config)).called(1);
      verifyNever(() => mockRepository.schedulePeriodicTask(any()));
    });

    test('calls schedulePeriodicTask when frequency is set', () async {
      const periodicConfig = BackgroundTaskConfig(
        taskId: 'sync-periodic',
        taskName: BackgroundTaskNames.syncData,
        frequency: Duration(hours: 1),
      );

      when(() => mockRepository.schedulePeriodicTask(periodicConfig))
          .thenAnswer((_) async => const Right(unit));

      final result = await useCase(periodicConfig);

      expect(result, const Right(unit));
      verify(() => mockRepository.schedulePeriodicTask(periodicConfig)).called(1);
    });

    test('returns failure when scheduling fails', () async {
      const failure = BackgroundFailure.schedulingFailed(
        message: 'WorkManager not initialized',
      );

      when(() => mockRepository.scheduleOneOffTask(config))
          .thenAnswer((_) async => const Left(failure));

      final result = await useCase(config);

      expect(result, const Left(failure));
    });
  });
}
```

### BLoC Tests

```dart
// test/features/background_task/presentation/bloc/background_task_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockScheduleBackgroundTaskUseCase extends Mock
    implements ScheduleBackgroundTaskUseCase {}

class MockCancelBackgroundTaskUseCase extends Mock
    implements CancelBackgroundTaskUseCase {}

void main() {
  late BackgroundTaskBloc bloc;
  late MockScheduleBackgroundTaskUseCase mockScheduleUseCase;
  late MockCancelBackgroundTaskUseCase mockCancelUseCase;

  const config = BackgroundTaskConfig(
    taskId: 'sync-001',
    taskName: BackgroundTaskNames.syncData,
  );

  setUp(() {
    mockScheduleUseCase = MockScheduleBackgroundTaskUseCase();
    mockCancelUseCase = MockCancelBackgroundTaskUseCase();
    bloc = BackgroundTaskBloc(mockScheduleUseCase, mockCancelUseCase);
  });

  tearDown(() => bloc.close());

  group('BackgroundTaskBloc', () {
    blocTest<BackgroundTaskBloc, BackgroundTaskState>(
      'emits [loading, scheduled] when task is scheduled successfully',
      build: () {
        when(() => mockScheduleUseCase(config))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(BackgroundTaskEvent.scheduleTask(config)),
      expect: () => [
        const BackgroundTaskState.loading(),
        const BackgroundTaskState.scheduled(taskId: 'sync-001'),
      ],
    );

    blocTest<BackgroundTaskBloc, BackgroundTaskState>(
      'emits [loading, error] when scheduling fails',
      build: () {
        when(() => mockScheduleUseCase(config)).thenAnswer(
          (_) async => const Left(
            BackgroundFailure.schedulingFailed(message: 'Not initialized'),
          ),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(BackgroundTaskEvent.scheduleTask(config)),
      expect: () => [
        const BackgroundTaskState.loading(),
        const BackgroundTaskState.error('Scheduling failed: Not initialized'),
      ],
    );

    blocTest<BackgroundTaskBloc, BackgroundTaskState>(
      'emits [loading, cancelled] when task is cancelled successfully',
      build: () {
        when(() => mockCancelUseCase('sync-001'))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(const BackgroundTaskEvent.cancelTask('sync-001')),
      expect: () => [
        const BackgroundTaskState.loading(),
        const BackgroundTaskState.cancelled(taskId: 'sync-001'),
      ],
    );
  });
}
```

## 10. Best Practices

### WorkManager
- Always use `ExistingWorkPolicy.replace` for tasks that should not stack
- Use `BackoffPolicy.exponential` for tasks that may fail transiently (network sync)
- Keep task execution time under **10 minutes** on Android; iOS is more restrictive
- Never access UI or BuildContext from the dispatcher — it runs in a headless isolate
- Use `isInDebugMode: true` during development to force immediate task execution

### Push Provider Strategy
- Domain and presentation layers must never import provider-specific packages (e.g., `firebase_messaging`, `onesignal_flutter`) — only the data layer does
- Always normalize provider messages into `PushMessage` at the data source boundary
- Use `dart-define` (`PUSH_PROVIDER=fcm`) to select the provider at build time without code changes
- If the project uses multiple providers simultaneously (e.g., FCM for Android, OneSignal for iOS), resolve the correct strategy per platform inside `PushProviderModule`
- Background handler top-level functions are provider-specific by necessity — keep them thin and delegate immediately to `ProcessBackgroundMessageUseCase`

### General
- Never share state between the main isolate and background isolates
- Always re-initialize DI (`configureDependencies()`) inside background entry points
- Use `abstract final class` for task name constants to prevent instantiation
- Test UseCases and BLoC independently — do not test the top-level dispatcher directly

## Message Handling Matrix

| App State | Notification message | Data-only message |
|---|---|---|
| Foreground | `onForegroundMessage` stream (BLoC) | `onForegroundMessage` stream (BLoC) |
| Background | System tray (auto) + background handler | Background handler only |
| Terminated | System tray (auto) + background handler | Background handler only |
| Tapped (background) | `onMessageOpenedApp` stream | — |
| Tapped (terminated) | `getInitialMessage()` | — |

> This matrix applies to FCM. OneSignal and other providers have equivalent concepts
> but different API names — they are normalized by the provider implementation.
