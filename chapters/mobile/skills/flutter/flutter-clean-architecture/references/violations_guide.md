# Violations Guide — Before/After Fixes

Complete examples of architectural violations with corrections.
Each violation includes severity, detection command, and the fix.

---

## V1: Domain Model with JSON (CRITICAL)

**Why it's wrong:** Domain models must be pure business concepts. JSON parsing is
a data concern — it couples the domain to the API contract.

```dart
// ❌ VIOLATION — domain model with fromJson
class User {
  final String id;
  final String name;
  User({required this.id, required this.name});
  factory User.fromJson(Map<String, dynamic> json) =>
      User(id: json['user_id'], name: json['name']); // ← DATA CONCERN IN DOMAIN
}

// ✅ FIX — split into DomainModel (domain) + DataModel (data)

// domain/domain_models/user.dart
@freezed
class User with _$User {
  const factory User({required String id, required String name}) = _User;
  // NO fromJson — domain is JSON-agnostic
}

// data/data_models/user_model.dart
@freezed
class UserModel with _$UserModel {
  const factory UserModel({
    @JsonKey(name: 'user_id') required String id,
    required String name,
  }) = _UserModel;
  factory UserModel.fromJson(Map<String, dynamic> json) => _$UserModelFromJson(json);
}

// data/data_models/user_mapper.dart
abstract final class UserMapper {
  static User fromModel(UserModel model) => User(id: model.id, name: model.name);
}
```

**Detection:**
```bash
grep -rn "fromJson\|toJson" lib/*/domain/domain_models/
```

---

## V2: BLoC Calling DataSource Directly (HIGH)

**Why it's wrong:** The BLoC is in the Presentation layer. DataSources are in the
Data layer. Presentation must never import Data directly.

```dart
// ❌ VIOLATION — BLoC bypasses UseCase and Repository
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(this._remoteDataSource); // ← DATA SOURCE IN PRESENTATION
  final ProductRemoteDataSource _remoteDataSource;

  Future<void> _onLoad(LoadProductEvent event, Emitter<ProductState> emit) async {
    final model = await _remoteDataSource.getProduct(event.id); // ← WRONG
    emit(ProductState.success(product: ProductUIMapper.fromDataModel(model)));
  }
}

// ✅ FIX — BLoC only knows about UseCase
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(this._getProduct) : super(const ProductState.initial()) {
    on<LoadProductEvent>(_onLoad);
  }
  final GetProductUseCase _getProduct;

  Future<void> _onLoad(LoadProductEvent event, Emitter<ProductState> emit) async {
    emit(const ProductState.loading());
    final result = await _getProduct(GetProductParams(id: event.id));
    result.fold(
      (failure) => emit(ProductState.error(failure: failure)),
      (product) => emit(ProductState.success(
        product: ProductUIMapper.toUIModel(product),
      )),
    );
  }
}
```

**Detection:**
```bash
grep -rn "DataSource" lib/*/presentation/bloc/
```

---

## V3: Domain Importing Flutter (CRITICAL)

**Why it's wrong:** Domain must be pure Dart. Flutter imports make it impossible
to test domain logic without a Flutter environment and break portability.

```dart
// ❌ VIOLATION — domain entity importing Flutter
import 'package:flutter/material.dart'; // ← FLUTTER IN DOMAIN

class Product {
  final bool isAvailable;
  Color get statusColor => isAvailable ? Colors.green : Colors.red; // ← WRONG
}

// ✅ FIX — domain is color-agnostic; color is a presentation decision

// domain/domain_models/product.dart
@freezed
class Product with _$Product {
  const factory Product({
    required String id,
    required bool isAvailable,
  }) = _Product;
  // No Color, no Flutter
}

// presentation/ui_models/product_uimodel.dart
abstract final class ProductUIMapper {
  static Color statusColor(Product p) =>
      p.isAvailable ? Colors.green : Colors.red;
}
```

**Detection:**
```bash
grep -r "import 'package:flutter" lib/*/domain/
```

---

## V4: Presentation Importing DataModel (HIGH)

**Why it's wrong:** BLoC events and states must use domain types or primitives.
DataModels are a Data layer concern.

```dart
// ❌ VIOLATION — BLoC event containing DataModel
@freezed
class ProductEvent with _$ProductEvent {
  const factory ProductEvent.updated(ProductModel model) = _Updated; // ← DATA MODEL IN PRESENTATION
}

// ✅ FIX — events use domain models or primitive params only
@freezed
class ProductEvent with _$ProductEvent {
  const factory ProductEvent.updated(Product product) = _Updated; // domain model ✅
  // or with primitives:
  const factory ProductEvent.load({required String id}) = _Load;
}
```

**Detection:**
```bash
grep -rn "import.*data_models\|import.*_model\.dart" lib/*/presentation/
```

---

## V5: Throwing Instead of Returning Either (MEDIUM)

**Why it's wrong:** Throwing exceptions bypasses the explicit error handling that
`Either<Failure, T>` enforces. Callers can forget to handle errors.

