---
name: flutter-reactive-programming
description: > 
  Implements reactive programming patterns in Flutter: unidirectional data flow, reactive repositories (watch streams), reactive state with BLoC and Riverpod, ValueNotifier for lightweight local state, ChangeNotifier for simple reactive models, and reactive UI composition. No rxdart. Use this skill when designing how data flows reactively through the entire app — from data source to UI — or when choosing between BLoC, Riverpod, ValueNotifier, and ChangeNotifier for a given use case.
commands:
  - implement-reactive
inputs:
  - name: pattern
    description: Reactive pattern to implement (reactive-repository, bloc-stream, riverpod-stream, value-notifier, change-notifier, provider-composition, full-flow). "full-flow" generates the complete reactive chain from data source to UI.
    required: true
  - name: target
    description: Path to the file or feature directory where the reactive pattern will be implemented (e.g. lib/features/chat/ for full-flow, or a specific repository file).
    required: true
  - name: state_management
    description: State management approach to use (bloc, riverpod, value-notifier, change-notifier). Required when pattern is "full-flow" to determine the presentation layer tool.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Reactive Programming

See the reference files for complete patterns and code examples.

**Reactive programming = data flows automatically from source to UI when it changes.**
The UI never pulls data — it reacts to changes pushed from below.

## Scope — What This Skill Covers

```
flutter-reactive-programming (this skill)    flutter-streams-advanced skill
─────────────────────────────────────────    ──────────────────────────────
Reactive architecture patterns               Stream operators (map, where, etc.)
Unidirectional data flow                     StreamController, broadcast
Reactive repositories (watch streams)        Custom transformers
BLoC reactive pattern end-to-end             BLoC EventTransformer
Riverpod reactive pattern end-to-end         Riverpod StreamProvider
ValueNotifier / ChangeNotifier               Real-world stream patterns
Reactive UI composition
```

---

## The Reactive Data Flow

```
Data Source (DB watch / WebSocket / sensor)
    ↓  Stream<T>
Repository (transforms, combines, maps to domain entities)
    ↓  Stream<Either<Failure, T>>
UseCase (optional transformation)
    ↓  Stream<Either<Failure, T>>
BLoC / Notifier (maps to UI state)
    ↓  State
Widget (reacts, never polls)
```

**Key rule: data flows DOWN. Events flow UP.**

---

## Reactive Tool Selection

| Tool | Best for | Reactive mechanism |
|---|---|---|
| **BLoC** | Complex state, many events, testability | `emit.forEach`, `StreamSubscription` |
| **Riverpod** | Provider composition, simple reactive state | `StreamProvider`, `ref.watch` |
| **ValueNotifier** | Single value, lightweight, local to widget | `ValueListenableBuilder` |
| **ChangeNotifier** | Multiple fields, simple model, no codegen | `ListenableBuilder` / `AnimatedBuilder` |
| **InheritedWidget** | Framework-level, no package dependency | `dependOnInheritedWidgetOfExactType` |

---

## Dependencies

```yaml
dependencies:
  flutter_bloc: ^9.1.1
  bloc_concurrency: ^0.3.0
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
  fpdart: ^1.2.0

dev_dependencies:
  riverpod_generator: ^2.6.1
  build_runner: ^2.14.1
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
  mocktail: ^1.0.5
```

---

## Core Reactive Patterns — Quick Reference

### Reactive repository (watch stream)
```dart
abstract interface class ProductRepository {
  // ✅ Reactive — UI updates automatically when data changes
  Stream<Either<Failure, List<Product>>> watchProducts(String categoryId);

  // Non-reactive — one-shot fetch
  Future<Either<Failure, List<Product>>> getProducts(String categoryId);
}
```

### BLoC — react to stream
```dart
Future<void> _onWatch(WatchEvent event, Emitter<State> emit) async {
  await emit.forEach(
    _repository.watchProducts(event.categoryId),
    onData: (result) => result.fold(
      (f) => State.error(f.message),
      (products) => State.success(products: products),
    ),
  );
}
```

### Riverpod — stream as provider
```dart
@riverpod
Stream<List<Product>> products(ProductsRef ref, {required String categoryId}) =>
    ref.watch(productRepositoryProvider).watchProducts(categoryId);
```

### ValueNotifier — lightweight local state
```dart
final _counter = ValueNotifier<int>(0);

ValueListenableBuilder<int>(
  valueListenable: _counter,
  builder: (_, value, __) => Text('$value'),
)
```

---

## Real-World Reactive Use Cases

| Use case | Recommended tool |
|---|---|
| Product list that updates when DB changes | BLoC + `emit.forEach` / Riverpod `StreamProvider` |
| Cart badge count | `ValueNotifier<int>` or Riverpod `@riverpod int` |
| Form validation (multiple fields) | `ChangeNotifier` or Riverpod `Notifier` |
| Dashboard combining user + cart + notifications | Riverpod provider composition |
| Real-time chat | BLoC + WebSocket stream |
| Theme / locale switching | `ValueNotifier` + `InheritedWidget` |
| Authentication state | BLoC `emit.forEach` on auth stream |

---

## Quick Wins Checklist

- [ ] Repositories expose `watch*` streams for reactive data — not just `get*` futures
- [ ] BLoC uses `emit.forEach` for stream-to-state — not manual `StreamSubscription`
- [ ] Riverpod `StreamProvider` used for DB/WebSocket streams
- [ ] `ValueNotifier` used for simple single-value local state (no BLoC overhead)
- [ ] `ChangeNotifier` used for simple multi-field models (no codegen needed)
- [ ] UI never polls — it reacts to pushed changes
- [ ] `distinct()` / `buildWhen` used to prevent redundant rebuilds

## Reference Files

- `references/reactive_architecture.md` — unidirectional data flow, reactive repository pattern, domain stream design
- `references/bloc_reactive.md` — BLoC reactive patterns: emit.forEach, stream subscriptions, auth flow, real-time chat
- `references/riverpod_reactive.md` — Riverpod reactive patterns: StreamProvider, Notifier, provider composition, form validation
- `references/lightweight_reactive.md` — ValueNotifier, ChangeNotifier, ListenableBuilder, when to use each
