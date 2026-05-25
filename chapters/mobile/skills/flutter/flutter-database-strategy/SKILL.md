---
name: flutter-database-strategy
description: >
  Choose and implement the right local database for Flutter: Drift (relational, reactive SQLite), ObjectBox (NoSQL, highest performance), Isar community forks (NoSQL, document store), sqflite (raw SQLite), and flutter_secure_storage (encrypted sensitive data). Hive is in maintenance mode — do NOT use for new projects. Use this skill when choosing a local persistence strategy, implementing DAOs, schema migrations, or reactive queries.
commands:
  - setup-database
inputs:
  - name: action
    description: Action to perform (implement, migrate, audit). "implement" generates the full database layer (tables/entities, DAO, mapper, DI registration), "migrate" creates a schema migration for an existing database, "audit" checks for Hive usage, missing migrations, or unencrypted sensitive data.
    required: true
  - name: target
    description: Path to the data layer or feature directory (e.g. lib/core/database/ for implement, lib/features/product/data/ for feature-specific DAO).
    required: true
  - name: database
    description: Database engine to use (drift, objectbox, isar, sqflite). Defaults to drift.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Database Strategy

See `references/implementation_guide.md` for complete patterns and code examples.

## Package Status (April 2026)

| Package | Version | Status | Notes |
|---|---|---|---|
| **drift** | 2.23.x | ✅ Active | Recommended for relational data |
| **drift_flutter** | 0.2.x | ✅ Active | Flutter-specific drift integration |
| **objectbox** | 5.3.x | ✅ Active | Fastest NoSQL, optional built-in Sync |
| **isar_community** | 3.x fork | ⚠️ Bug-fix only | Community fork of original Isar |
| **isar_plus** | 3.x fork | ⚠️ Enhanced fork | More features, community maintained |
| **sqflite** | 2.x | ✅ Active | Low-level SQLite, no reactive streams |
| **flutter_secure_storage** | 10.0.0 | ✅ Active | Encrypted storage (Keychain/Keystore) |
| **shared_preferences** | 2.x | ✅ Active | Simple key-value, not a database |
| **Hive** | 4.x | ❌ Maintenance mode | Do NOT use for new projects |

---

## Decision Guide

```
Need relational data, joins, complex queries, migrations?
  → Drift (type-safe SQLite, reactive streams, isolate support)

Need maximum write throughput, object graphs, no SQL?
  → ObjectBox (fastest Flutter DB, optional built-in Sync server)

Need simple NoSQL document store, full-text search?
  → isar_community or isar_plus (Isar forks — evaluate maintenance status)

Need raw SQL control, no codegen?
  → sqflite (low-level, no reactive streams)

Need to store tokens, keys, credentials?
  → flutter_secure_storage (Keychain on iOS, Keystore on Android)

Need simple key-value (theme, language, flags)?
  → shared_preferences (not a database — for primitives only)

Need offline-first with Supabase/Postgres sync?
  → PowerSync (see flutter-offline-first-pattern skill)
```

---

## Quick Comparison

| Feature | Drift | ObjectBox | Isar (community) | sqflite |
|---|---|---|---|---|
| Type | Relational (SQLite) | NoSQL (object) | NoSQL (document) | Relational (SQLite) |
| Reactive streams | ✅ Any query | ✅ Box queries | ✅ Queries | ❌ Manual |
| Codegen required | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| Migrations | ✅ Built-in | ⚠️ Manual | ⚠️ Limited | ⚠️ Manual |
| Isolate support | ✅ Built-in | ✅ Built-in | ✅ Built-in | ⚠️ Manual |
| Encryption | ✅ SQLCipher | ✅ Built-in | ✅ Built-in | ⚠️ Plugin |
| Cross-platform | ✅ All | ✅ Mobile/Desktop | ✅ Mobile/Desktop | ✅ Mobile |
| Write performance | Good | Fastest | Fast | Good |
| Complex queries | ✅ Full SQL | ⚠️ Limited | ⚠️ Limited | ✅ Full SQL |

---

## Architecture Integration

```
Domain (Entity, Repository interface)
  ↓
Data (RepositoryImpl)
  ├── DAO / Box / Collection  ← database access
  └── Mapper                  ← DB row/object ↔ domain entity
```

All dependencies injected via GetIt + Injectable.  
Errors returned as `Either<Failure, T>` using fpdart.  
Repository interfaces use `abstract interface class`.

---

## Dependencies by Choice

```yaml
# Option A: Drift (relational — recommended default)
dependencies:
  drift: ^2.23.0
  drift_flutter: ^0.2.0
  sqlite3_flutter_libs: ^0.5.0
dev_dependencies:
  drift_dev: ^2.23.0
  build_runner: ^2.14.1

# Option B: ObjectBox (NoSQL — highest performance)
dependencies:
  objectbox: ^5.3.0
  objectbox_flutter_libs: any
dev_dependencies:
  objectbox_generator: ^5.3.0
  build_runner: ^2.14.1

# Option C: Isar community fork (NoSQL — evaluate before adopting)
dependencies:
  isar_community: ^3.1.0
  isar_flutter_libs: ^3.1.0
dev_dependencies:
  isar_generator: ^3.1.0
  build_runner: ^2.14.1

# Sensitive data (always alongside any DB choice)
dependencies:
  flutter_secure_storage: ^10.0.0
```

---

## Key Patterns

### Drift — reactive DAO
```dart
// Auto-updating stream — UI rebuilds when data changes
Stream<List<Product>> watchByCategory(String categoryId) =>
    (select(products)
          ..where((t) => t.categoryId.equals(categoryId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();

// Batch upsert — efficient for sync
Future<void> upsertAll(List<ProductsCompanion> items) =>
    batch((b) => b.insertAllOnConflictUpdate(products, items));
```

### ObjectBox — reactive box query
```dart
// Auto-updating stream
Stream<List<ProductEntity>> watchByCategory(String categoryId) {
  final query = _box.query(ProductEntity_.categoryId.equals(categoryId))
      .order(ProductEntity_.name)
      .build();
  return query.watch(triggerImmediately: true).map((q) => q.find());
}
```

### Repository — abstract interface class
```dart
abstract interface class ProductRepository {
  Stream<Either<Failure, List<Product>>> watchProducts();
  Future<Either<Failure, Product>> getProduct(String id);
  Future<Either<Failure, Unit>> saveProduct(Product product);
  Future<Either<Failure, Unit>> deleteProduct(String id);
}
```

---

## Quick Wins Checklist

- [ ] Hive removed from new projects — replaced with Drift or isar_community
- [ ] `abstract interface class` used for all repository contracts
- [ ] DAOs/Boxes injected via GetIt (`@injectable`)
- [ ] Reactive streams used instead of one-shot `Future` queries where possible
- [ ] Migrations defined for Drift schema changes
- [ ] Sensitive data (tokens, keys) stored in `flutter_secure_storage`, not in the DB
- [ ] `batch()` used for bulk inserts/updates in Drift
- [ ] Database opened in background isolate (Drift: `NativeDatabase.createInBackground`)

## Reference Files

- `references/drift.md` — setup, tables, migrations, DAO, mapper, SQLCipher encryption, in-memory testing
- `references/objectbox.md` — entity definition, Store setup, Box DAO, mapper, built-in Sync server
- `references/isar.md` — collection definition, database setup, DAO with full-text search, mapper
- `references/secure_storage.md` — `flutter_secure_storage` service, encryption key generation, usage with Drift and Isar
- `references/repository_pattern.md` — `abstract interface class` repository, implementation, Drift in-memory tests, UseCase mock tests
