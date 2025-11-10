import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Tarjeta de tienda para vista de lista
class StoreListCard extends StatelessWidget {
  final String storeName;
  final String? logoUrl;
  final String? ubicacion;
  final String? provincia;
  final String? municipio;
  final String? direccion;
  final int productCount;
  final double? latitude;
  final double? longitude;
  final VoidCallback onTap;
  final VoidCallback? onMapTap;

  const StoreListCard({
    super.key,
    required this.storeName,
    this.logoUrl,
    this.ubicacion,
    this.provincia,
    this.municipio,
    this.direccion,
    required this.productCount,
    this.latitude,
    this.longitude,
    required this.onTap,
    this.onMapTap,
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
          padding: const EdgeInsets.all(AppTheme.paddingM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo de la tienda
              _buildStoreLogo(),
              const SizedBox(width: AppTheme.paddingM),
              
              // Información de la tienda
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre y botón de mapa
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            storeName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (latitude != null && longitude != null)
                          IconButton(
                            icon: const Icon(
                              Icons.map_outlined,
                              color: AppTheme.primaryColor,
                              size: 24,
                            ),
                            onPressed: onMapTap,
                            tooltip: 'Ver en el mapa',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Ubicación
                    if (ubicacion != null || provincia != null || municipio != null)
                      _buildLocationInfo(),
                    
                    const SizedBox(height: 12),
                    
                    // Total de productos
                    _buildProductCount(),
                    
                    const SizedBox(height: 8),
                    
                    // Dirección
                    if (direccion != null && direccion!.isNotEmpty)
                      _buildAddress(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreLogo() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(
          color: Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: logoUrl != null && logoUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
              child: Image.network(
                logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholderLogo();
                },
              ),
            )
          : _buildPlaceholderLogo(),
    );
  }

  Widget _buildPlaceholderLogo() {
    return Icon(
      Icons.store,
      size: 40,
      color: Colors.grey[400],
    );
  }

  Widget _buildLocationInfo() {
    final List<String> locationParts = [];
    
    if (ubicacion != null && ubicacion!.isNotEmpty) {
      locationParts.add(ubicacion!);
    }
    if (municipio != null && municipio!.isNotEmpty) {
      locationParts.add(municipio!);
    }
    if (provincia != null && provincia!.isNotEmpty) {
      locationParts.add(provincia!);
    }
    
    final locationText = locationParts.join(', ');
    
    return Row(
      children: [
        const Icon(
          Icons.location_on_outlined,
          size: 16,
          color: AppTheme.secondaryColor,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            locationText,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProductCount() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusS),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: AppTheme.primaryColor,
          ),
          const SizedBox(width: 6),
          Text(
            '$productCount ${productCount == 1 ? 'producto' : 'productos'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddress() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.home_outlined,
          size: 16,
          color: AppTheme.textSecondary,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            direccion!,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
