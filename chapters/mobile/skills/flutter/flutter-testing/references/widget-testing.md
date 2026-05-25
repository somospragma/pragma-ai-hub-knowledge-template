# Widget Testing Reference

Widget tests validate UI rendering, state transitions, and user interactions
without running the full app.

## Stack

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  bloc_test: ^9.1.7
  mocktail: ^1.0.5
  network_image_mock: ^2.1.1
```

---

## Setup Pattern

```dart
// test/features/product/presentation/pages/product_page_test.dart
class MockProductBloc extends MockBloc<ProductEvent, ProductState>
    implements ProductBloc {}

Widget buildSubject(ProductBloc bloc) => MaterialApp(
  home: BlocProvider<ProductBloc>.value(
    value: bloc,
    child: const ProductView(),
  ),
);

void main() {
  late MockProductBloc mockBloc;

  setUp(() {
    mockBloc = MockProductBloc();
    when(() => mockBloc.state).thenReturn(const ProductState.initial());
  });

  tearDown(() => mockBloc.close());
}
```

---

## Testing All BLoC States

```dart
group('ProductPage', () {
  testWidgets('shows loading indicator when state is loading', (tester) async {
    when(() => mockBloc.state).thenReturn(const ProductState.loading());

    await tester.pumpWidget(buildSubject(mockBloc));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);
  });

  testWidgets('shows ProductCard when state is success', (tester) async {
    when(() => mockBloc.state)
        .thenReturn(ProductState.success(product: tProductVm));

    await tester.pumpWidget(buildSubject(mockBloc));

    expect(find.byType(ProductCard), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    expect(find.text(r'$9.99'), findsOneWidget);
  });

  testWidgets('shows error message and retry button when state is error',
      (tester) async {
    when(() => mockBloc.state).thenReturn(
      const ProductState.error(message: 'No connection'),
    );

    await tester.pumpWidget(buildSubject(mockBloc));

    expect(find.text('No connection'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('shows empty state widget when state is empty', (tester) async {
    when(() => mockBloc.state).thenReturn(const ProductState.empty());

    await tester.pumpWidget(buildSubject(mockBloc));

    expect(find.byKey(const Key('empty_state')), findsOneWidget);
  });
});
```

---

## Testing State Transitions

```dart
testWidgets('transitions from loading to success', (tester) async {
  whenListen(
    mockBloc,
    Stream.fromIterable([
      const ProductState.loading(),
      ProductState.success(product: tProductVm),
    ]),
    initialState: const ProductState.initial(),
  );

  await tester.pumpWidget(buildSubject(mockBloc));

  // initial
  expect(find.byType(CircularProgressIndicator), findsNothing);

  // loading
  await tester.pump();
  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  // success
  await tester.pump();
  expect(find.byType(ProductCard), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
});
```

---

## Testing User Interactions

```dart
testWidgets('dispatches loadRequested on retry tap', (tester) async {
  when(() => mockBloc.state).thenReturn(
    const ProductState.error(message: 'No connection'),
  );

  await tester.pumpWidget(buildSubject(mockBloc));
  await tester.tap(find.byType(TextButton));

  verify(() => mockBloc.add(const ProductEvent.loadRequested(id: '1')))
      .called(1);
});

testWidgets('submits form with valid data', (tester) async {
  await tester.pumpWidget(buildSubject(mockBloc));

  await tester.enterText(find.byKey(const Key('name_field')), 'Widget');
  await tester.enterText(find.byKey(const Key('price_field')), '9.99');
  await tester.tap(find.byKey(const Key('submit_button')));
  await tester.pump();

  verify(() => mockBloc.add(any())).called(1);
});
```

---

## pump() vs pumpAndSettle()

| Situation | Use |
|---|---|
| Immediate `setState` / BLoC emit | `pump()` |
| Known animation duration | `pump(const Duration(milliseconds: 300))` |
| Unknown animation duration (dismiss, page transition) | `pumpAndSettle()` |
| Full app with ongoing timers / streams | `pump()` — never `pumpAndSettle()` |

```dart
// ✅ pump() for immediate state change
await tester.tap(find.byIcon(Icons.add));
await tester.pump();
expect(find.text('1'), findsOneWidget);

// ✅ pumpAndSettle() for dismiss animation
await tester.drag(find.byType(Dismissible), const Offset(500, 0));
await tester.pumpAndSettle();
expect(find.text('Item'), findsNothing);

// ❌ pumpAndSettle() on a full app — causes TimeoutException
await tester.pumpWidget(MyApp());
await tester.pumpAndSettle(); // WRONG — app never settles
```

---

## Common Finders

```dart
find.byType(CircularProgressIndicator)
find.byKey(const Key('product_title'))
find.text('Retry')
find.textContaining('Widget')
find.byIcon(Icons.refresh)
find.bySemanticsLabel('Add to cart')

// Descendant
find.descendant(
  of: find.byType(ProductCard),
  matching: find.byType(Text),
)

// Ancestor
find.ancestor(
  of: find.text('Widget'),
  matching: find.byType(Card),
)

// Counts
expect(find.byType(ListTile), findsWidgets);       // 1+
expect(find.byType(ListTile), findsNWidgets(3));   // exactly 3
expect(find.text('Missing'), findsNothing);
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

  when(() => mockBloc.state)
      .thenReturn(ProductState.success(products: [tProductVm]));
  await tester.pump();

  await tester.tap(find.byType(ProductCard).first);
  await tester.pumpAndSettle();

  verify(() => mockObserver.didPush(any(), any())).called(1);
});
```

---

## Testing with Network Images

```dart
testWidgets('shows product image', (tester) async {
  await mockNetworkImagesFor(() async {
    when(() => mockBloc.state)
        .thenReturn(ProductState.success(product: tProductVmWithImage));

    await tester.pumpWidget(buildSubject(mockBloc));

    expect(find.byType(Image), findsOneWidget);
  });
});
```

---

## Testing Accessibility

```dart
testWidgets('add to cart button has correct semantics', (tester) async {
  when(() => mockBloc.state)
      .thenReturn(ProductState.success(product: tProductVm));

  await tester.pumpWidget(buildSubject(mockBloc));

  final semantics = tester.getSemantics(find.byKey(const Key('add_to_cart')));
  expect(semantics.label, 'Add to cart');
  expect(semantics.hasFlag(SemanticsFlag.isButton), true);
});
```

---

## Testing Responsive Layout

```dart
testWidgets('adapts layout on small screen', (tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(buildSubject(mockBloc));

  // verify compact layout
  expect(find.byType(ProductCardCompact), findsOneWidget);
});
```

---

## Rules

- Always wrap the widget under test in `MaterialApp` (and `Scaffold` if needed)
- Use `MockBloc` from `bloc_test` — never instantiate a real BLoC in widget tests
- Test all BLoC states: initial, loading, success, error, empty
- Use `pump()` for state changes, `pumpAndSettle()` only for animations
- Test accessibility semantics for interactive widgets
- Use `network_image_mock` to prevent real network calls
