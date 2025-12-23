import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../models/crm/crm_metrics.dart';
import '../../utils/number_formatter.dart';

/// Widget atómico para mostrar KPIs CRM
class CRMKPICards extends StatelessWidget {
  final CRMMetrics metrics;
  final bool isLoading;

  const CRMKPICards({
    Key? key,
    required this.metrics,
    this.isLoading = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Primera fila: Métricas principales
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Total Contactos',
                '${metrics.totalContactsCalculated}',
                Icons.contacts,
                AppColors.primary,
                '${metrics.activeContactsPercentage.toStringAsFixed(1)}% activos',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                'Score Relaciones',
                '${metrics.relationshipScore.toStringAsFixed(1)}%',
                Icons.trending_up,
                _getScoreColor(metrics.relationshipScore),
                _getScoreLabel(metrics.relationshipScore),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Segunda fila: Clientes y Proveedores
        Row(
          children: [
            Expanded(
              child: _buildDetailedKPICard(
                'Clientes',
                '${metrics.totalCustomers}',
                Icons.people,
                Colors.blue,
                [
                  KPIDetail('VIP', '${metrics.vipCustomers}', Colors.amber),
                  KPIDetail('Activos', '${metrics.activeCustomers}', Colors.green),
                  KPIDetail('Puntos', NumberFormatter.formatNumber(metrics.loyaltyPoints), Colors.purple),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDetailedKPICard(
                'Proveedores',
                '${metrics.totalSuppliers}',
                Icons.factory,
                Colors.orange,
                [
                  KPIDetail('Activos', '${metrics.activeSuppliers}', Colors.green),
                  KPIDetail('Productos', '${metrics.uniqueProducts}', Colors.blue),
                  KPIDetail('T. Entrega', '${metrics.averageLeadTime.toStringAsFixed(1)}d', Colors.grey),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Tercera fila: Métricas calculadas
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Diversificación',
                '${metrics.supplierDiversificationScore.toStringAsFixed(1)}/10',
                Icons.scatter_plot,
                Colors.teal,
                'Productos por proveedor',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                'Fidelización',
                '${metrics.customerLoyaltyScore.toStringAsFixed(1)}%',
                Icons.stars,
                Colors.amber,
                'Clientes VIP',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard(
    String title,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedKPICard(
    String title,
    String mainValue,
    IconData icon,
    Color color,
    List<KPIDetail> details,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        mainValue,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: details.map((detail) => _buildDetailItem(detail)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(KPIDetail detail) {
    return Column(
      children: [
        Text(
          detail.value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: detail.color,
          ),
        ),
        Text(
          detail.label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _getScoreLabel(double score) {
    if (score >= 80) return 'Excelente';
    if (score >= 60) return 'Bueno';
    if (score >= 40) return 'Regular';
    return 'Necesita mejora';
  }
}

/// Clase para detalles de KPI
class KPIDetail {
  final String label;
  final String value;
  final Color color;

  KPIDetail(this.label, this.value, this.color);
}
