---
name: test-plan
description: >
  Workflow for analyzing, planning, and generating complete test coverage
  for an existing feature. Inventories all source files, identifies missing
  tests, generates unit/widget tests per layer, validates coverage targets,
  and produces a testing report. Use when a feature exists but lacks tests
  or has incomplete coverage.
trigger: "@test-coverage-engineer /test-plan"
metadata:
  author: Pragma Mobile Chapter
  version: "1.0"
---

# Workflow: Test Plan (Full Coverage for Existing Feature)

## When to Use

Use this workflow when:

- A feature exists and has no tests or incomplete test coverage
- The user asks to "add tests", "improve coverage", "test the checkout feature"
- After a `/new-feature` workflow completes (tests are a separate step)
- After a `/refactor-feature` workflow if coverage is still below targets
- The user wants a coverage report for a specific feature

Do NOT use for:
- Testing DS components (use `@test-engineer` via DS pipeline)
- Golden tests (use `@golden-test-engineer`)
- Integration/E2E tests (separate workflow — future)
- Creating a new feature (use `/new-feature`)

---

## Prerequisites

- Feature must already exist at the given path with source code
- `.copilot/config/project.config.yaml` valid (or run `/bootstrap-workspace` first)
- Context resolved:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`

---

## Inputs

```text
@test-coverage-engineer /test-plan
feature_name: product_catalog
feature_path: lib/src/features/product_catalog/
```

### Input variations

```text
# Full coverage (default — all layers)
@test-coverage-engineer /test-plan
feature_name: product_catalog
feature_path: lib/src/features/product_catalog/

# Single layer focus
@test-coverage-engineer /test-plan
feature_name: checkout
feature_path: lib/src/features/checkout/
scope: presentation

# Specific files focus
@test-coverage-engineer /test-plan
feature_name: auth
feature_path: lib/src/features/auth/
focus: login_bloc.dart, token_repository_impl.dart

