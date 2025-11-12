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
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo de la tienda
                _buildStoreLogo(),
                const SizedBox(width: 14),

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
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (latitude != null && longitude != null)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.map_outlined,
                                  color: AppTheme.primaryColor,
                                  size: 20,
                                ),
                                onPressed: onMapTap,
                                tooltip: 'Ver en el mapa',
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Ubicación
                      if (ubicacion != null ||
                          provincia != null ||
                          municipio != null)
                        _buildLocationInfo(),

                      const SizedBox(height: 10),

                      // Total de productos
                      _buildProductCount(),

                      // Dirección
                      if (direccion != null && direccion!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildAddress(),
                      ],
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

  Widget _buildStoreLogo() {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: logoUrl != null && logoUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
    return Center(
      child: Icon(
        Icons.store_rounded,
        size: 32,
        color: Colors.grey[400],
      ),
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
        Icon(
          Icons.location_on_rounded,
          size: 15,
          color: AppTheme.secondaryColor.withOpacity(0.8),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            locationText,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary.withOpacity(0.9),
              height: 1.3,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withOpacity(0.08),
            AppTheme.primaryColor.withOpacity(0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_rounded,
            size: 14,
            color: AppTheme.primaryColor.withOpacity(0.9),
          ),
          const SizedBox(width: 6),
          Text(
            '$productCount ${productCount == 1 ? 'producto' : 'productos'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor.withOpacity(0.9),
              letterSpacing: -0.1,
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
        Icon(
          Icons.home_rounded,
          size: 14,
          color: AppTheme.textSecondary.withOpacity(0.6),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            direccion!,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSecondary.withOpacity(0.8),
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
