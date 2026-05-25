---
name: flutter-secure-storage
description: >
  Implements secure local storage in Flutter for tokens, credentials, and sensitive data. Use this skill for storing auth tokens, API keys, user credentials, PII, or any sensitive data locally. Triggers on 'store token', 'save credentials', 'persist auth', 'secure storage', SharedPreferences with sensitive data (flag as insecure), logout (must clear all storage). Enforces OWASP MASVS-STORAGE-1 (formerly M2). Stack: flutter_secure_storage 10.0.0. Dart 3.3+ / Flutter 3.32+.
commands:
  - secure-storage
inputs:
  - name: action
    description: Action to perform (implement, audit, migrate). "implement" generates the token repository and secure storage setup, "audit" checks for insecure storage patterns (tokens in SharedPreferences, plain files, logs), "migrate" upgrades from flutter_secure_storage 9.x to 10.x.
    required: true
  - name: target
    description: Path to the file or feature directory to act on (e.g. lib/core/auth/ for implement, lib/ for audit).
    required: true
  - name: data_type
    description: Type of sensitive data being stored (auth-tokens, api-keys, credentials, pii, encryption-keys). Determines the storage pattern and platform options generated.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Secure Storage in Flutter

OWASP MASVS-STORAGE-1 compliance for local data persistence.

---

## Storage Decision Matrix

| Data | Sensitive? | Storage |
|---|---|---|
| Auth token, refresh token | ✅ Critical | `FlutterSecureStorage` |
| API keys, secrets | ✅ Critical | `FlutterSecureStorage` |
| PII (email, SSN, card number) | ✅ Critical | `FlutterSecureStorage` |
| Encryption keys for Isar / local DB | ✅ Critical | `FlutterSecureStorage` |
| Large encrypted datasets | ✅ Sensitive | Isar with encryption key stored in `FlutterSecureStorage` — see `flutter-database-strategy` |
| User preferences (theme, language) | ✅ Safe | `SharedPreferences` |
| Feature flags, onboarding state | ✅ Safe | `SharedPreferences` |

---

## Setup

```yaml
dependencies:
  flutter_secure_storage: ^10.0.0
```

### Android — disable Google Drive backup

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<application
  android:allowBackup="false"
  android:fullBackupContent="@xml/backup_rules"
  ...>
```

Create `android/app/src/main/res/xml/backup_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
  <!-- Exclude secure storage shared preferences from backup -->
  <exclude domain="sharedpref" path="FlutterSecureStorage" />
</full-backup-content>
```

Minimum Android SDK: **23** (Android 6.0).

### iOS — add to `Info.plist` if using biometric access

```xml
<key>NSFaceIDUsageDescription</key>
<string>Used to secure app data</string>
```

Minimum iOS: **12**.

---

## Token Repository Pattern

```dart
// lib/src/core/auth/token_repository.dart
abstract interface class TokenRepository {
  Future<void> saveTokens({required String access, required String refresh});
  Future<String?> getAccessToken();
  Future<String?> getRefreshToken();
  Future<bool> isExpired(String token);
  Future<String?> getValidAccessToken(); // auto-refreshes if needed
  Future<bool> refreshTokens();
  Future<void> clearTokens();
}
```

```dart
// lib/src/core/auth/token_repository_impl.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: TokenRepository)
class TokenRepositoryImpl implements TokenRepository {
  TokenRepositoryImpl()
      : _storage = const FlutterSecureStorage(
          // Android: RSA OAEP + AES-GCM via Android Keystore (default, no extra config)
          aOptions: AndroidOptions(),
          // iOS: available after first unlock — required for background tasks
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock,
          ),
        );

  final FlutterSecureStorage _storage;

  static const _accessKey  = 'access_token';
  static const _refreshKey = 'refresh_token';

  @override
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) =>
      Future.wait([
        _storage.write(key: _accessKey,  value: access),
        _storage.write(key: _refreshKey, value: refresh),
      ]);

  @override
  Future<String?> getAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<bool> isExpired(String token) async {
    try {
      final exp = _decodeExp(token);
      if (exp == null) return true;
      return DateTime.now().isAfter(
        DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      );
    } catch (_) {
      return true; // malformed token → treat as expired
    }
  }

  @override
  Future<String?> getValidAccessToken() async {
    final token = await getAccessToken();
    if (token == null) return null;

    final exp = _decodeExp(token);
    if (exp == null) return null;

    // Consider expired 5 minutes early for safety
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final isNearExpiry = DateTime.now()
        .isAfter(expiry.subtract(const Duration(minutes: 5)));

    if (isNearExpiry) {
      final refreshed = await refreshTokens();
      if (!refreshed) return null;
      return getAccessToken();
    }
    return token;
  }

  @override
  Future<bool> refreshTokens() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await getIt<ApiClient>().post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      await saveTokens(
        access:  data['access_token']  as String,
        refresh: data['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearTokens() => _storage.deleteAll();

  /// Decodes the `exp` claim from a JWT without any external dependency.
  /// JWTs are header.payload.signature — payload is base64url-encoded JSON.
  int? _decodeExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      // base64url → base64 (pad to multiple of 4)
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)))
          as Map<String, dynamic>;
      return payload['exp'] as int?;
    } catch (_) {
      return null;
    }
  }
}
```

---

## Android Biometric Storage (Optional)

For apps requiring biometric authentication to access stored data:

```dart
// Biometric with graceful degradation (recommended)
const biometricStorage = FlutterSecureStorage(
  aOptions: AndroidOptions.biometric(
    enforceBiometrics: false, // works without biometrics if unavailable
    biometricPromptTitle: 'Authenticate to access your data',
  ),
);

