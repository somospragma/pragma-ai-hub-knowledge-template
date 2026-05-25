# pragma-ia-foundations — Guía de Implementación

## Para Contribuidores: Cómo Crear un Nuevo Skill

### Paso 1: Definir Estructura

Crea la carpeta del skill en el dominio correcto:

```bash
mkdir -p skills/{domain}/{skill-name}
cd skills/{domain}/{skill-name}
```

### Paso 2: Crear SKILL.md

Este archivo es el corazón del skill. Incluye:

```markdown
---
name: {skill-name}
description: |
  Descripción rica semánticamente para que agentes detecten este skill
  automáticamente por keywords. Incluir problema resuelto + casos de uso.
keywords: [keyword1, keyword2, keyword3]
domains: [{domain}]
requires-skills: [{dependency}]  # Opcional
version: 1.0
---

# {Skill Title}

## Cuando Usar Este Skill

[Contextos en que aplica]

## Contenido Principal

[Instrucciones, patrones, guía completa]

## Indicadores de Éxito

[Cómo validar que se aplicó correctamente]
```

**Reglas de SKILL.md:**

- ✅ Máximo 10MB
- ✅ Frontmatter YAML válido (sin errores de indentación)
- ✅ Sin credenciales, tokens, emails reales, rutas absolutas
- ✅ Keywords relevantes (mínimo 3, máximo 10)
- ✅ Referencias a otros skills con links relativos: `[Other Skill](../../otro-domain/skill/SKILL.md)`
- ✅ Si referencia documentación externa: usar links absolutos con protocolo `https://`

### Paso 3: Crear Evals

Archivo `evals/evals.json` con test cases:

```json
{
  "skill_name": "{skill-name}",
  "test_cases": [
    {
      "id": "test-001",
      "name": "Verificar detección de keywords",
      "input": "usuario pregunta sobre X",
      "expected_keyword_match": ["keyword1", "keyword2"],
      "expected_outcome": "Skill cargado correctamente"
    },
    {
      "id": "test-002",
      "name": "Aplicar skill en contexto Y",
      "input": "contexto específico",
      "expected_output": ["resultado 1", "resultado 2"],
      "pass_criteria": "output contiene ambos resultados"
    }
  ]
}
```

### Paso 4: Crear Referencias (Opcional)

Si necesitas contenido externo, crea `references/`:

```bash
mkdir references
cat > references/external-guide.md <<EOF
# Guía Externa

[Contenido de referencia]
EOF
```

### Paso 5: Crear Assets (Opcional)

Si necesitas templates, diagramas, ejemplos:

```bash
mkdir assets
cat > assets/template.md <<EOF
# Template

[Plantilla reutilizable]
EOF
```

### Paso 6: Crear Scripts (Opcional)

Si necesitas validación o generación:

```bash
mkdir scripts
cat > scripts/validate.py <<EOF
#!/usr/bin/env python3

def validate_skill():
    # Lógica de validación
    pass
EOF
chmod +x scripts/validate.py
```

### Paso 7: Validar Estructura

```bash
# Desde raíz del proyecto
python3 skills/transversal/documentation-projects/scripts/validate_structure.py \
  skills/{domain}/{skill-name}/
```

### Paso 8: Commit y Push

```bash
git checkout -b feature/add-{skill-name}
git add skills/{domain}/{skill-name}/
git commit -m "feat(skills/{domain}): add {skill-name} skill"
git push origin feature/add-{skill-name}
# Abre PR para review
```

---

## Para Contribuidores: Cómo Agregar un Prompt

### Paso 1: Crear el Archivo

```bash
cat > prompts/{domain}/{prompt-name}.md <<EOF
---
name: {prompt-name}
description: Breve descripción
keywords: [tag1, tag2]
related-skills: [skill1, skill2]
domain: {domain}
---

# {Prompt Title}

[Contenido del prompt para el agente]
EOF
```

**Reglas de Prompts:**

- ✅ Máximo 2MB
- ✅ YAML frontmatter válido
- ✅ Referencias a skills como `[Link](../../skills/{domain}/{skill}/SKILL.md)`
- ✅ Sin información sensible
- ✅ Destinado a ser cargado por agentes de IA

### Paso 2: Linkear en features.md

Actualizar `docs/features.md` para listar el nuevo prompt.

---

## Convenciones de Código y Estándares

### Estructura de Directorios

- ✅ Nomenclatura: `kebab-case` (ej: `changelog-management`, not `changelogManagement`)
- ✅ Máximo 3 niveles de nesting
- ✅ Evitar `_` excepto en prefijos agnósticos (`_estandar-instructions`)

