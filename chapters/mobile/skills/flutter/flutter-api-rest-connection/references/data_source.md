# DataSource Patterns — CRUD, Upload, Cancellation

## RemoteDataSource — Standard CRUD

```dart
// lib/{feature}/data/data_sources/remote/product_data_source.dart
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

abstract interface class ProductRemoteDataSource {
  Future<ProductModel> getProduct(String id);
  Future<List<ProductModel>> getProducts({
    required int page,
    required int limit,
    String? categoryId,
    CancelToken? cancelToken,
  });
  Future<ProductModel> createProduct(CreateProductRequest request);
  Future<ProductModel> updateProduct(String id, UpdateProductRequest request);
  Future<void> deleteProduct(String id);
}

@LazySingleton(as: ProductRemoteDataSource)
class ProductRemoteDataSourceImpl implements ProductRemoteDataSource {
  ProductRemoteDataSourceImpl(this._client);
  final ApiClient _client;

  @override
  Future<ProductModel> getProduct(String id) async {
    final response = await _client.get<Map<String, dynamic>>('/products/$id');
    return ProductModel.fromJson(response.data!);
  }

  @override
  Future<List<ProductModel>> getProducts({
    required int page,
    required int limit,
    String? categoryId,
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/products',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (categoryId != null) 'category_id': categoryId,
      },
      cancelToken: cancelToken,
    );
    final list = response.data!['data'] as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(ProductModel.fromJson)
        .toList();
  }

  @override
  Future<ProductModel> createProduct(CreateProductRequest request) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/products',
      data: request.toJson(),
    );
    return ProductModel.fromJson(response.data!);
  }

  @override
  Future<ProductModel> updateProduct(
    String id,
    UpdateProductRequest request,
  ) async {
    final response = await _client.patch<Map<String, dynamic>>(
      '/products/$id',
      data: request.toJson(),
    );
    return ProductModel.fromJson(response.data!);
  }

  @override
  Future<void> deleteProduct(String id) =>
      _client.delete<void>('/products/$id');
}
```

---

## Multipart File Upload with Progress

```dart
// lib/{feature}/data/data_sources/remote/media_data_source.dart
abstract interface class MediaRemoteDataSource {
  Stream<UploadProgress> uploadImage({
    required File file,
    required String productId,
    CancelToken? cancelToken,
  });
}

@LazySingleton(as: MediaRemoteDataSource)
class MediaRemoteDataSourceImpl implements MediaRemoteDataSource {
  MediaRemoteDataSourceImpl(this._client);
  final ApiClient _client;

  @override
  Stream<UploadProgress> uploadImage({
    required File file,
    required String productId,
    CancelToken? cancelToken,
  }) async* {
    final fileName = path.basename(file.path);
    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';

    yield UploadProgress.started(fileName: fileName);

    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      ),
      'product_id': productId,
    });

    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/media/upload',
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total > 0) {
            yield UploadProgress.uploading(
              fileName: fileName,
              progress: sent / total,
              sentBytes: sent,
              totalBytes: total,
            );
          }
        },
      );

      final url = response.data!['url'] as String;
      yield UploadProgress.completed(fileName: fileName, url: url);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        yield UploadProgress.cancelled(fileName: fileName);
      } else {
        yield UploadProgress.failed(
          fileName: fileName,
          error: (e.error as AppException?)?.when(
                network: (m) => m ?? 'Network error',
                timeout: (m) => m ?? 'Upload timed out',
                server: (m, _) => m ?? 'Server error',
                unknown: (m, _) => m ?? 'Upload failed',
                orElse: () => 'Upload failed',
              ) ??
              'Upload failed',
        );
      }
    }
  }
}
```

---

## Request Cancellation in BLoC

```dart
// lib/{feature}/presentation/bloc/product_bloc.dart
@injectable
class ProductBloc extends Bloc<ProductEvent, ProductState> {
  final GetProductsUseCase _getProducts;
  CancelToken? _cancelToken;

  ProductBloc(this._getProducts) : super(const ProductState.initial()) {
    on<LoadProductsEvent>(
      _onLoad,
      transformer: restartable(), // cancels previous handler on new event
    );
  }

  Future<void> _onLoad(
    LoadProductsEvent event,
    Emitter<ProductState> emit,
  ) async {
    // Cancel any in-flight request from the previous handler
    _cancelToken?.cancel('New request started');
    _cancelToken = CancelToken();

    emit(const ProductState.loading());

    final result = await _getProducts(
      GetProductsParams(
        categoryId: event.categoryId,
        cancelToken: _cancelToken,
      ),
    );

    result.fold(
      (failure) {
        // Silently ignore cancellation — a new request is already in flight
        if (failure is! NetworkFailure || !(_cancelToken?.isCancelled ?? false)) {
          emit(ProductState.error(failure.message ?? 'Error'));
        }
      },
      (products) => emit(ProductState.success(products: products)),
    );
  }

  @override
  Future<void> close() async {
    _cancelToken?.cancel('BLoC closed');
    return super.close();
  }
}
```

---

## Paginated Response Pattern

```dart
// lib/core/network/models/paginated_response.dart
@freezed
class PaginatedResponse<T> with _$PaginatedResponse<T> {
  const factory PaginatedResponse({
    required List<T> data,
    required int total,
    required int page,
    required int limit,
    required bool hasNextPage,
  }) = _PaginatedResponse<T>;

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object?) fromJsonT,
  ) =>
      PaginatedResponse(
        data: (json['data'] as List).map(fromJsonT).toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        limit: json['limit'] as int,
        hasNextPage: json['has_next_page'] as bool? ??
            (json['page'] as int) * (json['limit'] as int) < (json['total'] as int),
      );
}

// Usage in DataSource:
Future<PaginatedResponse<ProductModel>> getProducts({
  required int page,
  required int limit,
}) async {
  final response = await _client.get<Map<String, dynamic>>(
    '/products',
    queryParameters: {'page': page, 'limit': limit},
  );
  return PaginatedResponse.fromJson(
    response.data!,
    (json) => ProductModel.fromJson(json as Map<String, dynamic>),
  );
}
```

---

## Request/Response Models

```dart
// lib/{feature}/data/data_models/product_model.dart
@freezed
class ProductModel with _$ProductModel {
  const factory ProductModel({
    required String id,
    required String name,
    @JsonKey(name: 'price_in_cents') required int priceInCents,
    @JsonKey(name: 'category_id') required String categoryId,
    @JsonKey(name: 'image_url') String? imageUrl,
    @JsonKey(name: 'is_available') required bool isAvailable,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _ProductModel;

  factory ProductModel.fromJson(Map<String, dynamic> json) =>
      _$ProductModelFromJson(json);
}

// lib/{feature}/data/data_models/create_product_request.dart
@freezed
class CreateProductRequest with _$CreateProductRequest {
  const factory CreateProductRequest({
    required String name,
    @JsonKey(name: 'price_in_cents') required int priceInCents,
    @JsonKey(name: 'category_id') required String categoryId,
  }) = _CreateProductRequest;

  factory CreateProductRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateProductRequestFromJson(json);
}
```
