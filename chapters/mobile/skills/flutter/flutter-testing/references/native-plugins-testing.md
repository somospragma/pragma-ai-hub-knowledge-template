# Native Plugins Testing Reference

Testing code that depends on device hardware, platform APIs, or MethodChannels
requires isolating the native dependency behind a Dart interface.

---

## The Core Pattern: Interface → Impl → Fake

```
abstract interface class LocationDataSource   ← mock / fake in tests
         ↑
LocationDataSourceImpl (uses geolocator)      ← real app
         ↑
FakeLocationDataSource                        ← test double
```

Never depend on the plugin class directly in business logic.

---

## Step 1: Define the Interface

```dart
// lib/features/location/data/data_sources/location_data_source.dart
abstract interface class LocationDataSource {
  Future<LocationData> getCurrentLocation();
  Stream<LocationData> watchLocation();
  Future<bool> requestPermission();
}

class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

sealed class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
}

final class PermissionDeniedException extends LocationException {
  const PermissionDeniedException() : super('Location permission denied');
}

final class LocationUnavailableException extends LocationException {
  const LocationUnavailableException() : super('Location service unavailable');
}
```

---

## Step 2: Implement with the Plugin

```dart
// lib/features/location/data/data_sources/location_data_source_impl.dart
class LocationDataSourceImpl implements LocationDataSource {
  final Geolocator _geolocator;

  LocationDataSourceImpl({Geolocator? geolocator})
      : _geolocator = geolocator ?? Geolocator();

  @override
  Future<LocationData> getCurrentLocation() async {
    final permission = await _geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException();
    }

    final enabled = await _geolocator.isLocationServiceEnabled();
    if (!enabled) throw const LocationUnavailableException();

    final position = await _geolocator.getCurrentPosition();
    return LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  @override
  Stream<LocationData> watchLocation() =>
      _geolocator.getPositionStream().map(
        (p) => LocationData(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracy: p.accuracy,
        ),
      );

  @override
  Future<bool> requestPermission() async {
    final result = await _geolocator.requestPermission();
    return result == LocationPermission.whileInUse ||
        result == LocationPermission.always;
  }
}
```

---

## Step 3: Create a Fake for Tests

```dart
// test/fixtures/fake_location_data_source.dart
class FakeLocationDataSource implements LocationDataSource {
  final _controller = StreamController<LocationData>.broadcast();

  bool shouldDenyPermission = false;
  bool shouldFailLocation = false;
  LocationData? nextLocation;

  @override
  Future<LocationData> getCurrentLocation() async {
    if (shouldDenyPermission) throw const PermissionDeniedException();
    if (shouldFailLocation) throw const LocationUnavailableException();
    return nextLocation ??
        const LocationData(latitude: 4.711, longitude: -74.072, accuracy: 5.0);
  }

  @override
  Stream<LocationData> watchLocation() => _controller.stream;

  @override
  Future<bool> requestPermission() async => !shouldDenyPermission;

  // Test helpers
  void emit(LocationData location) => _controller.add(location);
  void emitError(Exception error) => _controller.addError(error);
  void dispose() => _controller.close();
}
```

---

## Unit Tests with the Fake

```dart
void main() {
  late FakeLocationDataSource fakeDataSource;
  late GetCurrentLocationUseCase sut;

  setUp(() {
    fakeDataSource = FakeLocationDataSource();
    sut = GetCurrentLocationUseCase(fakeDataSource);
  });

  tearDown(() => fakeDataSource.dispose());

  group('GetCurrentLocationUseCase', () {
    test('returns Right(LocationData) on success', () async {
      fakeDataSource.nextLocation = const LocationData(
        latitude: 4.711,
        longitude: -74.072,
        accuracy: 3.0,
      );

      final result = await sut(NoParams());

      expect(result.isRight(), true);
      result.fold(
        (_) => fail('expected Right'),
        (loc) => expect(loc.latitude, 4.711),
      );
    });

    test('returns Left(PermissionFailure) when permission denied', () async {
      fakeDataSource.shouldDenyPermission = true;

      final result = await sut(NoParams());

      expect(result.fold((f) => f, (_) => null), isA<PermissionFailure>());
    });

    test('returns Left(LocationFailure) when service unavailable', () async {
      fakeDataSource.shouldFailLocation = true;

      final result = await sut(NoParams());

      expect(result.fold((f) => f, (_) => null), isA<LocationFailure>());
    });
  });

  group('watchLocation stream', () {
    test('emits location updates', () {
      const loc1 = LocationData(latitude: 4.711, longitude: -74.072, accuracy: 5.0);
      const loc2 = LocationData(latitude: 4.712, longitude: -74.073, accuracy: 4.0);

      expect(
        fakeDataSource.watchLocation(),
        emitsInOrder([loc1, loc2]),
      );

      fakeDataSource.emit(loc1);
      fakeDataSource.emit(loc2);
    });

    test('propagates stream errors', () {
      expect(
        fakeDataSource.watchLocation(),
        emitsError(isA<LocationUnavailableException>()),
      );

      fakeDataSource.emitError(const LocationUnavailableException());
    });
  });
}
```

