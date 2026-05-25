---
name: flutter-isolates
description: >
  Runs CPU-intensive work off the main thread using Dart isolates: compute(), Isolate.run() for one-shot tasks, Isolate.spawn() for long-lived workers, worker_manager for isolate pools with cancellation and progress, and isolate_manager for cross-platform support (VM + Web Workers + WASM). Use this skill when JSON parsing, image processing, encryption, data transformation, or any CPU-bound work causes UI jank or dropped frames.
commands:
  - implement-isolate
inputs:
  - name: pattern
    description: Isolate pattern to implement (one-shot, long-lived, pool, cross-platform). "one-shot" uses Isolate.run for single tasks, "long-lived" uses Isolate.spawn with bidirectional comms, "pool" uses worker_manager for reusable isolates with cancellation, "cross-platform" uses isolate_manager for mobile + web + WASM.
    required: true
  - name: target
    description: Path to the file or feature where the isolate work will be implemented (e.g. lib/features/product/data/data_sources/product_parser.dart).
    required: true
  - name: task
    description: Description of the CPU-intensive task to offload (e.g. json-parsing, image-processing, encryption, data-transformation). Helps determine the optimal pattern and data serialization approach.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Dart Isolates & Workers

See the reference files for complete patterns and code examples.

**Rule: If it takes > 16ms on the main thread, move it to an isolate.**

## Key Concept — No Shared Memory

Dart isolates are true parallel workers. Unlike threads in Java/Kotlin, they do **not**
share memory. All data is copied via message passing (`SendPort`/`ReceivePort`).
This eliminates race conditions but means large objects have a copy cost.

---

## API Selection Guide

| API | Use when | Notes |
|---|---|---|
| `compute(fn, arg)` | Simple one-shot task, single arg/result | Thin wrapper over `Isolate.run` |
| `Isolate.run(fn)` | One-shot task, any return type | Dart 2.19+, preferred over `compute` |
| `Isolate.spawn()` | Long-lived worker, bidirectional comms | Manual lifecycle management |
| `worker_manager` | Pool of reusable isolates, cancellation, progress | Best for many short tasks |
| `isolate_manager` | Cross-platform (mobile + web + WASM) | Auto-compiles to JS Workers on web |

---

## Package Status (April 2026)

| Package | Version | Purpose |
|---|---|---|
| **worker_manager** | 4.x | Isolate pool, cancellation, progress, gentle cancel |
| **isolate_manager** | 5.x | Cross-platform isolates + Web Workers + WASM |
| **squadron** | 6.x | Worker thread pool, JS+WASM support |

---

## Quick Patterns

### One-shot (Isolate.run — preferred)
```dart
// Runs fn in a new isolate, returns result, isolate is killed automatically
final result = await Isolate.run(() => parseHeavyJson(rawJson));
```

### Isolate pool with cancellation (worker_manager)
```dart
final cancelable = workerManager.execute<List<Product>>(
  () => parseProducts(rawJson),
  priority: WorkPriority.immediately,
);
// Cancel if user navigates away
cancelable.cancel();
```

### Long-lived worker (Isolate.spawn)
```dart
// Bidirectional communication — worker stays alive, processes multiple messages
final worker = await IsolateWorker.create();
final result = await worker.send(WorkerMessage.process(data));
worker.dispose(); // kill when done
```

### Cross-platform (isolate_manager — mobile + web + WASM)
```dart
@pragma('vm:entry-point')
int heavyComputation(int input) => /* ... */;

final manager = IsolateManager.create(heavyComputation, concurrent: 2);
await manager.start();
final result = await manager.compute(42);
await manager.stop();
```

---

## What Belongs in an Isolate

```
✅ JSON parsing of large payloads (> 1MB)
✅ Image processing (resize, compress, filter)
✅ Encryption / decryption / hashing
✅ Data transformation (sort, filter, aggregate large lists)
✅ PDF generation / parsing
✅ CSV / Excel parsing
✅ Complex mathematical computations
✅ Text search / indexing

❌ Network requests (already async, non-blocking)
❌ Database queries (Drift/ObjectBox handle isolates internally)
❌ Simple UI state updates
❌ Short operations < 1ms
```

---

## Critical Rules

| Rule | Reason |
|---|---|
| Entry point must be top-level or static | Isolates cannot access instance state |
| Annotate with `@pragma('vm:entry-point')` | Prevents AOT tree-shaking |
| Pass only serializable data | No `BuildContext`, `Stream`, `ChangeNotifier` |
| Always kill long-lived isolates | Memory leak if not disposed |
| Cancel `worker_manager` tasks in `dispose()` | Prevents work after widget is gone |

---

## Architecture Integration

```
Presentation (BLoC)
  ↓
Domain (UseCase)
  ↓
Data (RepositoryImpl / DataSource)
  └── IsolateWorker / workerManager.execute()
        ↓ (separate isolate)
        CPU-intensive function (top-level or static)
```

---

## Quick Wins Checklist

- [ ] `Isolate.run()` used instead of `compute()` for new code
- [ ] All isolate entry points are top-level or static functions
- [ ] All entry points annotated with `@pragma('vm:entry-point')`
- [ ] Long-lived isolates disposed in `dispose()` or BLoC `close()`
- [ ] `worker_manager` cancelables cancelled in BLoC `close()`
- [ ] Only serializable data passed to isolates (no Flutter objects)
- [ ] `isolate_manager` used when targeting web/WASM

## Reference Files

- `references/one_shot_isolates.md` — compute(), Isolate.run(), clean architecture integration
- `references/long_lived_isolates.md` — Isolate.spawn(), bidirectional comms, IsolateWorker pattern
- `references/worker_packages.md` — worker_manager pool, isolate_manager cross-platform, squadron
