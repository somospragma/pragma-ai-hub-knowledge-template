---
name: flutter-generated-code-validation
description: >
  Validates, runs, and troubleshoots Flutter code generation: build_runner, Freezed, json_serializable, Injectable, AutoRoute. Use this skill when the user mentions build_runner, generated files (.g.dart, .freezed.dart, .gr.dart, .config.dart), 'run code generation', 'my generated code is broken', 'build failed', annotations such as @freezed, @injectable, @JsonSerializable, @AutoRouterConfig, or questions about configuring code generation. Apply BEFORE and AFTER modifying any annotated Dart class. Stack: build_runner, freezed, freezed_annotation, json_serializable, json_annotation, injectable, injectable_generator, auto_route, auto_route_generator.
commands:
  - validate-codegen
inputs:
  - name: action
    description: Action to perform (run, validate, troubleshoot). "run" executes build_runner with appropriate flags, "validate" checks generated files are up-to-date and correct, "troubleshoot" diagnoses and fixes common codegen errors (stale cache, missing parts, version mismatches).
    required: true
  - name: target
    description: Path to the project root, package, or specific file to run codegen on (e.g. . for full project, lib/features/product/ for scoped generation).
    required: true
  - name: generator
    description: Specific generator to focus on (freezed, json-serializable, injectable, auto-route, all). Defaults to all.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Flutter Code Generation — Validation and Troubleshooting

Full lifecycle: setup → generation → validation → troubleshooting.

---

## Package Versions (April 2026)

```yaml
dependencies:
  freezed_annotation: ^3.1.0
  json_annotation: ^4.11.0
  injectable: ^3.0.0
  auto_route: ^11.1.0

dev_dependencies:
  build_runner: ^2.15.0
  freezed: ^3.2.5
  json_serializable: ^6.13.1
  injectable_generator: ^3.0.2
  auto_route_generator: ^11.1.0
```

---

## Key Changes by Package

### Freezed 3.x (3.2.5)

- **`freezed_annotation` 3.x** — major version bump; incompatible with 2.x. Update both packages together.
- **`when()`/`map()` removed in 3.0, restored in a later 3.x patch** — they are available again, but Dart 3 `switch` expressions are the canonical and recommended approach.
- **Classes must be `abstract`, `sealed`, or manually implement `_$MyClass`** — plain `class` without one of these will throw at generation time.
- **`sealed` is the preferred modifier for union types** — enables exhaustive `switch` without `default`.
- **Immutable collections by default** — `List`, `Map`, `Set` in generated classes are `UnmodifiableListView`/`UnmodifiableMapView`/`UnmodifiableSetView`. Disable per class with `@Freezed(makeCollectionsUnmodifiable: false)`.
- **`MyClass._()` can now accept parameters** — enables inheritance and non-constant default values (see Mixed Mode below).
- **Mixed Mode** — Freezed now supports both factory-based and regular constructor syntax in the same class.
- **`// dart format off` generated automatically** — no need to exclude generated files from CI format checks.
- **`@Freezed(toJson: false, fromJson: false)`** — explicitly disable JSON generation per class.

### Injectable 3.0.0

- **Dart 3.8 minimum** — `environment.sdk: ">=3.8.0 <4.0.0"`.
- **`generateAccessors`** — new option on `@InjectableInit` to generate typed GetIt extension getters.
- **`generateForEnvironments`** — filter which environments trigger generation.
- **`@ignoreParam`** — ignore optional parameters in factory methods.
- **Cached factories** — support for `get_it 8.x` cached factory registration.
- **`get_it` constraint** — `>=8.3.0 <10.0.0`.

### auto_route 11.x

- Version bump from 10.x. `@RoutePage()` and `@AutoRouterConfig()` annotations unchanged.
- Ensure `auto_route` and `auto_route_generator` are both on `^11.1.0`.

### build_runner 2.15.0

- Improved incremental cache performance.
- `--build-filter` for targeted generation.

---

## Standard Commands

```bash
# One-time build (CI, initial setup)
dart run build_runner build --delete-conflicting-outputs

# Watch mode (local development — always use this)
dart run build_runner watch --delete-conflicting-outputs

# Clean cache + rebuild (when cache is stale or corrupt)
dart run build_runner clean && dart run build_runner build --delete-conflicting-outputs

# Build only specific generators
dart run build_runner build --build-filter="lib/src/features/product/**"
```

**Never** manually delete `.g.dart`, `.freezed.dart`, `.gr.dart`, or `.config.dart` —
let `--delete-conflicting-outputs` handle conflicts.

---

## Generator Map

| Annotation | Package | Output file | Triggered by |
|---|---|---|---|
| `@freezed` | freezed 3.2.5 | `.freezed.dart` | `part 'x.freezed.dart'` |
| `@JsonSerializable` | json_serializable 6.13.1 | `.g.dart` | `part 'x.g.dart'` |
| `@injectable`, `@lazySingleton` | injectable_generator 3.0.2 | `injection.config.dart` | All `@injectable` classes |
| `@AutoRouterConfig` | auto_route_generator 11.x | `.gr.dart` | `part 'router.gr.dart'` |