# Monorepo package
@test-coverage-engineer /test-plan
feature_name: payments
feature_path: packages/payments/lib/
topology: monorepo_melos
target_root: packages/payments/
```

---

## Execution Sequence

### PHASE 1 — Feature Analysis

**Agent:** `@test-coverage-engineer`

Steps:
1. Read all source files in `feature_path` recursively
2. Classify each file by layer (domain / data / presentation)
3. For each source file identify:
   - Public classes and methods
   - Dependencies (imports, injected services)
   - Complexity (branches, async, Either paths)
4. Locate existing test directory and map coverage:
   - Which source files have test files
   - Which test files are incomplete (not all paths tested)
   - Which source files have zero tests
5. Produce coverage inventory table

Output: Coverage inventory in console (or `PIPELINE_SPEC_PATH` if in pipeline).

---

### PHASE 2 — Test Plan

**Agent:** `@test-coverage-engineer`

Steps:
1. For each missing/incomplete test, define:
   - Test file path (mirroring source structure)
   - Test cases (descriptive names following `should [verb] when [condition]`)
   - Mocks needed (one level deep)
   - Fixtures needed (JSON responses, entity instances)
2. Prioritize: domain → data → BLoC → pages
3. Estimate total test cases to generate

Output: Test plan summary.

---

### PHASE 3 — Test Generation

**Agent:** `@test-coverage-engineer`

Steps:
1. Create test directory structure (mirror source)
2. For **missing** tests (🆕): generate complete test files
3. For **incomplete** tests (⚠️): add missing test cases to existing files
4. For **outdated** tests (🔄): update mocks, patterns, assertions to match current source
5. Track every modification to existing tests with a reason (for the report)
6. Each test file follows:
   - `mocktail 1.0.5` for mocking
   - `bloc_test 9.1.7` for BLoC
   - AAA pattern
   - `group()` for organization
   - One test file per source file

Test generation per layer:
- **Domain**: use case tests (success + failure + edge cases)
- **Data**: repository tests (remote success, remote failure, cache), mapper tests, data source tests
- **Presentation BLoC**: `blocTest()` for every event → state transition
- **Presentation Pages**: widget tests (render per state, interactions, navigation)
- **Integration**: full user flow tests (navigation, data loading, user actions)
  - Location: `integration_test/features/{feature_name}/`
  - Uses `IntegrationTestWidgetsFlutterBinding`
  - One test per main user flow
  - CANNOT be executed by the agent — marked as "pending manual validation"

Output: Test files created/modified on disk (unit + widget + integration).

---

### PHASE 4 — Execution & Validation

**Agent:** `@test-coverage-engineer`

Steps:
1. Run all tests:
   - `flutter test test/features/{feature_name}/`
   - Monorepo: `melos exec --scope={target_scope} -- "flutter test"`
2. Fix any failing tests immediately
3. Run coverage check:
   - `flutter test --coverage test/features/{feature_name}/`
4. Validate per-layer targets:
   - Domain: 95%+
   - Data: 85%+
   - Presentation BLoC: 85%+
   - Presentation Pages: 70%+
5. If below target: generate additional tests for uncovered branches
6. Re-run until all targets met

Output: All tests passing, coverage validated.

---

### PHASE 5 — Testing Report (mandatory — FILE CREATION action)

**Agent:** `@test-coverage-engineer`

> **CRITICAL: This is a FILE CREATION action. The agent MUST create this file
> on disk. The workflow is NOT complete until this file exists.**

**Action:** Create a NEW file at this EXACT path:
`{PROJECT_ROOT}/docs/testing/{feature_name}-testing-report-{YYYY-MM-DD}.md`

**Steps:**
1. If `docs/testing/` directory does not exist → CREATE IT
2. Create the file with:
   - Summary metrics (files analyzed, tests created, tests modified, tests passing)
   - Coverage by layer table (files, tests, coverage %, target, status)
   - Test inventory per layer (source file → test file → test cases → status)
   - **Changes to existing tests** table (file, action, reason for each modification)
   - Mocks created table
   - Gaps & recommendations
   - Run commands
3. VERIFY the file exists on disk after creation

**Example path:** `docs/testing/product_catalog-testing-report-2026-05-11.md`

Output: Testing report file created at `docs/testing/`.

---

## Mandatory Post-Execution Checklist

> **The agent MUST complete ALL items below before reporting to the user.
> If any item is missing, the test plan is INCOMPLETE.**

| # | Action | Verification |
|---|---|---|
| A | Generate test files for all untested source files | Files exist on disk |
| B | Run tests — all pass | `flutter test` exits with 0 |
| C | Validate coverage targets met | Domain 95%+, Data 85%+, BLoC 85%+, Pages 70%+ |
| D | Create `docs/testing/{feature_name}-testing-report-{date}.md` | File exists on disk (read it back) |
| E | Report final summary to user | Only after A–D are done |

---

## Verification (topology-aware)

After all phases:

- `single_repo`:
  ```bash
  flutter test test/features/{feature_name}/
  flutter test --coverage test/features/{feature_name}/
  ```
- `monorepo_melos`:
  ```bash
  melos exec --scope={target_scope} -- "flutter test"
  melos exec --scope={target_scope} -- "flutter test --coverage"
  ```

---

## Rules

### Completion criteria (ALL must be true)
- [ ] All source files have corresponding test files (unit + widget)
- [ ] All unit + widget tests pass (zero failures)
- [ ] Coverage targets met per layer
- [ ] Integration test files generated for main user flows
- [ ] Testing report file EXISTS at `docs/testing/{feature_name}-testing-report-{date}.md`

### Prohibitions
- NEVER use mockito — always mocktail
- NEVER test generated code (*.g.dart, *.freezed.dart)
- NEVER write tests that depend on other tests
- NEVER skip a layer — test domain, data, AND presentation
- NEVER end without creating the testing report file in `docs/testing/`
- NEVER leave failing tests

### Obligations
- ALWAYS mirror source directory structure in test directory
- ALWAYS use AAA pattern
- ALWAYS test both success AND failure paths
- ALWAYS test all BLoC events and state transitions
- ALWAYS use `blocTest()` for BLoC tests
- ALWAYS track every modification to existing tests with a reason (for the report)
- ALWAYS include "Changes to Existing Tests" section in the report (even if empty)
- ALWAYS generate integration tests for main user flows (in `integration_test/features/{feature_name}/`)
- ALWAYS mark integration tests as "pending manual validation" in the report
- ALWAYS create `docs/testing/` directory if it doesn't exist
- ALWAYS create the testing report file as the LAST action before reporting
- ALWAYS verify the report file exists on disk after creating it
- ALWAYS run `flutter test` to confirm all unit + widget tests pass before finishing
- NEVER attempt to run integration tests — they require a device/emulator
