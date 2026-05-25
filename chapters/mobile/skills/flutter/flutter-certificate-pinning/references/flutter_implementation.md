# Flutter Implementation — Dio Certificate Pinning

## Dependencies

```yaml
dependencies:
  dio: ^5.8.0
  get_it: ^9.2.1
  injectable: ^3.0.0
  fpdart: ^1.2.0
```

No additional pinning package needed — Dio's `HttpClient` provides the hooks.

---

## Pin Configuration

```dart
// lib/core/network/pinning/pin_config.dart

/// Certificate pin configuration.
/// Always include current + backup pin to enable rotation without app update.
abstract final class PinConfig {
  /// Production API pins — SPKI SHA-256 hashes of the intermediate CA public key.
  /// Format: 'sha256/<base64-encoded-hash>'
  static const Set<String> productionPins = {
    'sha256/CURRENT_SPKI_HASH_BASE64==',  // current intermediate CA key
    'sha256/BACKUP_SPKI_HASH_BASE64==',   // backup — pre-staged for next rotation
  };

  /// Staging/QA pins — separate from production
  static const Set<String> stagingPins = {
    'sha256/STAGING_SPKI_HASH_BASE64==',
    'sha256/STAGING_BACKUP_HASH_BASE64==',
  };

  /// Hosts that require pinning
  static const Set<String> pinnedHosts = {
    'api.yourapp.com',
    'auth.yourapp.com',
  };
}
```

---

## Certificate Pinning Interceptor

```dart
// lib/core/network/pinning/certificate_pinning_interceptor.dart
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@injectable
class CertificatePinningInterceptor extends Interceptor {
  final Set<String> _pins;
  final Set<String> _pinnedHosts;

  CertificatePinningInterceptor({
    required Set<String> pins,
    required Set<String> pinnedHosts,
  })  : _pins = pins,
        _pinnedHosts = pinnedHosts;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Pinning is enforced at the HttpClient level (see DioFactory)
    // This interceptor can add additional request-level checks if needed
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Catch certificate errors and provide a clear failure message
    if (err.type == DioExceptionType.badCertificate) {
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          type: DioExceptionType.badCertificate,
          message: 'Certificate pinning failed for ${err.requestOptions.uri.host}. '
              'Connection rejected to prevent MITM attack.',
          error: err.error,
        ),
      );
      return;
    }
    handler.next(err);
  }
}
```

---

## Dio Factory with Pinning

