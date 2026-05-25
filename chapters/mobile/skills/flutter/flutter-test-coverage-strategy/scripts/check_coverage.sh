#!/bin/bash
# check_coverage.sh
# Usage: bash scripts/check_coverage.sh [threshold] [project_path]
# Runs tests with coverage and enforces the minimum threshold.
# Defaults: threshold=80, project_path=current directory

THRESHOLD="${1:-80}"
PROJECT="${2:-.}"

cd "$PROJECT" || exit 1

echo "╔══════════════════════════════════════════╗"
echo "║      Flutter Test Coverage Check        ║"
echo "╚══════════════════════════════════════════╝"
echo "  Threshold : ${THRESHOLD}%"
echo "  Project   : $(pwd)"
echo ""

# ── Prerequisite: lcov ────────────────────────────────────────────────────────
if ! command -v lcov &> /dev/null; then
  echo "  lcov not found — installing..."
  sudo apt-get install -y lcov 2>/dev/null || brew install lcov 2>/dev/null
  if ! command -v lcov &> /dev/null; then
    echo "  ❌ Could not install lcov. Install it manually and retry."
    exit 1
  fi
fi

# ── Step 1: Run tests with coverage ──────────────────────────────────────────
echo "── Step 1: Run tests with coverage ──────────"
flutter test --coverage --reporter=compact --concurrency=4
TEST_EXIT=$?
if [ $TEST_EXIT -ne 0 ]; then
  echo ""
  echo "  ❌ Tests failed — fix failing tests before checking coverage."
  exit $TEST_EXIT
fi
echo "  ✅ All tests passed"

# ── Step 2: Filter generated files ───────────────────────────────────────────
echo ""
echo "── Step 2: Filter generated files ───────────"
lcov \
  --remove coverage/lcov.info \
  '*.freezed.dart' \
  '*.g.dart' \
  '*.gr.dart' \
  '*.config.dart' \
  '*/injection.dart' \
  '*/injection_container.dart' \
  -o coverage/lcov_filtered.info 2>/dev/null

echo "  ✅ Generated files excluded from coverage"

# ── Step 3: Coverage summary ──────────────────────────────────────────────────
echo ""
echo "── Step 3: Coverage summary ──────────────────"
lcov --summary coverage/lcov_filtered.info 2>&1

# ── Step 4: Enforce threshold ─────────────────────────────────────────────────
echo ""
echo "── Step 4: Enforce ${THRESHOLD}% threshold ──────────────"
COVERAGE=$(lcov --summary coverage/lcov_filtered.info 2>&1 \
  | grep "lines" | grep -oP '\d+\.\d+(?=%)' | head -1)

if [ -z "$COVERAGE" ]; then
  echo "  ❌ Could not parse coverage value from lcov output."
  exit 1
fi

echo "  Coverage  : ${COVERAGE}%"
echo "  Threshold : ${THRESHOLD}%"
echo ""

python3 -c "
cov    = float('$COVERAGE')
thresh = float('$THRESHOLD')
if cov < thresh:
    print(f'  ❌ FAIL: {cov:.1f}% is below the {thresh:.0f}% minimum threshold')
    raise SystemExit(1)
else:
    print(f'  ✅ PASS: {cov:.1f}% meets the {thresh:.0f}% minimum threshold')
"
THRESHOLD_EXIT=$?

# ── Step 5: Generate HTML report ──────────────────────────────────────────────
echo ""
echo "── Step 5: Generate HTML report ─────────────"
genhtml coverage/lcov_filtered.info \
  -o coverage/html \
  --title "Flutter Coverage Report" \
  --quiet

echo "  ✅ HTML report: coverage/html/index.html"

# Open report automatically on macOS (skip in CI)
if [[ "$CI" != "true" && "$(uname)" == "Darwin" ]]; then
  open coverage/html/index.html
fi

exit $THRESHOLD_EXIT
