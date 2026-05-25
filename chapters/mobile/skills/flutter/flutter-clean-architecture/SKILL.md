---
name: flutter-clean-architecture
description: >
  Explains, enforces, and audits Clean Architecture in Flutter projects —
  both for building new projects from scratch and for refactoring existing ones.
  Use this skill when asking about project structure, layer separation,
  'where does X go?', 'is this the right layer?', folder organization,
  dependency direction, or architectural violations. Also activated when
  reviewing code with violations, setting up a new project, migrating a legacy
  codebase, or onboarding.
  Canonical reference for layer boundaries, dependency rules, folder structure,
  cross-feature communication (Mediator), and incremental refactoring strategy.
  Supports single-project and monorepo with Melos.
  Stack- Flutter >=3.32.0, Dart >=3.8.0, BLoC 9.1.1, GetIt 9.2.1,
  Injectable 3.0.0, go_router 17.2.2, Freezed 3.2.5, fpdart 1.2.0.
commands:
  - audit-architecture
inputs:
  - name: action
    description: Action to perform (audit, setup, refactor-plan). "audit" checks for layer violations (domain importing Flutter, presentation importing data, JSON in domain models), "setup" scaffolds the full clean architecture folder structure for a new project, "refactor-plan" generates an incremental migration plan for an existing codebase.
    required: true
  - name: target
    description: Path to the project root or specific feature to audit (e.g. . for full project, lib/features/product/ for specific feature).
    required: true
  - name: strategy
    description: Project strategy (single-project, monorepo). Determines folder structure and configuration. Defaults to single-project.
    required: false
metadata:
  author: Pragma Mobile Chapter
  version: "2.1"
---

# Clean Architecture in Flutter

Canonical reference for layers, boundaries, and dependency rules.
Based on Uncle Bob's Clean Architecture, adapted for Flutter.

## Two Modes of Use

This skill applies to both scenarios — the approach differs, but the target architecture is the same.

| Mode | Starting point | Strategy |
|---|---|---|
| **Greenfield** | New project, blank slate | Apply the full structure from day one. Use the folder templates and contracts in the reference files directly. |
| **Refactoring** | Existing codebase with violations | Apply incrementally — one feature at a time. Run the violation checklist to prioritize. Never rewrite everything at once. |

### Incremental Refactoring Order

When migrating an existing project, follow this order to minimize risk:

```
1. Introduce Failure type (core/error/failure.dart)
2. Introduce UseCase base interfaces (core/usecase/usecase.dart)
3. Extract domain models — remove fromJson from existing models
4. Create repository interfaces in domain/
5. Move HTTP calls behind DataSource implementations
6. Create RepositoryImpl — map exceptions to Failure
7. Replace direct DataSource calls in BLoC with UseCase calls
8. Extract UIModels — move formatting/color logic out of domain
9. Introduce AppMediator — replace direct feature imports
10. Migrate to Melos monorepo (if needed)
```

Each step can be done per feature without breaking the rest of the app.
The violation checklist in `references/violations_guide.md` helps identify
which steps are most urgent for each feature.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER  (Flutter)                                  │
│  Page · BLoC · UIModel · Organism · Template                    │
├─────────────────────────────────────────────────────────────────┤
│  DOMAIN LAYER  (pure Dart — no Flutter, no JSON)                │
│  UseCase · Repository (interface) · DomainModel · Failure       │
├─────────────────────────────────────────────────────────────────┤
│  DATA LAYER                                                     │
│  RepositoryImpl · RemoteDataSource · LocalDataSource            │
│  DataModel · Mapper · ApiClient · CacheStore                    │
└─────────────────────────────────────────────────────────────────┘
         ↑ everything wired by the COMPOSITION ROOT (GetIt + Injectable)
