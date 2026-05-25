# M4 — Insecure Authentication

This category covers incorrect implementation of authentication and session management.

---

## Check M4-A: Insecure session and token management

**ID:** `M4-A-SESSION-MANAGEMENT`
**Objective:** Detect insecure token storage and missing expiry validation.
**Scope:** `lib/**.dart`

**Method:** Semantic search
**Insecure patterns:**

```dart
// PATTERN 1: Token in SharedPreferences
final prefs = await SharedPreferences.getInstance();
prefs.setString('auth_token', token);       // ❌ INSECURE
prefs.setString('refresh_token', refresh);  // ❌ INSECURE

// PATTERN 2: JWT without expiry validation
String getToken() {
  return prefs.getString('token');  // ❌ Does not check expiry
}

// PATTERN 3: Token in global static variable
class AppState {
  static String authToken = '';  // ❌ INSECURE
}

// PATTERN 4: No session expiry handling
Future<void> makeApiCall() async {
  final response = await http.get(
    Uri.parse('https://api.example.com/data'),
    headers: {'Authorization': 'Bearer $token'},  // ❌ Expiry not validated
  );
}

// PATTERN 5: Refresh token without rotation
Future<String> refreshAccessToken() async {
  final refreshToken = prefs.getString('refresh_token');
  final response = await http.post(...);
  final newAccessToken = response.data['access_token'];
  prefs.setString('auth_token', newAccessToken);  // ❌ Refresh token not rotated
  return newAccessToken;
}
```

**Lexical search:**
```regex
SharedPreferences.*setString.*['\"](?:auth_)?token['\"]
prefs\.getString\(['\"]token['\"].*(?!.*isExpired|expired|exp|_decodeExp)
static\s+String\s+.*token
```

**Criteria:**
- ❌ **Fail:** Tokens in SharedPreferences or global static variables
- ❌ **Fail:** JWT expiry not validated before use
- ⚠️ **Warning:** Refresh token without rotation
- ✅ **Pass:** Tokens in `FlutterSecureStorage` + expiry validation

**Severity:** `HIGH`
**Automation:** 🟡 Medium (60%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Secure storage with FlutterSecureStorage
// Pure Dart JWT expiry check — no external library needed
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenRepositoryImpl implements TokenRepository {
  const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await Future.wait([
      _storage.write(key: 'access_token', value: accessToken),
      _storage.write(key: 'refresh_token', value: refreshToken),
    ]);
  }

  // ✅ Validate expiry with 5-minute buffer — pure Dart
  Future<String?> getValidAccessToken() async {
    final token = await _storage.read(key: 'access_token');
    if (token == null) return null;

    final exp = _decodeExp(token);
    if (exp == null) return null;

    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final isNearExpiry = DateTime.now()
        .isAfter(expiry.subtract(const Duration(minutes: 5)));

    if (isNearExpiry) return await _refreshTokens();
    return token;
  }

  // ✅ Refresh with token rotation
  Future<String?> _refreshTokens() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null) { await clearTokens(); return null; }

    try {
      final response = await getIt<ApiClient>().post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data as Map<String, dynamic>;
      await saveTokens(
        data['access_token'] as String,
        data['refresh_token'] as String,  // ✅ Rotate refresh token
      );
      return data['access_token'] as String;
    } catch (_) {
      await clearTokens();
      return null;
    }
  }

  Future<void> clearTokens() => _storage.deleteAll();

  int? _decodeExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
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

```dart
// ✅ SOLUTION 2: Dio interceptor with automatic refresh
class AuthInterceptor extends Interceptor {
  final TokenRepository _tokenRepository;
  final _mutex = Mutex(); // synchronized package

  AuthInterceptor(this._tokenRepository);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _tokenRepository.getValidAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // ✅ Retry once with refreshed token
      await _mutex.protect(() async {
        final newToken = await _tokenRepository.getValidAccessToken();
        if (newToken != null) {
          err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          try {
            final response = await Dio().fetch(err.requestOptions);
            handler.resolve(response);
            return;
          } catch (_) {}
        }
        await _tokenRepository.clearTokens();
      });
    }
    handler.next(err);
  }
}
```

```dart
// ✅ SOLUTION 3: Biometric re-authentication for sensitive operations
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  final _localAuth = LocalAuthentication();

  Future<bool> authenticateForSensitiveOperation() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;

      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to continue',
        options: const AuthenticationOptions(
          useErrorDialogs: true,
          stickyAuth: true,
          biometricOnly: true,  // ✅ Biometrics only, no PIN fallback
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
```

---

## M4 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M4-A | HIGH | 🟡 60% | High |

**Total checks:** 1 | **Critical:** 0 | **High:** 1 | **Medium:** 0 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
