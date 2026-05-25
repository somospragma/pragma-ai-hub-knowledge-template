# Startup Optimization — Implementation Guide

See also: `flutter-rendering` skill for frame performance, `flutter-memory-profiling` for heap patterns.

## Overview

Cold start time is the elapsed time from the user tapping the app icon to the first
interactive frame. It directly impacts install conversion and user retention.

The optimization strategy is:
1. **Measure** — know your baseline with `--trace-startup`
2. **Parallelize** — run independent init tasks concurrently with `Future.wait`
3. **Defer** — move non-critical work after the first frame
4. **Lazy-load** — don't instantiate services until they're needed
5. **Hold the splash** — prevent white flash with `deferFirstFrame`/`allowFirstFrame`

---

## 1. Measuring Startup Time

### --trace-startup (CI/CD baseline)

```bash
# Run in profile mode — release mode is similar but harder to instrument
flutter run --profile --trace-startup --no-hot

# Output file: build/start_up_info.json
# Key metric: timeToFirstFrameMicros
cat build/start_up_info.json
```

```json
{
  "engineEnterTimestamp": 12345678,
  "timeToFrameworkInitMicros": 245000,
  "timeToFirstFrameMicros": 1842000,
  "timeAfterFrameworkInitMicros": 1597000
}
```

```
timeToFirstFrameMicros = 1,842,000 μs = 1.84s  ← your target metric
```

### DevTools startup trace

```bash
flutter run --profile
# Open DevTools → Performance tab → load startup trace
# Look for: main() → runApp() → first build() → first rasterized frame
```

### Programmatic measurement

```dart
// lib/core/startup/startup_timer.dart
import 'dart:developer' as developer;

class StartupTimer {
  static final _stopwatch = Stopwatch();
  static final _checkpoints = <String, int>{};

  static void start() => _stopwatch.start();

  static void checkpoint(String label) {
    _checkpoints[label] = _stopwatch.elapsedMilliseconds;
    developer.log('[$label] ${_stopwatch.elapsedMilliseconds}ms', name: 'startup');
  }

  static void report() {
    developer.log('Startup checkpoints: $_checkpoints', name: 'startup');
    // Send to Firebase Performance or your analytics service
  }
}

// Usage in main.dart:
void main() async {
  StartupTimer.start();
  WidgetsFlutterBinding.ensureInitialized();
  StartupTimer.checkpoint('binding_initialized');

  await Firebase.initializeApp();
  StartupTimer.checkpoint('firebase_ready');

  await configureDependencies();
  StartupTimer.checkpoint('di_ready');

  runApp(const App());
  StartupTimer.checkpoint('runApp_called');

  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTimer.checkpoint('first_frame');
    StartupTimer.report();
  });
}
```

### Firebase Performance Monitoring (production data)

```dart
// lib/core/startup/startup_trace.dart
import 'package:firebase_performance/firebase_performance.dart';

class StartupTrace {
  static Trace? _trace;

  static Future<void> start() async {
    _trace = FirebasePerformance.instance.newTrace('app_startup');
    await _trace?.start();
  }

  static Future<void> stop({required String firstScreen}) async {
    _trace?.putAttribute('first_screen', firstScreen);
    await _trace?.stop();
  }
}

// In main.dart:
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await StartupTrace.start();

  await configureDependencies();
  runApp(const App());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await StartupTrace.stop(firstScreen: 'home');
  });
}
```

---

## 2. Complete main.dart — Optimized Pattern

```dart
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:get_it/get_it.dart';
import 'core/di/injection.dart';
import 'core/startup/startup_timer.dart';
import 'firebase_options.dart';

void main() async {
  StartupTimer.start();

  // Step 1: Initialize Flutter binding — must be first
  final binding = WidgetsFlutterBinding.ensureInitialized();
  StartupTimer.checkpoint('binding');

  // Step 2: Hold the native splash — prevents white flash
  // Flutter won't render the first frame until FlutterNativeSplash.remove() is called
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Step 3: Parallelize independent critical initializations
  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    _initLocalStorage(),   // SharedPreferences, Hive, etc.
  ]);
  StartupTimer.checkpoint('parallel_init');

  // Step 4: DI — runs after its dependencies are ready
  await configureDependencies();
  StartupTimer.checkpoint('di');

  // Step 5: Launch app — first frame will be built now
  runApp(const App());

  // Step 6: Release splash — first frame is ready to display
  FlutterNativeSplash.remove();
  StartupTimer.checkpoint('runApp');

  // Step 7: Defer non-critical work until after first frame is painted
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTimer.checkpoint('first_frame');
    StartupTimer.report();
    _initNonCritical();
  });
}

Future<void> _initLocalStorage() async {
  await Future.wait([
    SharedPreferences.getInstance().then(
      (prefs) => GetIt.instance.registerSingleton<SharedPreferences>(prefs),
    ),
    Hive.initFlutter(),
  ]);
}

/// Non-critical services — do not block the first frame
void _initNonCritical() {
  // Fire-and-forget — errors should not crash the app
  Future.wait([
    GetIt.instance<AnalyticsService>().initialize(),
    GetIt.instance<CrashReporter>().initialize(),
    GetIt.instance<FeatureFlagService>().fetchFlags(),
    _precacheCriticalImages(),
  ]).catchError((e) {
    // Log but don't rethrow — non-critical failures are acceptable
    debugPrint('Non-critical init error: $e');
  });
}

Future<void> _precacheCriticalImages() async {
  final context = GetIt.instance<AppRouter>()
      .router
      .routerDelegate
      .navigatorKey
      .currentContext;
  if (context == null) return;

  await Future.wait([
    precacheImage(const AssetImage('assets/images/home_hero.webp'), context),
    precacheImage(const AssetImage('assets/images/onboarding_1.webp'), context),
  ]);
}
```

