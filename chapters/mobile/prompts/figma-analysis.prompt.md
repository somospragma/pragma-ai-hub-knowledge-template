---
name: figma-analysis
description: >
  Prompt especializado para analizar componentes o pantallas de Figma y
  convertirlos en especificación accionable para Flutter. Usar en la fase de
  análisis con `@figma-analyzer` cuando todavía no existe §1 en la spec.
  No usar cuando la tarea ya está en planificación, arquitectura o codegen.
agent: figma-analyzer
---

# Análisis de Figma para Flutter DS

## Skills de referencia

- flutter-ds-figma-mcp
- flutter-ds-theming-tokens
- flutter-ds-figma-checklist
- flutter-ds-atomic-hierarchy
- flutter-ds-asset-management

## Instrucción

Dado un enlace de Figma y una HU, generar `§1` del documento de spec usando
`PIPELINE_SPEC_PATH` como destino.

## Proceso

### 1. Acceso por MCP

1. Parsear URL (`fileKey`, `nodeId`).
2. Ejecutar `get_design_context(fileKey, nodeId)` como primer paso obligatorio.
3. Extraer de `get_design_context`:
   - anotaciones `Development`
   - estados/comportamientos guiados por Figma
   - nodos críticos para evidencia visual
4. Ejecutar `get_screenshot(...)` para cada cambio/annotación relevante.
5. `get_node(fileKey, nodeId)` para detectar tipo y estructura base.
6. Extraer todos los nodos `TEXT` visibles con texto literal exacto, node id,
   capa, scope/estado, estilo, alineación y reglas de truncamiento si existen.
7. Extraer constraints/layout relevantes: auto-layout, HUG/FILL/FIXED, padding,
   spacing, alignment, bounds, scroll/clip y zonas con riesgo de overflow.
8. Detectar nodos/vector assets relevantes.
9. Ejecutar `get_images(...)` por vector relevante (default `svg`, fallback `png`).
10. Si pantalla: `get_node_children` para secciones.
11. `get_styles(fileKey)` y `get_components(fileKey)` para contexto global.

### 1b. Si no hay acceso MCP o faltan datos críticos

- No solicitar input directo al usuario.
- Escribir sección parcial con `MCP status: ❌ no disponible`.
- Agregar `### 1.7 Bloqueos de Input` con faltantes exactos.
- Registrar estado `blocked_input` en bitácora y devolver control al orquestador.

Si MCP responde pero falla `get_design_context`, bloquear también
(`blocked_input`) para no omitir estados o comportamientos críticos.
Si `get_design_context` responde correctamente pero no hay anotaciones
`Development`, no bloquear: registrar `Development annotations: none` y
continuar.
Si falla `get_screenshot` para algún cambio guiado, bloquear también para no
perder evidencia visual obligatoria.
Si hay vectores críticos para la UI y falla su extracción (`get_images`) sin
fallback válido, bloquear también para no perder fidelidad visual.
Si faltan constraints detallados de Figma, no bloquear automáticamente: registrar
alerta, inferir mitigación conservadora anti-overflow y continuar si el layout
puede implementarse razonablemente.

### 2. Extracción visual y mapeo de tokens

Para cada elemento documenta layout, visual, texto, iconos y vectores.
Si un valor no tiene token, marcar `⚠️ ALERTA`.

Para textos visibles:

- Copiar `characters` exactamente como viene de Figma.
- Preservar mayúsculas, acentos, puntuación y saltos visibles.
- No traducir, corregir, resumir, expandir ni inventar copy.
- Separar texto visible de nombres técnicos de capas.

Adicionalmente, documenta una matriz de vectores con:

- uso funcional en pantalla/componente
- estrategia de consumo (`DS_ICON`, `SVG_ASSET`, `PNG_ASSET`)
- ruta/constante propuesta
- reglas de render (tamaño token, color token/original, semántica)

### 3. Variantes, estados y jerarquía

