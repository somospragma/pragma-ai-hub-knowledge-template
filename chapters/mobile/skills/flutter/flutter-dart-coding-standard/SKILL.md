---
name: flutter-dart-coding-standard
description: >
  Applies and enforces the Dart/Flutter coding standard for all code generation and review. Use this skill when writing, reviewing, or refactoring any Dart/Flutter code. Triggers on file creation, PR reviews, naming questions ('how do I name X?'), 'is this correct Dart?', import ordering, style reviews, linting configuration, or any Flutter code generation task. Always active when producing Dart — defines naming, file structure, import order, style rules, and analysis_options.yaml. Stack: Dart 3.8+, Flutter 3.32+, flutter_lints.
commands:
  - enforce-coding-standard
inputs:
  - name: action
    description: Action to perform (audit, fix, configure). "audit" checks code against the full coding standard (naming, imports, types, async rules, class modifiers), "fix" applies auto-fixable corrections (dart fix, format, import ordering), "configure" generates or updates analysis_options.yaml with the standard lint rules.
    required: true
  - name: target
    description: Path to the file, directory, or project root to check (e.g. lib/ for full audit, lib/features/product/ for feature-specific, . for configure).
    required: true
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Flutter / Dart Coding Standard

The authoritative style guide for all project Dart code.
Every generated file must comply with these rules.

---

## Core Principles

1. **Dart style guide** — dart.dev/effective-dart
2. **Explicit over implicit** — always declare types on class members
3. **Immutability by default** — `final` everywhere, `const` where possible
4. **Single responsibility** — one public class per file, files ≤ 200 lines
5. **Dart 3.8 features** — use records, patterns, sealed classes, `switch` expressions, extension types, null-aware collection elements

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Files | `snake_case.dart` | `user_profile_bloc.dart` |
| Classes, Enums, Extensions | `PascalCase` | `UserProfileBloc`, `AuthStatus` |
| Variables, params, methods | `camelCase` | `userName`, `isLoading` |
| Private members | `_camelCase` | `_repository`, `_onLoad` |
| Constants (`const`) | `camelCase` | `const maxRetries = 3` |
| Enum values (Dart 3) | `camelCase` | `enum Status { loading, success }` |
| Typedefs | `PascalCase` | `typedef OnSuccess = void Function(String)` |
| Extensions | `PascalCase` on type | `extension StringX on String` |

### File Suffix Convention per Feature

```
presentation/pages/         → {feature}_page.dart
presentation/bloc/          → {feature}_bloc.dart, _event.dart, _state.dart
presentation/mappers/       → {entity}_ui_mapper.dart
presentation/widgets/       → {widget_name}_widget.dart
domain/entities/            → {entity}.dart
domain/repositories/        → {feature}_repository.dart   (interface)
domain/use_cases/           → {action}_{entity}_use_case.dart
data/repositories/          → {feature}_repository_impl.dart
data/data_sources/remote/   → {feature}_remote_data_source.dart + _impl.dart
data/data_sources/local/    → {feature}_local_data_source.dart + _impl.dart
data/models/                → {entity}_dto.dart
data/mappers/               → {entity}_mapper.dart
```

---

## Import Order

Always in this order, with a blank line between groups:

```dart
// 1. Dart SDK
import 'dart:async';
import 'dart:convert';

// 2. Flutter SDK
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 3. Third-party packages (alphabetical)
import 'package:bloc/bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:injectable/injectable.dart';

// 4. Project — core/shared inside the same package
import '../../../core/error/failure.dart';
import '../../../core/usecase/usecase.dart';

// 5. Project — feature/module inside the same package
import '../entities/user.dart';
import '../repositories/auth_repository.dart';
```

**Rule:** Product implementation code lives under `lib/src`. External packages
must import public barrels (`package:<package>/<package>.dart`) and must never
import another package's `src`. Within the same package, use the configured
project style; when reaching from outside `lib` (for example tests), use
`package:<package>/src/...` only for the same package.

---

## Types and Nullability

