# Streams with Riverpod

Riverpod treats streams as first-class citizens. `StreamProvider` auto-subscribes,
handles loading/error/data states, and auto-disposes. No manual subscription management.

```yaml
dependencies:
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.6.1

dev_dependencies:
  riverpod_generator: ^2.6.1
  build_runner: ^2.14.1
```

---

## StreamProvider — Reactive DB or WebSocket Stream

```dart
// lib/features/product/presentation/providers/products_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'products_provider.g.dart';

// ✅ StreamProvider — auto-subscribes, auto-disposes, loading/error/data built-in
@riverpod
Stream<List<Product>> products(ProductsRef ref, {required String categoryId}) {
  final repository = ref.watch(productRepositoryProvider);
  // ref.onDispose is handled automatically — no manual cancel needed
  return repository.watchProducts(categoryId);
}
```

```dart
// Widget — no StreamBuilder, no BlocBuilder
class ProductListView extends ConsumerWidget {
  final String categoryId;
  const ProductListView({required this.categoryId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider(categoryId: categoryId));

    return productsAsync.when(
      loading: () => const CircularProgressIndicator(),
      error: (error, _) => ErrorWidget('$error'),
      data: (products) => ListView.builder(
        itemCount: products.length,
        itemBuilder: (_, i) => ProductTile(product: products[i]),
      ),
    );
  }
}
```

---

## Live Search — Debounce Without rxdart

Riverpod cancels the previous `Future` automatically when the watched state changes.
`Future.delayed` inside the provider acts as a debounce.

```dart
// lib/features/search/presentation/providers/search_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'search_provider.g.dart';

// Query state
@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void update(String query) => state = query;
  void clear() => state = '';
}

// Debounced search results — pure Dart, no rxdart
@riverpod
Future<List<SearchResult>> searchResults(SearchResultsRef ref) async {
  final query = ref.watch(searchQueryProvider);

  // ✅ Debounce: if query changes within 300ms, this Future is cancelled
  // and a new one starts — Riverpod handles this automatically
  await Future.delayed(const Duration(milliseconds: 300));

  if (query.trim().length < 2) return [];

  final repository = ref.watch(searchRepositoryProvider);
  return repository.search(query);
}
```

```dart
// Widget
class SearchView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);

    return Column(
      children: [
        TextField(
          onChanged: (q) =>
              ref.read(searchQueryProvider.notifier).update(q),
          decoration: const InputDecoration(
            hintText: 'Search...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (results) => results.isEmpty
                ? const Center(child: Text('No results'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, i) =>
                        SearchResultTile(result: results[i]),
                  ),
          ),
        ),
      ],
    );
  }
}
```

---

## AsyncNotifier — Complex State with Stream Subscriptions

Use when you need to manage multiple stream subscriptions and expose a single
computed state.

```dart
// lib/features/dashboard/presentation/providers/dashboard_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_provider.g.dart';

@riverpod
class DashboardNotifier extends _$DashboardNotifier {
  @override
  Future<DashboardData> build() async {
    // ✅ ref.onDispose handles cleanup — no manual cancel needed
    final userSub = ref
        .watch(userRepositoryProvider)
        .watchCurrentUser()
        .listen(_onUserUpdated);
    ref.onDispose(userSub.cancel);

    final cartSub = ref
        .watch(cartRepositoryProvider)
        .watchCart()
        .listen(_onCartUpdated);
    ref.onDispose(cartSub.cancel);

    // Initial load
    final user = await ref.watch(userRepositoryProvider).getCurrentUser();
    final cart = await ref.watch(cartRepositoryProvider).getCart();
    final unread = await ref
        .watch(notificationRepositoryProvider)
        .getUnreadCount();

    return DashboardData(
      user: user,
      cart: cart,
      unreadNotifications: unread,
    );
  }

  void _onUserUpdated(User user) {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(user: user));
    }
  }

  void _onCartUpdated(Cart cart) {
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(cart: cart));
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
```

```dart
// Widget
class DashboardView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardNotifierProvider);

    return dashboardAsync.when(
      loading: () => const DashboardSkeleton(),
      error: (e, _) => ErrorView(message: '$e'),
      data: (data) => DashboardContent(data: data),
    );
  }
}
```

---

## Multi-Source Composition — Provider Watching

Riverpod's `ref.watch` replaces `combineLatest` — the provider re-evaluates
whenever any watched provider changes.

