import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'marquee_text.dart';

/// Tarjeta de tienda para el marketplace
class StoreCard extends StatelessWidget {
  final String storeName;
  final int productCount;
  final int salesCount;
  final double rating;
  final String? logoUrl;
  final VoidCallback onTap;

  const StoreCard({
    super.key,
    required this.storeName,
    required this.productCount,
    required this.salesCount,
    required this.rating,
    this.logoUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.grey[50]!],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header con gradiente
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.1),
                    AppTheme.secondaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusL),
                  topRight: Radius.circular(AppTheme.radiusL),
                ),
              ),
              child: Row(
                children: [
                  // Logo de la tienda mejorado
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.white, Colors.grey[100]!],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: logoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusM,
                            ),
                            child: Image.network(
                              logoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.store_rounded,
                                  size: 35,
                                  color: AppTheme.primaryColor,
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.store_rounded,
                            size: 35,
                            color: AppTheme.primaryColor,
                          ),
                  ),
                  const SizedBox(width: 12),

                  // Información de la tienda
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 22,
                          child: MarqueeText(
                            text: storeName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Rating con diseño mejorado
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.warningColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: AppTheme.warningColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
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

            // Contenido principal
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  // Estadísticas mejoradas
                  Row(
                    children: [
                      Expanded(
                        child: _buildModernStatCard(
                          icon: Icons.inventory_2_rounded,
                          label: 'Productos',
                          value: _formatNumber(productCount),
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildModernStatCard(
                          icon: Icons.shopping_cart_rounded,
                          label: 'Ventas',
                          value: _formatNumber(salesCount),
                          color: AppTheme.successColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Botón de visitar mejorado
                  // Container(
                  //   width: double.infinity,
                  //   decoration: BoxDecoration(
                  //     gradient: LinearGradient(
                  //       colors: [
                  //         AppTheme.primaryColor,
                  //         AppTheme.primaryColor.withOpacity(0.8),
                  //       ],
                  //     ),
                  //     borderRadius: BorderRadius.circular(10),
                  //     boxShadow: [
                  //       BoxShadow(
                  //         color: AppTheme.primaryColor.withOpacity(0.3),
                  //         blurRadius: 6,
                  //         offset: const Offset(0, 3),
                  //       ),
                  //     ],
                  //   ),
                  //   child: Material(
                  //     color: Colors.transparent,
                  //     child: InkWell(
                  //       onTap: onTap,
                  //       borderRadius: BorderRadius.circular(10),
                  //       child: Padding(
                  //         padding: const EdgeInsets.symmetric(vertical: 10),
                  //         child: Row(
                  //           mainAxisAlignment: MainAxisAlignment.center,
                  //           children: [
                  //             const Icon(
                  //               Icons.storefront_rounded,
                  //               color: Colors.white,
                  //               size: 18,
                  //             ),
                  //             const SizedBox(width: 6),
                  //             const Text(
                  //               'Visitar Tienda',
                  //               style: TextStyle(
                  //                 color: Colors.white,
                  //                 fontSize: 13,
                  //                 fontWeight: FontWeight.bold,
                  //                 letterSpacing: 0.5,
                  //               ),
                  //             ),
                  //             const SizedBox(width: 4),
                  //             const Icon(
                  //               Icons.arrow_forward_rounded,
                  //               color: Colors.white,
                  //               size: 16,
                  //             ),
                  //           ],
                  //         ),
                  //       ),
                  //     ),
                  //   ),
                  // ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }
}
