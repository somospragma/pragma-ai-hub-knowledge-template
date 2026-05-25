---
name: new-feature
description: >
  Workflow for building a complete feature following Clean Architecture
  (domain → data → presentation) with optional DS component creation.
  Use when the user asks to create a new feature, implement a screen with
  backend logic, or scaffold a full module. Not for DS-only components
  (use /new-component) or view-only screens without logic (use /new-view).
trigger: "@feature-builder /new-feature"
metadata:
  author: Pragma Mobile Chapter
  version: "1.0"
---

# Workflow: New Feature (Full Clean Architecture)

## When to Use

Use this workflow when:

- The user asks to "create a feature", "implement the product catalog", "build the checkout flow"
- The feature requires domain logic (entities, use cases, repositories)
- The feature connects to a REST API or local database
- The feature needs a BLoC with state management
- The feature may need new DS components (detected in Phase 0)

Do NOT use for:
- DS component only (use `/new-component`)
- View/screen without backend logic (use `/new-view`)
- Refactoring existing code (use `/refactor-component`)

---

## Prerequisites

- Feature name and description provided by the user
- API contract **or** manual entity_name + fields provided:
  - If `api_contract` is given → `entity_name` is inferred from the schema (the primary schema referenced by the endpoints, or the user can hint which schema to use)
  - If no contract → `entity_name` and `fields` are required manually
- `.copilot/config/project.config.yaml` valid (or run `/bootstrap-workspace` first)
- Context resolved:
  - `PROJECT_ROOT`
  - `TARGET_ROOT`
  - `TOPOLOGY_REPO_MODE`
  - `PIPELINE_SPEC_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.spec_file}`
  - `PIPELINE_LOG_PATH = {TARGET_ROOT}/{pipeline.output_dir}/{pipeline.log_file}`

---

## Gate — Topology (mandatory)

1. Validate `TOPOLOGY_REPO_MODE` (`single_repo | monorepo_melos | multi_repo`).
2. Validate `PROJECT_ROOT` and `TARGET_ROOT` are accessible.
3. If `monorepo_melos`:
   - `melos_enabled = true`
   - `melos.yaml` exists at workspace root
   - `target_scope` is not empty
   - `target_package_path` exists
4. If `target_location = melos_package`:
   - Validate `package_name` and `workspace_root` are provided

If any validation fails, terminate with `blocked_input`.

---

## Inputs

```text
@feature-builder /new-feature
feature_name: product_catalog
description: Browse and search products by category with detail view
api_contract: <see below — accepts any format>
user_story: docs/hus/HU-045.md  (optional — contains acceptance criteria + DoD)
figma_url: https://www.figma.com/file/xxx/ProductList?node-id=123  (optional)
target_location: app_folder | melos_package
sequence_diagram: docs/diagrams/product_catalog_flow.mmd  (optional)
```

### `api_contract` — Single field, any format

The `api_contract` field accepts whatever the developer has available.
The agent auto-detects the format and extracts entities, endpoints, and schemas.

| What you have | What to put in `api_contract` |
|---|---|
| OpenAPI/Swagger file | `docs/api/openapi.yaml` or `https://api.example.com/docs/openapi.json` |
| GraphQL schema | `docs/api/schema.graphql` |
| Postman collection | `docs/api/collection.json` |
| Protobuf | `protos/product_service.proto` |
| JSON example response | `docs/api/product_response.json` |
| Markdown spec | `docs/api/product-api.md` |
| Inline cURL + response | Paste directly (see example below) |
| Manual endpoints + fields | Write them directly (see example below) |

**Examples:**

```text
# File path
api_contract: docs/api/openapi.yaml

# URL
api_contract: https://api.example.com/docs/openapi.json

# Inline JSON response (fastest)
api_contract: |
  GET /products
  Response:
  {
    "data": [{"product_id": "1", "name": "Widget", "price": 9.99, "category_id": "c1"}],
    "meta": {"page": 1, "total": 100, "has_more": true}
  }

  GET /products/:id
  Response:
  {"product_id": "1", "name": "Widget", "price": 9.99, "category_id": "c1", "image_url": "https://..."}

# Inline cURL
api_contract: |
  curl -X GET https://api.example.com/v1/products -H "Authorization: Bearer {token}"
  Response: {"data": [{"product_id": "1", "name": "Widget", "price": 9.99}], "meta": {"has_more": true}}

  curl -X GET https://api.example.com/v1/products/{id}
  Response: {"product_id": "1", "name": "Widget", "price": 9.99, "category_id": "c1"}

# Manual (simplest fallback — no file needed)
api_contract: |
  GET /products -> List<Product>
  GET /products/:id -> Product
  POST /products (body: CreateProductRequest) -> Product

  Product:
    id: String
    name: String
    price: double
    categoryId: String
    isAvailable: bool
    imageUrl: String?

  CreateProductRequest:
    name: String
    price: double
    categoryId: String
```

