# Async Patterns — Full Implementations

## Future Patterns

### Basic async/await with Either

```dart
Future<Either<Failure, User>> fetchUser(String id) async {
  try {
    final dto = await _remote.getUser(id);
    return Right(UserMapper.fromDto(dto));
  } on DioException catch (e) {
    return Left(Failure.network(
      message: e.message ?? 'Network error',
      statusCode: e.response?.statusCode,
    ));
  } catch (e) {
    return Left(Failure.unknown(message: e.toString(), originalError: e));
  }
}
```

### Parallel — independent operations

```dart
Future<Either<Failure, Dashboard>> loadDashboard() async {
  try {
    final [userResult, productsResult, ordersResult] = await Future.wait([
      _remote.getUser(),
      _remote.getProducts(),
      _remote.getOrders(),
    ]);
    return Right(Dashboard(
      user: UserMapper.fromDto(userResult as UserDto),
      products: (productsResult as List).map(ProductMapper.fromDto).toList(),
      orders: (ordersResult as List).map(OrderMapper.fromDto).toList(),
    ));
  } on DioException catch (e) {
    return Left(Failure.network(message: e.message ?? 'Error'));
  }
}
```

### Sequential — result A feeds into B

```dart
Future<Either<Failure, OrderDetails>> createAndFetchOrder(Cart cart) async {
  final createResult = await _createOrderUseCase(CreateOrderParams(cart: cart));
  return createResult.flatMap(
    (order) => _getOrderDetailsUseCase(GetOrderParams(id: order.id)),
  );
}
```

### Timeout

```dart
Future<UserDto> getUser(String id) =>
    _dio.get('/users/$id').timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Request timed out'),
    ).then((r) => UserDto.fromJson(r.data as Map<String, dynamic>));
```

### Retry with exponential backoff

```dart
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration base = const Duration(seconds: 1),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt == maxAttempts - 1) rethrow;
      await Future<void>.delayed(base * (1 << attempt)); // 1s, 2s, 4s
    }
  }
  throw StateError('unreachable');
}
```

---

## Stream Patterns

### emit.forEach — preferred (auto-cancels on BLoC close)

```dart
Future<void> _onWatchStarted(
  _WatchStarted event,
  Emitter<NotificationState> emit,
) async {
  emit(const NotificationState.loading());
  await emit.forEach(
    _repository.watchNotifications(),
    onData: (result) => result.fold(
      (f) => NotificationState.error(message: f.toString()),
      (n) => NotificationState.success(notifications: n),
    ),
    onError: (_, __) => const NotificationState.error(message: 'Stream error'),
  );
  // stream automatically cancelled when BLoC closes
}
```

### Manual StreamSubscription — when you need explicit control

```dart
@injectable
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  NotificationBloc(this._repository) : super(const NotificationState.initial()) {
    on<_WatchStarted>(_onWatchStarted);
  }

  final NotificationRepository _repository;
  StreamSubscription<Either<Failure, List<Notification>>>? _sub;

  Future<void> _onWatchStarted(
    _WatchStarted event,
    Emitter<NotificationState> emit,
  ) async {
    await _sub?.cancel();
    emit(const NotificationState.loading());

    _sub = _repository.watchNotifications().listen(
      (result) => result.fold(
        (failure) => add(_NotificationError(failure)),
        (notifications) => add(_NotificationsReceived(notifications)),
      ),
    );
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
```

### StreamController with proper lifecycle

```dart
class EventBus {
  final _controller = StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get events => _controller.stream;
  Stream<T> on<T extends AppEvent>() => events.whereType<T>();

  void emit(AppEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  Future<void> dispose() => _controller.close();
}
```

---

## Debounce and Throttle — Native Dart (no rxdart)

### Debounce — pure Dart with Timer

```dart
class Debouncer {
  Debouncer({required this.duration});
  final Duration duration;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() => _timer?.cancel();
}

// Usage in a BLoC event handler
final _debouncer = Debouncer(duration: const Duration(milliseconds: 300));

void _onQueryChanged(QueryChanged event, Emitter<SearchState> emit) {
  _debouncer(() async {
    if (event.query.trim().length < 2) return;
    emit(const SearchState.loading());
    final result = await _searchUseCase(SearchParams(query: event.query));
    emit(result.fold(SearchState.error, SearchState.success));
  });
}

@override
Future<void> close() {
  _debouncer.dispose();
  return super.close();
}
```

### Debounce — bloc_concurrency restartable()

```dart
// restartable() cancels the previous handler when a new event arrives.
// Combine with a small delay to achieve debounce behaviour.
on<SearchQueryChanged>(
  _onQueryChanged,
  transformer: restartable(),
);

Future<void> _onQueryChanged(
  SearchQueryChanged event,
  Emitter<SearchState> emit,
) async {
  // If a new event arrives before this delay completes,
  // restartable() cancels this handler and starts fresh.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (event.query.trim().length < 2) return;

  emit(const SearchState.loading());
  final result = await _searchUseCase(SearchParams(query: event.query));
  emit(result.fold(SearchState.error, SearchState.success));
}
```

### Throttle — pure Dart with a flag

```dart
class Throttler {
  Throttler({required this.duration});
  final Duration duration;
  bool _isThrottled = false;

  bool call(void Function() action) {
    if (_isThrottled) return false;
    _isThrottled = true;
    action();
    Future<void>.delayed(duration).then((_) => _isThrottled = false);
    return true;
  }
}
```

### Throttle — bloc_concurrency droppable()

```dart
// droppable() ignores new events while the current handler is running
on<AddToCartPressed>(
  _onAddToCart,
  transformer: droppable(),
);
```

---

## bloc_concurrency — Full Transformer Guide

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

// sequential() — process one at a time, queue the rest
// Use for: pagination, ordered writes, operations that must not overlap
on<LoadPageRequested>(_onLoadPage, transformer: sequential());

// concurrent() — process all events simultaneously (default behaviour)
// Use for: analytics tracking, independent fire-and-forget events
on<TrackViewEvent>(_onTrackView, transformer: concurrent());

// droppable() — ignore new events while one is processing
// Use for: form submit, add-to-cart, any action that must not double-fire
on<SubmitFormPressed>(_onSubmit, transformer: droppable());

// restartable() — cancel current and start fresh on new event
// Use for: search, autocomplete, any input-driven async call
on<SearchQueryChanged>(_onSearch, transformer: restartable());
```

| Transformer | Behaviour | Analogy |
|---|---|---|
| `sequential()` | Queue — FIFO | Single-lane road |
| `concurrent()` | All run in parallel | Multi-lane highway |
| `droppable()` | Ignore while busy | Busy signal |
| `restartable()` | Cancel and restart | Interrupt |
