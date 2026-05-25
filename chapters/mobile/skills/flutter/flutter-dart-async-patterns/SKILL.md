---
name: flutter-dart-async-patterns
description: >
  Implements correct async patterns in Flutter/Dart: Future, Stream, async/await, error handling, cancellation, parallel execution, timeouts, and Either-based results. Use this skill when working with async code, Futures, Streams, async generators, parallel calls, timeouts, retries, or asking 'how do I handle async X?'. Triggers on Future.wait, StreamController, async/await, 'run in parallel', 'cancel request', debounce, throttle, or any concurrent operation in Dart. No rxdart — use native Dart streams + bloc_concurrency only. Stack: Dart 3.8+, Flutter 3.32+, bloc_concurrency, fpdart.
commands:
  - implement-async
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the correct async pattern for a given scenario, "audit" checks existing async code for anti-patterns (fire-and-forget, uncancelled subscriptions, swallowed exceptions, untyped Futures).
    required: true
  - name: target
    description: Path to the file or directory to implement/audit (e.g. lib/features/product/data/ for implement, lib/ for audit).
    required: true
  - name: pattern
    description: Specific async pattern to implement (parallel, sequential, debounce, throttle, retry, timeout, stream-subscription). Helps generate the correct code structure.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Async Patterns in Dart/Flutter

Correct async patterns for Dart 3.8+. All async code must follow these rules.

---

## Core Rules

1. **Always `await`** — no fire-and-forget in business logic
2. **Always cancel** — `StreamSubscription.cancel()` in `close()`/`dispose()`
3. **Always type** — no `Future<dynamic>`, no `Stream<dynamic>`
4. **Use Either** — never throw in domain/data layers
5. **Handle errors** — no empty catch blocks
6. **No rxdart** — use native Dart streams and `bloc_concurrency` transformers

---

## Pattern Decision Table

| Scenario | Pattern |
|---|---|
| Single async call with error handling | `async/await` + `Either` |
| Multiple independent calls | `Future.wait([...])` |
| Result A feeds into B | `flatMap` / sequential `await` |
| Stream in BLoC (preferred) | `emit.forEach` — auto-cancels |
| Stream in BLoC (explicit control) | `StreamSubscription` + cancel in `close()` |
| Debounce search input | `restartable()` + `Future.delayed` |
| Throttle button tap | `droppable()` |
| Queue events one at a time | `sequential()` |
| CPU-heavy work | `Isolate.run()` — see `flutter-isolates` skill |

---

## Dart 3.x Language Features for Async Code

### Wildcard Variables (3.7) — `_` is non-binding

```dart
// Multiple wildcards in destructuring — no "already defined" error
final [_, value, _] = await Future.wait([
  cacheInvalidation(),   // result discarded
  fetchUser(id),         // keep this
  logAnalytics(),        // result discarded
]);
```

### Null-Aware Elements (3.8) — `?expression` in collections

```dart
// Build lists from nullable async results — no if-null boilerplate
return [
  UserHeader(user),
  ?promo?.toWidget(),   // included only if non-null
  ?banner?.toWidget(),  // included only if non-null
  const FooterWidget(),
];

// In maps — entry omitted entirely when value is null
final headers = <String, String>{
  'Content-Type': 'application/json',
  ?'Authorization': authToken != null ? 'Bearer $authToken' : null,
};
```

### Dot Shorthands (3.10) — omit type name when inferable

```dart
// BLoC state emission
emit(.loading());
emit(.success(data: users));
emit(.error(message: failure.message));

// Duration
await Future<void>.delayed(const .seconds(1));
```

### Digit Separators (3.6)

```dart
const maxRetryDelay = Duration(milliseconds: 30_000);
const maxFileSize = 10_000_000; // 10 MB
```

---

## bloc_concurrency Transformers — Quick Reference

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

on<LoadPageRequested>(_onLoadPage,  transformer: sequential());  // queue
on<TrackViewEvent>(_onTrackView,    transformer: concurrent());  // default
on<SubmitFormPressed>(_onSubmit,    transformer: droppable());   // throttle
on<SearchQueryChanged>(_onSearch,   transformer: restartable()); // debounce
```

---

## Anti-Patterns Checklist

```dart
// ❌ Fire-and-forget
_repository.saveUser(user); // not awaited — errors lost

// ❌ Swallowed exception
try { await _fetch(); } catch (_) {} // silent failure

// ❌ Uncancelled subscription
_repo.watch().listen((_) { ... }); // never cancelled — memory leak

// ❌ Dynamic async type
Future getData() async { ... } // Future<dynamic>

// ❌ rxdart
import 'package:rxdart/rxdart.dart'; // FORBIDDEN

// ❌ compute() — legacy
await compute(parseJson, data); // use Isolate.run() instead
```

---

## Reference Files

- `references/patterns.md` — Full implementations: Future patterns, Stream patterns, Debounce/Throttle, retry

> For CPU-heavy work, see **`flutter-isolates`** skill.
> For stream composition and reactive patterns, see **`flutter-streams-advanced`**.
> For mutex, semaphore, and concurrency primitives, see **`flutter-concurrency`**.
