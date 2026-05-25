# Secure Storage & Encryption Keys

`flutter_secure_storage` is not a database — use it for small amounts of sensitive
string data: tokens, API keys, and database encryption keys.

Backed by **Keychain** on iOS and **Keystore / EncryptedSharedPreferences** on Android.

## Setup

```yaml
dependencies:
  flutter_secure_storage: ^10.0.0
```

## Service

```dart
// lib/core/security/secure_storage_service.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@lazySingleton
class SecureStorageService {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  Future<Either<StorageFailure, Unit>> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return const Right(unit);
    } catch (e) {
      return Left(StorageFailure.writeFailed(message: '$e'));
    }
  }

  Future<Either<StorageFailure, String?>> read(String key) async {
    try {
      return Right(await _storage.read(key: key));
    } catch (e) {
      return Left(StorageFailure.readFailed(message: '$e'));
    }
  }

  Future<Either<StorageFailure, Unit>> delete(String key) async {
    try {
      await _storage.delete(key: key);
      return const Right(unit);
    } catch (e) {
      return Left(StorageFailure.deleteFailed(message: '$e'));
    }
  }

  Future<Either<StorageFailure, Unit>> deleteAll() async {
    try {
      await _storage.deleteAll();
      return const Right(unit);
    } catch (e) {
      return Left(StorageFailure.deleteFailed(message: '$e'));
    }
  }
}

// Key constants — avoid magic strings
abstract final class SecureStorageKeys {
  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const dbEncryptionKey = 'db_encryption_key';
  static const userId = 'user_id';
}
```

## Generating a Database Encryption Key

Use this pattern to generate and persist a random key for SQLCipher (Drift) or Isar encryption.
The key is generated once and stored securely — never hardcoded.

```dart
// lib/core/security/db_encryption_key_provider.dart
import 'dart:convert';
import 'dart:math';
import 'package:injectable/injectable.dart';

@lazySingleton
class DbEncryptionKeyProvider {
  final SecureStorageService _storage;
  DbEncryptionKeyProvider(this._storage);

  Future<String> getOrCreate() async {
    final result = await _storage.read(SecureStorageKeys.dbEncryptionKey);

    return result.fold(
      (_) => _generateAndStore(),
      (stored) async => stored ?? await _generateAndStore(),
    );
  }

  Future<String> _generateAndStore() async {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64Url.encode(keyBytes);
    await _storage.write(SecureStorageKeys.dbEncryptionKey, key);
    return key;
  }
}
```

## Usage with Drift (SQLCipher)

```dart
// In AppDatabase — retrieve key before opening connection
@singleton
class AppDatabase extends _$AppDatabase {
  AppDatabase._(QueryExecutor e) : super(e);

  @factoryMethod
  static Future<AppDatabase> create(DbEncryptionKeyProvider keyProvider) async {
    final key = await keyProvider.getOrCreate();
    return AppDatabase._(_openEncryptedConnection(key));
  }

  static QueryExecutor _openEncryptedConnection(String key) =>
      driftDatabase(
        name: 'app_database_encrypted',
        native: DriftNativeOptions(
          setup: (db) => db.execute("PRAGMA key = '$key'"),
        ),
      );
}
```

## Usage with Isar

```dart
@singleton
class IsarDatabase {
  @factoryMethod
  static Future<IsarDatabase> create(DbEncryptionKeyProvider keyProvider) async {
    final instance = IsarDatabase();
    final key = await keyProvider.getOrCreate();
    await instance._init(encryptionKey: key);
    return instance;
  }

  Future<void> _init({String? encryptionKey}) async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [ProductCollectionSchema],
      directory: dir.path,
      encryptionKey: encryptionKey,
    );
  }
}
```
