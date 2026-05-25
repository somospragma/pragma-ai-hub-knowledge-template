---
name: flutter-navigation-strategy
description: >
  Implements declarative navigation in Flutter using go_router 17.x. Use this skill when asking about routing, navigation, redirect guards, nested navigation, tab navigation, page transitions, ShellRoute, cross-module navigation, Mediator pattern for navigation, or how to navigate between screens. Triggers on GoRouter setup, context.go, context.push, redirect, ShellRoute, StatefulShellRoute, AppNavigator, PopScope, or any navigation request. For deep link platform configuration and implementation, see the flutter-deep-link-strategy skill. Stack: go_router, go_router_builder, build_runner. Requires Flutter >=3.29 / Dart >=3.7.
commands:
  - setup-navigation-strategy
inputs:
  - name: action
    description: Action to perform (implement, audit, add-route). "implement" generates the full router setup with auth redirect and shell, "audit" checks existing navigation for anti-patterns (Navigator 1.0 usage, hardcoded paths, missing redirects), "add-route" adds a new route to an existing router configuration.
    required: true
  - name: target
    description: Path to the router file or app directory (e.g. lib/app/router/ for implement, lib/ for audit).
    required: true
  - name: pattern
    description: Navigation pattern to implement (shell-tabs, shell-drawer, mediator, type-safe-routes, auth-redirect). Use when action is "implement" to specify the architecture.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.2"
---

# Navigation Strategy — go_router 17.x

Declarative, type-safe navigation for Flutter. Official Flutter team package.

---

## Setup

```yaml
dependencies:
  go_router: ^17.2.2

dev_dependencies:
  go_router_builder: ^4.3.0   # Type-safe routes (optional but recommended)
  build_runner: ^2.15.0
```

> **Why go_router?** Official Flutter package, first-class deep linking support,
> `StatefulShellRoute` for stateful tabs, async redirect, `onEnter`/`onExit` callbacks,
> type-safe routes via code generation, and case-sensitive URLs (v15+).

---

## Router Definition

```dart
// lib/app/router/app_router.dart
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AppRouter {
  AppRouter(this._authNotifier);
  final AuthNotifier _authNotifier;

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: kDebugMode,
    caseSensitive: true,          // Default since v15 — URLs are case-sensitive
    refreshListenable: _authNotifier,
    redirect: _globalRedirect,
    observers: [getIt<AnalyticsRouteObserver>()],
    onException: (context, state, router) {
      router.go('/error', extra: state.uri.toString());
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/error',
        builder: (context, state) => ErrorPage(
          uri: state.extra as String?,
        ),
      ),
      _shellRoute,
    ],
  );

  StatefulShellRoute get _shellRoute => StatefulShellRoute.indexedStack(
    // Use pageBuilder (not builder) to control the shell transition
    pageBuilder: (context, state, navigationShell) => NoTransitionPage(
      child: ShellPage(navigationShell: navigationShell),
    ),
    branches: [
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomePage(),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/products',
            name: 'products',
            builder: (context, state) => const ProductListPage(),
            routes: [
              GoRoute(
                path: ':productId',
                name: 'productDetail',
                builder: (context, state) => ProductDetailPage(
                  productId: state.pathParameters['productId']!,
                  fromSearch: state.uri.queryParameters['fromSearch'] == 'true',
                  scrollToSection: state.uri.fragment, // fragment support v14.7+
                ),
                onExit: (context, state) async {
                  // Confirm exit if there are unsaved changes
                  return true;
                },
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/cart',
            name: 'cart',
            builder: (context, state) => const CartPage(),
          ),
        ],
      ),
      StatefulShellBranch(
        preload: true, // Pre-load this branch on startup (v14.5+)
        routes: [
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage(),
            routes: [
              GoRoute(
                path: 'settings',
                name: 'settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  Future<String?> _globalRedirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final isLoggedIn = _authNotifier.isAuthenticated;
    final isAuthRoute = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';

    if (!isLoggedIn && !isAuthRoute) return '/login';
    if (isLoggedIn && isAuthRoute) return '/home';
    return null; // No redirect
  }
}
```

---

## Auth Redirect — Listenable Pattern

