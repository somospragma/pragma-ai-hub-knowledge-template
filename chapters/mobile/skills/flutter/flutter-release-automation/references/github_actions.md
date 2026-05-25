# GitHub Actions — PR and Release Workflows

## Step-by-Step Setup

### Step 1 — Repository Secrets

Go to your GitHub repository → **Settings → Secrets and variables → Actions → New repository secret** and add:

```
# Android signing
KEYSTORE_BASE64         → base64 -w 0 android/app/keystore.jks
KEYSTORE_PASSWORD       → your keystore password
KEY_ALIAS               → your key alias
KEY_PASSWORD            → your key password

# iOS (Fastlane match)
MATCH_PASSWORD          → your match encryption password
MATCH_GIT_URL           → https://github.com/your-org/certificates

# App Store Connect API
ASC_KEY_ID              → from App Store Connect → Users → Integrations
ASC_ISSUER_ID           → from App Store Connect → Users → Integrations
ASC_KEY_CONTENT         → contents of the downloaded .p8 file

# App config
PROD_API_URL            → https://api.yourapp.com/v1
FIREBASE_APP_ID_ANDROID → from Firebase Console → Project Settings
FIREBASE_TOKEN          → firebase login:ci (run locally)
PLAY_SERVICE_ACCOUNT_JSON → contents of Google Play service account .json
```

### Step 2 — Copy Workflow Files

```bash
mkdir -p .github/workflows

# Release pipeline (triggered on tag push)
cp skills/flutter-release-automation/assets/release_workflow.yml \
   .github/workflows/release.yml

# PR quality gate (triggered on pull request)
# Copy the PR workflow from references/github_actions.md
touch .github/workflows/pr.yml
```

### Step 3 — Update Package Name

In `.github/workflows/release.yml`, replace:
```yaml
packageName: com.example.yourapp   # ← your actual package name
```

### Step 4 — Configure Fastlane for iOS

Follow the complete setup in `references/fastlane_signing.md`.
Minimum required: `ios/Gemfile`, `ios/fastlane/Appfile`, `ios/fastlane/Matchfile`, `ios/fastlane/Fastfile`.

### Step 5 — Trigger Your First Release

```bash
git tag v1.0.0
git push origin v1.0.0
# → GitHub Actions triggers the release pipeline automatically
```

### Step 6 — Monitor the Pipeline

Go to your repository → **Actions** tab → select the running workflow.
Each job (quality → build-android → build-ios → distribute → post-release) runs in sequence.

---

## File Structure

```
.github/
└── workflows/
    ├── pr.yml          ← quality gates on every PR
    └── release.yml     ← full build + sign + distribute on tag push
```

---

## PR Workflow — Quality Gates

```yaml
# .github/workflows/pr.yml
name: PR Quality Gates

on:
  pull_request:
    branches: [main, develop]

concurrency:
  group: pr-${{ github.ref }}
  cancel-in-progress: true   # cancel previous run if new commit pushed

env:
  FLUTTER_VERSION: '3.32.0'

jobs:
  quality:
    name: Lint, Analyze & Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - name: Cache pub dependencies
        uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
          restore-keys: pub-${{ runner.os }}-

      - name: Install dependencies
        run: flutter pub get

      - name: Run build_runner
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Check formatting
        run: dart format --output=none --set-exit-if-changed lib/ test/

      - name: Analyze
        run: flutter analyze --fatal-infos --fatal-warnings

      - name: Run tests with coverage
        run: flutter test --coverage --reporter=github

      - name: Check coverage threshold
        run: |
          sudo apt-get install -y lcov
          # Remove generated files from coverage
          lcov --remove coverage/lcov.info \
            '*.freezed.dart' '*.g.dart' '*.config.dart' \
            -o coverage/filtered.info
          # Fail if coverage < 80%
          COVERAGE=$(lcov --summary coverage/filtered.info 2>&1 \
            | grep "lines" | awk '{print $2}' | tr -d '%')
          echo "Coverage: ${COVERAGE}%"
          if (( $(echo "$COVERAGE < 80" | bc -l) )); then
            echo "❌ Coverage ${COVERAGE}% is below 80% threshold"
            exit 1
          fi
          echo "✅ Coverage ${COVERAGE}% meets threshold"

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: coverage-report
          path: coverage/filtered.info
```

---

## Release Workflow — Full Pipeline

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'   # matches v1.2.3

env:
  FLUTTER_VERSION: '3.32.0'

