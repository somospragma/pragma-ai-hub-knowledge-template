# pragma-ia-foundations — Features

## Catálogo de Skills Transversales

Estos skills aplican a todos los dominios y están disponibles en `skills/transversal/`.

### Changelog Management 📝

**Ubicación:** `skills/transversal/changelog-management/`

**Descripción:** Mantener un changelog profesional siguiendo Keep a Changelog + Semantic Versioning.

**Funcionalidades:**
- ✅ Estructura estandarizada de changelog
- ✅ Categorización de cambios (Added, Changed, Deprecated, Removed, Fixed, Security)
- ✅ Validación de versiones semánticas
- ✅ Templates reutilizables

**Para quién:** Desarrolladores, Release managers

**Keywords:** `changelog`, `versioning`, `release-notes`, `semantic-versioning`

---

### Commit Conventions 💬

**Ubicación:** `skills/transversal/commit-conventions/`

**Descripción:** Estandarizar commits siguiendo Conventional Commits (feat, fix, docs, etc.).

**Funcionalidades:**
- ✅ Tipos de commit (feat, fix, docs, refactor, chore, etc.)
- ✅ Scopes por proyecto relación
- ✅ Message body y footers
- ✅ Validación automática pre-commit

**Para quién:** Todos los desarrolladores

**Keywords:** `commits`, `conventional-commits`, `git`, `messages`

---

### Documentation Projects 📚

**Ubicación:** `skills/transversal/documentation-projects/`

**Descripción:** Crear documentación completa usando framework de 7 documentos (overview, requirements, structure, tech-stack, features, implementation, user-flow).

**Funcionalidades:**
- ✅ Framework agnóstico de 7 documentos
- ✅ Templates por dominio (backend, frontend, mobile, QA, infra)
- ✅ Scripts de análisis (completitud, validación, security)
- ✅ Cuestionarios guiados

**Para quién:** Arquitectos, Technical writers, Team leads

**Keywords:** `documentation`, `specs`, `technical-writing`, `requirements`

---

### IDE Setup (Agent-First) 🤖

**Ubicación:** `skills/transversal/ide-setup-agent-first/`

**Descripción:** Configurar repositorios para trabajo optimizado con agentes de IA (Copilot, Kiro, Cursor).

**Funcionalidades:**
- ✅ Fase 0: Descubrimiento de repo
- ✅ Fase 1: Crear/actualizar AGENTS.md
- ✅ Fase 2: Steering files (.github/copilot-instructions.md, etc.)
- ✅ Fase 3: Spec-driven development
- ✅ Fase 4: Optimización de contexto
- ✅ Fase 5: Gobernanza y seguridad

**Para quién:** Tech leads, DevOps, Agent architects

**Keywords:** `agents`, `copilot`, `agent-setup`, `ai-governance`

---

### Spec-Driven Development 📋

**Ubicación:** `skills/transversal/specs-driven/`

**Descripción:** Crear especificaciones de features con approval gates (requirements → design → tasks).

**Funcionalidades:**
- ✅ 3 archivos por feature: requirements.md, design.md, tasks.md
- ✅ Gates de aprobación humana
- ✅ Microtareas organizadas
- ✅ Templates predefinidos

**Para quién:** Product managers, Architects, Feature lead

**Keywords:** `specs`, `requirements`, `design`, `approval-gates`

---

## Catálogo de Skills por Dominio

### Backend Skills 🔧

Ubicación: `skills/backend/`

| Skill | Descripción | Keywords |
|-------|-------------|----------|
| API Design | Patrones REST, gRPC, GraphQL | `api`, `rest`, `design-patterns` |
| Database Strategies | SQL, NoSQL, indexing | `database`, `sql`, `optimization` |
| Microservices | Service mesh, observabilidad | `microservices`, `distributed` |
| Testing Strategies | Unit, integration, E2E | `testing`, `tdd`, `coverage` |

---

### Frontend Skills 🎨

