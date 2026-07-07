import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promotion.dart';
import '../models/product.dart';
import '../services/user_preferences_service.dart';
import '../services/store_selector_service.dart';
import '../services/payment_method_service.dart';
import '../models/payment_method.dart';

class PromotionService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _prefsService = UserPreferencesService();
  
  // Usar una instancia compartida o crear una nueva si es necesario
  StoreSelectorService? _storeSelectorService;
  
  StoreSelectorService get _storeService {
    _storeSelectorService ??= StoreSelectorService();
    return _storeSelectorService!;
  }

  /// Lista promociones con filtros y paginación
  Future<List<Promotion>> listPromotions({
    dynamic idTienda,
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
      final storeIdInt = await _getStoreId(idTienda);
      if (storeIdInt == null) {
        throw Exception('No se encontró ID de tienda del usuario');
      }

      print('📢 Listando promociones para tienda: $storeIdInt');
      print(
        '📢 Parámetros: search=$search, estado=$estado, tipo=$tipoPromocion',
      );

      // Llamar a la función RPC fn_listar_promociones2
      final response = await _supabase.rpc(
        'fn_listar_promociones2',
        params: {
          'p_id_tienda': storeIdInt,
          'p_activas':
              estado, // Cambiar de p_estado a p_activas según la función
        },
      );

      print('📢 Respuesta promociones: $response');

      if (response == null) {
        print('⚠️ Respuesta nula del servidor');
        return [];
      }

      // La función retorna directamente una lista de promociones
      final List<dynamic> promotionsData = response is List ? response : [];

      if (promotionsData.isEmpty) {
        print('⚠️ No se encontraron promociones');
        return [];
      }

      print('✅ Procesando ${promotionsData.length} promociones de Supabase');

      // Convertir cada promoción del formato RPC al modelo
      final promotions =
          promotionsData
              .map((promotionData) {
                try {
                  final dynamic rawTypeId =
                      promotionData['id_tipo_promocion'] ??
                      promotionData['idTipoPromocion'] ??
                      promotionData['tipo_promocion_id'] ??
                      promotionData['id_tipo'] ??
                      promotionData['tipo_id'];
                  final typeIdString =
                      rawTypeId != null ? rawTypeId.toString() : null;

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
                    // CRÍTICO: usar el tipo REAL retornado por el RPC.
                    // No forzar defaults: eso hace que al editar se modifique el tipo sin tocarlo.
                    'id_tipo_promocion': typeIdString,
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
      return [];
    }
  }

  /// Valida una promoción para una venta específica
  Future<PromotionValidationResult> validatePromotion({
    required String codigoPromocion,
    required dynamic idTienda,
    List<Map<String, dynamic>>? productos,
  }) async {
    try {
      print('🔍 Validando promoción: $codigoPromocion');

      // Usar la función RPC fn_validar_promocion_venta
      final response = await _supabase.rpc(
        'fn_validar_promocion_venta',
        params: {
          'p_codigo_promocion': codigoPromocion,
          'p_id_tienda': idTienda is int ? idTienda : int.tryParse(idTienda.toString()) ?? 0,
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

  /// Actualiza una promoción existente
  Future<Promotion> updatePromotion(
    String promotionId,
    Map<String, dynamic> promotionData,
  ) async {
    try {
      print('📝 Actualizando promoción: $promotionId');
      print('📝 Datos a actualizar: $promotionData');

      // Obtener ID de usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      // Preparar parámetros según la estructura exacta de fn_actualizar_promocion
      final params = <String, dynamic>{
        'p_id': int.parse(promotionId), // ID es obligatorio
        'p_uuid_usuario': userId, // UUID del usuario autenticado
      };
      
      // Solo agregar parámetros que no sean null para usar COALESCE correctamente
      if (promotionData['nombre'] != null) {
        params['p_nombre'] = promotionData['nombre'];
      }
      if (promotionData['codigo_promocion'] != null) {
        params['p_codigo_promocion'] = promotionData['codigo_promocion'];
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
      if (promotionData['id_tipo_promocion'] != null) {
        params['p_id_tipo_promocion'] = int.tryParse(promotionData['id_tipo_promocion']?.toString() ?? '1') ?? 1;
      }
      if (promotionData['requiere_medio_pago'] != null) {
        params['p_requiere_medio_pago'] = promotionData['requiere_medio_pago'];
      }
      if (promotionData['id_medio_pago_requerido'] != null) {
        params['p_id_medio_pago_requerido'] = promotionData['id_medio_pago_requerido'];
      }

      print('📝 Parámetros para RPC: $params');

      final response = await _supabase.rpc(
        'fn_actualizar_promocion',
        params: params,
      );

      print('📝 Respuesta de actualización: $response');

      // La función SQL ahora retorna JSONB con success, message, etc.
      if (response == null) {
        throw Exception('No se recibió respuesta del servidor');
      }

      final Map<String, dynamic> result = response is Map<String, dynamic> 
          ? response 
          : {'success': false, 'message': 'Respuesta inválida del servidor'};

      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Error desconocido al actualizar promoción');
      }

      print('✅ Promoción actualizada exitosamente');
      
      // Obtener la promoción actualizada
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

      if (response != true) {
        throw Exception('Error al eliminar promoción');
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

      // Intentar obtener desde la lista de promociones ya que fn_obtener_promocion_detalle no existe
      final promotions = await listPromotions();
      final promotion = promotions.firstWhere(
        (p) => p.id == promotionId,
        orElse: () => throw Exception('Promoción no encontrada'),
      );

      return promotion;
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

      if (response != true) {
        throw Exception('Error al cambiar estado');
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
        print('⚠️ Respuesta nula del servidor');
        return [];
      }

      print('📋 Respuesta tipos promoción: $response');

      final List<dynamic> typesData =
          response is List ? response : response['data'] ?? [];

      if (typesData.isEmpty) {
        print('⚠️ No se encontraron tipos de promoción');
        return [];
      }

      final types = typesData.map((t) => PromotionType.fromJson(t)).toList();
      print('✅ Cargados ${types.length} tipos de promoción desde Supabase');

      return types;
    } catch (e) {
      print('❌ Error obteniendo tipos promoción: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getPromotionStats({
    dynamic idTienda,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
  }) async {
    try {
      final storeIdInt = await _getStoreId(idTienda);
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

      return response ?? {};
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {};
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

  /// Crea una nueva promoción
  Future<Promotion> createPromotion(Map<String, dynamic> promotionData) async {
    try {
      print('📝 Creando nueva promoción');
      print('📝 Datos de promoción: $promotionData');

      // Obtener ID de tienda del usuario
      final storeIdInt = await _getStoreId(promotionData['id_tienda']);
      if (storeIdInt == null) {
        throw Exception('No se encontró ID de tienda del usuario');
      }

      // Obtener UUID de usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      // Preparar parámetros para la función RPC
      final params = <String, dynamic>{
        'p_uuid_usuario': userId,
        'p_id_tienda': storeIdInt,
        'p_id_tipo_promocion': int.tryParse(promotionData['id_tipo_promocion']?.toString() ?? '1') ?? 1,
        'p_codigo_promocion': promotionData['codigo_promocion'],
        'p_nombre': promotionData['nombre'],
        'p_fecha_inicio': promotionData['fecha_inicio'],
        'p_id_campana': promotionData['id_campana'],
        'p_descripcion': promotionData['descripcion'],
        'p_valor_descuento': promotionData['valor_descuento'],
        'p_fecha_fin': promotionData['fecha_fin'],
        'p_min_compra': promotionData['min_compra'],
        'p_limite_usos': promotionData['limite_usos'],
        'p_aplica_todo': promotionData['aplica_todo'] ?? false,
        'p_requiere_medio_pago': promotionData['requiere_medio_pago'] ?? false,
        'p_id_medio_pago_requerido': promotionData['id_medio_pago_requerido'],
      };

      print('📝 Parámetros para RPC: $params');

      final response = await _supabase.rpc(
        'fn_insertar_promocion',
        params: params,
      );

      print('📝 Respuesta de creación: $response');

      if (response == null) {
        throw Exception('No se recibió respuesta del servidor');
      }

      // La nueva función retorna un JSON con success, id y message
      if (response is Map<String, dynamic>) {
        final success = response['success'] as bool?;
        final message = response['message'] as String?;
        
        if (success != true) {
          throw Exception(message ?? 'Error desconocido al crear la promoción');
        }
        
        final promotionId = response['id']?.toString();
        if (promotionId == null) {
          throw Exception('No se pudo obtener el ID de la promoción creada');
        }

        print('✅ Promoción creada exitosamente con ID: $promotionId');
        
        // Obtener la promoción recién creada
        return await getPromotionById(promotionId);
      } else {
        throw Exception('Formato de respuesta inesperado del servidor');
      }
    } catch (e) {
      print('❌ Error creando promoción: $e');
      rethrow;
    }
  }

  /// Agrega productos específicos a una promoción
  Future<void> addProductsToPromotion(String promotionId, List<Product> products) async {
    try {
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró ID de usuario');
      }

      print('📝 Agregando ${products.length} productos a promoción: $promotionId');

      for (final product in products) {
        final categoryId = int.tryParse(product.categoryId);
        Map<String, dynamic>? matchedSubcategory;
        if (product.subcategorias.isNotEmpty) {
          matchedSubcategory = product.subcategorias.firstWhere(
            (subcat) {
              final subcatCategoryId =
                  subcat['idcategoria'] ?? subcat['id_categoria'];
              if (categoryId == null || subcatCategoryId == null) {
                return true;
              }
              return subcatCategoryId.toString() == categoryId.toString();
            },
            orElse: () => product.subcategorias.first,
          );
        }

        final rawSubcategoryId = matchedSubcategory == null
            ? null
            : (matchedSubcategory['id'] ??
                matchedSubcategory['id_sub_categoria'] ??
                matchedSubcategory['id_subcategoria']);
        final subcategoryId = rawSubcategoryId == null
            ? null
            : int.tryParse(rawSubcategoryId.toString());

        final response = await _supabase.rpc(
          'fn_agregar_producto_promocion',
          params: {
            'p_id_promocion': int.parse(promotionId),
            'p_id_producto': int.parse(product.id),
            'p_id_categoria': categoryId,
            'p_id_subcategoria': subcategoryId,
            'p_uuid_usuario': userId,
          },
        );

        print('📝 Respuesta agregar producto ${product.name}: $response');

        if (response == null || response['success'] != true) {
          throw Exception(response?['message'] ?? 'Error al agregar producto ${product.name}');
        }
      }

      print('✅ Productos agregados exitosamente a la promoción');
    } catch (e) {
      print('❌ Error agregando productos a promoción: $e');
      rethrow;
    }
  }

  /// Crea una nueva promoción con productos específicos
  Future<Promotion> createPromotionWithProducts(
    Map<String, dynamic> promotionData,
    List<Product> selectedProducts,
  ) async {
    try {
      print('📝 Creando promoción con productos específicos');
      
      // Primero crear la promoción
      final promotion = await createPromotion(promotionData);
      
      // Si hay productos seleccionados, agregarlos a la promoción
      if (selectedProducts.isNotEmpty) {
        await addProductsToPromotion(promotion.id, selectedProducts);
      }
      
      return promotion;
    } catch (e) {
      print('❌ Error creando promoción con productos: $e');
      rethrow;
    }
  }

  Future<int?> _getStoreId([dynamic providedStoreId]) async {
    // Si se proporciona un ID específico, usarlo
    if (providedStoreId != null) {
      if (providedStoreId is int) return providedStoreId;
      return int.tryParse(providedStoreId.toString());
    }
    
    // Intentar obtener desde el store selector service
    int? storeId = await _storeService.getSelectedStoreId();
    
    // Si no hay tienda seleccionada, intentar inicializar el servicio
    if (storeId == null) {
      await _storeService.initialize();
      storeId = await _storeService.getSelectedStoreId();
    }
    
    // Como último recurso, usar la primera tienda disponible
    if (storeId == null && _storeService.userStores.isNotEmpty) {
      storeId = _storeService.userStores.first.id;
    }
    
    return storeId;
  }

  /// Obtiene los métodos de pago disponibles
  Future<List<PaymentMethod>> getPaymentMethods() async {
    try {
      print('💳 Cargando métodos de pago usando PaymentMethodService');
      return await PaymentMethodService.getActivePaymentMethods();
    } catch (e) {
      print('❌ Error cargando métodos de pago: $e');
      return _getMockPaymentMethods();
    }
  }

  List<PaymentMethod> _getMockPaymentMethods() {
    return [
      PaymentMethod(
        id: 1,
        denominacion: 'Efectivo',
        esDigital: false,
        esEfectivo: true,
        esActivo: true,
      ),
      PaymentMethod(
        id: 2,
        denominacion: 'Tarjeta de Crédito',
        esDigital: true,
        esEfectivo: false,
        esActivo: true,
      ),
      PaymentMethod(
        id: 3,
        denominacion: 'Tarjeta de Débito',
        esDigital: true,
        esEfectivo: false,
        esActivo: true,
      ),
      PaymentMethod(
        id: 4,
        denominacion: 'Transferencia Bancaria',
        esDigital: true,
        esEfectivo: false,
        esActivo: true,
      ),
      PaymentMethod(
        id: 5,
        denominacion: 'Pago Móvil',
        esDigital: true,
        esEfectivo: false,
        esActivo: true,
      ),
    ];
  }

  // Métodos de datos mock para fallback
  List<Promotion> _getMockPromotions() {
    return [
      Promotion(
        id: '1',
        idTienda: '1',
        idTipoPromocion: '1',
        nombre: 'Descuento Verano 2026',
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

  /// Obtiene los productos disponibles para seleccionar en promociones
  Future<List<Map<String, dynamic>>> listPromotionSelectableProducts({
    required int storeId,
  }) async {
    try {
      print('📦 Listando productos disponibles para promociones: $storeId');

      final response = await _supabase.rpc(
        'fn_listar_productos_para_promociones',
        params: {
          'p_id_tienda': storeId,
        },
      );

      print('📦 Respuesta listando productos para promociones: $response');

      if (response == null) {
        print('⚠️ Respuesta nula al listar productos para promociones');
        return [];
      }

      final List<dynamic> data = response is List ? response : [];
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ Error listando productos para promociones: $e');
      return [];
    }
  }

  /// Obtiene los productos afectados por una promoción específica
  Future<List<Product>> getPromotionProducts(String promotionId) async {
    try {
      print('📦 Obteniendo productos para promoción: $promotionId');
      
      // Convertir String a int para la función RPC
      final promotionIdInt = int.tryParse(promotionId);
      if (promotionIdInt == null) {
        throw Exception('ID de promoción inválido: $promotionId');
      }
      
      // Llamar a la función RPC para obtener productos de la promoción
      final response = await _supabase.rpc(
        'listar_productos_promocion',
        params: {
          'p_id_promocion': promotionIdInt,
        },
      );

      if (response == null) {
        print('⚠️ No se encontraron productos para la promoción $promotionId');
        return [];
      }

      final List<dynamic> data = response as List<dynamic>;
      print('✅ Encontrados ${data.length} productos para la promoción');
      
      // Debug: Log first product's raw data
      if (data.isNotEmpty) {
        print('DEBUG: Raw product data: ${data.first}');
      }
      
      return data.map((item) => Product.fromJson(item)).toList();
    } catch (e) {
      print('❌ Error obteniendo productos de promoción: $e');
      // Si la función RPC no existe, devolver lista vacía
      if (e.toString().contains('Could not find the function')) {
        print('⚠️ Función fn_listar_productos_promocion no encontrada, devolviendo lista vacía');
        return [];
      }
      throw Exception('Error al obtener productos de la promoción: $e');
    }
  }
}
