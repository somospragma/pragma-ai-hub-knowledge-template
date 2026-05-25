# Biometric Service — Clean Architecture Implementation

## Domain Layer

```dart
// lib/core/auth/biometric/biometric_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'biometric_failure.freezed.dart';

@freezed
class BiometricFailure with _$BiometricFailure {
  const factory BiometricFailure.notAvailable() = BiometricNotAvailable;
  const factory BiometricFailure.notEnrolled() = BiometricNotEnrolled;
  const factory BiometricFailure.lockout() = BiometricLockout;
  const factory BiometricFailure.permanentLockout() = BiometricPermanentLockout;
  const factory BiometricFailure.cancelled() = BiometricCancelled;
  const factory BiometricFailure.failed() = BiometricFailed;
  const factory BiometricFailure.unknown({required String message}) = BiometricUnknown;
}

// lib/core/auth/biometric/biometric_service.dart
import 'package:fpdart/fpdart.dart';
import 'package:local_auth/local_auth.dart';

abstract interface class BiometricService {
  Future<bool> isAvailable();
  Future<bool> hasStrongBiometrics();
  Future<Either<BiometricFailure, bool>> authenticate({
    required String reason,
    bool biometricOnly = true,
    bool sensitiveTransaction = false,
  });
  Future<bool> isEnrollmentChanged();
}
```

## Data Layer — BiometricService Implementation

```dart
// lib/core/auth/biometric/biometric_service_impl.dart
import 'package:injectable/injectable.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:fpdart/fpdart.dart';

@LazySingleton(as: BiometricService)
class BiometricServiceImpl implements BiometricService {
  final LocalAuthentication _auth;
  final SecureStorageService _storage;

  BiometricServiceImpl(this._storage) : _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    final canCheck = await _auth.canCheckBiometrics;
    final isSupported = await _auth.isDeviceSupported();
    return canCheck && isSupported;
  }

  @override
  Future<bool> hasStrongBiometrics() async {
    final biometrics = await _auth.getAvailableBiometrics();
    return biometrics.contains(BiometricType.strong) ||
        biometrics.contains(BiometricType.face);
  }

  @override
  Future<Either<BiometricFailure, bool>> authenticate({
    required String reason,
    bool biometricOnly = true,
    bool sensitiveTransaction = false,
  }) async {
    try {
      final available = await isAvailable();
      if (!available) return const Left(BiometricFailure.notAvailable());

      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) return const Left(BiometricFailure.notEnrolled());

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,           // survive app backgrounding (phone call, etc.)
          sensitiveTransaction: sensitiveTransaction, // "Confirm payment" on Android
          useErrorDialogs: true,
        ),
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Authentication required',
            cancelButton: 'Cancel',
          ),
          IOSAuthMessages(
            cancelButton: 'Cancel',
          ),
        ],
      );

      return Right(authenticated);
    } on LocalAuthException catch (e) {
      return Left(_mapException(e));
    } catch (e) {
      return Left(BiometricFailure.unknown(message: '$e'));
    }
  }

  BiometricFailure _mapException(LocalAuthException e) {
    return switch (e.code) {
      LocalAuthExceptionCode.biometricLockout => const BiometricFailure.permanentLockout(),
      LocalAuthExceptionCode.temporaryLockout => const BiometricFailure.lockout(),
      LocalAuthExceptionCode.notEnrolled => const BiometricFailure.notEnrolled(),
      LocalAuthExceptionCode.noBiometricHardware => const BiometricFailure.notAvailable(),
      LocalAuthExceptionCode.passcodeNotSet => const BiometricFailure.notAvailable(),
      _ => BiometricFailure.unknown(message: e.message ?? e.code.toString()),
    };
  }

  /// Detect if biometric enrollment changed since last login.
  /// If changed, the stored token should be invalidated (MASVS-AUTH-3).
  @override
  Future<bool> isEnrollmentChanged() async {
    final biometrics = await _auth.getAvailableBiometrics();
    final currentHash = biometrics.map((b) => b.name).join(',');
    final storedHash = await _storage.read(SecureStorageKeys.biometricEnrollmentHash);

    if (storedHash == null) {
      // First time — store current enrollment
      await _storage.write(SecureStorageKeys.biometricEnrollmentHash, currentHash);
      return false;
    }

    if (storedHash != currentHash) {
      // Enrollment changed — update stored hash
      await _storage.write(SecureStorageKeys.biometricEnrollmentHash, currentHash);
      return true;
    }

    return false;
  }
}
```

