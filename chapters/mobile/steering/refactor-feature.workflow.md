---
name: refactor-feature
description: >
  Workflow for refactoring an existing feature that already follows Clean
  Architecture (or close to it). Analyzes code smells, architectural
  violations, and complexity — then executes incremental improvements that
  keep the app compiling at every stage. Not for DS components (use
  /refactor-component) or legacy rewrites from scratch.
trigger: "@refactoring-advisor /refactor-feature"
metadata:
  author: Pragma Mobile Chapter
  version: "1.0"
---

# Workflow: Refactor Feature (Evolutionary Improvement)

## When to Use

Use this workflow when:

- The feature already exists and follows Clean Architecture (or partially)
- The user wants to improve structure without rewriting from scratch
- The BLoC is too large and needs splitting
- A use case is inline in the BLoC and needs extraction
- The feature needs to be moved to a Melos package
- Patterns need updating (dartz→fpdart, fold→match, Freezed 2→3)
- Layers have violations (presentation importing data, BLoC calling DataSource)
- The feature needs a new endpoint/entity added to existing structure

Do NOT use for:
- DS component refactoring (use `/refactor-component`)
- Creating a new feature from scratch (use `/new-feature`)
- Adding tests to existing code (use `/test-plan`)

---

## Prerequisites

- Feature path provided by the user (must exist and contain code)
- `.copilot/config/project.config.yaml` valid (or run `/bootstrap-workspace` first)
- Context resolved:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`
  - `PIPELINE_SPEC_PATH`
  - `PIPELINE_LOG_PATH`

---

## Gate — Topology (mandatory)

1. Validate `TOPOLOGY_REPO_MODE` (`single_repo | monorepo_melos | multi_repo`).
2. Validate `PROJECT_ROOT` and `TARGET_ROOT` are accessible.
3. Validate `feature_path` exists and contains Dart files.
4. If `target_location = melos_package`:
   - Validate `package_name` and `workspace_root` are provided
   - Validate workspace root `pubspec.yaml` has `workspace:` key
5. If `monorepo_melos`:
   - `melos_enabled = true`
   - `target_scope` is not empty

If any validation fails, terminate with `blocked_input`.

---

## Inputs

```text
@refactoring-advisor /refactor-feature
feature_path: lib/src/features/checkout/
intent: Split the CheckoutBloc into CartBloc and PaymentBloc, extract coupon validation to a use case
constraints: Don't change the API contract, keep route paths the same
user_story: docs/hus/HU-078.md  (optional — contains acceptance criteria + DoD)
target_location: same | melos_package
sequence_diagram: docs/diagrams/checkout_flow.mmd  (optional)
```

### Input variations

```text
# Simple refactor (most common)
@refactoring-advisor /refactor-feature
feature_path: lib/src/features/checkout/
intent: The BLoC is too large, needs splitting

# Package extraction
@refactoring-advisor /refactor-feature
feature_path: lib/src/features/payments/
intent: Extract to a standalone Melos package
target_location: melos_package
package_name: payments

# Pattern update
@refactoring-advisor /refactor-feature
feature_path: lib/src/features/auth/
intent: Replace dartz with fpdart, update Freezed to 3.x syntax

# Add endpoint to existing feature
@refactoring-advisor /refactor-feature
feature_path: lib/src/features/products/
intent: Add DELETE /products/:id endpoint to existing feature
api_contract: |
  DELETE /products/:id -> void (204)
