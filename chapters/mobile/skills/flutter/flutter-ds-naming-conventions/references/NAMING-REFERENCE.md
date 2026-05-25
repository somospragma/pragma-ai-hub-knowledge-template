# Naming Reference — Extended

## Golden File Names

| Format | Example |
|--------|---------|
| `[component]_[variant]_[state].png` | `ds_button_primary_default.png` |
| `[component]_all_variants.png` | `ds_button_all_variants.png` |
| `[component]_all_states.png` | `ds_button_all_states.png` |
| `[component]_dark.png` | `ds_button_dark.png` |

## Branch Naming

| Type | Format | Example |
|------|--------|---------|
| DS pipeline (configurable) | `{naming.branch_prefix}[slug]` | `feat/ds-product-card` |
| App view (/new-view) | `{naming.view_branch_prefix}[slug]` | `feat/app-product-detail` |

## Commit Types (Conventional Commits)

| Type | Usage | Example |
|------|-------|---------|
| `feat:` | New component | `feat: add {{DS_PREFIX}}Badge atom component` |
| `test:` | New tests | `test: add widget and golden tests for Badge` |
| `docs:` | Documentation | `docs: add widgetbook stories for Badge` |
| `fix:` | Bug fix | `fix: Badge color token in disabled state` |
| `refactor:` | Refactor | `refactor: extract Badge colors to resolver` |

## Full Figma → Dart Mapping

| Figma Name | Dart Name |
|-----------|-----------|
| `Card / Product` | `{{DS_PREFIX}}ProductCard` (organism) |
| `Badge` | `{{DS_PREFIX}}Badge` (atom) |
| `Icon / Close` | `{{DS_PREFIX}}Icon` with `Icons.close` |
| `Button / Primary / Medium` | `{{DS_PREFIX}}Button(variant: .primary, size: .md)` |
| `Input / Text / Default` | `{{DS_PREFIX}}TextField(state: .default_)` |
