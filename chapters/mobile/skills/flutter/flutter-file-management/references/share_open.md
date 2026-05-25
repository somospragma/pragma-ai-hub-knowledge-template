# Share, Open & Save Files

Sharing files via OS share sheet, opening with native apps, and saving to the
Downloads folder — with MASVS-PLATFORM-2 compliance (FileProvider on Android).

## Setup

```yaml
dependencies:
  share_plus: ^10.1.0
  open_filex: ^4.4.0
  file_saver: ^0.2.14
  path_provider: ^2.1.4
  path: ^1.9.0
```

---

## Share Files — share_plus

`share_plus` handles FileProvider internally on Android — never exposes raw
internal paths via Intent (MASVS-PLATFORM-2 compliant).

```dart
// lib/features/file/data/datasources/file_share_data_source.dart
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FileShareDataSource {

  /// Share a single file via the OS share sheet.
  Future<Either<FileFailure, Unit>> shareFile(
    File file, {
    String? subject,
    String? text,
  }) async {
    try {
      final result = await SharePlus.instance.shareXFiles(
        [XFile(file.path)],
        subject: subject,
        text: text,
      );

      // ShareResultStatus.dismissed is not an error — user chose not to share
      return const Right(unit);
    } catch (e) {
      return Left(FileFailure.unknown(message: 'Share failed: $e'));
    }
  }

  /// Share multiple files.
  Future<Either<FileFailure, Unit>> shareFiles(
    List<File> files, {
    String? subject,
  }) async {
    try {
      await SharePlus.instance.shareXFiles(
        files.map((f) => XFile(f.path)).toList(),
        subject: subject,
      );
      return const Right(unit);
    } catch (e) {
      return Left(FileFailure.unknown(message: 'Share failed: $e'));
    }
  }

  /// Share text content (no file).
  Future<Either<FileFailure, Unit>> shareText(String text, {String? subject}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      return const Right(unit);
    } catch (e) {
      return Left(FileFailure.unknown(message: 'Share failed: $e'));
    }
  }
}
```

---

## Open Files with Native App — open_filex

```dart
// lib/features/file/data/datasources/file_open_data_source.dart
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FileOpenDataSource {

  /// Open a file with the appropriate native app.
  /// open_filex uses FileProvider on Android — MASVS-PLATFORM-2 compliant.
  Future<Either<FileFailure, Unit>> openFile(File file) async {
    try {
      if (!await file.exists()) {
        return Left(FileFailure.notFound(fileName: path.basename(file.path)));
      }

      final result = await OpenFilex.open(file.path);

      return switch (result.type) {
        ResultType.done => const Right(unit),
        ResultType.noAppToOpen => Left(FileFailure.unknown(
            message: 'No app available to open this file type',
          )),
        ResultType.fileNotFound => Left(FileFailure.notFound(
            fileName: path.basename(file.path),
          )),
        ResultType.permissionDenied => Left(FileFailure.unknown(
            message: 'Permission denied to open file',
          )),
        ResultType.error => Left(FileFailure.unknown(
            message: result.message,
          )),
      };
    } catch (e) {
      return Left(FileFailure.unknown(message: 'Open failed: $e'));
    }
  }
}
```

---

## Save to Downloads Folder — file_saver

Use `file_saver` when the user explicitly wants to save a file to their Downloads
folder (user-accessible, not app-private).

> ⚠️ **MASVS-STORAGE-1**: Never save sensitive data (tokens, PII, credentials)
> to the Downloads folder — it is accessible to other apps and the user.
> Use `getApplicationDocumentsDirectory()` for sensitive files.

