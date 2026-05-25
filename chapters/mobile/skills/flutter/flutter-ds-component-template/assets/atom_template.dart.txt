import 'package:flutter/material.dart';
// Tokens imports per project.config.yaml

/// Brief one-line description of the atom.
///
/// Usage example:
/// ```dart
/// {{DS_PREFIX}}ComponentName(
///   requiredParam: value,
///   onAction: () {},
/// )
/// ```
class {{DS_PREFIX}}ComponentName extends StatelessWidget {
  /// Creates a [{{DS_PREFIX}}ComponentName].
  const {{DS_PREFIX}}ComponentName({
    super.key,
    required this.requiredParam,
    this.optionalParam = defaultValue,
    this.state = {{DS_PREFIX}}ComponentNameState.default_,
    this.variant = {{DS_PREFIX}}ComponentNameVariant.primary,
    this.onAction,
  });

  /// Description of the required parameter.
  final String requiredParam;

  /// Description of the optional parameter with default.
  final String optionalParam;

  /// Current visual state of the component.
  final {{DS_PREFIX}}ComponentNameState state;

  /// Visual variant of the component.
  final {{DS_PREFIX}}ComponentNameVariant variant;

  /// Callback when the main action is triggered.
  final VoidCallback? onAction;

  bool get _isInteractive =>
      state != {{DS_PREFIX}}ComponentNameState.disabled &&
      state != {{DS_PREFIX}}ComponentNameState.loading;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      {{DS_PREFIX}}ComponentNameState.loading => _buildLoading(context),
      {{DS_PREFIX}}ComponentNameState.disabled => Opacity(
          opacity: 0.5,
          child: IgnorePointer(child: _buildDefault(context)),
        ),
      _ => _buildDefault(context),
    };
  }

  Widget _buildDefault(BuildContext context) {
    // TODO: Implement main layout using tokens
    return const Placeholder();
  }

  Widget _buildLoading(BuildContext context) {
    // TODO: Implement skeleton/shimmer using shimmer tokens
    return const Placeholder();
  }

  Color _resolveBackgroundColor(BuildContext context) {
    return switch (variant) {
      {{DS_PREFIX}}ComponentNameVariant.primary => Colors.transparent,
      {{DS_PREFIX}}ComponentNameVariant.secondary => Colors.transparent,
    };
  }
}

/// Possible states for [{{DS_PREFIX}}ComponentName].
enum {{DS_PREFIX}}ComponentNameState {
  /// Default interactive state.
  default_,
  /// Disabled, no interaction.
  disabled,
  /// Loading, shows skeleton.
  loading,
  /// Accessibility focus.
  focused,
  /// Error state.
  error,
}

/// Visual variants for [{{DS_PREFIX}}ComponentName].
enum {{DS_PREFIX}}ComponentNameVariant {
  /// Primary variant.
  primary,
  /// Secondary variant.
  secondary,
}
