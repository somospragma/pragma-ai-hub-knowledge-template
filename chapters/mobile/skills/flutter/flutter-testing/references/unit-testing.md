# Unit Testing Reference

Unit tests validate isolated business logic without any framework or I/O dependencies.
They are the fastest and highest-ROI tests in the pyramid.

## Stack

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.1.7
  mocktail: ^1.0.5
  fake_async: ^1.3.1
```

## Folder Structure

```
test/
├── fixtures/
│   ├── product_fixtures.dart     # shared test data
│   └── fixture_reader.dart       # JSON file loader
├── features/
│   └── product/
│       ├── domain/
│       │   ├── use_cases/
│       │   │   └── get_product_use_case_test.dart
│       │   └── entities/
│       │       └── product_test.dart
│       ├── data/
│       │   ├── repositories/
│       │   │   └── product_repository_impl_test.dart
│       │   ├── data_sources/
│       │   │   └── product_remote_data_source_test.dart
│       │   └── mappers/
│       │       └── product_mapper_test.dart
│       └── presentation/
│           └── bloc/
│               └── product_bloc_test.dart
```

---

## Domain — UseCase

Test: happy path, every failure variant, edge cases on parameters.

```dart
// test/features/product/domain/use_cases/get_product_use_case_test.dart
class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late GetProductUseCase sut;
  late MockProductRepository mockRepo;

  setUpAll(() => registerFallbackValue(const GetProductParams(id: '')));

  setUp(() {
    mockRepo = MockProductRepository();
    sut = GetProductUseCase(mockRepo);
  });

  final tProduct = Product(id: '1', name: 'Widget', price: 9.99);

  group('GetProductUseCase', () {
    test('delegates to repository with correct id', () async {
      when(() => mockRepo.getProduct(any()))
          .thenAnswer((_) async => Right(tProduct));

      await sut(const GetProductParams(id: '1'));

      verify(() => mockRepo.getProduct('1')).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('returns Right(Product) on success', () async {
      when(() => mockRepo.getProduct(any()))
          .thenAnswer((_) async => Right(tProduct));

      expect(await sut(const GetProductParams(id: '1')), Right(tProduct));
    });

    test('propagates NetworkFailure', () async {
      when(() => mockRepo.getProduct(any())).thenAnswer(
        (_) async => const Left(Failure.network(message: 'No connection')),
      );

      final result = await sut(const GetProductParams(id: '1'));
      expect(result.fold((f) => f, (_) => null), isA<NetworkFailure>());
    });

    test('propagates NotFoundFailure', () async {
      when(() => mockRepo.getProduct(any())).thenAnswer(
        (_) async => const Left(Failure.notFound(message: 'Not found')),
      );

      final result = await sut(const GetProductParams(id: 'x'));
      expect(result.fold((f) => f, (_) => null), isA<NotFoundFailure>());
    });
  });
}
```

---

## Data — RepositoryImpl

Test: remote success + local cache, remote failure + local fallback, both fail.

```dart
class MockProductRemoteDataSource extends Mock
    implements ProductRemoteDataSource {}

class MockProductLocalDataSource extends Mock
    implements ProductLocalDataSource {}

void main() {
  late ProductRepositoryImpl sut;
  late MockProductRemoteDataSource mockRemote;
  late MockProductLocalDataSource mockLocal;

  setUp(() {
    mockRemote = MockProductRemoteDataSource();
    mockLocal = MockProductLocalDataSource();
    sut = ProductRepositoryImpl(
      remoteDataSource: mockRemote,
      localDataSource: mockLocal,
    );
  });

  group('getProduct', () {
    test('returns remote data and caches it on success', () async {
      when(() => mockRemote.getProduct('1'))
          .thenAnswer((_) async => tProductModel);
      when(() => mockLocal.cacheProduct(any()))
          .thenAnswer((_) async {});

      final result = await sut.getProduct('1');

      expect(result, Right(tProduct));
      verify(() => mockLocal.cacheProduct(tProductModel)).called(1);
    });

    test('returns cached data when remote fails', () async {
      when(() => mockRemote.getProduct('1')).thenThrow(ServerException());
      when(() => mockLocal.getProduct('1'))
          .thenAnswer((_) async => tProductModel);

      final result = await sut.getProduct('1');

      expect(result, Right(tProduct));
    });

    test('returns Failure when both remote and local fail', () async {
      when(() => mockRemote.getProduct('1')).thenThrow(ServerException());
      when(() => mockLocal.getProduct('1')).thenThrow(CacheException());

      final result = await sut.getProduct('1');

      expect(result.isLeft(), true);
    });
  });
}
```

---

## Data — Mapper

Test: all fields, edge cases, round-trip, missing required fields.

```dart
group('ProductMapper', () {
  test('fromJson maps all fields correctly', () {
    final json = {
      'id': '1',
      'name': 'Widget',
      'price': 9.99,
      'category_id': 'c1',
    };

    final result = ProductMapper.fromJson(json);

    expect(result.id, '1');
    expect(result.name, 'Widget');
    expect(result.price, 9.99);
    expect(result.categoryId, 'c1');
  });

  test('toJson round-trips without data loss', () {
    final entity = Product(id: '1', name: 'Widget', price: 9.99, categoryId: 'c1');
    final restored = ProductMapper.fromJson(ProductMapper.toJson(entity));

    expect(restored, entity);
  });

  test('fromJson trims whitespace from name', () {
    final json = {'id': '1', 'name': '  Widget  ', 'price': 9.99};
    expect(ProductMapper.fromJson(json).name, 'Widget');
  });

  test('fromJson throws on missing required id', () {
    expect(
      () => ProductMapper.fromJson({'name': 'Widget', 'price': 9.99}),
      throwsA(isA<ArgumentError>()),
    );
  });
});
```

---

## Presentation — BLoC

```dart
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
    verify: (_) =>
        verify(() => mockUseCase(const GetProductParams(id: '1'))).called(1),
  );

  blocTest<ProductBloc, ProductState>(
    'emits [loading, error] when load fails with NetworkFailure',
    build: () {
      when(() => mockUseCase(any())).thenAnswer(
        (_) async => const Left(Failure.network(message: 'No connection')),
      );
      return sut;
    },
    act: (b) => b.add(const ProductEvent.loadRequested(id: '1')),
    expect: () => [
      const ProductState.loading(),
      isA<ProductState>().having(
        (s) => s.mapOrNull(error: (e) => e.message),
        'error message',
        'No connection',
      ),
    ],
  );

  blocTest<ProductBloc, ProductState>(
    'does not emit when event has empty id',
    build: () => sut,
    act: (b) => b.add(const ProductEvent.loadRequested(id: '')),
    expect: () => [],
  );
}
```

---

## Test Fixtures

```dart
// test/fixtures/product_fixtures.dart
const tProduct = Product(id: '1', name: 'Widget', price: 9.99, categoryId: 'c1');

