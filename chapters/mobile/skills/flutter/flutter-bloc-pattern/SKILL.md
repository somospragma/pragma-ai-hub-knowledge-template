---
name: flutter-bloc-pattern
description: >
  Implements the BLoC pattern correctly in Flutter with bloc 9.x and flutter_bloc 9.x. Use this skill when creating or modifying a BLoC, event, state, or any widget using BlocProvider/BlocBuilder/BlocListener. Triggers on 'create a BLoC', 'add an event', 'emit a state', BlocBuilder, BlocListener, BlocConsumer, BlocProvider, MultiBlocProvider, or any state management question using bloc. Stack- bloc, flutter_bloc, bloc_concurrency, bloc_test.
commands:
  - implement-bloc
inputs:
  - name: action
    description: Action to perform (implement, add-event, audit). "implement" generates a complete BLoC (event + state + bloc class + page integration), "add-event" adds a new event handler to an existing BLoC, "audit" checks existing BLoCs for anti-patterns (missing transformer, DataSource injection, context access, add() inside handlers).
    required: true
  - name: target
    description: Path to the BLoC file or feature directory (e.g. lib/features/auth/presentation/bloc/ for implement, lib/ for audit).
    required: true
  - name: feature_name
    description: Name of the feature for the BLoC (e.g. login, product, cart). Required when action is "implement".
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# BLoC Pattern in Flutter

Canonical patterns for state management with BLoC 9.x.

---

## BLoC Full Implementation

### Event (Freezed sealed union)

```dart
// lib/src/features/auth/presentation/bloc/login_event.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'login_event.freezed.dart';

@freezed
sealed class LoginEvent with _$LoginEvent {
  const factory LoginEvent.loginRequested({
    required String email,
    required String password,
  }) = _LoginRequested;

  const factory LoginEvent.logoutRequested() = _LogoutRequested;

  const factory LoginEvent.biometricLoginRequested() = _BiometricLoginRequested;
}
```

### State (Freezed sealed union)

```dart
// lib/src/features/auth/presentation/bloc/login_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/user.dart';
part 'login_state.freezed.dart';

@freezed
sealed class LoginState with _$LoginState {
  const factory LoginState.initial() = _Initial;
  const factory LoginState.loading() = _Loading;
  const factory LoginState.success({required User user}) = _Success;
  const factory LoginState.error({
    required String message,
    required String code,
  }) = _Error;
}
```

### BLoC Implementation

```dart
// lib/src/features/auth/presentation/bloc/login_bloc.dart
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:injectable/injectable.dart';
import '../../domain/use_cases/login_use_case.dart';
import '../../domain/use_cases/logout_use_case.dart';
import 'login_event.dart';
import 'login_state.dart';

@injectable
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc(this._loginUseCase, this._logoutUseCase)
      : super(const LoginState.initial()) {
    // ✅ Always declare transformer explicitly on every on<>
    on<_LoginRequested>(_onLogin, transformer: droppable());
    on<_LogoutRequested>(_onLogout, transformer: sequential());
    on<_BiometricLoginRequested>(_onBiometric, transformer: droppable());
  }

  final LoginUseCase _loginUseCase;
  final LogoutUseCase _logoutUseCase;

  Future<void> _onLogin(
    _LoginRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginState.loading());
    final result = await _loginUseCase(
      LoginParams(email: event.email, password: event.password),
    );
    emit(result.fold(
      (failure) => LoginState.error(
        message: switch (failure) {
          NetworkFailure(:final message) => message,
          ServerFailure(code: '401') => 'Invalid credentials',
          ServerFailure(:final message) => message,
          ValidationFailure(:final message) => message,
          _ => 'An unexpected error occurred',
        },
        code: failure.runtimeType.toString(),
      ),
      (user) => LoginState.success(user: user),
    ));
  }

  Future<void> _onLogout(
    _LogoutRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginState.loading());
    await _logoutUseCase();
    emit(const LoginState.initial());
  }

  Future<void> _onBiometric(
    _BiometricLoginRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginState.loading());
    final result = await _loginUseCase.withBiometric();
    emit(result.fold(
      (f) => LoginState.error(message: f.toString(), code: ''),
      (user) => LoginState.success(user: user),
    ));
  }
}
```

---

## Widget Integration

### BlocProvider — Page Level

```dart
// ✅ Always provide BLoC at the Page level via getIt
@RoutePage()
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<LoginBloc>(),
        child: const _LoginView(),
      );
}
```

### BlocBuilder — UI Rebuild

```dart
class _LoginView extends StatelessWidget {
  const _LoginView();

  @override
  Widget build(BuildContext context) => BlocBuilder<LoginBloc, LoginState>(
        buildWhen: (prev, curr) => prev != curr,
        builder: (context, state) => switch (state) {
          LoginState.initial() => const _LoginForm(),
          LoginState.loading() => const Center(child: CircularProgressIndicator()),
          LoginState.success(:final user) => _WelcomeCard(user: user),
          LoginState.error(:final message) => _LoginForm(errorMessage: message),
        },
      );
}
```

### BlocListener — Side Effects Only

```dart
// ✅ Navigation, SnackBars, Dialogs — never rebuild UI here
BlocListener<LoginBloc, LoginState>(
  listenWhen: (prev, curr) => curr is _Success || curr is _Error,
  listener: (context, state) {
    switch (state) {
      case LoginState.success():
        context.router.replaceAll([const HomeRoute()]);
      case LoginState.error(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
      default:
        break;
    }
  },
  child: const _LoginForm(),
)
```

### BlocConsumer — Build + Listen