```dart
// ✅ Always declare return types
String get displayName => '$firstName $lastName';
Future<Either<Failure, User>> call(LoginParams params);

// ✅ Use final for immutable fields
final class LoginUseCase { ... }
final String _baseUrl;

// ✅ const where possible
const SizedBox(height: 16);
const EdgeInsets.symmetric(horizontal: 24);
const Duration(milliseconds: 300);

// ✅ Dart 3 switch expression
String describeFailure(Failure failure) => switch (failure) {
  NetworkFailure(:final message, :final statusCode) =>
    'Network ${statusCode ?? ''}: $message',
  ServerFailure(:final message, :final code) =>
    'Server $code: $message',
  CacheFailure(:final message) => 'Cache: $message',
  ValidationFailure(:final field, :final message) =>
    'Validation: $field — $message',
  UnknownFailure(:final message) => 'Unknown: $message',
};

// ✅ Records for simple groupings
(String name, int age) getUserInfo() => ('Alice', 30);
final (name, age) = getUserInfo();

// ✅ Null-aware collection elements (Dart 3.8+)
// ?value skips the element if it is null — no if-null boilerplate
String? subtitle;
final items = [
  'Title',
  ?subtitle,       // omitted if null
  'Footer',
];

Map<String, String> buildHeaders({String? authToken}) => {
  'Content-Type': 'application/json',
  ?'Authorization': authToken != null ? 'Bearer $authToken' : null,
  // ↑ entry omitted entirely when authToken is null
};

// ❌ Never var on class members
var name = 'Juan'; // forbidden on fields
// ❌ Never dynamic without justification
Future fetchData(); // forbidden — use Future<T>
```

---

## Methods and Functions

```dart
// ✅ Expression body for single-statement methods
String get fullName => '$firstName $lastName';
Widget _buildTitle() => Text(title, style: styles.h1);
bool isValid(String s) => s.isNotEmpty && s.length >= 3;

// ✅ Block body for 2+ statements
Future<void> _loadData() async {
  emit(const State.loading());
  final result = await _useCase(params);
  result.fold(_handleError, _handleSuccess);
}

// ✅ Named parameters for 2+ params
void doSomething({
  required String id,
  required String name,
  bool isActive = true,
});

// ✅ Trailing commas on multi-line arguments (enables dartfmt)
Text(
  'Hello',
  style: const TextStyle(fontSize: 16),
  textAlign: TextAlign.center,
)
```

---

## Async Rules

```dart
// ✅ Always await — never fire-and-forget in business logic
await _repository.saveUser(user);

// ✅ Always cancel StreamSubscriptions
late final StreamSubscription<AuthState> _authSub;

@override
Future<void> close() {
  _authSub.cancel();
  return super.close();
}

// ✅ Typed Futures and Streams — never Future<dynamic>
Future<Either<Failure, User>> getUser(String id);
Stream<Either<Failure, List<Message>>> watchMessages(String chatId);

// ✅ Use Either — never throw in domain/data layers
Future<Either<Failure, User>> call(params) async {
  try {
    return Right(await _repository.getUser(params.id));
  } on DioException catch (e) {
    return Left(Failure.network(message: e.message ?? 'Network error'));
  }
}
```

---

## Dart 3 Class Modifiers

```dart
// sealed — exhaustive pattern matching (states, failures)
sealed class AuthState { ... }  // or @freezed sealed class

// final — prevents extension and implementation
final class AppConfig {
  const AppConfig._();
  static const baseUrl = String.fromEnvironment('API_BASE_URL');
}

// abstract interface — contracts (preferred over plain abstract class)
abstract interface class AuthRepository {
  Future<Either<Failure, User>> signIn(SignInParams params);
}

// extension type — zero-cost type-safe wrappers (Dart 3.3+)
extension type UserId(String value) implements String {
  factory UserId.generate() => UserId(const Uuid().v4());
  bool get isValid => value.isNotEmpty;
}
```

---

## strict_top_level_inference (flutter_lints 6.x)

New in flutter_lints 6.0 / Dart 3.8. Requires explicit type annotations on
top-level declarations where the type cannot be trivially inferred.

```dart
// ❌ Triggers strict_top_level_inference
final logger = Logger(); // type not obvious from context

// ✅ Explicit type
final Logger logger = Logger();

// ✅ Also fine — type is trivially inferred from literal
const maxRetries = 3;
const baseUrl = 'https://api.example.com';
```

---

## unnecessary_underscores (flutter_lints 6.x)

New in flutter_lints 6.0. Warns when a named parameter or variable uses `_`
as a name when it could simply be omitted.

```dart
// ❌ Triggers unnecessary_underscores
list.forEach((_) => count++);

// ✅ Omit the unused parameter
list.forEach((_) => count++); // use wildcard _ only when needed for disambiguation

// ✅ Correct use of wildcard — discarding one of multiple values
final (name, _) = getUserInfo();
```

---

## Reference Files

- `references/analysis_options.md` — Complete `analysis_options.yaml` with all lint rules explained
- `references/dart3_patterns.md` — Records, patterns, sealed classes, switch expressions, null-aware elements
- `assets/analysis_options.yaml` — Ready-to-copy template for the project
- `scripts/lint_fix.sh` — Script to apply dart fix + format automatically
