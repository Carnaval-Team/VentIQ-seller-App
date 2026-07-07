// Stub para plataformas no-web. Nunca se ejecuta en runtime web; existe
// solo para que `conditional imports` resuelvan en mobile/desktop.

import 'dart:typed_data';

class PickedImageData {
  final Uint8List bytes;
  final String name;
  final String? mimeType;
  const PickedImageData({
    required this.bytes,
    required this.name,
    this.mimeType,
  });
}

/// Implementación nativa-web del picker. En el stub (mobile/desktop) lanza.
Future<PickedImageData?> pickImageWeb({required bool useCamera}) {
  throw UnsupportedError(
    'pickImageWeb solo está disponible en Flutter Web. Usa image_picker en mobile.',
  );
}
