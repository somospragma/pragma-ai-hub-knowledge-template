# M1 — Improper Platform Usage

This category covers misuse of platform features or failure to use platform security controls.

---

## Check M1-A: Debuggable enabled in production (Android)

**ID:** `M1-A-DEBUG-ENABLED`
**Objective:** The release APK/AAB must not have `android:debuggable="true"`.
**Scope:**
- `android/app/src/main/AndroidManifest.xml`
- `android/app/build.gradle`

**Method:** Lexical search
**Patterns:**
```regex
android:debuggable\s*=\s*"true"
debuggable\s+true
```

**Verification commands:**
```bash
# Search in manifests
grep -r 'android:debuggable="true"' android/app/src/main/

# Search in build.gradle (release block)
grep -A10 "buildTypes" android/app/build.gradle | grep -A5 "release" | grep "debuggable true"
```

**Criteria:**
- ✅ **Pass:** `debuggable="true"` not found, or only present in `debug/AndroidManifest.xml`
- ❌ **Fail:** `debuggable="true"` in the main manifest or in the `release` block of build.gradle

**Severity:** `HIGH`
**Automation:** 🟢 High (100%)

**Remediation:**
```xml
<!-- AndroidManifest.xml — remove or set to false -->
<application
    android:debuggable="false">
```

```gradle
// build.gradle
android {
    buildTypes {
        release {
            debuggable false  // explicit or omit (false by default)
            minifyEnabled true
            shrinkResources true
        }
        debug {
            debuggable true  // OK in debug only
        }
    }
}
```

