---
name: flutter-dependency-injection-pattern
description: >
  Configures and wires dependency injection in Flutter using GetIt + Injectable. Use this skill when the user asks about DI, GetIt configuration, registering a service, 'how do I inject X?', 'wire my dependencies', 'add to DI', @injectable, @lazySingleton, @singleton, injection modules, or when adding any new class that must be resolved via getIt(). Also triggers when creating a new feature that requires DI registration. Stack: get_it, injectable, injectable_generator, build_runner. Dart 3.8+ / Flutter 3.32+.
commands:
  - setup-di
inputs:
  - name: action
    description: Action to perform (implement, register, audit). "implement" generates the full DI infrastructure (injection.dart, modules, environments), "register" adds a new class to the DI container with correct annotation, "audit" checks for unregistered classes, incorrect lifetimes, or direct instantiation bypassing GetIt.
    required: true
  - name: target
    description: Path to the DI directory or specific class to register (e.g. lib/core/di/ for implement, lib/features/product/data/repositories/product_repository_impl.dart for register).
    required: true
  - name: lifetime
    description: Registration lifetime when action is "register" (lazy-singleton, singleton, factory, cached-factory). Determines the annotation used.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# DI in Flutter — GetIt + Injectable

Canonical DI configuration. GetIt is the service locator; Injectable generates the wiring.

---

## Package Versions (April 2026)

```yaml
dependencies:
  get_it: ^9.2.1
  injectable: ^3.0.0

dev_dependencies:
  injectable_generator: ^3.0.2
  build_runner: ^2.15.0
```

---

## Central Configuration

```dart
// lib/src/core/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
  generateAccessors: true, // generates typed extension getters on GetIt (3.0.0+)
)
Future<void> configureDependencies({String env = Environment.prod}) async =>
    getIt.init(environment: env);
```

```dart
// main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  runApp(const App());
}
```

---

## Registration Annotations

| Annotation | Lifetime | Use for |
|---|---|---|
| `@lazySingleton` | Created on first access, single instance | Repositories, DataSources, ApiClient |
| `@singleton` | Created at startup, single instance | Config, Logger, Analytics |
| `@injectable` | New instance per resolution | BLoCs, UseCases |
| `@Injectable(cache: true)` | Cached factory — reuses instance until released | Flow controllers, temporary stateful services |
| `@preResolve` | Async singleton awaited before init | SharedPreferences, database initialization |
| `@module` | Abstract provider class | Third-party types without injectable constructors |
| `@ignoreParam` | Ignore an optional parameter in factory methods | Parameters injected manually at call site (3.0.0+) |

---

## Registration Pattern per Feature

```dart
// Repository (auto-detected by @LazySingleton(as:))
@LazySingleton(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  const ProductRepositoryImpl(this._remote, this._local);
  final ProductRemoteDataSource _remote;
  final ProductLocalDataSource _local;
}

// Data Sources
@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceImpl implements ProductRemoteDataSource {
  const ProductRemoteDataSourceImpl(this._apiClient);
  final ApiClient _apiClient;
}

@LazySingleton(as: ProductLocalDataSource)
class ProductLocalDataSourceImpl implements ProductLocalDataSource {
  const ProductLocalDataSourceImpl(this._cache);
  final CacheStore _cache;
}

// UseCase (factory — new instance per BLoC)
@injectable
class GetProductUseCase {
  const GetProductUseCase(this._repository);
  final ProductRepository _repository;
}

// BLoC (factory — new instance per screen)
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(this._getProduct) : super(const ProductState.initial()) { ... }
  final GetProductUseCase _getProduct;
}
```

---

## Core Infrastructure Modules

