# DI Module Patterns

## Firebase Module

```dart
@module
abstract class FirebaseModule {
  @preResolve
  @singleton
  Future<FirebaseApp> get firebaseApp => Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  @lazySingleton
  FirebaseFirestore get firestore => FirebaseFirestore.instance;

  @lazySingleton
  FirebaseAuth get auth => FirebaseAuth.instance;

  @lazySingleton
  FirebaseStorage get storage => FirebaseStorage.instance;

  @lazySingleton
  FirebaseMessaging get messaging => FirebaseMessaging.instance;

  @lazySingleton
  FirebaseAnalytics get analytics => FirebaseAnalytics.instance;

  @lazySingleton
  FirebaseCrashlytics get crashlytics => FirebaseCrashlytics.instance;
}
```

---

## Dio Factory

```dart
class DioFactory {
  static Dio create({
    required String baseUrl,
    List<Interceptor>? interceptors,
    Duration connectTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
  }) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    if (interceptors != null) {
      dio.interceptors.addAll(interceptors);
    }

    return dio;
  }
}
```

---

## Testing — Reset GetIt

```dart
// test/helpers/di_test_helper.dart
Future<void> setupTestDependencies() async {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ProductRepository>()) {
    await getIt.reset();
  }

  getIt.registerLazySingleton<ProductRepository>(
    () => MockProductRepository(),
  );
  getIt.registerFactory<ProductBloc>(
    () => ProductBloc(getIt<GetProductUseCase>()),
  );
}

// In test setUp:
setUp(() async {
  await setupTestDependencies();
});

tearDown(() async {
  await GetIt.instance.reset();
});
```

---

## Scoped Registration (per user session)

```dart
// Register scoped dependencies after login
Future<void> onUserLoggedIn(User user) async {
  getIt.pushNewScope(scopeName: 'userSession');
  getIt.registerLazySingleton<UserSession>(() => UserSession(user));
}

// Clean up on logout
Future<void> onUserLoggedOut() async {
  await getIt.popScopesTill('userSession');
}
```

---

## @ignoreParam — Manual Parameter Injection

Use when a parameter must be provided at the call site, not resolved by the container.
Introduced in injectable 3.0.0.

```dart
@injectable
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(
    this._searchProducts,
    @ignoreParam this.initialQuery, // ← not injected by GetIt
  ) : super(const SearchState.initial());

  final SearchProductsUseCase _searchProducts;
  final String? initialQuery;
}

// Resolve with the manual parameter:
BlocProvider(
  create: (_) => getIt<SearchBloc>(param1: widget.query),
  child: const SearchView(),
)
```

---

## generateForEnvironments — Exclude Mocks from Prod

Filter which environments trigger code generation.
Prevents mock classes from being included in the prod binary.

```dart
@InjectableInit(
  generateForEnvironments: [Environment.prod, Environment.dev],
)
Future<void> configureDependencies({String env = Environment.prod}) async =>
    getIt.init(environment: env);
```

```dart
// This class is only generated for dev — never included in prod
@dev
@LazySingleton(as: AnalyticsService)
class MockAnalyticsService implements AnalyticsService {
  @override
  void logEvent(String name, Map<String, Object?> params) {
    debugPrint('[MockAnalytics] $name: $params');
  }
}
```
