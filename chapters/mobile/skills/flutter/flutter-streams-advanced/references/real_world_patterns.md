# Real-World Stream Patterns — Native Dart

Complete patterns for the most common stream use cases.
No rxdart — pure Dart + BLoC/Riverpod.

---

## 1. Live Search

### With BLoC

```dart
// lib/features/search/presentation/bloc/search_bloc.dart
@injectable
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _repository;

  SearchBloc(this._repository) : super(const SearchState.idle()) {
    on<QueryChangedEvent>(
      _onQueryChanged,
      // ✅ debounce 300ms + cancel previous — no rxdart
      transformer: debounceRestartable(const Duration(milliseconds: 300)),
    );
  }

  Future<void> _onQueryChanged(
    QueryChangedEvent event,
    Emitter<SearchState> emit,
  ) async {
    if (event.query.trim().length < 2) {
      emit(const SearchState.idle());
      return;
    }
    emit(const SearchState.loading());
    final result = await _repository.search(event.query);
    result.fold(
      (f) => emit(SearchState.error(f.message)),
      (r) => emit(r.isEmpty ? const SearchState.empty() : SearchState.success(results: r)),
    );
  }
}
```

### With Riverpod

```dart
@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';
  void update(String q) => state = q;
}

@riverpod
Future<List<SearchResult>> searchResults(SearchResultsRef ref) async {
  final query = ref.watch(searchQueryProvider);
  await Future.delayed(const Duration(milliseconds: 300)); // debounce
  if (query.trim().length < 2) return [];
  return ref.watch(searchRepositoryProvider).search(query);
}
```

---

## 2. Real-Time Feed

```dart
// lib/features/feed/data/datasources/feed_data_source.dart
@lazySingleton
class FeedDataSource {
  // Broadcast controller — multiple listeners, no replay
  final _controller = StreamController<List<FeedItem>>.broadcast();
  List<FeedItem> _current = [];

  Stream<List<FeedItem>> get stream => _controller.stream;
  List<FeedItem> get current => List.unmodifiable(_current);

  void prepend(FeedItem item) {
    _current = [item, ..._current];
    _emit();
  }

  void update(FeedItem updated) {
    _current = _current.map((i) => i.id == updated.id ? updated : i).toList();
    _emit();
  }

  void remove(String id) {
    _current = _current.where((i) => i.id != id).toList();
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_current));
  }

  void dispose() => _controller.close();
}

// BLoC — watch the feed stream
@injectable
class FeedBloc extends Bloc<FeedEvent, FeedState> {
  final FeedRepository _repository;

  FeedBloc(this._repository) : super(const FeedState.loading()) {
    on<WatchFeedEvent>(_onWatch);
  }

  Future<void> _onWatch(
    WatchFeedEvent event,
    Emitter<FeedState> emit,
  ) async {
    await emit.forEach<Either<Failure, List<FeedItem>>>(
      _repository.watchFeed(),
      onData: (result) => result.fold(
        (f) => FeedState.error(f.message),
        (items) => FeedState.success(items: items),
      ),
    );
  }
}
```

---

## 3. Event Bus — Decoupled Communication

```dart
// lib/core/events/app_event_bus.dart
sealed class AppEvent {}
class UserLoggedInEvent extends AppEvent { final User user; UserLoggedInEvent(this.user); }
class UserLoggedOutEvent extends AppEvent {}
class CartUpdatedEvent extends AppEvent { final int itemCount; CartUpdatedEvent(this.itemCount); }

@lazySingleton
class AppEventBus {
  final _controller = StreamController<AppEvent>.broadcast();

  Stream<T> on<T extends AppEvent>() => _controller.stream.whereType<T>();

  void emit(AppEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void dispose() => _controller.close();
}

// Emit on login
GetIt.instance<AppEventBus>().emit(UserLoggedInEvent(user));

// React in CartBloc
@injectable
class CartBloc extends Bloc<CartEvent, CartState> {
  final AppEventBus _bus;
  StreamSubscription? _logoutSub;

  CartBloc(this._bus) : super(const CartState.initial()) {
    _logoutSub = _bus.on<UserLoggedOutEvent>().listen((_) {
      add(const CartEvent.clear());
    });
    on<ClearCartEvent>(_onClear);
  }

  @override
  Future<void> close() async {
    await _logoutSub?.cancel();
    return super.close();
  }
}
```

---

## 4. Pagination

### With BLoC

```dart
@injectable
class ProductListBloc extends Bloc<ProductListEvent, ProductListState> {
  final ProductRepository _repository;
  static const _pageSize = 20;
  int _page = 0;

  ProductListBloc(this._repository) : super(const ProductListState.initial()) {
    on<LoadNextPageEvent>(_onLoadNext, transformer: droppable()); // ignore while loading
    on<RefreshEvent>(_onRefresh);
  }

  Future<void> _onLoadNext(
    LoadNextPageEvent event,
    Emitter<ProductListState> emit,
  ) async {
    final current = state;
    if (current is ProductListSuccess && current.hasReachedEnd) return;

    final existing = current is ProductListSuccess ? current.products : <Product>[];
    emit(ProductListState.loadingMore(products: existing));

    final result = await _repository.getProducts(page: _page, pageSize: _pageSize);
    result.fold(
      (f) => emit(ProductListState.error(f.message)),
      (newItems) {
        _page++;
        emit(ProductListState.success(
          products: [...existing, ...newItems],
          hasReachedEnd: newItems.length < _pageSize,
        ));
      },
    );
  }

  Future<void> _onRefresh(RefreshEvent event, Emitter<ProductListState> emit) async {
    _page = 0;
    emit(const ProductListState.initial());
    add(const ProductListEvent.loadNextPage());
  }
}
```

