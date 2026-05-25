# Deep Links — Implementation Guide

Ver también: `flutter-navigation-strategy` skill for foundational patterns.

## Descripción General

This skill covers comprehensive deep links implementation in Flutter using go_router 17.2.2 following clean architecture principles. Includes URL parsing, route guards, dynamic routing, and error handling.

## Principios Clave

1. Follow Clean Architecture layer separation
2. Use Either<Failure, T> for error handling with fpdart
3. Register dependencies via GetIt + Injectable
4. Implement route guards and authentication checks
5. Handle dynamic parameters and query strings
6. Write unit tests for all business logic
7. Use go_router for declarative routing

## Stack Recomendado

- Dart 3.5+ / Flutter 3.24+
- go_router 17.2.2 for routing and deep links
- flutter_bloc 9.1.1 for state management
- GetIt 9.2.1 + Injectable 3.0.0 for DI
- Freezed 3.2.5 for data classes
- fpdart 1.2.0 for functional programming
- Mocktail 1.0.5 for testing

## Dependencias

```yaml
dependencies:
  go_router: ^17.2.2
  flutter_bloc: ^9.1.1
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
  fpdart: ^1.2.0

dev_dependencies:
  build_runner: ^2.14.1
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
  mocktail: ^1.0.5
```

## Arquitectura de Deep Links

### 1. Router Configuration (Presentation Layer)

El proyecto puede tener distintas estructuras de shell. El guide cubre los dos casos más comunes:

- **`ShellRoute`** — shell simple (drawer, scaffold compartido, etc.)
- **`StatefulShellRoute`** — bottom navigation bar con tabs persistentes (el más frecuente en apps reales)

#### Caso A: ShellRoute simple

```dart
// lib/core/router/app_router.dart
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@injectable
class AppRouter {
  final AuthenticationRepository _authRepository;

  AppRouter(this._authRepository);

  late final GoRouter router = GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: true,
    redirect: _handleRedirect,
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const LoginPage(),
      ),

      // Shell simple: comparte Scaffold/AppBar entre rutas
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (_, __) => const HomePage(),
          ),
          GoRoute(
            path: '/product/:productId',
            name: 'product',
            builder: (context, state) {
              final productId = state.pathParameters['productId']!;
              final variant = state.uri.queryParameters['variant'];
              return BlocProvider(
                create: (_) => getIt<ProductBloc>()
                  ..add(LoadProduct(productId, variant: variant)),
                child: const ProductPage(),
              );
            },
          ),
          GoRoute(
            path: '/profile/:userId',
            name: 'profile',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              final tab = state.uri.queryParameters['tab'];
              return ProfilePage(userId: userId, initialTab: tab);
            },
          ),
          GoRoute(
            path: '/content/:type/:id',
            name: 'dynamicContent',
            builder: (context, state) => DynamicContentPage(
              contentType: state.pathParameters['type']!,
              contentId: state.pathParameters['id']!,
              metadata: state.extra as Map<String, dynamic>?,
            ),
          ),
          GoRoute(
            path: '/share/:token',
            name: 'share',
            builder: (context, state) {
              final token = state.pathParameters['token']!;
              return BlocProvider(
                create: (_) => getIt<ShareBloc>()
                  ..add(ProcessShareToken(token)),
                child: const SharePage(),
              );
            },
          ),
        ],
      ),

      GoRoute(
        path: '/error',
        name: 'error',
        builder: (context, state) => ErrorPage(
          message: state.extra as String?,
        ),
      ),
    ],
    errorBuilder: (context, state) => ErrorPage(
      message: 'Route not found: ${state.matchedLocation}',
    ),
  );

  String? _handleRedirect(BuildContext context, GoRouterState state) {
    final isAuthenticated = _authRepository.isAuthenticated;
    final isOnAuthPage = state.matchedLocation.startsWith('/login');
    final isOnSplash = state.matchedLocation == '/splash';

    if (!isAuthenticated && !isOnAuthPage && !isOnSplash) {
      return '/login';
    }
    if (isAuthenticated && isOnAuthPage) {
      return '/home';
    }
    return null;
  }
}
```

#### Caso B: StatefulShellRoute con Bottom Navigation (más común)

