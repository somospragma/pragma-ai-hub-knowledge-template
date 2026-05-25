# Parallel Execution, Debounce & Double-Submit Prevention

Native Dart patterns for running operations concurrently, rate-limiting UI actions,
and preventing duplicate submissions.

---

## Future.wait — Parallel I/O

Run independent async operations concurrently instead of sequentially.

```dart
// ❌ Sequential — total time = sum of all durations
Future<DashboardData> loadDashboard() async {
  final user = await _userRepo.getUser();       // 200ms
  final cart = await _cartRepo.getCart();       // 150ms
  final config = await _configRepo.getConfig(); // 100ms
  // Total: ~450ms
  return DashboardData(user: user, cart: cart, config: config);
}

// ✅ Parallel — total time = max of all durations
Future<DashboardData> loadDashboard() async {
  final results = await Future.wait([
    _userRepo.getUser(),
    _cartRepo.getCart(),
    _configRepo.getConfig(),
  ]);
  // Total: ~200ms (longest operation)
  return DashboardData(
    user: results[0] as User,
    cart: results[1] as Cart,
    config: results[2] as AppConfig,
  );
}

// ✅ Dart 3 — typed parallel with records (no casting)
Future<DashboardData> loadDashboard() async {
  final (user, cart, config) = await (
    _userRepo.getUser(),
    _cartRepo.getCart(),
    _configRepo.getConfig(),
  ).wait;
  return DashboardData(user: user, cart: cart, config: config);
}
```

### Future.wait with error handling

```dart
// ❌ Future.wait fails fast — first error cancels all
// ✅ eagerError: false — wait for all, collect errors
Future<void> syncAll() async {
  final results = await Future.wait(
    [
      _syncProducts(),
      _syncOrders(),
      _syncInventory(),
    ],
    eagerError: false, // don't fail on first error — collect all results
  );
  // All completed — check individual results if needed
}

// ✅ Handle partial failures with Either
Future<void> syncAllSafe() async {
  final futures = [
    _syncProducts().then((_) => const Right<String, Unit>(unit))
        .catchError((e) => Left<String, Unit>('products: $e')),
    _syncOrders().then((_) => const Right<String, Unit>(unit))
        .catchError((e) => Left<String, Unit>('orders: $e')),
  ];

  final results = await Future.wait(futures);
  final failures = results.whereType<Left<String, Unit>>().toList();
  if (failures.isNotEmpty) {
    throw SyncException(failures.map((f) => f.value).join(', '));
  }
}
```

---

## Future.any — First Wins

```dart
// Return the first successful result — useful for fallback strategies
Future<List<Product>> getProductsWithFallback() async {
  return Future.any([
    _remoteDataSource.getProducts(),           // try remote first
    Future.delayed(
      const Duration(seconds: 3),
      () => _localDataSource.getProducts(),    // fallback after 3s
    ),
  ]);
}

// Race a request against a timeout
Future<T> withTimeout<T>(Future<T> operation, Duration timeout) {
  return Future.any([
    operation,
    Future.delayed(timeout).then((_) => throw TimeoutException('Timed out')),
  ]);
}
```

---

## Debounce — Wait for Silence

### In a StatefulWidget

```dart
class _SearchFieldState extends State<SearchField> {
  Timer? _debounce;

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      context.read<SearchBloc>().add(SearchEvent.queryChanged(query));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel(); // ✅ always cancel
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(onChanged: _onChanged);
}
```

### Reusable Debouncer class

```dart
// lib/core/concurrency/debouncer.dart
import 'dart:async';

class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

// Usage in a widget or service:
class _ProductListState extends State<ProductList> {
  final _debouncer = Debouncer(delay: const Duration(milliseconds: 300));

  @override
  void dispose() {
    _debouncer.dispose(); // ✅
    super.dispose();
  }

  void _onFilterChanged(String filter) {
    _debouncer.run(() {
      context.read<ProductBloc>().add(ProductEvent.filterChanged(filter));
    });
  }
}
```

---

## Throttle — Rate Limit (First Wins)

Emit the first event, ignore subsequent ones for the duration.
Use for scroll events, button taps, analytics tracking.

