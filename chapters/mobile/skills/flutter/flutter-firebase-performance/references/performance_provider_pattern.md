# Performance Monitor — Strategy + Adapter Pattern

Use this pattern so the performance monitoring provider can be swapped
(Firebase → Sentry → Datadog) without touching business logic or BLoC.

---

## 1. Domain — PerformanceMonitor Interface (Strategy)

```dart
// lib/core/performance/performance_monitor.dart

/// A single active trace — stop it when the measured operation completes.
abstract interface class PerformanceTrace {
  void putAttribute(String name, String value);
  void putMetric(String name, int value);
  Future<void> stop();
}

/// Provider-agnostic performance monitoring contract.
/// Business logic and BLoC only know this interface.
abstract interface class PerformanceMonitor {
  /// Start a named trace. Call stop() on the returned trace when done.
  Future<PerformanceTrace> startTrace(String name);

  /// Convenience: wrap an async operation in a trace automatically.
  Future<void> recordTrace(
    String name,
    Future<void> Function() operation, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  });
}
```

---

## 2. Firebase Adapter (Primary)

```dart
// lib/core/performance/adapters/firebase_performance_adapter.dart
import 'package:firebase_performance/firebase_performance.dart';
import 'package:injectable/injectable.dart';

@Injectable(as: PerformanceMonitor, env: [Environment.prod, 'staging'])
class FirebasePerformanceAdapter implements PerformanceMonitor {
  final FirebasePerformance _perf = FirebasePerformance.instance;

  @override
  Future<PerformanceTrace> startTrace(String name) async {
    final trace = _perf.newTrace(name);
    await trace.start();
    return _FirebaseTrace(trace);
  }

  @override
  Future<void> recordTrace(
    String name,
    Future<void> Function() operation, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    final trace = _perf.newTrace(name);
    attributes?.forEach(trace.putAttribute);
    await trace.start();
    try {
      await operation();
      metrics?.forEach(trace.putMetric);
    } finally {
      await trace.stop();
    }
  }
}

class _FirebaseTrace implements PerformanceTrace {
  final Trace _trace;
  _FirebaseTrace(this._trace);

  @override
  void putAttribute(String name, String value) => _trace.putAttribute(name, value);

  @override
  void putMetric(String name, int value) => _trace.putMetric(name, value);

  @override
  Future<void> stop() => _trace.stop();
}
```

---

## 3. Sentry Adapter (Alternative — error + performance in one SDK)

```dart
// lib/core/performance/adapters/sentry_performance_adapter.dart
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:injectable/injectable.dart';

/// Adapter for Sentry performance monitoring.
/// Sentry uses "transactions" (= traces) and "spans" (= sub-operations).
@Injectable(as: PerformanceMonitor, env: ['sentry'])
class SentryPerformanceAdapter implements PerformanceMonitor {

  @override
  Future<PerformanceTrace> startTrace(String name) async {
    final transaction = Sentry.startTransaction(name, 'task');
    return _SentryTrace(transaction);
  }

  @override
  Future<void> recordTrace(
    String name,
    Future<void> Function() operation, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    final transaction = Sentry.startTransaction(name, 'task');
    attributes?.forEach((k, v) => transaction.setTag(k, v));

    try {
      await operation();
      metrics?.forEach((k, v) => transaction.setMeasurement(k, v.toDouble()));
      transaction.status = SpanStatus.ok();
    } catch (e) {
      transaction.throwable = e;
      transaction.status = SpanStatus.internalError();
      rethrow;
    } finally {
      await transaction.finish();
    }
  }
}

class _SentryTrace implements PerformanceTrace {
  final ISentrySpan _transaction;
  _SentryTrace(this._transaction);

  @override
  void putAttribute(String name, String value) =>
      _transaction.setTag(name, value);

  @override
  void putMetric(String name, int value) =>
      _transaction.setMeasurement(name, value.toDouble());

  @override
  Future<void> stop() async {
    _transaction.status = SpanStatus.ok();
    await _transaction.finish();
  }
}
```

---

## 4. Datadog Adapter (Enterprise — RUM + APM)

```dart
// lib/core/performance/adapters/datadog_performance_adapter.dart
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:injectable/injectable.dart';

/// Adapter for Datadog RUM performance monitoring.
@Injectable(as: PerformanceMonitor, env: ['datadog'])
class DatadogPerformanceAdapter implements PerformanceMonitor {

  @override
  Future<PerformanceTrace> startTrace(String name) async {
    // Datadog uses RUM actions and custom timings
    DatadogSdk.instance.rum?.startAction(
      RumActionType.custom,
      name,
      {},
    );
    return _DatadogTrace(name);
  }

  @override
  Future<void> recordTrace(
    String name,
    Future<void> Function() operation, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    final stopwatch = Stopwatch()..start();
    DatadogSdk.instance.rum?.startAction(RumActionType.custom, name, {
      ...?attributes,
    });

    try {
      await operation();
      stopwatch.stop();
      DatadogSdk.instance.rum?.stopAction(RumActionType.custom, name, {
        'duration_ms': stopwatch.elapsedMilliseconds,
        ...?attributes,
        ...?metrics?.map((k, v) => MapEntry(k, v)),
      });
    } catch (e) {
      stopwatch.stop();
      DatadogSdk.instance.rum?.stopAction(RumActionType.custom, name, {
        'error': '$e',
        'duration_ms': stopwatch.elapsedMilliseconds,
      });
      rethrow;
    }
  }
}

class _DatadogTrace implements PerformanceTrace {
  final String _name;
  final Map<String, String> _attributes = {};
  final Map<String, int> _metrics = {};

  _DatadogTrace(this._name);

  @override
  void putAttribute(String name, String value) => _attributes[name] = value;

  @override
  void putMetric(String name, int value) => _metrics[name] = value;

  @override
  Future<void> stop() async {
    DatadogSdk.instance.rum?.stopAction(RumActionType.custom, _name, {
      ..._attributes,
      ..._metrics.map((k, v) => MapEntry(k, v)),
    });
  }
}
```

