# BLoC Implementation Guide — bloc 9.1.1 / flutter_bloc 9.1.1

Canonical guide for implementing Events, States, and BLoCs using `bloc 9.1.1`,
`flutter_bloc 9.1.1`, and `bloc_concurrency 0.3.x` with Freezed sealed unions.

---

## 1. File Structure

```
lib/features/<feature>/presentation/bloc/
├── <feature>_bloc.dart        # BLoC class (logic)
├── <feature>_event.dart       # Events (sealed union)
└── <feature>_state.dart       # States (sealed union)
```

> Each BLoC lives inside its feature module. One BLoC = one event file + one state file + one BLoC file.

---

## 2. Events — Correct Definition

Events represent **user or system intentions**. They are modeled as sealed unions with Freezed.

### Rules

| Rule | Description |
|---|---|
| Naming | Past tense or imperative: `LoginRequested`, `ItemAdded`, `DataRefreshed` |
| Immutability | Every event is `const` and its fields are `final` |
| No logic | Events do NOT transform data; they only carry parameters |
| One factory per action | Each user or system interaction is a separate factory |

### Complete example

```dart
// lib/features/products/presentation/bloc/product_list_event.dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'product_list_event.freezed.dart';

@freezed
sealed class ProductListEvent with _$ProductListEvent {
  /// User opened the screen or pulled to refresh.
  const factory ProductListEvent.started() = _Started;

  /// User reached the end of the scroll → load more.
  const factory ProductListEvent.nextPageRequested() = _NextPageRequested;

  /// User typed in the search field.
  const factory ProductListEvent.searchQueryChanged({
    required String query,
  }) = _SearchQueryChanged;

  /// User changed the category filter.
  const factory ProductListEvent.categoryFilterChanged({
    required String categoryId,
  }) = _CategoryFilterChanged;

  /// User deleted a product.
  const factory ProductListEvent.itemDeleted({
    required String productId,
  }) = _ItemDeleted;
}
```

### Event anti-patterns

```dart
// ❌ Generic names — do not communicate intent
const factory ProductListEvent.update() = _Update;

// ❌ Event with internal logic
const factory ProductListEvent.filtered({
  required List<Product> filtered, // ← the UI should not filter
}) = _Filtered;

// ❌ Monolithic event with optional parameters
const factory ProductListEvent.load({
  String? query,
  String? categoryId,
  int? page,
  bool? forceRefresh,
}) = _Load; // ← create a separate event for each action
```

---

## 3. States — Correct Definition

States represent **complete UI snapshots**. They are modeled as sealed unions with Freezed.

### Rules

| Rule | Description |
|---|---|
| Exhaustive | Each state covers a distinct visual case of the screen |
| Self-contained | Each variant carries all the data the UI needs to render |
| No logic | The state does NOT compute anything; the BLoC emits it already resolved |
| `const` always | If it has no dynamic fields, it must be `const` |

### Complete example

```dart
// lib/features/products/presentation/bloc/product_list_state.dart
import 'package:freezed_annotation/freezed_annotation.dart';
import '../../domain/entities/product.dart';
part 'product_list_state.freezed.dart';

@freezed
sealed class ProductListState with _$ProductListState {
  /// Initial state before any load.
  const factory ProductListState.initial() = _Initial;

  /// Load in progress (first load or full refresh).
  const factory ProductListState.loading() = _Loading;

  /// Data loaded successfully.
  const factory ProductListState.success({
    required List<Product> products,
    required bool hasReachedEnd,
    @Default(false) bool isLoadingMore,
  }) = _Success;

  /// Recoverable error with retry option.
  const factory ProductListState.error({
    required String message,
    required String code,
  }) = _Error;
}
```

### "Append" pattern for pagination

When the BLoC loads more data, it emits a copy of the `_Success` state with the extended list:

```dart
// Inside the BLoC handler
if (state case ProductListState.success(:final products)) {
  emit((state as _Success).copyWith(isLoadingMore: true));
  final result = await _getProducts(page: nextPage);
  result.fold(
    (f) => emit((state as _Success).copyWith(isLoadingMore: false)),
    (newItems) => emit((state as _Success).copyWith(
      products: [...products, ...newItems],
      hasReachedEnd: newItems.isEmpty,
      isLoadingMore: false,
    )),
  );
}
```

### State anti-patterns

```dart
// ❌ "God" state with boolean flags
@freezed
class ProductListState with _$ProductListState {
  const factory ProductListState({
    required bool isLoading,
    required bool hasError,
    String? errorMessage,
    List<Product>? products,
  }) = _ProductListState;
  // ← impossible to exhaust combinations; UI will have nested if/else
}

// ❌ State that stores framework objects
const factory ProductListState.error({
  required BuildContext context, // ← FORBIDDEN
}) = _Error;
```

