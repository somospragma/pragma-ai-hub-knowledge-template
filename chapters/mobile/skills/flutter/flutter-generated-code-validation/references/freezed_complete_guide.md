# Freezed Complete Guide — Version 3.2.5 (April 2026)

## Key Changes in Freezed 3.x

- **`freezed_annotation` 3.x** — major version bump; incompatible with 2.x. Update both packages together.
- **Classes must be `abstract`, `sealed`, or manually implement `_$MyClass`** — plain `class` will throw at generation time.
- **`sealed` is the preferred modifier for union types** — enables exhaustive `switch` without `default`.
- **`when()`/`map()` removed in 3.0, restored in a later 3.x patch** — available again, but Dart 3 `switch` expressions are the canonical approach.
- **Immutable collections by default** — `List`, `Map`, `Set` become `UnmodifiableListView`/`UnmodifiableMapView`/`UnmodifiableSetView`. Disable with `@Freezed(makeCollectionsUnmodifiable: false)`.
- **Mixed Mode** — Freezed now supports both factory-based and regular constructor syntax.
- **`MyClass._()` can accept parameters** — enables inheritance and non-constant default values.
- **`// dart format off` generated automatically** — no need to exclude generated files from CI format checks.
- **`@Freezed(toJson: false, fromJson: false)`** — explicitly disable JSON generation per class.

---

## Basic Immutable Class

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'user.freezed.dart';
part 'user.g.dart'; // only when using fromJson

