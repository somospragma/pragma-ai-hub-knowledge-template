---
name: flutter-rendering
description: >
  Optimize Flutter rendering performance: eliminate jank, minimize widget rebuilds, use RepaintBoundary, const widgets, Impeller-aware patterns, and profiling with DevTools. Use this skill when reporting jank, slow scroll, dropped frames, excessive rebuilds, or asking about performance overlay, const constructors, RepaintBoundary, list virtualization, Impeller, or Flutter DevTools performance tab. Always profile before optimizing.
commands:
  - optimize-rendering
inputs:
  - name: action
    description: Action to perform (diagnose, optimize, audit). "diagnose" profiles and identifies jank sources, "optimize" applies rendering fixes, "audit" checks for common anti-patterns (missing const, Opacity misuse, non-virtualized lists).
    required: true
  - name: target
    description: Path to the widget, page, or feature directory to analyze (e.g. lib/features/product/presentation/pages/product_list_page.dart).
    required: true
  - name: issue
    description: Specific rendering issue to focus on (jank, rebuilds, memory, slow-scroll, dropped-frames). Helps narrow the diagnosis scope.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Flutter Rendering Performance

**Rule #1: Always profile before optimizing. Never guess.**

As of Flutter 3.27, **Impeller is the default renderer** on iOS and Android API 29+.
Shader compilation jank is largely eliminated — but layout, rebuild, and raster costs still apply.

## Rule #1: Profile First

```bash
# Always profile in profile mode — debug is 10x slower and unrepresentative
flutter run --profile

# Trace startup time
flutter run --profile --trace-startup
```

```dart
// Enable performance overlay — Green = GPU raster, Blue = CPU build
// > 8ms per layer = budget exceeded (16ms total for 60fps, 8ms for 120fps)
MaterialApp(showPerformanceOverlay: true)
```

```dart
// Enable in debug builds to visualize rebuild regions
void main() {
  debugProfileBuildsEnabled = true;      // shows build times in DevTools
  debugRepaintRainbowEnabled = true;     // flashes repaint regions with colors
  debugPaintLayerBordersEnabled = true;  // shows layer boundaries
  runApp(const App());
}
```

See `references/devtools_profiling.md` for the full step-by-step profiling workflow.

---

## Impeller — What Changes in 2026

Impeller precompiles all shaders at engine build time (AOT), eliminating runtime shader
compilation jank. Key implications:

```dart
// ✅ Impeller handles these without jank — no special workaround needed
// - First-frame animations
// - Complex path rendering
// - BlendMode effects
// - Backdrop filters

// ⚠️ Still costs raster time — profile and optimize if > 8ms:
// - saveLayer() / BackdropFilter (creates new compositing layer)
// - Opacity widget on complex subtrees (use AnimatedOpacity or FadeTransition instead)
// - ClipRRect on large surfaces
// - ImageFilter.blur on large areas

// ✅ Impeller-friendly: prefer these over saveLayer-based equivalents
FadeTransition(opacity: animation, child: widget)       // vs Opacity(opacity: 0.5)
ColorFiltered(colorFilter: filter, child: widget)       // vs ShaderMask
DecoratedBox(decoration: BoxDecoration(borderRadius:…)) // vs ClipRRect when possible
```

```dart
// ⚠️ Disable Impeller only if you have a confirmed Impeller-specific bug
// AndroidManifest.xml
// <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false" />

// Info.plist (iOS)
// <key>FLTEnableImpeller</key><false/>
```

---

## const — Eliminate Rebuilds at Compile Time

```dart
// ✅ const = widget instance is reused, never rebuilt
const SizedBox(height: 16)
const EdgeInsets.all(24)
const Text('Static Label', style: TextStyle(fontSize: 14))
const Icon(Icons.home)
const Divider()

// ✅ Always add const constructor to your own stateless widgets
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.label, super.key});
  final String label;

  @override
  Widget build(BuildContext context) => /* ... */;
}

// ✅ Usage — compiler reuses the same instance
const StatusBadge(label: 'Available')
```

---

## RepaintBoundary — Isolate Repaint Regions

Use when a subtree repaints frequently and its neighbors do not.
Each `RepaintBoundary` creates a new compositing layer — don't overuse it.