jobs:
  # ── 1. Quality Gates ──────────────────────────────────────────────────
  quality:
    name: Quality Gates
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart format --output=none --set-exit-if-changed lib/ test/
      - run: flutter analyze --fatal-infos --fatal-warnings
      - run: flutter test --coverage --reporter=github

  # ── 2. Build Android ─────────────────────────────────────────────────
  build-android:
    name: Build Android AAB
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Decode keystore
        run: |
          echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore.jks

      - name: Create key.properties
        run: |
          cat > android/key.properties << EOF
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          storeFile=keystore.jks
          EOF

      - name: Extract version from tag
        id: version
        run: |
          TAG="${GITHUB_REF#refs/tags/v}"
          echo "version=${TAG}" >> $GITHUB_OUTPUT
          echo "build_number=${GITHUB_RUN_NUMBER}" >> $GITHUB_OUTPUT

      - name: Update pubspec version
        run: |
          sed -i "s/^version:.*/version: ${{ steps.version.outputs.version }}+${{ steps.version.outputs.build_number }}/" pubspec.yaml

      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs

      - name: Build App Bundle
        run: |
          flutter build appbundle --release \
            --obfuscate \
            --split-debug-info=build/symbols/android \
            --dart-define=API_BASE_URL=${{ secrets.PROD_API_URL }} \
            --dart-define=IS_PRODUCTION=true \
            --build-number=${{ steps.version.outputs.build_number }}

      - name: Upload AAB artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-aab
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 7

      - name: Upload Android debug symbols
        uses: actions/upload-artifact@v4
        with:
          name: android-symbols
          path: build/symbols/android/
          retention-days: 30

  # ── 3. Build iOS ─────────────────────────────────────────────────────
  build-ios:
    name: Build iOS IPA
    needs: quality
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true

      - uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}

      - name: Setup Ruby (for Fastlane)
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
          working-directory: ios

      - name: Extract version from tag
        id: version
        run: |
          TAG="${GITHUB_REF#refs/tags/v}"
          echo "version=${TAG}" >> $GITHUB_OUTPUT
          echo "build_number=${GITHUB_RUN_NUMBER}" >> $GITHUB_OUTPUT

      - name: Update pubspec version
        run: |
          sed -i '' "s/^version:.*/version: ${{ steps.version.outputs.version }}+${{ steps.version.outputs.build_number }}/" pubspec.yaml

      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs

      - name: Build iOS (no codesign — Fastlane handles signing)
        run: |
          flutter build ios --release --no-codesign \
            --obfuscate \
            --split-debug-info=build/symbols/ios \
            --dart-define=API_BASE_URL=${{ secrets.PROD_API_URL }} \
            --dart-define=IS_PRODUCTION=true \
            --build-number=${{ steps.version.outputs.build_number }}

      - name: Archive and export with Fastlane
        run: cd ios && bundle exec fastlane release
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_URL: ${{ secrets.MATCH_GIT_URL }}
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}

      - name: Upload IPA artifact
        uses: actions/upload-artifact@v4
        with:
          name: ios-ipa
          path: ios/build/Runner.ipa
          retention-days: 7

      - name: Upload iOS debug symbols
        uses: actions/upload-artifact@v4
        with:
          name: ios-symbols
          path: build/symbols/ios/
          retention-days: 30

  # ── 4. Distribute ─────────────────────────────────────────────────────
  distribute-android:
    name: Distribute Android
    needs: build-android
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download AAB
        uses: actions/download-artifact@v4
        with:
          name: android-aab
          path: build/

      - name: Upload to Play Store (internal track)
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: com.example.yourapp
          releaseFiles: build/app-release.aab
          track: internal
          status: completed

  distribute-ios:
    name: Distribute iOS
    needs: build-ios
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download IPA
        uses: actions/download-artifact@v4
        with:
          name: ios-ipa
          path: ios/build/

      - name: Upload to TestFlight
        run: cd ios && bundle exec fastlane upload_testflight
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}

  # ── 5. Post-release ───────────────────────────────────────────────────
  post-release:
    name: Post-Release Tasks
    needs: [distribute-android, distribute-ios]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download Android symbols
        uses: actions/download-artifact@v4
        with:
          name: android-symbols
          path: build/symbols/android/

      - name: Upload symbols to Firebase Crashlytics
        run: |
          npm install -g firebase-tools
          firebase crashlytics:symbols:upload \
            --app=${{ secrets.FIREBASE_APP_ID_ANDROID }} \
            build/symbols/android/
        env:
          FIREBASE_TOKEN: ${{ secrets.FIREBASE_TOKEN }}

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          files: |
            build/app-release.aab
```

---

## Reusable Workflow — Quality Gate

Extract quality gates into a reusable workflow to avoid duplication:

```yaml
# .github/workflows/quality-gate.yml
name: Quality Gate (Reusable)

on:
  workflow_call:
    inputs:
      flutter-version:
        required: true
        type: string
      coverage-threshold:
        required: false
        type: number
        default: 80

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ inputs.flutter-version }}
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart format --output=none --set-exit-if-changed lib/ test/
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage

# Usage in other workflows:
# jobs:
#   quality:
#     uses: ./.github/workflows/quality-gate.yml
#     with:
#       flutter-version: '3.32.0'
#       coverage-threshold: 80
```
