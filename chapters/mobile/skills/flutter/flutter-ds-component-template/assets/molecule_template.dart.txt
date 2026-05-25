import 'package:flutter/material.dart';
// import 'package:{{package_name}}/atoms/text/{{ds_prefix_snake}}_text.dart';
// import 'package:{{package_name}}/atoms/indicators/{{ds_prefix_snake}}_badge.dart';

/// Description of molecule — composes [Atom1] and [Atom2].
///
/// Usage example:
/// ```dart
/// MoleculeName(
///   title: 'Title',
///   subtitle: 'Subtitle',
/// )
/// ```
class MoleculeName extends StatelessWidget {
  /// Creates a [MoleculeName].
  const MoleculeName({
    super.key,
    required this.title,
    required this.subtitle,
    this.badgeLabel,
    this.state = MoleculeNameState.default_,
    this.onAction,
  });

  /// Primary text.
  final String title;

  /// Secondary text.
  final String subtitle;

  /// Badge label (nullable = not shown).
  final String? badgeLabel;

  /// Visual state.
  final MoleculeNameState state;

  /// Main action callback.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      MoleculeNameState.loading => _buildLoading(context),
      MoleculeNameState.disabled => Opacity(
          opacity: 0.5,
          child: IgnorePointer(child: _buildDefault(context)),
        ),
      _ => _buildDefault(context),
    };
  }

  Widget _buildDefault(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ USE DS atoms — do not recreate
        // {{DS_PREFIX}}Text(text: title, variant: ...),
        // SizedBox(height: {{DS_PREFIX}}Spacing.xs),
        // {{DS_PREFIX}}Text(text: subtitle, variant: ...),
        // if (badgeLabel != null)
        //   {{DS_PREFIX}}Badge(label: badgeLabel!, variant: ...),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Column(
      children: [
        // Propagate loading to child atoms
        // {{DS_PREFIX}}Text(text: '', state: {{DS_PREFIX}}TextState.loading),
      ],
    );
  }
}

/// Possible states for [MoleculeName].
enum MoleculeNameState { default_, disabled, loading, focused, error }
