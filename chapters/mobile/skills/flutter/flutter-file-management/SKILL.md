---
name: flutter-file-management
description: >
  Handles file operations in Flutter: pick, read/write, download with progress, upload, share, and manage app storage directories. Includes OWASP MASVS-STORAGE security requirements: internal-only storage for sensitive files, path traversal prevention, MIME validation, and no sensitive data in external/shared storage. Use this skill when implementing file picker, document download, file upload, file sharing, or any local file I/O.
commands:
  - manage-files
inputs:
  - name: action
    description: Action to perform (implement, audit). "implement" generates the file management infrastructure (repository, data source, security utilities), "audit" checks existing file operations for path traversal vulnerabilities, external storage usage, or missing MIME validation.
    required: true
  - name: target
    description: Path to the core/files directory or feature where file operations will be integrated (e.g. lib/core/files/ for implement, lib/ for audit).
    required: true
  - name: operations
    description: Comma-separated list of file operations to implement (pick, download, upload, share, read-write, all). Defaults to all.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# File Management

See the reference files for complete patterns and code examples.

## Package Status (April 2026)

| Package | Version | Purpose |
|---|---|---|
| **file_picker** | 8.x | Pick files from device (all platforms) |
| **path_provider** | 2.x | App-sandboxed directory paths |
| **share_plus** | 10.x | Share files via OS share sheet |
| **open_filex** | 4.x | Open files with native app |
| **dio** | 5.x | Download/upload with progress |
| **file_saver** | 0.x | Save files to Downloads folder |
| **mime** | 2.x | MIME type detection and validation |

---

## OWASP MASVS-STORAGE Security Requirements

These are **mandatory** — not optional — for any app handling files.

| Control | Requirement | Level |
|---|---|---|
| **MASVS-STORAGE-1** | Sensitive files stored only in app internal sandbox | L1 |
| **MASVS-STORAGE-2** | Sensitive files encrypted at rest (KeyStore/Keychain key) | L2 |
| **MASVS-STORAGE-1** | No sensitive data written to external/shared storage | L1 |
| **MASVS-PLATFORM-2** | Files shared via FileProvider (Android) — never raw paths | L1 |
| **MASVS-CODE-4** | Validate MIME type and extension before processing | L1 |
| **MASVS-CODE-4** | Prevent path traversal — sanitize all file names | L1 |

### Storage location rules

```
✅ getApplicationDocumentsDirectory()  — internal sandbox, app-private
✅ getApplicationSupportDirectory()    — internal sandbox, app-private
✅ getTemporaryDirectory()             — temp, cleared by OS
❌ getExternalStorageDirectory()       — world-readable on Android < 10
❌ /sdcard/, /storage/emulated/0/      — never write sensitive data here
❌ Hardcoded absolute paths            — path traversal risk
```

---

## Core Patterns

### 1. Safe file path construction (no path traversal)
```dart
// ❌ Path traversal vulnerability
final file = File('${dir.path}/$userInput');

// ✅ Sanitize filename — strip directory separators
String sanitizeFileName(String name) {
  return path.basename(name)                    // strip directory components
      .replaceAll(RegExp(r'[^\w\s\-.]'), '_')  // allow only safe chars
      .trim();
}
final file = File(path.join(dir.path, sanitizeFileName(userInput)));
```

### 2. MIME validation before processing
```dart
// ❌ Trust file extension only — easily spoofed
if (file.path.endsWith('.pdf')) { ... }

// ✅ Validate actual MIME type from file bytes
Future<bool> isValidPdf(File file) async {
  final bytes = await file.openRead(0, 4).first;
  // PDF magic bytes: %PDF
  return bytes.length >= 4 &&
      bytes[0] == 0x25 && bytes[1] == 0x50 &&
      bytes[2] == 0x44 && bytes[3] == 0x46;
}
```

### 3. Internal storage only for sensitive files
```dart
// ✅ Always use app-sandboxed directories
final dir = await getApplicationDocumentsDirectory();
final file = File(path.join(dir.path, 'report.pdf'));

// ❌ Never write sensitive data to external storage
// final dir = await getExternalStorageDirectory(); // world-readable
```

### 4. Share via FileProvider (Android) — never raw paths
```dart
// ✅ share_plus handles FileProvider internally
await SharePlus.instance.shareXFiles([XFile(file.path)]);

// ❌ Never expose raw internal paths via Intent
```

---

## Architecture Integration

```
Presentation (BLoC)
  ↓
Domain (UseCase → FileRepository interface)
  ↓
Data (FileRepositoryImpl)
  └── FileDataSource
        ├── FilePicker (pick)
        ├── Dio (download/upload)
        ├── dart:io File (read/write)
        └── SharePlus (share)
```

All dependencies injected via GetIt + Injectable.
Errors returned as `Either<FileFailure, T>` using fpdart.

---

## Quick Wins Checklist

- [ ] All sensitive files written to `getApplicationDocumentsDirectory()` — never external
- [ ] File names sanitized with `path.basename()` before use
- [ ] MIME type validated from file bytes (not just extension)
- [ ] Allowed extensions whitelist enforced in `file_picker`
- [ ] Max file size enforced before processing
- [ ] `share_plus` used for sharing — never raw file paths via Intent
- [ ] Temp files cleaned up in `finally` blocks
- [ ] Download progress exposed via `Stream<double>` to BLoC
- [ ] Upload uses `FormData` with `CancelToken` for cancellation

## Reference Files

- `references/file_operations.md` — pick, read, write, delete, path safety, MIME validation
- `references/download_upload.md` — Dio download with progress, upload with progress, cancellation
- `references/share_open.md` — share_plus, open_filex, file_saver, FileProvider
