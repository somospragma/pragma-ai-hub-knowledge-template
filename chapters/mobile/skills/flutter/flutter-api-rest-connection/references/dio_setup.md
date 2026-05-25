# Dio Setup — Client, DI Module, ApiClient Interface

## ApiClient Interface (Domain boundary)

```dart
// lib/core/network/api_client.dart
import 'package:dio/dio.dart';

/// HTTP contract — the only thing DataSources know about.
/// Domain never imports this.
abstract interface class ApiClient {
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  });

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  });

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  });

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  });

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  });
}
```

## ApiClientImpl

```dart
// lib/core/network/api_client_impl.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ApiClient)
class ApiClientImpl implements ApiClient {
  ApiClientImpl(this._dio);
  final Dio _dio;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
  }) =>
      _dio.post<T>(
        path,
        data: data,
        options: options,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
      );

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.put<T>(path, data: data, options: options, cancelToken: cancelToken);

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.patch<T>(path, data: data, options: options, cancelToken: cancelToken);

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.delete<T>(path, data: data, options: options, cancelToken: cancelToken);
}
```

## DI Network Module

```dart
// lib/core/di/modules/network_module.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter/foundation.dart';

@module
abstract class NetworkModule {

  /// Single Dio instance — shared across the entire app.
  @lazySingleton
  Dio dio(
    AuthInterceptor authInterceptor,
    RetryInterceptor retryInterceptor,
    ErrorInterceptor errorInterceptor,
  ) {
    final dio = Dio(
      BaseOptions(
        baseUrl: const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'https://api.yourapp.com/v1',
        ),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    dio.interceptors.addAll([
      authInterceptor,    // 1st: adds auth header, handles 401
      retryInterceptor,   // 2nd: retries on network failure
      errorInterceptor,   // 3rd: maps DioException → AppException
      // Logging last — sees the final request/response
      if (!kReleaseMode)
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
        ),
    ]);

    return dio;
  }
}
```

## Environment Base URL

The base URL must come from the environment configuration — never hardcoded.
If the project uses **flavors or schemes**, the URL is resolved through the
flavor config (see `flutter-environments` skill). If not, use `--dart-define`.

### With flavors / schemes (recommended for multi-environment projects)

```dart
// lib/core/config/env.dart
// Populated by the flavor config — see flutter-environments skill
abstract final class Env {
  // Resolved at build time from flavor (dev/staging/prod)
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.yourapp.com/v1',
  );

  static const isProduction = bool.fromEnvironment(
    'IS_PRODUCTION',
    defaultValue: false,
  );
}
```

```dart
// With envied (flutter-environments skill pattern):
// lib/core/config/env.g.dart — generated from .env.dev / .env.staging / .env.prod
@EnviedField(varName: 'API_BASE_URL')
static const String apiBaseUrl = _Env.apiBaseUrl;
```

```bash
# Flavor-based builds — base URL comes from the flavor config
flutter run --flavor dev      # uses .env.dev → API_BASE_URL=https://dev-api.yourapp.com/v1
flutter run --flavor staging  # uses .env.staging
flutter build apk --flavor prod  # uses .env.prod
```

### Without flavors (simple projects)

```bash
flutter run --dart-define=API_BASE_URL=https://dev-api.yourapp.com/v1
flutter build apk --dart-define=API_BASE_URL=https://api.yourapp.com/v1
```

> **See `flutter-environments` skill** for the complete flavor/scheme setup,
> `.env` file management with `envied`, and CI/CD integration.

## AppException — Unified HTTP Error Type

```dart
// lib/core/network/app_exception.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_exception.freezed.dart';

/// Unified exception type produced by ErrorInterceptor.
/// RepositoryImpl maps these to domain Failures.
@freezed
sealed class AppException with _$AppException implements Exception {
  const factory AppException.network({String? message}) = NetworkException;
  const factory AppException.timeout({String? message}) = TimeoutException;
  const factory AppException.unauthorized({String? message}) = UnauthorizedException;
  const factory AppException.forbidden({String? message}) = ForbiddenException;
  const factory AppException.notFound({String? message}) = NotFoundException;
  const factory AppException.conflict({String? message}) = ConflictException;
  const factory AppException.unprocessable({
    String? message,
    Map<String, List<String>>? fieldErrors,
  }) = UnprocessableException;
  const factory AppException.server({String? message, int? statusCode}) = ServerException;
  const factory AppException.cancelled({String? message}) = CancelledException;
  const factory AppException.unknown({String? message, Object? error}) = UnknownException;
}
```
