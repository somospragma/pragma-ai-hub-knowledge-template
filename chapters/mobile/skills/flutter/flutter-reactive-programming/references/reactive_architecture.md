# Reactive Architecture — Unidirectional Data Flow

The reactive architecture principle: **data flows down, events flow up**.
The UI never fetches data — it subscribes to streams and reacts to changes.

---

## The Full Reactive Stack

```
┌─────────────────────────────────────────────────────────────┐
│  Widget                                                      │
│  • Renders state                                             │
│  • Dispatches events UP (add, notifier.method, ref.read)    │
├─────────────────────────────────────────────────────────────┤
│  State (BLoC State / AsyncValue / ValueNotifier)            │
│  • Immutable snapshot of what the UI should show            │
├─────────────────────────────────────────────────────────────┤
│  BLoC / Notifier                                            │
│  • Maps domain stream events → UI state                     │
│  • Handles user events → calls use cases                    │
├─────────────────────────────────────────────────────────────┤
│  UseCase                                                     │
│  • Orchestrates domain logic                                 │
│  • Returns Stream<Either<Failure, T>> or Future             │
├─────────────────────────────────────────────────────────────┤
│  Repository (abstract interface class)                       │
│  • watch*() → Stream (reactive)                             │
│  • get*() → Future (one-shot)                               │
│  • save/delete → Future (command)                           │
├─────────────────────────────────────────────────────────────┤
│  Data Source (Drift DAO / ObjectBox / WebSocket / REST)     │
│  • Emits raw data changes                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Reactive Repository Design

Every repository should expose both reactive (watch) and imperative (get/save) APIs.

```dart
// lib/features/product/domain/repositories/product_repository.dart
import 'package:fpdart/fpdart.dart';

abstract interface class ProductRepository {
  // ── Reactive (push) ───────────────────────────────────────────────────
  /// Emits whenever the product list changes (DB write, sync, etc.)
  Stream<Either<Failure, List<Product>>> watchProducts({
    required String categoryId,
  });

  /// Emits whenever a specific product changes
  Stream<Either<Failure, Product>> watchProduct(String id);

  // ── One-shot (pull) ───────────────────────────────────────────────────
  Future<Either<Failure, List<Product>>> getProducts({
    required String categoryId,
    int page = 0,
    int pageSize = 20,
  });

  Future<Either<Failure, Product>> getProduct(String id);