```dart
// lib/app/router/auth_notifier.dart
@lazySingleton
class AuthNotifier extends ChangeNotifier {
  AuthNotifier(this._tokenRepository);
  final TokenRepository _tokenRepository;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> checkAuth() async {
    final token = await _tokenRepository.getAccessToken();
    final wasAuthenticated = _isAuthenticated;
    _isAuthenticated = token != null;
    if (wasAuthenticated != _isAuthenticated) notifyListeners();
  }

  Future<void> logout() async {
    await _tokenRepository.clearTokens();
    _isAuthenticated = false;
    notifyListeners(); // go_router re-evaluates all redirects
  }
}
```

> go_router uses `redirect` + `refreshListenable` instead of route guards.
> When `AuthNotifier` calls `notifyListeners()`, go_router re-evaluates all redirects automatically.

---

## Navigation API

```dart
// Declarative — replaces the entire stack (use for deep linking)
context.go('/products/abc');

// Push onto the stack
context.push('/products/abc');

// Push with in-memory extra data (not serialized to URL — in-app only)
context.push('/products/abc', extra: productModel);

// Named navigation
context.goNamed('productDetail', pathParameters: {'productId': 'abc'});
context.pushNamed(
  'productDetail',
  pathParameters: {'productId': 'abc'},
  queryParameters: {'fromSearch': 'true'},
);

// Replace current route (keeps same page key)
context.replace('/home');

// Replace and push a new route
context.pushReplacement('/home');

// Pop
context.pop();

// Pop with result
context.pop<bool>(true);

// Guard before popping
if (context.canPop()) context.pop();

// Relative navigation (v14.6+)
context.go('./details'); // Relative to current path

// Navigate to a specific branch in StatefulShellRoute
navigationShell.goBranch(1); // Switch to tab index 1
```

---

## Tab Navigation with StatefulShellRoute

