---
name: codegen-view
description: >
  Prompt para generar una vista o pantalla Flutter completa en la capa de
  presentación de la app, componiendo componentes DS existentes y respetando el
  contrato de arquitectura y topología.
agent: widget-developer
---

# Generación de Vista/Pantalla Flutter (Determinista)

## Skills de referencia

- flutter-ds-theming-tokens
- flutter-ds-folder-structure
- flutter-ds-naming-conventions
- flutter-ds-widget-anatomy
- flutter-ds-responsive-layout
- flutter-ds-a11y-semantics
- flutter-ds-component-template
- flutter-bloc-pattern
- flutter-navigation-strategy
- flutter-errors

## INSTRUCCIÓN

Genera el código Flutter de una vista/pantalla que compone organismos,
moléculas y átomos del Design System existentes.

## Handoff mínimo obligatorio

Antes de implementar, validar que recibes:

1. `workflow`, `phase_id`, `mode`.
2. `project_root`.
3. `topology` (`repo_mode`, `feature_location_mode`, `shared_core_mode`, `ds_mode`).
4. `target` (`package_name`, `package_path`, `target_root`, `feature_root`).
5. `execution_context` (`melos_enabled`, `melos_root`, `target_scope`).
6. `contracts_context` (`generation_scope`, `contracts_policy`).
7. `architecture_refs` (`contract_path`, `mermaid_path` opcional).
8. `input_refs` y `output_paths`.

Si falta cualquiera de estos campos, devolver `blocked_input`.

## Regla de fuente de verdad (MCP)

- Este prompt NO consulta Figma MCP.
- Debe implementar usando únicamente `§1`, `§2`, `§3`, `§4` y contratos de
  arquitectura/dependencias entregados por fases previas.
- Si la spec no contiene información suficiente para implementación determinista,
  devolver `blocked_input`.
- Textos visibles, labels, placeholders, títulos, CTAs y mensajes deben salir
  literalmente de `§1.1b`, `§2` o `§4.B`; no crear copy adicional.
- `loading`, `empty`, `error` y `populated` siempre deben existir. Si Figma no
  define alguno, usar el fallback estándar definido en `§4`/`§4.B` y registrar
  alerta para el desarrollador.
- Constraints incompletos de Figma no bloquean por sí solos: aplicar mitigación
  anti-overflow conservadora y registrar alerta.

## INPUTS FUNCIONALES

1. Nombre de vista/pantalla.
2. `§1` completo (incluye `§1.4b`, `§1.3b` y `§1.3c` si existen vectores/anotaciones Development).
3. `§2`, `§3`, `§4` (incluye `§4.A` si hay contrato de vectores).
   También debe incluir `§4.B` para textos y overflow.
4. HU y criterios de aceptación.
5. Estados requeridos: `loading`, `empty`, `error`, `populated`.
6. Reglas de navegación.
7. Contrato de arquitectura.

## Fuente de verdad de arquitectura

1. Usar primero `.copilot/config/ARCHITECTURE-CONTRACT.yaml`.
2. Usar `.copilot/config/ARCHITECTURE.md` solo como soporte visual.
3. Si hay conflicto, prevalece el YAML.

## Reglas por política de generación

### `generation_scope = presentation_only`

- Solo crear código de presentación.
- Prohibido crear implementaciones de domain/data.
- Permitido usar callbacks y modelos de entrada adaptadores de UI.

### `generation_scope = full_feature`

- Este prompt sigue siendo de presentación.
- Si se necesitan domain/data, dejarlos como dependencia declarada en contratos,
  no implementarlos aquí.

## Reglas por `contracts_policy`

### `optional`

- Continuar aunque no existan contratos de domain/data.
- Resolver con callbacks y estados de vista.

### `generate`

- Exigir referencia a `§4.C` (contratos mínimos generados por arquitecto).
- Consumir esos contratos en la vista sin crear implementación real.
- Si `§4.C` no existe, devolver `blocked_input`.

### `required`

