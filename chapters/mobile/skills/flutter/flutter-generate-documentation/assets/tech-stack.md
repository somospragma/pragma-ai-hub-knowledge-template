# pragma-ia-foundations — Tech Stack

## Tecnologías Principales por Componente

### Markup & Metadata

**Markdown** + **YAML Frontmatter**

- **Propósito:** Formato portable y agnóstico para skills, prompts, documentación
- **Versión:** CommonMark 0.30+
- **Justificación:** 
  - Portable entre IDEs (Copilot, Kiro, Cursor, etc.)
  - Renderizable en browsers, Git, terminals
  - Versionable en Git sin conflictos complejos
  - Legible en crudo sin herramientas especiales
- **Alternativas Consideradas:**
  - JSON: Verboso, difícil de leer en crudo
  - RST: Menos común, soporte limitado en IDEs
  - HTML: No portable, difícil de versionar

### Scripting & Automation

**Python 3.9+**, **Bash**

- **Propósito:** Scripts de validación, generación, testing
- **Justificación:**
  - Python: Análisis de estructura, validación de YAML, evals
  - Bash: CI/CD pipelines, comandos simples
- **Herramientas clave:**
  - `PyYAML`: Parseo de YAML
  - `pytest`: Testing de scripts
  - `pyyaml-include`: Referencias entre archivos YAML

### Versionamiento & Control

**Git** + **Semantic Versioning**

- **Propósito:** Historial, branching estrategia, releases
- **Convención:** [Conventional Commits](CONTRIBUTING.md) (feat, fix, docs, chore, etc.)
- **Tags:** `v{MAJOR}.{MINOR}.{PATCH}`
- **Branches:** main, develop, feature/*, bugfix/*

### Verificación & Calidad

**GitHub Actions**, **Pre-commit hooks**

- **Propósito:** CI/CD, validación automática
- **Checks:**
  - YAML valid syntax
  - No datos sensibles (credentials, tokens, emails)
  - Markdown valid
  - Links válidos (internal/external)
  - Evals ejecutables

### Integración con Agentes

**AGENTS.md**, **.github/copilot-instructions.md**, **.kiro/**, **.cursor/**

- **Propósito:** Instrucciones persistentes para agentes de IA
- **Agnóstico:** Soporta Copilot, Kiro, Cursor, Antigravity
- **Detección automática:** Agentes leen estos archivos en inicio

## Herramientas por Rol

| Rol | Herramienta | Propósito |
|-----|-----------|-----------|
| Desarrollador | VS Code + Copilot | Escribir skills, prompts |
| Arquitecto | Markdown editor | Documentar decisiones |
| DevOps | GitHub Actions | Validación + deployment |
| Agente de IA | AGENTS.md + instructions | Context + guardrails |

## Dependencias Externas

| Dependencia | Versión | Uso | Licencia |
|-------------|---------|-----|---------|
| `PyYAML` | 6.0+ | Parseo de YAML en scripts | MIT |
| `pytest` | 7.0+ | Testing de scripts Python | MIT |
| `yamllint` | 1.26+ | Linting de YAML | GPL-3.0 |

## No se usan

- Bases de datos (todo es Markdown)
- Contenedores (todo es portable)
- Compiladores (todo es interpretado)
- Servers (contenido estático)

## Futuras Expansiones

| Tecnología | Caso de Uso | Estado |
|-----------|-----------|--------|
| GraphQL | API para consultar skills | Exploratory |
| OpenAPI | Spec compartida de APIs | Exploratory |
| Mermaid | Diagramas de arquitectura | Supported |

## Constraintts de Rendimiento

| Métrica | Target | Justificación |
|---------|--------|---------------|
| Tiempo de carga SKILL.md | < 500ms | Latencia de agente |
| Tamaño máx SKILL.md | 10MB | Ventana de contexto |
| Tamaño promedio Prompt | < 2MB | Ventana de contexto del agente |
| Tiempo de evals | < 5s por skill | Feedback rápido en CI |
