# Analytics Provider — Strategy + Adapter Pattern

Use this pattern so the analytics provider can be swapped (Firebase → Mixpanel →
Amplitude → Segment) without touching domain, BLoC, or use cases.

---

## 1. Domain — AnalyticsProvider Interface (Strategy)

```dart
// lib/core/analytics/analytics_provider.dart

/// Provider-agnostic analytics contract.
/// Domain, BLoC, and use cases only know this interface — never a specific SDK.
abstract interface class AnalyticsProvider {
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  });

  Future<void> setUserId(String? userId);

  Future<void> setUserProperty({
    required String name,
    required String? value,
  });

  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  });

  Future<void> setEnabled(bool enabled);

  Future<void> resetAnalyticsData();
}
```

---

## 2. Firebase Adapter (Primary)

See `firebase_implementation.md` for the full `FirebaseAnalyticsAdapter`.

```dart
@Injectable(as: AnalyticsProvider, env: [Environment.prod, 'staging'])
class FirebaseAnalyticsAdapter implements AnalyticsProvider { ... }
```

---

## 3. Mixpanel Adapter (Alternative)

```dart
// lib/core/analytics/adapters/mixpanel_analytics_adapter.dart
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:injectable/injectable.dart';

@Injectable(as: AnalyticsProvider, env: ['mixpanel'])
class MixpanelAnalyticsAdapter implements AnalyticsProvider {
  final Mixpanel _mixpanel;

  MixpanelAnalyticsAdapter(this._mixpanel);

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    _mixpanel.track(name, properties: parameters?.cast<String, dynamic>());
  }

  @override
  Future<void> setUserId(String? userId) async {
    if (userId != null) {
      _mixpanel.identify(userId);
    } else {
      _mixpanel.reset(); // clear identity on logout
    }
  }

  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    if (value != null) {
      _mixpanel.getPeople().set(name, value);
    } else {
      _mixpanel.getPeople().unset(name);
    }
  }

  @override
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    _mixpanel.track('screen_viewed', properties: {
      'screen_name': screenName,
      if (screenClass != null) 'screen_class': screenClass,
    });
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      _mixpanel.optInTracking();
    } else {
      _mixpanel.optOutTracking();
    }
  }

  @override
  Future<void> resetAnalyticsData() async {
    _mixpanel.reset();
  }
}
```

---

## 4. Composite Adapter — Fan-Out to Multiple Providers

Use when you need to send events to more than one analytics provider simultaneously.

```dart
// lib/core/analytics/adapters/composite_analytics_adapter.dart
import 'package:injectable/injectable.dart';

/// Sends every analytics call to all registered providers.
/// Useful when migrating between providers or running multiple in parallel.
@Injectable(as: AnalyticsProvider, env: ['composite'])
class CompositeAnalyticsAdapter implements AnalyticsProvider {
  final List<AnalyticsProvider> _providers;

  CompositeAnalyticsAdapter(this._providers);

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) =>
      _fanOut((p) => p.logEvent(name: name, parameters: parameters));

  @override
  Future<void> setUserId(String? userId) =>
      _fanOut((p) => p.setUserId(userId));

  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) =>
      _fanOut((p) => p.setUserProperty(name: name, value: value));

  @override
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) =>
      _fanOut((p) => p.logScreenView(
        screenName: screenName,
        screenClass: screenClass,
      ));

  @override
  Future<void> setEnabled(bool enabled) =>
      _fanOut((p) => p.setEnabled(enabled));

  @override
  Future<void> resetAnalyticsData() =>
      _fanOut((p) => p.resetAnalyticsData());

  /// Runs the operation on all providers concurrently.
  /// Errors from individual providers are caught and logged — never propagated.
  Future<void> _fanOut(Future<void> Function(AnalyticsProvider) fn) async {
    await Future.wait(
      _providers.map((p) => fn(p).catchError((e) {
        debugPrint('[Analytics] Provider ${p.runtimeType} error: $e');
      })),
    );
  }
}
```

