---
name: flutter-data-encryption
description: >
  Implements cryptography and data encryption in Flutter: AES-256-GCM at-rest encryption, PBKDF2/Argon2 password hashing, SHA-256 checksums, and asymmetric cryptography (RSA-OAEP, ECDSA). Use this skill for any cryptographic operation. Triggers on 'encrypt data', 'hash passwor', 'AES', 'RSA', 'ECDSA', OWASP M10 (Insufficient Cryptography), or protecting data confidentiality and integrity. Always rejects weak algorithms: MD5, SHA-1, AES-ECB, DES, RC4, Random() for crypto. For storing encryption keys and tokens, see flutter-secure-storage. For certificate pinning, see flutter-certificate-pinning. Stack: pointycastle, crypto. Dart 3.8+ / Flutter 3.32+.
commands:
  - setup-encryption
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the encryption service, password hasher, and hash service with correct algorithms, "audit" checks existing code for weak algorithms (MD5, SHA-1, ECB, insecure Random, hardcoded keys).
    required: true
  - name: target
    description: Path to the core/crypto directory or project root (e.g. lib/core/crypto/ for implement, lib/ for audit).
    required: true
  - name: algorithm
    description: Specific algorithm to implement (aes-gcm, pbkdf2, sha256, hmac, rsa-oaep, ecdsa, all). Defaults to all.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Data Encryption in Flutter

OWASP M10 (Insufficient Cryptography) compliance. Always use modern algorithms.

> **Only two cryptographic dependencies:** `pointycastle` for symmetric/asymmetric
> encryption, key derivation, and signatures. `crypto` for hashing (SHA-256, HMAC).
> Do not use `encrypt` — it wraps pointycastle but hides critical parameters like
> nonce and authentication tag, removing explicit control over NIST parameters.

---

## Algorithm Decision Table

| Use case | Algorithm | Forbidden |
|---|---|---|
| Symmetric encryption | AES-256-GCM (12-byte nonce, 128-bit tag) | DES, RC4, AES-ECB, AES-CBC |
| Password hashing | PBKDF2-SHA256 (≥310k iter) or Argon2id | MD5, SHA-1, SHA-256 plain |
| Data integrity | SHA-256, SHA-512, HMAC-SHA256 | MD5, SHA-1 |
| Key derivation | PBKDF2-SHA256, Argon2 | Simple hash |
| Asymmetric encryption | RSA-OAEP-SHA256/SHA512 | RSA-PKCS1v1.5 |
| Digital signatures | ECDSA-SHA256 (secp256r1), RSA-PSS-SHA256 | RSA-PKCS1v1.5 signatures |
| CSPRNG | `Random.secure()` | `Random()` |

---

## Dependencies

```yaml
dependencies:
  pointycastle: ^4.0.0   # AES-GCM, PBKDF2, RSA, ECDSA
  crypto: ^3.0.7          # SHA-256, SHA-512, HMAC
```

> **Key storage is not a concern of this skill.** Encryption keys must be stored
> in `FlutterSecureStorage` (Keychain/Keystore). See `flutter-secure-storage` skill.
> The `EncryptionService` below receives the key as a parameter — the caller
> is responsible for fetching it from secure storage.

---

## AES-256-GCM — At-Rest Encryption

```dart
// lib/src/core/crypto/encryption_service.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

abstract interface class EncryptionService {
  /// Encrypts [plaintext] using the provided [key].
  /// Returns "base64(nonce):base64(ciphertext+tag)".
  String encrypt(String plaintext, Uint8List key);

  /// Decrypts a value produced by [encrypt].
  /// Throws [FormatException] on invalid format.
  /// Throws [InvalidCipherTextException] on authentication failure (tampered data).
  String decrypt(String ciphertext, Uint8List key);
}

class AesGcmEncryptionService implements EncryptionService {
  static const _nonceLength = 12; // 96-bit per NIST SP 800-38D
  static const _tagBits = 128;    // Authentication tag length

  @override
  String encrypt(String plaintext, Uint8List key) {
    // ✅ Unique nonce per encryption — NEVER reuse
    final nonce = Uint8List.fromList(
      List.generate(_nonceLength, (_) => Random.secure().nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input); // ciphertext || 16-byte auth tag
    // Format: base64(nonce):base64(ciphertext+tag)
    return '${base64Encode(nonce)}:${base64Encode(output)}';
  }

  @override
  String decrypt(String ciphertext, Uint8List key) {
    final parts = ciphertext.split(':');
    if (parts.length != 2) throw const FormatException('Invalid ciphertext format');
    final nonce = Uint8List.fromList(base64Decode(parts[0]));
    final encrypted = Uint8List.fromList(base64Decode(parts[1]));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)),
      );
    // GCM validates the auth tag automatically — throws InvalidCipherTextException
    // if the data has been tampered with
    final decrypted = cipher.process(encrypted);
    return utf8.decode(decrypted);
  }
}
```