```

---

## The Golden Rule — Dependency Direction

**Dependencies point ONLY inward:**

```
Presentation → Domain ← Data
```

| From | Can import | CANNOT import |
|---|---|---|
| Domain | Nothing (pure Dart only) | Presentation, Data, Flutter, JSON |
| Data | Domain (interfaces, domain models, failures) | Presentation |
| Presentation | Domain (domain models, use cases, failures) | Data directly |
| GetIt modules | Everything | (it is the composition root) |

---

## Folder Structure

Two supported strategies — see `references/folder_structure.md` for the complete trees,
Melos configuration, and naming table.

| Strategy | When to use |
|---|---|
| **Single Project** | 1 app, small team (1–5 devs), minimal shared logic |
| **Monorepo with Melos** | 2+ apps, shared design system, medium–large team |

### Feature structure (both strategies)

```
{feature}/
├── data/
│   ├── data_sources/
│   │   ├── local/   → {feature}_data_source.dart
│   │   └── remote/  → {feature}_data_source.dart
│   ├── data_models/ → {name}_model.dart        # @freezed + fromJson
│   └── repositories/→ {feature}_repository_impl.dart
├── domain/
│   ├── domain_models/ → {name}.dart            # @freezed, NO JSON
│   ├── usecases/      → {name}_usecase.dart    # @injectable
│   └── repositories/  → {feature}_repository.dart  # abstract interface class
└── presentation/
    ├── ui_models/ → {name}_uimodel.dart
    ├── bloc/      → {feature}_bloc/event/state.dart  # @injectable + @freezed
    ├── pages/     → {feature}_page.dart
    ├── organism/  → {name}_organism.dart
    └── templates/ → {name}_template_mobile/web.dart
```

---

## Cross-Feature Communication — Mediator Pattern

Features must **never import each other directly**. Direct imports between features
create horizontal coupling that breaks the module boundary and makes features
impossible to reuse or test in isolation.

```
❌ feature_a/presentation/bloc/order_bloc.dart
   imports feature_b/domain/usecases/get_user_usecase.dart
   → OrderBloc now depends on the User feature internals

✅ Both features communicate through a shared Mediator
   → OrderBloc sends a message; UserBloc reacts
   → Neither knows the other exists
```

The **Mediator** acts as a central message bus. Features publish events and
subscribe to events — they never reference each other.

```dart
// core/mediator/app_mediator.dart
abstract interface class AppMediator {
  void send(MediatorEvent event);
  Stream<T> on<T extends MediatorEvent>();
}

// A feature publishes:
_mediator.send(const UserLoggedInEvent(userId: '123'));

// Another feature reacts:
_mediator.on<UserLoggedInEvent>().listen((event) {
  add(CartEvent.loadForUser(event.userId));
});
```

See `references/mediator_pattern.md` for the full implementation, event catalog,
and integration with BLoC and GetIt.

### Presentation Layer

| Component | Responsibility | Must NOT |
|---|---|---|
| Page | BlocProvider + route entry point | Contain business logic |
| BLoC | Handle events, call UseCases, emit states | Call DataSources directly |
| UIModel | Values ready to display in the UI | Contain business logic |
| Organism | Reusable composed widgets for the feature | Import Data layer |
| Template | Mobile/web layout for the Page | Contain business logic |

### Domain Layer

| Component | Responsibility | Must NOT |
|---|---|---|
| UseCase | One business operation | Import Flutter, Data layer, JSON |
| DomainModel | Business concept + domain logic | Have fromJson/toJson |
| Repository (interface) | Data access contract | Have implementation details |
| Failure | Sealed error type | Have HTTP-specific fields |

### Data Layer

| Component | Responsibility | Must NOT |
|---|---|---|
| RepositoryImpl | Orchestrate sources, map errors to Failure | Contain business rules |
| RemoteDataSource | HTTP calls, returns DataModels | Return domain models |
| LocalDataSource | Cache read/write, returns DataModels | Return domain models |
| DataModel | Reflects API JSON structure (`@freezed` + `fromJson`) | Be used in Domain/Presentation |
| Mapper | DataModel ↔ DomainModel conversion | Contain business logic |

---

## Stack Versions (April 2026)

```yaml
dependencies:
  flutter_bloc: ^9.1.1
  get_it: ^9.2.1
  injectable: ^3.0.0
  go_router: ^17.2.2
  freezed_annotation: ^3.1.0
  fpdart: ^1.2.0
  dio: ^5.9.2

dev_dependencies:
  build_runner: ^2.14.1
  freezed: ^3.2.5
  injectable_generator: ^3.0.2
  mocktail: ^1.0.5
