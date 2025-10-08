import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../../utils/number_formatter.dart';

// Reemplazar el widget ProductsKPICards existente

class ProductsKPICards extends StatelessWidget {
  final Map<String, dynamic> kpis;
  final bool isLoading;

  const ProductsKPICards({
    Key? key,
    required this.kpis,
    required this.isLoading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        children: List.generate(6, (index) => _buildLoadingCard()),
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.3,
      crossAxisSpacing: 16,
      mainAxisSpacing: 18,
      children: [
        _buildKPICard(
          context,
          'Total Productos',
          '${kpis['totalProductos'] ?? 0}',
          Icons.inventory_2,
          Colors.blue,
        ),
        _buildKPICard(
          context,
          'Con Stock',
          '${kpis['productosConStock'] ?? 0}',
          Icons.check_circle,
          Colors.green,
          percentage: kpis['porcentajeConStock']?.toDouble(),
        ),
        _buildKPICard(
          context,
          'Productos Elaborados',
          '${kpis['productosElaborados'] ?? 0}',
          Icons.construction,
          Colors.orange,
        ),
        _buildKPICard(
          context,
          'Stock Bajo',
          '${kpis['productosStockBajo'] ?? 0}',
          Icons.warning,
          Colors.red,
          percentage: kpis['porcentajeStockBajo']?.toDouble(),
        ),
        _buildKPICard(
          context,
          'Sin Movimiento',
          '${kpis['productosSinMovimiento'] ?? 0}',
          Icons.pause_circle,
          Colors.grey,
          percentage: kpis['porcentajeSinMovimiento']?.toDouble(),
        ),
        _buildKPICard(
          context,
          'Valor Inventario',
          'CUP \$${NumberFormatter.formatCurrency(kpis['valorTotalInventario'] ?? 0.0)}',
          Icons.attach_money,
          Colors.green,
        ),
      ],
    );
  }

  Widget _buildKPICard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    double? percentage,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12), // Reducir padding general
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isSmall = constraints.maxWidth < 200; // Ajusta este valor según necesites

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      color: color,
                      size: isSmall ? 20 : 24, // Icono más pequeño en móviles
                    ),
                    SizedBox(width: isSmall ? 6 : 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                          fontSize: isSmall ? 12 : null, // Texto más pequeño
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isSmall ? 6 : 8),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: isSmall ? 18 : null, // Valor más pequeño
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (percentage != null) ...[
                  SizedBox(height: isSmall ? 2 : 4),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: isSmall ? 4 : 6,
                        vertical: isSmall ? 1 : 2
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: isSmall ? 10 : null,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 24,
              width: 80,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductsQuickActions extends StatelessWidget {
  final VoidCallback? onAddProduct;
  final VoidCallback? onViewAll;
  final VoidCallback? onViewAlerts;
  final VoidCallback? onViewReports;

  const ProductsQuickActions({
    super.key,
    this.onAddProduct,
    this.onViewAll,
    this.onViewAlerts,
    this.onViewReports,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Acciones Rápidas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.add,
                  label: 'Agregar',
                  color: AppColors.primary,
                  onTap: onAddProduct,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.list,
                  label: 'Ver Todos',
                  color: AppColors.info,
                  onTap: onViewAll,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.warning,
                  label: 'Alertas',
                  color: AppColors.warning,
                  onTap: onViewAlerts,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.analytics,
                  label: 'Reportes',
                  color: AppColors.success,
                  onTap: onViewReports,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
