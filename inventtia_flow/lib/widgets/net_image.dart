import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Carga una imagen desde URL usando [CachedNetworkImage] en móvil
/// y [Image.network] en web (CachedNetworkImage no soporta web).
class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function()? placeholder;
  final Widget Function()? errorWidget;

  const NetImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) =>
            errorWidget?.call() ?? const SizedBox.shrink(),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return placeholder?.call() ??
              const Center(
                  child: CircularProgressIndicator(strokeWidth: 2));
        },
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      placeholder: (_, __) =>
          placeholder?.call() ??
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (_, __, ___) =>
          errorWidget?.call() ?? const SizedBox.shrink(),
    );
  }
}
