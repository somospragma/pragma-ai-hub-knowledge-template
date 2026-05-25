# BLoC / Cubit Integration — Either + Failure

Stack: `flutter_bloc 9.1.1` · `fpdart 1.2.0` · Dart 3.3+

---

## Sealed State with Failure

```dart
// features/products/presentation/bloc/products_state.dart

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:your_app/core/error/failures.dart';

part 'products_state.freezed.dart';

@freezed
sealed class ProductsState with _$ProductsState {
  const factory ProductsState.initial()                           = ProductsInitial;
  const factory ProductsState.loading()                           = ProductsLoading;
  const factory ProductsState.loaded(List<Product> products)      = ProductsLoaded;
  const factory ProductsState.failure(Failure failure)            = ProductsFailure;
  // Granular state: reload while keeping previous data
  const factory ProductsState.refreshing(List<Product> products)  = ProductsRefreshing;
}
```

---

## Cubit with TaskEither — recommended pattern for simple logic

```dart
// features/products/presentation/cubit/products_cubit.dart

class ProductsCubit extends Cubit<ProductsState> {
  ProductsCubit({required GetProductsUseCase getProducts})
      : _getProducts = getProducts,
        super(const ProductsState.initial());

  final GetProductsUseCase _getProducts;

  Future<void> loadProducts() async {
    emit(const ProductsState.loading());

    final result = await _getProducts().run();

    // fold in Cubit: Left → failure, Right → loaded
    result.fold(
      (failure) => emit(ProductsState.failure(failure)),
      (products) => emit(ProductsState.loaded(products)),
    );
  }

  Future<void> refresh() async {
    // Keep current products while reloading
    final current = switch (state) {
      ProductsLoaded(:final products)    => products,
      ProductsRefreshing(:final products) => products,
      _ => <Product>[],
    };

    emit(ProductsState.refreshing(current));

    final result = await _getProducts().run();
    result.fold(
      (failure) => emit(ProductsState.failure(failure)),
      (products) => emit(ProductsState.loaded(products)),
    );
  }
}
```

---

## BLoC with Events and TaskEither — for complex logic

```dart
// ─── Events ───────────────────────────────────────────────────────────────────

sealed class ProductsEvent {
  const ProductsEvent();
}
final class ProductsLoadRequested extends ProductsEvent {
  const ProductsLoadRequested();
}
final class ProductsRefreshRequested extends ProductsEvent {
  const ProductsRefreshRequested();
}
final class ProductDeleteRequested extends ProductsEvent {
  const ProductDeleteRequested(this.productId);
  final String productId;
}

// ─── BLoC ─────────────────────────────────────────────────────────────────────

class ProductsBloc extends Bloc<ProductsEvent, ProductsState> {
  ProductsBloc({
    required GetProductsUseCase getProducts,
    required DeleteProductUseCase deleteProduct,
  })  : _getProducts = getProducts,
        _deleteProduct = deleteProduct,
        super(const ProductsState.initial()) {
    on<ProductsLoadRequested>(_onLoad);
    on<ProductsRefreshRequested>(_onRefresh);
    on<ProductDeleteRequested>(_onDelete);
  }

  final GetProductsUseCase _getProducts;
  final DeleteProductUseCase _deleteProduct;

  Future<void> _onLoad(
    ProductsLoadRequested event,
    Emitter<ProductsState> emit,
  ) async {
    emit(const ProductsState.loading());
    final result = await _getProducts().run();
    result.fold(
      (f) => emit(ProductsState.failure(f)),
      (p) => emit(ProductsState.loaded(p)),
    );
  }

  Future<void> _onRefresh(
    ProductsRefreshRequested event,
    Emitter<ProductsState> emit,
  ) async {
    final current = state is ProductsLoaded
        ? (state as ProductsLoaded).products
        : <Product>[];

    emit(ProductsState.refreshing(current));

    final result = await _getProducts().run();
    result.fold(
      (f) => emit(ProductsState.failure(f)),
      (p) => emit(ProductsState.loaded(p)),
    );
  }

  Future<void> _onDelete(
    ProductDeleteRequested event,
    Emitter<ProductsState> emit,
  ) async {
    final result = await _deleteProduct(event.productId).run();

    result.fold(
      (f) => emit(ProductsState.failure(f)),
      (_) {
        // Optimistically remove from the current list
        if (state is ProductsLoaded) {
          final updated = (state as ProductsLoaded)
              .products
              .where((p) => p.id != event.productId)
              .toList();
          emit(ProductsState.loaded(updated));
        }
      },
    );
  }
}
```

---

## Widget: BlocBuilder with Sealed State

```dart
BlocBuilder<ProductsBloc, ProductsState>(
  builder: (context, state) => switch (state) {
    ProductsInitial()       => const SizedBox.shrink(),
    ProductsLoading()       => const Center(child: CircularProgressIndicator()),
    ProductsLoaded(:final products) => ProductsListView(products: products),
    ProductsRefreshing(:final products) => Stack(
        children: [
          ProductsListView(products: products),
          const Positioned(
            top: 0, left: 0, right: 0,
            child: LinearProgressIndicator(),
          ),
        ],
      ),
    ProductsFailure(:final failure) => FailureView(
        failure: failure,
        onRetry: () => context.read<ProductsBloc>().add(
          const ProductsLoadRequested(),
        ),
      ),
  },
)
```

---

## BlocListener for Error Side Effects

```dart
BlocListener<ProductsBloc, ProductsState>(
  listenWhen: (prev, curr) => curr is ProductsFailure,
  listener: (context, state) {
    if (state is ProductsFailure) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.failure.localizedMessage(context), // i18n
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          action: state.failure.isRetryable
              ? SnackBarAction(
                  label: l.retryButton, // translated from ARB
                  onPressed: () => context.read<ProductsBloc>()
                      .add(const ProductsLoadRequested()),
                )
              : null,
        ),
      );
    }
  },
  child: BlocBuilder<ProductsBloc, ProductsState>(/* ... */),
)
```
