# Versioning Guide — Conventional Commits + Melos 7.5.1

## Conventional Commits Format

```
<type>(<scope>): <short description>

[optional body — explain WHY, not WHAT]

[optional footer]
BREAKING CHANGE: <description of what breaks and how to migrate>
```

### Types and Version Bumps

| Type | Description | Version bump |
|---|---|---|
| `fix` | Bug fix | **patch** (0.0.x) |
| `feat` | New feature | **minor** (0.x.0) |
| `feat!` or `BREAKING CHANGE` | Breaking change | **major** (x.0.0) |
| `chore` | Maintenance, tooling | none |
| `docs` | Documentation only | none |
| `style` | Formatting, no logic change | none |
| `refactor` | Code restructure, no behavior change | none |
| `perf` | Performance improvement | none |
| `test` | Adding or fixing tests | none |
| `build` | Build system changes | none |
| `ci` | CI configuration changes | none |

### Scope

The scope is optional but recommended — it identifies which package or area was changed:

```
feat(feature_auth): add biometric login support
fix(core): handle null response in ApiClient
chore(deps): upgrade flutter_bloc to 9.1.1
```

### Examples

```bash
# Patch bump (bug fix)
git commit -m "fix(feature_catalog): correct price formatting for COP currency"

# Minor bump (new feature)
git commit -m "feat(feature_auth): add Google Sign-In support"

# Major bump (breaking change — method 1: ! suffix)
git commit -m "feat(core)!: rename ApiClient.get to ApiClient.fetch"

# Major bump (breaking change — method 2: footer)
git commit -m "refactor(core): restructure error handling

BREAKING CHANGE: Failure.network now requires statusCode parameter.
Migrate: Failure.network(message: msg) → Failure.network(message: msg, statusCode: null)"

# No version bump
git commit -m "chore: update melos to 6.3.0"
git commit -m "docs(feature_auth): add README with setup instructions"
git commit -m "test(feature_catalog): add pagination tests"
```

---

## melos version Workflow

### 1. Preview (always run first)

```bash
# See what would be bumped without making any changes
melos version --dry-run
```

Output example:
```
🔍 Determining version bumps...

  feature_auth: 0.2.1 → 0.3.0 (minor — feat: add biometric login)
  core: 1.0.3 → 1.0.4 (patch — fix: null safety in ApiClient)
  feature_catalog: 0.1.0 → 0.1.0 (no changes)

📝 Workspace CHANGELOG.md will be updated.
```

### 2. Apply versions

```bash
# Bump versions, update CHANGELOG.md, create git tags, commit
melos version

# Skip confirmation prompt (for CI)
melos version --yes

# Only bump packages that changed since the last tag
melos version --diff=HEAD~1

# Bump all packages to the same version (monolithic versioning)
melos version --all --yes
```

### 3. Push

```bash
# Push the version commit and all new tags
git push --follow-tags
```

---

## Pre-release Versions

```bash
# Create a pre-release (e.g., 0.3.0-dev.1)
melos version --prerelease-id=dev

# Subsequent pre-releases increment automatically
# 0.3.0-dev.1 → 0.3.0-dev.2 → 0.3.0-dev.3

# Graduate pre-release to stable (0.3.0-dev.3 → 0.3.0)
melos version --graduate

# Graduate only specific packages
melos version --graduate --scope=feature_auth
```

---

## CHANGELOG.md Format

Melos generates a `CHANGELOG.md` per package following the [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## 0.3.0 - 2026-04-30

### Features

- **feature_auth**: add biometric login support ([abc1234](https://github.com/...))

### Bug Fixes

- **core**: handle null response in ApiClient ([def5678](https://github.com/...))

---

## 0.2.1 - 2026-03-15

### Bug Fixes

- **feature_auth**: fix token refresh race condition ([ghi9012](https://github.com/...))
```

---

## Workspace CHANGELOG.md

When `workspaceChangelog: true` is set in `melos.yaml`, a root-level `CHANGELOG.md`
aggregates all package changes:

```markdown
## 2026-04-30

### Packages

- `feature_auth` upgraded from `0.2.1` to `0.3.0`
- `core` upgraded from `1.0.3` to `1.0.4`
```

---

## Automated Releases in CI

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: ubuntu-latest
    # Only run if the commit is NOT a version bump commit
    if: "!contains(github.event.head_commit.message, 'chore(release)')"
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0            # Required for git history analysis
          token: ${{ secrets.PAT }} # Personal Access Token with push rights

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

      - name: Version and publish
        run: melos version --yes
        env:
          GIT_AUTHOR_NAME: github-actions[bot]
          GIT_AUTHOR_EMAIL: github-actions[bot]@users.noreply.github.com

      - name: Push version commit and tags
        run: git push --follow-tags origin main
```

---

## Versioning Strategy Decision

| Strategy | When to use | melos.yaml setting |
|---|---|---|
| **Independent** (default) | Each package has its own version | Default behavior |
| **Locked** | All packages share the same version | `melos version --all` |
| **Diff-based** | Only changed packages get bumped | `melos version --diff=HEAD~1` |

For most Flutter monorepos, **independent versioning** is recommended — it allows
feature packages to evolve at their own pace without forcing a version bump on
unrelated packages.
