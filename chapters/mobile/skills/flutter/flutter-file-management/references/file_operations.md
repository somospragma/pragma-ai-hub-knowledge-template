# File Operations — Pick, Read, Write, Delete

Covers file picking, reading, writing, and deletion with MASVS-STORAGE security controls.

## Setup

```yaml
dependencies:
  file_picker: ^8.1.0
  path_provider: ^2.1.4
  path: ^1.9.0
  mime: ^2.0.0
  fpdart: ^1.2.0
  injectable: ^3.0.0
```

---

## Security Utilities (use everywhere)

```dart
// lib/core/file/file_security.dart
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';

abstract final class FileSecurity {
  /// Strip directory components and unsafe characters from a user-supplied filename.
  /// Prevents path traversal attacks (MASVS-CODE-4).
  static String sanitizeFileName(String name) {
    return path.basename(name)
        .replaceAll(RegExp(r'[^\w\s\-.]'), '_')
        .trim();
  }

  /// Validate MIME type from actual file bytes — not just extension.
  /// Extension can be spoofed; magic bytes cannot (MASVS-CODE-4).
  static Future<String?> detectMimeType(File file) async {
    try {
      final bytes = await file.openRead(0, 12).first;
      return lookupMimeType(file.path, headerBytes: bytes);
    } catch (_) {
      return null;
    }
  }

  /// Check if a file's actual MIME type is in the allowed set.
  static Future<bool> isAllowedMimeType(
    File file,
    Set<String> allowedMimeTypes,
  ) async {
    final mime = await detectMimeType(file);
    return mime != null && allowedMimeTypes.contains(mime);
  }

  /// Validate file size does not exceed the limit.
  static Future<bool> isWithinSizeLimit(File file, int maxBytes) async {
    final stat = await file.stat();
    return stat.size <= maxBytes;
  }

  /// Build a safe file path inside the app sandbox.
  /// Never use user input directly as a path component.
  static Future<String> safePath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return path.join(dir.path, sanitizeFileName(fileName));
  }
}
```

---

## File Picker

```dart
// lib/features/file/data/datasources/file_picker_data_source.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FilePickerDataSource {
  /// Pick a single document — whitelist allowed extensions (MASVS-CODE-4)
  Future<Either<FileFailure, File>> pickDocument({
    List<String> allowedExtensions = const ['pdf', 'docx', 'xlsx', 'txt'],
    int maxSizeBytes = 10 * 1024 * 1024, // 10MB default
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        withData: false,       // stream from path — don't load all bytes into memory
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) {
        return const Left(FileFailure.cancelled());
      }

      final pickedFile = result.files.single;
      if (pickedFile.path == null) {
        return const Left(FileFailure.pathUnavailable());
      }

      final file = File(pickedFile.path!);

      // Validate size
      if (!await FileSecurity.isWithinSizeLimit(file, maxSizeBytes)) {
        return Left(FileFailure.fileTooLarge(
          maxBytes: maxSizeBytes,
          actualBytes: await file.length(),
        ));
      }

      // Validate MIME type from bytes — not just extension
      final allowed = allowedExtensions
          .map((ext) => lookupMimeType('file.$ext') ?? '')
          .toSet();
      if (!await FileSecurity.isAllowedMimeType(file, allowed)) {
        return const Left(FileFailure.invalidMimeType());
      }

      return Right(file);
    } catch (e) {
      return Left(FileFailure.unknown(message: '$e'));
    }
  }

  /// Pick multiple images
  Future<Either<FileFailure, List<File>>> pickImages({
    int maxCount = 10,
    int maxSizeBytes = 5 * 1024 * 1024, // 5MB per image
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return const Left(FileFailure.cancelled());
      }

      final files = <File>[];
      for (final picked in result.files.take(maxCount)) {
        if (picked.path == null) continue;
        final file = File(picked.path!);

        if (!await FileSecurity.isWithinSizeLimit(file, maxSizeBytes)) continue;
        if (!await FileSecurity.isAllowedMimeType(
          file, {'image/jpeg', 'image/png', 'image/webp', 'image/gif'},
        )) continue;

        files.add(file);
      }

      if (files.isEmpty) return const Left(FileFailure.noValidFiles());
      return Right(files);
    } catch (e) {
      return Left(FileFailure.unknown(message: '$e'));
    }
  }
}
```

---

## Read and Write — Internal Storage Only

