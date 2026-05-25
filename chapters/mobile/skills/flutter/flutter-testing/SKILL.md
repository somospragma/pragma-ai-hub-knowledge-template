---
name: flutter-testing
description: >
  Defines how to write tests in Flutter- unit tests, widget tests, integration tests, golden tests, mutation tests, and native plugin testing. Use this skill when asking 'how do I test this?', 'how do I mock a dependency?', 'how do I write a BLoC test?', 'how do I test a widget?', 'how do I test a plugin?', or when implementing any test from scratch. For coverage thresholds, CI enforcement, and lcov reports, see flutter-test-coverage-strategy. Stack: flutter_test, bloc_test, mocktail, integration_test, fake_async.
commands:
  - flutter-test
inputs:
  - name: type
    description: Type of test to generate (unit, widget, integration, golden, mutation, native-plugin, all). Use "all" to generate tests for every layer when target is a feature directory.
    required: true
  - name: target
    description: Path to the class/file to test, or a full feature directory (e.g. lib/features/product/) to generate tests for all layers.
    required: true
  - name: feature
    description: Name of the module or feature the file belongs to (e.g. product, auth, cart).
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Flutter Testing

## Scope of This Skill

This skill covers **how to write tests**: patterns, examples, mocking, and tooling.
For **coverage thresholds, lcov reports, and CI enforcement**, see `flutter-test-coverage-strategy`.

---

## Test Stack (April 2026)

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  bloc_test: ^9.1.7
  mocktail: ^1.0.5
  fake_async: ^1.3.1
  network_image_mock: ^2.1.1
  leak_tracker_flutter_testing: ^3.0.0
```

---

## Testing Pyramid

```
        ▲  Integration Tests   (5–10%)   — full flows, real or staging backend
       ▲▲  Widget Tests        (20–30%)  — UI states, interactions, navigation
      ▲▲▲  Unit Tests          (60–70%)  — UseCases, Repos, Mappers, BLoCs
```

Golden tests and mutation tests are complementary — they do not replace the pyramid.

---

## Test Types Overview

| Type | What it validates | Speed | Reference |
|---|---|---|---|
| Unit | Isolated logic (UseCases, Repos, Mappers, BLoCs) | ⚡⚡⚡ | [unit-testing.md](references/unit-testing.md) |
| Widget | UI rendering, state transitions, interactions | ⚡⚡ | [widget-testing.md](references/widget-testing.md) |
| Integration | End-to-end user flows | 🐢 | [integration-testing.md](references/integration-testing.md) |
| Golden | Visual regression | ⚡⚡ | [golden-testing.md](references/golden-testing.md) |
| Mutation | Test effectiveness validation | 🐢🐢 | [mutation-testing.md](references/mutation-testing.md) |
| Native Plugins | MethodChannel / EventChannel isolation | ⚡⚡ | [native-plugins-testing.md](references/native-plugins-testing.md) |

---

## AAA Pattern

Every test follows Arrange → Act → Assert:

```dart
test('returns Right(product) when repository succeeds', () async {
  // Arrange
  when(() => mockRepo.getProduct(any()))
      .thenAnswer((_) async => Right(tProduct));

  // Act
  final result = await sut(const GetProductParams(id: '1'));

  // Assert
  expect(result, Right(tProduct));
  verify(() => mockRepo.getProduct('1')).called(1);
  verifyNoMoreInteractions(mockRepo);
});
```

---

## Unit Tests

### UseCase

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

### BLoC

```dart
// test/features/product/presentation/bloc/product_bloc_test.dart
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
    'emits [loading, error] when load fails',
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
}
```

### Mapper

```dart
group('ProductMapper', () {
  test('fromJson maps all fields correctly', () {
    final json = {'id': '1', 'name': 'Widget', 'price': 9.99};
    final result = ProductMapper.fromJson(json);

    expect(result.id, '1');
    expect(result.name, 'Widget');
    expect(result.price, 9.99);
  });

  test('toJson round-trips without data loss', () {
    final entity = Product(id: '1', name: 'Widget', price: 9.99);
    final json = ProductMapper.toJson(entity);
    final restored = ProductMapper.fromJson(json);

    expect(restored, entity);
  });

  test('fromJson throws on missing required field', () {
    expect(
      () => ProductMapper.fromJson({'name': 'Widget'}),
      throwsA(isA<ArgumentError>()),
    );
  });
});
```

---

## Widget Tests

```dart
// test/features/product/presentation/pages/product_page_test.dart
class MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

Widget buildSubject(ProductBloc bloc) => MaterialApp(
  home: BlocProvider<ProductBloc>.value(
    value: bloc,
    child: const ProductView(),
  ),
);

