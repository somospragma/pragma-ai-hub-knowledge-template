# Advanced Mocktail Patterns

## Version: mocktail ^1.0.5

---

## Setup — registerFallbackValue

Required for any custom type used with `any()` or `captureAny()`.
Call in `setUpAll` — once per test file.

```dart
setUpAll(() {
  // Register all custom param types
  registerFallbackValue(const GetProductParams(id: ''));
  registerFallbackValue(const LoginParams(email: '', password: ''));
  registerFallbackValue(ProductDto(id: '', name: '', price: 0, categoryId: ''));
  registerFallbackValue(const CartItem(productId: '', quantity: 0));
});
```

---

## Argument Matchers

```dart
// Match any value
when(() => mockRepo.getProduct(any()))
    .thenAnswer((_) async => Right(tProduct));

// Match specific value
when(() => mockRepo.getProduct('1'))
    .thenAnswer((_) async => Right(tProduct));

// Named parameter
when(() => mockRepo.getProducts(categoryId: any(named: 'categoryId')))
    .thenAnswer((_) async => Right([]));

// Named parameter with specific value
when(() => mockRepo.getProducts(categoryId: 'electronics'))
    .thenAnswer((_) async => Right([tProduct]));

// Multiple parameters — mix any() and specific values
when(() => mockRepo.getProducts(
  categoryId: any(named: 'categoryId'),
  page: 1,
  limit: any(named: 'limit'),
)).thenAnswer((_) async => Right([]));
```

---

## Response Variants

```dart
// Async value
when(() => mockStorage.read(key: any(named: 'key')))
    .thenAnswer((_) async => 'token_value');

// Return null
when(() => mockCache.get(any()))
    .thenAnswer((_) async => null);

// Throw exception (DioException)
when(() => mockRemote.getProduct(any())).thenThrow(
  DioException(
    type: DioExceptionType.connectionError,
    requestOptions: RequestOptions(path: '/products/1'),
    error: const AppException.network(message: 'No connection'),
  ),
);

// Return void
when(() => mockCache.put(any(), any()))
    .thenAnswer((_) async {});

// Synchronous value (for non-async methods)
when(() => mockConfig.baseUrl)
    .thenReturn('https://api.example.com');

// Return different values on successive calls
var callCount = 0;
when(() => mockRepo.getProduct(any())).thenAnswer((_) async {
  callCount++;
  return callCount == 1
      ? const Left(Failure.network())
      : Right(tProduct);
});

// Throw on first call, succeed on second (retry testing)
when(() => mockRemote.getProduct(any()))
    .thenThrow(DioException(requestOptions: RequestOptions(path: '')))
    .thenAnswer((_) async => tDto);
```

---

## Verification

```dart
// Called exactly once
verify(() => mockRepo.getProduct('1')).called(1);

// Called N times
verify(() => mockAnalytics.logEvent(any())).called(3);

// Never called
verifyNever(() => mockRemote.getProduct(any()));

// No other interactions beyond what was verified
verifyNoMoreInteractions(mockRepo);

// Verify order of calls
verifyInOrder([
  () => mockLocal.getCachedProduct('1'),
  () => mockRemote.getProduct('1'),
  () => mockLocal.cacheProduct(tDto),
]);

// Verify with named parameters
verify(() => mockRepo.getProducts(
  categoryId: 'electronics',
  page: any(named: 'page'),
)).called(1);
```

---

## Argument Capture

```dart
// Capture a single argument
final captured = verify(
  () => mockAnalytics.logEvent(captureAny()),
).captured;
final eventName = captured.first as String;
expect(eventName, 'product_viewed');

// Capture named parameter
final captured = verify(
  () => mockRepo.getProducts(categoryId: captureAny(named: 'categoryId')),
).captured;
expect(captured.first, 'electronics');

// Capture complex object
final captured = verify(
  () => mockRemote.createOrder(captureAny()),
).captured;
final request = captured.first as CreateOrderRequest;
expect(request.items.length, 3);
expect(request.totalAmount, 29.97);
```

---

## Fake Implementations

Use fakes when mocks become too verbose or when you need stateful behavior.

```dart
// Stateful fake — better than a mock for token storage
class FakeTokenRepository implements TokenRepository {
  String? _accessToken;
  String? _refreshToken;

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    _accessToken = access;
    _refreshToken = refresh;
  }

  @override
  Future<String?> getAccessToken() async => _accessToken;

  @override
  Future<String?> getRefreshToken() async => _refreshToken;

  @override
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
  }

  @override
  Future<bool> hasValidToken() async => _accessToken != null;
}

// Usage in tests — no when() needed
setUp(() {
  fakeTokenRepo = FakeTokenRepository();
  sut = AuthBloc(fakeTokenRepo);
});

test('clears tokens on logout', () async {
  await fakeTokenRepo.saveTokens(access: 'token', refresh: 'refresh');
  sut.add(const AuthEvent.logoutRequested());
  await Future.delayed(Duration.zero);
  expect(await fakeTokenRepo.getAccessToken(), isNull);
});
```

---

## Mocking Streams

```dart
// Mock a stream that emits values
when(() => mockRepo.watchProducts(any()))
    .thenAnswer((_) => Stream.fromIterable([
      Right([tProduct]),
      Right([tProduct, tProduct2]),
    ]));

// Mock an empty stream
when(() => mockRepo.watchProducts(any()))
    .thenAnswer((_) => const Stream.empty());

// Mock a stream that emits an error
when(() => mockRepo.watchProducts(any()))
    .thenAnswer((_) => Stream.error(
      const Failure.network(message: 'Connection lost'),
    ));

// Mock a broadcast stream (for BLoC tests)
when(() => mockBloc.stream)
    .thenAnswer((_) => Stream.fromIterable([
      const ProductState.loading(),
      ProductState.success(product: tProduct),
    ]));
```

---

## Common Mistakes

```dart
// ❌ Forgetting registerFallbackValue for custom types
when(() => mockRepo.getProduct(any()))  // throws if GetProductParams not registered

// ✅ Always register in setUpAll
setUpAll(() => registerFallbackValue(const GetProductParams(id: '')));

// ❌ Verifying before the async operation completes
sut.add(event);
verify(() => mockUseCase(any())).called(1);  // may fail — async not done

// ✅ Wait for async operations
sut.add(event);
await Future.delayed(Duration.zero);  // or use blocTest which handles this
verify(() => mockUseCase(any())).called(1);

// ❌ Not closing BLoC in tearDown — memory leak
setUp(() => sut = ProductBloc(mockUseCase));
// missing tearDown

// ✅ Always close BLoC
tearDown(() => sut.close());
```
