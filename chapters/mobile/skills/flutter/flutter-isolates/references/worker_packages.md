# Worker Packages — worker_manager, isolate_manager, squadron

Higher-level abstractions over raw isolates: pools, cancellation, progress,
and cross-platform support (Web Workers + WASM).

---

## worker_manager — Isolate Pool with Cancellation

Best for: many short-to-medium CPU tasks, cancellable work, progress reporting.
Reuses isolates instead of spawning a new one per task — more efficient than `compute()`.

### Setup

```yaml
dependencies:
  worker_manager: ^4.0.0
```

### Initialization

```dart
// lib/core/di/worker_module.dart
import 'package:worker_manager/worker_manager.dart';
import 'package:injectable/injectable.dart';

@module
abstract class WorkerModule {
  @singleton
  @preResolve
  Future<Executor> get workerManager async {
    // warmUpCount: number of isolates to pre-spawn
    // useOneIsolateOnly: true = single isolate (useful for ordered tasks)
    await workerManager.warmUp(log: false);
    return workerManager;
  }
}
```

### Basic Execution

```dart
// lib/features/product/data/datasources/product_parser.dart
import 'package:worker_manager/worker_manager.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class ProductParser {
  final Executor _executor;
  ProductParser(this._executor);

  // ── Simple execution ──────────────────────────────────────────────────

  Future<Either<ParseFailure, List<Product>>> parseProducts(
    String rawJson,
  ) async {
    try {
      final result = await _executor.execute(
        () => _parseProductsIsolate(rawJson),
        priority: WorkPriority.immediately,
      );
      return Right(result);
    } catch (e) {
      return Left(ParseFailure.failed(message: '$e'));
    }
  }

  // ── Cancellable execution ─────────────────────────────────────────────

  Cancelable<List<Product>>? _currentTask;

  Cancelable<List<Product>> parseProductsCancellable(String rawJson) {
    _currentTask?.cancel(); // cancel previous if still running
    _currentTask = _executor.execute(
      () => _parseProductsIsolate(rawJson),
      priority: WorkPriority.immediately,
    );
    return _currentTask!;
  }

  void cancelCurrentTask() => _currentTask?.cancel();

  // ── Execution with progress ───────────────────────────────────────────

  Cancelable<ProcessingResult> processWithProgress({
    required List<RawItem> items,
    required void Function(String message) onProgress,
  }) {
    return _executor.executeWithPort<ProcessingResult, String>(
      (SendPort sendPort) async {
        for (var i = 0; i < items.length; i++) {
          sendPort.send('Processing item ${i + 1}/${items.length}');
          // process items[i]
        }
        return ProcessingResult(/* ... */);
      },
      onMessage: onProgress,
      priority: WorkPriority.high,
    );
  }

  // ── Gentle cancellation (check periodically, clean up gracefully) ─────

  Cancelable<ProcessingResult> processGently(List<RawItem> items) {
    return _executor.executeGentle<ProcessingResult>(
      (IsCanceled isCanceled) async {
        final results = <ProcessedItem>[];
        for (final item in items) {
          if (isCanceled()) break; // check before each item
          results.add(processItem(item));
        }
        return ProcessingResult(items: results);
      },
      priority: WorkPriority.immediately,
    );
  }
}

// Entry point — top-level, outside any class
@pragma('vm:entry-point')
List<Product> _parseProductsIsolate(String rawJson) {
  final list = jsonDecode(rawJson) as List;
  return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
}
```

### BLoC with Cancellable Tasks

```dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final ProductParser _parser;
  Cancelable<List<Product>>? _parseTask;

  ProductBloc(this._parser) : super(const ProductState.initial()) {
    on<ParseProductsEvent>(_onParse);
    on<CancelParseEvent>(_onCancel);
  }

  Future<void> _onParse(
    ParseProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    emit(const ProductState.loading());

    try {
      _parseTask = _parser.parseProductsCancellable(event.rawJson);
      final products = await _parseTask!;
      emit(ProductState.success(products: products));
    } on CanceledError {
      emit(const ProductState.cancelled());
    } catch (e) {
      emit(ProductState.error('Parse failed: $e'));
    }
  }

  void _onCancel(CancelParseEvent event, Emitter<ProductState> emit) {
    _parseTask?.cancel();
    emit(const ProductState.cancelled());
  }

  @override
  Future<void> close() async {
    _parseTask?.cancel(); // ✅ always cancel on close
    await workerManager.dispose();
    return super.close();
  }
}
```

