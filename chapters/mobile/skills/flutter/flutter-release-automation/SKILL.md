---
name: flutter-release-automation
description: >
  Automates Flutter release pipelines across CI/CD platforms- GitHub Actions, Azure DevOps, and Jenkins. Covers the full pipeline: quality gates (lint, test, coverage) → build (AAB/IPA) → signing (Android keystore, iOS Fastlane match) → obfuscation → distribution (Play Store, App Store, Firebase App Distribution) → version management and debug symbol upload. Use this skill when setting up or improving CI/CD for Flutter, configuring signing secrets, automating store deployments, or implementing quality gates.
commands:
  - setup-release-automation
inputs:
  - name: action
    description: Action to perform (setup, audit, migrate). "setup" generates the full CI/CD pipeline configuration, "audit" checks an existing pipeline for missing quality gates or best practices, "migrate" converts between CI platforms (e.g. GitHub Actions to Azure DevOps).
    required: true
  - name: platform
    description: CI/CD platform to target (github-actions, azure-devops, jenkins).
    required: true
  - name: strategy
    description: Branching strategy to implement (gitflow, trunk-based). Determines trigger rules and environment mapping.
    required: false
  - name: targets
    description: Build targets to include (android, ios, both). Defaults to both.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Release Automation

See the reference files for complete patterns and code examples.

**A release pipeline is only as good as its quality gates. Never ship without them.**

## Continuous Delivery Strategy — Branch → Environment → Store

This is the core of CD. The branch that receives a push determines the environment
and the store destination. Never deploy to production from a feature or release branch.

### GitFlow Strategy

```
feature/* ──→ develop ──→ release/* ──→ main
                │               │          │
                │               │          └──→ PRODUCTION
                │               │               Play Store (production track)
                │               │               App Store (App Store submission)
                │               │
                │               └──→ STAGING / QA
                │                    Play Store (internal / closed testing)
                │                    TestFlight (external testing)
                │
                └──→ PR quality gate only (no build, no deploy)
```

### Trunk-Based Strategy

```
feature/* ──→ main/trunk
                  │
                  ├──→ release/v*.*.* ──→ STAGING / QA
                  │                        Play Store (internal track)
                  │                        TestFlight (internal testing)
                  │
                  └──→ PRODUCTION (on merge to main after release/* is validated)
                        Play Store (production track)
                        App Store (App Store submission)
```

### Pipeline Trigger Rules

| Branch / Event | Pipeline | Environment | Destination |
|---|---|---|---|
| PR to `develop` / `main` | Quality gate only | — | No build |
| Push to `release/*` | Build + Sign + Distribute | **Staging / QA** | Play Store internal / TestFlight internal |
| Merge to `main` / tag `v*.*.*` | Build + Sign + Distribute | **Production** | Play Store production / App Store |

### Environment Variables per Stage

```
release/* branch  →  STAGING_API_URL, IS_PRODUCTION=false
main / tag        →  PROD_API_URL,    IS_PRODUCTION=true
```

See `references/cd_strategy.md` for complete workflow files implementing this strategy.

---

Each reference file contains the full configuration, but here is the onboarding path for each platform:

### GitHub Actions
```
Step 1 → Configure secrets in GitHub repo → Settings → Secrets and variables → Actions
Step 2 → Copy assets/release_workflow.yml to .github/workflows/release.yml
Step 3 → Copy PR quality gate from references/github_actions.md to .github/workflows/pr.yml
Step 4 → Configure Fastlane for iOS signing (see references/fastlane_signing.md)
Step 5 → Push a tag v1.2.3 to trigger the release pipeline
```

### Azure DevOps
```
Step 1 → Create variable groups in Pipelines → Library
Step 2 → Create the pipeline from references/azure_devops.md
Step 3 → Link variable groups to the pipeline
Step 4 → Configure service connections (Google Play, App Store)
Step 5 → Configure Fastlane for iOS signing (see references/fastlane_signing.md)
Step 6 → Push a tag v1.2.3 to trigger the release pipeline
```

### Jenkins
```
Step 1 → Configure credentials in Jenkins → Manage Jenkins → Credentials
Step 2 → Create a Pipeline job pointing to your Jenkinsfile
Step 3 → Configure macOS agent for iOS builds
Step 4 → Configure Fastlane for iOS signing (see references/fastlane_signing.md)
Step 5 → Configure webhook to trigger on tag push
```