---

## The Token Gate Pattern

Biometrics protect access to a token stored in `flutter_secure_storage`.
They do not replace the token or the server-side session.

```dart
// lib/features/auth/data/repositories/auth_repository_impl.dart

/// Called on app resume — check if biometric re-auth is needed
Future<Either<AuthFailure, String>> getTokenWithBiometricGate() async {
  // 1. Check if enrollment changed — invalidate token if so (MASVS-AUTH-3)
  if (await _biometricService.isEnrollmentChanged()) {
    await _storage.delete(SecureStorageKeys.accessToken);
    return const Left(AuthFailure.biometricEnrollmentChanged());
  }

  // 2. Check if token exists
  final tokenResult = await _storage.read(SecureStorageKeys.accessToken);
  final token = tokenResult.getOrElse((_) => null);
  if (token == null) {
    return const Left(AuthFailure.notAuthenticated());
  }

  // 3. Require biometric to unlock the token
  final biometricResult = await _biometricService.authenticate(
    reason: 'Confirm your identity to continue',
    biometricOnly: false, // allow PIN fallback
  );

  return biometricResult.fold(
    (failure) => Left(AuthFailure.biometricFailed(failure)),
    (authenticated) => authenticated
        ? Right(token)
        : const Left(AuthFailure.biometricCancelled()),
  );
}

/// Called after successful server login — store token
Future<Either<AuthFailure, Unit>> storeTokenAfterLogin(String token) async {
  // Store token in secure storage — biometrics will gate future access
  await _storage.write(SecureStorageKeys.accessToken, token);

  // Store current biometric enrollment hash for change detection
  await _biometricService.isEnrollmentChanged(); // initializes hash

  return const Right(unit);
}

/// Called on logout — clear token
Future<void> logout() async {
  await _storage.delete(SecureStorageKeys.accessToken);
  await _storage.delete(SecureStorageKeys.biometricEnrollmentHash);
}
```

---

## Use Cases

```dart
// lib/features/auth/domain/usecases/authenticate_with_biometric_usecase.dart
@injectable
class AuthenticateWithBiometricUseCase {
  final BiometricService _biometric;
  AuthenticateWithBiometricUseCase(this._biometric);

  Future<Either<BiometricFailure, bool>> call({
    String reason = 'Confirm your identity to continue',
    bool sensitiveTransaction = false,
  }) =>
      _biometric.authenticate(
        reason: reason,
        biometricOnly: false, // allow PIN fallback
        sensitiveTransaction: sensitiveTransaction,
      );
}

// lib/features/auth/domain/usecases/check_biometric_availability_usecase.dart
@injectable
class CheckBiometricAvailabilityUseCase {
  final BiometricService _biometric;
  CheckBiometricAvailabilityUseCase(this._biometric);

  Future<BiometricAvailability> call() async {
    if (!await _biometric.isAvailable()) {
      return BiometricAvailability.notAvailable;
    }
    if (await _biometric.hasStrongBiometrics()) {
      return BiometricAvailability.strongAvailable;
    }
    return BiometricAvailability.weakAvailable;
  }
}

enum BiometricAvailability { notAvailable, weakAvailable, strongAvailable }
```

---

## BLoC Integration

```dart
// lib/features/auth/presentation/bloc/biometric_bloc.dart
@injectable
class BiometricBloc extends Bloc<BiometricEvent, BiometricState> {
  final AuthenticateWithBiometricUseCase _authenticate;
  final CheckBiometricAvailabilityUseCase _checkAvailability;

  BiometricBloc(this._authenticate, this._checkAvailability)
      : super(const BiometricState.initial()) {
    on<CheckAvailabilityEvent>(_onCheckAvailability);
    on<AuthenticateEvent>(_onAuthenticate, transformer: droppable());
  }

  Future<void> _onCheckAvailability(
    CheckAvailabilityEvent event,
    Emitter<BiometricState> emit,
  ) async {
    final availability = await _checkAvailability();
    emit(BiometricState.availabilityChecked(availability: availability));
  }

  Future<void> _onAuthenticate(
    AuthenticateEvent event,
    Emitter<BiometricState> emit,
  ) async {
    emit(const BiometricState.authenticating());

    final result = await _authenticate(
      reason: event.reason,
      sensitiveTransaction: event.sensitiveTransaction,
    );

    result.fold(
      (failure) => emit(BiometricState.failed(failure: failure)),
      (authenticated) => emit(authenticated
          ? const BiometricState.authenticated()
          : const BiometricState.cancelled()),
    );
  }
}

@freezed
class BiometricEvent with _$BiometricEvent {
  const factory BiometricEvent.checkAvailability() = CheckAvailabilityEvent;
  const factory BiometricEvent.authenticate({
    required String reason,
    @Default(false) bool sensitiveTransaction,
  }) = AuthenticateEvent;
}

@freezed
class BiometricState with _$BiometricState {
  const factory BiometricState.initial() = BiometricInitial;
  const factory BiometricState.availabilityChecked({
    required BiometricAvailability availability,
  }) = BiometricAvailabilityChecked;
  const factory BiometricState.authenticating() = BiometricAuthenticating;
  const factory BiometricState.authenticated() = BiometricAuthenticated;
  const factory BiometricState.cancelled() = BiometricCancelled;
  const factory BiometricState.failed({required BiometricFailure failure}) = BiometricFailed;
}
```