---

## 4. BLoC Class — Correct Implementation

The BLoC orchestrates: receives events, calls use cases, and emits states.

### Rules

| Rule | Description |
|---|---|
| Constructor injection | Only receives **UseCases** (never DataSources or Repositories directly) |
| `@injectable` | Registered in the DI container (injectable / get_it) |
| `on<PrivateType>` | Register handlers with the private type generated by Freezed (`_Started`, etc.) |
| Explicit `transformer` | Every `on<>` must explicitly declare its concurrency strategy |
| No internal `add()` | Do not call `add()` inside a handler (infinite loop risk) |
| No `context` | The BLoC never accesses `BuildContext` |

### Complete example

```dart
// lib/features/products/presentation/bloc/product_list_bloc.dart
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:injectable/injectable.dart';
import '../../domain/use_cases/get_products_use_case.dart';
import '../../domain/use_cases/delete_product_use_case.dart';
import '../../domain/use_cases/search_products_use_case.dart';
import 'product_list_event.dart';
import 'product_list_state.dart';

@injectable
class ProductListBloc extends Bloc<ProductListEvent, ProductListState> {
  ProductListBloc(
    this._getProducts,
    this._deleteProduct,
    this._searchProducts,
  ) : super(const ProductListState.initial()) {
    on<_Started>(_onStarted, transformer: droppable());
    on<_NextPageRequested>(_onNextPage, transformer: droppable());
    on<_SearchQueryChanged>(_onSearch, transformer: restartable());
    on<_CategoryFilterChanged>(_onCategoryFilter, transformer: restartable());
    on<_ItemDeleted>(_onItemDeleted, transformer: sequential());
  }

  final GetProductsUseCase _getProducts;
  final DeleteProductUseCase _deleteProduct;
  final SearchProductsUseCase _searchProducts;

  int _currentPage = 0;

  Future<void> _onStarted(
    _Started event,
    Emitter<ProductListState> emit,
  ) async {
    _currentPage = 0;
    emit(const ProductListState.loading());
    final result = await _getProducts(page: _currentPage);
    emit(result.fold(
      (failure) => ProductListState.error(
        message: failure.message,
        code: failure.runtimeType.toString(),
      ),
      (products) => ProductListState.success(
        products: products,
        hasReachedEnd: products.isEmpty,
      ),
    ));
  }

  Future<void> _onNextPage(
    _NextPageRequested event,
    Emitter<ProductListState> emit,
  ) async {
    if (state case ProductListState.success(
      :final products,
      hasReachedEnd: false,
      isLoadingMore: false,
    )) {
      emit((state as _Success).copyWith(isLoadingMore: true));
      _currentPage++;
      final result = await _getProducts(page: _currentPage);
      emit(result.fold(
        (_) => (state as _Success).copyWith(isLoadingMore: false),
        (newItems) => (state as _Success).copyWith(
          products: [...products, ...newItems],
          hasReachedEnd: newItems.isEmpty,
          isLoadingMore: false,
        ),
      ));
    }
  }

  Future<void> _onSearch(
    _SearchQueryChanged event,
    Emitter<ProductListState> emit,
  ) async {
    if (event.query.length < 2) return;
    emit(const ProductListState.loading());
    final result = await _searchProducts(query: event.query);
    emit(result.fold(
      (f) => ProductListState.error(message: f.message, code: ''),
      (products) => ProductListState.success(
        products: products,
        hasReachedEnd: true,
      ),
    ));
  }

  Future<void> _onCategoryFilter(
    _CategoryFilterChanged event,
    Emitter<ProductListState> emit,
  ) async {
    _currentPage = 0;
    emit(const ProductListState.loading());
    final result = await _getProducts(
      page: _currentPage,
      categoryId: event.categoryId,
    );
    emit(result.fold(
      (f) => ProductListState.error(message: f.message, code: ''),
      (products) => ProductListState.success(
        products: products,
        hasReachedEnd: products.isEmpty,
      ),
    ));
  }

  Future<void> _onItemDeleted(
    _ItemDeleted event,
    Emitter<ProductListState> emit,
  ) async {
    final result = await _deleteProduct(productId: event.productId);
    result.fold(
      (_) => null, // silent error or handle per UX requirements
      (_) {
        if (state case ProductListState.success(
          :final products,
          :final hasReachedEnd,
        )) {
          emit(ProductListState.success(
            products: products.where((p) => p.id != event.productId).toList(),
            hasReachedEnd: hasReachedEnd,
          ));
        }
      },
    );
  }
}
```

---

## 5. Widget Integration

### BlocProvider (always at Page level)

```dart
@RoutePage()
class ProductListPage extends StatelessWidget {
  const ProductListPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<ProductListBloc>()
          ..add(const ProductListEvent.started()),
        child: const _ProductListView(),
      );
}
```