---

## isolate_manager — Cross-Platform (VM + Web Workers + WASM)

Best for: apps targeting web or WASM in addition to mobile.
Automatically compiles isolate functions to JavaScript Workers on web.

### Setup

```yaml
dependencies:
  isolate_manager: ^5.0.0

dev_dependencies:
  isolate_manager_generator: ^5.0.0
  build_runner: ^2.14.1
```

### Basic Usage

```dart
// lib/core/isolate/heavy_computation.dart
import 'package:isolate_manager/isolate_manager.dart';

// Annotate for web worker generation
@pragma('vm:entry-point')
@isolateManagerWorker
int computeSum(List<int> numbers) {
  return numbers.reduce((a, b) => a + b);
}

// Usage:
final manager = IsolateManager.create(
  computeSum,
  concurrent: 2,  // number of parallel isolates
);

await manager.start();

// Compute — works on VM (isolate) and web (JS Worker) transparently
final result = await manager.compute([1, 2, 3, 4, 5]);
print(result); // 15

await manager.stop();
```

### With Progress Reporting

```dart
@pragma('vm:entry-point')
@isolateManagerWorker
int processWithProgress(
  List<int> data,
  IsolateManagerController controller,
) {
  var sum = 0;
  for (var i = 0; i < data.length; i++) {
    sum += data[i];
    // Send progress update
    controller.sendResult(i / data.length);
  }
  return sum;
}

// Listen to progress:
manager.stream.listen((result) {
  if (result is double) {
    print('Progress: ${(result * 100).toStringAsFixed(0)}%');
  } else if (result is int) {
    print('Final result: $result');
  }
});

await manager.compute(largeDataset);
```

### Generate Web Workers

```bash
# Generates .js worker files for web deployment
dart run isolate_manager:generate
```

### DI Registration

```dart
@module
abstract class IsolateManagerModule {
  @singleton
  @preResolve
  Future<IsolateManager<int, List<int>>> get computeSumManager async {
    final manager = IsolateManager.create(computeSum, concurrent: 2);
    await manager.start();
    return manager;
  }
}
```

---

## squadron — Worker Thread Pool (JS + WASM)

Best for: service-oriented worker architecture, complex worker APIs, JS+WASM targets.

### Setup

```yaml
dependencies:
  squadron: ^6.1.0
  squadron_builder: ^6.1.0

dev_dependencies:
  build_runner: ^2.14.1
```

### Worker Service

```dart
// lib/core/workers/data_processing_service.dart
import 'package:squadron/squadron.dart';

part 'data_processing_service.activator.g.dart';
part 'data_processing_service.worker.g.dart';
part 'data_processing_service.worker_pool.g.dart';

@SquadronService(baseUrl: '~/workers', targetPlatform: TargetPlatform.all)
class DataProcessingService extends WorkerService {

  @SquadronMethod()
  Future<List<Product>> parseProducts(String rawJson) async {
    final list = jsonDecode(rawJson) as List;
    return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  @SquadronMethod()
  Stream<double> processWithProgress(List<RawItem> items) async* {
    for (var i = 0; i < items.length; i++) {
      // process items[i]
      yield (i + 1) / items.length;
    }
  }
}

// Usage with worker pool:
final pool = DataProcessingServiceWorkerPool(
  ConcurrencySettings(minWorkers: 1, maxWorkers: 4, maxParallel: 2),
);
await pool.start();

final products = await pool.parseProducts(rawJson);

await pool.stop();
```

```bash
# Generate worker files
dart run build_runner build
```

---

## Package Comparison

| Feature | worker_manager | isolate_manager | squadron |
|---|---|---|---|
| Isolate pool | ✅ | ✅ | ✅ |
| Cancellation | ✅ (Cancelable) | ✅ | ✅ |
| Progress reporting | ✅ (executeWithPort) | ✅ (stream) | ✅ (Stream) |
| Gentle cancellation | ✅ (executeGentle) | ❌ | ❌ |
| Web Workers | ❌ | ✅ (auto-compile) | ✅ |
| WASM | ❌ | ✅ | ✅ |
| Codegen required | ❌ | ✅ (web only) | ✅ |
| Service-oriented API | ❌ | ❌ | ✅ |
| Setup complexity | Low | Medium | High |

### Decision guide

```
Mobile only, need cancellation?          → worker_manager
Mobile + web + WASM?                     → isolate_manager
Complex worker API, service pattern?     → squadron
Simple one-shot, no pool needed?         → Isolate.run()
```
