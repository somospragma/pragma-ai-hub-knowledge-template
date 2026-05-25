# Common Jank Causes & Fixes

Top causes of dropped frames in Flutter apps, ordered by frequency.
Always confirm with DevTools profiling before applying a fix.

---

## 1. BlocBuilder Wrapping Too Much

**Symptom:** Every state emission rebuilds a large subtree including static widgets.

```dart
// ❌ Scaffold + AppBar + body all rebuild on every state change
BlocBuilder<MyBloc, MyState>(
  builder: (context, state) => Scaffold(
    appBar: AppBar(title: Text(state.title)),
    body: ExpensiveBody(state: state),
  ),
)

// ✅ Only rebuild the parts that actually change
Scaffold(
  appBar: const AppBar(title: Text('Fixed Title')),
  body: BlocBuilder<MyBloc, MyState>(
    buildWhen: (prev, curr) => prev.data != curr.data,
    builder: (context, state) => ExpensiveBody(data: state.data),
  ),
)

// ✅ Or use context.select for a single field
final title = context.select<MyBloc, String>((b) => b.state.title);
```

---

## 2. Missing const Constructors

**Symptom:** Widgets that never change are rebuilt on every parent rebuild.

```dart
// ❌ New instance created on every parent rebuild
child: Padding(
  padding: EdgeInsets.all(16),
  child: Text('Hello', style: TextStyle(fontSize: 14)),
)

// ✅ Compiler reuses the same instance — zero rebuild cost
child: const Padding(
  padding: EdgeInsets.all(16),
  child: Text('Hello', style: TextStyle(fontSize: 14)),
)
```

```bash
# Auto-fix missing const across the project
dart fix --apply
```

---

## 3. ListView(children: [...]) for Long Lists

**Symptom:** Slow initial render, high memory usage, jank when list is long.

```dart
// ❌ Builds ALL items at once — O(n) build cost upfront
ListView(
  children: products.map((p) => ProductCard(product: p)).toList(),
)

// ✅ Builds only visible items — O(1) per frame
ListView.builder(
  itemCount: products.length,
  itemExtent: 80.0,          // fixed height = O(1) layout
  itemBuilder: (_, i) => ProductCard(product: products[i]),
)
```

---

## 4. Opacity on Complex Subtrees

**Symptom:** Raster thread spike when opacity changes. DevTools shows `saveLayer`.

```dart
// ❌ Opacity triggers saveLayer — composites entire subtree to offscreen buffer
Opacity(opacity: _visible ? 1.0 : 0.0, child: ComplexWidget())

// ✅ FadeTransition — no saveLayer, uses compositing layer only during animation
FadeTransition(opacity: _animation, child: ComplexWidget())

// ✅ AnimatedOpacity — same benefit for simple show/hide
AnimatedOpacity(
  opacity: _visible ? 1.0 : 0.0,
  duration: const Duration(milliseconds: 200),
  child: ComplexWidget(),
)
```

---

## 5. Heavy Computation Inside build()

**Symptom:** UI thread spike on every rebuild. Flame chart shows wide `build` spans.

```dart
// ❌ Sort + filter runs on every rebuild
Widget build(BuildContext context) {
  final sorted = items.toList()..sort((a, b) => a.name.compareTo(b.name));
  final filtered = sorted.where((i) => i.isActive).toList();
  return ProductList(items: filtered);
}

// ✅ Compute in BLoC state — runs once when data changes
// In the BLoC:
final sortedActive = (state.items.toList()..sort(...))
    .where((i) => i.isActive)
    .toList();
emit(state.copyWith(sortedActiveItems: sortedActive));

// In the widget — just reads pre-computed data
Widget build(BuildContext context) {
  final items = context.select<ProductBloc, List<Product>>(
    (b) => b.state.sortedActiveItems,
  );
  return ProductList(items: items);
}
```

---

## 6. Images Decoded at Full Resolution

**Symptom:** High memory usage, slow image display, memory tab shows large image objects.

