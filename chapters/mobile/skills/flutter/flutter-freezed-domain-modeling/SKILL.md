---
name: flutter-freezed-domain-modeling
description: >
  Models domain entities, value objects, sealed states, failures, and DTOs using Freezed in Flutter. Use this skill when creating or modifying domain entities, value objects, sealed states, union types, DTOs, or failure types. Triggers on 'create entity', 'model domain', 'add state', 'define failure', 'create DTO', 'how do I represent X in the domain?', the @freezed annotation, or any request to define data structures in the domain or data layers. Always apply to ensure correct Freezed patterns and proper layer separation (entities WITHOUT JSON; DTOs WITH JSON). Stack: Dart 3.8+, freezed, freezed_annotation, fpdart.
commands:
  - freezed-model-domain
inputs:
  - name: type
    description: Type of data structure to model (entity, value-object, failure, dto, state, event, view-model). Determines the layer, Freezed pattern, and whether JSON is included.
    required: true
  - name: target
    description: Path to the file or feature directory where the model will be created (e.g. lib/features/product/domain/entities/ or lib/features/product/data/models/).
    required: true
  - name: name
    description: Name of the class to generate (e.g. Product, UserDto, LoginState, NetworkFailure).
    required: true
  - name: fields
    description: Comma-separated list of fields with types (e.g. "id:String, name:String, price:double, imageUrl:String?"). Optional — if omitted, the skill will ask for fields interactively.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Domain Modeling with Freezed

Defines how each data structure is modeled per clean architecture layer.

---

## Layer → Type Decision Matrix

| Layer | Type | Freezed? | JSON? | Example |
|---|---|---|---|---|
| Domain | Entity | ✅ | ❌ Never | `User`, `Product`, `Order` |
| Domain | ValueObject | ✅ | ❌ | `Email`, `Money`, `ProductId` |
| Domain | Failure | ✅ sealed | ❌ | `NetworkFailure`, `ServerFailure` |
| Data | DTO | ✅ | ✅ Always | `UserDto`, `ProductDto` |
| Presentation | State | ✅ sealed | ❌ | `LoginState`, `ProductState` |
| Presentation | Event | ✅ sealed | ❌ | `LoginEvent`, `ProductEvent` |
| Presentation | ViewModel | ✅ | ❌ | `ProductViewModel`, `UserViewModel` |

**Critical rule:** Domain entities NEVER have `fromJson`/`toJson`. JSON serialization is the responsibility of the data layer.

---

## Domain Entity Pattern

```dart
// lib/src/features/product/domain/entities/product.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'product.freezed.dart';

@freezed
abstract class Product with _$Product {
  const Product._(); // required for custom getters

  const factory Product({
    required String id,
    required String name,
    required double price,
    required String categoryId,
    @Default(false) bool isAvailable,
    String? imageUrl,
    DateTime? updatedAt,
  }) = _Product;

  // Domain logic goes here — never in BLoC or UseCase
  bool get isOnSale => price < 50.0;
  bool get hasImage => imageUrl != null;
  String get displayPrice => '\$$price';
}
```

---

## ValueObject Pattern (Extension Types — Dart 3.3+)

```dart
// lib/src/features/auth/domain/value_objects/email.dart
extension type Email(String value) implements String {
  factory Email.parse(String raw) {
    final trimmed = raw.trim().toLowerCase();
    if (!_isValid(trimmed)) {
      throw const FormatException('Invalid email format');
    }
    return Email(trimmed);
  }

  static Email? tryParse(String raw) {
    try { return Email.parse(raw); } catch (_) { return null; }
  }

  static bool _isValid(String s) =>
      RegExp(r'^[\w.]+@[\w.]+\.\w{2,}$').hasMatch(s);
}

extension type Money(double value) {
  Money operator +(Money other) => Money(value + other.value);
  Money operator *(double factor) => Money(value * factor);
  String get formatted => '\$${value.toStringAsFixed(2)}';
}
```

---

## Sealed Failure Type

```dart
// lib/src/core/error/failure.dart
part 'failure.freezed.dart';

@freezed
sealed class Failure with _$Failure {
  const factory Failure.network({required String message, int? statusCode}) = NetworkFailure;
  const factory Failure.server({required String message, required String code}) = ServerFailure;
  const factory Failure.cache({required String message}) = CacheFailure;
  const factory Failure.validation({required String message, required String field}) = ValidationFailure;
  const factory Failure.unknown({required String message, Object? originalError}) = UnknownFailure;
}
```

---

## Either with fpdart — Failure Integration

```dart
// lib/src/core/typedefs/typedefs.dart
import 'package:fpdart/fpdart.dart';
import '../error/failure.dart';

/// Project-wide alias — all domain results use this type
typedef ResultFuture<T> = Future<Either<Failure, T>>;
typedef ResultStream<T> = Stream<Either<Failure, T>>;
```