Ubicación: `skills/frontend/`

| Skill | Descripción | Keywords |
|-------|-------------|----------|
| React Patterns | Hooks, state management, optimization | `react`, `components`, `hooks` |
| CSS Architecture | BEM, SCSS, responsive | `css`, `styling`, `responsive` |
| Performance | Bundle optimization, lazy loading | `performance`, `optimization` |
| Testing Frontend | Jest, Cypress, visual regression | `testing`, `e2e`, `jest` |

---

### Mobile Skills 📱

Ubicación: `skills/mobile/`

| Skill | Descripción | Keywords |
|-------|-------------|----------|
| Flutter Architecture | Clean architecture, state management | `flutter`, `architecture`, `blo` |
| Native Integration | Platform channels, iOS/Android | `native`, `platform-specific` |
| Mobile Testing | Widget, E2E, performance | `testing`, `mobile`, `flutter-test` |
| App Lifecycle | Initialization, background tasks | `lifecycle`, `initialization` |

---

### QA/Testing Skills ✅

Ubicación: `skills/qa-testing/`

| Skill | Descripción | Keywords |
|-------|-------------|----------|
| Test Automation | Frameworks, CI/CD, reporting | `automation`, `testing`, `ci-cd` |
| Test Strategy | Coverage, types, planning | `strategy`, `planning`, `coverage` |
| Performance Testing | Load, stress, profiling | `performance`, `load-testing` |
| Security Testing | OWASP, penetration testing | `security`, `penetration`, `owasp` |

---

### Architecture Skills 🏗️

Ubicación: `skills/arquitectura/`

| Skill | Descripción | Keywords |
|-------|-------------|----------|
| Design Patterns | SOLID, DDD, creational | `design-patterns`, `solid`, `ddd` |
| System Design | Scalability, CAP theorem | `system-design`, `scalability` |
| ADRs | Architecture Decision Records | `adr`, `decisions`, `documentation` |
| Monorepo vs Multirepo | Strategies, tools | `monorepo`, `structure` |

---

### DevSecOps Skills 🔐

Ubicación: `skills/devsecops/`

| Skill | Descripción | Keywords |
|-------|-------------|----------|
| Security Best Practices | OWASP, secrets management | `security`, `best-practices`, `secrets` |
| CI/CD Pipelines | GitHub Actions, GitLab CI | `ci-cd`, `automation`, `deployment` |
| Observability | Logs, metrics, tracing | `observability`, `monitoring`, `logs` |
| Infrastructure as Code | Terraform, CloudFormation | `iac`, `Infrastructure`, `terraform` |

---

## Catálogo de Prompts

Ubicación: `prompts/{domain}/`

Cada dominio tiene un conjunto de prompts especializados para agentes:

- `backend-api-design.md` — Asistente para diseño de APIs
- `frontend-component-refactor.md` — Ayuda en refactoring de componentes
- `mobile-architecture-review.md` — Review de arquitectura mobile
- `qa-test-plan.md` — Generación de planes de testing
- etc.

Cada prompt:
- Tiene instrucciones claras para el agente
- Referencia skills relacionados
- Incluye ejemplos
- Define el rol del agente

---

## Catálogo de Agentes

Ubicación: `agents/{domain}/`

Cada dominio puede tener agentes especializados con AGENTS.md local:

- `agents/backend/AGENTS.md` — Briefing para agentes backend
- `agents/frontend/AGENTS.md` — Briefing para agentes frontend
- `agents/mobile/AGENTS.md` — Briefing para agentes mobile
- etc.

---

## Catálogo de CLIs

Ubicación: `clis/{domain}/`

Herramientas ejecutables para automatización:

- `clis/transversal/changelog-updater/` — Auto-actualizar CHANGELOG.md
- `clis/backend/db-migrator/` — Helpers para migraciones
- `clis/qa-testing/test-reporter/` — Consolidar reportes de test
- etc.

