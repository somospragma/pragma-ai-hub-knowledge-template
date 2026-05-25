# ObjectBox — NoSQL, Highest Performance

Use ObjectBox when you need the fastest possible write throughput, object graphs,
or the optional built-in Sync server for offline-first apps.

## Setup

```yaml
dependencies:
  objectbox: ^5.3.0
  objectbox_flutter_libs: any  # platform-specific native libs

dev_dependencies:
  objectbox_generator: ^5.3.0
  build_runner: ^2.14.1
```

```bash
# Generates objectbox-model.json and objectbox.g.dart
dart run build_runner build --delete-conflicting-outputs
```

## Entity Definition

```dart
// lib/features/product/data/entities/product_entity.dart
import 'package:objectbox/objectbox.dart';

@Entity()
class ProductEntity {
  @Id()
  int dbId = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  late String id;

  late String name;
  late double price;
  late int stock;

  @Index()
  late String categoryId;

  String? imageUrl;
  late DateTime updatedAt;
  bool isSynced = false;

  @Property(type: PropertyType.date)
  late DateTime cachedAt;
}
```

## Store Setup

```dart
// lib/core/database/objectbox_store.dart
import 'package:objectbox/objectbox.dart';
import 'package:injectable/injectable.dart';
import 'objectbox.g.dart';

@singleton
class ObjectBoxStore {
  late final Store _store;
  late final Box<ProductEntity> products;

  @factoryMethod
  static Future<ObjectBoxStore> create() async {
    final instance = ObjectBoxStore();
    await instance._init();
    return instance;
  }

  Future<void> _init() async {
    _store = await openStore();
    products = _store.box<ProductEntity>();
  }

  void close() => _store.close();
}
```

## Box DAO

```dart
// lib/features/product/data/datasources/product_box.dart
import 'package:objectbox/objectbox.dart';
import 'package:injectable/injectable.dart';

@injectable
class ProductBox {
  final ObjectBoxStore _store;
  ProductBox(this._store);

  Box<ProductEntity> get _box => _store.products;

  // ── Reactive queries ──────────────────────────────────────────────────

  Stream<List<ProductEntity>> watchAll() {
    final query = _box.query().order(ProductEntity_.name).build();
    return query.watch(triggerImmediately: true).map((q) => q.find());
  }

  Stream<List<ProductEntity>> watchByCategory(String categoryId) {
    final query = _box
        .query(ProductEntity_.categoryId.equals(categoryId))
        .order(ProductEntity_.name)
        .build();
    return query.watch(triggerImmediately: true).map((q) => q.find());
  }

  // ── One-shot queries ──────────────────────────────────────────────────

  ProductEntity? findById(String id) =>
      _box.query(ProductEntity_.id.equals(id)).build().findFirst();

  List<ProductEntity> findUnsynced() =>
      _box.query(ProductEntity_.isSynced.equals(false)).build().find();

  // ── Writes ────────────────────────────────────────────────────────────

  void upsert(ProductEntity entity) => _box.put(entity);

  /// Batch upsert — runs in a single transaction, much faster than individual puts
  void upsertAll(List<ProductEntity> entities) => _box.putMany(entities);

  void delete(int dbId) => _box.remove(dbId);

  void deleteAll(List<int> dbIds) => _box.removeMany(dbIds);
}
```

## Mapper — Entity ↔ Domain

```dart
// lib/features/product/data/mappers/product_objectbox_mapper.dart
import 'package:injectable/injectable.dart';

@injectable
class ProductObjectBoxMapper {
  Product fromEntity(ProductEntity e) => Product(
    id: e.id,
    name: e.name,
    price: e.price,
    stock: e.stock,
    categoryId: e.categoryId,
    imageUrl: e.imageUrl,
    updatedAt: e.updatedAt,
  );

  ProductEntity toEntity(Product p) => ProductEntity()
    ..id = p.id
    ..name = p.name
    ..price = p.price
    ..stock = p.stock
    ..categoryId = p.categoryId
    ..imageUrl = p.imageUrl
    ..updatedAt = p.updatedAt
    ..cachedAt = DateTime.now();
}
```

## ObjectBox Sync (Optional — Built-in Offline Sync)

ObjectBox provides an optional Sync server for bidirectional offline-first sync
without building custom sync infrastructure.

```dart
// Requires objectbox_sync_flutter_libs instead of objectbox_flutter_libs
// and a running ObjectBox Sync Server

final syncClient = Sync.client(
  store,
  'ws://your-sync-server:9999',
  SyncCredentials.sharedSecretUint8List(Uint8List.fromList(secretKey)),
);

syncClient.start();

// Conflict resolution (ObjectBox 5.3+)
syncClient.setConflictResolution(SyncConflictResolution.lastWriteWins);
```

## DI Registration (async factory)

```dart
// lib/core/di/database_module.dart
@module
abstract class DatabaseModule {
  @singleton
  @preResolve  // resolves the Future before injection
  Future<ObjectBoxStore> get objectBoxStore => ObjectBoxStore.create();
}
```
