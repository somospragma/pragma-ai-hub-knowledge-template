# Parallelism, Conditional Builds, and Concurrency

---

## 1. Parallel Jobs — Android + iOS Simultaneously

The single biggest time saving on release pipelines. Android and iOS builds
are independent — run them in parallel after the quality gate passes.

```yaml
jobs:
  quality:
    runs-on: ubuntu-latest
    # ... quality gate steps

  build-android:
    needs: quality          # ✅ waits for quality, then runs in parallel with build-ios
    runs-on: ubuntu-latest
    # ... android build steps

  build-ios:
    needs: quality          # ✅ runs at the same time as build-android
    runs-on: macos-latest
    # ... ios build steps

  distribute:
    needs: [build-android, build-ios]   # waits for both
    # ... distribution steps
```

**Timeline comparison:**
```
Sequential:  quality(5m) → android(8m) → ios(10m) → distribute(3m) = 26 min
Parallel:    quality(5m) → android(8m) + ios(10m) → distribute(3m) = 18 min
                                         ↑ parallel
```

**Saving:** 5–10 minutes on every release build.

---

## 2. Concurrency Cancellation — Kill Stale PR Runs

When a developer pushes a new commit to a PR, cancel the previous run immediately.
Without this, old runs queue up and waste runner minutes.

```yaml
# At the top of every workflow file
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

**For release pipelines** — don't cancel in-progress releases:
```yaml
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false   # ✅ never cancel a release in progress
```

**Saving:** Eliminates queue buildup. On active PRs, can save 10–30 minutes of wasted runner time per day.

---

## 3. Path Filters — Skip Build When Unrelated Files Change

Don't run the full pipeline when only documentation, assets, or config files changed.

```yaml
# .github/workflows/pr.yml
on:
  pull_request:
    branches: [main, develop]
    paths:
      - 'lib/**'
      - 'test/**'
      - 'pubspec.yaml'
      - 'pubspec.lock'
      - 'android/**'
      - 'ios/**'
      - '.github/workflows/**'
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.gitignore'
      - 'LICENSE'
```

**For more granular control** — use `dorny/paths-filter`:

```yaml
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      dart: ${{ steps.filter.outputs.dart }}
      android: ${{ steps.filter.outputs.android }}
      ios: ${{ steps.filter.outputs.ios }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            dart:
              - 'lib/**'
              - 'test/**'
              - 'pubspec.yaml'
              - 'pubspec.lock'
            android:
              - 'android/**'
              - 'lib/**'
              - 'pubspec.lock'
            ios:
              - 'ios/**'
              - 'lib/**'
              - 'pubspec.lock'

  quality:
    needs: changes
    if: needs.changes.outputs.dart == 'true'   # skip if no Dart changes
    runs-on: ubuntu-latest
    steps:
      # ... quality gate

  build-android:
    needs: [changes, quality]
    if: needs.changes.outputs.android == 'true'
    runs-on: ubuntu-latest
    steps:
      # ... android build

  build-ios:
    needs: [changes, quality]
    if: needs.changes.outputs.ios == 'true'
    runs-on: macos-latest
    steps:
      # ... ios build
```

**Saving:** 5–15 minutes when only docs or assets change (entire pipeline skipped).

---

## 4. Conditional Steps — Skip Expensive Steps When Not Needed

```yaml
# Only run build_runner if generated files are outdated
- name: Check if build_runner needed
  id: check-generated
  run: |
    if git diff --quiet HEAD -- "*.g.dart" "*.freezed.dart"; then
      echo "needed=false" >> $GITHUB_OUTPUT
    else
      echo "needed=true" >> $GITHUB_OUTPUT
    fi

- name: Run build_runner
  if: steps.check-generated.outputs.needed == 'true'
  run: dart run build_runner build --delete-conflicting-outputs

# Only run CocoaPods install if Podfile.lock changed
- name: Check if pods need update
  id: check-pods
  run: |
    if git diff --quiet HEAD~1 HEAD -- ios/Podfile.lock; then
      echo "changed=false" >> $GITHUB_OUTPUT
    else
      echo "changed=true" >> $GITHUB_OUTPUT
    fi

- name: Install CocoaPods
  if: steps.check-pods.outputs.changed == 'true' || steps.pods-cache.outputs.cache-hit != 'true'
  run: cd ios && pod install
```

---

## 5. Matrix Builds — Test on Multiple Flutter Versions

For packages or plugins that need to support multiple Flutter versions:

```yaml
jobs:
  test:
    strategy:
      matrix:
        flutter-version: ['3.27.0', '3.32.0']
        os: [ubuntu-latest, macos-latest]
      fail-fast: false   # don't cancel other matrix jobs on first failure
    runs-on: ${{ matrix.os }}
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ matrix.flutter-version }}
          cache: true
      - run: flutter test
```

---

## 6. Fail Fast — Cheap Checks First

Order steps from cheapest to most expensive. Fail early to save time.

```yaml
steps:
  # 1. Fastest — format check (< 5s)
  - run: dart format --output=none --set-exit-if-changed lib/ test/

  # 2. Fast — static analysis (< 30s)
  - run: flutter analyze --fatal-infos

  # 3. Medium — unit tests (1–5 min)
  - run: flutter test --concurrency=4

  # 4. Slow — build (5–15 min) — only if above pass
  - run: flutter build appbundle --release
```

**Saving:** If format check fails, you save the entire test + build time.

---

## 7. Reusable Workflows — DRY Across Repos

Extract common steps into reusable workflows to avoid duplication across multiple apps:

```yaml
# .github/workflows/flutter-quality.yml (reusable)
name: Flutter Quality Gate
on:
  workflow_call:
    inputs:
      flutter-version:
        type: string
        default: '3.32.0'
      coverage-threshold:
        type: number
        default: 80
    secrets:
      # pass secrets through if needed
      SOME_SECRET:
        required: false

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ inputs.flutter-version }}
          cache: true
      - uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed lib/ test/
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage --concurrency=4
```

```yaml
# In your app's workflow — call the reusable workflow
jobs:
  quality:
    uses: your-org/flutter-workflows/.github/workflows/flutter-quality.yml@main
    with:
      flutter-version: '3.32.0'
      coverage-threshold: 80
```

---

## 8. Azure DevOps — Parallel Stages

```yaml
stages:
  - stage: QualityGates
    jobs:
      - job: Quality
        # ...

  - stage: Build
    dependsOn: QualityGates
    jobs:
      - job: BuildAndroid
        pool:
          vmImage: ubuntu-latest
        # runs in parallel with BuildIOS
      - job: BuildIOS
        pool:
          vmImage: macos-latest
        # runs in parallel with BuildAndroid
```

---

## Pipeline Time Budget — Tracking

Add a timing summary to every pipeline:

```yaml
- name: Pipeline timing summary
  if: always()
  run: |
    echo "## Pipeline Timing" >> $GITHUB_STEP_SUMMARY
    echo "| Step | Duration |" >> $GITHUB_STEP_SUMMARY
    echo "|------|----------|" >> $GITHUB_STEP_SUMMARY
    echo "| Total | ${{ github.event.workflow_run.run_duration_ms }}ms |" >> $GITHUB_STEP_SUMMARY
```

Track pipeline duration over time. If it exceeds the budget, investigate which step grew.
