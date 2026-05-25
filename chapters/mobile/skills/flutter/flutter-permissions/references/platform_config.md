# Platform Configuration — Android, iOS, AppGallery

## Android — AndroidManifest.xml

Only declare permissions your app actually uses. Unused permissions in the manifest
can trigger Play Store policy violations and rejection.

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- ── Camera ──────────────────────────────────────────────────────── -->
    <uses-permission android:name="android.permission.CAMERA"/>

    <!-- ── Microphone ─────────────────────────────────────────────────── -->
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>

    <!-- ── Location ───────────────────────────────────────────────────── -->
    <!-- Coarse only — for approximate location (city-level) -->
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <!-- Fine — for precise GPS location (requires justification in Play Console) -->
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <!-- Background — ONLY if core feature requires it (navigation, tracking) -->
    <!-- Requires separate Play Console declaration and review -->
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>

    <!-- ── Notifications (Android 13+ / API 33+) ──────────────────────── -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <!-- ── Storage / Media ────────────────────────────────────────────── -->
    <!-- Android 13+ (API 33+) — granular media permissions -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
    <!-- Android 14+ (API 34+) — partial photo/video access -->
    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>
    <!-- Legacy storage — Android 12 and below only -->
    <uses-permission
        android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29"/>

    <!-- ── Contacts ───────────────────────────────────────────────────── -->
    <!-- Android 17+ (API 37+): Use Contact Picker instead when possible -->
    <!-- READ_CONTACTS only if Contact Picker is insufficient for core functionality -->
    <uses-permission android:name="android.permission.READ_CONTACTS"/>

    <!-- ── Bluetooth (Android 12+ / API 31+) ─────────────────────────── -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>

    <!-- ── Phone ──────────────────────────────────────────────────────── -->
    <uses-permission android:name="android.permission.READ_PHONE_STATE"/>

    <!-- ── Calendar ───────────────────────────────────────────────────── -->
    <uses-permission android:name="android.permission.READ_CALENDAR"/>
    <uses-permission android:name="android.permission.WRITE_CALENDAR"/>

    <application ...>
        ...
    </application>
</manifest>
```

### build.gradle — required SDK versions

```groovy
// android/app/build.gradle
android {
    compileSdk 35

    defaultConfig {
        minSdk 23
        targetSdk 35
    }
}
```

---

## iOS — Info.plist

Every permission requires a usage description string. Vague strings like
"Used by the app" are rejected by App Store review.

```xml
<!-- ios/Runner/Info.plist -->
<dict>
    <!-- ── Camera ──────────────────────────────────────────────────────── -->
    <key>NSCameraUsageDescription</key>
    <string>Used to capture photos for your product listings and profile picture.</string>

    <!-- ── Microphone ─────────────────────────────────────────────────── -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Used to record voice notes and video with audio.</string>

    <!-- ── Photo Library ──────────────────────────────────────────────── -->
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Used to select photos from your library for product listings.</string>
    <!-- iOS 14+ — add photo without full library access -->
    <key>NSPhotoLibraryAddUsageDescription</key>
    <string>Used to save photos to your library.</string>

    <!-- ── Location ───────────────────────────────────────────────────── -->
    <!-- When In Use — for features that need location only while app is open -->
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Used to show stores and services near your current location.</string>
    <!-- Always — only if background location is a core feature -->
    <!-- Requires strong justification — App Store review scrutinizes this -->
    <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
    <string>Used to track your delivery in real time, even when the app is in the background.</string>

    <!-- ── Contacts ───────────────────────────────────────────────────── -->
    <key>NSContactsUsageDescription</key>
    <string>Used to find friends who are already using the app.</string>

    <!-- ── Notifications ──────────────────────────────────────────────── -->
    <!-- No Info.plist key needed — requested via UNUserNotificationCenter -->

    <!-- ── Bluetooth ──────────────────────────────────────────────────── -->
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Used to connect to nearby Bluetooth devices for data transfer.</string>

    <!-- ── Calendar ───────────────────────────────────────────────────── -->
    <key>NSCalendarsUsageDescription</key>
    <string>Used to add your appointments and reminders to your calendar.</string>
    <!-- iOS 17+ — full access vs write-only -->
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Used to read and manage your calendar events.</string>
    <key>NSCalendarsWriteOnlyAccessUsageDescription</key>
    <string>Used to add new events to your calendar.</string>

    <!-- ── Speech Recognition ─────────────────────────────────────────── -->
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Used to convert your voice to text for search queries.</string>

    <!-- ── Face ID ────────────────────────────────────────────────────── -->
    <key>NSFaceIDUsageDescription</key>
    <string>Used to authenticate your identity for secure access.</string>

    <!-- ── Tracking (ATT — iOS 14+) ───────────────────────────────────── -->
    <!-- Required if you use any cross-app tracking (IDFA, fingerprinting) -->
    <key>NSUserTrackingUsageDescription</key>
    <string>Your data will be used to deliver personalized ads.</string>
