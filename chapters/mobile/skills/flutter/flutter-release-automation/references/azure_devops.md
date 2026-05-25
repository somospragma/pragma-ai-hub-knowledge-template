# Azure DevOps — YAML Pipelines

## Step-by-Step Setup

### Step 1 — Create Variable Groups

Go to **Pipelines → Library → + Variable group** and create two groups:

**Group name: `flutter-android-signing`**
```
KEYSTORE_BASE64       → base64 -w 0 android/app/keystore.jks   (mark as secret 🔒)
KEYSTORE_PASSWORD     → your keystore password                   (mark as secret 🔒)
KEY_ALIAS             → your key alias
KEY_PASSWORD          → your key password                        (mark as secret 🔒)
```

**Group name: `flutter-app-config`**
```
PROD_API_URL                → https://api.yourapp.com/v1        (mark as secret 🔒)
STAGING_API_URL             → https://staging-api.yourapp.com   (mark as secret 🔒)
FIREBASE_APP_ID_ANDROID     → from Firebase Console
FIREBASE_APP_ID_IOS         → from Firebase Console
FIREBASE_TOKEN              → firebase login:ci                  (mark as secret 🔒)
PLAY_SERVICE_ACCOUNT_JSON   → contents of .json file            (mark as secret 🔒)
MATCH_PASSWORD              → Fastlane match password           (mark as secret 🔒)
MATCH_GIT_URL               → https://github.com/org/certs
ASC_KEY_ID                  → App Store Connect key ID
ASC_ISSUER_ID               → App Store Connect issuer ID
ASC_KEY_CONTENT             → contents of .p8 file              (mark as secret 🔒)
```

### Step 2 — Create Service Connections

Go to **Project Settings → Service connections**:

1. **Google Play** → Add service connection → Google Play → upload service account JSON
2. **Apple App Store** → Add service connection → Apple App Store → upload .p8 key

### Step 3 — Install Required Extensions

Go to **Organization Settings → Extensions → Browse marketplace** and install:
- **Flutter** (by Hey24sheep) — provides `FlutterInstall` and `FlutterBuild` tasks
- **Google Play** (by Microsoft) — provides `GooglePlayRelease` task

### Step 4 — Create the Pipelines

**PR pipeline:**
1. Go to **Pipelines → New pipeline**
2. Select your repository
3. Choose **Existing Azure Pipelines YAML file**
4. Path: `/azure-pipelines/pr.yml`
5. Copy the PR YAML from this file

**Release pipeline:**
1. Go to **Pipelines → New pipeline**
2. Select your repository
3. Choose **Existing Azure Pipelines YAML file**
4. Path: `/azure-pipelines/release.yml`
5. Copy the release YAML from this file

### Step 5 — Link Variable Groups to Pipeline

In each pipeline → **Edit → Variables → Variable groups → Link variable group**:
- Link `flutter-android-signing`
- Link `flutter-app-config`

### Step 6 — Configure macOS Agent for iOS

iOS builds require a macOS agent. Options:
- **Microsoft-hosted**: use `vmImage: macos-latest` (included in Azure DevOps)
- **Self-hosted**: register a macOS machine with Xcode installed

### Step 7 — Configure Fastlane for iOS

Follow the complete setup in `references/fastlane_signing.md`.

### Step 8 — Trigger Your First Release

```bash
git tag v1.0.0
git push origin v1.0.0
# → Azure DevOps triggers the release pipeline via the tag trigger
```

---

## File Structure

```
azure-pipelines/
├── pr.yml          ← quality gates on every PR
├── release.yml     ← full build + sign + distribute
└── templates/
    ├── flutter-setup.yml
    ├── quality-gate.yml
    └── android-build.yml
```

---

## Variable Groups (Azure DevOps Library)

Create two variable groups in **Pipelines → Library**:

**`flutter-android-signing`**
- `KEYSTORE_BASE64` (secret)
- `KEYSTORE_PASSWORD` (secret)
- `KEY_ALIAS`
- `KEY_PASSWORD` (secret)

**`flutter-app-config`**
- `PROD_API_URL` (secret)
- `STAGING_API_URL` (secret)
- `FIREBASE_APP_ID_ANDROID`
- `FIREBASE_APP_ID_IOS`
- `FIREBASE_TOKEN` (secret)
- `PLAY_SERVICE_ACCOUNT_JSON` (secret)

---

## PR Pipeline — Quality Gates

