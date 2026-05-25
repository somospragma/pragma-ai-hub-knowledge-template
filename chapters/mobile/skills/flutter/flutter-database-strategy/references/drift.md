# Drift — Relational SQLite

Recommended for apps with relational data, complex queries, joins, or schema migrations.
Provides type-safe SQL, reactive streams, and built-in isolate support.

See also: `flutter-offline-first-pattern` skill for cache-first sync patterns using Drift.

## Setup

```yaml
dependencies:
  drift: ^2.23.0
  drift_flutter: ^0.2.0        # Flutter-specific connection helper
  sqlite3_flutter_libs: ^0.5.0 # Bundled SQLite for Android/iOS

dev_dependencies:
  drift_dev: ^2.23.0
  build_runner: ^2.14.1
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Table Definitions

```dart
// lib/core/database/tables/products_table.dart
import 'package:drift/drift.dart';

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  RealColumn get price => real()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get imageUrl => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

## Database Class with Migrations

```dart
// lib/core/database/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:injectable/injectable.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Products, Categories])
@singleton
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(products, products.imageUrl);
      if (from < 3) await m.addColumn(products, products.isSynced);
    },
    beforeOpen: (details) async {
      // Enforce foreign key constraints
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'app_database');
}
```

## DAO — Data Access Object

```dart
// lib/features/product/data/datasources/product_dao.dart
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products, Categories])
@injectable
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  // ── Reactive queries ──────────────────────────────────────────────────

  Stream<List<Product>> watchAll() =>
      (select(products)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Stream<List<Product>> watchByCategory(String categoryId) =>
      (select(products)
            ..where((t) => t.categoryId.equals(categoryId))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  // ── One-shot queries ──────────────────────────────────────────────────

  Future<Product?> findById(String id) =>
      (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Product>> findUnsynced() =>
      (select(products)..where((t) => t.isSynced.equals(false))).get();

  // ── Writes ────────────────────────────────────────────────────────────

  Future<void> upsert(ProductsCompanion product) =>
      into(products).insertOnConflictUpdate(product);

  /// Efficient batch upsert — use for sync operations
  Future<void> upsertAll(List<ProductsCompanion> items) =>
      batch((b) => b.insertAllOnConflictUpdate(products, items));

  Future<void> markSynced(String id) =>
      (update(products)..where((t) => t.id.equals(id)))
          .write(const ProductsCompanion(isSynced: Value(true)));

  Future<int> deleteById(String id) =>
      (delete(products)..where((t) => t.id.equals(id))).go();

  Future<int> deleteOlderThan(Duration age) {
    final cutoff = DateTime.now().subtract(age);
    return (delete(products)
          ..where((t) => t.cachedAt.isSmallerThanValue(cutoff)))
        .go();
  }

  // ── Join queries ──────────────────────────────────────────────────────

  Stream<List<ProductWithCategory>> watchWithCategories() {
    final query = select(products).join([
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ]);
    return query.watch().map((rows) => rows
        .map((row) => ProductWithCategory(
              product: row.readTable(products),
              category: row.readTableOrNull(categories),
            ))
        .toList());
  }

  // ── Aggregates ────────────────────────────────────────────────────────

  Future<int> countByCategory(String categoryId) async {
    final count = products.id.count();
    final query = selectOnly(products)
      ..addColumns([count])
      ..where(products.categoryId.equals(categoryId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }
}
```

## Mapper — DB Row ↔ Domain Entity

```dart
// lib/features/product/data/mappers/product_mapper.dart
import 'package:injectable/injectable.dart';

@injectable
class ProductMapper {
  Product fromRow(Product row) => Product(
    id: row.id,
    name: row.name,
    price: row.price,
    stock: row.stock,
    categoryId: row.categoryId,
    imageUrl: row.imageUrl,
    updatedAt: row.updatedAt,
  );

  ProductsCompanion toCompanion(Product entity) => ProductsCompanion(
    id: Value(entity.id),
    name: Value(entity.name),
    price: Value(entity.price),
    stock: Value(entity.stock),
    categoryId: Value(entity.categoryId),
    imageUrl: Value(entity.imageUrl),
    updatedAt: Value(entity.updatedAt),
    isSynced: const Value(false),
  );
}
```

## Encryption with SQLCipher

```yaml
# Replace sqlite3_flutter_libs with the encrypted variant
dependencies:
  drift: ^2.23.0
  drift_flutter: ^0.2.0
  sqlcipher_flutter_libs: ^0.5.0
  sqlite3: ^2.4.0
```

```dart
// Retrieve the key from flutter_secure_storage (see secure_storage.md)
static QueryExecutor _openEncryptedConnection(String encryptionKey) {
  return driftDatabase(
    name: 'app_database_encrypted',
    native: DriftNativeOptions(
      databasePath: () async {
        final dir = await getApplicationDocumentsDirectory();
        return path.join(dir.path, 'app_encrypted.db');
      },
      setup: (db) => db.execute("PRAGMA key = '$encryptionKey'"),
    ),
  );
}
```

## Testing with In-Memory Database

```dart
// Use NativeDatabase.memory() — no file I/O, fast, isolated per test
AppDatabase createTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late ProductDao dao;

  setUp(() {
    db = createTestDatabase();
    dao = ProductDao(db);
  });

  tearDown(() => db.close());

  test('upsertAll persists multiple products', () async {
    await dao.upsertAll([
      ProductsCompanion.insert(
        id: 'p1', name: 'Product 1', price: 9.99,
        categoryId: 'cat1', updatedAt: DateTime.now(),
      ),
    ]);

    final all = await dao.watchAll().first;
    expect(all.length, 1);
    expect(all.first.id, 'p1');
  });
}
```