```

---

## Execution Sequence

### PHASE 1 — Analysis

**Agent:** `@refactoring-advisor`

Steps:
1. Read all files in `feature_path` recursively
2. Map the current architecture:
   - Layers present (domain / data / presentation)
   - State management pattern
   - Error handling approach
   - DI mechanism
   - Freezed version/syntax
3. Detect code smells and violations:
   - Layer dependency violations
   - God classes (>300 lines or >5 responsibilities)
   - Missing abstractions (concrete where interface expected)
   - Outdated patterns (dartz, fold, Freezed 2.x, Provider)
   - DI issues (manual instantiation, missing annotations)
   - Error handling gaps (raw try/catch, hardcoded messages)
   - Dead code (unused imports, commented blocks)
4. Count existing tests and map coverage
5. Map internal dependency graph (who imports whom)

Output: Analysis section in `PIPELINE_SPEC_PATH`.

---

### PHASE 2 — Impact Assessment

**Agent:** `@refactoring-advisor`

Steps:
1. List all files that will be affected
2. Identify external dependents (other features importing from this one)
3. Assess breaking changes:
   - Public API changes (exported classes/functions)
   - DI registration changes (other modules depending on these registrations)
   - Route changes (navigation from other features)
4. Identify tests that will need updates vs tests that should still pass
5. Rate overall risk: `low` | `medium` | `high`

Output: Impact assessment section in `PIPELINE_SPEC_PATH`.

---

### PHASE 3 — Refactoring Plan

**Agent:** `@refactoring-advisor`

Steps:
1. Decompose the refactoring into atomic steps
2. Each step MUST leave the app in a compilable state
3. Order by:
   - Dependencies (prerequisites first)
   - Risk (lowest first)
   - Type (additive → structural → destructive)
4. For each step specify:
   - Action (extract, split, move, rename, replace, delete)
   - Files created / modified / deleted
   - Risk level (low / medium / high)
   - Reversibility (✅ / ⚠️)
   - Verification command

Output: Refactoring plan section in `PIPELINE_SPEC_PATH`.

---

### PHASE 4 — Checkpoint (mandatory)

**Agent:** `@refactoring-advisor`

Present to the user:
1. Analysis summary (current state + issues found)
2. Impact assessment (files affected, breaking changes, risk)
3. Refactoring plan (ordered steps with risk ratings)

Question:
"I've analyzed the feature and prepared a refactoring plan with {N} atomic steps (risk: {level}). Want me to proceed with execution?"

**Do NOT proceed without explicit approval.**

If the user requests changes to the plan, adjust and re-present.

---

### PHASE 5 — Execution (iterative)

**Agent:** `@refactoring-advisor`

For each step in the approved plan:

1. **Execute** the change
2. **Verify compilation**:
   - `single_repo`: `flutter analyze --fatal-infos`
   - `monorepo_melos`: `melos exec --scope={target_scope} -- "flutter analyze --fatal-infos"`
3. **Verify DI** (if annotations changed):
   - `dart run build_runner build --delete-conflicting-outputs`
4. **Run existing tests**:
   - `flutter test {feature_path}` (or scoped with Melos)
5. **Assess test results**:
   - All pass → continue to next step
   - Expected failures (structural change) → queue for Phase 6
   - Unexpected failures (regression) → revert step, reassess plan
6. **Log** step completion

If a step fails compilation:
- Fix immediately (do not move to next step)
- If fix requires plan adjustment, re-present to user

Output: Execution log per step in `PIPELINE_LOG_PATH`.

> **IMPORTANT: After completing ALL refactoring steps, you are NOT done.**
> You MUST continue to Phase 6 (tests), Phase 7 (audit), and Phase 8 (documentation).
> The refactoring is incomplete without tests and the documentation file.

---

### PHASE 6 — Test Analysis & Coverage (mandatory)

**Agent:** `@refactoring-advisor`

> **This phase is NOT optional.** Every refactoring MUST include test analysis
> and generation. A refactoring without verified test coverage is incomplete.

Steps:
1. Locate the test directory for the feature (create if missing)
2. Inventory existing tests (unit, widget, integration)
3. If tests exist: update broken ones (imports, mocks, assertions)
4. **Generate missing tests** for EVERY file that lacks coverage:
   - Domain use cases: success path, failure path, edge cases
   - Data repositories: cache-first logic, error mapping
   - Data mappers: fromModel/toModel with JSON fixtures
   - Data sources: HTTP calls with mocked Dio
   - BLoC: every event → state transition
   - Pages/Widgets: rendering, interactions, state-driven UI
5. Coverage targets (non-negotiable):
   - Domain: 95%+
   - Data: 85%+
   - Presentation BLoC: 85%+
   - Presentation pages: 70%+
6. Test generation rules:
   - `mocktail 1.0.5` for mocking
   - `bloc_test 9.1.7` for BLoC tests
   - AAA pattern (Arrange-Act-Assert)
   - Descriptive names: `should [verb] when [condition]`
   - One test file per source file
   - ALL success AND failure paths covered
7. Run all tests and verify they pass

Output: Test files created + coverage summary in `PIPELINE_SPEC_PATH`.

---

### PHASE 7 — Audit

**Agent:** `@code-auditor`

Steps:
1. Review all modified/created files against:
   - Clean Architecture dependency rules
   - SOLID principles
   - Dart coding standard
   - Naming conventions
   - DI correctness
2. Verify no regressions introduced:
   - No new layer violations
   - No dead code left behind
   - Barrel exports updated (if package extraction)
   - No unused DI registrations
3. If issues found:
   - Return to `@refactoring-advisor` for corrections
   - Max retries: `pipeline.max_audit_retries` (default: 3)
4. If approved: mark complete

Output: `§5` audit report in `PIPELINE_SPEC_PATH`.

---

### PHASE 8 — Report & Documentation

**Agent:** `@refactoring-advisor`

Generate two outputs:

#### 8a. Pipeline report

```markdown
## Refactoring Report: {feature_name}

