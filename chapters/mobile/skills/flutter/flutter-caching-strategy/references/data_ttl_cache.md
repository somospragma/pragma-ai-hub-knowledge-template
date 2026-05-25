# Data-Layer TTL Cache

In-memory and data-layer caching for computed results, aggregations, and data
that doesn't come from HTTP endpoints.

## In-Memory LRU Cache

```dart
// lib/core/cache/ttl_cache.dart
import 'package:injectable/injectable.dart';

class _CacheEntry<V> {
  final V value;
  final DateTime expiresAt;
  _CacheEntry({required this.value, required this.expiresAt});
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Generic TTL cache with LRU eviction.
/// Inject as a named singleton per use case.
class TtlCache<K, V> {
  final Duration ttl;
  final int maxSize;
  final _store = <K, _CacheEntry<V>>{};

  TtlCache({required this.ttl, this.maxSize = 100});

  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    // LRU: move to end on access
    _store.remove(key);
    _store[key] = entry;
    return entry.value;
  }

  void set(K key, V value) {
    // Evict oldest entry if at capacity
    if (_store.length >= maxSize && !_store.containsKey(key)) {
      _store.remove(_store.keys.first);
    }
    _store[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  bool containsKey(K key) => get(key) != null;

  void invalidate(K key) => _store.remove(key);

  void invalidateWhere(bool Function(K key) predicate) =>
      _store.removeWhere((key, _) => predicate(key));

  void clear() => _store.clear();

  int get size => _store.length;
}
```

## Repository Integration — Cache-Aside Pattern

```dart
// lib/features/product/data/repositories/product_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  final ProductRemoteDataSource _remote;
  final ProductDao _dao;
  final ProductMapper _mapper;

  // In-memory cache: product list per category, 5-minute TTL
  final _listCache = TtlCache<String, List<Product>>(
    ttl: const Duration(minutes: 5),
    maxSize: 50,
  );

  // In-memory cache: single product, 10-minute TTL
  final _detailCache = TtlCache<String, Product>(
    ttl: const Duration(minutes: 10),
    maxSize: 200,
  );

  ProductRepositoryImpl(this._remote, this._dao, this._mapper);

  @override
  Future<Either<Failure, List<Product>>> getProducts(String categoryId) async {
    // 1. Check in-memory cache first (fastest)
    final cached = _listCache.get(categoryId);
    if (cached != null) return Right(cached);

    // 2. Check local DB (fast, persisted)
    final local = await _dao.findByCategory(categoryId);
    if (local.isNotEmpty) {
      final products = local.map(_mapper.fromRow).toList();
      _listCache.set(categoryId, products); // warm in-memory cache
      return Right(products);
    }

    // 3. Fetch from network
    try {
      final dtos = await _remote.getProducts(categoryId: categoryId);
      final products = dtos.map(_mapper.fromDto).toList();

      // Persist to DB and warm caches
      await _dao.upsertAll(dtos.map(_mapper.toCompanion).toList());
      _listCache.set(categoryId, products);

      return Right(products);
    } on DioException catch (e) {
      return Left(Failure.network(message: e.message ?? 'Network error'));
    }
  }

  @override
  Future<Either<Failure, Product>> getProduct(String id) async {
    // 1. In-memory cache
    final cached = _detailCache.get(id);
    if (cached != null) return Right(cached);

    // 2. Local DB
    final local = await _dao.findById(id);
    if (local != null) {
      final product = _mapper.fromRow(local);
      _detailCache.set(id, product);
      return Right(product);
    }

    // 3. Network
    try {
      final dto = await _remote.getProduct(id);
      final product = _mapper.fromDto(dto);
      await _dao.upsert(_mapper.toCompanion(dto));
      _detailCache.set(id, product);
      return Right(product);
    } on DioException catch (e) {
      return Left(Failure.network(message: e.message ?? 'Network error'));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveProduct(Product product) async {
    try {
      await _dao.upsert(_mapper.toCompanion(product));
      // Invalidate affected cache entries
      _detailCache.invalidate(product.id);
      _listCache.invalidate(product.categoryId);
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteProduct(String id) async {
    try {
      final product = await _dao.findById(id);
      await _dao.deleteById(id);
      _detailCache.invalidate(id);
      if (product != null) _listCache.invalidate(product.categoryId);
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }

  /// Force refresh — bypass all caches
  Future<Either<Failure, List<Product>>> refreshProducts(String categoryId) async {
    _listCache.invalidate(categoryId);
    return getProducts(categoryId);
  }
}
```

## Stale-While-Revalidate Pattern

Return stale data immediately, refresh in background, emit updated data via stream.

```dart
// lib/features/product/data/repositories/product_repository_impl.dart

@override
Stream<Either<Failure, List<Product>>> watchProducts(String categoryId) async* {
  // 1. Emit stale data immediately (zero latency)
  final stale = _listCache.get(categoryId)
      ?? (await _dao.findByCategory(categoryId)).map(_mapper.fromRow).toList();

  if (stale.isNotEmpty) {
    yield Right(stale);
  }

  // 2. Revalidate in background
  try {
    final dtos = await _remote.getProducts(categoryId: categoryId);
    final fresh = dtos.map(_mapper.fromDto).toList();
    await _dao.upsertAll(dtos.map(_mapper.toCompanion).toList());
    _listCache.set(categoryId, fresh);
    yield Right(fresh);
  } on DioException catch (e) {
    if (stale.isEmpty) {
      yield Left(Failure.network(message: e.message ?? 'Network error'));
    }
    // If we had stale data, silently swallow the error — user already has data
  }
}
```

