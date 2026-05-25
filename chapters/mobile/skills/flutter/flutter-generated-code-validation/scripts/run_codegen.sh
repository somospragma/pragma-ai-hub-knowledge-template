#!/bin/bash
# run_codegen.sh
# Usage: bash scripts/run_codegen.sh [watch|build|clean|verify] [project_path]
# Manages code generation with build_runner

MODE="${1:-build}"
PROJECT="${2:-.}"

cd "$PROJECT" || exit 1

echo "╔══════════════════════════════════════╗"
echo "║     Flutter Code Generation         ║"
echo "╚══════════════════════════════════════╝"

case "$MODE" in
  watch)
    echo "  Starting build_runner in watch mode..."
    dart run build_runner watch --delete-conflicting-outputs
    ;;

  build)
    echo "  Running one-time build..."
    dart run build_runner build --delete-conflicting-outputs
    EXIT=$?
    if [ $EXIT -eq 0 ]; then
      echo "  ✅ Code generation completed"
      echo ""
      echo "  Generated files:"
      find lib/ -name "*.g.dart" -o -name "*.freezed.dart" \
           -o -name "*.gr.dart" -o -name "*.config.dart" 2>/dev/null | sort
    else
      echo "  ❌ Code generation failed"
      exit $EXIT
    fi
    ;;

  clean)
    echo "  Cleaning generated files and cache..."
    dart run build_runner clean
    echo "  ✅ Clean complete. Run 'build' to regenerate."
    ;;

  verify)
    echo "  Verifying that generated files are up to date..."
    dart run build_runner build --delete-conflicting-outputs
    if git diff --exit-code -- "*.g.dart" "*.freezed.dart" "*.gr.dart" "*.config.dart" 2>/dev/null; then
      echo "  ✅ Generated files are up to date"
    else
      echo "  ❌ Generated files are out of date — commit the changes"
      exit 1
    fi
    ;;

  *)
    echo "  Usage: bash scripts/run_codegen.sh [watch|build|clean|verify]"
    echo "    watch  — continuous generation during development"
    echo "    build  — one-time build (default)"
    echo "    clean  — clear cache + generated files"
    echo "    verify — CI check: generated files match source"
    exit 1
    ;;
esac
