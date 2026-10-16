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
          fileOptions: FileOptions(
            contentType: _contentTypeDe(bytes),
            upsert: true,
          ),
        );

    return _urlVersionada(_supabase.storage.from(_bucket).getPublicUrl(path));
  }

  /// `Content-Type` según los primeros bytes REALES del archivo.
  ///
  /// La compresión a JPEG puede fallar (sobre todo en web, con formatos que el
  /// compresor no entiende) y entonces se suben los bytes originales. Etiquetar
  /// siempre como JPEG dejaba un PNG servido como `image/jpeg`.
  static String _contentTypeDe(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /// Añade el sello de versión a la URL pública de una foto recién subida.
  ///
  /// **Por qué es necesario:** la foto se sube siempre al MISMO path
  /// (`locales/3.jpg`, `servicios/7.jpg`), así que la URL pública es idéntica
  /// antes y después de reemplazarla. Y una URL idéntica no se vuelve a pedir:
  /// `CachedNetworkImage` guarda en disco por URL (30 días por defecto) y el CDN
  /// de Storage también cachea, así que **los clientes seguirían viendo la foto
  /// vieja**. Con el sello dentro de la columna `foto`, la URL cambia al
  /// reemplazarla y todo el mundo descarga la nueva.
  ///
  /// El sello viaja en la URL guardada, no en un `Map` en memoria: por eso
  /// también funciona para un cliente que abre la app al día siguiente.
  static String _urlVersionada(String url) {
    final sello = DateTime.now().millisecondsSinceEpoch;
    return url.contains('?') ? '$url&v=$sello' : '$url?v=$sello';
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
  /// invalida, ni las que **ya traen** un sello de versión (hoy todas las fotos
  /// recién subidas lo llevan dentro): repetirlo daría `?v=1&v=2`.
  static String conVersion(String? url) {
    if (url == null || url.isEmpty) return '';
    final version = _versiones[url];
    if (version == null) return url;
    if (!url.startsWith('http') || url.contains('token=')) return url;
    if (url.contains('v=')) return url;
    final separador = url.contains('?') ? '&' : '?';
    return '$url${separador}v=$version';
  }
}
