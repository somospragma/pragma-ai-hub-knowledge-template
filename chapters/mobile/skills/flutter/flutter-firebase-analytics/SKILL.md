---
name: flutter-firebase-analytics
description: >
  Implements analytics event tracking and user properties in Flutter using Firebase Analytics as the primary provider. Uses a Strategy + Adapter pattern so the analytics provider can be swapped (Firebase → Mixpanel → Amplitude → custom) without touching domain or presentation layers. Covers screen tracking via go_router observer, custom events, user properties, and consent management.
commands:
  - setup-analytics
inputs:
  - name: action
    description: Action to perform (implement, add-event, audit). "implement" generates the full analytics architecture (interface, adapter, route observer, DI), "add-event" adds tracking for a specific user action or flow, "audit" checks for missing event tracking on critical user paths or direct SDK imports.
    required: true
  - name: target
    description: Path to the core/analytics directory or specific feature to instrument (e.g. lib/core/analytics/ for implement, lib/features/checkout/ for add-event).
    required: true
  - name: provider
    description: Analytics provider to use (firebase, mixpanel, amplitude, composite, noop). Defaults to firebase.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Analytics Strategy

See the reference files for complete patterns and code examples.

**Analytics = understand what users actually do, not what you think they do.**

## Provider Options (April 2026)

| Provider | Package | Best for |
|---|---|---|
| **Firebase Analytics** | `firebase_analytics ^12.3.0` | Free, Google ecosystem, BigQuery export |
| **Mixpanel** | `mixpanel_flutter` | Product analytics, funnels, cohorts |
| **Amplitude** | `amplitude_flutter` | Behavioral analytics, A/B testing |
| **Segment** | `analytics` | CDP — routes events to multiple destinations |
| **Custom / OpenTelemetry** | — | Full control, vendor-neutral |

> Firebase Analytics is the primary implementation. Use the `AnalyticsProvider`
> Strategy + Adapter pattern to swap providers without touching business logic.

---

## Provider Strategy Pattern

```
Domain (AnalyticsProvider interface)
  ↓ abstract interface class — knows nothing about Firebase or any SDK
Data (AnalyticsProviderAdapter)
  ├── FirebaseAnalyticsAdapter   implements AnalyticsProvider  ← primary
  ├── MixpanelAnalyticsAdapter   implements AnalyticsProvider  ← alternative
  ├── CompositeAnalyticsAdapter  implements AnalyticsProvider  ← fan-out to multiple
  └── NoOpAnalyticsAdapter       implements AnalyticsProvider  ← tests / debug
DI
  └── bind AnalyticsProvider → FirebaseAnalyticsAdapter  ← change to swap
```

---

## Core Patterns — Quick Reference

### Log event
```dart
_analytics.logEvent(
  name: 'product_viewed',
  parameters: {'product_id': id, 'category': category},
);
```

### Screen tracking (go_router observer)
```dart
GoRouter(
  observers: [AnalyticsRouteObserver(_analytics)],
  routes: [...],
)
```

### User property
```dart
_analytics.setUserProperty(name: 'subscription_tier', value: 'premium');
```

### User ID (after login)
```dart
_analytics.setUserId(userId);
// On logout:
_analytics.setUserId(null);
```

---

## Event Naming Conventions

```
✅ snake_case, descriptive, action-oriented
✅ product_viewed, checkout_started, payment_completed
✅ onboarding_step_completed (with step parameter)

❌ ProductViewed, product-viewed, pv
❌ button_clicked (too generic — what button?)
❌ screen_shown (use screen tracking instead)
```

---

## Consent & Privacy

```dart
// ✅ Disable collection until user consents (GDPR/CCPA)
await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);

// Enable after consent
await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
```

---

## Quick Wins Checklist

- [ ] `AnalyticsProvider` interface used — not Firebase SDK directly in BLoC/domain
- [ ] `NoOpAnalyticsAdapter` used in debug builds and tests
- [ ] Screen tracking via `AnalyticsRouteObserver` on go_router
- [ ] User ID set on login, cleared on logout
- [ ] Analytics collection disabled until user consents (GDPR)
- [ ] Event names follow `snake_case` convention
- [ ] `CompositeAnalyticsAdapter` used when sending to multiple providers
- [ ] `setUserId(null)` called on logout

## Reference Files

- `references/firebase_implementation.md` — Firebase Analytics setup, screen observer, events, user properties, consent
- `references/analytics_provider_pattern.md` — AnalyticsProvider interface, adapters (Firebase, Mixpanel, Composite, NoOp), DI binding