void main() {
  late MockProductBloc mockBloc;

  setUp(() => mockBloc = MockProductBloc());
  tearDown(() => mockBloc.close());

  group('ProductPage', () {
    testWidgets('shows loading indicator when state is loading', (tester) async {
      when(() => mockBloc.state).thenReturn(const ProductState.loading());

      await tester.pumpWidget(buildSubject(mockBloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows ProductCard when state is success', (tester) async {
      when(() => mockBloc.state)
          .thenReturn(ProductState.success(product: tProductVm));

      await tester.pumpWidget(buildSubject(mockBloc));

      expect(find.byType(ProductCard), findsOneWidget);
      expect(find.text('Widget'), findsOneWidget);
    });

    testWidgets('shows error and retry button when state is error', (tester) async {
      when(() => mockBloc.state).thenReturn(
        const ProductState.error(message: 'No connection'),
      );

      await tester.pumpWidget(buildSubject(mockBloc));

      expect(find.text('No connection'), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('dispatches loadRequested on retry tap', (tester) async {
      when(() => mockBloc.state).thenReturn(
        const ProductState.error(message: 'No connection'),
      );

      await tester.pumpWidget(buildSubject(mockBloc));
      await tester.tap(find.byType(TextButton));

      verify(() => mockBloc.add(const ProductEvent.loadRequested(id: '1')))
          .called(1);
    });
  });
}
```

### pump() vs pumpAndSettle()

| Situation | Use |
|---|---|
| Immediate `setState` / BLoC emit | `pump()` |
| Known animation duration | `pump(Duration(...))` |
| Unknown animation duration (dismiss, transitions) | `pumpAndSettle()` |
| Full app with ongoing timers | Never `pumpAndSettle()` — use `pump()` |

---

## Mocking

### Mocktail (default for all internal contracts)

```dart
// 1. Declare mock
class MockUserRepository extends Mock implements UserRepository {}

// 2. Register fallback for custom types
setUpAll(() => registerFallbackValue(const GetUserParams(id: '')));

// 3. Stub
when(() => mockRepo.getUser(any()))
    .thenAnswer((_) async => Right(tUser));

// 4. Verify
verify(() => mockRepo.getUser('1')).called(1);
verifyNoMoreInteractions(mockRepo);

// 5. Stub a stream
when(() => mockRepo.watchUsers())
    .thenAnswer((_) => Stream.fromIterable([[tUser]]));

// 6. Stub void method (no thenAnswer needed)
when(() => mockLogger.log(any())).thenReturn(null);
```

### Mockito (only for generated HTTP clients)

Use `@GenerateMocks` + `build_runner` when you need a type-safe mock of `http.Client`
or another third-party class that cannot be implemented manually. For all internal
interfaces, prefer mocktail.

---

## Test Fixtures

```dart
// test/fixtures/product_fixtures.dart
const tProduct = Product(id: '1', name: 'Widget', price: 9.99);

const tProductVm = ProductViewModel(
  id: '1',
  title: 'Widget',
  priceLabel: r'$9.99',
);

// Factory for parameterized tests
Product makeProduct({
  String id = '1',
  String name = 'Widget',
  double price = 9.99,
}) => Product(id: id, name: name, price: price);

// JSON fixture reader
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();
```

---

## File Naming Convention

Mirror `lib/` exactly in `test/`:

```
lib/src/features/product/domain/use_cases/get_product_use_case.dart
test/features/product/domain/use_cases/get_product_use_case_test.dart

lib/src/features/product/data/repositories/product_repository_impl.dart
test/features/product/data/repositories/product_repository_impl_test.dart

lib/src/features/product/presentation/bloc/product_bloc.dart
test/features/product/presentation/bloc/product_bloc_test.dart
```

---

## Useful Commands

```bash
# Run all tests
flutter test --concurrency=4

# Run a single file
flutter test test/features/product/domain/use_cases/get_product_use_case_test.dart

# Run by name pattern
flutter test --name "GetProductUseCase"

# Run with coverage (see flutter-test-coverage-strategy for thresholds)
flutter test --coverage --concurrency=4

# Run integration tests
flutter test integration_test/

# Run on a real device
flutter drive --target=integration_test/app_test.dart

# Update golden files
flutter test --update-goldens test/golden/
```

---

## Testing Checklist

- [ ] Every UseCase: happy path + all failure variants
- [ ] Every BLoC: all events → state sequences
- [ ] Every Mapper: all fields + round-trip + missing required field
- [ ] Every Page/View: all BLoC states + key user interactions
- [ ] Custom fallback values registered with `registerFallbackValue`
- [ ] `tearDown(() => bloc.close())` in every BLoC test
- [ ] `verifyNoMoreInteractions` on critical mocks
- [ ] Integration tests cover the top 3–5 critical user flows
- [ ] Golden tests for visually complex custom widgets

---

## Reference Files

- `references/unit-testing.md` — Unit tests: UseCases, Repos, DataSources, Mappers, BLoCs
- `references/widget-testing.md` — Widget tests: finders, interactions, BLoC mocking, navigation
- `references/integration-testing.md` — Integration tests: flows, IntegrationTestWidgetsFlutterBinding
- `references/golden-testing.md` — Golden tests: setup, update workflow, CI integration
- `references/mutation-testing.md` — Mutation testing: effectiveness validation, boundary tests
- `references/mocking.md` — Mocking patterns: mocktail advanced, fallbacks, streams, void methods
- `references/native-plugins-testing.md` — MethodChannel / EventChannel mocking, plugin isolation
