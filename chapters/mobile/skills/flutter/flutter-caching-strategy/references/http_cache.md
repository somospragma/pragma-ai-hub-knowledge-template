# HTTP Cache — dio_cache_interceptor

HTTP response caching using `dio_cache_interceptor`. Respects standard HTTP cache
directives (ETag, Last-Modified, Cache-Control, max-stale) and supports offline fallback.

## Setup

```yaml
dependencies:
  dio: ^5.8.0
  dio_cache_interceptor: ^3.5.0

  # Choose ONE backing store:
  dio_cache_interceptor_drift_store: ^3.2.0   # Drift (recommended)
  # dio_cache_interceptor_isar_store: ^3.1.0  # Isar community
  # dio_cache_interceptor_objectbox_store: ^3.1.0 # ObjectBox (no web)
  # dio_cache_interceptor/mem_cache_store      # built-in, volatile
```

## Backing Store Setup

### Drift store (recommended)

```dart
// lib/core/network/cache/http_cache_store.dart
import 'package:dio_cache_interceptor_drift_store/dio_cache_interceptor_drift_store.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class HttpCacheStoreProvider {
  final AppDatabase _db;
  HttpCacheStoreProvider(this._db);

  late final DriftCacheStore store = DriftCacheStore(_db);
}
```

### In-memory store (for tests or ephemeral cache)

```dart
// Volatile — cleared on app restart, LRU eviction
final store = MemCacheStore(maxSize: 10 * 1024 * 1024); // 10MB
```

## Global Cache Configuration

```dart
// lib/core/network/cache/cache_options_factory.dart
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class CacheOptionsFactory {
  final HttpCacheStoreProvider _storeProvider;
  CacheOptionsFactory(this._storeProvider);

  /// Standard: respects HTTP Cache-Control, falls back to cache on network error
  CacheOptions get standard => CacheOptions(
    store: _storeProvider.store,
    policy: CachePolicy.request,
    hitCacheOnNetworkFailure: true,   // serve stale when offline
    hitCacheOnErrorCodes: [500, 503], // serve stale on server errors
    maxStale: const Duration(days: 7),
    priority: CachePriority.normal,
  );

  /// Short-lived: for frequently changing data (prices, stock)
  CacheOptions get shortLived => CacheOptions(
    store: _storeProvider.store,
    policy: CachePolicy.request,
    hitCacheOnNetworkFailure: true,
    maxStale: const Duration(minutes: 5),
    priority: CachePriority.high,
  );

  /// Long-lived: for rarely changing data (config, categories)
  CacheOptions get longLived => CacheOptions(
    store: _storeProvider.store,
    policy: CachePolicy.request,
    hitCacheOnNetworkFailure: true,
    maxStale: const Duration(days: 30),
    priority: CachePriority.low,
  );

  /// No cache: for auth, payments, mutations
  CacheOptions get noCache => CacheOptions(
    store: _storeProvider.store,
    policy: CachePolicy.noCache,
  );
}
```

## Dio Setup with Cache Interceptor

```dart
// lib/core/network/dio_factory.dart
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class DioFactory {
  final CacheOptionsFactory _cacheOptions;

  DioFactory(this._cacheOptions);

  Dio create({String? baseUrl}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl ?? '',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    dio.interceptors.addAll([
      DioCacheInterceptor(options: _cacheOptions.standard),
      // Add auth, logging interceptors here
    ]);

    return dio;
  }
}
```

## Cache Policies Reference

| Policy | Behavior |
|---|---|
| `CachePolicy.request` | Respects HTTP Cache-Control headers (default) |
| `CachePolicy.forceCache` | Always return cache, never hit network |
| `CachePolicy.refresh` | Always hit network, update cache |
| `CachePolicy.refreshForceCache` | Hit network, update cache, return cache on error |
| `CachePolicy.noCache` | Never cache, always hit network |

## Per-Request Policy Overrides