const tProductModel = ProductModel(
  id: '1',
  name: 'Widget',
  price: 9.99,
  categoryId: 'c1',
);

// Factory for parameterized tests
Product makeProduct({
  String id = '1',
  String name = 'Widget',
  double price = 9.99,
  String categoryId = 'c1',
}) => Product(id: id, name: name, price: price, categoryId: categoryId);

// JSON fixture reader
// test/fixtures/fixture_reader.dart
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();
```

---

## Testing Async Code

```dart
// Futures
test('completes async operation', () async {
  final result = await sut(const GetProductParams(id: '1'));
  expect(result.isRight(), true);
});

// Streams with expectLater
test('emits values in order', () {
  expect(
    mockRepo.watchProducts(),
    emitsInOrder([
      isA<List<Product>>().having((l) => l.length, 'length', 0),
      isA<List<Product>>().having((l) => l.length, 'length', 1),
    ]),
  );
});

// BLoC with wait (for debounce / timers)
blocTest<SearchBloc, SearchState>(
  'debounces search input',
  build: () => sut,
  act: (b) => b.add(const SearchEvent.queryChanged(query: 'wi')),
  wait: const Duration(milliseconds: 300),
  expect: () => [isA<SearchState>().having((s) => s.query, 'query', 'wi')],
);
```

---

## Rules

- One test file per production file, mirroring the `lib/` structure
- One test = one behaviour
- Tests must be independent and deterministic
- Use `setUp()` for shared initialization, `tearDown()` for cleanup
- Use `group()` to organize related tests
- Never call real network or database in unit tests
- Always `tearDown(() => bloc.close())` for BLoC tests
