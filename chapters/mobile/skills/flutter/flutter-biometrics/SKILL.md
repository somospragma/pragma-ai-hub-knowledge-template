---
name: flutter-biometrics
description: >
  Implements biometric authentication (Face ID, fingerprint) in Flutter using local_auth 2.x for login and re-authentication of sensitive operations. Covers the correct security pattern: biometrics gate access to a token stored in flutter_secure_storage — they never replace the token. Includes MASVS-AUTH compliance, fallback to PIN/passcode, lockout handling, and passkeys (FIDO2) as the modern alternative. Use this skill when implementing biometric login, re-authentication before sensitive operations (payments, account deletion), or passkey-based login.
commands:
  - setup-biometrics
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the full biometric authentication setup (service, use case, BLoC integration, platform config), "audit" checks existing biometric implementation for security issues (token not gated, missing lockout handling, wrong Activity base class).
    required: true
  - name: target
    description: Path to the auth/biometric directory or project root (e.g. lib/core/auth/ for implement, . for audit including platform files).
    required: true
  - name: approach
    description: Authentication approach to implement (local-auth, passkeys, both). Defaults to local-auth.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Biometric Authentication

See the reference files for complete patterns and code examples.

## Package Status (April 2026)

```yaml
dependencies:
  local_auth: ^2.3.0
  flutter_secure_storage: ^10.0.0  # store the token biometrics protect
  # passkeys: ^2.x.x               # optional — FIDO2/WebAuthn alternative
```

---

## The Correct Security Model

```
❌ WRONG: biometrics replace the auth token
   User authenticates → biometric success → user is "logged in"
   (no server-side token, no session — easily bypassed)

✅ CORRECT: biometrics gate access to a stored token
   Login → server issues token → token stored in flutter_secure_storage
   App resume → biometric prompt → success → token retrieved → API calls proceed
   Biometric failure → token stays locked → user must re-login
```

**Biometrics are a local convenience mechanism, not a server-side authentication factor.**

---

## Authentication Approaches (2026)

| Approach | Use when | Security level |
|---|---|---|
| **local_auth** (biometric gate) | Protect locally stored token | Medium — local only |
| **Passkeys (FIDO2/WebAuthn)** | Passwordless login with server verification | High — phishing-resistant |
| **Biometric + PIN fallback** | When biometrics may be unavailable | Medium |

> **If the project uses a FIDO2 provider (Corbado, custom relying party, etc.),
> use the `FidoProvider` Strategy + Adapter pattern** described in
> `references/passkeys.md`. This makes swapping providers a single DI binding
> change — plug-and-play. Never couple the domain layer to a specific FIDO SDK.

---

## MASVS-AUTH Requirements

| Control | Requirement |
|---|---|
| MASVS-AUTH-1 | Biometrics must not be the sole authentication factor for sensitive operations |
| MASVS-AUTH-2 | Tokens stored in platform-backed secure storage (Keychain/Keystore) |
| MASVS-AUTH-3 | Biometric enrollment changes must invalidate stored credentials |
| MASVS-AUTH-3 | Lockout after repeated failures must be enforced |

---

## Core Patterns — Quick Reference

### Check availability
```dart
final canCheck = await _auth.canCheckBiometrics;
final isSupported = await _auth.isDeviceSupported();
final biometrics = await _auth.getAvailableBiometrics();
final hasStrong = biometrics.contains(BiometricType.strong)
    || biometrics.contains(BiometricType.face);
```

### Authenticate with new LocalAuthException API
```dart
try {
  final authenticated = await _auth.authenticate(
    localizedReason: 'Confirm your identity to continue',
    options: const AuthenticationOptions(
      biometricOnly: true,
      stickyAuth: true,
      sensitiveTransaction: true,
    ),
  );
} on LocalAuthException catch (e) {
  switch (e.code) {
    case LocalAuthExceptionCode.biometricLockout:
    case LocalAuthExceptionCode.temporaryLockout:
      // Too many failures — show lockout message
    case LocalAuthExceptionCode.notEnrolled:
      // No biometrics enrolled — offer PIN fallback
    case LocalAuthExceptionCode.noBiometricHardware:
      // Device doesn't support biometrics
  }
}
```

### Gate a sensitive operation
```dart
Future<void> _onDeleteAccountTapped() async {
  final result = await _biometricUseCase();
  if (!mounted) return;
  result.fold(
    (failure) => _showError(failure),
    (authenticated) {
      if (authenticated) {
        context.read<AccountBloc>().add(const AccountEvent.deleteRequested());
      }
    },
  );
}
```

---

## Android Setup

```kotlin
// android/app/src/main/kotlin/.../MainActivity.kt
// ✅ Must extend FlutterFragmentActivity — NOT FlutterActivity
class MainActivity : FlutterFragmentActivity()
```

```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```

## iOS Setup

```xml
<!-- Info.plist -->
<key>NSFaceIDUsageDescription</key>
<string>Used to authenticate securely and protect your account.</string>
```

---

## Quick Wins Checklist

- [ ] `MainActivity` extends `FlutterFragmentActivity` (Android)
- [ ] `NSFaceIDUsageDescription` in `Info.plist` (iOS)
- [ ] Token stored in `flutter_secure_storage` — biometrics only gate access to it
- [ ] `LocalAuthException` handled (not `PlatformException`)
- [ ] `biometricOnly: true` for sensitive operations
- [ ] `stickyAuth: true` to survive app backgrounding
- [ ] Lockout states handled (`biometricLockout`, `temporaryLockout`)
- [ ] `notEnrolled` state offers PIN/passcode fallback
- [ ] Biometric enrollment changes invalidate stored token (MASVS-AUTH-3)

## Reference Files

- `references/biometric_service.md` — BiometricService, use cases, BLoC, token gate pattern, enrollment change detection
- `references/platform_setup.md` — Android (FlutterFragmentActivity, manifest), iOS (Info.plist, Podfile), dialog customization
- `references/passkeys.md` — FIDO2/WebAuthn passkeys as modern alternative to password + biometric
