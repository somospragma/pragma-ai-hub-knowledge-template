# Memory Profiling & Leak Detection — Implementation Guide

See also: `flutter-rendering` skill for frame performance patterns.

## Overview

Dart is garbage-collected, but memory leaks still occur when objects hold references
that prevent the GC from collecting them. The most common causes are:

- Undisposed controllers (animation, text, scroll, focus)
- Uncancelled stream subscriptions
- BLoC instances not closed
- Timers not cancelled
- Unbounded image caches
- Isolates never killed
- `BuildContext` stored in long-lived objects

This guide covers detection with DevTools and `leak_tracker`, and the correct
disposal patterns to prevent leaks.

---

## 1. DevTools Memory Tab — Complete Workflow

### Launch in profile mode

```bash
# ❌ Debug mode adds extra allocations — not representative
flutter run

# ✅ Profile mode — AOT compiled, real memory behavior
flutter run --profile
```

### Heap snapshot workflow

```
Step 1: App reaches stable state (home screen loaded, data fetched)
         ↓
Step 2: DevTools → Memory tab → click GC (force garbage collection)
         ↓
Step 3: Click "Take Heap Snapshot" → Snapshot 1 (baseline)
         ↓
Step 4: Reproduce the suspected leak
         (navigate to screen → perform action → navigate back → repeat 3–5×)
         ↓
Step 5: Click GC again
         ↓
Step 6: Click "Take Heap Snapshot" → Snapshot 2
         ↓
Step 7: Select "Diff" mode → compare Snapshot 2 vs Snapshot 1
         ↓
Step 8: Sort by "Delta" column (descending)
         → Classes with positive delta = objects that grew = leak candidates
         ↓
Step 9: Click a suspicious class → expand "Retaining Path"
         → Follow the chain to find what is keeping the object alive
```

### Reading the retaining path

```
Example retaining path for a leaked _MyScreenState:

_MyScreenState
  ← _MyScreenState._eventSub          ← StreamSubscription not cancelled
    ← _BroadcastStream._listeners
      ← MyBloc._controller
        ← MyBloc
          ← BlocProvider._value
            ← (root)

Fix: cancel _eventSub in _MyScreenState.dispose()
```

### Allocation tracing

Use when you want to find WHERE objects are being allocated (not just that they exist):

1. DevTools → Memory → **Allocation Tracing** tab
2. Click **Start** recording
3. Perform the action that causes memory growth
4. Click **Stop**
5. Sort by **Total Instances** or **Total Size**
6. Click a class to see the call stack where it was allocated

### Memory chart interpretation

```
Steady growth with no drops after GC  → leak (objects not being collected)
Sawtooth pattern (grow → GC → drop)   → normal allocation/collection cycle
Sudden spike then stable              → one-time allocation (e.g., image decode)
Spike that never drops                → image cache or large object not released
```

---

## 2. leak_tracker — Automated Leak Detection in Tests

`leak_tracker` is the official Dart package that detects:
- **Not-disposed objects**: disposable objects that were never disposed
- **Not-GC'd objects**: objects that were disposed but still retained by a reference

```yaml
# pubspec.yaml
dev_dependencies:
  leak_tracker: ^10.0.0
  leak_tracker_flutter_testing: ^3.0.0
  flutter_test:
    sdk: flutter
```

### Enable globally for all widget tests

```dart
// test/flutter_test_config.dart
// This file is automatically picked up by flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.settings = LeakTesting.settings
      .withTrackedAll()  // track all disposable Flutter objects
      .withIgnored(      // ignore known false positives
        classes: {
          // Add classes that are intentionally long-lived
          'KeepAliveHandle': const LeakTrackingTestConfig.ignore(),
        },
      );
  await testMain();
}
```

### Test a specific widget for leaks

