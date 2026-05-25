# Repository Pattern & Testing

Clean architecture integration for any local database choice.

**Rule: Never expose database-specific types (rows, entities, companions) outside the data layer.**
Always map to domain entities at the repository boundary.

## Domain Repository Interface

```dart
// lib/features/product/domain/repositories/product_repository.dart
import 'package:fpdart/fpdart.dart';

abstract interface class ProductRepository {
  Stream<Either<Failure, List<Product>>> watchProducts();
  Stream<Either<Failure, List<Product>>> watchByCategory(String categoryId);
  Future<Either<Failure, Product>> getProduct(String id);
  Future<Either<Failure, Unit>> saveProduct(Product product);
  Future<Either<Failure, Unit>> saveAll(List<Product> products);
  Future<Either<Failure, Unit>> deleteProduct(String id);
  Future<Either<Failure, List<Product>>> searchProducts(String query);
}
```

## Repository Implementation (Drift example)

```dart
// lib/features/product/data/repositories/product_repository_impl.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@Injectable(as: ProductRepository)
class ProductRepositoryImpl implements ProductRepository {
  final ProductDao _dao;
  final ProductMapper _mapper;

  ProductRepositoryImpl(this._dao, this._mapper);

  @override
  Stream<Either<Failure, List<Product>>> watchProducts() =>
      _dao.watchAll().map(
        (rows) => Right<Failure, List<Product>>(
          rows.map(_mapper.fromRow).toList(),
        ),
      );

  @override
  Stream<Either<Failure, List<Product>>> watchByCategory(String categoryId) =>
      _dao.watchByCategory(categoryId).map(
        (rows) => Right<Failure, List<Product>>(
          rows.map(_mapper.fromRow).toList(),
        ),
      );

  @override
  Future<Either<Failure, Product>> getProduct(String id) async {
    try {
      final row = await _dao.findById(id);
      if (row == null) return Left(Failure.notFound(id: id));
      return Right(_mapper.fromRow(row));
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveProduct(Product product) async {
    try {
      await _dao.upsert(_mapper.toCompanion(product));
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> saveAll(List<Product> products) async {
    try {
      await _dao.upsertAll(products.map(_mapper.toCompanion).toList());
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteProduct(String id) async {
    try {
      await _dao.deleteById(id);
      return const Right(unit);
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }

  @override
  Future<Either<Failure, List<Product>>> searchProducts(String query) async {
    try {
      final rows = await (_dao.db.select(_dao.db.products)
            ..where((t) => t.name.like('%$query%')))
          .get();
      return Right(rows.map(_mapper.fromRow).toList());
    } catch (e) {
      return Left(Failure.local(message: '$e'));
    }
  }
}
```

## Testing with Drift In-Memory Database

```dart
// test/features/product/data/repositories/product_repository_impl_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

// In-memory database — no file I/O, fast, isolated per test
AppDatabase createTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late ProductDao dao;
  late ProductMapper mapper;
  late ProductRepositoryImpl repository;

  setUp(() {
    db = createTestDatabase();
    dao = ProductDao(db);
    mapper = ProductMapper();
    repository = ProductRepositoryImpl(dao, mapper);
  });

  tearDown(() => db.close());

  group('ProductRepository', () {
    test('watchProducts emits empty list initially', () async {
      final first = await repository.watchProducts().first;
      expect(first, const Right([]));
    });

    test('saveProduct persists and watchProducts emits it', () async {
      final product = Product(
        id: 'p1', name: 'Test Product', price: 9.99,
        stock: 10, categoryId: 'cat1', updatedAt: DateTime.now(),
      );

      await repository.saveProduct(product);

      final result = await repository.watchProducts().first;
      expect(result.isRight(), true);
      expect(result.getOrElse((_) => []).first.id, 'p1');
    });

    test('saveAll persists multiple products', () async {
      final products = List.generate(5, (i) => Product(
        id: 'p$i', name: 'Product $i', price: i * 10.0,
        stock: i, categoryId: 'cat1', updatedAt: DateTime.now(),
      ));

      final result = await repository.saveAll(products);
      expect(result, const Right(unit));

      final saved = await repository.watchProducts().first;
      expect(saved.getOrElse((_) => []).length, 5);
    });

    test('deleteProduct removes the product', () async {
      await repository.saveProduct(Product(
        id: 'p1', name: 'To Delete', price: 5.0,
        stock: 1, categoryId: 'cat1', updatedAt: DateTime.now(),
      ));

      await repository.deleteProduct('p1');

      final result = await repository.getProduct('p1');
      expect(result.isLeft(), true);
    });

    test('watchByCategory filters correctly', () async {
      await repository.saveAll([
        Product(id: 'p1', name: 'A', price: 1, stock: 1, categoryId: 'cat1', updatedAt: DateTime.now()),
        Product(id: 'p2', name: 'B', price: 2, stock: 1, categoryId: 'cat2', updatedAt: DateTime.now()),
      ]);

      final result = await repository.watchByCategory('cat1').first;
      expect(result.getOrElse((_) => []).length, 1);
      expect(result.getOrElse((_) => []).first.id, 'p1');
    });
  });
}
```

## Testing with Mocked Repository (UseCase tests)

```dart
// test/features/product/domain/usecases/get_product_usecase_test.dart
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

class MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late GetProductUseCase useCase;
  late MockProductRepository mockRepository;

  setUp(() {
    mockRepository = MockProductRepository();
    useCase = GetProductUseCase(mockRepository);
  });

  test('returns product when found', () async {
    const product = Product(id: 'p1', name: 'Test', price: 9.99, stock: 1,
        categoryId: 'cat1', updatedAt: null);

    when(() => mockRepository.getProduct('p1'))
        .thenAnswer((_) async => const Right(product));

    final result = await useCase('p1');
    expect(result, const Right(product));
  });

  test('returns failure when not found', () async {
    when(() => mockRepository.getProduct('missing'))
        .thenAnswer((_) async => const Left(Failure.notFound(id: 'missing')));

    final result = await useCase('missing');
    expect(result.isLeft(), true);
  });
}
```
