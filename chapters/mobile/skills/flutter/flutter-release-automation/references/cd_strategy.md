# Continuous Delivery Strategy — Branch → Environment → Store

## The Core Rule

```
release/* branch  →  Staging environment  →  Closed testing (Play Store internal / TestFlight)
main / trunk      →  Production environment →  Public stores (Play Store production / App Store)
```

**Never deploy to production from a release branch.**
**Never deploy to staging from main.**

---

## Strategy A — GitFlow

### Branch Model

```
main          ← production releases only (merge from release/*)
  └── develop ← integration branch
        ├── feature/login
        ├── feature/checkout
        └── release/1.2.0  ← QA / staging deploys from here
```

### Trigger → Environment → Store Mapping

| Trigger | Environment | API URL | Store destination |
|---|---|---|---|
| PR → `develop` | None | — | Quality gate only, no build |
| PR → `main` | None | — | Quality gate only, no build |
| Push to `release/*` | **Staging** | `STAGING_API_URL` | Play Store **internal track** / TestFlight **internal** |
| Merge `release/*` → `main` | **Production** | `PROD_API_URL` | Play Store **production** / App Store **submission** |

### GitHub Actions — GitFlow

```yaml
# .github/workflows/cd-gitflow.yml
name: CD — GitFlow

on:
  push:
    branches:
      - 'release/**'   # → staging
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'  # → production (created on merge to main)

env:
  FLUTTER_VERSION: '3.32.0'

jobs:
  # ── Determine environment ──────────────────────────────────────────────
  setup:
    name: Determine Environment
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.env.outputs.environment }}
      api_url: ${{ steps.env.outputs.api_url }}
      is_production: ${{ steps.env.outputs.is_production }}
      play_track: ${{ steps.env.outputs.play_track }}
    steps:
      - id: env
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            echo "environment=production"    >> $GITHUB_OUTPUT
            echo "api_url=${{ secrets.PROD_API_URL }}"     >> $GITHUB_OUTPUT
            echo "is_production=true"        >> $GITHUB_OUTPUT
            echo "play_track=production"     >> $GITHUB_OUTPUT
          else
            echo "environment=staging"       >> $GITHUB_OUTPUT
            echo "api_url=${{ secrets.STAGING_API_URL }}"  >> $GITHUB_OUTPUT
            echo "is_production=false"       >> $GITHUB_OUTPUT
            echo "play_track=internal"       >> $GITHUB_OUTPUT
          fi

  # ── Quality Gates ──────────────────────────────────────────────────────
  quality:
    name: Quality Gates
    needs: setup
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart format --output=none --set-exit-if-changed lib/ test/
      - run: flutter analyze --fatal-infos --fatal-warnings
      - run: flutter test --coverage

  # ── Build Android ──────────────────────────────────────────────────────
  build-android:
    name: Build Android (${{ needs.setup.outputs.environment }})
    needs: [setup, quality]
    runs-on: ubuntu-latest
    environment: ${{ needs.setup.outputs.environment }}  # GitHub Environment protection rules
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Decode keystore
        run: echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore.jks

      - name: Create key.properties
        run: |
          cat > android/key.properties << EOF
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          storeFile=keystore.jks
          EOF

      - name: Extract version
        id: version
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            TAG="${GITHUB_REF#refs/tags/v}"
          else
            # For release/* branches: use branch name as version base
            BRANCH="${GITHUB_REF#refs/heads/release/}"
            TAG="${BRANCH}"
          fi
          echo "version=${TAG}" >> $GITHUB_OUTPUT
          echo "build_number=${GITHUB_RUN_NUMBER}" >> $GITHUB_OUTPUT

      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs

      - name: Build App Bundle
        run: |
          flutter build appbundle --release \
            --obfuscate \
            --split-debug-info=build/symbols/android \
            --dart-define=API_BASE_URL=${{ needs.setup.outputs.api_url }} \
            --dart-define=IS_PRODUCTION=${{ needs.setup.outputs.is_production }} \
            --build-number=${{ steps.version.outputs.build_number }}

      - uses: actions/upload-artifact@v4
        with:
          name: android-aab-${{ needs.setup.outputs.environment }}
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 30

  # ── Build iOS ──────────────────────────────────────────────────────────
  build-ios:
    name: Build iOS (${{ needs.setup.outputs.environment }})
    needs: [setup, quality]
    runs-on: macos-latest
    environment: ${{ needs.setup.outputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
          working-directory: ios

      - name: Extract version
        id: version
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            TAG="${GITHUB_REF#refs/tags/v}"
          else
            BRANCH="${GITHUB_REF#refs/heads/release/}"
            TAG="${BRANCH}"
          fi
          echo "version=${TAG}" >> $GITHUB_OUTPUT
          echo "build_number=${GITHUB_RUN_NUMBER}" >> $GITHUB_OUTPUT

      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs

      - name: Build iOS
        run: |
          flutter build ios --release --no-codesign \
            --obfuscate \
            --split-debug-info=build/symbols/ios \
            --dart-define=API_BASE_URL=${{ needs.setup.outputs.api_url }} \
            --dart-define=IS_PRODUCTION=${{ needs.setup.outputs.is_production }} \
            --build-number=${{ steps.version.outputs.build_number }}

      - name: Archive and sign (Fastlane)
        run: cd ios && bundle exec fastlane release
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_URL: ${{ secrets.MATCH_GIT_URL }}
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
          BUILD_NUMBER: ${{ steps.version.outputs.build_number }}

      - uses: actions/upload-artifact@v4
        with:
          name: ios-ipa-${{ needs.setup.outputs.environment }}
          path: ios/build/Runner.ipa
          retention-days: 30

  # ── Distribute ─────────────────────────────────────────────────────────
  distribute-android:
    name: Distribute Android → ${{ needs.setup.outputs.play_track }}
    needs: [setup, build-android]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: android-aab-${{ needs.setup.outputs.environment }}
          path: build/

      - name: Upload to Play Store
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: com.example.yourapp
          releaseFiles: build/app-release.aab
          track: ${{ needs.setup.outputs.play_track }}   # internal OR production
          status: completed

  distribute-ios:
    name: Distribute iOS → ${{ needs.setup.outputs.environment == 'production' && 'App Store' || 'TestFlight' }}
    needs: [setup, build-ios]
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.3'
          bundler-cache: true
          working-directory: ios
      - uses: actions/download-artifact@v4
        with:
          name: ios-ipa-${{ needs.setup.outputs.environment }}
          path: ios/build/

      - name: Upload to TestFlight (staging)
        if: needs.setup.outputs.environment == 'staging'
        run: cd ios && bundle exec fastlane upload_testflight
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
          IPA_PATH: ios/build/Runner.ipa

      - name: Submit to App Store (production)
        if: needs.setup.outputs.environment == 'production'
        run: cd ios && bundle exec fastlane production
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_CONTENT: ${{ secrets.ASC_KEY_CONTENT }}
          IPA_PATH: ios/build/Runner.ipa
```

