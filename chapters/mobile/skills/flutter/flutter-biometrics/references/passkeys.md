# Passkeys (FIDO2/WebAuthn) — Strategy + Adapter Pattern

Passkeys are the modern, phishing-resistant replacement for passwords.
They use public-key cryptography where the private key never leaves the device
and is protected by biometrics or device PIN.

## Why Passkeys vs local_auth

| Aspect | local_auth | Passkeys (FIDO2) |
|---|---|---|
| Authentication factor | Local only — no server verification | Server-verified — phishing-resistant |
| What it protects | A token stored locally | The login itself |
| Sync across devices | ❌ No | ✅ Yes (iCloud Keychain, Google Password Manager) |
| Phishing resistance | ❌ No | ✅ Yes — bound to domain |
| Backend required | No | Yes (relying party server) |
| Use case | App resume, re-auth gate | Primary login |

---

## Provider Strategy Pattern — Plug-and-Play FIDO

If the project uses a FIDO2 provider, **never couple the domain or presentation
layers to a specific SDK or vendor**. Use the Strategy + Adapter pattern so that
swapping providers is a single DI binding change — plug-and-play.

```
Domain (FidoProvider interface)
  ↓ abstract interface class — knows nothing about any specific SDK
Data (FidoProviderAdapter)
  ├── ProviderAFidoAdapter   implements FidoProvider  ← e.g. your first vendor
  ├── ProviderBFidoAdapter   implements FidoProvider  ← e.g. a future vendor
  └── MockFidoAdapter        implements FidoProvider  ← tests
DI (Injectable)
  └── bind FidoProvider → ProviderAFidoAdapter  ← change this one line to swap
```

---

## 1. Domain — FidoProvider Interface (Strategy)

```dart
// lib/core/auth/fido/fido_provider.dart
import 'package:fpdart/fpdart.dart';

/// Provider-agnostic FIDO2 contract.
/// The domain layer only knows this interface — never a specific SDK or vendor.
abstract interface class FidoProvider {
  /// Check if passkeys are supported on this device.
  Future<bool> isAvailable();

  /// Register a new passkey for the user.
  /// Returns the credential ID on success.
  Future<Either<FidoFailure, String>> register({
    required String userId,
    required String username,
  });

  /// Authenticate with an existing passkey.
  /// Returns a session token on success.
  Future<Either<FidoFailure, String>> authenticate({
    required String username,
  });
}

// lib/core/auth/fido/fido_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'fido_failure.freezed.dart';

@freezed
class FidoFailure with _$FidoFailure {
  const factory FidoFailure.notAvailable() = FidoNotAvailable;
  const factory FidoFailure.registrationFailed({required String message}) = FidoRegistrationFailed;
  const factory FidoFailure.authenticationFailed({required String message}) = FidoAuthenticationFailed;
  const factory FidoFailure.cancelled() = FidoCancelled;
  const factory FidoFailure.serverError({required String message}) = FidoServerError;
  const factory FidoFailure.unknown({required String message}) = FidoUnknown;
}
```

---

## 2. Use Cases — Depend Only on FidoProvider

```dart
// lib/features/auth/domain/usecases/register_passkey_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class RegisterPasskeyUseCase {
  final FidoProvider _provider;
  RegisterPasskeyUseCase(this._provider);

  Future<Either<FidoFailure, String>> call({
    required String userId,
    required String username,
  }) =>
      _provider.register(userId: userId, username: username);
}

// lib/features/auth/domain/usecases/authenticate_with_passkey_usecase.dart
@injectable
class AuthenticateWithPasskeyUseCase {
  final FidoProvider _provider;
  AuthenticateWithPasskeyUseCase(this._provider);

  Future<Either<FidoFailure, String>> call({required String username}) =>
      _provider.authenticate(username: username);
}
```

---

## 3. Adapters — One Per Provider (Adapter Pattern)

Each adapter wraps a specific FIDO2 SDK/vendor behind the `FidoProvider` interface.
The examples below use generic names — replace with your actual vendor SDK.

### Provider A Adapter (example)