```dart
// lib/core/concurrency/throttler.dart
import 'dart:async';

class Throttler {
  final Duration interval;
  DateTime? _lastRun;

  Throttler({required this.interval});

  bool run(void Function() action) {
    final now = DateTime.now();
    if (_lastRun == null || now.difference(_lastRun!) >= interval) {
      _lastRun = now;
      action();
      return true; // executed
    }
    return false; // throttled
  }
}

// Usage — track scroll position at most once per 100ms
final _scrollThrottler = Throttler(interval: const Duration(milliseconds: 100));

void _onScroll(ScrollNotification notification) {
  _scrollThrottler.run(() {
    _analyticsService.trackScroll(notification.metrics.pixels);
  });
}
```

---

## Double-Submit Prevention

### BLoC — droppable() transformer

```dart
// The cleanest approach — BLoC handles it natively
on<SubmitOrderEvent>(
  _onSubmit,
  transformer: droppable(), // ignores new events while one is processing
);

Future<void> _onSubmit(
  SubmitOrderEvent event,
  Emitter<OrderState> emit,
) async {
  emit(const OrderState.submitting());
  final result = await _orderRepository.submitOrder(event.order);
  result.fold(
    (f) => emit(OrderState.error(f.message)),
    (order) => emit(OrderState.success(order: order)),
  );
}
```

### Widget-level guard — for non-BLoC scenarios

```dart
class _CheckoutButtonState extends State<CheckoutButton> {
  bool _isSubmitting = false;

  Future<void> _onTap() async {
    if (_isSubmitting) return; // ✅ guard
    setState(() => _isSubmitting = true);

    try {
      await widget.onSubmit();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isSubmitting ? null : _onTap, // disabled while submitting
      child: _isSubmitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Place Order'),
    );
  }
}
```

### Reusable SingleExecutor — one operation at a time

```dart
// lib/core/concurrency/single_executor.dart

/// Ensures only one async operation runs at a time.
/// New calls are dropped while one is in progress.
class SingleExecutor {
  bool _running = false;

  Future<T?> run<T>(Future<T> Function() fn) async {
    if (_running) return null; // drop
    _running = true;
    try {
      return await fn();
    } finally {
      _running = false;
    }
  }

  bool get isRunning => _running;
}

// Usage in a service:
class PaymentService {
  final _executor = SingleExecutor();

  Future<PaymentResult?> processPayment(PaymentRequest request) {
    return _executor.run(() => _paymentApi.process(request));
  }
}
```

---

## Parallel with Concurrency Limit

Run many operations in parallel but limit how many run simultaneously.

```dart
// lib/core/concurrency/bounded_parallel.dart

/// Run [tasks] in parallel with at most [maxConcurrent] running at once.
Future<List<T>> boundedParallel<T>(
  List<Future<T> Function()> tasks, {
  required int maxConcurrent,
}) async {
  final results = List<T?>.filled(tasks.length, null);
  var index = 0;

  Future<void> worker() async {
    while (true) {
      final i = index++;
      if (i >= tasks.length) return;
      results[i] = await tasks[i]();
    }
  }

  await Future.wait(
    List.generate(maxConcurrent, (_) => worker()),
  );

  return results.cast<T>();
}

// Usage — upload 20 images, max 3 at a time
final uploadTasks = images.map(
  (image) => () => _uploadService.upload(image),
).toList();

final results = await boundedParallel(uploadTasks, maxConcurrent: 3);
```

---

## Testing Concurrency Patterns

```dart
void main() {
  group('Debouncer', () {
    test('only executes once after rapid calls', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 100));
      var count = 0;

      debouncer.run(() => count++);
      debouncer.run(() => count++);
      debouncer.run(() => count++);

      await Future.delayed(const Duration(milliseconds: 150));
      expect(count, 1); // only last call executed
      debouncer.dispose();
    });
  });

  group('SingleExecutor', () {
    test('drops concurrent calls', () async {
      final executor = SingleExecutor();
      var executionCount = 0;

      final futures = List.generate(
        5,
        (_) => executor.run(() async {
          executionCount++;
          await Future.delayed(const Duration(milliseconds: 50));
          return executionCount;
        }),
      );

      await Future.wait(futures);
      expect(executionCount, 1); // only first call ran
    });
  });

  group('boundedParallel', () {
    test('respects concurrency limit', () async {
      var concurrent = 0;
      var maxConcurrent = 0;

      final tasks = List.generate(10, (i) => () async {
        concurrent++;
        maxConcurrent = max(maxConcurrent, concurrent);
        await Future.delayed(const Duration(milliseconds: 20));
        concurrent--;
        return i;
      });

      await boundedParallel(tasks, maxConcurrent: 3);
      expect(maxConcurrent, lessThanOrEqualTo(3));
    });
  });
}
```
