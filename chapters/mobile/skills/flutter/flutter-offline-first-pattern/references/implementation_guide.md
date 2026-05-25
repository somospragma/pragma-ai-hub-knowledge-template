# Offline-First Pattern — Implementation Guide

See also: `flutter-background-processing` for WorkManager sync tasks.

## Overview

Offline-first means the app reads and writes to a local database first.
The network is used only to synchronize — never as a blocking dependency for UI.

**Data flow:**
```
User action → Local DB write → UI updates instantly (stream)
                             → Sync queue → Remote API (when connected)
                                          → Conflict resolution
                                          → Local DB update → UI updates again
```

---

## 1. Local Database — Drift (Recommended Default)

Drift is a reactive, type-safe SQLite library with built-in isolate support and
auto-updating streams. It is the recommended default for relational offline-first data.

### Setup

```yaml
dependencies:
  drift: ^2.23.0
  drift_flutter: ^0.2.0
  sqlite3_flutter_libs: ^0.5.0  # bundled SQLite for Android/iOS

dev_dependencies:
  drift_dev: ^2.23.0
  build_runner: ^2.14.1
```

### Database definition

```dart
// lib/core/database/app_database.dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:injectable/injectable.dart';

part 'app_database.g.dart';

// Table definition
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  RealColumn get price => real()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  TextColumn get categoryId => text().references(Categories, #id)();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

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

class SyncOperations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get operationType => text()(); // 'create' | 'update' | 'delete'
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get payload => text()();       // JSON
  IntColumn get failureCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isPending => boolean().withDefault(const Constant(true))();
}

@DriftDatabase(tables: [Products, Categories, SyncOperations])
@singleton
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Add migration steps here as schema evolves
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'app_database');
  }
}
```

### Data Access Object (DAO)

```dart
// lib/features/product/data/datasources/product_dao.dart
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products, Categories])
@injectable
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  // ✅ Reactive stream — UI updates automatically when data changes
  Stream<List<Product>> watchAll() =>
      (select(products)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Stream<List<Product>> watchByCategory(String categoryId) =>
      (select(products)
            ..where((t) => t.categoryId.equals(categoryId))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Future<Product?> findById(String id) =>
      (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsertProduct(ProductsCompanion product) =>
      into(products).insertOnConflictUpdate(product);

  Future<void> upsertAll(List<ProductsCompanion> items) =>
      batch((b) => b.insertAllOnConflictUpdate(products, items));

  Future<void> deleteById(String id) =>
      (delete(products)..where((t) => t.id.equals(id))).go();

  Future<void> markSynced(String id) =>
      (update(products)..where((t) => t.id.equals(id)))
          .write(const ProductsCompanion(isSynced: Value(true)));

  // Join query — type-safe across tables
  Stream<List<ProductWithCategory>> watchWithCategories() {
    final query = select(products).join([
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
    ]);
    return query.watch().map((rows) => rows.map((row) {
      return ProductWithCategory(
        product: row.readTable(products),
        category: row.readTableOrNull(categories),
      );
    }).toList());
  }
}
```

---

## 2. Connectivity Service

```dart
// lib/core/network/connectivity_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:injectable/injectable.dart';
import 'dart:io';

@lazySingleton
class ConnectivityService {
  final _connectivity = Connectivity();

  /// Check connectivity type — does NOT guarantee internet reachability
  Future<bool> get hasNetworkInterface async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// ✅ Actual internet reachability check — not just network interface
  Future<bool> get isReachable async {
    if (!await hasNetworkInterface) return false;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Stream of connectivity changes — emits true when connection restored
  Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged
          .map((results) => results.any((r) => r != ConnectivityResult.none))
          .distinct();

  /// Stream that emits only when connectivity is RESTORED (false → true)
  Stream<void> get onConnectionRestored => onConnectivityChanged
      .pairwise()
      .where((pair) => !pair.first && pair.last)
      .map((_) {});
}
```

---

## 3. Sync Queue — Persisted Pending Mutations