```dart
// lib/core/auth/fido/adapters/provider_a_fido_adapter.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

/// Adapter for Provider A's FIDO2 SDK.
/// Wraps vendor-specific SDK calls behind the FidoProvider interface.
/// To swap: create a new adapter, change the DI binding — nothing else changes.
@Injectable(as: FidoProvider, env: ['provider_a', Environment.prod])
class ProviderAFidoAdapter implements FidoProvider {
  final ProviderAFidoSdk _sdk;   // vendor SDK — injected
  final FidoApiClient _api;      // your backend client — injected

  ProviderAFidoAdapter(this._sdk, this._api);

  @override
  Future<bool> isAvailable() async {
    try {
      return await _sdk.canAuthenticate();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Either<FidoFailure, String>> register({
    required String userId,
    required String username,
  }) async {
    try {
      // 1. Get registration challenge from your backend
      final challenge = await _api.getRegistrationChallenge(userId: userId);

      // 2. Create passkey on device (triggers biometric prompt)
      final credential = await _sdk.register(
        challenge: challenge.value,
        userId: userId,
        username: username,
        relyingPartyId: 'yourapp.com',
      );

      // 3. Send attestation to your backend for verification
      final credentialId = await _api.verifyRegistration(
        userId: userId,
        attestation: credential,
      );

      return Right(credentialId);
    } on FidoSdkCancelledException {
      return const Left(FidoFailure.cancelled());
    } on FidoSdkException catch (e) {
      return Left(FidoFailure.registrationFailed(message: e.message));
    } catch (e) {
      return Left(FidoFailure.unknown(message: '$e'));
    }
  }

  @override
  Future<Either<FidoFailure, String>> authenticate({
    required String username,
  }) async {
    try {
      // 1. Get authentication challenge from your backend
      final challenge = await _api.getAuthenticationChallenge(username: username);

      // 2. Sign challenge with device passkey (triggers biometric prompt)
      final assertion = await _sdk.authenticate(
        challenge: challenge.value,
        relyingPartyId: 'yourapp.com',
        allowedCredentials: challenge.allowedCredentials,
      );

      // 3. Send assertion to your backend for verification
      final token = await _api.verifyAuthentication(
        username: username,
        assertion: assertion,
      );

      return Right(token);
    } on FidoSdkCancelledException {
      return const Left(FidoFailure.cancelled());
    } on FidoSdkException catch (e) {
      return Left(FidoFailure.authenticationFailed(message: e.message));
    } catch (e) {
      return Left(FidoFailure.unknown(message: '$e'));
    }
  }
}
```

### Provider B Adapter (example — different vendor, same interface)

```dart
// lib/core/auth/fido/adapters/provider_b_fido_adapter.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

/// Adapter for Provider B's FIDO2 SDK.
/// Different vendor, different SDK API — same FidoProvider interface.
@Injectable(as: FidoProvider, env: ['provider_b'])
class ProviderBFidoAdapter implements FidoProvider {
  final ProviderBFidoSdk _sdk;
  final FidoApiClient _api;

  ProviderBFidoAdapter(this._sdk, this._api);

  @override
  Future<bool> isAvailable() async => _sdk.isPasskeySupported();

  @override
  Future<Either<FidoFailure, String>> register({
    required String userId,
    required String username,
  }) async {
    try {
      // Provider B may have a different challenge/attestation format
      final options = await _api.beginRegistration(userId: userId);
      final result = await _sdk.createCredential(
        options: options.toProviderBFormat(),
      );
      final credentialId = await _api.completeRegistration(result);
      return Right(credentialId);
    } on ProviderBException catch (e) {
      if (e.isCancellation) return const Left(FidoFailure.cancelled());
      return Left(FidoFailure.registrationFailed(message: e.description));
    } catch (e) {
      return Left(FidoFailure.serverError(message: '$e'));
    }
  }

  @override
  Future<Either<FidoFailure, String>> authenticate({
    required String username,
  }) async {
    try {
      final options = await _api.beginAuthentication(username: username);
      final assertion = await _sdk.getAssertion(
        options: options.toProviderBFormat(),
      );
      final token = await _api.completeAuthentication(assertion);
      return Right(token);
    } on ProviderBException catch (e) {
      if (e.isCancellation) return const Left(FidoFailure.cancelled());
      return Left(FidoFailure.authenticationFailed(message: e.description));
    } catch (e) {
      return Left(FidoFailure.serverError(message: '$e'));
    }
  }
}
```

### Mock Adapter (for tests)

