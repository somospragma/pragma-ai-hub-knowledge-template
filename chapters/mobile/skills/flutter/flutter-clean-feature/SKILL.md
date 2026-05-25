---
name: flutter-clean-feature
description: >
  Implements a complete Flutter feature following Clean Architecture with BLoC + GetIt/Injectable. Use this skill when the user asks to 'create a feature', 'implement screen X', 'add a module', 'build flow Y', or any request involving coordinated files across the presentation, domain, and data layers. Also triggers when implementing a use case, repository, data source, BLoC, or page as part of a new or existing feature, creating a new Melos package for a feature, or adding a feature to an existing package in a monorepo. This is the master skill for feature development. Supports single-project and monorepo with Melos. Stack: Flutter 3.32+, Dart 3.8+, BLoC, GetIt, Injectable, Freezed, fpdart, go_router.
commands:
  - build-feature
inputs:
  - name: feature_name
    description: Name of the feature in snake_case (e.g. product_catalog, user_auth, checkout).
    required: true
  - name: target
    description: Path where the feature will be created (e.g. lib/features/product/ for app folder, packages/feature_product/ for Melos package).
    required: true
  - name: entity_name
    description: Primary domain entity name in PascalCase (e.g. Product, User, Order). Drives model, DTO, mapper, and BLoC naming.
    required: true
  - name: target_location
    description: Where to create the feature (app-folder, melos-package). "app-folder" creates inside the app's lib/, "melos-package" creates a standalone workspace package.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Flutter Clean Feature — Implementation Guide

Step-by-step guide for building a complete feature from entity to UI.
Architecture: **Presentation → Domain ← Data**, wired by the **Composition Root (GetIt)**.

---

## Architecture Map

> In a single project, features live in `lib/{feature}/`.
> In a monorepo, features can live in `lib/src/features/{feature}/` (inside the app)
> **or** as a standalone Melos package in `packages/feature_{name}/`.
> See [Monorepo — Feature as a Package](#monorepo--feature-as-a-package) for the decision guide.

```
{feature}/
├── presentation/
│   ├── ui_models/      {name}_uimodel.dart
│   ├── bloc/           {feature}_bloc|event|state.dart
│   ├── pages/          {feature}_page.dart
│   ├── organism/       {name}_organism.dart         ← Composed widgets for the feature
│   └── templates/
│       ├── {name}_template_mobile.dart
│       └── {name}_template_web.dart                 ← If cross-platform applies
├── domain/
│   ├── domain_models/  {name}.dart                  ← Freezed, no JSON
│   ├── usecases/       {name}_usecase.dart
│   └── repositories/   {feature}_repository.dart    ← Interface only
└── data/
    ├── data_sources/
    │   ├── remote/     {feature}_data_source.dart
    │   └── local/      {feature}_data_source.dart
    ├── data_models/    {name}_model.dart             ← Freezed + JSON
    └── repositories/   {feature}_repository_impl.dart
```

---

## Dependency Rules (never violate)

```
Presentation → Domain (entities, use cases, failures)
Data        → Domain (repository interfaces, entities, failures)
Domain      → NOTHING (pure Dart, zero Flutter imports, zero JSON)
GetIt       → EVERYTHING (single composition point)
```

---

## Implementation Steps

### Step 1 — Domain Model

```dart
// lib/{feature}/domain/domain_models/product.dart
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
  bool get isDiscounted => price < 100.0;
  bool get hasImage => imageUrl != null;
  String get displayPrice => '\$$price';
}
```

### Step 2 — Failure Type (core, shared across features)

```dart
// lib/src/core/error/failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';
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

### Step 3 — Repository Contract

```dart
// lib/{feature}/domain/repositories/product_repository.dart
import 'package:fpdart/fpdart.dart';
import '../../../../core/error/failure.dart';
import '../domain_models/product.dart';

abstract interface class ProductRepository {
  Future<Either<Failure, Product>> getProduct(String id);
  Future<Either<Failure, List<Product>>> getProducts({String? categoryId});
  Future<Either<Failure, void>> updateProduct(Product product);
}
```

### Step 4 — Use Case

```dart
// lib/{feature}/domain/usecases/get_product_usecase.dart
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../domain_models/product.dart';
import '../repositories/product_repository.dart';

class GetProductParams {
  const GetProductParams({required this.id});
  final String id;
}

@injectable
class GetProductUseCase implements UseCase<Product, GetProductParams> {
  const GetProductUseCase(this._repository);
  final ProductRepository _repository;

  @override
  Future<Either<Failure, Product>> call(GetProductParams params) =>
      _repository.getProduct(params.id);
}
```

### Step 5 — DataModel (Data layer only)

```dart
// lib/{feature}/data/data_models/product_model.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'product_model.freezed.dart';
part 'product_model.g.dart';

@freezed
abstract class ProductModel with _$ProductModel {
  const factory ProductModel({
    @JsonKey(name: 'product_id') required String id,
    required String name,
    required double price,
    @JsonKey(name: 'category_id') required String categoryId,
    @JsonKey(name: 'is_available') @Default(false) bool isAvailable,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'updated_at') String? updatedAt,
  }) = _ProductModel;

  factory ProductModel.fromJson(Map<String, dynamic> json) =>
      _$ProductModelFromJson(json);
}
```

### Step 6 — Mapper

```dart
// lib/{feature}/data/mappers/product_mapper.dart
import '../../domain/domain_models/product.dart';
import '../data_models/product_model.dart';