```dart
// ✅ Isolate an animation from static content
Scaffold(
  body: Column(
    children: [
      const StaticHeader(),           // never repaints
      Expanded(
        child: RepaintBoundary(        // animation repaints stay inside this layer
          child: AnimatedProgressWidget(),
        ),
      ),
    ],
  ),
)

// ✅ List items — isolate expensive items that have their own animations
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => RepaintBoundary(
    key: ValueKey(items[index].id),
    child: ProductListItem(item: items[index]),
  ),
)

// ❌ Don't wrap every widget — each boundary has memory and compositing cost
// Only add RepaintBoundary where DevTools shows unnecessary repaints
```

---

## List Virtualization

```dart
// ❌ Builds ALL items upfront — never use for dynamic/long lists
ListView(children: items.map((i) => ItemWidget(item: i)).toList())

// ✅ Fixed-height items — itemExtent enables O(1) layout (fastest)
ListView.builder(
  itemCount: items.length,
  itemExtent: 72.0,
  itemBuilder: (context, i) => ItemWidget(item: items[i]),
)

// ✅ Variable-height items — itemExtentBuilder (Flutter 3.13+)
// Provides height per index without building the widget — faster than no extent
ListView.builder(
  itemCount: items.length,
  itemExtentBuilder: (index, dimensions) => items[index].isExpanded ? 120.0 : 72.0,
  itemBuilder: (context, i) => ItemWidget(item: items[i]),
)

// ✅ Sliver-based for complex scrolling layouts
CustomScrollView(
  slivers: [
    SliverAppBar(pinned: true, title: const Text('Products')),
    SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => ItemWidget(item: items[i]),
    ),
  ],
)

// ✅ Grids
GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    childAspectRatio: 0.75,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
  ),
  itemCount: items.length,
  itemBuilder: (context, i) => GridItem(item: items[i]),
)

// ✅ Separated list without building separator widgets eagerly
ListView.separated(
  itemCount: items.length,
  separatorBuilder: (_, __) => const Divider(height: 1),
  itemBuilder: (context, i) => ItemWidget(item: items[i]),
)
```

---

## BlocBuilder — Minimize Rebuild Scope

```dart
// ❌ Entire Scaffold rebuilds on every state change
BlocBuilder<ProductBloc, ProductState>(
  builder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Products')),
    body: ProductList(state: state),
  ),
)

// ✅ Only the changing subtree rebuilds
Scaffold(
  appBar: const AppBar(title: Text('Products')),
  body: BlocBuilder<ProductBloc, ProductState>(
    // Only rebuild when the state TYPE changes — not on every emission
    buildWhen: (prev, curr) => prev.runtimeType != curr.runtimeType,
    builder: (context, state) => switch (state) {
      ProductLoading() => const CircularProgressIndicator(),
      ProductSuccess(:final products) => ProductList(products: products),
      ProductError(:final message) => ErrorWidget(message: message),
      _ => const SizedBox.shrink(),
    },
  ),
)

// ✅ context.select — rebuild only when a specific field changes
// (flutter_bloc 9.x — requires BlocProvider above)
final count = context.select<CartBloc, int>(
  (bloc) => bloc.state.itemCount,
);
// This widget only rebuilds when itemCount changes, not on any CartBloc state

// ✅ BlocSelector — same as select but as a widget
BlocSelector<CartBloc, CartState, int>(
  selector: (state) => state.itemCount,
  builder: (context, count) => CartBadge(count: count),
)
```

---

## Avoid Expensive Operations in build()

```dart
// ❌ Heavy computation inside build — runs on every rebuild
Widget build(BuildContext context) {
  final sorted = items.toList()..sort((a, b) => a.name.compareTo(b.name)); // ❌
  final filtered = sorted.where((i) => i.isActive).toList();               // ❌
  return ListView.builder(/* ... */);
}

// ✅ Compute in the BLoC/state, or cache with a local variable
// In the BLoC state — computed once when state changes:
@freezed
class ProductState with _$ProductState {
  const factory ProductState.success({
    required List<Product> products,
    required List<Product> sortedActiveProducts, // pre-computed
  }) = ProductSuccess;
}

// ✅ Or use didUpdateWidget / initState in StatefulWidget
@override
void didUpdateWidget(covariant ProductList oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.products != widget.products) {
    _sorted = widget.products.toList()..sort(/* ... */);
  }
}
```

---

## Image Performance

