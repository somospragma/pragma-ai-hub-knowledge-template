---
name: flutter-startup-optimization
description: >
  Optimize Flutter cold start time: measure with --trace-startup and Firebase Performance, parallelize initialization with Future.wait, defer non-critical work, use lazy singletons in GetIt, hold the native splash with deferFirstFrame/allowFirstFrame, and precache critical assets. Target < 2s cold start on mid-range devices. Use this skill when the app feels slow to launch, shows a white flash before the splash, or when startup time exceeds budget in CI.
commands:
  - optimize-startup
inputs:
  - name: action
    description: Action to perform (measure, optimize, audit). "measure" profiles current startup time, "optimize" applies improvements, "audit" checks for common startup anti-patterns.
    required: true
  - name: target
    description: Path to the main entry point or app initialization file (e.g. lib/main.dart, lib/app/di/injection.dart).
    required: true
  - name: device_tier
    description: Target device tier for threshold validation (high-end, mid-range, low-end). Defaults to mid-range (< 2s target).
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Startup Optimization

**Rule #1: Measure before optimizing. Use `--trace-startup` and DevTools — never guess.**

## Startup Phases (What to Optimize)

```
[Native launch]          → OS loads the process, JVM/ART init (Android), dyld (iOS)
[Engine init]            → Flutter engine starts, Dart VM boots
[Framework init]         → WidgetsBinding, rendering pipeline
[main() executes]        → Your initialization code runs ← optimize here
[First frame rendered]   → runApp() + first build() completes ← target < 2s total
[App usable]             → Data loaded, interactive ← defer non-critical work
```

---

## 1. Measure First

```bash
# ✅ Trace startup — outputs JSON with phase timestamps
flutter run --profile --trace-startup
# Prints: "timeToFirstFrameMicros": 1842000  → 1.84s

# Parse the output file
cat build/start_up_info.json | python3 -m json.tool
# Key fields:
# engineEnterTimestamp     — engine started
# timeToFrameworkInit      — framework initialized
# timeToFirstFrameMicros   — first frame rendered ← your target metric
```

```dart
// ✅ Programmatic measurement — log to Firebase Performance or analytics
import 'dart:developer' as developer;

void main() async {
  final stopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeApp();

  stopwatch.stop();
  developer.log('Init time: ${stopwatch.elapsedMilliseconds}ms', name: 'startup');

  runApp(const App());
}
```

### Startup time targets

| Device tier | Cold start target | Action if exceeded |
|---|---|---|
| High-end (flagship) | < 1.5s | Investigate heavy plugins |
| Mid-range | < 2.0s | Parallelize init, defer non-critical |
| Low-end | < 3.0s | Lazy singletons, minimal main() |

---

## 2. Native Splash — Eliminate White Flash

```yaml
# pubspec.yaml
dependencies:
  flutter_native_splash: ^2.4.0
```

```yaml
# flutter_native_splash.yaml (project root)
flutter_native_splash:
  color: "#FFFFFF"
  image: assets/splash/logo.png
  color_dark: "#121212"
  image_dark: assets/splash/logo_dark.png
  android_12:
    image: assets/splash/logo_android12.png
    icon_background_color: "#FFFFFF"
  fullscreen: false
  web: false
```

```bash
# Generate native splash assets
dart run flutter_native_splash:create
```

```dart
// ✅ Hold the native splash until initialization is complete
// This prevents the white flash between native splash and first Flutter frame
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hold the splash — Flutter won't render the first frame yet
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.instance);

  await _initializeApp();

  runApp(const App());

  // Release the splash AFTER runApp — first frame is now ready
  FlutterNativeSplash.remove();
}
```

---

## 3. Parallelize Initialization — Future.wait

```dart
// ❌ Sequential — each step waits for the previous one
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();          // 300ms
  await SharedPreferences.getInstance();   // 50ms
  await configureDependencies();           // 100ms
  // Total: ~450ms sequential
  runApp(const App());
}

// ✅ Parallel — independent tasks run concurrently
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.instance);

  // Run independent initializations in parallel
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    _initSharedPreferences(),
    _initHiveBoxes(),
  ]);

  // DI must run after its dependencies are ready
  await configureDependencies();

  runApp(const App());
  FlutterNativeSplash.remove();
}
```

---

## 4. Lazy Singletons in GetIt — Don't Init What You Don't Need

```dart
// ❌ registerSingleton — instantiated immediately at registration time
// All of these run during app startup even if never used
getIt.registerSingleton<AnalyticsService>(AnalyticsService());
getIt.registerSingleton<CrashReporter>(CrashReporter());
getIt.registerSingleton<FeatureFlagService>(FeatureFlagService());

// ✅ registerLazySingleton — instantiated only on first access
// Zero startup cost for services not needed on the first screen
getIt.registerLazySingleton<AnalyticsService>(() => AnalyticsService());
getIt.registerLazySingleton<CrashReporter>(() => CrashReporter());
getIt.registerLazySingleton<FeatureFlagService>(() => FeatureFlagService());
```

```dart
// ✅ With Injectable — use @lazySingleton annotation
@lazySingleton
class AnalyticsService {
  // Instantiated only when first injected
}

// ✅ Only register eagerly what the first screen actually needs
@singleton  // eager — needed immediately
class AuthRepository { ... }

@lazySingleton  // lazy — needed later
class ReportingService { ... }
```

---

## 5. Defer Non-Critical Work After First Frame

```dart
// ✅ Schedule non-critical work after the first frame is rendered
// Users see the UI immediately — background work happens after
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.instance);

  // Only critical path — minimum needed to show first screen
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    configureDependencies(),
  ]);

  runApp(const App());
  FlutterNativeSplash.remove();

  // Defer everything else — runs after first frame is painted
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initNonCritical();
  });
}

Future<void> _initNonCritical() async {
  // These don't block the first frame
  await Future.wait([
    getIt<AnalyticsService>().initialize(),
    getIt<CrashReporter>().initialize(),
    getIt<FeatureFlagService>().fetchFlags(),
    _precacheCriticalImages(),
  ]);
}

Future<void> _precacheCriticalImages() async {
  // Precache images that appear on the home screen
  // so they render instantly when the user gets there
  final context = getIt<AppRouter>().router.routerDelegate.navigatorKey.currentContext;
  if (context == null) return;
  await Future.wait([
    precacheImage(const AssetImage('assets/images/home_hero.webp'), context),
  ]);
}
```

---

## 6. Deferred Loading — Reduce Initial Dart Bundle

```dart
// Heavy features loaded only when first accessed
import 'package:myapp/features/analytics_dashboard/analytics_dashboard.dart'
    deferred as analyticsDashboard;

// In the router — load on navigation, not at startup
Future<Widget> buildAnalyticsDashboard() async {
  await analyticsDashboard.loadLibrary();
  return analyticsDashboard.AnalyticsDashboard();
}
```

---

## 7. Quick Wins Checklist

- [ ] Measure with `--trace-startup` — know your baseline before changing anything
- [ ] `flutter_native_splash` + `FlutterNativeSplash.preserve/remove` — no white flash
- [ ] `Future.wait` for independent initializations — parallelize Firebase, prefs, etc.
- [ ] `@lazySingleton` for services not needed on the first screen
- [ ] `addPostFrameCallback` for analytics, crash reporting, feature flags
- [ ] `precacheImage` for above-the-fold images — after first frame
- [ ] Deferred imports for heavy features not needed at launch
- [ ] Profile with DevTools → Performance → startup trace to find the bottleneck

## Reference Files

- `references/implementation_guide.md` — complete main.dart patterns, DI configuration, CI measurement, and platform-specific tips
