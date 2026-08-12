import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class StoreDataService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _storageBucket = 'images_back';

  Future<Map<String, dynamic>?> getStoreData(int storeId) async {
    try {
      final response = await _supabase
          .from('app_dat_tienda')
          .select()
          .eq('id', storeId)
          .single();
      return response;
    } catch (e) {
      print('❌ Error obteniendo datos de tienda: $e');
      rethrow;
    }
  }

  /// Sube bytes de imagen (compatible Android / web).
  Future<String?> uploadStoreImageBytes(
    int storeId,
    Uint8List imageBytes, {
    String? fileName,
  }) async {
    try {
      print('📤 Subiendo imagen de tienda...');

      final safeName = (fileName == null || fileName.trim().isEmpty)
          ? 'tienda.jpg'
          : fileName.trim().replaceAll(RegExp(r'[^\w.\-]+'), '_');
      final uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_tienda_${storeId}_$safeName';

      final response = await _supabase.storage.from(_storageBucket).uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir la imagen');
      }

      final publicUrl =
          _supabase.storage.from(_storageBucket).getPublicUrl(uniqueFileName);

      print('✅ Imagen subida correctamente: $publicUrl');
      return publicUrl;
    } catch (e) {
      print('❌ Error subiendo imagen: $e');
      rethrow;
    }
  }

  /// Compatibilidad: sube desde path local (solo plataformas con dart:io).
  @Deprecated('Usar uploadStoreImageBytes para Android y web')
  Future<String?> uploadStoreImage(int storeId, dynamic imageFile) async {
    final bytes = await imageFile.readAsBytes() as Uint8List;
    final name = imageFile.path?.toString().split(RegExp(r'[\\/]')).last;
    return uploadStoreImageBytes(storeId, bytes, fileName: name);
  }

  Future<bool> updateStoreData({
    required int storeId,
    String? denominacion,
    String? direccion,
    String? ubicacion,
    String? phone,
    String? pais,
    String? estado,
    String? nombrePais,
    String? nombreEstado,
    double? latitude,
    double? longitude,
    String? imagenUrl,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (denominacion != null) updateData['denominacion'] = denominacion;
      if (direccion != null) updateData['direccion'] = direccion;
      if (ubicacion != null) updateData['ubicacion'] = ubicacion;
      if (phone != null) updateData['phone'] = phone;
      if (pais != null) updateData['pais'] = pais;
      if (estado != null) updateData['estado'] = estado;
      if (nombrePais != null) updateData['nombre_pais'] = nombrePais;
      if (nombreEstado != null) updateData['nombre_estado'] = nombreEstado;
      if (latitude != null) updateData['latitude'] = latitude;
      if (longitude != null) updateData['longitude'] = longitude;

      if (latitude != null && longitude != null) {
        updateData['ubicacion'] = '$latitude,$longitude';
      }

      if (imagenUrl != null) updateData['imagen_url'] = imagenUrl;

      await _supabase
          .from('app_dat_tienda')
          .update(updateData)
          .eq('id', storeId);

      print('✅ Datos de tienda actualizados correctamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando datos de tienda: $e');
      rethrow;
    }
  }

  Future<bool> updateStoreField(
    int storeId,
    String fieldKey,
    dynamic value,
  ) async {
    try {
      print('🔄 Actualizando campo $fieldKey para tienda: $storeId');

      await _supabase.from('app_dat_tienda').update({
        fieldKey: value,
      }).eq('id', storeId);

      print('✅ Campo $fieldKey actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando campo $fieldKey: $e');
      rethrow;
    }
  }
}