```dart
// ✅ Downscale to display size — saves GPU memory
Image.network(
  url,
  cacheWidth: (200 * MediaQuery.devicePixelRatioOf(context)).round(),
  cacheHeight: (200 * MediaQuery.devicePixelRatioOf(context)).round(),
  filterQuality: FilterQuality.medium,
)

// ✅ cached_network_image with memory cache bounds
CachedNetworkImage(
  imageUrl: url,
  memCacheWidth: 400,
  memCacheHeight: 400,
  placeholder: (_, __) => const ShimmerPlaceholder(),
  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
)

// ✅ Preload above-the-fold images before navigation
await precacheImage(NetworkImage(heroImageUrl), context);

// ✅ Use SVG for icons/illustrations — no raster memory cost
// (flutter_svg package)
SvgPicture.asset('assets/icons/home.svg', width: 24, height: 24)
```

---

## Opacity and Animations

```dart
// ❌ Opacity widget triggers saveLayer on complex subtrees — expensive
Opacity(opacity: 0.5, child: ComplexWidget())

// ✅ AnimatedOpacity uses a compositing layer only during animation
AnimatedOpacity(
  opacity: _visible ? 1.0 : 0.0,
  duration: const Duration(milliseconds: 200),
  child: ComplexWidget(),
)

// ✅ FadeTransition — most efficient, driven by Animation<double>
FadeTransition(
  opacity: _animationController,
  child: ComplexWidget(),
)

// ✅ For simple color/size animations — AnimatedContainer avoids rebuilds
AnimatedContainer(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOut,
  width: _expanded ? 200 : 100,
  color: _active ? Colors.blue : Colors.grey,
)

// ✅ Use AnimationController + Tween for full control
// Animations driven by AnimationController do NOT trigger setState rebuilds
// on the parent — only the AnimatedWidget/AnimatedBuilder subtree rebuilds
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) => Transform.scale(
    scale: _scaleAnimation.value,
    child: child, // child is NOT rebuilt — passed through
  ),
  child: const ExpensiveStaticWidget(), // built once
)
```

---

## CustomPainter — Efficient Canvas Drawing

```dart
// ✅ shouldRepaint prevents unnecessary redraws
class ChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  const ChartPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Batch path operations — one drawPath call is faster than many drawLine calls
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = i * size.width / (data.length - 1);
      final y = size.height - (data[i] * size.height);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}

// ✅ Wrap in RepaintBoundary if the chart repaints independently
RepaintBoundary(
  child: CustomPaint(
    painter: ChartPainter(data: chartData, color: Colors.blue),
    size: const Size(double.infinity, 200),
  ),
)
```

---

## Deferred Loading — Reduce Initial Build Cost

```dart
// ✅ Defer expensive widgets until they are actually needed
// Use Visibility with maintainState: false (default) to avoid building off-screen tabs
IndexedStack(
  index: _currentTab,
  children: [
    const HomeTab(),
    // Only build when first visited — use lazy initialization
    if (_tabsVisited.contains(1)) const ProfileTab() else const SizedBox.shrink(),
  ],
)

// ✅ For heavy off-screen content — KeepAlive only after first visit
class ProfileTab extends StatefulWidget {
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // keeps state after first build

  @override
  Widget build(BuildContext context) {
    super.build(context); // required with AutomaticKeepAliveClientMixin
    return const ProfileContent();
  }
}
```

---

## Performance Budget (2026 Targets)

| Metric | Target | Tool |
|---|---|---|
| Frame build time | < 8ms | DevTools → Performance |
| Frame raster time | < 8ms | DevTools → Performance |
| Widget rebuilds/frame | < 3 for key widgets | DevTools → Widget Rebuild Stats |
| Memory (mid-range device) | < 150MB | DevTools → Memory |
| Cold start (release) | < 2s | `--trace-startup` |
| 120Hz frame budget | < 8ms total | Performance overlay |

---

## Quick Diagnosis Checklist

When you see jank or dropped frames, check in this order:

1. **Profile mode?** — Never diagnose in debug mode
2. **Rebuild scope** — Is `BlocBuilder` wrapping too much? Use `buildWhen` or `BlocSelector`
3. **const missing** — Run `dart fix --apply` to add missing const
4. **List type** — Is `ListView(children: [...])` used for a long list?
5. **Opacity/saveLayer** — Check DevTools for `saveLayer` calls in the raster thread
6. **Image size** — Are images decoded at full resolution? Add `cacheWidth`/`cacheHeight`
7. **RepaintBoundary** — Enable `debugRepaintRainbowEnabled` to find excessive repaints
8. **build() cost** — Is sorting/filtering happening inside `build()`?
9. **Impeller issue?** — Check if disabling Impeller resolves it (then file a bug)

## Reference Files

- `references/devtools_profiling.md` — step-by-step DevTools performance profiling guide
- `references/common_jank_fixes.md` — top 10 most common causes of jank with fixes