Cuando el proyecto tiene bottom navigation bar con tabs persistentes, un deep link debe activar la tab correcta y navegar dentro de ella sin perder el estado de las otras tabs.

```dart
// lib/core/router/app_router.dart
@injectable
class AppRouter {
  final AuthenticationRepository _authRepository;

  AppRouter(this._authRepository);

  late final GoRouter router = GoRouter(
    initialLocation: '/home',
    debugLogDiagnostics: true,
    redirect: _handleRedirect,
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const LoginPage(),
      ),

      // StatefulShellRoute: mantiene estado de cada tab
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainScaffold(navigationShell: navigationShell),
        branches: [
          // Tab 0 — Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                builder: (_, __) => const HomePage(),
                routes: [
                  // Deep link dentro de la tab Home
                  GoRoute(
                    path: 'product/:productId',
                    name: 'product',
                    builder: (context, state) {
                      final productId = state.pathParameters['productId']!;
                      final variant = state.uri.queryParameters['variant'];
                      return BlocProvider(
                        create: (_) => getIt<ProductBloc>()
                          ..add(LoadProduct(productId, variant: variant)),
                        child: const ProductPage(),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'content/:type/:id',
                    name: 'dynamicContent',
                    builder: (context, state) => DynamicContentPage(
                      contentType: state.pathParameters['type']!,
                      contentId: state.pathParameters['id']!,
                      metadata: state.extra as Map<String, dynamic>?,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Tab 1 — Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile/:userId',
                name: 'profile',
                builder: (context, state) => ProfilePage(
                  userId: state.pathParameters['userId']!,
                  initialTab: state.uri.queryParameters['tab'],
                ),
              ),
            ],
          ),

          // Tab 2 — Share / Explore
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/share/:token',
                name: 'share',
                builder: (context, state) {
                  final token = state.pathParameters['token']!;
                  return BlocProvider(
                    create: (_) => getIt<ShareBloc>()
                      ..add(ProcessShareToken(token)),
                    child: const SharePage(),
                  );
                },
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/error',
        name: 'error',
        builder: (context, state) => ErrorPage(
          message: state.extra as String?,
        ),
      ),
    ],
    errorBuilder: (context, state) => ErrorPage(
      message: 'Route not found: ${state.matchedLocation}',
    ),
  );

  String? _handleRedirect(BuildContext context, GoRouterState state) {
    final isAuthenticated = _authRepository.isAuthenticated;
    final isOnAuthPage = state.matchedLocation.startsWith('/login');
    final isOnSplash = state.matchedLocation == '/splash';

    if (!isAuthenticated && !isOnAuthPage && !isOnSplash) {
      return '/login';
    }
    if (isAuthenticated && isOnAuthPage) {
      return '/home';
    }
    return null;
  }
}

// lib/presentation/shell/main_scaffold.dart
// Shell widget que recibe el navigationShell de StatefulShellRoute
class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => _onTabSelected(index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.share), label: 'Share'),
        ],
      ),
    );
  }

  void _onTabSelected(int index) {
    // goBranch mantiene el estado de la tab y respeta el back stack
    navigationShell.goBranch(
      index,
      // Si el usuario toca la tab activa, vuelve al root de esa tab
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}
```

#### Cuándo usar cada uno

| Escenario | Recomendación |
|---|---|
| Scaffold/AppBar compartido sin tabs | `ShellRoute` |
| Bottom navigation con tabs persistentes | `StatefulShellRoute.indexedStack` |
| Deep link debe activar tab específica | `StatefulShellRoute` — la ruta pertenece a la branch correcta |
| Deep link abre pantalla sobre el shell | Ruta fuera del shell (nivel raíz) |

### 2. Deep Link Domain Layer

