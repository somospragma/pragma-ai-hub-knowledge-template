# Jenkins — Declarative Pipeline

Jenkins requires a macOS agent for iOS builds. Android can run on any agent.

## Step-by-Step Setup

### Step 1 — Install Jenkins Plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:
- **Pipeline** — declarative pipeline support
- **Git** — source code management
- **Credentials Binding** — inject secrets into builds
- **Copy Artifact** — share artifacts between jobs
- **HTML Publisher** — publish coverage reports
- **Slack Notification** — build notifications (optional)
- **AnsiColor** — colored console output (optional)

### Step 2 — Configure Credentials

Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**:

| ID | Type | Value |
|---|---|---|
| `KEYSTORE_FILE` | Secret file | Upload your `.jks` keystore |
| `KEYSTORE_PASSWORD` | Secret text | Keystore password |
| `KEY_ALIAS` | Secret text | Key alias |
| `KEY_PASSWORD` | Secret text | Key password |
| `PROD_API_URL` | Secret text | `https://api.yourapp.com/v1` |
| `MATCH_PASSWORD` | Secret text | Fastlane match password |
| `MATCH_GIT_URL` | Secret text | `https://github.com/org/certs` |
| `ASC_KEY_ID` | Secret text | App Store Connect key ID |
| `ASC_ISSUER_ID` | Secret text | App Store Connect issuer ID |
| `ASC_KEY_CONTENT` | Secret file | Upload your `.p8` file |
| `FIREBASE_TOKEN` | Secret text | `firebase login:ci` output |
| `FIREBASE_APP_ID_ANDROID` | Secret text | Firebase App ID |
| `PLAY_SERVICE_ACCOUNT` | Secret file | Upload service account `.json` |

### Step 3 — Configure Agents

**Linux agent** (for Android builds):
```bash
# On the Linux machine, install:
sudo apt-get install -y openjdk-17-jdk android-sdk
# Install Flutter
git clone https://github.com/flutter/flutter.git ~/flutter
export PATH="$PATH:$HOME/flutter/bin"
# Label the agent: linux
```

**macOS agent** (for iOS builds — required):
```bash
# On the macOS machine, install:
xcode-select --install
brew install flutter ruby rbenv
rbenv install 3.3.0 && rbenv global 3.3.0
gem install fastlane
# Label the agent: macos
```

Register agents: **Manage Jenkins → Nodes → New Node**.

### Step 4 — Create the Pipeline Job

1. Go to **New Item → Pipeline**
2. Name it `flutter-release`
3. Under **Build Triggers**, check **GitHub hook trigger for GITScm polling** (or configure webhook)
4. Under **Pipeline**, select **Pipeline script from SCM**
5. Set SCM to Git, enter your repository URL
6. Set **Script Path** to `Jenkinsfile`
7. Save

### Step 5 — Configure Webhook (GitHub → Jenkins)

In your GitHub repository → **Settings → Webhooks → Add webhook**:
```
Payload URL: https://your-jenkins.com/github-webhook/
Content type: application/json
Events: Push (for tags)
```

### Step 6 — Configure Fastlane for iOS

Follow the complete setup in `references/fastlane_signing.md`.

### Step 7 — Add Jenkinsfile to Your Repository

Copy the Jenkinsfile from this document to the root of your repository:
```bash
touch Jenkinsfile
# Paste the pipeline content from the section below
git add Jenkinsfile
git commit -m "ci: add Jenkins release pipeline"
git push
```

### Step 8 — Trigger Your First Release

```bash
git tag v1.0.0
git push origin v1.0.0
# → Jenkins detects the tag push via webhook and starts the pipeline
```

### Step 9 — Monitor the Build

Go to **Jenkins → flutter-release → Build #1 → Console Output** to see real-time logs.
Each stage (Quality Gates → Build Android → Build iOS → Distribute → Post-Release) appears in the Stage View.

---

## Prerequisites

- Jenkins with Pipeline plugin
- macOS agent with Xcode, Flutter, Ruby, Fastlane installed
- Linux/Ubuntu agent for Android builds
- Credentials configured in Jenkins Credentials Manager

## Credentials Setup (Jenkins)

```
Jenkins → Manage Jenkins → Credentials → Global:

ID: KEYSTORE_FILE          Type: Secret file    (upload .jks)
ID: KEYSTORE_PASSWORD      Type: Secret text
ID: KEY_ALIAS              Type: Secret text
ID: KEY_PASSWORD           Type: Secret text
ID: PROD_API_URL           Type: Secret text
ID: MATCH_PASSWORD         Type: Secret text
ID: MATCH_GIT_URL          Type: Secret text
ID: ASC_KEY_ID             Type: Secret text
ID: ASC_ISSUER_ID          Type: Secret text
ID: ASC_KEY_CONTENT        Type: Secret file    (upload .p8)
ID: FIREBASE_TOKEN         Type: Secret text
ID: PLAY_SERVICE_ACCOUNT   Type: Secret file    (upload .json)
```

