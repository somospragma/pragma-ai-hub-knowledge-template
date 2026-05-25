# Feature Flags per Environment

`lib/core/config/app_config.dart` → `FeatureFlags`

---

## Principle

Feature flags control which features are active in each environment.
They live in `AppConfig` as typed fields of `FeatureFlags` — no scattered
`if (flavor == 'prod')` in business code. This allows activating a feature
in staging for QA without touching prod, or doing a gradual rollout by
changing only the `.env` file.

---

## Definition in .env

```dotenv
# .env.dev
ENABLE_NEW_CHECKOUT=true      # Active in dev for development
ENABLE_ANALYTICS=false        # Off in dev to avoid polluting data
ENABLE_BIOMETRIC_AUTH=true
ENABLE_DARK_MODE_V2=true

# .env.staging
ENABLE_NEW_CHECKOUT=true      # Active in staging for QA
ENABLE_ANALYTICS=true
ENABLE_BIOMETRIC_AUTH=true
ENABLE_DARK_MODE_V2=false

# .env.prod
ENABLE_NEW_CHECKOUT=false     # Off in prod until validated in staging
ENABLE_ANALYTICS=true
ENABLE_BIOMETRIC_AUTH=true
ENABLE_DARK_MODE_V2=false
```

---

## FeatureFlags — Typed Model

```dart
// lib/core/config/feature_flags.dart

final class FeatureFlags {
  const FeatureFlags({
    required this.newCheckout,
    required this.analytics,
    required this.biometricAuth,
    required this.darkModeV2,
  });

  final bool newCheckout;
  final bool analytics;
  final bool biometricAuth;
  final bool darkModeV2;

  /// Helper for logging and debugging — shows the state of all flags.
  Map<String, bool> toMap() => {
    'new_checkout':   newCheckout,
    'analytics':      analytics,
    'biometric_auth': biometricAuth,
    'dark_mode_v2':   darkModeV2,
  };
}
```

---

## Consumption in the UI — with Riverpod

```dart
// Direct access provider for flags
final featureFlagsProvider = Provider<FeatureFlags>(
  (ref) => ref.read(appConfigProvider).featureFlags,
);

// In a widget
final flags = ref.watch(featureFlagsProvider);

if (flags.newCheckout)
  const NewCheckoutScreen()
else
  const LegacyCheckoutScreen(),
```

---

## Consumption in the UI — with BLoC

```dart
// Inject AppConfig into the BLoC that needs it
class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc({required AppConfig config}) : _flags = config.featureFlags, ...;

  final FeatureFlags _flags;

  void _onCheckoutStarted(...) {
    if (_flags.newCheckout) {
      // new flow
    } else {
      // legacy flow
    }
  }
}
```

---

## Logging Flag State on Startup

Logging which flags are active when the app initializes is useful for debugging
in staging when QA reports unexpected behavior:

```dart
// In main_staging.dart, after initializing AppConfig
AppLogger.info(
  'feature_flags_initialized',
  context: config.featureFlags.toMap(),
);
```

---

## Adding a New Flag — Checklist

1. Add the variable to all three `.env.*` files and to `.env.example`
2. Add the `@EnviedField` in `env_dev.dart`, `env_staging.dart`, `env_prod.dart`
3. Regenerate with `dart run build_runner build --delete-conflicting-outputs`
4. Add the field to `FeatureFlags`
5. Pass it in `AppConfig.forFlavor()` for all three flavors
6. Add the secret to GitHub Actions, Azure DevOps, and the Fastlane CI `.env` files