```dart
// ❌ VIOLATION — repository throws exception
class ProductRepositoryImpl implements ProductRepository {
  @override
  Future<Product> getProduct(String id) async { // ← NO EITHER
    try {
      final model = await _remote.getProduct(id);
      return ProductMapper.fromDataModel(model);
    } catch (e) {
      throw Exception('Failed to get product'); // ← THROWS
    }
  }
}

// ✅ FIX — return Either, never throw from domain/data
class ProductRepositoryImpl implements ProductRepository {
  @override
  Future<Either<Failure, Product>> getProduct({required String id}) async {
    try {
      final cached = await _local.getCachedProduct(id);
      if (cached != null) return Right(ProductMapper.fromDataModel(cached));
      final model = await _remote.getProduct(id);
      await _local.cacheProduct(model);
      return Right(ProductMapper.fromDataModel(model));
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } on CacheException catch (e) {
      return Left(Failure.cache(message: e.message));
    } catch (e) {
      return Left(Failure.unexpected(error: e));
    }
  }
}
```

---

## V6: Multiple Use Cases in One File (LOW)

**Why it's wrong:** One file per use case makes it easy to find, test, and
understand each operation independently.

```dart
// ❌ VIOLATION — multiple use cases in same file
// product_use_cases.dart
@injectable
class GetProductUseCase { ... }
@injectable
class GetProductListUseCase { ... }   // ← SAME FILE
@injectable
class UpdateProductUseCase { ... }    // ← SAME FILE

// ✅ FIX — one file per use case
// usecases/get_product_usecase.dart       → GetProductUseCase
// usecases/get_product_list_usecase.dart  → GetProductListUseCase
// usecases/update_product_usecase.dart    → UpdateProductUseCase
```

---

## V7: Infrastructure in Presentation (HIGH)

**Why it's wrong:** `SharedPreferences`, `Hive`, `Drift` are infrastructure details.
They belong in the Data layer, accessed through a repository interface.

```dart
// ❌ VIOLATION — infrastructure in BLoC
@injectable
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(this._prefs); // ← SHARED PREFERENCES IN BLOC
  final SharedPreferences _prefs;

  Future<void> _onLoad(LoadSettingsEvent event, Emitter<SettingsState> emit) async {
    final isDark = _prefs.getBool('dark_mode'); // ← WRONG
    emit(SettingsState.loaded(isDarkMode: isDark ?? false));
  }
}

// ✅ FIX — go through domain layer
@injectable
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(this._getSettings) : super(const SettingsState.initial()) {
    on<LoadSettingsEvent>(_onLoad);
  }
  final GetSettingsUseCase _getSettings;

  Future<void> _onLoad(LoadSettingsEvent event, Emitter<SettingsState> emit) async {
    final result = await _getSettings();
    result.fold(
      (failure) => emit(SettingsState.error(failure: failure)),
      (settings) => emit(SettingsState.loaded(settings: settings)),
    );
  }
}
// Domain: SettingsRepository.getSettings() → Future<Either<Failure, Settings>>
// Data: SettingsLocalDataSourceImpl reads from SharedPreferences
```

---

## V8: Repository Interface Returning DataModel (HIGH)

**Why it's wrong:** The repository interface lives in the Domain layer. Returning
a DataModel would make Domain depend on Data — a direct violation of the dependency rule.

```dart
// ❌ VIOLATION — repository returns DataModel
abstract interface class ProductRepository {
  Future<ProductModel> getProduct(String id); // ← DATA MODEL IN DOMAIN INTERFACE
}

// ✅ FIX — repository returns DomainModel wrapped in Either
abstract interface class ProductRepository {
  Future<Either<Failure, Product>> getProduct({required String id});
}
```

**Detection:**
```bash
grep -rn "Model>" lib/*/domain/repositories/
```

---

## V9: UseCase with Multiple Responsibilities (MEDIUM)

**Why it's wrong:** A use case should do one thing. Multiple responsibilities
make it hard to test and violate the Single Responsibility Principle.

```dart
// ❌ VIOLATION — use case doing too much
@injectable
class ProductUseCase {
  Future<Either<Failure, Product>> getProduct(String id) async { ... }
  Future<Either<Failure, List<Product>>> getProducts() async { ... } // ← SECOND RESPONSIBILITY
  Future<Either<Failure, Unit>> updateProduct(Product p) async { ... } // ← THIRD
}

// ✅ FIX — one use case per operation
@injectable
class GetProductUseCase implements UseCase<Product, GetProductParams> { ... }

@injectable
class GetProductListUseCase implements UseCaseNoParams<List<Product>> { ... }

@injectable
class UpdateProductUseCase implements UseCase<Unit, UpdateProductParams> { ... }
```

---

## V10: abstract class Instead of abstract interface class (LOW)

**Why it's wrong:** In Dart 3+, `abstract interface class` explicitly signals
that the class is a pure interface contract — no implementation, no state.
Using `abstract class` allows adding implementation, which blurs the boundary.

```dart
// ❌ VIOLATION — using abstract class for a contract
abstract class ProductRepository {
  Future<Either<Failure, Product>> getProduct({required String id});
}

// ✅ FIX — use abstract interface class for pure contracts
abstract interface class ProductRepository {
  Future<Either<Failure, Product>> getProduct({required String id});
}
```

This applies to: Repository interfaces, DataSource interfaces, UseCase interfaces,
`ApiClient`, `CacheStore`, and any other pure contract.

**Detection:**
```bash
grep -rn "^abstract class" lib/*/domain/repositories/ lib/*/data/data_sources/ lib/core/
```
