---
name: codegen-atom
description: >
  Prompt para generar código Flutter de un átomo del Design System. Usar cuando
  el componente ya fue clasificado como átomo, existe plan técnico aprobado y
  el DAG indica que esta pieza debe implementarse en la fase actual. No usar si
  aún faltan análisis, inventario o arquitectura.
agent: widget-developer
---

# Generación de Átomo Flutter

## Skills de referencia

- flutter-ds-theming-tokens
- flutter-ds-component-template
- flutter-ds-naming-conventions
- flutter-ds-lint-rules
- flutter-ds-widget-anatomy
- flutter-ds-a11y-semantics

## INSTRUCCIÓN

Genera el código Flutter completo de un componente atómico del Design System.

## INPUTS QUE RECIBIRÁS

1. Nombre del átomo a crear
2. Especificaciones visuales (de §1 y §2)
3. Estados requeridos
4. Variantes requeridas
5. Path de destino (de §3)
6. Interfaz diseñada (de §4)
7. Contrato de textos y overflow (`§4.B`), obligatorio en `/new-component` y
   `/new-view`; puede declarar "sin textos/riesgos" si no aplica al átomo

## REGLAS ABSOLUTAS

### Tokens
- TODO color → token semántico (según `project.config.yaml` → `tokens.access_method`)
- TODA tipografía → token de texto/typography
- TODO spacing → token de spacing (constantes estáticas)
- TODO radius → token de radius
- TODA elevación → token de elevation
- **CERO valores mágicos**. Si no hay token → generar ⚠️ ALERTA

### Template
- Usar SIEMPRE el template de Átomo del skill `flutter-ds-component-template`
- Seguir la anatomía del skill `flutter-ds-widget-anatomy`

### Naming
- Clase: `{{DS_PREFIX}}[Nombre]` en PascalCase
- Archivo: `{{ds_prefix_snake}}_[nombre].dart` en snake_case
- Enum de estado: `{{DS_PREFIX}}[Nombre]State`
- Enum de variante: `{{DS_PREFIX}}[Nombre]Variant`
- Enum de tamaño: `{{DS_PREFIX}}[Nombre]Size`

### Clean Code
- Código autoexplicativo por nombres y estructura
- Prohibidos comentarios inline/bloque/Dartdoc por defecto
- Solo permitir comentario fundamental cuando no sea deducible del código
- Constructor `const` siempre que posible
- Named parameters siempre
- 1 widget público por archivo
- Métodos privados `_build*` para lógica de estados
- Métodos privados `_resolve*` para resolver tokens por variante/estado

### Accesibilidad
- Consultar `flutter-ds-a11y-semantics`
- `Semantics` labels en elementos interactivos
- Áreas de toque mínimo 48x48

### Textos y Overflow
- Usar textos visibles solo desde `§1.1b`/`§2`/`§4.B`.
- No inventar, traducir, corregir ni reescribir labels.
- Si el átomo renderiza texto dentro de un contenedor limitado, respetar
  `maxLines`/`overflow` solo si Figma o `§4.B` lo indican.
- No fijar width/height para resolver overflow salvo que Figma marque FIXED.

## ESTRUCTURA DEL ARCHIVO

```dart
import 'package:flutter/material.dart';
import 'package:{{package_name}}/tokens/...';

class {{DS_PREFIX}}[Nombre] extends StatelessWidget {
  const {{DS_PREFIX}}[Nombre]({super.key, required this.param, ...});

  final Type param;

  bool get _isInteractive => ...;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ...State.loading => _buildLoading(context),
      ...State.disabled => Opacity(opacity: 0.5, child: IgnorePointer(child: _buildDefault(context))),
      _ => _buildDefault(context),
    };
  }

  Widget _buildDefault(BuildContext context) { ... }
  Widget _buildLoading(BuildContext context) { ... }

  Color _resolveBackgroundColor(BuildContext context) { ... }
  EdgeInsets _resolvePadding() { ... }
}

enum {{DS_PREFIX}}[Nombre]State { default_, disabled, loading, focused, error }
enum {{DS_PREFIX}}[Nombre]Variant { primary, secondary }
enum {{DS_PREFIX}}[Nombre]Size { sm, md, lg }
```

## CHECKLIST PRE-ENTREGA

- [ ] ¿Usa SOLO tokens del DS para valores visuales?
- [ ] ¿Sin comentarios inline/bloque/Dartdoc salvo excepción fundamental?
- [ ] ¿Constructor es `const`?
- [ ] ¿Todos los parámetros son named?
- [ ] ¿Implementa TODOS los estados requeridos?
- [ ] ¿Implementa TODAS las variantes requeridas?
- [ ] ¿`build()` delega a métodos privados?
- [ ] ¿Disabled usa `Opacity` + `IgnorePointer`?
- [ ] ¿Loading muestra skeleton/shimmer con tokens?
- [ ] ¿Callbacks son null-safe?
- [ ] ¿Compila (imports correctos, tipos correctos)?
- [ ] ¿Accesibilidad: Semantics labels?
- [ ] ¿1 widget público por archivo?
- [ ] ¿Package imports (no relativos)?
- [ ] ¿Textos visibles son literales del contrato Figma?
- [ ] ¿Overflow mitigado sin alterar copy ni layout base?