---

## 5. NoOp Adapter — Debug / Tests

```dart
// lib/core/analytics/adapters/noop_analytics_adapter.dart
import 'package:injectable/injectable.dart';

@Injectable(as: AnalyticsProvider, env: [Environment.dev, Environment.test])
class NoOpAnalyticsAdapter implements AnalyticsProvider {
  @override
  Future<void> logEvent({required String name, Map<String, Object>? parameters}) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> setUserProperty({required String name, required String? value}) async {}

  @override
  Future<void> logScreenView({required String screenName, String? screenClass}) async {}

  @override
  Future<void> setEnabled(bool enabled) async {}

  @override
  Future<void> resetAnalyticsData() async {}
}
```

---

## 6. DI Binding — One Line to Swap Providers

```dart
// lib/core/di/analytics_module.dart
import 'package:injectable/injectable.dart';

@module
abstract class AnalyticsModule {
  @singleton
  FirebaseAnalytics get firebaseAnalytics => FirebaseAnalytics.instance;

  // ✅ Change this one binding to swap providers
  @lazySingleton
  AnalyticsProvider analyticsProvider(
    FirebaseAnalyticsAdapter firebase,
    MixpanelAnalyticsAdapter mixpanel,
    NoOpAnalyticsAdapter noOp,
  ) {
    const provider = String.fromEnvironment(
      'ANALYTICS_PROVIDER',
      defaultValue: 'firebase',
    );
    return switch (provider) {
      'mixpanel' => mixpanel,
      'noop' => noOp,
      _ => kReleaseMode ? firebase : noOp,
    };
  }

  // Composite: send to Firebase + Mixpanel simultaneously
  @lazySingleton
  @Named('composite')
  AnalyticsProvider compositeProvider(
    FirebaseAnalyticsAdapter firebase,
    MixpanelAnalyticsAdapter mixpanel,
  ) =>
      CompositeAnalyticsAdapter([firebase, mixpanel]);
}
```

```bash
# Build with specific provider
flutter build apk --dart-define=ANALYTICS_PROVIDER=firebase
flutter build apk --dart-define=ANALYTICS_PROVIDER=mixpanel
flutter run --dart-define=ANALYTICS_PROVIDER=noop  # development
```

---

## 7. Testing — NoOp Adapter

```dart
// test/features/auth/presentation/bloc/auth_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late AuthBloc bloc;
  late MockAuthRepository mockRepo;

  setUp(() {
    mockRepo = MockAuthRepository();
    bloc = AuthBloc(
      mockRepo,
      NoOpAnalyticsAdapter(), // ✅ zero overhead in tests
    );
  });

  tearDown(() => bloc.close());

  blocTest<AuthBloc, AuthState>(
    'emits authenticated on successful login',
    build: () {
      when(() => mockRepo.signIn(any(), any()))
          .thenAnswer((_) async => Right(User.mock()));
      return bloc;
    },
    act: (b) => b.add(SignInEvent(email: 'a@b.com', password: 'pass')),
    expect: () => [isA<AuthStateAuthenticated>()],
  );
}
```

---

## Provider Comparison

| Feature | Firebase | Mixpanel | Amplitude | Segment |
|---|---|---|---|---|
| Free tier | ✅ generous | ✅ limited | ✅ limited | ✅ limited |
| Auto events | ✅ (app_open, etc.) | ❌ | ❌ | ❌ |
| Funnels | ⚠️ basic | ✅ advanced | ✅ advanced | via destinations |
| Cohorts | ⚠️ basic | ✅ | ✅ | via destinations |
| BigQuery export | ✅ | ❌ | ❌ | ❌ |
| Multi-destination | ❌ | ❌ | ❌ | ✅ (CDP) |
| Flutter SDK | ✅ official | ✅ | ✅ | ✅ |
| Setup complexity | Low | Low | Low | Medium |
