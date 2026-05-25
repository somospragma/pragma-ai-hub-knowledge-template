# Riverpod Reactive Patterns

Complete reactive patterns using Riverpod 2.6 — from data source to UI.

---

## StreamProvider — Reactive DB Stream

```dart
// lib/features/product/presentation/providers/product_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'product_providers.g.dart';

// ✅ StreamProvider — auto-subscribes, auto-disposes, loading/error/data built-in
@riverpod
Stream<List<Product>> products(
  ProductsRef ref, {
  required String categoryId,
}) {
  return ref.watch(productRepositoryProvider).watchProducts(
    categoryId: categoryId,
  );
}

// Widget — no StreamBuilder, no BlocBuilder
class ProductListView extends ConsumerWidget {
  final String categoryId;
  const ProductListView({required this.categoryId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider(categoryId: categoryId));

    return productsAsync.when(
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
      data: (products) => products.isEmpty
          ? const Text('No products')
          : ListView.builder(
              itemCount: products.length,
              itemBuilder: (_, i) => ProductTile(product: products[i]),
            ),
    );
  }
}
```

---

## Notifier — Reactive State with Commands

```dart
// lib/features/product/presentation/providers/product_list_notifier.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'product_list_notifier.g.dart';

@riverpod
class ProductListNotifier extends _$ProductListNotifier {
  @override
  Stream<List<Product>> build({required String categoryId}) {
    // ✅ ref.onDispose handles cleanup automatically
    return ref.watch(productRepositoryProvider).watchProducts(
      categoryId: categoryId,
    );
  }

  Future<void> saveProduct(Product product) async {
    await ref.read(productRepositoryProvider).saveProduct(product);
    // ✅ No manual refresh — watch stream emits automatically after save
  }

  Future<void> deleteProduct(String id) async {
    await ref.read(productRepositoryProvider).deleteProduct(id);
    // ✅ Watch stream emits updated list automatically
  }
}
```

---

## AsyncNotifier — Complex Reactive State

```dart
// lib/features/dashboard/presentation/providers/dashboard_notifier.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dashboard_notifier.g.dart';

@riverpod
class DashboardNotifier extends _$DashboardNotifier {
  @override
  Future<DashboardData> build() async {
    // ✅ Subscribe to multiple streams — ref.onDispose handles cleanup
    final userSub = ref
        .watch(userRepositoryProvider)
        .watchCurrentUser()
        .listen(_onUserChanged);
    ref.onDispose(userSub.cancel);

    final cartSub = ref
        .watch(cartRepositoryProvider)
        .watchCart()
        .listen(_onCartChanged);
    ref.onDispose(cartSub.cancel);

    // Initial load
    final (user, cart, unread) = await (
      ref.watch(userRepositoryProvider).getCurrentUser(),
      ref.watch(cartRepositoryProvider).getCart(),
      ref.watch(notificationRepositoryProvider).getUnreadCount(),
    ).wait;

    return DashboardData(user: user, cart: cart, unreadNotifications: unread);
  }

  void _onUserChanged(User user) {
    state = state.whenData((data) => data.copyWith(user: user));
  }

  void _onCartChanged(Cart cart) {
    state = state.whenData((data) => data.copyWith(cart: cart));
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}
```

---

## Provider Composition — Reactive Multi-Source

```dart
// lib/features/checkout/presentation/providers/checkout_providers.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'checkout_providers.g.dart';

// Each provider is independently reactive
@riverpod
Stream<Cart> cart(CartRef ref) =>
    ref.watch(cartRepositoryProvider).watchCart();

@riverpod
Stream<User> currentUser(CurrentUserRef ref) =>
    ref.watch(userRepositoryProvider).watchCurrentUser();

@riverpod
Stream<List<Address>> savedAddresses(SavedAddressesRef ref) =>
    ref.watch(addressRepositoryProvider).watchAddresses();

// ✅ Composed provider — re-evaluates when ANY dependency changes
@riverpod
AsyncValue<CheckoutSummary> checkoutSummary(CheckoutSummaryRef ref) {
  final cartAsync = ref.watch(cartProvider);
  final userAsync = ref.watch(currentUserProvider);
  final addressesAsync = ref.watch(savedAddressesProvider);

  // Combine — if any is loading/error, propagate it
  return cartAsync.whenData((cart) =>
    userAsync.whenData((user) =>
      addressesAsync.whenData((addresses) =>
        CheckoutSummary(
          cart: cart,
          user: user,
          defaultAddress: addresses.firstOrNull,
          total: cart.total,
        ),
      ),
    ),
  ).flatten();
}

// Extension to flatten nested AsyncValues
extension<T> on AsyncValue<AsyncValue<AsyncValue<T>>> {
  AsyncValue<T> flatten() => when(
    loading: () => const AsyncLoading(),
    error: AsyncError.new,
    data: (inner) => inner.when(
      loading: () => const AsyncLoading(),
      error: AsyncError.new,
      data: (innermost) => innermost,
    ),
  );
}
```

---

## Reactive Form Validation

