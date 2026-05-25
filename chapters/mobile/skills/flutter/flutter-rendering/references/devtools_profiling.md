# DevTools Performance Profiling Guide

## Step 1 — Always Run in Profile Mode

```bash
# ❌ Never diagnose in debug mode — JIT + assertions make it 5–10x slower
flutter run

# ✅ Profile mode: AOT compiled, no debug overhead, real performance
flutter run --profile

# DevTools opens automatically, or visit the URL printed in the terminal
# e.g. http://127.0.0.1:9100
```

---

## Step 2 — Performance Tab (Frame Timeline)

1. Open DevTools → **Performance** tab
2. Click **Record**
3. Reproduce the janky interaction (scroll, navigate, animate)
4. Click **Stop**
5. Inspect the **Frame Chart**

### Reading the Frame Chart

```
Green  < 8ms   ✅  120fps budget met
Yellow 8–16ms  ⚠️  60fps only — investigate
Red    > 16ms  ❌  Jank — fix required
```

Each frame has two bars:
- **UI thread** (top) — Dart build + layout
- **Raster thread** (bottom) — GPU compositing

If only the raster bar is red → look for `saveLayer`, `BackdropFilter`, large `ClipRRect`.  
If only the UI bar is red → look for expensive `build()`, excessive rebuilds, heavy computation.

### Flame Chart Navigation

- Click a red/yellow frame to zoom in
- Look for the widest spans — those are the bottlenecks
- `build` calls in the UI thread show which widgets are rebuilding
- `Picture::playback` in the raster thread shows draw call cost

---

## Step 3 — Widget Rebuild Stats

```dart
// Add to main() — debug builds only
void main() {
  debugProfileBuildsEnabled = true;
  runApp(const App());
}
```

In DevTools → **Widget Rebuild Stats** tab:
- Sort by **rebuild count**
- Widgets rebuilding > 10× per frame are candidates for optimization
- Use `buildWhen`, `BlocSelector`, `context.select`, or `const` to reduce

---

## Step 4 — Repaint Regions

```dart
// Visualize which areas repaint on each frame
void main() {
  debugRepaintRainbowEnabled = true; // flashes repaint regions with cycling colors
  runApp(const App());
}
```

- Static content should **not** flash
- If a large area flashes when only a small part changed → add `RepaintBoundary`
- Each unique color cycle = one repaint event

---

## Step 5 — Memory Tab

1. DevTools → **Memory** tab
2. Click **Take Heap Snapshot** (baseline)
3. Perform the operation (scroll, navigate, load images)
4. Click **GC** (force garbage collection)
5. Take another snapshot
6. Compare — objects that should have been collected but weren't = memory leak

### Common memory leaks
- `StreamSubscription` not cancelled in `dispose()`
- `AnimationController` not disposed
- `TextEditingController` / `FocusNode` not disposed
- `BlocProvider` created inside `build()` instead of above the widget tree

---

## Step 6 — Trace Startup Time

```bash
flutter run --profile --trace-startup 2>&1 | grep "timeToFirstFrameMicros"
# Target: < 2,000,000 microseconds (2 seconds) on mid-range device
```

In DevTools → **Performance** tab → load the startup trace JSON:
- Look for `engineEnterTimestamp` → `timeToFirstFrameMicros`
- Expensive `initState` calls, heavy DI initialization, or large asset decoding show up here

---

## Step 7 — Raster Cache Inspector

DevTools → **Performance** → **Raster Cache** tab:
- Shows which layers are cached on the GPU
- Large uncached layers that repaint frequently = candidates for `RepaintBoundary`
- Layers that are cached but never reused = wasted GPU memory

---

## Performance Budget Reference

| Metric | Target | Where to Check |
|---|---|---|
| Frame build time (UI thread) | < 8ms | Performance tab — top bar |
| Frame raster time (GPU thread) | < 8ms | Performance tab — bottom bar |
| Widget rebuilds per frame | < 3 for key widgets | Widget Rebuild Stats |
| Heap memory (mid-range device) | < 150MB | Memory tab |
| Cold start (release mode) | < 2s | `--trace-startup` |
| 120Hz frame budget (total) | < 8ms | Performance overlay |

---

## Useful DevTools Shortcuts

| Action | How |
|---|---|
| Open DevTools | URL printed by `flutter run`, or `flutter pub global run devtools` |
| Performance overlay in app | `MaterialApp(showPerformanceOverlay: true)` |
| Slow animations (0.25× speed) | DevTools → Performance → **Slow Animations** toggle |
| Highlight repaints | `debugRepaintRainbowEnabled = true` |
| Track rebuilds | `debugProfileBuildsEnabled = true` |
| Force GC | Memory tab → GC button |
