# Platform Configuration — Android and iOS

## Android — Network Security Config

Android's Network Security Config is the **platform-native** way to configure
certificate pinning. It applies to all network traffic from the app, including
WebViews and third-party SDKs.

### 1. Create the config file

```xml
<!-- android/app/src/main/res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>

    <!-- Production API — certificate pinning enabled -->
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="false">api.yourapp.com</domain>
        <domain includeSubdomains="false">auth.yourapp.com</domain>

        <pin-set expiration="2027-01-01">
            <!-- Current intermediate CA public key (SPKI SHA-256) -->
            <pin digest="SHA-256">CURRENT_SPKI_HASH_BASE64==</pin>
            <!-- Backup pin — pre-staged for next rotation -->
            <!-- Generate this BEFORE the rotation, not during -->
            <pin digest="SHA-256">BACKUP_SPKI_HASH_BASE64==</pin>
        </pin-set>

        <!-- Trust only the system CA store — no user-installed CAs -->
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </domain-config>

    <!-- CDN / static assets — no pinning needed, but enforce TLS -->
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="true">cdn.yourapp.com</domain>
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </domain-config>

    <!-- Default: block all cleartext traffic -->
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </base-config>

</network-security-config>
```

> **`expiration` attribute**: When the expiration date passes, Android disables
> pinning for that domain (fails open). This is a safety net — not a rotation mechanism.
> Always rotate pins before expiration. Set expiration ~2 years out and update it
> with each rotation.

### 2. Reference in AndroidManifest.xml

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<application
    android:networkSecurityConfig="@xml/network_security_config"
    android:usesCleartextTraffic="false"
    ...>
```

### 3. Debug override — separate config for development

```xml
<!-- android/app/src/debug/res/xml/network_security_config.xml -->
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Debug: trust user-installed CAs (for Charles Proxy, mitmproxy) -->
    <!-- ⚠️ NEVER include this in release builds -->
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system"/>
            <certificates src="user"/>  <!-- allows proxy tools in debug -->
        </trust-anchors>
    </base-config>
</network-security-config>
```

```xml
<!-- android/app/src/debug/AndroidManifest.xml -->
<application
    android:networkSecurityConfig="@xml/network_security_config">
</application>
```

---

## iOS — App Transport Security (ATS)

iOS enforces TLS by default via ATS. Certificate pinning is implemented in code
(see `flutter_implementation.md`). ATS configuration ensures no cleartext fallback.

### Info.plist — enforce TLS, no exceptions

```xml
<!-- ios/Runner/Info.plist -->
<dict>
    <!-- ✅ ATS enabled by default — do NOT add NSAppTransportSecurity unless needed -->
    <!-- If you must configure ATS, use the strictest settings: -->

    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- ❌ Never set NSAllowsArbitraryLoads to true in production -->
        <!-- <key>NSAllowsArbitraryLoads</key><false/> -->

        <!-- If specific domains need configuration: -->
        <key>NSExceptionDomains</key>
        <dict>
            <key>api.yourapp.com</key>
            <dict>
                <!-- Require TLS 1.2+ -->
                <key>NSExceptionMinimumTLSVersion</key>
                <string>TLSv1.2</string>
                <!-- Require forward secrecy -->
                <key>NSExceptionRequiresForwardSecrecy</key>
                <true/>
                <!-- No cleartext -->
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <false/>
            </dict>
        </dict>
    </dict>
</dict>
```

### iOS debug — allow proxy tools

For development with Charles Proxy or mitmproxy on iOS, you need to install
the proxy's CA certificate on the device and trust it in Settings.
**Do not modify ATS for this** — install the CA cert manually on the test device.

---

## Build Flavor Separation

Use Flutter flavors to apply different pinning configs per environment:

```dart
// lib/core/config/app_config.dart
enum AppEnvironment { development, staging, production }

abstract final class AppConfig {
  static AppEnvironment get environment {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'production');
    return switch (env) {
      'development' => AppEnvironment.development,
      'staging' => AppEnvironment.staging,
      _ => AppEnvironment.production,
    };
  }

  static Set<String> get pins => switch (environment) {
    AppEnvironment.production => PinConfig.productionPins,
    AppEnvironment.staging => PinConfig.stagingPins,
    AppEnvironment.development => {}, // no pinning in dev — use proxy tools
  };

  static bool get isPinningEnabled =>
      environment != AppEnvironment.development;
}
```

```bash
# Build with environment
flutter build apk --dart-define=APP_ENV=production
flutter build apk --dart-define=APP_ENV=staging
flutter run --dart-define=APP_ENV=development
```

---

## Verifying Pinning is Active

### Android — verify with adb

```bash
# Run the app and attempt a network request
# If pinning is active, a MITM proxy will show connection errors

# Check Network Security Config is applied
adb shell dumpsys package com.example.yourapp | grep networkSecurityConfig
```

### iOS — verify with Xcode

```bash
# Run with Xcode → Console → filter for "pinning" or "certificate"
# A successful pin shows no errors
# A failed pin shows: "The certificate for this server is invalid"
```

### Both platforms — test with mitmproxy

```bash
# Start mitmproxy
mitmproxy --listen-port 8080

# Configure device to use proxy
# Attempt API call from app
# ✅ Expected: connection refused / certificate error
# ❌ If request succeeds: pinning is NOT working
```
