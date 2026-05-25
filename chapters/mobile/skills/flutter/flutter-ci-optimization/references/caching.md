# Caching — pub, Flutter SDK, build_runner, Gradle

Caching is the highest-ROI optimization. Apply all four layers.

---

## Layer 1 — Flutter SDK Cache

`subosito/flutter-action` has built-in caching. Always enable it.

```yaml
- name: Setup Flutter
  uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.32.0'
    channel: stable
    cache: true              # ✅ caches ~/.flutter, saves ~60s per run
    cache-key: flutter-${{ runner.os }}-${{ hashFiles('.flutter-version') }}
```

**Saving:** ~60 seconds per job.

---

## Layer 2 — Pub Dependencies Cache

```yaml
- name: Cache pub dependencies
  uses: actions/cache@v4
  with:
    path: |
      ~/.pub-cache
      .dart_tool/
    key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
    restore-keys: |
      pub-${{ runner.os }}-
```

**Key strategy:**
- `pubspec.lock` changes → cache miss → full `flutter pub get`
- `pubspec.lock` unchanged → cache hit → instant restore

**Saving:** 1–3 minutes per job depending on number of dependencies.

---

## Layer 3 — build_runner Output Cache

If generated files are committed to the repo, skip `build_runner` entirely on CI.
If not committed, cache the output keyed on source files.

### Option A: Commit generated files (recommended)

```yaml
- name: Verify generated files are up to date
  run: |
    git diff --exit-code -- "*.g.dart" "*.freezed.dart" "*.config.dart" || \
    (echo "❌ Generated files out of date — run build_runner locally and commit" && exit 1)
# No build_runner step needed — files already exist
```

**Saving:** 30–90 seconds per job (eliminates codegen entirely on CI).

### Option B: Cache build_runner output

```yaml
- name: Cache build_runner output
  uses: actions/cache@v4
  id: build-runner-cache
  with:
    path: |
      .dart_tool/build/
      lib/**/*.g.dart
      lib/**/*.freezed.dart
      lib/**/*.config.dart
    key: build-runner-${{ runner.os }}-${{ hashFiles('pubspec.lock', 'lib/**/*.dart') }}
    restore-keys: build-runner-${{ runner.os }}-

- name: Run build_runner (only on cache miss)
  if: steps.build-runner-cache.outputs.cache-hit != 'true'
  run: dart run build_runner build --delete-conflicting-outputs
```

**Saving:** 30–90 seconds when cache hits.

---

## Layer 4 — Gradle Cache (Android)

Gradle downloads are expensive. Cache them separately from pub.

```yaml
- name: Cache Gradle dependencies
  uses: actions/cache@v4
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: gradle-${{ runner.os }}-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
    restore-keys: gradle-${{ runner.os }}-

- name: Cache Android build outputs
  uses: actions/cache@v4
  with:
    path: |
      android/.gradle
      android/app/build/
    key: android-build-${{ runner.os }}-${{ hashFiles('android/**/*.gradle*', 'pubspec.lock') }}
    restore-keys: android-build-${{ runner.os }}-
```

**Saving:** 1–3 minutes on Android builds.

---

## Layer 5 — CocoaPods Cache (iOS)

```yaml
- name: Cache CocoaPods
  uses: actions/cache@v4
  with:
    path: |
      ios/Pods
      ~/.cocoapods
    key: pods-${{ runner.os }}-${{ hashFiles('ios/Podfile.lock') }}
    restore-keys: pods-${{ runner.os }}-

- name: Install CocoaPods (only on cache miss)
  if: steps.pods-cache.outputs.cache-hit != 'true'
  run: cd ios && pod install
```

**Saving:** 2–4 minutes on iOS builds.

---

## Complete Caching Setup — GitHub Actions

```yaml
# Reusable job template with all cache layers
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Layer 1: Flutter SDK
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'
          channel: stable
          cache: true

      # Layer 2: Pub dependencies
      - name: Cache pub
        uses: actions/cache@v4
        with:
          path: |
            ~/.pub-cache
            .dart_tool/
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
          restore-keys: pub-${{ runner.os }}-

      # Layer 3: build_runner (if not committing generated files)
      - name: Cache build_runner
        uses: actions/cache@v4
        id: br-cache
        with:
          path: |
            .dart_tool/build/
            lib/**/*.g.dart
            lib/**/*.freezed.dart
          key: br-${{ runner.os }}-${{ hashFiles('pubspec.lock', 'lib/**/*.dart') }}

      - run: flutter pub get

      - name: Run build_runner
        if: steps.br-cache.outputs.cache-hit != 'true'
        run: dart run build_runner build --delete-conflicting-outputs

      # ... rest of quality gate steps
```

---

## Azure DevOps — Cache Configuration

```yaml
# azure-pipelines.yml
steps:
  - task: Cache@2
    displayName: Cache pub dependencies
    inputs:
      key: '"pub" | "$(Agent.OS)" | pubspec.lock'
      path: $(PUB_CACHE)
      restoreKeys: '"pub" | "$(Agent.OS)"'

  - task: Cache@2
    displayName: Cache Gradle
    inputs:
      key: '"gradle" | "$(Agent.OS)" | android/build.gradle'
      path: $(GRADLE_USER_HOME)
      restoreKeys: '"gradle" | "$(Agent.OS)"'
```

---

## Jenkins — Cache Configuration

```groovy
// Jenkinsfile — cache pub using stash/unstash or workspace persistence
stage('Restore Cache') {
    steps {
        // Use Jenkins workspace persistence — pub-cache survives between builds
        // on the same agent
        sh '''
            export PUB_CACHE="${WORKSPACE}/.pub-cache"
            flutter pub get
        '''
    }
}
```

---

## Cache Key Strategy

```
Good key:   pub-linux-<hash of pubspec.lock>
            → invalidates only when dependencies change

Bad key:    pub-linux-<hash of all dart files>
            → invalidates on every code change (defeats the purpose)

Restore keys (fallback order):
  1. pub-linux-<exact pubspec.lock hash>   ← exact match
  2. pub-linux-                             ← any previous pub cache for this OS
```

---

## Measuring Cache Effectiveness

Add this step to measure actual savings:

```yaml
- name: Report cache status
  run: |
    echo "pub-cache size: $(du -sh ~/.pub-cache 2>/dev/null | cut -f1)"
    echo "dart_tool size: $(du -sh .dart_tool 2>/dev/null | cut -f1)"
    echo "gradle size: $(du -sh ~/.gradle 2>/dev/null | cut -f1)"
```

Check the GitHub Actions job summary — cache hits show "Cache restored from key: ..."
A cache hit on pub saves the full `flutter pub get` download time.
