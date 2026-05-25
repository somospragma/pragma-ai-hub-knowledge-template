# SentryHandler — Sentry

`handlers/sentry_handler.dart`

## Dependencies

**REQUIRED before adding any package:**

1. Check pub.dev for the latest stable version:
   - [`sentry_flutter`](https://pub.dev/packages/sentry_flutter)

2. Install — *the user must run these commands manually (do NOT auto-run):*

```bash
flutter pub add sentry_flutter
```

> The DSN is obtained from **Sentry Dashboard → Project Settings → Client Keys**.

```dart
import 'package:sentry_flutter/sentry_flutter.dart';
import '../log_event.dart';
import '../log_handler.dart';

final class SentryHandler implements LogHandler {
  const SentryHandler({required this.dsn});
  final String dsn;

  @override
  String get name => 'sentry';

  @override
  Future<void> initialize() async {
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.tracesSampleRate = 1.0;       // adjust in prod (0.1–0.2)
        options.profilesSampleRate = 1.0;
        options.attachScreenshot = true;
        options.attachViewHierarchy = true;
        options.enableLogs = true;            // enables the new Sentry logs system
      },
    );
  }

  @override
  Future<void> log(LogEvent event) async {
    switch (event.category) {
      case LogCategory.error:
        await Sentry.captureException(
          event.error ?? event.message,
          stackTrace: event.stackTrace,
          withScope: (scope) {
            scope.level = _sentryLevel(event.level);
            scope.setContexts('log_context', event.context);
            scope.setTag('category', event.category.name);
          },
        );

      case LogCategory.navigation:
        // Navigation log using the new Sentry logs system
        Sentry.logger.info(
          'Navigation: ${event.context['from']} → ${event.context['to']}',
          attributes: {
            'from': SentryAttribute.string(event.context['from']?.toString() ?? ''),
            'to': SentryAttribute.string(event.context['to']?.toString() ?? ''),
          },
        );

      case LogCategory.performance:
        // Performance transaction
        final transaction = Sentry.startTransaction(
          event.message,
          'performance',
          bindToScope: true,
        );
        transaction.setData('duration_ms', event.context['duration_ms']);
        await transaction.finish();

      default:
        // Use the new logs system instead of manual breadcrumbs
        _logByLevel(event);
    }
  }

  @override
  Future<void> dispose() async => Sentry.close();

  void _logByLevel(LogEvent event) {
    final attributes = {
      for (final entry in event.context.entries)
        entry.key: SentryAttribute.string(entry.value.toString()),
    };

    switch (event.level) {
      case LogLevel.debug:
        Sentry.logger.debug(event.message, attributes: attributes);
      case LogLevel.info:
        Sentry.logger.info(event.message, attributes: attributes);
      case LogLevel.warning:
        Sentry.logger.warn(event.message, attributes: attributes);
      case LogLevel.error:
        Sentry.logger.error(event.message, attributes: attributes);
      case LogLevel.fatal:
        Sentry.logger.fatal(event.message, attributes: attributes);
    }
  }

  SentryLevel _sentryLevel(LogLevel level) => switch (level) {
    LogLevel.debug   => SentryLevel.debug,
    LogLevel.info    => SentryLevel.info,
    LogLevel.warning => SentryLevel.warning,
    LogLevel.error   => SentryLevel.error,
    LogLevel.fatal   => SentryLevel.fatal,
  };
}
```
