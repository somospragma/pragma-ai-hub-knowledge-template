---
name: flutter-api-rest-connection
description: >
  Configures and implements REST API connections in Flutter using Dio: base client setup, interceptors (auth, logging, retry, error mapping), token refresh with mutex lock, multipart file upload, request cancellation, environment-based base URLs, and clean architecture integration (DataSource → Repository). Use this skill when setting up HTTP communication with a backend, adding auth headers, handling 401 token refresh, implementing retry logic, uploading files, or mapping HTTP errors to domain Failures.
commands:
  - setup-api-client
inputs:
  - name: action
    description: Action to perform (implement, add-interceptor, audit). "implement" generates the full Dio client setup (ApiClient, DI module, base interceptors), "add-interceptor" adds a specific interceptor to an existing client, "audit" checks for missing auth headers, no retry logic, hardcoded URLs, or error mapping gaps.
    required: true
  - name: target
    description: Path to the core/network directory or project root (e.g. lib/core/network/ for implement, lib/ for audit).
    required: true
  - name: interceptor
    description: Specific interceptor to add (auth, retry, error-mapping, logging, cache). Required when action is "add-interceptor".
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# REST API Connection

See the reference files for complete patterns and code examples.

**The HTTP layer lives entirely in the Data layer. Domain never knows about Dio, HTTP status codes, or JSON.**

## Package Status (April 2026)

```yaml
dependencies:
  dio: ^5.9.2
  pretty_dio_logger: ^1.4.0   # structured request/response logging
  get_it: ^9.2.1
  injectable: ^3.0.0
  fpdart: ^1.2.0

dev_dependencies:
  injectable_generator: ^3.0.2
  build_runner: ^2.14.1
  mocktail: ^1.0.5
```

---

## Architecture — Where HTTP Lives

```
Presentation (BLoC)
  ↓ calls
Domain (UseCase → Repository interface)
  ↓ calls
Data (RepositoryImpl)
  └── RemoteDataSource          ← calls ApiClient
        └── ApiClient (Dio)     ← HTTP, interceptors, error mapping
```

**Rules:**
- `ApiClient` and `Dio` are **Data layer only** — never imported in Domain or Presentation
- `RemoteDataSource` returns `DataModel` — never `DomainModel`
- `RepositoryImpl` maps `DioException` → `Failure` — never throws
- `Domain` only sees `Either<Failure, T>` — never HTTP details

---

## Interceptor Stack (execution order)

```
Request  →  AuthInterceptor → LoggingInterceptor → [server]
Response ←  LoggingInterceptor ← ErrorInterceptor ← RetryInterceptor ← [server]
```

| Interceptor | Responsibility |
|---|---|
| `AuthInterceptor` | Adds `Authorization: Bearer <token>` to every request; handles 401 → token refresh |
| `RetryInterceptor` | Retries on network timeout (max 3 attempts, exponential backoff) |
| `ErrorInterceptor` | Maps `DioException` → `AppException` for consistent error handling |
| `LoggingInterceptor` | Logs requests/responses in debug builds only |

---

## Quick Reference

### Dio client setup
```dart
Dio(BaseOptions(
  baseUrl: Env.apiBaseUrl,
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 30),
  headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
))
..interceptors.addAll([authInterceptor, retryInterceptor, errorInterceptor, logger]);
```

### Authenticated request
```dart
// AuthInterceptor adds the token automatically — no manual header needed
final response = await _client.get('/products');
```

### Cancel a request
```dart
final token = CancelToken();
await _client.get('/search', cancelToken: token);
token.cancel(); // call from dispose() or BLoC close()
```

### Multipart upload
```dart
final formData = FormData.fromMap({
  'file': await MultipartFile.fromFile(file.path, filename: 'photo.jpg'),
  'description': 'Product photo',
});
await _client.post('/upload', data: formData);
```

---

## Quick Wins Checklist

- [ ] `Dio` registered as `@lazySingleton` — one instance per app
- [ ] `AuthInterceptor` adds `Bearer` token to every request automatically
- [ ] 401 → token refresh uses `Lock` (synchronized) — no concurrent refresh race
- [ ] `RetryInterceptor` handles transient network failures
- [ ] `ErrorInterceptor` maps all `DioException` types to `AppException`
- [ ] `RepositoryImpl` maps `AppException` → `Failure` — never throws
- [ ] `CancelToken` used in BLoC — cancelled in `close()`
- [ ] `LoggingInterceptor` disabled in release builds (`kReleaseMode`)
- [ ] Base URL comes from flavor config (`flutter-environments` skill) or `--dart-define` — never hardcoded
- [ ] Timeouts configured: `connectTimeout` 10s, `receiveTimeout` 30s

## Reference Files

- `references/dio_setup.md` — Dio client, DI module, environment base URL (flavors + dart-define), ApiClient interface
- `references/interceptors.md` — AuthInterceptor (with token refresh + mutex), RetryInterceptor, ErrorInterceptor, LoggingInterceptor
- `references/data_source.md` — RemoteDataSource patterns, RepositoryImpl error mapping, multipart upload, request cancellation
- `references/testing.md` — mocking Dio with Mocktail, testing interceptors, testing DataSource and Repository

> **Related skills:** `flutter-environments` (flavor/scheme setup, base URL per environment),
> `flutter-caching-strategy` (HTTP cache layer on top of Dio),
> `flutter-certificate-pinning` (HTTPS security),
> `flutter-offline-first-pattern` (local cache + sync strategy).
