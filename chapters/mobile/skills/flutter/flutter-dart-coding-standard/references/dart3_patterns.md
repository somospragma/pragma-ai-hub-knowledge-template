# Dart 3 Features — Patterns, Records, Sealed Classes, Null-Aware Elements

## Records (Dart 3.0+)

```dart
// Named record typedef
typedef UserInfo = ({String name, int age, String email});

// Return multiple values without a class
UserInfo getUserInfo() => (name: 'Alice', age: 30, email: 'alice@example.com');

// Destructuring
final (:name, :age, :email) = getUserInfo();
print('$name is $age years old');

// Positional records
(double lat, double lng) getLocation() => (48.8566, 2.3522);
final (lat, lng) = getLocation();
```

---

## Pattern Matching (Dart 3.0+)

```dart
// Switch expression (replaces ternary chains)
String describeFailure(Failure failure) => switch (failure) {
  NetworkFailure(:final message, :final statusCode) =>
    'Network ${statusCode ?? ''}: $message',
  ServerFailure(:final message, :final code) =>
    'Server $code: $message',
  CacheFailure(:final message) => 'Cache: $message',
  ValidationFailure(:final field, :final message) =>
    'Validation: $field — $message',
  UnknownFailure(:final message) => 'Unknown: $message',
};

// Pattern in if
if (result case Right(value: final user)) {
  // user is typed as User here
}

// List patterns
switch (path.split('/')) {
  case ['products', final id]: handleProduct(id);
  case ['categories', final id, 'products']: handleCategoryProducts(id);
  default: handleNotFound();
}

// Guard clause
switch (event) {
  case ProductEvent.loadRequested(:final id) when id.isNotEmpty:
    await _loadProduct(id, emit);
  case ProductEvent.loadRequested():
    emit(const ProductState.error(message: 'Invalid ID', code: 'INVALID'));
}
```

---

## Sealed Classes (Dart 3.0+)

```dart
// Without Freezed — use sealed for exhaustive pattern matching
sealed class Shape {
  const Shape();
}

final class Circle extends Shape {
  const Circle({required this.radius});
  final double radius;
}

final class Rectangle extends Shape {
  const Rectangle({required this.width, required this.height});
  final double width;
  final double height;
}

// Exhaustive switch — compiler error if a case is missing
double area(Shape shape) => switch (shape) {
  Circle(:final radius) => 3.14159 * radius * radius,
  Rectangle(:final width, :final height) => width * height,
};
```

**When to use `sealed` vs `@freezed`:**
- `sealed`: simple hierarchy, no JSON, no `copyWith` needed
- `@freezed`: need `fromJson`/`toJson`, `copyWith`, union types with many fields

---

## Class Modifiers (Dart 3.0+)

```dart
// base — can be extended but not implemented
base class BaseRepository {
  final ApiClient _client;
  const BaseRepository(this._client);
}

// abstract interface — can be implemented but not extended
abstract interface class PaymentGateway {
  Future<void> charge(double amount);
  Future<void> refund(String transactionId);
}

// final — cannot be extended or implemented
final class AppConfig {
  const AppConfig._();
  static const baseUrl = String.fromEnvironment('API_BASE_URL');
  static const timeout = Duration(seconds: 30);
}
```

---

## Extension Types (Dart 3.3+)

```dart
// Type-safe ID wrappers with zero runtime overhead
extension type ProductId(String value) implements String {
  factory ProductId.generate() => ProductId(const Uuid().v4());
  bool get isValid => value.isNotEmpty;
}

extension type Email(String value) implements String {
  static Email? tryParse(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (!trimmed.contains('@')) return null;
    return Email(trimmed);
  }
}

// Usage — compile-time type safety
Future<Product> getProduct(ProductId id) => ...
getProduct(ProductId('123'));  // ✅
getProduct('123');             // ❌ compile error
```

---

## Null-Aware Collection Elements (Dart 3.8+)

Skip null values in collections without `if` boilerplate.

```dart
// Lists — ?value is omitted if null
String? subtitle;
final items = [
  'Title',
  ?subtitle,   // omitted when null
  'Footer',
];
// items == ['Title', 'Footer'] when subtitle is null

// Maps — ?key or ?value omits the entire entry
String? authToken;
final headers = {
  'Content-Type': 'application/json',
  ?'Authorization': authToken != null ? 'Bearer $authToken' : null,
  // entry omitted entirely when authToken is null
};

// Practical example — building query parameters
String? search;
int? page;
final params = {
  'limit': '20',
  ?'search': search,
  ?'page': page?.toString(),
};

// Before Dart 3.8 (verbose)
final paramsBefore = {
  'limit': '20',
  if (search != null) 'search': search,
  if (page != null) 'page': page.toString(),
};
```

---

## strict_top_level_inference (Dart 3.8 / flutter_lints 6.0)

Requires explicit types on top-level declarations where the type is not
trivially obvious from the initializer.

```dart
// ❌ Triggers strict_top_level_inference
final logger = Logger();
final router = GoRouter(routes: [...]);

// ✅ Explicit type
final Logger logger = Logger();
final GoRouter router = GoRouter(routes: [...]);

// ✅ Fine — type trivially inferred from literal
const maxRetries = 3;
const baseUrl = 'https://api.example.com';
final items = <String>[];
```

---

## unnecessary_underscores (flutter_lints 6.0)

Warns when `_` is used as a parameter name when it could be omitted.

```dart
// ❌ Triggers unnecessary_underscores
list.forEach((_) => count++);
stream.listen((_) => refresh());

// ✅ Omit the unused parameter entirely
list.forEach((_) => count++);  // use _ only when needed for disambiguation

// ✅ Correct wildcard use — discarding one of multiple values
final (name, _) = getUserInfo();
final [first, ..._, last] = items;
```