```dart
// lib/features/checkout/presentation/providers/checkout_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'checkout_provider.g.dart';

@riverpod
AsyncValue<CheckoutSummary> checkoutSummary(CheckoutSummaryRef ref) {
  // ✅ Watch multiple providers — re-evaluates when any changes
  final cartAsync = ref.watch(cartProvider);
  final userAsync = ref.watch(currentUserProvider);
  final addressAsync = ref.watch(selectedAddressProvider);

  // Combine AsyncValues — if any is loading/error, propagate it
  return cartAsync.whenData((cart) {
    return userAsync.whenData((user) {
      return addressAsync.whenData((address) {
        return CheckoutSummary(
          cart: cart,
          user: user,
          deliveryAddress: address,
          total: cart.total + address.deliveryFee,
        );
      });
    });
  }).flatten(); // flatten nested AsyncValue<AsyncValue<AsyncValue<T>>>
}

// Extension to flatten nested AsyncValues
extension AsyncValueX<T> on AsyncValue<AsyncValue<AsyncValue<T>>> {
  AsyncValue<T> flatten() => when(
    loading: () => const AsyncLoading(),
    error: (e, s) => AsyncError(e, s),
    data: (inner) => inner.when(
      loading: () => const AsyncLoading(),
      error: (e, s) => AsyncError(e, s),
      data: (innermost) => innermost,
    ),
  );
}
```

---

## Pagination with Riverpod

```dart
// lib/features/product/presentation/providers/product_list_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'product_list_provider.g.dart';

@riverpod
class ProductListNotifier extends _$ProductListNotifier {
  static const _pageSize = 20;

  @override
  Future<ProductListData> build({required String categoryId}) async {
    final products = await ref
        .watch(productRepositoryProvider)
        .getProducts(categoryId: categoryId, page: 0, pageSize: _pageSize);

    return ProductListData(
      products: products,
      currentPage: 0,
      hasReachedEnd: products.length < _pageSize,
    );
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || current.hasReachedEnd) return;

    // Keep current data visible while loading next page
    state = AsyncData(current.copyWith(isLoadingMore: true));

    final nextPage = await ref
        .watch(productRepositoryProvider)
        .getProducts(
          categoryId: categoryId,
          page: current.currentPage + 1,
          pageSize: _pageSize,
        );

    state = AsyncData(ProductListData(
      products: [...current.products, ...nextPage],
      currentPage: current.currentPage + 1,
      hasReachedEnd: nextPage.length < _pageSize,
    ));
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future; // wait for rebuild
  }
}
```

---

## Testing Riverpod Providers

```dart
// test/features/search/presentation/providers/search_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSearchRepository extends Mock implements SearchRepository {}

void main() {
  late ProviderContainer container;
  late MockSearchRepository mockRepo;

  setUp(() {
    mockRepo = MockSearchRepository();
    container = ProviderContainer(
      overrides: [
        searchRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('searchResultsProvider', () {
    test('returns empty list for short query', () async {
      container.read(searchQueryProvider.notifier).update('a');

      await Future.delayed(const Duration(milliseconds: 350));

      final result = await container.read(searchResultsProvider.future);
      expect(result, isEmpty);
      verifyNever(() => mockRepo.search(any()));
    });

    test('calls repository after debounce', () async {
      when(() => mockRepo.search('flutter'))
          .thenAnswer((_) async => [SearchResult(id: '1', title: 'Flutter')]);

      container.read(searchQueryProvider.notifier).update('flutter');

      await Future.delayed(const Duration(milliseconds: 350));

      final result = await container.read(searchResultsProvider.future);
      expect(result.length, 1);
      verify(() => mockRepo.search('flutter')).called(1);
    });

    test('StreamProvider emits loading then data', () async {
      when(() => mockRepo.watchProducts('cat1'))
          .thenAnswer((_) => Stream.fromIterable([
                [Product(id: 'p1', name: 'Test')],
              ]));

      final sub = container.listen(
        productsProvider(categoryId: 'cat1'),
        (_, __) {},
      );

      expect(
        container.read(productsProvider(categoryId: 'cat1')),
        const AsyncLoading<List<Product>>(),
      );

      await Future.delayed(Duration.zero);

      expect(
        container.read(productsProvider(categoryId: 'cat1')).value?.length,
        1,
      );

      sub.close();
    });
  });
}
```