---

## Execution Sequence

### PHASE 0 — UI Component Inventory (conditional)

**Condition:** `figma_url` or `ui_components` is provided.
**Agent:** `@feature-builder` (internal) + delegation to `@ds-orchestrator`

Steps:
1. Identify required DS components from Figma or description
2. Search the repository for each component
3. Classify: ✅ exists | ⚠️ partial | 🆕 missing
4. For each 🆕 or ⚠️ component:
   - Delegate to `@ds-orchestrator /new-component` or `/refactor-component`
   - Wait for DS pipeline completion
5. If DS pipeline returns `blocked_input`, present options to user

Output: Phase 0 inventory table in `PIPELINE_SPEC_PATH`.

**Skip condition:** No `figma_url` and no `ui_components` provided.

---

### PHASE 1 — Scaffold

**Agent:** `@feature-builder`

Steps:
1. Determine target location (app folder vs Melos package)
2. If Melos package:
   - Create `pubspec.yaml` with `resolution: workspace`
   - Create barrel export `lib/{package_name}.dart`
   - Update root `pubspec.yaml` workspace list
   - Run `dart pub get`
3. Create all directories per the architecture map

Output: Directory structure created, registered in `PIPELINE_LOG_PATH`.

---

### PHASE 1.5 — API Contract Analysis (conditional)

**Condition:** `api_contract` is provided (file, URL, or inline cURL in the prompt).
**Agent:** `@feature-builder`

Steps:
1. Detect format (OpenAPI, GraphQL, Postman, Protobuf, JSON example, Markdown, cURL)
2. Read and parse the contract
3. Locate schemas and paths relevant to `entity_name`
4. Extract:
   - Endpoints with methods, path params, query params
   - Request/response schemas (field names, types, required/optional, nullability)
   - Pagination pattern (offset/limit, cursor, page/pageSize)
   - Error response structure (status codes, error body)
   - Enum definitions → Dart enums
   - Nested object schemas → separate DTOs
5. Produce an internal **API Analysis** that feeds Phase 2 and Phase 3:
   - Domain model fields (from response schema, cleaned of API naming)
   - DTO fields (exact API field names with `@JsonKey` mappings)
   - Data source method signatures (one per endpoint)
   - Use case list (inferred from endpoints: GET list → GetAll, GET by id → GetById, POST → Create, etc.)

Output: API analysis section in `PIPELINE_SPEC_PATH`.

**Skip condition:** No `api_contract` provided and no inline cURL — use `fields` and `api_endpoints` directly.

---

### PHASE 2 — Domain Layer

**Agent:** `@feature-builder`

Generate:
1. Domain model (`@freezed abstract class`, no JSON, with business logic getters)
2. Repository interface (`abstract interface class`, `Either<Failure, T>` returns)
3. Use case(s) (`@injectable`, implements `UseCase<T, Params>`)

Output: Domain files in `PIPELINE_SPEC_PATH` file list.

---

### PHASE 3 — Data Layer

**Agent:** `@feature-builder`

Generate:
1. DTO (`@freezed abstract class` + `fromJson`, `@JsonKey` for API field names)
2. Mapper (`abstract final class` with `fromModel` / `toModel`)
3. Remote data source (interface + `@LazySingleton` implementation)
4. Local data source (interface only — implementation noted as optional)
5. Repository implementation (`@LazySingleton(as:)`, cache-first, error mapping)

Output: Data files in `PIPELINE_SPEC_PATH` file list.

---

### PHASE 4 — Presentation Layer

**Agent:** `@feature-builder`

Generate:
1. Event (`@freezed sealed class`, one factory per user action)
2. State (`@freezed sealed class`: initial, loading, success, error)
3. BLoC (`@injectable`, explicit `transformer:` on every `on<>`, `result.match()`)
4. UIModel (`@freezed abstract class` + `fromDomain` factory)
5. Page (`BlocProvider` + `getIt<Bloc>()` + `BlocBuilder` with exhaustive switch)

Output: Presentation files in `PIPELINE_SPEC_PATH` file list.

---

### PHASE 5 — Wiring

**Agent:** `@feature-builder`

Steps:
1. Run `dart run build_runner build --delete-conflicting-outputs`
   - Monorepo: `melos exec --scope={package} -- "dart run build_runner build --delete-conflicting-outputs"`
2. Verify DI registration: `grep "{Entity}Repository\|{Feature}Bloc" injection.config.dart`
3. Register route in GoRouter (if router file is accessible)
   - If not accessible, note as manual step
4. If Melos package: register `ExternalModule` in app's injection container

Output: Wiring verification in `PIPELINE_SPEC_PATH`.

---

### PHASE 6 — Audit

**Agent:** `@code-auditor`

