# pragma-ia-foundations — User Flow

## Flujo 1: Agente de IA Consume Skills

### Escenario: Copilot Necesita Crear Documentación

```
Usuario en VS Code:
  "Crea documentación para mi proyecto backend"
       ↓
Copilot recibe query
       ↓
Lee .github/copilot-instructions.md (inicialización)
       ↓
Detecta keywords: "documentation", "project"
       ↓
Busca en pragma-ia-foundations/
       ↓
Carga skills/transversal/documentation-projects/SKILL.md
       ↓
Carga referencias según descripción del proyecto
       ↓
Aplica skill: obtiene 7 documentos base
       ↓
Devuelve respuesta con documentación generada
```

**Funciones críticas:**
- ✅ AGENTS.md inicializa contexto
- ✅ Keywords en SKILL.md.description permiten detección automática
- ✅ Referencias ricas en SKILL.md proveen contexto específico
- ✅ Frontmatter válido asegura parsing

---

## Flujo 2: Desarrollador Busca Skill Específico

### Escenario: Backend Dev Necesita Testing Strategy

```
Desarrollador abre pragma-ia-foundations/
       ↓
Lee docs/index.md o docs/features.md
       ↓
Busca "Testing" en features.md
       ↓
Encuentra link a skills/backend/testing-strategies/ o skills/qa-testing/
       ↓
Abre SKILL.md y lee:
  - Descripción
  - Cuándo usar
  - Patrones y estrategias
  - Ejemplos
       ↓
Aplica patrones en código
       ↓
Contribuye mejoras (si las encuentra)
```

**Rutas de lectura sugeridas:**
- **Primer skill:** docs/index.md → docs/features.md → skill específico
- **Skill profundo:** skills/{domain}/{skill}/SKILL.md directamente
- **Búsqueda rápida:** CLI local (futuro): `pragma search "testing"`

---

## Flujo 3: Tech Lead Configura Proyecto para Agentes

### Escenario: Setup New Repo para Agent-First Development

```
Tech lead crea repo nuevo
       ↓
Lee skills/transversal/ide-setup-agent-first/ (Fase 0-5)
       ↓
Fase 0: Descubre estado del repo
       ↓
Fase 1: Crea AGENTS.md en raíz
       ↓
Fase 2: Crea .github/copilot-instructions.md
       ↓
Fase 3: Setup specs-driven dev
       ↓
Fase 4: Optimiza contexto del agente
       ↓
Fase 5: Configura gobernanza (deny list, guard rails)
       ↓
Developers trabajan con agente configurado
```

**Archivos generados:**
- ✅ AGENTS.md (raíz)
- ✅ .github/copilot-instructions.md
- ✅ .specs/ (optional)
- ✅ .agent/rules/ (optional)

---

## Flujo 4: Contribuidor Crea Nuevo Skill

### Escenario: Backend Architect Contribuye Skill de Microservices

```
Contribuidor identifica gap de conocimiento
       ↓
Lee docs/implementation.md (instrucciones)
       ↓
Crea estructura:
  skills/backend/microservices-patterns/
  ├── SKILL.md
  ├── evals/evals.json
  ├── references/
  └── assets/
       ↓
Escribe SKILL.md con:
  - Metadata (name, description, keywords)
  - Patrones architecónicos
  - Ejemplos
  - Referencias
       ↓
Agrega test cases en evals/evals.json
       ↓
Valida estructura:
  python3 scripts/validate_structure.py ...
       ↓
Crea PR con cambios
       ↓
Reviewer chequea:
  - YAML syntax
  - Sin credenciales
  - Completitud
  - Documentación
       ↓
Merge a main después de approval
       ↓
Skill disponible automáticamente para agentes
```

**Archivos modificados:**
- ✅ skills/backend/microservices-patterns/SKILL.md (nuevo)
- ✅ docs/features.md (actualizar catálogo)
- ✅ CHANGELOG.md (documentar release)

---

## Flujo 5: Equipo Integra Prompts Especializados

