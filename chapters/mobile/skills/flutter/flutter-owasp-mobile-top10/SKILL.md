---
name: flutter-owasp-mobile-top10
description: >
  Audits and remediates Flutter apps against the OWASP Mobile Top 10 (2024). Use this
  skill when asking about mobile security, ''is this secure?'', ''security review'',
  ''OWASP'', security audit, vulnerability verification, or when implementing
  authentication, storage, network calls, cryptography, or authorization. Triggers on
  storing tokens, HTTP calls, handling user data, login/logout, or any security-sensitive
  operation. Reference: OWASP Mobile App Security project (mas.owasp.org), 2024 edition.
  Stack- flutter_secure_storage 10.x, Dart 3.8+ / Flutter 3.32+.
commands:
  - owasp-audit
inputs:
  - name: action
    description: Action to perform (scan, audit, remediate). "scan" runs quick grep-based detection for all M1-M10 categories, "audit" performs a deep review of a specific category, "remediate" applies fixes for identified vulnerabilities.
    required: true
  - name: target
    description: Path to the project root or specific directory to scan (e.g. lib/ for full scan, lib/features/auth/ for auth-specific audit).
    required: true
  - name: category
    description: Specific OWASP category to focus on (M1-M10, or "all"). M1=credentials, M2=supply-chain, M3=auth, M4=input-validation, M5=communication, M6=privacy, M7=binary, M8=misconfiguration, M9=storage, M10=cryptography.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# OWASP Mobile Top 10 — Flutter Audit

Complete security checklist M1–M10.

## Quick Scan — Run Before Every Release

```bash
bash scripts/owasp_scan.sh [path_to_project]
```

See `references/owasp_scan_script.md` for the complete script with explanations.

---

## M1 — Improper Credential Usage

**Risk:** Hardcoded credentials, tokens in source code, secrets in version control.

### Detection

```bash
# Google API Keys
grep -rE "AIza[0-9A-Za-z\-_]{35}" lib/ android/ ios/ --include="*.dart" --include="*.xml"

# AWS Keys
grep -rE "AKIA[0-9A-Z]{16}" lib/ --include="*.dart"

# Stripe Keys
grep -rE "(sk|pk)_(live|test)_[0-9a-zA-Z]{24,}" lib/ --include="*.dart"

# Generic hardcoded secrets
grep -rE "(apiKey|api_key|secret|password|token)\s*[=:]\s*['\"][a-zA-Z0-9+/=]{16,}['\"]" \
  lib/ --include="*.dart" | grep -v "fromEnvironment\|storage.read\|_storage"

# Private Keys
grep -r "BEGIN.*PRIVATE KEY" lib/ android/ ios/

# JWT secrets
grep -rE "jwt[_-]?secret\s*[:=]" lib/ --include="*.dart"
```

### Fix

```dart
// ❌ Never
const apiKey = 'AIzaSyC1234567890abcdefghijklmnop';

// ✅ dart-define (build-time injection)
// Build: flutter build apk --dart-define=API_KEY=value
class AppConfig {
  static const apiKey = String.fromEnvironment('API_KEY');
}

// ✅ Backend endpoint (runtime fetch — preferred for sensitive keys)
Future<String> getClientKey() async {
  final token = await _tokenRepository.getValidAccessToken();
  final resp = await _apiClient.get(
    '/client/config',
    options: Options(headers: {'Authorization': 'Bearer $token'}),
  );
  return (resp.data as Map<String, dynamic>)['api_key'] as String;
}
```

---

## M2 — Inadequate Supply Chain Security

**Risk:** Vulnerable or malicious third-party packages.

### Detection

```bash
# Check for known vulnerabilities (Dart 3.x)
dart pub audit

# Check outdated packages
dart pub outdated

# Review direct dependencies
grep -A100 "^dependencies:" pubspec.yaml
```

### Fix

```yaml
# pubspec.yaml — pin major versions, review changelogs before upgrading
dependencies:
  dio: ^5.9.2          # ✅ Pinned major
  flutter_bloc: ^9.1.1 # ✅ Pinned
  # ❌ Never: dio: latest, dio: any
```

```bash
# Run in CI — fail build on vulnerabilities
dart pub audit --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('vulnerabilities'):
    for v in data['vulnerabilities']:
        print(f'VULN: {v[\"name\"]} — {v[\"description\"]}')
    sys.exit(1)
print('No vulnerabilities found')
"
```

---

## M3 — Insecure Authentication/Authorization

**Risk:** Weak auth, tokens not validated, client-side auth bypass.

### Detection

