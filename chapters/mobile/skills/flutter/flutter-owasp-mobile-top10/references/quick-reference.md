# Quick Reference — OWASP Mobile Top 10 Verification Commands

Fast grep commands for auditing each OWASP Mobile Top 10 category in Flutter projects.

---

## M1 — Improper Credential Usage

### Hardcoded API keys and secrets
```bash
# Google API Keys
grep -rE "AIza[0-9A-Za-z\-_]{35}" lib/ android/ ios/

# AWS Keys
grep -rE "AKIA[0-9A-Z]{16}" lib/ android/ ios/

# Stripe Keys
grep -rE "(sk|pk)_(live|test)_[0-9a-zA-Z]{24,}" lib/

# Generic secrets
grep -rE "(api[_-]?key|secret[_-]?key|password)\s*[:=]\s*['\"][^'\"]{16,}['\"]" lib/

# Private keys
grep -r "BEGIN.*PRIVATE KEY" lib/ android/ ios/
```

### Debuggable in production (Android)
```bash
grep -r 'android:debuggable="true"' android/app/src/main/
grep -A10 "buildTypes" android/app/build.gradle | grep -A5 "release" | grep "debuggable true"
```

### Backup enabled (Android)
```bash
grep 'android:allowBackup="true"' android/app/src/main/AndroidManifest.xml
```

### App Transport Security (iOS)
```bash
grep -A5 "NSAppTransportSecurity" ios/Runner/Info.plist
grep "NSAllowsArbitraryLoads" ios/Runner/Info.plist
```

### Excessive permissions (Android)
```bash
grep -h "uses-permission" android/app/src/main/AndroidManifest.xml
```

### Exported components (Android)
```bash
grep -B2 'android:exported="true"' android/app/src/main/AndroidManifest.xml
```

---

## M2 — Inadequate Supply Chain Security

```bash
# Known vulnerabilities
dart pub audit

# Outdated packages
dart pub outdated

# Unpinned dependencies
grep -E ":\s*(any|latest)" pubspec.yaml | grep -v "#"
```

---

## M3 — Insecure Authentication/Authorization

```bash
# Tokens in SharedPreferences
grep -r "SharedPreferences" lib/ | grep -i "token\|password\|secret\|key"

# No JWT expiry check
grep -r "getString.*token" lib/ | grep -v "isExpired\|exp\|_decodeExp"

# Auth bypass
grep -rE "(bypassAuth|skipAuth|devLogin|backdoor)" lib/ | grep -v test/

# Tokens in static globals
grep -rE "static\s+String\s+.*[Tt]oken" lib/
```

---

## M4 — Insufficient Input/Output Validation

```bash
# WebView without NavigationDelegate
grep -rn "WebView\|WebViewController" lib/ | grep -v "navigationDelegate\|NavigationDelegate"

# Unrestricted JavaScript
grep -rn "javascriptMode.*unrestricted" lib/

# JavaScript bridges
grep -rn "addJavaScriptChannel\|addJavascriptInterface" lib/
```

---

## M5 — Insecure Communication

```bash
# HTTP URLs (not localhost)
grep -r "http://" lib/ --exclude-dir=test | grep -v "localhost\|127.0.0.1"

# SSL bypass
grep -r "badCertificateCallback.*=> true" lib/

# Android cleartext
grep 'android:usesCleartextTraffic="true"' android/app/src/main/AndroidManifest.xml

# iOS ATS disabled
grep -A2 "NSAllowsArbitraryLoads" ios/Runner/Info.plist | grep "<true/>"
```

---

## M6 — Inadequate Privacy Controls

```bash
# PII in logs
grep -rE "(print|debugPrint|logger)\([^)]*\b(token|password|secret|api[_-]?key|ssn|email|phone)\b" lib/

# PII in analytics
grep -rn "logEvent\|setUserProperty" lib/ | grep -iE "email|phone|name|address"

# Unsanitized crash reports
grep -rn "FirebaseCrashlytics\|Sentry" lib/ | grep -v "sanitize\|redact\|userId\|user\.id" | grep -iE "email|phone|token"
```

