# App Size Optimization — Implementation Guide

## Overview

App size directly impacts install conversion, retention, and user experience — especially
on low-end devices and in markets with limited storage or bandwidth.

This guide covers every lever available in Flutter to reduce APK/IPA size, including
the mandatory Android 16KB page size compliance required by Google Play.

---

## 1. Measuring Size — The Right Way

### Never use debug builds for size measurement

```bash
# ❌ Debug build — includes JIT compiler, assertions, hot reload overhead (~100MB+)
flutter run

# ✅ Release build — AOT compiled, tree-shaken, representative of production
flutter build appbundle --release
flutter build apk --release --split-per-abi
flutter build ipa --release
```

### Analyze size breakdown

```bash
# Generates app-size-analysis.json with a full breakdown by package/file
flutter build appbundle --analyze-size
flutter build apk --analyze-size --target-platform android-arm64
flutter build ipa --analyze-size

# Open the analysis in DevTools:
dart devtools
# → App Size tab → Load app-size-analysis.json
# Shows a treemap: Flutter engine / Dart code / assets / native libs
```

### True user download size

The most accurate measurement is via **Google Play Console**:
1. Upload your AAB
2. Go to **Android Vitals → App Size**
3. Check **Download size** (arm64, XXXHDPI) — this is what users actually download

For iOS, use **Xcode App Size Report**:
```bash
flutter build ipa --export-method development
open build/ios/archive/*.xcarchive
# Distribute App → Development → App Thinning: all compatible device variants
# Xcode generates a size report per device variant
```

---

## 2. Android 16KB Page Size Compliance

### Background

Android 15 (API 35) introduced 16KB memory page support for ARMv9 devices.
Google Play **blocks app updates** for non-compliant apps targeting Android 15+:
- **November 1, 2025**: Enforcement started
- **May 31, 2026**: Extended deadline (if requested in Play Console)

Native `.so` libraries built with 4KB alignment crash at launch on 16KB-page devices.

### Required versions

```groovy
// android/settings.gradle
pluginManagement {
    plugins {
        id "com.android.application" version "8.6.0" apply false  // AGP 8.5.1+ minimum
        id "org.jetbrains.kotlin.android" version "2.1.0" apply false
    }
}
```

```properties
# android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-all.zip
```

```groovy
// android/app/build.gradle
android {
    compileSdk 35
    ndkVersion "28.0.12674087"  // NDK r28+ — required for 16KB ELF alignment

    defaultConfig {
        minSdk 23
        targetSdk 35
    }
}
```

```yaml
# pubspec.yaml
environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.32.0"  # Flutter 3.32+ ships 16KB-aligned engine binaries
```

### Verify alignment

```bash
# Build release APK
flutter build apk --release

# Method 1: Android Studio
# Build → Analyze APK → select .apk → lib/arm64-v8a/
# Each .so shows alignment — must be "16 KB LOAD section alignment"

# Method 2: readelf (requires Android NDK in PATH)
readelf -l build/app/intermediates/merged_native_libs/release/out/lib/arm64-v8a/libflutter.so \
  | grep -E "LOAD|Align"
# ✅ Good: Align = 0x4000 (16384 bytes = 16KB)
# ❌ Bad:  Align = 0x1000 (4096 bytes = 4KB)

# Method 3: Test on 16KB emulator
# Android Studio → SDK Manager → SDK Tools → "Pre-Release 16KB Android system image"
# Create AVD with this image → install and run your app
```

### Handling non-compliant plugins

```bash
# Step 1: Update all plugins — most have released 16KB-compatible versions
flutter pub upgrade
flutter pub outdated

# Step 2: Check which .so files are misaligned
# Android Studio → Analyze APK → lib/arm64-v8a → inspect each .so

# Step 3: If a plugin has no fix yet — file an issue with the maintainer
# Include: plugin name, version, .so file name, alignment value from readelf

# Step 4: Last resort only — disable 16KB packaging (will still fail on strict devices)
```

```groovy
// android/app/build.gradle — ONLY as a temporary last resort
android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true  // ⚠️ disables 16KB alignment
        }
    }
}
```

### Clean rebuild after version updates

```bash
flutter clean
flutter pub get
cd android && ./gradlew clean
cd ..
flutter build appbundle --release
```

---

## 3. Build Commands Reference

### Android

```bash
# AAB — recommended for Play Store (Play handles per-device optimization)
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android \
  --analyze-size

# APK split by ABI — for direct distribution (not Play Store)
# Produces: app-arm64-v8a-release.apk, app-armeabi-v7a-release.apk, app-x86_64-release.apk
flutter build apk --release \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/debug-info/android

# Single fat APK — only if you must distribute one file (larger)
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android
```

### iOS

```bash
# IPA for App Store
flutter build ipa --release \
  --obfuscate \
  --split-debug-info=build/debug-info/ios

# Check size with App Thinning
flutter build ipa --export-method development
open build/ios/archive/*.xcarchive
```

