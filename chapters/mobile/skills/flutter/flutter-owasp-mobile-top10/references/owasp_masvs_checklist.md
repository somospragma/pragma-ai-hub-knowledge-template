# OWASP MASVS Verification Checklist — Flutter

Based on OWASP Mobile Application Security Verification Standard (MASVS) v2.
Reference: https://mas.owasp.org/MASVS/

> **Note:** MASVS v2 removed the L1/L2/R levels. It now uses
> [MAS Testing Profiles](https://mas.owasp.org/MASWE/) and the MASWE catalog
> (Mobile Application Security Weakness Enumeration) to map weaknesses.

---

## MASVS-STORAGE — Secure Storage of Sensitive Data

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| STORAGE-1 | The app securely stores sensitive data | `FlutterSecureStorage` (Keychain/Keystore). See `flutter-secure-storage` skill | MASWE-0002, MASWE-0006 |
| STORAGE-2 | The app prevents leakage of sensitive data | No PII in logs, backups, clipboard, or screenshots | MASWE-0001, MASWE-0003, MASWE-0004 |

### Flutter Checklist

- [ ] Tokens and credentials in `FlutterSecureStorage`, never in `SharedPreferences`
- [ ] Isar with encryption key stored in `FlutterSecureStorage` for large sensitive datasets — see `flutter-database-strategy`
- [ ] `SharedPreferences` only for non-sensitive data (theme, language, onboarding)
- [ ] No PII in `print()`, `debugPrint()`, `logger.info/debug`
- [ ] Keyboard cache disabled on sensitive fields: `TextField(enableSuggestions: false, autocorrect: false)`
- [ ] Clipboard cleared after copying sensitive data
- [ ] Android `allowBackup="false"` or exclusion rules for sensitive data
- [ ] Sensitive screens blurred when app is backgrounded
- [ ] SQLite with `password:` parameter if it stores sensitive data

> **Scan:** `grep -rE "prefs\.(setString|getString).*token" lib/`
> **Scan:** `grep -rE "(print|debugPrint).*\b(email|phone|ssn|password|token)\b" lib/`

---

## MASVS-CRYPTO — Cryptographic Functionality

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| CRYPTO-1 | The app employs current, strong cryptography according to industry best practices | AES-256-GCM via `pointycastle 4.x`, SHA-256/SHA-512 via `crypto 3.x`. See `flutter-data-encryption` skill | MASWE-0019, MASWE-0020, MASWE-0021 |
| CRYPTO-2 | The app performs key management according to industry best practices | Keys in Android Keystore / iOS Keychain via `FlutterSecureStorage 10.x`. Key rotation implemented | MASWE-0009, MASWE-0013, MASWE-0014 |

### Flutter Checklist

- [ ] AES-256-GCM (no ECB, no CBC without authentication)
- [ ] RSA-OAEP with SHA-256 minimum (no PKCS#1 v1.5 for encryption)
- [ ] SHA-256 or SHA-512 for hashing (never MD5, SHA-1)
- [ ] `Random.secure()` for all cryptographic random values
- [ ] 12-byte nonce/IV for GCM, generated with `Random.secure()`, never reused
- [ ] Keys stored in Keychain/Keystore via `FlutterSecureStorage`, never hardcoded
- [ ] Do not use `package:encrypt` (unmaintained) — use `pointycastle` directly
- [ ] PBKDF2-SHA256 with ≥100k iterations for password-based key derivation

> **Scan:** `grep -rn "md5\.convert\|sha1\.convert\|AESMode\.ecb\|Random()" lib/`
> **Scan:** `grep -rE "(apiKey|secret|password)\s*[=:]\s*['\"][a-zA-Z0-9+/=]{16,}['\"]" lib/`

---

## MASVS-AUTH — Authentication and Authorization

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| AUTH-1 | The app uses secure authentication and authorization protocols following best practices | JWT with `exp` validation, refresh token flow, backend as authority. See `flutter-secure-storage` (TokenRepository) | MASWE-0033, MASWE-0038 |
| AUTH-2 | The app performs local authentication securely | Biometrics with `local_auth` + crypto binding to Keystore. See `flutter-biometrics` skill | MASWE-0044, MASWE-0045 |
| AUTH-3 | The app secures sensitive operations with additional authentication | Step-up auth for critical operations (transfers, password change) | MASWE-0029, MASWE-0030 |

### Flutter Checklist

- [ ] Access token expiry validated (with 5-minute buffer) before each use — pure Dart, no external library
- [ ] Refresh token flow implemented with retry and logout on failure
- [ ] Configurable session timeout with automatic cleanup
- [ ] No auth bypass in code (`bypassAuth`, `skipAuth`, `devLogin`)
- [ ] Permissions/roles validated on the backend, not only on the client
- [ ] Biometrics use `biometricOnly: true` for sensitive operations (no PIN fallback)
- [ ] Logout clears **all** tokens, cache, and session state
- [ ] No credentials in URL parameters

> **Scan:** `grep -rE "(bypassAuth|skipAuth|devLogin|backdoor)" lib/`
> **Scan:** `grep -rE "static\s+String\s+.*[Tt]oken" lib/`

---

## MASVS-NETWORK — Secure Network Communication

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| NETWORK-1 | The app secures all network traffic according to current best practices | HTTPS only, TLS 1.2+, no cleartext. Dio with SSL validation | MASWE-0048, MASWE-0050 |
| NETWORK-2 | The app performs identity pinning for all connections to remote endpoints handling sensitive data | Certificate pinning via network security config or Dio interceptor. See `flutter-certificate-pinning` skill | MASWE-0047, MASWE-0052 |

### Flutter Checklist

- [ ] All URLs use `https://`
- [ ] `badCertificateCallback` never returns `true` in production
- [ ] Android `usesCleartextTraffic="false"` in AndroidManifest
- [ ] iOS ATS (App Transport Security) **not** disabled (`NSAllowsArbitraryLoads` is not `true`)
- [ ] Certificate pinning on endpoints handling sensitive data
- [ ] App fails closed on TLS errors (no HTTP fallback)
- [ ] Timeouts configured on the HTTP client

> **Scan:** `grep -rE "http://(?!localhost|127\.0\.0\.1|10\.0\.)" lib/`
> **Scan:** `grep -rE "badCertificateCallback.*=>\s*true" lib/`

---

## MASVS-PLATFORM — Secure Platform Interaction

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| PLATFORM-1 | The app uses IPC mechanisms securely | Deep links validated, WebView with `navigationDelegate`, no unnecessary JavaScript bridges | MASWE-0058, MASWE-0068 |
| PLATFORM-2 | The app uses WebViews securely | URL allowlisting, restricted JavaScript, no `file://` access | MASWE-0069, MASWE-0071, MASWE-0072 |
| PLATFORM-3 | The app uses the user interface securely | Screenshots prevented on sensitive screens, UI does not leak data | MASWE-0053, MASWE-0055 |

### Flutter Checklist

- [ ] Deep links validated before navigating (IDs, scheme, host)
- [ ] WebView with `NavigationDelegate` and host allowlist
- [ ] WebView JavaScript enabled only when necessary
- [ ] No sensitive data in `Intent` extras or `UIPasteboard`
- [ ] Android: non-public components with `exported="false"`
- [ ] Screenshots prevented on sensitive screens (`FLAG_SECURE` on Android, blur on iOS)
- [ ] Push notifications do not contain sensitive data (tokens, visible OTPs)

> **Scan:** `grep -rn "WebView\|WebViewController" lib/ | grep -v navigationDelegate`
> **Scan:** `grep -E 'android:exported="true"' android/app/src/main/AndroidManifest.xml`

---

## MASVS-CODE — Code Quality and Security

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| CODE-1 | The app requires an up-to-date platform version | `minSdkVersion 23+` (Android), iOS 12+. Device API level check | MASWE-0077, MASWE-0078 |
| CODE-2 | The app has a mechanism for enforcing app updates | Force update via Remote Config, `package_info_plus` + backend version check | MASWE-0075 |
| CODE-3 | The app only uses software components without known vulnerabilities | `dart pub audit`, pinned dependencies, SBOM generated | MASWE-0076 |
| CODE-4 | The app validates and sanitizes all untrusted inputs | Input validation on forms, parameterized SQL, sanitized deep links | MASWE-0079, MASWE-0086 |

### Flutter Checklist

- [ ] `dart pub audit` runs in CI with zero vulnerabilities
- [ ] `dart pub outdated` reviewed periodically
- [ ] Dependencies pinned to major version (`^x.y.z`), never `any` or `latest`
- [ ] Input validation on all forms (email, phone, IDs)
- [ ] SQL queries parameterized (no string interpolation)
- [ ] Deep link parameters validated before use
- [ ] Safe deserialization (no `dart:mirrors`, no dynamic code execution)
- [ ] `minSdkVersion` >= 23 (Android 6.0) to leverage hardware Keystore
- [ ] Force update mechanism implemented

> **Scan:** `dart pub audit`
> **Scan:** `dart pub outdated`

---

## MASVS-RESILIENCE — Resilience Against Reverse Engineering and Tampering

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| RESILIENCE-1 | The app validates the integrity of the platform | Root/jailbreak detection. See `flutter-rasp-strategy` skill | MASWE-0097, MASWE-0099 |
| RESILIENCE-2 | The app implements anti-tampering mechanisms | Obfuscation with `--obfuscate`, integrity checks | MASWE-0089, MASWE-0104 |
| RESILIENCE-3 | The app implements anti-static analysis mechanisms | Code obfuscation, symbol stripping | MASWE-0089, MASWE-0092 |
| RESILIENCE-4 | The app implements anti-dynamic analysis mechanisms | Debugger detection, Frida detection. See `flutter-rasp-strategy` skill | MASWE-0101, MASWE-0102 |

### Flutter Checklist

- [ ] Release builds with `--obfuscate --split-debug-info=build/symbols/`
- [ ] Android ProGuard/R8 enabled: `minifyEnabled true`, `shrinkResources true`
- [ ] `debuggable false` in release build type
- [ ] Root/jailbreak detection in financial and health apps
- [ ] Device attestation (Google Play Integrity API, App Attest)
- [ ] No debug symbols in release binaries
- [ ] No debug/test code in release (`kDebugMode` guards)
- [ ] Debug entitlement disabled in iOS release (`get-task-allow = false`)

> **Scan:** `grep -A10 'buildTypes' android/app/build.gradle | grep 'minifyEnabled false'`
> **Scan:** `grep 'android:debuggable="true"' android/app/src/main/AndroidManifest.xml`
> **Scan:** `grep -r "flutter build" .github/workflows/ | grep -v "\-\-obfuscate"`

---

## MASVS-PRIVACY — User Privacy Protection

| ID | Control | Flutter Implementation | MASWE |
|---|---|---|---|
| PRIVACY-1 | The app minimizes access to sensitive data and resources | Permissions requested just-in-time, minimum necessary. See `flutter-permissions` skill | MASWE-0117 |
| PRIVACY-2 | The app prevents identification of the user | No tracking IDs without consent, anonymized analytics | MASWE-0109, MASWE-0110 |
| PRIVACY-3 | The app is transparent about data collection and usage | Accessible privacy policy, data collection declarations in stores | MASWE-0111, MASWE-0112 |
| PRIVACY-4 | The app offers user control over their data | Data deletion, export, consent management | MASWE-0113, MASWE-0115 |

### Flutter Checklist

- [ ] Permissions requested only when needed (just-in-time), not at startup
- [ ] Minimum permissions — remove unused permissions from the manifest
- [ ] Analytics without PII (no email, phone, name in events)
- [ ] Crash reports sanitized (userId only, no email or personal data)
- [ ] iOS privacy manifest correctly configured
- [ ] `NSPrivacyAccessedAPIType` declared for required APIs (iOS 17+)
- [ ] Consent management before tracking (ATT on iOS, consent dialog on Android)
- [ ] User data deletion mechanism (right to erasure, GDPR)
- [ ] Analytics provider configured to not send PII

> **Scan:** `grep -rn "logEvent\|setUserProperty" lib/ | grep -E "email|phone|name"`
> **Scan:** `grep -rE "(print|debugPrint|logger).*\b(email|phone|ssn|password)\b" lib/`
> **Scan:** `grep "uses-permission" android/app/src/main/AndroidManifest.xml | wc -l`

---

## Cross-Reference: Mobile Top 10 2024 → MASVS

| Mobile Top 10 | MASVS Control Groups |
|---|---|
| M1: Improper Credential Usage | MASVS-STORAGE, MASVS-CRYPTO |
| M2: Inadequate Supply Chain Security | MASVS-CODE |
| M3: Insecure Authentication/Authorization | MASVS-AUTH |
| M4: Insufficient Input/Output Validation | MASVS-CODE, MASVS-PLATFORM |
| M5: Insecure Communication | MASVS-NETWORK |
| M6: Inadequate Privacy Controls | MASVS-PRIVACY, MASVS-STORAGE |
| M7: Insufficient Binary Protections | MASVS-RESILIENCE |
| M8: Security Misconfiguration | MASVS-PLATFORM, MASVS-CODE |
| M9: Insecure Data Storage | MASVS-STORAGE, MASVS-CRYPTO |
| M10: Insufficient Cryptography | MASVS-CRYPTO |

---

## Related Skills

| MASVS Group | Skill |
|---|---|
| MASVS-STORAGE | `flutter-secure-storage`, `flutter-database-strategy` |
| MASVS-CRYPTO | `flutter-data-encryption` |
| MASVS-AUTH | `flutter-secure-storage` (TokenRepository), `flutter-biometrics` |
| MASVS-NETWORK | `flutter-certificate-pinning` |
| MASVS-PLATFORM | `flutter-deep-link-strategy` |
| MASVS-CODE | `flutter-ci-optimization` |
| MASVS-RESILIENCE | `flutter-rasp-strategy` |
| MASVS-PRIVACY | `flutter-permissions`, `flutter-firebase-analytics` |