---

## 3. Native Splash Configuration

### flutter_native_splash setup

```yaml
# pubspec.yaml
dependencies:
  flutter_native_splash: ^2.4.0
```

```yaml
# flutter_native_splash.yaml (project root)
flutter_native_splash:
  # Light mode
  color: "#FFFFFF"
  image: assets/splash/logo.png

  # Dark mode
  color_dark: "#121212"
  image_dark: assets/splash/logo_dark.png

  # Android 12+ (uses SplashScreen API)
  android_12:
    image: assets/splash/logo_android12.png
    icon_background_color: "#FFFFFF"
    icon_background_color_dark: "#121212"
    image_dark: assets/splash/logo_android12_dark.png

  # Branding image (shown at bottom, Android 12+ only)
  branding: assets/splash/branding.png
  branding_dark: assets/splash/branding_dark.png

  fullscreen: false
  web: false  # disable if not targeting web
```

```bash
# Generate native splash code
dart run flutter_native_splash:create

# Remove generated splash (if reverting)
dart run flutter_native_splash:remove
```

### deferFirstFrame / allowFirstFrame (manual approach)

If you prefer not to use `flutter_native_splash`, use the Flutter API directly:

```dart
void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Tell Flutter to not send the first frame to the engine yet
  // The native splash stays visible
  binding.deferFirstFrame();

  await _initializeApp();

  runApp(const App());

  // Allow Flutter to render the first frame — native splash dismissed
  binding.allowFirstFrame();
}
```

---

## 4. Dependency Injection — Lazy vs Eager

### Injectable annotations

```dart
// ✅ @singleton — eager, instantiated at DI init time
// Use for: services needed on the first screen (auth, router, local storage)
@singleton
class AuthRepository { ... }

@singleton
class AppRouter { ... }

// ✅ @lazySingleton — lazy, instantiated on first access
// Use for: services not needed until the user navigates deeper
@lazySingleton
class AnalyticsService { ... }

@lazySingleton
class ReportingService { ... }

@lazySingleton
class FeatureFlagService { ... }

// ✅ @injectable (factory) — new instance per injection
// Use for: BLoCs, use cases, per-request objects
@injectable
class ProductBloc { ... }
```

### Async singletons — register before DI init

```dart
// lib/core/di/injection.dart
@InjectableInit()
Future<void> configureDependencies() async => getIt.init();

// For async dependencies (SharedPreferences, Hive boxes):
// Register them BEFORE calling configureDependencies()
// so Injectable-generated code can resolve them

Future<void> _registerAsyncDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  await Hive.initFlutter();
  final settingsBox = await Hive.openBox<String>('settings');
  getIt.registerSingleton<Box<String>>(settingsBox, instanceName: 'settings');
}

// In main.dart:
await _registerAsyncDependencies();
await configureDependencies(); // Injectable-generated code runs after
```

### Startup cost by registration type

| Type | Startup cost | When to use |
|---|---|---|
| `@singleton` | Paid at DI init | First screen dependencies |
| `@lazySingleton` | Zero at startup | Everything else |
| `@injectable` (factory) | Zero at startup | BLoCs, use cases |
| `registerSingletonAsync` | Paid at DI init | Async deps (prefs, DB) |
| `registerLazySingletonAsync` | Zero at startup | Async deps not needed immediately |

---

## 5. Deferred Loading — Heavy Features

```dart
// lib/features/reports/reports_loader.dart
import 'package:myapp/features/reports/reports_dashboard.dart'
    deferred as reportsDashboard;

class ReportsDashboardLoader extends StatefulWidget {
  const ReportsDashboardLoader({super.key});

  @override
  State<ReportsDashboardLoader> createState() => _ReportsDashboardLoaderState();
}

class _ReportsDashboardLoaderState extends State<ReportsDashboardLoader> {
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await reportsDashboard.loadLibrary();
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return ErrorWidget('Failed to load reports: $_error');
    }
    if (!_loaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return reportsDashboard.ReportsDashboard();
  }
}
```