---

## Post-Generation Checklist

After every `build_runner build`, verify:

### 1. Zero build errors
```bash
dart run build_runner build --delete-conflicting-outputs 2>&1 | grep -E "^(ERROR|SEVERE|error:)"
# Expected: no output
```

### 2. Correct `part` directive order
```dart
// ✅ Correct — freezed MUST come before .g.dart
part 'user_dto.freezed.dart';
part 'user_dto.g.dart';

// ❌ Wrong order
part 'user_dto.g.dart';
part 'user_dto.freezed.dart';
```

### 3. Factory constructors present
```dart
// For @JsonSerializable on a @freezed class:
factory UserDto.fromJson(Map<String, dynamic> json) => _$UserDtoFromJson(json);
```

### 4. Injectable config updated
```bash
grep "ProductRepository\|ProductBloc" lib/src/core/di/injection.config.dart
# Must show the newly registered types
```

---

## Common Errors and Solutions

### `part of` not found / MissingRequiredAnnotationException
```dart
// Solution: add part directive after imports
import '...';

part 'user.freezed.dart'; // ← add this
// part 'user.g.dart';    // ← add this too if using @JsonSerializable

@freezed
sealed class User with _$User { ... }
```

### `_$UserFromJson is not defined`
```dart
// Solution: ensure the fromJson factory is present
@freezed
class UserDto with _$UserDto {
  const factory UserDto({required String id}) = _UserDto;

  // ← this must be present
  factory UserDto.fromJson(Map<String, dynamic> json) => _$UserDtoFromJson(json);
}
```

### `Already defined` errors / duplicate classes
```bash
# Solution: stale generated file in conflict
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Freezed — custom methods not working
```dart
// Solution: add const factory._() for custom getters
@freezed
class User with _$User {
  const User._(); // ← REQUIRED for custom methods

  const factory User({required String id, required String name}) = _User;

  // Now this works:
  String get initials => name.split(' ').map((w) => w[0]).join();
}
```

### Freezed 3.x — class must be abstract, sealed, or implement _$MyClass
```dart
// ❌ Freezed 3.x will throw at generation time
@freezed
class MyState with _$MyState {
  const factory MyState.initial() = _Initial;
}

// ✅ Use sealed for union types (enables exhaustive switch)
@freezed
sealed class MyState with _$MyState {
  const factory MyState.initial() = _Initial;
  const factory MyState.loading() = _Loading;
  const factory MyState.success(String data) = _Success;
}

// ✅ Or abstract for simple immutable classes
@freezed
abstract class UserDto with _$UserDto {
  const factory UserDto({required String id}) = _UserDto;
  factory UserDto.fromJson(Map<String, dynamic> json) => _$UserDtoFromJson(json);
}
```

### Freezed 3.x — `freezed_annotation` version mismatch
```bash
# Typical error:
# The argument type 'Freezed' can't be assigned to the parameter type 'Freezed'.
# Solution: ensure BOTH packages are on 3.x
dart pub upgrade freezed freezed_annotation
# Verify:
dart pub deps | grep freezed
# freezed 3.2.5 + freezed_annotation 3.1.0
```

### Freezed 3.x — Mixed Mode (non-factory constructor)
```dart
// Freezed 3.x supports regular constructors alongside factories.
// Useful for inheritance and non-constant default values.
@freezed
sealed class Response<T> with _$Response<T> {
  // ._() can now accept parameters — used for non-constant defaults
  Response._({DateTime? time}) : time = time ?? DateTime.now();

  factory Response.data(T value, {DateTime? time}) = ResponseData;
  factory Response.error(Object error) = ResponseError;

  @override
  final DateTime time;
}
```

### Injectable 3.x — `generateAccessors` for typed GetIt getters
```dart
// injection.dart
@InjectableInit(generateAccessors: true)
Future<GetIt> configureDependencies() => getIt.init();

// Generated: typed extension getters on GetIt
// Usage:
final repo = getIt.productRepository; // instead of getIt<ProductRepository>()
```

### AutoRoute 11.x — `@RoutePage()` not generating `.gr.dart`
```dart
// Ensure imports are from auto_route 11.x:
import 'package:auto_route/auto_route.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [...];
}
```

### build_runner slow / hanging
```bash
pkill -f build_runner
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

---

## `.gitignore` Policy

**Commit generated files** — CI does not run build_runner:

```gitignore
# Do NOT add these lines:
# *.g.dart
# *.freezed.dart
# *.gr.dart
# *.config.dart
```

---

## CI Configuration

```yaml
# .github/workflows/ci.yml
- name: Generate code
  run: dart run build_runner build --delete-conflicting-outputs

- name: Verify generated files are committed
  run: |
    git diff --exit-code -- "*.g.dart" "*.freezed.dart" "*.gr.dart" "*.config.dart" || \
    (echo "Generated files are out of date — run build_runner locally and commit" && exit 1)
```

---

## Reference Files

- `references/freezed_complete_guide.md` — All Freezed patterns: union types, JSON, custom methods, generics, Mixed Mode
- `scripts/run_codegen.sh` — Script to manage build_runner (watch/build/clean/verify)
