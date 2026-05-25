---
name: flutter-test-coverage-strategy
description: >
  Defines and enforces the complete test coverage strategy for Flutter projects: coverage thresholds by layer, what to test, CI enforcement, and coverage reports. Use this skill when asking about test coverage, 'what should I test?', 'how much coverage do I need?', 'configure coverage report', 'coverage badge', lcov, genhtml, or when auditing test completeness. Also activated when a feature is complete and coverage needs to be validated. Stack: flutter_test, bloc_test 9.x, mocktail 1.x, integration_test, lcov. Dart 3.8+ / Flutter 3.32+.
commands:
  - check-coverage
inputs:
  - name: target
    description: Path to the feature directory or specific file to analyze coverage for (e.g. lib/features/product/). Use "all" to audit the entire project.
    required: true
  - name: threshold
    description: Minimum coverage percentage to enforce (default 80). Overrides the project-level default when provided.
    required: false
  - name: report
    description: Whether to generate an HTML coverage report (true/false, default false).
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.2"
---

# Test Coverage Strategy

## Coverage Targets by Layer

| Layer | Target | Justification |
|---|---|---|
| Domain — UseCases | **95%+** | Pure Dart logic, zero dependencies, highest ROI |
| Domain — Entities | **90%+** | Custom getters/methods, no state |
| Data — Mappers | **95%+** | Pure transformation, fully deterministic |
| Data — RepositoryImpl | **85%+** | Critical path, intensive mocks but straightforward |
| Data — DataSources | **80%+** | Thin wrappers, verify delegation |
| Presentation — BLoC | **85%+** | State machine, `bloc_test` makes it easy |
| Presentation — Pages | **70%+** | Widget tests covering all states + key interactions; pure layout-only widgets may be skipped |
| Core Utilities | **80%+** | High reuse, worth protecting |

**Project minimum threshold: 80%** (enforced in CI)

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

## What to Test by Layer

### Domain — UseCase

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

  final tProduct = Product(id: '1', name: 'Widget', price: 9.99, categoryId: 'c1');

  group('GetProductUseCase', () {
    test('delegates to repository with correct id', () async {
      when(() => mockRepo.getProduct(any())).thenAnswer((_) async => Right(tProduct));
      await sut(const GetProductParams(id: '1'));
      verify(() => mockRepo.getProduct('1')).called(1);
      verifyNoMoreInteractions(mockRepo);
    });

    test('returns Right(Product) on success', () async {
      when(() => mockRepo.getProduct(any())).thenAnswer((_) async => Right(tProduct));
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
        (_) async => const Left(Failure.notFound(message: 'Product not found')),
      );
      final result = await sut(const GetProductParams(id: 'missing'));
      expect(result.fold((f) => f, (_) => null), isA<NotFoundFailure>());
    });
  });
}
```

### Presentation — BLoC

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
    verify: (_) => verify(() => mockUseCase(const GetProductParams(id: '1'))).called(1),
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
}
```

---

## Coverage Reports

```bash
# Run with coverage
flutter test --coverage

# Filter generated files (critical — they inflate numbers)
lcov \
  --remove coverage/lcov.info \
  '*.freezed.dart' \
  '*.g.dart' \
  '*.gr.dart' \
  '*.config.dart' \
  '*/injection.dart' \
  -o coverage/lcov_filtered.info

# Generate HTML report
genhtml coverage/lcov_filtered.info \
  -o coverage/html \
  --title "App Coverage Report"

# Show summary
lcov --summary coverage/lcov_filtered.info

# Open in browser (macOS)
open coverage/html/index.html
```

---

## CI Enforcement (GitHub Actions)

```yaml
- name: Run tests with coverage
  run: flutter test --coverage --reporter=github --concurrency=4

- name: Filter generated files
  run: |
    sudo apt-get install -y lcov
    lcov --remove coverage/lcov.info \
      '*.freezed.dart' '*.g.dart' '*.gr.dart' '*.config.dart' \
      -o coverage/lcov_filtered.info

- name: Enforce 80% threshold
  run: |
    COVERAGE=$(lcov --summary coverage/lcov_filtered.info 2>&1 \
      | grep "lines" | awk '{print $2}' | tr -d '%')
    echo "Coverage: ${COVERAGE}%"
    if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      echo "❌ Coverage ${COVERAGE}% is below 80% minimum"
      exit 1
    fi
    echo "✅ Coverage ${COVERAGE}% meets threshold"
```

---

## Test File Naming Convention

Mirror the `lib/` structure exactly in `test/`:

```
lib/src/features/product/domain/use_cases/get_product_use_case.dart
test/features/product/domain/use_cases/get_product_use_case_test.dart

lib/src/features/product/data/repositories/product_repository_impl.dart
test/features/product/data/repositories/product_repository_impl_test.dart

lib/src/features/product/presentation/bloc/product_bloc.dart
test/features/product/presentation/bloc/product_bloc_test.dart
```

---

## Quick Wins Checklist

- [ ] Every UseCase has a test file covering happy path + all failure variants
- [ ] Every BLoC has `blocTest` covering all events and state transitions
- [ ] Every Mapper has tests for all field mappings including edge cases
- [ ] Every Page/View has widget tests covering all BLoC states + key user interactions (70%+ target)
- [ ] Generated files excluded from coverage (`*.freezed.dart`, `*.g.dart`)
- [ ] CI enforces 80% minimum threshold — fails the build if below
- [ ] `flutter test --concurrency=4` used in CI for speed
- [ ] `verifyNoMoreInteractions` used to catch unexpected calls
- [ ] `tearDown(() => bloc.close())` in every BLoC test

## Reference Files

- `references/mocktail_patterns.md` — Advanced mocktail patterns: matchers, captors, fakes, verification
- `references/widget_testing.md` — Widget tests with BlocMock, finders, golden tests
- `scripts/check_coverage.sh` — Script to verify coverage and generate HTML report
