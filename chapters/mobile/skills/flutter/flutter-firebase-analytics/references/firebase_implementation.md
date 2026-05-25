# Firebase Analytics — Implementation Guide

Firebase Analytics is free, integrates with BigQuery, Crashlytics, and Remote Config,
and automatically tracks app_open, session_start, and first_open events.

## Setup

```yaml
dependencies:
  firebase_analytics: ^12.3.0
  firebase_core: ^4.7.0
```

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Disable until user consents — required for GDPR/CCPA compliance
  // Enable after showing consent dialog
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(kReleaseMode);

  await configureDependencies();
  runApp(const App());
}
```

---

## Screen Tracking — go_router Observer

```dart
// lib/core/analytics/analytics_route_observer.dart
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AnalyticsRouteObserver extends NavigatorObserver {
  final FirebaseAnalytics _analytics;

  AnalyticsRouteObserver(this._analytics);

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _trackScreen(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _trackScreen(newRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _trackScreen(previousRoute);
  }

  void _trackScreen(Route route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;

    _analytics.logScreenView(
      screenName: name,
      screenClass: name,
    );
  }
}

// Register observer in go_router:
GoRouter(
  observers: [GetIt.instance<AnalyticsRouteObserver>()],
  routes: [...],
)
```

---

## FirebaseAnalyticsAdapter

```dart
// lib/core/analytics/adapters/firebase_analytics_adapter.dart
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:injectable/injectable.dart';

@Injectable(as: AnalyticsProvider, env: [Environment.prod, 'staging'])
class FirebaseAnalyticsAdapter implements AnalyticsProvider {
  final FirebaseAnalytics _analytics;

  FirebaseAnalyticsAdapter(this._analytics);

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
  }) =>
      _analytics.logEvent(name: name, parameters: parameters);

  @override
  Future<void> setUserId(String? userId) =>
      _analytics.setUserId(id: userId);

  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
  }) =>
      _analytics.setUserProperty(name: name, value: value);

  @override
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) =>
      _analytics.logScreenView(
        screenName: screenName,
        screenClass: screenClass ?? screenName,
      );

  @override
  Future<void> setEnabled(bool enabled) =>
      _analytics.setAnalyticsCollectionEnabled(enabled);

  @override
  Future<void> resetAnalyticsData() =>
      _analytics.resetAnalyticsData();
}
```

---

## DI Module — FirebaseAnalytics singleton

```dart
// lib/core/di/analytics_module.dart
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:injectable/injectable.dart';

@module
abstract class AnalyticsModule {
  @singleton
  FirebaseAnalytics get firebaseAnalytics => FirebaseAnalytics.instance;
}
```

---

## Predefined Events — Type-Safe Constants

```dart
// lib/core/analytics/analytics_events.dart

/// Type-safe event names and parameter keys.
/// Prevents typos and makes refactoring safe.
abstract final class AnalyticsEvents {
  // ── Authentication ────────────────────────────────────────────────────
  static const loginSuccess = 'login_success';
  static const loginFailed = 'login_failed';
  static const signupCompleted = 'signup_completed';
  static const logoutCompleted = 'logout_completed';

  // ── Onboarding ────────────────────────────────────────────────────────
  static const onboardingStepCompleted = 'onboarding_step_completed';
  static const onboardingCompleted = 'onboarding_completed';
  static const onboardingSkipped = 'onboarding_skipped';

  // ── Product / Content ─────────────────────────────────────────────────
  static const productViewed = 'product_viewed';
  static const productSearched = 'product_searched';
  static const productAddedToCart = 'product_added_to_cart';
  static const productRemovedFromCart = 'product_removed_from_cart';

  // ── Checkout ──────────────────────────────────────────────────────────
  static const checkoutStarted = 'checkout_started';
  static const paymentMethodSelected = 'payment_method_selected';
  static const orderCompleted = 'order_completed';
  static const orderFailed = 'order_failed';