  // ── Commands ──────────────────────────────────────────────────────────
  Future<Either<Failure, Unit>> saveProduct(Product product);
  Future<Either<Failure, Unit>> deleteProduct(String id);
}
```

### Repository implementation — Drift reactive stream

```dart
// lib/features/product/data/repositories/product_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  final ProductDao _dao;
  final ProductRemoteDataSource _remote;
  final ProductMapper _mapper;

  ProductRepositoryImpl(this._dao, this._remote, this._mapper);

  @override
  Stream<Either<Failure, List<Product>>> watchProducts({
    required String categoryId,
  }) {
    // Drift DAO returns a Stream — emits on every DB change automatically
    return _dao
        .watchByCategory(categoryId)
        .map((rows) => Right<Failure, List<Product>>(
              rows.map(_mapper.fromRow).toList(),
            ))
        .handleError(
          (e) => Left<Failure, List<Product>>(
            Failure.local(message: '$e'),
          ),
        );
  }

  @override
  Stream<Either<Failure, Product>> watchProduct(String id) {
    return _dao
        .watchById(id)
        .map((row) => row != null
            ? Right<Failure, Product>(_mapper.fromRow(row))
            : Left<Failure, Product>(Failure.notFound(id: id)))
        .handleError(
          (e) => Left<Failure, Product>(Failure.local(message: '$e')),
        );
  }

  @override
  Future<Either<Failure, List<Product>>> getProducts({
    required String categoryId,
    int page = 0,
    int pageSize = 20,
  }) async {
    try {
      final dtos = await _remote.getProducts(
        categoryId: categoryId,
        page: page,
        pageSize: pageSize,
      );
      // Write to local DB — watch streams emit automatically
      await _dao.upsertAll(dtos.map(_mapper.toCompanion).toList());
      return Right(dtos.map(_mapper.fromDto).toList());
    } on DioException catch (e) {
      return Left(Failure.network(message: e.message ?? 'Network error'));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveProduct(Product product) async {
    try {
      await _dao.upsert(_mapper.toCompanion(product));
      // ✅ No need to manually notify — watch streams emit automatically
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }
}
```

---

## Reactive Domain — UseCase with Stream

```dart
// lib/features/product/domain/usecases/watch_products_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class WatchProductsUseCase {
  final ProductRepository _repository;
  WatchProductsUseCase(this._repository);

  Stream<Either<Failure, List<Product>>> call({
    required String categoryId,
  }) {
    return _repository
        .watchProducts(categoryId: categoryId)
        .distinct(); // skip if same list reference
  }
}

// lib/features/product/domain/usecases/watch_product_usecase.dart
@injectable
class WatchProductUseCase {
  final ProductRepository _repository;
  WatchProductUseCase(this._repository);

  Stream<Either<Failure, Product>> call(String id) =>
      _repository.watchProduct(id);
}
```

---

## Reactive Auth Flow — End-to-End

A complete example of reactive data flowing from auth state to UI.

```dart
// Domain — auth repository
abstract interface class AuthRepository {
  Stream<AuthState> watchAuthState(); // emits on login/logout/token refresh
  Future<Either<AuthFailure, User>> signIn(String email, String password);
  Future<Either<AuthFailure, Unit>> signOut();
}

// Data — Firebase/custom auth implementation
@Injectable(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final FirebaseAuth _auth;
  AuthRepositoryImpl(this._auth);

  @override
  Stream<AuthState> watchAuthState() {
    return _auth.authStateChanges().map((user) => user != null
        ? AuthState.authenticated(user: User.fromFirebase(user))
        : const AuthState.unauthenticated());
  }
}

// BLoC — reacts to auth stream
@injectable
class AuthBloc extends Bloc<AuthEvent, AuthBlocState> {
  final AuthRepository _repository;
  final AppEventBus _eventBus;

  AuthBloc(this._repository, this._eventBus)
      : super(const AuthBlocState.initial()) {
    on<WatchAuthEvent>(_onWatch);
    on<SignInEvent>(_onSignIn);
    on<SignOutEvent>(_onSignOut);
  }

  Future<void> _onWatch(
    WatchAuthEvent event,
    Emitter<AuthBlocState> emit,
  ) async {
    await emit.forEach<AuthState>(
      _repository.watchAuthState(),
      onData: (authState) => authState.when(
        authenticated: (user) {
          _eventBus.emit(UserLoggedInEvent(user));
          return AuthBlocState.authenticated(user: user);
        },
        unauthenticated: () {
          _eventBus.emit(UserLoggedOutEvent());
          return const AuthBlocState.unauthenticated();
        },
      ),
    );
  }
}

// Router — reacts to auth state
// In go_router redirect:
String? _handleRedirect(BuildContext context, GoRouterState state) {
  final authState = context.read<AuthBloc>().state;
  final isAuthenticated = authState is AuthBlocStateAuthenticated;
  final isOnAuth = state.matchedLocation.startsWith('/login');

  if (!isAuthenticated && !isOnAuth) return '/login';
  if (isAuthenticated && isOnAuth) return '/home';
  return null;
}
```

---

## Reactive Sync — Write Triggers Watch

The key insight: when you write to the local DB, all active `watch*` streams
emit automatically. No manual notification needed.

```dart
// Sync service — writes to DB, watch streams emit automatically
@injectable
class ProductSyncService {
  final ProductRemoteDataSource _remote;
  final ProductDao _dao;
  final ProductMapper _mapper;

  ProductSyncService(this._remote, this._dao, this._mapper);

  Future<void> syncProducts(String categoryId) async {
    final dtos = await _remote.getProducts(categoryId: categoryId);

    // ✅ Writing to DB automatically triggers all watchByCategory() streams
    // Any BLoC/widget watching this category will receive the update
    await _dao.upsertAll(dtos.map(_mapper.toCompanion).toList());
  }
}

// This is why the reactive pattern is powerful:
// 1. User opens product list → BLoC subscribes to watchProducts()
// 2. Background sync runs → writes to DB
// 3. Drift emits new list → BLoC receives it → UI updates
// No polling, no manual refresh, no setState()
```

---

## Anti-Patterns to Avoid

```dart
// ❌ Polling — never do this
Timer.periodic(const Duration(seconds: 30), (_) async {
  final products = await _repository.getProducts(categoryId: 'cat1');
  setState(() => _products = products);
});

// ❌ Manual notification after write
Future<void> saveProduct(Product product) async {
  await _dao.upsert(product);
  _notifyListeners(); // ❌ unnecessary — watch streams emit automatically
}

// ❌ Fetching in build()
Widget build(BuildContext context) {
  _repository.getProducts(); // ❌ called on every rebuild
  return /* ... */;
}

// ✅ Subscribe once, react to changes
@override
void initState() {
  super.initState();
  context.read<ProductBloc>().add(const ProductEvent.watchProducts('cat1'));
}
```
