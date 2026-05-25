---
name: flutter-caching-strategy
description: >
  Implements caching strategies in Flutter: HTTP response caching with dio_cache_interceptor (ETag, TTL, stale-while-revalidate, offline fallback), in-memory LRU cache, data-layer TTL cache with Drift/Isar, and image caching with cached_network_image. Use this skill when implementing API response caching, reducing redundant network calls, serving stale data while revalidating, or caching images and assets.
commands:
  - setup-caching
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the caching infrastructure (HTTP interceptor, TTL cache, image cache config), "audit" checks for missing cache layers, unbounded caches, or stale data not being served offline.
    required: true
  - name: target
    description: Path to the network/data directory or project root (e.g. lib/core/network/ for HTTP cache, lib/ for full audit).
    required: true
  - name: layer
    description: Cache layer to implement (http, data-ttl, image, in-memory, all). Defaults to all.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Caching Strategy

See the reference files for complete patterns and code examples.

**Core principle: The fastest request is the one never made.**

## Cache Layers

```
┌─────────────────────────────────────────────────────┐
│  1. In-memory (LRU)     — microseconds, process-scoped │
│  2. HTTP cache          — milliseconds, disk-backed    │
│  3. Data-layer TTL      — milliseconds, DB-backed      │
│  4. Image cache         — disk + memory, auto-managed  │
└─────────────────────────────────────────────────────┘
```

## Package Status (April 2026)

| Package | Version | Purpose |
|---|---|---|
| **dio_cache_interceptor** | 3.x | HTTP response caching (ETag, TTL, stale-while-revalidate) |
| **dio_cache_interceptor_drift_store** | 3.x | Drift backing store for HTTP cache |
| **dio_cache_interceptor_isar_store** | 3.x | Isar backing store for HTTP cache |
| **cached_network_image** | 3.x | Image caching (disk + memory) |
| **flutter_cache_manager** | 3.x | Generic file/asset caching |

---

## Cache Strategies

| Strategy | When to use | Behavior |
|---|---|---|
| **Cache-first** | Rarely changing data (config, catalogs) | Return cache immediately, skip network |
| **Network-first** | Real-time data (prices, stock) | Try network, fall back to cache on failure |
| **Stale-while-revalidate** | Most UI data | Return cache immediately, refresh in background |
| **Cache-only** | Offline mode | Return cache, error if missing |
| **Network-only** | Auth, payments | Always hit network, never cache |

---

## HTTP Cache — dio_cache_interceptor

```dart
// Global cache options — stale-while-revalidate with 7-day max-stale
final cacheOptions = CacheOptions(
  store: DriftCacheStore(db),          // or IsarCacheStore, MemCacheStore
  policy: CachePolicy.request,         // respects HTTP Cache-Control headers
  hitCacheOnNetworkFailure: true,       // serve stale on network error (offline)
  maxStale: const Duration(days: 7),   // override: keep cache up to 7 days
  priority: CachePriority.normal,
);

final dio = Dio()
  ..interceptors.add(DioCacheInterceptor(options: cacheOptions));
```

```dart
// Per-request policy override
// Force refresh — bypass cache for this request
final response = await dio.get(
  '/products',
  options: cacheOptions.copyWith(policy: CachePolicy.refresh).toOptions(),
);

// Cache-only — never hit network
final cached = await dio.get(
  '/config',
  options: cacheOptions.copyWith(policy: CachePolicy.forceCache).toOptions(),
);
```

---

## Data-Layer TTL Cache

For data that doesn't come from HTTP (e.g., computed results, aggregations):

```dart
@lazySingleton
class TtlCache<K, V> {
  final Duration ttl;
  final _store = <K, _CacheEntry<V>>{};

  TtlCache({required this.ttl});

  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  void set(K key, V value) {
    _store[key] = _CacheEntry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  void invalidate(K key) => _store.remove(key);
  void clear() => _store.clear();
}
```

---

## Image Cache

```dart
// ✅ cached_network_image — disk + memory, placeholder, error widget
CachedNetworkImage(
  imageUrl: url,
  memCacheWidth: 400,   // decode at display size — saves heap memory
  memCacheHeight: 400,
  placeholder: (_, __) => const ShimmerPlaceholder(),
  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
)

// ✅ Set global image cache limits
PaintingBinding.instance.imageCache
  ..maximumSizeBytes = 50 * 1024 * 1024  // 50MB
  ..maximumSize = 100;
```

---

## Architecture Integration

```
Presentation (BLoC)
  ↓
Domain (UseCase)
  ↓
Data (RepositoryImpl)
  ├── RemoteDataSource (Dio + DioCacheInterceptor)  ← HTTP cache
  ├── LocalDataSource (Drift/Isar DAO)              ← data-layer TTL cache
  └── TtlCache<K,V>                                 ← in-memory cache
```

All dependencies injected via GetIt + Injectable.
Errors returned as `Either<Failure, T>` using fpdart.

---

## Quick Wins Checklist

- [ ] `DioCacheInterceptor` added to Dio with `hitCacheOnNetworkFailure: true`
- [ ] Cache store backed by Drift or Isar (not Hive — maintenance mode)
- [ ] `maxStale` set per endpoint category (config: 7d, catalog: 1h, prices: 5min)
- [ ] `CachePolicy.refresh` used on pull-to-refresh
- [ ] `CachePolicy.forceCache` used in offline mode
- [ ] `cached_network_image` used for all network images
- [ ] `imageCache.maximumSizeBytes` set at app startup
- [ ] Cache invalidated on logout / user switch

## Reference Files

- `references/http_cache.md` — dio_cache_interceptor setup, policies, ETag, per-request overrides
- `references/data_ttl_cache.md` — in-memory LRU, data-layer TTL, repository integration
- `references/image_cache.md` — cached_network_image, flutter_cache_manager, memory limits
