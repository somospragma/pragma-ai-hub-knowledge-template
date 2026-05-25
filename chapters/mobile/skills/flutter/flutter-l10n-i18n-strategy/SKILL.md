---
name: flutter-l10n-i18n-strategy
description: >
  Implements advanced localization (l10n) and internationalization (i18n) in Flutter-type-safe translations with slang, official gen-l10n with ARB files, plurals, gender, date/number/currency formatting with intl, RTL layout support, dynamic locale switching, locale persistence, and translation workflow at scale. Use this skill when adding multi-language support, handling plurals or gender, formatting dates/currencies per locale, supporting RTL languages (Arabic, Hebrew, Persian), managing translation files, or setting up a translation CI pipeline.
commands:
  - setup-l10n-i18n
inputs:
  - name: action
    description: Action to perform (implement, add-locale, audit). "implement" generates the full l10n infrastructure (translation files, locale config, persistence), "add-locale" adds support for a new language, "audit" checks for hardcoded strings, missing translations, or incorrect formatting patterns.
    required: true
  - name: target
    description: Path to the l10n directory or project root (e.g. lib/l10n/ for implement, lib/ for audit).
    required: true
  - name: approach
    description: Translation approach to use (gen-l10n, slang). Defaults to gen-l10n (official Flutter toolchain).
    required: false
  - name: locales
    description: Comma-separated list of locale codes to support (e.g. en,es,pt,ar). Required when action is "implement" or "add-locale".
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Localization Strategy

See the reference files for complete patterns and code examples.

**i18n** = preparing the app to support multiple languages (infrastructure).
**l10n** = adapting the app for a specific locale — language + region + format (content).

## Package Status (April 2026)

```yaml
dependencies:
  # Translation infrastructure — flutter_localizations is the default
  flutter_localizations:    # ✅ default — official Flutter SDK, no extra package
    sdk: flutter
  intl: ^0.20.2             # required by flutter_localizations

  # Alternative: slang (type-safe, zero runtime parsing)
  # slang: ^4.14.0
  # slang_flutter: ^4.14.0

  # Locale persistence
  shared_preferences: ^2.x

dev_dependencies:
  # Only needed if using slang
  # slang_build_runner: ^4.14.0
  # build_runner: ^2.14.1
```

---

## Approach Selection

| Approach | Best for | Tradeoffs |
|---|---|---|
| **flutter_localizations + gen-l10n** ✅ **default** | Flutter-standard, no extra package, ARB files, compile-time safe | ARB-only format, slightly more verbose |
| **slang** | Type-safe, zero runtime parsing, JSON/YAML/ARB/CSV, Flutter-independent | Requires codegen + extra package |
| **easy_localization** | OTA updates, JSON files, simpler setup | Runtime parsing, less safe |

> **Default choice: `flutter_localizations` + `gen-l10n`** — it is the official Flutter
> toolchain, requires no additional packages beyond the SDK, and generates type-safe
> Dart code from ARB files at build time.
> Use **slang** when you need JSON/YAML format, Flutter-independent translations
> (shared Dart packages), or zero runtime parsing is a hard requirement.

---

## What to Localize

| Content | Tool |
|---|---|
| UI strings, labels, messages | slang / gen-l10n translation files |
| Plurals (`1 item` / `3 items`) | ICU plural rules in translation files |
| Gender (`Mr.` / `Ms.`) | ICU select rules in translation files |
| Dates (`Jan 15` / `15 ene`) | `intl.DateFormat` |
| Numbers (`1,234.56` / `1.234,56`) | `intl.NumberFormat` |
| Currencies (`$9.99` / `€9,99`) | `intl.NumberFormat.currency` |
| Text direction (LTR / RTL) | `Directionality` + `start/end` insets |
| App name | Platform-specific (AndroidManifest, Info.plist) |

---

## Key Naming Convention

```
✅ snake_case, hierarchical, feature-scoped
  auth.login.title
  auth.login.submit_button
  product.detail.add_to_cart
  common.error.network
  common.action.cancel

❌ Flat, ambiguous, or camelCase
  loginTitle
  error
  btn1
  submitButton
```

---

## RTL Support Rules

```dart
// ✅ Use directional-aware properties — adapt automatically to RTL
Padding(padding: const EdgeInsetsDirectional.only(start: 16))
Row(children: [...])                    // reverses in RTL
Align(alignment: AlignmentDirectional.centerStart)

// ❌ Hardcoded direction — breaks RTL
Padding(padding: const EdgeInsets.only(left: 16))  // always left
Align(alignment: Alignment.centerLeft)
```

RTL languages: Arabic (`ar`), Hebrew (`he`), Persian (`fa`), Urdu (`ur`).

---

## Locale Persistence Pattern

```dart
// Store user preference → restore on next launch
@riverpod
class LocaleNotifier extends _$LocaleNotifier {
  @override
  Locale build() {
    _loadSaved();
    return const Locale('en'); // default until loaded
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.toLanguageTag());
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString('locale');
    if (tag != null) state = Locale.fromSubtags(languageCode: tag.split('-').first);
  }
}
```

---

## Quick Wins Checklist

- [ ] All user-visible strings in translation files — zero hardcoded strings in widgets
- [ ] Plurals use ICU rules — not `count == 1 ? 'item' : 'items'`
- [ ] Dates formatted with `intl.DateFormat` — not `DateTime.toString()`
- [ ] Currencies formatted with `intl.NumberFormat.currency`
- [ ] `EdgeInsetsDirectional.only(start:)` used instead of `EdgeInsets.only(left:)`
- [ ] Fallback locale configured — app never crashes on missing translation
- [ ] `supportedLocales` matches available translation files exactly
- [ ] Locale preference persisted to `SharedPreferences`
- [ ] Missing translation detection in CI (`dart run slang analyze`)
- [ ] Translation files reviewed by native speakers before release

## Reference Files

- `references/translations.md` — gen-l10n setup (default), ARB files, ICU plurals/gender, dynamic switching, CI; slang as alternative
- `references/formatting.md` — date, number, currency, time formatting with intl; locale-aware patterns
- `references/rtl_advanced.md` — RTL layout, bidirectional text, locale-specific assets, platform app name, advanced patterns