```dart
// lib/features/deep_link/domain/entities/deep_link.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'deep_link.freezed.dart';

@freezed
class DeepLink with _$DeepLink {
  const factory DeepLink({
    required String path,
    required Map<String, String> parameters,
    required Map<String, String> queryParameters,
    String? fragment,
    Map<String, dynamic>? metadata,
  }) = _DeepLink;
}

@freezed
class DeepLinkResult with _$DeepLinkResult {
  const factory DeepLinkResult.success({
    required String route,
    Map<String, String>? pathParameters,
    Map<String, String>? queryParameters,
    Object? extra,
  }) = DeepLinkSuccess;

  const factory DeepLinkResult.requiresAuth({
    required String originalPath,
  }) = DeepLinkRequiresAuth;

  const factory DeepLinkResult.error({
    required String message,
    String? fallbackRoute,
  }) = DeepLinkError;
}

// lib/features/deep_link/domain/failures/deep_link_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'deep_link_failure.freezed.dart';

@freezed
class DeepLinkFailure with _$DeepLinkFailure {
  const factory DeepLinkFailure.invalidFormat({
    required String message,
  }) = InvalidFormatFailure;

  const factory DeepLinkFailure.notFound({
    required String resource,
  }) = NotFoundFailure;

  const factory DeepLinkFailure.unauthorized({
    required String message,
  }) = UnauthorizedFailure;

  const factory DeepLinkFailure.network({
    required String message,
  }) = NetworkFailure;

  const factory DeepLinkFailure.unknown({
    required String message,
  }) = UnknownFailure;
}

// lib/features/deep_link/domain/repositories/deep_link_repository.dart
import 'package:fpdart/fpdart.dart';

abstract interface class DeepLinkRepository {
  Future<Either<DeepLinkFailure, DeepLinkResult>> processDeepLink(String url);
  Future<Either<DeepLinkFailure, bool>> validateDeepLink(String url);
  Future<Either<DeepLinkFailure, String>> generateShareLink(String route, Map<String, dynamic> data);
}

// lib/features/deep_link/domain/usecases/process_deep_link_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class ProcessDeepLinkUseCase {
  final DeepLinkRepository _repository;

  ProcessDeepLinkUseCase(this._repository);

  Future<Either<DeepLinkFailure, DeepLinkResult>> call(String url) async {
    return await _repository.processDeepLink(url);
  }
}
```

### 3. Data Layer Implementation

