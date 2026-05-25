# BLoC Reactive Patterns

Complete reactive patterns using BLoC 9.x — from stream subscription to UI.

---

## emit.forEach — The Reactive Core

`emit.forEach` subscribes to a stream and maps each event to a state.
The subscription is automatically cancelled when the event handler completes
or the BLoC is closed. This is the idiomatic way to react to streams in BLoC.

```dart
// lib/features/product/presentation/bloc/product_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';

part 'product_bloc.freezed.dart';
part 'product_event.dart';
part 'product_state.dart';

@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final WatchProductsUseCase _watchProducts;
  final SaveProductUseCase _saveProduct;

  ProductBloc(this._watchProducts, this._saveProduct)
      : super(const ProductState.initial()) {
    on<WatchProductsEvent>(_onWatch);
    on<SaveProductEvent>(_onSave, transformer: droppable());
  }

  Future<void> _onWatch(
    WatchProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    emit(const ProductState.loading());

    // ✅ emit.forEach — subscribes to stream, maps events to states
    // Subscription cancelled automatically when handler completes or BLoC closes
    await emit.forEach<Either<Failure, List<Product>>>(
      _watchProducts(categoryId: event.categoryId),
      onData: (result) => result.fold(
        (failure) => ProductState.error(failure.message),
        (products) => products.isEmpty
            ? const ProductState.empty()
            : ProductState.success(products: products),
      ),
      onError: (error, _) => ProductState.error('$error'),
    );
  }

  Future<void> _onSave(
    SaveProductEvent event,
    Emitter<ProductState> emit,
  ) async {
    final result = await _saveProduct(event.product);
    // ✅ No need to reload — watchProducts stream emits automatically after save
    result.fold(
      (failure) => emit(ProductState.error(failure.message)),
      (_) => null, // stream will emit updated list
    );
  }
}

// product_event.dart
part of 'product_bloc.dart';

@freezed
class ProductEvent with _$ProductEvent {
  const factory ProductEvent.watchProducts({required String categoryId}) =
      WatchProductsEvent;
  const factory ProductEvent.saveProduct(Product product) = SaveProductEvent;
}

// product_state.dart
part of 'product_bloc.dart';

@freezed
class ProductState with _$ProductState {
  const factory ProductState.initial() = ProductInitial;
  const factory ProductState.loading() = ProductLoading;
  const factory ProductState.empty() = ProductEmpty;
  const factory ProductState.success({required List<Product> products}) =
      ProductSuccess;
  const factory ProductState.error(String message) = ProductError;
}
```

---

## Reactive Product Detail — Watch Single Item

```dart
// lib/features/product/presentation/bloc/product_detail_bloc.dart
@injectable
class ProductDetailBloc extends Bloc<ProductDetailEvent, ProductDetailState> {
  final WatchProductUseCase _watchProduct;
  final UpdateProductUseCase _updateProduct;

  ProductDetailBloc(this._watchProduct, this._updateProduct)
      : super(const ProductDetailState.loading()) {
    on<WatchProductDetailEvent>(_onWatch);
    on<UpdateProductEvent>(_onUpdate, transformer: droppable());
  }

  Future<void> _onWatch(
    WatchProductDetailEvent event,
    Emitter<ProductDetailState> emit,
  ) async {
    await emit.forEach<Either<Failure, Product>>(
      _watchProduct(event.productId),
      onData: (result) => result.fold(
        (failure) => ProductDetailState.error(failure.message),
        (product) => ProductDetailState.success(product: product),
      ),
    );
  }

  Future<void> _onUpdate(
    UpdateProductEvent event,
    Emitter<ProductDetailState> emit,
  ) async {
    // Optimistic: UI already shows the update via the watch stream
    final result = await _updateProduct(event.product);
    result.fold(
      (failure) => emit(ProductDetailState.error(failure.message)),
      (_) => null, // watch stream emits confirmed data
    );
  }
}
```

---

## Reactive Authentication — Full Flow

