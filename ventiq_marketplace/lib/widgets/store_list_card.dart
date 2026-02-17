import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'supabase_image.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = AppTheme.getCardColor(context);
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

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
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo de la tienda
                _buildStoreLogo(context),
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
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
                                color: accentColor.withOpacity(isDark ? 0.15 : 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: IconButton(
                                icon: Icon(
                                  Icons.map_outlined,
                                  color: accentColor,
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
                        _buildLocationInfo(context),

                      const SizedBox(height: 10),

                      // Total de productos
                      _buildProductCount(context),

                      // Dirección
                      if (direccion != null && direccion!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildAddress(context),
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

  Widget _buildStoreLogo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceColor : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
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
      child: logoUrl != null && logoUrl!.isNotEmpty
          ? SupabaseImage(
              imageUrl: logoUrl!,
              fit: BoxFit.cover,
              width: 70,
              height: 70,
              borderRadius: 12,
              placeholderAsset: null,
            )
          : _buildPlaceholderLogo(context),
    );
  }

  Widget _buildPlaceholderLogo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Icon(
        Icons.store_rounded,
        size: 32,
        color: isDark ? AppTheme.darkTextHint : Colors.grey[400],
      ),
    );
  }

  Widget _buildLocationInfo(BuildContext context) {
    final textSecondary = AppTheme.getTextSecondaryColor(context);
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
              color: textSecondary.withOpacity(0.9),
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildProductCount(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(isDark ? 0.15 : 0.08),
            accentColor.withOpacity(isDark ? 0.2 : 0.12),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accentColor.withOpacity(isDark ? 0.35 : 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_rounded,
            size: 14,
            color: accentColor.withOpacity(0.9),
          ),
          const SizedBox(width: 6),
          Text(
            '$productCount ${productCount == 1 ? 'producto' : 'productos'}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accentColor.withOpacity(0.9),
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddress(BuildContext context) {
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.home_rounded,
          size: 14,
          color: textSecondary.withOpacity(0.6),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            direccion!,
            style: TextStyle(
              fontSize: 11.5,
              color: textSecondary.withOpacity(0.8),
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