---

## 6. Startup Sequence — What Belongs Where

```
main() — CRITICAL PATH (blocks first frame)
├── WidgetsFlutterBinding.ensureInitialized()   ← always first
├── FlutterNativeSplash.preserve()              ← hold splash
├── Future.wait([                               ← parallel
│   Firebase.initializeApp(),
│   SharedPreferences.getInstance(),
│   Hive.initFlutter(),
│   ])
├── configureDependencies()                     ← after deps ready
└── runApp()                                    ← first frame

addPostFrameCallback — DEFERRED (after first frame)
├── AnalyticsService.initialize()
├── CrashReporter.initialize()
├── FeatureFlagService.fetchFlags()
├── precacheImage() for above-the-fold images
└── FlutterNativeSplash.remove()  ← if not called before runApp

On first navigation to a feature — LAZY
├── deferred library loadLibrary()
└── @lazySingleton first access
```

### What NOT to do in main()

```dart
// ❌ Network calls in main() — blocks first frame
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await http.get(Uri.parse('https://api.example.com/config')); // ❌ network in main
  runApp(const App());
}

// ❌ Heavy computation in main()
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _processLargeDataset(); // ❌ blocks first frame
  runApp(const App());
}

// ❌ Initializing services that aren't needed on the first screen
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await getIt<AnalyticsService>().initialize(); // ❌ not needed for first frame
  await getIt<ReportingService>().initialize(); // ❌ not needed for first frame
  runApp(const App());
}
```

---

## 7. CI/CD Startup Budget Enforcement

```yaml
# .github/workflows/startup_check.yml
name: Startup Time Check

on: [pull_request]

jobs:
  startup-check:
    runs-on: macos-latest  # iOS/Android emulator available
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.x'

      - name: Run startup trace
        run: |
          flutter run --profile --trace-startup --no-hot \
            -d emulator-5554 \
            2>&1 | tee startup_output.txt

      - name: Check startup budget
        run: |
          # Extract timeToFirstFrameMicros from the JSON output
          TIME=$(python3 -c "
          import json, sys
          with open('build/start_up_info.json') as f:
              data = json.load(f)
          print(data.get('timeToFirstFrameMicros', 0) // 1000)
          ")
          BUDGET=2000  # 2 seconds in milliseconds
          echo "Startup time: ${TIME}ms (budget: ${BUDGET}ms)"
          if [ "$TIME" -gt "$BUDGET" ]; then
            echo "❌ Startup time ${TIME}ms exceeds budget ${BUDGET}ms"
            exit 1
          fi
          echo "✅ Startup time ${TIME}ms is within budget"

      - name: Upload startup trace
        uses: actions/upload-artifact@v4
        with:
          name: startup-trace
          path: build/start_up_info.json
```

---

## 8. Platform-Specific Notes

### Android

- **Cold start** includes JVM/ART initialization — unavoidable overhead
- **Avoid** heavy work in `FlutterActivity.onCreate()` or `Application.onCreate()`
- **MultiDex** adds startup overhead on older Android — minimize it with `minSdk 21+`
- **R8/ProGuard** in release mode reduces class loading time — always enable for release

```groovy
// android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true      // enables R8 — reduces startup time
            shrinkResources true    // removes unused resources
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                         'proguard-rules.pro'
        }
    }
}
```

### iOS

- **Cold start** includes dyld linking — reduced by fewer dynamic frameworks
- **Avoid** heavy work in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
- **App Clips** can improve perceived startup for first-time users

```swift
// ios/Runner/AppDelegate.swift
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        // ✅ Keep this minimal — heavy init goes in main.dart
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
```

---

## 9. Startup Optimization Checklist

### Measurement
- [ ] Baseline measured with `--trace-startup` in profile mode
- [ ] `timeToFirstFrameMicros` recorded and tracked in CI
- [ ] Firebase Performance trace added for production monitoring

### Native splash
- [ ] `flutter_native_splash` configured with brand colors and logo
- [ ] `FlutterNativeSplash.preserve()` called before any async work
- [ ] `FlutterNativeSplash.remove()` called after `runApp()`

### Initialization
- [ ] Independent tasks use `Future.wait` (not sequential `await`)
- [ ] Only critical services initialized before `runApp()`
- [ ] Non-critical services deferred to `addPostFrameCallback`
- [ ] No network calls in `main()` before `runApp()`

### Dependency injection
- [ ] Services not needed on first screen use `@lazySingleton`
- [ ] Async dependencies registered before `configureDependencies()`
- [ ] BLoCs and use cases use `@injectable` (factory, not singleton)

### Assets
- [ ] Critical above-the-fold images precached in `addPostFrameCallback`
- [ ] Images are WebP format and sized correctly (see `flutter-app-size-optimization`)

### CI
- [ ] Startup time budget enforced in CI pipeline
- [ ] Startup trace artifact uploaded for regression analysis