## Cache Invalidation Strategies

```dart
// lib/core/cache/cache_invalidation_service.dart
import 'package:injectable/injectable.dart';

@lazySingleton
class CacheInvalidationService {
  final TtlCache<String, List<Product>> _productListCache;
  final TtlCache<String, Product> _productDetailCache;
  final CacheInvalidationService _httpCacheService;

  CacheInvalidationService(
    this._productListCache,
    this._productDetailCache,
    this._httpCacheService,
  );

  /// Call on logout — clear all user-specific caches
  Future<void> onLogout() async {
    _productListCache.clear();
    _productDetailCache.clear();
    await _httpCacheService.clearAll();
  }

  /// Call after a product mutation
  void onProductMutated(String productId, String categoryId) {
    _productDetailCache.invalidate(productId);
    _productListCache.invalidate(categoryId);
  }

  /// Call on pull-to-refresh
  void onPullToRefresh(String categoryId) {
    _productListCache.invalidate(categoryId);
  }
}
```

## BLoC Integration

```dart
// lib/features/product/presentation/bloc/product_bloc.dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final GetProductsUseCase _getProducts;
  final RefreshProductsUseCase _refreshProducts;

  ProductBloc(this._getProducts, this._refreshProducts)
      : super(const ProductState.initial()) {
    on<LoadProductsEvent>(_onLoad);
    on<RefreshProductsEvent>(_onRefresh);
  }

  Future<void> _onLoad(
    LoadProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    // Don't show loading if we already have data (stale-while-revalidate)
    if (state is! ProductSuccess) {
      emit(const ProductState.loading());
    }

    final result = await _getProducts(event.categoryId);
    result.fold(
      (failure) => emit(ProductState.error(failure.message)),
      (products) => emit(ProductState.success(products: products)),
    );
  }

  Future<void> _onRefresh(
    RefreshProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    // Keep current data visible during refresh
    emit(state.copyWith(isRefreshing: true));

    final result = await _refreshProducts(event.categoryId);
    result.fold(
      (failure) => emit(state.copyWith(isRefreshing: false, error: failure.message)),
      (products) => emit(ProductState.success(products: products, isRefreshing: false)),
    );
  }
}
```

## Testing

```dart
// test/features/product/data/repositories/product_repository_impl_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockProductRemoteDataSource extends Mock implements ProductRemoteDataSource {}
class MockProductDao extends Mock implements ProductDao {}

void main() {
  late ProductRepositoryImpl repository;
  late MockProductRemoteDataSource mockRemote;
  late MockProductDao mockDao;

  setUp(() {
    mockRemote = MockProductRemoteDataSource();
    mockDao = MockProductDao();
    repository = ProductRepositoryImpl(mockRemote, mockDao, ProductMapper());
  });

  group('getProducts', () {
    test('returns network data and warms cache on first call', () async {
      when(() => mockDao.findByCategory('cat1')).thenAnswer((_) async => []);
      when(() => mockRemote.getProducts(categoryId: 'cat1'))
          .thenAnswer((_) async => [ProductDto(id: 'p1', name: 'Test', price: 9.99)]);
      when(() => mockDao.upsertAll(any())).thenAnswer((_) async {});

      final result = await repository.getProducts('cat1');

      expect(result.isRight(), true);
      expect(result.getOrElse((_) => []).first.id, 'p1');
    });

    test('returns in-memory cache on second call without hitting network', () async {
      when(() => mockDao.findByCategory('cat1')).thenAnswer((_) async => []);
      when(() => mockRemote.getProducts(categoryId: 'cat1'))
          .thenAnswer((_) async => [ProductDto(id: 'p1', name: 'Test', price: 9.99)]);
      when(() => mockDao.upsertAll(any())).thenAnswer((_) async {});

      // First call — hits network
      await repository.getProducts('cat1');

      // Second call — should use in-memory cache
      final result = await repository.getProducts('cat1');

      expect(result.isRight(), true);
      // Remote was only called once
      verify(() => mockRemote.getProducts(categoryId: 'cat1')).called(1);
    });

    test('invalidates cache after saveProduct', () async {
      when(() => mockDao.upsert(any())).thenAnswer((_) async {});
      when(() => mockDao.findByCategory('cat1')).thenAnswer((_) async => []);
      when(() => mockRemote.getProducts(categoryId: 'cat1'))
          .thenAnswer((_) async => []);
      when(() => mockDao.upsertAll(any())).thenAnswer((_) async {});

      // Warm cache
      await repository.getProducts('cat1');

      // Mutate
      await repository.saveProduct(Product(
        id: 'p1', name: 'Updated', price: 15.0,
        stock: 1, categoryId: 'cat1', updatedAt: DateTime.now(),
      ));

      // Next call should hit network again (cache invalidated)
      await repository.getProducts('cat1');
      verify(() => mockRemote.getProducts(categoryId: 'cat1')).called(2);
    });
  });
}
```
