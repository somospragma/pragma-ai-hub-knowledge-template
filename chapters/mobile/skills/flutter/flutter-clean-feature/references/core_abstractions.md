# Core Abstractions

In a single project these live in `lib/core/`. In a monorepo in `packages/core/`.

## UseCase Base Classes

```dart
// lib/core/usecase/usecase.dart
import 'package:fpdart/fpdart.dart';
import '../error/failure.dart';

/// Use case with parameters
abstract interface class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Use case without parameters
abstract interface class UseCaseNoParams<Type> {
  Future<Either<Failure, Type>> call();
}

/// Use case that returns a stream (real-time data)
abstract interface class StreamUseCase<Type, Params> {
  Stream<Either<Failure, Type>> call(Params params);
}

/// Canonical placeholder for use cases with no params
class NoParams {
  const NoParams();
}
```

## ApiClient Contract

```dart
// lib/core/network/api_client.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class ApiClient {
  const ApiClient(this._dio);
  final Dio _dio;

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _dio.get(path, queryParameters: queryParameters, options: options);

  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) => _dio.post(path, data: data, queryParameters: queryParameters, options: options);

  Future<Response<dynamic>> put(
    String path, {
    dynamic data,
    Options? options,
  }) => _dio.put(path, data: data, options: options);

  Future<Response<dynamic>> patch(
    String path, {
    dynamic data,
    Options? options,
  }) => _dio.patch(path, data: data, options: options);

  Future<Response<dynamic>> delete(
    String path, {
    dynamic data,
    Options? options,
  }) => _dio.delete(path, data: data, options: options);
}
```

## CacheStore Contract

```dart
// lib/core/storage/cache_store.dart
abstract interface class CacheStore {
  Future<Map<String, dynamic>?> get(String key);
  Future<List<dynamic>?> getList(String key);
  Future<void> put(String key, Map<String, dynamic> value, {Duration? ttl});
  Future<void> putList(String key, List<dynamic> value, {Duration? ttl});
  Future<void> delete(String key);
  Future<void> deleteByPrefix(String prefix);
  Future<void> clear();
}

// lib/core/storage/hive_cache_store_impl.dart
@LazySingleton(as: CacheStore)
class HiveCacheStoreImpl implements CacheStore {
  static const _boxName = 'app_cache';
  static const _ttlSuffix = '_ttl';
  Box<dynamic>? _box;

  Future<Box<dynamic>> _getBox() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
    return _box!;
  }

  @override
  Future<Map<String, dynamic>?> get(String key) async {
    final box = await _getBox();
    final ttlKey = '$key$_ttlSuffix';
    final ttl = box.get(ttlKey) as int?;
    if (ttl != null && DateTime.now().millisecondsSinceEpoch > ttl) {
      await box.delete(key);
      await box.delete(ttlKey);
      return null;
    }
    final data = box.get(key);
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  @override
  Future<void> put(String key, Map<String, dynamic> value, {Duration? ttl}) async {
    final box = await _getBox();
    await box.put(key, value);
    if (ttl != null) {
      await box.put(
        '$key$_ttlSuffix',
        DateTime.now().add(ttl).millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> deleteByPrefix(String prefix) async {
    final box = await _getBox();
    final keys = box.keys.where((k) => k.toString().startsWith(prefix)).toList();
    await box.deleteAll(keys);
  }

  @override
  Future<void> clear() async => (await _getBox()).clear();

  @override
  Future<List<dynamic>?> getList(String key) async {
    final data = (await _getBox()).get(key);
    return data == null ? null : List<dynamic>.from(data as List);
  }

  @override
  Future<void> putList(String key, List<dynamic> value, {Duration? ttl}) async =>
      (await _getBox()).put(key, value);

  @override
  Future<void> delete(String key) async => (await _getBox()).delete(key);
}
```

## Auth Interceptor

```dart
// lib/core/network/interceptors/auth_interceptor.dart
@lazySingleton
class AuthInterceptor extends Interceptor {
  const AuthInterceptor(this._tokenRepository);
  final TokenRepository _tokenRepository;

  static const _publicPaths = ['/auth/login', '/auth/refresh', '/auth/register'];

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_publicPaths.any((p) => options.path.contains(p))) {
      return handler.next(options);
    }
    final token = await _tokenRepository.getValidAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      final refreshed = await _tokenRepository.refreshTokens();
      if (refreshed) {
        final token = await _tokenRepository.getAccessToken();
        err.requestOptions.headers['Authorization'] = 'Bearer $token';
        try {
          final response = await Dio().fetch(err.requestOptions);
          return handler.resolve(response);
        } catch (_) {}
      }
      await _tokenRepository.clearTokens();
    }
    handler.next(err);
  }
}
```
