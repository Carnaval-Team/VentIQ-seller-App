import 'package:flutter/material.dart';

/// Keeps the search card inside its sliver's paint bounds while extending the
/// indigo background behind its top edge. No negative translation is needed:
/// the search remains visible and hit-testable even while scrolling.
class HomeHeroHeader extends StatelessWidget {
  final Widget topBar;
  final Widget searchCard;

  const HomeHeroHeader({
    super.key,
    required this.topBar,
    required this.searchCard,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        topBar,
        Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 26,
              child: ColoredBox(color: Color(0xFF3E4E80)),
            ),
            // Painted last, the entire card (and its shadow) is in front.
            searchCard,
          ],
        ),
      ],
    );
  }
}
