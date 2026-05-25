# DataDogHandler — DataDog

`handlers/datadog_handler.dart`

## Dependencies

**REQUIRED before adding any package:**

1. Check pub.dev for the latest stable version:
   - [`datadog_flutter_plugin`](https://pub.dev/packages/datadog_flutter_plugin)

2. Install — *the user must run these commands manually (do NOT auto-run):*

```bash
flutter pub add datadog_flutter_plugin
```

> Requires `clientToken` and `applicationId` from **DataDog → UX Monitoring → Setup**.
> Adjust `DatadogSite` to your region (us1, eu1, etc.).

```dart
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import '../log_event.dart' as log_event;
import '../log_handler.dart';
import '../log_level.dart' as log_level;

final class DataDogHandler implements LogHandler {
  DataDogHandler({
    required this.clientToken,
    required this.applicationId,
    required this.env,
    this.site = DatadogSite.us1,
    this.serviceName = 'flutter_app',
  });

  final String clientToken;
  final String applicationId;
  final String env;
  final DatadogSite site;
  final String serviceName;

  late final DatadogLogger _logger;

  @override
  String get name => 'datadog';

  @override
  Future<void> initialize() async {
    final configuration = DatadogConfiguration(
      clientToken: clientToken,
      env: env,
      site: site,
      nativeCrashReportEnabled: true,
      loggingConfiguration: DatadogLoggingConfiguration(),
      rumConfiguration: DatadogRumConfiguration(
        applicationId: applicationId,
      ),
    );

    await DatadogSdk.instance.initialize(configuration, TrackingConsent.granted);

    _logger = DatadogSdk.instance.logs!.createLogger(
      DatadogLoggerConfiguration(
        name: serviceName,
        networkInfoEnabled: true,
        remoteLogThreshold: LogLevel.debug,
      ),
    );
  }

  @override
  Future<void> log(log_event.LogEvent event) async {
    final attrs = Map<String, Object?>.from(event.context)
      ..['category'] = event.category.name
      ..['timestamp'] = event.timestamp.toIso8601String();

    final message = event.message;

    switch (event.level) {
      case log_level.LogLevel.debug:
        _logger.debug(message, attributes: attrs);
      case log_level.LogLevel.info:
        _logger.info(message, attributes: attrs);
      case log_level.LogLevel.warning:
        _logger.warn(message, attributes: attrs);
      case log_level.LogLevel.error:
        _logger.error(
          message,
          errorMessage: event.error?.toString(),
          attributes: attrs,
        );
      case log_level.LogLevel.fatal:
        _logger.error(
          message,
          errorMessage: event.error?.toString(),
          errorKind: 'Fatal',
          attributes: attrs,
        );
    }

    // Performance metrics as RUM actions
    if (event.category == log_event.LogCategory.performance) {
      DatadogSdk.instance.rum?.addAction(
        RumActionType.custom,
        message,
        attrs,
      );
    }
  }

  @override
  Future<void> dispose() async {}
}
```

---

## Initialization in `main.dart`

DataDog offers two initialization approaches:

### Option 1: Using `DatadogSdk.runApp` (Recommended)

Automatically configures error handling:

```dart
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  final configuration = DatadogConfiguration(
    clientToken: '<CLIENT_TOKEN>',
    env: '<ENV_NAME>',
    site: DatadogSite.us1,
    nativeCrashReportEnabled: true,
    loggingConfiguration: DatadogLoggingConfiguration(),
    rumConfiguration: DatadogRumConfiguration(
      applicationId: '<RUM_APPLICATION_ID>',
    ),
  );

  await DatadogSdk.runApp(configuration, TrackingConsent.granted, () async {
    runApp(const MyApp());
  });
}
```

### Option 2: Manual initialization with custom error handling

Useful when you need custom logic before `runApp`:

```dart
import 'dart:ui';
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configuration = DatadogConfiguration(
    clientToken: '<CLIENT_TOKEN>',
    env: '<ENV_NAME>',
    site: DatadogSite.us1,
    nativeCrashReportEnabled: true,
    loggingConfiguration: DatadogLoggingConfiguration(),
    rumConfiguration: DatadogRumConfiguration(
      applicationId: '<RUM_APPLICATION_ID>',
    ),
  );

  // Capture Flutter framework errors
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    DatadogSdk.instance.rum?.handleFlutterError(details);
    originalOnError?.call(details);
  };

  // Capture unhandled async errors
  final platformOriginalOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (e, st) {
    DatadogSdk.instance.rum?.addErrorInfo(
      e.toString(),
      RumErrorSource.source,
      stackTrace: st,
    );
    return platformOriginalOnError?.call(e, st) ?? false;
  };

  await DatadogSdk.instance.initialize(configuration, TrackingConsent.granted);

  runApp(const MyApp());
}
```

---

## Sending Logs

After initializing DataDog with `DatadogLoggingConfiguration`, create a logger instance:

```dart
final logger = DatadogSdk.instance.logs?.createLogger(
  DatadogLoggerConfiguration(
    remoteLogThreshold: LogLevel.warning,
  ),
);

logger?.debug('A debug message.');
logger?.info('Some relevant information?');
logger?.warn('An important warning…');
logger?.error('An error was met!');
```

---

## Track RUM Views

DataDog can automatically track named routes using `DatadogNavigationObserver`:

```dart
MaterialApp(
  home: const HomeScreen(),
  navigatorObservers: [
    DatadogNavigationObserver(DatadogSdk.instance),
  ],
);
```

### Customize view names

```dart
RumViewInfo? infoExtractor(Route<dynamic> route) {
  final name = route.settings.name;
  if (name == 'my_named_route') {
    return RumViewInfo(
      name: 'MyDifferentName',
      attributes: {'extra_attribute': 'attribute_value'},
    );
  }
  return defaultViewInfoExtractor(route);
}

final observer = DatadogNavigationObserver(
  datadogSdk: DatadogSdk.instance,
  viewInfoExtractor: infoExtractor,
);
```

### Using `DatadogRouteAwareMixin`

For manual RUM view control:

```dart
class _MyHomeScreenState extends State<MyHomeScreen>
    with RouteAware, DatadogRouteAwareMixin {

  @override
  RumViewInfo get rumViewInfo => RumViewInfo(name: 'MyHomeScreen');
}
```

> With obfuscated code, the widget name is lost. Use `rumViewInfo` to maintain correct names.

---

## Automatic Resource Tracking

Enable automatic tracking of resources and HTTP calls:

```dart
final configuration = DatadogConfiguration(
  // ... other configuration
  firstPartyHosts: ['example.com'],
)..enableHttpTracking();
```

---

## Tracking from Background Isolates

```dart
import 'dart:isolate';
import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';

Future<void> spawnBackgroundIsolate() async {
  final receivePort = ReceivePort();
  await Isolate.spawn(_backgroundWork, receivePort.sendPort);
}

void _backgroundWork(SendPort port) async {
  // Attach DataDog to the background isolate
  await DatadogSdk.instance.attachToBackgroundIsolate();

  // Your background work here
  // Logs and RUM events will be sent correctly
}
```

> Calling `attachToBackgroundIsolate()` is required for DataDog to capture logs
> and events from secondary isolates.
