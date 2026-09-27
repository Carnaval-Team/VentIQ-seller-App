import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/home_banner.dart';

class HomeBannersService {
  static final _supabase = Supabase.instance.client;
  // Usamos el mismo bucket probado para imágenes de tienda/categorías.
  static const _bucket = 'images_back';
  static const _folder = 'banners';

  static Future<List<HomeBanner>> listBanners() async {
    final response = await _supabase
        .schema('carnavalapp')
        .rpc('fn_admin_home_banners_list') as List<dynamic>?;

    return response
            ?.map((item) => HomeBanner.fromJson(item as Map<String, dynamic>))
            .toList() ??
        [];
  }

  static Future<HomeBanner> upsertBanner({
    int? id,
    String? imageUrl,
    String? link,
    String? descripcion,
    required int orden,
    required bool activo,
  }) async {
    final response = await _supabase
        .schema('carnavalapp')
        .rpc('fn_admin_home_banners_upsert', params: {
      'p_id': id,
      'p_image_url': imageUrl,
      'p_link': link,
      'p_descripcion': descripcion,
      'p_orden': orden,
      'p_activo': activo,
    });

    if (response == null) {
      throw Exception('No se recibió respuesta del servidor');
    }

    if (response is List) {
      if (response.isEmpty) {
        throw Exception('No se recibió respuesta del servidor');
      }
      return HomeBanner.fromJson(response.first as Map<String, dynamic>);
    }

    return HomeBanner.fromJson(response as Map<String, dynamic>);
  }

  static Future<void> deleteBanner(int id, {bool hard = false}) async {
    await _supabase.schema('carnavalapp').rpc('fn_admin_home_banners_delete', params: {
      'p_id': id,
      'p_hard': hard,
    });
  }

  static Future<String> uploadImage(Uint8List bytes, {String? fileName}) async {
    final safeName = (fileName == null || fileName.trim().isEmpty)
        ? 'banner.jpg'
        : fileName.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final name = '$_folder/${DateTime.now().millisecondsSinceEpoch}_home_banner_$safeName';

    try {
      await _supabase.storage.from(_bucket).uploadBinary(
            name,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      return _supabase.storage.from(_bucket).getPublicUrl(name);
    } catch (e) {
      debugPrint('Error subiendo imagen del banner: $e');
      rethrow;
    }
  }
}
