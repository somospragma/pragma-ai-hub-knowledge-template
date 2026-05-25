# Page Transitions — go_router 17.x

## CustomTransitionPage

go_router uses `CustomTransitionPage` to control animations between routes.

```dart
GoRoute(
  path: '/details',
  pageBuilder: (context, state) => CustomTransitionPage<void>(
    key: state.pageKey,
    child: const DetailsPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    barrierDismissible: false,
  ),
),
```

---

## NoTransitionPage

```dart
GoRoute(
  path: '/settings',
  pageBuilder: (context, state) => const NoTransitionPage<void>(
    child: SettingsPage(),
  ),
),
```

> Use `NoTransitionPage` for the shell itself (`StatefulShellRoute.pageBuilder`)
> to avoid animating the scaffold on tab switches.

---

## Common Transitions

### Slide from right (iOS style)

```dart
CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        )),
        child: child,
      ),
)
```

### Slide from bottom (modal style)

```dart
CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      ),
)
```

### Scale + Fade (Material 3 style)

```dart
CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
)
```

---

## Reusable Helper

```dart
// lib/app/router/page_transitions.dart
abstract final class AppPageTransitions {
  static CustomTransitionPage<T> fade<T>({
    required LocalKey key,
    required Widget child,
    Duration duration = const Duration(milliseconds: 300),
  }) =>
      CustomTransitionPage<T>(
        key: key,
        child: child,
        transitionDuration: duration,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  static CustomTransitionPage<T> slideRight<T>({
    required LocalKey key,
    required Widget child,
  }) =>
      CustomTransitionPage<T>(
        key: key,
        child: child,
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
          child: child,
        ),
      );

  static CustomTransitionPage<T> slideUp<T>({
    required LocalKey key,
    required Widget child,
  }) =>
      CustomTransitionPage<T>(
        key: key,
        child: child,
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
}
```

Usage:

```dart
GoRoute(
  path: '/details',
  pageBuilder: (context, state) => AppPageTransitions.fade(
    key: state.pageKey,
    child: const DetailsPage(),
  ),
),
```

---

## Type-Safe Routes with Custom Transitions

```dart
@TypedGoRoute<FadeDetailRoute>(path: '/fade-detail')
class FadeDetailRoute extends GoRouteData with $FadeDetailRoute {
  const FadeDetailRoute();

  @override
  CustomTransitionPage<void> buildPage(
    BuildContext context,
    GoRouterState state,
  ) =>
      CustomTransitionPage<void>(
        key: state.pageKey,
        child: const DetailPage(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      );
}
```

---

## Platform-Adaptive Transitions

```dart
// lib/app/router/platform_transition.dart
CustomTransitionPage<T> platformTransitionPage<T>({
  required LocalKey key,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return CupertinoPageTransition(
          primaryRouteAnimation: animation,
          secondaryRouteAnimation: secondaryAnimation,
          linearTransition: false,
          child: child,
        );
      }
      // Material / Android
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child: child,
      );
    },
  );
}
```

---

## Dialog / BottomSheet as a Route

Routing dialogs and bottom sheets through go_router keeps them in the URL and
handles back navigation correctly.

```dart
GoRoute(
  path: '/confirm',
  pageBuilder: (context, state) => DialogPage(
    builder: (_) => AlertDialog(
      title: const Text('Confirm?'),
      actions: [
        TextButton(
          onPressed: () => context.pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => context.pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  ),
),

// DialogPage helper
class DialogPage<T> extends Page<T> {
  const DialogPage({required this.builder, super.key});
  final WidgetBuilder builder;

  @override
  Route<T> createRoute(BuildContext context) => DialogRoute<T>(
    context: context,
    settings: this,
    builder: builder,
  );
}
```

```dart
// BottomSheet as a route
class ModalBottomSheetPage<T> extends Page<T> {
  const ModalBottomSheetPage({required this.builder, super.key});
  final WidgetBuilder builder;

  @override
  Route<T> createRoute(BuildContext context) => ModalBottomSheetRoute<T>(
    settings: this,
    isScrollControlled: true,
    builder: builder,
  );
}
```

---

## StatefulShellRoute Transitions

Transitions inside `StatefulShellRoute` require special handling:

```dart
StatefulShellRoute.indexedStack(
  // Use pageBuilder to control the shell transition
  pageBuilder: (context, state, navigationShell) => NoTransitionPage<void>(
    child: ShellPage(navigationShell: navigationShell),
  ),
  branches: [/* ... */],
),
```

> Each branch inside `StatefulShellRoute` maintains its own `Navigator`,
> so transitions for inner routes are defined in each `GoRoute.pageBuilder` individually.
> The shell itself should use `NoTransitionPage` to avoid animating the scaffold on tab switches.
