# M7 — Poor Code Quality

This category covers code quality issues that can lead to security vulnerabilities.

---

## Check M7-A: Logging of sensitive information

**ID:** `M7-A-SENSITIVE-LOGGING`
**Objective:** Detect logs that expose tokens, passwords, or PII to the console or files.
**Scope:** `lib/**.dart`

**Method:** Lexical search
**Insecure patterns:**

```dart
// PATTERN 1: print() with sensitive data
print('User token: $authToken');           // ❌ DANGER
print('Password: $userPassword');          // ❌ DANGER
print('API Response: ${response.body}');   // ⚠️ May contain sensitive data

// PATTERN 2: debugPrint without conditional
debugPrint('Credit card: ${creditCard.number}');  // ❌ DANGER

// PATTERN 3: Logger at wrong level
logger.info('Auth token: $token');  // ❌ Token in logs

// PATTERN 4: Exception logging with sensitive data
try {
  await api.login(email, password);
} catch (e) {
  print('Login failed: $email, $password, $e');  // ❌❌ EXTREME DANGER
}
```

**Lexical search:**
```regex
(print|debugPrint|logger\.(info|debug|warning))\([^)]*\b(token|password|secret|api[_-]?key|ssn|credit|cvv|pin)\b
print.*response\.body
print.*stackTrace
catch.*print.*password
```

**Criteria:**
- ❌ **Fail:** Logs containing tokens, passwords, API keys, or PII
- ⚠️ **Warning:** Logging response bodies without sanitization
- ✅ **Pass:** Conditional logging with `kDebugMode` + sanitized data

