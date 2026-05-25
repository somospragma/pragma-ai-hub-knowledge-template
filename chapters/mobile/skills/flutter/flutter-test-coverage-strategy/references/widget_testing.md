# Widget Tests and Golden Tests

## Widget Test Setup

```dart
// test/features/product/presentation/pages/product_page_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// MockBloc from bloc_test — handles stream and state automatically
class MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

Widget buildSubject({required ProductBloc bloc}) => MaterialApp(
  home: BlocProvider<ProductBloc>.value(
    value: bloc,
    child: const ProductView(),
  ),
);

void main() {
  late MockProductBloc mockBloc;

  setUp(() => mockBloc = MockProductBloc());
  tearDown(() => mockBloc.close());

  group('ProductPage', () {
    testWidgets('shows loading indicator when state is loading', (tester) async {
      when(() => mockBloc.state).thenReturn(const ProductState.loading());

      await tester.pumpWidget(buildSubject(bloc: mockBloc));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ProductCard), findsNothing);
    });

    testWidgets('shows ProductCard when state is success', (tester) async {
      final vm = ProductViewModel(
        id: '1',
        title: 'Blue Widget',
        priceLabel: r'$9.99',
        showAvailabilityBadge: false,
      );
      when(() => mockBloc.state)
          .thenReturn(ProductState.success(product: vm));

      await tester.pumpWidget(buildSubject(bloc: mockBloc));

      expect(find.byType(ProductCard), findsOneWidget);
      expect(find.text('Blue Widget'), findsOneWidget);
      expect(find.text(r'$9.99'), findsOneWidget);
    });

    testWidgets('shows error message and retry button when state is error', (tester) async {
      when(() => mockBloc.state).thenReturn(
        const ProductState.error(message: 'No connection', code: 'NET'),
      );

      await tester.pumpWidget(buildSubject(bloc: mockBloc));

      expect(find.text('No connection'), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('dispatches loadRequested on retry tap', (tester) async {
      when(() => mockBloc.state).thenReturn(
        const ProductState.error(message: 'No connection', code: 'NET'),
      );

      await tester.pumpWidget(buildSubject(bloc: mockBloc));
      await tester.tap(find.byType(TextButton));

      verify(() => mockBloc.add(const ProductEvent.loadRequested(id: '1'))).called(1);
    });

    testWidgets('shows empty state when state is empty', (tester) async {
      when(() => mockBloc.state).thenReturn(const ProductState.empty());

      await tester.pumpWidget(buildSubject(bloc: mockBloc));

      expect(find.byKey(const Key('empty_state')), findsOneWidget);
    });
  });
}
```

---

## Testing State Transitions in Widgets

```dart
testWidgets('transitions from loading to success', (tester) async {
  // Emit a sequence of states
  whenListen(
    mockBloc,
    Stream.fromIterable([
      const ProductState.loading(),
      ProductState.success(product: tProductVm),
    ]),
    initialState: const ProductState.initial(),
  );

  await tester.pumpWidget(buildSubject(bloc: mockBloc));

  // Initial state
  expect(find.byType(CircularProgressIndicator), findsNothing);

  // After first emission (loading)
  await tester.pump();
  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  // After second emission (success)
  await tester.pump();
  expect(find.byType(ProductCard), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
});
```

---

## Common Finders

```dart
// By widget type
find.byType(CircularProgressIndicator)
find.byType(ProductCard)

// By key
find.byKey(const Key('product_title'))
find.byKey(const ValueKey('product_1'))

// By text
find.text('Retry')                    // exact match
find.textContaining('Widget')         // partial match

// By icon
find.byIcon(Icons.refresh)
find.byIcon(Icons.shopping_cart)

// By semantics label (accessibility)
find.bySemanticsLabel('Add to cart')
find.bySemanticsLabel(RegExp(r'Product.*'))

// Descendant — find widget inside another
find.descendant(
  of: find.byType(ProductCard),
  matching: find.byType(Text),
)

// Ancestor
find.ancestor(
  of: find.text('Blue Widget'),
  matching: find.byType(Card),
)
```

