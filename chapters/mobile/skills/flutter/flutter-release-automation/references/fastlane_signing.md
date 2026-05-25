# Fastlane — Signing, Lanes, and Distribution

Fastlane handles iOS code signing (match), archiving, and store uploads.
For Android, it handles Play Store uploads via `supply`.

## Step-by-Step Setup

### Step 1 — Install Ruby (avoid system Ruby)

```bash
# macOS — use rbenv to manage Ruby versions
brew install rbenv
rbenv install 3.3.0
rbenv global 3.3.0

# Add to ~/.zshrc or ~/.bash_profile
echo 'eval "$(rbenv init -)"' >> ~/.zshrc
source ~/.zshrc

# Verify
ruby --version   # should show 3.3.x
```

### Step 2 — Install Fastlane

```bash
gem install fastlane

# Verify
fastlane --version
```

### Step 3 — Initialize Fastlane in Your Project

```bash
cd ios
fastlane init
# Choose option 2: Automate beta distribution to TestFlight
# Follow the prompts — enter your Apple ID and app bundle ID
```

This creates:
```
ios/
├── Gemfile
└── fastlane/
    ├── Appfile
    └── Fastfile
```

### Step 4 — Create Gemfile

Replace the generated Gemfile with:

```ruby
# ios/Gemfile
source "https://rubygems.org"
gem "fastlane", "~> 2.225"
gem "cocoapods"
```

```bash
cd ios && bundle install
```

### Step 5 — Configure Appfile

```ruby
# ios/fastlane/Appfile
app_identifier("com.example.yourapp")   # ← your bundle ID
apple_id("your-apple-id@company.com")   # ← your Apple ID
itc_team_id("YOUR_ITC_TEAM_ID")         # ← from App Store Connect
team_id("YOUR_APPLE_TEAM_ID")           # ← from developer.apple.com
```

To find your team IDs:
```bash
# Check: developer.apple.com → Account → Membership → Team ID
# Or: App Store Connect → Users and Access → your account
```

### Step 6 — Generate App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access → Integrations → App Store Connect API**
2. Click **+** to create a new key
3. Name: `CI/CD Key`, Role: **Developer** (or Admin for full access)
4. Download the `.p8` file — **can only be downloaded once, save it securely**
5. Note the **Key ID** and **Issuer ID**
6. Store in CI secrets:
   - `ASC_KEY_ID` = Key ID (e.g., `ABC123DEF4`)
   - `ASC_ISSUER_ID` = Issuer ID (UUID format)
   - `ASC_KEY_CONTENT` = full contents of the `.p8` file

### Step 7 — Set Up Fastlane Match (Certificate Sync)

Match stores certificates and provisioning profiles in a private Git repository.

```bash
# 1. Create a private Git repo for certificates
#    e.g., github.com/your-org/ios-certificates (private repo)

# 2. Initialize match
cd ios
bundle exec fastlane match init
# Choose: git
# Enter your certificates repo URL when prompted
```

This creates `ios/fastlane/Matchfile`. Configure it:

```ruby
# ios/fastlane/Matchfile
git_url(ENV["MATCH_GIT_URL"])
storage_mode("git")
type("appstore")
app_identifier(["com.example.yourapp"])
username("your-apple-id@company.com")
```

### Step 8 — Generate Certificates (first time only, run locally)

```bash
cd ios

# Generate App Store certificates and provisioning profiles
# Creates them in Apple Developer Portal and stores encrypted in your certs repo
bundle exec fastlane match appstore

# You will be prompted for:
# - Apple ID password (or use API key)
# - Match passphrase → save this as MATCH_PASSWORD secret in CI
```

### Step 9 — Configure Fastfile

Copy the Fastfile from the section below into `ios/fastlane/Fastfile`.

### Step 10 — Verify Locally Before CI

```bash
cd ios

# Test the release lane locally (should produce ios/build/Runner.ipa)
bundle exec fastlane release

# Verify the IPA was created
ls -la build/Runner.ipa
```

### Step 11 — Add to .gitignore

```bash
# Add to your root .gitignore
cat >> .gitignore << 'EOF'
android/app/keystore.jks
android/key.properties
ios/fastlane/report.xml
ios/fastlane/Preview.html
*.p8
*.p12
*.mobileprovision
EOF
```

---

## Gemfile

```ruby
# ios/Gemfile
source "https://rubygems.org"

gem "fastlane", "~> 2.225"
gem "cocoapods"
```

```bash
cd ios && bundle install
```

---

## Appfile

```ruby
# ios/fastlane/Appfile
app_identifier("com.example.yourapp")
apple_id("your-apple-id@company.com")
itc_team_id("YOUR_ITC_TEAM_ID")
team_id("YOUR_APPLE_TEAM_ID")
```

---

## Matchfile — Certificate Sync

```ruby
# ios/fastlane/Matchfile
git_url(ENV["MATCH_GIT_URL"])
storage_mode("git")
type("appstore")
app_identifier(["com.example.yourapp"])
username("your-apple-id@company.com")
```

```bash
# First time: generate and store certificates
cd ios && bundle exec fastlane match appstore

# CI: read-only (never generate on CI)
cd ios && bundle exec fastlane match appstore --readonly
```

---

## Fastfile — iOS Lanes

