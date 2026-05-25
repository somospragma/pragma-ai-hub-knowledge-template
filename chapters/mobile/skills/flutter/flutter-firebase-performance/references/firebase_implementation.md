# Firebase Performance — Implementation Guide

Firebase Performance Monitoring automatically tracks app startup, HTTP requests,
and screen rendering. Custom traces let you measure specific code paths.

## Setup

```yaml
dependencies:
  firebase_performance: ^0.11.3
  firebase_core: ^4.7.0
  dio: ^5.9.2
```

```dart
// main.dart — initialize before runApp
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Disable in debug — avoids noise and overhead during development
  await FirebasePerformance.instance.setPerformanceCollectionEnabled(kReleaseMode);

  await configureDependencies();
  runApp(const App());
}
```

### Platform requirements (0.11.x)

```groovy
// android/app/build.gradle
android {
    defaultConfig {
        minSdk 21        // 0.11.x requires minSdk 21 (raised from 19)
        targetSdk 35
        compileSdk 35
    }
}
```

```ruby
# ios/Podfile
platform :ios, '13.0'  # 0.11.x requires iOS 13+ (raised from iOS 12)
```

---

## Startup Trace — Measure Initialization Time

```dart
// lib/core/performance/startup_trace.dart
import 'package:firebase_performance/firebase_performance.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class StartupTrace {
  Trace? _trace;

  Future<void> start() async {
    if (!kReleaseMode) return;
    _trace = FirebasePerformance.instance.newTrace('app_startup');
    await _trace?.start();
  }

  Future<void> stop({required String firstScreen}) async {
    _trace?.putAttribute('first_screen', firstScreen);
    await _trace?.stop();
    _trace = null;
  }
}

// Usage in main.dart:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final startupTrace = StartupTrace();
  await startupTrace.start();

  await configureDependencies();
  runApp(const App());

  // Stop after first frame
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await startupTrace.stop(firstScreen: 'home');
  });
}
```

---

## Custom Traces — Measure Critical User Flows

```dart
// lib/core/performance/firebase_performance_adapter.dart
import 'package:firebase_performance/firebase_performance.dart';
import 'package:injectable/injectable.dart';

/// Thin wrapper around Firebase Performance for custom traces.
/// Use via PerformanceMonitor interface (see performance_provider_pattern.md).
@Injectable(as: PerformanceMonitor, env: [Environment.prod, 'staging'])
class FirebasePerformanceAdapter implements PerformanceMonitor {
  final FirebasePerformance _perf = FirebasePerformance.instance;

  @override
  Future<PerformanceTrace> startTrace(String name) async {
    final trace = _perf.newTrace(name);
    await trace.start();
    return FirebasePerformanceTrace(trace);
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

/// Wraps a Firebase Trace to implement PerformanceTrace interface.
class FirebasePerformanceTrace implements PerformanceTrace {
  final Trace _trace;
  FirebasePerformanceTrace(this._trace);

  @override
  void putAttribute(String name, String value) => _trace.putAttribute(name, value);

  @override
  void putMetric(String name, int value) => _trace.putMetric(name, value);

  @override
  Future<void> stop() => _trace.stop();
}
```

---

## HTTP Monitoring — Dio Interceptor

Firebase Performance automatically tracks HTTP requests made via the native
HTTP client. For Dio, add a manual interceptor to capture metrics.

