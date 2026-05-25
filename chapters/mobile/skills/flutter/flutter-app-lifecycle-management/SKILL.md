---
name: flutter-app-lifecycle-management
description: >
  Correctly handles Flutter app lifecycle events: foreground/background transitions, screen lock, pause/resume, data refresh on resume, privacy screen, and session timeout. Use this skill when asking about AppLifecycleState, WidgetsBindingObserver, app going to background, pause/resume handling, refreshing data on resume, privacy screen in background, or session timeout on inactivity. Flutter 3.13+ uses the AppLifecycleListener API (recommended). UIScene lifecycle is now mandatory for iOS (required after iOS 26). Stack: Flutter 3.32+, Dart 3.8+.
commands:
  - setup-lifecycle
inputs:
  - name: action
    description: Action to perform (implement, audit, migrate-uiscene). "implement" generates the full lifecycle service (AppLifecycleListener, privacy screen, session timeout), "audit" checks for missing lifecycle handling (timers not cancelled, no privacy screen, stale data on resume), "migrate-uiscene" migrates iOS AppDelegate to UISceneDelegate (required for iOS 26+).
    required: true
  - name: target
    description: Path to the core/lifecycle directory or project root (e.g. lib/core/lifecycle/ for implement, ios/Runner/ for migrate-uiscene, . for audit).
    required: true
  - name: features
    description: Comma-separated lifecycle features to implement (privacy-screen, session-timeout, data-refresh, all). Defaults to all.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Flutter App Lifecycle Management

`AppLifecycleListener` API (introduced in Flutter 3.13, recommended).
Verified for Flutter 3.32+.

---

## Version History

| Flutter | Lifecycle Change |
|---|---|
| 3.13 | `AppLifecycleListener` API + `AppLifecycleState.hidden` |
| 3.27 | Edge-to-Edge `SystemUiMode` default on Android |
| 3.29 | Merged threads iOS/Android (UI + platform on same thread) |
| 3.35 | Merged threads macOS/Windows |
| 3.38 | **UISceneDelegate required on iOS** — iOS lifecycle migrates from `AppDelegate` to `UISceneDelegate`. `PredictiveBackPageTransitionBuilder` default on Android |
| 3.41 | Merged threads Linux. Auto-migration to UIScene on `flutter run`/`flutter build ios` |

> **Critical (iOS 26+):** Apple announced at WWDC25 that after iOS 26, any UIKit app
> built with the latest SDK **must** use the UIScene lifecycle or it will not launch.
> Flutter 3.41 auto-migrates if your `AppDelegate` is not customized.
> `AppLifecycleListener` in Dart continues to work without changes after migration —
> Flutter maps `UISceneDelegate` events to `AppLifecycleState` automatically.

---

## AppLifecycleListener (Recommended)

```dart
// lib/src/core/lifecycle/app_lifecycle_service.dart
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AppLifecycleService {
  AppLifecycleListener? _listener;

  void initialize() {
    _listener = AppLifecycleListener(
      onResume: _onResume,
      onInactive: _onInactive,
      onHide: _onHide,
      onShow: _onShow,
      onPause: _onPause,
      onRestart: _onRestart,
      onDetach: _onDetach,
      onExitRequested: _onExitRequested,
    );
  }

  void _onResume() {
    // App visible and active — refresh stale data
    getIt<AuthInterceptor>().refreshIfNeeded();
    getIt<SessionTimeoutService>().resetTimer();
  }

  void _onInactive() {
    // Transitioning — show privacy screen
    getIt<PrivacyScreenService>().show();
  }

  void _onHide() {
    // App in background — flush analytics
    // iOS: mapped from sceneDidEnterBackground (UISceneDelegate)
    // Android: mapped from onStop (Activity)
    getIt<AnalyticsService>().flush();
  }

  void _onShow() {
    // App becoming visible again
    // iOS: mapped from sceneWillEnterForeground (UISceneDelegate)
    getIt<DataRefreshService>().refreshIfStale();
  }

  void _onPause() {
    // App backgrounded — save state
    getIt<SessionTimeoutService>().startCountdown();
    getIt<AppStateRepository>().saveCurrentState();
  }

  void _onRestart() {
    // App restored from background
    getIt<PrivacyScreenService>().hide();
  }

  void _onDetach() {
    _listener?.dispose();
  }

  Future<AppExitResponse> _onExitRequested() async {
    // Save pending changes before exit (desktop only)
    await getIt<AppStateRepository>().saveCurrentState();
    return AppExitResponse.exit;
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
```

### Lifecycle State Flow

```
         ┌───────────────────────────────────────────┐
         │              DETACHED                     │
         └──────────┬───────────────────▲────────────┘
                    │ onRestart         │ onDetach
         ┌──────────▼───────────────────┴────────────┐
         │              RESUMED                      │
         └──────────┬───────────────────▲────────────┘
                    │ onInactive        │ onResume
         ┌──────────▼───────────────────┴────────────┐
         │              INACTIVE                     │
         └──────────┬───────────────────▲────────────┘
                    │ onHide            │ onShow
         ┌──────────▼───────────────────┴────────────┐
         │              HIDDEN                       │
         └──────────┬───────────────────▲────────────┘
                    │ onPause           │ onRestart
         ┌──────────▼───────────────────┴────────────┐
         │              PAUSED                       │
         └───────────────────────────────────────────┘
```

> Transitions shown in blue in the official docs (INACTIVE ↔ HIDDEN) only occur
> on iOS and Android.

### Initialization

```dart
// main.dart — after configureDependencies()
getIt<AppLifecycleService>().initialize();
```

