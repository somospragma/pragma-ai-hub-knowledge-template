# BLoC Testing Patterns — bloc_test 9.1.7

## blocTest — Core Patterns

```dart
import 'package:bloc_test/bloc_test.dart';

// ─── Basic success flow ──────────────────────────────────────────────────
blocTest<LoginBloc, LoginState>(
  'emits [loading, success] when credentials are valid',
  build: () {
    when(() => mockLoginUseCase(any()))
        .thenAnswer((_) async => Right(tUser));
    return LoginBloc(mockLoginUseCase, mockLogoutUseCase);
  },
  act: (bloc) => bloc.add(LoginEvent.loginRequested(
    email: 'user@test.com',
    password: 'Pass123!',
  )),
  expect: () => [
    const LoginState.loading(),
    LoginState.success(user: tUser),
  ],
  verify: (_) {
    verify(() => mockLoginUseCase(any())).called(1);
    verifyNoMoreInteractions(mockLoginUseCase);
  },
);

// ─── Error flow ──────────────────────────────────────────────────────────
blocTest<LoginBloc, LoginState>(
  'emits [loading, error] on NetworkFailure',
  build: () {
    when(() => mockLoginUseCase(any())).thenAnswer(
      (_) async => const Left(Failure.network(message: 'No connection')),
    );
    return LoginBloc(mockLoginUseCase, mockLogoutUseCase);
  },
  act: (bloc) => bloc.add(LoginEvent.loginRequested(
    email: 'user@test.com',
    password: 'Pass123!',
  )),
  expect: () => [
    const LoginState.loading(),
    isA<LoginState>().having(
      (s) => s.mapOrNull(error: (e) => e.message),
      'error message',
      'No connection',
    ),
  ],
);

// ─── No emissions ────────────────────────────────────────────────────────
blocTest<SearchBloc, SearchState>(
  'emits nothing when query is too short',
  build: () => SearchBloc(mockSearchUseCase),
  act: (bloc) => bloc.add(const SearchEvent.queryChanged(query: 'a')),
  expect: () => [],
);

// ─── Multiple events ─────────────────────────────────────────────────────
blocTest<CartBloc, CartState>(
  'accumulates items on multiple add events',
  build: () {
    when(() => mockAddItem(any())).thenAnswer((_) async => const Right(null));
    when(() => mockGetCart()).thenAnswer((_) async => Right(tCart));
    return CartBloc(mockAddItem, mockGetCart);
  },
  act: (bloc) async {
    bloc.add(CartEvent.itemAdded(productId: '1'));
    bloc.add(CartEvent.itemAdded(productId: '2'));
  },
  expect: () => [
    const CartState.loading(),
    isA<CartState>(),
    const CartState.loading(),
    isA<CartState>(),
  ],
);

// ─── Seed state ──────────────────────────────────────────────────────────
blocTest<ProductBloc, ProductState>(
  'can refresh from success state',
  seed: () => ProductState.success(product: tViewModel),
  build: () {
    when(() => mockGetProduct(any())).thenAnswer((_) async => Right(tProduct));
    return ProductBloc(mockGetProduct);
  },
  act: (bloc) => bloc.add(ProductEvent.refreshRequested(id: '1')),
  expect: () => [
    const ProductState.loading(),
    isA<ProductState>().having(
      (s) => s.mapOrNull(success: (_) => true),
      'is success',
      true,
    ),
  ],
);

// ─── Wait for async (debounce) ───────────────────────────────────────────
blocTest<SearchBloc, SearchState>(
  'emits after debounce delay',
  build: () {
    when(() => mockSearch(any())).thenAnswer((_) async => Right(tResults));
    return SearchBloc(mockSearch);
  },
  act: (bloc) => bloc.add(const SearchEvent.queryChanged(query: 'flutter')),
  wait: const Duration(milliseconds: 350), // wait for debounce
  expect: () => [
    const SearchState.loading(),
    isA<SearchState>(),
  ],
);
```

