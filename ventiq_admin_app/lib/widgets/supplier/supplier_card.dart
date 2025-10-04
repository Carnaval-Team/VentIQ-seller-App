import 'package:flutter/material.dart';
import '../../models/supplier.dart';

class SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onViewDetails;
  final bool showActions;
  final bool isSelected;
  final bool showMetrics;
  
  const SupplierCard({
    super.key,
    required this.supplier,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onViewDetails,
    this.showActions = true,
    this.isSelected = false,
    this.showMetrics = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.blue.shade50 : null,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con nombre y acciones
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.denominacion,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (supplier.fullAddress.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            supplier.fullAddress,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showActions) _buildActionButtons(context),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Información básica
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    icon: Icons.qr_code,
                    label: supplier.skuCodigo,
                    color: Colors.blue,
                  ),
                  if (supplier.leadTime != null)
                    _buildInfoChip(
                      icon: Icons.schedule,
                      label: supplier.leadTimeDisplay,
                      color: Colors.orange,
                    ),
                  if (supplier.hasMetrics)
                    _buildInfoChip(
                      icon: Icons.trending_up,
                      label: supplier.performanceLevel,
                      color: _getPerformanceColor(supplier.performanceLevel),
                    ),
                ],
              ),
              
              // Métricas adicionales si están disponibles
              if (showMetrics && supplier.hasMetrics) ...[
                const SizedBox(height: 12),
                _buildMetricsSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildActionButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onViewDetails != null)
          IconButton(
            icon: const Icon(Icons.visibility, size: 20),
            onPressed: onViewDetails,
            tooltip: 'Ver detalles',
          ),
        if (onEdit != null)
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: onEdit,
            tooltip: 'Editar',
          ),
        if (onDelete != null)
          IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Eliminar',
          ),
      ],
    );
  }
  
  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMetricsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Métricas',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  'Órdenes',
                  '${supplier.totalOrders ?? 0}',
                  Icons.shopping_cart,
                ),
              ),
              Expanded(
                child: _buildMetricItem(
                  'Promedio',
                  '\$${supplier.averageOrderValue?.toStringAsFixed(2) ?? '0.00'}',
                  Icons.attach_money,
                ),
              ),
              if (supplier.lastOrderDate != null)
                Expanded(
                  child: _buildMetricItem(
                    'Última orden',
                    _formatDate(supplier.lastOrderDate!),
                    Icons.calendar_today,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildMetricItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  
  Color _getPerformanceColor(String performance) {
    switch (performance) {
      case 'Excelente':
        return Colors.green;
      case 'Bueno':
        return Colors.blue;
      case 'Regular':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date).inDays;
    
    if (difference == 0) return 'Hoy';
    if (difference == 1) return 'Ayer';
    if (difference < 7) return 'Hace $difference días';
    if (difference < 30) return 'Hace ${(difference / 7).round()} semanas';
    return 'Hace ${(difference / 30).round()} meses';
  }
  
  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar eliminación'),
          content: Text(
            '¿Estás seguro de que deseas eliminar el proveedor "${supplier.denominacion}"?\n\nEsta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onDelete?.call();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
  }
}