```dart
// lib/core/sync/sync_queue_service.dart
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@freezed
class SyncOperation with _$SyncOperation {
  const factory SyncOperation({
    required String operationType,  // 'create' | 'update' | 'delete'
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) = _SyncOperation;
}

@lazySingleton
class SyncQueueService {
  final AppDatabase _db;
  final ConnectivityService _connectivity;

  SyncQueueService(this._db, this._connectivity);

  /// Enqueue a mutation — persisted to DB, survives app restarts
  Future<void> enqueue(SyncOperation op) async {
    await _db.into(_db.syncOperations).insert(
      SyncOperationsCompanion.insert(
        operationType: op.operationType,
        entityType: op.entityType,
        entityId: op.entityId,
        payload: jsonEncode(op.payload),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Process all pending operations — call when connectivity is restored
  Future<void> processQueue(RemoteDataSource remote) async {
    if (!await _connectivity.isReachable) return;

    final pending = await (_db.select(_db.syncOperations)
          ..where((t) => t.isPending.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();

    for (final op in pending) {
      await _processOperation(op, remote);
    }
  }

  Future<void> _processOperation(
    SyncOperation op,
    RemoteDataSource remote,
  ) async {
    try {
      await _executeRemoteOperation(op, remote);

      // Mark as processed
      await (_db.delete(_db.syncOperations)
            ..where((t) => t.id.equals(op.id)))
          .go();
    } catch (e) {
      final newFailureCount = op.failureCount + 1;

      if (newFailureCount >= 5) {
        // Give up after 5 failures — mark as failed, not pending
        await (_db.update(_db.syncOperations)
              ..where((t) => t.id.equals(op.id)))
            .write(SyncOperationsCompanion(
          isPending: const Value(false),
          failureCount: Value(newFailureCount),
        ));
      } else {
        // Increment failure count — will retry next time
        await (_db.update(_db.syncOperations)
              ..where((t) => t.id.equals(op.id)))
            .write(SyncOperationsCompanion(
          failureCount: Value(newFailureCount),
        ));
      }
    }
  }

  Future<void> _executeRemoteOperation(
    SyncOperation op,
    RemoteDataSource remote,
  ) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    switch (op.operationType) {
      case 'create':
        await remote.create(op.entityType, payload);
      case 'update':
        await remote.update(op.entityType, op.entityId, payload);
      case 'delete':
        await remote.delete(op.entityType, op.entityId);
    }
  }

  Future<int> get pendingCount async =>
      (_db.syncOperations.count(
        where: (t) => t.isPending.equals(true),
      )).getSingle();
}
```

---

## 4. Repository Implementation — Cache-First Pattern

```dart
// lib/features/product/data/repositories/product_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  final ProductDao _dao;
  final ProductRemoteDataSource _remote;
  final SyncQueueService _syncQueue;
  final ConnectivityService _connectivity;

  ProductRepositoryImpl(
    this._dao,
    this._remote,
    this._syncQueue,
    this._connectivity,
  );

  /// ✅ Cache-first: emit local data immediately, sync in background
  @override
  Stream<Either<Failure, List<Product>>> watchProducts() {
    // The Drift stream emits whenever the local DB changes
    // Background sync updates the DB → stream emits again automatically
    _syncProductsInBackground();

    return _dao.watchAll().map(
      (rows) => Right<Failure, List<Product>>(
        rows.map(ProductMapper.fromRow).toList(),
      ),
    );
  }

  /// Background sync — does not block the stream
  void _syncProductsInBackground() {
    Future.microtask(() async {
      if (!await _connectivity.isReachable) return;
      try {
        final remoteProducts = await _remote.getProducts();
        await _dao.upsertAll(
          remoteProducts.map(ProductMapper.toCompanion).toList(),
        );
      } catch (_) {
        // Silently fail — cached data is still shown
      }
    });
  }

  /// ✅ Optimistic update: write locally first, queue remote sync
  @override
  Future<Either<Failure, Unit>> updateProduct(Product product) async {
    try {
      // 1. Write to local DB immediately — UI updates via stream
      await _dao.upsertProduct(ProductMapper.toCompanion(product));

      // 2. Queue remote sync — will execute when connected
      await _syncQueue.enqueue(SyncOperation(
        operationType: 'update',
        entityType: 'product',
        entityId: product.id,
        payload: ProductMapper.toJson(product),
      ));

      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: 'Failed to update product: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteProduct(String id) async {
    try {
      await _dao.deleteById(id);
      await _syncQueue.enqueue(SyncOperation(
        operationType: 'delete',
        entityType: 'product',
        entityId: id,
        payload: {'id': id},
      ));
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: 'Failed to delete product: $e'));
    }
  }

  @override
  Future<Either<Failure, Product>> getProduct(String id) async {
    // Try local first
    final cached = await _dao.findById(id);
    if (cached != null) return Right(ProductMapper.fromRow(cached));

    // Fallback to remote if not cached
    if (!await _connectivity.isReachable) {
      return const Left(Failure.network(message: 'No internet connection'));
    }

    try {
      final dto = await _remote.getProduct(id);
      await _dao.upsertProduct(ProductMapper.toCompanion(dto));
      return Right(ProductMapper.fromDto(dto));
    } on DioException catch (e) {
      return Left(Failure.network(
        message: e.message ?? 'Network error',
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
```

