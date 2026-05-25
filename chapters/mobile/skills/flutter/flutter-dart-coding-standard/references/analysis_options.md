# analysis_options.yaml — Complete Configuration

## Current Versions (April 2026)
- `flutter_lints: ^6.0.0` (includes `lints: ^6.0.0`)
- Dart SDK: `>=3.8.0`

## analysis_options.yaml

Copy the complete file from `assets/analysis_options.yaml` to the project root.

## Key Rules Explained

### `strict-casts`, `strict-inference`, `strict-raw-types`
The analyzer reports implicit casts, unresolved type inference, and generic types
without parameters as errors. Catches many bugs at compile time.

### `strict_top_level_inference` (new in flutter_lints 6.0)
Requires explicit type annotations on top-level declarations where the type
cannot be trivially inferred from the initializer. Prevents ambiguous public APIs.

### `avoid_dynamic_calls`
Prevents calling methods on `dynamic` variables without an explicit cast.
Forces explicit type handling.

### `cancel_subscriptions` / `close_sinks`
Ensures `StreamSubscription.cancel()` and `Sink.close()` are always called.
Critical for memory management in BLoC.

### `discarded_futures`
Prevents fire-and-forget async calls that can fail silently.

### `require_trailing_commas`
Enables better git diffs and consistency in auto-formatting.

### `no_default_cases`
Forces `switch` statements on sealed classes/enums to be exhaustive.
The compiler detects missing cases.

### `unnecessary_underscores` (new in flutter_lints 6.0)
Warns when `_` is used as a named parameter or variable name when it could
simply be omitted. Use `_` only for genuine wildcard discards.

### Removed in flutter_lints 5.0 (no longer enforced)
- `prefer_const_constructors`
- `prefer_const_declarations`
- `prefer_const_literals_to_create_immutables`

These were removed because they produced too many false positives. Still use
`const` where it genuinely improves performance, but the linter no longer
enforces it everywhere.

---

## Suppressing Rules (use sparingly)

```dart
// Per-line suppression
final dynamic result = jsonDecode(raw); // ignore: avoid_dynamic_calls

// Per-file suppression (always explain why)
// ignore_for_file: avoid_dynamic_calls
// Reason: This file processes arbitrary JSON from external APIs

// Exclude entire directories in analysis_options.yaml
analyzer:
  exclude:
    - "lib/generated/**"
```

---

## dart fix Commands

```bash
# Preview what can be auto-fixed
dart fix --dry-run

# Apply fixes
dart fix --apply

# Format code
dart format lib/ test/

# Analyze (strict mode for CI)
flutter analyze --fatal-infos

# Full CI check
dart format --output=none --set-exit-if-changed lib/ test/
flutter analyze --fatal-infos
```