```dart
// lib/core/auth/fido/adapters/mock_fido_adapter.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: FidoProvider, env: [Environment.test])
class MockFidoAdapter implements FidoProvider {
  bool _shouldSucceed = true;
  FidoFailure? _failureToReturn;

  void configureSuccess() {
    _shouldSucceed = true;
    _failureToReturn = null;
  }

  void configureFailure(FidoFailure failure) {
    _shouldSucceed = false;
    _failureToReturn = failure;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Either<FidoFailure, String>> register({
    required String userId,
    required String username,
  }) async {
    if (!_shouldSucceed) {
      return Left(_failureToReturn ??
          const FidoFailure.registrationFailed(message: 'Mock failure'));
    }
    return const Right('mock-credential-id');
  }

  @override
  Future<Either<FidoFailure, String>> authenticate({
    required String username,
  }) async {
    if (!_shouldSucceed) {
      return Left(_failureToReturn ??
          const FidoFailure.authenticationFailed(message: 'Mock failure'));
    }
    return const Right('mock-session-token');
  }
}
```

---

## 4. DI Binding — The Only Line to Change When Swapping Providers

```dart
// lib/core/di/fido_module.dart
import 'package:injectable/injectable.dart';

@module
abstract class FidoModule {
  // ✅ Change this one binding to swap providers — nothing else in the app changes
  @singleton
  FidoProvider fidoProvider(ProviderAFidoAdapter adapter) => adapter;

  // To switch to Provider B:
  // @singleton
  // FidoProvider fidoProvider(ProviderBFidoAdapter adapter) => adapter;
}

// Alternative: select provider at build time via dart-define
// flutter run --dart-define=FIDO_PROVIDER=provider_a
@module
abstract class FidoModuleEnv {
  @singleton
  FidoProvider fidoProvider(
    ProviderAFidoAdapter providerA,
    ProviderBFidoAdapter providerB,
  ) {
    const provider = String.fromEnvironment(
      'FIDO_PROVIDER',
      defaultValue: 'provider_a',
    );
    return switch (provider) {
      'provider_b' => providerB,
      _ => providerA,
    };
  }
}
```

---

## 5. BLoC — Completely Provider-Agnostic

```dart
// lib/features/auth/presentation/bloc/passkey_auth_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';

part 'passkey_auth_bloc.freezed.dart';
part 'passkey_auth_event.dart';
part 'passkey_auth_state.dart';

@injectable
class PasskeyAuthBloc extends Bloc<PasskeyAuthEvent, PasskeyAuthState> {
  final RegisterPasskeyUseCase _register;
  final AuthenticateWithPasskeyUseCase _authenticate;

  PasskeyAuthBloc(this._register, this._authenticate)
      : super(const PasskeyAuthState.initial()) {
    on<CheckPasskeyAvailabilityEvent>(_onCheckAvailability);
    on<RegisterPasskeyEvent>(_onRegister, transformer: droppable());
    on<AuthenticateWithPasskeyEvent>(_onAuthenticate, transformer: droppable());
  }

  Future<void> _onCheckAvailability(
    CheckPasskeyAvailabilityEvent event,
    Emitter<PasskeyAuthState> emit,
  ) async {
    // FidoProvider.isAvailable() — no vendor knowledge here
    final available = await GetIt.instance<FidoProvider>().isAvailable();
    emit(PasskeyAuthState.availabilityChecked(isAvailable: available));
  }

  Future<void> _onRegister(
    RegisterPasskeyEvent event,
    Emitter<PasskeyAuthState> emit,
  ) async {
    emit(const PasskeyAuthState.loading());
    final result = await _register(
      userId: event.userId,
      username: event.username,
    );
    result.fold(
      (failure) => emit(PasskeyAuthState.error(_mapFailure(failure))),
      (_) => emit(const PasskeyAuthState.registered()),
    );
  }

  Future<void> _onAuthenticate(
    AuthenticateWithPasskeyEvent event,
    Emitter<PasskeyAuthState> emit,
  ) async {
    emit(const PasskeyAuthState.loading());
    final result = await _authenticate(username: event.username);
    result.fold(
      (failure) => emit(PasskeyAuthState.error(_mapFailure(failure))),
      (token) => emit(PasskeyAuthState.authenticated(token: token)),
    );
  }

  String _mapFailure(FidoFailure failure) => failure.when(
    notAvailable: () => 'Passkeys not available on this device',
    registrationFailed: (msg) => 'Registration failed: $msg',
    authenticationFailed: (msg) => 'Authentication failed: $msg',
    cancelled: () => 'Authentication cancelled',
    serverError: (msg) => 'Server error: $msg',
    unknown: (msg) => 'Unknown error: $msg',
  );
}

// passkey_auth_event.dart
part of 'passkey_auth_bloc.dart';

@freezed
class PasskeyAuthEvent with _$PasskeyAuthEvent {
  const factory PasskeyAuthEvent.checkAvailability() = CheckPasskeyAvailabilityEvent;
  const factory PasskeyAuthEvent.register({
    required String userId,
    required String username,
  }) = RegisterPasskeyEvent;
  const factory PasskeyAuthEvent.authenticate({
    required String username,
  }) = AuthenticateWithPasskeyEvent;
}

// passkey_auth_state.dart
part of 'passkey_auth_bloc.dart';

@freezed
class PasskeyAuthState with _$PasskeyAuthState {
  const factory PasskeyAuthState.initial() = PasskeyAuthInitial;
  const factory PasskeyAuthState.loading() = PasskeyAuthLoading;
  const factory PasskeyAuthState.availabilityChecked({
    required bool isAvailable,
  }) = PasskeyAuthAvailabilityChecked;
  const factory PasskeyAuthState.registered() = PasskeyAuthRegistered;
  const factory PasskeyAuthState.authenticated({required String token}) =
      PasskeyAuthAuthenticated;
  const factory PasskeyAuthState.error(String message) = PasskeyAuthError;
}
```