---

## M7 — Insufficient Binary Protections

```bash
# ProGuard/R8 disabled
grep -A10 "buildTypes" android/app/build.gradle | grep -A5 "release" | grep "minifyEnabled false"

# Missing obfuscation in CI
grep -r "flutter build" .github/workflows/ | grep -E "release|appbundle|apk" | grep -v "\-\-obfuscate"

# iOS debug symbols
grep "STRIP_INSTALLED_PRODUCT" ios/Runner.xcodeproj/project.pbxproj
grep "DEBUG_INFORMATION_FORMAT" ios/Runner.xcodeproj/project.pbxproj
```

---

## M8 — Security Misconfiguration

```bash
# Exported components
grep -E 'android:exported="true"' android/app/src/main/AndroidManifest.xml

# Backup enabled
grep 'android:allowBackup="true"' android/app/src/main/AndroidManifest.xml

# Excessive permissions
grep "uses-permission" android/app/src/main/AndroidManifest.xml | \
  grep -E "READ_CONTACTS|WRITE_EXTERNAL_STORAGE|READ_PHONE_STATE"
```

---

## M9 — Insecure Data Storage

```bash
# Tokens in SharedPreferences
grep -rE "SharedPreferences.*setString.*['\"].*token" lib/

# Unencrypted SQLite
grep -rn "openDatabase\b" lib/ | grep -v "password:"

# Sensitive data in temp files
grep -rn "getTemporaryDirectory\|writeAsString" lib/ | grep -iE "token|password|secret|key"

# Unencrypted local DB
grep -r "Isar.open\b" lib/ | grep -v "encryptionKey"
```

---

## M10 — Insufficient Cryptography

```bash
# Weak hash algorithms
grep -rn "md5\.convert" lib/ | grep -i "password\|token"
grep -rn "sha1\.convert" lib/
grep -rn "\bDES\b|\bRC4\b" lib/

# Weak cipher mode
grep -rn "AESMode\.ecb\|'AES/ECB'" lib/

# Insecure RNG
grep -rn "Random()" lib/ | grep -v "Random\.secure()"
```

---

## Debug / Extraneous Features

```bash
# Debug routes in production
grep -rE "['\"]/(debug|test|dev|admin)['\"]" lib/ --exclude-dir=test | grep -v "kDebugMode"

# Unconditional print()
grep -rE "^\s*print\(" lib/ | grep -v "kDebugMode"

# Dev packages in dependencies (not dev_dependencies)
grep -A100 "^dependencies:" pubspec.yaml | grep -B1 "^dev_dependencies:" | grep -E "(flutter_test|mocktail|test):"
```

---

## Severity-Based Quick Scan

### Critical only (4 checks)
```bash
grep -r "SharedPreferences" lib/ | grep -i "token\|password"
grep -r "openDatabase" lib/ | grep -v "password"
grep -r "http://" lib/ --exclude-dir=test | grep -v "localhost"
grep -rE "AIza[0-9A-Za-z\-_]{35}|AKIA[0-9A-Z]{16}" lib/ android/ ios/
```

### High severity (9 checks)
```bash
grep -r 'android:debuggable="true"' android/app/src/main/
grep "NSAllowsArbitraryLoads" ios/Runner/Info.plist
grep -B2 'android:exported="true"' android/app/src/main/AndroidManifest.xml
grep -r "javascriptMode.*unrestricted" lib/
grep -r "token" lib/ | grep "SharedPreferences"
grep -r "md5\.convert" lib/ | grep "password"
grep -rE "static\s+String\s+.*[Tt]oken" lib/
grep -rE "['\"]/(debug|test)['\"]" lib/ --exclude-dir=test
grep -r "flutter build" .github/workflows/ | grep -E "release|appbundle" | grep -v "\-\-obfuscate"
```

---

**Last updated:** April 2026
**Version:** 2.0