```dart
// test/features/product/presentation/product_screen_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:mocktail/mocktail.dart';

class MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

void main() {
  group('ProductScreen memory', () {
    testWidgets(
      'disposes all resources when removed from tree',
      (tester) async {
        final bloc = MockProductBloc();
        when(() => bloc.state).thenReturn(const ProductState.initial());
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());

        await tester.pumpWidget(
          BlocProvider<ProductBloc>.value(
            value: bloc,
            child: const MaterialApp(home: ProductScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Remove widget — triggers dispose chain
        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpAndSettle();

        // leak_tracker automatically fails the test if:
        // - Any AnimationController, TextEditingController, etc. was not disposed
        // - Any disposed object is still retained in memory
      },
    );

    testWidgets(
      'BLoC is closed when BlocProvider is removed',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider(
            create: (_) => ProductBloc(MockProductRepository()),
            child: const MaterialApp(home: ProductScreen()),
          ),
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        // ProductBloc.close() must have been called — leak_tracker verifies this
      },
    );
  });
}
```

### Programmatic leak checking

```dart
// For integration tests or manual verification
import 'package:leak_tracker/leak_tracker.dart';

void main() async {
  // Start tracking
  LeakTracking.start();

  // Run your app logic
  final bloc = MyBloc();
  bloc.add(const MyEvent());
  await Future.delayed(const Duration(seconds: 1));

  // Dispose
  await bloc.close();

  // Check for leaks
  final leaks = await LeakTracking.collectLeaks();
  if (leaks.isNotEmpty) {
    print('Leaks detected: ${leaks.length}');
    for (final leak in leaks.notDisposed) {
      print('Not disposed: ${leak.type} — ${leak.trackedClass}');
    }
    for (final leak in leaks.notGCed) {
      print('Not GCed: ${leak.type} — retaining path: ${leak.retainingPath}');
    }
  }

  LeakTracking.stop();
}
```

---

## 3. Disposal Patterns — Complete Reference

### StatefulWidget — full disposal

```dart
class FullyManagedScreen extends StatefulWidget {
  const FullyManagedScreen({super.key});

  @override
  State<FullyManagedScreen> createState() => _FullyManagedScreenState();
}

class _FullyManagedScreenState extends State<FullyManagedScreen>
    with SingleTickerProviderStateMixin {

  // Controllers
  late final AnimationController _animController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;
  late final ScrollController _scrollController;
  late final PageController _pageController;

  // Subscriptions
  StreamSubscription<ConnectivityResult>? _connectivitySub;
  StreamSubscription<AppLifecycleState>? _lifecycleSub;

  // Timers
  Timer? _debounceTimer;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _searchController = TextEditingController();
    _searchFocus = FocusNode();
    _scrollController = ScrollController();
    _pageController = PageController();

    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen(_onConnectivityChanged);

    _pollingTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshData(),
    );
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: 300),
      () => context.read<SearchBloc>().add(SearchEvent.search(query)),
    );
  }

  @override
  void dispose() {
    // Controllers — always dispose
    _animController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    _pageController.dispose();

    // Subscriptions — always cancel
    _connectivitySub?.cancel();
    _lifecycleSub?.cancel();

    // Timers — always cancel
    _debounceTimer?.cancel();
    _pollingTimer?.cancel();

    super.dispose(); // must be last
  }

  @override
  Widget build(BuildContext context) => /* ... */;
}
```

### BLoC — stream subscription management

