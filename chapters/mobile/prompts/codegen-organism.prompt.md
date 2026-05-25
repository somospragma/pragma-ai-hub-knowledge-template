---
name: codegen-organism
description: >
  Prompt para generar código Flutter de un organismo del Design System. Usar
  cuando toca construir una sección completa de UI a partir de moléculas y
  átomos ya planificados o existentes. No usar si todavía no está cerrada la
  descomposición atómica o el contrato técnico.
agent: widget-developer
---

# Generación de Organismo Flutter

## Skills de referencia

- flutter-ds-theming-tokens
- flutter-ds-component-template
- flutter-ds-naming-conventions
- flutter-ds-lint-rules
- flutter-ds-folder-structure
- flutter-ds-widget-anatomy
- flutter-ds-responsive-layout
- flutter-ds-a11y-semantics

## INSTRUCCIÓN

Genera el código Flutter completo de un organismo del Design System,
componiendo moléculas y átomos existentes y/o recién creados.

## INPUTS QUE RECIBIRÁS

1. Nombre del organismo a crear
2. Especificaciones visuales completas (de §1 y §2)
3. Lista de moléculas y átomos que compone (con paths e interfaces)
4. Estados requeridos
5. Criterios de aceptación funcionales (de la HU)
6. Path de destino
7. Interfaz diseñada (de §4)
8. Contrato de textos y overflow (`§4.B`), obligatorio en `/new-component` y
   `/new-view`; puede declarar "sin textos/riesgos" si no aplica al organismo

## DIFERENCIAS VS MOLÉCULA

Un organismo:
- Compone **moléculas + átomos** (mayor complejidad)
- Típicamente es una **sección completa de UI** (card, form, navigation bar)
- Puede tener **lógica de coordinación** entre moléculas
- Generalmente usa **Material** para elevation y surface
- Es el nivel más **parametrizable** (muchos callbacks y datos)
- Es el que más directamente **responde a la HU de negocio**

## REGLAS ESPECÍFICAS

### Comentarios en Código

- Prohibidos comentarios inline, de bloque y Dartdoc por defecto.
- Solo permitir comentario fundamental cuando no sea deducible del código
  (ej: workaround temporal, restricción regulatoria o decisión crítica de interoperabilidad).

### Composición con Material

> Los comentarios del snippet son didácticos y no deben copiarse en el código generado.

```dart
@override
Widget build(BuildContext context) {
  return Material(
    elevation: 0, // ElevationTokens.level1
    borderRadius: BorderRadius.circular(0), // {{DS_PREFIX}}BorderRadius.l
    color: /* token de surface */,
    clipBehavior: Clip.antiAlias,
    child: switch (state) {
      ...State.loading => _buildLoading(context),
      ...State.disabled => Opacity(
        opacity: 0.5,
        child: IgnorePointer(child: _buildContent(context)),
      ),
      _ => InkWell(
        onTap: onTap,
        child: _buildContent(context),
      ),
    },
  );
}
```

### Callbacks Múltiples

```dart
const {{DS_PREFIX}}ProductCard({
  // Datos
  required this.productName,
  required this.productPrice,
  this.productImageUrl,
  this.badgeLabel,
  // Estado
  this.state = {{DS_PREFIX}}ProductCardState.default_,
  // Callbacks — uno por cada acción del usuario
  this.onTap,
  this.onAddToCart,
  this.onToggleFavorite,
  this.onShare,
});
```

### Criterios de Aceptación

El organismo es donde se cumplen los criterios de la HU.
Para CADA criterio, verificar que el código lo implementa:

```dart
// HU: "Debe mostrar imagen, nombre, precio y botón de acción"
// → Verificar que el build incluye todos estos elementos

// HU: "El botón de favorito debe ser toggleable"
// → Verificar que existe param isFavorite + callback onToggleFavorite

// HU: "En estado loading, mostrar skeleton"
// → Verificar que _buildLoading() implementa skeleton COMPLETO
```

### Responsividad

```dart
Widget _buildContent(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 360) {
        return _buildCompact(context);
      }
      return _buildDefault(context);
    },
  );
}
```

### Textos y Overflow

- Usar únicamente textos literales provenientes de `§1.1b`/`§2`/`§4.B`.
- No inventar empty states, error messages, badges, CTAs o microcopy si no están
  en Figma/metadatos/anotaciones.
- Diseñar composición defensiva contra overflow:
  - `Flexible`/`Expanded` para textos en filas
  - `Wrap` para grupos horizontales que puedan saltar línea
  - scroll vertical cuando el organismo pueda crecer dentro de una vista
  - constraints flexibles en lugar de tamaños fijos
- Si Figma no trae constraints suficientes, aplicar la mitigación definida en
  `§4.B`, continuar y registrar alerta.

### Skeleton Completo

```dart
Widget _buildLoading(BuildContext context) {
  // El skeleton debe cubrir TODA la card, no solo partes
  return Column(
    children: [
      // Header skeleton
      MoleculeHeader(state: MoleculeHeaderState.loading),
      SizedBox(height: /* spacing token */),
      // Body skeleton
      MoleculeBody(state: MoleculeBodyState.loading),
      SizedBox(height: /* spacing token */),
      // Actions skeleton
      MoleculeActions(state: MoleculeActionsState.loading),
    ],
  );
}
```

## CHECKLIST PRE-ENTREGA

Todo lo de átomo y molécula MÁS:
- [ ] ¿Importa y usa moléculas + átomos del DS?
- [ ] ¿Usa Material para elevation/surface?
- [ ] ¿CADA criterio de aceptación de la HU está implementado?
- [ ] ¿Todos los callbacks de interacción están expuestos?
- [ ] ¿Considera responsividad (LayoutBuilder)?
- [ ] ¿Loading muestra skeleton COMPLETO (no solo partes)?
- [ ] ¿Error muestra indicadores claros?
- [ ] ¿InkWell/GestureDetector para interacción principal?
- [ ] ¿Accesibilidad: Semantics label con estado?
- [ ] ¿Si >200 líneas, fragmentado en archivos privados?
- [ ] ¿Textos visibles coinciden literalmente con Figma?
- [ ] ¿Riesgos de overflow están mitigados o alertados?