```dart
// lib/features/deep_link/data/repositories/deep_link_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: DeepLinkRepository)
class DeepLinkRepositoryImpl implements DeepLinkRepository {
  final DeepLinkDataSource _dataSource;
  final AuthenticationRepository _authRepository;

  DeepLinkRepositoryImpl(this._dataSource, this._authRepository);

  @override
  Future<Either<DeepLinkFailure, DeepLinkResult>> processDeepLink(String url) async {
    try {
      final uri = Uri.parse(url);
      
      // Validate URL format
      if (!_isValidDeepLink(uri)) {
        return Left(DeepLinkFailure.invalidFormat(
          message: 'Invalid deep link format: $url',
        ));
      }

      // Check if route requires authentication
      if (_requiresAuthentication(uri.path) && !_authRepository.isAuthenticated) {
        return Right(DeepLinkResult.requiresAuth(originalPath: url));
      }

      // Process different link types
      return await _processLinkByType(uri);
    } catch (e) {
      return Left(DeepLinkFailure.unknown(
        message: 'Failed to process deep link: $e',
      ));
    }
  }

  Future<Either<DeepLinkFailure, DeepLinkResult>> _processLinkByType(Uri uri) async {
    final path = uri.path;
    
    // Product links
    if (path.startsWith('/product/')) {
      return await _processProductLink(uri);
    }
    
    // Share links
    if (path.startsWith('/share/')) {
      return await _processShareLink(uri);
    }
    
    // Profile links
    if (path.startsWith('/profile/')) {
      return await _processProfileLink(uri);
    }
    
    // Dynamic content
    if (path.startsWith('/content/')) {
      return await _processDynamicContentLink(uri);
    }

    // Default handling
    return Right(DeepLinkResult.success(
      route: path,
      queryParameters: uri.queryParameters,
    ));
  }

  Future<Either<DeepLinkFailure, DeepLinkResult>> _processProductLink(Uri uri) async {
    final productId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
    
    if (productId == null) {
      return Left(DeepLinkFailure.invalidFormat(
        message: 'Product ID is required in product link',
      ));
    }

    // Validate product exists
    final productExistsResult = await _dataSource.validateProduct(productId);
    
    return productExistsResult.fold(
      (failure) => Left(failure),
      (exists) {
        if (!exists) {
          return Right(DeepLinkResult.error(
            message: 'Product not found',
            fallbackRoute: '/home',
          ));
        }

        return Right(DeepLinkResult.success(
          route: '/product/$productId',
          queryParameters: uri.queryParameters,
        ));
      },
    );
  }

  Future<Either<DeepLinkFailure, DeepLinkResult>> _processShareLink(Uri uri) async {
    final token = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
    
    if (token == null) {
      return Left(DeepLinkFailure.invalidFormat(
        message: 'Share token is required',
      ));
    }

    // Validate and decode share token
    final shareDataResult = await _dataSource.validateShareToken(token);
    
    return shareDataResult.fold(
      (failure) => Left(failure),
      (shareData) {
        if (shareData == null) {
          return Right(DeepLinkResult.error(
            message: 'Share link expired or invalid',
            fallbackRoute: '/home',
          ));
        }

        return Right(DeepLinkResult.success(
          route: '/share/$token',
          extra: shareData,
        ));
      },
    );
  }

  Future<Either<DeepLinkFailure, DeepLinkResult>> _processProfileLink(Uri uri) async {
    final userId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
    
    if (userId == null) {
      return Left(DeepLinkFailure.invalidFormat(
        message: 'User ID is required in profile link',
      ));
    }

    return Right(DeepLinkResult.success(
      route: '/profile/$userId',
      queryParameters: uri.queryParameters,
    ));
  }

  Future<Either<DeepLinkFailure, DeepLinkResult>> _processDynamicContentLink(Uri uri) async {
    if (uri.pathSegments.length < 3) {
      return Left(DeepLinkFailure.invalidFormat(
        message: 'Dynamic content link requires type and ID',
      ));
    }

    final type = uri.pathSegments[1];
    final id = uri.pathSegments[2];

    return Right(DeepLinkResult.success(
      route: '/content/$type/$id',
      queryParameters: uri.queryParameters,
    ));
  }

  @override
  Future<Either<DeepLinkFailure, bool>> validateDeepLink(String url) async {
    try {
      final uri = Uri.parse(url);
      return Right(_isValidDeepLink(uri));
    } catch (e) {
      return Left(DeepLinkFailure.invalidFormat(
        message: 'Invalid URL format: $e',
      ));
    }
  }

  @override
  Future<Either<DeepLinkFailure, String>> generateShareLink(
    String route, 
    Map<String, dynamic> data,
  ) async {
    return await _dataSource.generateShareLink(route, data);
  }

  bool _isValidDeepLink(Uri uri) {
    return uri.scheme.isNotEmpty && uri.host.isNotEmpty;
  }

  bool _requiresAuthentication(String path) {
    final publicPaths = ['/login', '/register', '/forgot-password', '/share'];
    return !publicPaths.any((publicPath) => path.startsWith(publicPath));
  }
}

// lib/features/deep_link/data/datasources/deep_link_data_source.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:dio/dio.dart';

@injectable
class DeepLinkDataSource {
  final Dio _dio;

  DeepLinkDataSource(this._dio);

  Future<Either<DeepLinkFailure, bool>> validateProduct(String productId) async {
    try {
      final response = await _dio.get('/products/$productId/exists');
      return Right(response.statusCode == 200);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Right(false);
      }
      return Left(DeepLinkFailure.network(
        message: 'Failed to validate product: ${e.message}',
      ));
    } catch (e) {
      return Left(DeepLinkFailure.unknown(
        message: 'Unexpected error validating product: $e',
      ));
    }
  }

  Future<Either<DeepLinkFailure, Map<String, dynamic>?>> validateShareToken(String token) async {
    try {
      final response = await _dio.get('/share/validate/$token');
      return Right(response.data as Map<String, dynamic>?);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 410) {
        return const Right(null); // Token expired or not found
      }
      return Left(DeepLinkFailure.network(
        message: 'Failed to validate share token: ${e.message}',
      ));
    } catch (e) {
      return Left(DeepLinkFailure.unknown(
        message: 'Unexpected error validating share token: $e',
      ));
    }
  }

  Future<Either<DeepLinkFailure, String>> generateShareLink(
    String route, 
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post('/share/generate', data: {
        'route': route,
        'data': data,
      });
      
      final shareUrl = response.data['share_url'] as String;
      return Right(shareUrl);
    } on DioException catch (e) {
      return Left(DeepLinkFailure.network(
        message: 'Failed to generate share link: ${e.message}',
      ));
    } catch (e) {
      return Left(DeepLinkFailure.unknown(
        message: 'Unexpected error generating share link: $e',
      ));
    }
  }
}
```