---

## 4. Obfuscation and Debug Symbols

### Why both flags together

- `--obfuscate` — renames Dart symbols to short random names → reduces binary size + protects code
- `--split-debug-info` — moves debug symbols to a separate file → removes them from the binary

```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android
```

### ⚠️ Critical: store and upload debug symbols

Without the debug-info files, crash stack traces are unreadable.

```bash
# Upload to Firebase Crashlytics (run after each release build)
firebase crashlytics:symbols:upload \
  --app=YOUR_FIREBASE_APP_ID \
  build/debug-info/android/app.android-arm64.symbols

# Or upload via Gradle plugin (automatic on build):
# android/app/build.gradle
apply plugin: 'com.google.firebase.crashlytics'

buildTypes {
    release {
        firebaseCrashlytics {
            nativeSymbolUploadEnabled true
            unstrippedNativeLibsDir 'build/app/intermediates/merged_native_libs/release'
        }
    }
}
```

```bash
# Upload to Google Play Console (for Play's deobfuscation)
# Play Console → App Bundle Explorer → select release → Downloads → Debug symbols
# Upload: build/debug-info/android/*.symbols
```

### Deobfuscating a crash stack manually

```bash
# Using flutter symbolize
flutter symbolize \
  --debug-info=build/debug-info/android/app.android-arm64.symbols \
  --input=obfuscated_stack_trace.txt
```

---

## 5. Tree Shaking

### Dart code tree shaking

Enabled automatically in release builds. Help it by:

```dart
// ❌ Dynamic dispatch — compiler can't determine what's used
final Map<String, WidgetBuilder> routes = {
  'home': (_) => HomePage(),
  'profile': (_) => ProfilePage(),
};
final page = routes[routeName]!();

// ✅ Static switch — unused branches can be eliminated
Widget buildPage(String route) => switch (route) {
  'home' => const HomePage(),
  'profile' => const ProfilePage(),
  _ => const NotFoundPage(),
};
```

### Icon font tree shaking

```dart
// ❌ Dynamic icon reference — defeats tree shaking, ALL icons included
final IconData icon = getIconForType(type);
Icon(icon)

// ✅ Static const reference — only used icons included in binary
const Icon(Icons.home)
const Icon(Icons.settings)
```

```bash
# If you see this warning — you have dynamic icon references:
# "This application cannot tree shake icons fonts"
# Fix: replace all dynamic IconData with static const references
```

### Conditional imports for platform-specific code

```dart
// ✅ Platform-specific code excluded from other platforms
import 'stub_service.dart'
    if (dart.library.io) 'mobile_service.dart'
    if (dart.library.html) 'web_service.dart';
```

---

## 6. Deferred Loading (Code Splitting)

### Basic deferred import

```dart
// Import the library with 'deferred as'
import 'package:myapp/features/analytics/analytics_dashboard.dart'
    deferred as analyticsDashboard;

// Load on demand — returns a Future that completes when the chunk is downloaded
Future<void> openAnalytics(BuildContext context) async {
  await analyticsDashboard.loadLibrary();
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => analyticsDashboard.AnalyticsDashboard()),
  );
}
```

### Deferred loading with BLoC

```dart
// lib/features/heavy_report/heavy_report_loader.dart
import 'package:myapp/features/heavy_report/heavy_report.dart'
    deferred as heavyReport;

@injectable
class HeavyReportBloc extends Bloc<HeavyReportEvent, HeavyReportState> {
  HeavyReportBloc() : super(const HeavyReportState.initial()) {
    on<LoadHeavyReportEvent>(_onLoad);
  }

  Future<void> _onLoad(
    LoadHeavyReportEvent event,
    Emitter<HeavyReportState> emit,
  ) async {
    emit(const HeavyReportState.loading());
    try {
      await heavyReport.loadLibrary();
      emit(const HeavyReportState.loaded());
    } catch (e) {
      emit(HeavyReportState.error('Failed to load: $e'));
    }
  }
}
```

### Android Deferred Components (Play Feature Delivery)

For large features (> 5MB), use Android's Play Feature Delivery to deliver on demand:

```yaml
# pubspec.yaml
flutter:
  deferred-components:
    - name: heavy_feature
      libraries:
        - package:myapp/features/heavy_feature/heavy_feature.dart
      assets:
        - assets/heavy_feature/
```

```bash
# Build with deferred components
flutter build appbundle --deferred-components

# Test locally with bundletool
bundletool build-apks \
  --bundle=build/app/outputs/bundle/release/app-release.aab \
  --output=app.apks \
  --local-testing

bundletool install-apks --apks=app.apks
```

---

## 7. Asset Optimization

### Image format selection

