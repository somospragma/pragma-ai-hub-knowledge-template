# OWASP Security Scan Script

Reference script for automated OWASP Mobile Top 10 security scanning.
For the full MASVS checklist, see `references/owasp_masvs_checklist.md`.

## Complete Scan Script

The actual script lives in `scripts/owasp_scan.sh`. Below is the reference version
with explanations for each check.

```bash
#!/bin/bash
# scripts/owasp_scan.sh
# Usage: bash scripts/owasp_scan.sh [path_to_flutter_project]
# Run before every release

PROJECT="${1:-.}"
FAIL=0

pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ FAIL: $1"; FAIL=1; }
warn() { echo "  ⚠️  WARN: $1"; }

echo "╔══════════════════════════════════════════╗"
echo "║   OWASP Mobile Top 10 — Flutter Scan    ║"
echo "╚══════════════════════════════════════════╝"
echo "  Project: $PROJECT"
echo ""

# ── M1: Hardcoded Credentials ─────────────────────────────────────────────
echo "── M1: Credential Security ──────────────────"

if grep -rE "AIza[0-9A-Za-z\-_]{35}" "$PROJECT/lib" "$PROJECT/android" "$PROJECT/ios" \
     --include="*.dart" --include="*.xml" --include="*.plist" 2>/dev/null | grep -v test/; then
  fail "Google API key hardcoded"
else pass "No Google API keys in source"; fi

if grep -rE "AKIA[0-9A-Z]{16}" "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "AWS access key hardcoded"
else pass "No AWS keys in source"; fi

if grep -rE "(sk|pk)_(live|test)_[0-9a-zA-Z]{24,}" "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "Stripe key hardcoded"
else pass "No Stripe keys in source"; fi

if grep -r "BEGIN.*PRIVATE KEY" "$PROJECT/lib" "$PROJECT/android" "$PROJECT/ios" 2>/dev/null | grep -v test/; then
  fail "Private key in source code"
else pass "No private keys in source"; fi

if grep -rE "(apiKey|api_key|secret|password|token)\s*[=:]\s*['\"][a-zA-Z0-9+/=]{20,}['\"]" \
     "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v "fromEnvironment\|storage\.read\|_storage\|test/"; then
  warn "Possible hardcoded secret — review manually"
else pass "No obvious hardcoded secrets"; fi

# ── M2: Supply Chain Security ──────────────────────────────────────────────
echo ""
echo "── M2: Supply Chain Security ────────────────"

if command -v dart &>/dev/null && [ -f "$PROJECT/pubspec.yaml" ]; then
  AUDIT_OUTPUT=$(cd "$PROJECT" && dart pub audit 2>&1)
  if echo "$AUDIT_OUTPUT" | grep -qi "affected\|vulnerability"; then
    fail "dart pub audit found vulnerabilities"
    echo "$AUDIT_OUTPUT" | head -20
  else pass "No known vulnerabilities in dependencies"; fi
else warn "dart CLI not available — run 'dart pub audit' manually"; fi

if grep -E ":\s*(any|latest)" "$PROJECT/pubspec.yaml" 2>/dev/null | grep -v "#"; then
  fail "Unpinned dependency found (any/latest) — pin to major version"
else pass "Dependencies are version-pinned"; fi

# ── M3: Authentication ────────────────────────────────────────────────────
echo ""
echo "── M3: Authentication / Authorization ───────"

if grep -rE "SharedPreferences.*setString.*['\"].*token" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "Token stored in SharedPreferences (use FlutterSecureStorage)"
else pass "No tokens in SharedPreferences"; fi

if grep -rE "(bypassAuth|skipAuth|devLogin|backdoor)" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "Authentication bypass detected"
else pass "No auth bypass found"; fi

if grep -rA2 "static\s+String\s+.*[Tt]oken" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "Token in static global variable"
else pass "No tokens in globals"; fi

# ── M4: Input/Output Validation ───────────────────────────────────────────
echo ""
echo "── M4: Input/Output Validation ──────────────"

if grep -rn "WebView\|WebViewController" "$PROJECT/lib" --include="*.dart" 2>/dev/null | \
     grep -v "navigationDelegate\|NavigationDelegate\|shouldOverrideUrl" | grep -v test/ | grep .; then
  warn "WebView without NavigationDelegate — verify URL validation"
else pass "WebViews have navigation control"; fi

if grep -rn "javascriptMode.*unrestricted\|setJavaScriptMode.*unrestricted" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/ | grep .; then
  warn "JavaScript unrestricted in WebView — ensure URL allowlisting is in place"
else pass "No unrestricted JavaScript in WebViews"; fi

if grep -rn "addJavaScriptChannel\|addJavascriptInterface" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/ | grep .; then
  warn "JavaScript bridge detected — review for data exposure"
else pass "No JavaScript bridges found"; fi

# ── M5: Communication ─────────────────────────────────────────────────────
echo ""
echo "── M5: Network Security ──────────────────────"

if grep -rE "http://(?!localhost|127\.0\.0\.1|10\.0\.)" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "HTTP URL found — use HTTPS"
else pass "No HTTP URLs found"; fi

if grep -rE "badCertificateCallback\s*=.*=>\s*true" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "SSL certificate validation bypassed"
else pass "SSL validation not bypassed"; fi

if [ -f "$PROJECT/android/app/src/main/AndroidManifest.xml" ]; then
  if grep -q 'usesCleartextTraffic="true"' "$PROJECT/android/app/src/main/AndroidManifest.xml"; then
    fail "Android cleartext traffic enabled"
  else pass "Android cleartext disabled"; fi
fi

if [ -f "$PROJECT/ios/Runner/Info.plist" ]; then
  if grep -A2 "NSAllowsArbitraryLoads" "$PROJECT/ios/Runner/Info.plist" 2>/dev/null | grep -q "<true/>"; then
    fail "iOS ATS (App Transport Security) disabled"
  else pass "iOS ATS enabled"; fi
fi

# ── M6: Privacy Controls ──────────────────────────────────────────────────
echo ""
echo "── M6: Privacy Controls ─────────────────────"

if grep -rE "(print|debugPrint|logger\.(info|debug)).*\b(email|phone|ssn|password|token)\b" \
     "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v test/ | grep .; then
  fail "PII found in logging statements"
else pass "No PII in logs"; fi

if grep -rn "logEvent\|setUserProperty" "$PROJECT/lib" --include="*.dart" 2>/dev/null | \
     grep -iE "email|phone|name|address" | grep -v test/ | grep .; then
  warn "Analytics may contain PII — verify event payloads"
else pass "No obvious PII in analytics"; fi

if grep -rn "FirebaseCrashlytics\|Sentry" "$PROJECT/lib" --include="*.dart" 2>/dev/null | \
     grep -v "sanitize\|redact\|userId\|user\.id" | grep -iE "email|phone|token" | grep -v test/ | grep .; then
  warn "Crash reports may contain unsanitized PII"
else pass "Crash reports appear sanitized"; fi

# ── M7: Binary Protections ────────────────────────────────────────────────
echo ""
echo "── M7: Binary Protections ───────────────────"

if [ -f "$PROJECT/android/app/build.gradle" ]; then
  if grep -A10 'buildTypes' "$PROJECT/android/app/build.gradle" | \
       grep -A5 'release' | grep -q 'minifyEnabled false'; then
    fail "ProGuard/R8 disabled for release builds"
  else pass "ProGuard/R8 appears enabled"; fi

  if grep -q 'android:debuggable="true"' "$PROJECT/android/app/src/main/AndroidManifest.xml" 2>/dev/null; then
    fail "App is debuggable in release"
  else pass "Debuggable not set to true in main manifest"; fi
fi

if ls "$PROJECT/.github/workflows/"*.yml 2>/dev/null | head -1 | xargs grep -l "flutter build" 2>/dev/null; then
  if grep -r "flutter build" "$PROJECT/.github/workflows/" 2>/dev/null | \
       grep -E "release|appbundle|apk" | grep -qv "\-\-obfuscate"; then
    warn "Some CI release builds may be missing --obfuscate flag"
  else pass "CI build commands include --obfuscate"; fi
fi

# ── M8: Misconfiguration ──────────────────────────────────────────────────
echo ""
echo "── M8: Configuration ────────────────────────"

if [ -f "$PROJECT/android/app/src/main/AndroidManifest.xml" ]; then
  if grep -q 'android:allowBackup="true"' "$PROJECT/android/app/src/main/AndroidManifest.xml"; then
    warn "Android backup enabled — ensure backup rules exclude sensitive data"
  else pass "Android backup disabled or restricted"; fi

  EXPORTED=$(grep -c 'android:exported="true"' "$PROJECT/android/app/src/main/AndroidManifest.xml" 2>/dev/null || echo 0)
  if [ "$EXPORTED" -gt 1 ]; then
    warn "$EXPORTED exported components — verify each requires public access"
  else pass "No unexpected exported components"; fi
fi

# ── M9: Data Storage ──────────────────────────────────────────────────────
echo ""
echo "── M9: Storage Security ─────────────────────"

if grep -rn "openDatabase\b" "$PROJECT/lib" --include="*.dart" 2>/dev/null | \
     grep -qv "password:" | grep -qv test/; then
  warn "SQLite openDatabase without password parameter — verify no sensitive data stored"
else pass "SQLite uses encryption or no sensitive data"; fi

if grep -rn "getTemporaryDirectory\|writeAsString" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/ | \
     grep -iE "token|password|secret|key" | grep .; then
  fail "Sensitive data may be written to temporary files"
else pass "No sensitive data in temp file writes"; fi

# ── M10: Cryptography ─────────────────────────────────────────────────────
echo ""
echo "── M10: Cryptography ────────────────────────"

if grep -rn "md5\.convert" "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "MD5 used for security purpose — replace with SHA-256"
else pass "No MD5 security usage found"; fi

if grep -rn "sha1\.convert" "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "SHA-1 used — replace with SHA-256 or SHA-512"
else pass "No SHA-1 usage found"; fi

if grep -rn "AESMode\.ecb\|'AES/ECB'" "$PROJECT/lib" --include="*.dart" 2>/dev/null | grep -v test/; then
  fail "AES-ECB mode used — use AES-GCM instead"
else pass "No AES-ECB usage found"; fi

if grep -rn "Random()" "$PROJECT/lib" --include="*.dart" 2>/dev/null | \
     grep -v "Random\.secure()" | grep -v test/ | grep .; then
  warn "Random() found — use Random.secure() for any cryptographic purpose"
else pass "Cryptographic RNG is secure"; fi

# ── Debug Features ────────────────────────────────────────────────────────
echo ""
echo "── Debug / Extraneous Features ──────────────"

if grep -rE "['\"]/(debug|test|dev|admin)['\"]" "$PROJECT/lib" \
     --include="*.dart" 2>/dev/null | grep -v test/ | grep -v "kDebugMode"; then
  fail "Debug routes accessible in production code"
else pass "No unguarded debug routes"; fi

if grep -rn "^\s*print(" "$PROJECT/lib" --include="*.dart" 2>/dev/null | \
     grep -v test/ | grep -v "kDebugMode" | grep .; then
  warn "print() without kDebugMode guard — use conditional logging"
else pass "No unconditional print() statements"; fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
if [ $FAIL -eq 0 ]; then
  echo "  ✅ SCAN PASSED — No critical issues found"
else
  echo "  ❌ SCAN FAILED — Fix issues before release"
  exit 1
fi
```

## Scan Coverage Matrix

| Mobile Top 10 | Automated Checks |
|---|---|
| M1: Improper Credential Usage | API keys (Google, AWS, Stripe), private keys, generic secrets |
| M2: Inadequate Supply Chain Security | `dart pub audit`, unpinned dependencies |
| M3: Insecure Authentication | Tokens in SharedPreferences, auth bypass, tokens in globals |
| M4: Insufficient Input/Output Validation | WebView without NavigationDelegate, JavaScript bridges |
| M5: Insecure Communication | HTTP URLs, SSL bypass, cleartext traffic config, iOS ATS |
| M6: Inadequate Privacy Controls | PII in logs, PII in analytics, unsanitized crash reports |
| M7: Insufficient Binary Protections | ProGuard/R8, debuggable flag, CI obfuscation |
| M8: Security Misconfiguration | Backup enabled, exported components |
| M9: Insecure Data Storage | Unencrypted SQLite, sensitive data in temp files |
| M10: Insufficient Cryptography | MD5, SHA-1, AES-ECB, insecure Random() |

> **Note:** Additional manual checks are required for full coverage.
> See `references/owasp_masvs_checklist.md` for the complete MASVS checklist.
