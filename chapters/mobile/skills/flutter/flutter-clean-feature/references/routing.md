# Navigation — go_router 17.2.2

## Current Versions
- `go_router: ^17.2.2`
- `go_router_builder: ^4.3.0` (optional, type-safe routes)
- `build_runner: ^2.15.0` (only if using go_router_builder)

## Router Definition

```dart
// lib/core/router/app_router.dart  (single project)
// lib/{app_name}/lib/app_router.dart  (monorepo)
import 'package:go_router/go_router.dart';

GoRouter appRouter({required AuthNotifier authNotifier}) => GoRouter(
  initialLocation: '/splash',
  caseSensitive: true,
  refreshListenable: authNotifier,
  redirect: (context, state) async {
    final isLoggedIn = authNotifier.isAuthenticated;
    final isLoggingIn = state.matchedLocation == '/login';
    final isSplash = state.matchedLocation == '/splash';

    if (isSplash) return null;
    if (!isLoggedIn) return isLoggingIn ? null : '/login';
    if (isLoggingIn) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),

    // Shell with bottom navigation
    StatefulShellRoute.indexedStack(
      pageBuilder: (_, __, navigationShell) => NoTransitionPage(
        child: ShellPage(navigationShell: navigationShell),
      ),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/products',
            builder: (_, __) => const ProductListPage(),
            routes: [
              GoRoute(
                path: ':productId',
                builder: (_, state) => ProductPage(
                  productId: state.pathParameters['productId']!,
                ),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/cart', builder: (_, __) => const CartPage()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
        ]),
      ],
    ),
  ],
  onException: (_, state, router) => router.go('/home'),
);
```

## Page with Parameters

```dart
// lib/{feature}/presentation/pages/product_page.dart
class ProductPage extends StatelessWidget {
  const ProductPage({required this.productId, this.fromSearch = false, super.key});
  final String productId;
  final bool fromSearch;

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => getIt<ProductBloc>()
          ..add(ProductEvent.loadRequested(id: productId)),
        child: const _ProductView(),
      );
}

// GoRoute registration:
GoRoute(
  path: ':productId',
  builder: (_, state) => ProductPage(
    productId: state.pathParameters['productId']!,
    fromSearch: state.uri.queryParameters['fromSearch'] == 'true',
  ),
),
```

## AuthNotifier (refreshListenable)

```dart
// lib/core/router/auth_notifier.dart
@lazySingleton
class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._tokenRepository);
  final TokenRepository _tokenRepository;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> checkAuth() async {
    final token = await _tokenRepository.getAccessToken();
    final wasAuth = _isAuthenticated;
    _isAuthenticated = token != null;
    if (wasAuth != _isAuthenticated) notifyListeners();
  }

  void setAuthenticated(bool value) {
    if (_isAuthenticated != value) {
      _isAuthenticated = value;
      notifyListeners();
    }
  }
}
```

## Shell Page with Bottom Navigation

```dart
class ShellPage extends StatelessWidget {
  const ShellPage({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: navigationShell,
    bottomNavigationBar: NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: (index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      ),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.search), label: 'Products'),
        NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Cart'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    ),
  );
}
```

## Navigation API

```dart
// Push (adds to stack)
context.push('/products/123');

// Go (replaces stack to root match)
context.go('/home');

// Replace current
context.pushReplacement('/home');

// Pop
context.pop();

// Pop with result
context.pop<bool>(true);

// Relative (from /products)
context.go('./123');

// Query parameters
context.push('/products?category=electronics');

// Named navigation
context.goNamed('productDetail', pathParameters: {'productId': '123'});

// Navigate from any context
GoRouter.of(context).go('/login');
```

## go_router 17.x Features

| Feature | Since | Usage |
|---|---|---|
| `caseSensitive: true` | 15.0 | Default — URLs are case-sensitive |
| `onEnter` | 16.3 | Callback on route enter (analytics, prefetch) |
| `onExit` | 14.0 | Callback on route exit (confirm discard) |
| `onException` | 14.0 | Global error handler |
| `preload: true` | 14.5 | Preload StatefulShellRoute branch |
| Relative navigation | 14.6 | `context.go('./details')` |
| Fragment support | 14.7 | `state.uri.fragment` |
| `RelativeGoRouteData` | 16.2 | Reusable relative routes with go_router_builder |
