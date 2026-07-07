import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

class PickedFile {
  final Uint8List bytes;
  final String nombre;
  final String mimeType;
  PickedFile({required this.bytes, required this.nombre, required this.mimeType});
}

class FilePickerService {
  static Future<PickedFile?> pickFile() async {
    try {
      final input = html.FileUploadInputElement();
      input.accept = 'image/*,.pdf,.doc,.docx,.xls,.xlsx';
      input.multiple = false;

      final completer = Completer<PickedFile?>();

      input.onChange.listen((e) async {
        final files = input.files;
        if (files == null || files.isEmpty) {
          completer.complete(null);
          return;
        }
        final file = files[0];

        if (file.size > 20 * 1024 * 1024) {
          completer.complete(null);
          return;
        }

        final reader = html.FileReader();
        reader.onLoadEnd.listen((_) {
          if (reader.result != null) {
            final bytes = Uint8List.fromList(reader.result as List<int>);
            completer.complete(PickedFile(
              bytes: bytes,
              nombre: file.name,
              mimeType: file.type.isNotEmpty ? file.type : 'application/octet-stream',
            ));
          } else {
            completer.complete(null);
          }
        });
        reader.onError.listen((_) => completer.complete(null));
        reader.readAsArrayBuffer(file);
      });

      input.click();

      return completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );
    } catch (e) {
      print('❌ Error picking file on web: $e');
      return null;
    }
  }
}
