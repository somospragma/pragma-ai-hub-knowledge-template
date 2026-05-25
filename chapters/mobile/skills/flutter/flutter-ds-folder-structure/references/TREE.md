# Full Directory Tree

```
{{package_name}}/
├── lib/
│   ├── {{package_name}}.dart
│   └── src/
│       ├── atoms/
│       │   ├── buttons/
│       │   │   ├── {{ds_prefix_snake}}_button.dart
│       │   │   ├── {{ds_prefix_snake}}_icon_button.dart
│       │   │   └── {{ds_prefix_snake}}_text_button.dart
│       │   ├── inputs/
│       │   │   ├── {{ds_prefix_snake}}_text_field.dart
│       │   │   ├── {{ds_prefix_snake}}_checkbox.dart
│       │   │   ├── {{ds_prefix_snake}}_radio.dart
│       │   │   └── {{ds_prefix_snake}}_switch.dart
│       │   ├── text/
│       │   │   └── {{ds_prefix_snake}}_text.dart
│       │   ├── images/
│       │   │   ├── {{ds_prefix_snake}}_image.dart
│       │   │   ├── {{ds_prefix_snake}}_avatar.dart
│       │   │   └── {{ds_prefix_snake}}_icon.dart
│       │   ├── indicators/
│       │   │   ├── {{ds_prefix_snake}}_badge.dart
│       │   │   ├── {{ds_prefix_snake}}_tag.dart
│       │   │   ├── {{ds_prefix_snake}}_spinner.dart
│       │   │   └── {{ds_prefix_snake}}_progress_bar.dart
│       │   ├── feedback/
│       │   │   ├── {{ds_prefix_snake}}_skeleton.dart
│       │   │   └── {{ds_prefix_snake}}_shimmer.dart
│       │   └── dividers/
│       │       └── {{ds_prefix_snake}}_divider.dart
│       │
│       ├── molecules/
│       │   ├── cards/
│       │   │   ├── card_header.dart
│       │   │   ├── card_body.dart
│       │   │   └── card_actions.dart
│       │   ├── list_items/
│       │   │   └── {{ds_prefix_snake}}_list_tile.dart
│       │   ├── search/
│       │   │   └── {{ds_prefix_snake}}_search_bar.dart
│       │   ├── forms/
│       │   │   └── labeled_input.dart
│       │   ├── navigation/
│       │   │   ├── {{ds_prefix_snake}}_tab_item.dart
│       │   │   └── {{ds_prefix_snake}}_breadcrumb.dart
│       │   └── feedback/
│       │       ├── {{ds_prefix_snake}}_alert_inline.dart
│       │       └── {{ds_prefix_snake}}_toast.dart
│       │
│       ├── organisms/
│       │   ├── cards/
│       │   │   ├── product_card.dart
│       │   │   ├── info_card.dart
│       │   │   └── action_card.dart
│       │   ├── navigation/
│       │   │   ├── {{ds_prefix_snake}}_app_bar.dart
│       │   │   ├── {{ds_prefix_snake}}_bottom_nav.dart
│       │   │   └── {{ds_prefix_snake}}_drawer.dart
│       │   ├── forms/
│       │   │   └── {{ds_prefix_snake}}_form_section.dart
│       │   ├── lists/
│       │   │   └── {{ds_prefix_snake}}_grouped_list.dart
│       │   └── feedback/
│       │       ├── {{ds_prefix_snake}}_dialog.dart
│       │       ├── {{ds_prefix_snake}}_bottom_sheet.dart
│       │       └── {{ds_prefix_snake}}_snackbar.dart
│       │
│       ├── tokens/
│       │   ├── spacing_tokens.dart
│       │   ├── radius_tokens.dart
│       │   ├── elevation_tokens.dart
│       │   └── opacity_tokens.dart
│       │
│       └── theme/
│           ├── {{ds_prefix_snake}}_theme.dart
│           ├── {{ds_prefix_snake}}_colors.dart
│           └── {{ds_prefix_snake}}_typography.dart
│
├── test/
│   ├── atoms/
│   │   └── [subfolder]/
│   │       ├── [component]_test.dart
│   │       └── [component]_golden_test.dart
│   ├── molecules/
│   │   └── [subfolder]/
│   │       ├── [component]_test.dart
│   │       └── [component]_golden_test.dart
│   ├── organisms/
│   │   └── [subfolder]/
│   │       ├── [component]_test.dart
│   │       └── [component]_golden_test.dart
│   └── helpers/
│       └── pump_app.dart
│
├── widgetbook/
│   ├── atoms/
│   │   └── [subfolder]/
│   │       └── [component]_use_case.dart
│   ├── molecules/
│   │   └── [subfolder]/
│   │       └── [component]_use_case.dart
│   └── organisms/
│       └── [subfolder]/
│           └── [component]_use_case.dart
│
│  ── APP-LEVEL (fuera del paquete DS, en el repo app) ──
│
├── lib/src/presentation/
│   ├── views/
│   │   └── [view]/
│   │       ├── [view]_view.dart
│   │       └── _[view]_section.dart
│   └── widgets/
│       └── [shared_view_widget].dart
│
├── test/presentation/
│   ├── views/
│   │   └── [view]/
│   │       ├── [view]_view_test.dart
│   │       └── [view]_view_golden_test.dart
│   └── widgets/
│       └── [shared_view_widget]_test.dart
│
├── widgetbook/features/
│   └── [feature]/
│       └── [view]/
│           └── [view]_use_case.dart
│
└── [pipeline.output_dir]/
    ├── [pipeline.log_file]
    └── [pipeline.spec_file]
```