**Severity:** `MEDIUM`
**Automation:** 🟢 High (85%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Conditional logging — debug only
import 'package:flutter/foundation.dart';

void logDebug(String message) {
  if (kDebugMode) print(message);
}

logDebug('User logged in: userId=${user.id}');  // ✅ Debug only, no PII
```

```dart
// ✅ SOLUTION 2: Secure logger with sanitization
class SecureLogger {
  static final _sensitivePatterns = [
    RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),  // Emails
    RegExp(r'\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b'),              // Credit cards
    RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),                                  // SSN
    RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*'),                        // Bearer tokens
    RegExp(r'AIza[0-9A-Za-z\-_]{35}'),                                 // Google API keys
  ];

  static String sanitize(String message) {
    var sanitized = message;
    for (final pattern in _sensitivePatterns) {
      sanitized = sanitized.replaceAll(pattern, '***REDACTED***');
    }
    return sanitized;
  }

  static void log(String message) {
    if (kDebugMode) print(sanitize(message));
  }

  static void logError(String message, [dynamic error, StackTrace? stackTrace]) {
    final sanitizedMessage = sanitize(message);
    if (kDebugMode) {
      print('ERROR: $sanitizedMessage');
      if (error != null) print('Details: ${sanitize(error.toString())}');
      if (stackTrace != null) print(stackTrace);
    }
    // ✅ Send to remote logging without sensitive data
    _sendToRemoteLogging(sanitizedMessage);
  }

  static void _sendToRemoteLogging(String message) {
    // Firebase Crashlytics, Sentry, etc.
  }
}
```

```dart
// ✅ SOLUTION 3: Dio interceptor with sanitization
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      print('→ ${options.method} ${options.uri}');
      print('  Headers: ${_sanitizeHeaders(options.headers)}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      print('← ${response.statusCode} ${response.requestOptions.uri}');
    }
    handler.next(response);
  }

  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final sanitized = Map<String, dynamic>.from(headers);
    const sensitiveHeaders = ['Authorization', 'Cookie', 'X-API-Key'];
    for (final h in sensitiveHeaders) {
      if (sanitized.containsKey(h)) sanitized[h] = '***REDACTED***';
    }
    return sanitized;
  }
}
```

```dart
// ✅ SOLUTION 4: Safe exception handling
Future<void> loginUser(String email, String password) async {
  try {
    await api.login(email, password);
  } catch (e, stackTrace) {
    // ❌ NEVER: print('Login failed: $email, $password, $e');
    // ✅ Log without PII
    SecureLogger.logError('Login failed', e, stackTrace);

    // ✅ Analytics without PII
    FirebaseAnalytics.instance.logEvent(
      name: 'login_failed',
      parameters: {'error_type': e.runtimeType.toString()},
    );
  }
}
```

---

## Check M7-B: Inadequate exception handling

**ID:** `M7-B-POOR-EXCEPTION-HANDLING`
**Objective:** Detect empty catch blocks or stack traces exposed to the user.
**Scope:** `lib/**.dart`

**Method:** Lexical search
**Insecure patterns:**

```dart
// PATTERN 1: Empty catch
try {
  await riskyOperation();
} catch (e) {
  // ❌ Silently ignored
}

// PATTERN 2: Stack trace shown to user
try {
  await processPayment();
} catch (e, stackTrace) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      content: Text('$e\n$stackTrace'),  // ❌❌ Exposes internals
    ),
  );
}

// PATTERN 3: Overly broad catch
try {
  await complexOperation();
} on Exception catch (e) {
  print('Something went wrong');  // ⚠️ Catches everything, hides bugs
}
```

**Lexical search:**
```regex
catch\s*\([^)]+\)\s*\{\s*\}
catch.*\n.*showDialog.*stackTrace
catch.*\n.*Text\(.*\$e
on\s+Exception\s+catch
```

**Criteria:**
- ❌ **Fail:** Empty catch blocks
- ❌ **Fail:** Stack traces shown to the user
- ⚠️ **Warning:** Generic catch without logging
- ✅ **Pass:** Specific exception handling + user-friendly messages

**Severity:** `MEDIUM`
**Automation:** 🟢 High (80%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Specific exception handling
Future<Either<Failure, User>> fetchUserProfile(String userId) async {
  try {
    final response = await _apiClient.get('/users/$userId');
    return Right(User.fromJson(response.data as Map<String, dynamic>));

  } on DioException catch (e) when (e.response?.statusCode == 401) {
    SecureLogger.logError('Unauthorized fetching user');
    return const Left(Failure.unauthorized());

  } on DioException catch (e) when (e.response?.statusCode == 403) {
    return const Left(Failure.forbidden(message: 'Access denied'));

  } on DioException catch (e) {
    SecureLogger.logError('Network error fetching user', e);
    return Left(Failure.network(message: e.message ?? 'Network error'));

  } catch (e, stackTrace) {
    SecureLogger.logError('Unexpected error fetching user', e, stackTrace);
    FirebaseCrashlytics.instance.recordError(e, stackTrace);
    return const Left(Failure.unknown());
  }
}
```

```dart
// ✅ SOLUTION 2: Custom domain exceptions
sealed class AppException implements Exception {
  const AppException(this.message, {this.code});
  final String message;
  final String? code;
}

final class NetworkException extends AppException {
  const NetworkException(super.message) : super(code: 'NETWORK_ERROR');
}

final class UnauthorizedException extends AppException {
  const UnauthorizedException() : super('Unauthorized', code: 'UNAUTHORIZED');
}

final class ForbiddenException extends AppException {
  const ForbiddenException(super.message) : super(code: 'FORBIDDEN');
}
```

```dart
// ✅ SOLUTION 3: Global error handler
void main() {
  FlutterError.onError = (details) {
    SecureLogger.logError('Flutter error', details.exception, details.stack);
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.recordError(
        details.exception,
        details.stack,
      );
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    SecureLogger.logError('Platform error', error, stack);
    return true;
  };

  runApp(const MyApp());
}
```

---

## M7 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M7-A | MEDIUM | 🟢 85% | Medium |
| M7-B | MEDIUM | 🟢 80% | Medium |

**Total checks:** 2 | **Critical:** 0 | **High:** 0 | **Medium:** 2 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
