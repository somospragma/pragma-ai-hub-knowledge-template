# pragma-ia-foundations — Estructura del Proyecto

## Arquitectura General

```
pragma-ia-foundations/
├── docs/                          # 📚 Documentación del proyecto (7 documentos)
├── skills/                        # 🎯 Skills reutilizables por dominio
│   ├── transversal/              # Skills compartidos (changelog, commit-conventions, documentation, etc.)
│   ├── backend/                  # Skills para backend
│   ├── frontend/                 # Skills para frontend
│   ├── mobile/                   # Skills para mobile
│   ├── qa-testing/               # Skills para QA/testing
│   ├── arquitectura/             # Skills para arquitectura
│   └── devsecops/                # Skills para DevSecOps
├── prompts/                       # 💬 Prompts especializados por dominio
│   ├── transversal/
│   ├── backend/
│   ├── frontend/
│   ├── mobile/
│   ├── qa-testing/
│   ├── arquitectura/
│   └── devsecops/
├── agents/                        # 🤖 Definiciones de agentes por dominio
│   ├── transversal/
│   ├── backend/
│   ├── frontend/
│   ├── mobile/
│   ├── qa-testing/
│   ├── arquitectura/
│   └── devsecops/
├── clis/                          # 🛠️ Herramientas CLI transversales
│   ├── transversal/
│   ├── backend/
│   ├── frontend/
│   ├── mobile/
│   ├── qa-testing/
│   ├── arquitectura/
│   └── devsecops/
├── AGENTS.md                      # 🎯 Briefing global para agentes
├── README.md                      # 📖 Punto de entrada
├── CHANGELOG.md                   # 📝 Registro de cambios
├── CONTRIBUTING.md                # 🤝 Guía de contribución
└── .github/
    └── copilot-instructions.md    # 🔧 Instrucciones para Copilot
```

## Estructura de un Skill

```
skills/{domain}/{skill-name}/
├── SKILL.md                       # 📄 Skill principal con metadata + contenido
├── evals/                         # ✅ Evaluaciones y test cases
│   └── evals.json
├── references/                    # 📚 Referencias externas
│   ├── reference-1.md
│   └── reference-2.md
├── assets/                        # 🎨 Assets (templates, ejemplos, diagramas)
│   ├── template-1.md
│   ├── example-1.json
│   └── diagram.mmd
└── scripts/                       # 🐍 Scripts de apoyo (si aplica)
    ├── validate.py
    └── generate.sh
```

## Estructura de un Prompt

```
prompts/{domain}/{prompt-name}.md
```

Contenido mínimo:
```markdown
---
name: {prompt-name}
description: [Breve descripción]
keywords: [tag1, tag2, tag3]
related-skills: [skill1, skill2]
domain: {domain}
---

# {Prompt Title}

[Contenido del prompt]
```

## Estructura de un CLI

```
clis/{domain}/{cli-name}/
├── README.md                      # 📖 Documentación
├── {cli-name}.py                  # 🐍 Implementación (lenguaje puede variar)
├── requirements.txt               # 🔧 Dependencias (si Python)
└── tests/                         # ✅ Tests (si aplica)
    └── test_{cli-name}.py
```

## Dominios y Responsabilidades

| Dominio | Responsable | Ejemplos de Skills | Skills Clave |
|---------|-------------|-------------------|----------------|
| **transversal** | Equipo Core | changelog, commit-conventions, documentation | Aplican a todos |
| **backend** | Backend team | API design, testing, database, microservicios | Patterns, tools |
| **frontend** | Frontend team | React, Vue, component patterns | State management, testing |
| **mobile** | Mobile team | Flutter, React Native, lifecycle | Clean arch, testing |
| **qa-testing** | QA team | Testing strategies, automation, CI/CD | Frameworks, coverage |
| **arquitectura** | Architects | Design patterns, domain-driven design, ADRs | Decisions, docs |
| **devsecops** | DevSecOps team | Seguridad, observabilidad, deployment | Security, monitoring |

## Flujos de Lectura

### Para Desarrollador Backend

1. **Descubrir skills:** `skills/backend/` + `skills/transversal/`
2. **Seguir patrones:** Leer `implementation.md` en `skills/backend/`
3. **Usar prompts:** Cargar `prompts/backend/` en Copilot
4. **Ejecutar CLI:** Usar herramientas de `clis/backend/`

### Para Arquitecto

1. **Visión global:** `docs/project-overview.md`
2. **Decisiones:** `skills/arquitectura/` para ADRs y decisiones
3. **Patrones:** `skills/{domain}/` para ver patrones por dominio

### Para Agente de IA (Copilot)

1. **Inicializar:** Leer `AGENTS.md`
2. **Detectar contexto:** Leer `.github/copilot-instructions.md`
3. **Cargar skills:** Detectar keywords del user query → cargar SKILL.md relevante
4. **Usar prompts:** Aplicar prompt especializado de `prompts/`

## Constraints y Límites

| Línea | Constraint |
|------|-----------|
| Máximo 10MB por SKILL.md (incluye references/) | Performance |
| Máximo 2MB por Prompt | Ventana de contexto del agente |
| Máximo 500 líneas por CLI principal | Mantenibilidad |
| Mínimo 1 eval por skill | Calidad |
| Máximo 3 niveles de nesting de directorios | Claridad |
