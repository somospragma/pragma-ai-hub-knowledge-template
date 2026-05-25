# One-Shot Isolates — compute() and Isolate.run()

For tasks that run once, return a result, and don't need to stay alive.
The isolate is created, executes the function, returns the result, and is killed automatically.

## Isolate.run() — Preferred (Dart 2.19+)

```dart
// Top-level or static function — required for isolates
// Annotate to prevent AOT tree-shaking
@pragma('vm:entry-point')
List<Product> _parseProducts(String rawJson) {
  final list = jsonDecode(rawJson) as List;
  return list.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
}

// In your data source or use case:
Future<List<Product>> parseProducts(String rawJson) async {
  // Runs in a new isolate — main thread stays free
  return Isolate.run(() => _parseProducts(rawJson));
}
```

```dart
// Multiple arguments — wrap in a record or map
@pragma('vm:entry-point')
List<Product> _filterAndSort(_FilterParams params) {
  return params.products
      .where((p) => p.categoryId == params.categoryId)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

// Pass a record (Dart 3+)
typedef _FilterParams = ({List<Product> products, String categoryId});

Future<List<Product>> filterAndSort(
  List<Product> products,
  String categoryId,
) async {
  return Isolate.run(
    () => _filterAndSort((products: products, categoryId: categoryId)),
  );
}
```

## compute() — Legacy Wrapper

`compute()` is a thin wrapper over `Isolate.run()`. Prefer `Isolate.run()` for new code.

```dart
// compute() signature: compute(topLevelFunction, singleArgument)
// Only accepts a single argument — use a record or map for multiple

@pragma('vm:entry-point')
String _encryptData(String plainText) {
  // CPU-intensive encryption
  return encrypt(plainText);
}

Future<String> encryptData(String plainText) =>
    compute(_encryptData, plainText);
```

## Clean Architecture Integration

```dart
// lib/features/product/data/datasources/product_parser.dart
import 'dart:isolate';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class ProductParser {

  /// Parse a large JSON payload off the main thread.
  Future<Either<ParseFailure, List<Product>>> parseProducts(
    String rawJson,
  ) async {
    try {
      final products = await Isolate.run(
        () => _parseProductsIsolate(rawJson),
      );
      return Right(products);
    } catch (e) {
      return Left(ParseFailure.invalidJson(message: '$e'));
    }
  }

  /// Process and transform a large list off the main thread.
  Future<Either<ParseFailure, List<Product>>> filterAndSort(
    List<Product> products,
    String categoryId,
  ) async {
    try {
      final result = await Isolate.run(
        () => _filterAndSortIsolate((
          products: products,
          categoryId: categoryId,
        )),
      );
      return Right(result);
    } catch (e) {
      return Left(ParseFailure.processingFailed(message: '$e'));
    }
  }
}

// ── Isolate entry points — top-level, outside any class ──────────────────────

@pragma('vm:entry-point')
List<Product> _parseProductsIsolate(String rawJson) {
  final list = jsonDecode(rawJson) as List;
  return list
      .map((e) => Product.fromJson(e as Map<String, dynamic>))
      .toList();
}

@pragma('vm:entry-point')
List<Product> _filterAndSortIsolate(
  ({List<Product> products, String categoryId}) params,
) {
  return params.products
      .where((p) => p.categoryId == params.categoryId)
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}
```

## BLoC Integration

```dart
// lib/features/product/presentation/bloc/product_bloc.dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final ProductRepository _repository;
  final ProductParser _parser;

  ProductBloc(this._repository, this._parser)
      : super(const ProductState.initial()) {
    on<LoadProductsEvent>(_onLoad);
  }

  Future<void> _onLoad(
    LoadProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    emit(const ProductState.loading());

    // 1. Fetch raw JSON from network (async, non-blocking)
    final rawResult = await _repository.fetchRawProducts();

    await rawResult.fold(
      (failure) async => emit(ProductState.error(failure.message)),
      (rawJson) async {
        // 2. Parse in isolate — main thread stays free
        final parseResult = await _parser.parseProducts(rawJson);

        parseResult.fold(
          (failure) => emit(ProductState.error(failure.message)),
          (products) => emit(ProductState.success(products: products)),
        );
      },
    );
  }
}
```

## Common Use Cases

```dart
// ── Image processing ──────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Uint8List _resizeImageIsolate(({Uint8List bytes, int targetWidth}) params) {
  // Use dart:ui or image package — no Flutter widgets
  final image = img.decodeImage(params.bytes)!;
  final resized = img.copyResize(image, width: params.targetWidth);
  return Uint8List.fromList(img.encodePng(resized));
}

Future<Uint8List> resizeImage(Uint8List bytes, int targetWidth) =>
    Isolate.run(() => _resizeImageIsolate((bytes: bytes, targetWidth: targetWidth)));

// ── Hashing / encryption ──────────────────────────────────────────────────────

@pragma('vm:entry-point')
String _hashPasswordIsolate(({String password, String salt}) params) {
  // bcrypt or argon2 — CPU-intensive
  return BCrypt.hashpw(params.password, params.salt);
}

Future<String> hashPassword(String password, String salt) =>
    Isolate.run(() => _hashPasswordIsolate((password: password, salt: salt)));

// ── CSV parsing ───────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
List<Map<String, String>> _parseCsvIsolate(String csvContent) {
  final lines = csvContent.split('\n');
  final headers = lines.first.split(',');
  return lines.skip(1).map((line) {
    final values = line.split(',');
    return Map.fromIterables(headers, values);
  }).toList();
}

Future<List<Map<String, String>>> parseCsv(String csvContent) =>
    Isolate.run(() => _parseCsvIsolate(csvContent));
```

## Testing

```dart
// Isolate.run() functions are just regular Dart functions — test them directly
void main() {
  group('ProductParser', () {
    test('parseProducts parses valid JSON', () async {
      const json = '[{"id":"1","name":"Test","price":9.99}]';
      // Test the isolate function directly — no need to spawn an isolate in tests
      final result = _parseProductsIsolate(json);
      expect(result.length, 1);
      expect(result.first.id, '1');
    });

    test('parseProducts returns failure for invalid JSON', () async {
      final parser = ProductParser();
      final result = await parser.parseProducts('invalid json');
      expect(result.isLeft(), true);
    });
  });
}
```
