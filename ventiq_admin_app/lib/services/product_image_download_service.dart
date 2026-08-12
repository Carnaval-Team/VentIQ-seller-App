import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'web_download_stub.dart'
    if (dart.library.html) 'web_download_web.dart' as web_download;

/// Descarga la imagen de un producto (web: archivo; móvil: compartir).
class ProductImageDownloadService {
  static Future<void> downloadProductImage({
    required String imageUrl,
    required String productName,
    String? sku,
  }) async {
    final url = imageUrl.trim();
    if (url.isEmpty) {
      throw Exception('El producto no tiene imagen');
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw Exception('No se pudo descargar la imagen (${response.statusCode})');
    }

    final bytes = Uint8List.fromList(response.bodyBytes);
    final contentType = response.headers['content-type'] ?? '';
    final ext = _extensionFrom(url, contentType);
    final mimeType = _mimeFromExtension(ext);
    final baseName = _sanitizeFileName(
      productName.trim().isNotEmpty
          ? productName.trim()
          : (sku?.trim().isNotEmpty == true ? sku!.trim() : 'producto'),
    );
    final fileName =
        '${baseName}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    if (kIsWeb) {
      web_download.downloadFileWeb(bytes, fileName, mimeType);
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: 'Imagen - $productName',
      text: 'Imagen del producto $productName',
    );
  }

  static String _sanitizeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    if (cleaned.isEmpty) return 'producto';
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  static String _extensionFrom(String url, String contentType) {
    final ct = contentType.toLowerCase();
    if (ct.contains('png')) return 'png';
    if (ct.contains('webp')) return 'webp';
    if (ct.contains('gif')) return 'gif';
    if (ct.contains('jpeg') || ct.contains('jpg')) return 'jpg';

    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    if (path.endsWith('.gif')) return 'gif';
    if (path.endsWith('.jpeg') || path.endsWith('.jpg')) return 'jpg';
    return 'jpg';
  }

  static String _mimeFromExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}
