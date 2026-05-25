---
name: flutter-melos-management
description: >
  Professional management of Flutter monorepos with Melos 7.x. Use this skill for everything related to Melos: initial setup, pubspec.yaml workspace configuration, bootstrap, scripts, exec, versioning with Conventional Commits, publishing, CI/CD integration, adding packages, managing dependencies across packages, and workspace maintenance. Triggers on 'melos', 'monorepo', 'melos bootstrap', 'melos run', 'melos exec', 'melos version', 'add package to monorepo', 'shared package', 'workspace', 'resolution: workspace', or any question about managing multiple Flutter packages together. Stack: melos 7.5.1, Dart 3.8+, Flutter 3.32+.
commands:
  - manage-melos
inputs:
  - name: action
    description: Action to perform (setup, add-package, audit, version, ci-setup). "setup" initializes a new Melos workspace, "add-package" adds a new package to an existing workspace, "audit" checks workspace health (dependency conflicts, missing resolution, outdated packages), "version" bumps versions using Conventional Commits, "ci-setup" generates CI/CD pipeline configuration for the monorepo.
    required: true
  - name: target
    description: Path to the workspace root (for setup/audit/version/ci-setup) or the new package path (for add-package, e.g. packages/feature_payments).
    required: true
  - name: package_type
    description: Type of package to create when action is "add-package" (feature, core, ui, app). Determines the directory structure and default dependencies.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# Melos 7.x — Flutter Monorepo Management

Professional management of multi-package Flutter repositories.
Melos 7.x uses **Dart pub workspaces** — no `melos.yaml`, no `pubspec_overrides.yaml`.
All configuration lives in the root `pubspec.yaml`.

---

## Installation

```bash
# Install globally — required once per machine
dart pub global activate melos

# Verify
melos --version   # should show 7.5.1

# Add to PATH if not already (add to ~/.zshrc or ~/.bashrc)
export PATH="$PATH:$HOME/.pub-cache/bin"
```

---

## Workspace Structure

```
my_project/
├── pubspec.yaml                  ← Root: workspace list + melos config (no melos.yaml)
│
├── apps/
│   ├── app_mobile/               ← Main Flutter app
│   │   ├── lib/
│   │   ├── android/
│   │   ├── ios/
│   │   └── pubspec.yaml          ← resolution: workspace
│   └── app_tablet/               ← Tablet variant (optional)
│       └── pubspec.yaml          ← resolution: workspace
│
└── packages/
    ├── core/                     ← Shared: Failure, UseCase, ApiClient, CacheStore
    │   └── pubspec.yaml          ← resolution: workspace
    ├── ui_system/                ← Design system: tokens, atoms, molecules, organisms
    │   └── pubspec.yaml          ← resolution: workspace
    ├── feature_auth/             ← Auth feature package
    │   └── pubspec.yaml          ← resolution: workspace
    ├── feature_catalog/          ← Catalog feature package
    │   └── pubspec.yaml          ← resolution: workspace
    └── feature_checkout/         ← Checkout feature package
        └── pubspec.yaml          ← resolution: workspace
```

---

## Root pubspec.yaml — Complete Configuration

In Melos 7.x, the root `pubspec.yaml` replaces `melos.yaml` entirely.