```dart
// lib/src/core/di/modules/network_module.dart
@module
abstract class NetworkModule {
  @lazySingleton
  Dio get dio => DioFactory.create(
    baseUrl: AppConfig.apiBaseUrl,
    interceptors: [getIt<AuthInterceptor>(), getIt<LoggingInterceptor>()],
  );

  @lazySingleton
  ApiClient get apiClient => ApiClient(getIt<Dio>());
}

// lib/src/core/di/modules/storage_module.dart
@module
abstract class StorageModule {
  @preResolve
  @lazySingleton
  Future<SharedPreferences> get prefs => SharedPreferences.getInstance();

  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
}
```

---

## Environments

```dart
// Mock for dev
@dev
@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceMock implements ProductRemoteDataSource {
  @override
  Future<ProductDto> getProduct(String id) async =>
      ProductDto(id: id, name: 'Mock Product', price: 9.99, categoryId: 'c1');
}

// Real for prod
@prod
@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceImpl implements ProductRemoteDataSource { ... }
```

### generateForEnvironments (3.0.0+)

Filter which environments trigger code generation — useful to exclude mock
classes from the prod binary entirely:

```dart
@InjectableInit(
  generateForEnvironments: [Environment.prod, Environment.dev],
)
```

---

## BLoC Resolution in the UI

```dart
// ✅ Always via getIt — never new ProductBloc(...)
BlocProvider(
  create: (_) => getIt<ProductBloc>()
    ..add(ProductEvent.loadRequested(id: productId)),
  child: const ProductView(),
)
```

---

## What's New in injectable 3.0.0 + get_it 9.x

### Dart 3.8 minimum

```yaml
environment:
  sdk: ">=3.8.0 <4.0.0"
```

### generateAccessors — typed GetIt extension getters

Eliminates `getIt<T>()` calls in favor of typed extension properties:

```dart
@InjectableInit(generateAccessors: true)
Future<void> configureDependencies(...) async => getIt.init(...);

// Generated extension (in injection.config.dart):
// extension GetItInjectableX on GetIt {
//   ProductBloc get productBloc => this<ProductBloc>();
//   ProductRepository get productRepository => this<ProductRepository>();
// }

// Usage — cleaner than getIt<ProductBloc>()
final bloc = getIt.productBloc;
```

### @ignoreParam — skip optional parameters

Use when a parameter should be injected manually at the call site, not by the container:

```dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(
    this._getProduct,
    @ignoreParam this.initialProductId, // ← not injected by GetIt
  ) : super(const ProductState.initial());

  final GetProductUseCase _getProduct;
  final String? initialProductId;
}

// Resolve with the manual parameter:
getIt<ProductBloc>(param1: 'abc-123');
```

### Cached Factories — flow-scoped instances

Combines factory with cache: the instance is reused until explicitly released.
Ideal for multi-step flows (checkout, onboarding) that need shared state:

```dart
@Injectable(cache: true)
class CheckoutFlowController {
  CheckoutFlowController(this._cartRepository);
  final CartRepository _cartRepository;
}

// Same instance throughout the flow:
final controller = getIt<CheckoutFlowController>();

// Release when the flow ends:
getIt.releaseInstance(controller);
```

### LIFO disposal order (get_it 9.0+)

Disposal always follows strict LIFO order based on `registrationNumber`.
The `strictDisposalOrder` parameter was removed from `reset()`, `resetScope()`,
`popScope()`, `popScopesTill()`, and `dropScope()`.

### DevTools Extension (get_it 9.1+)

Visualize and debug GetIt registrations from Dart DevTools:

```dart
// Enable in development (main_dev.dart, before configureDependencies)
void main() {
  GetIt.instance.debugEventsEnabled = true;
  configureDependencies();
  runApp(const App());
}
```

---

## After Changes

```bash
# Standard (build_runner):
dart run build_runner build --delete-conflicting-outputs

# Faster alternative (lean_builder — experimental):
dart run lean_builder build

# Verify the new class is registered:
grep "YourNewClass" lib/src/core/di/injection.config.dart
```

---

## Reference Files

- `references/module_patterns.md` — Module patterns: Firebase, Dio, SecureStorage, testing, scoped registration
- `assets/di_module_template.dart` — Ready-to-copy DI module template