---

## Sensitive Operation Gate — Widget Pattern

```dart
// lib/core/auth/biometric/biometric_gate.dart
/// Wraps any action that requires biometric re-authentication.
class BiometricGate extends StatelessWidget {
  final String reason;
  final bool sensitiveTransaction;
  final Widget child;
  final VoidCallback onAuthenticated;
  final void Function(BiometricFailure)? onFailed;

  const BiometricGate({
    required this.reason,
    required this.child,
    required this.onAuthenticated,
    this.sensitiveTransaction = false,
    this.onFailed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<BiometricBloc>()
        ..add(const BiometricEvent.checkAvailability()),
      child: BlocListener<BiometricBloc, BiometricState>(
        listener: (context, state) {
          if (state is BiometricAuthenticated) {
            onAuthenticated();
          } else if (state is BiometricFailed) {
            _handleFailure(context, state.failure);
          }
        },
        child: GestureDetector(
          onTap: () => context.read<BiometricBloc>().add(
            BiometricEvent.authenticate(
              reason: reason,
              sensitiveTransaction: sensitiveTransaction,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  void _handleFailure(BuildContext context, BiometricFailure failure) {
    onFailed?.call(failure);

    failure.when(
      notAvailable: () => _showSnackbar(context, 'Biometrics not available'),
      notEnrolled: () => _showEnrollmentDialog(context),
      lockout: () => _showSnackbar(context, 'Too many attempts. Try again later.'),
      permanentLockout: () => _showSettingsDialog(context),
      cancelled: () => null, // user cancelled — no message needed
      failed: () => _showSnackbar(context, 'Authentication failed'),
      unknown: (msg) => _showSnackbar(context, 'Authentication error'),
    );
  }
}

// Usage — delete account button
BiometricGate(
  reason: 'Confirm your identity to delete your account.',
  sensitiveTransaction: true,
  onAuthenticated: () =>
      context.read<AccountBloc>().add(const AccountEvent.deleteRequested()),
  child: const ElevatedButton(
    onPressed: null, // handled by BiometricGate
    child: Text('Delete Account'),
  ),
)
```

---

## Testing

```dart
// test/core/auth/biometric/biometric_service_impl_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockBiometricService extends Mock implements BiometricService {}

void main() {
  late MockBiometricService mockService;

  setUp(() => mockService = MockBiometricService());

  group('BiometricService', () {
    test('returns Right(true) on successful authentication', () async {
      when(() => mockService.authenticate(
        reason: any(named: 'reason'),
        biometricOnly: any(named: 'biometricOnly'),
        sensitiveTransaction: any(named: 'sensitiveTransaction'),
      )).thenAnswer((_) async => const Right(true));

      final result = await mockService.authenticate(reason: 'Test');
      expect(result, const Right(true));
    });

    test('returns Left(lockout) on too many failures', () async {
      when(() => mockService.authenticate(
        reason: any(named: 'reason'),
        biometricOnly: any(named: 'biometricOnly'),
        sensitiveTransaction: any(named: 'sensitiveTransaction'),
      )).thenAnswer((_) async => const Left(BiometricFailure.lockout()));

      final result = await mockService.authenticate(reason: 'Test');
      expect(result.isLeft(), true);
      result.fold(
        (f) => expect(f, isA<BiometricLockout>()),
        (_) => fail('Expected failure'),
      );
    });
  });
}
```
