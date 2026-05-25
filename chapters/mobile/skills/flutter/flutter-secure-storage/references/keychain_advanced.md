# iOS Keychain — Advanced Configuration

Advanced Keychain guide for `flutter_secure_storage` 10.x on iOS and macOS.

> **v10 note:** iOS and macOS share a unified implementation in `flutter_secure_storage_darwin`.
> `IOSOptions` and `MacOsOptions` both inherit from `AppleOptions`. Keychain operations
> now use a **serial queue** for thread safety. A **privacy manifest** is included automatically.

---

## Keychain Accessibility Levels

| Level | Available when | Migrates to new device | Recommended for |
|---|---|---|---|
| `passcode` | Only with active passcode | ❌ No | Ultra-sensitive keys (biometric private keys) |
| `unlocked` | Device unlocked only | ✅ Yes | **IOSOptions default** — active session data |
| `unlocked_this_device` | Unlocked, no migration | ❌ No | Temporary sensitive data |
| `first_unlock` | After first unlock post-boot | ✅ Yes | **Auth tokens (recommended)** |
| `first_unlock_this_device` | Same as above, no migration | ❌ No | Tokens that must not migrate to another device |

> The default `IOSOptions` accessibility is `unlocked`. For auth tokens, **always** specify
> `first_unlock` explicitly — it is required for background fetch and push notification handlers.

```dart
// Auth tokens — available after first unlock (background-safe)
const authStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);

// Device-bound tokens — do not migrate on backup/restore
const deviceBoundStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

// Maximum security — requires active passcode
const highSecurityStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.passcode,
  ),
);
```

---

## Keychain Access Groups (Sharing Between Apps)

Share Keychain data between multiple apps from the same development team.

### 1. Enable Keychain Sharing in Xcode

For each app that needs to share data:
1. Target → Signing & Capabilities → **+ Capability** → **Keychain Sharing**
2. Add the same Keychain Group (e.g., `com.mycompany.shared`)

This updates `*.entitlements`:

```xml
<!-- ios/Runner/Runner.entitlements -->
<key>keychain-access-groups</key>
<array>
  <string>$(AppIdentifierPrefix)com.mycompany.shared</string>
</array>
```

> **Important:** If you use App Groups and do not define `keychain-access-groups` in entitlements,
> writes will appear to succeed but data will never actually be persisted.

### 2. Configure flutter_secure_storage with Access Group

```dart
const sharedStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'com.mycompany.app',
    groupId: '$(AppIdentifierPrefix)com.mycompany.shared',
  ),
);

// Write — accessible from any app in the group
await sharedStorage.write(key: 'shared_token', value: token);

// Read from another app with the same groupId
final token = await sharedStorage.read(key: 'shared_token');
```

---

## iCloud Keychain Sync

Sync items across a user's devices via iCloud Keychain:

```dart
const syncedStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    synchronizable: true,
  ),
);
```

> **⚠️ Do not use `synchronizable: true` for session tokens or device-specific data.**
> Use it only for data the user expects on all their devices (e.g., encrypted preferences).

> **v10 fix:** `delete` and `deleteAll` now work correctly when `synchronizable` is enabled.
> In earlier versions, synced items were not deleted properly.

---

## Biometric Protection (AccessControlFlag)

`flutter_secure_storage` 10.x exposes biometric protection via `accessControlFlags`
on `AppleOptions`.

### Available Flags

| Flag | Description |
|---|---|
| `devicePasscode` | Requires device passcode |
| `biometryAny` | Requires Touch ID / Face ID (any enrolled biometry) |
| `biometryCurrentSet` | Requires currently enrolled biometry — invalidated if biometry changes |
| `userPresence` | Requires biometry **or** passcode (recommended for UX) |
| `watch` | Requires paired Apple Watch |
| `or` | Combines flags with OR |
| `and` | Combines flags with AND |
| `applicationPassword` | Uses app-provided password for encryption |

```dart
// Biometry or passcode — best UX with fallback
const flexibleBiometricStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    accessControlFlags: [AccessControlFlag.userPresence],
  ),
);

// Any enrolled biometry — no passcode fallback
const biometricOnlyStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    accessControlFlags: [AccessControlFlag.biometryAny],
  ),
);

// Current biometry set — invalidated if user adds/removes fingerprint or face
// Use for transaction signing in banking apps
const strictBiometricStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.unlocked,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  ),
);
```

Required in `Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>Used to secure app data</string>
```

> **Note:** `accessControlFlags` is only compatible with `accessibility: unlocked` or
> `accessibility: passcode`. It is **not** compatible with `first_unlock`.

---

## Full IOSOptions Reference

```dart
const storage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
    accountName: 'com.myapp.auth',   // kSecAttrService — groups related items
    groupId: null,                    // kSecAttrAccessGroup — for cross-app sharing
    synchronizable: false,            // kSecAttrSynchronizable — iCloud sync
    label: 'Auth Tokens',            // kSecAttrLabel — visible in Keychain tools
    description: 'Authentication tokens for MyApp', // kSecAttrDescription
    // accessControlFlags: [],        // Only with unlocked / passcode
  ),
);
```

---

## Migrating Between Accessibility Levels

If you change the accessibility level, existing items must be migrated manually.

> **v10 fix:** Migration now works correctly when a key already exists with a different
> accessibility option. Earlier versions failed silently.

```dart
class KeychainMigrator {
  static Future<void> migrate({
    required FlutterSecureStorage from,
    required FlutterSecureStorage to,
    required List<String> keys,
  }) async {
    for (final key in keys) {
      final value = await from.read(key: key);
      if (value != null) {
        await to.write(key: key, value: value);
        await from.delete(key: key);
      }
    }
  }
}
```

---

## Logout — Clear All Keychain Data

Clear items from **all** access groups used by the app.

> **v10 fix:** `deleteAll` now correctly removes items regardless of `synchronizable`
> state and accessibility restrictions.

```dart
Future<void> clearAllKeychainData() async {
  // Primary storage
  const mainStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  await mainStorage.deleteAll();

  // Shared storage (if applicable)
  const sharedStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
      groupId: '$(AppIdentifierPrefix)com.mycompany.shared',
    ),
  );
  await sharedStorage.deleteAll();
}
```

---

## Debugging Keychain State (Development Only)

```dart
Future<void> debugKeychainState() async {
  assert(() {
    _printKeychainStatus();
    return true;
  }());
}

Future<void> _printKeychainStatus() async {
  const storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final all = await storage.readAll();
  debugPrint('Keychain key count: ${all.length}');
  // Log key names only — NEVER log values
  for (final key in all.keys) {
    debugPrint('  Key present: $key');
  }
}
```

---

## Common Errors

| Error | Cause | Solution |
|---|---|---|
| `errSecItemNotFound` (-25300) | Key does not exist | Verify write used the same `accessibility` and `groupId` |
| `errSecDuplicateItem` (-25299) | Key exists with different accessibility | v10 handles automatically; if it persists, delete and re-write |
| `errSecAuthFailed` (-25293) | Biometric authentication failed | Use `userPresence` instead of `biometryAny` for passcode fallback |
| `errSecInteractionNotAllowed` (-25308) | Device locked + restrictive accessibility | Use `first_unlock` instead of `unlocked` |
| Items not deleted | `synchronizable` enabled on versions < 10 | Upgrade to v10 |
| Silent write failure | App Groups active but `keychain-access-groups` missing from entitlements | Add correct entitlements in Xcode |
