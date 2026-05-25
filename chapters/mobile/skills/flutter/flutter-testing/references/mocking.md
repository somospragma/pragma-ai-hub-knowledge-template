# Mocking Reference

Patterns for creating effective mocks with mocktail. For Mockito usage with generated
HTTP clients, see the note at the bottom.

## Stack

```yaml
dev_dependencies:
  mocktail: ^1.0.5
  bloc_test: ^9.1.7   # MockBloc / whenListen
```

---

## Fundamentals

### 1. Declare a mock

```dart
// Always mock the interface, never the implementation
class MockProductRepository extends Mock implements ProductRepository {}
class MockGetProductUseCase extends Mock implements GetProductUseCase {}
```

### 2. Register fallback values for custom types

Required when using `any()` with a custom type as a parameter.

```dart
setUpAll(() {
  registerFallbackValue(const GetProductParams(id: ''));
  registerFallbackValue(Product.empty());
});
```

### 3. Stub return values

```dart
// Future
when(() => mockRepo.getProduct(any()))
    .thenAnswer((_) async => Right(tProduct));

// Synchronous
when(() => mockRepo.isAvailable).thenReturn(true);

// Throw
when(() => mockRepo.getProduct(any()))
    .thenThrow(ServerException());

// Void method — use thenReturn(null) or just don't stub (mocktail returns null by default)
when(() => mockLogger.log(any())).thenReturn(null);
```

### 4. Verify calls

```dart
// Called exactly once with specific argument
verify(() => mockRepo.getProduct('1')).called(1);

// Called with any argument
verify(() => mockRepo.getProduct(any())).called(greaterThan(0));

// Never called
verifyNever(() => mockRepo.deleteProduct(any()));

// No further interactions after verified calls
verifyNoMoreInteractions(mockRepo);
```

---

## Argument Matchers

```dart
// Any value
when(() => mockRepo.getProduct(any())).thenAnswer(...);

// Named parameter
when(() => mockRepo.update(id: any(named: 'id'), name: 'Widget'))
    .thenAnswer(...);

// Custom predicate
when(() => mockRepo.getProduct(
  argThat(predicate<String>((s) => s.startsWith('prod-'))),
)).thenAnswer(...);
```

---

## Capturing Arguments

```dart
test('passes correct params to use case', () async {
  when(() => mockUseCase(any())).thenAnswer((_) async => Right(tProduct));

  await sut(const GetProductParams(id: '42'));

  final captured = verify(() => mockUseCase(captureAny())).captured;
  expect(captured.single, const GetProductParams(id: '42'));
});
```

---

## Streaming Behaviour

```dart
// Stub a stream
when(() => mockRepo.watchProducts())
    .thenAnswer((_) => Stream.fromIterable([[tProduct]]));

// BLoC: emit a sequence of states
whenListen(
  mockBloc,
  Stream.fromIterable([
    const ProductState.loading(),
    ProductState.success(product: tProductVm),
  ]),
  initialState: const ProductState.initial(),
);
```

---

## Conditional Behaviour

```dart
setUp(() {
  // Different response per argument
  when(() => mockRepo.getProduct('valid'))
      .thenAnswer((_) async => Right(tProduct));

  when(() => mockRepo.getProduct('missing'))
      .thenAnswer((_) async => const Left(Failure.notFound(message: 'Not found')));

  // Fallback for anything else
  when(() => mockRepo.getProduct(any()))
      .thenAnswer((_) async => Right(tProduct));
});
```

---

## Fakes (for complex stateful dependencies)

Use a fake when a mock would require too many stubs to be readable.

```dart
class FakeProductRepository implements ProductRepository {
  final List<Product> _products = [];
  bool shouldFail = false;

  @override
  Future<Either<Failure, Product>> getProduct(String id) async {
    if (shouldFail) return const Left(Failure.network(message: 'Error'));
    final product = _products.firstWhereOrNull((p) => p.id == id);
    if (product == null) return const Left(Failure.notFound(message: 'Not found'));
    return Right(product);
  }

  @override
  Future<Either<Failure, List<Product>>> getProducts() async {
    if (shouldFail) return const Left(Failure.network(message: 'Error'));
    return Right(_products);
  }

  void seed(List<Product> products) => _products
    ..clear()
    ..addAll(products);
}
```

---

## Reset Between Tests

```dart
tearDown(() {
  reset(mockRepo);           // Clear all stubs and interactions
  resetMocktailState();      // Clear all registered fallback values (use sparingly)
});
```

---

## MockBloc (bloc_test)

```dart
class MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

// In widget test
setUp(() {
  mockBloc = MockProductBloc();
  when(() => mockBloc.state).thenReturn(const ProductState.initial());
});

tearDown(() => mockBloc.close());
```

---

## Mockito (only for generated HTTP clients)

Use `@GenerateMocks` + `build_runner` only when you need a type-safe mock of
`http.Client` or another third-party class that cannot be manually implemented.

```yaml
dev_dependencies:
  mockito: ^5.4.4
  build_runner: ^2.14.1
```

```dart
@GenerateMocks([http.Client])
void main() { ... }
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

For all internal interfaces (`abstract interface class`), always use mocktail.

---

## Rules

- Mock the interface, never the concrete class
- Register fallback values for every custom type used with `any()`
- Prefer `verifyNoMoreInteractions` on critical mocks to catch unexpected calls
- Use fakes when a mock requires more than 3–4 stubs to be readable
- Never mock the class under test
- Never mock classes in the same layer you are testing