```bash
# Tokens in SharedPreferences
grep -rE "prefs\.(setString|getString).*['\"].*token" lib/ --include="*.dart"

# No JWT expiry check
grep -rn "getString.*token" lib/ --include="*.dart" | grep -v "isExpired\|exp\|_decodeExp"

# Client-side role checks without backend validation
grep -rE "if\s*\([^)]*\.(role|isAdmin)\s*==" lib/src/features/*/presentation/ --include="*.dart"

# Auth bypass / backdoor
grep -rE "(bypassAuth|skipAuth|devLogin|admin@dev)" lib/ --include="*.dart" | grep -v test/
```

### Fix

```dart
// ✅ Validate token expiry before use — pure Dart, no external dependency
Future<String?> getValidAccessToken() async {
  final token = await _storage.read(key: 'access_token');
  if (token == null) return null;

  final exp = _decodeExp(token);
  if (exp == null) return null;

  final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  final isNearExpiry = DateTime.now()
      .isAfter(expiry.subtract(const Duration(minutes: 5)));

  if (isNearExpiry) return await _refreshToken();
  return token;
}

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

// ✅ Permissions validated by backend — client only sends the request
Future<void> onDeleteTapped(String userId) async {
  final result = await _deleteUserUseCase(DeleteUserParams(id: userId));
  result.fold(
    (f) => f.maybeMap(
      server: (e) => e.code == '403'
          ? _showError('Not authorized')
          : _showError(e.message),
      orElse: () => _showError(f.toString()),
    ),
    (_) => _showSuccess('User deleted'),
  );
}
```

---

## M4 — Insufficient Input/Output Validation

**Risk:** Injection attacks, XSS in WebViews, unvalidated deep links.

### Detection

```bash
# WebView without navigationDelegate
grep -rn "WebView\|WebViewController" lib/ --include="*.dart" | grep -v "navigationDelegate\|shouldOverrideUrl"

# JavaScript enabled without URL validation
grep -rn "javascriptMode.*unrestricted" lib/ --include="*.dart"

# Deep link URL not validated before navigation
grep -rn "router.navigate.*deepLink\|Uri.parse.*intent" lib/ --include="*.dart"
```

### Fix

```dart
// ✅ WebView with strict navigation control
WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setNavigationDelegate(NavigationDelegate(
    onNavigationRequest: (request) {
      final uri = Uri.parse(request.url);
      const allowedHosts = {'app.example.com', 'cdn.example.com'};
      if (!allowedHosts.contains(uri.host) || uri.scheme != 'https') {
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    },
  ));

// ✅ Validate deep link params before navigating
@override
void onNavigation(NavigationResolver resolver, StackRouter router) async {
  final id = resolver.route.pathParams.get('id');
  if (id == null || !_isValidId(id)) {
    resolver.redirect(const HomeRoute());
    return;
  }
  resolver.next();
}
```

---

## M5 — Insecure Communication

**Risk:** HTTP traffic, SSL bypass, missing certificate pinning.

### Detection

```bash
# HTTP URLs (not localhost)
grep -rE "http://(?!localhost|127\.0\.0\.1|10\.0\.)" lib/ --include="*.dart" | grep -v test/

# SSL bypass
grep -rE "badCertificateCallback.*=>\s*true" lib/ --include="*.dart"
grep -rE "onHttpClientCreate.*badCertificateCallback" lib/ --include="*.dart"

# Android cleartext
grep 'usesCleartextTraffic="true"' android/app/src/main/AndroidManifest.xml

# iOS ATS bypass
grep -A2 "NSAllowsArbitraryLoads" ios/Runner/Info.plist | grep "<true/>"
```

### Fix

```dart
// ✅ HTTPS only
final response = await _dio.get('https://api.example.com/products');

// ✅ Never disable SSL validation
(dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () =>
    HttpClient()..badCertificateCallback = (cert, host, port) => false;
```

```xml
<!-- ✅ AndroidManifest.xml -->
<application android:usesCleartextTraffic="false">
```

See `flutter-certificate-pinning` skill for pinning implementation.

---

## M6 — Inadequate Privacy Controls

**Risk:** PII in logs, analytics with personal data, insecure data exposure.

### Detection

```bash
# PII in logs
grep -rE "(print|debugPrint|logger\.(info|debug)).*\b(email|phone|ssn|password|token)\b" \
  lib/ --include="*.dart" | grep -v test/

# Sensitive data in crash reports without sanitization
grep -rn "FirebaseCrashlytics\|Sentry" lib/ --include="*.dart" | grep -v "sanitize\|redact"

# Analytics with user PII
grep -rn "logEvent\|setUserProperty" lib/ --include="*.dart" | grep -E "email|phone|name"
```