```dart
@injectable
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final UserRepository _userRepository;
  final NotificationRepository _notificationRepository;

  StreamSubscription<User>? _userSub;
  StreamSubscription<List<Notification>>? _notificationSub;

  DashboardBloc(this._userRepository, this._notificationRepository)
      : super(const DashboardState.initial()) {
    on<StartWatchingEvent>(_onStartWatching);
    on<StopWatchingEvent>(_onStopWatching);
    on<UserUpdatedEvent>(_onUserUpdated);
    on<NotificationsUpdatedEvent>(_onNotificationsUpdated);
  }

  Future<void> _onStartWatching(
    StartWatchingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    // ✅ Cancel before re-subscribing — prevents duplicate listeners
    await _userSub?.cancel();
    await _notificationSub?.cancel();

    _userSub = _userRepository.watchCurrentUser().listen(
      (user) => add(DashboardEvent.userUpdated(user)),
    );

    _notificationSub = _notificationRepository.watchUnread().listen(
      (notifications) => add(DashboardEvent.notificationsUpdated(notifications)),
    );
  }

  Future<void> _onStopWatching(
    StopWatchingEvent event,
    Emitter<DashboardState> emit,
  ) async {
    await _userSub?.cancel();
    await _notificationSub?.cancel();
    _userSub = null;
    _notificationSub = null;
  }

  @override
  Future<void> close() async {
    // ✅ Always cancel all subscriptions in close()
    await _userSub?.cancel();
    await _notificationSub?.cancel();
    return super.close();
  }
}
```

### Avoiding context retention

```dart
// ❌ Context stored in a service — outlives the widget
@injectable
class NavigationService {
  BuildContext? _context; // ❌ NEVER store context

  void setContext(BuildContext context) {
    _context = context; // ❌
  }
}

// ✅ Use GoRouter directly — no context needed
@injectable
class NavigationService {
  final GoRouter _router;
  NavigationService(this._router);

  void goToProduct(String productId) => _router.go('/product/$productId');
}

// ✅ Or use a GlobalKey<NavigatorState>
final navigatorKey = GlobalKey<NavigatorState>();

// In MaterialApp:
MaterialApp(navigatorKey: navigatorKey)

// Navigate without context:
navigatorKey.currentState?.pushNamed('/product/$productId');
```

### Async operations and mounted check

```dart
class _ProductDetailState extends State<ProductDetail> {
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await widget.repository.fetchProduct(widget.productId);

    // ✅ Always check mounted after any async gap
    if (!mounted) return;

    setState(() => _product = data);
  }

  Future<void> _onShareTapped() async {
    final url = await generateShareUrl(_product);

    // ✅ Check mounted before using context after await
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Link copied: $url')),
    );
  }
}
```

---

## 4. Image Cache Management

```dart
// lib/core/config/image_cache_config.dart
class ImageCacheConfig {
  static void configure() {
    // ✅ Set limits before runApp — prevents unbounded growth
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 50 * 1024 * 1024  // 50MB max
      ..maximumSize = 100;                    // max 100 decoded images
  }
}

// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ImageCacheConfig.configure();
  await configureDependencies();
  runApp(const App());
}
```

```dart
// ✅ Evict specific images when navigating away from image-heavy screens
class _GalleryScreenState extends State<GalleryScreen> {
  @override
  void dispose() {
    // Evict all gallery images from cache — they won't be needed until next visit
    for (final url in widget.imageUrls) {
      imageCache.evict(NetworkImage(url));
    }
    super.dispose();
  }
}

// ✅ Decode at display size — reduces heap memory per image
Widget buildThumbnail(String url, double size, BuildContext context) {
  final pixelSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
  return Image.network(
    url,
    width: size,
    height: size,
    cacheWidth: pixelSize,
    cacheHeight: pixelSize,
    fit: BoxFit.cover,
  );
}
```

---

## 5. Isolate Lifecycle