```yaml
# pubspec.yaml (workspace root)
name: my_project
description: Workspace root — not a publishable package.
publish_to: none

environment:
  sdk: ">=3.8.0 <4.0.0"   # Dart 3.6+ required for pub workspaces

# ─── Pub Workspaces ───────────────────────────────────────────────────────────
# List all packages explicitly — globs are not yet supported
workspace:
  - apps/app_mobile
  - apps/app_tablet
  - packages/core
  - packages/ui_system
  - packages/feature_auth
  - packages/feature_catalog
  - packages/feature_checkout

dev_dependencies:
  melos: ^7.5.1

# ─── Melos Configuration ──────────────────────────────────────────────────────
melos:
  # Versioning configuration
  command:
    version:
      workspaceChangelog: true
      branch: main
      tagVersionSeparator: "/"
      message: "chore(release): publish packages\n\n{new_package_versions}"

    bootstrap:
      hooks:
        post: melos run build_runner

  # ─── Scripts ────────────────────────────────────────────────────────────────
  scripts:

    # ── Quality ────────────────────────────────────────────────────────────────

    analyze:
      run: melos exec -- "flutter analyze --no-pub --fatal-infos"
      description: Run flutter analyze on all Flutter packages
      packageFilters:
        flutter: true

    format:
      run: melos exec -- "dart format --set-exit-if-changed lib/ test/"
      description: Check formatting on all packages

    format:fix:
      run: melos exec -- "dart format lib/ test/"
      description: Apply formatting on all packages

    # ── Testing ────────────────────────────────────────────────────────────────

    test:
      run: melos exec --concurrency=4 -- "flutter test --coverage --reporter=github"
      description: Run tests on all packages that have a test/ directory
      packageFilters:
        flutter: true
        dirExists: test

    coverage:
      run: |
        melos exec -- "flutter test --coverage"
        melos exec -- "lcov --remove coverage/lcov.info '*.freezed.dart' '*.g.dart' '*.config.dart' -o coverage/lcov_filtered.info"
        melos exec -- "lcov --summary coverage/lcov_filtered.info"
      description: Run tests with coverage and filter generated files
      packageFilters:
        flutter: true
        dirExists: test

    # ── Code Generation ────────────────────────────────────────────────────────

    build_runner:
      run: melos exec -- "dart run build_runner build --delete-conflicting-outputs"
      description: Run build_runner on packages that depend on it
      packageFilters:
        dependsOn: build_runner

    build_runner:watch:
      run: melos exec -- "dart run build_runner watch --delete-conflicting-outputs"
      description: Run build_runner in watch mode
      packageFilters:
        dependsOn: build_runner

    # ── Maintenance ────────────────────────────────────────────────────────────

    clean:
      run: melos exec -- "flutter clean"
      description: Clean all packages
      packageFilters:
        flutter: true

    get:
      run: dart pub get
      description: Resolve all workspace dependencies (runs at root)

    outdated:
      run: melos exec -- "flutter pub outdated"
      description: Check outdated dependencies on all packages

    # ── CI Pipeline ────────────────────────────────────────────────────────────

    ci:
      run: |
        melos run format
        melos run analyze
        melos run build_runner
        melos run test
      description: Full CI pipeline — format, analyze, codegen, test

    # ── Script Groups (7.x) ────────────────────────────────────────────────────
    # Groups allow running related scripts together
    groups:
      quality:
        - format
        - analyze
      codegen:
        - build_runner
```

---

## Per-Package pubspec.yaml

Every package in the workspace must declare `resolution: workspace`:

```yaml
# packages/feature_auth/pubspec.yaml
name: feature_auth
description: Authentication feature — domain, data, and presentation layers.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.8.0 <4.0.0"
  flutter: ">=3.32.0"

# ← Required in every workspace package (Melos 7.x / pub workspaces)
resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  # Local workspace packages — no path: needed, workspace resolves them
  core: any
  ui_system: any
  # External packages
  flutter_bloc: ^9.1.1
  bloc_concurrency: ^0.3.0
  get_it: ^9.2.1
  injectable: ^3.0.0
  freezed_annotation: ^3.1.0
  json_annotation: ^4.11.0
  fpdart: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.15.0
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
  json_serializable: ^6.13.1
  bloc_test: ^9.1.7
  mocktail: ^1.0.5
  flutter_lints: ^6.0.0
```

> **Key difference from 6.x:** Local workspace packages use `any` as the version
> constraint instead of `path: ../../packages/core`. Pub workspaces resolves them
> automatically via the root `pubspec.yaml` workspace list.

---

## Core Commands

### Bootstrap

```bash
# Resolve all workspace dependencies (replaces melos bootstrap in 7.x)
dart pub get

# Or use melos bootstrap (still works, calls dart pub get internally)
melos bootstrap
melos bs
```

> In Melos 7.x, `dart pub get` at the root resolves all workspace packages.
> No `pubspec_overrides.yaml` files are created.

### Exec

```bash
# Run a command in all packages
melos exec -- "flutter pub get"

# Run in packages matching a filter
melos exec --scope=feature_* -- "flutter test"
melos exec --depends-on=freezed -- "dart run build_runner build --delete-conflicting-outputs"
melos exec --flutter -- "flutter analyze"

# Run with concurrency limit (default: number of processors)
melos exec --concurrency=2 -- "flutter test"

# Fail fast — stop on first error
melos exec --fail-fast -- "flutter analyze"

# Run sequentially
melos exec --no-concurrency -- "flutter pub get"

# Run in topological order (dependencies first)
melos exec --order-dependents -- "flutter pub get"
```

### Run Scripts

```bash
# List all available scripts
melos run
melos run --list   # 7.x: shows scripts as a list

# Run a specific script
melos run analyze
melos run test
melos run build_runner
melos run ci

# Run with package filter (7.x)
melos run test --scope=feature_auth
```

### Format (built-in in 7.x)

```bash
# Format all packages
melos format

# Format with line length
melos format --line-length=120

# Check formatting without applying
melos format --set-exit-if-changed
```

### List Packages

```bash
# List all packages
melos list

# List with details
melos list --long

# List as JSON
melos list --json

# List as Mermaid diagram (7.x)
melos list --mermaid

# List packages that depend on a specific package
melos list --depends-on=core

# List packages that changed since last tag
melos list --diff=HEAD~1
```

### Clean

```bash
# Clean all packages
melos clean

# Clean and re-bootstrap
melos clean && dart pub get
```

---

## Package Filters