```dart
// lib/features/product/data/datasources/product_remote_data_source.dart
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:injectable/injectable.dart';

@injectable
class ProductRemoteDataSource {
  final Dio _dio;
  final CacheOptionsFactory _cacheOptions;

  ProductRemoteDataSource(this._dio, this._cacheOptions);

  /// Normal fetch — uses standard cache (stale-while-revalidate via maxStale)
  Future<List<ProductDto>> getProducts() async {
    final response = await _dio.get('/products');
    return (response.data as List).map(ProductDto.fromJson).toList();
  }

  /// Pull-to-refresh — force network, update cache
  Future<List<ProductDto>> refreshProducts() async {
    final response = await _dio.get(
      '/products',
      options: _cacheOptions.standard
          .copyWith(policy: CachePolicy.refresh)
          .toOptions(),
    );
    return (response.data as List).map(ProductDto.fromJson).toList();
  }

  /// Offline mode — return cache only, error if missing
  Future<List<ProductDto>> getProductsCachedOnly() async {
    final response = await _dio.get(
      '/products',
      options: _cacheOptions.standard
          .copyWith(policy: CachePolicy.forceCache)
          .toOptions(),
    );
    return (response.data as List).map(ProductDto.fromJson).toList();
  }

  /// Prices — short TTL, no stale fallback
  Future<PriceDto> getPrice(String productId) async {
    final response = await _dio.get(
      '/products/$productId/price',
      options: _cacheOptions.shortLived.toOptions(),
    );
    return PriceDto.fromJson(response.data);
  }

  /// Config — long TTL, rarely changes
  Future<AppConfigDto> getConfig() async {
    final response = await _dio.get(
      '/config',
      options: _cacheOptions.longLived.toOptions(),
    );
    return AppConfigDto.fromJson(response.data);
  }

  /// Auth — never cached
  Future<TokenDto> login(String email, String password) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password},
      options: _cacheOptions.noCache.toOptions(),
    );
    return TokenDto.fromJson(response.data);
  }
}
```

## ETag and Conditional Requests

`dio_cache_interceptor` handles ETag and `If-None-Match` automatically when the server
sends `ETag` headers. No additional code needed — the interceptor:

1. Stores the `ETag` value with the cached response
2. On subsequent requests, sends `If-None-Match: <etag>`
3. On `304 Not Modified`, returns the cached response without re-downloading the body

```dart
// Server response (first request):
// ETag: "abc123"
// Cache-Control: max-age=300

// Interceptor automatically sends on next request:
// If-None-Match: "abc123"

// Server responds 304 → interceptor returns cached body
// Server responds 200 → interceptor updates cache with new body + ETag
```

## Cache Invalidation

```dart
// lib/core/network/cache/cache_invalidation_service.dart
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class CacheInvalidationService {
  final HttpCacheStoreProvider _storeProvider;
  CacheInvalidationService(this._storeProvider);

  /// Invalidate a specific endpoint
  Future<void> invalidate(String url) async {
    final key = CacheOptions.defaultCacheKeyBuilder(
      RequestOptions(path: url),
    );
    await _storeProvider.store.delete(key);
  }

  /// Clear all cached responses — call on logout or user switch
  Future<void> clearAll() async {
    await _storeProvider.store.clean();
  }

  /// Clear entries older than a given duration
  Future<void> clearExpired() async {
    await _storeProvider.store.clean(
      staleOnly: true,
    );
  }
}
```

## Testing

```dart
// Use MemCacheStore in tests — no file I/O, isolated per test
void main() {
  late Dio dio;
  late CacheOptions testCacheOptions;

  setUp(() {
    testCacheOptions = CacheOptions(
      store: MemCacheStore(),
      policy: CachePolicy.request,
      hitCacheOnNetworkFailure: true,
      maxStale: const Duration(minutes: 5),
    );

    dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: testCacheOptions));
  });

  test('returns cached response on second request', () async {
    // First request — hits network
    final first = await dio.get('https://httpbin.org/get');
    expect(first.statusCode, 200);

    // Second request — served from cache
    final second = await dio.get('https://httpbin.org/get');
    expect(second.extra[CacheResponse.cacheKey], isNotNull); // cache hit
  });
}
```