---

## Interaction Testing

```dart
// Tap
await tester.tap(find.byType(ElevatedButton));
await tester.pump();  // rebuild after tap

// Long press
await tester.longPress(find.byType(ProductCard));
await tester.pump();

// Scroll
await tester.drag(find.byType(ListView), const Offset(0, -300));
await tester.pump();

// Enter text
await tester.enterText(find.byType(TextField), 'search query');
await tester.pump();

// Pump and settle (wait for all animations)
await tester.pumpAndSettle();

// Pump with duration (for specific animations)
await tester.pump(const Duration(milliseconds: 300));
```

---

## Golden Tests (Visual Regression)

```dart
// test/features/product/presentation/widgets/product_card_golden_test.dart
import 'package:alchemist/alchemist.dart';  // or flutter_test matchesGoldenFile

void main() {
  group('ProductCard golden tests', () {
    goldenTest(
      'renders correctly in available state',
      fileName: 'product_card_available',
      builder: () => GoldenTestGroup(
        children: [
          GoldenTestScenario(
            name: 'light theme',
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: ProductCard(
                  vm: ProductViewModel(
                    id: '1',
                    title: 'Blue Widget',
                    priceLabel: r'$9.99',
                    showAvailabilityBadge: false,
                  ),
                ),
              ),
            ),
          ),
          GoldenTestScenario(
            name: 'dark theme',
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: Scaffold(
                body: ProductCard(
                  vm: ProductViewModel(
                    id: '1',
                    title: 'Blue Widget',
                    priceLabel: r'$9.99',
                    showAvailabilityBadge: false,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  });
}
```

```bash
# Update goldens (when UI changes intentionally)
flutter test --update-goldens test/features/product/presentation/widgets/

# Run golden tests only
flutter test --tags golden

# Run all tests except goldens (faster CI)
flutter test --exclude-tags golden
```

---

## Testing with Network Images

```dart
// Use network_image_mock to prevent network calls in widget tests
import 'package:network_image_mock/network_image_mock.dart';

testWidgets('shows product image', (tester) async {
  await mockNetworkImagesFor(() async {
    when(() => mockBloc.state).thenReturn(
      ProductState.success(product: tProductVmWithImage),
    );

    await tester.pumpWidget(buildSubject(bloc: mockBloc));

    expect(find.byType(Image), findsOneWidget);
  });
});
```

---

## Testing Navigation

```dart
testWidgets('navigates to product detail on card tap', (tester) async {
  final mockObserver = MockNavigatorObserver();

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [mockObserver],
      home: BlocProvider<ProductBloc>.value(
        value: mockBloc,
        child: const ProductListPage(),
      ),
    ),
  );

  when(() => mockBloc.state).thenReturn(
    ProductState.success(products: [tProductVm]),
  );
  await tester.pump();

  await tester.tap(find.byType(ProductCard).first);
  await tester.pumpAndSettle();

  verify(() => mockObserver.didPush(any(), any())).called(1);
});
```

---

## Widget Test Best Practices

```dart
// ✅ Always provide a MaterialApp wrapper
Widget buildSubject({required ProductBloc bloc}) => MaterialApp(
  home: BlocProvider.value(value: bloc, child: const ProductView()),
);

// ✅ Use pumpAndSettle for animations, pump() for immediate state
await tester.pump();          // one frame
await tester.pumpAndSettle(); // all animations complete

// ✅ Test accessibility
testWidgets('has correct semantics', (tester) async {
  // ...
  final semantics = tester.getSemantics(find.byType(ElevatedButton));
  expect(semantics.label, 'Add to cart');
  expect(semantics.hasFlag(SemanticsFlag.isButton), true);
});

// ✅ Test with different screen sizes
testWidgets('adapts to small screen', (tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(buildSubject(bloc: mockBloc));
  // verify layout adapts
});
```