### 4. BLoC Implementation

```dart
// lib/features/deep_link/presentation/bloc/deep_link_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:go_router/go_router.dart';
import 'package:fpdart/fpdart.dart';

part 'deep_link_bloc.freezed.dart';
part 'deep_link_event.dart';
part 'deep_link_state.dart';

@injectable
class DeepLinkBloc extends Bloc<DeepLinkEvent, DeepLinkState> {
  final ProcessDeepLinkUseCase _processDeepLinkUseCase;
  final GoRouter _router;

  DeepLinkBloc(this._processDeepLinkUseCase, this._router) 
      : super(const DeepLinkState.initial()) {
    on<ProcessDeepLinkEvent>(_onProcessDeepLink);
    on<ResetDeepLinkEvent>(_onResetDeepLink);
  }

  Future<void> _onProcessDeepLink(
    ProcessDeepLinkEvent event,
    Emitter<DeepLinkState> emit,
  ) async {
    emit(const DeepLinkState.loading());

    final result = await _processDeepLinkUseCase(event.url);

    result.fold(
      (failure) => emit(DeepLinkState.error(_mapFailureToMessage(failure))),
      (deepLinkResult) {
        deepLinkResult.when(
          success: (route, pathParams, queryParams, extra) {
            try {
              _router.go(route, extra: extra);
              emit(const DeepLinkState.success());
            } catch (e) {
              emit(DeepLinkState.error('Navigation failed: $e'));
            }
          },
          requiresAuth: (originalPath) {
            _router.go('/login', extra: {'redirect': originalPath});
            emit(const DeepLinkState.requiresAuth());
          },
          error: (message, fallbackRoute) {
            if (fallbackRoute != null) {
              try {
                _router.go(fallbackRoute);
              } catch (e) {
                // Fallback to home if fallback route fails
                _router.go('/home');
              }
            }
            emit(DeepLinkState.error(message));
          },
        );
      },
    );
  }

  void _onResetDeepLink(
    ResetDeepLinkEvent event,
    Emitter<DeepLinkState> emit,
  ) {
    emit(const DeepLinkState.initial());
  }

  String _mapFailureToMessage(DeepLinkFailure failure) {
    return failure.when(
      invalidFormat: (message) => 'Invalid link format: $message',
      notFound: (resource) => '$resource not found',
      unauthorized: (message) => 'Access denied: $message',
      network: (message) => 'Network error: $message',
      unknown: (message) => 'An error occurred: $message',
    );
  }
}

part of 'deep_link_bloc.dart';

@freezed
class DeepLinkEvent with _$DeepLinkEvent {
  const factory DeepLinkEvent.processDeepLink(String url) = ProcessDeepLinkEvent;
  const factory DeepLinkEvent.resetDeepLink() = ResetDeepLinkEvent;
}

part of 'deep_link_bloc.dart';

@freezed
class DeepLinkState with _$DeepLinkState {
  const factory DeepLinkState.initial() = DeepLinkInitial;
  const factory DeepLinkState.loading() = DeepLinkLoading;
  const factory DeepLinkState.success() = DeepLinkSuccess;
  const factory DeepLinkState.requiresAuth() = DeepLinkRequiresAuth;
  const factory DeepLinkState.error(String message) = DeepLinkError;
}
```

### 5. App Integration

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure dependency injection
  await configureDependencies();
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => GetIt.instance<AuthBloc>()),
        BlocProvider(create: (_) => GetIt.instance<DeepLinkBloc>()),
      ],
      child: MaterialApp.router(
        title: 'Deep Link App',
        routerConfig: GetIt.instance<AppRouter>().router,
      ),
    );
  }
}

