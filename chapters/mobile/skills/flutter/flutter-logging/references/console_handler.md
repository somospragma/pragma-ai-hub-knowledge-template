# ConsoleHandler — Development

`handlers/console_handler.dart`

**Dependencies:** None (uses `flutter/foundation.dart` from the SDK).

```dart
import 'package:flutter/foundation.dart';
import '../log_event.dart';
import '../log_handler.dart';

/// Pretty-prints to the console. Active in dev only.
/// Formats events to be easy to read in the IDE.
final class ConsoleHandler implements LogHandler {
  @override
  String get name => 'console';

  @override
  Future<void> initialize() async {} // no setup needed

  @override
  Future<void> log(LogEvent event) async {
    if (!kDebugMode) return; // never in release, just in case
    final icon = _icon(event.level);
    final ctx = event.context.isEmpty ? '' : ' | ${event.context}';
    final err = event.error != null ? '\n  ↳ ${event.error}' : '';
    debugPrint('$icon [${event.category.name}] ${event.message}$ctx$err');
  }

  @override
  Future<void> dispose() async {}

  String _icon(LogLevel level) => switch (level) {
    LogLevel.debug   => '🔍',
    LogLevel.info    => 'ℹ️',
    LogLevel.warning => '⚠️',
    LogLevel.error   => '🔴',
    LogLevel.fatal   => '💀',
  };
}
```
