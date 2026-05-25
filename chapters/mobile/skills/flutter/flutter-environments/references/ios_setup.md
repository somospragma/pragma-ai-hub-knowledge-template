# iOS Setup — Schemes, xcconfig, Firebase, and Signing

`ios/Flutter/` · `ios/Runner.xcodeproj/`

---

## Table of Contents

1. [Schemes — Dev, Staging, Prod](#1-schemes--dev-staging-prod)
2. [xcconfig — build variables per environment](#2-xcconfig--build-variables-per-environment)
3. [GoogleService-Info.plist per scheme](#3-googleservice-infoplist-per-scheme)
4. [Run Script — copy the correct plist](#4-run-script--copy-the-correct-plist)
5. [Bundle ID and app name per flavor](#5-bundle-id-and-app-name-per-flavor)
6. [Signing — certificates and provisioning profiles](#6-signing--certificates-and-provisioning-profiles)

---

## 1. Schemes — Dev, Staging, Prod

Xcode > Product > Scheme > Manage Schemes → create three schemes:

| Scheme | Build Configuration (Run) | Build Configuration (Archive) |
|---|---|---|
| `Dev` | `Debug-dev` | `Release-dev` |
| `Staging` | `Debug-staging` | `Release-staging` |
| `Prod` | `Debug-prod` | `Release-prod` |

Each scheme is shared by checking **Shared** (generates the `.xcscheme` in
`xcshareddata/xcschemes/` and is committed to the repo).

### Create Build Configurations

Xcode > Project > Runner > Info > Configurations:
Duplicate `Debug` → `Debug-dev`, `Debug-staging`, `Debug-prod`
Duplicate `Release` → `Release-dev`, `Release-staging`, `Release-prod`

---

## 2. xcconfig — Build Variables per Environment

Flutter already uses `Debug.xcconfig` and `Release.xcconfig` in `ios/Flutter/`.
Extend that system by creating per-flavor configs that include them:

### ios/Flutter/Dev.xcconfig

```xcconfig
#include "Generated.xcconfig"
FLUTTER_TARGET=lib/main_dev.dart
APP_BUNDLE_ID=com.example.myapp.dev
APP_DISPLAY_NAME=MyApp Dev
FLUTTER_FLAVOR=dev
```

### ios/Flutter/Staging.xcconfig

```xcconfig
#include "Generated.xcconfig"
FLUTTER_TARGET=lib/main_staging.dart
APP_BUNDLE_ID=com.example.myapp.staging
APP_DISPLAY_NAME=MyApp Staging
FLUTTER_FLAVOR=staging
```

### ios/Flutter/Prod.xcconfig

```xcconfig
#include "Generated.xcconfig"
FLUTTER_TARGET=lib/main_prod.dart
APP_BUNDLE_ID=com.example.myapp
APP_DISPLAY_NAME=MyApp
FLUTTER_FLAVOR=prod
```

### Connect xcconfig to Build Configurations

In Xcode > Project > Runner > Info > Configurations:
- `Debug-dev`       → `ios/Flutter/Dev.xcconfig`
- `Debug-staging`   → `ios/Flutter/Staging.xcconfig`
- `Debug-prod`      → `ios/Flutter/Prod.xcconfig`
- `Release-dev`     → `ios/Flutter/Dev.xcconfig`
- `Release-staging` → `ios/Flutter/Staging.xcconfig`
- `Release-prod`    → `ios/Flutter/Prod.xcconfig`

### Info.plist — use xcconfig variables

```xml
<!-- ios/Runner/Info.plist -->
<key>CFBundleIdentifier</key>
<string>$(APP_BUNDLE_ID)</string>

<key>CFBundleDisplayName</key>
<string>$(APP_DISPLAY_NAME)</string>
```

---

## 3. GoogleService-Info.plist per Scheme

Download one `GoogleService-Info.plist` per Firebase project and place them:

```
ios/Runner/
├── GoogleService-Info-Dev.plist
├── GoogleService-Info-Staging.plist
└── GoogleService-Info-Prod.plist
```

**Do not add any of these to the "Copy Bundle Resources" Build Phase** —
the Run Script in the next step handles copying the correct one.

---

## 4. Run Script — Copy the Correct plist

In Xcode > Runner Target > Build Phases > + > New Run Script Phase.
Drag the script **before** "Copy Bundle Resources":

```bash
# Selects the correct GoogleService-Info.plist based on the active flavor.
# FLUTTER_FLAVOR is defined in the active xcconfig.

PLIST_SOURCE="${SRCROOT}/Runner/GoogleService-Info-${FLUTTER_FLAVOR^}.plist"
PLIST_DEST="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"

if [ ! -f "$PLIST_SOURCE" ]; then
  echo "error: GoogleService-Info-${FLUTTER_FLAVOR^}.plist not found"
  exit 1
fi

cp "$PLIST_SOURCE" "$PLIST_DEST"
echo "Copied: $PLIST_SOURCE → $PLIST_DEST"
```

> `${FLUTTER_FLAVOR^}` capitalizes the first letter: `dev` → `Dev`.

---

## 5. Bundle ID and App Name per Flavor

The `APP_BUNDLE_ID` and `APP_DISPLAY_NAME` defined in the xcconfig files
are applied in `Info.plist` via `$(APP_BUNDLE_ID)` and `$(APP_DISPLAY_NAME)`.

This allows installing all three flavors simultaneously on the same device —
each appears as an independent app with its own icon.

### Icons per Flavor

Xcode > Runner > Assets.xcassets → create three AppIcon sets:
- `AppIcon` → prod
- `AppIcon-Dev` → dev (with badge)
- `AppIcon-Staging` → staging (with badge)

In each xcconfig, add:

```xcconfig
# Dev.xcconfig
ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon-Dev

# Staging.xcconfig
ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon-Staging

# Prod.xcconfig
ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon
```

---

## 6. Signing — Certificates and Provisioning Profiles

### Xcode Configuration (manual signing recommended for CI)

In Xcode > Runner Target > Signing & Capabilities, disable
"Automatically manage signing" for Release configurations.

Assign per Build Configuration:

| Configuration | Bundle ID | Provisioning Profile |
|---|---|---|
| `Release-dev` | `com.example.myapp.dev` | `MyApp Dev Distribution` |
| `Release-staging` | `com.example.myapp.staging` | `MyApp Staging Distribution` |
| `Release-prod` | `com.example.myapp` | `MyApp Distribution` |

### ExportOptions.plist per Flavor

CI needs one `ExportOptions.plist` per flavor for `xcodebuild -exportArchive`:

```xml
<!-- ios/ExportOptions-prod.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>com.example.myapp</key>
        <string>MyApp Distribution</string>
    </dict>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
</dict>
</plist>
```

Create equivalent `ExportOptions-dev.plist` and `ExportOptions-staging.plist`
with their respective Bundle IDs and provisioning profiles.