```bash
# By name (supports glob)
--scope=feature_*
--scope=feature_auth,feature_catalog

# Exclude packages
--ignore=feature_checkout

# Only Flutter packages
--flutter

# Only Dart packages
--no-flutter

# Packages that depend on a specific package
--depends-on=core

# Packages that have a specific directory
--dir-exists=test

# Packages that changed since a git ref
--diff=HEAD~1
--diff=main

# Published packages only
--published

# Private packages only (publish_to: none)
--private
```

---

## Versioning with Conventional Commits

```bash
# Preview version bumps (dry run — always run first)
melos version --dry-run

# Bump versions, update CHANGELOG.md, create git tags
melos version

# Skip confirmation (for CI)
melos version --yes

# Only bump packages that changed since last tag
melos version --diff=HEAD~1

# Create a pre-release
melos version --prerelease-id=dev

# Graduate pre-release to stable (0.3.0-dev.3 → 0.3.0)
melos version --graduate
```

### Commit Message Format

```
feat(feature_auth): add biometric login       → minor bump (0.x.0)
fix(core): handle null in ApiClient           → patch bump (0.0.x)
feat(core)!: rename ApiClient.get to fetch    → major bump (x.0.0)
chore: update dependencies                    → no bump
```

---

## Adding a New Package to the Workspace

```bash
# 1. Create the package directory and pubspec.yaml
mkdir -p packages/feature_payments/lib/src

cat > packages/feature_payments/pubspec.yaml << 'EOF'
name: feature_payments
description: Payments feature.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.8.0 <4.0.0"
  flutter: ">=3.32.0"

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  core: any

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.15.0
  freezed: ^3.2.5
EOF

# 2. Create the barrel export
echo "library feature_payments;" > packages/feature_payments/lib/feature_payments.dart

# 3. Add to the workspace list in root pubspec.yaml
# workspace:
#   - ...existing packages...
#   - packages/feature_payments   ← add this line

# 4. Resolve workspace dependencies
dart pub get

# 5. Add as a dependency in the app's pubspec.yaml
# dependencies:
#   feature_payments: any   ← workspace resolves it

# 6. Re-resolve
dart pub get
```

---

## .gitignore for Melos 7.x Workspaces

```gitignore
# Pub / Dart tool
.dart_tool/
.packages
build/

# Melos 7.x — no pubspec_overrides.yaml generated
# (nothing extra to ignore compared to a regular Flutter project)
```

---

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main, develop]
  push:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Required for melos version --diff

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'
          cache: true

      - name: Install Melos
        run: dart pub global activate melos 7.5.1

      - name: Bootstrap workspace
        run: melos bootstrap

      - name: Check formatting
        run: melos run format

      - name: Analyze
        run: melos run analyze

      - name: Generate code
        run: melos run build_runner

      - name: Run tests
        run: melos run test
```

### Release workflow

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    # Skip if this is already a version bump commit
    if: "!contains(github.event.head_commit.message, 'chore(release)')"
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          token: ${{ secrets.PAT }}

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.32.0'

      - name: Configure git
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"

      - name: Install Melos
        run: dart pub global activate melos 7.5.1

      - name: Bootstrap
        run: melos bootstrap

      - name: Version packages
        run: melos version --yes

      - name: Push version commit and tags
        run: git push --follow-tags origin main
```

---

## Environment Variables in Scripts

| Variable | Description |
|---|---|
| `MELOS_PACKAGE_NAME` | Current package name |
| `MELOS_PACKAGE_VERSION` | Current package version |
| `MELOS_PACKAGE_PATH` | Absolute path to the package |
| `MELOS_ROOT_PATH` | Absolute path to the workspace root |
| `MELOS_WORKSPACE_NAME` | Workspace name |

```yaml
scripts:
  echo:
    run: echo "Running in $MELOS_PACKAGE_NAME at $MELOS_PACKAGE_PATH"
```

---

## Common Errors and Solutions

| Error | Cause | Solution |
|---|---|---|
| `Package not found in workspace` | Package not in `workspace:` list | Add it to root `pubspec.yaml` workspace list, run `dart pub get` |
| `resolution: workspace missing` | Package not declaring workspace resolution | Add `resolution: workspace` to the package's `pubspec.yaml` |
| `Dependency conflict` | Two packages require incompatible versions | Align versions across all `pubspec.yaml` files |
| `melos: command not found` | Not in PATH | Add `$HOME/.pub-cache/bin` to PATH |
| `Bootstrap fails on CI` | Missing `fetch-depth: 0` | Add `fetch-depth: 0` to `actions/checkout` |
| `Version command finds no changes` | No Conventional Commits since last tag | Check commit messages follow the format |
| `Workspace globs not supported` | Trying to use `workspace: - packages/**` | List all packages explicitly in `workspace:` |

---

## Reference Files

- `references/pubspec_yaml_complete.md` — Full annotated root `pubspec.yaml` with all melos options
- `references/versioning_guide.md` — Conventional Commits, CHANGELOG generation, pre-releases, graduate
