---
name: flutter-ds-asset-management
description: >
  Graphic asset management (SVGs, icons, images) for the Design System.
  Use when downloading assets from Figma, optimizing SVGs, registering
  resources in centralized classes, or referencing assets in widget code.
commands:
  - manage-ds-assets
inputs:
  - name: action
    description: Action to perform (register, optimize, audit). "register" adds new assets to the centralized resource class and pubspec.yaml, "optimize" runs SVGO on SVG files to clean metadata, "audit" checks for hardcoded asset paths, unregistered assets, or missing pubspec declarations.
    required: true
  - name: target
    description: Path to the assets directory or specific asset file (e.g. assets/icons/ for audit, assets/icons/icon_close.svg for register/optimize).
    required: true
  - name: asset_type
    description: Type of asset (icon, illustration, logo). Determines the registry class and target directory.
    required: false
metadata:
  author: pragma-ds
  version: "1.1"
  domain: flutter-design-system
---

# Asset Management

## Asset Types

> Las rutas `assets/...` de este documento son rutas del proyecto Flutter
> objetivo (paquete/app), no rutas internas del skill.

| Type | Format | Location | Registry |
|------|--------|----------|----------|
| DS Icons | SVG | `assets/icons/` | `{{DS_PREFIX}}Icons` class |
| Illustrations | SVG/PNG | `assets/illustrations/` | `{{DS_PREFIX}}Illustrations` class |
| Logos | SVG | `assets/logos/` | `{{DS_PREFIX}}Logos` class |

## Process

### 1. Download
- Export from Figma as SVG (preferred)
- Name: `snake_case` descriptive (e.g., `icon_close.svg`)

### 2. Optimize (SVG)
```bash
svgo input.svg -o output.svg --multipass
```
- Clean XML (no unnecessary Figma metadata)
- No heavy inline styles
- Correct viewbox
- Optimized paths

### 3. Register
```dart
abstract class {{DS_PREFIX}}AppResources {
  /// Close icon.
  static const String iconClose = 'assets/icons/icon_close.svg';
}
```

### 4. Declare in pubspec
```yaml
flutter:
  assets:
    - assets/icons/
    - assets/illustrations/
    - assets/logos/
```

## Usage in Widgets

```dart
// ✅ CORRECT — Centralized reference
SvgPicture.asset(
  {{DS_PREFIX}}AppResources.iconClose,
  width: {{DS_PREFIX}}Sizes.iconMd,
  height: {{DS_PREFIX}}Sizes.iconMd,
  colorFilter: ColorFilter.mode(/* color token */, BlendMode.srcIn),
)

// ❌ Hardcoded path
SvgPicture.asset('assets/icons/icon_close.svg')

// ❌ Hardcoded size
SvgPicture.asset(icon, width: 24, height: 24)
```

## Checklist

- [ ] Asset downloaded and placed in correct folder
- [ ] SVG optimized (no unnecessary metadata)
- [ ] Variable registered in resource class
- [ ] Declared in `pubspec.yaml` under `flutter.assets`
- [ ] Render size uses size token
- [ ] Color uses semantic token (not hardcoded)
