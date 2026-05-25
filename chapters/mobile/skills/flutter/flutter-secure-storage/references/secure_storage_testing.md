# Secure Storage Testing — flutter_secure_storage 10.x

> **v10 change:** The library ships `setMockInitialValues` and `TestFlutterSecureStoragePlatform`
> for testing without manual implementations. Do **not** implement `FlutterSecureStorage` manually.

---

## 1. setMockInitialValues — Standard Setup

Works like `SharedPreferences.setMockInitialValues`. Uses an in-memory store internally.
Call it in `setUp` (not `setUpAll`) to isolate each test.

```dart
// test/core/auth/token_repository_impl_test.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token':  'mock.access.token',
      'refresh_token': 'mock.refresh.token',
    });
  });

  test('read returns pre-seeded value', () async {
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'access_token'), 'mock.access.token');
  });

  test('write persists value in mock store', () async {
    const storage = FlutterSecureStorage();
    await storage.write(key: 'new_key', value: 'new_value');
    expect(await storage.read(key: 'new_key'), 'new_value');
  });

  test('delete removes value', () async {
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'access_token');
    expect(await storage.read(key: 'access_token'), isNull);
  });

  test('deleteAll clears all values', () async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();
    expect(await storage.readAll(), isEmpty);
  });

  test('containsKey returns correct result', () async {
    const storage = FlutterSecureStorage();
    expect(await storage.containsKey(key: 'access_token'), isTrue);
    expect(await storage.containsKey(key: 'nonexistent'), isFalse);
  });
}
```

---

## 2. Platform Interface Mock — Advanced Cases

Use when you need to simulate platform errors, latency, or verify exact call arguments.

```dart
// test/helpers/mock_secure_storage_platform.dart
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockSecureStoragePlatform extends Mock
    with MockPlatformInterfaceMixin
    implements FlutterSecureStoragePlatform {}
```

```dart
// test/core/auth/token_repository_error_test.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mock_secure_storage_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSecureStoragePlatform mockPlatform;

  setUp(() {
    mockPlatform = MockSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = mockPlatform;
  });

  test('read throws when Keychain is unavailable', () async {
    when(() => mockPlatform.read(
          key: any(named: 'key'),
          options: any(named: 'options'),
        )).thenThrow(Exception('Keychain unavailable'));

    const storage = FlutterSecureStorage();
    expect(() => storage.read(key: 'token'), throwsException);
  });

  test('write is called with correct key and value', () async {
    when(() => mockPlatform.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          options: any(named: 'options'),
        )).thenAnswer((_) async {});

    const storage = FlutterSecureStorage();
    await storage.write(key: 'token', value: 'abc123');

    verify(() => mockPlatform.write(
          key: 'token',
          value: 'abc123',
          options: any(named: 'options'),
        )).called(1);
  });
}
```

---

## 3. Repository Mock — Testing Use Cases

For use case tests, mock `TokenRepository` (the interface), not `FlutterSecureStorage`.

```dart
// test/mocks/mocks.dart
class MockTokenRepository extends Mock implements TokenRepository {}
```

```dart
// test/features/auth/domain/use_cases/logout_use_case_test.dart
void main() {
  late MockTokenRepository mockTokenRepo;
  late LogoutUseCase sut;

  setUp(() {
    mockTokenRepo = MockTokenRepository();
    sut = LogoutUseCase(mockTokenRepo);
  });

  test('clears tokens on success', () async {
    when(() => mockTokenRepo.clearTokens()).thenAnswer((_) async {});

    final result = await sut();

    expect(result.isRight(), isTrue);
    verify(() => mockTokenRepo.clearTokens()).called(1);
  });

  test('returns Left(Failure) when clearTokens throws', () async {
    when(() => mockTokenRepo.clearTokens())
        .thenThrow(Exception('Keychain locked'));

    final result = await sut();

    expect(result.isLeft(), isTrue);
  });
}
```

---

## 4. TokenRepositoryImpl Integration Tests

Test the real implementation against the in-memory mock store.

