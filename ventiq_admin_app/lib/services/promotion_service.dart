import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promotion.dart';
import '../services/user_preferences_service.dart';
import '../services/store_selector_service.dart';

class PromotionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _prefsService = UserPreferencesService();
  final StoreSelectorService _storeSelectorService = StoreSelectorService();

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
      final storeIdInt = idTienda != null
          ? int.tryParse(idTienda)
          : await _storeSelectorService.getSelectedStoreId();
      if (storeIdInt == null) {
        throw Exception('No se encontró ID de tienda del usuario');
      }

      print('📢 Listando promociones para tienda: $storeIdInt');
      print(
        '📢 Parámetros: search=$search, estado=$estado, tipo=$tipoPromocion',
      );

      // Llamar a la función RPC fn_listar_promociones
      final response = await _supabase.rpc(
        'fn_listar_promociones',
        params: {
          'p_id_tienda': storeIdInt,
          'p_activas':
              estado, // Cambiar de p_estado a p_activas según la función
        },
      );

      print('📢 Respuesta promociones: $response');

      if (response == null) {
        print('⚠️ Respuesta nula, usando datos mock');
        return _getMockPromotions();
      }

      // La función retorna directamente una lista de promociones
      final List<dynamic> promotionsData = response is List ? response : [];

      if (promotionsData.isEmpty) {
        print('⚠️ No se encontraron promociones, usando datos mock');
        return _getMockPromotions();
      }

      print('✅ Procesando ${promotionsData.length} promociones de Supabase');

      // Convertir cada promoción del formato RPC al modelo
      final promotions =
          promotionsData
              .map((promotionData) {
                try {
                  // Mapear los campos de la función RPC al formato esperado por el modelo
                  final mappedData = {
                    'id': promotionData['id']?.toString(),
                    'codigo_promocion': promotionData['codigo_promocion'],
                    'nombre': promotionData['nombre'],
                    'descripcion': promotionData['descripcion'],
                    'valor_descuento': promotionData['valor_descuento'],
                    'fecha_inicio': promotionData['fecha_inicio'],
                    'fecha_fin':
                        promotionData['fecha_fin'], // Puede ser null para promociones sin vencimiento
                    'min_compra': promotionData['min_compra'],
                    'limite_usos': promotionData['limite_usos'],
                    'aplica_todo': promotionData['aplica_todo'],
                    'estado': promotionData['estado'],
                    'requiere_medio_pago': promotionData['requiere_medio_pago'],
                    'medio_pago_requerido':
                        promotionData['medio_pago_requerido'],
                    'tipo_promocion':
                        promotionData['tipo_promocion'], // Nombre del tipo
                    'tienda': promotionData['tienda'], // Nombre de la tienda
                    'id_tienda': storeIdInt.toString(),
                    'id_tipo_promocion': '1', // Valor por defecto
                    'created_at': DateTime.now().toIso8601String(),
                  };

                  final fechaFinText =
                      promotionData['fecha_fin'] != null
                          ? promotionData['fecha_fin'].toString()
                          : 'Sin vencimiento';
                  print(
                    '📝 Promoción mapeada: ${mappedData['nombre']} - ${mappedData['codigo_promocion']} (Vence: $fechaFinText)',
                  );

                  return Promotion.fromJson(mappedData);
                } catch (e) {
                  print('❌ Error procesando promoción: $e');
                  print('📄 Datos originales: $promotionData');
                  return null;
                }
              })
              .where((p) => p != null)
              .cast<Promotion>()
              .toList();

      // Aplicar filtros locales si es necesario
      var filteredPromotions = promotions;

      // Filtro por búsqueda de texto
      if (search != null && search.isNotEmpty) {
        filteredPromotions =
            filteredPromotions
                .where(
                  (p) =>
                      p.nombre.toLowerCase().contains(search.toLowerCase()) ||
                      p.codigoPromocion.toLowerCase().contains(
                        search.toLowerCase(),
                      ) ||
                      (p.descripcion?.toLowerCase().contains(
                            search.toLowerCase(),
                          ) ??
                          false),
                )
                .toList();
      }

      // Filtro por tipo de promoción
      if (tipoPromocion != null && tipoPromocion.isNotEmpty) {
        filteredPromotions =
            filteredPromotions
                .where(
                  (p) =>
                      p.tipoPromocionNombre?.toLowerCase() ==
                      tipoPromocion.toLowerCase(),
                )
                .toList();
      }

      // Filtro por rango de fechas
      if (fechaDesde != null) {
        filteredPromotions =
            filteredPromotions
                .where(
                  (p) =>
                      p.fechaInicio.isAfter(fechaDesde) ||
                      p.fechaInicio.isAtSameMomentAs(fechaDesde),
                )
                .toList();
      }

      if (fechaHasta != null) {
        filteredPromotions =
            filteredPromotions
                .where(
                  (p) =>
                      p.fechaFin ==
                          null || // Include promotions with no expiration
                      p.fechaFin!.isBefore(fechaHasta) ||
                      p.fechaFin!.isAtSameMomentAs(fechaHasta),
                )
                .toList();
      }

      print('✅ Retornando ${filteredPromotions.length} promociones filtradas');
      return filteredPromotions;
    } catch (e) {
      print('❌ Error listando promociones: $e');
      print('🔄 Usando datos mock como fallback');
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
      final storeId = await _storeSelectorService.getSelectedStoreId();
      
      if (userId == null || storeId == null) {
        throw Exception('No se encontraron datos de usuario o tienda');
      }

      // Obtener UUID del usuario autenticado desde Supabase
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Usuario no autenticado');
      }
      final userUuid = user.id;

      print('📢 Creando promoción: $promotionData');

      // Preparar parámetros según la estructura de fn_insertar_promocion
      final params = {
        'p_uuid_usuario': userUuid,
        'p_id_tienda': storeId,
        'p_id_tipo_promocion': promotionData['id_tipo_promocion'],
        'p_codigo_promocion': promotionData['codigo_promocion'],
        'p_nombre': promotionData['nombre'],
        'p_descripcion': promotionData['descripcion'],
        'p_valor_descuento': promotionData['valor_descuento'],
        'p_fecha_inicio': promotionData['fecha_inicio'],
        'p_fecha_fin': promotionData['fecha_fin'],
        'p_min_compra': promotionData['min_compra'],
        'p_limite_usos': promotionData['limite_usos'],
        'p_aplica_todo': promotionData['aplica_todo'],
        'p_requiere_medio_pago': promotionData['requiere_medio_pago'] ?? false,
        'p_id_medio_pago_requerido': promotionData['id_medio_pago_requerido'],
        'p_id_campana': null, // Por defecto null, se puede agregar al formulario más adelante
      };

      print('📢 Parámetros para fn_insertar_promocion: $params');

      final response = await _supabase.rpc(
        'fn_insertar_promocion',
        params: params,
      );

      print('✅ Respuesta de creación: $response');

      if (response == null) {
        throw Exception('No se recibió respuesta del servidor');
      }

      // La función retorna un objeto JSON con success, id y message
      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Error al crear promoción');
      }

      // Obtener la promoción creada usando el ID retornado
      final promotionId = response['id'];
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
      print('📝 Datos a actualizar: $promotionData');

      // Preparar parámetros según la estructura exacta de fn_actualizar_promocion
      final params = <String, dynamic>{};
      
      // Solo agregar parámetros que no sean null para usar COALESCE correctamente
      if (promotionData['nombre'] != null) {
        params['p_nombre'] = promotionData['nombre'];
      }
      if (promotionData['descripcion'] != null) {
        params['p_descripcion'] = promotionData['descripcion'];
      }
      if (promotionData['valor_descuento'] != null) {
        params['p_valor_descuento'] = promotionData['valor_descuento'];
      }
      if (promotionData['fecha_inicio'] != null) {
        params['p_fecha_inicio'] = promotionData['fecha_inicio'];
      }
      if (promotionData['fecha_fin'] != null) {
        params['p_fecha_fin'] = promotionData['fecha_fin'];
      }
      if (promotionData['min_compra'] != null) {
        params['p_min_compra'] = promotionData['min_compra'];
      }
      if (promotionData['limite_usos'] != null) {
        params['p_limite_usos'] = promotionData['limite_usos'];
      }
      if (promotionData['aplica_todo'] != null) {
        params['p_aplica_todo'] = promotionData['aplica_todo'];
      }
      if (promotionData['estado'] != null) {
        params['p_estado'] = promotionData['estado'];
      }
      if (promotionData['requiere_medio_pago'] != null) {
        params['p_requiere_medio_pago'] = promotionData['requiere_medio_pago'];
      }
      if (promotionData['id_medio_pago_requerido'] != null) {
        params['p_id_medio_pago_requerido'] = promotionData['id_medio_pago_requerido'];
      }
      
      // El ID es obligatorio
      params['p_id'] = int.parse(promotionId);

      print('📝 Parámetros para RPC: $params');

      final response = await _supabase.rpc(
        'fn_actualizar_promocion',
        params: params,
      );

      print('📝 Respuesta de actualización: $response');

      // La función retorna un booleano (FOUND), no un objeto con success
      if (response != true) {
        throw Exception('No se pudo actualizar la promoción');
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
        print('⚠️ Respuesta nula, usando datos mock');
        return _getMockPromotionTypes();
      }

      print('📋 Respuesta tipos promoción: $response');

      final List<dynamic> typesData =
          response is List ? response : response['data'] ?? [];

      if (typesData.isEmpty) {
        print('⚠️ No se encontraron tipos de promoción, usando datos mock');
        return _getMockPromotionTypes();
      }

      final types = typesData.map((t) => PromotionType.fromJson(t)).toList();
      print('✅ Cargados ${types.length} tipos de promoción desde Supabase');

      return types;
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
      final storeIdInt = idTienda != null
          ? int.tryParse(idTienda)
          : await _storeSelectorService.getSelectedStoreId();
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
