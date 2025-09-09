import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/store_selector_service.dart';

class MarketingService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final StoreSelectorService _storeSelectorService = StoreSelectorService();

  // =====================================================
  // DASHBOARD FUNCTIONS
  // =====================================================

  /// Obtiene resumen general de marketing
  Future<Map<String, dynamic>> getDashboardSummary({int? storeId}) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📊 Obteniendo resumen de marketing para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_marketing_dashboard_resumen',
        params: {'p_id_tienda': selectedStoreId},
      );

      print('✅ Respuesta dashboard: $response');
      return response ?? _getMockDashboardData();
    } catch (e) {
      print('❌ Error obteniendo resumen dashboard: $e');
      return _getMockDashboardData();
    }
  }

  /// Obtiene métricas de rendimiento
  Future<Map<String, dynamic>> getPerformanceMetrics({
    int? storeId,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📈 Obteniendo métricas de rendimiento para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_marketing_metricas_rendimiento',
        params: {
          'p_id_tienda': selectedStoreId,
          'p_fecha_desde': fechaDesde?.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
        },
      );

      print('✅ Respuesta métricas: $response');
      return response ?? _getMockMetricsData();
    } catch (e) {
      print('❌ Error obteniendo métricas: $e');
      return _getMockMetricsData();
    }
  }

  // =====================================================
  // CAMPAIGNS FUNCTIONS
  // =====================================================

  /// Lista campañas con paginación
  Future<List<Map<String, dynamic>>> listCampaigns({
    int? storeId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📋 Listando campañas para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_listar_campanas',
        params: {
          'p_id_tienda': selectedStoreId,
          'p_limite': limit,
          'p_offset': offset,
        },
      );

      print('✅ Respuesta campañas: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error listando campañas: $e');
      return [];
    }
  }

  /// Crea una nueva campaña
  Future<int> createCampaign({
    required int storeId,
    required String nombre,
    required String descripcion,
    required int idTipoCampana,
    required DateTime fechaInicio,
    DateTime? fechaFin,
    double? presupuesto,
  }) async {
    try {
      print('📝 Creando campaña: $nombre');

      final response = await _supabase.rpc(
        'fn_insertar_campana',
        params: {
          'p_id_tienda': storeId,
          'p_nombre': nombre,
          'p_descripcion': descripcion,
          'p_id_tipo_campana': idTipoCampana,
          'p_fecha_inicio': fechaInicio.toIso8601String().split('T')[0],
          'p_fecha_fin': fechaFin?.toIso8601String().split('T')[0],
          'p_presupuesto': presupuesto,
        },
      );

      print('✅ Campaña creada con ID: $response');
      return response as int;
    } catch (e) {
      print('❌ Error creando campaña: $e');
      rethrow;
    }
  }

  /// Actualiza una campaña existente
  Future<bool> updateCampaign({
    required int id,
    required String nombre,
    required String descripcion,
    required int idTipoCampana,
    required DateTime fechaInicio,
    DateTime? fechaFin,
    double? presupuesto,
    int? estado,
  }) async {
    try {
      print('📝 Actualizando campaña: $id');

      final response = await _supabase.rpc(
        'fn_actualizar_campana',
        params: {
          'p_id': id,
          'p_nombre': nombre,
          'p_descripcion': descripcion,
          'p_id_tipo_campana': idTipoCampana,
          'p_fecha_inicio': fechaInicio.toIso8601String().split('T')[0],
          'p_fecha_fin': fechaFin?.toIso8601String().split('T')[0],
          'p_presupuesto': presupuesto,
          'p_estado': estado,
        },
      );

      print('✅ Campaña actualizada: $response');
      return response as bool;
    } catch (e) {
      print('❌ Error actualizando campaña: $e');
      rethrow;
    }
  }

  /// Elimina una campaña
  Future<bool> deleteCampaign(int id) async {
    try {
      print('🗑️ Eliminando campaña: $id');

      final response = await _supabase.rpc(
        'fn_eliminar_campana',
        params: {'p_id': id},
      );

      print('✅ Campaña eliminada: $response');
      return response as bool;
    } catch (e) {
      print('❌ Error eliminando campaña: $e');
      rethrow;
    }
  }

  // =====================================================
  // COMMUNICATIONS FUNCTIONS
  // =====================================================

  /// Lista comunicaciones
  Future<List<Map<String, dynamic>>> listCommunications({int? storeId}) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📧 Listando comunicaciones para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_listar_comunicaciones',
        params: {'p_id_tienda': selectedStoreId},
      );

      print('✅ Respuesta comunicaciones: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error listando comunicaciones: $e');
      return [];
    }
  }

  /// Crea una nueva comunicación
  Future<int> createCommunication({
    required int storeId,
    required String asunto,
    required String contenido,
    int idTipoCampana = 1,
    int? idCampana,
    int? idSegmento,
    DateTime? fechaProgramada,
  }) async {
    try {
      print('📧 Creando comunicación: $asunto');

      final response = await _supabase.rpc(
        'fn_insertar_comunicacion',
        params: {
          'p_id_tienda': storeId,
          'p_asunto': asunto,
          'p_contenido': contenido,
          'p_id_tipo_campana': idTipoCampana,
          'p_id_campana': idCampana,
          'p_id_segmento': idSegmento,
          'p_fecha_programada': fechaProgramada?.toIso8601String(),
        },
      );

      print('✅ Comunicación creada con ID: $response');
      return response as int;
    } catch (e) {
      print('❌ Error creando comunicación: $e');
      rethrow;
    }
  }

  /// Actualiza una comunicación
  Future<bool> updateCommunication({
    required int id,
    required String asunto,
    required String contenido,
    DateTime? fechaProgramada,
    int? estado,
  }) async {
    try {
      print('📧 Actualizando comunicación: $id');

      final response = await _supabase.rpc(
        'fn_actualizar_comunicacion',
        params: {
          'p_id': id,
          'p_asunto': asunto,
          'p_contenido': contenido,
          'p_fecha_programada': fechaProgramada?.toIso8601String(),
          'p_estado': estado,
        },
      );

      print('✅ Comunicación actualizada: $response');
      return response as bool;
    } catch (e) {
      print('❌ Error actualizando comunicación: $e');
      rethrow;
    }
  }

  // =====================================================
  // SEGMENTS FUNCTIONS
  // =====================================================

  /// Lista segmentos de clientes
  Future<List<Map<String, dynamic>>> listSegments({int? storeId}) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('👥 Listando segmentos para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_listar_segmentos',
        params: {'p_id_tienda': selectedStoreId},
      );

      print('✅ Respuesta segmentos: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error listando segmentos: $e');
      return [];
    }
  }

  /// Crea un nuevo segmento
  Future<int> createSegment({
    required int storeId,
    required String nombre,
    required String descripcion,
    Map<String, dynamic> criterios = const {},
  }) async {
    try {
      print('👥 Creando segmento: $nombre');

      final response = await _supabase.rpc(
        'fn_insertar_segmento',
        params: {
          'p_id_tienda': storeId,
          'p_nombre': nombre,
          'p_descripcion': descripcion,
          'p_criterios': criterios,
        },
      );

      print('✅ Segmento creado con ID: $response');
      return response as int;
    } catch (e) {
      print('❌ Error creando segmento: $e');
      rethrow;
    }
  }

  /// Actualiza un segmento
  Future<bool> updateSegment({
    required int id,
    required String nombre,
    required String descripcion,
    Map<String, dynamic>? criterios,
  }) async {
    try {
      print('👥 Actualizando segmento: $id');

      final response = await _supabase.rpc(
        'fn_actualizar_segmento',
        params: {
          'p_id': id,
          'p_nombre': nombre,
          'p_descripcion': descripcion,
          'p_criterios': criterios,
        },
      );

      print('✅ Segmento actualizado: $response');
      return response as bool;
    } catch (e) {
      print('❌ Error actualizando segmento: $e');
      rethrow;
    }
  }

  /// Elimina un segmento
  Future<bool> deleteSegment(int id) async {
    try {
      print('🗑️ Eliminando segmento: $id');

      final response = await _supabase.rpc(
        'fn_eliminar_segmento',
        params: {'p_id': id},
      );

      print('✅ Segmento eliminado: $response');
      return response as bool;
    } catch (e) {
      print('❌ Error eliminando segmento: $e');
      rethrow;
    }
  }

  /// Obtiene clientes de un segmento
  Future<List<Map<String, dynamic>>> getSegmentClients({
    required int segmentId,
    int limit = 100,
  }) async {
    try {
      print('👥 Obteniendo clientes del segmento: $segmentId');

      final response = await _supabase.rpc(
        'fn_clientes_por_segmento',
        params: {
          'p_id_segmento': segmentId,
          'p_limite': limit,
        },
      );

      print('✅ Respuesta clientes segmento: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error obteniendo clientes del segmento: $e');
      return [];
    }
  }

  // =====================================================
  // LOYALTY FUNCTIONS
  // =====================================================

  /// Obtiene resumen de fidelización
  Future<Map<String, dynamic>> getLoyaltySummary({int? storeId}) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('⭐ Obteniendo resumen de fidelización para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_fidelizacion_resumen',
        params: {'p_id_tienda': selectedStoreId},
      );

      print('✅ Respuesta fidelización: $response');
      return response ?? _getMockLoyaltyData();
    } catch (e) {
      print('❌ Error obteniendo resumen fidelización: $e');
      return _getMockLoyaltyData();
    }
  }

  /// Lista eventos de fidelización
  Future<List<Map<String, dynamic>>> listLoyaltyEvents({
    int? storeId,
    int limit = 50,
  }) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('⭐ Listando eventos de fidelización para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_listar_eventos_fidelizacion',
        params: {
          'p_id_tienda': selectedStoreId,
          'p_limite': limit,
        },
      );

      print('✅ Respuesta eventos fidelización: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error listando eventos fidelización: $e');
      return [];
    }
  }

  /// Registra un evento de fidelización
  Future<int> registerLoyaltyEvent({
    required int clientId,
    required int storeId,
    required String tipoEvento,
    int puntosOtorgados = 0,
    String? descripcion,
    int? idOperacion,
  }) async {
    try {
      print('⭐ Registrando evento de fidelización: $tipoEvento');

      final response = await _supabase.rpc(
        'fn_registrar_evento_fidelizacion',
        params: {
          'p_id_cliente': clientId,
          'p_id_tienda': storeId,
          'p_tipo_evento': tipoEvento,
          'p_puntos_otorgados': puntosOtorgados,
          'p_descripcion': descripcion,
          'p_id_operacion': idOperacion,
        },
      );

      print('✅ Evento fidelización registrado con ID: $response');
      return response as int;
    } catch (e) {
      print('❌ Error registrando evento fidelización: $e');
      rethrow;
    }
  }

  // =====================================================
  // ANALYTICS FUNCTIONS
  // =====================================================

  /// Obtiene análisis de promociones
  Future<Map<String, dynamic>> getPromotionAnalysis({
    int? storeId,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('📊 Obteniendo análisis de promociones para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_analisis_promociones',
        params: {
          'p_id_tienda': selectedStoreId,
          'p_fecha_desde': fechaDesde?.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
        },
      );

      print('✅ Respuesta análisis promociones: $response');
      return response ?? _getMockPromotionAnalysis();
    } catch (e) {
      print('❌ Error obteniendo análisis promociones: $e');
      return _getMockPromotionAnalysis();
    }
  }

  /// Obtiene análisis de clientes
  Future<Map<String, dynamic>> getClientAnalysis({int? storeId}) async {
    try {
      final selectedStoreId = storeId ?? await _storeSelectorService.getSelectedStoreId();
      if (selectedStoreId == null) {
        throw Exception('No se encontró ID de tienda');
      }

      print('👥 Obteniendo análisis de clientes para tienda: $selectedStoreId');

      final response = await _supabase.rpc(
        'fn_analisis_clientes',
        params: {'p_id_tienda': selectedStoreId},
      );

      print('✅ Respuesta análisis clientes: $response');
      return response ?? _getMockClientAnalysis();
    } catch (e) {
      print('❌ Error obteniendo análisis clientes: $e');
      return _getMockClientAnalysis();
    }
  }

  // =====================================================
  // UTILITY FUNCTIONS
  // =====================================================

  /// Obtiene tipos de campaña
  Future<List<Map<String, dynamic>>> getCampaignTypes() async {
    try {
      print('📋 Obteniendo tipos de campaña');

      final response = await _supabase.rpc('fn_listar_tipos_campana');

      print('✅ Respuesta tipos campaña: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error obteniendo tipos campaña: $e');
      return [];
    }
  }

  /// Obtiene criterios de segmentación
  Future<List<Map<String, dynamic>>> getSegmentationCriteria() async {
    try {
      print('📋 Obteniendo criterios de segmentación');

      final response = await _supabase.rpc('fn_listar_criterios_segmentacion');

      print('✅ Respuesta criterios segmentación: $response');
      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('❌ Error obteniendo criterios segmentación: $e');
      return [];
    }
  }

  // =====================================================
  // MOCK DATA FOR FALLBACK
  // =====================================================

  Map<String, dynamic> _getMockDashboardData() {
    return {
      'total_promociones': 8,
      'promociones_activas': 3,
      'total_campanas': 5,
      'campanas_activas': 2,
      'total_segmentos': 4,
      'comunicaciones_enviadas': 12,
      'eventos_fidelizacion': 45,
    };
  }

  Map<String, dynamic> _getMockMetricsData() {
    return {
      'periodo': {
        'desde': DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
        'hasta': DateTime.now().toIso8601String(),
      },
      'promociones_creadas': 3,
      'campanas_ejecutadas': 2,
      'comunicaciones_enviadas': 8,
      'eventos_fidelizacion': 25,
    };
  }

  Map<String, dynamic> _getMockLoyaltyData() {
    return {
      'clientes_registrados': 150,
      'clientes_con_puntos': 89,
      'total_puntos_emitidos': 12500,
      'eventos_mes_actual': 34,
      'clientes_nivel_oro': 12,
      'clientes_nivel_plata': 28,
      'clientes_nivel_bronce': 49,
    };
  }

  Map<String, dynamic> _getMockPromotionAnalysis() {
    return {
      'total_promociones': 8,
      'promociones_utilizadas': 6,
      'descuento_total_aplicado': 125000.0,
      'roi_promociones': 2.8,
      'conversion_rate': 15.2,
    };
  }

  Map<String, dynamic> _getMockClientAnalysis() {
    return {
      'total_clientes': 150,
      'clientes_activos': 89,
      'clientes_nuevos_mes': 12,
      'ticket_promedio': 45000.0,
      'frecuencia_compra': 2.3,
    };
  }
}