---

## Jenkinsfile — Full Release Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent none  // each stage defines its own agent

    environment {
        FLUTTER_VERSION = '3.32.0'
        FLUTTER_HOME    = "${WORKSPACE}/.flutter"
        PATH            = "${FLUTTER_HOME}/bin:${PATH}"
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    triggers {
        // Trigger on tag push matching v*.*.*
        // Configure in SCM webhook settings
    }

    stages {
        // ── Stage 1: Quality Gates ────────────────────────────────────
        stage('Quality Gates') {
            agent { label 'linux' }
            steps {
                script {
                    installFlutter()
                }
                sh 'flutter pub get'
                sh 'dart run build_runner build --delete-conflicting-outputs'
                sh 'dart format --output=none --set-exit-if-changed lib/ test/'
                sh 'flutter analyze --fatal-infos --fatal-warnings'
                sh 'flutter test --coverage'
                sh '''
                    sudo apt-get install -y lcov
                    lcov --remove coverage/lcov.info \
                        "*.freezed.dart" "*.g.dart" "*.config.dart" \
                        -o coverage/filtered.info
                    lcov --summary coverage/filtered.info
                '''
            }
            post {
                always {
                    publishHTML(target: [
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'coverage',
                        reportFiles: 'filtered.info',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }

        // ── Stage 2: Build Android ────────────────────────────────────
        stage('Build Android') {
            agent { label 'linux' }
            environment {
                KEYSTORE_FILE     = credentials('KEYSTORE_FILE')
                KEYSTORE_PASSWORD = credentials('KEYSTORE_PASSWORD')
                KEY_ALIAS         = credentials('KEY_ALIAS')
                KEY_PASSWORD      = credentials('KEY_PASSWORD')
                PROD_API_URL      = credentials('PROD_API_URL')
            }
            steps {
                script {
                    installFlutter()
                    def version = extractVersion()
                    updatePubspecVersion(version, env.BUILD_NUMBER)
                }

                sh 'cp $KEYSTORE_FILE android/app/keystore.jks'

                sh '''
                    cat > android/key.properties << EOF
storePassword=${KEYSTORE_PASSWORD}
keyPassword=${KEY_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=keystore.jks
EOF
                '''

                sh 'flutter pub get'
                sh 'dart run build_runner build --delete-conflicting-outputs'

                sh """
                    flutter build appbundle --release \\
                        --obfuscate \\
                        --split-debug-info=build/symbols/android \\
                        --dart-define=API_BASE_URL=${PROD_API_URL} \\
                        --dart-define=IS_PRODUCTION=true \\
                        --build-number=${BUILD_NUMBER}
                """

                archiveArtifacts artifacts: 'build/app/outputs/bundle/release/*.aab'
                archiveArtifacts artifacts: 'build/symbols/android/**'
            }
        }

        // ── Stage 3: Build iOS ────────────────────────────────────────
        stage('Build iOS') {
            agent { label 'macos' }  // ✅ must run on macOS
            environment {
                MATCH_PASSWORD    = credentials('MATCH_PASSWORD')
                MATCH_GIT_URL     = credentials('MATCH_GIT_URL')
                ASC_KEY_ID        = credentials('ASC_KEY_ID')
                ASC_ISSUER_ID     = credentials('ASC_ISSUER_ID')
                ASC_KEY_CONTENT   = credentials('ASC_KEY_CONTENT')
                PROD_API_URL      = credentials('PROD_API_URL')
            }
            steps {
                script {
                    installFlutter()
                    def version = extractVersion()
                    updatePubspecVersionMac(version, env.BUILD_NUMBER)
                }

                sh 'cd ios && bundle install'
                sh 'flutter pub get'
                sh 'dart run build_runner build --delete-conflicting-outputs'

                sh """
                    flutter build ios --release --no-codesign \\
                        --obfuscate \\
                        --split-debug-info=build/symbols/ios \\
                        --dart-define=API_BASE_URL=${PROD_API_URL} \\
                        --dart-define=IS_PRODUCTION=true \\
                        --build-number=${BUILD_NUMBER}
                """

                sh 'cd ios && bundle exec fastlane release'

                archiveArtifacts artifacts: 'ios/build/*.ipa'
                archiveArtifacts artifacts: 'build/symbols/ios/**'
            }
        }

        // ── Stage 4: Distribute ───────────────────────────────────────
        stage('Distribute') {
            parallel {
                stage('Play Store') {
                    agent { label 'linux' }
                    environment {
                        PLAY_SERVICE_ACCOUNT = credentials('PLAY_SERVICE_ACCOUNT')
                    }
                    steps {
                        // Download AAB from previous stage artifacts
                        copyArtifacts(
                            projectName: env.JOB_NAME,
                            selector: specific(env.BUILD_NUMBER),
                            filter: 'build/app/outputs/bundle/release/*.aab'
                        )
                        sh '''
                            # Upload to Play Store internal track using fastlane supply
                            cd android && bundle exec fastlane supply \
                                --aab build/app/outputs/bundle/release/app-release.aab \
                                --track internal \
                                --json_key $PLAY_SERVICE_ACCOUNT \
                                --package_name com.example.yourapp
                        '''
                    }
                }

                stage('TestFlight') {
                    agent { label 'macos' }
                    environment {
                        ASC_KEY_ID      = credentials('ASC_KEY_ID')
                        ASC_ISSUER_ID   = credentials('ASC_ISSUER_ID')
                        ASC_KEY_CONTENT = credentials('ASC_KEY_CONTENT')
                    }
                    steps {
                        copyArtifacts(
                            projectName: env.JOB_NAME,
                            selector: specific(env.BUILD_NUMBER),
                            filter: 'ios/build/*.ipa'
                        )
                        sh 'cd ios && bundle exec fastlane upload_testflight'
                    }
                }
            }
        }

        // ── Stage 5: Post-Release ─────────────────────────────────────
        stage('Post-Release') {
            agent { label 'linux' }
            environment {
                FIREBASE_TOKEN           = credentials('FIREBASE_TOKEN')
                FIREBASE_APP_ID_ANDROID  = credentials('FIREBASE_APP_ID_ANDROID')
            }
            steps {
                copyArtifacts(
                    projectName: env.JOB_NAME,
                    selector: specific(env.BUILD_NUMBER),
                    filter: 'build/symbols/android/**'
                )
                sh '''
                    npm install -g firebase-tools
                    firebase crashlytics:symbols:upload \
                        --app=$FIREBASE_APP_ID_ANDROID \
                        build/symbols/android/
                '''
            }
        }
    }

    post {
        success {
            slackSend(
                color: 'good',
                message: "✅ Release ${env.BUILD_NUMBER} deployed successfully"
            )
        }
        failure {
            slackSend(
                color: 'danger',
                message: "❌ Release ${env.BUILD_NUMBER} failed at stage: ${env.STAGE_NAME}"
            )
        }
        always {
            cleanWs()  // clean workspace after every build
        }
    }
}

// ── Helper functions ──────────────────────────────────────────────────────

def installFlutter() {
    sh """
        if [ ! -d "${FLUTTER_HOME}" ]; then
            git clone --depth 1 --branch ${FLUTTER_VERSION} \\
                https://github.com/flutter/flutter.git ${FLUTTER_HOME}
        fi
        flutter --version
        flutter pub cache repair
    """
}

def extractVersion() {
    def tag = sh(script: "git describe --tags --abbrev=0", returnStdout: true).trim()
    return tag.replaceFirst('^v', '')
}

def updatePubspecVersion(String version, String buildNumber) {
    sh "sed -i 's/^version:.*/version: ${version}+${buildNumber}/' pubspec.yaml"
}

def updatePubspecVersionMac(String version, String buildNumber) {
    sh "sed -i '' 's/^version:.*/version: ${version}+${buildNumber}/' pubspec.yaml"
}
```

---

## Shared Library (for multi-project reuse)

```groovy
// vars/flutterQualityGate.groovy (Jenkins Shared Library)
def call(Map config = [:]) {
    def flutterVersion = config.flutterVersion ?: '3.32.0'
    def coverageThreshold = config.coverageThreshold ?: 80

    stage('Quality Gate') {
        sh "flutter pub get"
        sh "dart run build_runner build --delete-conflicting-outputs"
        sh "dart format --output=none --set-exit-if-changed lib/ test/"
        sh "flutter analyze --fatal-infos"
        sh "flutter test --coverage"
        sh """
            sudo apt-get install -y lcov
            lcov --remove coverage/lcov.info '*.g.dart' '*.freezed.dart' \
                -o coverage/filtered.info
            COVERAGE=\$(lcov --summary coverage/filtered.info 2>&1 \
                | grep "lines" | awk '{print \$2}' | tr -d '%')
            if (( \$(echo "\$COVERAGE < ${coverageThreshold}" | bc -l) )); then
                echo "Coverage \${COVERAGE}% below ${coverageThreshold}%"
                exit 1
            fi
        """
    }
}

// Usage in Jenkinsfile:
// @Library('flutter-shared-lib') _
// flutterQualityGate(flutterVersion: '3.32.0', coverageThreshold: 80)
```
