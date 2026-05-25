# Test Optimization — Sharding, Concurrency, Flaky Tests

Tests are usually the slowest part of the quality gate. These techniques
cut test time by 50–70% without reducing coverage.

---

## 1. Test Concurrency — Run Tests in Parallel

Flutter supports running test files concurrently with `--concurrency`.

```bash
# Default: 1 concurrent test process
flutter test

# ✅ Run 4 test files concurrently
flutter test --concurrency=4

# ✅ Recommended: match CPU count of the runner
flutter test --concurrency=$(nproc)   # Linux
flutter test --concurrency=$(sysctl -n hw.ncpu)  # macOS
```

```yaml
# In GitHub Actions
- name: Run tests
  run: flutter test --coverage --concurrency=4 --reporter=github
```

**Saving:** 40–60% of test time on multi-core runners (ubuntu-latest has 2 cores, macos-latest has 3).

**Important:** Tests must be independent — no shared mutable state between test files.

---

## 2. Test Sharding — Split Across Multiple Runners

For large test suites (> 200 tests), split them across multiple parallel runners.

```yaml
jobs:
  test:
    strategy:
      matrix:
        shard: [1, 2, 3, 4]   # 4 shards = 4 parallel runners
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'
          cache: true
      - uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
      - run: flutter pub get

      - name: Run test shard ${{ matrix.shard }} of 4
        run: |
          # Get all test files
          TEST_FILES=$(find test -name "*_test.dart" | sort)
          TOTAL=$(echo "$TEST_FILES" | wc -l)
          SHARD_SIZE=$(( (TOTAL + 3) / 4 ))  # ceiling division
          SHARD_INDEX=$(( ${{ matrix.shard }} - 1 ))
          START=$(( SHARD_INDEX * SHARD_SIZE + 1 ))
          END=$(( START + SHARD_SIZE - 1 ))

          SHARD_FILES=$(echo "$TEST_FILES" | sed -n "${START},${END}p")
          echo "Running shard ${{ matrix.shard }}: $(echo "$SHARD_FILES" | wc -l) files"

          flutter test --coverage --concurrency=4 $SHARD_FILES

      - name: Upload coverage shard
        uses: actions/upload-artifact@v4
        with:
          name: coverage-shard-${{ matrix.shard }}
          path: coverage/lcov.info

  # Merge coverage from all shards
  coverage:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download all coverage shards
        uses: actions/download-artifact@v4
        with:
          pattern: coverage-shard-*
          merge-multiple: false
          path: coverage-shards/

      - name: Merge coverage reports
        run: |
          sudo apt-get install -y lcov
          # Merge all shard lcov files
          MERGE_ARGS=""
          for dir in coverage-shards/*/; do
            MERGE_ARGS="$MERGE_ARGS -a ${dir}lcov.info"
          done
          lcov $MERGE_ARGS -o coverage/merged.info

          # Remove generated files
          lcov --remove coverage/merged.info \
            '*.freezed.dart' '*.g.dart' '*.config.dart' \
            -o coverage/filtered.info

          # Check threshold
          COVERAGE=$(lcov --summary coverage/filtered.info 2>&1 \
            | grep "lines" | awk '{print $2}' | tr -d '%')
          echo "Total coverage: ${COVERAGE}%"
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "❌ Coverage ${COVERAGE}% below 80%"
            exit 1
          fi
```

**Saving:** With 4 shards, a 20-minute test suite becomes ~5 minutes.

---

## 3. Test by Category — Run Fast Tests First

Organize tests by speed and run them in order. Fail fast on unit tests before
running slower integration tests.

```yaml
jobs:
  unit-tests:
    name: Unit Tests (fast)
    runs-on: ubuntu-latest
    steps:
      - # ... setup
      - name: Run unit tests only
        run: flutter test test/unit/ --concurrency=4

  widget-tests:
    name: Widget Tests (medium)
    needs: unit-tests   # only run if unit tests pass
    runs-on: ubuntu-latest
    steps:
      - # ... setup
      - name: Run widget tests
        run: flutter test test/widget/ --concurrency=2

  integration-tests:
    name: Integration Tests (slow)
    needs: widget-tests  # only run if widget tests pass
    runs-on: ubuntu-latest
    steps:
      - # ... setup
      - name: Run integration tests
        run: flutter test test/integration/
```

