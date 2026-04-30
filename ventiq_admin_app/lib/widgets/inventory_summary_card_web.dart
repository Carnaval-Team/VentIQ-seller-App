import 'package:flutter/material.dart';
import '../models/inventory.dart';
import '../config/app_colors.dart';

class InventorySummaryCardWeb extends StatelessWidget {
  final InventorySummaryByUser summary;
  final VoidCallback? onTap;

  const InventorySummaryCardWeb({Key? key, required this.summary, this.onTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    // print('🎨 Building InventorySummaryCardWeb for: ${summary.productoNombre}');
    // print(
    //   '🎨 Card data - ID: ${summary.idProducto}, Quantity: ${summary.cantidadTotalEnAlmacen}, Zones: ${summary.zonasDiferentes}, Presentations: ${summary.presentacionesDiferentes}',
    // );

    final color = summary.stockLevelColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.inventory_2_rounded,
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                summary.productoNombre,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  letterSpacing: 0.1,
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (summary.productoDescripcion != null &&
                                  summary.productoDescripcion!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  summary.productoDescripcion!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _buildMetaChip(
                                    Icons.qr_code_2_rounded,
                                    summary.productoSku,
                                    AppColors.textSecondary,
                                  ),
                                  if (summary.variantDisplay.isNotEmpty)
                                    _buildMetaChip(
                                      Icons.label_outline_rounded,
                                      summary.variantDisplay,
                                      AppColors.textSecondary,
                                    ),
                                  if (summary.hasMultipleLocations)
                                    _buildMetaChip(
                                      Icons.location_on_outlined,
                                      '${summary.zonasDiferentes} zonas',
                                      AppColors.info,
                                    ),
                                  if (summary.hasMultiplePresentations)
                                    _buildMetaChip(
                                      Icons.category_outlined,
                                      '${summary.presentacionesDiferentes} pres.',
                                      AppColors.warning,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              summary.cantidadTotalEnAlmacen
                                  .toStringAsFixed(0),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: color,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'unidades',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                summary.stockLevel,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// List widget for displaying multiple inventory summary cards
class InventorySummaryListWeb extends StatelessWidget {
  final List<InventorySummaryByUser> summaries;
  final Function(InventorySummaryByUser)? onItemTap;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const InventorySummaryListWeb({
    Key? key,
    required this.summaries,
    this.onItemTap,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Debug information
    print('🎯 InventorySummaryListWeb.build called');
    print('📊 isLoading: $isLoading');
    print('📊 errorMessage: $errorMessage');
    print('📊 summaries.length: ${summaries.length}');
    
    if (isLoading) {
      print('🔄 Showing loading state');
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (errorMessage != null) {
      print('❌ Showing error state: $errorMessage');
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
      print('📭 Showing empty state');
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

    print('✅ Building ListView with ${summaries.length} items');
    for (int i = 0; i < summaries.length && i < 3; i++) {
      final summary = summaries[i];
      print('📋 Item $i: ${summary.productoNombre} - ${summary.cantidadTotalEnAlmacen} units');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: summaries.length,
      itemBuilder: (context, index) {
        final summary = summaries[index];
        return InventorySummaryCardWeb(
          summary: summary,
          onTap: onItemTap != null ? () => onItemTap!(summary) : null,
        );
      },
    );
  }
}