```dart
// ❌ 4K image decoded fully even if displayed at 100×100
Image.network(url)

// ✅ Decode at display size — massive memory saving
Image.network(
  url,
  cacheWidth: (100 * MediaQuery.devicePixelRatioOf(context)).round(),
  cacheHeight: (100 * MediaQuery.devicePixelRatioOf(context)).round(),
)

// ✅ With caching
CachedNetworkImage(
  imageUrl: url,
  memCacheWidth: 200,
  memCacheHeight: 200,
)
```

---

## 7. AnimationController Not Using AnimatedBuilder

**Symptom:** `setState` called on every animation tick, rebuilding the entire widget.

```dart
// ❌ setState on every tick rebuilds the whole widget
_controller.addListener(() => setState(() {}));

Widget build(BuildContext context) {
  return Transform.scale(scale: _controller.value, child: const MyWidget());
}

// ✅ AnimatedBuilder rebuilds only its subtree, and child is built once
AnimatedBuilder(
  animation: _controller,
  builder: (context, child) => Transform.scale(
    scale: _scaleAnimation.value,
    child: child,           // not rebuilt on animation tick
  ),
  child: const MyWidget(),  // built once
)
```

---

## 8. Excessive RepaintBoundary (or Missing Where Needed)

**Symptom (too many):** High GPU memory usage, compositing overhead.  
**Symptom (too few):** Large areas flash in `debugRepaintRainbowEnabled`.

```dart
// ❌ Wrapping every widget — each boundary costs GPU memory
ListView.builder(
  itemBuilder: (_, i) => RepaintBoundary(child: SimpleTextTile(item: items[i])),
)

// ✅ Only wrap items that have their own animations or repaint independently
ListView.builder(
  itemBuilder: (_, i) => items[i].hasAnimation
      ? RepaintBoundary(child: AnimatedProductCard(item: items[i]))
      : ProductCard(item: items[i]),
)
```

---

## 9. StreamBuilder / FutureBuilder Rebuilding Too Often

**Symptom:** Widget rebuilds on every stream event even when data hasn't changed.

```dart
// ❌ Rebuilds on every stream emission regardless of value change
StreamBuilder<List<Product>>(
  stream: productStream,
  builder: (context, snapshot) => ProductList(products: snapshot.data ?? []),
)

// ✅ Use BLoC to debounce/deduplicate stream events before they reach the UI
// In the BLoC — only emit when data actually changes:
_productStream.distinct().listen((products) {
  if (products != state.products) {
    emit(state.copyWith(products: products));
  }
});

// ✅ Or use distinctUntilChanged / debounceTime from rxdart if needed
```

---

## 10. Navigator.push Causing Jank on First Route

**Symptom:** Jank on first navigation to a route. Subsequent navigations are smooth.

```dart
// ❌ Route builds everything synchronously on push
Navigator.push(context, MaterialPageRoute(builder: (_) => HeavyPage()))

// ✅ Preload the route's data before navigating
await context.read<ProductBloc>().preloadProduct(productId);
if (mounted) context.push('/product/$productId');

// ✅ Use page transitions that give the new route time to build
// PageRouteBuilder with a short duration reduces perceived jank
PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (_, __, ___) => const HeavyPage(),
  transitionsBuilder: (_, animation, __, child) =>
      FadeTransition(opacity: animation, child: child),
)

// ✅ With go_router — preload in redirect or before go()
```

---

## Quick Reference Table

| Cause | Symptom | Fix |
|---|---|---|
| BlocBuilder too wide | Many widgets rebuild | `buildWhen`, `BlocSelector`, `context.select` |
| Missing `const` | Static widgets rebuild | `dart fix --apply` |
| `ListView(children:[])` | Slow initial render | `ListView.builder` + `itemExtent` |
| `Opacity` on complex tree | Raster spike, `saveLayer` | `FadeTransition`, `AnimatedOpacity` |
| Heavy `build()` | UI thread spike | Move computation to BLoC state |
| Full-res images | High memory | `cacheWidth`/`cacheHeight` |
| `setState` in animation | Full widget rebuild per tick | `AnimatedBuilder` with `child` |
| Too many `RepaintBoundary` | High GPU memory | Only add where DevTools shows repaints |
| Frequent stream rebuilds | Unnecessary rebuilds | BLoC deduplication, `distinct()` |
| First-route jank | Jank on first push | Preload data, `FadeTransition` |
