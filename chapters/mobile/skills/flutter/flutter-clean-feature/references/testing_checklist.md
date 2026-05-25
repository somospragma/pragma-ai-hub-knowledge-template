# Test Checklist per Layer

## Dependencies (pubspec.yaml dev_dependencies)

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.1.7
  mocktail: ^1.0.5
  fake_async: ^1.3.1
  integration_test:
    sdk: flutter
```

## Layer 1: Domain — UseCase Tests

**File:** `test/features/product/domain/usecases/get_product_usecase_test.dart`

```dart
import 'package:fpdart/fpdart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late GetProductUseCase sut;
  late MockProductRepository mockRepository;

  setUpAll(() {
    registerFallbackValue(const GetProductParams(id: ''));
  });

  setUp(() {
    mockRepository = MockProductRepository();
    sut = GetProductUseCase(mockRepository);
  });

  final tProduct = Product(id: '1', name: 'Test', price: 9.99, categoryId: 'c1');

  group('GetProductUseCase', () {
    test('calls repository with the correct id', () async {
      when(() => mockRepository.getProduct(any()))
          .thenAnswer((_) async => Right(tProduct));

      await sut(const GetProductParams(id: '1'));

      verify(() => mockRepository.getProduct('1')).called(1);
      verifyNoMoreInteractions(mockRepository);
    });

    test('returns Right(Product) when repository succeeds', () async {
      when(() => mockRepository.getProduct(any()))
          .thenAnswer((_) async => Right(tProduct));

      final result = await sut(const GetProductParams(id: '1'));

      expect(result, Right(tProduct));
    });

    test('returns NetworkFailure on network error', () async {
      when(() => mockRepository.getProduct(any())).thenAnswer(
        (_) async => const Left(Failure.network(message: 'No connection')),
      );

      final result = await sut(const GetProductParams(id: '1'));

      expect(result.fold((f) => f, (_) => null), isA<NetworkFailure>());
    });
  });
}
```

## Layer 2: Data — Mapper Tests

```dart
// test/features/product/data/mappers/product_mapper_test.dart
void main() {
  group('ProductMapper', () {
    final tModel = ProductModel(
      id: '1', name: 'Widget', price: 4.99, categoryId: 'c1',
      isAvailable: true, updatedAt: '2024-01-01T00:00:00.000Z',
    );

    group('fromModel', () {
      test('maps all fields correctly', () {
        final result = ProductMapper.fromModel(tModel);
        expect(result.id, '1');
        expect(result.name, 'Widget');
        expect(result.price, 4.99);
        expect(result.isAvailable, true);
      });

      test('handles invalid date by returning null', () {
        final model = tModel.copyWith(updatedAt: 'not-a-date');
        expect(ProductMapper.fromModel(model).updatedAt, isNull);
      });
    });
  });
}
```

## Layer 2: Data — Repository Tests

```dart
class MockProductRemoteDataSource extends Mock implements ProductRemoteDataSource {}
class MockProductLocalDataSource extends Mock implements ProductLocalDataSource {}

void main() {
  late ProductRepositoryImpl sut;
  late MockProductRemoteDataSource mockRemote;
  late MockProductLocalDataSource mockLocal;

  setUp(() {
    mockRemote = MockProductRemoteDataSource();
    mockLocal = MockProductLocalDataSource();
    sut = ProductRepositoryImpl(mockRemote, mockLocal);
  });

  group('getProduct', () {
    test('returns cached entity without calling remote', () async {
      when(() => mockLocal.getCachedProduct(any())).thenAnswer((_) async => tModel);

      final result = await sut.getProduct('1');

      expect(result.isRight(), true);
      verifyNever(() => mockRemote.getProduct(any()));
    });

    test('fetches from remote and caches when no cache exists', () async {
      when(() => mockLocal.getCachedProduct(any())).thenAnswer((_) async => null);
      when(() => mockRemote.getProduct(any())).thenAnswer((_) async => tModel);
      when(() => mockLocal.cacheProduct(any())).thenAnswer((_) async {});

      await sut.getProduct('1');

      verify(() => mockLocal.cacheProduct(tModel)).called(1);
    });

    test('returns NetworkFailure on DioException', () async {
      when(() => mockLocal.getCachedProduct(any())).thenAnswer((_) async => null);
      when(() => mockRemote.getProduct(any())).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/products/1')),
      );

      final result = await sut.getProduct('1');

      expect(result.fold((f) => f, (_) => null), isA<NetworkFailure>());
    });
  });
}
```

## Layer 3: Presentation — BLoC Tests

```dart
import 'package:fpdart/fpdart.dart';

class MockGetProductUseCase extends Mock implements GetProductUseCase {}

void main() {
  late ProductBloc sut;
  late MockGetProductUseCase mockUseCase;

  setUpAll(() => registerFallbackValue(const GetProductParams(id: '')));

  setUp(() {
    mockUseCase = MockGetProductUseCase();
    sut = ProductBloc(mockUseCase);
  });

  tearDown(() => sut.close());

  test('initial state is ProductState.initial()', () {
    expect(sut.state, const ProductState.initial());
  });

  blocTest<ProductBloc, ProductState>(
    'emits [loading, success] when load succeeds',
    build: () {
      when(() => mockUseCase(any())).thenAnswer((_) async => Right(tProduct));
      return sut;
    },
    act: (b) => b.add(const ProductEvent.loadRequested(id: '1')),
    expect: () => [
      const ProductState.loading(),
      isA<ProductState>().having(
        (s) => s.mapOrNull(success: (s) => s.product.id),
        'product id',
        '1',
      ),
    ],
  );

  blocTest<ProductBloc, ProductState>(
    'emits [loading, error] on NetworkFailure',
    build: () {
      when(() => mockUseCase(any())).thenAnswer(
        (_) async => const Left(Failure.network(message: 'No internet')),
      );
      return sut;
    },
    act: (b) => b.add(const ProductEvent.loadRequested(id: '1')),
    expect: () => [
      const ProductState.loading(),
      isA<ProductState>().having(
        (s) => s.mapOrNull(error: (e) => e.message),
        'error message',
        'No internet',
      ),
    ],
  );
}
```

## Coverage Targets

| Layer | Target |
|---|---|
| Domain (UseCases, Entities) | 90%+ |
| Data (Repositories, Mappers) | 80%+ |
| Presentation (BLoCs) | 80%+ |
| Presentation (Pages) | 70%+ |

```bash
# Run with coverage
flutter test --coverage

# Filter generated files
lcov --remove coverage/lcov.info \
  '*.freezed.dart' '*.g.dart' '*.gr.dart' '*.config.dart' \
  -o coverage/filtered.info

lcov --summary coverage/filtered.info
```