```dart
// lib/src/features/shell/presentation/pages/shell_page.dart
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
        // Reset branch to its initial location when tapping the current tab
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

> `initialLocation: index == navigationShell.currentIndex` resets the branch to its
> root when the user taps the already-active tab. Each branch maintains its own navigation stack.

---

## ShellRoute vs StatefulShellRoute

| Scenario | Use |
|---|---|
| Shared scaffold/AppBar without tabs | `ShellRoute` |
| Bottom navigation with persistent tab state | `StatefulShellRoute.indexedStack` |
| Deep link must activate a specific tab | `StatefulShellRoute` — route in the correct branch |
| Deep link opens a screen above the shell | Route outside the shell (root level) |
| Drawer navigation without tab state | `ShellRoute` |

### ShellRoute — shared scaffold without tabs

Use `ShellRoute` when you need a persistent wrapper (AppBar, Drawer, FAB) around a
set of routes but do **not** need per-tab state preservation.

```dart
ShellRoute(
  // pageBuilder gives you transition control over the shell itself
  pageBuilder: (context, state, child) => NoTransitionPage(
    child: MainScaffold(child: child),
  ),
  routes: [
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardPage(),
    ),
    GoRoute(
      path: '/reports',
      builder: (context, state) => const ReportsPage(),
      routes: [
        GoRoute(
          path: ':reportId',
          builder: (context, state) => ReportDetailPage(
            reportId: state.pathParameters['reportId']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
)

// lib/src/features/shell/presentation/pages/main_scaffold.dart
class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My App')),
    drawer: const AppDrawer(),
    body: child,  // go_router swaps this on navigation
    floatingActionButton: const GlobalFab(),
  );
}
```

> With `ShellRoute`, navigating between `/dashboard` and `/reports` replaces the
> `child` widget but keeps `MainScaffold` alive. The back stack is shared — there
> is no per-route state preservation.

---

## Cross-Module Navigation with Mediator

In modular architectures, feature modules must remain independent — a `products`
module should not import `go_router` or know about the `checkout` module's routes.
The Mediator pattern solves this by placing the navigation contract in a shared
layer that both modules depend on.

### The pattern

```
┌─────────────────────────────────────────────────────┐
│  lib/src/core/navigation/                           │
│    app_navigator.dart   ← abstract interface class  │
│    app_navigator_impl.dart ← go_router impl         │
└─────────────────────────────────────────────────────┘
         ↑ depends on              ↑ depends on
┌──────────────────┐      ┌──────────────────────────┐
│  products module │      │  app_router.dart          │
│  (calls navigate)│      │  (registers impl via DI)  │
└──────────────────┘      └──────────────────────────┘
```

### 1. Define the navigation contract (core layer)

```dart
// lib/src/core/navigation/app_navigator.dart

/// Navigation contract — feature modules depend only on this interface.
/// No module imports go_router or knows about other modules' routes.
abstract interface class AppNavigator {
  // Auth
  void goLogin();
  void goHome();

  // Products
  void goProductDetail(String productId, {bool fromSearch = false});
  void goProductList();

  // Checkout
  void goCheckout({required String orderId});
  Future<bool?> goCheckoutConfirmation({required double amount});

  // Profile
  void goProfile();
  void goSettings();

  // Generic
  void goBack();
  bool canGoBack();
}
```

### 2. Implement with go_router (app layer)

```dart
// lib/src/core/navigation/app_navigator_impl.dart
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';
import 'app_navigator.dart';

@LazySingleton(as: AppNavigator)
class AppNavigatorImpl implements AppNavigator {
  AppNavigatorImpl(this._router);
  final GoRouter _router;

  @override
  void goLogin() => _router.go('/login');

  @override
  void goHome() => _router.go('/home');

  @override
  void goProductDetail(String productId, {bool fromSearch = false}) =>
      _router.go('/products/$productId?fromSearch=$fromSearch');

  @override
  void goProductList() => _router.go('/products');

  @override
  void goCheckout({required String orderId}) =>
      _router.push('/checkout/$orderId');

  @override
  Future<bool?> goCheckoutConfirmation({required double amount}) =>
      _router.push<bool>('/checkout/confirm?amount=$amount');

  @override
  void goProfile() => _router.go('/profile');

  @override
  void goSettings() => _router.push('/profile/settings');

  @override
  void goBack() => _router.pop();

  @override
  bool canGoBack() => _router.canPop();
}
```

### 3. Register in DI

```dart
// lib/src/core/di/navigation_module.dart
@module
abstract class NavigationModule {
  @lazySingleton
  GoRouter router(AppRouter appRouter) => appRouter.router;
}

// AppNavigatorImpl is registered automatically via @LazySingleton(as: AppNavigator)
```

### 4. Use from any feature module

Feature modules receive `AppNavigator` via injection — they never import go_router
or reference other modules' pages directly.

```dart
// lib/src/features/products/presentation/bloc/product_bloc.dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  ProductBloc(this._getProduct, this._navigator) : super(...) {
    on<ProductTapped>(_onProductTapped);
  }

  final GetProductUseCase _getProduct;
  final AppNavigator _navigator;  // ← injected interface, not go_router

  void _onProductTapped(ProductTapped event, Emitter<ProductState> emit) {
    _navigator.goProductDetail(event.productId);
  }
}
```

```dart
// lib/src/features/checkout/presentation/pages/cart_page.dart
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final navigator = getIt<AppNavigator>();

    return Scaffold(
      body: ...,
      bottomNavigationBar: FilledButton(
        onPressed: () async {
          // Navigate to checkout and wait for result
          final confirmed = await navigator.goCheckoutConfirmation(amount: total);
          if (confirmed == true) navigator.goHome();
        },
        child: const Text('Proceed to Checkout'),
      ),
    );
  }
}
```

### 5. Cross-module navigation triggered by a BLoC event

When a business event in one module must navigate to another module's screen,
dispatch through the Mediator — never import the target module.

```dart
// lib/src/features/auth/presentation/bloc/auth_bloc.dart
@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._login, this._navigator) : super(const AuthState.initial()) {
    on<LoginSubmitted>(_onLoginSubmitted);
  }

  final LoginUseCase _login;
  final AppNavigator _navigator;

  Future<void> _onLoginSubmitted(
    LoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState.loading());
    final result = await _login(LoginParams(
      email: event.email,
      password: event.password,
    ));
    result.fold(
      (failure) => emit(AuthState.failure(failure)),
      (_) {
        emit(const AuthState.success());
        _navigator.goHome();  // ← navigates to home without knowing HomeRoute
      },
    );
  }
}
```

> **Rule:** Feature modules only import `AppNavigator` from `core/navigation`.
> They never import `go_router`, `AppRouter`, or any other module's pages.
> The `AppNavigatorImpl` in the app layer is the only place that knows the actual routes.

---

## Back Navigation — PopScope

```dart
// Intercept back navigation (replaces WillPopScope, removed in Flutter 3.22)
PopScope(
  canPop: false, // Prevent default back
  onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    final shouldLeave = await _showUnsavedChangesDialog(context);
    if (shouldLeave && context.mounted) context.pop();
  },
  child: const MyFormPage(),
)
```

> Use `onExit` on `GoRoute` for route-level exit confirmation instead of wrapping
> every page in `PopScope`.

```dart
GoRoute(
  path: '/edit/:id',
  builder: (context, state) => const EditPage(),
  onExit: (context, state) async {
    // Return false to block navigation away from this route
    final bloc = context.read<EditBloc>();
    if (!bloc.state.hasUnsavedChanges) return true;
    return await showUnsavedChangesDialog(context) ?? false;
  },
),
```

---

## MaterialApp Integration

```dart
// lib/app/app.dart
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'My App',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    routerConfig: getIt<AppRouter>().router,
  );
}
```

---

## Type-Safe Routes (go_router_builder)

```dart
// lib/app/router/routes.dart
import 'package:go_router/go_router.dart';
part 'routes.g.dart';