```dart
BlocConsumer<LoginBloc, LoginState>(
  listenWhen: (prev, curr) => curr is _Success,
  listener: (context, state) {
    if (state case LoginState.success()) {
      context.router.replaceAll([const HomeRoute()]);
    }
  },
  buildWhen: (prev, curr) => curr is! _Success,
  builder: (context, state) => switch (state) {
    LoginState.loading() => const CircularProgressIndicator(),
    LoginState.error(:final message) => Text(message),
    _ => const _LoginForm(),
  },
)
```

### MultiBlocProvider

```dart
MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => getIt<AuthBloc>()),
    BlocProvider(create: (_) => getIt<NotificationBloc>()),
  ],
  child: const AppShell(),
)
```

---

## Stream-based Real-time BLoC

```dart
@injectable
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repository) : super(const ChatState.initial()) {
    on<_WatchStarted>(_onWatchStarted);
    on<_MessageSent>(_onMessageSent, transformer: sequential());
  }

  final ChatRepository _repository;

  Future<void> _onWatchStarted(
    _WatchStarted event,
    Emitter<ChatState> emit,
  ) async {
    emit(const ChatState.loading());
    // ✅ emit.forEach auto-cancels stream on BLoC close
    await emit.forEach(
      _repository.watchMessages(event.chatId),
      onData: (result) => result.fold(
        (f) => ChatState.error(message: f.toString()),
        (messages) => ChatState.success(messages: messages),
      ),
      onError: (_, __) => const ChatState.error(message: 'Connection lost'),
    );
  }

  Future<void> _onMessageSent(
    _MessageSent event,
    Emitter<ChatState> emit,
  ) async {
    await _repository.sendMessage(event.message);
    // Stream auto-updates the messages list
  }
}
```

---

## What's New in bloc 9.x

### onDone callback

Called when the BLoC's event handler stream completes (i.e., the BLoC is closed).
Useful for cleanup or final logging:

```dart
@injectable
class AnalyticsBloc extends Bloc<AnalyticsEvent, AnalyticsState> {
  AnalyticsBloc(this._service) : super(const AnalyticsState.initial()) {
    on<_EventTracked>(_onEventTracked);
  }

  final AnalyticsService _service;

  @override
  void onDone() {
    // Called when the BLoC is closed — flush any pending analytics
    _service.flush();
    super.onDone();
  }
}
```

### MultiBlocObserver

Register multiple observers simultaneously — useful for combining logging,
analytics, and crash reporting without coupling them:

```dart
// main.dart
Bloc.observer = MultiBlocObserver(
  observers: [
    LoggingBlocObserver(),
    AnalyticsBlocObserver(),
    CrashlyticsBlocObserver(),
  ],
);
```

### bloc_lint — Static Analysis for BLoC

New package that adds lint rules enforcing BLoC best practices at analysis time:

```yaml
# pubspec.yaml
dev_dependencies:
  bloc_lint: ^1.0.0
```

```yaml
# analysis_options.yaml
include: package:bloc_lint/recommended.yaml
```

Catches common mistakes: missing `transformer`, `add()` inside handlers,
`context` access inside BLoC, DataSource injection instead of UseCase.

---

## bloc_concurrency Transformers

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

// droppable — ignore new events while processing current
on<_Started>(_onStarted, transformer: droppable());

// sequential — queue events, process one at a time
on<_MessageSent>(_onSend, transformer: sequential());

// restartable — cancel current, start fresh (search, filters)
on<_SearchQueryChanged>(_onSearch, transformer: restartable());

// concurrent — process all simultaneously (default)
on<_EventLogged>(_onLog); // transformer: concurrent()
```

| Transformer | Behaviour | Use for |
|---|---|---|
| `droppable()` | Ignore while busy | Load, refresh, pagination |
| `sequential()` | Queue FIFO | Send message, write operations |
| `restartable()` | Cancel and restart | Search, autocomplete, filters |
| `concurrent()` | All in parallel | Logging, analytics |

---

## Forbidden Patterns

```dart
// ❌ Accessing context inside BLoC
void _onEvent(event, emit) {
  Navigator.of(context).push(...); // FORBIDDEN — use BlocListener in UI
}

// ❌ DataSource injected into BLoC
@injectable
class MyBloc extends Bloc {
  MyBloc(this._dataSource); // FORBIDDEN — inject UseCase instead
  final ProductRemoteDataSource _dataSource;
}

// ❌ add() from within a handler (infinite loop risk)
void _onLoad(event, emit) async {
  add(AnotherEvent()); // DANGEROUS — call private methods instead
}

// ❌ Calling bloc.close() manually from UI
// BlocProvider handles lifecycle automatically

// ❌ context.watch to dispatch events
onPressed: () => context.watch<MyBloc>().add(...); // FORBIDDEN — use context.read
```

---

## Reference Files

- `references/bloc_implementation_guide.md` — Complete guide: Events, States, BLoC class, file structure, rules, anti-patterns, checklist
- `references/bloc_testing_patterns.md` — `blocTest`, `whenListen`, state sequences, fake async

## Architecture Diagrams

- `references/CleanArchitecture.mmd` — Layered flowchart: Presentation → Domain → Data → Infrastructure → Composition Root
- `references/ClassDiagram.mmd` — Full class hierarchy: Page → BLoC → UseCase → Repository → DataSources → Infrastructure + DI wiring
- `references/SequenceDiagram.mmd` — Concrete request/response flow with real class names
- `references/PlaceholdersSequenceDiagram.mmd` — Same sequence flow with `{Feature}` placeholders — use as a template when generating a new feature
