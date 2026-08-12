// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum ImagePickSource { camera, gallery }

class PickedImageResult {
  final Uint8List bytes;
  final String fileName;

  const PickedImageResult({
    required this.bytes,
    required this.fileName,
  });
}

/// Web implementation: input file (galería/archivo) o capture (cámara en móvil).
/// El navegador gestiona los permisos; no hace falta permission_handler.
class ImagePickerService {
  static const int _maxBytes = 8 * 1024 * 1024; // 8 MB

  static Future<PickedImageResult?> pickImage({
    BuildContext? context,
    ImagePickSource? source,
  }) async {
    try {
      final resolved = source ??
          (context != null && context.mounted
              ? await _showImageSourceSheet(context)
              : ImagePickSource.gallery);
      if (resolved == null) return null;

      return _pickWithHtmlInput(useCamera: resolved == ImagePickSource.camera);
    } catch (e) {
      debugPrint('❌ Error picking image on web: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo seleccionar la imagen: $e')),
        );
      }
      return null;
    }
  }

  static Future<PickedImageResult?> _pickWithHtmlInput({
    required bool useCamera,
  }) {
    final uploadInput = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..multiple = false;

    if (useCamera) {
      // En móviles abre la cámara; en desktop el navegador puede ignorarlo
      // y mostrar el selector de archivos.
      uploadInput.setAttribute('capture', 'environment');
    }

    final completer = Completer<PickedImageResult?>();

    uploadInput.onChange.listen((_) async {
      final files = uploadInput.files;
      if (files == null || files.isEmpty) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      final file = files.first;
      if (!file.type.startsWith('image/')) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      if (file.size > _maxBytes) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }

      final reader = html.FileReader();
      reader.onLoadEnd.listen((_) {
        if (completer.isCompleted) return;
        final result = reader.result;
        Uint8List? bytes;
        if (result is Uint8List) {
          bytes = result;
        } else if (result is ByteBuffer) {
          bytes = result.asUint8List();
        } else if (result is List<int>) {
          bytes = Uint8List.fromList(result);
        }
        if (bytes == null) {
          completer.complete(null);
          return;
        }
        final name = (file.name.trim().isNotEmpty)
            ? file.name
            : 'store_${DateTime.now().millisecondsSinceEpoch}.jpg';
        completer.complete(PickedImageResult(bytes: bytes, fileName: name));
      });
      reader.onError.listen((_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      reader.readAsArrayBuffer(file);
    });

    // Cancelación: el usuario cierra el diálogo sin elegir archivo.
    void onFocus(_) {
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!completer.isCompleted &&
            (uploadInput.files == null || uploadInput.files!.isEmpty)) {
          completer.complete(null);
        }
      });
      html.window.removeEventListener('focus', onFocus);
    }

    html.window.addEventListener('focus', onFocus);
    uploadInput.click();

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => null,
    );
  }

  static Future<ImagePickSource?> _showImageSourceSheet(
    BuildContext context,
  ) {
    return showModalBottomSheet<ImagePickSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Seleccionar imagen',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('Tomar foto'),
                subtitle: const Text(
                  'Usar la cámara (mejor en móvil / tablet)',
                ),
                onTap: () => Navigator.pop(ctx, ImagePickSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Galería / archivo'),
                subtitle: const Text('Elegir una imagen del dispositivo'),
                onTap: () => Navigator.pop(ctx, ImagePickSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
