# Long-Lived Isolates — Isolate.spawn()

For workers that stay alive, process multiple messages, and communicate bidirectionally.
Use when the setup cost of spawning a new isolate per task is too high, or when
you need streaming results from a continuous background process.

## Core Concepts

```
Main isolate                    Worker isolate
     │                               │
     │──── SendPort (to worker) ────►│
     │                               │
     │◄─── SendPort (to main) ───────│
     │                               │
     │──── message ─────────────────►│ process
     │◄─── result ───────────────────│
     │                               │
     │──── kill ────────────────────►│ (Isolate.kill)
```

## IsolateWorker — Reusable Pattern

```dart
// lib/core/isolate/isolate_worker.dart
import 'dart:isolate';
import 'dart:async';

/// A long-lived isolate that processes messages and returns results.
/// Manages its own lifecycle — call dispose() when done.
class IsolateWorker<TInput, TOutput> {
  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final Map<int, Completer<TOutput>> _pending = {};
  int _nextId = 0;

  IsolateWorker._(this._isolate, this._sendPort, this._receivePort);

  /// Spawn the worker isolate and establish bidirectional communication.
  static Future<IsolateWorker<TInput, TOutput>> create<TInput, TOutput>(
    void Function(SendPort) entryPoint,
  ) async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(entryPoint, receivePort.sendPort);

    // First message from the isolate is its SendPort
    final sendPort = await receivePort.first as SendPort;

    final worker = IsolateWorker<TInput, TOutput>._(
      isolate,
      sendPort,
      receivePort,
    );

    // Listen for results
    receivePort.skip(1).listen((message) {
      if (message is _WorkerResponse<TOutput>) {
        final completer = worker._pending.remove(message.id);
        if (message.error != null) {
          completer?.completeError(message.error!);
        } else {
          completer?.complete(message.result);
        }
      }
    });

    return worker;
  }

  /// Send a message to the worker and await the result.
  Future<TOutput> send(TInput input) {
    final id = _nextId++;
    final completer = Completer<TOutput>();
    _pending[id] = completer;
    _sendPort.send(_WorkerRequest(id: id, input: input));
    return completer.future;
  }

  /// Kill the isolate and clean up resources.
  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
    // Complete any pending requests with an error
    for (final completer in _pending.values) {
      completer.completeError(StateError('Worker disposed'));
    }
    _pending.clear();
  }
}

// Message types — must be serializable (no Flutter objects)
class _WorkerRequest<T> {
  final int id;
  final T input;
  const _WorkerRequest({required this.id, required this.input});
}

class _WorkerResponse<T> {
  final int id;
  final T? result;
  final Object? error;
  const _WorkerResponse({required this.id, this.result, this.error});
}
```

## Worker Entry Point

```dart
// lib/core/isolate/data_processing_worker.dart
// Top-level function — required for Isolate.spawn()

@pragma('vm:entry-point')
void dataProcessingWorkerEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();

  // Send our SendPort to the main isolate so it can send us messages
  mainSendPort.send(receivePort.sendPort);

  // Process messages
  receivePort.listen((message) {
    if (message is _WorkerRequest<ProcessingInput>) {
      try {
        final result = _processData(message.input);
        mainSendPort.send(_WorkerResponse(id: message.id, result: result));
      } catch (e) {
        mainSendPort.send(_WorkerResponse(id: message.id, error: e));
      }
    }
  });
}

ProcessingOutput _processData(ProcessingInput input) {
  // CPU-intensive work here
  return ProcessingOutput(/* ... */);
}
```

## Streaming Results from a Long-Lived Isolate