@TypedGoRoute<HomeRoute>(path: '/home')
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const HomePage();
}

@TypedGoRoute<ProductDetailRoute>(path: '/products/:productId')
class ProductDetailRoute extends GoRouteData with $ProductDetailRoute {
  const ProductDetailRoute({
    required this.productId,
    this.fromSearch = false,
  });
  final String productId;
  final bool fromSearch;

  @override
  Widget build(BuildContext context, GoRouterState state) => ProductDetailPage(
    productId: productId,
    fromSearch: fromSearch,
  );
}

// Relative routes (v16.2+) — reusable in different parts of the route tree
@TypedRelativeGoRoute<DetailsRoute>(path: 'details')
class DetailsRoute extends RelativeGoRouteData with $DetailsRoute {
  const DetailsRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const DetailsPage();
}
```

```dart
// Type-safe navigation
const ProductDetailRoute(productId: 'abc', fromSearch: true).go(context);
const ProductDetailRoute(productId: 'abc').push(context);
const ProductDetailRoute(productId: 'abc').location; // '/products/abc'

// Relative navigation (v16.2+)
const DetailsRoute().goRelative(context);
const DetailsRoute().pushRelative(context);
```

```bash
# Generate routes
dart run build_runner build --delete-conflicting-outputs
```

---

## Error Handling

```dart
GoRouter(
  // onException — full control over unmatched routes and errors
  onException: (context, state, router) {
    router.go('/error', extra: state.uri.toString());
  },

  // errorBuilder — fallback widget for unhandled errors
  errorBuilder: (context, state) => ErrorPage(
    error: state.error,
    uri: state.uri.toString(),
  ),
);
```

---

## What NEVER to Do

```dart
// ❌ FORBIDDEN — Navigator 1.0 mixed with go_router
Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyPage()));

// ❌ FORBIDDEN — context.go when you want to push (go replaces the stack)
context.go('/details'); // Use context.push if you want to add to the stack

// ❌ FORBIDDEN — extra for deep links (not serialized to URL)
// extra is in-memory only. It does not survive URL-based navigation.
context.go('/product', extra: productModel); // Does not work as a deep link

// ❌ FORBIDDEN — hardcoded paths scattered across the codebase
context.go('/app/products/${product.id}/reviews'); // Fragile — use named or type-safe routes

// ❌ FORBIDDEN — synchronous storage access in redirect
redirect: (context, state) {
  final token = prefs.getString('token'); // ❌ SharedPrefs sync in redirect
  return null;
},

// ❌ FORBIDDEN — WillPopScope (removed in Flutter 3.22)
WillPopScope(onWillPop: () async => true, child: ...); // Use PopScope instead

// ❌ FORBIDDEN — mixing case in route paths (case-sensitive since v15)
context.go('/Products/abc'); // Will not match '/products/:id'
```

---

## Reference Files

- `references/transitions.md` — Custom page transitions, `CustomTransitionPage`, `NoTransitionPage`, dialog routes
