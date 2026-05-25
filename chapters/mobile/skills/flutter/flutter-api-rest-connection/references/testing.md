# Testing — Mocking Dio, Interceptors, DataSource, Repository

## Mocking ApiClient with Mocktail

```dart
// test/helpers/mock_api_client.dart
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

// Register fallback values for Dio types
void registerFallbackValues() {
  registerFallbackValue(Options());
  registerFallbackValue(CancelToken());
}
```

---

## Testing RemoteDataSource

```dart
// test/features/product/data/data_sources/product_data_source_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

void main() {
  late MockApiClient mockClient;
  late ProductRemoteDataSourceImpl dataSource;

  setUp(() {
    registerFallbackValues();
    mockClient = MockApiClient();
    dataSource = ProductRemoteDataSourceImpl(mockClient);
  });

  group('ProductRemoteDataSource', () {
    test('getProduct returns ProductModel on success', () async {
      when(() => mockClient.get<Map<String, dynamic>>(
        '/products/p1',
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      )).thenAnswer((_) async => Response(
        data: {
          'id': 'p1',
          'name': 'Test Product',
          'price_in_cents': 999,
          'category_id': 'cat1',
          'is_available': true,
          'created_at': '2026-04-29T00:00:00.000Z',
        },
        statusCode: 200,
        requestOptions: RequestOptions(path: '/products/p1'),
      ));

      final result = await dataSource.getProduct('p1');

      expect(result.id, 'p1');
      expect(result.name, 'Test Product');
      expect(result.priceInCents, 999);
    });

    test('getProduct throws DioException on 404', () async {
      when(() => mockClient.get<Map<String, dynamic>>(
        '/products/missing',
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
        cancelToken: any(named: 'cancelToken'),
      )).thenThrow(DioException(
        type: DioExceptionType.badResponse,
        response: Response(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/products/missing'),
        ),
        requestOptions: RequestOptions(path: '/products/missing'),
        error: const AppException.notFound(message: 'Product not found'),
      ));

      expect(
        () => dataSource.getProduct('missing'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
```

---

## Testing RepositoryImpl

```dart
// test/features/product/data/repositories/product_repository_impl_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockProductRemoteDataSource extends Mock
    implements ProductRemoteDataSource {}

class MockProductLocalDataSource extends Mock
    implements ProductLocalDataSource {}

void main() {
  late MockProductRemoteDataSource mockRemote;
  late MockProductLocalDataSource mockLocal;
  late ProductRepositoryImpl repository;

  setUp(() {
    mockRemote = MockProductRemoteDataSource();
    mockLocal = MockProductLocalDataSource();
    repository = ProductRepositoryImpl(mockRemote, mockLocal);
  });

  group('ProductRepository.getProduct', () {
    final model = ProductModel(
      id: 'p1',
      name: 'Test',
      priceInCents: 999,
      categoryId: 'cat1',
      isAvailable: true,
      createdAt: DateTime(2026),
    );

    test('returns cached product without calling remote', () async {
      when(() => mockLocal.getCachedProduct('p1'))
          .thenAnswer((_) async => model);

      final result = await repository.getProduct(id: 'p1');

      expect(result.isRight(), true);
      expect(result.getOrElse((_) => throw Error()).id, 'p1');
      verifyNever(() => mockRemote.getProduct(any()));
    });

    test('fetches from remote on cache miss and caches result', () async {
      when(() => mockLocal.getCachedProduct('p1'))
          .thenAnswer((_) async => null);
      when(() => mockRemote.getProduct('p1'))
          .thenAnswer((_) async => model);
      when(() => mockLocal.cacheProduct(model))
          .thenAnswer((_) async {});

      final result = await repository.getProduct(id: 'p1');

      expect(result.isRight(), true);
      verify(() => mockLocal.cacheProduct(model)).called(1);
    });

    test('returns Failure.notFound on 404', () async {
      when(() => mockLocal.getCachedProduct('missing'))
          .thenAnswer((_) async => null);
      when(() => mockRemote.getProduct('missing')).thenThrow(
        DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/products/missing'),
          error: const AppException.notFound(message: 'Not found'),
        ),
      );

      final result = await repository.getProduct(id: 'missing');

      expect(result.isLeft(), true);
      result.fold(
        (f) => expect(f, isA<NotFoundFailure>()),
        (_) => fail('Expected failure'),
      );
    });

    test('returns Failure.network on connection error', () async {
      when(() => mockLocal.getCachedProduct('p1'))
          .thenAnswer((_) async => null);
      when(() => mockRemote.getProduct('p1')).thenThrow(
        DioException(
          type: DioExceptionType.connectionError,
          requestOptions: RequestOptions(path: '/products/p1'),
          error: const AppException.network(message: 'No internet'),
        ),
      );

      final result = await repository.getProduct(id: 'p1');

      expect(result.isLeft(), true);
      result.fold(
        (f) => expect(f, isA<NetworkFailure>()),
        (_) => fail('Expected failure'),
      );
    });
  });
}
```

