# RASP Provider Strategy + Adapter Pattern

If the project needs to swap RASP providers (freeRASP → commercial RASP → custom),
use the Strategy + Adapter pattern. Domain and presentation layers only know
`RaspProvider` — never a specific SDK.

---

## 1. Domain — RaspProvider Interface (Strategy)

```dart
// lib/core/security/rasp/rasp_provider.dart
import 'dart:async';

/// Provider-agnostic RASP contract.
/// Domain and BLoC only know this interface — never a specific SDK.
abstract interface class RaspProvider {
  /// Initialize the RASP provider with app-specific configuration.
  Future<void> initialize();

  /// Stream of detected threats — emits whenever a threat is detected.
  Stream<RaspThreat> get threatStream;

  /// Stream of detected malware packages (Android only).
  Stream<List<String>> get malwareStream;

  /// Dispose resources when the app is closing.
  Future<void> dispose();
}
```

---

## 2. FreeRaspAdapter — Primary Implementation

```dart
// lib/core/security/rasp/adapters/free_rasp_adapter.dart
import 'dart:async';
import 'package:freerasp/freerasp.dart';
import 'package:injectable/injectable.dart';

/// Adapter that wraps freeRASP behind the RaspProvider interface.
/// To swap providers: create a new adapter, change the DI binding.
@Injectable(as: RaspProvider, env: [Environment.prod, 'staging'])
class FreeRaspAdapter implements RaspProvider {
  final _threatController = StreamController<RaspThreat>.broadcast();
  final _malwareController = StreamController<List<String>>.broadcast();

  @override
  Stream<RaspThreat> get threatStream => _threatController.stream;

  @override
  Stream<List<String>> get malwareStream => _malwareController.stream;

  @override
  Future<void> initialize() async {
    await Talsec.instance.start(FreeRaspConfig.config);

    Talsec.instance.attachListener(ThreatCallback(
      onRootDetected: () => _emit(RaspThreat.root),
      onJailbreakDetected: () => _emit(RaspThreat.jailbreak),
      onHookDetected: () => _emit(RaspThreat.hook),
      onTamperDetected: () => _emit(RaspThreat.tamper),
      onDebuggerDetected: () => _emit(RaspThreat.debugger),
      onEmulatorDetected: () => _emit(RaspThreat.emulator),
      onUntrustedInstallationDetected: () => _emit(RaspThreat.untrustedInstall),
      onDeviceBindingDetected: () => _emit(RaspThreat.deviceBinding),
      onSecureHardwareNotAvailable: () => _emit(RaspThreat.noSecureHardware),
      onMalwareDetected: (apps) => _malwareController.add(
        apps.map((a) => a.packageName).toList(),
      ),
    ));
  }

  void _emit(RaspThreat threat) {
    if (!_threatController.isClosed) _threatController.add(threat);
  }

  @override
  Future<void> dispose() async {
    await _threatController.close();
    await _malwareController.close();
  }
}
```

---

## 3. CommercialRaspAdapter — Example Alternative

```dart
// lib/core/security/rasp/adapters/commercial_rasp_adapter.dart
import 'dart:async';
import 'package:injectable/injectable.dart';

/// Adapter for a commercial RASP SDK.
/// Same interface — swap by changing the DI binding.
@Injectable(as: RaspProvider, env: ['commercial'])
class CommercialRaspAdapter implements RaspProvider {
  final CommercialRaspSdk _sdk; // vendor SDK — injected
  final _threatController = StreamController<RaspThreat>.broadcast();
  final _malwareController = StreamController<List<String>>.broadcast();

  CommercialRaspAdapter(this._sdk);

  @override
  Stream<RaspThreat> get threatStream => _threatController.stream;

  @override
  Stream<List<String>> get malwareStream => _malwareController.stream;

  @override
  Future<void> initialize() async {
    await _sdk.initialize(
      onRootDetected: () => _threatController.add(RaspThreat.root),
      onJailbreakDetected: () => _threatController.add(RaspThreat.jailbreak),
      onHookDetected: () => _threatController.add(RaspThreat.hook),
      onTamperDetected: () => _threatController.add(RaspThreat.tamper),
      // Map vendor-specific callbacks to domain RaspThreat constants
    );
  }

  @override
  Future<void> dispose() async {
    await _sdk.shutdown();
    await _threatController.close();
    await _malwareController.close();
  }
}
```

---

## 4. MockRaspAdapter — For Tests

```dart
// lib/core/security/rasp/adapters/mock_rasp_adapter.dart
import 'dart:async';
import 'package:injectable/injectable.dart';

@Injectable(as: RaspProvider, env: [Environment.test])
class MockRaspAdapter implements RaspProvider {
  final _threatController = StreamController<RaspThreat>.broadcast();
  final _malwareController = StreamController<List<String>>.broadcast();

  @override
  Stream<RaspThreat> get threatStream => _threatController.stream;

  @override
  Stream<List<String>> get malwareStream => _malwareController.stream;

  @override
  Future<void> initialize() async {
    // No-op in tests — threats are emitted manually via simulateThreat()
  }

  /// Simulate a threat for testing purposes.
  void simulateThreat(RaspThreat threat) {
    _threatController.add(threat);
  }

  /// Simulate malware detection for testing purposes.
  void simulateMalware(List<String> packages) {
    _malwareController.add(packages);
  }

  @override
  Future<void> dispose() async {
    await _threatController.close();
    await _malwareController.close();
  }
}
```

