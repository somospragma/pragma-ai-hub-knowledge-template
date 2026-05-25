---
name: flutter-deep-link-strategy
description: >
  Comprehensive deep link implementation using go_router 17.2.2, fpdart functional programming, clean architecture patterns, route guards, dynamic parameters, and platform-specific configuration.
commands:
  - setup-deep-links
inputs:
  - name: action
    description: Action to perform (implement, add-link, audit). "implement" generates the full deep link architecture (domain, data, BLoC, platform config), "add-link" adds a new deep link route with validation and navigation, "audit" checks existing deep links for missing validation, unguarded routes, or platform config gaps.
    required: true
  - name: target
    description: Path to the deep link feature directory or router file (e.g. lib/features/deep_link/ for implement, lib/app/router/ for add-link).
    required: true
  - name: link_type
    description: Type of deep link to add (product, profile, share, content, custom). Determines the URL pattern, parameters, and validation logic. Required when action is "add-link".
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Deep Link Strategy

See `references/implementation_guide.md` for complete patterns and code examples.

## Quick Reference

This skill provides comprehensive deep link strategy implementation patterns for Flutter following
clean architecture with modern functional programming. All code examples use:

- Dart 3.5+ / Flutter 3.24+
- go_router 17.2.2 for declarative routing and deep links
- flutter_bloc 9.1.1 for state management  
- GetIt 9.2.1 + Injectable 3.0.0 for dependency injection
- Freezed 3.2.5 for immutable data classes
- fpdart 1.2.0 for functional programming and error handling

## Core Features

### 1. Declarative Routing with go_router
- `ShellRoute` — shell simple (scaffold/drawer compartido)
- `StatefulShellRoute.indexedStack` — bottom navigation con tabs persistentes
- Deep links activan la tab correcta dentro del shell
- Route guards y authentication redirects
- Dynamic parameter handling (`/product/:id`)
- Query string support (`?tab=reviews&sort=date`)
- Error handling y fallback routes

### 2. Clean Architecture Implementation
```
Domain (Entities, UseCases, Repositories) 
  ↓
Data (RepositoryImpl, DataSources)
  ↓  
Presentation (BLoC, Pages)
```

### 3. Functional Error Handling
- `Either<DeepLinkFailure, T>` for all operations
- Comprehensive failure types with Freezed
- Proper error propagation through layers

### 4. Deep Link Types Supported
- **Product Links**: `/product/:productId?variant=color`
- **Share Links**: `/share/:token` with validation
- **Profile Links**: `/profile/:userId?tab=activity`
- **Dynamic Content**: `/content/:type/:id`
- **Authentication-aware routing**

### 5. Platform Configuration
- Android App Links with intent filters
- iOS Universal Links with associated domains
- Custom scheme support for both platforms

## Architecture Integration

```
ProcessDeepLinkUseCase → DeepLinkRepository → DeepLinkRepositoryImpl → DeepLinkDataSource
                                    ↓
                            DeepLinkBloc (Presentation)
                                    ↓
                            go_router Navigation
```

All dependencies injected via GetIt + Injectable. Errors returned as `Either<DeepLinkFailure, T>` using fpdart.

## Key Implementation Patterns

### Router Configuration
```dart
// Caso A: ShellRoute simple (scaffold compartido)
ShellRoute(
  builder: (context, state, child) => MainShell(child: child),
  routes: [ /* rutas protegidas */ ],
)

// Caso B: StatefulShellRoute (bottom navigation con tabs persistentes)
// Deep link activa la branch/tab correcta automáticamente
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      MainScaffold(navigationShell: navigationShell),
  branches: [
    StatefulShellBranch(routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomePage(),
        routes: [
          // Deep links anidados dentro de la tab
          GoRoute(path: 'product/:productId', ...),
        ],
      ),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(path: '/profile/:userId', ...),
    ]),
  ],
)
```

| Escenario | Recomendación |
|---|---|
| Scaffold/AppBar compartido sin tabs | `ShellRoute` |
| Bottom navigation con tabs persistentes | `StatefulShellRoute.indexedStack` |
| Deep link debe activar tab específica | `StatefulShellRoute` — ruta en la branch correcta |
| Deep link abre pantalla sobre el shell | Ruta fuera del shell (nivel raíz) |

### Domain Layer
```dart
@freezed
class DeepLinkFailure with _$DeepLinkFailure {
  const factory DeepLinkFailure.invalidFormat({required String message}) = InvalidFormatFailure;
  const factory DeepLinkFailure.notFound({required String resource}) = NotFoundFailure;
  const factory DeepLinkFailure.unauthorized({required String message}) = UnauthorizedFailure;
}

abstract interface class DeepLinkRepository {
  Future<Either<DeepLinkFailure, DeepLinkResult>> processDeepLink(String url);
}
```

### BLoC State Management
```dart
@injectable
class DeepLinkBloc extends Bloc<DeepLinkEvent, DeepLinkState> {
  final ProcessDeepLinkUseCase _processDeepLinkUseCase;
  final GoRouter _router;

  DeepLinkBloc(this._processDeepLinkUseCase, this._router);
}
```

## Testing Strategy

- **Unit Tests**: UseCases and Repository logic
- **BLoC Tests**: State transitions with bloc_test
- **Integration Tests**: End-to-end deep link flow
- **Widget Tests**: Navigation behavior

## Security & Best Practices

- Parameter validation and sanitization
- Authentication checks before navigation
- Rate limiting for share links
- HTTPS enforcement for universal links
- Fallback routes for invalid links

## Reference Files

- `references/implementation_guide.md` — Complete implementation with code examples, platform setup, and testing strategies