### Wiring with key from FlutterSecureStorage

The caller fetches the key from secure storage and passes it to the service.
This keeps the crypto layer pure and testable without mocking storage.

```dart
// lib/src/core/crypto/encryption_key_provider.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class EncryptionKeyProvider {
  EncryptionKeyProvider(this._storage);
  final FlutterSecureStorage _storage;

  static const _keyStorageKey = 'aes_master_key_v1';
  static const _keyLength = 32; // AES-256

  Uint8List? _cachedKey;

  Future<Uint8List> getOrCreateKey() async {
    if (_cachedKey != null) return _cachedKey!;
    var keyB64 = await _storage.read(key: _keyStorageKey);
    if (keyB64 == null) {
      final key = Uint8List.fromList(
        List.generate(_keyLength, (_) => Random.secure().nextInt(256)),
      );
      keyB64 = base64Encode(key);
      await _storage.write(key: _keyStorageKey, value: keyB64);
    }
    _cachedKey = base64Decode(keyB64) as Uint8List;
    return _cachedKey!;
  }
}

// Usage in a repository or use case:
// final key = await _keyProvider.getOrCreateKey();
// final encrypted = _encryptionService.encrypt(sensitiveData, key);
```

---

## PBKDF2-SHA256 — Password Hashing

```dart
// lib/src/core/crypto/password_hasher.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class PasswordHasher {
  static const _iterations = 310000; // NIST SP 800-132 recommendation (2024)
  static const _keyLength = 32;      // 256-bit output
  static const _saltLength = 16;     // 128-bit salt

  /// Returns "base64(salt):base64(hash)"
  String hash(String password) {
    final salt = _generateSalt();
    final hash = _pbkdf2(utf8.encode(password), salt);
    return '${base64Encode(salt)}:${base64Encode(hash)}';
  }

  bool verify(String password, String storedHash) {
    final parts = storedHash.split(':');
    if (parts.length != 2) return false;
    final salt = base64Decode(parts[0]);
    final expected = base64Decode(parts[1]);
    final actual = _pbkdf2(utf8.encode(password), salt);
    return _constantTimeEquals(actual, expected);
  }

  Uint8List _pbkdf2(List<int> password, Uint8List salt) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    kdf.init(Pbkdf2Parameters(salt, _iterations, _keyLength));
    return kdf.process(Uint8List.fromList(password));
  }

  Uint8List _generateSalt() {
    final rng = FortunaRandom()
      ..seed(KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ));
    return rng.nextBytes(_saltLength);
  }

  // ✅ Constant-time comparison prevents timing attacks
  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
    return diff == 0;
  }
}
```

---

## SHA-256 & HMAC — Integrity

```dart
// lib/src/core/crypto/hash_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class HashService {
  String sha256Of(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  String sha256OfBytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  String hmacSha256(String message, String secretKey) {
    final hmac = Hmac(sha256, utf8.encode(secretKey));
    return hmac.convert(utf8.encode(message)).toString();
  }

  bool verifyHmac(String message, String secretKey, String expectedHmac) {
    final actual = hmacSha256(message, secretKey);
    // Constant-time comparison
    if (actual.length != expectedHmac.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHmac.codeUnitAt(i);
    }
    return diff == 0;
  }
}
```

---

## Forbidden Patterns (auto-reject)

```dart
// ❌ MD5 for any security purpose
md5.convert(data); // NEVER for security

// ❌ SHA-1
sha1.convert(data); // NEVER for passwords or signatures

// ❌ AES-ECB (leaks data patterns)
final ecb = PaddedBlockCipher('AES/ECB/PKCS7'); // NEVER

// ❌ Insecure random
Random().nextInt(256); // NEVER for crypto — use Random.secure()

// ❌ Hardcoded key
const encKey = 'my_secret_key_1234'; // NEVER — use FlutterSecureStorage

// ❌ Reusing nonce (catastrophic in GCM)
final nonce = Uint8List(12); // all zeros — NEVER reuse a nonce

// ❌ encrypt package (hides critical GCM parameters)
import 'package:encrypt/encrypt.dart'; // NEVER — use pointycastle directly

// ❌ RSA-PKCS1v1.5 encryption (padding oracle attacks)
final cipher = PKCS1Encoding(RSAEngine()); // NEVER for new code
```

---

## Reference Files

- `references/rsa_patterns.md` — RSA key generation, OAEP encryption (SHA-256/SHA-512), ECDSA signing, RSA-PSS
- `references/secret_scanning.md` — Regex patterns to detect hardcoded secrets in CI
