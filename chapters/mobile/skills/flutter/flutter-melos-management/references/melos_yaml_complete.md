# Root pubspec.yaml — Complete Annotated Reference (Melos 7.5.1)

In Melos 7.x, there is no `melos.yaml`. All configuration lives in the root `pubspec.yaml`
under the `melos:` key, alongside the `workspace:` list required by Dart pub workspaces.

```yaml
# pubspec.yaml (workspace root)
name: my_project
description: Workspace root — not a publishable package.
publish_to: none

environment:
  sdk: ">=3.8.0 <4.0.0"   # Dart 3.6+ required for pub workspaces

# ─── Pub Workspaces ───────────────────────────────────────────────────────────
# All packages must be listed explicitly — globs are not yet supported.
# Each listed package must have `resolution: workspace` in its own pubspec.yaml.
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

  # ── Command Configuration ────────────────────────────────────────────────────

  command:
    bootstrap:
      # Run a hook after bootstrap completes
      hooks:
        post: melos run build_runner

    clean:
      hooks:
        pre: echo "Cleaning workspace..."

    version:
      # Generate a workspace-level CHANGELOG.md in addition to per-package ones
      workspaceChangelog: true
      # Git tag format: {package_name}/{version}
      tagVersionSeparator: "/"
      # Commit message for the version bump commit
      message: "chore(release): publish packages\n\n{new_package_versions}"
      # Branch that is allowed to run melos version
      branch: main

  # ── Scripts ──────────────────────────────────────────────────────────────────

  scripts:

    # ── Simple script ──────────────────────────────────────────────────────────

    analyze:
      run: melos exec -- "flutter analyze --no-pub --fatal-infos"
      description: Run flutter analyze on all Flutter packages
      packageFilters:
        flutter: true

    # ── Script with multiple steps ─────────────────────────────────────────────

    ci:
      run: |
        melos run format
        melos run analyze
        melos run build_runner
        melos run test
      description: Full CI pipeline

    # ── Script with package filters ────────────────────────────────────────────

    test:
      run: melos exec --concurrency=4 -- "flutter test --coverage --reporter=github"
      description: Run tests on all packages that have a test/ directory
      packageFilters:
        flutter: true
        dirExists: test

    # ── Script with exec and dependency filter ─────────────────────────────────

    build_runner:
      run: melos exec -- "dart run build_runner build --delete-conflicting-outputs"
      description: Run build_runner on packages that depend on it
      packageFilters:
        dependsOn: build_runner

    # ── Script with hooks ──────────────────────────────────────────────────────

    publish:
      run: melos publish --yes
      description: Publish all changed packages
      hooks:
        pre: melos run test
        post: echo "Published successfully"

    # ── Private script (not shown in melos run list) ───────────────────────────

    _internal:setup:
      run: echo "Internal setup"
      private: true

    # ── Script with package filter options in yaml (7.x) ──────────────────────

    test:auth:
      run: melos exec -- "flutter test --coverage"
      description: Run tests only on feature_auth
      packageFilters:
        scope: feature_auth

    # ── Script groups (7.x) ────────────────────────────────────────────────────
    # Run multiple scripts together: melos run quality
    groups:
      quality:
        - format
        - analyze
      codegen:
        - build_runner
```

---

## Package Filter Reference

All filters can be used in `packageFilters` within scripts or as CLI flags with `melos exec`.

```yaml
packageFilters:
  # By name (supports glob patterns)
  scope: feature_*
  # or as a list:
  scope:
    - feature_auth
    - feature_catalog

  # Exclude packages
  ignore: feature_checkout

  # Only Flutter packages
  flutter: true

  # Only Dart packages (no Flutter)
  flutter: false

  # Packages that depend on a specific package
  dependsOn: core
  dependsOn:
    - core
    - flutter_bloc

  # Packages that have a specific directory
  dirExists: test

  # Packages that have a specific file
  fileExists: analysis_options.yaml

  # Packages that changed since a git ref
  diff: HEAD~1
  diff: main

  # Only published packages (no publish_to: none)
  published: true

  # Only private packages (publish_to: none)
  private: true
```

---

## Per-Package pubspec.yaml Template

```yaml
# packages/feature_auth/pubspec.yaml
name: feature_auth
description: Authentication feature — domain, data, and presentation layers.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.8.0 <4.0.0"
  flutter: ">=3.32.0"

# ← REQUIRED in every workspace package
resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  # Local workspace packages — use `any`, workspace resolves them
  core: any
  ui_system: any
  # External packages — pin to major version
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

---

## Key Differences from Melos 6.x

| Melos 6.x | Melos 7.x |
|---|---|
| `melos.yaml` at root | No `melos.yaml` — config in root `pubspec.yaml` under `melos:` |
| `packages:` glob in `melos.yaml` | `workspace:` list in root `pubspec.yaml` (no globs) |
| `pubspec_overrides.yaml` per package | `resolution: workspace` in each package |
| `path: ../../packages/core` for local deps | `core: any` — workspace resolves it |
| `melos bootstrap` creates overrides | `dart pub get` at root resolves everything |
| `command.bootstrap.usePubspecOverrides: true` | Not needed |