```dart
// test/core/auth/token_repository_impl_test.dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TokenRepositoryImpl sut;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    sut = TokenRepositoryImpl();
  });

  test('saveTokens persists both tokens', () async {
    await sut.saveTokens(access: 'a.b.c', refresh: 'x.y.z');

    expect(await sut.getAccessToken(),  'a.b.c');
    expect(await sut.getRefreshToken(), 'x.y.z');
  });

  test('isExpired returns true for expired JWT', () async {
    final expired = _buildJwt(DateTime.now().subtract(const Duration(hours: 1)));
    expect(await sut.isExpired(expired), isTrue);
  });

  test('isExpired returns true within 5-minute buffer', () async {
    // Expires in 3 minutes — within the 5-minute safety buffer
    final almostExpired = _buildJwt(DateTime.now().add(const Duration(minutes: 3)));
    expect(await sut.isExpired(almostExpired), isTrue);
  });

  test('isExpired returns false for valid token', () async {
    final valid = _buildJwt(DateTime.now().add(const Duration(hours: 1)));
    expect(await sut.isExpired(valid), isFalse);
  });

  test('isExpired returns true for malformed token', () async {
    expect(await sut.isExpired('not.a.jwt'), isTrue);
  });

  test('clearTokens removes all data', () async {
    await sut.saveTokens(access: 'a', refresh: 'r');
    await sut.clearTokens();

    expect(await sut.getAccessToken(),  isNull);
    expect(await sut.getRefreshToken(), isNull);
  });

  test('getValidAccessToken returns null when no token stored', () async {
    expect(await sut.getValidAccessToken(), isNull);
  });
}

/// Builds a minimal JWT with a specific expiry for testing.
String _buildJwt(DateTime expiry) {
  final exp     = expiry.millisecondsSinceEpoch ~/ 1000;
  final header  = base64UrlEncode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = base64UrlEncode(utf8.encode('{"exp":$exp,"sub":"test"}'));
  return '$header.$payload.fake_signature';
}
```

---

## 5. Listener Tests (v10)

```dart
// test/core/storage/listener_test.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterSecureStorage storage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = const FlutterSecureStorage();
  });

  test('listener is notified on write', () async {
    String? notified;
    storage.registerListener(
      key: 'access_token',
      listener: (value) => notified = value,
    );

    await storage.write(key: 'access_token', value: 'new_token');
    expect(notified, 'new_token');
  });

  test('listener receives null on delete', () async {
    await storage.write(key: 'access_token', value: 'existing');

    String? notified = 'not_null';
    storage.registerListener(
      key: 'access_token',
      listener: (value) => notified = value,
    );

    await storage.delete(key: 'access_token');
    expect(notified, isNull);
  });

  test('unregisterListener stops notifications', () async {
    var callCount = 0;
    void onChanged(String? _) => callCount++;

    storage.registerListener(key: 'k', listener: onChanged);
    await storage.write(key: 'k', value: 'v1');
    expect(callCount, 1);

    storage.unregisterListener(key: 'k', listener: onChanged);
    await storage.write(key: 'k', value: 'v2');
    expect(callCount, 1); // did not increment
  });

  test('unregisterAllListeners clears everything', () {
    storage.registerListener(key: 'a', listener: (_) {});
    storage.registerListener(key: 'b', listener: (_) {});
    storage.unregisterAllListeners();

    expect(storage.getListeners, isEmpty);
  });

  test('getListeners exposes registered listeners', () {
    void onChanged(String? _) {}
    storage.registerListener(key: 'k', listener: onChanged);

    expect(storage.getListeners.containsKey('k'), isTrue);
    expect(storage.getListeners['k'], contains(onChanged));
  });
}
```

---

## Rules

- Call `setMockInitialValues` in `setUp`, not `setUpAll` — each test needs a clean store
- Do **not** implement `FlutterSecureStorage` manually — use `setMockInitialValues` or the platform interface mock
- For use case tests, mock `TokenRepository` (the interface), not `FlutterSecureStorage`
- For `TokenRepositoryImpl` tests, use `setMockInitialValues` so the real implementation runs against the in-memory store
- `TestWidgetsFlutterBinding.ensureInitialized()` is required in any test using platform channels
