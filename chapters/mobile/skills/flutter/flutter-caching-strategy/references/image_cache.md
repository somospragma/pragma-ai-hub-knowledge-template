# Image Cache

Image caching in Flutter: disk + memory caching for network images,
memory limits, and asset preloading.

## Setup

```yaml
dependencies:
  cached_network_image: ^3.4.0
  flutter_cache_manager: ^3.4.0  # underlying cache manager (also used standalone)
```

## Global Image Cache Limits

Set at app startup — prevents unbounded memory growth on image-heavy screens.

```dart
// lib/core/config/image_cache_config.dart
class ImageCacheConfig {
  static void configure() {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 50 * 1024 * 1024  // 50MB decoded image memory
      ..maximumSize = 100;                    // max 100 decoded images
  }
}

// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ImageCacheConfig.configure();
  // ...
  runApp(const App());
}
```

## CachedNetworkImage — Standard Usage

```dart
// ✅ With placeholder and error widget
CachedNetworkImage(
  imageUrl: product.imageUrl,
  // Decode at display size — saves heap memory
  memCacheWidth: (displayWidth * MediaQuery.devicePixelRatioOf(context)).round(),
  memCacheHeight: (displayHeight * MediaQuery.devicePixelRatioOf(context)).round(),
  fit: BoxFit.cover,
  placeholder: (context, url) => const ShimmerPlaceholder(),
  errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 48),
)

// ✅ As ImageProvider (for BoxDecoration, CircleAvatar, etc.)
CircleAvatar(
  backgroundImage: CachedNetworkImageProvider(
    user.avatarUrl,
    maxWidth: 100,
    maxHeight: 100,
  ),
  radius: 24,
)

// ✅ With progress indicator
CachedNetworkImage(
  imageUrl: url,
  progressIndicatorBuilder: (context, url, progress) =>
      CircularProgressIndicator(value: progress.progress),
  errorWidget: (_, __, ___) => const Icon(Icons.error),
)
```

## Custom Cache Manager — TTL and Max Objects

```dart
// lib/core/cache/custom_cache_manager.dart
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ProductImageCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'product_images';

  ProductImageCacheManager()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 7),   // TTL
          maxNrOfCacheObjects: 500,                // max files on disk
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: HttpFileService(),
        ));
}

// Usage with CachedNetworkImage
CachedNetworkImage(
  imageUrl: product.imageUrl,
  cacheManager: GetIt.instance<ProductImageCacheManager>(),
  memCacheWidth: 400,
  memCacheHeight: 400,
)
```

## Preloading Critical Images

Preload above-the-fold images after the first frame to ensure instant display.

```dart
// lib/core/cache/image_preloader.dart
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ImagePreloader {
  /// Preload a list of image URLs into the Flutter image cache.
  /// Call from addPostFrameCallback — after first frame is rendered.
  Future<void> preload(BuildContext context, List<String> urls) async {
    await Future.wait(
      urls.map((url) => precacheImage(
        CachedNetworkImageProvider(url, maxWidth: 400, maxHeight: 400),
        context,
      )),
    );
  }
}

// Usage in main.dart or home screen initState:
WidgetsBinding.instance.addPostFrameCallback((_) async {
  if (!mounted) return;
  await GetIt.instance<ImagePreloader>().preload(
    context,
    featuredProducts.map((p) => p.imageUrl).take(5).toList(),
  );
});
```

## Cache Eviction

```dart
// Evict a specific image from memory and disk cache
Future<void> evictImage(String url) async {
  // Remove from Flutter's in-memory image cache
  imageCache.evict(CachedNetworkImageProvider(url));

  // Remove from disk cache
  await DefaultCacheManager().removeFile(url);
}

// Evict all images for a screen (e.g., when navigating away from a gallery)
@override
void dispose() {
  for (final url in widget.imageUrls) {
    imageCache.evict(CachedNetworkImageProvider(url));
  }
  super.dispose();
}

// Clear entire disk cache (e.g., on logout)
Future<void> clearImageCache() async {
  imageCache.clear();
  await DefaultCacheManager().emptyCache();
}
```

## SVG — Zero Raster Memory for Icons and Illustrations

```yaml
dependencies:
  flutter_svg: ^2.0.0
```

```dart
// ✅ SVG scales perfectly, no raster memory cost
SvgPicture.asset(
  'assets/icons/home.svg',
  width: 24,
  height: 24,
  colorFilter: ColorFilter.mode(Colors.blue, BlendMode.srcIn),
)

// ✅ Network SVG with caching
SvgPicture.network(
  'https://cdn.example.com/icons/home.svg',
  width: 24,
  height: 24,
)
```

## Best Practices

| Concern | Rule |
|---|---|
| Memory limits | Always set `imageCache.maximumSizeBytes` at startup |
| Decode size | Always set `memCacheWidth`/`memCacheHeight` to display size × DPR |
| Icons | Use SVG (`flutter_svg`) — no raster memory |
| Thumbnails | Use `CachedNetworkImageProvider` with `maxWidth`/`maxHeight` |
| Galleries | Evict images in `dispose()` when navigating away |
| Logout | Call `imageCache.clear()` + `DefaultCacheManager().emptyCache()` |
| Preloading | Use `precacheImage` in `addPostFrameCallback`, not in `main()` |