---

## 5. NoOp Adapter (Debug / Tests — zero overhead)

```dart
// lib/core/performance/adapters/noop_performance_adapter.dart
import 'package:injectable/injectable.dart';

/// No-op adapter — does nothing. Use in debug builds and tests.
/// Eliminates performance monitoring overhead during development.
@Injectable(as: PerformanceMonitor, env: [Environment.dev, Environment.test])
class NoOpPerformanceAdapter implements PerformanceMonitor {
  @override
  Future<PerformanceTrace> startTrace(String name) async =>
      const _NoOpTrace();

  @override
  Future<void> recordTrace(
    String name,
    Future<void> Function() operation, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) =>
      operation();
}

class _NoOpTrace implements PerformanceTrace {
  const _NoOpTrace();

  @override
  void putAttribute(String name, String value) {}

  @override
  void putMetric(String name, int value) {}

  @override
  Future<void> stop() async {}
}
```

---

## 6. DI Binding — One Line to Swap Providers

```dart
// lib/core/di/performance_module.dart
import 'package:injectable/injectable.dart';

@module
abstract class PerformanceModule {
  // ✅ Change this one binding to swap providers
  @lazySingleton
  PerformanceMonitor performanceMonitor(
    FirebasePerformanceAdapter firebase,
    SentryPerformanceAdapter sentry,
    DatadogPerformanceAdapter datadog,
    NoOpPerformanceAdapter noOp,
  ) {
    const provider = String.fromEnvironment(
      'PERF_PROVIDER',
      defaultValue: 'firebase',
    );
    return switch (provider) {
      'sentry' => sentry,
      'datadog' => datadog,
      'noop' => noOp,
      _ => kReleaseMode ? firebase : noOp,
    };
  }
}
```

```bash
# Build with specific provider
flutter build apk --dart-define=PERF_PROVIDER=firebase
flutter build apk --dart-define=PERF_PROVIDER=sentry
flutter run --dart-define=PERF_PROVIDER=noop  # development
```

---

## 7. Usage in Repository / UseCase

```dart
// lib/features/checkout/domain/usecases/submit_order_usecase.dart
@injectable
class SubmitOrderUseCase {
  final CheckoutRepository _repository;
  final PerformanceMonitor _monitor;

  SubmitOrderUseCase(this._repository, this._monitor);

  Future<Either<CheckoutFailure, Order>> call(Cart cart) async {
    // ✅ Uses PerformanceMonitor interface — not Firebase SDK directly
    final trace = await _monitor.startTrace('checkout_submit');
    trace.putAttribute('payment_method', cart.paymentMethod.name);
    trace.putAttribute('item_count', cart.items.length.toString());

    try {
      final result = await _repository.submitOrder(cart);
      result.fold(
        (failure) => trace.putAttribute('status', 'error'),
        (order) {
          trace.putAttribute('status', 'success');
          trace.putMetric('order_total_cents', (order.total * 100).round());
        },
      );
      return result;
    } finally {
      await trace.stop(); // ✅ always stop in finally
    }
  }
}
```

---

## 8. Testing — NoOp Adapter

```dart
// test/features/checkout/domain/usecases/submit_order_usecase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockCheckoutRepository extends Mock implements CheckoutRepository {}

void main() {
  late SubmitOrderUseCase useCase;
  late MockCheckoutRepository mockRepo;

  setUp(() {
    mockRepo = MockCheckoutRepository();
    useCase = SubmitOrderUseCase(
      mockRepo,
      NoOpPerformanceAdapter(), // ✅ zero overhead in tests
    );
  });

  test('submits order and returns success', () async {
    when(() => mockRepo.submitOrder(any()))
        .thenAnswer((_) async => Right(Order.mock()));

    final result = await useCase(Cart.mock());
    expect(result.isRight(), true);
  });
}
```

---

## Provider Comparison

| Feature | Firebase | Sentry | Datadog |
|---|---|---|---|
| Custom traces | ✅ | ✅ (transactions) | ✅ (RUM actions) |
| HTTP monitoring | ✅ automatic | ✅ automatic | ✅ automatic |
| Error correlation | ⚠️ via Crashlytics | ✅ built-in | ✅ built-in |
| Session replay | ❌ | ✅ (v9+) | ✅ |
| Distributed tracing | ❌ | ✅ | ✅ |
| Free tier | ✅ generous | ✅ limited | ❌ paid |
| Flutter 3.27+ | ✅ | ✅ | ✅ (v3.0+) |
| Setup complexity | Low | Low | Medium |
