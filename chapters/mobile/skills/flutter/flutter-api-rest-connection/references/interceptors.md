# Interceptors — Auth, Retry, Error, Logging

## AuthInterceptor — Token Injection + 401 Refresh

The most critical interceptor. Adds the Bearer token to every request and
handles token refresh when a 401 is received — using a `Lock` to prevent
concurrent refresh race conditions.

```dart
// lib/core/network/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:synchronized/synchronized.dart';

@injectable
class AuthInterceptor extends Interceptor {
  final TokenRepository _tokenRepository;
  final Lock _refreshLock = Lock();

  AuthInterceptor(this._tokenRepository);

  // ── Request: inject token ─────────────────────────────────────────────

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenRepository.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // ── Response error: handle 401 ────────────────────────────────────────

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    try {
      // ✅ Lock prevents multiple concurrent refresh calls
      final newToken = await _refreshLock.synchronized(() async {
        // Check if another waiter already refreshed the token
        final currentToken = await _tokenRepository.getAccessToken();
        final requestToken = err.requestOptions.headers['Authorization']
            ?.toString()
            .replaceFirst('Bearer ', '');

        if (currentToken != null && currentToken != requestToken) {
          return currentToken; // already refreshed — reuse
        }

        return await _tokenRepository.refreshToken();
      });

      // Retry the original request with the new token
      final retryOptions = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newToken';

      final response = await Dio().fetch(retryOptions);
      handler.resolve(response);
    } on UnauthorizedException {
      // Refresh failed — force logout
      await _tokenRepository.clearTokens();
      handler.next(err);
    } catch (e) {
      handler.next(err);
    }
  }
}
```

---

## RetryInterceptor — Transient Network Failures

Retries on connection timeout, receive timeout, and connection errors.
Uses exponential backoff. Does NOT retry on 4xx/5xx responses.

```dart
// lib/core/network/interceptors/retry_interceptor.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@injectable
class RetryInterceptor extends Interceptor {
  static const _maxRetries = 3;
  static const _initialDelay = Duration(milliseconds: 500);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;

    final shouldRetry = _isRetryable(err) && retryCount < _maxRetries;

    if (!shouldRetry) {
      return handler.next(err);
    }

    // Exponential backoff: 500ms, 1000ms, 2000ms
    final delay = _initialDelay * (1 << retryCount);
    await Future.delayed(delay);

    err.requestOptions.extra['retryCount'] = retryCount + 1;

    try {
      final response = await Dio().fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  bool _isRetryable(DioException err) => switch (err.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.connectionError => true,
    _ => false,
  };
}
```

---

## ErrorInterceptor — DioException → AppException

Converts all `DioException` types into a unified `AppException` so that
`RepositoryImpl` only needs to catch one type.

```dart
// lib/core/network/interceptors/error_interceptor.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@injectable
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final appException = _mapToAppException(err);
    handler.next(
      err.copyWith(error: appException),
    );
  }

  AppException _mapToAppException(DioException err) {
    // Cancelled by CancelToken
    if (err.type == DioExceptionType.cancel) {
      return AppException.cancelled(message: err.message);
    }

    // Network / timeout errors (no response)
    if (err.response == null) {
      return switch (err.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          AppException.timeout(message: err.message),
        DioExceptionType.connectionError =>
          AppException.network(message: err.message),
        _ => AppException.unknown(message: err.message, error: err),
      };
    }

    // HTTP error responses
    final statusCode = err.response!.statusCode;
    final message = _extractMessage(err.response);

    return switch (statusCode) {
      401 => AppException.unauthorized(message: message),
      403 => AppException.forbidden(message: message),
      404 => AppException.notFound(message: message),
      409 => AppException.conflict(message: message),
      422 => AppException.unprocessable(
          message: message,
          fieldErrors: _extractFieldErrors(err.response),
        ),
      >= 500 => AppException.server(message: message, statusCode: statusCode),
      _ => AppException.unknown(message: message),
    };
  }

  String? _extractMessage(Response? response) {
    try {
      final data = response?.data;
      if (data is Map<String, dynamic>) {
        return data['message'] as String? ??
            data['error'] as String? ??
            data['detail'] as String?;
      }
    } catch (_) {}
    return 'HTTP ${response?.statusCode}';
  }

  Map<String, List<String>>? _extractFieldErrors(Response? response) {
    try {
      final data = response?.data as Map<String, dynamic>?;
      final errors = data?['errors'] as Map<String, dynamic>?;
      return errors?.map(
        (key, value) => MapEntry(
          key,
          (value as List).cast<String>(),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
```

---

## Failure Mapping in RepositoryImpl

After `ErrorInterceptor` converts `DioException` → `AppException`,
`RepositoryImpl` maps `AppException` → domain `Failure`:

```dart
// lib/{feature}/data/repositories/product_repository_impl.dart
@LazySingleton(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._remoteDataSource, this._localDataSource);
  final ProductRemoteDataSource _remoteDataSource;
  final ProductLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, Product>> getProduct({required String id}) async {
    try {
      final cached = await _localDataSource.getCachedProduct(id);
      if (cached != null) return Right(ProductMapper.fromModel(cached));

      final model = await _remoteDataSource.getProduct(id);
      await _localDataSource.cacheProduct(model);
      return Right(ProductMapper.fromModel(model));

    } on DioException catch (e) {
      // ErrorInterceptor already set e.error to AppException
      return Left(_mapAppException(e.error as AppException? ??
          AppException.unknown(message: e.message)));
    } catch (e) {
      return Left(Failure.unexpected(error: e));
    }
  }

  Failure _mapAppException(AppException e) => e.when(
    network: (msg) => Failure.network(message: msg),
    timeout: (msg) => Failure.network(message: msg ?? 'Request timed out'),
    unauthorized: (msg) => Failure.unauthorized(message: msg),
    forbidden: (msg) => Failure.unauthorized(message: msg),
    notFound: (msg) => Failure.notFound(message: msg),
    conflict: (msg) => Failure.server(message: msg),
    unprocessable: (msg, fields) => Failure.validation(
      message: msg,
      fieldErrors: fields,
    ),
    server: (msg, code) => Failure.server(message: msg, statusCode: code),
    cancelled: (msg) => Failure.network(message: msg ?? 'Request cancelled'),
    unknown: (msg, err) => Failure.unexpected(message: msg, error: err),
  );
}
```
