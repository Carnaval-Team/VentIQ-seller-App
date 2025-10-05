import 'package:flutter/material.dart';
import '../../config/app_colors.dart';

class SupplierAlertsWidget extends StatelessWidget {
  final List<dynamic> alerts;
  final bool isLoading;

  const SupplierAlertsWidget({
    super.key,
    required this.alerts,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (alerts.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.success, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Estado del Proveedor',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified, color: AppColors.success, size: 32),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Todo en orden',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'No hay alertas activas para este proveedor',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: AppColors.warning, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Alertas del Proveedor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${alerts.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...alerts.map((alert) => _buildAlertItem(alert)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertItem(dynamic alert) {
    if (alert == null) return const SizedBox.shrink();
    
    String alertText = alert.toString();
    AlertType alertType = _getAlertType(alertText);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alertType.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alertType.color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alertType.icon,
            color: alertType.color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alertType.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: alertType.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alertText,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                if (alertType.action.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: alertType.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Acción: ${alertType.action}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: alertType.color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  AlertType _getAlertType(String alertText) {
    final lowerAlert = alertText.toLowerCase();
    
    if (lowerAlert.contains('performance bajo') || lowerAlert.contains('crítico')) {
      return AlertType(
        icon: Icons.trending_down,
        color: AppColors.error,
        title: 'Performance Crítico',
        action: 'Revisar métricas y contactar proveedor',
      );
    }
    
    if (lowerAlert.contains('lead time excesivo') || lowerAlert.contains('retraso')) {
      return AlertType(
        icon: Icons.schedule,
        color: AppColors.warning,
        title: 'Problemas de Tiempo',
        action: 'Renegociar tiempos de entrega',
      );
    }
    
    if (lowerAlert.contains('sin compras recientes') || lowerAlert.contains('inactivo')) {
      return AlertType(
        icon: Icons.pause_circle,
        color: Colors.orange,
        title: 'Proveedor Inactivo',
        action: 'Evaluar continuidad de la relación',
      );
    }
    
    if (lowerAlert.contains('precio') || lowerAlert.contains('costo')) {
      return AlertType(
        icon: Icons.attach_money,
        color: AppColors.warning,
        title: 'Alerta de Precios',
        action: 'Revisar estructura de costos',
      );
    }
    
    if (lowerAlert.contains('calidad') || lowerAlert.contains('defecto')) {
      return AlertType(
        icon: Icons.report_problem,
        color: AppColors.error,
        title: 'Problemas de Calidad',
        action: 'Implementar controles de calidad',
      );
    }
    
    // Alerta genérica
    return AlertType(
      icon: Icons.info,
      color: AppColors.primary,
      title: 'Información General',
      action: 'Revisar detalles',
    );
  }
}

class AlertType {
  final IconData icon;
  final Color color;
  final String title;
  final String action;

  AlertType({
    required this.icon,
    required this.color,
    required this.title,
    required this.action,
  });
}
