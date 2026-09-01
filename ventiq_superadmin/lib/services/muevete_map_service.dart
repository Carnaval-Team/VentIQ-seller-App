import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MueveteMapService {
  static final _supabase = Supabase.instance.client;

  static const _remoteBucket = 'muevete';
  static const _remotePath = 'maps/cuba.mbtiles';

  /// Uploads a local .mbtiles file to Supabase Storage and records the version.
  static Future<void> uploadMbtiles(
    String localFilePath, {
    int version = 1,
  }) async {
    final file = File(localFilePath);
    if (!file.existsSync()) {
      throw Exception('Archivo no encontrado: $localFilePath');
    }
    final bytes = await file.readAsBytes();

    await _supabase.storage.from(_remoteBucket).uploadBinary(
          _remotePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    try {
      await _supabase.schema('muevete').from('map_versions').upsert({
        'id': 1,
        'version': version,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[MueveteMapService] Could not record version: $e');
    }
  }
}
