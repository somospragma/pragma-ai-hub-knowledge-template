# SOPP AI Hub — Knowledge {Cuenta}

Repositorio de conocimiento SOPP AI para **{nombre de la cuenta}**.

Este repo extiende el [core](https://dev.azure.com/Pragma-SOPP/SOPP-Core/_git/kratos-knowledge-core) con assets específicos para esta cuenta. Puede agregar assets nuevos o sobrescribir los del core.

## IDEs soportados

| IDE | Tipos de asset soportados |
|---|---|
| **Kiro** | steering, skill, workflow, prompt, agent |
| **GitHub Copilot** | steering, skill, prompt |
| **Amazon Q (IDE)** | steering, skill, prompt |
| **Amazon Q (CLI)** | steering, skill, agent |
| **Claude Code** | steering, skill, workflow |

## Setup inicial

1. Crear el repo desde este template con nombre `pragma-ai-hub-knowledge-{cuenta}`
2. Configurar el webhook en el Hub (contactar equipo de plataforma)
3. Actualizar `.github/CODEOWNERS` con los equipos de la cuenta
4. Crear el primer asset y hacer PR a main

## Estructura

```
chapters/                     ← Assets por chapter (misma estructura que core)
├── backend/
│   ├── steering/
│   ├── skills/
│   │   ├── _all/
│   │   ├── java-spring/
│   │   ├── node-express/
│   │   └── ...
│   ├── workflows/
│   ├── guardrails/
│   ├── prompts/
│   ├── personas/
│   └── convenciones/
├── calidad/
├── mobile/
├── frontend/
└── arquitectura/

projects/                     ← Assets por proyecto (3ra capa de herencia)
└── {nombre_proyecto}/
    └── chapters/
        └── ...               ← Misma estructura que chapters/

shared/                       ← Assets globales de la cuenta
├── steering/
├── guardrails/
├── docs/
└── adrs/
```

> No necesitas crear todas las carpetas — solo las que tengan contenido.

## Cómo crear un asset

Cada archivo `.md` requiere frontmatter YAML:

```yaml
---
id: mi-skill-id              # kebab-case, único en el repo
version: 1.0.0               # semver
scope: stack                  # global | chapter | stack
type: skill                   # skill | steering | workflow | guardrail | prompt | persona | convencion
chapter: backend              # requerido si scope != global
stack: [java-spring]          # requerido si scope = stack
tags: []
description: Qué hace este asset en una línea
---

## Contenido del asset...
```

## Override de assets del core

Si quieres modificar un asset que ya existe en el core para esta cuenta:

### Override completo (reemplaza todo)

```yaml
---
id: mismo-id-que-en-core
version: 1.0.0
scope: stack
type: skill
chapter: backend
stack: [java-spring]
pragma_extends: chapters/backend/skills/java-spring/el-asset
pragma_override: full
description: Versión personalizada para esta cuenta
---

## Contenido completamente nuevo
El contenido del core se ignora.
```

### Override parcial (merge por secciones)

Solo declara las secciones `##` que quieres cambiar o agregar:

```yaml
---
id: mismo-id-que-en-core
version: 1.0.0
scope: stack
type: skill
chapter: backend
stack: [java-spring]
pragma_extends: chapters/backend/skills/java-spring/el-asset
pragma_override: merge
description: Extensión para esta cuenta
---

## Instrucción
Nuevo contenido de esta sección (reemplaza la del core)

## Estándares de la cuenta
Nueva sección que no existe en core (se agrega al final)
```

**Reglas del merge:**
- Sección existe en core y en cuenta → **gana cuenta**
- Sección existe solo en core → se mantiene
- Sección existe solo en cuenta → se agrega al final

## Assets por proyecto (3ra capa)

Si necesitas assets específicos para un proyecto dentro de la cuenta:

```
projects/
└── agentes_ia/               ← nombre normalizado del proyecto
    └── chapters/
        └── backend/
            └── skills/
                └── java-spring/
                    └── mi-skill-proyecto.md
```

La prioridad es: **proyecto > cuenta > core**. Si un asset existe en las 3 capas, el del proyecto gana.

## Flujo de contribución

```
1. Crea una rama feature/mi-asset
2. Agrega el archivo .md en la carpeta correcta
3. Abre PR a main
4. El linter valida automáticamente
5. El AI Steward o Chapter Lead aprueba
6. Al mergear, el Hub procesa y distribuye
7. Los pragmáticos reciben el asset en su próximo sync
```

## Quién puede contribuir

- **Pragmáticos de la cuenta** — abren PRs con nuevos assets
- **AI Steward de la cuenta** — aprueba y gestiona el contenido
- **Chapter Leads** — aprueban assets de su chapter

## Flujo de ramas y ambientes

```
feature/* → PR a develop → merge
                              ↓
                          develop (push)
                              ↓
                    GitHub Action webhook.yml
                              ↓
              ┌───────────────┼───────────────┐
              ▼                               ▼
    Hub TEMPORAL                      Hub DEV (oficial)
    (se elimina después)              cuenta 700693144401

develop → PR a main → merge
                          ↓
                      main (push)
                          ↓
                GitHub Action webhook.yml
                          ↓
                    Hub PROD (oficial)
                    cuenta 258975980616
```

| Rama | Ambientes que notifica | Propósito |
|---|---|---|
| `develop` | Temporal + DEV oficial | Validar cambios antes de producción |
| `main` | PROD oficial | Contenido en producción para los pragmáticos |

### Environments de GitHub (Settings → Environments)

Cada environment tiene sus propios secrets (`SOPP_HUB_URL`, `SOPP_HUB_API_KEY`, `SOPP_WEBHOOK_SECRET`):

| Environment | Cuándo se usa |
|---|---|
| `temporal` | Push a develop (⚠️ se elimina cuando se retire el ambiente temporal) |
| `dev` | Push a develop |
| `prod` | Push a main |

## Contacto

- **AI Steward**: {nombre del steward}
- **Equipo de Plataforma**: #sopp-ai-hub
