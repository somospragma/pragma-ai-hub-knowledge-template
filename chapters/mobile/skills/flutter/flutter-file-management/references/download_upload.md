# Download & Upload with Progress

File download and upload using Dio with progress streams, cancellation, and
MASVS-compliant storage (internal sandbox only for sensitive files).

## Setup

```yaml
dependencies:
  dio: ^5.8.0
  path_provider: ^2.1.4
  path: ^1.9.0
  fpdart: ^1.2.0
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
```

---

## Download with Progress

```dart
// lib/features/file/data/datasources/file_download_data_source.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FileDownloadDataSource {
  final Dio _dio;
  FileDownloadDataSource(this._dio);

  /// Download a file to internal app sandbox with progress reporting.
  /// Returns a Stream of progress (0.0 → 1.0) and completes with the File.
  ///
  /// MASVS-STORAGE-1: saves to internal sandbox, not external storage.
  Stream<DownloadProgress> download({
    required String url,
    required String fileName,
    CancelToken? cancelToken,
  }) async* {
    final controller = StreamController<DownloadProgress>();

    try {
      // ✅ Internal sandbox — never external storage
      final dir = await getApplicationDocumentsDirectory();
      final safeName = FileSecurity.sanitizeFileName(fileName);
      final filePath = path.join(dir.path, safeName);

      // Temp path — rename to final path only on success
      final tempPath = '$filePath.tmp';

      yield DownloadProgress.started(fileName: safeName);

      await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            controller.add(DownloadProgress.downloading(
              fileName: safeName,
              progress: received / total,
              receivedBytes: received,
              totalBytes: total,
            ));
          }
        },
        options: Options(
          // Validate response before writing to disk
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // Validate downloaded file before making it available
      final tempFile = File(tempPath);
      if (!await tempFile.exists()) {
        yield DownloadProgress.failed(
          fileName: safeName,
          error: 'Downloaded file not found',
        );
        return;
      }

      // Rename temp → final (atomic on most platforms)
      final finalFile = await tempFile.rename(filePath);

      yield DownloadProgress.completed(
        fileName: safeName,
        file: finalFile,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        yield DownloadProgress.cancelled(fileName: fileName);
      } else {
        yield DownloadProgress.failed(
          fileName: fileName,
          error: e.message ?? 'Download failed',
        );
      }
    } catch (e) {
      yield DownloadProgress.failed(fileName: fileName, error: '$e');
    } finally {
      // Clean up temp file if it still exists
      final tempPath = path.join(
        (await getApplicationDocumentsDirectory()).path,
        '${FileSecurity.sanitizeFileName(fileName)}.tmp',
      );
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();
    }
  }
}

// lib/features/file/domain/entities/download_progress.dart
@freezed
class DownloadProgress with _$DownloadProgress {
  const factory DownloadProgress.started({required String fileName}) = DownloadStarted;
  const factory DownloadProgress.downloading({
    required String fileName,
    required double progress,   // 0.0 → 1.0
    required int receivedBytes,
    required int totalBytes,
  }) = Downloading;
  const factory DownloadProgress.completed({
    required String fileName,
    required File file,
  }) = DownloadCompleted;
  const factory DownloadProgress.cancelled({required String fileName}) = DownloadCancelled;
  const factory DownloadProgress.failed({
    required String fileName,
    required String error,
  }) = DownloadFailed;
}
```

---

## Upload with Progress

```dart
// lib/features/file/data/datasources/file_upload_data_source.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FileUploadDataSource {
  final Dio _dio;
  FileUploadDataSource(this._dio);

  /// Upload a single file with progress reporting.
  Stream<UploadProgress> uploadFile({
    required String url,
    required File file,
    required String fieldName,
    Map<String, dynamic>? additionalFields,
    CancelToken? cancelToken,
  }) async* {
    try {
      final fileName = path.basename(file.path);

      yield UploadProgress.started(fileName: fileName);

      final formData = FormData.fromMap({
        fieldName: await MultipartFile.fromFile(
          file.path,
          filename: fileName,
          // Let Dio detect content type from file
        ),
        if (additionalFields != null) ...additionalFields,
      });

      final response = await _dio.post(
        url,
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

      yield UploadProgress.completed(
        fileName: fileName,
        responseData: response.data,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        yield UploadProgress.cancelled(fileName: path.basename(file.path));
      } else {
        yield UploadProgress.failed(
          fileName: path.basename(file.path),
          error: e.message ?? 'Upload failed',
          statusCode: e.response?.statusCode,
        );
      }
    } catch (e) {
      yield UploadProgress.failed(
        fileName: path.basename(file.path),
        error: '$e',
      );
    }
  }

  /// Upload multiple files in a single multipart request.
  Stream<UploadProgress> uploadMultiple({
    required String url,
    required List<File> files,
    required String fieldName,
    CancelToken? cancelToken,
  }) async* {
    try {
      yield UploadProgress.started(fileName: '${files.length} files');

      final multipartFiles = await Future.wait(
        files.map((f) => MultipartFile.fromFile(
          f.path,
          filename: path.basename(f.path),
        )),
      );

      final formData = FormData.fromMap({
        fieldName: multipartFiles,
      });

      final response = await _dio.post(
        url,
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total > 0) {
            yield UploadProgress.uploading(
              fileName: '${files.length} files',
              progress: sent / total,
              sentBytes: sent,
              totalBytes: total,
            );
          }
        },
      );

      yield UploadProgress.completed(
        fileName: '${files.length} files',
        responseData: response.data,
      );
    } on DioException catch (e) {
      yield UploadProgress.failed(
        fileName: '${files.length} files',
        error: e.message ?? 'Upload failed',
        statusCode: e.response?.statusCode,
      );
    }
  }
}

@freezed
class UploadProgress with _$UploadProgress {
  const factory UploadProgress.started({required String fileName}) = UploadStarted;
  const factory UploadProgress.uploading({
    required String fileName,
    required double progress,
    required int sentBytes,
    required int totalBytes,
  }) = Uploading;
  const factory UploadProgress.completed({
    required String fileName,
    required dynamic responseData,
  }) = UploadCompleted;
  const factory UploadProgress.cancelled({required String fileName}) = UploadCancelled;
  const factory UploadProgress.failed({
    required String fileName,
    required String error,
    int? statusCode,
  }) = UploadFailed;
}
```

