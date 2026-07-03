import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ImagenService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _bucket = 'flow-imagenes';

  /// Abre el selector de imagen (galería o cámara) y devuelve el XFile o null.
  static Future<XFile?> seleccionarImagen({
    ImageSource source = ImageSource.gallery,
  }) async {
    final picker = ImagePicker();
    return picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
  }

  /// Comprime y sube la imagen al bucket. Devuelve la URL pública.
  static Future<String> subirImagen({
    required XFile imagen,
    required String path,
  }) async {
    Uint8List bytes;
    
    if (kIsWeb) {
      // Web: Read bytes directly and compress in memory
      final originalBytes = await imagen.readAsBytes();
      final compressedBytes = await FlutterImageCompress.compressWithList(
        originalBytes,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      bytes = compressedBytes;
    } else {
      // Mobile: Use temporary directory for compression
      final tmpDir = await getTemporaryDirectory();
      final compressedPath = '${tmpDir.path}/upload_compressed.jpg';

      final compressed = await FlutterImageCompress.compressAndGetFile(
        imagen.path,
        compressedPath,
        quality: 80,
        format: CompressFormat.jpeg,
      );

      bytes = await (compressed ?? imagen).readAsBytes();
    }

    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }

  /// Elimina la imagen del bucket.
  static Future<void> eliminarImagen(String path) async {
    await _supabase.storage.from(_bucket).remove([path]);
  }

  /// Construye el path para un local.
  static String pathLocal(int idLocal) => 'locales/$idLocal.jpg';

  /// Construye el path para un servicio.
  static String pathServicio(int idServicio) => 'servicios/$idServicio.jpg';
}