// lib/core/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async => getIt.init();
```

## Configuración de Plataforma

### Android Configuration

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"
    android:theme="@style/LaunchTheme">
    
    <!-- Standard App Launch -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    
    <!-- Deep Link Intent Filters -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="https"
              android:host="yourapp.com" />
    </intent-filter>
    
    <!-- Custom Scheme -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="yourapp" />
    </intent-filter>
</activity>
```

### iOS Configuration

```xml
<!-- ios/Runner/Info.plist -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>yourapp.com</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>https</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleURLName</key>
        <string>yourapp.custom</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>
        </array>
    </dict>
</array>

<!-- Associated Domains -->
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:yourapp.com</string>
</array>
```

## Testing Strategy

### Unit Tests

```dart
// test/features/deep_link/domain/usecases/process_deep_link_usecase_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockDeepLinkRepository extends Mock implements DeepLinkRepository {}

void main() {
  late ProcessDeepLinkUseCase useCase;
  late MockDeepLinkRepository mockRepository;

  setUp(() {
    mockRepository = MockDeepLinkRepository();
    useCase = ProcessDeepLinkUseCase(mockRepository);
  });

  group('ProcessDeepLinkUseCase', () {
    test('should return success when deep link is valid', () async {
      // Arrange
      const url = 'https://yourapp.com/product/123';
      const expectedResult = DeepLinkResult.success(
        route: '/product/123',
      );
      
      when(() => mockRepository.processDeepLink(url))
          .thenAnswer((_) async => const Right(expectedResult));

      // Act
      final result = await useCase(url);

      // Assert
      expect(result, const Right(expectedResult));
      verify(() => mockRepository.processDeepLink(url)).called(1);
    });

    test('should return failure when deep link is invalid', () async {
      // Arrange
      const url = 'invalid-url';
      const failure = DeepLinkFailure.invalidFormat(
        message: 'Invalid deep link format',
      );
      
      when(() => mockRepository.processDeepLink(url))
          .thenAnswer((_) async => const Left(failure));

      // Act
      final result = await useCase(url);

      // Assert
      expect(result, const Left(failure));
    });

    test('should return requiresAuth when user is not authenticated', () async {
      // Arrange
      const url = 'https://yourapp.com/profile/123';
      const expectedResult = DeepLinkResult.requiresAuth(
        originalPath: url,
      );
      
      when(() => mockRepository.processDeepLink(url))
          .thenAnswer((_) async => const Right(expectedResult));

      // Act
      final result = await useCase(url);

      // Assert
      expect(result, const Right(expectedResult));
    });
  });
}

// test/features/deep_link/presentation/bloc/deep_link_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';

class MockProcessDeepLinkUseCase extends Mock implements ProcessDeepLinkUseCase {}
class MockGoRouter extends Mock implements GoRouter {}

void main() {
  late DeepLinkBloc bloc;
  late MockProcessDeepLinkUseCase mockUseCase;
  late MockGoRouter mockRouter;

  setUp(() {
    mockUseCase = MockProcessDeepLinkUseCase();
    mockRouter = MockGoRouter();
    bloc = DeepLinkBloc(mockUseCase, mockRouter);
  });

  group('DeepLinkBloc', () {
    blocTest<DeepLinkBloc, DeepLinkState>(
      'emits [loading, success] when deep link is processed successfully',
      build: () {
        when(() => mockUseCase(any())).thenAnswer(
          (_) async => const Right(DeepLinkResult.success(route: '/product/123')),
        );
        when(() => mockRouter.go(any(), extra: any(named: 'extra')))
            .thenReturn(null);
        return bloc;
      },
      act: (bloc) => bloc.add(const DeepLinkEvent.processDeepLink('https://app.com/product/123')),
      expect: () => [
        const DeepLinkState.loading(),
        const DeepLinkState.success(),
      ],
    );

    blocTest<DeepLinkBloc, DeepLinkState>(
      'emits [loading, error] when deep link processing fails',
      build: () {
        when(() => mockUseCase(any())).thenAnswer(
          (_) async => const Left(DeepLinkFailure.invalidFormat(message: 'Invalid format')),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(const DeepLinkEvent.processDeepLink('invalid-url')),
      expect: () => [
        const DeepLinkState.loading(),
        const DeepLinkState.error('Invalid link format: Invalid format'),
      ],
    );

    blocTest<DeepLinkBloc, DeepLinkState>(
      'emits [loading, requiresAuth] when authentication is required',
      build: () {
        when(() => mockUseCase(any())).thenAnswer(
          (_) async => const Right(DeepLinkResult.requiresAuth(originalPath: 'https://app.com/profile/123')),
        );
        when(() => mockRouter.go(any(), extra: any(named: 'extra')))
            .thenReturn(null);
        return bloc;
      },
      act: (bloc) => bloc.add(const DeepLinkEvent.processDeepLink('https://app.com/profile/123')),
      expect: () => [
        const DeepLinkState.loading(),
        const DeepLinkState.requiresAuth(),
      ],
    );
  });
}
```