---

## BLoC Integration

```dart
// lib/features/file/presentation/bloc/file_transfer_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:dio/dio.dart';

part 'file_transfer_bloc.freezed.dart';
part 'file_transfer_event.dart';
part 'file_transfer_state.dart';

@injectable
class FileTransferBloc extends Bloc<FileTransferEvent, FileTransferState> {
  final FileDownloadDataSource _downloadSource;
  final FileUploadDataSource _uploadSource;

  CancelToken? _cancelToken;

  FileTransferBloc(this._downloadSource, this._uploadSource)
      : super(const FileTransferState.idle()) {
    on<StartDownloadEvent>(_onStartDownload);
    on<StartUploadEvent>(_onStartUpload);
    on<CancelTransferEvent>(_onCancel);
  }

  Future<void> _onStartDownload(
    StartDownloadEvent event,
    Emitter<FileTransferState> emit,
  ) async {
    _cancelToken = CancelToken();

    await emit.forEach(
      _downloadSource.download(
        url: event.url,
        fileName: event.fileName,
        cancelToken: _cancelToken,
      ),
      onData: (progress) => progress.when(
        started: (name) => FileTransferState.inProgress(
          fileName: name, progress: 0.0, isDownload: true,
        ),
        downloading: (name, p, received, total) => FileTransferState.inProgress(
          fileName: name, progress: p, isDownload: true,
          receivedBytes: received, totalBytes: total,
        ),
        completed: (name, file) => FileTransferState.completed(
          fileName: name, file: file,
        ),
        cancelled: (name) => const FileTransferState.cancelled(),
        failed: (name, error) => FileTransferState.error(message: error),
      ),
    );
  }

  Future<void> _onStartUpload(
    StartUploadEvent event,
    Emitter<FileTransferState> emit,
  ) async {
    _cancelToken = CancelToken();

    await emit.forEach(
      _uploadSource.uploadFile(
        url: event.url,
        file: event.file,
        fieldName: event.fieldName,
        cancelToken: _cancelToken,
      ),
      onData: (progress) => progress.when(
        started: (name) => FileTransferState.inProgress(
          fileName: name, progress: 0.0, isDownload: false,
        ),
        uploading: (name, p, sent, total) => FileTransferState.inProgress(
          fileName: name, progress: p, isDownload: false,
          receivedBytes: sent, totalBytes: total,
        ),
        completed: (name, _) => FileTransferState.completed(fileName: name),
        cancelled: (name) => const FileTransferState.cancelled(),
        failed: (name, error, _) => FileTransferState.error(message: error),
      ),
    );
  }

  void _onCancel(CancelTransferEvent event, Emitter<FileTransferState> emit) {
    _cancelToken?.cancel('User cancelled');
    emit(const FileTransferState.cancelled());
  }
}

// file_transfer_event.dart
part of 'file_transfer_bloc.dart';

@freezed
class FileTransferEvent with _$FileTransferEvent {
  const factory FileTransferEvent.startDownload({
    required String url,
    required String fileName,
  }) = StartDownloadEvent;
  const factory FileTransferEvent.startUpload({
    required String url,
    required File file,
    required String fieldName,
  }) = StartUploadEvent;
  const factory FileTransferEvent.cancel() = CancelTransferEvent;
}

// file_transfer_state.dart
part of 'file_transfer_bloc.dart';

@freezed
class FileTransferState with _$FileTransferState {
  const factory FileTransferState.idle() = FileTransferIdle;
  const factory FileTransferState.inProgress({
    required String fileName,
    required double progress,
    required bool isDownload,
    int? receivedBytes,
    int? totalBytes,
  }) = FileTransferInProgress;
  const factory FileTransferState.completed({
    required String fileName,
    File? file,
  }) = FileTransferCompleted;
  const factory FileTransferState.cancelled() = FileTransferCancelled;
  const factory FileTransferState.error({required String message}) = FileTransferError;
}
```

---

## Progress UI Widget

```dart
// lib/features/file/presentation/widgets/file_transfer_progress.dart
class FileTransferProgressWidget extends StatelessWidget {
  const FileTransferProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FileTransferBloc, FileTransferState>(
      builder: (context, state) => state.when(
        idle: () => const SizedBox.shrink(),
        inProgress: (name, progress, isDownload, received, total) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isDownload ? 'Downloading $name' : 'Uploading $name'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            if (received != null && total != null)
              Text('${_formatBytes(received)} / ${_formatBytes(total)}'),
          ],
        ),
        completed: (name, _) => Text('✅ $name ready'),
        cancelled: () => const Text('Transfer cancelled'),
        error: (msg) => Text('❌ $msg', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
```