```dart
// ✅ Prefer compute() for one-shot tasks — no lifecycle management needed
Future<List<ProcessedItem>> processItems(List<RawItem> items) async {
  return compute(_processItemsInIsolate, items);
}

List<ProcessedItem> _processItemsInIsolate(List<RawItem> items) {
  return items.map((item) => ProcessedItem.from(item)).toList();
}

// ✅ For long-running isolates — manage lifecycle explicitly
class IsolateManager {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;

  Future<void> start() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _isolateEntryPoint,
      _receivePort!.sendPort,
    );

    // Get the send port from the isolate
    _sendPort = await _receivePort!.first as SendPort;
  }

  Future<T> send<T>(dynamic message) async {
    final responsePort = ReceivePort();
    _sendPort?.send([message, responsePort.sendPort]);
    return await responsePort.first as T;
  }

  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
    _sendPort = null;
  }
}

// In a StatefulWidget:
class _HeavyProcessingState extends State<HeavyProcessing> {
  final _isolateManager = IsolateManager();

  @override
  void initState() {
    super.initState();
    _isolateManager.start();
  }

  @override
  void dispose() {
    _isolateManager.dispose(); // ✅ kills isolate
    super.dispose();
  }
}
```

---

## 6. Memory Monitoring in CI

```dart
// integration_test/memory_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('memory does not grow after repeated navigation', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    // Measure baseline
    final baseline = await tester.binding.defaultBinaryMessenger
        .handlePlatformMessage('flutter/memory', null, (_) {});

    // Navigate back and forth 10 times
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const Key('product_list_item_0')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // Force GC and check heap
    // Use DevTools Memory tab to verify no growth after this test
  });
}
```

```bash
# Run with DevTools connected to capture memory timeline
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/memory_test.dart \
  --profile
```

---

## 7. Common Leak Patterns — Quick Reference

### Pattern 1: addListener without removeListener

```dart
// ❌ Listener added but never removed
@override
void initState() {
  super.initState();
  widget.model.addListener(_onModelChanged); // ❌ never removed
}

// ✅ Always pair addListener with removeListener
@override
void initState() {
  super.initState();
  widget.model.addListener(_onModelChanged);
}

@override
void dispose() {
  widget.model.removeListener(_onModelChanged); // ✅
  super.dispose();
}
```

### Pattern 2: GlobalKey held in static state

```dart
// ❌ Static GlobalKey holds a reference to the widget tree
class MyApp extends StatelessWidget {
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey(); // ❌ static

  @override
  Widget build(BuildContext context) => Scaffold(key: scaffoldKey);
}

// ✅ Use a non-static key, or pass it through DI
final navigatorKey = GlobalKey<NavigatorState>(); // top-level, not static class member
```

### Pattern 3: BlocProvider inside build()

```dart
// ❌ New BLoC created on every rebuild — old one never closed
Widget build(BuildContext context) {
  return BlocProvider(          // ❌ inside build()
    create: (_) => MyBloc(),
    child: MyWidget(),
  );
}

// ✅ BlocProvider above the widget that needs it — created once
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(        // ✅ in the route/screen level
      create: (_) => GetIt.instance<MyBloc>(),
      child: const MyWidget(),
    );
  }
}
```

### Pattern 4: Future not awaited in dispose

```dart
// ❌ Async dispose — subscription cancel is fire-and-forget
@override
void dispose() {
  _subscription.cancel(); // returns Future — not awaited ⚠️
  super.dispose();
}

// ✅ For StreamSubscription, cancel() is safe to call without await in dispose()
// The subscription will be cancelled asynchronously — this is acceptable
// For BLoC.close(), flutter_bloc handles this correctly via BlocProvider

// ✅ If you need to await async cleanup, use a flag
bool _disposed = false;

@override
void dispose() {
  _disposed = true;
  _subscription?.cancel();
  super.dispose();
}
```

---

## 8. Memory Budget Reference

| Scenario | Target heap | Action if exceeded |
|---|---|---|
| App launch (home screen) | < 50MB | Audit DI singletons, static state |
| After loading a list screen | < 80MB | Check image cache, list item widgets |
| After navigating back | ≈ launch baseline | Leak — use DevTools diff |
| Image gallery (50 images) | < 150MB | Reduce `imageCache.maximumSizeBytes` |
| Peak usage | < 200MB | Profile with DevTools, reduce cache |

> iOS terminates apps that exceed ~200–300MB depending on device.
> Android is more lenient but will trigger GC pressure and jank above 200MB.
