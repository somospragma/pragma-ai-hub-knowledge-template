# Mutex / Lock — synchronized Package

Prevents concurrent access to async critical sections within a single isolate.
The most common use case: token refresh, database writes, file operations.

```yaml
dependencies:
  synchronized: ^3.3.0
```

---

## Basic Lock

```dart
import 'package:synchronized/synchronized.dart';

// ✅ Lock instance must be SHARED — create as a field or singleton
// ❌ Never create Lock() inside the method — each call gets its own lock
class TokenRepository {
  final _lock = Lock(); // shared instance

  Future<String> getValidToken() async {
    return _lock.synchronized(() async {
      // Only one caller runs this block at a time
      // Others wait in queue until the current one finishes
      final token = await _storage.read('access_token');
      if (_isExpired(token)) {
        return await _refreshToken();
      }
      return token!;
    });
  }
}
```

---

## Token Refresh — The Classic Race Condition

Without a lock, multiple 401 responses trigger multiple simultaneous refresh calls,
each overwriting the token and invalidating the others.

```dart
// lib/core/network/auth_interceptor.dart
import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class AuthInterceptor extends Interceptor {
  final TokenRepository _tokenRepo;
  final Lock _refreshLock = Lock();

  AuthInterceptor(this._tokenRepo);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    try {
      // ✅ Lock ensures only ONE refresh happens even if multiple requests fail with 401
      // All other callers wait here until the first refresh completes
      final newToken = await _refreshLock.synchronized(() async {
        // Check if token was already refreshed by a previous waiter
        final current = await _tokenRepo.getAccessToken();
        final requestToken = err.requestOptions.headers['Authorization']
            ?.toString()
            .replaceFirst('Bearer ', '');

        if (current != null && current != requestToken) {
          // Token was already refreshed — use the new one
          return current;
        }

        // Perform the actual refresh
        return await _tokenRepo.refreshToken();
      });

      // Retry the original request with the new token
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $newToken';
      final response = await Dio().fetch(options);
      handler.resolve(response);
    } catch (e) {
      handler.next(err);
    }
  }
}
```

---

## Reentrant Lock

A reentrant lock can be acquired multiple times from the same Zone without deadlocking.
Use when a synchronized method calls another synchronized method on the same lock.

```dart
class DatabaseService {
  final _lock = Lock(reentrant: true);

  Future<void> saveOrder(Order order) async {
    await _lock.synchronized(() async {
      await _saveOrderItems(order.items); // calls another synchronized method
      await _updateInventory(order.items);
    });
  }

  Future<void> _saveOrderItems(List<OrderItem> items) async {
    // ✅ Reentrant — won't deadlock even though saveOrder already holds the lock
    await _lock.synchronized(() async {
      for (final item in items) {
        await _db.insert('order_items', item.toMap());
      }
    });
  }
}
```

---

## MultiLock — Acquire Multiple Locks Atomically

```dart
import 'package:synchronized/synchronized.dart';

class TransferService {
  final _accountLocks = <String, Lock>{};

  Lock _lockFor(String accountId) =>
      _accountLocks.putIfAbsent(accountId, Lock.new);

  Future<void> transfer({
    required String fromId,
    required String toId,
    required double amount,
  }) async {
    // ✅ MultiLock acquires both locks atomically — prevents deadlock
    // (always acquires in the same order regardless of call order)
    final multiLock = MultiLock(locks: [_lockFor(fromId), _lockFor(toId)]);

    await multiLock.synchronized(() async {
      final from = await _accountRepo.get(fromId);
      final to = await _accountRepo.get(toId);

      if (from.balance < amount) throw InsufficientFundsException();

      await _accountRepo.update(from.copyWith(balance: from.balance - amount));
      await _accountRepo.update(to.copyWith(balance: to.balance + amount));
    });
  }
}
```

---

## Semaphore — Limit Concurrent Operations

A semaphore allows up to N concurrent operations. Useful for rate-limiting
parallel API calls or controlling resource access.

```dart
// lib/core/concurrency/semaphore.dart
// Pure Dart — no external package needed
class Semaphore {
  final int maxCount;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_current < maxCount) {
      _current++;
      return;
    }
    // Wait until a slot is available
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      next.complete();
    } else {
      _current--;
    }
  }

  Future<T> run<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}

// Usage — max 3 concurrent image uploads
final _uploadSemaphore = Semaphore(3);

Future<void> uploadImages(List<File> images) async {
  await Future.wait(
    images.map((image) => _uploadSemaphore.run(
      () => _uploadService.upload(image),
    )),
  );
}
```

---

## Lock with Timeout

```dart
// Fail fast if lock cannot be acquired within a duration
Future<void> tryWrite(Data data) async {
  try {
    await _lock.synchronized(
      () async => await _db.write(data),
      timeout: const Duration(seconds: 5),
    );
  } on TimeoutException {
    throw ConcurrencyException('Write timed out — resource busy');
  }
}
```

---

## Testing Lock Behavior

```dart
// test/core/concurrency/token_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  group('TokenRepository lock', () {
    test('refreshes token only once when called concurrently', () async {
      final mockStorage = MockSecureStorage();
      final mockApi = MockAuthApi();
      final repo = TokenRepository(mockStorage, mockApi);

      var refreshCount = 0;
      when(() => mockApi.refreshToken(any())).thenAnswer((_) async {
        refreshCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return 'new_token';
      });

      when(() => mockStorage.read('access_token'))
          .thenAnswer((_) async => 'expired_token');
      when(() => mockStorage.write(any(), any())).thenAnswer((_) async {});

      // Simulate 5 concurrent calls
      await Future.wait(List.generate(5, (_) => repo.getValidToken()));

      // ✅ Token was refreshed only once despite 5 concurrent calls
      expect(refreshCount, 1);
    });
  });
}
```