---

## Testing AuthInterceptor

```dart
// test/core/network/interceptors/auth_interceptor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTokenRepository extends Mock implements TokenRepository {}

void main() {
  late MockTokenRepository mockTokenRepo;
  late AuthInterceptor interceptor;
  late Dio dio;

  setUp(() {
    mockTokenRepo = MockTokenRepository();
    interceptor = AuthInterceptor(mockTokenRepo);
    dio = Dio()..interceptors.add(interceptor);
  });

  group('AuthInterceptor', () {
    test('adds Authorization header when token exists', () async {
      when(() => mockTokenRepo.getAccessToken())
          .thenAnswer((_) async => 'test-token-123');

      final options = RequestOptions(path: '/test');
      final handler = RequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer test-token-123');
    });

    test('does not add Authorization header when no token', () async {
      when(() => mockTokenRepo.getAccessToken())
          .thenAnswer((_) async => null);

      final options = RequestOptions(path: '/test');
      final handler = RequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), false);
    });
  });
}
```

---

## Testing ErrorInterceptor

```dart
// test/core/network/interceptors/error_interceptor_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ErrorInterceptor interceptor;

  setUp(() => interceptor = ErrorInterceptor());

  group('ErrorInterceptor', () {
    DioException makeDioException({
      required int statusCode,
      Map<String, dynamic>? responseData,
    }) =>
        DioException(
          type: DioExceptionType.badResponse,
          requestOptions: RequestOptions(path: '/test'),
          response: Response(
            statusCode: statusCode,
            data: responseData,
            requestOptions: RequestOptions(path: '/test'),
          ),
        );

    test('maps 401 to UnauthorizedException', () {
      final err = makeDioException(statusCode: 401);
      final handler = ErrorInterceptorHandler();

      interceptor.onError(err, handler);

      expect(err.error, isA<UnauthorizedException>());
    });

    test('maps 404 to NotFoundException', () {
      final err = makeDioException(
        statusCode: 404,
        responseData: {'message': 'Resource not found'},
      );
      final handler = ErrorInterceptorHandler();

      interceptor.onError(err, handler);

      final exception = err.error as NotFoundException;
      expect(exception.message, 'Resource not found');
    });

    test('maps 422 to UnprocessableException with field errors', () {
      final err = makeDioException(
        statusCode: 422,
        responseData: {
          'message': 'Validation failed',
          'errors': {
            'email': ['Invalid email format'],
            'password': ['Too short', 'Must contain a number'],
          },
        },
      );
      final handler = ErrorInterceptorHandler();

      interceptor.onError(err, handler);

      final exception = err.error as UnprocessableException;
      expect(exception.fieldErrors?['email'], ['Invalid email format']);
      expect(exception.fieldErrors?['password']?.length, 2);
    });

    test('maps connection timeout to TimeoutException', () {
      final err = DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: '/test'),
      );
      final handler = ErrorInterceptorHandler();

      interceptor.onError(err, handler);

      expect(err.error, isA<TimeoutException>());
    });
  });
}
```
