# Streams with BLoC — Native, No rxdart

`flutter_bloc 9.x` + `bloc_concurrency` covers the most common reactive patterns
without any additional dependency.

```yaml
dependencies:
  flutter_bloc: ^9.1.1
  bloc_concurrency: ^0.3.0
```

---

## EventTransformer — The Core Concept

An `EventTransformer<E>` is a function that wraps the event stream before it
reaches the handler. It has the signature:

```dart
typedef EventTransformer<Event> =
    Stream<Event> Function(Stream<Event> events, EventMapper<Event> mapper);
```

`bloc_concurrency` ships four ready-made transformers:

```dart
import 'package:bloc_concurrency/bloc_concurrency.dart';

// sequential() — queue events, process one at a time (no overlap)
on<LoadPageEvent>(_onLoad, transformer: sequential());

// droppable() — ignore new events while one is processing
on<SubmitFormEvent>(_onSubmit, transformer: droppable());

// restartable() — cancel current handler, start new one (replaces switchMap)
on<SearchEvent>(_onSearch, transformer: restartable());

// concurrent() — process all events in parallel (default BLoC behavior)
on<TrackAnalyticsEvent>(_onTrack, transformer: concurrent());
```

---

## Debounce — Pure Dart, No rxdart

```dart
// lib/core/bloc/transformers.dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Debounce transformer: waits for silence before passing the event to the mapper.
/// Combine with restartable() for live search behavior.
EventTransformer<E> debounce<E>(Duration duration) {
  return (events, mapper) =>
      events.transform(_DebounceTransformer(duration)).asyncExpand(mapper);
}

class _DebounceTransformer<T> extends StreamTransformerBase<T, T> {
  final Duration duration;
  const _DebounceTransformer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    Timer? timer;

    controller = StreamController<T>(
      onListen: () {
        final sub = stream.listen(
          (event) {
            timer?.cancel();
            timer = Timer(duration, () {
              if (!controller.isClosed) controller.add(event);
            });
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            controller.close();
          },
        );
        controller.onCancel = sub.cancel;
      },
    );

    return controller.stream;
  }
}
```

### Combining debounce + restartable

```dart
// lib/core/bloc/transformers.dart (continued)

/// Debounce + restartable: wait for silence, then cancel previous and start new.
/// This is the idiomatic replacement for rxdart's debounceTime + switchMap.
EventTransformer<E> debounceRestartable<E>(Duration duration) {
  return (events, mapper) => restartable<E>()(
        events.transform(_DebounceTransformer(duration)),
        mapper,
      );
}
```

---

## Live Search — BLoC, No rxdart

```dart
// lib/features/search/presentation/bloc/search_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:fpdart/fpdart.dart';

part 'search_bloc.freezed.dart';
part 'search_event.dart';
part 'search_state.dart';

@injectable
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _repository;

  SearchBloc(this._repository) : super(const SearchState.idle()) {
    on<QueryChangedEvent>(
      _onQueryChanged,
      // ✅ debounce 300ms + cancel previous — no rxdart
      transformer: debounceRestartable(const Duration(milliseconds: 300)),
    );
    on<SearchClearedEvent>(_onCleared);
  }

  Future<void> _onQueryChanged(
    QueryChangedEvent event,
    Emitter<SearchState> emit,
  ) async {
    final query = event.query.trim();

    if (query.isEmpty) {
      emit(const SearchState.idle());
      return;
    }
    if (query.length < 2) return;

    emit(const SearchState.loading());

    final result = await _repository.search(query);
    result.fold(
      (failure) => emit(SearchState.error(failure.message)),
      (results) => emit(results.isEmpty
          ? const SearchState.empty()
          : SearchState.success(results: results)),
    );
  }

  void _onCleared(SearchClearedEvent event, Emitter<SearchState> emit) {
    emit(const SearchState.idle());
  }
}

// search_event.dart
part of 'search_bloc.dart';

@freezed
class SearchEvent with _$SearchEvent {
  const factory SearchEvent.queryChanged(String query) = QueryChangedEvent;
  const factory SearchEvent.cleared() = SearchClearedEvent;
}

// search_state.dart
part of 'search_bloc.dart';

@freezed
class SearchState with _$SearchState {
  const factory SearchState.idle() = SearchIdle;
  const factory SearchState.loading() = SearchLoading;
  const factory SearchState.success({required List<SearchResult> results}) = SearchSuccess;
  const factory SearchState.empty() = SearchEmpty;
  const factory SearchState.error(String message) = SearchError;
}
```

---

## Watching a Stream Inside a BLoC — emit.forEach

`emit.forEach` subscribes to a stream and maps each event to a state.
The subscription is automatically cancelled when the event handler completes
or the BLoC is closed.