```dart
// lib/core/network/dio_factory.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class DioFactory {
  final Set<String> _pins;
  final Set<String> _pinnedHosts;

  DioFactory({
    required Set<String> pins,
    required Set<String> pinnedHosts,
  })  : _pins = pins,
        _pinnedHosts = pinnedHosts;

  Dio create({required String baseUrl}) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));

    // ✅ Apply certificate pinning via HttpClient adapter
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = _validateCertificate;
      return client;
    };

    dio.interceptors.addAll([
      CertificatePinningInterceptor(
        pins: _pins,
        pinnedHosts: _pinnedHosts,
      ),
      // Add auth, logging interceptors here
    ]);

    return dio;
  }

  /// Validates the server certificate against pinned SPKI hashes.
  /// Returns false to REJECT the connection if pinning fails.
  bool _validateCertificate(X509Certificate cert, String host, int port) {
    // Only validate pinned hosts
    if (!_pinnedHosts.contains(host)) return true;

    final spkiHash = _computeSpkiHash(cert);
    final pinMatches = _pins.contains('sha256/$spkiHash');

    if (!pinMatches) {
      // Log the failure for monitoring — never silently accept
      _logPinningFailure(host, spkiHash);
    }

    // ✅ Return false = reject connection (MASVS-NETWORK-2 requirement)
    // Never return true on pin mismatch — that defeats the purpose
    return pinMatches;
  }

  /// Computes the SPKI SHA-256 hash of the certificate's public key.
  /// This is what we pin — not the full certificate.
  String _computeSpkiHash(X509Certificate cert) {
    // Extract the DER-encoded SubjectPublicKeyInfo from the certificate
    // The der property gives us the full certificate DER
    // We need to extract just the SPKI portion
    final derBytes = cert.der;
    final spkiBytes = _extractSpki(derBytes);
    final digest = sha256.convert(spkiBytes);
    return base64.encode(digest.bytes);
  }

  /// Extracts the SubjectPublicKeyInfo (SPKI) from a DER-encoded certificate.
  /// SPKI is the public key + algorithm identifier — stable across cert renewals.
  Uint8List _extractSpki(Uint8List certDer) {
    // Parse DER structure to find SPKI
    // Certificate structure: SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
    // tbsCertificate: SEQUENCE { version, serialNumber, ..., subjectPublicKeyInfo, ... }
    // This is a simplified extraction — use a proper ASN.1 parser in production
    return _parseSpkiFromDer(certDer);
  }

  Uint8List _parseSpkiFromDer(Uint8List der) {
    // Walk the DER structure to find the subjectPublicKeyInfo field
    // Position: Certificate > TBSCertificate > subjectPublicKeyInfo
    var offset = 0;

    // Skip outer SEQUENCE tag and length
    offset = _skipTagAndLength(der, offset);
    // Skip inner TBSCertificate SEQUENCE tag and length
    offset = _skipTagAndLength(der, offset);
    // Skip version [0] EXPLICIT if present
    if (der[offset] == 0xa0) offset = _skipTagAndLength(der, offset);
    // Skip serialNumber INTEGER
    offset = _skipTagAndLength(der, offset);
    // Skip signature AlgorithmIdentifier SEQUENCE
    offset = _skipTagAndLength(der, offset);
    // Skip issuer Name SEQUENCE
    offset = _skipTagAndLength(der, offset);
    // Skip validity SEQUENCE
    offset = _skipTagAndLength(der, offset);
    // Skip subject Name SEQUENCE
    offset = _skipTagAndLength(der, offset);

    // Now at subjectPublicKeyInfo SEQUENCE — extract it
    final spkiStart = offset;
    final spkiLength = _getLength(der, offset + 1);
    final spkiEnd = offset + 1 + _getLengthBytes(der, offset + 1) + spkiLength;

    return Uint8List.fromList(der.sublist(spkiStart, spkiEnd));
  }

  int _skipTagAndLength(Uint8List der, int offset) {
    offset++; // skip tag
    return offset + _getLengthBytes(der, offset) + _getLength(der, offset);
  }

  int _getLength(Uint8List der, int offset) {
    if (der[offset] < 0x80) return der[offset];
    final numBytes = der[offset] & 0x7f;
    var length = 0;
    for (var i = 0; i < numBytes; i++) {
      length = (length << 8) | der[offset + 1 + i];
    }
    return length;
  }

  int _getLengthBytes(Uint8List der, int offset) {
    if (der[offset] < 0x80) return 1;
    return 1 + (der[offset] & 0x7f);
  }

  void _logPinningFailure(String host, String actualHash) {
    // Send to your monitoring/alerting system
    // This may indicate an active MITM attack or a missed rotation
    debugPrint(
      '[SECURITY] Certificate pinning FAILED for $host. '
      'Actual SPKI hash: sha256/$actualHash. '
      'Expected one of: $_pins',
    );
  }
}
```

---

## DI Registration

```dart
// lib/core/di/network_module.dart
import 'package:injectable/injectable.dart';

@module
abstract class NetworkModule {
  @lazySingleton
  DioFactory dioFactory() => DioFactory(
    pins: kReleaseMode ? PinConfig.productionPins : PinConfig.stagingPins,
    pinnedHosts: PinConfig.pinnedHosts,
  );

  @lazySingleton
  Dio productionDio(DioFactory factory) =>
      factory.create(baseUrl: 'https://api.yourapp.com');
}
```

---

## Handling Pinning Failures in the Repository

```dart
// lib/features/product/data/repositories/product_repository_impl.dart

@override
Future<Either<Failure, List<Product>>> getProducts() async {
  try {
    final response = await _dio.get('/products');
    return Right(/* parse response */);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.badCertificate) {
      // ✅ Pinning failure — do NOT fall back to unverified connection
      return const Left(Failure.certificatePinningFailed(
        message: 'Secure connection could not be established. '
            'Please check your network and try again.',
      ));
    }
    return Left(Failure.network(message: e.message ?? 'Network error'));
  }
}
```

---

## Failure Type

```dart
// Add to your app's Failure union
@freezed
class Failure with _$Failure {
  // ... existing failures ...
  const factory Failure.certificatePinningFailed({required String message}) =
      CertificatePinningFailed;
}
```

---

## Testing Pinning

```dart
// test/core/network/certificate_pinning_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  group('CertificatePinningInterceptor', () {
    test('rejects connection with badCertificate error on pin mismatch', () async {
      final interceptor = CertificatePinningInterceptor(
        pins: {'sha256/EXPECTED_HASH=='},
        pinnedHosts: {'api.yourapp.com'},
      );

      final handler = MockErrorInterceptorHandler();
      final error = DioException(
        requestOptions: RequestOptions(path: 'https://api.yourapp.com/test'),
        type: DioExceptionType.badCertificate,
      );

      interceptor.onError(error, handler);

      verify(() => handler.reject(any())).called(1);
    });
  });
}
```