**References:**
- [Android Debuggable Security](https://developer.android.com/studio/publish/preparing#publishing-configure)

---

## Check M1-B: allowBackup enabled without restrictions (Android)

**ID:** `M1-B-BACKUP-ENABLED`
**Objective:** Prevent uncontrolled backups that expose sensitive data.
**Scope:** `android/app/src/main/AndroidManifest.xml`

**Method:** Lexical search
**Pattern:**
```regex
android:allowBackup\s*=\s*"true"
```

**Criteria:**
- ⚠️ **Warning:** `allowBackup="true"` without `android:fullBackupContent` defined
- ❌ **Fail:** `allowBackup="true"` in apps with sensitive data (tokens, PII)

**Severity:** `MEDIUM`
**Automation:** 🟢 High (90%)

**Remediation:**
```xml
<!-- Option 1: Disable backup entirely -->
<application
    android:allowBackup="false"
    android:fullBackupContent="false">

<!-- Option 2: Controlled backup with exclusions -->
<application
    android:allowBackup="true"
    android:fullBackupContent="@xml/backup_rules">
```

```xml
<!-- res/xml/backup_rules.xml -->
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <exclude domain="sharedpref" path="secure_prefs.xml"/>
    <exclude domain="database" path="sensitive.db"/>
    <exclude domain="file" path="tokens/"/>
</full-backup-content>
```

---

## Check M1-C: App Transport Security (ATS) with broad exceptions (iOS)

**ID:** `M1-C-ATS-BYPASS`
**Objective:** Ensure ATS is not completely disabled.
**Scope:** `ios/Runner/Info.plist`

**Method:** Lexical search in XML/plist
**Pattern:**
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

**Criteria:**
- ❌ **Fail:** `NSAllowsArbitraryLoads = true` without specific domain exceptions
- ⚠️ **Warning:** Exceptions for specific domains without justification

**Severity:** `HIGH`
**Automation:** 🟢 High (95%)

**Remediation:**
```xml
<!-- AVOID: Full bypass -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>

<!-- PREFERRED: Specific domain exceptions if needed -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>legacy-api.example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <false/>
        </dict>
    </dict>
</dict>
```

---

## Check M1-D: Excessive or unnecessary permissions (Android)

**ID:** `M1-D-EXCESSIVE-PERMISSIONS`
**Objective:** Detect declared permissions that are potentially unused.
**Scope:** `android/app/src/main/AndroidManifest.xml` + `lib/**.dart`

**Method:** Lexical + semantic cross-reference
**Permissions to verify:**
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_CONTACTS"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_PHONE_STATE"/>
```

**Cross-validation:**
| Permission | Verify presence in code |
|---|---|
| CAMERA | `image_picker`, `camera` package |
| ACCESS_FINE_LOCATION | `geolocator`, `location` package |
| RECORD_AUDIO | `audio_recorder`, `permission_handler` |
| READ_CONTACTS | `contacts_service`, `flutter_contacts` |

**Criteria:**
- ⚠️ **Warning:** Permission declared but no related code found
- ✅ **Pass:** Permission declared and usage detected in code

**Severity:** `MEDIUM`
**Automation:** 🟡 Medium (70%)

**Remediation:**
```xml
<!-- Remove unused permissions -->
<!-- BEFORE -->
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>

<!-- AFTER (if only location is used) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

---

## Check M1-E: Exported Android components without protection

**ID:** `M1-E-EXPORTED-COMPONENTS`
**Objective:** Detect Activities/Services/Receivers exported without a justified intent-filter.
**Scope:** `android/app/src/main/AndroidManifest.xml`

**Method:** Lexical search with XML structural analysis
**Patterns:**
```regex
<activity[^>]+android:exported\s*=\s*"true"(?![^<]*<intent-filter)
<service[^>]+android:exported\s*=\s*"true"(?![^<]*<intent-filter)
<receiver[^>]+android:exported\s*=\s*"true"(?![^<]*<intent-filter)
```

**Criteria:**
- ❌ **Fail:** `exported="true"` without a corresponding `<intent-filter>`
- ⚠️ **Warning:** `exported="true"` with `intent-filter` but without input validation

**Severity:** `HIGH`
**Automation:** 🟢 High (85%)

**Remediation:**
```xml
<!-- BEFORE: Unnecessarily exposed component -->
<activity
    android:name=".InternalActivity"
    android:exported="true"/>

<!-- AFTER: Protected by default -->
<activity
    android:name=".InternalActivity"
    android:exported="false"/>

<!-- If it genuinely needs to be public -->
<activity
    android:name=".PublicActivity"
    android:exported="true"
    android:permission="android.permission.signature">
    <intent-filter>
        <action android:name="com.example.ACTION_VIEW"/>
    </intent-filter>
</activity>
```

**Important note (Android 12+):**
```xml
<!-- Android 12+ requires explicit declaration -->
<activity
    android:name=".MyActivity"
    android:exported="false"/>  <!-- REQUIRED for targetSdk 31+ -->
```

---

## Check M1-F: Sensitive iOS permissions without usage description

**ID:** `M1-F-IOS-PERMISSIONS`
**Objective:** Verify that sensitive permissions have clear usage descriptions.
**Scope:** `ios/Runner/Info.plist`

**Method:** Lexical search for missing keys
**Permissions to verify:**
```
NSCameraUsageDescription
NSPhotoLibraryUsageDescription
NSLocationWhenInUseUsageDescription
NSLocationAlwaysUsageDescription
NSMicrophoneUsageDescription
NSContactsUsageDescription
NSCalendarsUsageDescription
NSBluetoothPeripheralUsageDescription
NSFaceIDUsageDescription
```

**Criteria:**
- ❌ **Fail:** Functionality is used but the `*UsageDescription` key is missing
- ✅ **Pass:** All used functionalities have a description

**Severity:** `HIGH` (App Store rejects apps without this)
**Automation:** 🟡 Medium (75%)

**Remediation:**
```xml
<!-- Info.plist -->
<key>NSCameraUsageDescription</key>
<string>This app needs camera access to take product photos</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>We use your location to show nearby stores</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>We need access to your photos so you can select a profile picture</string>
```

---

## M1 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M1-A | HIGH | 🟢 100% | Low |
| M1-B | MEDIUM | 🟢 90% | Low |
| M1-C | HIGH | 🟢 95% | Low |
| M1-D | MEDIUM | 🟡 70% | Medium |
| M1-E | HIGH | 🟢 85% | Low |
| M1-F | HIGH | 🟡 75% | Medium |

**Total checks:** 6 | **Critical:** 0 | **High:** 4 | **Medium:** 2 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
