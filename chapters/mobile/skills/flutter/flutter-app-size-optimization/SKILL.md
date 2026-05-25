---
name: flutter-app-size-optimization
description: >
  Reduce Flutter APK/IPA size: tree shaking, deferred components, asset compression, ABI splits, --split-debug-info, obfuscation, size analysis tools, and Android 16KB page size compliance (required for Google Play as of November 2025). Use this skill when the app is too large, when Google Play warns about 16KB page size, or when optimizing download/install size for emerging markets.
commands:
  - optimize-app-size
inputs:
  - name: action
    description: Action to perform (analyze, optimize, audit-16kb). "analyze" runs --analyze-size and reports the breakdown, "optimize" applies size reduction techniques (asset compression, deferred loading, unused deps removal), "audit-16kb" checks Android 16KB page size compliance (AGP, NDK, Flutter versions, .so alignment).
    required: true
  - name: target
    description: Path to the project root or specific build output to analyze (e.g. . for full project, build/app/outputs/ for existing build).
    required: true
  - name: platform
    description: Platform to optimize for (android, ios, both). Defaults to both.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# App Size Optimization

See `references/implementation_guide.md` for complete patterns, commands, and platform config.

**Rule #1: Measure before optimizing. Use `--analyze-size` and Play Console — never guess.**

## Quick Reference — What Costs the Most

| Category | Typical contribution | Fix |
|---|---|---|
| Flutter engine | ~7MB (fixed, unavoidable) | — |
| Dart code | 1–5MB | Tree shaking, deferred loading |
| Assets (images, fonts) | 2–20MB+ | WebP/AVIF, font subsetting, on-demand |
| Native `.so` libraries | 2–10MB | ABI splits, remove unused plugins |
| Debug symbols | 5–15MB | `--split-debug-info` |

---

## 1. Always Measure First

```bash
# ✅ Analyze size breakdown — shows what's actually large
flutter build appbundle --analyze-size
flutter build apk --analyze-size
flutter build ipa --analyze-size

# Output: app-size-analysis.json — open in DevTools → App Size tab
# or: dart devtools → load the JSON file
```

```bash
# ✅ True user download size — use Play Console
# Upload AAB → Android Vitals → App Size → Download size (arm64, XXXHDPI)
# This is what users actually download after Play's processing
```

---

## 2. Build Commands — Release Flags

```bash
# ✅ Android App Bundle (AAB) — Play delivers only what each device needs
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android

# ✅ APK split by ABI — eliminates x86/x86_64 from arm64 devices
flutter build apk --release \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/debug-info/android

# ✅ iOS IPA
flutter build ipa --release \
  --obfuscate \
  --split-debug-info=build/debug-info/ios
```

> **Always use AAB over APK for Play Store.** AAB enables Play's dynamic delivery,
> which strips unused ABI, density, and language resources per device.

---

## 3. Android 16KB Page Size (Required — Google Play)

**Deadline:** November 1, 2025 (extended to May 31, 2026 if requested in Play Console).  
Apps targeting Android 15+ (API 35) that ship non-aligned `.so` libraries are **blocked from updates**.

### Minimum required versions

```groovy
// android/settings.gradle
plugins {
    id "com.android.application" version "8.6.0" apply false  // AGP 8.5.1+ minimum
}
```

```properties
# android/gradle/wrapper/gradle-wrapper.properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.7-all.zip
```

```groovy
// android/app/build.gradle
android {
    ndkVersion "28.0.12674087"  // NDK r28+ required for 16KB alignment

    defaultConfig {
        minSdk 23
        targetSdk 35  // Android 15
        compileSdk 35
    }
}
```

```yaml
# pubspec.yaml — Flutter 3.32+ required for 16KB compliance
environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.32.0"
```

### Verify compliance

```bash
# Build release APK/AAB, then inspect in Android Studio:
# Build → Analyze APK → select .apk/.aab → lib/ folder
# Each .so must show "16 KB LOAD section alignment" — not "4 KB"

# Or use command line (requires Android SDK build-tools):
readelf -l build/app/intermediates/merged_native_libs/release/out/lib/arm64-v8a/libflutter.so \
  | grep -E "LOAD|ALIGN"
# Look for: Align = 0x4000 (16384 = 16KB) ✅
# Bad:      Align = 0x1000 (4096 = 4KB)   ❌
```

### If a plugin is not 16KB compliant

```bash
# Identify which .so files are misaligned
# Android Studio → Analyze APK → lib/arm64-v8a → check each .so alignment

# Check if the plugin has a newer version with 16KB support
flutter pub outdated

# If no fix available — file an issue with the plugin maintainer
# Temporary workaround (only if absolutely necessary):
# android/app/build.gradle
android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true  // ⚠️ disables 16KB alignment — use only as last resort
        }
    }
}
```

---

## 4. Tree Shaking

Dart's compiler automatically removes unused code in release builds.
Help it by avoiding patterns that defeat tree shaking:

```dart
// ❌ Dynamic dispatch prevents tree shaking — compiler can't know what's used
final widget = registry['home']!();

// ✅ Static references — compiler can eliminate unused branches
Widget buildPage(String route) => switch (route) {
  'home' => const HomePage(),
  'profile' => const ProfilePage(),
  _ => const NotFoundPage(),
};
```

