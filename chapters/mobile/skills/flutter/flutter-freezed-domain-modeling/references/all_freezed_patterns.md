# All Freezed Patterns — Advanced Reference

## Paginated Response

```dart
@freezed
abstract class PaginatedDto<T> with _$PaginatedDto<T> {
  const factory PaginatedDto({
    required List<T> items,
    @JsonKey(name: 'total_count') required int totalCount,
    required int page,
    required int limit,
    @JsonKey(name: 'has_more') @Default(false) bool hasMore,
  }) = _PaginatedDto<T>;

  factory PaginatedDto.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$PaginatedDtoFromJson(json, fromJsonT);
}
```

---

## Nested Freezed Objects

```dart
@freezed
abstract class OrderDto with _$OrderDto {
  const factory OrderDto({
    required String id,
    required UserDto customer,
    required List<OrderItemDto> items,
    required AddressDto shippingAddress,
    @JsonKey(name: 'total_amount') required double totalAmount,
    @JsonKey(name: 'status') required String status,
  }) = _OrderDto;

  factory OrderDto.fromJson(Map<String, dynamic> json) =>
      _$OrderDtoFromJson(json);
}
```

---

## Custom JSON Converter

```dart
// Convert between int (API timestamp) and DateTime (Dart)
class TimestampConverter implements JsonConverter<DateTime, int> {
  const TimestampConverter();

  @override
  DateTime fromJson(int timestamp) =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);

  @override
  int toJson(DateTime date) => date.millisecondsSinceEpoch ~/ 1000;
}

@freezed
abstract class EventDto with _$EventDto {
  const factory EventDto({
    required String id,
    @TimestampConverter() required DateTime startTime,
    @TimestampConverter() required DateTime endTime,
  }) = _EventDto;

  factory EventDto.fromJson(Map<String, dynamic> json) =>
      _$EventDtoFromJson(json);
}
```

---

## Discriminated Union (Polymorphic JSON)

```dart
@freezed
sealed class NotificationDto with _$NotificationDto {
  @FreezedUnionValue('message')
  const factory NotificationDto.message({
    required String id,
    required String text,
    required String senderId,
  }) = MessageNotificationDto;

  @FreezedUnionValue('order_update')
  const factory NotificationDto.orderUpdate({
    required String id,
    required String orderId,
    required String newStatus,
  }) = OrderNotificationDto;

  factory NotificationDto.fromJson(Map<String, dynamic> json) =>
      _$NotificationDtoFromJson(json);
}
```

---

## ApiResponse Wrapper

```dart
@freezed
abstract class ApiResponse<T> with _$ApiResponse<T> {
  const factory ApiResponse({
    @JsonKey(name: 'status_code') required int statusCode,
    required String message,
    T? data,
    @JsonKey(name: 'error_code') String? errorCode,
    Map<String, dynamic>? meta,
  }) = _ApiResponse<T>;

  const ApiResponse._();

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$ApiResponseFromJson(json, fromJsonT);
}
```

---

## Freezed Equality

Freezed generates `==` and `hashCode` based on all fields by default.

```dart
@freezed
abstract class Point with _$Point {
  const factory Point({required double x, required double y}) = _Point;
}

final a = Point(x: 1, y: 2);
final b = Point(x: 1, y: 2);
print(a == b); // true — value equality

// Disable with @Freezed(equal: false):
@Freezed(equal: false)
abstract class UniqueEntity with _$UniqueEntity { ... }
```

---

## TaskEither — Async Composition with fpdart

`TaskEither` wraps a `Future<Either<L, R>>` and allows composing async
operations with `flatMap` without manually unwrapping each `Either`.

```dart
import 'package:fpdart/fpdart.dart';

// Wrap an async function that returns Either into a TaskEither
TaskEither<Failure, UserDto> fetchUser(String id) =>
    TaskEither(() => _remoteDataSource.getUser(id));

// Composition: fetch → map → validate — all chained
TaskEither<Failure, Product> getValidatedProduct(String id) =>
    TaskEither(() => _remoteDataSource.getProduct(id))
        .map(ProductMapper.fromDto)           // DTO → Entity
        .flatMap((product) => product.isAvailable
            ? TaskEither.right(product)
            : TaskEither.left(
                const Failure.validation(
                  message: 'Product not available',
                  field: 'isAvailable',
                ),
              ));

// Execute the TaskEither in a repository
@override
Future<Either<Failure, Product>> getById(String id) =>
    getValidatedProduct(id).run();
```

### TaskEither with tryCatch

```dart
// tryCatch converts exceptions into Left automatically
TaskEither<Failure, List<Product>> getAllProducts() =>
    TaskEither.tryCatch(
      () async {
        final response = await _remoteDataSource.getProducts();
        return response.map(ProductMapper.fromDto).toList();
      },
      (error, stackTrace) => Failure.unknown(
        message: error.toString(),
        originalError: error,
      ),
    );
```

### Chaining multiple independent operations

```dart
// Run two operations and combine their results
Future<Either<Failure, OrderSummary>> getOrderSummary(String orderId) =>
    TaskEither(() => _orderRepository.getById(orderId))
        .flatMap((order) =>
            TaskEither(() => _productRepository.getById(order.productId))
                .map((product) => OrderSummary(order: order, product: product)))
        .run();
```

---

## Either Pattern Matching with Freezed Failures (fpdart)

```dart
import 'package:fpdart/fpdart.dart';

// ✅ match() — replaces fold() from dartz
final result = await getProductUseCase(id);
final state = result.match(
  (failure) => switch (failure) {
    NetworkFailure(:final message)                    => ProductState.error(message: message, code: 'NETWORK'),
    ServerFailure(:final message, :final code)        => ProductState.error(message: message, code: code),
    ValidationFailure(:final message)                 => ProductState.error(message: message, code: 'VALIDATION'),
    CacheFailure(:final message)                      => ProductState.error(message: message, code: 'CACHE'),
    UnknownFailure(:final message)                    => ProductState.error(message: message, code: 'UNKNOWN'),
  },
  (product) => ProductState.success(product: ProductUiMapper.fromEntity(product)),
);

// ✅ getOrElse — default value if Left
final user = result.getOrElse((_) => User.empty());

// ✅ map / mapLeft — transform without unwrapping
final mapped = result
    .map((product) => product.displayPrice)
    .mapLeft((failure) => failure.message);

// ✅ isRight / isLeft — quick check
if (result.isRight()) {
  // success
}
```