---

## 5. Sync Orchestrator — Triggered by Connectivity

```dart
// lib/core/sync/sync_orchestrator.dart
import 'package:injectable/injectable.dart';
import 'dart:async';

@lazySingleton
class SyncOrchestrator {
  final SyncQueueService _syncQueue;
  final ConnectivityService _connectivity;
  final ProductRemoteDataSource _productRemote;

  StreamSubscription<void>? _connectivitySub;

  SyncOrchestrator(
    this._syncQueue,
    this._connectivity,
    this._productRemote,
  );

  /// Start listening for connectivity restoration
  void start() {
    _connectivitySub = _connectivity.onConnectionRestored.listen((_) {
      _onConnectionRestored();
    });
  }

  Future<void> _onConnectionRestored() async {
    // Process all pending mutations when connection is restored
    await _syncQueue.processQueue(_productRemote);
  }

  /// Manual sync trigger (e.g., pull-to-refresh)
  Future<void> syncNow() async {
    if (!await _connectivity.isReachable) return;
    await _syncQueue.processQueue(_productRemote);
  }

  void dispose() {
    _connectivitySub?.cancel();
  }
}

// Register in main.dart after DI:
// GetIt.instance<SyncOrchestrator>().start();
```

---

## 6. BLoC Integration

```dart
// lib/features/product/presentation/bloc/product_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';
import 'dart:async';

part 'product_bloc.freezed.dart';
part 'product_event.dart';
part 'product_state.dart';

@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final WatchProductsUseCase _watchProducts;
  final UpdateProductUseCase _updateProduct;
  final SyncOrchestrator _syncOrchestrator;

  StreamSubscription<Either<Failure, List<Product>>>? _productsSub;

  ProductBloc(this._watchProducts, this._updateProduct, this._syncOrchestrator)
      : super(const ProductState.initial()) {
    on<WatchProductsEvent>(_onWatchProducts);
    on<ProductsUpdatedEvent>(_onProductsUpdated);
    on<UpdateProductEvent>(_onUpdateProduct);
    on<SyncNowEvent>(_onSyncNow);
  }

  Future<void> _onWatchProducts(
    WatchProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    emit(const ProductState.loading());

    await _productsSub?.cancel();
    _productsSub = _watchProducts().listen(
      (result) => add(ProductEvent.productsUpdated(result)),
    );
  }

  void _onProductsUpdated(
    ProductsUpdatedEvent event,
    Emitter<ProductState> emit,
  ) {
    event.result.fold(
      (failure) => emit(ProductState.error(failure.message)),
      (products) => emit(ProductState.success(products: products)),
    );
  }

  Future<void> _onUpdateProduct(
    UpdateProductEvent event,
    Emitter<ProductState> emit,
  ) async {
    // Optimistic: UI already shows the update via the stream
    // Just queue the sync — no loading state needed
    final result = await _updateProduct(event.product);
    result.fold(
      (failure) => emit(ProductState.error(failure.message)),
      (_) => null, // stream will emit updated data automatically
    );
  }

  Future<void> _onSyncNow(
    SyncNowEvent event,
    Emitter<ProductState> emit,
  ) async {
    await _syncOrchestrator.syncNow();
  }

  @override
  Future<void> close() async {
    await _productsSub?.cancel();
    return super.close();
  }
}

// product_event.dart
part of 'product_bloc.dart';

@freezed
class ProductEvent with _$ProductEvent {
  const factory ProductEvent.watchProducts() = WatchProductsEvent;
  const factory ProductEvent.productsUpdated(
    Either<Failure, List<Product>> result,
  ) = ProductsUpdatedEvent;
  const factory ProductEvent.updateProduct(Product product) = UpdateProductEvent;
  const factory ProductEvent.syncNow() = SyncNowEvent;
}

// product_state.dart
part of 'product_bloc.dart';

@freezed
class ProductState with _$ProductState {
  const factory ProductState.initial() = ProductInitial;
  const factory ProductState.loading() = ProductLoading;
  const factory ProductState.success({
    required List<Product> products,
    @Default(false) bool isSyncing,
  }) = ProductSuccess;
  const factory ProductState.error(String message) = ProductError;
}
```

