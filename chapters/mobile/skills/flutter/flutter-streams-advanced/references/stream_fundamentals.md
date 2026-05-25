# Stream Fundamentals — Native Dart

Core stream patterns using only `dart:async`. No external dependencies.

---

## Single-Subscription vs Broadcast

```dart
// Single-subscription — one listener only, throws on second listen
final controller = StreamController<int>();
controller.stream.listen(print); // ✅
controller.stream.listen(print); // ❌ throws StateError

// Broadcast — multiple listeners, no replay
final broadcast = StreamController<int>.broadcast();
broadcast.stream.listen(print); // ✅
broadcast.stream.listen(print); // ✅ both receive events

// Convert single → broadcast (use sparingly — loses backpressure)
final broadcastStream = singleStream.asBroadcastStream();
```

---

## StreamController — Correct Usage

```dart
// lib/core/events/app_event_bus.dart
import 'dart:async';
import 'package:injectable/injectable.dart';

@lazySingleton
class AppEventBus {
  // ✅ Expose Stream, never the controller itself
  final _controller = StreamController<AppEvent>.broadcast();

  Stream<AppEvent> get stream => _controller.stream;

  // Typed sub-streams — filter without creating new controllers
  Stream<UserLoggedInEvent> get onUserLoggedIn =>
      stream.whereType<UserLoggedInEvent>();

  Stream<CartUpdatedEvent> get onCartUpdated =>
      stream.whereType<CartUpdatedEvent>();

  void emit(AppEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  // ✅ Always close the controller
  void dispose() => _controller.close();
}
```

---

## Native Dart Operators

```dart
// map — transform each event
stream.map((product) => product.name)

// where — filter events
stream.where((product) => product.isAvailable)

// distinct — skip consecutive duplicates (by equality)
stream.distinct()

// distinct with custom equality
stream.distinct((prev, curr) => prev.id == curr.id)

// asyncMap — async transform, processes one at a time
stream.asyncMap((id) async => await repository.getProduct(id))

// asyncExpand — async transform + flatten (replaces switchMap without rxdart)
// Each new event cancels the previous inner stream
stream.asyncExpand((query) => repository.search(query).asStream())

// expand — sync flatten (one event → many)
stream.expand((order) => order.items)

// take — first N events then close
stream.take(5)

// skip — skip first N events
stream.skip(1)

// takeWhile — emit while condition is true
stream.takeWhile((value) => value < 100)

// timeout — error if no event within duration
stream.timeout(const Duration(seconds: 10))

// handleError — recover without terminating the stream
stream.handleError((e) => logger.error('$e'))

// transform — apply a StreamTransformer
stream.transform(myTransformer)
```

---

## Custom StreamTransformer — Debounce

```dart
// lib/core/streams/debounce_transformer.dart
import 'dart:async';

/// Waits for silence before emitting the last event.
/// Pure Dart — no rxdart needed.
class DebounceTransformer<T> extends StreamTransformerBase<T, T> {
  final Duration duration;
  const DebounceTransformer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    Timer? timer;

    controller = StreamController<T>(
      onListen: () {
        final sub = stream.listen(
          (event) {
            timer?.cancel();
            timer = Timer(duration, () {
              if (!controller.isClosed) controller.add(event);
            });
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            controller.close();
          },
        );
        controller.onCancel = sub.cancel;
      },
    );

    return controller.stream;
  }
}
```

---

## Custom StreamTransformer — Sliding Window

```dart
// lib/core/streams/sliding_window_transformer.dart

/// Emits a sliding window of the last N events.
class SlidingWindowTransformer<T> extends StreamTransformerBase<T, List<T>> {
  final int windowSize;
  const SlidingWindowTransformer({required this.windowSize});

  @override
  Stream<List<T>> bind(Stream<T> stream) async* {
    final buffer = <T>[];
    await for (final event in stream) {
      buffer.add(event);
      if (buffer.length > windowSize) buffer.removeAt(0);
      yield List.unmodifiable(buffer);
    }
  }
}

// Usage — last 5 sensor readings:
sensorStream
    .transform(SlidingWindowTransformer(windowSize: 5))
    .listen(updateChart);
```

---

## Combining Streams — Native Dart

### StreamZip — pair events by index