---

## 6. Platform Configuration

### Android — Digital Asset Links

```json
// https://yourapp.com/.well-known/assetlinks.json
[{
  "relation": [
    "delegate_permission/common.handle_all_urls",
    "delegate_permission/common.get_login_creds"
  ],
  "target": {
    "namespace": "android_app",
    "package_name": "com.example.yourapp",
    "sha256_cert_fingerprints": ["YOUR_APP_SIGNING_CERT_SHA256"]
  }
}]
```

### iOS — Apple App Site Association + Entitlements

```json
// https://yourapp.com/.well-known/apple-app-site-association
{
  "webcredentials": {
    "apps": ["TEAMID.com.example.yourapp"]
  }
}
```

```xml
<!-- ios/Runner/Runner.entitlements -->
<dict>
    <key>com.apple.developer.associated-domains</key>
    <array>
        <string>webcredentials:yourapp.com</string>
    </array>
</dict>
```

---

## 7. Testing — Inject MockFidoAdapter

```dart
// test/features/auth/presentation/bloc/passkey_auth_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

void main() {
  late PasskeyAuthBloc bloc;
  late MockFidoAdapter mockAdapter;

  setUp(() {
    mockAdapter = MockFidoAdapter();
    bloc = PasskeyAuthBloc(
      RegisterPasskeyUseCase(mockAdapter),
      AuthenticateWithPasskeyUseCase(mockAdapter),
    );
  });

  tearDown(() => bloc.close());

  group('PasskeyAuthBloc', () {
    blocTest<PasskeyAuthBloc, PasskeyAuthState>(
      'emits [loading, authenticated] on success',
      build: () {
        mockAdapter.configureSuccess();
        return bloc;
      },
      act: (b) => b.add(
        const PasskeyAuthEvent.authenticate(username: 'user@test.com'),
      ),
      expect: () => [
        const PasskeyAuthState.loading(),
        const PasskeyAuthState.authenticated(token: 'mock-session-token'),
      ],
    );

    blocTest<PasskeyAuthBloc, PasskeyAuthState>(
      'emits [loading, error] on authentication failure',
      build: () {
        mockAdapter.configureFailure(
          const FidoFailure.authenticationFailed(message: 'Biometric failed'),
        );
        return bloc;
      },
      act: (b) => b.add(
        const PasskeyAuthEvent.authenticate(username: 'user@test.com'),
      ),
      expect: () => [
        const PasskeyAuthState.loading(),
        isA<PasskeyAuthError>(),
      ],
    );

    blocTest<PasskeyAuthBloc, PasskeyAuthState>(
      'emits [loading, error(cancelled)] when user cancels',
      build: () {
        mockAdapter.configureFailure(const FidoFailure.cancelled());
        return bloc;
      },
      act: (b) => b.add(
        const PasskeyAuthEvent.authenticate(username: 'user@test.com'),
      ),
      expect: () => [
        const PasskeyAuthState.loading(),
        const PasskeyAuthState.error('Authentication cancelled'),
      ],
    );
  });
}
```

---

## Decision Guide

```
Using a FIDO2 provider?
  → Always use FidoProvider interface + adapter
  → Domain and BLoC never import any vendor SDK
  → Swap providers by changing one DI binding

local_auth vs Passkeys?
  → local_auth: re-auth gate, protect locally stored token, works offline
  → Passkeys: primary login, phishing-resistant, cross-device sync

How many adapters to create?
  → One per vendor/SDK you integrate
  → Always one MockFidoAdapter for tests
  → The interface never changes when you add a new adapter
```