```dart
// lib/features/product/presentation/bloc/product_bloc.dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final ProductRepository _repository;

  ProductBloc(this._repository) : super(const ProductState.initial()) {
    on<WatchProductsEvent>(_onWatch);
    on<RefreshEvent>(_onRefresh);
  }

  Future<void> _onWatch(
    WatchProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    emit(const ProductState.loading());

    // ✅ emit.forEach — subscribes to stream, maps events to states
    // Subscription is cancelled automatically when handler completes
    await emit.forEach<Either<Failure, List<Product>>>(
      _repository.watchProducts(event.categoryId),
      onData: (result) => result.fold(
        (failure) => ProductState.error(failure.message),
        (products) => ProductState.success(products: products),
      ),
      onError: (error, _) => ProductState.error('$error'),
    );
  }

  Future<void> _onRefresh(
    RefreshEvent event,
    Emitter<ProductState> emit,
  ) async {
    // Trigger a new WatchProductsEvent — previous stream is cancelled
    add(ProductEvent.watchProducts(event.categoryId));
  }
}
```

---

## Multi-Stream Combination — Native Dart

Without rxdart's `combineLatest`, use `StreamZip` or manual `StreamController`:

```dart
// lib/features/dashboard/data/repositories/dashboard_repository_impl.dart

/// Combine two streams using StreamZip (native Dart).
/// Emits when BOTH streams have emitted — pairs by index.
Stream<DashboardData> watchDashboard() {
  return StreamZip([
    _userRepo.watchCurrentUser(),
    _cartRepo.watchCart(),
  ]).map((values) => DashboardData(
    user: values[0] as User,
    cart: values[1] as Cart,
  ));
}

/// Combine with latest-value semantics — manual broadcast controller.
Stream<DashboardData> watchDashboardLatest() {
  User? latestUser;
  Cart? latestCart;
  final controller = StreamController<DashboardData>.broadcast();

  void tryEmit() {
    if (latestUser != null && latestCart != null) {
      controller.add(DashboardData(user: latestUser!, cart: latestCart!));
    }
  }

  final userSub = _userRepo.watchCurrentUser().listen((u) {
    latestUser = u;
    tryEmit();
  });
  final cartSub = _cartRepo.watchCart().listen((c) {
    latestCart = c;
    tryEmit();
  });

  controller.onCancel = () {
    userSub.cancel();
    cartSub.cancel();
  };

  return controller.stream;
}
```

---

## BLoC with Multi-Stream — emit.onEach

```dart
// lib/features/dashboard/presentation/bloc/dashboard_bloc.dart
@injectable
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardRepository _repository;

  DashboardBloc(this._repository) : super(const DashboardState.loading()) {
    on<InitializeDashboardEvent>(_onInitialize);
    on<DashboardDataUpdatedEvent>(_onDataUpdated);
  }

  Future<void> _onInitialize(
    InitializeDashboardEvent event,
    Emitter<DashboardState> emit,
  ) async {
    await emit.forEach<DashboardData>(
      _repository.watchDashboardLatest(),
      onData: (data) => DashboardState.success(data: data),
      onError: (e, _) => DashboardState.error('$e'),
    );
  }
}
```

---

## Testing BLoC Streams

```dart
// test/features/search/presentation/bloc/search_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fpdart/fpdart.dart';

class MockSearchRepository extends Mock implements SearchRepository {}

void main() {
  late SearchBloc bloc;
  late MockSearchRepository mockRepo;

  setUp(() {
    mockRepo = MockSearchRepository();
    bloc = SearchBloc(mockRepo);
  });

  tearDown(() => bloc.close());

  group('SearchBloc', () {
    blocTest<SearchBloc, SearchState>(
      'emits idle when query is empty',
      build: () => bloc,
      act: (b) => b.add(const SearchEvent.queryChanged('')),
      expect: () => [const SearchState.idle()],
    );

    blocTest<SearchBloc, SearchState>(
      'emits [loading, success] after debounce',
      build: () {
        when(() => mockRepo.search('flutter')).thenAnswer(
          (_) async => Right([SearchResult(id: '1', title: 'Flutter')]),
        );
        return bloc;
      },
      act: (b) => b.add(const SearchEvent.queryChanged('flutter')),
      wait: const Duration(milliseconds: 350), // wait for debounce
      expect: () => [
        const SearchState.loading(),
        isA<SearchSuccess>(),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'only last query is processed when typing fast',
      build: () {
        when(() => mockRepo.search('dart')).thenAnswer(
          (_) async => Right([SearchResult(id: '2', title: 'Dart')]),
        );
        return bloc;
      },
      act: (b) async {
        b.add(const SearchEvent.queryChanged('d'));
        b.add(const SearchEvent.queryChanged('da'));
        b.add(const SearchEvent.queryChanged('dar'));
        b.add(const SearchEvent.queryChanged('dart'));
      },
      wait: const Duration(milliseconds: 350),
      expect: () => [
        const SearchState.loading(),
        isA<SearchSuccess>(), // only 'dart' was searched
      ],
      verify: (_) => verify(() => mockRepo.search('dart')).called(1),
    );
  });
}
```
