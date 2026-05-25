---
name: atomic-inventory
description: >
   Prompt para inventariar componentes existentes, clasificar reutilización y
   construir el DAG de creación bottom-up. Usar cuando ya existe el análisis de
   Figma (§1) y toca decidir qué se reutiliza, qué se extiende y qué se crea
   con `@component-planner`. No usar como entrypoint de una tarea completa.
agent: component-planner
---

# Inventario Atómico, Spec Canónica y DAG

## Skills de referencia

- flutter-ds-folder-structure
- flutter-ds-naming-conventions
- flutter-ds-atomic-hierarchy
- flutter-ds-theming-tokens
- flutter-ds-asset-management
- flutter-ds-responsive-layout

## INSTRUCCIÓN

A partir del análisis de Figma (§1), generar la especificación canónica
del componente, inventariar el repositorio y crear el plan de creación.

## PROCESO

### Fase A: Especificación Canónica

1. **Normalizar** cada valor de §1 a su token exacto del DS
   - Consultar `flutter-ds-theming-tokens` y el catálogo del proyecto
   - Si no hay token → ⚠️ ALERTA (no inventar tokens)

2. **Definir props** del componente:
   - Nombre: `{{DS_PREFIX}}[Nombre]` o descriptivo según nivel
   - Parámetros tipados con required/optional/defaults
   - Enums: State, Variant, Size
   - Callbacks tipados
   - Comportamientos especiales desde `§1.3b Anotaciones Development`
   - Contrato de vectores desde `§1.3c Vectores y Assets`
   - Contrato de textos literales desde `§1.1b Textos Literales`
   - Contrato de layout seguro desde `§1.1c Layout, Constraints y Riesgo de Overflow`
   - No inventar copy ni UX adicional si no está sustentado por Figma/metadatos

3. **Escribir** §2 en `PIPELINE_SPEC_PATH`

### Fase B: Inventario del Repositorio

Para CADA sub-componente de la descomposición atómica:

**Búsqueda en 4 pasos:**

1. **Nombre exacto**: `symbol:[NombreComponente]` en el repo
2. **Archivo esperado**: path según `flutter-ds-folder-structure`
3. **Funcionalidad**: semantic search si pasos 1-2 no encuentran
4. **Carpeta**: listar archivos en `lib/[nivel]/[subcarpeta]/`

**Para cada encontrado:**
- Leer archivo completo
- Extraer: constructor, parámetros, estados, variantes
- Clasificar:
  - ✅ Compatible → reutilizar
  - ⚠️ Parcial → documentar qué falta
  - ❌ Incompatible → crear nuevo

**Para cada NO encontrado:**
- 🆕 Marcar como "Por crear"
- Asignar nivel atómico
- Proponer path y nombre

### Fase C: DAG de Dependencias

1. Inferir dependencias entre sub-componentes
2. Clasificar:
   - `reusar` → componente existente
   - `separado` → nuevo widget independiente
   - `inline` → widget privado del padre
3. Generar orden bottom-up estricto

### Fase D: Textos y Overflow

1. Propagar los textos de `§1.1b` sin traducir, corregir, resumir ni mejorar.
2. Si un estado requerido no trae texto desde Figma, registrar alerta de alcance
   y deuda; no convertir un placeholder técnico en copy final. Para vistas,
   mantener `loading`, `empty`, `error` y `populated` usando fallback estándar
   del proyecto cuando Figma no los defina.
3. Propagar riesgos de `§1.1c` y definir mitigación por componente/vista.
4. Si faltan constraints detallados, no bloquear solo por eso: inferir una
   mitigación conservadora anti-overflow y marcar la inferencia.

## OUTPUT OBLIGATORIO

```markdown
## §2 Especificación Canónica: [NombreComponente]

### Props
| Parámetro | Tipo | Required | Default | Token/Ref |
|-----------|------|----------|---------|-----------|

### Enums
- {{DS_PREFIX}}[Nombre]State: default_, disabled, loading, focused, error
- {{DS_PREFIX}}[Nombre]Variant: primary, secondary, ...
- {{DS_PREFIX}}[Nombre]Size: sm, md, lg (si aplica)

### Callbacks
| Callback | Tipo | Descripción |
|----------|------|-------------|

### Comportamientos Especiales (desde §1.3b)
| Regla/Annotation | Impacto UI | Prop/Estado/Callback requerido | Prioridad |
|------------------|------------|-------------------------------|-----------|

### Estados de Vista y Fallbacks (solo `/new-view`)
| Estado | Fuente | Componente/Widget | Copy | Fallback estándar | Alerta |
|--------|--------|-------------------|------|-------------------|--------|

### Contrato de Vectores (desde §1.3c)
| Vector/Asset | Uso UI | Estrategia | Owner (DS/APP) | Ruta/Constante | Estado |
|-------------|--------|------------|----------------|----------------|--------|

### Contrato de Textos Literales (desde §1.1b)
| Prop/Elemento | Texto exacto Figma | Node ID | Scope/Estado | Editable por agente |
|---------------|--------------------|---------|--------------|---------------------|

### Contrato de Layout Seguro (desde §1.1c)
| Elemento | Riesgo de overflow | Mitigación requerida | Inferido por falta de constraints | Severidad |
|----------|--------------------|-----------------------|-----------------------------------|-----------|

## §3 Inventario y DAG

### ✅ Existentes — Reutilizar
| Componente | Nivel | Path | API |
|-----------|-------|------|-----|

### ⚠️ Existentes — Requieren Extensión
| Componente | Nivel | Path | Qué falta | Cambio propuesto |
|-----------|-------|------|-----------|------------------|

### 🆕 Faltantes — Crear
| Componente | Nivel | Path propuesto | Estrategia | Specs |
|-----------|-------|---------------|-----------|-------|

### 🎯 Inventario de Vectores/Assets
| Vector/Asset | Estrategia final | Reutiliza DS Icon | Asset a crear/registrar | Ubicación |
|-------------|------------------|-------------------|-------------------------|----------|

### 🧩 Inventario de Textos y Overflow
| Componente/Widget | Textos literales usados | Mitigación overflow | Alertas |
|-------------------|-------------------------|---------------------|---------|

### DAG
[Diagrama de dependencias]

### 📋 Orden de Creación (bottom-up)
1. [Átomo 1] — sin dependencias
2. [Átomo 2] — depende de Átomo 1
3. [Molécula 1] — depende de Átomo 1, Átomo 2
4. [Organismo] — depende de Molécula 1

### ⚠️ Alertas
- [ambigüedades, conflictos, decisiones pendientes]
```

## REGLA DE ORO

NUNCA propongas crear un componente que ya existe y es compatible.
Si hay duda sobre compatibilidad, marca como ⚠️ Parcial con detalle.
NUNCA ignores anotaciones `Development` reportadas en `§1.3b`.
NUNCA ignores vectores reportados en `§1.3c`.
NUNCA inventes, traduzcas, corrijas ni reescribas textos visibles de Figma.
NUNCA bloquees solo por constraints incompletos si puedes mitigar overflow de
forma conservadora y reportar la alerta.
