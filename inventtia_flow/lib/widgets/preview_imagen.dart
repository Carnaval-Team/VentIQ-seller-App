import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Previsualización de una imagen recién elegida con `image_picker`.
///
/// Existe porque `Image.file(File(xfile.path))` **no funciona en web**: allí no
/// hay sistema de archivos y la ruta es un blob URL. En web se leen los bytes
/// (`XFile.readAsBytes`) y se pinta con `Image.memory`; en nativo se sigue
/// usando `Image.file`, que no copia el archivo entero a memoria.
///
/// Antes cada formulario repetía el `Image.file` y la app web se rompía al
/// previsualizar. Ahora hay un solo sitio que sabe la diferencia.
class PreviewImagen extends StatelessWidget {
  const PreviewImagen({
    super.key,
    required this.file,
    this.fit = BoxFit.cover,
    this.width = double.infinity,
    this.height,
  });

  final XFile file;
  final BoxFit fit;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return _Cargando(
              width: width,
              height: height,
              error: snapshot.hasError,
            );
          }
          return Image.memory(
            bytes,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (_, __, ___) =>
                _Cargando(width: width, height: height, error: true),
          );
        },
      );
    }
    return Image.file(
      File(file.path),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) =>
          _Cargando(width: width, height: height, error: true),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando({
    required this.width,
    required this.height,
    required this.error,
  });

  final double width;
  final double? height;
  final bool error;

  @override
  Widget build(BuildContext context) {
    if (error) {
      return SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.grey),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
