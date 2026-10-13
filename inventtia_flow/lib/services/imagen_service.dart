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

    await _supabase.storage
        .from(_bucket)
        .uploadBinary(
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

  // ── Cache-busting de imágenes reemplazadas ───────────────────────────────
  //
  // La foto se sube siempre al MISMO path (`locales/3.jpg`, `servicios/7.jpg`)
  // con `upsert: true`, así que la URL pública no cambia al reemplazarla. Sin
  // esto, el navegador (o la caché de `CachedNetworkImage`) sigue enseñando la
  // imagen vieja aunque la nueva ya esté subida.
  //
  // Se guarda la versión en memoria y sólo se añade al pintar, nunca al guardar
  // en la base de datos: así la columna `foto` sigue teniendo la URL limpia.
  static final Map<String, int> _versiones = {};
  static int _contadorVersiones = 0;

  /// Marca una URL como recién reemplazada para que se vuelva a descargar.
  static void invalidar(String? url) {
    if (url == null || url.isEmpty) return;
    _versiones[url] = ++_contadorVersiones;
  }

  /// URL lista para pintar, con el `?v=` de la última sustitución si la hubo.
  ///
  /// No toca las URLs firmadas (llevan `token=`) porque añadirles parámetros las
  /// invalida.
  static String conVersion(String? url) {
    if (url == null || url.isEmpty) return '';
    final version = _versiones[url];
    if (version == null) return url;
    if (!url.startsWith('http') || url.contains('token=')) return url;
    final separador = url.contains('?') ? '&' : '?';
    return '$url${separador}v=$version';
  }
}
