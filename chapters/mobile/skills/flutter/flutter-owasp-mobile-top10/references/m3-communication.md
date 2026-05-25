# M3 — Insecure Communication

This category covers network security issues including HTTP without TLS, certificate validation bypass, and insecure WebViews.

---

## Check M3-A: HTTP traffic without TLS

**ID:** `M3-A-HTTP-PLAINTEXT`
**Objective:** Detect HTTP (non-HTTPS) endpoints and certificate validation bypass.
**Scope:** `lib/**.dart`, `AndroidManifest.xml`, `Info.plist`

**Method:** Lexical search
**Insecure patterns in Dart:**

```dart
// PATTERN 1: HTTP URL
final response = await http.get(Uri.parse('http://api.example.com'));  // ❌ INSECURE

// PATTERN 2: SSL certificate bypass
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;  // ❌ DANGER
  }
}

// PATTERN 3: Dio without SSL validation
(dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () =>
    HttpClient()..badCertificateCallback = (cert, host, port) => true;  // ❌ DANGER
```

**Lexical search:**
```regex
['"]http://(?!localhost|127\.0\.0\.1)
badCertificateCallback\s*=\s*\([^)]*\)\s*=>\s*true
onHttpClientCreate.*badCertificateCallback
```

**Android — Cleartext Traffic:**
```xml
<!-- AndroidManifest.xml -->
<application android:usesCleartextTraffic="true">  <!-- ❌ DANGER -->
```

**iOS — ATS Bypass:**
```xml
<key>NSAllowsArbitraryLoads</key>
<true/>  <!-- ❌ DANGER -->
```

**Criteria:**
- ❌ **Fail:** `http://` URLs (except localhost in debug)
- ❌ **Fail:** `badCertificateCallback` returning `true`
- ❌ **Fail:** `usesCleartextTraffic="true"` on Android
- ✅ **Pass:** HTTPS only + certificate validation enabled

**Severity:** `CRITICAL`
**Automation:** 🟢 High (95%)

**Remediation:**

```dart
// ✅ Always use HTTPS
final response = await http.get(Uri.parse('https://api.example.com'));

// ✅ NEVER disable SSL validation in production
import 'package:flutter/foundation.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) {
        if (kDebugMode && host == 'dev.example.com') {
          return true;  // Only in debug, only for dev server
        }
        return false;  // ✅ Validate in production
      };
  }
}
```

```xml
<!-- AndroidManifest.xml -->
<application android:usesCleartextTraffic="false">  <!-- ✅ SECURE -->
```

```xml
<!-- res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </base-config>
    <!-- Debug overrides only -->
    <debug-overrides>
        <trust-anchors>
            <certificates src="user"/>
        </trust-anchors>
    </debug-overrides>
</network-security-config>
```

---

## Check M3-B: WebView with insecure configuration

**ID:** `M3-B-INSECURE-WEBVIEW`
**Objective:** Detect WebViews with JavaScript enabled but without URL validation.
**Scope:** `lib/**.dart`

**Method:** Lexical + semantic search
**Insecure patterns:**

```dart
// PATTERN 1: JavaScript enabled without restrictions
WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..loadRequest(Uri.parse(userProvidedUrl));  // ❌ Unvalidated URL

// PATTERN 2: No NavigationDelegate
WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted);
  // No navigation control ❌

// PATTERN 3: JavaScript channel without input validation
controller.addJavaScriptChannel(
  'MessageHandler',
  onMessageReceived: (message) {
    eval(message.message);  // ❌❌ EXTREME DANGER
  },
);
```

**Lexical search:**
```regex
setJavaScriptMode.*unrestricted(?!.*NavigationDelegate)
WebViewController\((?!.*NavigationDelegate)
addJavaScriptChannel.*onMessageReceived.*(?!.*validate)
```

**Criteria:**
- ❌ **Fail:** JavaScript enabled + unvalidated URLs
- ❌ **Fail:** JavaScript channels without input sanitization
- ✅ **Pass:** JavaScript disabled OR strict URL allowlisting

**Severity:** `HIGH`
**Automation:** 🟢 High (80%)

**Remediation:**

```dart
// ✅ SOLUTION 1: Disable JavaScript if not needed
WebViewController()
  ..setJavaScriptMode(JavaScriptMode.disabled)
  ..loadRequest(Uri.parse('https://trusted-domain.com/content'));

// ✅ SOLUTION 2: JavaScript with strict URL validation
WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..setNavigationDelegate(NavigationDelegate(
    onNavigationRequest: (request) {
      final uri = Uri.parse(request.url);
      const allowedHosts = {'trusted-domain.com', 'api.trusted-domain.com'};

      if (!allowedHosts.contains(uri.host) || uri.scheme != 'https') {
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    },
  ))
  ..addJavaScriptChannel(
    'MessageHandler',
    onMessageReceived: (message) {
      // ✅ Sanitize before processing
      final sanitized = _sanitizeInput(message.message);
      _handleMessage(sanitized);
    },
  );

String _sanitizeInput(String input) {
  return input
      .replaceAll(RegExp(r'<script.*?>.*?</script>', caseSensitive: false), '')
      .replaceAll(RegExp(r'[<>"\']'), '');
}
```

---

## M3 Summary

| Check | Severity | Automation | Fix Effort |
|---|---|---|---|
| M3-A | CRITICAL | 🟢 95% | High |
| M3-B | HIGH | 🟢 80% | Medium |

**Total checks:** 2 | **Critical:** 1 | **High:** 1 | **Medium:** 0 | **Low:** 0

**Last updated:** April 2026 | **Version:** 2.0
