# Lightweight Reactive — ValueNotifier and ChangeNotifier

For local, widget-scoped state that doesn't need BLoC or Riverpod overhead.
Both are built into Flutter — zero dependencies.

---

## When to Use Each

| Tool | Use when |
|---|---|
| `ValueNotifier<T>` | Single value, simple toggle, counter, selected item |
| `ChangeNotifier` | Multiple related fields, simple model, no codegen |
| `BLoC` | Complex events, many state transitions, testability priority |
| `Riverpod Notifier` | Provider composition, cross-widget state, codegen OK |

**Rule:** Start with `ValueNotifier`. Graduate to `ChangeNotifier` when you have multiple fields. Graduate to BLoC/Riverpod when you need event history, complex transitions, or cross-feature state.

---

## ValueNotifier — Single Reactive Value

```dart
// ✅ Counter
final _counter = ValueNotifier<int>(0);

// Increment
_counter.value++;

// React in widget
ValueListenableBuilder<int>(
  valueListenable: _counter,
  builder: (context, count, child) => Text('Count: $count'),
)

// ✅ Always dispose
@override
void dispose() {
  _counter.dispose();
  super.dispose();
}
```

### Real-world: selected tab index

```dart
class _HomePageState extends State<HomePage> {
  final _selectedTab = ValueNotifier<int>(0);

  @override
  void dispose() {
    _selectedTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: _selectedTab,
        builder: (context, tab, _) => IndexedStack(
          index: tab,
          children: const [HomeTab(), SearchTab(), ProfileTab()],
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _selectedTab,
        builder: (context, tab, _) => NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => _selectedTab.value = i,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
```

### Real-world: expansion panel toggle

```dart
class ExpandableSection extends StatefulWidget {
  final String title;
  final Widget content;
  const ExpandableSection({required this.title, required this.content, super.key});

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection> {
  final _isExpanded = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isExpanded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _isExpanded,
          builder: (context, expanded, _) => ListTile(
            title: Text(widget.title),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => _isExpanded.value = !_isExpanded.value,
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _isExpanded,
          builder: (context, expanded, child) => AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: child!,
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
          child: widget.content, // ✅ child is built once — not rebuilt on toggle
        ),
      ],
    );
  }
}
```

---

## ChangeNotifier — Multiple Reactive Fields

```dart
// lib/features/cart/presentation/notifiers/cart_notifier.dart
import 'package:flutter/foundation.dart';

class CartNotifier extends ChangeNotifier {
  final List<CartItem> _items = [];
  bool _isLoading = false;
  String? _error;

  // ✅ Expose immutable views — never expose the mutable list
  List<CartItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);
  double get total => _items.fold(0.0, (sum, item) => sum + item.subtotal);
  bool get isEmpty => _items.isEmpty;

  Future<void> addItem(Product product, {int quantity = 1}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final existing = _items.indexWhere((i) => i.productId == product.id);
      if (existing >= 0) {
        _items[existing] = _items[existing].copyWith(
          quantity: _items[existing].quantity + quantity,
        );
      } else {
        _items.add(CartItem.fromProduct(product, quantity: quantity));
      }
    } catch (e) {
      _error = '$e';
    } finally {
      _isLoading = false;
      notifyListeners(); // ✅ single notify at the end
    }
  }

  void removeItem(String productId) {
    _items.removeWhere((i) => i.productId == productId);
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    final index = _items.indexWhere((i) => i.productId == productId);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(quantity: quantity);
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
```

### Widget — ListenableBuilder (Flutter 3.x)

```dart
// ✅ ListenableBuilder — rebuilds only when notifyListeners() is called
class CartSummary extends StatelessWidget {
  final CartNotifier cart;
  const CartSummary({required this.cart, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Column(
        children: [
          Text('${cart.itemCount} items'),
          Text('Total: \$${cart.total.toStringAsFixed(2)}'),
          if (cart.isLoading) const LinearProgressIndicator(),
          if (cart.error != null) Text(cart.error!, style: const TextStyle(color: Colors.red)),
        ],
      ),
    );
  }
}

// ✅ Selective rebuild — only rebuild the badge, not the whole AppBar
class CartBadge extends StatelessWidget {
  final CartNotifier cart;
  const CartBadge({required this.cart, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      // ✅ child is built once — passed through without rebuilding
      builder: (context, child) => Badge(
        count: cart.itemCount,
        child: child!,
      ),
      child: const Icon(Icons.shopping_cart),
    );
  }
}
```

### Register with GetIt + Injectable

```dart
// ✅ Register as lazySingleton — shared across the app
@lazySingleton
class CartNotifier extends ChangeNotifier { ... }

// In widget — access via GetIt
final cart = GetIt.instance<CartNotifier>();
```

---

## Combining ValueNotifier and ChangeNotifier

```dart
// Multiple notifiers → single Listenable with Listenable.merge
class FilteredProductList extends StatefulWidget {
  @override
  State<FilteredProductList> createState() => _FilteredProductListState();
}

class _FilteredProductListState extends State<FilteredProductList> {
  final _sortOrder = ValueNotifier<SortOrder>(SortOrder.nameAsc);
  final _priceRange = ValueNotifier<RangeValues>(const RangeValues(0, 1000));
  final _inStockOnly = ValueNotifier<bool>(false);

  late final _filters = Listenable.merge([_sortOrder, _priceRange, _inStockOnly]);

  @override
  void dispose() {
    _sortOrder.dispose();
    _priceRange.dispose();
    _inStockOnly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _filters, // rebuilds when ANY filter changes
      builder: (context, _) {
        final filtered = _applyFilters(
          products: widget.products,
          sort: _sortOrder.value,
          priceRange: _priceRange.value,
          inStockOnly: _inStockOnly.value,
        );
        return ProductGrid(products: filtered);
      },
    );
  }
}
```

---

## ValueNotifier vs ChangeNotifier vs BLoC — Decision

```
Single value that changes?
  → ValueNotifier<T>

Multiple related fields, simple model?
  → ChangeNotifier

Need async operations with loading/error states?
  → ChangeNotifier (simple) or BLoC/Riverpod (complex)

State shared across multiple screens?
  → BLoC (with GetIt) or Riverpod provider

Need event history / undo / replay?
  → BLoC

Need to compose with other reactive sources?
  → Riverpod (ref.watch composition)

Need testability with bloc_test?
  → BLoC
```

---

## Testing ValueNotifier and ChangeNotifier

```dart
void main() {
  group('CartNotifier', () {
    late CartNotifier cart;

    setUp(() => cart = CartNotifier());
    tearDown(() => cart.dispose());

    test('addItem increases itemCount', () async {
      final product = Product(id: 'p1', name: 'Test', price: 9.99);
      await cart.addItem(product);
      expect(cart.itemCount, 1);
    });

    test('addItem same product increases quantity', () async {
      final product = Product(id: 'p1', name: 'Test', price: 9.99);
      await cart.addItem(product);
      await cart.addItem(product);
      expect(cart.itemCount, 2);
      expect(cart.items.length, 1); // one item, quantity 2
    });

    test('notifyListeners called on addItem', () async {
      var notified = false;
      cart.addListener(() => notified = true);

      final product = Product(id: 'p1', name: 'Test', price: 9.99);
      await cart.addItem(product);

      expect(notified, true);
    });

    test('clear empties the cart', () async {
      final product = Product(id: 'p1', name: 'Test', price: 9.99);
      await cart.addItem(product);
      cart.clear();
      expect(cart.isEmpty, true);
    });
  });
}
```
