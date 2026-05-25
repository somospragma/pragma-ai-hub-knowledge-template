# Platform Setup — Android and iOS

## Android

### MainActivity — FlutterFragmentActivity (required)

```kotlin
// android/app/src/main/kotlin/com/example/app/MainActivity.kt
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

// ✅ MUST extend FlutterFragmentActivity — NOT FlutterActivity
// local_auth uses Android's BiometricPrompt which requires a FragmentActivity
class MainActivity : FlutterFragmentActivity()
```

### AndroidManifest.xml

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Required for biometric authentication -->
    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>

    <!-- Legacy fingerprint — Android 9 and below (optional) -->
    <!-- <uses-permission android:name="android.permission.USE_FINGERPRINT"/> -->

    <application ...>
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme">
            ...
        </activity>
    </application>
</manifest>
```

### build.gradle — minimum SDK

```groovy
// android/app/build.gradle
android {
    defaultConfig {
        minSdk 24  // local_auth requires Android 6.0+ (API 24)
        targetSdk 35
        compileSdk 35
    }
}
```

### Android BiometricType behavior

| BiometricType | Android behavior |
|---|---|
| `BiometricType.fingerprint` | Fingerprint sensor |
| `BiometricType.face` | Face recognition (device-specific) |
| `BiometricType.strong` | Class 3 biometric (high security) — use for sensitive operations |
| `BiometricType.weak` | Class 2 biometric (lower security) — avoid for payments/sensitive ops |

```dart
// ✅ Prefer strong biometrics for sensitive operations
final biometrics = await _auth.getAvailableBiometrics();
final hasStrong = biometrics.contains(BiometricType.strong)
    || biometrics.contains(BiometricType.face);

if (!hasStrong) {
  // Offer PIN/password fallback for sensitive operations
  // biometricOnly: false allows device PIN/pattern as fallback
}
```

---

## iOS

### Info.plist

```xml
<!-- ios/Runner/Info.plist -->
<dict>
    <!-- Required for Face ID — Touch ID does not need a separate key -->
    <key>NSFaceIDUsageDescription</key>
    <string>Used to authenticate securely and protect your account.</string>
</dict>
```

### iOS BiometricType behavior

| BiometricType | iOS behavior |
|---|---|
| `BiometricType.face` | Face ID (iPhone X+, iPad Pro) |
| `BiometricType.fingerprint` | Touch ID (older iPhones, MacBook) |
| `BiometricType.strong` | Not used on iOS — use `face` or `fingerprint` |

```dart
// iOS: check for Face ID or Touch ID specifically
final biometrics = await _auth.getAvailableBiometrics();
final hasFaceId = biometrics.contains(BiometricType.face);
final hasTouchId = biometrics.contains(BiometricType.fingerprint);
```

### iOS fallback behavior

On iOS, `biometricOnly: false` allows the device passcode as fallback.
`biometricOnly: true` shows only the biometric prompt — no passcode option.

```dart
// For login — allow passcode fallback
await _auth.authenticate(
  localizedReason: 'Sign in to your account',
  options: const AuthenticationOptions(biometricOnly: false),
);

// For sensitive operations — biometric only, no passcode
await _auth.authenticate(
  localizedReason: 'Confirm payment',
  options: const AuthenticationOptions(
    biometricOnly: true,
    sensitiveTransaction: true,
  ),
);
```

---

## Dialog Customization

```dart
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

final authenticated = await _auth.authenticate(
  localizedReason: 'Confirm your identity to view your balance',
  options: const AuthenticationOptions(
    biometricOnly: false,
    stickyAuth: true,
    sensitiveTransaction: true,
  ),
  authMessages: const [
    AndroidAuthMessages(
      signInTitle: 'Authentication required',
      biometricHint: 'Touch the fingerprint sensor',
      biometricNotRecognized: 'Fingerprint not recognized. Try again.',
      biometricRequiredTitle: 'Biometric required',
      cancelButton: 'Cancel',
      deviceCredentialRequiredTitle: 'Device credential required',
      goToSettingsButton: 'Settings',
      goToSettingsDescription: 'Please set up biometrics in Settings.',
    ),
    IOSAuthMessages(
      cancelButton: 'Cancel',
      goToSettingsButton: 'Settings',
      goToSettingsDescription: 'Please set up Face ID or Touch ID in Settings.',
      lockOut: 'Biometrics disabled. Please unlock using your passcode.',
    ),
  ],
);
```

---

## Background Handling — persistAcrossBackgrounding

```dart
// ✅ Use when the user might receive a call or switch apps during auth
final authenticated = await _auth.authenticate(
  localizedReason: 'Confirm your identity',
  options: const AuthenticationOptions(
    stickyAuth: true,  // wait for app to foreground again, then retry
    biometricOnly: false,
  ),
);
```

---

## LocalAuthExceptionCode — Complete Reference

```dart
try {
  final result = await _auth.authenticate(localizedReason: 'Authenticate');
} on LocalAuthException catch (e) {
  switch (e.code) {
    case LocalAuthExceptionCode.noBiometricHardware:
      // Device has no biometric hardware
      break;
    case LocalAuthExceptionCode.notEnrolled:
      // Hardware present but no biometrics enrolled
      // → Offer to open Settings to enroll
      break;
    case LocalAuthExceptionCode.temporaryLockout:
      // Too many failed attempts — temporary lockout
      // → Show "try again in X seconds" message
      break;
    case LocalAuthExceptionCode.biometricLockout:
      // Permanent lockout — requires device PIN to unlock
      // → Show "use PIN to unlock" message
      break;
    case LocalAuthExceptionCode.passcodeNotSet:
      // No device passcode set (iOS) — biometrics require passcode
      // → Guide user to set up passcode in Settings
      break;
    case LocalAuthExceptionCode.lockedOut:
      // Device is locked out
      break;
    default:
      // Other errors
      break;
  }
}
```

---

## Enrollment Change Detection (MASVS-AUTH-3)

When the user adds or removes a fingerprint/face, the stored token should be
invalidated to prevent unauthorized access with a newly enrolled biometric.

```dart
// lib/core/auth/biometric/enrollment_change_detector.dart
@injectable
class EnrollmentChangeDetector {
  final SecureStorageService _storage;
  final LocalAuthentication _auth;

  EnrollmentChangeDetector(this._storage) : _auth = LocalAuthentication();

  Future<bool> hasEnrollmentChanged() async {
    final biometrics = await _auth.getAvailableBiometrics();
    final currentHash = _computeHash(biometrics);
    final storedHash = (await _storage.read(
      SecureStorageKeys.biometricEnrollmentHash,
    )).getOrElse((_) => null);

    if (storedHash == null) {
      await _storeHash(currentHash);
      return false;
    }

    if (storedHash != currentHash) {
      await _storeHash(currentHash);
      return true; // enrollment changed — invalidate token
    }

    return false;
  }

  String _computeHash(List<BiometricType> biometrics) =>
      biometrics.map((b) => b.name).toList()
        ..sort()
        ..join(',');

  Future<void> _storeHash(String hash) =>
      _storage.write(SecureStorageKeys.biometricEnrollmentHash, hash);
}

// Usage in app startup / resume:
Future<void> _onAppResumed() async {
  if (await _enrollmentDetector.hasEnrollmentChanged()) {
    // Biometric enrollment changed — force re-login
    await _authRepository.logout();
    context.go('/login');
    _showMessage('Security settings changed. Please sign in again.');
  }
}
```
