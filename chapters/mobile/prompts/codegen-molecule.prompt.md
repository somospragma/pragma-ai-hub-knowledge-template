---
name: codegen-molecule
description: >
  Prompt para generar código Flutter de una molécula del Design System. Usar
  cuando el componente compone 2+ átomos, el plan técnico ya está definido y el
  DAG indica creación en esta fase. No usar como primer paso del pipeline.
agent: widget-developer
---

# Generación de Molécula Flutter

## Skills de referencia

- flutter-ds-theming-tokens
- flutter-ds-component-template
- flutter-ds-naming-conventions
- flutter-ds-lint-rules
- flutter-ds-folder-structure
- flutter-ds-widget-anatomy

## INSTRUCCIÓN

Genera el código Flutter completo de una molécula del Design System,
componiendo átomos existentes y/o recién creados.

## INPUTS QUE RECIBIRÁS

1. Nombre de la molécula a crear
2. Especificaciones visuales (de §1 y §2)
3. Lista de átomos que compone (con paths e interfaces)
4. Estados requeridos
5. Path de destino
6. Interfaz diseñada (de §4)
7. Contrato de textos y overflow (`§4.B`), obligatorio en `/new-component` y
   `/new-view`; puede declarar "sin textos/riesgos" si no aplica a la molécula

## DIFERENCIAS VS ÁTOMO

Una molécula:
- **IMPORTA y USA** átomos del DS (no recrea funcionalidad)
- **DELEGA** propiedades visuales a los átomos hijos
- **PROPAGA** estados a los átomos hijos cuando corresponde
- **COMPONE** layout (Row, Column, Stack) para organizar átomos
- **AGREGA** lógica de coordinación entre átomos

## REGLAS ESPECÍFICAS

### Comentarios en Código

- Prohibidos comentarios inline, de bloque y Dartdoc por defecto.
- Solo permitir comentario fundamental cuando no sea deducible del código
  (ej: workaround temporal, restricción regulatoria o decisión crítica de interoperabilidad).

### Composición Correcta

> Los comentarios del snippet son didácticos y no deben copiarse en el código generado.

```dart
// ✅ CORRECTO — Usar átomos existentes del DS
import 'package:{{package_name}}/atoms/text/{{ds_prefix_snake}}_text.dart';
import 'package:{{package_name}}/atoms/indicators/{{ds_prefix_snake}}_badge.dart';

// En build:
{{DS_PREFIX}}Text(text: title, variant: {{DS_PREFIX}}TextVariant.titleMedium)
{{DS_PREFIX}}Badge(label: badgeLabel, variant: {{DS_PREFIX}}BadgeVariant.info)

// ❌ INCORRECTO — Recrear funcionalidad de un átomo
Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
Container(
  padding: EdgeInsets.all(4),
  decoration: BoxDecoration(color: Colors.blue),
  child: Text(badgeLabel),
)
```

### Propagación de Estados

```dart
// Cuando la molécula está en loading, los átomos hijos también:
Widget _buildLoading(BuildContext context) {
  return Column(
    children: [
      {{DS_PREFIX}}Text(text: '', state: {{DS_PREFIX}}TextState.loading),
      {{DS_PREFIX}}Badge(label: '', state: {{DS_PREFIX}}BadgeState.loading),
    ],
  );
}
```

### Parámetros

```dart
// ✅ CORRECTO — Parámetros de datos
const {{DS_PREFIX}}CardHeader({
  required this.title,
  required this.subtitle,
  this.badgeLabel,     // nullable = no se muestra
  this.imageUrl,       // nullable = no se muestra
});

// ❌ INCORRECTO — Pasar widgets directos
const {{DS_PREFIX}}CardHeader({
  required this.titleWidget,
  required this.badgeWidget,
});
```

### Spacing entre Átomos

```dart
// ✅ Spacing con tokens
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    {{DS_PREFIX}}Text(text: title),
    SizedBox(height: {{DS_PREFIX}}Spacing.xs),  // Token de spacing
    {{DS_PREFIX}}Text(text: subtitle),
  ],
)
```

### Textos y Overflow

- Propagar textos literales a átomos hijos sin modificar copy.
- No crear labels, helper text, placeholders ni CTAs no presentes en Figma.
- En `Row`, envolver hijos textuales con `Flexible`/`Expanded` cuando compartan
  espacio con iconos, badges, botones o valores dinámicos.
- Usar `Wrap` solo cuando el contrato permita que el grupo horizontal salte de
  línea.
- Si faltan constraints detallados, aplicar la mitigación definida en `§4.B` y
  registrar alerta; no bloquear por ese único motivo.

## CHECKLIST PRE-ENTREGA

Todo lo del átomo MÁS:
- [ ] ¿Importa y usa átomos del DS (no recrea funcionalidad)?
- [ ] ¿Los imports son package imports correctos?
- [ ] ¿Propaga estados a los átomos hijos?
- [ ] ¿Los parámetros son de datos (no de widgets)?
- [ ] ¿El layout respeta el diseño de Figma (Row/Column/Stack)?
- [ ] ¿Los spacings entre átomos usan tokens?
- [ ] ¿Elementos opcionales son nullable y se ocultan cuando null?
- [ ] ¿Textos visibles coinciden literalmente con Figma?
- [ ] ¿Filas y textos largos tienen mitigación anti-overflow?
