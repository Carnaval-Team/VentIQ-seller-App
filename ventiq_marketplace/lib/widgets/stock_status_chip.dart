import 'package:flutter/material.dart';
import '../config/app_theme.dart';

enum StockStatusType { available, low, out }

class StockStatusChip extends StatelessWidget {
  final int stock;
  final int lowStockThreshold;
  final bool showQuantity;
  final bool fullWidth;
  final double fontSize;
  final double iconSize;
  final EdgeInsets padding;
  final double borderRadius;
  final double? maxWidth;

  const StockStatusChip({
    super.key,
    required this.stock,
    this.lowStockThreshold = 10,
    this.showQuantity = false,
    this.fullWidth = false,
    this.fontSize = 11,
    this.iconSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    this.borderRadius = 10,
    this.maxWidth = 120,
  });

  StockStatusType get _type {
    if (stock <= 0) return StockStatusType.out;
    if (stock <= lowStockThreshold) return StockStatusType.low;
    return StockStatusType.available;
  }

  Color get _color {
    switch (_type) {
      case StockStatusType.available:
        return AppTheme.successColor;
      case StockStatusType.low:
        return AppTheme.warningColor;
      case StockStatusType.out:
        return AppTheme.errorColor;
    }
  }

  String get _label {
    switch (_type) {
      case StockStatusType.available:
        return 'Disponible';
      case StockStatusType.low:
        return 'Casi agotado';
      case StockStatusType.out:
        return 'Agotado';
    }
  }

  IconData get _icon {
    switch (_type) {
      case StockStatusType.available:
        return Icons.check_circle_rounded;
      case StockStatusType.low:
        return Icons.warning_rounded;
      case StockStatusType.out:
        return Icons.cancel_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = showQuantity && stock > 0 ? '$_label ($stock)' : _label;

    final content = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: fullWidth
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(_icon, size: iconSize, color: _color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: _color,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );

    final inner = maxWidth == null
        ? content
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: content,
          );

    return Container(
      width: fullWidth ? double.infinity : null,
      padding: padding,
      decoration: BoxDecoration(
        color: _color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: _color.withOpacity(0.22), width: 1),
      ),
      child: inner,
    );
  }
}
