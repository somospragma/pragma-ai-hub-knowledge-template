---
name: flutter-ci-optimization
description: >
  Optimizes Flutter CI/CD pipelines to achieve fast feedback loops: pub cache, Flutter SDK cache, build_runner output cache, parallel jobs, conditional builds (path filters), test sharding, concurrency cancellation, and pipeline time budgets. Target: PR quality gate under 8 minutes, full release pipeline under 20 minutes. Use this skill when pipelines are slow, builds run unnecessarily, tests take too long, or the team is waiting too long for CI feedback.
commands:
  - optimize-ci
inputs:
  - name: action
    description: Action to perform (audit, optimize, configure). "audit" analyzes an existing pipeline for missing caches, sequential jobs, and unnecessary steps, "optimize" applies speed improvements to the pipeline configuration, "configure" generates an optimized CI pipeline from scratch.
    required: true
  - name: target
    description: Path to the CI configuration file or directory (e.g. .github/workflows/ for GitHub Actions, azure-pipelines.yml for Azure DevOps).
    required: true
  - name: platform
    description: CI platform (github-actions, azure-devops, jenkins). Determines the syntax and available optimizations.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "1.1"
---

# CI Optimization

See the reference files for complete patterns and code examples.

**The goal: fast feedback. A developer should know if their PR is green within 8 minutes.**

## Why CI Speed Matters

```
Slow CI (> 20 min)  → developers stop waiting → they context-switch → bugs slip through
Fast CI (< 8 min)   → developers stay focused → immediate feedback → higher quality
```

## Time Budget Targets

| Pipeline | Target | Acceptable max |
|---|---|---|
| PR quality gate | < 8 min | 12 min |
| Full release build (Android + iOS parallel) | < 20 min | 30 min |
| Nightly / scheduled full suite | < 45 min | 60 min |

---

## The 5 Levers of CI Speed

| Lever | Typical saving | Effort |
|---|---|---|
| **1. Caching** (pub, Flutter SDK, build_runner) | 3–6 min | Low |
| **2. Parallel jobs** (Android + iOS simultaneously) | 5–10 min | Low |
| **3. Conditional builds** (skip if unrelated files changed) | 2–8 min | Medium |
| **4. Test sharding** (split tests across runners) | 50–70% of test time | Medium |
| **5. Concurrency cancellation** (cancel stale PR runs) | Eliminates queue waste | Low |

---

## Quick Wins — Apply in Order

```
1. Add pub cache          → saves ~2 min every run
2. Add Flutter SDK cache  → saves ~1 min every run
3. Cancel stale runs      → eliminates queue buildup
4. Parallelize Android/iOS → saves 5–10 min on release
5. Add path filters       → skips build when only docs changed
6. Cache build_runner     → saves ~1 min on codegen-heavy projects
7. Shard tests            → cuts test time by 50–70%
```

---

## Minimum Viable Cache (add to every pipeline)

```yaml
# 1. Flutter SDK cache (built into subosito/flutter-action)
- uses: subosito/flutter-action@v2
  with:
    flutter-version: '3.32.0'
    cache: true              # ✅ caches the Flutter SDK

# 2. Pub dependencies cache
- uses: actions/cache@v4
  with:
    path: ~/.pub-cache
    key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
    restore-keys: pub-${{ runner.os }}-

# 3. Cancel stale runs on new push
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

---

## Quick Wins Checklist

- [ ] `subosito/flutter-action` with `cache: true` — Flutter SDK cached
- [ ] `actions/cache@v4` for `~/.pub-cache` keyed on `pubspec.lock`
- [ ] `concurrency.cancel-in-progress: true` — stale PR runs cancelled
- [ ] Android and iOS build jobs run in parallel (`needs: quality`)
- [ ] Path filters skip build when only `*.md`, `docs/`, `assets/` changed
- [ ] `build_runner` output cached keyed on `pubspec.lock` + source hash
- [ ] `flutter test --concurrency=4` — parallel test execution
- [ ] Test sharding for large test suites (> 200 tests)
- [ ] `flutter analyze` runs before tests (fails fast on syntax errors)
- [ ] Generated files committed — no `build_runner` on every CI run

## Reference Files

- `references/caching.md` — pub cache, Flutter SDK cache, build_runner cache, Gradle cache
- `references/parallelism_and_conditions.md` — parallel jobs, path filters, conditional steps, concurrency cancellation
- `references/test_optimization.md` — test sharding, concurrency flag, flaky test quarantine, coverage filtering