---

## MethodChannel Mocking

For services that communicate with native code via `MethodChannel`:

```dart
// lib/services/biometric_service.dart
class BiometricService {
  static const _channel = MethodChannel('com.example.app/biometrics');

  Future<bool> authenticate(String reason) async {
    try {
      return await _channel.invokeMethod<bool>('authenticate', {'reason': reason}) ?? false;
    } on PlatformException catch (e) {
      throw BiometricException(e.message ?? 'Authentication failed');
    }
  }
}

// test/services/biometric_service_test.dart
void main() {
  const channel = MethodChannel('com.example.app/biometrics');

  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns true on successful authentication', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'authenticate') return true;
      return null;
    });

    final result = await BiometricService().authenticate('Confirm identity');
    expect(result, true);
  });

  test('throws BiometricException on PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'AUTH_FAILED', message: 'Not enrolled');
    });

    expect(
      () => BiometricService().authenticate('Confirm identity'),
      throwsA(isA<BiometricException>()),
    );
  });

  test('passes reason argument to native', () async {
    String? capturedReason;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedReason = call.arguments['reason'] as String?;
      return true;
    });

    await BiometricService().authenticate('Confirm payment');
    expect(capturedReason, 'Confirm payment');
  });
}
```

---

## EventChannel Mocking

For streaming data from native (GPS, sensors, connectivity):

```dart
// The EventChannel itself cannot be easily mocked in unit tests.
// The recommended approach is to wrap it behind an interface (same pattern above)
// and use a fake StreamController in tests.

// lib/services/sensor_service.dart
abstract interface class SensorService {
  Stream<double> watchAccelerometer();
}

class SensorServiceImpl implements SensorService {
  static const _channel = EventChannel('com.example.app/accelerometer');

  @override
  Stream<double> watchAccelerometer() =>
      _channel.receiveBroadcastStream().map((e) => e as double);
}

// test/fixtures/fake_sensor_service.dart
class FakeSensorService implements SensorService {
  final _controller = StreamController<double>.broadcast();

  @override
  Stream<double> watchAccelerometer() => _controller.stream;

  void emit(double value) => _controller.add(value);
  void dispose() => _controller.close();
}
```

---

## Common Plugin Fakes

### SharedPreferences

```dart
class FakeLocalStorage implements LocalStorageService {
  final _store = <String, String>{};

  @override Future<void> save(String key, String value) async => _store[key] = value;
  @override Future<String?> get(String key) async => _store[key];
  @override Future<void> clear() async => _store.clear();
}
```

### Connectivity

```dart
class FakeConnectivityService implements ConnectivityService {
  final _controller = StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _status = ConnectivityStatus.online;

  @override Stream<ConnectivityStatus> watch() => _controller.stream;
  @override Future<ConnectivityStatus> check() async => _status;

  void goOffline() { _status = ConnectivityStatus.offline; _controller.add(_status); }
  void goOnline()  { _status = ConnectivityStatus.online;  _controller.add(_status); }
  void dispose()   => _controller.close();
}
```

---

## Rules

- Always isolate plugins behind `abstract interface class`
- Use fakes (not mocks) for stateful plugin behaviour (streams, permission state)
- Use `MethodChannel` mock handler only for thin service wrappers
- Never test plugin internals — test your code's response to plugin outputs
- Register `TestWidgetsFlutterBinding.ensureInitialized()` before any MethodChannel test
- Clean up mock handlers in `tearDown`
