# Completer and Cancellable Operations

`Completer` gives manual control over a `Future`.
`CancelToken` (Dio) makes HTTP requests cancellable.
Both are essential for clean resource management.

---

## Completer — Manual Future Control

```dart
import 'dart:async';

// Completer bridges callback-based APIs to Future-based code
// and enables manual completion from outside the async chain.

// ✅ Basic usage
final completer = Completer<String>();

// Complete from anywhere — once only
void onDataReceived(String data) {
  if (!completer.isCompleted) {
    completer.complete(data);
  }
}

void onError(Object error) {
  if (!completer.isCompleted) {
    completer.completeError(error);
  }
}

// Await the result
final result = await completer.future;
```

### Completer as a one-time gate

```dart
// lib/core/auth/auth_ready_gate.dart
// Blocks all requests until authentication is initialized.
import 'dart:async';
import 'package:injectable/injectable.dart';

@lazySingleton
class AuthReadyGate {
  final _completer = Completer<void>();

  /// Wait until auth is initialized before proceeding.
  Future<void> get ready => _completer.future;

  /// Call once when auth initialization is complete.
  void markReady() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Call if auth initialization fails.
  void markFailed(Object error) {
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}

// In AuthBloc — mark ready after initialization
Future<void> _onInitialize(InitializeEvent event, Emitter emit) async {
  try {
    await _authService.initialize();
    GetIt.instance<AuthReadyGate>().markReady();
  } catch (e) {
    GetIt.instance<AuthReadyGate>().markFailed(e);
  }
}

// In any interceptor or service — wait for auth before proceeding
@override
Future<void> onRequest(options, handler) async {
  await GetIt.instance<AuthReadyGate>().ready; // blocks until auth is ready
  options.headers['Authorization'] = 'Bearer ${await _tokenRepo.getToken()}';
  handler.next(options);
}
```

### Completer with timeout

```dart
Future<T> withTimeout<T>(
  Future<T> Function() operation,
  Duration timeout,
) async {
  final completer = Completer<T>();

  // Start the operation
  operation().then(
    (value) { if (!completer.isCompleted) completer.complete(value); },
    onError: (e) { if (!completer.isCompleted) completer.completeError(e); },
  );

  // Start the timeout
  Future.delayed(timeout, () {
    if (!completer.isCompleted) {
      completer.completeError(
        TimeoutException('Operation timed out after $timeout'),
      );
    }
  });

  return completer.future;
}

// Usage:
final result = await withTimeout(
  () => _api.fetchData(),
  const Duration(seconds: 10),
);
```

---

## CancelToken — Cancellable HTTP Requests

```dart
// lib/features/product/data/datasources/product_remote_data_source.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class ProductRemoteDataSource {
  final Dio _dio;
  ProductRemoteDataSource(this._dio);

  Future<Either<Failure, List<ProductDto>>> getProducts({
    required String categoryId,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.get(
        '/products',
        queryParameters: {'categoryId': categoryId},
        cancelToken: cancelToken, // ✅ pass through
      );
      return Right((response.data as List)
          .map((e) => ProductDto.fromJson(e))
          .toList());
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        return const Left(Failure.cancelled());
      }
      return Left(Failure.network(message: e.message ?? 'Network error'));
    }
  }
}
```

### CancelToken in BLoC — cancel on new event

```dart
// lib/features/product/presentation/bloc/product_bloc.dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final ProductRepository _repository;
  CancelToken? _cancelToken;

  ProductBloc(this._repository) : super(const ProductState.initial()) {
    on<LoadProductsEvent>(
      _onLoad,
      transformer: restartable(), // cancels previous handler
    );
  }

  Future<void> _onLoad(
    LoadProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    // Cancel any in-flight request from the previous handler
    _cancelToken?.cancel('New request started');
    _cancelToken = CancelToken();

    emit(const ProductState.loading());

    final result = await _repository.getProducts(
      categoryId: event.categoryId,
      cancelToken: _cancelToken,
    );

    result.fold(
      (failure) {
        if (failure is! Cancelled) {
          emit(ProductState.error(failure.message));
        }
        // Silently ignore cancellation — a new request is already in flight
      },
      (products) => emit(ProductState.success(products: products)),
    );
  }

  @override
  Future<void> close() async {
    _cancelToken?.cancel('BLoC closed');
    return super.close();
  }
}
```

