#!/bin/bash
# lint_fix.sh
# Usage: bash scripts/lint_fix.sh [project_path]
# Applies dart fix, formats code, and runs the analyzer.

PROJECT="${1:-.}"

echo "╔══════════════════════════════════════╗"
echo "║     Automatic Lint Fix              ║"
echo "╚══════════════════════════════════════╝"

cd "$PROJECT" || exit 1

echo ""
echo "── Step 1: dart fix (auto-fix lint violations) ──────"
dart fix --apply
echo "  ✅ dart fix applied"

echo ""
echo "── Step 2: dart format ──────────────────────────────"
dart format lib/ test/
echo "  ✅ dart format applied"

echo ""
echo "── Step 3: flutter analyze ──────────────────────────"
flutter analyze --fatal-infos
ANALYZE_EXIT=$?
if [ $ANALYZE_EXIT -eq 0 ]; then
  echo "  ✅ flutter analyze: no issues"
else
  echo "  ❌ flutter analyze found issues — fix manually"
  exit $ANALYZE_EXIT
fi

echo ""
echo "── Step 4: Check import order ───────────────────────"
IMPORT_ISSUES=$(grep -rn "^import 'dart:" lib/ --include="*.dart" -l | \
  while read -r file; do
    dart_line=$(grep -n "^import 'dart:" "$file" | head -1 | cut -d: -f1)
    pkg_line=$(grep -n "^import 'package:" "$file" | head -1 | cut -d: -f1)
    if [ -n "$dart_line" ] && [ -n "$pkg_line" ] && [ "$pkg_line" -lt "$dart_line" ]; then
      echo "  $file (dart: import after package:)"
    fi
  done)

if [ -n "$IMPORT_ISSUES" ]; then
  echo "  ⚠️  Import order issues (fix manually):"
  echo "$IMPORT_ISSUES"
else
  echo "  ✅ Import order correct"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  ✅ All automatic fixes applied"
