# freeRASP Implementation Guide

freeRASP (by Talsec) is the primary RASP provider. It runs continuous security
checks and invokes callbacks when threats are detected.

## Setup

```yaml
dependencies:
  freerasp: ^6.11.0
```

### Android — build.gradle

```groovy
// android/app/build.gradle
android {
    defaultConfig {
        minSdk 23  // freeRASP requires Android 6.0+
        targetSdk 35
    }
}
```

### Android — signing certificate hash

freeRASP validates the app's signing certificate to detect tampering.
You need the **base64-encoded SHA-256** of your signing certificate.

```bash
# From Play Console → Setup → App Signing → App Signing Key Certificate → SHA-256
# Convert the colon-separated hex to base64:
echo "AA:BB:CC:..." | tr -d ':' | xxd -r -p | base64

# Or from your keystore directly:
keytool -list -v -keystore your-keystore.jks -alias your-alias \
  | grep "SHA256:" \
  | awk '{print $2}' \
  | tr -d ':' \
  | xxd -r -p \
  | base64

# Or from an APK:
apksigner verify --print-certs your-app.apk \
  | grep "SHA-256" \
  | awk '{print $NF}' \
  | xxd -r -p \
  | base64
```

---

## TalsecConfig — Full Configuration

```dart
// lib/core/security/rasp/freerasp_config.dart
import 'package:freerasp/freerasp.dart';
import 'package:flutter/foundation.dart';

abstract final class FreeRaspConfig {
  static TalsecConfig get config => TalsecConfig(
    androidConfig: AndroidConfig(
      // Must match applicationId in android/app/build.gradle
      expectedPackageName: 'com.example.yourapp',

      // Base64-encoded SHA-256 of your signing certificate
      // Get from Play Console → Setup → App Signing → SHA-256
      // Include both debug and release hashes during development
      expectedSigningCertificateHashes: [
        'RELEASE_SIGNING_CERT_SHA256_BASE64==',
        // Add debug hash only for non-production builds:
        if (!kReleaseMode) 'DEBUG_SIGNING_CERT_SHA256_BASE64==',
      ],

      // Alternative stores beyond Google Play and Huawei AppGallery
      // (those two are included internally by freeRASP)
      // Add Samsung Galaxy Store, Amazon, etc. if you distribute there
      supportedAlternativeStores: const [],
    ),

    iosConfig: IOSConfig(
      // Must match CFBundleIdentifier in Info.plist
      bundleIds: const ['com.example.yourapp'],

      // Apple Developer Team ID — found in developer.apple.com
      teamId: 'YOUR_APPLE_TEAM_ID',
    ),

    // Email for weekly security reports from Talsec
    watcherMail: 'security@yourcompany.com',

    // ✅ CRITICAL: true in production, false in debug/development
    // isProd: false disables some checks to ease development
    isProd: kReleaseMode,

    // Kill the app if threat callbacks are hooked by an attacker
    // Recommended: true for high-security apps
    malwareConfig: MalwareConfig(
      blacklistedHashes: const [],
      blacklistedPackageNames: const [],
      suspiciousPermissions: const [],
    ),
  );
}
```

---

## ThreatCallback — All Threat Handlers

```dart
// lib/core/security/rasp/freerasp_threat_callback.dart
import 'package:freerasp/freerasp.dart';
import 'package:injectable/injectable.dart';

/// Builds the ThreatCallback that routes all freeRASP threats to the RaspBloc.
/// Callbacks run on a background thread — use addEvent, not setState.
@injectable
class FreeRaspThreatCallbackFactory {
  final RaspBloc _bloc;
  FreeRaspThreatCallbackFactory(this._bloc);

  ThreatCallback build() => ThreatCallback(
    // ── Critical threats — block the app ──────────────────────────────

    onRootDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.root)),

    onJailbreakDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.jailbreak)),

    onHookDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.hook)),

    onTamperDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.tamper)),

    onDebuggerDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.debugger)),

    // ── High threats — block in production ────────────────────────────

    onEmulatorDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.emulator)),

    onUntrustedInstallationDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.untrustedInstall)),

    // ── Medium threats — warn user ─────────────────────────────────────

    onDeviceBindingDetected: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.deviceBinding)),

    onSecureHardwareNotAvailable: () =>
        _bloc.add(const RaspEvent.threatDetected(RaspThreat.noSecureHardware)),

    // ── Malware detection (Android only) ──────────────────────────────

    onMalwareDetected: (List<SuspiciousAppInfo> suspiciousApps) =>
        _bloc.add(RaspEvent.malwareDetected(
          apps: suspiciousApps.map((a) => a.packageName).toList(),
        )),
  );
}
```

---

## Initialization — main.dart

```dart
// lib/main.dart
import 'package:freerasp/freerasp.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await configureDependencies();

  // ✅ Start freeRASP before runApp — checks run immediately
  await Talsec.instance.start(FreeRaspConfig.config);

  runApp(const App());
}

// In App widget — attach the threat callback after BLoC is available
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    // Attach callback after BLoC is created
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callbackFactory = GetIt.instance<FreeRaspThreatCallbackFactory>();
      Talsec.instance.attachListener(callbackFactory.build());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<RaspBloc>(),
      child: BlocListener<RaspBloc, RaspState>(
        listener: _onRaspStateChanged,
        child: MaterialApp.router(
          routerConfig: GetIt.instance<AppRouter>().router,
        ),
      ),
    );
  }

  void _onRaspStateChanged(BuildContext context, RaspState state) {
    if (state is RaspThreatDetected) {
      _handleThreat(context, state.threat);
    }
  }

  void _handleThreat(BuildContext context, RaspThreat threat) {
    switch (threat.severity) {
      case ThreatSeverity.critical:
        // Block the app — show non-dismissible dialog
        _showBlockingDialog(context, threat);
      case ThreatSeverity.high:
        if (kReleaseMode) {
          _showBlockingDialog(context, threat);
        }
        // In debug/staging: log but don't block
      case ThreatSeverity.medium:
        _showWarningSnackbar(context, threat);
    }
  }

  void _showBlockingDialog(BuildContext context, RaspThreat threat) {
    showDialog(
      context: context,
      barrierDismissible: false, // ✅ non-dismissible
      builder: (_) => AlertDialog(
        title: const Text('Security Alert'),
        content: Text(threat.userMessage),
        actions: [
          TextButton(
            onPressed: () {
              // Exit the app — do not allow continued use
              SystemNavigator.pop();
            },
            child: const Text('Close App'),
          ),
        ],
      ),
    );
  }
}
```

