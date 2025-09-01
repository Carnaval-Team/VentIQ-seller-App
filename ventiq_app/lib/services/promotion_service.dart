import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class PromotionService {
  static final PromotionService _instance = PromotionService._internal();
  factory PromotionService() => _instance;
  PromotionService._internal();

  final _supabase = Supabase.instance.client;
  final _userPreferencesService = UserPreferencesService();

  /// Obtiene las promociones globales activas para la tienda
  /// Filtra por: id_tienda, aplica_todo = true, requiere_medio_pago = true, id_medio_pago_requerido = 1
  Future<Map<String, dynamic>?> getGlobalPromotion(int idTienda) async {
    try {
      print('🎯 PromotionService: Buscando promoción global para tienda $idTienda');
      
      final now = DateTime.now().toIso8601String();
      
      final response = await _supabase
          .from('app_mkt_promociones')
          .select('id, codigo_promocion, nombre, descripcion, valor_descuento, id_tipo_promocion')
          .eq('id_tienda', idTienda)
          .eq('aplica_todo', true)
          .eq('requiere_medio_pago', true)
          .eq('id_medio_pago_requerido', 1)
          .eq('estado', true)
          .lte('fecha_inicio', now)
          .gte('fecha_fin', now)
          .limit(1)
          .single();

      if (response.isNotEmpty) {
        print('✅ Promoción global encontrada:');
        print('  - ID: ${response['id']}');
        print('  - Código: ${response['codigo_promocion']}');
        print('  - Nombre: ${response['nombre']}');
        print('  - Valor Descuento: ${response['valor_descuento']}');
        print('  - Tipo Descuento: ${response['id_tipo_promocion']} (1=%, 2=fijo)');
        
        return {
          'id_promocion': response['id'],
          'codigo_promocion': response['codigo_promocion'],
          'nombre': response['nombre'],
          'descripcion': response['descripcion'],
          'valor_descuento': response['valor_descuento']?.toDouble(),
          'tipo_descuento': response['id_tipo_promocion'],
        };
      } else {
        print('ℹ️ No se encontró promoción global activa para la tienda');
        return null;
      }
    } catch (e) {
      print('❌ Error obteniendo promoción global: $e');
      return null;
    }
  }

  /// Guarda los datos de la promoción global en las preferencias
  /// Si no hay promoción, guarda null en todos los campos
  Future<void> saveGlobalPromotion({
    int? idPromocion,
    String? codigoPromocion,
    double? valorDescuento,
    int? tipoDescuento,
  }) async {
    try {
      await _userPreferencesService.savePromotionData(
        idPromocion: idPromocion,
        codigoPromocion: codigoPromocion,
        valorDescuento: valorDescuento,
        tipoDescuento: tipoDescuento,
      );
      
      if (idPromocion != null && codigoPromocion != null) {
        print('✅ Promoción global guardada en preferencias');
        print('  - Valor: $valorDescuento');
        print('  - Tipo: $tipoDescuento (1=%, 2=fijo)');
      } else {
        print('✅ Promoción global limpiada (null) en preferencias');
      }
    } catch (e) {
      print('❌ Error guardando promoción: $e');
    }
  }

  /// Obtiene la promoción global guardada
  Future<Map<String, dynamic>?> getSavedGlobalPromotion() async {
    try {
      return await _userPreferencesService.getPromotionData();
    } catch (e) {
      print('❌ Error obteniendo promoción guardada: $e');
      return null;
    }
  }

  /// Limpia la promoción global guardada
  Future<void> clearGlobalPromotion() async {
    try {
      await _userPreferencesService.clearPromotionData();
      print('✅ Promoción global limpiada');
    } catch (e) {
      print('❌ Error limpiando promoción: $e');
    }
  }
}
