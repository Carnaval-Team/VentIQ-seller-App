import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class SupabaseImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double? borderRadius;
  final String? placeholderAsset;
  final Widget? placeholderWidget;
  final Widget? errorWidgetOverride;

  /// Prefijo de URL de object storage de Supabase
  static const String _objectPrefix =
      'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/';

  /// Prefijo de URL de render (transformación de imágenes) de Supabase
  static const String _renderPrefix =
      'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/render/image/public/images_back/';

  const SupabaseImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderAsset,
    this.placeholderWidget,
    this.errorWidgetOverride,
  });

  /// Convierte la URL de object storage a render con dimensiones optimizadas
  String _getOptimizedUrl() {
    if (imageUrl.isEmpty) return imageUrl;

    // Si es URL de object storage de Supabase, convertir a render
    if (imageUrl.contains(_objectPrefix)) {
      final params = <String>[];

      // Calcular dimensiones óptimas (x2 para pantallas retina)
      final targetWidth = width != null && width! != double.infinity
          ? (width! * 2).toInt()
          : 400;
      final targetHeight = height != null && height! != double.infinity
          ? (height! * 2).toInt()
          : 400;

      params.add('width=$targetWidth');
      params.add('height=$targetHeight');
      params.add('quality=80');

      final renderUrl = imageUrl.replaceFirst(_objectPrefix, _renderPrefix);
      return '$renderUrl?${params.join('&')}';
    }

    // Para otras URLs de Supabase, agregar parámetros de optimización
    if (imageUrl.contains('supabase.co') && !imageUrl.contains('/render/')) {
      final separator = imageUrl.contains('?') ? '&' : '?';
      final params = <String>[];

      if (width != null && width! != double.infinity) {
        params.add('width=${(width! * 2).toInt()}');
      }
      if (height != null && height! != double.infinity) {
        params.add('height=${(height! * 2).toInt()}');
      }
      params.add('quality=80');

      if (params.isNotEmpty) {
        return '$imageUrl$separator${params.join('&')}';
      }
    }

    return imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? const Color(0xFF2D2D30) : Colors.grey[200];
    final iconColor = isDark ? const Color(0xFF707070) : Colors.grey[400];

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius ?? 0),
      child: CachedNetworkImage(
        imageUrl: _getOptimizedUrl(),
        width: width,
        height: height,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 200),
        fadeOutDuration: const Duration(milliseconds: 200),
        memCacheWidth: width != null && width! != double.infinity
            ? (width! * 2).toInt()
            : null,
        memCacheHeight: height != null && height! != double.infinity
            ? (height! * 2).toInt()
            : null,
        placeholder: (context, url) {
          if (placeholderWidget != null) {
            return SizedBox(
              width: width,
              height: height,
              child: placeholderWidget,
            );
          }
          if (placeholderAsset != null) {
            return Image.asset(
              placeholderAsset!,
              width: width,
              height: height,
              fit: fit,
            );
          }
          return Container(
            width: width,
            height: height,
            color: placeholderColor,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorWidget: (context, url, error) {
          if (errorWidgetOverride != null) {
            return SizedBox(
              width: width,
              height: height,
              child: errorWidgetOverride,
            );
          }
          return Container(
            width: width,
            height: height,
            color: placeholderColor,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: iconColor,
                size: (width ?? 50) * 0.4,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Helper estático para obtener URL optimizada sin crear widget
  static String getOptimizedImageUrl(
    String url, {
    int? width,
    int? height,
    int quality = 80,
  }) {
    if (url.isEmpty) return url;

    if (url.contains(_objectPrefix)) {
      final params = <String>[];
      if (width != null) params.add('width=$width');
      if (height != null) params.add('height=$height');
      params.add('quality=$quality');

      final renderUrl = url.replaceFirst(_objectPrefix, _renderPrefix);
      return '$renderUrl?${params.join('&')}';
    }

    return url;
  }
}