---

## UIScene Lifecycle — iOS (Flutter 3.38+ / Required after iOS 26)

> As of Flutter 3.41, `flutter run` and `flutter build ios` auto-migrate to UIScene
> if `AppDelegate` is not customized. If migration succeeds, you will see:
> `"Finished migration to UIScene lifecycle"` in the build log.

### Migrate AppDelegate

Plugin registration must move from `application:didFinishLaunchingWithOptions:`
to the new `didInitializeImplicitFlutterEngine` callback:

```swift
// ios/Runner/AppDelegate.swift

// BEFORE (pre-3.38):
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// AFTER (3.38+ / required for iOS 26+):
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
```

### Info.plist — Application Scene Manifest

```xml
<key>UIApplicationSceneManifest</key>
<dict>
  <key>UIApplicationSupportsMultipleScenes</key>
  <false/>
  <key>UISceneConfigurations</key>
  <dict>
    <key>UIWindowSceneSessionRoleApplication</key>
    <array>
      <dict>
        <key>UISceneClassName</key>
        <string>UIWindowScene</string>
        <key>UISceneDelegateClassName</key>
        <string>FlutterSceneDelegate</string>
        <key>UISceneConfigurationName</key>
        <string>flutter</string>
        <key>UISceneStoryboardFile</key>
        <string>Main</string>
      </dict>
    </array>
  </dict>
</dict>
```

### Custom SceneDelegate (Optional)

Only needed if you require direct access to iOS scene events:

```swift
// ios/Runner/SceneDelegate.swift
import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    // Custom foreground logic
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    // Custom background logic
  }
}
```

Change `UISceneDelegateClassName` in `Info.plist` to `$(PRODUCT_MODULE_NAME).SceneDelegate`.

### UISceneDelegate → AppLifecycleState Mapping

| UISceneDelegate (iOS native) | AppLifecycleState (Flutter) |
|---|---|
| `sceneDidBecomeActive` | `resumed` |
| `sceneWillResignActive` | `inactive` |
| `sceneWillEnterForeground` | triggers `onShow` |
| `sceneDidEnterBackground` | triggers `onHide` |
| `scene:willConnectToSession:options:` | replaces `didFinishLaunchingWithOptions` for UI |

---

## Privacy Screen (Banking / Sensitive Apps)

```dart
// lib/src/core/lifecycle/privacy_screen_service.dart
@lazySingleton
class PrivacyScreenService extends ChangeNotifier {
  bool _isShowing = false;
  bool get isShowing => _isShowing;

  void show() {
    if (!_isShowing) {
      _isShowing = true;
      notifyListeners();
    }
  }

  void hide() {
    if (_isShowing) {
      _isShowing = false;
      notifyListeners();
    }
  }
}

// In App widget
@override
Widget build(BuildContext context) => ListenableBuilder(
  listenable: getIt<PrivacyScreenService>(),
  builder: (context, child) => Stack(
    children: [
      child!,
      if (getIt<PrivacyScreenService>().isShowing)
        const ColoredBox(
          color: Colors.white,
          child: Center(child: FlutterLogo(size: 80)),
        ),
    ],
  ),
  child: RouterScope(/* your router */),
);
```

---

## Session Timeout

```dart
// lib/src/core/session/session_timeout_service.dart
@lazySingleton
class SessionTimeoutService {
  static const _timeout = Duration(minutes: 15);
  Timer? _timer;

  void resetTimer() {
    _timer?.cancel();
    _timer = Timer(_timeout, _onTimeout);
  }

  void startCountdown() {
    if (_timer?.isActive != true) resetTimer();
  }

  void _onTimeout() {
    getIt<LogoutUseCase>()();
    getIt<AppRouter>().replaceAll([const LoginRoute()]);
  }

  void cancel() => _timer?.cancel();
}
```

---

## Legacy WidgetsBindingObserver

> Prefer `AppLifecycleListener` for new projects. `WidgetsBindingObserver` is still
> supported but does not receive API improvements.

```dart
class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        getIt<SessionTimeoutService>().resetTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        getIt<SessionTimeoutService>().startCountdown();
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.detached:
        break;
    }
  }
}
```

---

## Merged Threads (UI + Platform)

As of Flutter 3.41, **all platforms** run UI and platform code on the same thread:

| Platform | Merged since |
|---|---|
| iOS, Android | Flutter 3.29 |
| macOS, Windows | Flutter 3.35 |
| Linux | Flutter 3.41 |

**Lifecycle implication:** `AppLifecycleListener` callbacks now execute on the same
thread as native platform code, eliminating race conditions between UI and platform
threads during lifecycle transitions.

---

## What NEVER to Do

```dart
// ❌ FORBIDDEN — access FlutterViewController in didFinishLaunchingWithOptions (3.38+)
// let controller = window?.rootViewController as! FlutterViewController // CRASH

// ❌ FORBIDDEN — use applicationDidBecomeActive in AppDelegate (deprecated with UIScene)
// UI lifecycle events now go through UISceneDelegate

// ❌ FORBIDDEN — Timer without cancel in dispose
class BadService {
  final timer = Timer.periodic(const Duration(seconds: 1), (_) {}); // memory leak!
}

// ❌ FORBIDDEN — direct access to WidgetsBinding.instance.lifecycleState
// without an observer — the state may be stale

// ❌ FORBIDDEN — not migrating to UIScene before iOS 26 release
// Apps not using UIScene will not launch on iOS 26+
```

---

## Reference Files

- `references/background_services.md` — WorkManager 0.9.x for background tasks, FCM background handling, hook-based debug system
