# Dependency Registration — GetIt + Injectable

## Current Versions
- `get_it: ^9.2.1`
- `injectable: ^3.0.0`
- `injectable_generator: ^3.0.2`
- `build_runner: ^2.15.0`

## Module Pattern per Feature

Most features do NOT need an explicit `@module` — annotating the impl class with
`@LazySingleton(as: Repository)` is sufficient for auto-wiring.

```dart
// lib/features/product/data/di/product_module.dart
// Only needed when data sources have dependencies Injectable cannot auto-detect
// (e.g., named String parameters).
@module
abstract class ProductModule {
  // Example of manual wiring:
  // @lazySingleton
  // ProductRemoteDataSource get remoteDs => ProductRemoteDataSourceImpl(getIt());
}
```

## Lifetime Rules

| Class type | Annotation | Reason |
|---|---|---|
| Repository | `@LazySingleton(as: Repository)` | Shared, single instance |
| RemoteDataSourceImpl | `@LazySingleton(as: RemoteDataSource)` | Shared, stateless |
| LocalDataSourceImpl | `@LazySingleton(as: LocalDataSource)` | Shared, stateless |
| UseCase | `@injectable` | Factory — new instance per BLoC |
| BLoC | `@injectable` | Factory — new instance per screen |
| ApiClient | `@lazySingleton` | Shared, configured once |
| CacheStore | `@lazySingleton` | Shared, manages state |

## Core Injectable Configuration

```dart
// lib/core/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
  generateAccessors: true, // generates typed extension getters (injectable 3.0+)
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

// main_dev.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies(env: Environment.dev);
  runApp(const App());
}
```

## Core Infrastructure Modules

```dart
// lib/core/di/modules/network_module.dart
@module
abstract class NetworkModule {
  @lazySingleton
  Dio get dio {
    final dio = Dio(BaseOptions(
      baseUrl: const String.fromEnvironment('API_BASE_URL'),
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));
    dio.interceptors.addAll([
      getIt<AuthInterceptor>(),
      getIt<LoggingInterceptor>(),
      getIt<ErrorInterceptor>(),
    ]);
    return dio;
  }

  @lazySingleton
  ApiClient get apiClient => ApiClient(getIt<Dio>());
}

// lib/core/di/modules/storage_module.dart
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

  @lazySingleton
  CacheStore get cacheStore => HiveCacheStoreImpl();
}
```

## Resolving BLoC from the UI

```dart
// Always use getIt — never new MyBloc(...)
BlocProvider(
  create: (_) => getIt<ProductBloc>()
    ..add(ProductEvent.loadRequested(id: productId)),
  child: const ProductView(),
)

// Multiple BLoCs
MultiBlocProvider(
  providers: [
    BlocProvider(create: (_) => getIt<ProductBloc>()),
    BlocProvider(create: (_) => getIt<CartBloc>()),
  ],
  child: const CheckoutView(),
)
```

## Environment-Based Registration

```dart
// Mock for dev/test
@dev
@test
@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceMock implements ProductRemoteDataSource {
  @override
  Future<ProductModel> getProduct(String id) async =>
      ProductModel(id: id, name: 'Mock Product', price: 9.99, categoryId: 'c1');
}

// Real for prod
@prod
@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceImpl implements ProductRemoteDataSource { ... }
```

## After Adding Annotations

```bash
dart run build_runner build --delete-conflicting-outputs
# Verify:
grep "ProductRepository\|ProductBloc" lib/core/di/injection.config.dart
```

## Common Errors

| Error | Cause | Solution |
|---|---|---|
| `type not registered` | Missing annotation or not rebuilt | Add `@injectable`, run build_runner |
| Circular dependency | A→B→A | Introduce interface, break the cycle |
| `@preResolve` not working | Async singleton not awaited | Ensure `await configureDependencies()` |
| BLoC as singleton | Wrong annotation | Use `@injectable` (not `@lazySingleton`) for BLoCs |
