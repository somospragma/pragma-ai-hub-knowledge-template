# Riverpod Integration — Either + AsyncNotifier

Stack: `riverpod` · `riverpod_annotation` · `fpdart 1.2.0`

---

## State with Explicit Failure

```dart
// features/auth/presentation/providers/auth_state.dart

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:your_app/core/error/failures.dart';

part 'auth_state.freezed.dart';

@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.initial()                        = AuthInitial;
  const factory AuthState.loading()                        = AuthLoading;
  const factory AuthState.authenticated(User user)         = AuthAuthenticated;
  const factory AuthState.unauthenticated()                = AuthUnauthenticated;
  const factory AuthState.failure(Failure failure)         = AuthFailureState;
}
```

---

## AsyncNotifier with Either — complete pattern

```dart
// features/auth/presentation/providers/auth_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fpdart/fpdart.dart';

part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() => const AuthState.initial();

  Future<void> signIn({required String email, required String password}) async {
    state = const AuthState.loading();

    // TaskEither is executed with .run() — returns Either<Failure, T>
    final result = await ref
        .read(signInUseCaseProvider)
        .call(email: email, password: password)
        .run();

    // fold: Left = failure, Right = success
    state = result.fold(
      AuthState.failure,
      AuthState.authenticated,
    );
  }

  Future<void> signOut() async {
    final result = await ref.read(signOutUseCaseProvider).call().run();
    state = result.fold(
      AuthState.failure,
      (_) => const AuthState.unauthenticated(),
    );
  }
}
```

---

## FutureProvider with Either (simple read)

```dart
@riverpod
Future<Either<Failure, List<Product>>> products(ProductsRef ref) async {
  return ref.read(getProductsUseCaseProvider).call().run();
}

// In the widget:
final productsAsync = ref.watch(productsProvider);

productsAsync.when(
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => ErrorView(message: e.toString()),  // Riverpod error, not Failure
  data: (result) => result.fold(
    (failure) => FailureView(failure: failure),        // domain error
    (products) => ProductsList(products: products),
  ),
);
```

---

## Recommended Pattern: AsyncNotifier with Granular State

```dart
// For lists with pagination or complex state
@riverpod
class ProductsNotifier extends _$ProductsNotifier {
  @override
  AsyncValue<List<Product>> build() => const AsyncValue.data([]);

  Future<void> loadProducts({bool refresh = false}) async {
    if (refresh) state = const AsyncValue.loading();

    final result = await ref.read(getProductsUseCaseProvider).call().run();

    state = result.fold(
      // Convert Failure → AsyncError for Riverpod consistency
      (failure) => AsyncValue.error(failure, StackTrace.current),
      AsyncValue.data,
    );
  }
}

// Widget with AsyncValue:
Consumer(
  builder: (context, ref, _) {
    final state = ref.watch(productsNotifierProvider);
    return state.when(
      loading: () => const LoadingWidget(),
      error: (error, _) {
        // error can be a Failure if it comes from our fold
        if (error is Failure) return FailureWidget(failure: error);
        return const UnexpectedErrorWidget();
      },
      data: (products) => ProductsListView(products: products),
    );
  },
)
```

---

## Reusable FailureView Widget

```dart
// lib/core/widgets/failure_view.dart

import 'package:your_app/core/l10n/generated/app_localizations.dart';

class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(failure.icon, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              failure.localizedMessage(context), // i18n — never failure.message
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null && failure.isRetryable) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(l.retryButton), // translated from ARB
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```