### Fastlane (required for iOS on all platforms)
```
Step 1 → Install Ruby + Fastlane locally
Step 2 → Run fastlane init in ios/ folder
Step 3 → Configure Appfile and Matchfile
Step 4 → Generate App Store Connect API key
Step 5 → Run fastlane match appstore to generate and store certificates
Step 6 → Verify locally: cd ios && bundle exec fastlane release
```

See each reference file for the complete step-by-step with commands and configuration details.

---

```
┌─────────────────────────────────────────────────────────────────┐
│  1. QUALITY GATES                                               │
│     format check → analyze → unit tests → coverage threshold   │
├─────────────────────────────────────────────────────────────────┤
│  2. BUILD                                                       │
│     build_runner → flutter build (AAB / IPA) → obfuscate       │
├─────────────────────────────────────────────────────────────────┤
│  3. SIGN                                                        │
│     Android: keystore → jarsigner                               │
│     iOS: Fastlane match → Xcode archive → export               │
├─────────────────────────────────────────────────────────────────┤
│  4. DISTRIBUTE                                                  │
│     Internal: Firebase App Distribution / TestFlight            │
│     Production: Play Store / App Store                          │
├─────────────────────────────────────────────────────────────────┤
│  5. POST-RELEASE                                                │
│     Upload debug symbols → tag release → update CHANGELOG      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Platform Selection

| Platform | Best for | Notes |
|---|---|---|
| **GitHub Actions** | GitHub repos, open source, SaaS teams | Native integration, generous free tier |
| **Azure DevOps** | Enterprise, Microsoft ecosystem, on-premise | Strong secret management, YAML + classic |
| **Jenkins** | On-premise, full control, complex pipelines | Requires infrastructure, most flexible |

---

## Flutter Version Strategy

```yaml
# Always pin Flutter version — never use 'latest'
FLUTTER_VERSION: '3.32.0'   # pin to tested version
FLUTTER_CHANNEL: 'stable'
```

---

## Secrets Required (all platforms)

### Android
| Secret | Description |
|---|---|
| `KEYSTORE_BASE64` | Base64-encoded `.jks` keystore file |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias |
| `KEY_PASSWORD` | Key password |

### iOS
| Secret | Description |
|---|---|
| `MATCH_PASSWORD` | Fastlane match encryption password |
| `MATCH_GIT_URL` | Git repo URL for certificates |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_KEY_CONTENT` | App Store Connect API key content (p8) |

### App
| Secret | Description |
|---|---|
| `PROD_API_URL` | Production API base URL |
| `STAGING_API_URL` | Staging API base URL |
| `FIREBASE_APP_ID_ANDROID` | Firebase App ID for distribution |
| `FIREBASE_APP_ID_IOS` | Firebase App ID for distribution |
| `FIREBASE_TOKEN` | Firebase CLI token |

---

## Version Management

```bash
# From Git tag (v1.2.3 → version: 1.2.3+<build_number>)
TAG="${GITHUB_REF#refs/tags/v}"   # GitHub Actions
BUILD_NUMBER="${GITHUB_RUN_NUMBER}"

# Update pubspec.yaml
sed -i "s/^version:.*/version: ${TAG}+${BUILD_NUMBER}/" pubspec.yaml
```

---

## Quick Wins Checklist

- [ ] Flutter version pinned — not `latest`
- [ ] `build_runner` runs before every build
- [ ] `--obfuscate --split-debug-info` on all release builds
- [ ] Debug symbols uploaded to Crashlytics after every release
- [ ] Coverage threshold enforced (fail if < 80%)
- [ ] `dart format --set-exit-if-changed` in quality gate
- [ ] `flutter analyze --fatal-infos` in quality gate
- [ ] Keystore never committed to repo — always from secrets
- [ ] `key.properties` in `.gitignore`
- [ ] Separate pipelines for PR (quality only) and release (full)
- [ ] Environment-specific `--dart-define` per flavor

## Reference Files

- `references/cd_strategy.md` — **start here** — branch strategy, trigger rules, environment mapping, complete GitHub Actions workflows for GitFlow and Trunk-Based
- `references/github_actions.md` — GitHub Actions PR + release workflows (full pipeline)
- `references/azure_devops.md` — Azure DevOps YAML pipeline (PR + release)
- `references/jenkins.md` — Jenkinsfile declarative pipeline
- `references/fastlane_signing.md` — Fastlane setup, match, iOS/Android lanes, Appfile

## Ready-to-Use Assets

- `assets/release_workflow.yml` — copy to `.github/workflows/release.yml` in your project
