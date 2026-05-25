# RSA & ECDSA Patterns — pointycastle 4.x

> **pointycastle 4.0.0 changes:**
> - `generateKeyPair()` now returns typed `AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>` — no casting needed.
> - Added `OAEPEncoding.withSHA512()` factory.
> - New cipher engines: Blowfish, Camellia, Twofish.
> - New OIDs for secp256r1.

---

## RSA-OAEP Key Generation + Encryption

```dart
// lib/core/crypto/rsa_service.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class RsaService {
  /// Generate RSA key pair (4096-bit recommended, 2048 minimum).
  /// In pointycastle 4.x, generics are built-in — no casting needed.
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateKeyPair({
    int bitLength = 4096,
  }) {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), bitLength, 64),
        _secureRandom(),
      ));
    return keyGen.generateKeyPair();
  }

  /// Encrypt with RSA-OAEP-SHA256 (recommended default)
  Uint8List encryptOaepSha256(Uint8List data, RSAPublicKey publicKey) {
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return _processInBlocks(cipher, data);
  }

  /// Decrypt with RSA-OAEP-SHA256
  Uint8List decryptOaepSha256(Uint8List ciphertext, RSAPrivateKey privateKey) {
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return _processInBlocks(cipher, ciphertext);
  }

  /// Encrypt with RSA-OAEP-SHA512 (new factory in pointycastle 4.0)
  Uint8List encryptOaepSha512(Uint8List data, RSAPublicKey publicKey) {
    final cipher = OAEPEncoding.withSHA512(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return _processInBlocks(cipher, data);
  }

  /// Decrypt with RSA-OAEP-SHA512
  Uint8List decryptOaepSha512(Uint8List ciphertext, RSAPrivateKey privateKey) {
    final cipher = OAEPEncoding.withSHA512(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return _processInBlocks(cipher, ciphertext);
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher cipher, Uint8List data) {
    final output = <int>[];
    var offset = 0;
    while (offset < data.length) {
      final end = (offset + cipher.inputBlockSize).clamp(0, data.length);
      output.addAll(cipher.process(data.sublist(offset, end)));
      offset = end;
    }
    return Uint8List.fromList(output);
  }

  SecureRandom _secureRandom() {
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    return FortunaRandom()..seed(KeyParameter(seed));
  }
}
```

---

## ECDSA Signing (ES256 — secp256r1)

```dart
// lib/core/crypto/ecdsa_service.dart
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class EcdsaService {
  static final _curve = ECCurve_secp256r1();

  /// Generate ECDSA key pair on secp256r1 (P-256)
  AsymmetricKeyPair<ECPublicKey, ECPrivateKey> generateKeyPair() {
    final keyGen = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(_curve),
        _secureRandom(),
      ));
    return keyGen.generateKeyPair();
  }

  /// Sign data with ECDSA-SHA256
  ECSignature sign(Uint8List data, ECPrivateKey privateKey) {
    final signer = ECDSASigner(SHA256Digest())
      ..init(true, PrivateKeyParameter<ECPrivateKey>(privateKey));
    return signer.generateSignature(data) as ECSignature;
  }

  /// Verify ECDSA-SHA256 signature
  bool verify(Uint8List data, ECSignature signature, ECPublicKey publicKey) {
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(publicKey));
    return verifier.verifySignature(data, signature);
  }

  SecureRandom _secureRandom() {
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    return FortunaRandom()..seed(KeyParameter(seed));
  }
}
```

---

## RSA-PSS Signing (Preferred over PKCS#1 v1.5)

```dart
/// Sign with RSA-PSS-SHA256 (more secure than PKCS#1 v1.5 signatures)
Uint8List signPss(Uint8List data, RSAPrivateKey privateKey) {
  final signer = PSSSigner(RSAEngine(), SHA256Digest(), SHA256Digest())
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final sig = signer.generateSignature(data) as PSSSignature;
  return sig.bytes;
}

/// Verify RSA-PSS-SHA256 signature
bool verifyPss(
  Uint8List data,
  Uint8List signatureBytes,
  RSAPublicKey publicKey,
) {
  final signer = PSSSigner(RSAEngine(), SHA256Digest(), SHA256Digest())
    ..init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
  return signer.verifySignature(data, PSSSignature(signatureBytes));
}
```

---

## Forbidden Patterns

```dart
// ❌ RSA-PKCS1v1.5 encryption (vulnerable to padding oracle attacks)
final cipher = PKCS1Encoding(RSAEngine()); // NEVER for new code

// ❌ Key size < 2048 bits
RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64); // NEVER

// ❌ Insecure random for key generation
final rng = FortunaRandom()
  ..seed(KeyParameter(Uint8List.fromList([1, 2, 3]))); // NEVER — use Random.secure()

// ❌ Casting key pairs (unnecessary in pointycastle 4.x)
final pair = keyGen.generateKeyPair();
final pub = pair.publicKey as RSAPublicKey; // Not needed — already typed in 4.x
```
