# M8 — Code Tampering

This category covers protection against modification of the app's code and binaries.

---

## Check M8-A: Obfuscation disabled in production (Android)

**ID:** `M8-A-NO-OBFUSCATION`
**Objective:** Verify that ProGuard/R8 is enabled for release builds.
**Scope:** `android/app/build.gradle`

**Method:** Lexical search
**Insecure pattern:**

```gradle
// android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled false   // ❌ Obfuscation disabled
            shrinkResources false // ⚠️ No resource shrinking
        }
    }
}
```

**Verification command:**
```bash
grep -A5 "buildTypes" android/app/build.gradle | grep -A3 "release" | grep "minifyEnabled false"
```

**Criteria:**
- ❌ **Fail:** `minifyEnabled false` in release
- ⚠️ **Warning:** `minifyEnabled true` but no ProGuard rules configured
- ✅ **Pass:** Obfuscation enabled + rules configured

**Severity:** `MEDIUM`
**Automation:** 🟢 High (100%)

**Remediation:**

```gradle
// ✅ android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            signingConfig signingConfigs.release
            debuggable false
        }
        debug {
            minifyEnabled false
        }
    }
}
```

```proguard
# ✅ android/app/proguard-rules.pro

# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep annotation attributes
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# Keep data models used for JSON serialization
-keep class com.example.app.models.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Aggressive optimization
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses

# Remove logs in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}
```

---

## Check M8-B: Debug symbols not stripped (iOS)

**ID:** `M8-B-DEBUG-SYMBOLS`
**Objective:** Verify that debug symbols are stripped in iOS release builds.
**Scope:** `ios/Runner.xcodeproj/project.pbxproj`

**Method:** Lexical search
**Verification commands:**
```bash
grep "STRIP_INSTALLED_PRODUCT" ios/Runner.xcodeproj/project.pbxproj
grep "DEBUG_INFORMATION_FORMAT" ios/Runner.xcodeproj/project.pbxproj
```

**Criteria:**
- ⚠️ **Warning:** `STRIP_INSTALLED_PRODUCT = NO` in Release
- ⚠️ **Warning:** `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` in Release
- ✅ **Pass:** Symbols stripped in Release

**Severity:** `MEDIUM`
**Automation:** 🟢 High (90%)

**Remediation:**

Configure in Xcode:
1. Open `ios/Runner.xcworkspace`
2. Select target "Runner"
3. Build Settings → Release
4. "Strip Installed Product" → YES
5. "Debug Information Format" → DWARF (without dsym)

```
/* Release build settings */
STRIP_INSTALLED_PRODUCT = YES;
STRIP_STYLE = "non-global";
DEAD_CODE_STRIPPING = YES;
DEBUG_INFORMATION_FORMAT = "dwarf";
DEPLOYMENT_POSTPROCESSING = YES;
COPY_PHASE_STRIP = YES;
```

---

## Check M8-C: Dart code obfuscation in CI

**ID:** `M8-C-DART-OBFUSCATION`
**Objective:** Verify that `--obfuscate` is used in all release build commands.
**Scope:** `.github/workflows/`, `.gitlab-ci.yml`, `Makefile`

**Method:** Lexical search
**Verification command:**
```bash
grep -r "flutter build" .github/workflows/ | grep -E "release|appbundle|apk" | grep -v "\-\-obfuscate"
```

**Criteria:**
- ❌ **Fail:** `flutter build apk/appbundle/ios` without `--obfuscate`
- ⚠️ **Warning:** Obfuscation enabled but symbols not saved
- ✅ **Pass:** `--obfuscate` + `--split-debug-info` in all release builds

**Severity:** `MEDIUM`
**Automation:** 🟢 High (95%)

**Remediation:**

```bash
# ✅ Always obfuscate release builds
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/symbols/android

flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols/android

flutter build ios --release \
  --obfuscate \
  --split-debug-info=build/symbols/ios
```

```yaml
# ✅ .github/workflows/release.yml
jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'

      - name: Build App Bundle with obfuscation
        run: |
          flutter build appbundle --release \
            --obfuscate \
            --split-debug-info=build/symbols

      - name: Upload debug symbols
        uses: actions/upload-artifact@v4
        with:
          name: android-symbols
          path: build/symbols

  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'

      - name: Build iOS with obfuscation
        run: |
          flutter build ios --release \
            --obfuscate \
            --split-debug-info=build/symbols/ios \
            --no-codesign
```

---

## Check M8-D: Root/jailbreak detection

**ID:** `M8-D-ROOT-DETECTION`
**Objective:** Implement detection of compromised devices for high-security apps.
**Scope:** `lib/**.dart`

**Method:** Semantic search for implementation
**Criteria:**
- ⚠️ **Warning:** Apps with sensitive data without root/jailbreak detection
- ✅ **Pass:** Detection implemented (required for financial and health apps)

**Severity:** `MEDIUM` (HIGH for financial apps)
**Automation:** 🟡 Medium (40%)

**Remediation:**

See `flutter-rasp-strategy` skill for the complete freeRASP implementation with `ThreatCallback`, `RaspBloc`, and the Strategy+Adapter pattern.

```dart
// ✅ Quick reference — freeRASP 6.x
import 'package:freerasp/freerasp.dart';

class RaspService {
  Future<void> initialize() async {
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: 'com.example.app',
        signingCertHashes: ['your_cert_hash'],
        supportedAlternativeStores: [],
      ),
      iosConfig: IOSConfig(
        bundleIds: ['com.example.app'],
        teamId: 'YOUR_TEAM_ID',
      ),
      watcherMail: 'security@example.com',
      isProd: true,
    );

    await Talsec.instance.start(config);

    Talsec.instance.attachListener(ThreatCallback(
      onRootDetected: () => _handleThreat('root'),
      onDebuggerDetected: () => _handleThreat('debugger'),
      onEmulatorDetected: () => _handleThreat('emulator'),
      onTamperDetected: () => _handleThreat('tamper'),
      onHookDetected: () => _handleThreat('hook'),
    ));
  }

  void _handleThreat(String type) {
    // Log and block the app
    SecureLogger.log('Security threat detected: $type');
    // Navigate to blocked screen or exit
  }
}
```

---

## M8 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M8-A | MEDIUM | 🟢 100% | Low |
| M8-B | MEDIUM | 🟢 90% | Low |
| M8-C | MEDIUM | 🟢 95% | Low |
| M8-D | MEDIUM | 🟡 40% | Medium |

**Total checks:** 4 | **Critical:** 0 | **High:** 0 | **Medium:** 4 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