### Escenario: QA Team Agrega Prompts de Testing

```
QA lead revisa skills/qa-testing/
       ↓
Identifica gap: "no hay prompt para test plans"
       ↓
Crea prompts/qa-testing/test-plan-generator.md
       ↓
Contenido:
  ---
  name: test-plan-generator
  related-skills: [testing-strategies, test-automation]
  keywords: [qa, test-plan, planning]
  ---
  
  # Prompt para generar planes de test
  
  [Instrucciones claras para agentes]
       ↓
Linkea skill relacionado:
  Ver [Testing Strategies](../../skills/qa-testing/testing-strategies/SKILL.md)
       ↓
Agrega a docs/features.md
       ↓
Commit y push
       ↓
Agentes detectan prompt automáticamente
```

---

## Flujo 6: MCP Server Consume Skills Programáticamente

### Escenario: Custom MCP Server Integra Skills (Futuro)

```
Desarrollo de MCP server
       ↓
Conecta a pragma-ia-foundations/ como resource provider
       ↓
Descubre skills via:
  GET /resources/skills/{domain}
       ↓
Carga SKILL.md completo
       ↓
Parsea YAML frontmatter
       ↓
Extrae keywords para contexto del agente
       ↓
Carga contenido rich (markdown + assets)
       ↓
Devuelve al agente en formato estructurado
       ↓
Agente aplica skill con contexto completo
```

**Endpoints posibles (futuro):**
```
GET /resources/skills/list
GET /resources/skills/{domain}
GET /resources/skills/{domain}/{skill-name}
GET /resources/prompts/{domain}
GET /resources/agents/{domain}
```

---

## Flujos por Rol Resumido

| Rol | Entrada | Acción | Salida |
|-----|---------|--------|--------|
| **Agente de IA** | Query del usuario | Detectar keywords → Cargar skill | Aplicar skill en respuesta |
| **Desarrollador** | Necesidad técnica | Buscar en docs/features.md → Leer SKILL.md | Implementar patrón/solución |
| **Tech Lead** | Nuevo repo | Ejecutar ide-setup-agent-first | AGENTS.md + .github/copilot-instructions.md |
| **Contribuidor** | Gap de conocimiento | docs/implementation.md → Crear skill | PR → Merge → Disponible |
| **QA Lead** | Plan de testing | Buscar prompts QA → Copilot genera | Plan de pruebas listo |
| **Architect** | Decisión técnica | Documentar en ADR → Linker en skills | Conocimiento compartido |

---

## Indicadores de Éxito

### Para Agentes

- ✅ **Detección automática:** Keywords se detectan sin intervención manual
- ✅ **Carga rápida:** SKILL.md carga en < 500ms
- ✅ **Aplicación válida:** Skill se aplica correctamente en contexto
- ✅ **No context rot:** Skill disponible en próximas sesiones por AGENTS.md

### Para Desarrolladores

- ✅ **Descubribilidad:** Encuentra el skill que necesita sin buscar en Google
- ✅ **Claridad:** Entiende patrón/solución sin ambigüedad
- ✅ **Aplicabilidad:** Puede aplicar el skill a su código sin fricción
- ✅ **Mejora libre:** Puede sugerir mejoras sin conflicto

### Para Mantenedores

- ✅ **Crecimiento ordenado:** Nuevos skills no rompen estructura
- ✅ **Calidad:** Todos los skills pasan evals y validación
- ✅ **Documentación:** Sin TBDs sin justificación
- ✅ **Seguridad:** Sin credenciales, datos sensibles o rutas absolutas

---

## Problemas Conocidos y Soluciones

| Problema | Solución |
|----------|----------|
| Skill no se carga en agente | Validar YAML frontmatter, validar keywords |
| Búsqueda lenta de skills | Indexar skills en CI/CD (futuro) |
| Referencias rotas | Scripts de validación en CI chequean links |
| Documentación desactualizada | Gate de revisión en PRs requiere actualizar docs/ |
| Skills duplicados en dominios | Review policy: centralizar en transversal si aplica |