---

## 7. Conflict Resolution Patterns

```dart
// lib/core/sync/conflict_resolver.dart

/// Last-write-wins based on updatedAt timestamp
class LastWriteWinsResolver {
  Product resolve(Product local, Product remote) {
    return remote.updatedAt.isAfter(local.updatedAt) ? remote : local;
  }
}

/// Field-level merge — combine non-conflicting fields
class FieldMergeResolver {
  Product resolve(Product local, Product remote, Product base) {
    // Fields changed locally but not remotely → keep local
    // Fields changed remotely but not locally → keep remote
    // Fields changed in both → remote wins (or prompt user)
    return Product(
      id: local.id,
      name: local.name != base.name ? local.name : remote.name,
      price: remote.price != base.price ? remote.price : local.price,
      stock: remote.stock, // server is authoritative for stock
      updatedAt: DateTime.now(),
    );
  }
}

/// Server-wins — always use remote data (e.g., inventory, pricing)
class ServerWinsResolver {
  Product resolve(Product local, Product remote) => remote;
}
```

---

## 8. ObjectBox Alternative (NoSQL, High Performance)

```dart
// lib/core/database/objectbox_store.dart
// Use when: high-throughput writes, object graphs, no complex SQL queries

import 'package:objectbox/objectbox.dart';
import 'package:injectable/injectable.dart';

@Entity()
class ProductEntity {
  @Id()
  int dbId = 0;

  @Unique()
  late String id;
  late String name;
  late double price;
  late int stock;
  late DateTime updatedAt;
  bool isSynced = false;
}

@singleton
class ObjectBoxStore {
  late final Store _store;
  late final Box<ProductEntity> products;

  Future<void> init() async {
    _store = await openStore();
    products = _store.box<ProductEntity>();
  }

  // ✅ Reactive query — auto-updating stream
  Stream<List<ProductEntity>> watchProducts() {
    final query = products.query()
        .order(ProductEntity_.name)
        .build();
    return query.watch(triggerImmediately: true)
        .map((q) => q.find());
  }

  void upsert(ProductEntity entity) => products.put(entity);
  void upsertAll(List<ProductEntity> entities) => products.putMany(entities);
  void delete(int dbId) => products.remove(dbId);
}
```

---

## 9. PowerSync (Managed Sync — Supabase/Postgres)

Use PowerSync when you need automatic bidirectional sync with a Supabase or Postgres backend
without building your own sync infrastructure.

```dart
// lib/core/database/powersync_database.dart
import 'package:powersync/powersync.dart';
import 'package:injectable/injectable.dart';

const schema = Schema([
  Table('products', [
    Column.text('name'),
    Column.real('price'),
    Column.integer('stock'),
    Column.text('category_id'),
    Column.text('updated_at'),
  ]),
]);

@singleton
class PowerSyncDatabase {
  late final PowerSyncDatabase _db;

  Future<void> init(String supabaseUrl, String supabaseKey) async {
    _db = PowerSyncDatabase(schema: schema, path: 'powersync.db');

    // Connect to Supabase — PowerSync handles sync automatically
    await _db.connect(
      connector: SupabaseConnector(
        powerSyncUrl: 'https://your-instance.powersync.co',
        supabaseUrl: supabaseUrl,
        supabaseKey: supabaseKey,
      ),
    );
  }

  // ✅ Reactive SQL query — updates automatically when sync occurs
  Stream<List<Map<String, dynamic>>> watchProducts() =>
      _db.watch('SELECT * FROM products ORDER BY name');

  // ✅ Write locally — PowerSync syncs to Supabase automatically
  Future<void> upsertProduct(Map<String, dynamic> product) =>
      _db.execute(
        'INSERT OR REPLACE INTO products (id, name, price, stock) VALUES (?, ?, ?, ?)',
        [product['id'], product['name'], product['price'], product['stock']],
      );
}
```

