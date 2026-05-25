# Store Policies — Google Play, App Store, AppGallery

Current permission policies as of April 2026. These change frequently — always
verify against the official developer documentation before submission.

---

## Google Play — Permission Policies

### Core principle
> "Only request permissions that are necessary for your app's core functionality.
> Permissions must be directly tied to features users can see and use."

### Sensitive permissions requiring justification

| Permission | Policy | Action required |
|---|---|---|
| `ACCESS_BACKGROUND_LOCATION` | Only for core features (navigation, delivery tracking) | Declare in Play Console + submit form |
| `READ_CONTACTS` (Android 17+) | Use Contact Picker first; READ_CONTACTS only if picker is insufficient | Migrate to Contact Picker for API 37+ |
| `ACCESS_FINE_LOCATION` | Use location button (system UI) as minimum scope where possible | Prefer coarse location unless precise is essential |
| `READ_CALL_LOG` / `PROCESS_OUTGOING_CALLS` | Restricted — only for default dialer/SMS apps | Requires declaration |
| `READ_SMS` / `RECEIVE_SMS` | Restricted — only for default SMS apps or OTP autofill | Requires declaration |
| `MANAGE_EXTERNAL_STORAGE` | Restricted — only for file managers, backup apps | Requires declaration |
| `PACKAGE_USAGE_STATS` | Restricted — only for parental control, device management | Requires declaration |

### April 2026 policy updates

```
Location Permissions Policy (April 15, 2026):
- The system location button is now the recommended minimum scope for precise location
- Apps should prefer coarse location unless precise is essential for core functionality
- Pre-review checks in Play Console will flag location policy issues (Oct 2026)

Contact Permissions Policy (April 2026):
- Apps targeting Android 17 (API 37+) must use the Contact Picker first
- READ_CONTACTS only permitted if Contact Picker cannot fulfill the core use case
- Pre-review checks will flag contact permission policy issues (Oct 2026)
```

### Minimum scope principle

```dart
// ❌ Requesting more than needed
await Permission.locationAlways.request(); // background — rarely justified

// ✅ Request minimum scope, escalate only if needed
final coarse = await Permission.locationCoarse.request();
if (coarse.isGranted) {
  // Use coarse location for most features
}

// Only request precise if the feature genuinely requires it
if (needsPreciseLocation) {
  final precise = await Permission.locationWhenInUse.request();
}
```

### Android 17 — Contact Picker (API 37+)

```dart
// ✅ Use Contact Picker instead of READ_CONTACTS where possible
// The Contact Picker provides a standardized, secure, searchable interface
// No permission required — user selects contacts explicitly

// In Flutter, use the 'contacts_service' or 'flutter_contacts' package
// which supports the Contact Picker API on Android 17+

// Only fall back to READ_CONTACTS if:
// - Your app needs to read ALL contacts (e.g., sync app, backup app)
// - The Contact Picker cannot fulfill the core use case
```

### Play Console — Background Location Declaration

If your app uses `ACCESS_BACKGROUND_LOCATION`:

1. Go to Play Console → App content → Sensitive app permissions
2. Complete the background location declaration form
3. Explain the core feature that requires background location
4. Submit for review — this adds review time

---

## App Store — Permission Policies

### Core principle
> "Apps may not request access to personal data without a clear, specific reason
> that is directly tied to the app's core functionality."

### Usage description requirements

```
✅ Specific and accurate:
"Used to capture photos for your product listings."

❌ Vague — will be rejected:
"Used by the app."
"Required for app functionality."
"Needed for features."
```

### Always-on location — high scrutiny

`NSLocationAlwaysAndWhenInUseUsageDescription` triggers manual App Store review.
You must demonstrate that background location is essential for a core feature.

```
Accepted use cases:
- Navigation apps (turn-by-turn)
- Delivery tracking (real-time driver location)
- Fitness apps (route recording)
- Geofencing for core features

Rejected use cases:
- Analytics or advertising
- "Nice to have" features
- Features that work fine with When In Use
```

### App Tracking Transparency (ATT — iOS 14+)

```dart
// Required before accessing IDFA or any cross-app tracking
// Must show ATT prompt before any tracking begins

// In Flutter, use 'app_tracking_transparency' package:
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

Future<void> requestTrackingPermission() async {
  final status = await AppTrackingTransparency.requestTrackingAuthorization();
  if (status == TrackingStatus.authorized) {
    // Can use IDFA for personalized ads
  }
}
```

### Privacy Nutrition Labels

Every app must declare data collection in App Store Connect:
- What data is collected
- Whether it's linked to the user's identity
- Whether it's used for tracking

This is separate from permission strings — it's a declaration in App Store Connect.

### Required Reason APIs (iOS 17+)

Some APIs require a "required reason" declaration in `PrivacyInfo.xcprivacy`:

```xml
<!-- ios/Runner/PrivacyInfo.xcprivacy -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <!-- File timestamp APIs -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string> <!-- Access file timestamps for app functionality -->
            </array>
        </dict>
        <!-- UserDefaults -->
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string> <!-- Access UserDefaults to read/write app preferences -->
            </array>
        </dict>
    </array>
</dict>
</plist>
```

---

## AppGallery (Huawei) — Permission Policies

### Standard Android permissions
AppGallery follows standard Android permission guidelines. The same
`AndroidManifest.xml` declarations used for Google Play apply.

### Key differences from Google Play

| Aspect | Google Play | AppGallery |
|---|---|---|
| Location background | Requires Play Console declaration | Standard Android declaration |
| Sensitive permissions | Restricted list with review | Similar restrictions |
| HMS-specific | N/A | HMS Location Kit, Push Kit require separate setup |
| Privacy policy | Required for sensitive permissions | Required — must be accessible in-app |

### Privacy policy requirement

AppGallery requires a privacy policy URL for apps that request any sensitive permission.
The policy must be accessible from within the app (not just on the store listing).

---

## Compliance Checklist — Before Submission

### Google Play
- [ ] Only permissions used by core features are declared in manifest
- [ ] Background location declared in Play Console (if used)
- [ ] `READ_CONTACTS` replaced with Contact Picker for Android 17+ targets
- [ ] Precise location justified — coarse used where sufficient
- [ ] No permissions used for advertising/analytics only
- [ ] `maxSdkVersion` set on legacy storage permissions

### App Store
- [ ] Every permission has a specific, accurate usage description string
- [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` only if background location is core
- [ ] ATT prompt implemented if any cross-app tracking is used
- [ ] `PrivacyInfo.xcprivacy` file present with required reason declarations
- [ ] Privacy Nutrition Labels completed in App Store Connect
- [ ] Podfile macros set to `0` for unused permissions

### AppGallery
- [ ] Privacy policy URL accessible from within the app
- [ ] Standard Android permissions declared correctly
- [ ] HMS-specific permissions handled separately from GMS permissions