---

## 4. Coverage Filtering — Exclude Generated Files

Generated files inflate coverage numbers and slow down lcov processing.
Always filter them out.

```bash
# Remove generated files from coverage report
lcov --remove coverage/lcov.info \
  '*.freezed.dart' \
  '*.g.dart' \
  '*.config.dart' \
  '*.gr.dart' \
  '*/injection.config.dart' \
  -o coverage/filtered.info

# Show summary
lcov --summary coverage/filtered.info
```

```yaml
- name: Filter and check coverage
  run: |
    sudo apt-get install -y lcov
    lcov --remove coverage/lcov.info \
      '*.freezed.dart' '*.g.dart' '*.config.dart' \
      -o coverage/filtered.info

    COVERAGE=$(lcov --summary coverage/filtered.info 2>&1 \
      | grep "lines" | awk '{print $2}' | tr -d '%')
    echo "Coverage: ${COVERAGE}%"

    if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      echo "❌ Coverage ${COVERAGE}% is below 80% threshold"
      exit 1
    fi
    echo "✅ Coverage ${COVERAGE}% meets threshold"
```

---

## 5. Flaky Test Management

Flaky tests are tests that sometimes pass and sometimes fail without code changes.
They destroy CI reliability and waste developer time.

### Detect flaky tests

```bash
# Run the same test 10 times to detect flakiness
for i in {1..10}; do
  flutter test test/path/to/suspected_flaky_test.dart
  echo "Run $i: $?"
done
```

### Quarantine flaky tests

```dart
// Mark flaky tests with a tag — exclude from main CI
@Tags(['flaky'])
void main() {
  test('this test is flaky', () {
    // ...
  });
}
```

```yaml
# Main CI — exclude flaky tests
- run: flutter test --exclude-tags flaky

# Nightly job — run flaky tests separately to track them
- run: flutter test --tags flaky
```

### Common causes of flaky tests

```dart
// ❌ Time-dependent — flaky on slow CI runners
test('should complete within 100ms', () async {
  final stopwatch = Stopwatch()..start();
  await doSomething();
  expect(stopwatch.elapsedMilliseconds, lessThan(100)); // flaky!
});

// ✅ Use fake async instead
test('should complete', () async {
  await fakeAsync((async) async {
    await doSomething();
    async.elapse(const Duration(milliseconds: 100));
    // verify result
  });
});

// ❌ Shared state between tests — flaky when run in parallel
int counter = 0;  // global state

// ✅ Isolate state in setUp/tearDown
setUp(() => counter = 0);
tearDown(() => counter = 0);
```

---

## 6. Test Reporter — Better CI Output

```yaml
- name: Run tests
  run: flutter test --coverage --reporter=github   # ✅ GitHub-native annotations

# For detailed HTML report
- name: Generate HTML coverage report
  run: genhtml coverage/filtered.info -o coverage/html

- name: Upload HTML coverage
  uses: actions/upload-artifact@v4
  with:
    name: coverage-html
    path: coverage/html/
```

---

## 7. Skip Tests on Non-Code Changes

```yaml
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      tests-needed: ${{ steps.filter.outputs.dart }}
    steps:
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            dart:
              - 'lib/**'
              - 'test/**'
              - 'pubspec.lock'

  test:
    needs: changes
    if: needs.changes.outputs.tests-needed == 'true'
    runs-on: ubuntu-latest
    steps:
      - run: flutter test --concurrency=4
```

---

## Time Budget — Test Suite Targets

| Test suite size | Target time | Technique |
|---|---|---|
| < 50 tests | < 1 min | `--concurrency=4` |
| 50–200 tests | < 3 min | `--concurrency=4` + coverage filtering |
| 200–500 tests | < 5 min | 2–4 shards + `--concurrency=4` |
| > 500 tests | < 8 min | 4–8 shards + category split |