```yaml
# azure-pipelines/pr.yml
trigger: none

pr:
  branches:
    include:
      - main
      - develop

variables:
  FLUTTER_VERSION: '3.32.0'
  vmImageUbuntu: 'ubuntu-latest'

pool:
  vmImage: $(vmImageUbuntu)

stages:
  - stage: QualityGates
    displayName: Quality Gates
    jobs:
      - job: LintAnalyzeTest
        displayName: Lint, Analyze & Test
        steps:
          - task: FlutterInstall@0
            displayName: Install Flutter
            inputs:
              mode: auto
              channel: stable
              version: specific
              specificVersion: $(FLUTTER_VERSION)

          - task: Cache@2
            displayName: Cache pub dependencies
            inputs:
              key: '"pub" | "$(Agent.OS)" | pubspec.lock'
              path: $(PUB_CACHE)
              restoreKeys: '"pub" | "$(Agent.OS)"'

          - script: flutter pub get
            displayName: Install dependencies

          - script: dart run build_runner build --delete-conflicting-outputs
            displayName: Run build_runner

          - script: dart format --output=none --set-exit-if-changed lib/ test/
            displayName: Check formatting

          - script: flutter analyze --fatal-infos --fatal-warnings
            displayName: Analyze

          - script: flutter test --coverage
            displayName: Run tests

          - script: |
              sudo apt-get install -y lcov
              lcov --remove coverage/lcov.info \
                '*.freezed.dart' '*.g.dart' '*.config.dart' \
                -o coverage/filtered.info
              lcov --summary coverage/filtered.info
            displayName: Coverage report

          - task: PublishCodeCoverageResults@2
            displayName: Publish coverage
            inputs:
              summaryFileLocation: coverage/filtered.info
              failIfCoverageEmpty: true
```

---

## Release Pipeline — Full Build + Sign + Distribute

