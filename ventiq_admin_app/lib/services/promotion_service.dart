import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promotion.dart';
import '../services/user_preferences_service.dart';

class PromotionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _prefsService = UserPreferencesService();

  /// Lista promociones con filtros y paginación
  Future<List<Promotion>> listPromotions({
    String? idTienda,
    String? search,
    bool? estado,
    String? tipoPromocion,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // Obtener ID de tienda del usuario si no se especifica
      final storeIdInt =
          idTienda != null
              ? int.tryParse(idTienda)
              : await _prefsService.getIdTienda();
      if (storeIdInt == null) {
        throw Exception('No se encontró ID de tienda del usuario');
      }

      print('📢 Listando promociones para tienda: $storeIdInt');

      // Usar función RPC para listar promociones (asumiendo que existe)
      final response = await _supabase.rpc(
        'fn_listar_promociones',
        params: {
          'p_id_tienda': storeIdInt,
          'p_busqueda': search,
          'p_estado': estado,
          'p_tipo_promocion': tipoPromocion,
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
          'p_pagina': page,
          'p_limite': limit,
        },
      );

      print('📢 Respuesta promociones: $response');

      if (response == null) {
        return [];
      }

      final List<dynamic> promotionsData =
          response is List ? response : response['data'] ?? [];

      return promotionsData.map((p) => Promotion.fromJson(p)).toList();
    } catch (e) {
      print('❌ Error listando promociones: $e');
      // Fallback a datos mock
      return _getMockPromotions();
    }
  }

  /// Valida una promoción para una venta específica
  Future<PromotionValidationResult> validatePromotion({
    required String codigoPromocion,
    required String idTienda,
    List<Map<String, dynamic>>? productos,
  }) async {
    try {
      print('🔍 Validando promoción: $codigoPromocion');

      // Usar la función RPC fn_validar_promocion_venta
      final response = await _supabase.rpc(
        'fn_validar_promocion_venta',
        params: {
          'p_codigo_promocion': codigoPromocion,
          'p_id_tienda': int.parse(idTienda),
          'p_productos': productos,
        },
      );

      print('✅ Resultado validación: $response');

      if (response == null) {
        return PromotionValidationResult(
          valida: false,
          mensaje: 'No se pudo validar la promoción',
        );
      }

      return PromotionValidationResult.fromJson(response);
    } catch (e) {
      print('❌ Error validando promoción: $e');
      return PromotionValidationResult(
        valida: false,
        mensaje: 'Error al validar promoción: $e',
      );
    }
  }

  /// Crea una nueva promoción
  Future<Promotion> createPromotion(Map<String, dynamic> promotionData) async {
    try {
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      print('📢 Creando promoción: $promotionData');

      // Usar función RPC para crear promoción
      final response = await _supabase.rpc(
        'fn_crear_promocion_completa',
        params: {
          'p_promocion_data': promotionData,
          'p_productos_data': promotionData['productos'] ?? [],
          'p_usuario_creador': userId,
        },
      );

      print('✅ Promoción creada: $response');

      if (response == null || response['success'] != true) {
        throw Exception(response?['message'] ?? 'Error al crear promoción');
      }

      // Obtener la promoción creada
      final promotionId = response['data']['id_promocion'];
      return await getPromotionById(promotionId.toString());
    } catch (e) {
      print('❌ Error creando promoción: $e');
      rethrow;
    }
  }

  /// Actualiza una promoción existente
  Future<Promotion> updatePromotion(
    String promotionId,
    Map<String, dynamic> promotionData,
  ) async {
    try {
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      print('📝 Actualizando promoción: $promotionId');

      final response = await _supabase.rpc(
        'fn_actualizar_promocion',
        params: {
          'p_id_promocion': int.parse(promotionId),
          'p_promocion_data': promotionData,
          'p_usuario_modificador': userId,
        },
      );

      if (response == null || response['success'] != true) {
        throw Exception(
          response?['message'] ?? 'Error al actualizar promoción',
        );
      }

      return await getPromotionById(promotionId);
    } catch (e) {
      print('❌ Error actualizando promoción: $e');
      rethrow;
    }
  }

  /// Elimina una promoción
  Future<void> deletePromotion(String promotionId) async {
    try {
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      print('🗑️ Eliminando promoción: $promotionId');

      final response = await _supabase.rpc(
        'fn_eliminar_promocion',
        params: {
          'p_id_promocion': int.parse(promotionId),
          'p_usuario_eliminador': userId,
        },
      );

      if (response == null || response['success'] != true) {
        throw Exception(response?['message'] ?? 'Error al eliminar promoción');
      }
    } catch (e) {
      print('❌ Error eliminando promoción: $e');
      rethrow;
    }
  }

  /// Obtiene una promoción por ID
  Future<Promotion> getPromotionById(String promotionId) async {
    try {
      print('🔍 Obteniendo promoción: $promotionId');

      final response = await _supabase.rpc(
        'fn_obtener_promocion_detalle',
        params: {'p_id_promocion': int.parse(promotionId)},
      );

      if (response == null) {
        throw Exception('Promoción no encontrada');
      }

      return Promotion.fromJson(response);
    } catch (e) {
      print('❌ Error obteniendo promoción: $e');
      rethrow;
    }
  }

  /// Activa o desactiva una promoción
  Future<void> togglePromotionStatus(String promotionId, bool estado) async {
    try {
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      print('🔄 Cambiando estado promoción $promotionId a: $estado');

      final response = await _supabase.rpc(
        'fn_cambiar_estado_promocion',
        params: {
          'p_id_promocion': int.parse(promotionId),
          'p_nuevo_estado': estado,
          'p_usuario_modificador': userId,
        },
      );

      if (response == null || response['success'] != true) {
        throw Exception(response?['message'] ?? 'Error al cambiar estado');
      }
    } catch (e) {
      print('❌ Error cambiando estado promoción: $e');
      rethrow;
    }
  }

  /// Obtiene tipos de promoción disponibles
  Future<List<PromotionType>> getPromotionTypes() async {
    try {
      print('📋 Obteniendo tipos de promoción');

      final response = await _supabase.rpc('fn_listar_tipos_promocion');

      if (response == null) {
        return _getMockPromotionTypes();
      }

      final List<dynamic> typesData =
          response is List ? response : response['data'] ?? [];

      return typesData.map((t) => PromotionType.fromJson(t)).toList();
    } catch (e) {
      print('❌ Error obteniendo tipos promoción: $e');
      return _getMockPromotionTypes();
    }
  }

  /// Obtiene estadísticas de promociones
  Future<Map<String, dynamic>> getPromotionStats({
    String? idTienda,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final storeIdInt =
          idTienda != null
              ? int.tryParse(idTienda)
              : await _prefsService.getIdTienda();
      if (storeIdInt == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📊 Obteniendo estadísticas promociones');

      final response = await _supabase.rpc(
        'fn_estadisticas_promociones',
        params: {
          'p_id_tienda': storeIdInt,
          'p_fecha_desde': fechaDesde?.toIso8601String(),
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
        },
      );

      return response ?? _getMockStats();
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return _getMockStats();
    }
  }

  /// Genera código promocional único
  Future<String> generatePromotionCode({String? prefix}) async {
    try {
      final response = await _supabase.rpc(
        'fn_generar_codigo_promocion',
        params: {'p_prefijo': prefix},
      );

      return response?['codigo'] ?? _generateMockCode(prefix);
    } catch (e) {
      print('❌ Error generando código: $e');
      return _generateMockCode(prefix);
    }
  }

  // Métodos de datos mock para fallback
  List<Promotion> _getMockPromotions() {
    return [
      Promotion(
        id: '1',
        idTienda: '1',
        idTipoPromocion: '1',
        nombre: 'Descuento Verano 2024',
        descripcion: 'Descuento especial para productos de temporada',
        codigoPromocion: 'VERANO2024',
        valorDescuento: 15.0,
        minCompra: 50000.0,
        fechaInicio: DateTime.now().subtract(const Duration(days: 5)),
        fechaFin: DateTime.now().add(const Duration(days: 25)),
        estado: true,
        aplicaTodo: false,
        limiteUsos: 100,
        usosActuales: 23,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        tipoPromocion: PromotionType(
          id: '1',
          denominacion: 'Descuento Porcentual',
          descripcion: 'Descuento basado en porcentaje',
          icono: 'percent',
          createdAt: DateTime.now(),
        ),
      ),
      Promotion(
        id: '2',
        idTienda: '1',
        idTipoPromocion: '2',
        nombre: '2x1 en Bebidas',
        descripcion: 'Lleva 2 y paga 1 en bebidas seleccionadas',
        codigoPromocion: '2X1BEBIDAS',
        valorDescuento: 0.0,
        fechaInicio: DateTime.now().subtract(const Duration(days: 2)),
        fechaFin: DateTime.now().add(const Duration(days: 12)),
        estado: true,
        aplicaTodo: false,
        limiteUsos: 50,
        usosActuales: 8,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        tipoPromocion: PromotionType(
          id: '2',
          denominacion: '2x1',
          descripcion: 'Promoción dos por uno',
          icono: 'two_for_one',
          createdAt: DateTime.now(),
        ),
      ),
    ];
  }

  List<PromotionType> _getMockPromotionTypes() {
    return [
      PromotionType(
        id: '1',
        denominacion: 'Descuento Porcentual',
        descripcion: 'Descuento basado en porcentaje del total',
        icono: 'percent',
        createdAt: DateTime.now(),
      ),
      PromotionType(
        id: '2',
        denominacion: 'Descuento Fijo',
        descripcion: 'Descuento de monto fijo',
        icono: 'money_off',
        createdAt: DateTime.now(),
      ),
      PromotionType(
        id: '3',
        denominacion: '2x1',
        descripcion: 'Promoción dos por uno',
        icono: 'two_for_one',
        createdAt: DateTime.now(),
      ),
      PromotionType(
        id: '4',
        denominacion: 'Puntos Extra',
        descripcion: 'Puntos adicionales para el cliente',
        icono: 'stars',
        createdAt: DateTime.now(),
      ),
    ];
  }

  Map<String, dynamic> _getMockStats() {
    return {
      'total_promociones': 12,
      'promociones_activas': 5,
      'promociones_vencidas': 4,
      'promociones_programadas': 3,
      'total_usos': 156,
      'descuento_total_aplicado': 245000.0,
      'roi_promociones': 3.2,
      'conversion_rate': 12.5,
    };
  }

  String _generateMockCode(String? prefix) {
    final random = DateTime.now().millisecondsSinceEpoch.toString().substring(
      8,
    );
    return '${prefix ?? 'PROMO'}$random';
  }
}
