import 'package:flutter/material.dart';
import '../models/inventory.dart';
import '../config/app_colors.dart';

class InventorySummaryCard extends StatelessWidget {
  final InventorySummaryByUser summary;
  final VoidCallback? onTap;

  const InventorySummaryCard({Key? key, required this.summary, this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('🎨 Building InventorySummaryCard for: ${summary.productoNombre}');
    print(
      '🎨 Card data - ID: ${summary.idProducto}, Quantity: ${summary.cantidadTotalEnAlmacen}, Zones: ${summary.zonasDiferentes}, Presentations: ${summary.presentacionesDiferentes}',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with product name and stock badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              summary.productoNombre,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Icons for multiple layouts and presentations
                          if (summary.hasMultipleLocations) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: AppColors.info,
                            ),
                          ],
                          if (summary.hasMultiplePresentations) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.inventory,
                              size: 16,
                              color: AppColors.warning,
                            ),
                          ],
                        ],
                      ),
                      if (summary.variantDisplay.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          summary.variantDisplay,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: summary.stockLevelColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    summary.stockLevel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quantity and ID row
            Row(
              children: [
                Icon(
                  Icons.inventory_2,
                  color: summary.stockLevelColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${summary.cantidadTotalEnAlmacen.toStringAsFixed(0)} unidades',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: summary.stockLevelColor,
                  ),
                ),
                const Spacer(),
                Text(
                  'ID: ${summary.idProducto}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Distribution badges
            Row(
              children: [
                if (summary.hasMultipleLocations) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.info.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 12,
                          color: AppColors.info,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${summary.zonasDiferentes} zonas',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.info,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (summary.hasMultiplePresentations) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.category,
                          size: 12,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${summary.presentacionesDiferentes} presentaciones',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// List widget for displaying multiple inventory summary cards
class InventorySummaryList extends StatelessWidget {
  final List<InventorySummaryByUser> summaries;
  final Function(InventorySummaryByUser)? onItemTap;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const InventorySummaryList({
    Key? key,
    required this.summaries,
    this.onItemTap,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Error al cargar inventario',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (summaries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 16),
              Text(
                'No hay productos en inventario',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No se encontraron productos con stock disponible',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        return InventorySummaryCard(
          summary: summary,
          onTap: onItemTap != null ? () => onItemTap!(summary) : null,
        );
      },
    );
  }
}
