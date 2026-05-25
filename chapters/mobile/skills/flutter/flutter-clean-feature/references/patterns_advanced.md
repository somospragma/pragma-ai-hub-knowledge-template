# Advanced Feature Patterns

## Pagination with Infinite Scroll

```dart
// Domain
class GetProductsParams {
  const GetProductsParams({this.page = 1, this.limit = 20, this.categoryId});
  final int page;
  final int limit;
  final String? categoryId;
}

// BLoC state with pagination
@freezed
sealed class ProductListState with _$ProductListState {
  const factory ProductListState.initial() = _Initial;
  const factory ProductListState.loading() = _Loading;
  const factory ProductListState.loaded({
    required List<ProductUIModel> products,
    required bool hasMore,
    required int currentPage,
  }) = _Loaded;
  const factory ProductListState.loadingMore({
    required List<ProductUIModel> products,
    required int currentPage,
  }) = _LoadingMore;
  const factory ProductListState.error({required String message}) = _Error;
}

@injectable
class ProductListBloc extends Bloc<ProductListEvent, ProductListState> {
  ProductListBloc(this._getProducts) : super(const ProductListState.initial()) {
    on<_LoadRequested>(_onLoad, transformer: droppable());
    on<_LoadMoreRequested>(_onLoadMore, transformer: droppable());
  }

  final GetProductsUseCase _getProducts;
  static const _pageSize = 20;

  Future<void> _onLoad(
    _LoadRequested event,
    Emitter<ProductListState> emit,
  ) async {
    emit(const ProductListState.loading());
    final result = await _getProducts(const GetProductsParams(page: 1, limit: _pageSize));
    emit(result.match(
      (f) => ProductListState.error(message: f.toString()),
      (paginated) => ProductListState.loaded(
        products: paginated.items.map(ProductUIMapper.toUIModel).toList(),
        hasMore: paginated.hasMore,
        currentPage: 1,
      ),
    ));
  }

  Future<void> _onLoadMore(
    _LoadMoreRequested event,
    Emitter<ProductListState> emit,
  ) async {
    final current = state.mapOrNull(loaded: (s) => s);
    if (current == null || !current.hasMore) return;

    emit(ProductListState.loadingMore(
      products: current.products,
      currentPage: current.currentPage,
    ));

    final nextPage = current.currentPage + 1;
    final result = await _getProducts(GetProductsParams(page: nextPage, limit: _pageSize));
    emit(result.match(
      (_) => ProductListState.loaded(
        products: current.products,
        hasMore: current.hasMore,
        currentPage: current.currentPage,
      ),
      (paginated) => ProductListState.loaded(
        products: [
          ...current.products,
          ...paginated.items.map(ProductUIModel.fromDomain),
        ],
        hasMore: paginated.hasMore,
        currentPage: nextPage,
      ),
    ));
  }
}
```

---

## Real-Time Feature with Streams

```dart
// Domain — repository that returns a stream
abstract interface class ChatRepository {
  Stream<Either<Failure, List<Message>>> watchMessages(String chatId);
  Future<Either<Failure, void>> sendMessage(Message message);
}

// BLoC — emit.forEach auto-cancels on close
@injectable
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._chatRepository) : super(const ChatState.initial()) {
    on<_WatchStarted>(_onWatchStarted);
    on<_MessageSent>(_onMessageSent, transformer: sequential());
  }

  final ChatRepository _chatRepository;

  Future<void> _onWatchStarted(
    _WatchStarted event,
    Emitter<ChatState> emit,
  ) async {
    emit(const ChatState.loading());
    await emit.forEach(
      _chatRepository.watchMessages(event.chatId),
      onData: (result) => result.match(
        (f) => ChatState.error(message: f.toString()),
        (messages) => ChatState.success(messages: messages),
      ),
      onError: (_, __) => const ChatState.error(message: 'Connection error'),
    );
  }
}
```

---

## Optimistic Update

```dart
Future<void> _onToggleFavorite(
  _ToggleFavorite event,
  Emitter<ProductState> emit,
) async {
  final current = state.mapOrNull(success: (s) => s);
  if (current == null) return;

  // Optimistic: update UI immediately
  final optimistic = current.product.copyWith(isFavorite: !current.product.isFavorite);
  emit(ProductState.success(product: optimistic));

  // Apply on backend
  final result = await _toggleFavorite(ToggleFavoriteParams(id: event.id));
  result.match(
    (failure) {
      // Revert on error
      emit(ProductState.success(product: current.product));
    },
    (_) {}, // Already applied
  );
}
```

---

## Search with Debounce (bloc_concurrency — no rxdart)

```dart
@injectable
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  SearchBloc(this._searchProducts) : super(const SearchState.initial()) {
    // restartable() cancels the previous handler when a new event arrives.
    // Combined with a small delay, this achieves debounce behaviour.
    on<_QueryChanged>(_onQueryChanged, transformer: restartable());
  }

  final SearchProductsUseCase _searchProducts;

  Future<void> _onQueryChanged(
    _QueryChanged event,
    Emitter<SearchState> emit,
  ) async {
    // If a new event arrives before this delay completes,
    // restartable() cancels this handler and starts fresh.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (event.query.trim().length < 2) {
      emit(const SearchState.initial());
      return;
    }

    emit(const SearchState.loading());
    final result = await _searchProducts(SearchParams(query: event.query));
    emit(result.match(
      (f) => SearchState.error(message: f.toString()),
      (results) => results.isEmpty
          ? const SearchState.empty()
          : SearchState.success(
              results: results.map(ProductUIModel.fromDomain).toList(),
            ),
    ));
  }
}
```