```dart
// ❌ Importing entire packages when only one class is needed
import 'package:some_large_package/some_large_package.dart';

// ✅ Import a public sublibrary when the package exposes one
import 'package:some_large_package/specific_class.dart';
```

```bash
# ✅ Icon font tree shaking — only include used icons
# Automatic in release builds IF you use static const references
# ❌ This defeats icon tree shaking:
Icon(iconData)  // dynamic — compiler can't know which icons are used

# ✅ This enables icon tree shaking:
const Icon(Icons.home)  // static — unused icons are stripped
```

---

## 5. Deferred Loading (Code Splitting)

Load heavy features only when first accessed. Reduces initial download size.

```dart
// lib/src/features/heavy_feature/heavy_feature.dart
// Mark the library as deferrable — no changes needed inside it

// lib/src/features/heavy_feature/heavy_feature_loader.dart
import 'package:myapp/features/heavy_feature/heavy_feature.dart' deferred as heavyFeature;

class HeavyFeatureLoader extends StatefulWidget {
  const HeavyFeatureLoader({super.key});

  @override
  State<HeavyFeatureLoader> createState() => _HeavyFeatureLoaderState();
}

class _HeavyFeatureLoaderState extends State<HeavyFeatureLoader> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadFeature();
  }

  Future<void> _loadFeature() async {
    await heavyFeature.loadLibrary(); // downloads the deferred chunk
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const CircularProgressIndicator();
    return heavyFeature.HeavyFeaturePage();
  }
}
```

> **Note:** Deferred loading works on Android (via Play's dynamic delivery) and web.
> On iOS, the code is still included in the binary but initialized lazily.

---

## 6. Asset Optimization

```bash
# ✅ Convert PNG/JPG to WebP — typically 25–35% smaller
# Using cwebp (install via brew install webp):
cwebp -q 85 input.png -o output.webp

# ✅ Convert to AVIF for even better compression (modern devices)
# Using ffmpeg:
ffmpeg -i input.png -c:v libaom-av1 output.avif

# ✅ Compress existing PNGs losslessly
pngcrush -brute input.png output.png
# or: optipng -o7 input.png
```

```yaml
# pubspec.yaml — declare only the assets you actually use
flutter:
  assets:
    - assets/images/logo.webp
    - assets/images/onboarding/  # only if ALL files in this folder are used

  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
        - asset: assets/fonts/Roboto-Bold.ttf
        # ❌ Don't include weights you don't use (Thin, Light, Black, etc.)
```

```dart
// ✅ Use SVG for icons and illustrations — zero raster memory, scales perfectly
// flutter_svg package
SvgPicture.asset('assets/icons/home.svg', width: 24, height: 24)

// ✅ Use network images for non-critical content — don't bundle in the app
CachedNetworkImage(imageUrl: 'https://cdn.example.com/hero.webp')
```

---

## 7. Remove Unused Dependencies

```bash
# Find unused packages
flutter pub deps --no-dev | grep -v "^[|\\`]"

# Check for outdated packages (newer versions may be smaller)
flutter pub outdated

# After removing packages from pubspec.yaml:
flutter clean && flutter pub get
```

```yaml
# pubspec.yaml — audit regularly
dependencies:
  # ❌ Remove packages you added "just in case"
  # ❌ Remove packages whose functionality you now handle differently
  # ✅ Prefer packages that are modular (import only what you need)
```

---

## 8. Obfuscation + Debug Symbol Splitting

```bash
# ✅ Obfuscate Dart symbols — reduces binary size + protects code
# ✅ --split-debug-info — moves debug symbols out of the binary
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/debug-info/android

# ⚠️ CRITICAL: Store the debug-info directory securely
# You MUST upload it to Firebase Crashlytics / Play Console to deobfuscate crash stacks
# Without it, crash reports will show obfuscated symbol names
```

```bash
# Upload debug symbols to Firebase Crashlytics (CI/CD step)
firebase crashlytics:symbols:upload \
  --app=YOUR_APP_ID \
  build/debug-info/android/app.android-arm64.symbols
```

---

## 9. Size Targets & Monitoring

| Build type | Target download size | Notes |
|---|---|---|
| Initial install (AAB, arm64) | < 20MB | Play Console → App Size |
| After deferred components | < 10MB initial | Heavy features loaded on demand |
| iOS IPA (App Thinning) | < 30MB | Xcode App Size Report |

```bash
# ✅ Add size check to CI — fail if size exceeds budget
flutter build appbundle --analyze-size 2>&1 | grep "Download Size"
# Parse output and fail pipeline if > threshold
```

---

## Quick Wins Checklist

- [ ] Build with `--split-per-abi` (APK) or use AAB
- [ ] Add `--obfuscate --split-debug-info` to release builds
- [ ] Run `--analyze-size` and check the DevTools App Size tab
- [ ] Convert large PNG/JPG assets to WebP
- [ ] Remove unused font weights from pubspec.yaml
- [ ] Remove unused packages (`flutter pub deps`)
- [ ] Use `const Icon(Icons.x)` — not `Icon(dynamicIconData)` — for tree shaking
- [ ] Verify 16KB page size compliance (Android) — check AGP 8.5.1+, NDK r28+, Flutter 3.32+
- [ ] Upload debug symbols to Crashlytics after enabling obfuscation

## Reference Files

- `references/implementation_guide.md` — detailed commands, Gradle config, CI integration, and platform-specific setup
