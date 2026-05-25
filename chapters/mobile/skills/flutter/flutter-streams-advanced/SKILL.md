---
name: flutter-streams-advanced
description: >
  Implements advanced Dart Stream patterns using only native Dart and Flutter: single vs broadcast, StreamController, custom transformers, stream composition, and real-world use cases. State management covered with BLoC (bloc_concurrency) and Riverpod (StreamProvider, AsyncNotifier). No rxdart dependency. Use this skill when implementing reactive data flows, live search, real-time updates, event buses, pagination, or combining multiple async data sources.
commands:
  - implement-stream
inputs:
  - name: pattern
    description: Stream pattern to implement (live-search, real-time-feed, event-bus, pagination, multi-source, optimistic-update, connectivity-aware, custom-transformer).
    required: true
  - name: target
    description: Path to the file or feature where the stream pattern will be implemented (e.g. lib/features/chat/data/data_sources/chat_remote_data_source.dart).
    required: true
  - name: state_management
    description: State management approach to use (bloc, riverpod). Determines which integration pattern is generated.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Advanced Streams

See the reference files for complete patterns and code examples.

**Core principle: Streams are sequences of asynchronous events. Never block — transform and compose.**

## Dependencies

```yaml
dependencies:
  flutter_bloc: ^9.1.1
  bloc_concurrency: ^0.3.0   # sequential, droppable, restartable, concurrent
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  fpdart: ^1.2.0

dev_dependencies:
  riverpod_generator: ^2.6.1
  build_runner: ^2.14.1
```

No rxdart. Everything covered with native Dart streams + `bloc_concurrency`.

---

## Stream Types — Choose Correctly

| Type | Listeners | Use when |
|---|---|---|
| **Single-subscription** | 1 only | HTTP response, file read, one-time operation |
| **Broadcast** | Many | UI events, notifications, shared data feed |
| **StreamController** (broadcast) | Many | Event bus, manual push |

---

## Native Dart Operators — Quick Reference

```dart
stream.map(fn)            // transform each event
stream.where(predicate)   // filter events
stream.asyncMap(fn)       // async transform, one at a time
stream.asyncExpand(fn)    // async transform, flatten (like switchMap)
stream.expand(fn)         // sync flatten (one → many)
stream.distinct()         // skip consecutive duplicates
stream.take(n)            // first N events then close
stream.skip(n)            // skip first N events
stream.timeout(duration)  // error if no event within duration
stream.handleError(fn)    // recover from errors without terminating
stream.asBroadcastStream() // convert single → broadcast
```

---

## BLoC — EventTransformer (bloc_concurrency)

```dart
// restartable() — cancel current handler, start new (replaces switchMap)
on<SearchEvent>(_onSearch, transformer: restartable());

// droppable() — ignore new events while one is processing
on<SubmitEvent>(_onSubmit, transformer: droppable());

// sequential() — queue events, process one at a time
on<LoadPageEvent>(_onLoad, transformer: sequential());

// concurrent() — process all in parallel (default)
on<TrackEvent>(_onTrack, transformer: concurrent());
```

Debounce without rxdart → custom `_DebounceStreamTransformer` (see `references/bloc_streams.md`).

---

## Riverpod — Streams as First-Class Citizens

```dart
// StreamProvider — auto-subscribes, auto-disposes, loading/error/data built-in
@riverpod
Stream<List<Product>> products(ProductsRef ref, {required String categoryId}) =>
    ref.watch(productRepositoryProvider).watchProducts(categoryId);

// Debounce without rxdart — Riverpod cancels the previous Future automatically
@riverpod
Future<List<SearchResult>> searchResults(SearchResultsRef ref) async {
  final query = ref.watch(searchQueryProvider);
  await Future.delayed(const Duration(milliseconds: 300)); // debounce
  if (query.length < 2) return [];
  return ref.watch(searchRepositoryProvider).search(query);
}
```

---

## Real-World Use Cases

| Use case | Native Dart pattern |
|---|---|
| Live search | `_DebounceStreamTransformer` + `restartable()` (BLoC) / `Future.delayed` (Riverpod) |
| Real-time feed | Broadcast `StreamController` + `BehaviorSubject`-like pattern |
| Multi-source data | `StreamZip` / `asyncExpand` / Riverpod provider composition |
| Optimistic update | `async*` yield optimistic → yield confirmed/rollback |
| Pagination | `scan`-like accumulator with `asyncExpand` |
| Event bus | `StreamController.broadcast()` singleton |
| Connectivity-aware | `asyncExpand` on connectivity changes |

---

## Critical Rules

| Rule | Reason |
|---|---|
| Cancel `StreamSubscription` in `dispose()` / `close()` | Memory leak |
| Never expose `StreamController` — expose `.stream` only | Encapsulation |
| Use `broadcast()` for multiple listeners | Single-subscription throws on second listen |
| Close `StreamController` when done | Prevents memory leaks |
| `cancelOnError: false` in `listen()` | Stream continues after recoverable errors |

---

## Quick Wins Checklist

- [ ] `StreamSubscription` cancelled in `dispose()` or BLoC `close()`
- [ ] `StreamController` closed in `dispose()`
- [ ] `broadcast()` used when multiple widgets/blocs listen to the same stream
- [ ] `restartable()` used for search/navigation (replaces switchMap)
- [ ] `droppable()` used for form submission (prevents double-submit)
- [ ] `distinct()` used to prevent redundant rebuilds
- [ ] Errors handled with `handleError` — never swallowed silently
- [ ] No rxdart dependency

## Reference Files

- `references/stream_fundamentals.md` — StreamController, broadcast, custom transformers, error handling
- `references/bloc_streams.md` — BLoC EventTransformer, bloc_concurrency, debounce without rxdart
- `references/riverpod_streams.md` — StreamProvider, AsyncNotifier, debounce, multi-source composition
- `references/real_world_patterns.md` — live search, real-time feed, event bus, pagination, optimistic update
