import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

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

  Future<String?> uploadStoreImage(int storeId, File imageFile) async {
    try {
      print('📤 Subiendo imagen de tienda...');
      
      // Generar nombre único para evitar conflictos
      final uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_tienda_$storeId.jpg';
      
      // Leer archivo como bytes
      final imageBytes = await imageFile.readAsBytes();
      
      // Subir imagen al bucket 'images_back' con opciones específicas
      final response = await _supabase.storage
          .from(_storageBucket)
          .uploadBinary(
            uniqueFileName,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir la imagen');
      }

      // Obtener URL pública de la imagen
      final publicUrl = _supabase.storage
          .from(_storageBucket)
          .getPublicUrl(uniqueFileName);

      print('✅ Imagen subida correctamente: $publicUrl');
      return publicUrl;
    } catch (e) {
      print('❌ Error subiendo imagen: $e');
      rethrow;
    }
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
}
