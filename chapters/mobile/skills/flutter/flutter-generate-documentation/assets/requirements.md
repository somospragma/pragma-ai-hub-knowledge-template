# pragma-ia-foundations — Requirements

## Requisitos Funcionales

### RF-001: Catálogo de Skills Organizado

**Descripción:** El repositorio debe mantener skills organizados por dominio (backend, frontend, mobile, QA, arquitectura, DevOps, transversal) con estructura consistente.

**Criterios de Aceptación:**
- ✅ Cada skill tiene SKILL.md con metadata (name, description, keywords)
- ✅ Cada skill puede usar referencias/ y assets/ opcionales
- ✅ Cada skill tiene evals/ para validar calidad
- ✅ Los 7 dominios coexisten sin conflictos

**Prioridad:** CRÍTICA

### RF-002: Prompts Especializados por Dominio

**Descripción:** Mantener prompts reutilizables organizados por dominio (backend, frontend, etc.) para agentes de IA.

**Criterios de Aceptación:**
- ✅ Prompts organizados en carpetas por dominio
- ✅ Naming consistente y documentado
- ✅ Cada prompt referencia skills relacionados

**Prioridad:** ALTA

### RF-003: Definiciones de Agentes

**Descripción:** Mantener AGENTS.md globales y posiblemente locales por dominio, con briefing para agentes de IA.

**Criterios de Aceptación:**
- ✅ AGENTS.md raíz con stack, comandos críticos, límites
- ✅ Referencias a documentación sin duplication
- ✅ Integrable con Copilot, Kiro, Cursor

**Prioridad:** CRÍTICA

### RF-004: CLIs y Herramientas Transversales

**Descripción:** Mantener utilidades CLI y scripts usables por toolchains.

**Criterios de Aceptación:**
- ✅ CLIs documentadas y versionadas
- ✅ Scripts ejecutables desde CI/CD
- ✅ README en cada CLI

**Prioridad:** MEDIA

### RF-005: Detección Automática de Skills por Agentes

**Descripción:** Agentes de IA deben poder descubrir y cargar skills automáticamente basado en keywords.

**Criterios de Aceptación:**
- ✅ Cada SKILL.md tiene description con keywords semánticas
- ✅ Agentes detectan keywords en queries del usuario
- ✅ Skill completo se carga solo cuando es necesario

**Prioridad:** ALTA

## Requisitos Técnicos

### RT-001: Estructura Agnóstica

**Descripción:** El repositorio debe ser agnóstico a IDE (Copilot, Kiro, Cursor, Antigravity), lenguaje y stack de cada dominio.

**Criterios:**
- No asumir Python vs. Bash vs. otra tecnología
- Formato Markdown + YAML frontmatter para portabilidad
- Validar que funcione con múltiples IDEs

**Prioridad:** ALTA

### RT-002: Performance de Carga

**Descripción:** Los skills deben cargarse en < 500ms incluso con repositorio grande.

**Criterios:**
- Máximo 10MB por SKILL.md
- Referencias lazy-loading (no cargar archivos grandes por defecto)
- Estructura de directorios optimizada

**Prioridad:** MEDIA

### RT-003: Validación y Linting

**Descripción:** Estructura y contenido deben pasar validaciones automáticas.

**Criterios:**
- YAML frontmatter válido en todos los SKILL.md
- Sin datos sensibles (tokens, emails, URLs reales, rutas absolutas)
- Markdown válido

**Prioridad:** ALTA

### RT-004: Control de Versiones

**Descripción:** Seguir Semantic Versioning y mantener CHANGELOG actualizado.

**Criterios:**
- CHANGELOG.md documentado
- Tags en Git para releases
- Conveencional Commits en mensajes

**Prioridad:** ALTA

## Requisitos de Calidad

- **Code Quality:** Markdown válido (no syntax errors)
- **Documentation:** Cada skill ≥ 80% documentado (no TBDs)
- **Evals:** Cada skill incluye evals.json con test cases
- **Review:** Code review obligatorio antes de merge
- **Security:** Sin credenciales, tokens o datos sensibles

## Requisitos de Ambiente

| Ambiente | Características | Restricciones |
|----------|-----------------|---------------|
| **DEV** | Rama develop, PRs activos | Contribuidores autorizados |
| **QA** | Testing de skills antes de release | Evals deben pasar |
| **STAGING** | Versión pre-release de main | No cambios directos |
| **PROD** | main branch, tags de versión | Solo releases tagged |