// Strict biometric enforcement (banking / high-security apps)
// Requires Android 9+ (API 28)
const strictBiometricStorage = FlutterSecureStorage(
  aOptions: AndroidOptions.biometric(
    enforceBiometrics: true,
    biometricPromptTitle: 'Authentication Required',
  ),
);
```

---

## Logout — Clear Everything

Logout **must** clear all secure storage, caches, and in-memory state.

```dart
// lib/src/features/auth/domain/use_cases/logout_use_case.dart
@injectable
class LogoutUseCase implements UseCaseNoParams<void> {
  const LogoutUseCase(this._tokenRepository);

  final TokenRepository _tokenRepository;

  @override
  Future<Either<Failure, void>> call() async {
    try {
      await Future.wait([
        _tokenRepository.clearTokens(),     // Keychain / Keystore
        DefaultCacheManager().emptyCache(),  // flutter_cache_manager image cache
        // Add your local DB clear here (e.g., Isar) if it holds user data
      ]);
      return const Right(null);
    } catch (e) {
      return Left(Failure.unknown(message: e.toString()));
    }
  }
}
```

---

## Storage Listeners (New in v10)

React to storage changes without polling:

```dart
final storage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

// Register
storage.registerListener(
  key: 'access_token',
  listener: (value) {
    if (value == null) {
      // Token was deleted — trigger logout flow
    }
  },
);

// Unregister when no longer needed
storage.unregisterListener(key: 'access_token', listener: myListener);

// Or clear all listeners at once
storage.unregisterAllListeners();
```

---

## What NEVER to Do

```dart
// ❌ FORBIDDEN — SharedPreferences for tokens
prefs.setString('auth_token', token);

// ❌ FORBIDDEN — global static variables
class AppState { static String authToken = ''; }

// ❌ FORBIDDEN — unencrypted local database for sensitive data
// (always store the DB encryption key in FlutterSecureStorage)

// ❌ FORBIDDEN — logging tokens
print('Token: $accessToken');
debugPrint('Auth: ${response.data}');

// ❌ FORBIDDEN — storing tokens in plain files
File('tokens.json').writeAsStringSync(jsonEncode(tokens));
```

---

## Platform Notes

### Android
- `AndroidOptions()` uses **RSA OAEP + AES-GCM** via Android Keystore — no extra config needed.
- Minimum SDK: **23** (Android 6.0).
- **Migration from 9.x:** `encryptedSharedPreferences` is deprecated. Use `AndroidOptions()` without parameters. Data migration is automatic with `migrateOnAlgorithmChange: true` (enabled by default in v10).
- Disable Google Drive backup to prevent key-related exceptions (see Setup above).

### iOS
- `IOSOptions(accessibility: KeychainAccessibility.first_unlock)` is required for background tasks (push notifications, background fetch).
- Default accessibility is `unlocked` — always override explicitly for auth tokens.
- For apps using App Groups, add `keychain-access-groups` to entitlements or writes will silently fail.
- See `references/keychain_advanced.md` for Keychain sharing, biometric access, and iCloud sync.

---

## Reference Files

- `references/secure_storage_testing.md` — mocking SecureStorage in unit tests, listener tests
- `references/keychain_advanced.md` — iOS Keychain sharing, access groups, biometric flags, accessibility levels