### GitFlow — Day-to-Day Workflow

```bash
# 1. Developer finishes a feature
git checkout develop
git merge feature/my-feature
git push origin develop
# → PR quality gate runs, no build

# 2. QA cycle starts — create release branch
git checkout -b release/1.2.0
git push origin release/1.2.0
# → Pipeline triggers automatically
# → Builds with STAGING_API_URL + IS_PRODUCTION=false
# → Uploads to Play Store INTERNAL track
# → Uploads to TestFlight INTERNAL testing
# → QA team tests on closed testing

# 3. QA approves — merge to main and tag
git checkout main
git merge release/1.2.0
git tag v1.2.0
git push origin main --tags
# → Pipeline triggers on tag
# → Builds with PROD_API_URL + IS_PRODUCTION=true
# → Uploads to Play Store PRODUCTION track
# → Submits to App Store for review
```

---

## Strategy B — Trunk-Based Development

### Branch Model

```
main/trunk    ← single source of truth — always production-ready
  ├── feature/login    (short-lived, merged quickly to main)
  ├── feature/checkout (short-lived, merged quickly to main)
  └── release/v1.2.0   (cut from main to stabilize → QA → then main gets the tag)
```

### The Correct Flow

```
feature/* ──→ main ──→ release/v1.2.0 ──→ QA validates ──→ tag v1.2.0 on main
                              │                                      │
                              └──→ STAGING / QA                     └──→ PRODUCTION
                                   Play Store internal                    Play Store production
                                   TestFlight internal                    App Store submission
```

**Key principle:** `release/*` is cut from `main` to freeze and stabilize.
QA tests on the release branch. Once approved, `main` gets the version tag → production deploy.

### Trigger → Environment → Store Mapping

| Trigger | Environment | API URL | Store destination |
|---|---|---|---|
| PR → `main` | None | — | Quality gate only, no build |
| Push to `release/v*` | **Staging / QA** | `STAGING_API_URL` | Play Store **internal** / TestFlight **internal** |
| Tag `v*.*.*` on `main` | **Production** | `PROD_API_URL` | Play Store **production** / App Store **submission** |

### GitHub Actions — Trunk-Based

