import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:async';

class PickedFile {
  final Uint8List bytes;
  final String nombre;
  final String mimeType;
  PickedFile({
    required this.bytes,
    required this.nombre,
    required this.mimeType,
  });
}

class FilePickerService {
  static const int _maxSize = 20 * 1024 * 1024;

  static Future<PickedFile?> pickFile() async {
    html.FileUploadInputElement? input;
    final subs = <StreamSubscription<html.Event>>[];

    void cleanup() {
      for (final sub in subs) {
        sub.cancel();
      }
      input?.remove();
    }

    try {
      input = html.FileUploadInputElement()
        ..accept = 'image/*,.pdf,.doc,.docx,.xls,.xlsx'
        ..multiple = false
        ..style.display = 'none';
      html.document.body?.append(input);

      final completer = Completer<PickedFile?>();

      void complete(PickedFile? value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
        cleanup();
      }

      subs.add(
        input.onChange.listen((_) async {
          final files = input!.files;
          if (files == null || files.isEmpty) {
            complete(null);
            return;
          }
          final file = files[0];

          if (file.size > _maxSize) {
            complete(null);
            return;
          }

          final reader = html.FileReader();
          final readerSubs = <StreamSubscription<html.Event>>[];

          readerSubs.add(
            reader.onLoadEnd.listen((_) {
              if (reader.result != null) {
                final bytes = Uint8List.fromList(reader.result as List<int>);
                complete(
                  PickedFile(
                    bytes: bytes,
                    nombre: file.name,
                    mimeType: file.type.isNotEmpty
                        ? file.type
                        : 'application/octet-stream',
                  ),
                );
              } else {
                complete(null);
              }
              for (final sub in readerSubs) {
                sub.cancel();
              }
            }),
          );

          readerSubs.add(
            reader.onError.listen((_) {
              complete(null);
              for (final sub in readerSubs) {
                sub.cancel();
              }
            }),
          );

          reader.readAsArrayBuffer(file);
        }),
      );

      // Si el usuario cierra el selector sin elegir archivo, la ventana vuelve
      // a tener el foco y aún no hay files. Esperamos un poco para no competir
      // con el onChange del archivo seleccionado.
      subs.add(
        html.window.onFocus.take(1).listen((_) async {
          await Future.delayed(const Duration(milliseconds: 400));
          final files = input!.files;
          if (!completer.isCompleted &&
              (files == null || files.isEmpty)) {
            complete(null);
          }
        }),
      );

      input.click();

      return completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          cleanup();
          return null;
        },
      );
    } catch (e) {
      cleanup();
      print('❌ Error picking file on web: $e');
      return null;
    }
  }
}