### Fix

```dart
// ✅ Never log sensitive data
// ❌ print('User email: $email');
// ✅ Log only non-sensitive identifiers
SecureLogger.log('User logged in: userId=${user.id}');

// ✅ Sanitize before crash reports
FirebaseCrashlytics.instance.setCustomKey('userId', user.id); // ID only
// ❌ FirebaseCrashlytics.instance.setCustomKey('email', user.email);
```

---

## M7 — Insufficient Binary Protections

**Risk:** Unobfuscated code, debug builds in production, missing ProGuard/R8.

### Detection

```bash
# Android — obfuscation disabled
grep -A10 'buildTypes' android/app/build.gradle | grep -A5 'release' | grep 'minifyEnabled false'

# Flutter — no obfuscation in CI
grep -r "flutter build apk\|flutter build appbundle" .github/workflows/ | grep -v "\-\-obfuscate"

# Debug mode in release build
grep -r 'android:debuggable="true"' android/app/src/main/AndroidManifest.xml
```

### Fix

```bash
# ✅ Always obfuscate release builds
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/symbols/android

flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols/android
```

```gradle
// ✅ android/app/build.gradle
buildTypes {
  release {
    minifyEnabled true
    shrinkResources true
    proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    debuggable false
  }
}
```

---

## M8 — Security Misconfiguration

**Risk:** Exported Android components, excessive permissions, backup enabled.

### Detection

```bash
# Exported components without permission
grep -E 'android:exported="true"' android/app/src/main/AndroidManifest.xml

# Backup enabled (exposes database, SharedPreferences)
grep 'android:allowBackup="true"' android/app/src/main/AndroidManifest.xml

# Excessive permissions
grep "uses-permission" android/app/src/main/AndroidManifest.xml | \
  grep -E "READ_CONTACTS|WRITE_EXTERNAL_STORAGE|READ_PHONE_STATE|PROCESS_OUTGOING_CALLS"
```

### Fix

```xml
<!-- ✅ Disable backup or use exclusion rules -->
<application
    android:allowBackup="false"
    android:fullBackupContent="false">

<!-- ✅ Non-public components must be unexported -->
<activity android:name=".InternalActivity" android:exported="false"/>

<!-- ✅ Remove unused permissions -->
```

---

## M9 — Insecure Data Storage

**Risk:** Tokens in SharedPreferences, unencrypted local DB, data in logs/temp files.

### Detection

```bash
# Tokens in SharedPreferences
grep -rE "SharedPreferences.*setString.*['\"].*token" lib/ --include="*.dart"

# Unencrypted SQLite
grep -rn "openDatabase\b" lib/ --include="*.dart" | grep -v "password:"

# Sensitive data in temp files
grep -rn "getTemporaryDirectory\|writeAsString" lib/ --include="*.dart"
```

### Fix

See `flutter-secure-storage` skill for complete implementation.

```dart
// ✅ FlutterSecureStorage for all tokens and credentials
await _secureStorage.write(key: 'access_token', value: token);
// ❌ prefs.setString('token', token);

// ✅ Isar with encryption key stored in FlutterSecureStorage for large datasets
// See flutter-database-strategy skill
```

---

## M10 — Insufficient Cryptography

**Risk:** Weak algorithms, hardcoded keys, insecure RNG.

### Detection

```bash
# MD5 for security
grep -rn "md5\.convert" lib/ --include="*.dart"

# SHA1
grep -rn "sha1\.convert" lib/ --include="*.dart"

# ECB mode
grep -rn "AESMode\.ecb" lib/ --include="*.dart"

# Insecure random
grep -rn "Random()" lib/ --include="*.dart" | grep -v "Random\.secure()"
```

### Fix

See `flutter-data-encryption` skill for complete implementation.

```dart
// ✅ AES-256-GCM for encryption (pointycastle 4.x)
// ✅ PBKDF2-SHA256 (≥100k iterations) for password hashing
// ✅ SHA-256 for checksums (crypto 3.x)
// ✅ Random.secure() for all cryptographic operations
// ❌ NEVER: MD5, SHA1, AES-ECB, DES, RC4, Random()
// ❌ NEVER: package:encrypt (unmaintained)
```

---

## Reference Files

- `references/owasp_scan_script.md` — Complete bash scan script with per-check explanations
- `references/owasp_masvs_checklist.md` — OWASP MASVS v2 verification checklist with Flutter-specific controls and MASWE weakness mapping
- `references/quick-reference.md` — Quick grep commands by severity for fast audits