abstract final class ProductMapper {
  static Product fromModel(ProductModel model) => Product(
        id: model.id,
        name: model.name,
        price: model.price,
        categoryId: model.categoryId,
        isAvailable: model.isAvailable,
        imageUrl: model.imageUrl,
        updatedAt: model.updatedAt != null
            ? DateTime.tryParse(model.updatedAt!)
            : null,
      );

  static ProductModel toModel(Product entity) => ProductModel(
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

### Step 7 — Remote Data Source

```dart
// lib/{feature}/data/data_sources/remote/product_data_source.dart
import '../../data_models/product_model.dart';

abstract interface class ProductRemoteDataSource {
  Future<ProductModel> getProduct(String id);
  Future<List<ProductModel>> getProducts({String? categoryId});
  Future<void> updateProduct(ProductModel model);
}

@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceImpl implements ProductRemoteDataSource {
  const ProductRemoteDataSourceImpl(this._apiClient);
  final ApiClient _apiClient;

  @override
  Future<ProductModel> getProduct(String id) async {
    final response = await _apiClient.get('/products/$id');
    return ProductModel.fromJson(response.data as Map<String, dynamic>);
  }

  @override
  Future<List<ProductModel>> getProducts({String? categoryId}) async {
    final response = await _apiClient.get(
      '/products',
      queryParameters: categoryId != null ? {'category_id': categoryId} : null,
    );
    return (response.data as List<dynamic>)
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> updateProduct(ProductModel model) =>
      _apiClient.put('/products/${model.id}', data: model.toJson());
}
```

### Step 8 — Local Data Source

```dart
// lib/{feature}/data/data_sources/local/product_data_source.dart
abstract interface class ProductLocalDataSource {
  Future<ProductModel?> getCachedProduct(String id);
  Future<List<ProductModel>> getCachedProducts();
  Future<void> cacheProduct(ProductModel model);
  Future<void> cacheProducts(List<ProductModel> models);
  Future<void> clearCache();
}
```

### Step 9 — Repository Implementation

```dart
// lib/{feature}/data/repositories/product_repository_impl.dart
import 'package:fpdart/fpdart.dart';

@LazySingleton(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  const ProductRepositoryImpl(this._remote, this._local);
  final ProductRemoteDataSource _remote;
  final ProductLocalDataSource _local;

  @override
  Future<Either<Failure, Product>> getProduct(String id) async {
    try {
      final cached = await _local.getCachedProduct(id);
      if (cached != null) return Right(ProductMapper.fromModel(cached));

      final model = await _remote.getProduct(id);
      await _local.cacheProduct(model);
      return Right(ProductMapper.fromModel(model));
    } on DioException catch (e) {
      return Left(Failure.network(
        message: e.message ?? 'Network error',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return Left(Failure.unknown(message: e.toString(), originalError: e));
    }
  }
}
```

### Step 10 — BLoC (Event + State + BLoC)

```dart
// Event
@freezed
sealed class ProductEvent with _$ProductEvent {
  const factory ProductEvent.loadRequested({required String id}) = _LoadRequested;
  const factory ProductEvent.refreshRequested({required String id}) = _RefreshRequested;
}

// State
@freezed
sealed class ProductState with _$ProductState {
  const factory ProductState.initial() = _Initial;
  const factory ProductState.loading() = _Loading;
  const factory ProductState.success({required ProductUIModel product}) = _Success;
  const factory ProductState.error({required String message, required String code}) = _Error;
}

// BLoC
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(this._getProduct) : super(const ProductState.initial()) {
    on<_LoadRequested>(_onLoad, transformer: droppable());
    on<_RefreshRequested>(_onLoad, transformer: droppable());
  }

  final GetProductUseCase _getProduct;

  Future<void> _onLoad(
    _LoadRequested event,
    Emitter<ProductState> emit,
  ) async {
    emit(const ProductState.loading());
    final result = await _getProduct(GetProductParams(id: event.id));
    emit(result.match(
      (failure) => ProductState.error(
        message: switch (failure) {
          NetworkFailure(:final message) => message,
          ServerFailure(:final message) => message,
          CacheFailure(:final message) => message,
          ValidationFailure(:final message) => message,
          UnknownFailure() => 'An unexpected error occurred',
        },
        code: failure.runtimeType.toString(),
      ),
      (product) => ProductState.success(
        product: ProductUIModel.fromDomain(product),
      ),
    ));
  }
}
```

### Step 11 — UIModel

```dart
// lib/{feature}/presentation/ui_models/product_uimodel.dart
@freezed
abstract class ProductUIModel with _$ProductUIModel {
  const factory ProductUIModel({
    required String id,
    required String title,
    required String priceLabel,
    required bool showAvailabilityBadge,
    String? imageUrl,
  }) = _ProductUIModel;

  /// Converts a DomainModel to a UIModel ready for the view
  factory ProductUIModel.fromDomain(Product entity) => ProductUIModel(
        id: entity.id,
        title: entity.name,
        priceLabel: '\$${entity.price.toStringAsFixed(2)}',
        showAvailabilityBadge: !entity.isAvailable,
        imageUrl: entity.imageUrl,
      );
}
```

### Step 12 — Page

```dart
// lib/{feature}/presentation/pages/product_page.dart
class ProductPage extends StatelessWidget {
  const ProductPage({required this.productId, super.key});
  final String productId;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<ProductBloc>()
          ..add(ProductEvent.loadRequested(id: productId)),
        child: const _ProductView(),
      );
}
```

---

## Monorepo — Feature as a Package

In a Melos monorepo, a feature can live in two places. Choose based on scope:

| Where | When |
|---|---|
| `apps/{app}/lib/src/features/{feature}/` | Feature is **exclusive to one app** — no sharing needed |
| `packages/feature_{name}/` | Feature is **shared across 2+ apps**, or is large enough to own its own versioning, tests, and CI |

### Decision: folder vs package

```
Is this feature used by more than one app?          → package
Will it be developed by a separate team/squad?      → package
Does it have its own release cadence?               → package
Is it a bounded domain (auth, payments, catalog)?   → package
Otherwise                                           → folder inside the app
```

### Creating a new Melos package for a feature

```bash
# 1. Create the package folder
mkdir -p packages/feature_product/lib

# 2. Create pubspec.yaml
cat > packages/feature_product/pubspec.yaml << 'EOF'
name: feature_product
description: Product catalog feature — domain, data, and presentation layers.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.8.0 <4.0.0"
  flutter: ">=3.32.0"

resolution: workspace   # ← required in Melos 7.x

dependencies:
  flutter:
    sdk: flutter
  # Local workspace packages — use `any`, workspace resolves them
  core: any
  # State management
  flutter_bloc: ^9.1.1
  bloc_concurrency: ^0.3.0
  # DI
  get_it: ^9.2.1
  injectable: ^3.0.0
  # Models
  freezed_annotation: ^3.1.0
  json_annotation: ^4.11.0
  fpdart: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.15.0
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
  json_serializable: ^6.13.1
  bloc_test: ^9.1.7
  mocktail: ^1.0.5
EOF

# 3. Add to workspace list in root pubspec.yaml, then resolve
dart pub get
```

### Adding the package to melos.yaml

```yaml
# pubspec.yaml (project root) — workspace list
# Add the new package to the workspace: list
workspace:
  - apps/app_mobile
  - packages/core
  - packages/ui_system
  - packages/feature_auth
  - packages/feature_catalog
  - packages/feature_product    # ← add this line

# melos scripts stay under the melos: key
melos:
  scripts:
    analyze:
      run: melos exec -- "flutter analyze --no-pub"
    test:
      run: melos exec -- "flutter test --coverage"
    build_runner:
      run: melos exec -- "dart run build_runner build --delete-conflicting-outputs"
    # Run only on a specific package
    test:product:
      run: melos exec --scope=feature_product -- "flutter test --coverage"
```

### Package structure

```
packages/feature_product/
├── lib/
│   ├── feature_product.dart          ← Public barrel export
│   ├── src/
│   │   ├── presentation/
│   │   │   ├── ui_models/
│   │   │   ├── bloc/
│   │   │   ├── pages/
│   │   │   └── organism/
│   │   ├── domain/
│   │   │   ├── domain_models/
│   │   │   ├── usecases/
│   │   │   └── repositories/
│   │   └── data/
│   │       ├── data_sources/
│   │       ├── data_models/
│   │       └── repositories/
├── test/
└── pubspec.yaml
```

### Barrel export — control the public API

```dart
// packages/feature_product/lib/feature_product.dart
// Only export what the app needs — keep internals private

// Pages (needed by the app router)
export 'src/presentation/pages/product_page.dart';
export 'src/presentation/pages/product_list_page.dart';

// BLoC (needed by the app if it provides it at a higher level)
export 'src/presentation/bloc/product_bloc.dart';
export 'src/presentation/bloc/product_event.dart';
export 'src/presentation/bloc/product_state.dart';

// DI module (needed by the app's injection container)
export 'src/di/product_module.dart';

// Do NOT export: data_models, data_sources, mappers, repository impls
// Those are internal implementation details
```

### DI wiring when the feature is a package

The app's injection container imports the feature's `@module` and registers it:

```dart
// apps/my_app/lib/injection_container.dart
import 'package:feature_product/feature_product.dart'; // imports ProductModule

@InjectableInit(
  externalPackageModulesAfter: [
    ExternalModule(ProductPackageModule),  // registers feature's DI
  ],
)
Future<void> configureDependencies() async => getIt.init();
```

```dart
// packages/feature_product/lib/src/di/product_module.dart
import 'package:injectable/injectable.dart';

// Marks this as an external module for the app's injection container
@module
abstract class ProductPackageModule {
  // Injectable auto-detects @LazySingleton / @injectable annotations
  // in this package — no manual registration needed here
}
```

> **Rule:** The feature package registers its own dependencies via `@LazySingleton(as:)`
> and `@injectable` annotations. The app only needs to declare `ExternalModule(ProductPackageModule)`
> in its `@InjectableInit`. Injectable 3.0 handles the rest.

### Import paths in the app

```dart
// ✅ When feature is a package — use the package import
import 'package:feature_product/feature_product.dart';

// ✅ When feature is a folder inside the app — use the app package import
import 'package:my_app/features/product/presentation/pages/product_page.dart';

// ❌ Never use relative imports across package boundaries
import '../../../packages/feature_product/lib/src/...'; // FORBIDDEN
```

### Adding a feature to an existing package

If the feature belongs to an existing domain package (e.g., `packages/feature_catalog`
already exists and you're adding a `product_detail` sub-feature):

```
packages/feature_catalog/
├── lib/
│   ├── feature_catalog.dart          ← Add new exports here
│   └── src/
│       ├── product_list/             ← Existing feature
│       └── product_detail/           ← New sub-feature — same structure
│           ├── presentation/
│           ├── domain/
│           └── data/
```

```bash
# Run build_runner only on the affected package
melos exec --scope=feature_catalog -- \
  "dart run build_runner build --delete-conflicting-outputs"

# Run tests only on the affected package
melos exec --scope=feature_catalog -- "flutter test --coverage"
```

---

## Post-Implementation Checklist

```
□ All Freezed files have part directives
□ Run: dart run build_runner build --delete-conflicting-outputs
□   (monorepo: melos exec --scope={package} -- "dart run build_runner build --delete-conflicting-outputs")
□ Register in DI → see references/di_registration.md
□ Register route in GoRouter → see references/routing.md
□ Write tests → see references/testing_checklist.md
□ Run: flutter analyze (zero warnings)
□   (monorepo: melos exec --scope={package} -- "flutter analyze --no-pub")
□ Run: flutter test
□   (monorepo: melos exec --scope={package} -- "flutter test --coverage")

Monorepo only:
□ New package added to melos.yaml packages glob (if applicable)
□ melos bootstrap run after adding new package
□ Barrel export (lib/{package}.dart) updated with new public API
□ App's injection_container.dart declares ExternalModule if new package
□ App's pubspec.yaml declares the new package as a path dependency
```

---

## Reference Files (read as needed)

- `references/di_registration.md` — GetIt + Injectable module configuration for this feature
- `references/routing.md` — GoRouter registration, redirect guards, deep links
- `references/testing_checklist.md` — Complete test suite per layer with examples
- `references/core_abstractions.md` — UseCase base, CacheStore, ApiClient contracts
- `references/patterns_advanced.md` — Pagination, search, real-time streams, optimistic updates
- `assets/feature_checklist.md` — PR checklist template
