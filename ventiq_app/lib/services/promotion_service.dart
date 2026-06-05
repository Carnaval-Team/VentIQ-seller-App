import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/promotion_rules.dart';
import 'user_preferences_service.dart';

class PromotionService {
  static final PromotionService _instance = PromotionService._internal();
  factory PromotionService() => _instance;
  PromotionService._internal();

  final _supabase = Supabase.instance.client;
  final _userPreferencesService = UserPreferencesService();

  /// Obtiene las promociones globales activas para la tienda
  /// Primero busca en la tabla directa, si no encuentra usa fn_listar_promociones2
  Future<Map<String, dynamic>?> getGlobalPromotion(int idTienda) async {
    try {
      print(
        '🎯 PromotionService: Buscando promoción global para tienda $idTienda',
      );

      final now = DateTime.now().toIso8601String();

      // Primer intento: búsqueda directa en tabla
      try {
        final response =
            await _supabase
                .from('app_mkt_promociones')
                .select(
                  'id, codigo_promocion, nombre, descripcion, valor_descuento, id_tipo_promocion, min_compra, aplica_todo, requiere_medio_pago, id_medio_pago_requerido',
                )
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
          final idTipoPromocion =
              (response['id_tipo_promocion'] as num?)?.toInt();
          final tipoDescuento =
              PromotionRules.resolveTipoDescuentoFromPromotionTypeId(
                idTipoPromocion,
              ) ??
              1;

          print('✅ Promoción global encontrada (búsqueda directa):');
          print('  - ID: ${response['id']}');
          print('  - Código: ${response['codigo_promocion']}');
          print('  - Nombre: ${response['nombre']}');
          print('  - Valor Descuento: ${response['valor_descuento']}');
          print(
            '  - Tipo Descuento: $tipoDescuento (1=%, 2=fijo, 3=recargo %, 4=recargo fijo)',
          );
          print('  - Min Compra: ${response['min_compra']}');

          return {
            'id_promocion': response['id'],
            'codigo_promocion': response['codigo_promocion'],
            'nombre': response['nombre'],
            'descripcion': response['descripcion'],
            'valor_descuento': response['valor_descuento']?.toDouble(),
            'tipo_descuento': tipoDescuento,
            'tipo_promocion_nombre': _getTipoPromocionNombre(idTipoPromocion),
            'id_tipo_promocion': idTipoPromocion,
            'min_compra': _parseMinCompraValue(response['min_compra']),
            'aplica_todo': response['aplica_todo'] as bool?,
            'requiere_medio_pago': response['requiere_medio_pago'] as bool?,
            'id_medio_pago_requerido':
                response['id_medio_pago_requerido'] as int?,
          };
        }
      } catch (e) {
        print('ℹ️ No se encontró promoción directa, usando RPC: $e');
      }

      // Segundo intento: usar fn_listar_promociones2
      print('🔄 Usando fn_listar_promociones2 para buscar promociones...');
      final rpcResponse = await _supabase.rpc(
        'fn_listar_promociones2',
        params: {'p_id_tienda': idTienda, 'p_activas': true},
      );

      if (rpcResponse != null &&
          rpcResponse is List &&
          rpcResponse.isNotEmpty) {
        print('📋 Promociones encontradas via RPC: ${rpcResponse.length}');

        // Buscar promoción global (aplica_todo = true)
        final globalPromotion = rpcResponse.firstWhere(
          (promo) => promo['aplica_todo'] == true,
          orElse: () => null,
        );

        if (globalPromotion != null) {
          final tipoPromocionNombre =
              globalPromotion['tipo_promocion'] as String?;
          final idTipoPromocion =
              (globalPromotion['id_tipo_promocion'] as num?)?.toInt();
          final tipoDescuento =
              PromotionRules.resolveTipoDescuentoFromPromotionTypeId(
                idTipoPromocion,
              ) ??
              _getTipoDescuentoFromNombre(tipoPromocionNombre);

          print('✅ Promoción global encontrada (RPC):');
          print('  - ID: ${globalPromotion['id']}');
          print('  - Código: ${globalPromotion['codigo_promocion']}');
          print('  - Nombre: ${globalPromotion['nombre']}');
          print('  - Valor Descuento: ${globalPromotion['valor_descuento']}');
          print('  - Tipo Promoción: ${globalPromotion['tipo_promocion']}');
          print('  - Min Compra: ${globalPromotion['min_compra']}');
          return {
            'id_promocion': globalPromotion['id'],
            'codigo_promocion': globalPromotion['codigo_promocion'],
            'nombre': globalPromotion['nombre'],
            'descripcion': globalPromotion['descripcion'],
            'valor_descuento':
                double.tryParse(
                  globalPromotion['valor_descuento'].toString(),
                ) ??
                0.0,
            'tipo_descuento': tipoDescuento,
            'tipo_promocion_nombre':
                tipoPromocionNombre ?? _getTipoPromocionNombre(idTipoPromocion),
            'id_tipo_promocion': idTipoPromocion,
            'min_compra': _parseMinCompraValue(globalPromotion['min_compra']),
            'aplica_todo': globalPromotion['aplica_todo'] as bool?,
            'requiere_medio_pago':
                globalPromotion['requiere_medio_pago'] as bool?,
            'id_medio_pago_requerido':
                globalPromotion['id_medio_pago_requerido'] as int?,
          };
        }
      }

      print('ℹ️ No se encontró promoción global activa para la tienda');
      return null;
    } catch (e) {
      print('❌ Error obteniendo promoción global: $e');
      return null;
    }
  }

  /// Obtiene promociones específicas para un producto usando la nueva función
  /// Retorna una lista de promociones con información de medio de pago requerido
  Future<List<Map<String, dynamic>>> getProductPromotions(int productId) async {
    try {
      print(
        '🎯 PromotionService: Buscando promociones para producto ID: $productId',
      );

      final rpcResponse = await _supabase.rpc(
        'fn_listar_promociones_producto_nueva',
        params: {'p_id_producto': productId},
      );

      if (rpcResponse != null &&
          rpcResponse is List &&
          rpcResponse.isNotEmpty) {
        print('✅ Promociones encontradas: ${rpcResponse.length}');

        // Convertir respuesta a lista de promociones
        final promotions = <Map<String, dynamic>>[];

        for (final promo in rpcResponse) {
          final promotion = _mapPromotionRow(promo);

          promotions.add(promotion);

          print('  📌 Promoción: ${promotion['nombre']}');
          print('     - Valor: ${promotion['valor_descuento']}');
          print('     - Es recargo: ${promotion['es_recargo']}');
          print(
            '     - Requiere medio pago: ${promotion['requiere_medio_pago']}',
          );
          print(
            '     - ID medio pago: ${promotion['id_medio_pago_requerido']}',
          );
          print('     - ID tipo promo: ${promotion['id_tipo_promocion']}');
          print('  - Min Compra producto: ${promotion['min_compra']}');
        }

        return promotions;
      }

      print('ℹ️ No se encontraron promociones para el producto ID: $productId');
      return [];
    } catch (e) {
      print('❌ Error obteniendo promociones de producto: $e');
      return [];
    }
  }

  /// Mapea una fila cruda de promoción (de fn_listar_promociones_producto_nueva
  /// o de su versión batch) al formato interno usado por la app.
  Map<String, dynamic> _mapPromotionRow(dynamic promo) {
    final tipoPromocionNombre = promo['tipo_promocion'] as String?;
    final idTipoPromocion = (promo['id_tipo_promocion'] as num?)?.toInt();
    final tipoDescuento =
        PromotionRules.resolveTipoDescuentoFromPromotionTypeId(
          idTipoPromocion,
        ) ??
        _getTipoDescuentoFromNombre(tipoPromocionNombre);

    return {
      'id_promocion': promo['id'] as int,
      'codigo_promocion': promo['codigo_promocion'] as String?,
      'nombre': promo['nombre'] as String?,
      'descripcion': promo['descripcion'] as String?,
      'valor_descuento':
          double.tryParse(promo['valor_descuento'].toString()) ?? 0.0,
      'tipo_promocion_nombre': tipoPromocionNombre,
      'tipo_descuento': tipoDescuento,
      'id_tipo_promocion': idTipoPromocion,
      'min_compra': _parseMinCompraValue(promo['min_compra']),
      'aplica_todo': promo['aplica_todo'] as bool? ?? false,
      'precio_base': double.tryParse(promo['precio_base'].toString()) ?? 0.0,
      'es_recargo': promo['es_recargo'] as bool? ?? false,
      'requiere_medio_pago': promo['requiere_medio_pago'] as bool? ?? false,
      'id_medio_pago_requerido': promo['id_medio_pago_requerido'] as int?,
    };
  }

  /// Obtiene las promociones de MÚLTIPLES productos en UNA sola llamada
  /// (RPC batch fn_listar_promociones_productos_batch). Elimina el N+1 al
  /// sincronizar promociones por producto.
  ///
  /// Devuelve { id_producto : [promociones...] }. Si el RPC batch no existe
  /// (no se ha subido el .sql), hace fallback a llamadas individuales.
  Future<Map<int, List<Map<String, dynamic>>>> getProductPromotionsBatch(
    List<int> productIds,
  ) async {
    final Map<int, List<Map<String, dynamic>>> result = {};
    if (productIds.isEmpty) return result;

    try {
      final rpcResponse = await _supabase.rpc(
        'fn_listar_promociones_productos_batch',
        params: {'ids_param': productIds},
      );

      if (rpcResponse is List) {
        for (final row in rpcResponse) {
          final idProducto = (row['id_producto'] as num?)?.toInt();
          if (idProducto == null) continue;
          result.putIfAbsent(idProducto, () => []).add(_mapPromotionRow(row));
        }
        print(
          '✅ Promociones batch: ${result.length} productos con promos en 1 RPC',
        );
        return result;
      }
    } catch (e) {
      print(
        '⚠️ RPC batch fn_listar_promociones_productos_batch no disponible ($e). '
        'Fallback a llamadas individuales.',
      );
    }

    // Fallback: una llamada por producto (comportamiento previo).
    for (final id in productIds) {
      final promos = await getProductPromotions(id);
      if (promos.isNotEmpty) result[id] = promos;
    }
    return result;
  }

  /// Verifica si una promoción aplica según el método de pago
  /// Maneja el caso especial donde ID 999 cuenta como ID 4
  bool shouldApplyPromotion(
    Map<String, dynamic> promotion,
    int? paymentMethodId,
  ) {
    // Si la promoción no requiere medio de pago, siempre aplica
    if (promotion['requiere_medio_pago'] != true) {
      return true;
    }

    // Si requiere medio de pago pero no hay método seleccionado, no aplica
    if (paymentMethodId == null) {
      return false;
    }

    final requiredPaymentId = promotion['id_medio_pago_requerido'] as int?;
    if (requiredPaymentId == null) {
      return false;
    }

    // Caso especial: ID 999 cuenta como ID 4
    final normalizedPaymentId = paymentMethodId == 999 ? 4 : paymentMethodId;

    return normalizedPaymentId == requiredPaymentId;
  }

  /// Convierte el nombre del tipo de promoción a ID numérico para compatibilidad
  int _getTipoDescuentoFromNombre(String? tipoNombre) {
    switch (tipoNombre?.toLowerCase()) {
      case 'descuento porcentual':
        return 1; // Porcentual
      case 'descuento exacto':
        return 2; // Fijo/Exacto
      case 'recargo porcentual':
        return 3; // Recargo porcentual (nuevo)
      case 'recargo fijo':
        return 4; // Recargo fijo
      default:
        return 1; // Default porcentual
    }
  }

  /// Convierte ID numérico a nombre del tipo de promoción
  String _getTipoPromocionNombre(int? tipoId) {
    switch (tipoId) {
      case 1:
      case 10:
        return 'Descuento porcentual';
      case 2:
      case 3:
      case 4:
      case 5:
      case 6:
      case 7:
      case 11:
        return 'Descuento exacto';
      case 8:
        return 'Recargo fijo';
      case 9:
        return 'Recargo porcentual';
      default:
        return 'Descuento porcentual';
    }
  }

  /// Guarda los datos de la promoción global en las preferencias
  /// Si no hay promoción, guarda null en todos los campos
  Future<void> saveGlobalPromotion({
    int? idPromocion,
    String? codigoPromocion,
    double? valorDescuento,
    int? tipoDescuento,
    int? idTipoPromocion,
    double? minCompra,
    bool? aplicaTodo,
    bool? requiereMedioPago,
    int? idMedioPagoRequerido,
  }) async {
    try {
      await _userPreferencesService.savePromotionData(
        idPromocion: idPromocion,
        codigoPromocion: codigoPromocion,
        valorDescuento: valorDescuento,
        tipoDescuento: tipoDescuento,
        idTipoPromocion: idTipoPromocion,
        minCompra: minCompra,
        aplicaTodo: aplicaTodo,
        requiereMedioPago: requiereMedioPago,
        idMedioPagoRequerido: idMedioPagoRequerido,
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

  double? _parseMinCompraValue(dynamic value) {
    print('Minimo de compra: $value');
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final normalized = value.replaceAll(',', '.');
      return double.tryParse(normalized);
    }

    return null;
  }
}