### BlocBuilder (render based on state)

```dart
class _ProductListView extends StatelessWidget {
  const _ProductListView();

  @override
  Widget build(BuildContext context) => BlocBuilder<ProductListBloc, ProductListState>(
        buildWhen: (prev, curr) => prev != curr,
        builder: (context, state) => switch (state) {
          ProductListState.initial() => const SizedBox.shrink(),
          ProductListState.loading() => const Center(child: CircularProgressIndicator()),
          ProductListState.success(:final products, :final isLoadingMore) =>
            _ProductGrid(products: products, isLoadingMore: isLoadingMore),
          ProductListState.error(:final message) => _ErrorView(message: message),
        },
      );
}
```

### BlocListener (side effects: navigation, snackbars, dialogs)

```dart
BlocListener<ProductListBloc, ProductListState>(
  listenWhen: (prev, curr) => curr is _Error,
  listener: (context, state) {
    if (state case ProductListState.error(:final message)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  },
  child: const _ProductListView(),
)
```

### Dispatching events from the UI

```dart
// ✅ Correct — use context.read<Bloc>() to dispatch
ElevatedButton(
  onPressed: () => context.read<ProductListBloc>().add(
    const ProductListEvent.started(),
  ),
  child: const Text('Retry'),
)

// ❌ Incorrect — do NOT use context.watch to dispatch
onPressed: () => context.watch<ProductListBloc>().add(...) // FORBIDDEN
```

---

## 6. Transformer Selection (bloc_concurrency 0.3.x)

| Transformer | Behaviour | When to use |
|---|---|---|
| `droppable()` | Ignores new events while one is processing | Initial load, pull-to-refresh, pagination |
| `sequential()` | Queues events, processes one at a time in order | Send message, write operations |
| `restartable()` | Cancels current event and starts the new one | Search with debounce, filters |
| `concurrent()` | Processes all in parallel (default if not specified) | Logging, analytics |

```dart
on<_Started>(_onStarted, transformer: droppable());
on<_MessageSent>(_onSend, transformer: sequential());
on<_SearchQueryChanged>(_onSearch, transformer: restartable());
on<_EventLogged>(_onLog); // concurrent() by default
```

---

## 7. onDone — Cleanup on BLoC Close

New in bloc 9.x. Called when the BLoC's event handler stream completes.

```dart
@injectable
class AnalyticsBloc extends Bloc<AnalyticsEvent, AnalyticsState> {
  AnalyticsBloc(this._service) : super(const AnalyticsState.initial()) {
    on<_EventTracked>(_onEventTracked);
  }

  final AnalyticsService _service;

  @override
  void onDone() {
    // Flush any pending analytics when the BLoC is closed
    _service.flush();
    super.onDone();
  }
}
```

---

## 8. MultiBlocObserver

Register multiple observers simultaneously — useful for combining logging,
analytics, and crash reporting:

```dart
// main.dart
Bloc.observer = MultiBlocObserver(
  observers: [
    LoggingBlocObserver(),
    AnalyticsBlocObserver(),
    CrashlyticsBlocObserver(),
  ],
);

// Each observer only needs to implement what it cares about
class LoggingBlocObserver extends BlocObserver {
  @override
  void onTransition(Bloc bloc, Transition transition) {
    super.onTransition(bloc, transition);
    if (kDebugMode) {
      debugPrint('[${bloc.runtimeType}] ${transition.event} → ${transition.nextState}');
    }
  }
}

class CrashlyticsBlocObserver extends BlocObserver {
  @override
  void onError(BlocBase bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    FirebaseCrashlytics.instance.recordError(error, stackTrace);
  }
}
```

---

## 9. Implementation Checklist

- [ ] `_event.dart`: Freezed sealed union, one factory per intention, descriptive names
- [ ] `_state.dart`: Freezed sealed union, exhaustive variants, self-contained data
- [ ] `_bloc.dart`: `@injectable`, constructor with UseCases only, explicit `transformer` on every `on<>`
- [ ] `BlocProvider` at Page level, not inside internal widgets
- [ ] `BlocBuilder` with `buildWhen` and exhaustive `switch` over state
- [ ] `BlocListener` only for side effects (navigation, snackbar, dialog)
- [ ] No `context` inside the BLoC
- [ ] No `add()` inside handlers
- [ ] No DataSources injected directly into the BLoC
- [ ] `onDone()` overridden when cleanup is needed on close

## Architecture Diagrams

- `CleanArchitecture.mmd` — Layered flowchart of all layers and their dependencies
- `ClassDiagram.mmd` — Full class hierarchy with DI wiring
- `SequenceDiagram.mmd` — Concrete request/response flow
- `PlaceholdersSequenceDiagram.mmd` — Template with `{Feature}` placeholders for new features
