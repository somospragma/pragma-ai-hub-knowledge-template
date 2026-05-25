import 'package:flutter/material.dart';
// Imports of molecules and atoms

/// Description of organism — complete UI section.
///
/// Fulfills HU: [reference].
///
/// Usage example:
/// ```dart
/// OrganismName(
///   title: 'Product Name',
///   price: '\$99.99',
///   onTap: () {},
///   onAddToCart: () {},
/// )
/// ```
class OrganismName extends StatelessWidget {
  /// Creates an [OrganismName].
  const OrganismName({
    super.key,
    required this.title,
    required this.price,
    this.imageUrl,
    this.badgeLabel,
    this.state = OrganismNameState.default_,
    this.onTap,
    this.onAddToCart,
    this.onToggleFavorite,
  });

  /// Product name.
  final String title;

  /// Formatted price.
  final String price;

  /// Image URL (nullable = not shown).
  final String? imageUrl;

  /// Badge label (nullable = not shown).
  final String? badgeLabel;

  /// Visual state of the organism.
  final OrganismNameState state;

  /// Callback when tapping the full organism.
  final VoidCallback? onTap;

  /// Callback for add to cart action.
  final VoidCallback? onAddToCart;

  /// Callback for toggling favorite.
  final ValueChanged<bool>? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0, // Use ElevationTokens.level1
      borderRadius: BorderRadius.circular(0), // Use {{DS_PREFIX}}BorderRadius.l
      clipBehavior: Clip.antiAlias,
      child: switch (state) {
        OrganismNameState.loading => _buildLoading(context),
        OrganismNameState.disabled => Opacity(
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

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compose molecules and atoms here
          ],
        );
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    // Complete skeleton of the organism
    return const Placeholder();
  }
}

/// States for [OrganismName].
enum OrganismNameState { default_, disabled, loading, focused, error }