---

## 5. RaspBloc — Provider-Agnostic

```dart
// lib/core/security/rasp/rasp_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'dart:async';

part 'rasp_bloc.freezed.dart';
part 'rasp_event.dart';
part 'rasp_state.dart';

@singleton
class RaspBloc extends Bloc<RaspEvent, RaspState> {
  final RaspProvider _provider;
  StreamSubscription<RaspThreat>? _threatSub;
  StreamSubscription<List<String>>? _malwareSub;

  RaspBloc(this._provider) : super(const RaspState.initializing()) {
    on<InitializeRaspEvent>(_onInitialize);
    on<ThreatDetectedEvent>(_onThreatDetected);
    on<MalwareDetectedEvent>(_onMalwareDetected);
  }

  Future<void> _onInitialize(
    InitializeRaspEvent event,
    Emitter<RaspState> emit,
  ) async {
    await _provider.initialize();

    _threatSub = _provider.threatStream.listen(
      (threat) => add(RaspEvent.threatDetected(threat)),
    );

    _malwareSub = _provider.malwareStream.listen(
      (apps) => add(RaspEvent.malwareDetected(apps: apps)),
    );

    emit(const RaspState.secure());
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

  @override
  Future<void> close() async {
    await _threatSub?.cancel();
    await _malwareSub?.cancel();
    await _provider.dispose();
    return super.close();
  }
}

// rasp_event.dart
part of 'rasp_bloc.dart';

@freezed
class RaspEvent with _$RaspEvent {
  const factory RaspEvent.initialize() = InitializeRaspEvent;
  const factory RaspEvent.threatDetected(RaspThreat threat) = ThreatDetectedEvent;
  const factory RaspEvent.malwareDetected({required List<String> apps}) = MalwareDetectedEvent;
}

// rasp_state.dart
part of 'rasp_bloc.dart';

@freezed
class RaspState with _$RaspState {
  const factory RaspState.initializing() = RaspInitializing;
  const factory RaspState.secure() = RaspSecure;
  const factory RaspState.threatDetected({required RaspThreat threat}) = RaspThreatDetected;
  const factory RaspState.malwareDetected({
    required List<String> suspiciousPackages,
  }) = RaspMalwareDetected;
}
```

---

## 6. DI Binding — One Line to Swap Providers

```dart
// lib/core/di/rasp_module.dart
import 'package:injectable/injectable.dart';

@module
abstract class RaspModule {
  // ✅ Change this one binding to swap RASP providers
  @singleton
  RaspProvider raspProvider(FreeRaspAdapter adapter) => adapter;

  // To switch to commercial RASP:
  // @singleton
  // RaspProvider raspProvider(CommercialRaspAdapter adapter) => adapter;
}

// Or via dart-define:
// flutter build apk --dart-define=RASP_PROVIDER=freerasp
@module
abstract class RaspModuleEnv {
  @singleton
  RaspProvider raspProvider(
    FreeRaspAdapter freeRasp,
    CommercialRaspAdapter commercial,
  ) {
    const provider = String.fromEnvironment(
      'RASP_PROVIDER',
      defaultValue: 'freerasp',
    );
    return switch (provider) {
      'commercial' => commercial,
      _ => freeRasp,
    };
  }
}
```

---

## 7. Testing — MockRaspAdapter

```dart
// test/core/security/rasp/rasp_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RaspBloc bloc;
  late MockRaspAdapter mockAdapter;

  setUp(() {
    mockAdapter = MockRaspAdapter();
    bloc = RaspBloc(mockAdapter);
  });

  tearDown(() => bloc.close());

  group('RaspBloc', () {
    blocTest<RaspBloc, RaspState>(
      'emits secure after initialization',
      build: () => bloc,
      act: (b) => b.add(const RaspEvent.initialize()),
      expect: () => [
        const RaspState.initializing(),
        const RaspState.secure(),
      ],
    );

    blocTest<RaspBloc, RaspState>(
      'emits threatDetected when root is detected',
      build: () => bloc,
      act: (b) async {
        b.add(const RaspEvent.initialize());
        await Future.delayed(Duration.zero);
        mockAdapter.simulateThreat(RaspThreat.root);
      },
      expect: () => [
        const RaspState.initializing(),
        const RaspState.secure(),
        const RaspState.threatDetected(threat: RaspThreat.root),
      ],
    );

    blocTest<RaspBloc, RaspState>(
      'emits malwareDetected when suspicious apps found',
      build: () => bloc,
      act: (b) async {
        b.add(const RaspEvent.initialize());
        await Future.delayed(Duration.zero);
        mockAdapter.simulateMalware(['com.suspicious.app']);
      },
      expect: () => [
        const RaspState.initializing(),
        const RaspState.secure(),
        const RaspState.malwareDetected(
          suspiciousPackages: ['com.suspicious.app'],
        ),
      ],
    );
  });
}
```

---

## Architecture Summary

```
main.dart
  └── RaspBloc.add(initialize)
        └── RaspProvider.initialize()  ← FreeRaspAdapter calls Talsec.start()
              └── threatStream emits RaspThreat
                    └── RaspBloc emits RaspState.threatDetected
                          └── App widget BlocListener
                                └── _handleThreat() → blocking dialog / warn

Swap provider:
  Change DI binding: FreeRaspAdapter → CommercialRaspAdapter
  Nothing else changes — BLoC, domain, UI are all provider-agnostic
```
