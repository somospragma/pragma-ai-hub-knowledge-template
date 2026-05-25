# M2 — Insecure Data Storage

This category covers insecure storage of sensitive data on the device, including plaintext storage, unencrypted databases, and cache leakage.

---

## Check M2-A: Sensitive data stored in plaintext

**ID:** `M2-A-PLAINTEXT-STORAGE`
**Objective:** Prevent tokens, passwords, and PII from being saved in unencrypted storage.
**Scope:** `lib/**.dart`

**Method:** Semantic + lexical search
**Insecure patterns:**

```dart
// PATTERN 1: SharedPreferences with sensitive data
SharedPreferences prefs = await SharedPreferences.getInstance();
prefs.setString('token', authToken);        // ❌ INSECURE
prefs.setString('password', userPass);      // ❌ INSECURE
prefs.setString('api_key', apiKey);         // ❌ INSECURE
prefs.setString('refresh_token', refresh);  // ❌ INSECURE

// PATTERN 2: File storage without encryption
final file = File('${dir.path}/credentials.txt');
await file.writeAsString(token);            // ❌ INSECURE

// PATTERN 3: Isar without encryption key for sensitive data
final isar = await Isar.open([UserSchema]);  // ❌ INSECURE if it stores sensitive data
```

**Lexical search:**
```regex
SharedPreferences.*\.(setString|setInt)\s*\(\s*['"](?:token|password|secret|key|credential|pin|ssn|credit)
File\(.*\)\.writeAsString\([^)]*(?:token|password|secret)
```

**Criteria:**
- ❌ **Fail:** Sensitive data in SharedPreferences, File, or unencrypted database
- ✅ **Pass:** Use of `FlutterSecureStorage` for tokens; Isar with encryption key for datasets

**Severity:** `CRITICAL`
**Automation:** 🟢 High (90%)

**Remediation:**

```dart
// ✅ SOLUTION: FlutterSecureStorage (Keychain/Keystore)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

// Save
await storage.write(key: 'access_token', value: token);
await storage.write(key: 'refresh_token', value: refreshToken);

// Read
final token = await storage.read(key: 'access_token');

// Clear on logout
await storage.deleteAll();
```

```dart
// ✅ For large sensitive datasets: Isar with encryption key from SecureStorage
// See flutter-database-strategy skill for complete implementation
// The encryption key must be stored in FlutterSecureStorage, never hardcoded
```

**Allowed false positives:**
```dart
// OK: Non-sensitive data in SharedPreferences
prefs.setBool('theme_mode_dark', true);   // OK
prefs.setString('language', 'en');        // OK
prefs.setInt('onboarding_completed', 1);  // OK
```

---

## Check M2-B: Unencrypted local database

**ID:** `M2-B-UNENCRYPTED-DB`
**Objective:** Detect SQLite/Drift/Isar without encryption for sensitive data.
**Scope:** `lib/**.dart`, `pubspec.yaml`

**Method:** Lexical search for imports + semantic search
**Detection:**

```dart
// INSECURE PATTERN: sqflite without encryption
import 'package:sqflite/sqflite.dart';

final database = await openDatabase('app.db');  // ⚠️ No password

// Storing sensitive data
await db.insert('users', {
  'email': email,
  'token': authToken,  // ⚠️ INSECURE
});
```

**Lexical search:**
```regex
import\s+['"]package:sqflite/sqflite\.dart['"](?!.*sqlcipher)
openDatabase\s*\([^)]*\)(?!.*password)
Isar\.open\b(?!.*encryptionKey)
```

**Criteria:**
- ❌ **Fail:** `sqflite` used without `sqlcipher` + sensitive data detected
- ❌ **Fail:** Isar opened without `encryptionKey` for sensitive data
- ✅ **Pass:** Encryption key provided, stored in `FlutterSecureStorage`

**Severity:** `CRITICAL`
**Automation:** 🟢 High (85%)

**Remediation:**

```dart
// ✅ SOLUTION: Isar with encryption key from SecureStorage
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';

Future<Isar> openSecureIsar() async {
  const storage = FlutterSecureStorage(aOptions: AndroidOptions());
  const keyName = 'isar_enc_key';

  var keyHex = await storage.read(key: keyName);
  if (keyHex == null) {
    // Generate a 32-byte key and store it securely
    final key = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    keyHex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await storage.write(key: keyName, value: keyHex);
  }

  return Isar.open(
    [UserSchema, TransactionSchema],
    encryptionKey: keyHex,  // ✅ Encrypted
  );
}
```

```dart
// ✅ sqflite_sqlcipher if sqflite is required
import 'package:sqflite_sqlcipher/sqflite.dart';

final database = await openDatabase(
  'app.db',
  password: encryptionKey,  // ✅ Encrypted
  version: 1,
);
```

---

## Check M2-C: Sensitive data in cache and temporary files

**ID:** `M2-C-CACHE-LEAKAGE`
**Objective:** Detect persistence of sensitive data in cache or temp directories.
**Scope:** `lib/**.dart`

**Method:** Semantic search
**Patterns:**

```dart
// PATTERN 1: Temporary directory with sensitive data
final tempDir = await getTemporaryDirectory();
final file = File('${tempDir.path}/token.txt');
await file.writeAsString(token);  // ⚠️ INSECURE

// PATTERN 2: CachedNetworkImage with auth headers
CachedNetworkImage(
  imageUrl: 'https://api.com/user/avatar',
  httpHeaders: {'Authorization': 'Bearer $token'},  // ⚠️ Token may be cached
)
```

**Criteria:**
- ⚠️ **Warning:** Temporary files with potentially sensitive data
- ❌ **Fail:** Image cache with authentication headers

**Severity:** `MEDIUM`
**Automation:** 🟡 Medium (65%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Avoid caching with auth headers
// Use signed URLs or a backend proxy instead of passing auth headers
// to CachedNetworkImage

// ✅ SOLUTION 2: Clear all sensitive data on logout
Future<void> clearSensitiveData() async {
  // Clear secure storage
  await const FlutterSecureStorage().deleteAll();

  // Clear image cache
  await DefaultCacheManager().emptyCache();

  // Clear custom temp files
  final tempDir = await getTemporaryDirectory();
  if (tempDir.existsSync()) {
    tempDir.deleteSync(recursive: true);
  }
}
```

---

## M2 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M2-A | CRITICAL | 🟢 90% | High |
| M2-B | CRITICAL | 🟢 85% | High |
| M2-C | MEDIUM | 🟡 65% | Medium |

**Total checks:** 3 | **Critical:** 2 | **High:** 0 | **Medium:** 1 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