```

**Key decisions:**
- `fpdart` instead of `dartz` — actively maintained, better Dart 3 support
- `abstract interface class` for all repository and data source contracts
- `@freezed` for domain models, data models, BLoC events and states
- `@injectable` / `@lazySingleton` / `@singleton` for DI registration

---

## Common Questions — "Where Does X Go?"

| What | Where | Why |
|---|---|---|
| `fromJson` / `toJson` | `data/data_models/` only | Domain must not know about JSON |
| `Color`, `TextStyle`, `Widget` | `presentation/` only | Domain must not import Flutter |
| Error mapping (DioException → Failure) | `data/repositories/` | RepositoryImpl is the boundary |
| String formatting for display | `presentation/ui_models/` (UIMapper) | Presentation concern |
| Business validation (e.g. min age) | `domain/domain_models/` or `domain/usecases/` | Business rule |
| HTTP base URL | `core/di/modules/network_module.dart` | Infrastructure config |
| Navigation after action | `presentation/bloc/` via callback or `presentation/pages/` via BlocListener | Presentation concern |
| Shared `Failure` type | `core/error/failure.dart` | Used by all layers |
| Feature-specific `Failure` | `{feature}/domain/` | Scoped to the feature |
| `SharedPreferences` / `Hive` | `data/data_sources/local/` | Infrastructure detail |
| Analytics event | `presentation/bloc/` (after state change) | Triggered by user action |

---

## Violation Detection Checklist

Run on every PR review. Paths vary by strategy used.

```bash
# Detect base path (single project vs monorepo)
FEATURES_PATH="lib/src/features/*/"; [[ ! -d "lib/src/features" ]] && FEATURES_PATH="lib/features/*/"

# ❌ Domain importing Flutter
grep -r "import 'package:flutter" ${FEATURES_PATH}domain/ && echo "VIOLATION: Domain imports Flutter"

# ❌ Domain importing Data layer
grep -r "import.*data.*model\|import.*data.*mapper\|import.*repository_impl" ${FEATURES_PATH}domain/ && echo "VIOLATION: Domain imports Data"

# ❌ Presentation importing Data directly
grep -r "import.*data_source\|import.*data_models\|import.*_model\.dart" ${FEATURES_PATH}presentation/ && echo "VIOLATION: Presentation imports Data"

# ❌ Domain model with fromJson
grep -rn "fromJson\|toJson" ${FEATURES_PATH}domain/domain_models/ && echo "VIOLATION: DomainModel has JSON"

# ❌ BLoC with DataSource injected
grep -rn "DataSource" ${FEATURES_PATH}presentation/bloc/ && echo "VIOLATION: BLoC has DataSource"

# ❌ Repository interface returning DataModel
grep -rn "Model>" ${FEATURES_PATH}domain/repositories/ && echo "VIOLATION: Repository returns DataModel"

# ❌ UseCase importing Data layer
grep -rn "import.*data_source\|import.*_model\.dart\|import.*repository_impl" ${FEATURES_PATH}domain/usecases/ && echo "VIOLATION: UseCase imports Data"
```

---

## Request/Response Sequence (happy path)

```
User taps button
  → Page adds Event to BLoC
    → BLoC emits Loading state
    → BLoC calls UseCase(params)
      → UseCase calls Repository.method(params)
        → RepositoryImpl queries LocalDataSource
        → [cache miss] RepositoryImpl calls RemoteDataSource
          → RemoteDataSource calls ApiClient.get(endpoint)
            ← ApiClient returns Response
          ← RemoteDataSource returns DataModel
        → RepositoryImpl maps DataModel → DomainModel
        → RepositoryImpl saves DataModel to cache via LocalDataSource
        ← RepositoryImpl returns Right(DomainModel)
      ← UseCase returns Right(DomainModel)
    → BLoC maps DomainModel → UIModel
    → BLoC emits Success(UIModel)
  ← Page rebuilds with UIModel data
```

---

## Reference Files

- `references/folder_structure.md` — complete folder trees (single project + monorepo), Melos config, naming table, strategy selection guide
- `references/mediator_pattern.md` — Mediator implementation, event catalog, BLoC integration, cross-feature communication rules
- `references/violations_guide.md` — complete before/after violation examples with fixes
- `references/layer_contracts.md` — interface contracts, generic base classes, and shared abstractions
