# pragma-ai-knowledge-{cuenta}

Repositorio de conocimiento SOPP AI para **{nombre de la cuenta}**.

## Setup inicial

1. Crear el repo desde este template
2. Configurar los secrets en GitHub Actions:
   - `SOPP_HUB_URL` — URL base del API Gateway del Hub
   - `SOPP_HUB_API_KEY` — API Key del Hub
   - `SOPP_WEBHOOK_SECRET` — Secret HMAC compartido con el Hub
3. Actualizar `.github/CODEOWNERS` con los equipos de la cuenta
4. Crear el primer asset y hacer PR a main

## Estructura

```
chapters/
  backend/
    steering/         ← instrucciones de comportamiento para backend
    skills/           ← skills por stack (java-spring, node-express, dotnet, etc.)
    workflows/        ← flujos de trabajo
    guardrails/       ← restricciones
    prompts/          ← plantillas con variables
    personas/         ← modos con rol específico
    convenciones/     ← estándares de código
  calidad/
  mobile/
  frontend/
  arquitectura/
shared/
  steering/           ← aplica a TODOS los pragmáticos de la cuenta
  guardrails/         ← restricciones globales de la cuenta
  docs/               ← documentación consultable
  adrs/               ← decisiones de arquitectura
```

## Cómo crear un asset

Cada archivo `.md` debe tener un frontmatter YAML con estos campos obligatorios:

```yaml
---
id: mi-skill-id              # kebab-case, único en el repo
version: 1.0.0               # semver
scope: stack                  # global | chapter | stack
type: skill                   # skill | steering | workflow | guardrail | prompt | persona | doc | adr | convencion
chapter: backend              # requerido si scope != global
stack: [java-spring]          # requerido si scope = stack
tags: []
description: Qué hace este asset en una línea
---

## Contenido del asset...
```

## Override de assets de core

Para sobrescribir un asset que existe en `pragma-ai-knowledge-core`:

**Override completo** (reemplaza todo):
```yaml
---
id: mismo-id-que-en-core
pragma_extends: chapters/backend/skills/java-spring/el-asset
pragma_override: full
---
```

**Override parcial** (solo cambia secciones específicas):
```yaml
---
id: mismo-id-que-en-core
pragma_extends: chapters/backend/skills/java-spring/el-asset
pragma_override: merge
---

## Sección que quiero cambiar
Nuevo contenido de esta sección
```

## GitHub Actions

- **lint.yml** — Valida frontmatter y estructura en cada PR
- **webhook.yml** — Notifica al Hub cuando se mergea a main
