---
name: flutter-memory-profiling
description: >
  Profile and fix memory leaks in Flutter using DevTools Memory tab, heap snapshots, retaining paths, allocation tracing, and the leak_tracker package for automated detection in tests. Covers correct disposal patterns for controllers, streams, BLoC, images, and isolates. Use this skill when the app crashes with OOM, slows down over time, or when investigating retained objects, growing heap, or undisposed controllers.
commands:
  - profile-memory
inputs:
  - name: action
    description: Action to perform (diagnose, audit, fix). "diagnose" guides through DevTools heap snapshot workflow, "audit" checks code for common leak patterns (undisposed controllers, uncancelled subscriptions, stored context), "fix" applies disposal fixes to identified leaks.
    required: true
  - name: target
    description: Path to the widget, BLoC, or feature directory to analyze (e.g. lib/features/gallery/presentation/pages/gallery_page.dart or lib/features/chat/).
    required: true
  - name: issue
    description: Specific memory issue to focus on (leak, oom, growing-heap, undisposed-controller, image-cache). Helps narrow the diagnosis scope.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Memory Profiling & Leak Detection

**Rule #1: Profile in profile mode. Debug mode allocates extra objects and is not representative.**

## Quick Reference — Most Common Leak Sources

| Source | Symptom | Fix |
|---|---|---|
| `StreamSubscription` not cancelled | Heap grows on navigation | Cancel in `dispose()` or BLoC `close()` |
| `AnimationController` not disposed | Ticker keeps running | Dispose in `dispose()` |
| `TextEditingController` / `FocusNode` | Retained after widget removed | Dispose in `dispose()` |
| `BlocProvider` inside `build()` | New BLoC created on every rebuild | Move above widget tree |
| `Timer` not cancelled | Fires after widget is gone | Cancel in `dispose()` |
| Image cache unbounded | Memory grows on image-heavy screens | Set `PaintingBinding.instance.imageCache.maximumSizeBytes` |
| `Isolate` not killed | Background work never stops | Call `isolate.kill()` |
| Global singletons holding context | Context outlives widget | Never store `BuildContext` in long-lived objects |

---

## 1. Profile First — Setup

```bash
# ✅ Always use profile mode — debug adds extra allocations
flutter run --profile

# DevTools opens automatically or visit the URL printed in terminal
# Navigate to: Memory tab
```

```dart
// Enable MemoryAllocations — required for leak_tracker to track Flutter objects
void main() {
  // Enables Flutter framework object tracking (widgets, controllers, etc.)
  WidgetsBinding.instance; // ensures binding is initialized
  runApp(const App());
}
```

---

## 2. DevTools Memory Tab — Workflow

### Step 1: Establish a baseline
1. Open DevTools → **Memory** tab
2. Let the app reach a stable state (home screen loaded)
3. Click **GC** (force garbage collection)
4. Click **Take Heap Snapshot** → this is your baseline

### Step 2: Reproduce the suspected leak
- Navigate to the screen you suspect leaks
- Perform the action (scroll, load data, navigate away and back)
- Repeat 3–5 times to amplify the leak

### Step 3: Capture and compare
1. Click **GC** again
2. Click **Take Heap Snapshot**
3. Select **Diff** mode → compare snapshot 2 vs snapshot 1
4. Sort by **Delta** (positive = objects that grew) — these are leak candidates

### Step 4: Inspect retaining paths
- Click on a suspicious class (e.g., `_MyWidgetState`, `MyBloc`)
- Expand **Retaining Path** — shows the chain of references keeping it alive
- The root of the chain is the leak source

---

## 3. Automated Leak Detection — leak_tracker

`leak_tracker` is the official Dart package for detecting not-disposed and not-GC'd objects in tests.

```yaml
dev_dependencies:
  leak_tracker: ^10.0.0
  leak_tracker_flutter_testing: ^3.0.0
```

```dart
// test/widget_test.dart — enable leak tracking for all widget tests
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

void main() {
  // Enable leak tracking globally for all tests in this file
  LeakTesting.settings = LeakTesting.settings.withIgnoredAll();

  testWidgets('MyScreen disposes all resources', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MyScreen()));
    await tester.pumpAndSettle();

    // Navigate away — triggers dispose
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    // leak_tracker will fail the test if any disposable object was not disposed
    // or was disposed but not GC'd (retained reference)
  });
}
```

```dart
// For specific test cases — check for leaks explicitly
testWidgets('BLoC is closed when widget is removed', (tester) async {
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => MyBloc(),
      child: const MyWidget(),
    ),
  );

  // Remove widget — BlocProvider should close the BLoC
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();

  // If MyBloc.close() was not called, leak_tracker reports a leak
});
```

---

## 4. Correct Disposal Patterns

### StatefulWidget — dispose everything

```dart
class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  StreamSubscription<Event>? _eventSub;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _scrollController = ScrollController();

    // Subscribe to streams
    _eventSub = context.read<EventBloc>().stream.listen(_onEvent);
  }

  void _onEvent(EventState state) {
    // Handle event — safe because subscription is cancelled in dispose
  }

  @override
  void dispose() {
    _animController.dispose();   // ✅ stops ticker
    _textController.dispose();   // ✅ releases text buffer
    _focusNode.dispose();        // ✅ releases focus resources
    _scrollController.dispose(); // ✅ releases scroll position
    _eventSub?.cancel();         // ✅ stops stream listener
    _debounceTimer?.cancel();    // ✅ stops pending timer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => /* ... */;
}
```

### BLoC — cancel subscriptions in close()

```dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final ProductRepository _repository;
  StreamSubscription<List<Product>>? _productsSub;

  ProductBloc(this._repository) : super(const ProductState.initial()) {
    on<WatchProductsEvent>(_onWatchProducts);
    on<ProductsUpdatedEvent>(_onProductsUpdated);
  }

  Future<void> _onWatchProducts(
    WatchProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    // ✅ Cancel previous subscription before creating a new one
    await _productsSub?.cancel();

    _productsSub = _repository.watchProducts().listen(
      (products) => add(ProductsUpdatedEvent(products)),
      onError: (e) => add(ProductErrorEvent('$e')),
    );
  }

  void _onProductsUpdated(
    ProductsUpdatedEvent event,
    Emitter<ProductState> emit,
  ) {
    emit(ProductState.success(products: event.products));
  }

  @override
  Future<void> close() async {
    await _productsSub?.cancel(); // ✅ always cancel in close()
    return super.close();
  }
}
```

### Never store BuildContext in long-lived objects

```dart
// ❌ Context outlives the widget — crash or stale reference
class MyService {
  final BuildContext context; // ❌ NEVER do this
  MyService(this.context);
}

// ❌ Storing context in a BLoC
class MyBloc extends Bloc<MyEvent, MyState> {
  final BuildContext _context; // ❌
  MyBloc(this._context) : super(/* ... */);
}

// ✅ Pass data, not context — use callbacks or navigation service
class MyBloc extends Bloc<MyEvent, MyState> {
  final NavigationService _navigation; // ✅ injected service, not context
  MyBloc(this._navigation) : super(/* ... */);
}

// ✅ If you must use context in a widget callback, check mounted first
void _onTap() async {
  final result = await someAsyncOperation();
  if (!mounted) return; // ✅ guard before using context after async gap
  context.go('/result');
}
```

---

## 5. Image Cache Management

```dart
// ✅ Set memory cache limits — prevents unbounded growth on image-heavy screens
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Default is 100MB — reduce for memory-constrained devices
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB
  PaintingBinding.instance.imageCache.maximumSize = 100; // max 100 images

  await configureDependencies();
  runApp(const App());
}

// ✅ Clear image cache when navigating away from image-heavy screens
@override
void dispose() {
  // Clear specific images from cache if they won't be needed again
  imageCache.evict(NetworkImage(widget.imageUrl));
  super.dispose();
}

// ✅ Use cacheWidth/cacheHeight to decode at display size — saves heap memory
Image.network(
  url,
  cacheWidth: (displayWidth * MediaQuery.devicePixelRatioOf(context)).round(),
  cacheHeight: (displayHeight * MediaQuery.devicePixelRatioOf(context)).round(),
)
```

---

## 6. Isolate Lifecycle Management

```dart
// ❌ Isolate spawned but never killed — runs forever
Future<void> runHeavyWork() async {
  final isolate = await Isolate.spawn(heavyTask, data);
  // ... forgot to kill it
}

// ✅ Always kill isolates when done or when the widget is disposed
class _MyWidgetState extends State<MyWidget> {
  Isolate? _isolate;
  ReceivePort? _receivePort;

  Future<void> _startWork() async {
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      heavyTask,
      _receivePort!.sendPort,
    );

    _receivePort!.listen((result) {
      if (mounted) setState(() => _result = result);
      _cleanup(); // kill after receiving result
    });
  }

  void _cleanup() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _receivePort = null;
  }

  @override
  void dispose() {
    _cleanup(); // ✅ always clean up in dispose
    super.dispose();
  }
}

// ✅ Prefer compute() for one-shot tasks — handles lifecycle automatically
final result = await compute(heavyTask, inputData);
```

---

## 7. Memory Budget & Monitoring

```dart
// ✅ Log memory usage in debug builds for monitoring
import 'dart:developer' as developer;

void logMemoryUsage(String label) {
  developer.postEvent('memory_checkpoint', {'label': label});
  // View in DevTools → Timeline → custom events
}

// Usage
logMemoryUsage('before_image_load');
await loadImages();
logMemoryUsage('after_image_load');
```

### Memory targets (mid-range device)

| Metric | Target | Action if exceeded |
|---|---|---|
| Baseline heap | < 50MB | Audit singletons and static state |
| After heavy screen | < 150MB | Check image cache, dispose controllers |
| After navigation back | ≈ baseline | Leak — find retaining path in DevTools |
| Peak (image gallery) | < 200MB | Reduce `imageCache.maximumSizeBytes` |

---

## Quick Diagnosis Checklist

When memory grows or the app crashes with OOM:

1. **Profile mode?** — Never diagnose in debug mode
2. **Heap snapshot diff** — Take baseline → reproduce → diff → sort by delta
3. **Retaining path** — Click the leaking class → expand retaining path → find root
4. **Controllers** — Is every `AnimationController`, `TextEditingController`, `ScrollController` disposed?
5. **Streams** — Is every `StreamSubscription` cancelled in `dispose()` or BLoC `close()`?
6. **BLoC placement** — Is `BlocProvider` above the widget tree, not inside `build()`?
7. **Timers** — Is every `Timer` cancelled in `dispose()`?
8. **Image cache** — Is `imageCache.maximumSizeBytes` set? Are images decoded at display size?
9. **Isolates** — Is every spawned `Isolate` killed when done?
10. **Context** — Is `BuildContext` stored anywhere outside a widget?

## Reference Files

- `references/implementation_guide.md` — DevTools step-by-step workflow, leak_tracker setup, disposal patterns, and CI integration
