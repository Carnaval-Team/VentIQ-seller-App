import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B1220), Color(0xFF0F1B2D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        _GlowBlob(
          size: 220,
          offset: const Offset(-120, -80),
          color: AppColors.accentStrong.withOpacity(0.18),
        ),
        _GlowBlob(
          size: 260,
          offset: const Offset(190, -40),
          color: AppColors.accent.withOpacity(0.16),
        ),
        _GlowBlob(
          size: 280,
          offset: const Offset(150, 520),
          color: AppColors.accentWarm.withOpacity(0.12),
        ),
        child,
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.size,
    required this.offset,
    required this.color,
  });

  final double size;
  final Offset offset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.45),
              blurRadius: 80,
              spreadRadius: 10,
            ),
          ],
        ),
      ),
    );
  }
}