```ruby
# ios/fastlane/Fastfile
default_platform(:ios)

platform :ios do

  # ── App Store Connect API Key ─────────────────────────────────────────
  # Used by all lanes — avoids 2FA issues on CI
  def api_key
    app_store_connect_api_key(
      key_id: ENV["APP_STORE_CONNECT_API_KEY_ID"],
      issuer_id: ENV["APP_STORE_CONNECT_API_ISSUER_ID"],
      key_content: ENV["APP_STORE_CONNECT_API_KEY_CONTENT"],
      is_key_content_base64: false,
      in_house: false
    )
  end

  # ── Release lane: archive + export ───────────────────────────────────
  desc "Archive and export IPA for App Store"
  lane :release do
    # Sync certificates (read-only on CI)
    sync_code_signing(
      type: "appstore",
      readonly: is_ci,
      git_url: ENV["MATCH_GIT_URL"],
      app_identifier: "com.example.yourapp"
    )

    # Update build number from CI
    increment_build_number(
      build_number: ENV["BUILD_NUMBER"] || Time.now.to_i.to_s,
      xcodeproj: "Runner.xcodeproj"
    )

    # Archive
    build_app(
      workspace: "Runner.xcworkspace",
      scheme: "Runner",
      configuration: "Release",
      export_method: "app-store",
      output_directory: "build",
      output_name: "Runner.ipa",
      export_options: {
        provisioningProfiles: {
          "com.example.yourapp" => "match AppStore com.example.yourapp"
        },
        signingStyle: "manual"
      },
      xcargs: "-allowProvisioningUpdates"
    )
  end

  # ── Upload to TestFlight ──────────────────────────────────────────────
  desc "Upload IPA to TestFlight"
  lane :upload_testflight do
    upload_to_testflight(
      api_key: api_key,
      ipa: ENV["IPA_PATH"] || "build/Runner.ipa",
      skip_waiting_for_build_processing: true,
      changelog: "Automated release from CI"
    )
  end

  # ── Beta lane: release + upload ───────────────────────────────────────
  desc "Build and upload to TestFlight in one step"
  lane :beta do
    release
    upload_testflight
  end

  # ── Production lane ───────────────────────────────────────────────────
  desc "Submit to App Store for review"
  lane :production do
    deliver(
      api_key: api_key,
      ipa: "build/Runner.ipa",
      submit_for_review: false,  # set true to auto-submit
      automatic_release: false,
      force: true,
      skip_screenshots: true,
      skip_metadata: true
    )
  end

  # ── Error handling ────────────────────────────────────────────────────
  error do |lane, exception|
    puts "Lane #{lane} failed: #{exception.message}"
    # Add Slack/Teams notification here if needed
  end
end
```

---

## Fastfile — Android Lanes

```ruby
# android/fastlane/Fastfile
default_platform(:android)

platform :android do

  desc "Upload AAB to Play Store internal track"
  lane :internal do
    upload_to_play_store(
      track: "internal",
      aab: "../build/app/outputs/bundle/release/app-release.aab",
      json_key: ENV["PLAY_SERVICE_ACCOUNT_JSON"],
      package_name: "com.example.yourapp",
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_changelogs: true,
      skip_upload_images: true,
      skip_upload_screenshots: true
    )
  end

  desc "Promote internal to production"
  lane :promote_to_production do
    upload_to_play_store(
      track: "internal",
      track_promote_to: "production",
      json_key: ENV["PLAY_SERVICE_ACCOUNT_JSON"],
      package_name: "com.example.yourapp",
      skip_upload_aab: true,
      rollout: "0.1"  # 10% staged rollout
    )
  end
end
```

---

## Android Signing — key.properties

```
# android/key.properties (NEVER commit this file)
storePassword=<keystore_password>
keyPassword=<key_password>
keyAlias=<key_alias>
storeFile=keystore.jks
```

```groovy
// android/app/build.gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ?
                file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                         'proguard-rules.pro'
        }
    }
}
```

---

## .gitignore — Never Commit Secrets

```gitignore
# Android signing
android/app/keystore.jks
android/key.properties

# iOS certificates (managed by match)
ios/fastlane/report.xml
ios/fastlane/Preview.html
ios/fastlane/screenshots/
ios/fastlane/test_output/

# API keys
fastlane/api_key.json
*.p8
*.p12
*.mobileprovision
```

---

## Generating the Keystore (Android — one time)

```bash
# Generate keystore
keytool -genkey -v \
  -keystore android/app/keystore.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias your-key-alias

# Encode to base64 for CI secrets
base64 -i android/app/keystore.jks | pbcopy  # macOS — copies to clipboard
base64 -w 0 android/app/keystore.jks         # Linux

# Store the output as KEYSTORE_BASE64 secret in your CI platform
```

---

## App Store Connect API Key (iOS — one time)

```
1. Go to App Store Connect → Users and Access → Integrations → App Store Connect API
2. Click + to create a new key
3. Role: Developer (minimum) or Admin
4. Download the .p8 file (can only be downloaded once)
5. Note the Key ID and Issuer ID
6. Store in CI secrets:
   - ASC_KEY_ID = the Key ID
   - ASC_ISSUER_ID = the Issuer ID
   - ASC_KEY_CONTENT = contents of the .p8 file (or base64 encoded)
```

---

## Firebase App Distribution (alternative to TestFlight/Play Store for internal)

```ruby
# In Fastfile — add to any lane
lane :distribute_firebase do
  firebase_app_distribution(
    app: ENV["FIREBASE_APP_ID"],
    firebase_cli_token: ENV["FIREBASE_TOKEN"],
    groups: "internal-testers, qa-team",
    release_notes: "Build #{ENV['BUILD_NUMBER']} — automated release",
    apk_path: "build/app/outputs/flutter-apk/app-release.apk"
    # or ipa_path for iOS
  )
end
```

```bash
# Install Firebase App Distribution plugin
fastlane add_plugin firebase_app_distribution
```
