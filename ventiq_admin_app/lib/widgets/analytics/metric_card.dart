import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Color? backgroundColor;
  final double? changePercent;
  final String? changeLabel;
  final VoidCallback? onTap;
  final bool isLoading;
  final String? unit;
  final Widget? customContent;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.backgroundColor,
    this.changePercent,
    this.changeLabel,
    this.onTap,
    this.isLoading = false,
    this.unit,
    this.customContent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: backgroundColor ?? Colors.white,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10), // Reduced from 12
          child: isLoading ? _buildLoadingState() : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color.withOpacity(0.5), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (customContent != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // ✅ Agregar esto
        children: [
          _buildHeader(),
          const SizedBox(height: 8), // ✅ Reducir espacio
          customContent!,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // ✅ Tamaño mínimo
      children: [
        _buildHeader(),
        const SizedBox(height: 6), // ✅ Menos espacio
        _buildValue(),
        if (subtitle != null || changePercent != null) ...[
          const SizedBox(height: 2), // ✅ Menos espacio
          _buildFooter(),
        ],
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6), // ✅ Menos padding
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6), // ✅ Menos radio
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValue() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: FittedBox(
            // ✅ Evita overflow
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20, // ✅ Más pequeño
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
          ),
        ),
        // ...
      ],
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        if (changePercent != null) ...[
          _buildTrendIndicator(),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            subtitle ?? changeLabel ?? '',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildTrendIndicator() {
    if (changePercent == null) return const SizedBox.shrink();

    final isPositive = changePercent! > 0;
    final isNeutral = changePercent == 0;

    Color trendColor;
    IconData trendIcon;

    if (isNeutral) {
      trendColor = Colors.grey;
      trendIcon = Icons.remove;
    } else if (isPositive) {
      trendColor = Colors.green;
      trendIcon = Icons.trending_up;
    } else {
      trendColor = Colors.red;
      trendIcon = Icons.trending_down;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: trendColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trendIcon, size: 12, color: trendColor),
          const SizedBox(width: 2),
          Text(
            '${changePercent!.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              color: trendColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Widget especializado para métricas de inventario
class InventoryMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final String healthLevel;
  final VoidCallback? onTap;
  final bool isLoading;

  const InventoryMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    required this.healthLevel,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return MetricCard(
      title: title,
      value: value,
      icon: icon,
      color: color,
      subtitle: subtitle,
      onTap: onTap,
      isLoading: isLoading,
      customContent: isLoading ? null : _buildHealthIndicator(),
    );
  }

  Widget _buildHealthIndicator() {
    Color healthColor;
    switch (healthLevel.toLowerCase()) {
      case 'excelente':
      case 'saludable':
        healthColor = Colors.green;
        break;
      case 'buena':
      case 'precaución':
        healthColor = Colors.orange;
        break;
      case 'regular':
      case 'alerta':
        healthColor = Colors.red.shade300;
        break;
      case 'crítico':
      case 'lenta':
        healthColor = Colors.red;
        break;
      default:
        healthColor = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          // ✅ Evita overflow
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 18, // ✅ Más pequeño
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: healthColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              // ✅ Agregar Expanded principal
              child: Row(
                children: [
                  Flexible(
                    // Changed from Text to Flexible
                    child: Text(
                      healthLevel,
                      style: TextStyle(
                        fontSize: 11, // Reduced from 12
                        color: healthColor,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      // ✅ Expanded anidado para el subtítulo
                      child: Text(
                        '• $subtitle',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        overflow:
                            TextOverflow.ellipsis, // ✅ Truncar si es muy largo
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Widget para alertas críticas
class AlertMetricCard extends StatelessWidget {
  final int alertCount;
  final String alertType;
  final VoidCallback? onTap;
  final bool isLoading;

  const AlertMetricCard({
    super.key,
    required this.alertCount,
    required this.alertType,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    Color alertColor;
    IconData alertIcon;

    switch (alertType.toLowerCase()) {
      case 'crítico':
      case 'critical':
        alertColor = Colors.red;
        alertIcon = Icons.error;
        break;
      case 'advertencia':
      case 'warning':
        alertColor = Colors.orange;
        alertIcon = Icons.warning;
        break;
      default:
        alertColor = Colors.blue;
        alertIcon = Icons.info;
    }

    return MetricCard(
      title: 'Alertas $alertType',
      value: alertCount.toString(),
      icon: alertIcon,
      color: alertColor,
      backgroundColor: alertCount > 0 ? alertColor.withOpacity(0.05) : null,
      subtitle:
          alertCount == 0
              ? 'Todo en orden'
              : '$alertCount ${alertCount == 1 ? 'producto requiere' : 'productos requieren'} atención',
      onTap: onTap,
      isLoading: isLoading,
    );
  }
}