```dart
// Repository interface (domain layer)
import 'package:fpdart/fpdart.dart';

abstract interface class ProductRepository {
  ResultFuture<Product> getById(String id);
  ResultFuture<List<Product>> getAll();
}
```

```dart
// Use case
import 'package:fpdart/fpdart.dart';

class GetProductUseCase {
  const GetProductUseCase(this._repository);
  final ProductRepository _repository;

  ResultFuture<Product> call(String id) => _repository.getById(id);
}
```

```dart
// Repository implementation (data layer)
import 'package:fpdart/fpdart.dart';

class ProductRepositoryImpl implements ProductRepository {
  const ProductRepositoryImpl(this._remoteDataSource);
  final ProductRemoteDataSource _remoteDataSource;

  @override
  ResultFuture<Product> getById(String id) async {
    try {
      final dto = await _remoteDataSource.getProduct(id);
      return Right(ProductMapper.fromDto(dto));
    } on DioException catch (e) {
      return Left(Failure.network(message: e.message ?? 'Network error'));
    } on Exception catch (e) {
      return Left(Failure.unknown(message: e.toString(), originalError: e));
    }
  }
}
```

```dart
// ✅ fpdart uses match() instead of fold() (dartz)
// Consuming Either in a BLoC event handler
Future<void> _onLoad(_LoadRequested event, Emitter<ProductState> emit) async {
  emit(const ProductState.loading());
  final result = await _getProductUseCase(event.id);
  emit(result.match(
    (failure) => ProductState.error(
      message: failure.toString(),
      code: failure.runtimeType.toString(),
    ),
    (product) => ProductState.success(product: ProductUiMapper.fromEntity(product)),
  ));
}
```

### dartz → fpdart migration summary

| dartz | fpdart 1.2.x | Notes |
|---|---|---|
| `import 'package:dartz/dartz.dart'` | `import 'package:fpdart/fpdart.dart'` | Single import |
| `Right(value)` | `Right(value)` | No change |
| `Left(failure)` | `Left(failure)` | No change |
| `.fold((l) => ..., (r) => ...)` | `.match((l) => ..., (r) => ...)` | **Main change** |
| `Option<T>` | `Option<T>` | Similar API |
| `Some(value)` / `None()` | `Some(value)` / `const None()` | No change |
| — | `TaskEither<L, R>` | Async composition with flatMap |

---

## BLoC Union State

```dart
// lib/src/features/product/presentation/bloc/product_state.dart
part 'product_state.freezed.dart';

@freezed
sealed class ProductState with _$ProductState {
  const factory ProductState.initial() = _Initial;
  const factory ProductState.loading() = _Loading;
  const factory ProductState.success({required ProductViewModel product}) = _Success;
  const factory ProductState.error({required String message, required String code}) = _Error;
}
```

```dart
// Usage — Dart 3 exhaustive switch expression
Widget build(BuildContext context) => switch (state) {
  ProductState.initial() => const SizedBox.shrink(),
  ProductState.loading() => const CircularProgressIndicator(),
  ProductState.success(:final product) => ProductCard(vm: product),
  ProductState.error(:final message) => ErrorWidget(message: message),
};
```

---

## DTO (Data Layer Only)

```dart
// lib/src/features/product/data/models/product_dto.dart
part 'product_dto.freezed.dart';
part 'product_dto.g.dart';

@freezed
abstract class ProductDto with _$ProductDto {
  const factory ProductDto({
    @JsonKey(name: 'product_id') required String id,
    required String name,
    required double price,
    @JsonKey(name: 'category_id') required String categoryId,
    @JsonKey(name: 'is_available') @Default(false) bool isAvailable,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'updated_at') String? updatedAt,
  }) = _ProductDto;

  factory ProductDto.fromJson(Map<String, dynamic> json) =>
      _$ProductDtoFromJson(json);
}
```

---

## Mapper Pattern

```dart
// lib/src/features/product/data/mappers/product_mapper.dart
abstract final class ProductMapper {
  static Product fromDto(ProductDto dto) => Product(
        id: dto.id,
        name: dto.name,
        price: dto.price,
        categoryId: dto.categoryId,
        isAvailable: dto.isAvailable,
        imageUrl: dto.imageUrl,
        updatedAt: dto.updatedAt != null
            ? DateTime.tryParse(dto.updatedAt!)
            : null,
      );

  static ProductDto toDto(Product entity) => ProductDto(
        id: entity.id,
        name: entity.name,
        price: entity.price,
        categoryId: entity.categoryId,
        isAvailable: entity.isAvailable,
        imageUrl: entity.imageUrl,
        updatedAt: entity.updatedAt?.toIso8601String(),
      );
}
```

---

## Reference Files

- `references/all_freezed_patterns.md` — Advanced patterns: generics, pagination, nested objects, custom JSON converters, discriminated unions, TaskEither with fpdart