### CancelToken in StatefulWidget

```dart
class _ProductDetailState extends State<ProductDetail> {
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _cancelToken = CancelToken();
    try {
      final product = await _repository.getProduct(
        widget.productId,
        cancelToken: _cancelToken,
      );
      if (mounted) setState(() => _product = product);
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel && mounted) {
        setState(() => _error = e.message);
      }
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel('Widget disposed'); // ✅ cancel on dispose
    super.dispose();
  }
}
```

---

## Cancellable Operation — Pure Dart (no Dio)

For non-HTTP async operations that need cancellation:

```dart
// lib/core/concurrency/cancellable_operation.dart
class CancellableOperation<T> {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Run an operation that checks for cancellation at each step.
  Future<T?> run(Future<T> Function(CancellableOperation<T> op) fn) async {
    if (_cancelled) return null;
    return fn(this);
  }
}

// Usage — long-running data processing with cancellation checkpoints
Future<List<ProcessedItem>?> processItems(List<RawItem> items) async {
  final op = CancellableOperation<List<ProcessedItem>>();

  return op.run((op) async {
    final results = <ProcessedItem>[];
    for (final item in items) {
      if (op.isCancelled) return results; // checkpoint
      results.add(await processItem(item));
    }
    return results;
  });
}
```

---

## Race Condition — First Wins vs Last Wins

```dart
// ❌ Race condition: last response wins regardless of order
Future<void> _onSearch(String query) async {
  final results = await _api.search(query);
  setState(() => _results = results); // may be stale if a newer query finished first
}

// ✅ Last request wins — cancel previous with CancelToken
CancelToken? _searchToken;

Future<void> _onSearch(String query) async {
  _searchToken?.cancel();
  _searchToken = CancelToken();

  try {
    final results = await _api.search(query, cancelToken: _searchToken);
    if (mounted) setState(() => _results = results);
  } on DioException catch (e) {
    if (e.type != DioExceptionType.cancel && mounted) {
      setState(() => _error = e.message);
    }
  }
}

// ✅ First request wins — ignore subsequent until first completes
bool _isLoading = false;

Future<void> _onLoad() async {
  if (_isLoading) return; // drop subsequent calls
  _isLoading = true;
  try {
    final data = await _api.loadData();
    if (mounted) setState(() => _data = data);
  } finally {
    _isLoading = false;
  }
}
```

---

## Testing Completer and Cancellation

```dart
void main() {
  group('CancellableOperation', () {
    test('returns null when cancelled before start', () async {
      final op = CancellableOperation<String>();
      op.cancel();

      final result = await op.run((_) async => 'result');
      expect(result, isNull);
    });

    test('stops processing at checkpoint when cancelled', () async {
      final op = CancellableOperation<List<int>>();
      var processedCount = 0;

      final items = List.generate(10, (i) => i);
      final result = await op.run((op) async {
        final results = <int>[];
        for (final item in items) {
          if (op.isCancelled) break;
          if (item == 5) op.cancel(); // cancel mid-way
          results.add(item);
          processedCount++;
        }
        return results;
      });

      expect(processedCount, lessThan(10));
    });
  });

  group('AuthReadyGate', () {
    test('blocks until markReady is called', () async {
      final gate = AuthReadyGate();
      var readyReceived = false;

      gate.ready.then((_) => readyReceived = true);

      expect(readyReceived, false);
      gate.markReady();
      await Future.microtask(() {}); // let microtask queue drain
      expect(readyReceived, true);
    });
  });
}
```