Steps:
1. Review all generated files against:
   - SOLID principles
   - Clean Architecture dependency rules
   - Dart coding standard
   - Naming conventions
   - DI correctness (no DataSource in BLoC, no domain importing Flutter)
2. If issues found:
   - Report in `§5`
   - Return to `@feature-builder` for corrections
   - Max retries: `pipeline.max_audit_retries` (default: 3)
3. If approved: mark complete

Output: `§5` audit report in `PIPELINE_SPEC_PATH`.

---

### CHECKPOINT HUMANO (optional)

**Condition:** `pipeline.human_checkpoint: true`

Present to the developer:
1. Feature build report (all files created)
2. DI registration status
3. Route registration status
4. Any manual steps needed

Wait for explicit approval.

---

### PHASE 7 — Delivery

**Agent:** `@delivery-manager`

Steps:
1. Validate all files are within `TARGET_ROOT` scope
2. Validate topology constraints (monorepo: no changes outside `target_scope`)
3. Generate branch name using `naming.branch_prefix` + feature name
4. Commits with Conventional Commits (`feat({feature}): implement {feature} feature`)
5. PR description with:
   - Feature description
   - Files created (by layer)
   - DI registration status
   - Route registration status
   - Next steps (tests, Widgetbook)

Output: `§7` delivery report in `PIPELINE_SPEC_PATH`.

---

### PHASE 8 — Documentation (mandatory)

**Agent:** `@feature-builder` (via `flutter-generate-documentation` skill)

**Condition:** Always executes — NEVER skip.

Steps:
1. Resolve documentation directory:
   - If `docs/` exists at `PROJECT_ROOT` → use it
   - If `documentation/` or similar exists → use the existing one
   - Otherwise → create `docs/` at `PROJECT_ROOT`
2. Check which of the 7 documents exist:
   - `index.md`, `project-overview.md`, `requirements.md`, `project-structure.md`,
     `tech-stack.md`, `features.md`, `implementation.md`, `user-flow.md`
3. For **missing documents** → generate from templates (`flutter-generate-documentation` skill)
4. For **existing documents** → update with the new feature information:
   - `features.md` → add feature entry (name, description, status, layer files)
   - `project-structure.md` → update folder tree if new directories were created
   - `implementation.md` → update if new patterns, DI modules, or routes were added
   - `tech-stack.md` → update if new dependencies were introduced
   - `user-flow.md` → add user flow if the feature introduces a new user journey
   - `requirements.md` → add functional requirements if `acceptance_criteria` or `functional_requirements` were provided as input
   - `project-overview.md` → update current state table if feature changes project scope
5. Commit documentation changes: `docs({feature}): update project documentation`

Output: List of created/updated documents in `PIPELINE_LOG_PATH`.

**Skill invocation:** `@generate-docs action=update target={docs_path} documents=all`

---

## Verification (topology-aware)

After all phases:

- `single_repo` or `multi_repo`:
  ```bash
  flutter analyze --fatal-infos
  dart run build_runner build --delete-conflicting-outputs
  ```
- `monorepo_melos`:
  ```bash
  melos exec --scope={target_scope} -- "flutter analyze --fatal-infos"
  melos exec --scope={target_scope} -- "dart run build_runner build --delete-conflicting-outputs"
  ```

---

## Output Report

```markdown
## Feature Build Report: {feature_name}

### Summary
- **Entity**: {EntityName}
- **Location**: {path}
- **Target**: {app_folder | melos_package}
- **Files created**: {count}
- **DI registered**: ✅ | ❌
- **Route registered**: ✅ | ❌ | ⚠️ manual
- **build_runner**: ✅ | ❌
- **Audit**: ✅ approved | ❌ rejected (attempt {N})
- **Documentation**: ✅ updated | 🆕 created

### Phase 0 — DS Components (if applicable)
| Component | Status | Action |
|---|---|---|

### Files Created
| # | Layer | File | Status |
|---|---|---|---|

### Next Steps
- [ ] Write tests (use `flutter-testing` / `flutter-test-coverage-strategy`)
- [ ] Register route in GoRouter (if manual step)
- [ ] Run `flutter test`
```

---

## Rules

- NEVER skip domain or data layers — always generate the full stack
- NEVER proceed to Phase 1 if Phase 0 has unresolved `blocked_input`
- NEVER generate files outside `TARGET_ROOT`
- NEVER generate tests (that is a separate workflow/agent responsibility)
- NEVER skip Phase 8 (Documentation) — it is mandatory after every feature build
- ALWAYS run topology gate before any file generation
- ALWAYS run `build_runner` in Phase 5 before audit
- ALWAYS delegate DS component creation to `@ds-orchestrator` (never build DS components directly)
- ALWAYS register each phase in `PIPELINE_LOG_PATH`
- ALWAYS generate/update project documentation in Phase 8 using `flutter-generate-documentation` skill
- If a phase fails or returns `blocked_input`, stop and report to user
