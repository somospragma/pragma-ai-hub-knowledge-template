# FailureMessageKey — Semantic i18n Key Enum

`lib/core/error/failure_message_key.dart`

---

## Table of Contents

1. [The Problem](#the-problem)
2. [FailureMessageKey — complete enum](#failuremessagekey--complete-enum)
3. [Failures redesigned — no hardcoded strings](#failures-redesigned--no-hardcoded-strings)
4. [FailureView — resolution in the UI](#failureview--resolution-in-the-ui)

---

## The Problem

`Failure` objects live in the **domain layer**, which has no `BuildContext`.
Translated messages only exist in the **presentation layer**, which does have `BuildContext`.

**Solution:** `Failure` objects do NOT store a hardcoded `String message`.
Instead they store a **semantic key** (`FailureMessageKey`) that the UI resolves with `AppLocalizations`.

```
Failure (domain)           →  semantic key (enum)
ErrorHandler (data)        →  assigns the correct key
FailureView (presentation) →  key.resolve(context) → translated String
```

---

## FailureMessageKey — complete enum

```dart
import 'package:flutter/widgets.dart';
import 'package:your_app/core/l10n/generated/app_localizations.dart';

/// Semantic key that points to an ARB entry.
/// Decouples the domain from the locale — the UI resolves the text.
enum FailureMessageKey {
  network,
  timeout,
  unauthorized,
  notFound,
  server,
  // 4XX - Client errors
  serverBadRequest,
  serverUnauthorized,
  serverForbidden,
  serverNotFound,
  serverMethodNotAllowed,
  serverRequestTimeout,
  serverConflict,
  serverGone,
  serverPayloadTooLarge,
  serverUnsupportedMediaType,
  serverUnprocessable,
  serverTooManyRequests,
  // 5XX - Server errors
  serverInternalError,
  serverNotImplemented,
  serverBadGateway,
  serverUnavailable,
  serverGatewayTimeout,
  authUserNotFound,
  authWrongPassword,
  authEmailInUse,
  authUserDisabled,
  authTooManyRequests,
  authGeneric,
  firestore,
  storage,
  database,
  databaseBusy,
  databaseReadOnly,
  databaseConstraint,
  cache,
  unexpected;

  /// Resolves the key to the translated String for the active locale.
  String resolve(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (this) {
      network                    => l.errorNetwork,
      timeout                    => l.errorTimeout,
      unauthorized               => l.errorUnauthorized,
      notFound                   => l.errorNotFound,
      server                     => l.errorServer,
      serverBadRequest           => l.errorServerBadRequest,
      serverUnauthorized         => l.errorServerUnauthorized,
      serverForbidden            => l.errorServerForbidden,
      serverNotFound             => l.errorServerNotFound,
      serverMethodNotAllowed     => l.errorServerMethodNotAllowed,
      serverRequestTimeout       => l.errorServerRequestTimeout,
      serverConflict             => l.errorServerConflict,
      serverGone                 => l.errorServerGone,
      serverPayloadTooLarge      => l.errorServerPayloadTooLarge,
      serverUnsupportedMediaType => l.errorServerUnsupportedMediaType,
      serverUnprocessable        => l.errorServerUnprocessable,
      serverTooManyRequests      => l.errorServerTooManyRequests,
      serverInternalError        => l.errorServerInternalError,
      serverNotImplemented       => l.errorServerNotImplemented,
      serverBadGateway           => l.errorServerBadGateway,
      serverUnavailable          => l.errorServerUnavailable,
      serverGatewayTimeout       => l.errorServerGatewayTimeout,
      authUserNotFound           => l.errorAuthUserNotFound,
      authWrongPassword          => l.errorAuthWrongPassword,
      authEmailInUse             => l.errorAuthEmailInUse,
      authUserDisabled           => l.errorAuthUserDisabled,
      authTooManyRequests        => l.errorAuthTooManyRequests,
      authGeneric                => l.errorAuthGeneric,
      firestore                  => l.errorFirestore,
      storage                    => l.errorStorage,
      database                   => l.errorDatabase,
      databaseBusy               => l.errorDatabaseBusy,
      databaseReadOnly           => l.errorDatabaseReadOnly,
      databaseConstraint         => l.errorDatabaseConstraint,
      cache                      => l.errorCache,
      unexpected                 => l.errorUnexpected,
    };
  }
}
```

---

## Failures redesigned — no hardcoded strings

`lib/core/error/failures.dart`

```dart
import 'failure_message_key.dart';

/// Failures no longer have a String message — they have an i18n key.
/// Exception: ValidationFailure and BusinessRuleFailure, whose message
/// comes from the domain (already translated or generated dynamically).
sealed class Failure {
  const Failure();

  /// Key for standard messages mapped in the ARB.
  FailureMessageKey? get messageKey => null;

  /// Literal message for dynamic cases (validation, business rules).
  /// In these cases messageKey is null.
  String? get literalMessage => null;

  /// Resolves the final message with context for i18n.
  /// ALWAYS use this method in the UI.
  String localizedMessage(BuildContext context) =>
      messageKey?.resolve(context) ?? literalMessage ?? '';
}

// ─── Network / API ────────────────────────────────────────────────────────────

final class NetworkFailure extends Failure {
  const NetworkFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.network;
}

final class ServerFailure extends Failure {
  const ServerFailure({this.key = FailureMessageKey.server});
  final FailureMessageKey key;
  @override
  FailureMessageKey get messageKey => key;
}

final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.unauthorized;
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.notFound;
}

final class TimeoutFailure extends Failure {
  const TimeoutFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.timeout;
}

// ─── Firebase ─────────────────────────────────────────────────────────────────

final class AuthFailure extends Failure {
  const AuthFailure({required this.authKey});
  final FailureMessageKey authKey;
  @override
  FailureMessageKey get messageKey => authKey;
}

final class FirestoreFailure extends Failure {
  const FirestoreFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.firestore;
}

final class StorageFailure extends Failure {
  const StorageFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.storage;
}

// ─── Local Database ───────────────────────────────────────────────────────────

final class DatabaseFailure extends Failure {
  const DatabaseFailure({this.dbKey = FailureMessageKey.database});
  final FailureMessageKey dbKey;
  @override
  FailureMessageKey get messageKey => dbKey;
}

// ─── Cache ────────────────────────────────────────────────────────────────────

final class CacheFailure extends Failure {
  const CacheFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.cache;
}

// ─── Validation / Business — dynamic message, NOT in ARB ─────────────────────
//
// These messages are generated by the domain at runtime.
// For known static translations, add them to the ARB and use messageKey.

final class ValidationFailure extends Failure {
  /// [message] should already be in the correct language from the domain,
  /// or resolved with AppLocalizations in the use case if context is available.
  const ValidationFailure({required this.message});
  final String message;
  @override
  String? get literalMessage => message;
}

final class BusinessRuleFailure extends Failure {
  const BusinessRuleFailure({required this.message});
  final String message;
  @override
  String? get literalMessage => message;
}

// ─── Unexpected ───────────────────────────────────────────────────────────────

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure();
  @override
  FailureMessageKey get messageKey => FailureMessageKey.unexpected;
}
```

---

## FailureView — resolution in the UI

```dart
// lib/core/widgets/failure_view.dart

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
              failure.localizedMessage(context), // ← i18n resolution here
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null && failure.isRetryable) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRetry,
                child: Text(l.retryButton), // ← also translated
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

---

## Checklist

- [ ] `Failure` uses `messageKey` — none has a hardcoded `String message`
- [ ] `ValidationFailure` and `BusinessRuleFailure` are the only exceptions
- [ ] The UI **always** calls `failure.localizedMessage(context)`
- [ ] Each `FailureMessageKey` has its corresponding entry in the ARB files