```dart
// lib/features/file/data/datasources/file_storage_data_source.dart
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FileStorageDataSource {

  // ── Write ─────────────────────────────────────────────────────────────

  /// Write bytes to internal app sandbox (MASVS-STORAGE-1 compliant).
  Future<Either<FileFailure, File>> writeBytes(
    String fileName,
    List<int> bytes,
  ) async {
    try {
      final filePath = await FileSecurity.safePath(fileName);
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return Right(file);
    } catch (e) {
      return Left(FileFailure.writeFailed(message: '$e'));
    }
  }

  /// Write JSON data to internal storage.
  Future<Either<FileFailure, File>> writeJson(
    String fileName,
    Map<String, dynamic> data,
  ) async {
    final bytes = utf8.encode(jsonEncode(data));
    return writeBytes(fileName, bytes);
  }

  // ── Read ──────────────────────────────────────────────────────────────

  Future<Either<FileFailure, List<int>>> readBytes(String fileName) async {
    try {
      final filePath = await FileSecurity.safePath(fileName);
      final file = File(filePath);
      if (!await file.exists()) {
        return Left(FileFailure.notFound(fileName: fileName));
      }
      return Right(await file.readAsBytes());
    } catch (e) {
      return Left(FileFailure.readFailed(message: '$e'));
    }
  }

  Future<Either<FileFailure, String>> readText(String fileName) async {
    final result = await readBytes(fileName);
    return result.map((bytes) => utf8.decode(bytes));
  }

  // ── Delete ────────────────────────────────────────────────────────────

  Future<Either<FileFailure, Unit>> delete(String fileName) async {
    try {
      final filePath = await FileSecurity.safePath(fileName);
      final file = File(filePath);
      if (await file.exists()) await file.delete();
      return const Right(unit);
    } catch (e) {
      return Left(FileFailure.deleteFailed(message: '$e'));
    }
  }

  /// Delete all files in the app temp directory.
  Future<void> clearTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
        await tempDir.create();
      }
    } catch (_) {}
  }

  // ── Exists / Metadata ─────────────────────────────────────────────────

  Future<bool> exists(String fileName) async {
    final filePath = await FileSecurity.safePath(fileName);
    return File(filePath).exists();
  }

  Future<Either<FileFailure, FileStat>> stat(String fileName) async {
    try {
      final filePath = await FileSecurity.safePath(fileName);
      return Right(await File(filePath).stat());
    } catch (e) {
      return Left(FileFailure.unknown(message: '$e'));
    }
  }
}
```

---

## Failure Types

```dart
// lib/features/file/domain/entities/file_failure.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'file_failure.freezed.dart';

@freezed
class FileFailure with _$FileFailure {
  const factory FileFailure.cancelled() = FileCancelled;
  const factory FileFailure.pathUnavailable() = FilePathUnavailable;
  const factory FileFailure.notFound({required String fileName}) = FileNotFound;
  const factory FileFailure.fileTooLarge({
    required int maxBytes,
    required int actualBytes,
  }) = FileTooLarge;
  const factory FileFailure.invalidMimeType() = FileInvalidMimeType;
  const factory FileFailure.noValidFiles() = FileNoValidFiles;
  const factory FileFailure.writeFailed({required String message}) = FileWriteFailed;
  const factory FileFailure.readFailed({required String message}) = FileReadFailed;
  const factory FileFailure.deleteFailed({required String message}) = FileDeleteFailed;
  const factory FileFailure.downloadFailed({required String message}) = FileDownloadFailed;
  const factory FileFailure.uploadFailed({required String message}) = FileUploadFailed;
  const factory FileFailure.unknown({required String message}) = FileUnknown;
}
```

---

## Repository Interface

```dart
// lib/features/file/domain/repositories/file_repository.dart
import 'dart:io';
import 'package:fpdart/fpdart.dart';

abstract interface class FileRepository {
  Future<Either<FileFailure, File>> pickDocument({
    List<String> allowedExtensions,
    int maxSizeBytes,
  });
  Future<Either<FileFailure, List<File>>> pickImages({int maxCount});
  Future<Either<FileFailure, File>> writeBytes(String fileName, List<int> bytes);
  Future<Either<FileFailure, List<int>>> readBytes(String fileName);
  Future<Either<FileFailure, Unit>> delete(String fileName);
  Future<bool> exists(String fileName);
}
```

---

## Testing

```dart
// test/features/file/data/datasources/file_storage_data_source_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  late FileStorageDataSource dataSource;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_test_');
    // Override path_provider to use temp dir in tests
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    dataSource = FileStorageDataSource();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('FileStorageDataSource', () {
    test('writeBytes and readBytes round-trip', () async {
      const bytes = [1, 2, 3, 4, 5];
      await dataSource.writeBytes('test.bin', bytes);
      final result = await dataSource.readBytes('test.bin');
      expect(result.getOrElse((_) => []), bytes);
    });

    test('readBytes returns notFound for missing file', () async {
      final result = await dataSource.readBytes('missing.bin');
      expect(result.isLeft(), true);
      result.fold(
        (f) => expect(f, isA<FileNotFound>()),
        (_) => fail('Expected failure'),
      );
    });

    test('sanitizeFileName strips path traversal', () {
      expect(
        FileSecurity.sanitizeFileName('../../../etc/passwd'),
        'passwd',
      );
      expect(
        FileSecurity.sanitizeFileName('../../secret.txt'),
        'secret.txt',
      );
    });
  });
}
```
