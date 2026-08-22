import 'package:flutter/material.dart';

import '../config/app_theme.dart';

class DraggableSheet extends StatelessWidget {
  final Widget child;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final DraggableScrollableController? controller;
  final bool snap;
  final List<double>? snapSizes;

  const DraggableSheet({
    super.key,
    required this.child,
    this.initialChildSize = 0.35,
    this.minChildSize = 0.08,
    this.maxChildSize = 0.92,
    this.controller,
    this.snap = true,
    this.snapSizes,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedSnaps = snapSizes ??
        <double>{
          minChildSize,
          initialChildSize,
          maxChildSize,
        }.toList()
          ..sort();

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      controller: controller,
      snap: snap,
      snapSizes: resolvedSnaps,
      shouldCloseOnMinExtent: false,
      builder: (context, scrollController) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle — also toggles expand/collapse on tap
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final c = controller;
                  if (c == null || !c.isAttached) return;
                  final mid = initialChildSize;
                  final target =
                      c.size > (mid + minChildSize) / 2 ? minChildSize : mid;
                  c.animateTo(
                    target,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 8),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black26,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PrimaryScrollController(
                  controller: scrollController,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