```dart
// lib/core/network/performance_http_interceptor.dart
import 'package:dio/dio.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:injectable/injectable.dart';

@injectable
class PerformanceHttpInterceptor extends Interceptor {
  final FirebasePerformance _perf = FirebasePerformance.instance;
  final _activeMetrics = <String, HttpMetric>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!kReleaseMode) {
      handler.next(options);
      return;
    }

    final metric = _perf.newHttpMetric(
      options.uri.toString(),
      _mapMethod(options.method),
    );

    // Store metric keyed by request ID for retrieval in onResponse/onError
    final requestId = _requestId(options);
    _activeMetrics[requestId] = metric;

    metric.start().then((_) => handler.next(options));
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _stopMetric(
      options: response.requestOptions,
      statusCode: response.statusCode,
      responsePayloadSize: _estimateSize(response.data),
      requestPayloadSize: _estimateSize(response.requestOptions.data),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _stopMetric(
      options: err.requestOptions,
      statusCode: err.response?.statusCode,
    );
    handler.next(err);
  }

  void _stopMetric({
    required RequestOptions options,
    int? statusCode,
    int? responsePayloadSize,
    int? requestPayloadSize,
  }) {
    final requestId = _requestId(options);
    final metric = _activeMetrics.remove(requestId);
    if (metric == null) return;

    if (statusCode != null) metric.httpResponseCode = statusCode;
    if (responsePayloadSize != null) metric.responsePayloadSize = responsePayloadSize;
    if (requestPayloadSize != null) metric.requestPayloadSize = requestPayloadSize;

    metric.stop();
  }

  String _requestId(RequestOptions options) =>
      '${options.method}_${options.uri}_${options.hashCode}';

  HttpMethod _mapMethod(String method) => switch (method.toUpperCase()) {
    'GET' => HttpMethod.Get,
    'POST' => HttpMethod.Post,
    'PUT' => HttpMethod.Put,
    'DELETE' => HttpMethod.Delete,
    'PATCH' => HttpMethod.Patch,
    'HEAD' => HttpMethod.Head,
    'OPTIONS' => HttpMethod.Options,
    'CONNECT' => HttpMethod.Connect,
    'TRACE' => HttpMethod.Trace,
    _ => HttpMethod.Get,
  };

  int _estimateSize(dynamic data) {
    if (data == null) return 0;
    if (data is String) return data.length;
    if (data is List) return data.length;
    return data.toString().length;
  }
}
```

---

## Screen Trace — Measure Screen Render Time

```dart
// lib/core/performance/screen_trace_mixin.dart
import 'package:flutter/material.dart';
import 'package:firebase_performance/firebase_performance.dart';

/// Mixin that automatically traces screen render time.
/// Add to StatefulWidget State classes for key screens.
mixin ScreenTraceMixin<T extends StatefulWidget> on State<T> {
  Trace? _screenTrace;

  /// Override to provide the screen name for the trace.
  String get screenTraceName;

  @override
  void initState() {
    super.initState();
    _startTrace();
  }

  void _startTrace() async {
    if (!kReleaseMode) return;
    _screenTrace = FirebasePerformance.instance.newTrace(
      'screen_${screenTraceName.toLowerCase().replaceAll(' ', '_')}',
    );
    await _screenTrace?.start();
  }

  /// Call this when the screen has finished loading its data.
  void markScreenLoaded({Map<String, String>? attributes}) {
    attributes?.forEach((k, v) => _screenTrace?.putAttribute(k, v));
    _screenTrace?.stop();
    _screenTrace = null;
  }

  @override
  void dispose() {
    // Stop trace if not already stopped (e.g., user navigated away before load)
    _screenTrace?.stop();
    _screenTrace = null;
    super.dispose();
  }
}

// Usage:
class _ProductListState extends State<ProductListPage>
    with ScreenTraceMixin {
  @override
  String get screenTraceName => 'product_list';

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProductBloc, ProductState>(
      listener: (context, state) {
        if (state is ProductSuccess) {
          // Mark screen as loaded when data arrives
          markScreenLoaded(attributes: {
            'product_count': state.products.length.toString(),
            'category': widget.categoryId,
          });
        }
      },
      child: /* ... */,
    );
  }
}
```

---

## Custom Trace — Critical User Flow

```dart
// lib/features/checkout/data/repositories/checkout_repository_impl.dart

Future<Either<CheckoutFailure, Order>> submitOrder(Cart cart) async {
  // ✅ Wrap the entire checkout flow in a trace
  final trace = FirebasePerformance.instance.newTrace('checkout_submit');
  trace.putAttribute('payment_method', cart.paymentMethod.name);
  trace.putAttribute('item_count', cart.items.length.toString());
  await trace.start();

  try {
    final order = await _api.submitOrder(cart);
    trace.putMetric('order_total_cents', (order.total * 100).round());
    trace.putAttribute('status', 'success');
    return Right(order);
  } on DioException catch (e) {
    trace.putAttribute('status', 'error');
    trace.putAttribute('error_code', '${e.response?.statusCode}');
    return Left(CheckoutFailure.network(message: e.message ?? 'Network error'));
  } finally {
    await trace.stop(); // ✅ always stop in finally
  }
}
```

---

## Firebase Console — Alerts Setup

After deploying, configure alerts in Firebase Console → Performance:

```
1. Go to Firebase Console → Performance Monitoring
2. Select a trace (e.g., "checkout_submit")
3. Click "Add alert"
4. Configure:
   - Metric: Duration (p95)
   - Threshold: > 3000ms
   - Notification: email / Slack webhook
5. Repeat for:
   - app_startup > 2000ms
   - HTTP /api/products > 500ms p95
   - screen_product_list > 300ms
```