### Summary
- **Scope**: refactor
- **Intent**: {user's original intent}
- **Steps executed**: {N}/{total}
- **Files created**: {count}
- **Files modified**: {count}
- **Files deleted**: {count}
- **Tests updated**: {count}
- **Compilation**: ✅
- **Tests**: ✅ all pass
- **Audit**: ✅ approved

### Changes by Step
| # | Action | Files | Status |
|---|---|---|---|
| 1 | Extract ValidateCouponUseCase | +1, ~1 | ✅ |
| 2 | Split CheckoutBloc → CartBloc + PaymentBloc | +2, ~3, -1 | ✅ |
| 3 | Replace fold() with match() | ~6 | ✅ |

### Next Steps
- [ ] Run full test suite: `flutter test`
- [ ] Consider adding tests: `@test-coverage-engineer /test-plan`
- [ ] Update feature documentation if public API changed
- [ ] Verify navigation from other features still works
```

Output: Report in `PIPELINE_SPEC_PATH`.

#### 8b. Refactoring documentation file (mandatory — FILE CREATION action)

> **CRITICAL: This is a FILE CREATION action, not just a report to the user.**
> The agent MUST use the file creation tool to write this file to disk.
> The refactoring is NOT complete until this file exists on disk.

**Action:** Create a NEW file at this EXACT path:
`{PROJECT_ROOT}/docs/refactoring/{feature_name}-refactoring-{YYYY-MM-DD}.md`

**Steps:**
1. If `docs/refactoring/` directory does not exist → CREATE IT
2. Create the file with: Intent, Before (structure + issues), After (structure + improvements), Rationale, Files Changed table, Test Coverage table
3. VERIFY the file exists on disk after creation

**Example path:** `docs/refactoring/checkout-refactoring-2026-05-08.md`

Output: Documentation file created at `docs/refactoring/`.

---

### PHASE 9 — Project Documentation Update (mandatory)

**Agent:** `@refactoring-advisor` (via `flutter-generate-documentation` skill)

**Condition:** Always executes — NEVER skip.

Steps:
1. Resolve documentation directory:
   - If `docs/` exists at `PROJECT_ROOT` → use it
   - If `documentation/` or similar exists → use the existing one
   - Otherwise → create `docs/` at `PROJECT_ROOT`
2. Check which of the 7 project documents exist:
   - `index.md`, `project-overview.md`, `requirements.md`, `project-structure.md`,
     `tech-stack.md`, `features.md`, `implementation.md`, `user-flow.md`
3. For **missing documents** → generate from templates (`flutter-generate-documentation` skill)
4. For **existing documents** → update with the refactoring changes:
   - `project-structure.md` → update if folder structure changed (extracted classes, new packages)
   - `features.md` → update feature entry if public API or behavior changed
   - `implementation.md` → update if new patterns, DI modules, or architectural decisions were introduced
   - `tech-stack.md` → update if dependencies were added or removed
   - `user-flow.md` → update if user journeys were affected
5. Commit documentation changes: `docs({feature}): update project documentation after refactoring`

Output: List of created/updated documents in `PIPELINE_LOG_PATH`.

**Skill invocation:** `@generate-docs action=update target={docs_path} documents=all`

---

## Mandatory Post-Execution Checklist

> **The agent MUST complete ALL items below before reporting to the user.
> If any item is missing, the refactoring is INCOMPLETE.**

| # | Action | Verification |
|---|---|---|
| A | Generate test files for all untested source files | `flutter test` passes, coverage targets met |
| B | Delegate audit to `@code-auditor` | Audit approved |
| C | Create `docs/refactoring/{feature_name}-refactoring-{date}.md` | File exists on disk (read it back) |
| D | Report final summary to user | Only after A, B, C are done |

---

## Verification (topology-aware)

After all phases:

- `single_repo`:
  ```bash
  flutter analyze --fatal-infos
  dart run build_runner build --delete-conflicting-outputs
  flutter test
  ```
- `monorepo_melos`:
  ```bash
  melos exec --scope={target_scope} -- "flutter analyze --fatal-infos"
  melos exec --scope={target_scope} -- "dart run build_runner build --delete-conflicting-outputs"
  melos exec --scope={target_scope} -- "flutter test"
  ```

---

## Rules

### Completion criteria (ALL must be true)
- [ ] All refactoring steps executed and compiling
- [ ] All tests pass (existing updated + new generated)
- [ ] Coverage targets met (domain 95%, data 85%, BLoC 85%, pages 70%)
- [ ] `@code-auditor` approved
- [ ] Documentation file EXISTS at `docs/refactoring/{feature_name}-refactoring-{date}.md`
- [ ] Project documentation (7 documents) updated via `flutter-generate-documentation` skill

### Prohibitions
- NEVER skip the analysis phase — always understand before changing
- NEVER make a change that leaves the app in a non-compilable state
- NEVER proceed past Phase 4 without explicit user approval
- NEVER delete tests without updating them to match new structure
- NEVER change behavior during refactoring (unless explicitly requested as part of intent)
- NEVER refactor DS components — delegate to `@ds-orchestrator /refactor-component`
- NEVER end without creating the documentation file in `docs/refactoring/`
- NEVER end without generating missing tests in Phase 6
- NEVER skip Phase 9 (Project Documentation Update) — it is mandatory after every refactoring

### Obligations
- ALWAYS verify compilation after each atomic step
- ALWAYS run build_runner if DI annotations or Freezed classes changed
- ALWAYS preserve existing test coverage (update broken tests, never delete)
- ALWAYS generate missing tests to meet coverage targets
- ALWAYS use mocktail for mocking and bloc_test for BLoC tests
- ALWAYS delegate to `@code-auditor` for final quality review
- ALWAYS register each phase in `PIPELINE_LOG_PATH`
- ALWAYS create `docs/refactoring/` directory if it doesn't exist
- ALWAYS create the documentation .md file as the LAST action before reporting completion
- ALWAYS verify the documentation file exists on disk after creating it
- ALWAYS update project documentation (7 documents) in Phase 9 using `flutter-generate-documentation` skill
- If a step causes unexpected test failures, REVERT and reassess before continuing