---

## whenListen — Stream-based BLoC Tests

```dart
// Mock BLoC for widget tests
class MockChatBloc extends MockBloc<ChatEvent, ChatState> implements ChatBloc {}

void main() {
  late MockChatBloc mockBloc;
  setUp(() => mockBloc = MockChatBloc());

  testWidgets('shows messages as stream emits', (tester) async {
    whenListen(
      mockBloc,
      Stream.fromIterable([
        const ChatState.loading(),
        ChatState.success(messages: [tMessage1]),
        ChatState.success(messages: [tMessage1, tMessage2]),
      ]),
      initialState: const ChatState.initial(),
    );

    await tester.pumpWidget(
      BlocProvider<ChatBloc>.value(
        value: mockBloc,
        child: const ChatView(),
      ),
    );

    await tester.pump(); // loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(); // 1 message
    expect(find.byType(MessageBubble), findsOneWidget);

    await tester.pump(); // 2 messages
    expect(find.byType(MessageBubble), findsNWidgets(2));
  });
}
```

---

## Testing with fake_async

```dart
import 'package:fake_async/fake_async.dart';

test('cancels search on new query', () {
  fakeAsync((async) {
    final bloc = SearchBloc(mockSearch);

    bloc.add(const SearchEvent.queryChanged(query: 'flutter'));
    async.elapse(const Duration(milliseconds: 100)); // before debounce

    bloc.add(const SearchEvent.queryChanged(query: 'flutter bloc'));
    async.elapse(const Duration(milliseconds: 400)); // after debounce

    // Only one search for the final query
    verify(() => mockSearch(SearchParams(query: 'flutter bloc'))).called(1);
    verifyNever(() => mockSearch(SearchParams(query: 'flutter')));

    bloc.close();
    async.flushMicrotasks();
  });
});
```

---

## BLoC Lifecycle Testing

```dart
test('cancels stream subscription on close', () async {
  final streamController = StreamController<Either<Failure, List<Message>>>();

  when(() => mockRepo.watchMessages(any()))
      .thenAnswer((_) => streamController.stream);

  final bloc = ChatBloc(mockRepo)
    ..add(const ChatEvent.watchStarted(chatId: 'room1'));

  await Future<void>.delayed(const Duration(milliseconds: 10));

  await bloc.close();

  // Adding to stream after close should not throw
  expect(
    () => streamController.add(Right([])),
    returnsNormally,
  );

  await streamController.close();
});
```

---

## Testing onDone

```dart
test('calls onDone when bloc is closed', () async {
  var doneCalled = false;
  final bloc = TestableBloc(
    onDoneCallback: () => doneCalled = true,
  );

  await bloc.close();

  expect(doneCalled, isTrue);
});

// Testable BLoC that exposes onDone
class TestableBloc extends Bloc<TestEvent, TestState> {
  TestableBloc({required this.onDoneCallback})
      : super(const TestState.initial()) {
    on<_Started>(_onStarted);
  }

  final void Function() onDoneCallback;

  @override
  void onDone() {
    onDoneCallback();
    super.onDone();
  }

  Future<void> _onStarted(_Started event, Emitter<TestState> emit) async {}
}
```

---

## Testing MultiBlocObserver

```dart
test('MultiBlocObserver notifies all observers on error', () {
  final observer1 = MockBlocObserver();
  final observer2 = MockBlocObserver();

  Bloc.observer = MultiBlocObserver(
    observers: [observer1, observer2],
  );

  final bloc = LoginBloc(mockLoginUseCase, mockLogoutUseCase);
  final error = Exception('test error');
  final stackTrace = StackTrace.current;

  bloc.addError(error, stackTrace);

  verify(() => observer1.onError(bloc, error, stackTrace)).called(1);
  verify(() => observer2.onError(bloc, error, stackTrace)).called(1);
});
```
