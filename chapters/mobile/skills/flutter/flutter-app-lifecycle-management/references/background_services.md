# Background Services

## WorkManager 0.9.x (Android + iOS background tasks)

> **Breaking changes in 0.9.0:** Federated architecture, camelCase enums,
> hook-based debug system, native Map transfer (no JSON serialization).

```yaml
dependencies:
  workmanager: ^0.9.0
```

### Federated Architecture (0.9.0)

WorkManager now uses separate packages per platform:
- `workmanager_platform_interface` — shared interface
- `workmanager_android` — Android implementation (native WorkManager)
- `workmanager_apple` — iOS implementation (BGTaskScheduler)

Only declare `workmanager` in your `pubspec.yaml` — platform dependencies resolve automatically.

### Setup — Callback Dispatcher

```dart
// Must be a top-level function (runs in a separate isolate)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case 'syncData':
        await _syncInBackground(inputData);
      case 'cleanCache':
        await _cleanOldCache();
      case Workmanager.iOSBackgroundTask:
        // iOS Background Fetch (periodic)
        await _handleBackgroundFetch();
    }
    return Future.value(true);
  });
}
```

### Initialization

```dart
// In main.dart
// 0.9.0: isInDebugMode replaced by hook-based debug system
// The parameter still exists for compatibility but use native hooks instead
await Workmanager().initialize(callbackDispatcher);
```

### Hook-Based Debug System (New in 0.9.0)

Replaces the old `isInDebugMode: true`. Native configuration per platform:

**Android** — in your `Application` class:
```kotlin
// android/app/src/main/kotlin/.../MyApplication.kt
import dev.fluttercommunity.workmanager.WorkmanagerDebug
import dev.fluttercommunity.workmanager.LoggingDebugHandler

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // LoggingDebugHandler: visible in `adb logcat`
        // NotificationDebugHandler: shows debug notifications
        WorkmanagerDebug.setCurrent(LoggingDebugHandler())
    }
}
```

**iOS** — in `AppDelegate.swift`:
```swift
import workmanager_apple

// In application:didFinishLaunchingWithOptions:
// or didInitializeImplicitFlutterEngine: (Flutter 3.38+)
WorkmanagerDebug.setCurrent(LoggingDebugHandler())
// Or for notifications: WorkmanagerDebug.setCurrent(NotificationDebugHandler())
```

### Schedule Tasks

```dart
// Periodic task
await Workmanager().registerPeriodicTask(
  'sync-task',
  'syncData',
  frequency: const Duration(hours: 1),  // Android minimum: 15 min
  constraints: Constraints(
    // 0.9.0: enum values are now camelCase
    networkType: NetworkType.connected,
    requiresBatteryNotLow: true,
    requiresStorageNotLow: true,
  ),
  existingWorkPolicy: ExistingWorkPolicy.keep,
  initialDelay: const Duration(minutes: 5),
  inputData: {
    'syncType': 'incremental',
    'maxRecords': 100,  // 0.9.0: native Map transfer (no JSON)
  },
);

// One-off task
await Workmanager().registerOneOffTask(
  'upload-task',
  'fileUpload',
  constraints: Constraints(
    networkType: NetworkType.unmetered,  // WiFi only
  ),
  inputData: {'filePath': '/path/to/file.pdf'},
);

// iOS Processing Task (long-running, BGTaskScheduler)
await Workmanager().registerProcessingTask(
  'heavy-processing',
  'dataProcessing',
  constraints: Constraints(
    networkType: NetworkType.connected,
    requiresCharging: true,
  ),
);
```

### Breaking Changes 0.5.x → 0.9.0

| 0.5.x | 0.9.0 |
|---|---|
| `NetworkType.not_required` | `NetworkType.notRequired` |
| `NetworkType.not_roaming` | `NetworkType.notRoaming` |
| `OutOfQuotaPolicy.run_as_non_expedited_work_request` | `OutOfQuotaPolicy.runAsNonExpeditedWorkRequest` |
| `OutOfQuotaPolicy.drop_work_request` | `OutOfQuotaPolicy.dropWorkRequest` |
| `isInDebugMode: true` | Hook-based debug system (native) |
| inputData serialized as JSON | Native Map transfer |

### New APIs in 0.9.0

```dart
// Check if a periodic task is scheduled (Android only)
final isScheduled = await Workmanager().isScheduledByUniqueName('sync-task');

// Print scheduled tasks (returns String — useful for iOS debugging)
final tasks = await Workmanager().printScheduledTasks();
debugPrint(tasks);
```

### Cancel Tasks

```dart
await Workmanager().cancelByUniqueName('sync-task');
await Workmanager().cancelByTag('sync-tasks');
await Workmanager().cancelAll();
```

### iOS Platform Setup

**Minimum iOS 14.0.** Configure `Info.plist` based on task type:

**Option A — Background Fetch (periodic, controlled by iOS):**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
</array>
```
No `AppDelegate` configuration needed. iOS controls frequency (typically once/day).

**Option B — BGTaskScheduler (processing, one-off, periodic with custom frequency):**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>

<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.yourapp.processing_task</string>
</array>
```

```swift
// AppDelegate.swift
import workmanager_apple

// In didFinishLaunchingWithOptions: or didInitializeImplicitFlutterEngine: (Flutter 3.38+):
WorkmanagerPlugin.registerBGProcessingTask(
  withIdentifier: "com.yourapp.processing_task"
)

// For periodic with custom frequency:
WorkmanagerPlugin.registerPeriodicTask(
  withIdentifier: "com.yourapp.periodic_task",
  frequency: NSNumber(value: 20 * 60)  // 20 min (minimum 15 min)
)
```

> **Privacy Manifest:** `workmanager_apple` 0.9.0 includes a Privacy Manifest for App Store compliance.

### Platform Limitations

| Feature | Android | iOS |
|---|---|---|
| Minimum frequency | 15 minutes | 15 min (BGTask), variable (fetch) |
| Execution time | No practical limit | 30 seconds |
| Constraints | Full | Limited (network, charging) |
| `isScheduledByUniqueName` | ✅ | ❌ |
| `registerProcessingTask` | ❌ | ✅ |
| Guaranteed execution | Eventually | Not guaranteed |
| Debug hooks | LoggingDebugHandler, Notification | LoggingDebugHandler, Notification |

---

## FCM Background Handler

> **Flutter 3.38+ note:** After migrating to UIScene, FCM correctly handles lifecycle
> events through `FlutterSceneDelegate`. No changes required in the Dart handler.

```dart
// Must be a top-level function, not inside a class
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Minimal: only initialize what is needed
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Handle silently — no UI
  await _handleBackgroundMessage(message);
}

// Register before runApp
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
```

---

## What NEVER to Do

```dart
// ❌ FORBIDDEN — initialize the full app in a background callback
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await initializeFullApp();  // Exceeds 30s on iOS, wastes resources
    return true;
  });
}

// ❌ FORBIDDEN — use isInDebugMode in production (0.9.0 legacy)
await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
// Use hook-based debug system with build flavors instead

// ❌ FORBIDDEN — snake_case enums (only valid in 0.5.x)
// NetworkType.not_required  // Compile error in 0.9.0
// Use: NetworkType.notRequired

// ❌ FORBIDDEN — assume guaranteed execution on iOS
// Always design the app to work correctly when background tasks do not run
```