```dart
import 'dart:async';

// Emits when ALL streams have emitted — pairs by position
final combined = StreamZip([
  userStream,
  cartStream,
]).map((values) => DashboardData(
  user: values[0] as User,
  cart: values[1] as Cart,
));
```

### Latest-value combiner — manual broadcast controller

```dart
/// Emits whenever ANY source stream emits, using the latest value from each.
/// Native Dart equivalent of rxdart's combineLatest.
Stream<DashboardData> combineLatestDashboard(
  Stream<User> userStream,
  Stream<Cart> cartStream,
) {
  User? latestUser;
  Cart? latestCart;
  final controller = StreamController<DashboardData>.broadcast();

  void tryEmit() {
    if (latestUser != null && latestCart != null) {
      controller.add(DashboardData(user: latestUser!, cart: latestCart!));
    }
  }

  final userSub = userStream.listen((u) { latestUser = u; tryEmit(); });
  final cartSub = cartStream.listen((c) { latestCart = c; tryEmit(); });

  controller.onCancel = () {
    userSub.cancel();
    cartSub.cancel();
  };

  return controller.stream;
}
```

### Merge — interleave multiple streams

```dart
/// Emit events from all streams as they arrive.
/// Native Dart equivalent of rxdart's merge.
Stream<T> mergeStreams<T>(List<Stream<T>> streams) {
  final controller = StreamController<T>.broadcast();
  final subs = <StreamSubscription<T>>[];
  var doneCount = 0;

  for (final stream in streams) {
    subs.add(stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        doneCount++;
        if (doneCount == streams.length) controller.close();
      },
    ));
  }

  controller.onCancel = () {
    for (final sub in subs) sub.cancel();
  };

  return controller.stream;
}

// Usage:
final allNotifications = mergeStreams([
  fcmStream,
  websocketStream,
  localNotificationStream,
]);
```

---

## Error Handling

```dart
// ❌ Error terminates the stream — no recovery
stream.listen((data) => process(data));

// ✅ cancelOnError: false — stream continues after error
stream.listen(
  (data) => process(data),
  onError: (error, stackTrace) => logger.error('$error'),
  cancelOnError: false, // ✅ keep listening
);

// ✅ handleError — recover inline, stream continues
stream
    .handleError((e) => logger.warning('Handled: $e'))
    .listen(process);

// ✅ Provide fallback value on error
stream
    .handleError(
      (e) => logger.error('$e'),
      test: (e) => e is NetworkException, // only handle specific errors
    )
    .map((data) => data ?? defaultValue)
    .listen(process);
```

---

## StreamSubscription — Lifecycle

```dart
// ✅ Always cancel subscriptions in dispose() or BLoC close()
class _MyWidgetState extends State<MyWidget> {
  StreamSubscription<List<Product>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = repository.watchProducts().listen(
      (products) => setState(() => _products = products),
      onError: (e) => setState(() => _error = '$e'),
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    _sub?.cancel(); // ✅
    super.dispose();
  }
}

// ✅ In BLoC — cancel all subscriptions in close()
@override
Future<void> close() async {
  await _productsSub?.cancel();
  await _connectivitySub?.cancel();
  return super.close();
}
```

---

## Testing Streams

```dart
// test/core/streams/debounce_transformer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

void main() {
  group('DebounceTransformer', () {
    test('emits only last event after silence', () {
      fakeAsync((async) {
        final controller = StreamController<String>();
        final results = <String>[];

        controller.stream
            .transform(DebounceTransformer(const Duration(milliseconds: 300)))
            .listen(results.add);

        controller.add('a');
        controller.add('b');
        controller.add('c');

        async.elapse(const Duration(milliseconds: 300));

        expect(results, ['c']); // only last value after silence
      });
    });

    test('emits each event separated by silence', () {
      fakeAsync((async) {
        final controller = StreamController<String>();
        final results = <String>[];

        controller.stream
            .transform(DebounceTransformer(const Duration(milliseconds: 200)))
            .listen(results.add);

        controller.add('first');
        async.elapse(const Duration(milliseconds: 200));
        controller.add('second');
        async.elapse(const Duration(milliseconds: 200));

        expect(results, ['first', 'second']);
      });
    });
  });
}
```
