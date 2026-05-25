# M5 — Insufficient Cryptography

This category covers the use of weak cryptographic algorithms or incorrect cryptographic implementations.

---

## Check M5-A: Weak cryptographic algorithms

**ID:** `M5-A-WEAK-CRYPTO`
**Objective:** Detect MD5, SHA-1, DES, RC4, and other weak algorithms.
**Scope:** `lib/**.dart`

**Method:** Lexical search
**Insecure patterns:**

```dart
// PATTERN 1: MD5 for passwords
import 'package:crypto/crypto.dart';

String hashPassword(String password) {
  return md5.convert(utf8.encode(password)).toString();  // ❌ MD5 is weak
}

// PATTERN 2: SHA-1 for sensitive data
final hash = sha1.convert(utf8.encode(data));  // ⚠️ SHA-1 is deprecated

// PATTERN 3: ECB mode (insecure)
final cipher = AES(key, mode: AESMode.ecb);  // ❌ ECB is not secure

// PATTERN 4: Key derived without a KDF
final key = utf8.encode(password);  // ❌ No KDF used
```

**Lexical search:**
```regex
md5\.convert.*password
\bsha1\.convert\b
\bDES\b|\bRC4\b|\bECB\b
AESMode\.ecb
utf8\.encode\(password\)(?!.*pbkdf2|argon2|scrypt)
```

**Criteria:**
- ❌ **Fail:** MD5/SHA-1 used for passwords or sensitive data
- ❌ **Fail:** Weak algorithms (DES, RC4, ECB mode)
- ⚠️ **Warning:** Key derivation without a KDF
- ✅ **Pass:** SHA-256+, AES-GCM, PBKDF2/Argon2

**Severity:** `HIGH`
**Automation:** 🟢 High (90%)

**Remediation:**

```dart
// ✅ SOLUTION 1: SHA-256 instead of MD5
import 'package:crypto/crypto.dart';

String hashData(String data) {
  return sha256.convert(utf8.encode(data)).toString();  // ✅ SHA-256
}

// ✅ SOLUTION 2: PBKDF2 for password hashing
import 'package:pointycastle/export.dart';

String hashPassword(String password, String salt) {
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(
    utf8.encode(salt),
    100000,  // ✅ 100k iterations minimum
    32,
  ));
  final key = pbkdf2.process(utf8.encode(password));
  return base64.encode(key);
}

// ✅ SOLUTION 3: AES-256-GCM instead of ECB
import 'package:pointycastle/export.dart';

class SecureEncryption {
  // Generate a 32-byte key using Random.secure()
  static Uint8List generateKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  // Generate a 12-byte nonce (IV) — never reuse
  static Uint8List generateNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(12, (_) => rng.nextInt(256)));
  }

  // Encrypt with AES-256-GCM
  static Uint8List encrypt(Uint8List plaintext, Uint8List key) {
    final nonce = generateNonce();
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));

    final ciphertext = cipher.process(plaintext);
    // Return nonce + ciphertext (both needed for decryption)
    return Uint8List.fromList([...nonce, ...ciphertext]);
  }

  // Decrypt
  static Uint8List decrypt(Uint8List data, Uint8List key) {
    final nonce = data.sublist(0, 12);
    final ciphertext = data.sublist(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(ciphertext);
  }
}
```

---

## Check M5-B: Hardcoded secrets and keys

**ID:** `M5-B-HARDCODED-SECRETS`
**Objective:** Detect API keys, tokens, and private keys in source code.
**Scope:** `lib/**.dart`, `android/**`, `ios/**`

**Method:** Lexical search with regex
**Patterns:**

```dart
// PATTERN 1: API keys
const API_KEY = 'AIzaSyC1234567890abcdefghijklmnop';  // ❌ Google API Key

// PATTERN 2: AWS credentials
const AWS_ACCESS_KEY = 'AKIAIOSFODNN7EXAMPLE';  // ❌ AWS key

// PATTERN 3: Stripe keys
const STRIPE_SECRET = 'sk_live_1234567890abcdefghijklmnop';  // ❌ Stripe secret

// PATTERN 4: Private keys
const PRIVATE_KEY = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...
-----END PRIVATE KEY-----
''';  // ❌❌ EXTREME DANGER
```

**Lexical search:**
```bash
# Google API Keys
grep -rE "AIza[0-9A-Za-z\-_]{35}" lib/ android/ ios/

# AWS Keys
grep -rE "AKIA[0-9A-Z]{16}" lib/ android/ ios/

# Stripe Keys
grep -rE "(sk|pk)_(live|test)_[0-9a-zA-Z]{24,}" lib/

# Generic secrets
grep -rE "(api[_-]?key|secret[_-]?key|password)\s*[:=]\s*['\"][^'\"]{16,}['\"]" lib/

# Private keys
grep -r "BEGIN.*PRIVATE KEY" lib/ android/ ios/

# JWT secrets
grep -rE "jwt[_-]?secret\s*[:=]" lib/

# Database URLs with credentials
grep -rE "mongodb://.*:.*@|postgres://.*:.*@|mysql://.*:.*@" lib/
```

**Criteria:**
- ❌ **Fail:** Any API key/secret pattern detected
- ❌ **Fail:** Private keys in source code
- ⚠️ **Warning:** Constants with suspicious names (`API_KEY`, `SECRET`)
- ✅ **Pass:** Environment variables or backend-fetched values

**Severity:** `CRITICAL`
**Automation:** 🟢 High (95%)

**Remediation:**

```dart
// ❌ NEVER do this
const API_KEY = 'AIzaSyC1234567890abcdefghijklmnop';

// ✅ SOLUTION 1: dart-define (compile-time injection)
// Build: flutter build apk --dart-define=API_KEY=your_key_here
class AppConfig {
  static const apiKey = String.fromEnvironment('API_KEY');

  static void validate() {
    if (apiKey.isEmpty) throw Exception('API_KEY not configured');
  }
}

void main() {
  AppConfig.validate();
  runApp(const MyApp());
}
```

```dart
// ✅ SOLUTION 2: Fetch from authenticated backend endpoint
class ApiKeyService {
  Future<String> getApiKey() async {
    final token = await _tokenRepository.getValidAccessToken();
    final response = await _apiClient.get(
      '/client/config',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return (response.data as Map<String, dynamic>)['api_key'] as String;
  }
}
```

```gitignore
# ✅ .gitignore — REQUIRED
.env
.env.local
.env.production
android/key.properties
ios/Runner/GoogleService-Info.plist
```

---

## M5 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M5-A | HIGH | 🟢 90% | Medium |
| M5-B | CRITICAL | 🟢 95% | Low |

**Total checks:** 2 | **Critical:** 1 | **High:** 1 | **Medium:** 0 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
