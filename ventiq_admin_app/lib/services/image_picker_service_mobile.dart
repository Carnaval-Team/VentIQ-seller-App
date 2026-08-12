import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum ImagePickSource { camera, gallery }

class PickedImageResult {
  final Uint8List bytes;
  final String fileName;

  const PickedImageResult({
    required this.bytes,
    required this.fileName,
  });
}

/// Mobile implementation: cámara o galería vía image_picker.
///
/// No usa permission_handler. En Android 13+ la galería usa el Photo Picker
/// del sistema (sin permiso de almacenamiento). La cámara pide CAMERA
/// automáticamente cuando hace falta.
class ImagePickerService {
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

      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: resolved == ImagePickSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        // Evita leer EXIF completo (puede disparar permisos extra en algunos OEMs).
        requestFullMetadata: false,
      );

      if (image == null) return null;

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;

      final name = image.name.trim().isNotEmpty
          ? image.name
          : 'store_${DateTime.now().millisecondsSinceEpoch}.jpg';

      return PickedImageResult(bytes: bytes, fileName: name);
    } on PlatformException catch (e) {
      debugPrint('❌ PlatformException picking image: ${e.code} ${e.message}');
      if (context != null && context.mounted) {
        final msg = _friendlyPermissionMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error picking image on mobile: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo seleccionar la imagen: $e')),
        );
      }
      return null;
    }
  }

  static String _friendlyPermissionMessage(PlatformException e) {
    final code = e.code.toLowerCase();
    if (code.contains('camera') ||
        code.contains('permission') ||
        (e.message?.toLowerCase().contains('permission') ?? false)) {
      return 'Permiso denegado. Actívalo en Ajustes > Apps > Inventtia Gestión '
          'para cámara o fotos, e inténtalo de nuevo.';
    }
    return 'No se pudo abrir ${e.code}: ${e.message ?? 'error desconocido'}';
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
                subtitle: const Text('Usar la cámara del dispositivo'),
                onTap: () => Navigator.pop(ctx, ImagePickSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('Galería'),
                subtitle: const Text('Elegir una imagen existente'),
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