@freezed
abstract class User with _$User {
  const factory User({
    required String id,
    required String email,
    required String name,
    @Default(UserRole.viewer) UserRole role,
    @Default([]) List<String> tags, // ← immutable by default in Freezed 3.x
    String? avatarUrl,
    DateTime? lastLoginAt,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

enum UserRole { admin, editor, viewer }
```

---

## Custom Methods (const factory._() pattern)

```dart
@freezed
abstract class User with _$User {
  const User._(); // ← REQUIRED for custom methods

  const factory User({
    required String id,
    required String firstName,
    required String lastName,
    required String email,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  // Custom getters
  String get fullName => '$firstName $lastName';
  String get initials => '${firstName[0]}${lastName[0]}'.toUpperCase();
  bool get hasValidEmail =>
      RegExp(r'^[\w.]+@[\w.]+\.\w{2,}$').hasMatch(email);
}
```

---

## Union Types (Sealed / ADT Pattern)

Ideal for: States, Failures, Events — where cases are mutually exclusive.

```dart
// lib/features/auth/presentation/bloc/auth_state.dart
part 'auth_state.freezed.dart';

@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.initial() = _Initial;
  const factory AuthState.loading() = _Loading;
  const factory AuthState.authenticated({required User user}) = _Authenticated;
  const factory AuthState.unauthenticated() = _Unauthenticated;
  const factory AuthState.error({
    required String message,
    required String code,
  }) = _Error;
}
```

```dart
// ✅ Preferred: exhaustive Dart 3 switch expression
final screen = switch (state) {
  AuthState.initial()                    => const SplashScreen(),
  AuthState.loading()                    => const LoadingScreen(),
  AuthState.authenticated(:final user)   => HomeScreen(user: user),
  AuthState.unauthenticated()            => const LoginScreen(),
  AuthState.error(:final message)        => ErrorScreen(message: message),
};

// Also available: when() / map() (restored in Freezed 3.x patch)
state.when(
  initial: () => const SplashScreen(),
  loading: () => const LoadingScreen(),
  authenticated: (user) => HomeScreen(user: user),
  unauthenticated: () => const LoginScreen(),
  error: (message, code) => ErrorScreen(message: message),
);

// Partial match
final user = state.mapOrNull(authenticated: (s) => s.user);
```

---

## Failure Type (shared core)

```dart
// lib/core/error/failure.dart
part 'failure.freezed.dart';

@freezed
sealed class Failure with _$Failure {
  const factory Failure.network({
    required String message,
    int? statusCode,
  }) = NetworkFailure;

  const factory Failure.server({
    required String message,
    required String code,
  }) = ServerFailure;

  const factory Failure.cache({required String message}) = CacheFailure;

  const factory Failure.validation({
    required String message,
    required String field,
  }) = ValidationFailure;

  const factory Failure.unknown({
    required String message,
    Object? originalError,
  }) = UnknownFailure;
}

// Usage with Dart 3 switch
String toUserMessage(Failure failure) => switch (failure) {
  NetworkFailure(statusCode: 401) => 'Session expired. Please log in again.',
  NetworkFailure(statusCode: 403) => 'Access denied.',
  NetworkFailure(statusCode: 404) => 'Resource not found.',
  NetworkFailure(:final message)  => message,
  ServerFailure(:final message)   => message,
  ValidationFailure(:final field, :final message) => '$field: $message',
  _                               => 'An unexpected error occurred.',
};
```

---

## DTO with JSON Serialization

```dart
part 'user_dto.freezed.dart';
part 'user_dto.g.dart';

@freezed
abstract class UserDto with _$UserDto {
  const factory UserDto({
    @JsonKey(name: 'user_id') required String id,
    required String email,
    required String name,
    @JsonKey(name: 'user_role') @Default('viewer') String role,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'last_login_at') String? lastLoginAt,
    @JsonKey(name: 'address') AddressDto? address,
    @JsonKey(name: 'tags') @Default([]) List<String> tags,
  }) = _UserDto;

  factory UserDto.fromJson(Map<String, dynamic> json) => _$UserDtoFromJson(json);
}
```

---

## Mixed Mode (Freezed 3.x)

Freezed 3.x supports regular constructors alongside factory constructors.
Useful for inheritance and non-constant default values.

```dart
// Non-constant default values via ._() with parameters
@freezed
sealed class Response<T> with _$Response<T> {
  // ._() can now accept parameters
  Response._({DateTime? time}) : time = time ?? DateTime.now();

  factory Response.data(T value, {DateTime? time}) = ResponseData;
  // Optional ._() parameters don't need to be repeated in every factory
  factory Response.error(Object error) = ResponseError;

  @override
  final DateTime time;
}
```

```dart
// Inheritance via ._() with super()
class Base {
  Base(String value);
}

@freezed
abstract class MyClass extends Base with _$MyClass {
  MyClass._(super.value) : super();

  factory MyClass(int value) = _MyClass;
}
```

---

## Ejecting Union Cases

Point a union factory to a manually written class — Freezed won't generate it:

```dart
@freezed
sealed class Result<T> with _$Result {
  Result._();
  factory Result.data(T data) = ResultData;       // Freezed generates this
  factory Result.error(Object error) = ResultError; // We wrote this manually
}

// Manually written — can also be a @freezed class
class ResultError<T> extends Result<T> {
  ResultError(this.error) : super._();
  final Object error;
}
```

---

## Generic Classes

```dart
@freezed
abstract class ApiResponse<T> with _$ApiResponse<T> {
  const factory ApiResponse({
    @JsonKey(name: 'status_code') required int statusCode,
    required String message,
    T? data,
    @JsonKey(name: 'error_code') String? errorCode,
  }) = _ApiResponse<T>;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$ApiResponseFromJson(json, fromJsonT);
}

// Usage
final response = ApiResponse<UserDto>.fromJson(
  json,
  (obj) => UserDto.fromJson(obj as Map<String, dynamic>),
);
```

---

## copyWith

```dart
final original = User(id: '1', firstName: 'Alice', lastName: 'Smith', email: 'a@b.com');

// Freezed generates copyWith automatically:
final updated = original.copyWith(firstName: 'Bob');

// Nullable fields:
final noAvatar = original.copyWith(avatarUrl: null); // ✅ works with Freezed
```

---

## Generation Control with @Freezed

```dart
// Disable JSON for a specific class
@Freezed(toJson: false, fromJson: false)
abstract class DomainEntity with _$DomainEntity {
  const factory DomainEntity({required String id}) = _DomainEntity;
}

// Allow mutable collections (override Freezed 3.x default)
@Freezed(makeCollectionsUnmodifiable: false)
abstract class MutableData with _$MutableData {
  const factory MutableData({required List<String> items}) = _MutableData;
}

// Disable copyWith
@Freezed(copyWith: false)
abstract class Immutable with _$Immutable {
  const factory Immutable({required String value}) = _Immutable;
}
```

---

## build.yaml — json_serializable 6.13.1 configuration

```yaml
# build.yaml (project root)
targets:
  $default:
    builders:
      json_serializable:
        options:
          disallow_unrecognized_keys: false  # Don't fail on extra JSON fields
          explicit_to_json: true             # Serialize nested objects
          create_factory: true
          create_to_json: true
      freezed:
        options:
          make_collections_unmodifiable: true  # Default in Freezed 3.x
```