### Integration Tests

```dart
// integration_test/deep_link_test.dart
void main() {
  group('Deep Link Integration Tests', () {
    testWidgets('should navigate to product page from deep link', (tester) async {
      await tester.pumpWidget(MyApp());
      
      // Simulate deep link
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('routeUpdated', {
            'location': '/product/123',
            'state': null,
          }),
        ),
        (data) {},
      );
      
      await tester.pumpAndSettle();
      
      // Verify navigation
      expect(find.byType(ProductPage), findsOneWidget);
    });
  });
}
```

## Mejores Prácticas

### 1. URL Structure
- Use consistent URL patterns: `/resource/:id`
- Include query parameters for filters: `?tab=reviews&sort=date`
- Keep URLs human-readable and SEO-friendly

### 2. Error Handling
- Always provide fallback routes for invalid links
- Show user-friendly error messages
- Log deep link failures for debugging

### 3. Security
- Validate all parameters and tokens
- Implement rate limiting for share links
- Use HTTPS for all deep links

### 4. Performance
- Cache validation results when possible
- Implement lazy loading for deep link destinations
- Use background processing for complex validations

### 5. Analytics
- Track deep link usage and conversion rates
- Monitor failed deep link attempts
- Measure user engagement from different link sources

## Patrones Avanzados

### Dynamic Route Generation

```dart
class DynamicRouteGenerator {
  static GoRoute generateContentRoute(String contentType) {
    return GoRoute(
      path: '/$contentType/:id',
      name: contentType,
      builder: (context, state) {
        return ContentFactory.createPage(
          contentType: contentType,
          id: state.pathParameters['id']!,
          queryParams: state.uri.queryParameters,
        );
      },
    );
  }
}
```

### Link Preview Generation

```dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@freezed
class LinkPreview with _$LinkPreview {
  const factory LinkPreview({
    required String title,
    required String description,
    String? imageUrl,
    Map<String, dynamic>? metadata,
  }) = _LinkPreview;
}

@injectable
class LinkPreviewService {
  final DeepLinkDataSource _dataSource;

  LinkPreviewService(this._dataSource);

  Future<Either<DeepLinkFailure, LinkPreview>> generatePreview(
    String route, 
    Map<String, dynamic> data,
  ) async {
    try {
      final preview = LinkPreview(
        title: _generateTitle(route, data),
        description: _generateDescription(route, data),
        imageUrl: _generateImageUrl(route, data),
        metadata: data,
      );
      
      return Right(preview);
    } catch (e) {
      return Left(DeepLinkFailure.unknown(
        message: 'Failed to generate preview: $e',
      ));
    }
  }

  String _generateTitle(String route, Map<String, dynamic> data) {
    if (route.startsWith('/product/')) {
      return data['productName'] ?? 'Product Details';
    } else if (route.startsWith('/profile/')) {
      return '${data['userName'] ?? 'User'} Profile';
    }
    return 'App Content';
  }

  String _generateDescription(String route, Map<String, dynamic> data) {
    if (route.startsWith('/product/')) {
      return data['productDescription'] ?? 'Check out this amazing product!';
    } else if (route.startsWith('/profile/')) {
      return 'View ${data['userName'] ?? 'user'} profile and activity';
    }
    return 'Discover amazing content in our app';
  }

  String? _generateImageUrl(String route, Map<String, dynamic> data) {
    return data['imageUrl'] as String?;
  }
}
```

Esta implementación completa proporciona una base sólida para manejar deep links en Flutter usando go_router 17.2.2 con arquitectura limpia y mejores prácticas.