```dart
// lib/core/isolate/streaming_worker.dart

@pragma('vm:entry-point')
void streamingWorkerEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _StreamRequest) {
      // Send multiple progress updates
      for (var i = 0; i <= 100; i += 10) {
        mainSendPort.send(_ProgressUpdate(
          requestId: message.id,
          progress: i / 100.0,
          partial: _processChunk(message.data, i),
        ));
      }
      // Signal completion
      mainSendPort.send(_StreamComplete(requestId: message.id));
    }
  });
}

// Usage:
class StreamingIsolateWorker {
  late final Isolate _isolate;
  late final SendPort _sendPort;
  late final ReceivePort _receivePort;

  Future<void> init() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      streamingWorkerEntryPoint,
      _receivePort.sendPort,
    );
    _sendPort = await _receivePort.first as SendPort;
  }

  Stream<double> processWithProgress(ProcessingData data) {
    final controller = StreamController<double>();
    final requestId = DateTime.now().microsecondsSinceEpoch;

    _sendPort.send(_StreamRequest(id: requestId, data: data));

    _receivePort.listen((message) {
      if (message is _ProgressUpdate && message.requestId == requestId) {
        controller.add(message.progress);
      } else if (message is _StreamComplete && message.requestId == requestId) {
        controller.close();
      }
    });

    return controller.stream;
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
  }
}
```

## Clean Architecture Integration

```dart
// lib/features/data_processing/data/datasources/processing_data_source.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@lazySingleton
class ProcessingDataSource {
  IsolateWorker<ProcessingInput, ProcessingOutput>? _worker;

  Future<void> initialize() async {
    _worker = await IsolateWorker.create(dataProcessingWorkerEntryPoint);
  }

  Future<Either<ProcessingFailure, ProcessingOutput>> process(
    ProcessingInput input,
  ) async {
    if (_worker == null) {
      return const Left(ProcessingFailure.notInitialized());
    }
    try {
      final result = await _worker!.send(input);
      return Right(result);
    } catch (e) {
      return Left(ProcessingFailure.failed(message: '$e'));
    }
  }

  void dispose() {
    _worker?.dispose();
    _worker = null;
  }
}
```

## BLoC with Long-Lived Worker

```dart
// lib/features/data_processing/presentation/bloc/processing_bloc.dart
@injectable
class ProcessingBloc extends Bloc<ProcessingEvent, ProcessingState> {
  final ProcessingDataSource _dataSource;
  StreamSubscription<double>? _progressSub;

  ProcessingBloc(this._dataSource) : super(const ProcessingState.idle()) {
    on<StartProcessingEvent>(_onStart);
    on<ProgressUpdateEvent>(_onProgress);
    on<CancelProcessingEvent>(_onCancel);
  }

  Future<void> _onStart(
    StartProcessingEvent event,
    Emitter<ProcessingState> emit,
  ) async {
    emit(const ProcessingState.processing(progress: 0.0));

    final result = await _dataSource.process(event.input);

    result.fold(
      (failure) => emit(ProcessingState.error(failure.message)),
      (output) => emit(ProcessingState.completed(output: output)),
    );
  }

  void _onProgress(
    ProgressUpdateEvent event,
    Emitter<ProcessingState> emit,
  ) {
    emit(ProcessingState.processing(progress: event.progress));
  }

  void _onCancel(
    CancelProcessingEvent event,
    Emitter<ProcessingState> emit,
  ) {
    _progressSub?.cancel();
    emit(const ProcessingState.idle());
  }

  @override
  Future<void> close() async {
    _progressSub?.cancel();
    return super.close();
  }
}
```

## When to Use Long-Lived vs One-Shot

| Scenario | Recommendation |
|---|---|
| Parse one JSON response | `Isolate.run()` — one-shot |
| Parse many JSON responses (list screen) | `worker_manager` — pool |
| Continuous sensor data processing | Long-lived `Isolate.spawn()` |
| Image processing pipeline | Long-lived or `worker_manager` |
| Single encryption operation | `Isolate.run()` — one-shot |
| Background sync loop | Long-lived `Isolate.spawn()` |
| Multiple concurrent tasks | `worker_manager` or `isolate_manager` |
