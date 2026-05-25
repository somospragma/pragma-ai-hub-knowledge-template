# {{DS_PREFIX}}ComponentName

> Brief 1-2 line description of the component.

## Preview

| Variant | Light | Dark |
|---------|-------|------|
| Primary | [screenshot] | [screenshot] |
| Secondary | [screenshot] | [screenshot] |

## Usage

```dart
{{DS_PREFIX}}ComponentName(
  title: 'Product Name',
  price: '\$99.99',
  variant: {{DS_PREFIX}}ComponentNameVariant.primary,
  onTap: () {
    // Handle tap
  },
)
```

## API

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `title` | `String` | ✅ | — | Primary title |
| `price` | `String` | ✅ | — | Formatted price |
| `variant` | `Variant` | ❌ | `.primary` | Visual variant |
| `state` | `State` | ❌ | `.default_` | Visual state |
| `onTap` | `VoidCallback?` | ❌ | `null` | Tap callback |

### Enums

#### {{DS_PREFIX}}ComponentNameVariant
| Value | Description |
|-------|-------------|
| `primary` | Primary variant |
| `secondary` | Secondary variant |

#### {{DS_PREFIX}}ComponentNameState
| Value | Description |
|-------|-------------|
| `default_` | Default state |
| `disabled` | No interaction, reduced opacity |
| `loading` | Shows skeleton |
| `error` | Error indicator |

## Tokens Used

| Category | Token | Usage |
|----------|-------|-------|
| Color | `colorScheme.surface` | Card background |
| Color | `colorScheme.onSurface` | Primary text |
| Spacing | `{{DS_PREFIX}}Spacing.m` | Internal padding |
| Radius | `{{DS_PREFIX}}BorderRadius.l` | Rounded corners |
| Elevation | `ElevationTokens.level1` | Card shadow |

## Composition

```
ProductCard (Organism)
├── CardHeader (Molecule)
│   ├── {{DS_PREFIX}}Image (Atom)
│   └── {{DS_PREFIX}}Badge (Atom)
├── CardBody (Molecule)
│   └── {{DS_PREFIX}}Text (Atom) ×2
└── CardActions (Molecule)
    └── {{DS_PREFIX}}Button (Atom)
```

## States

| State | Behavior |
|-------|----------|
| Default | Interactive, normal colors |
| Disabled | Opacity 0.5, no interaction |
| Loading | Complete skeleton |
| Error | Error indicators visible |

## Figma

- **Design**: [Figma URL]
- **Atomic level**: Organism

## Anti-patterns

- ❌ Do not use for lists of 10+ items (use `ListView`)
- ❌ Do not nest inside another `ProductCard`
- ❌ Do not pass widgets as parameters (use data)
