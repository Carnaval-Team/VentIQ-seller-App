import 'package:supabase_flutter/supabase_flutter.dart';

class RatingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Usuario fijo para las calificaciones
  static const String _fixedUserId = '9c7afeaa-6135-44c5-a943-42cad8f81b05';

  /// Calificar la aplicación globalmente
  Future<void> submitAppRating({
    required double rating,
    String? comentario,
    String? userId,
  }) async {
    try {
      await _supabase.from('app_dat_application_rating').insert({
        'id_usuario': userId ?? _fixedUserId,
        'rating': rating,
        'comentario': comentario,
      });
      print('✅ Rating de aplicación enviado');
    } catch (e) {
      print('❌ Error enviando rating de aplicación: $e');
      rethrow;
    }
  }

  /// Calificar una tienda
  Future<void> submitStoreRating({
    required int storeId,
    required double rating,
    String? comentario,
    String? userId,
  }) async {
    try {
      await _supabase.from('app_dat_tienda_rating').insert({
        'id_tienda': storeId,
        'id_usuario': userId ?? _fixedUserId,
        'rating': rating,
        'comentario': comentario,
      });
      print('✅ Rating de tienda $storeId enviado');
    } catch (e) {
      print('❌ Error enviando rating de tienda: $e');
      rethrow;
    }
  }

  /// Calificar un producto
  Future<void> submitProductRating({
    required int productId,
    required double rating,
    String? comentario,
    String? userId,
  }) async {
    try {
      await _supabase.from('app_dat_producto_rating').insert({
        'id_producto': productId,
        'id_usuario': userId ?? _fixedUserId,
        'rating': rating,
        'comentario': comentario,
      });
      print('✅ Rating de producto $productId enviado');
    } catch (e) {
      print('❌ Error enviando rating de producto: $e');
      rethrow;
    }
  }

  /// Verificar si usuario ya calificó (Opcional, si se necesitara validación en UI)
  /// Retorna el rating anterior si existe, o null
  Future<Map<String, dynamic>?> getUserStoreRating(
    int storeId, {
    String? userId,
  }) async {
    try {
      final response = await _supabase
          .from('app_dat_tienda_rating')
          .select()
          .eq('id_tienda', storeId)
          .eq('id_usuario', userId ?? _fixedUserId)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUserProductRating(
    int productId, {
    String? userId,
  }) async {
    try {
      final response = await _supabase
          .from('app_dat_producto_rating')
          .select()
          .eq('id_producto', productId)
          .eq('id_usuario', userId ?? _fixedUserId)
          .maybeSingle();
      return response;
    } catch (e) {
      return null;
    }
  }
}
