import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class PickedFile {
  final Uint8List bytes;
  final String nombre;
  final String mimeType;
  PickedFile({required this.bytes, required this.nombre, required this.mimeType});
}

class FilePickerService {
  static Future<PickedFile?> pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx', 'xls', 'xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      if (file.bytes == null) return null;

      final ext = (file.extension ?? 'bin').toLowerCase();
      final mime = _mimeFromExt(ext);

      return PickedFile(bytes: file.bytes!, nombre: file.name, mimeType: mime);
    } catch (e) {
      print('❌ Error picking file on mobile: $e');
      return null;
    }
  }

  static String _mimeFromExt(String ext) {
    switch (ext) {
      case 'pdf':   return 'application/pdf';
      case 'doc':   return 'application/msword';
      case 'docx':  return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':   return 'application/vnd.ms-excel';
      case 'xlsx':  return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'png':   return 'image/png';
      case 'jpg':
      case 'jpeg':  return 'image/jpeg';
      default:      return 'application/octet-stream';
    }
  }
}