### With Riverpod

```dart
@riverpod
class ProductListNotifier extends _$ProductListNotifier {
  static const _pageSize = 20;

  @override
  Future<ProductListData> build({required String categoryId}) async {
    final items = await ref.watch(productRepositoryProvider)
        .getProducts(categoryId: categoryId, page: 0, pageSize: _pageSize);
    return ProductListData(products: items, page: 0, hasReachedEnd: items.length < _pageSize);
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || current.hasReachedEnd) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final next = await ref.watch(productRepositoryProvider).getProducts(
      categoryId: categoryId,
      page: current.page + 1,
      pageSize: _pageSize,
    );

    state = AsyncData(ProductListData(
      products: [...current.products, ...next],
      page: current.page + 1,
      hasReachedEnd: next.length < _pageSize,
    ));
  }
}
```

---

## 5. Optimistic Update with Rollback

```dart
// lib/features/product/data/repositories/product_repository_impl.dart

/// Emit optimistic update immediately, confirm or rollback after remote call.
Stream<Either<Failure, Product>> updateProductOptimistic(Product updated) async* {
  // 1. Emit optimistic update — UI responds instantly
  yield Right(updated);

  // 2. Persist locally
  await _dao.upsert(_mapper.toCompanion(updated));

  // 3. Sync to remote
  try {
    final confirmed = await _remote.updateProduct(updated);
    yield Right(_mapper.fromDto(confirmed));
  } on DioException catch (e) {
    // 4. Rollback — restore previous version from local DB
    final previous = await _dao.findById(updated.id);
    if (previous != null) yield Right(_mapper.fromRow(previous));
    yield Left(Failure.network(message: e.message ?? 'Update failed'));
  }
}
```

---

## 6. Connectivity-Aware Stream

```dart
// lib/core/network/connectivity_aware_repository.dart
@injectable
class ConnectivityAwareProductRepository {
  final ProductRepository _repository;
  final ConnectivityService _connectivity;

  ConnectivityAwareProductRepository(this._repository, this._connectivity);

  /// Re-subscribes to data stream when connectivity is restored.
  /// Uses asyncExpand — native Dart equivalent of switchMap.
  Stream<Either<Failure, List<Product>>> watchProducts(String categoryId) {
    return _connectivity.onConnectivityChanged
        .distinct()
        // asyncExpand cancels the previous inner stream on each new event
        .asyncExpand((isConnected) => isConnected
            ? _repository.watchProducts(categoryId)
            : Stream.value(
                const Left<Failure, List<Product>>(
                  Failure.network(message: 'No internet connection'),
                ),
              ));
  }
}
```

---

## 7. Batched Writes — bufferTime with native Dart

```dart
// lib/core/analytics/analytics_service.dart
@lazySingleton
class AnalyticsService {
  final _controller = StreamController<AnalyticsEvent>.broadcast();
  StreamSubscription? _batchSub;

  void initialize() {
    // Collect events for 10 seconds, then send batch
    _batchSub = _batchedStream(_controller.stream, const Duration(seconds: 10))
        .where((batch) => batch.isNotEmpty)
        .asyncMap(_sendBatch)
        .listen(
          (_) {},
          onError: (e) => debugPrint('Analytics error: $e'),
          cancelOnError: false,
        );
  }

  void track(AnalyticsEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Native Dart buffer — collects events over a time window.
  Stream<List<T>> _batchedStream<T>(Stream<T> source, Duration window) async* {
    var buffer = <T>[];
    var timer = Timer(window, () {});

    await for (final event in source) {
      buffer.add(event);
      if (!timer.isActive) {
        yield buffer;
        buffer = [];
        timer = Timer(window, () {});
      }
    }
    if (buffer.isNotEmpty) yield buffer;
  }

  Future<void> _sendBatch(List<AnalyticsEvent> events) async {
    // Send to analytics backend
  }

  void dispose() {
    _batchSub?.cancel();
    _controller.close();
  }
}
```

---

## 8. Multi-Source Dashboard

### With BLoC (native combineLatest)

```dart
@injectable
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final UserRepository _userRepo;
  final CartRepository _cartRepo;
  StreamSubscription<DashboardData>? _sub;

  DashboardBloc(this._userRepo, this._cartRepo)
      : super(const DashboardState.loading()) {
    on<InitializeDashboardEvent>(_onInit);
    on<DashboardDataUpdatedEvent>(_onUpdated);
  }

  Future<void> _onInit(
    InitializeDashboardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    await _sub?.cancel();

    // Native combineLatest using broadcast controller
    _sub = combineLatestDashboard(
      _userRepo.watchCurrentUser(),
      _cartRepo.watchCart(),
    ).listen(
      (data) => add(DashboardEvent.dataUpdated(data)),
      onError: (e) => emit(DashboardState.error('$e')),
      cancelOnError: false,
    );
  }

  void _onUpdated(DashboardDataUpdatedEvent event, Emitter<DashboardState> emit) {
    emit(DashboardState.success(data: event.data));
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
```

### With Riverpod (provider composition)

```dart
// ✅ ref.watch composition replaces combineLatest
@riverpod
AsyncValue<DashboardData> dashboardData(DashboardDataRef ref) {
  final userAsync = ref.watch(currentUserProvider);
  final cartAsync = ref.watch(cartProvider);

  return userAsync.whenData((user) {
    return cartAsync.whenData((cart) {
      return DashboardData(user: user, cart: cart);
    });
  }).flatten();
}
```
