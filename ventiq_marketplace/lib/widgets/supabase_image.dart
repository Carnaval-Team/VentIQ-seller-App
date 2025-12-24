import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class SupabaseImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double? borderRadius;
  final String? placeholderAsset;

  const SupabaseImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderAsset,
  });

  String _getOptimizedUrl() {
    if (!imageUrl.contains('supabase.co')) return imageUrl;

    // Si ya tiene query params, agregamos con &, si no con ?
    final separator = imageUrl.contains('?') ? '&' : '?';
    final params = <String>[];

    // Si tenemos un ancho definido, solicitamos ese tamaño (o el doble para retina)
    if (width != null && width! != double.infinity) {
      params.add('width=${(width! * 2).toInt()}');
    }

    // Calidad 80 por defecto para buen balance
    params.add('quality=80');
    // Formato webp para mejor compresión
    params.add('format=webp');

    if (params.isEmpty) return imageUrl;

    return '$imageUrl$separator${params.join('&')}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius ?? 0),
      child: CachedNetworkImage(
        imageUrl: _getOptimizedUrl(),
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: Colors.grey[400],
              size: (width ?? 50) * 0.4,
            ),
          ),
        ),
      ),
    );
  }
}