```dart
// lib/features/auth/presentation/providers/login_form_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'login_form_provider.g.dart';

@freezed
class LoginFormState with _$LoginFormState {
  const factory LoginFormState({
    @Default('') String email,
    @Default('') String password,
    @Default(false) bool isSubmitting,
    String? emailError,
    String? passwordError,
  }) = _LoginFormState;

  const LoginFormState._();

  bool get isValid =>
      emailError == null &&
      passwordError == null &&
      email.isNotEmpty &&
      password.isNotEmpty;
}

@riverpod
class LoginFormNotifier extends _$LoginFormNotifier {
  @override
  LoginFormState build() => const LoginFormState();

  void updateEmail(String email) {
    state = state.copyWith(
      email: email,
      emailError: _validateEmail(email),
    );
  }

  void updatePassword(String password) {
    state = state.copyWith(
      password: password,
      passwordError: _validatePassword(password),
    );
  }

  Future<void> submit() async {
    if (!state.isValid || state.isSubmitting) return;

    state = state.copyWith(isSubmitting: true);

    try {
      await ref.read(authRepositoryProvider).signIn(
        state.email,
        state.password,
      );
      // Auth stream emits authenticated state — router redirects automatically
    } catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        emailError: 'Invalid credentials',
      );
    }
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return null; // don't show error while empty
    if (!email.contains('@')) return 'Invalid email';
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) return null;
    if (password.length < 8) return 'At least 8 characters';
    return null;
  }
}

// Widget
class LoginForm extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(loginFormNotifierProvider);
    final notifier = ref.read(loginFormNotifierProvider.notifier);

    return Column(
      children: [
        TextField(
          onChanged: notifier.updateEmail,
          decoration: InputDecoration(errorText: form.emailError),
        ),
        TextField(
          onChanged: notifier.updatePassword,
          obscureText: true,
          decoration: InputDecoration(errorText: form.passwordError),
        ),
        ElevatedButton(
          onPressed: form.isValid && !form.isSubmitting ? notifier.submit : null,
          child: form.isSubmitting
              ? const CircularProgressIndicator()
              : const Text('Sign In'),
        ),
      ],
    );
  }
}
```

---

## Reactive Pagination

```dart
// lib/features/product/presentation/providers/product_pagination_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'product_pagination_provider.g.dart';

@freezed
class ProductPageState with _$ProductPageState {
  const factory ProductPageState({
    @Default([]) List<Product> products,
    @Default(0) int page,
    @Default(false) bool hasReachedEnd,
    @Default(false) bool isLoadingMore,
  }) = _ProductPageState;
}

@riverpod
class ProductPaginationNotifier extends _$ProductPaginationNotifier {
  static const _pageSize = 20;

  @override
  Future<ProductPageState> build({required String categoryId}) async {
    final products = await ref.watch(productRepositoryProvider).getProducts(
      categoryId: categoryId,
      page: 0,
      pageSize: _pageSize,
    );

    return ProductPageState(
      products: products.getOrElse((_) => []),
      hasReachedEnd: products.getOrElse((_) => []).length < _pageSize,
    );
  }

  Future<void> loadNextPage() async {
    final current = state.valueOrNull;
    if (current == null || current.hasReachedEnd || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    final result = await ref.read(productRepositoryProvider).getProducts(
      categoryId: categoryId,
      page: current.page + 1,
      pageSize: _pageSize,
    );

    result.fold(
      (failure) => state = AsyncError(failure, StackTrace.current),
      (newProducts) => state = AsyncData(ProductPageState(
        products: [...current.products, ...newProducts],
        page: current.page + 1,
        hasReachedEnd: newProducts.length < _pageSize,
      )),
    );
  }
}
```

---

## Testing Riverpod Reactive Providers

```dart
// test/features/product/presentation/providers/product_providers_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late ProviderContainer container;
  late MockProductRepository mockRepo;

  setUp(() {
    mockRepo = MockProductRepository();
    container = ProviderContainer(
      overrides: [
        productRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  group('productsProvider', () {
    test('emits products from repository stream', () async {
      final products = [Product(id: 'p1', name: 'Test', price: 9.99)];

      when(() => mockRepo.watchProducts(categoryId: 'cat1'))
          .thenAnswer((_) => Stream.value(Right(products)));

      final sub = container.listen(
        productsProvider(categoryId: 'cat1'),
        (_, __) {},
      );

      // Initially loading
      expect(
        container.read(productsProvider(categoryId: 'cat1')),
        const AsyncLoading<List<Product>>(),
      );

      await Future.delayed(Duration.zero);

      // Then data
      expect(
        container.read(productsProvider(categoryId: 'cat1')).value,
        products,
      );

      sub.close();
    });
  });

  group('LoginFormNotifier', () {
    test('isValid is false with empty fields', () {
      final form = container.read(loginFormNotifierProvider);
      expect(form.isValid, false);
    });

    test('isValid is true with valid email and password', () {
      final notifier = container.read(loginFormNotifierProvider.notifier);
      notifier.updateEmail('user@example.com');
      notifier.updatePassword('password123');

      final form = container.read(loginFormNotifierProvider);
      expect(form.isValid, true);
      expect(form.emailError, isNull);
      expect(form.passwordError, isNull);
    });

    test('shows email error for invalid email', () {
      final notifier = container.read(loginFormNotifierProvider.notifier);
      notifier.updateEmail('not-an-email');

      final form = container.read(loginFormNotifierProvider);
      expect(form.emailError, isNotNull);
    });
  });
}
```