```dart
// lib/features/auth/presentation/bloc/auth_bloc.dart
@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repository;

  AuthBloc(this._repository) : super(const AuthState.initial()) {
    on<WatchAuthStateEvent>(_onWatchAuth);
    on<SignInEvent>(_onSignIn, transformer: droppable());
    on<SignOutEvent>(_onSignOut, transformer: droppable());
  }

  Future<void> _onWatchAuth(
    WatchAuthStateEvent event,
    Emitter<AuthState> emit,
  ) async {
    // ✅ Reacts to auth changes: login, logout, token expiry, app resume
    await emit.forEach<AuthStatus>(
      _repository.watchAuthState(),
      onData: (status) => status.when(
        authenticated: (user) => AuthState.authenticated(user: user),
        unauthenticated: () => const AuthState.unauthenticated(),
        loading: () => const AuthState.loading(),
      ),
    );
  }

  Future<void> _onSignIn(
    SignInEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthState.loading());
    final result = await _repository.signIn(event.email, event.password);
    result.fold(
      (failure) => emit(AuthState.error(failure.message)),
      (_) => null, // watchAuthState stream emits authenticated state
    );
  }

  Future<void> _onSignOut(
    SignOutEvent event,
    Emitter<AuthState> emit,
  ) async {
    await _repository.signOut();
    // watchAuthState stream emits unauthenticated state automatically
  }
}
```

---

## Reactive Real-Time Chat

```dart
// lib/features/chat/presentation/bloc/chat_bloc.dart
@injectable
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _repository;

  ChatBloc(this._repository) : super(const ChatState.loading()) {
    on<WatchMessagesEvent>(_onWatch);
    on<SendMessageEvent>(_onSend, transformer: sequential()); // queue messages
  }

  Future<void> _onWatch(
    WatchMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    await emit.forEach<Either<Failure, List<Message>>>(
      _repository.watchMessages(event.roomId),
      onData: (result) => result.fold(
        (failure) => ChatState.error(failure.message),
        (messages) => ChatState.success(
          messages: messages,
          roomId: event.roomId,
        ),
      ),
    );
  }

  Future<void> _onSend(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    // Optimistic: add message locally first
    final current = state;
    if (current is ChatSuccess) {
      final optimistic = Message.pending(
        id: DateTime.now().toIso8601String(),
        text: event.text,
        senderId: event.senderId,
      );
      emit(current.copyWith(
        messages: [...current.messages, optimistic],
      ));
    }

    final result = await _repository.sendMessage(
      roomId: event.roomId,
      text: event.text,
    );

    result.fold(
      (failure) {
        // Remove optimistic message on failure
        if (current is ChatSuccess) emit(current);
        emit(ChatState.error(failure.message));
      },
      (_) => null, // watch stream emits confirmed message
    );
  }
}
```

---

## Reactive Dashboard — Multiple Streams

```dart
// lib/features/dashboard/presentation/bloc/dashboard_bloc.dart
@injectable
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final UserRepository _userRepo;
  final CartRepository _cartRepo;
  final NotificationRepository _notifRepo;

  StreamSubscription<DashboardData>? _dataSub;

  DashboardBloc(this._userRepo, this._cartRepo, this._notifRepo)
      : super(const DashboardState.loading()) {
    on<InitializeDashboardEvent>(_onInit);
    on<DashboardDataUpdatedEvent>(_onUpdated);
  }

  Future<void> _onInit(
    InitializeDashboardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    await _dataSub?.cancel();

    // Combine multiple reactive streams using native Dart combineLatest helper
    _dataSub = combineLatestDashboard(
      _userRepo.watchCurrentUser(),
      _cartRepo.watchCart(),
      _notifRepo.watchUnreadCount(),
    ).listen(
      (data) => add(DashboardEvent.dataUpdated(data)),
      onError: (e) => emit(DashboardState.error('$e')),
      cancelOnError: false,
    );
  }

  void _onUpdated(
    DashboardDataUpdatedEvent event,
    Emitter<DashboardState> emit,
  ) {
    emit(DashboardState.success(data: event.data));
  }

  @override
  Future<void> close() async {
    await _dataSub?.cancel();
    return super.close();
  }
}

// Native Dart combineLatest (no rxdart)
Stream<DashboardData> combineLatestDashboard(
  Stream<User> userStream,
  Stream<Cart> cartStream,
  Stream<int> unreadStream,
) {
  User? user;
  Cart? cart;
  int? unread;
  final controller = StreamController<DashboardData>.broadcast();

  void tryEmit() {
    if (user != null && cart != null && unread != null) {
      controller.add(DashboardData(user: user!, cart: cart!, unreadNotifications: unread!));
    }
  }

  final subs = [
    userStream.listen((u) { user = u; tryEmit(); }),
    cartStream.listen((c) { cart = c; tryEmit(); }),
    unreadStream.listen((n) { unread = n; tryEmit(); }),
  ];

  controller.onCancel = () { for (final s in subs) s.cancel(); };
  return controller.stream;
}
```

