---
name: flutter-ds-widget-anatomy
description: >
  Standard internal structure for a Design System widget file.
  Use when writing or reviewing Flutter widget code to ensure correct
  ordering of imports, constructor, properties, build methods,
  resolvers, enums, and helper classes.
commands:
  - review-widget-anatomy
inputs:
  - name: action
    description: Action to perform (review, scaffold). "review" checks an existing widget file against the anatomy rules (ordering, naming, limits), "scaffold" generates a new DS widget file following the correct structure.
    required: true
  - name: target
    description: Path to the widget file to review or the directory where the new widget will be created (e.g. lib/ui_system/atoms/button/ds_button.dart).
    required: true
  - name: name
    description: Name of the widget to scaffold (e.g. Button, Card, Badge). Required when action is "scaffold".
    required: false
metadata:
  author: pragma-ds
  version: "1.2"
  domain: flutter-design-system
---

# Widget Anatomy

## File Structure Order

Every DS widget file follows this strict order:

### 1. Imports
```dart
import 'package:flutter/material.dart';
import 'package:{{package_name}}/tokens/spacing_tokens.dart';
// Package imports always (never relative). Grouped: flutter → DS → third-party
```

### 2. Widget Class
```dart
class {{DS_PREFIX}}WidgetName extends StatelessWidget {
  const {{DS_PREFIX}}WidgetName({
    super.key,
    required this.label,
    this.variant = Variant.primary,
    this.state = State.default_,
    this.onPressed,
  });

  final String label;

  bool get _isInteractive => state != ...State.disabled && onPressed != null;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ...State.loading => _buildLoading(context),
      ...State.disabled => _buildDisabled(context),
      _ => _buildDefault(context),
    };
  }

  Widget _buildDefault(BuildContext context) { /* ... */ }
  Widget _buildLoading(BuildContext context) { /* ... */ }
  Widget _buildDisabled(BuildContext context) {
    return Opacity(opacity: 0.5, child: IgnorePointer(child: _buildDefault(context)));
  }

  Color _resolveBackgroundColor(BuildContext context) {
    return switch (variant) { /* token per variant */ };
  }
}
```

### 3. Enums
```dart
enum {{DS_PREFIX}}WidgetNameState { default_, disabled, loading, focused, error }
enum {{DS_PREFIX}}WidgetNameVariant { primary, secondary }
enum {{DS_PREFIX}}WidgetNameSize { sm, md, lg }
```

### 4. Private Helper Classes (if needed)

## Rules

1. **1 public widget per file** — no exceptions
2. **Enums** go in the same file, after the widget
3. **Private helpers** only if simple (< 30 lines)
4. **Imports**: package imports grouped and sorted
5. **Constructor**: `const`, `super.key`, required first, callbacks last
6. **Properties**: `final`, self-explanatory names
7. **Build**: delegates to `_build*` methods — never a giant build
8. **Resolvers**: `_resolve*` methods for token logic per variant/state
9. **Limits**: ~200 lines per file, ~30 lines per method
10. **Comments**: avoid inline/block/doc comments by default; allow only
    fundamental, non-obvious technical notes