- Variantes Figma → enums Flutter.
- Estados de componente: default/hover/pressed/disabled/loading/focused/error.
- Incluir estados/comportamientos especiales definidos en anotaciones
  `Development` (alertas, reglas condicionales, transiciones, callbacks).
- Para vistas, registrar siempre `loading`, `empty`, `error` y `populated`.
  Si Figma no define visual/copy para alguno, marcarlo como
  `fallback_required` y alertar que debe resolverse con fallback estándar del
  proyecto.
- Descomposición atómica.
- Si es vista completa, incluir `§1.4b` (scaffold, scroll, navegación, estados).

### 4. Criterios de aceptación

Extraer checklist funcional desde la HU.
Si la HU pide textos, estados o UX no presentes en Figma/metadatos, reportarlo
como alerta de alcance y no generar copy ni UI adicional.

## Output obligatorio

Escribir en `PIPELINE_SPEC_PATH`:

```markdown
## §1 Análisis de Figma: [NombreComponente/NombreVista]

### 1.0 Metadatos MCP
- **File key**: [fileKey]
- **Node ID**: [nodeId]
- **Tipo**: [Component | Component Set | Frame/Screen]
- **MCP status**: [✅ acceso directo | ❌ no disponible]
- **Design context status**: [✅ obtenido | ❌ no disponible]
- **Screenshots por cambio**: [N capturas]

### 1.1 Propiedades Visuales
| Elemento | Propiedad | Valor Figma | Token Flutter | Status |
|----------|-----------|-------------|---------------|--------|

### 1.1b Textos Literales
| Node ID | Scope/Estado | Capa | Texto exacto Figma | Uso Flutter | Editable por agente |
|---------|--------------|------|--------------------|-------------|---------------------|

### 1.1c Layout, Constraints y Riesgo de Overflow
| Elemento | Node ID | Constraints Figma | Riesgo | Mitigación recomendada | Status |
|----------|---------|-------------------|--------|--------------------------|--------|

### 1.2 Variantes
| Variante Figma | Enum Flutter | Diferencias visuales |
|---------------|-------------|---------------------|

### 1.3 Estados
| Estado | Fuente (Figma/Fallback) | Cambios visuales | Copy | Implementación Flutter | Alerta |
|--------|--------------------------|-----------------|------|------------------------|--------|

### 1.3b Anotaciones Development (obligatorio si existen)
| Annotation | Nodo/Scope | Tipo (estado/comportamiento/regla) | Impacto Flutter | Requerido |
|-----------|------------|--------------------------------------|-----------------|----------|

### 1.3c Vectores y Assets (obligatorio si existen)
| Vector/Asset | Node ID | Uso UI | Estrategia (DS_ICON\|SVG_ASSET\|PNG_ASSET) | Ruta/Constante propuesta | Render (size/color/semantics) | Estado |
|-------------|---------|--------|----------------------------------------------|--------------------------|-------------------------------|--------|

### 1.4 Descomposición Atómica
[árbol propuesto]

### 1.4b Estructura de Vista (solo si aplica)
- **Scaffold**: [...]
- **Scroll**: [...]
- **Organismos identificados**: [...]
- **Navegación**: [...]
- **Estados de vista**: [...]

### 1.5 Criterios de Aceptación
- [ ] CA-1 ...
- [ ] CA-2 ...

### 1.6 Alertas
- ⚠️ ...
- ⚠️ Si `get_design_context` falla, marcar bloqueo explícito.
- ⚠️ Si no hay anotaciones `Development`, registrar `none` y continuar.
- ⚠️ Si faltan vectores críticos para la UI objetivo, marcar bloqueo explícito.
- ⚠️ Si faltan constraints de Figma, continuar con mitigación anti-overflow y
  registrar el riesgo; no bloquear salvo que impida implementar.
- ⚠️ Si la HU pide textos/UX no presentes en Figma, reportar como alcance no
  cubierto por diseño, sin inventar copy.

### 1.7 Bloqueos de Input (solo si aplica)
- ❓ ...
```