### Markdown

- ✅ Headers: H1 (#) para título, H2 (##) para secciones principales
- ✅ Listas: `-` para bulleted, `1.` para numeradas
- ✅ Código: `` ` `` para inline, ` ``` ` para bloques
- ✅ Links internos: `[Texto](../../otro-domain/skill/SKILL.md)`
- ✅ Links externos: `https://...` con protocolo

### YAML Frontmatter

Indentación estricta (2 espacios):

```yaml
---
name: my-skill
description: Descripción multi-línea
keywords: [tag1, tag2]
version: 1.0
---
```

No usar tabs. Validar con `yamllint`.

### Seguridad

- ❌ NUNCA grabar: tokens, API keys, passwords
- ❌ NUNCA grabar: emails reales, URLs con auth
- ❌ NUNCA grabar: rutas absolutas `/Users/...`, `C:\...`
- ✅ Usar placeholders: `[YOUR_API_KEY]`, `[USER_EMAIL]`, `/path/to/...`

---

## Proceso de Review

Solo skills que pasen esto pueden mergear:

### Checklist para Reviewers

```markdown
- [ ] SKILL.md tiene YAML válido
- [ ] Sin datos sensibles (ejecutar grep en references/)
- [ ] Descripción clara y rich en keywords
- [ ] Evals presentes y válidos
- [ ] Referencias son links relativos (internos) o HTTPS (externos)
- [ ] Máximo 10MB
- [ ] Sin TBDs sin justificación
- [ ] Estructura consistente con otros skills del mismo dominio
```

### CI/CD Checks (Automático)

```bash
# Los siguientes checks se ejecutan automáticamente en GitHub Actions

yamllint skills/{domain}/{skill-name}/SKILL.md
python3 scripts/validate_structure.py skills/{domain}/{skill-name}/
python3 scripts/analyze_completeness.py skills/{domain}/{skill-name}/
# Buscar credenciales con regex
grep -r "password\|token\|api[_-]key\|secret" skills/{domain}/{skill-name}/ && exit 1 || true
```

---

## Actualización de AGENTS.md Global

Cuando agregues un nuevo skill crítico, actualiza `AGENTS.md`:

1. Agrega los comandos relevantes si aplica
2. Linkea el skill en la sección de Skills
3. Si afecta límites o deny lists, actualiza

---

## Actualización de Documentación

Cuando agregues un skill/prompt/CLI, actualiza:

- `docs/features.md` — Agregar a catálogo
- `docs/project-structure.md` — Si cambia la estructura
- `CHANGELOG.md` — Documentar cambio

---

## Testing Local

Antes de pushear:

```bash
# Validar estructura
python3 skills/transversal/documentation-projects/scripts/validate_structure.py skills/

# Validar completitud
python3 skills/transversal/documentation-projects/scripts/analyze_completeness.py skills/

# Revisar cambios
git diff --stat
```

---

## FAQ de Contribución

### ¿Debo duplicar contenido entre skills?

**No.** Usa referencias (links relativos). Si dos skills comparten lógica, considera:
1. Crear un skill compartido en `transversal/`
2. Linkear desde ambos skills
3. Especializar en cada dominio sin copiar

### ¿Qué tamaño debe tener un SKILL.md?

**Depende del contenido:**
- Skill simple (patterns, convenciones): 1-3 MB
- Skill complejo (full workflow): 3-8 MB
- Máximo permitido: 10 MB

Si superas 10 MB, considera:
- Mover references/ a carpeta externa
- Crear sub-skills
- Comprimir ejemplos

### ¿Puedo usar imágenes?

Sí, pero:
- Usar formato comprimido (PNG, WebP)
- Máximo 100 KB por imagen
- Guardar en `assets/`
- Linker con path relativo: `![alt](../assets/image.png)`

### ¿Cada skill necesita evals?

**Sí.** Mínimo 2 test cases que validen:
1. Detección de keywords
2. Aplicación del skill en contexto real

---

## Comandos Útiles

```bash
# Crear estructura de skill
mkdir -p skills/{domain}/new-skill/{evals,references,assets,scripts}

# Validar todos los skills
find skills -name "SKILL.md" | xargs -I {} python3 scripts/validate_structure.py $(dirname {})

# Buscar TBDs sin resolver
grep -r "TODO\|TBD\|FIXME" skills/ prompts/ agents/ docs/

# Contar skills por dominio
find skills -name "SKILL.md" | cut -d/ -f2 | sort | uniq -c
```

