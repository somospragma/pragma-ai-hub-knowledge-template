---
name: flutter-offline-first-pattern
description: >
  Implements offline-first architecture in Flutter: local cache as primary source of truth, background sync, connectivity detection, optimistic updates, and conflict resolution. Covers local database options (Drift, ObjectBox, Isar), sync strategies (manual queue, PowerSync managed sync), and clean architecture integration. Use this skill when building apps that must work without internet, need instant UI response, or require background data synchronization.
commands:
  - setup-offline-first
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the full offline-first architecture (local DB, sync queue, connectivity service, repository pattern), "audit" checks existing implementation for missing sync handlers, unqueued mutations, or connectivity gaps.
    required: true
  - name: target
    description: Path to the feature or core directory where offline-first will be integrated (e.g. lib/features/product/ or lib/core/sync/).
    required: true
  - name: database
    description: Local database to use (drift, objectbox, isar, powersync). Defaults to drift.
    required: false
  - name: conflict_strategy
    description: Conflict resolution strategy (last-write-wins, server-wins, client-wins, field-merge, user-prompted). Defaults to last-write-wins.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Offline-First Pattern

See `references/implementation_guide.md` for complete patterns and code examples.

**Core principle: The local database is the source of truth. The network is a sync mechanism.**

## Local Database Options (2026)

| Database | Type | Best for | Notes |
|---|---|---|---|
| **Drift** 2.23.x | Relational (SQLite) | Complex queries, joins, migrations | Reactive streams, built-in isolate support, type-safe SQL |
| **ObjectBox** 5.x | NoSQL (object store) | High-throughput, object graphs | Optional built-in Sync server, fastest writes |
| **Isar** 3.x | NoSQL (document) | Simple models, full-text search | Hive successor, pure Dart, no native code |
| **sqflite** 2.x | Relational (SQLite) | Simple SQL, no codegen | Low-level, no reactive streams |
| **Hive** 4.x | Key-value | Simple preferences, small data | ⚠️ Maintenance mode — use Isar for new projects |
| **PowerSync** | SQLite + managed sync | Supabase/Postgres/MongoDB sync | Managed sync engine, handles conflicts automatically |

### Decision guide

```
Need relational data + complex queries + migrations?  → Drift
Need fastest raw performance + object graphs?         → ObjectBox
Need simple NoSQL + full-text search?                 → Isar
Need managed sync with Supabase/Postgres?             → PowerSync (uses SQLite internally)
Need simple key-value cache only?                     → shared_preferences or Isar
```

---

## Architecture

```
Presentation (BLoC)
  ↓ watches Stream<Either<Failure, T>>
Domain (UseCase → Repository interface)
  ↓
Data (RepositoryImpl)
  ├── LocalDataSource  ← primary source of truth (Drift / ObjectBox / Isar)
  └── RemoteDataSource ← sync source (REST / GraphQL / WebSocket)
       ↑
  SyncQueue (persisted pending mutations)
       ↑
  ConnectivityService (connectivity_plus 6.x)
```

---

## Core Strategy: Cache-First, Sync-in-Background

```dart
// ✅ Always emit cached data first — zero latency for the user
// Then sync from remote and emit updated data
Stream<Either<Failure, List<Product>>> watchProducts() async* {
  // Phase 1: Emit local data immediately (no network wait)
  yield* _local.watchProducts().map(
    (products) => Right<Failure, List<Product>>(products),
  );

  // Phase 2: Trigger background sync if connected
  // The stream above will automatically emit new data when sync completes
  _syncIfConnected();
}
```

---

## Key Patterns

### 1. Reactive local stream (Drift)
```dart
// Drift watchAll() returns a Stream — UI updates automatically when DB changes
Stream<List<Product>> watchProducts() =>
    (_db.select(_db.products)..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
```

### 2. Optimistic update
```dart
// Write to local DB immediately → update UI instantly → sync to remote
Future<Either<Failure, Unit>> updateProduct(Product product) async {
  await _local.upsert(product);          // instant UI update
  await _syncQueue.enqueue(             // queue for remote sync
    SyncOperation.update(entity: 'product', data: product.toJson()),
  );
  return const Right(unit);
}
```

### 3. Sync queue with retry
```dart
// Persisted queue survives app restarts
// Processes when connectivity is restored
class SyncQueueService {
  Future<void> enqueue(SyncOperation op);
  Future<void> processQueue();  // called on connectivity restored
  Future<void> retryFailed();   // exponential backoff
}
```

### 4. Conflict resolution strategies
| Strategy | When to use |
|---|---|
| Last-write-wins (timestamp) | Simple data, low conflict probability |
| Server-wins | Server is authoritative (e.g., inventory) |
| Client-wins | User edits always override (e.g., notes) |
| Field-level merge | Complex objects, partial updates |
| User-prompted | High-value data where loss is unacceptable |

---

## Dependencies

```yaml
dependencies:
  # Choose ONE local database:
  drift: ^2.23.0              # relational — recommended default
  drift_flutter: ^0.2.0       # Flutter-specific drift integration
  # objectbox: ^5.3.0         # NoSQL alternative
  # isar: ^3.1.0              # NoSQL, Hive successor
  # powersync: ^1.x.x         # managed sync (Supabase/Postgres)

  connectivity_plus: ^6.1.0
  fpdart: ^1.2.0
  flutter_bloc: ^9.1.1
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0

dev_dependencies:
  drift_dev: ^2.23.0
  build_runner: ^2.14.1
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
```

---

## Quick Wins Checklist

- [ ] Local DB chosen based on data model (relational → Drift, NoSQL → Isar/ObjectBox)
- [ ] Repository emits cached data before attempting network sync
- [ ] `ConnectivityService` uses `connectivity_plus` with actual reachability check
- [ ] Sync queue persisted to local DB (survives app restarts)
- [ ] Optimistic updates write to local DB first, queue remote sync
- [ ] Conflict resolution strategy defined per entity type
- [ ] BLoC uses `buildWhen` to avoid rebuilds on identical data
- [ ] Sync triggered on `onConnectivityChanged` (restored event)

## Reference Files

- `references/implementation_guide.md` — complete implementation with Drift, connectivity, sync queue, conflict resolution, BLoC, and testing patterns
