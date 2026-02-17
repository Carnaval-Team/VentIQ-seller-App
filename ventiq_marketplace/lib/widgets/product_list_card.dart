import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'supabase_image.dart';
import 'stock_status_chip.dart';

/// Tarjeta de producto para vista de lista
class ProductListCard extends StatelessWidget {
  final String productName;
  final double price;
  final String? imageUrl;
  final String storeName;
  final int availableStock;
  final bool showStockStatus;
  final double rating;
  final List<String> presentations;
  final VoidCallback onTap;

  const ProductListCard({
    super.key,
    required this.productName,
    required this.price,
    this.imageUrl,
    required this.storeName,
    required this.availableStock,
    this.showStockStatus = true,
    required this.rating,
    required this.presentations,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final priceColor = AppTheme.getPriceColor(context);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Imagen del producto
                _buildProductImage(context),
                const SizedBox(width: 12),

                // Información del producto
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nombre y Rating
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              productName,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                                height: 1.3,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildRating(context),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Precio
                      Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: priceColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Presentaciones
                      if (presentations.isNotEmpty) _buildPresentations(context),

                      if (presentations.isNotEmpty) const SizedBox(height: 8),

                      // Tienda y Stock
                      Row(
                        children: [
                          Expanded(child: _buildStoreInfo(context)),
                          if (showStockStatus) const SizedBox(width: 8),
                          if (showStockStatus) _buildStockInfo(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 85,
      height: 85,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.darkDividerColor : Colors.grey.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? SupabaseImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              width: 85,
              height: 85,
              borderRadius: 10,
              placeholderAsset: null,
            )
          : _buildPlaceholderImage(context),
    );
  }

  Widget _buildPlaceholderImage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Icon(
        Icons.shopping_bag_rounded,
        size: 36,
        color: isDark ? AppTheme.darkTextHint : Colors.grey[400],
      ),
    );
  }

  Widget _buildRating(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.warningColor.withOpacity(isDark ? 0.2 : 0.12),
            AppTheme.warningColor.withOpacity(isDark ? 0.15 : 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.warningColor.withOpacity(isDark ? 0.4 : 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 13,
            color: AppTheme.warningColor.withOpacity(0.95),
          ),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.warningColor.withOpacity(0.95),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentations(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: presentations.take(3).map((presentation) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.secondaryColor.withOpacity(isDark ? 0.15 : 0.08),
                AppTheme.secondaryColor.withOpacity(isDark ? 0.2 : 0.12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppTheme.secondaryColor.withOpacity(isDark ? 0.35 : 0.2),
              width: 0.5,
            ),
          ),
          child: Text(
            presentation,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryColor.withOpacity(isDark ? 1.0 : 0.9),
              letterSpacing: -0.1,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStoreInfo(BuildContext context) {
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    return Row(
      children: [
        Icon(
          Icons.store_rounded,
          size: 13,
          color: textSecondary.withOpacity(0.7),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            storeName,
            style: TextStyle(
              fontSize: 11.5,
              color: textSecondary.withOpacity(0.85),
              height: 1.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStockInfo() {
    return StockStatusChip(
      stock: availableStock,
      lowStockThreshold: 10,
      showQuantity: false,
      fontSize: 11,
      iconSize: 13,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      borderRadius: 6,
      maxWidth: 96,
    );
  }
}