| Format | Use case | Typical saving vs PNG |
|---|---|---|
| WebP (lossy, q=85) | Photos, complex images | 25–35% |
| WebP (lossless) | UI graphics with transparency | 10–20% |
| AVIF | Modern devices, best compression | 40–50% |
| SVG | Icons, illustrations, logos | 90%+ (vector) |
| PNG | Simple graphics, pixel art | baseline |

```bash
# Batch convert PNG to WebP (install: brew install webp)
find assets/images -name "*.png" -exec sh -c \
  'cwebp -q 85 "$1" -o "${1%.png}.webp"' _ {} \;

# Batch compress existing PNGs
find assets/images -name "*.png" -exec optipng -o5 {} \;

# Convert to AVIF (install: brew install ffmpeg with libaom)
ffmpeg -i input.png -c:v libaom-av1 -crf 30 -b:v 0 output.avif
```

### Font subsetting

```bash
# Include only the characters your app uses (e.g., Latin + numbers)
# Install: pip install fonttools
pyftsubset Roboto-Regular.ttf \
  --unicodes="U+0020-007E,U+00A0-00FF" \
  --output-file=Roboto-Regular-subset.ttf \
  --flavor=woff2
```

```yaml
# pubspec.yaml — only include weights you actually use
flutter:
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf        # weight 400
        - asset: assets/fonts/Roboto-Medium.ttf         # weight 500
        - asset: assets/fonts/Roboto-Bold.ttf           # weight 700
        # ❌ Remove: Thin (100), Light (300), Black (900) if unused
```

### Avoid bundling non-critical assets

```dart
// ✅ Load non-critical images from CDN — not bundled in the app
CachedNetworkImage(
  imageUrl: 'https://cdn.example.com/content/${item.id}.webp',
  memCacheWidth: 400,
  memCacheHeight: 400,
)

// ✅ Use SVG for all icons — no raster variants needed
SvgPicture.asset('assets/icons/home.svg', width: 24, height: 24)
```

---

## 8. Removing Unused Dependencies

```bash
# List all transitive dependencies
flutter pub deps

# Find packages that may be unused
flutter pub deps --no-dev 2>/dev/null | grep "^[a-z]"

# Check for newer, smaller alternatives
flutter pub outdated

# After removing packages:
flutter clean && flutter pub get
```

### Common packages with lighter alternatives

| Heavy package | Lighter alternative | Notes |
|---|---|---|
| `http` + custom logic | `dio` with interceptors | More features, similar size |
| Full `firebase_*` suite | Only the Firebase packages you use | Don't add all Firebase packages |
| `intl` (full) | `intl` with `--no-tree-shake-icons` | Only include needed locales |
| Large icon packs | SVG icons or `flutter_svg` | No raster variants |

---

## 9. CI/CD Size Budget Enforcement

```yaml
# .github/workflows/size_check.yml
name: App Size Check

on: [pull_request]

jobs:
  size-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.x'

      - name: Build AAB with size analysis
        run: |
          flutter build appbundle --release --analyze-size \
            --obfuscate \
            --split-debug-info=build/debug-info/android \
            2>&1 | tee size_output.txt

      - name: Check size budget
        run: |
          # Extract download size from analysis output
          SIZE=$(grep -oP 'Download Size: \K[0-9.]+' size_output.txt | head -1)
          BUDGET=20  # MB
          if (( $(echo "$SIZE > $BUDGET" | bc -l) )); then
            echo "❌ App size ${SIZE}MB exceeds budget ${BUDGET}MB"
            exit 1
          fi
          echo "✅ App size ${SIZE}MB is within budget ${BUDGET}MB"

      - name: Upload size analysis artifact
        uses: actions/upload-artifact@v4
        with:
          name: size-analysis
          path: |
            build/debug-info/
            *-code-size-snapshot.json
```

---

## 10. Size Optimization Checklist

### Build configuration
- [ ] Use AAB (not APK) for Play Store
- [ ] `--split-per-abi` if distributing APKs directly
- [ ] `--obfuscate --split-debug-info` on all release builds
- [ ] Debug symbols uploaded to Crashlytics and Play Console

### Android 16KB compliance
- [ ] AGP 8.5.1+ (recommend 8.6.0)
- [ ] Gradle 8.5+
- [ ] NDK r28+ (`ndkVersion "28.0.12674087"`)
- [ ] Flutter 3.32+
- [ ] `targetSdk 35`
- [ ] All plugins verified with 16KB alignment in APK Analyzer
- [ ] Tested on 16KB emulator image

### Assets
- [ ] All PNG/JPG converted to WebP (q=85) or AVIF
- [ ] SVG used for icons and illustrations
- [ ] Unused font weights removed from pubspec.yaml
- [ ] Non-critical images loaded from CDN, not bundled

### Code
- [ ] `--analyze-size` run and treemap reviewed
- [ ] Unused packages removed from pubspec.yaml
- [ ] Dynamic `IconData` replaced with `const Icon(Icons.x)` for tree shaking
- [ ] Heavy features use deferred loading
- [ ] CI size budget check in place