</dict>
```

### iOS Podfile — Enable Only Used Permissions

This is critical: `permission_handler` touches all permission SDKs by default.
Set unused permissions to `0` to reduce binary size and avoid App Store rejection
for permissions you don't actually use.

```ruby
# ios/Podfile
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',

        # ✅ Enable only the permissions your app uses
        # Set to 0 to disable — reduces binary size and review risk

        ## Camera
        'PERMISSION_CAMERA=1',

        ## Microphone
        'PERMISSION_MICROPHONE=1',

        ## Photo Library
        'PERMISSION_PHOTOS=1',
        'PERMISSION_PHOTOS_ADD_ONLY=1',

        ## Location
        'PERMISSION_LOCATION=1',
        # 'PERMISSION_LOCATION_ALWAYS=0',  # only if background location needed

        ## Notifications
        'PERMISSION_NOTIFICATIONS=1',

        ## Contacts
        # 'PERMISSION_CONTACTS=0',  # disable if not used

        ## Calendar
        # 'PERMISSION_EVENTS=0',
        # 'PERMISSION_EVENTS_FULL_ACCESS=0',
        # 'PERMISSION_REMINDERS=0',

        ## Bluetooth
        # 'PERMISSION_BLUETOOTH=0',

        ## Speech
        # 'PERMISSION_SPEECH_RECOGNIZER=0',

        ## Sensors
        # 'PERMISSION_SENSORS=0',

        ## App Tracking Transparency
        # 'PERMISSION_APP_TRACKING_TRANSPARENCY=0',

        ## Critical Alerts
        # 'PERMISSION_CRITICAL_ALERTS=0',
      ]
    end
  end
end
```

---

## AppGallery (Huawei)

Flutter apps distributed via AppGallery use standard Android permissions.
`permission_handler` works without modification for system permissions.

```xml
<!-- Same AndroidManifest.xml as Google Play -->
<!-- No additional permission declarations needed for system permissions -->
```

### HMS-specific notes

```dart
// ⚠️ HMS Location Kit (Huawei devices without GMS)
// permission_handler works for the permission request
// But the actual location API requires HMS Location Kit, not Google Play Services

// Check if device has GMS or HMS at runtime:
// Use the 'device_info_plus' package to detect Huawei devices
// Then route to the appropriate location implementation

// For standard permissions (camera, microphone, storage, notifications):
// permission_handler works identically on GMS and HMS devices
```

---

## Permission by Feature — Quick Reference

| Feature | Android permissions | iOS keys |
|---|---|---|
| Camera | `CAMERA` | `NSCameraUsageDescription` |
| Video recording | `CAMERA` + `RECORD_AUDIO` | `NSCameraUsageDescription` + `NSMicrophoneUsageDescription` |
| Photo picker | `READ_MEDIA_IMAGES` (API 33+) | `NSPhotoLibraryUsageDescription` |
| Location (approximate) | `ACCESS_COARSE_LOCATION` | `NSLocationWhenInUseUsageDescription` |
| Location (precise) | `ACCESS_FINE_LOCATION` | `NSLocationWhenInUseUsageDescription` |
| Location (background) | `ACCESS_BACKGROUND_LOCATION` | `NSLocationAlwaysAndWhenInUseUsageDescription` |
| Push notifications | `POST_NOTIFICATIONS` (API 33+) | No key — use `UNUserNotificationCenter` |
| Contacts | `READ_CONTACTS` (prefer Contact Picker on API 37+) | `NSContactsUsageDescription` |
| Bluetooth | `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` (API 31+) | `NSBluetoothAlwaysUsageDescription` |
| Biometrics | No manifest permission | `NSFaceIDUsageDescription` |