---

## Widget — Reactive UI

```dart
// lib/features/product/presentation/pages/product_list_page.dart
class ProductListPage extends StatelessWidget {
  final String categoryId;
  const ProductListPage({required this.categoryId, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.instance<ProductBloc>()
        ..add(ProductEvent.watchProducts(categoryId: categoryId)),
      child: const _ProductListView(),
    );
  }
}

class _ProductListView extends StatelessWidget {
  const _ProductListView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductBloc, ProductState>(
      // ✅ Only rebuild when state TYPE changes — not on every emission
      buildWhen: (prev, curr) => prev.runtimeType != curr.runtimeType,
      builder: (context, state) => switch (state) {
        ProductLoading() => const Center(child: CircularProgressIndicator()),
        ProductEmpty() => const Center(child: Text('No products')),
        ProductSuccess(:final products) => _ProductList(products: products),
        ProductError(:final message) => Center(child: Text(message)),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
```

---

## Testing BLoC Reactive Patterns

```dart
// test/features/product/presentation/bloc/product_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockWatchProductsUseCase extends Mock implements WatchProductsUseCase {}
class MockSaveProductUseCase extends Mock implements SaveProductUseCase {}

void main() {
  late ProductBloc bloc;
  late MockWatchProductsUseCase mockWatch;
  late MockSaveProductUseCase mockSave;

  setUp(() {
    mockWatch = MockWatchProductsUseCase();
    mockSave = MockSaveProductUseCase();
    bloc = ProductBloc(mockWatch, mockSave);
  });

  tearDown(() => bloc.close());

  group('ProductBloc reactive', () {
    final products = [Product(id: 'p1', name: 'Test', price: 9.99)];

    blocTest<ProductBloc, ProductState>(
      'emits [loading, success] when stream emits products',
      build: () {
        when(() => mockWatch(categoryId: 'cat1')).thenAnswer(
          (_) => Stream.value(Right(products)),
        );
        return bloc;
      },
      act: (b) => b.add(const ProductEvent.watchProducts(categoryId: 'cat1')),
      expect: () => [
        const ProductState.loading(),
        ProductState.success(products: products),
      ],
    );

    blocTest<ProductBloc, ProductState>(
      'emits error when stream emits failure',
      build: () {
        when(() => mockWatch(categoryId: 'cat1')).thenAnswer(
          (_) => Stream.value(const Left(Failure.network(message: 'Offline'))),
        );
        return bloc;
      },
      act: (b) => b.add(const ProductEvent.watchProducts(categoryId: 'cat1')),
      expect: () => [
        const ProductState.loading(),
        const ProductState.error('Offline'),
      ],
    );

    blocTest<ProductBloc, ProductState>(
      'reacts to multiple stream emissions',
      build: () {
        when(() => mockWatch(categoryId: 'cat1')).thenAnswer(
          (_) => Stream.fromIterable([
            Right(products),
            Right([...products, Product(id: 'p2', name: 'New', price: 5.0)]),
          ]),
        );
        return bloc;
      },
      act: (b) => b.add(const ProductEvent.watchProducts(categoryId: 'cat1')),
      expect: () => [
        const ProductState.loading(),
        ProductState.success(products: products),
        isA<ProductSuccess>().having((s) => s.products.length, 'length', 2),
      ],
    );
  });
}
```
