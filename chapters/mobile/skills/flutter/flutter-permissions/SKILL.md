---
name: flutter-permissions
description: >
  Handles runtime permissions in Flutter with permission_handler 11.x: request at point of use, rationale dialogs, settings redirect, and platform manifest configuration. Includes store policy constraints: Google Play (April 2026 location/contacts policy, Android 17 Contact Picker requirement), App Store (usage description strings, Podfile macros), and AppGallery (standard Android permissions). Use this skill when requesting camera, location, microphone, contacts, notifications, storage, or any sensitive permission.
commands:
  - setup-permissions
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the permission service, use case, and platform configuration for the specified permissions, "audit" checks existing permission handling for policy violations, missing rationale, or incorrect manifest entries.
    required: true
  - name: target
    description: Path to the core/permissions directory or feature where permissions will be integrated (e.g. lib/core/permissions/ or lib/features/camera/).
    required: true
  - name: permissions
    description: Comma-separated list of permissions to handle (camera, location, microphone, contacts, notifications, storage, photos, bluetooth, all). Use "all" to generate the full permission service covering every declared permission.
    required: true
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Runtime Permissions

See the reference files for complete patterns and code examples.

**Rule #1: Request permissions at the point of use — never at app startup.**
**Rule #2: Only request permissions your app genuinely needs for core functionality.**

## Package Status (April 2026)

```yaml
dependencies:
  permission_handler: ^11.3.1
```

`compileSdkVersion 35` required in `android/app/build.gradle`.

---

## Store Policy Constraints (April 2026)

### Google Play
| Policy | Requirement | Enforcement |
|---|---|---|
| Minimum scope | Request only the permission level needed (e.g., coarse location before precise) | Active |
| Location button | Precise location should use the system location button where possible | April 2026 |
| Background location | Only if core feature requires it — must justify in Play Console | Active |
| READ_CONTACTS (Android 17+) | Must use Contact Picker first; READ_CONTACTS only if picker is insufficient | Android 17 / API 37 |
| Sensitive permissions | Must be directly tied to core app functionality — no advertising/analytics use | Active |
| Pre-review checks | Play Console flags location/contacts policy issues before submission | Oct 2026 |

### App Store (iOS)
| Policy | Requirement |
|---|---|
| Usage description | Every permission needs a clear, specific `NS*UsageDescription` string |
| Purpose strings | Must explain exactly why the app needs the permission — vague strings rejected |
| Tracking (ATT) | `NSUserTrackingUsageDescription` required before any cross-app tracking |
| Always location | `NSLocationAlwaysAndWhenInUseUsageDescription` — requires strong justification |
| Podfile macros | Only enable permissions you actually use — reduces binary size and review risk |

### AppGallery (Huawei)
- Standard Android permissions apply — same `permission_handler` works
- Huawei devices without GMS: `permission_handler` works for system permissions
- HMS-specific features (location kit, push) require HMS SDK separately

---

## Permission Status Flow

```
check() → granted          → proceed
        → denied           → show rationale → request() → granted / permanentlyDenied
        → permanentlyDenied → openAppSettings()
        → restricted (iOS) → show explanation, cannot request
        → limited (iOS)    → partial access granted
```

---

## Core Patterns — Quick Reference

### Request at point of use
```dart
// ✅ Request when the user triggers the feature — not at startup
Future<void> _onTakePhotoTapped() async {
  final granted = await _permissionService.request(Permission.camera);
  if (!mounted) return;
  if (granted) {
    context.push('/camera');
  } else {
    _showPermissionDeniedSnackbar('Camera');
  }
}
```

### Show rationale before requesting (Android)
```dart
// ✅ Explain WHY before the system dialog appears
if (await Permission.location.shouldShowRequestRationale) {
  await _showRationaleDialog(
    title: 'Location needed',
    message: 'We use your location to show nearby stores.',
  );
}
final status = await Permission.location.request();
```

### Redirect to settings when permanently denied
```dart
if (status.isPermanentlyDenied) {
  await openAppSettings(); // opens app settings page
}
```

---

## Architecture Integration

```
Presentation (BLoC / Widget)
  ↓ calls
Domain (PermissionUseCase)
  ↓ calls
Core (PermissionService — abstract interface class)
  ↓ wraps
permission_handler (platform API)
```

---

## Quick Wins Checklist

- [ ] Permissions requested at point of use — not in `main()` or `initState()`
- [ ] Rationale shown before system dialog on Android (`shouldShowRequestRationale`)
- [ ] `openAppSettings()` offered when `isPermanentlyDenied`
- [ ] Only permissions used by core features declared in manifest/Info.plist
- [ ] iOS Podfile macros set to `0` for unused permissions
- [ ] Background location justified in Play Console (if used)
- [ ] Android 17: Contact Picker used instead of READ_CONTACTS where possible
- [ ] iOS usage description strings are specific and accurate — not generic

## Reference Files

- `references/permission_service.md` — PermissionService, use cases, BLoC integration, clean architecture
- `references/platform_config.md` — Android manifest, iOS Info.plist + Podfile macros, AppGallery notes
- `references/store_policies.md` — Google Play, App Store, AppGallery policy details and compliance checklist