  // ── Engagement ────────────────────────────────────────────────────────
  static const notificationReceived = 'notification_received';
  static const notificationTapped = 'notification_tapped';
  static const featureDiscovered = 'feature_discovered';
  static const errorShown = 'error_shown';
}

abstract final class AnalyticsParams {
  static const productId = 'product_id';
  static const productName = 'product_name';
  static const categoryId = 'category_id';
  static const searchQuery = 'search_query';
  static const paymentMethod = 'payment_method';
  static const orderTotal = 'order_total';
  static const currency = 'currency';
  static const stepNumber = 'step_number';
  static const stepName = 'step_name';
  static const errorCode = 'error_code';
  static const errorMessage = 'error_message';
  static const featureName = 'feature_name';
}

abstract final class AnalyticsUserProperties {
  static const subscriptionTier = 'subscription_tier';
  static const userSegment = 'user_segment';
  static const appLanguage = 'app_language';
  static const onboardingCompleted = 'onboarding_completed';
}
```

---

## Usage in BLoC / UseCase

```dart
// lib/features/auth/presentation/bloc/auth_bloc.dart
@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;
  final AnalyticsProvider _analytics; // ✅ interface, not Firebase SDK

  AuthBloc(this._repository, this._analytics) : super(/* ... */) {
    on<SignInEvent>(_onSignIn);
    on<SignOutEvent>(_onSignOut);
  }

  Future<void> _onSignIn(SignInEvent event, Emitter<AuthState> emit) async {
    final result = await _repository.signIn(event.email, event.password);

    result.fold(
      (failure) {
        _analytics.logEvent(
          name: AnalyticsEvents.loginFailed,
          parameters: {AnalyticsParams.errorCode: failure.code},
        );
        emit(AuthState.error(failure.message));
      },
      (user) {
        _analytics.setUserId(user.id);
        _analytics.setUserProperty(
          name: AnalyticsUserProperties.subscriptionTier,
          value: user.subscriptionTier.name,
        );
        _analytics.logEvent(name: AnalyticsEvents.loginSuccess);
        emit(AuthState.authenticated(user: user));
      },
    );
  }

  Future<void> _onSignOut(SignOutEvent event, Emitter<AuthState> emit) async {
    await _repository.signOut();
    await _analytics.setUserId(null);       // ✅ clear user ID on logout
    await _analytics.resetAnalyticsData();  // ✅ clear user properties
    emit(const AuthState.unauthenticated());
  }
}
```

---

## Consent Management (GDPR / CCPA)

```dart
// lib/features/consent/presentation/bloc/consent_bloc.dart
@injectable
class ConsentBloc extends Bloc<ConsentEvent, ConsentState> {
  final AnalyticsProvider _analytics;

  ConsentBloc(this._analytics) : super(const ConsentState.initial()) {
    on<ConsentGrantedEvent>(_onGranted);
    on<ConsentRevokedEvent>(_onRevoked);
  }

  Future<void> _onGranted(
    ConsentGrantedEvent event,
    Emitter<ConsentState> emit,
  ) async {
    await _analytics.setEnabled(true);
    emit(const ConsentState.granted());
  }

  Future<void> _onRevoked(
    ConsentRevokedEvent event,
    Emitter<ConsentState> emit,
  ) async {
    await _analytics.setEnabled(false);
    await _analytics.resetAnalyticsData(); // clear previously collected data
    emit(const ConsentState.revoked());
  }
}
```

---

## Android — google-services.json

```
android/app/google-services.json  ← download from Firebase Console
```

```groovy
// android/build.gradle
buildscript {
    dependencies {
        classpath 'com.google.gms:google-services:4.4.2'
    }
}

// android/app/build.gradle
apply plugin: 'com.google.gms.google-services'
```

## iOS — GoogleService-Info.plist

```
ios/Runner/GoogleService-Info.plist  ← download from Firebase Console
```

No additional code needed — Firebase auto-initializes on iOS.