- Exigir contratos domain/data existentes y referenciados en spec.
- Si faltan referencias, devolver `blocked_input`.

## Diferencias vs componente DS

- La vista no es componente DS.
- No lleva prefijo `{{DS_PREFIX}}`.
- No se exporta en barrel DS.
- Vive en `structure.views_path` (default `lib/src/presentation/views`).
- Widgets privados de vista en `structure.view_widgets_path` (default
  `lib/src/presentation/widgets`).

## Estructura esperada

```dart
import 'package:flutter/material.dart';
import 'package:{{package_name}}/{{package_name}}.dart';

class [NombreView] extends StatelessWidget {
  const [NombreView]({super.key});

  static const routeName = '/[route-name]';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return switch (viewState) {
      ViewState.loading => _buildLoading(context),
      ViewState.empty => _buildEmpty(context),
      ViewState.error => _buildError(context),
      ViewState.populated => _buildContent(context),
    };
  }
}
```

## Estados obligatorios

- `loading`: skeletons de organismos DS.
- `empty`: diseño/copy Figma si existe; si no, fallback estándar alertado.
- `error`: diseño/copy Figma si existe; si no, fallback estándar alertado.
- `populated`: composición final.
- Estados especiales derivados de anotaciones `Development` (si aplican).

## Reglas de implementación

1. Reutilizar componentes DS existentes; no duplicar widgets.
2. Seguir patrón de estado/navegación/DI del contrato.
3. Sin lógica de negocio en la vista.
4. Si la vista >300 líneas, fragmentar en widgets privados.
5. No escribir fuera de `target.target_root`.
6. Implementar reglas/alertas/comportamientos especiales definidos en `§1.3b`.
7. Prohibidos comentarios inline/bloque/Dartdoc por defecto; solo permitir
   comentario fundamental no deducible del código.
8. Preservar los textos literales del contrato; no traducir, corregir ni
   reemplazar copy con valores "más realistas".
9. No agregar UI o UX adicional que no venga de Figma/metadatos/anotaciones.

## Reglas anti-overflow en vista

1. Aplicar `SafeArea` en la pantalla completa salvo contraindicación en Figma.
2. Elegir el patrón de scroll definido en `§4.V`; si no está completo, usar una
   opción conservadora que evite overflow vertical y registrar alerta.
3. En filas con texto + iconos/botones/badges, envolver el texto con
   `Flexible`/`Expanded` según composición.
4. Usar `Wrap` para chips, acciones secundarias o grupos horizontales que puedan
   saltar línea sin romper el diseño.
5. No usar `maxLines`/`ellipsis` salvo que Figma o `§4.B` indiquen truncamiento.
6. No introducir anchos fijos para "hacer calzar" el diseño; usar constraints
   flexibles y tokens.

## Reglas de vectores en vista (cuando aplique)

1. Consumir `§1.3c` + `§4.A` como fuente de verdad para vectores.
2. Respetar estrategia por elemento:
   - `DS_ICON` -> ícono/componente DS
   - `SVG_ASSET` -> renderer vectorial + constante de recurso
   - `PNG_ASSET` -> fallback raster definido en contrato
3. No hardcodear rutas de asset en la vista.
4. Mantener tamaño/color/semántica según contrato.
5. Si falta contrato para un vector crítico, devolver `blocked_input`.

## Checklist pre-entrega

- [ ] Scaffold y estructura de pantalla correctas.
- [ ] Estados `loading/empty/error/populated` implementados.
- [ ] Fallbacks de estado sin Figma están alertados.
- [ ] Navegación crítica implementada.
- [ ] Sin prefijo DS.
- [ ] Criterios HU cubiertos.
- [ ] Reglas de contratos/política respetadas.
- [ ] Vectores críticos implementados según `§1.3c`/`§4.A`.
- [ ] Textos visibles coinciden literalmente con `§1.1b`/`§4.B`.
- [ ] Riesgos de overflow de `§1.1c`/`§4.B` mitigados o alertados.