---

## 10. Testing

```dart
// test/features/product/data/repositories/product_repository_impl_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';
import 'package:drift/native.dart';

class MockProductRemoteDataSource extends Mock implements ProductRemoteDataSource {}
class MockConnectivityService extends Mock implements ConnectivityService {}
class MockSyncQueueService extends Mock implements SyncQueueService {}

void main() {
  late AppDatabase db;
  late ProductDao dao;
  late MockProductRemoteDataSource mockRemote;
  late MockConnectivityService mockConnectivity;
  late MockSyncQueueService mockSyncQueue;
  late ProductRepositoryImpl repository;

  setUp(() {
    // Use in-memory database for tests
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = ProductDao(db);
    mockRemote = MockProductRemoteDataSource();
    mockConnectivity = MockConnectivityService();
    mockSyncQueue = MockSyncQueueService();

    repository = ProductRepositoryImpl(
      dao,
      mockRemote,
      mockSyncQueue,
      mockConnectivity,
    );
  });

  tearDown(() => db.close());

  group('watchProducts', () {
    test('emits cached data immediately without network', () async {
      // Arrange — seed local DB
      await dao.upsertProduct(ProductsCompanion.insert(
        id: 'p1',
        name: 'Product 1',
        price: 9.99,
        stock: const Value(10),
        categoryId: 'cat1',
        updatedAt: DateTime.now(),
      ));

      when(() => mockConnectivity.isReachable)
          .thenAnswer((_) async => false);

      // Act
      final stream = repository.watchProducts();

      // Assert — first emission is cached data
      final first = await stream.first;
      expect(first.isRight(), true);
      expect(first.getOrElse((_) => []).length, 1);
    });

    test('syncs from remote when connected', () async {
      when(() => mockConnectivity.isReachable)
          .thenAnswer((_) async => true);
      when(() => mockRemote.getProducts()).thenAnswer((_) async => [
        ProductDto(id: 'p1', name: 'Remote Product', price: 19.99, stock: 5),
      ]);

      final stream = repository.watchProducts();

      // Wait for sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      final emissions = await stream.take(2).toList();
      // Second emission should include synced data
      expect(emissions.last.getOrElse((_) => []).first.name, 'Remote Product');
    });
  });

  group('updateProduct', () {
    test('writes to local DB and enqueues sync', () async {
      when(() => mockSyncQueue.enqueue(any())).thenAnswer((_) async {});

      final product = Product(
        id: 'p1',
        name: 'Updated',
        price: 15.0,
        stock: 3,
        updatedAt: DateTime.now(),
      );

      final result = await repository.updateProduct(product);

      expect(result, const Right(unit));
      verify(() => mockSyncQueue.enqueue(any())).called(1);

      // Verify local DB was updated
      final saved = await dao.findById('p1');
      expect(saved?.name, 'Updated');
    });
  });
}
```

---

## 11. Database Selection Summary

| Scenario | Recommended | Reason |
|---|---|---|
| E-commerce catalog with categories | Drift | Relational joins, type-safe queries |
| Note-taking / document app | Isar | Simple NoSQL, full-text search |
| IoT / sensor data, high write volume | ObjectBox | Fastest writes, object graphs |
| Supabase/Postgres backend | PowerSync | Managed sync, no custom sync code |
| Simple user preferences | shared_preferences | No DB overhead needed |
| Chat / messaging | Drift or PowerSync | Ordered queries or managed sync |
| Offline maps / large binary assets | Drift + file system | DB for metadata, files for blobs |

> **Hive** is in maintenance mode as of 2025. Use **Isar** for new projects that previously would have used Hive.
