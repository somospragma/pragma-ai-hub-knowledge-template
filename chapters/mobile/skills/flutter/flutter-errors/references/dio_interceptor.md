# Dio Error Interceptor

`lib/core/network/dio_error_interceptor.dart`

---

## Complete Interceptor

```dart
import 'package:dio/dio.dart';
import 'package:your_app/core/error/exceptions.dart';

/// Converts Dio errors into AppException before they reach the datasource.
/// Register on the Dio instance: dio.interceptors.add(DioErrorInterceptor())
class DioErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final exception = _mapDioException(err);
    // Replace the error with our typed exception
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        response: err.response,
        type: err.type,
      ),
    );
  }

  AppException _mapDioException(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout    ||
    DioExceptionType.receiveTimeout => TimeoutException(cause: e),

    DioExceptionType.connectionError => NetworkException(cause: e),

    DioExceptionType.badResponse => _mapStatusCode(
      e.response?.statusCode ?? 0,
      e,
    ),

    DioExceptionType.cancel => NetworkException(
      message: 'Request cancelled',
      cause: e,
    ),

    _ => NetworkException(cause: e),
  };

  AppException _mapStatusCode(int code, DioException e) => switch (code) {
    401 => UnauthorizedException(cause: e),
    403 => UnauthorizedException(
        message: 'You do not have permission for this action',
        cause: e,
      ),
    404 => NotFoundException(cause: e),
    >= 500 => ServerException(
        statusCode: code,
        message: 'Server error ($code)',
        cause: e,
      ),
    _ => ServerException(
        statusCode: code,
        cause: e,
      ),
  };
}
```

---

## Dio Client Configuration

```dart
// lib/core/network/dio_client.dart

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dio_client.g.dart';

@riverpod
Dio dioClient(DioClientRef ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.addAll([
    DioErrorInterceptor(),
    AuthInterceptor(ref),          // Adds Bearer token
    if (kDebugMode) LogInterceptor( // Debug only
      requestBody: true,
      responseBody: true,
    ),
  ]);

  return dio;
}
```

---

## Datasource Using the Interceptor + TaskEither

```dart
// features/products/data/datasources/products_remote_datasource.dart

class ProductsRemoteDatasource {
  const ProductsRemoteDatasource({required Dio dio}) : _dio = dio;

  final Dio _dio;

  TaskEither<Failure, List<Product>> getProducts() =>
      TaskEither.tryCatch(
        () async {
          final response = await _dio.get<List<dynamic>>('/products');
          return (response.data ?? [])
              .map((e) => ProductDto.fromJson(e as Map<String, dynamic>))
              .map((dto) => dto.toDomain())
              .toList();
        },
        // The interceptor already converted DioException into AppException.
        // ErrorHandler.map handles both types.
        (error, stackTrace) => ErrorHandler.map(error, stackTrace),
      );

  TaskEither<Failure, Product> getProductById(String id) =>
      TaskEither.tryCatch(
        () async {
          final response = await _dio.get<Map<String, dynamic>>('/products/$id');
          return ProductDto.fromJson(response.data!).toDomain();
        },
        ErrorHandler.map,
      );

  TaskEither<Failure, Product> createProduct(CreateProductParams params) =>
      TaskEither.tryCatch(
        () async {
          final response = await _dio.post<Map<String, dynamic>>(
            '/products',
            data: params.toJson(),
          );
          return ProductDto.fromJson(response.data!).toDomain();
        },
        ErrorHandler.map,
      );
}
```

---

## Auth Interceptor (expired token handling + retry)

```dart
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref);
  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _ref.read(authTokenProvider);
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
    // Attempt refresh if the error is 401
    if (err.response?.statusCode == 401) {
      try {
        final newToken = await _ref.read(refreshTokenUseCaseProvider).call().run();
        newToken.fold(
          (_) => handler.next(err), // refresh failed — let the error through
          (token) async {
            // Retry the original request with the new token
            final opts = err.requestOptions;
            opts.headers['Authorization'] = 'Bearer $token';
            final response = await _ref.read(dioClientProvider).fetch(opts);
            handler.resolve(response);
          },
        );
      } catch (_) {
        handler.next(err);
      }
    } else {
      handler.next(err);
    }
  }
}
```
