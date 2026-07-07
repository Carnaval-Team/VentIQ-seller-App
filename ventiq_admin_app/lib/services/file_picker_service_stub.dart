import 'dart:typed_data';

class PickedFile {
  final Uint8List bytes;
  final String nombre;
  final String mimeType;
  PickedFile({required this.bytes, required this.nombre, required this.mimeType});
}

class FilePickerService {
  static Future<PickedFile?> pickFile() async {
    throw UnsupportedError('File picker not supported on this platform');
  }
}