```dart
// lib/features/file/data/datasources/file_save_data_source.dart
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class FileSaveDataSource {

  /// Save bytes to the user's Downloads folder.
  /// Only for non-sensitive files (reports, exports, public documents).
  Future<Either<FileFailure, String>> saveToDownloads({
    required String fileName,
    required Uint8List bytes,
    required MimeType mimeType,
  }) async {
    try {
      // Sanitize filename before saving
      final safeName = FileSecurity.sanitizeFileName(fileName);

      final savedPath = await FileSaver.instance.saveFile(
        name: safeName,
        bytes: bytes,
        mimeType: mimeType,
      );

      return Right(savedPath);
    } catch (e) {
      return Left(FileFailure.writeFailed(message: 'Save to downloads failed: $e'));
    }
  }

  /// Save a PDF report to Downloads.
  Future<Either<FileFailure, String>> savePdfReport({
    required String reportName,
    required Uint8List pdfBytes,
  }) async {
    return saveToDownloads(
      fileName: '$reportName.pdf',
      bytes: pdfBytes,
      mimeType: MimeType.pdf,
    );
  }

  /// Save a CSV export to Downloads.
  Future<Either<FileFailure, String>> saveCsvExport({
    required String exportName,
    required String csvContent,
  }) async {
    return saveToDownloads(
      fileName: '$exportName.csv',
      bytes: Uint8List.fromList(utf8.encode(csvContent)),
      mimeType: MimeType.csv,
    );
  }
}
```

---

## Android FileProvider Configuration

`share_plus` and `open_filex` handle FileProvider automatically.
If you need manual FileProvider setup (e.g., custom sharing):

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application ...>
    <provider
        android:name="androidx.core.content.FileProvider"
        android:authorities="${applicationId}.fileprovider"
        android:exported="false"
        android:grantUriPermissions="true">
        <meta-data
            android:name="android.support.FILE_PROVIDER_PATHS"
            android:resource="@xml/file_paths" />
    </provider>
</application>
```

```xml
<!-- android/app/src/main/res/xml/file_paths.xml -->
<paths>
    <!-- App internal storage only — never external -->
    <files-path name="app_files" path="." />
    <cache-path name="app_cache" path="." />
    <!-- ❌ Do NOT add external-path for sensitive files -->
</paths>
```

---

## MASVS Security Summary for File Sharing

| Operation | Compliant approach | Non-compliant |
|---|---|---|
| Share internal file | `share_plus` (uses FileProvider) | Raw `file://` URI via Intent |
| Open internal file | `open_filex` (uses FileProvider) | Raw path via Intent |
| Save user export | `file_saver` to Downloads | Hardcoded `/sdcard/` path |
| Sensitive file | `getApplicationDocumentsDirectory()` | External storage |
| Temp file cleanup | Delete in `finally` block | Leave in temp dir |

---

## Complete Use Case Example

```dart
// lib/features/report/domain/usecases/download_and_share_report_usecase.dart
import 'package:injectable/injectable.dart';
import 'package:fpdart/fpdart.dart';

@injectable
class DownloadAndShareReportUseCase {
  final FileDownloadDataSource _download;
  final FileShareDataSource _share;

  DownloadAndShareReportUseCase(this._download, this._share);

  /// Download a report PDF and immediately share it.
  Stream<Either<FileFailure, Unit>> call({
    required String reportUrl,
    required String reportName,
  }) async* {
    File? downloadedFile;

    await for (final progress in _download.download(
      url: reportUrl,
      fileName: '$reportName.pdf',
    )) {
      yield* progress.when(
        started: (_) async* { /* no-op */ },
        downloading: (_, p, __, ___) async* { /* emit progress if needed */ },
        completed: (_, file) async* {
          downloadedFile = file;
          final shareResult = await _share.shareFile(
            file,
            subject: reportName,
          );
          yield shareResult.fold(
            (f) => Left(f),
            (_) => const Right(unit),
          );
        },
        cancelled: (_) async* {
          yield const Left(FileFailure.cancelled());
        },
        failed: (_, error) async* {
          yield Left(FileFailure.downloadFailed(message: error));
        },
      );
    }
  }
}
```
