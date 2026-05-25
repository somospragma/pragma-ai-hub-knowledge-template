# Mutation Testing Reference

Mutation testing validates the **effectiveness** of your existing tests by introducing
small code changes (mutations) and checking whether your tests catch them.
High coverage does not guarantee effective tests — mutation testing does.

## The Core Problem

```dart
// Code under test
bool isAdult(int age) => age >= 18;

// Test with 100% line coverage but weak assertion
test('returns true for age 18', () {
  expect(isAdult(18), true); // passes even if >= is changed to >
});
```

A mutation of `>=` → `>` would survive this test. The test is not effective.

---

## Types of Mutations

### Arithmetic operators
`+` → `-`, `*` → `/`, `%` → `*`

### Relational operators
`>=` → `>`, `<` → `<=`, `==` → `!=`

### Logical operators
`&&` → `||`, `!` removed

### Boundary values
`18` → `17`, `18` → `19`

### Return values
`return Right(value)` → `return Left(failure)`

---

## Killing Mutations: Boundary Testing

The most effective technique is testing exact boundary values.

```dart
// Function with boundaries
String getGrade(int score) {
  if (score >= 90) return 'A';
  if (score >= 80) return 'B';
  if (score >= 70) return 'C';
  if (score >= 60) return 'D';
  return 'F';
}

// ❌ Weak — mutations survive
test('returns A for high score', () {
  expect(getGrade(95), 'A'); // >= 90 → > 90 still passes
});

// ✅ Strong — kills boundary mutations
group('getGrade', () {
  // Exact boundary values
  test('returns A for score 90', () => expect(getGrade(90), 'A'));
  test('returns B for score 89', () => expect(getGrade(89), 'B')); // kills >= 90 → > 90
  test('returns B for score 80', () => expect(getGrade(80), 'B'));
  test('returns C for score 79', () => expect(getGrade(79), 'C')); // kills >= 80 → > 80
  test('returns C for score 70', () => expect(getGrade(70), 'C'));
  test('returns D for score 69', () => expect(getGrade(69), 'D')); // kills >= 70 → > 70
  test('returns D for score 60', () => expect(getGrade(60), 'D'));
  test('returns F for score 59', () => expect(getGrade(59), 'F')); // kills >= 60 → > 60
  test('returns F for score 0',  () => expect(getGrade(0),  'F'));
});
```

---

## Killing Mutations: Exact Assertions

Vague assertions let mutations survive. Use exact expected values.

```dart
// ❌ Vague — mutations survive
test('applies discount', () {
  expect(calculateDiscount(100, 5), lessThan(100)); // any reduction passes
});

// ✅ Exact — kills arithmetic mutations
group('calculateDiscount', () {
  test('applies 5% for quantity < 5',  () => expect(calculateDiscount(100, 4), 95.0));
  test('applies 10% for quantity 5–9', () => expect(calculateDiscount(100, 5), 90.0));
  test('applies 10% for quantity 9',   () => expect(calculateDiscount(100, 9), 90.0));
  test('applies 15% for quantity 10+', () => expect(calculateDiscount(100, 10), 85.0));
  test('caps discount at 30%',         () => expect(calculateDiscount(100, 1000), 70.0));
  test('handles zero price',           () => expect(calculateDiscount(0, 10), 0.0));
});
```

---

## Killing Mutations: Either / fpdart

```dart
// ❌ Weak
test('returns a result', () async {
  final result = await sut(params);
  expect(result.isRight(), true); // Left with any value also passes if isRight is mutated
});

// ✅ Strong
test('returns Right(product) on success', () async {
  final result = await sut(params);
  expect(result, Right(tProduct)); // exact value — kills Right → Left mutation
});

test('returns Left(NetworkFailure) on network error', () async {
  final result = await sut(params);
  expect(result.fold((f) => f, (_) => null), isA<NetworkFailure>());
});
```

---

## Mutation Score Targets by Layer

| Layer | Target | Rationale |
|---|---|---|
| Domain — UseCases | **90%+** | Pure business logic, highest risk |
| Domain — Entities | **85%+** | Custom methods and computed properties |
| Data — Mappers | **90%+** | Deterministic transformations |
| Data — RepositoryImpl | **80%+** | Critical path |
| Presentation — BLoC | **75%+** | State transitions |

---

## Tooling

Dart does not have a mature mutation testing framework as of 2026.
The practical approach is **manual mutation analysis**:

1. Identify boundary conditions in the code under review
2. Write tests that cover `boundary - 1`, `boundary`, `boundary + 1`
3. Temporarily mutate the code (change `>=` to `>`, flip `&&` to `||`) and verify tests fail
4. Revert the mutation

For automated mutation testing, `mutation_test` (pub.dev) provides basic support:

```yaml
dev_dependencies:
  mutation_test: ^1.0.0
```

```bash
dart run mutation_test
```

---

## When to Apply Mutation Analysis

- After reaching 80%+ line coverage on a module
- Before releasing a critical feature (payments, auth, pricing)
- During a test quality audit
- When a bug escapes to production despite existing tests

---

## Rules

- Do not aim for 100% mutation score — it is impractical and not cost-effective
- Focus mutation analysis on domain logic and mappers first
- Use exact expected values in assertions, not just `isA<>` or `greaterThan`
- Always test both sides of every boundary condition
- Mutation testing complements coverage — it does not replace it