---

## RaspBloc

```dart
// lib/core/security/rasp/rasp_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'rasp_bloc.freezed.dart';
part 'rasp_event.dart';
part 'rasp_state.dart';

@singleton
class RaspBloc extends Bloc<RaspEvent, RaspState> {
  RaspBloc() : super(const RaspState.secure()) {
    on<ThreatDetectedEvent>(_onThreatDetected);
    on<MalwareDetectedEvent>(_onMalwareDetected);
  }

  void _onThreatDetected(
    ThreatDetectedEvent event,
    Emitter<RaspState> emit,
  ) {
    emit(RaspState.threatDetected(threat: event.threat));
  }

  void _onMalwareDetected(
    MalwareDetectedEvent event,
    Emitter<RaspState> emit,
  ) {
    emit(RaspState.malwareDetected(suspiciousPackages: event.apps));
  }
}

// rasp_event.dart
part of 'rasp_bloc.dart';

@freezed
class RaspEvent with _$RaspEvent {
  const factory RaspEvent.threatDetected(RaspThreat threat) = ThreatDetectedEvent;
  const factory RaspEvent.malwareDetected({required List<String> apps}) = MalwareDetectedEvent;
}

// rasp_state.dart
part of 'rasp_bloc.dart';

@freezed
class RaspState with _$RaspState {
  const factory RaspState.secure() = RaspSecure;
  const factory RaspState.threatDetected({required RaspThreat threat}) = RaspThreatDetected;
  const factory RaspState.malwareDetected({required List<String> suspiciousPackages}) = RaspMalwareDetected;
}
```

---

## RaspThreat Domain Entity

```dart
// lib/core/security/rasp/rasp_threat.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'rasp_threat.freezed.dart';

enum ThreatSeverity { critical, high, medium }

@freezed
class RaspThreat with _$RaspThreat {
  const factory RaspThreat({
    required String id,
    required String name,
    required ThreatSeverity severity,
    required String userMessage,
    required String technicalDescription,
  }) = _RaspThreat;

  // ── Predefined threats ────────────────────────────────────────────────

  static const root = RaspThreat(
    id: 'root',
    name: 'Root Detected',
    severity: ThreatSeverity.critical,
    userMessage: 'This app cannot run on rooted devices for security reasons.',
    technicalDescription: 'Root access detected (su, Magisk, SuperSU)',
  );

  static const jailbreak = RaspThreat(
    id: 'jailbreak',
    name: 'Jailbreak Detected',
    severity: ThreatSeverity.critical,
    userMessage: 'This app cannot run on jailbroken devices for security reasons.',
    technicalDescription: 'Jailbreak detected (unc0ver, checkra1n, Dopamine)',
  );

  static const hook = RaspThreat(
    id: 'hook',
    name: 'Hook Framework Detected',
    severity: ThreatSeverity.critical,
    userMessage: 'A security threat has been detected. The app will close.',
    technicalDescription: 'Hooking framework detected (Frida, Shadow, Xposed)',
  );

  static const tamper = RaspThreat(
    id: 'tamper',
    name: 'App Tampering Detected',
    severity: ThreatSeverity.critical,
    userMessage: 'App integrity check failed. Please reinstall from the official store.',
    technicalDescription: 'Signing certificate mismatch — app has been tampered',
  );

  static const debugger = RaspThreat(
    id: 'debugger',
    name: 'Debugger Detected',
    severity: ThreatSeverity.critical,
    userMessage: 'A security threat has been detected. The app will close.',
    technicalDescription: 'Debugger attached to the process',
  );

  static const emulator = RaspThreat(
    id: 'emulator',
    name: 'Emulator Detected',
    severity: ThreatSeverity.high,
    userMessage: 'This app is not supported on emulators.',
    technicalDescription: 'Running on Android emulator or iOS simulator',
  );

  static const untrustedInstall = RaspThreat(
    id: 'untrusted_install',
    name: 'Untrusted Installation',
    severity: ThreatSeverity.high,
    userMessage: 'This app was not installed from an official store. Please reinstall.',
    technicalDescription: 'App installed from an untrusted source',
  );

  static const deviceBinding = RaspThreat(
    id: 'device_binding',
    name: 'Device Binding Issue',
    severity: ThreatSeverity.medium,
    userMessage: 'A security warning has been detected on your device.',
    technicalDescription: 'Device binding check failed',
  );

  static const noSecureHardware = RaspThreat(
    id: 'no_secure_hardware',
    name: 'Secure Hardware Unavailable',
    severity: ThreatSeverity.medium,
    userMessage: 'Your device does not meet the security requirements for this app.',
    technicalDescription: 'Secure hardware (TEE/StrongBox) not available',
  );
}
```
