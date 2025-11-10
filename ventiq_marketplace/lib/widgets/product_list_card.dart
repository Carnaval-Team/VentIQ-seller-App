import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Tarjeta de producto para vista de lista
class ProductListCard extends StatelessWidget {
  final String productName;
  final double price;
  final String? imageUrl;
  final String storeName;
  final int availableStock;
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
    required this.rating,
    required this.presentations,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: AppTheme.paddingS,
      ),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Imagen del producto
              _buildProductImage(),
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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRating(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    
                    // Precio
                    Text(
                      '\$${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    
                    // Presentaciones
                    if (presentations.isNotEmpty) _buildPresentations(),
                    
                    const SizedBox(height: 8),
                    
                    // Tienda y Stock
                    Row(
                      children: [
                        Expanded(child: _buildStoreInfo()),
                        const SizedBox(width: 8),
                        _buildStockInfo(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage() {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: imageUrl != null && imageUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              child: Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholderImage();
                },
              ),
            )
          : _buildPlaceholderImage(),
    );
  }

  Widget _buildPlaceholderImage() {
    return Icon(
      Icons.shopping_bag_outlined,
      size: 40,
      color: Colors.grey[400],
    );
  }

  Widget _buildRating() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star,
            size: 12,
            color: AppTheme.warningColor,
          ),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.warningColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentations() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: presentations.take(3).map((presentation) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.secondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppTheme.secondaryColor.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Text(
            presentation,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryColor,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStoreInfo() {
    return Row(
      children: [
        Icon(
          Icons.store_outlined,
          size: 12,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            storeName,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStockInfo() {
    final bool isLowStock = availableStock < 10;
    final Color stockColor = isLowStock ? AppTheme.errorColor : AppTheme.textSecondary;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 12,
          color: stockColor,
        ),
        const SizedBox(width: 3),
        Text(
          '$availableStock',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: stockColor,
          ),
        ),
      ],
    );
  }
}