```yaml
# .github/workflows/cd-trunk.yml
name: CD — Trunk-Based

on:
  push:
    branches:
      - 'release/v[0-9]*'       # → staging / QA
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'  # → production (tagged on main after QA approval)
  pull_request:
    branches:
      - main                    # → quality gate only

env:
  FLUTTER_VERSION: '3.32.0'

jobs:
  # Quality gate — runs on PR only, no build
  quality:
    if: github.event_name == 'pull_request'
    name: Quality Gate (PR)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: dart format --output=none --set-exit-if-changed lib/ test/
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage

  # Determine environment from trigger
  setup:
    if: github.event_name == 'push'
    name: Determine Environment
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.env.outputs.environment }}
      api_url: ${{ steps.env.outputs.api_url }}
      is_production: ${{ steps.env.outputs.is_production }}
      play_track: ${{ steps.env.outputs.play_track }}
    steps:
      - id: env
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            # Tag on main → production
            echo "environment=production"  >> $GITHUB_OUTPUT
            echo "api_url=${{ secrets.PROD_API_URL }}" >> $GITHUB_OUTPUT
            echo "is_production=true"      >> $GITHUB_OUTPUT
            echo "play_track=production"   >> $GITHUB_OUTPUT
          else
            # release/v* branch → staging / QA
            echo "environment=staging"     >> $GITHUB_OUTPUT
            echo "api_url=${{ secrets.STAGING_API_URL }}" >> $GITHUB_OUTPUT
            echo "is_production=false"     >> $GITHUB_OUTPUT
            echo "play_track=internal"     >> $GITHUB_OUTPUT
          fi

  # Build Android
  build-android:
    name: Build Android (${{ needs.setup.outputs.environment }})
    needs: [setup]
    runs-on: ubuntu-latest
    environment: ${{ needs.setup.outputs.environment }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          cache: true
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Decode keystore
        run: echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore.jks

      - name: Create key.properties
        run: |
          cat > android/key.properties << EOF
          storePassword=${{ secrets.KEYSTORE_PASSWORD }}
          keyPassword=${{ secrets.KEY_PASSWORD }}
          keyAlias=${{ secrets.KEY_ALIAS }}
          storeFile=keystore.jks
          EOF

      - name: Extract version
        id: version
        run: |
          if [[ "${GITHUB_REF}" == refs/tags/* ]]; then
            TAG="${GITHUB_REF#refs/tags/v}"
          else
            # release/v1.2.0 → 1.2.0
            BRANCH="${GITHUB_REF#refs/heads/release/v}"
            TAG="${BRANCH}"
          fi
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
            --dart-define=API_BASE_URL=${{ needs.setup.outputs.api_url }} \
            --dart-define=IS_PRODUCTION=${{ needs.setup.outputs.is_production }} \
            --build-number=${{ steps.version.outputs.build_number }}

      - uses: actions/upload-artifact@v4
        with:
          name: android-aab-${{ needs.setup.outputs.environment }}
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 30

  # Distribute Android
  distribute-android:
    name: Distribute Android → ${{ needs.setup.outputs.play_track }}
    needs: [setup, build-android]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: android-aab-${{ needs.setup.outputs.environment }}
          path: build/

      - name: Upload to Play Store
        uses: r0adkll/upload-google-play@v1
        with:
          serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
          packageName: com.example.yourapp
          releaseFiles: build/app-release.aab
          track: ${{ needs.setup.outputs.play_track }}   # internal OR production
          status: completed
          rollout: ${{ needs.setup.outputs.environment == 'production' && '0.1' || '' }}
```

### Trunk-Based — Day-to-Day Workflow

```bash
# 1. Developer merges feature to main (continuous integration)
git checkout main
git merge feature/my-feature
git push origin main
# → Only quality gate runs on PR, no deploy

# 2. Team decides to release — cut release branch from main
git checkout -b release/v1.2.0
git push origin release/v1.2.0
# → Pipeline triggers on release/v* branch
# → Builds with STAGING_API_URL + IS_PRODUCTION=false
# → Uploads to Play Store INTERNAL track
# → Uploads to TestFlight INTERNAL testing
# → QA team tests on closed testing

# 3. QA approves — tag main for production
git checkout main
git tag v1.2.0
git push origin v1.2.0
# → Pipeline triggers on tag
# → Builds with PROD_API_URL + IS_PRODUCTION=true
# → Uploads to Play Store PRODUCTION track (10% staged rollout)
# → Submits to App Store for review
```

---

## GitHub Environments — Protection Rules

Configure environments in **GitHub repo → Settings → Environments**:

### `staging` environment
```
No protection rules needed — deploys automatically
Add secrets: STAGING_API_URL
```

### `production` environment
```
Required reviewers: [lead developer, QA lead]
Wait timer: 0 minutes (or set a delay)
Deployment branches: release/v* only
Add secrets: PROD_API_URL
```

This means production deployments require manual approval from a reviewer
before the pipeline continues — even if the branch trigger fires.

---

## Play Store Track Strategy

| Track | Who tests | When to use |
|---|---|---|
| **Internal** | Dev team only (up to 100 testers) | Every staging deploy — fast, no review |
| **Closed testing (Alpha)** | Selected QA group | Extended QA cycle |
| **Open testing (Beta)** | Public opt-in | Pre-launch feedback |
| **Production** | All users | After QA approval, staged rollout |

```
release/* push → Internal track (immediate, no Google review)
main / tag     → Production track (staged rollout: 10% → 50% → 100%)
```

## TestFlight Track Strategy

| Track | Who tests | When to use |
|---|---|---|
| **Internal** | App Store Connect users (up to 100) | Every staging deploy — no review needed |
| **External** | Up to 10,000 testers | Extended beta, requires Apple review (24–48h) |
| **App Store** | All users | After QA approval |

```
release/* push → Internal TestFlight (no Apple review, immediate)
main / tag     → App Store submission (requires Apple review)
```
