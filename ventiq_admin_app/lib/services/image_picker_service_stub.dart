import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Stub implementation for image picker service
class ImagePickerService {
  /// Resultado de una selección de imagen.
  static Future<PickedImageResult?> pickImage({
    BuildContext? context,
    ImagePickSource? source,
  }) async {
    throw UnsupportedError('Image picker not supported on this platform');
  }
}

enum ImagePickSource { camera, gallery }

class PickedImageResult {
  final Uint8List bytes;
  final String fileName;

  const PickedImageResult({
    required this.bytes,
    required this.fileName,
  });
}