```yaml
# azure-pipelines/release.yml
trigger:
  tags:
    include:
      - 'v*.*.*'

variables:
  - group: flutter-android-signing
  - group: flutter-app-config
  - name: FLUTTER_VERSION
    value: '3.32.0'
  - name: BUILD_NUMBER
    value: $(Build.BuildId)

stages:
  # ── Stage 1: Quality Gates ────────────────────────────────────────────
  - stage: QualityGates
    displayName: Quality Gates
    pool:
      vmImage: ubuntu-latest
    jobs:
      - job: Quality
        steps:
          - task: FlutterInstall@0
            inputs:
              mode: auto
              channel: stable
              version: specific
              specificVersion: $(FLUTTER_VERSION)
          - script: flutter pub get
          - script: dart run build_runner build --delete-conflicting-outputs
          - script: dart format --output=none --set-exit-if-changed lib/ test/
          - script: flutter analyze --fatal-infos
          - script: flutter test --coverage

  # ── Stage 2: Build Android ────────────────────────────────────────────
  - stage: BuildAndroid
    displayName: Build Android
    dependsOn: QualityGates
    pool:
      vmImage: ubuntu-latest
    jobs:
      - job: BuildAAB
        displayName: Build App Bundle
        steps:
          - task: FlutterInstall@0
            inputs:
              mode: auto
              channel: stable
              version: specific
              specificVersion: $(FLUTTER_VERSION)

          - task: JavaToolInstaller@0
            inputs:
              versionSpec: '17'
              jdkArchitectureOption: x64
              jdkSourceOption: PreInstalled

          - script: |
              echo "$(KEYSTORE_BASE64)" | base64 -d > $(Build.SourcesDirectory)/android/app/keystore.jks
            displayName: Decode keystore

          - script: |
              cat > $(Build.SourcesDirectory)/android/key.properties << EOF
              storePassword=$(KEYSTORE_PASSWORD)
              keyPassword=$(KEY_PASSWORD)
              keyAlias=$(KEY_ALIAS)
              storeFile=keystore.jks
              EOF
            displayName: Create key.properties

          - script: |
              TAG=$(Build.SourceBranchName)
              VERSION=${TAG#v}
              sed -i "s/^version:.*/version: ${VERSION}+$(BUILD_NUMBER)/" pubspec.yaml
            displayName: Update version

          - script: flutter pub get
          - script: dart run build_runner build --delete-conflicting-outputs

          - script: |
              flutter build appbundle --release \
                --obfuscate \
                --split-debug-info=$(Build.ArtifactStagingDirectory)/symbols/android \
                --dart-define=API_BASE_URL=$(PROD_API_URL) \
                --dart-define=IS_PRODUCTION=true \
                --build-number=$(BUILD_NUMBER)
            displayName: Build App Bundle

          - task: CopyFiles@2
            inputs:
              sourceFolder: build/app/outputs/bundle/release
              contents: '*.aab'
              targetFolder: $(Build.ArtifactStagingDirectory)/android

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: $(Build.ArtifactStagingDirectory)/android
              artifactName: android-aab

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: $(Build.ArtifactStagingDirectory)/symbols/android
              artifactName: android-symbols

  # ── Stage 3: Build iOS ────────────────────────────────────────────────
  - stage: BuildIOS
    displayName: Build iOS
    dependsOn: QualityGates
    pool:
      vmImage: macos-latest
    jobs:
      - job: BuildIPA
        displayName: Build IPA
        steps:
          - task: FlutterInstall@0
            inputs:
              mode: auto
              channel: stable
              version: specific
              specificVersion: $(FLUTTER_VERSION)

          - task: UseRubyVersion@0
            inputs:
              versionSpec: '3.3'

          - script: |
              cd ios && bundle install
            displayName: Install Fastlane

          - script: |
              TAG=$(Build.SourceBranchName)
              VERSION=${TAG#v}
              sed -i '' "s/^version:.*/version: ${VERSION}+$(BUILD_NUMBER)/" pubspec.yaml
            displayName: Update version

          - script: flutter pub get
          - script: dart run build_runner build --delete-conflicting-outputs

          - script: |
              flutter build ios --release --no-codesign \
                --obfuscate \
                --split-debug-info=$(Build.ArtifactStagingDirectory)/symbols/ios \
                --dart-define=API_BASE_URL=$(PROD_API_URL) \
                --dart-define=IS_PRODUCTION=true \
                --build-number=$(BUILD_NUMBER)
            displayName: Build iOS

          - script: cd ios && bundle exec fastlane release
            displayName: Archive and sign with Fastlane
            env:
              MATCH_PASSWORD: $(MATCH_PASSWORD)
              MATCH_GIT_URL: $(MATCH_GIT_URL)
              APP_STORE_CONNECT_API_KEY_ID: $(ASC_KEY_ID)
              APP_STORE_CONNECT_API_ISSUER_ID: $(ASC_ISSUER_ID)
              APP_STORE_CONNECT_API_KEY_CONTENT: $(ASC_KEY_CONTENT)

          - task: CopyFiles@2
            inputs:
              sourceFolder: ios/build
              contents: '*.ipa'
              targetFolder: $(Build.ArtifactStagingDirectory)/ios

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: $(Build.ArtifactStagingDirectory)/ios
              artifactName: ios-ipa

          - task: PublishBuildArtifacts@1
            inputs:
              pathToPublish: $(Build.ArtifactStagingDirectory)/symbols/ios
              artifactName: ios-symbols

  # ── Stage 4: Distribute ───────────────────────────────────────────────
  - stage: Distribute
    displayName: Distribute
    dependsOn:
      - BuildAndroid
      - BuildIOS
    pool:
      vmImage: ubuntu-latest
    jobs:
      - job: DistributeAndroid
        displayName: Play Store (internal)
        steps:
          - task: DownloadBuildArtifacts@1
            inputs:
              artifactName: android-aab
              downloadPath: $(System.ArtifactsDirectory)

          - task: GooglePlayRelease@4
            inputs:
              serviceConnection: 'Google Play Service Connection'
              applicationId: com.example.yourapp
              action: SingleBundle
              bundleFile: $(System.ArtifactsDirectory)/android-aab/*.aab
              track: internal

      - job: DistributeIOS
        displayName: TestFlight
        pool:
          vmImage: macos-latest
        steps:
          - task: DownloadBuildArtifacts@1
            inputs:
              artifactName: ios-ipa
              downloadPath: $(System.ArtifactsDirectory)

          - task: UseRubyVersion@0
            inputs:
              versionSpec: '3.3'

          - script: cd ios && bundle exec fastlane upload_testflight
            env:
              APP_STORE_CONNECT_API_KEY_ID: $(ASC_KEY_ID)
              APP_STORE_CONNECT_API_ISSUER_ID: $(ASC_ISSUER_ID)
              APP_STORE_CONNECT_API_KEY_CONTENT: $(ASC_KEY_CONTENT)
              IPA_PATH: $(System.ArtifactsDirectory)/ios-ipa/Runner.ipa
