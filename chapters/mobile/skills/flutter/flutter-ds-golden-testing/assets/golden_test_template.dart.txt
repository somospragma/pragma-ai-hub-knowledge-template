@Tags(['golden'])
import 'package:alchemist/alchemist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:{{package_name}}/{{package_name}}.dart';

void main() {
  // All variants (light)
  goldenTest(
    '{{DS_PREFIX}}ComponentName — all variants',
    fileName: 'component_name_all_variants',
    builder: () => GoldenTestGroup(
      scenarioConstraints: const BoxConstraints(maxWidth: 400),
      children: [
        for (final variant in {{DS_PREFIX}}ComponentNameVariant.values)
          GoldenTestScenario(
            name: variant.name,
            child: SizedBox(
              width: 327,
              height: 48,
              child: {{DS_PREFIX}}ComponentName(
                label: variant.name,
                variant: variant,
              ),
            ),
          ),
      ],
    ),
  );

  // All states
  goldenTest(
    '{{DS_PREFIX}}ComponentName — all states',
    fileName: 'component_name_all_states',
    builder: () => GoldenTestGroup(
      scenarioConstraints: const BoxConstraints(maxWidth: 400),
      children: [
        for (final state in {{DS_PREFIX}}ComponentNameState.values)
          GoldenTestScenario(
            name: state.name,
            child: SizedBox(
              width: 327,
              height: 48,
              child: {{DS_PREFIX}}ComponentName(label: state.name, state: state),
            ),
          ),
      ],
    ),
  );

  // Dark mode
  goldenTest(
    '{{DS_PREFIX}}ComponentName — dark',
    fileName: 'component_name_dark',
    builder: () => GoldenTestGroup(
      children: [
        GoldenTestScenario(
          name: 'dark default',
          child: Theme(
            data: ThemeData(
              brightness: Brightness.dark,
              // extensions: [/* dark theme extension */],
            ),
            child: const SizedBox(
              width: 327,
              height: 48,
              child: {{DS_PREFIX}}ComponentName(label: 'Dark'),
            ),
          ),
        ),
      ],
    ),
  );

  // Combination: variant × state
  goldenTest(
    '{{DS_PREFIX}}ComponentName — primary loading',
    fileName: 'component_name_primary_loading',
    builder: () => GoldenTestGroup(
      children: [
        GoldenTestScenario(
          name: 'primary loading',
          child: const SizedBox(
            width: 327,
            height: 48,
            child: {{DS_PREFIX}}ComponentName(
              label: '',
              variant: {{DS_PREFIX}}ComponentNameVariant.primary,
              state: {{DS_PREFIX}}ComponentNameState.loading,
            ),
          ),
        ),
      ],
    ),
  );
}
