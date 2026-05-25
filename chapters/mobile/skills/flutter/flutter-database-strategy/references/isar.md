# Isar — NoSQL Document Store

> ⚠️ **Maintenance warning:** The original `isar` package is no longer actively maintained.
> For new projects use `isar_community` (bug fixes for v3) or `isar_plus` (enhanced fork).
> Always check the fork's maintenance status before adopting.
> For production apps requiring long-term support, prefer **Drift** or **ObjectBox**.

Use Isar when you need a simple NoSQL document store with full-text search
and don't require relational joins or complex SQL queries.

## Setup (isar_community)

```yaml
dependencies:
  isar_community: ^3.1.0
  isar_flutter_libs: ^3.1.0  # platform native libs

dev_dependencies:
  isar_generator: ^3.1.0
  build_runner: ^2.14.1
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Collection Definition

```dart
// lib/features/product/data/entities/product_collection.dart
import 'package:isar_community/isar_community.dart';

part 'product_collection.g.dart';

@collection
class ProductCollection {
  Id dbId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String id;

  @Index()
  late String name;

  late double price;
  late int stock;

  @Index()
  late String categoryId;

  String? imageUrl;
  late DateTime updatedAt;
  bool isSynced = false;
}
```

## Database Setup

```dart
// lib/core/database/isar_database.dart
import 'package:isar_community/isar_community.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';

@singleton
class IsarDatabase {
  late final Isar _isar;

  @factoryMethod
  static Future<IsarDatabase> create() async {
    final instance = IsarDatabase();
    await instance._init();
    return instance;
  }

  Future<void> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [ProductCollectionSchema],
      directory: dir.path,
      name: 'app_database',
      // Optional encryption — key from flutter_secure_storage (see secure_storage.md)
      // encryptionKey: await _getEncryptionKey(),
    );
  }

  IsarCollection<ProductCollection> get products => _isar.productCollections;
  Isar get isar => _isar;
}
```

## DAO

```dart
// lib/features/product/data/datasources/product_isar_dao.dart
import 'package:isar_community/isar_community.dart';
import 'package:injectable/injectable.dart';

@injectable
class ProductIsarDao {
  final IsarDatabase _db;
  ProductIsarDao(this._db);

  // ── Reactive queries ──────────────────────────────────────────────────

  Stream<List<ProductCollection>> watchAll() =>
      _db.products.where().sortByName().watch(fireImmediately: true);

  Stream<List<ProductCollection>> watchByCategory(String categoryId) =>
      _db.products
          .where()
          .categoryIdEqualTo(categoryId)
          .sortByName()
          .watch(fireImmediately: true);

  // ── One-shot queries ──────────────────────────────────────────────────

  Future<ProductCollection?> findById(String id) =>
      _db.products.where().idEqualTo(id).findFirst();

  Future<List<ProductCollection>> findUnsynced() =>
      _db.products.filter().isSyncedEqualTo(false).findAll();

  // ── Full-text search ──────────────────────────────────────────────────

  Future<List<ProductCollection>> search(String query) =>
      _db.products.filter().nameContains(query, caseSensitive: false).findAll();

  // ── Writes ────────────────────────────────────────────────────────────

  Future<void> upsert(ProductCollection entity) =>
      _db.isar.writeTxn(() => _db.products.put(entity));

  Future<void> upsertAll(List<ProductCollection> entities) =>
      _db.isar.writeTxn(() => _db.products.putAll(entities));

  Future<void> delete(int dbId) =>
      _db.isar.writeTxn(() => _db.products.delete(dbId));
}
```

## Mapper — Collection ↔ Domain

```dart
// lib/features/product/data/mappers/product_isar_mapper.dart
import 'package:injectable/injectable.dart';

@injectable
class ProductIsarMapper {
  Product fromCollection(ProductCollection c) => Product(
    id: c.id,
    name: c.name,
    price: c.price,
    stock: c.stock,
    categoryId: c.categoryId,
    imageUrl: c.imageUrl,
    updatedAt: c.updatedAt,
  );

  ProductCollection toCollection(Product p) => ProductCollection()
    ..id = p.id
    ..name = p.name
    ..price = p.price
    ..stock = p.stock
    ..categoryId = p.categoryId
    ..imageUrl = p.imageUrl
    ..updatedAt = p.updatedAt;
}
```

## DI Registration (async factory)

```dart
@module
abstract class DatabaseModule {
  @singleton
  @preResolve
  Future<IsarDatabase> get isarDatabase => IsarDatabase.create();
}
```
