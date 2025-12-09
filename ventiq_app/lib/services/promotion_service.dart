import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class PromotionService {
  static final PromotionService _instance = PromotionService._internal();
  factory PromotionService() => _instance;
  PromotionService._internal();

  final _supabase = Supabase.instance.client;
  final _userPreferencesService = UserPreferencesService();

  /// Obtiene las promociones globales activas para la tienda
  /// Primero busca en la tabla directa, si no encuentra usa fn_listar_promociones
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
                  'id, codigo_promocion, nombre, descripcion, valor_descuento, id_tipo_promocion',
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
          print('✅ Promoción global encontrada (búsqueda directa):');
          print('  - ID: ${response['id']}');
          print('  - Código: ${response['codigo_promocion']}');
          print('  - Nombre: ${response['nombre']}');
          print('  - Valor Descuento: ${response['valor_descuento']}');
          print(
            '  - Tipo Descuento: ${response['id_tipo_promocion']} (1=%, 2=fijo)',
          );

          return {
            'id_promocion': response['id'],
            'codigo_promocion': response['codigo_promocion'],
            'nombre': response['nombre'],
            'descripcion': response['descripcion'],
            'valor_descuento': response['valor_descuento']?.toDouble(),
            'tipo_descuento': response['id_tipo_promocion'],
            'tipo_promocion_nombre': _getTipoPromocionNombre(
              response['id_tipo_promocion'],
            ),
          };
        }
      } catch (e) {
        print('ℹ️ No se encontró promoción directa, usando RPC: $e');
      }

      // Segundo intento: usar fn_listar_promociones
      print('🔄 Usando fn_listar_promociones para buscar promociones...');
      final rpcResponse = await _supabase.rpc(
        'fn_listar_promociones',
        params: {'p_id_tienda': idTienda},
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
          print('✅ Promoción global encontrada (RPC):');
          print('  - ID: ${globalPromotion['id']}');
          print('  - Código: ${globalPromotion['codigo_promocion']}');
          print('  - Nombre: ${globalPromotion['nombre']}');
          print('  - Valor Descuento: ${globalPromotion['valor_descuento']}');
          print('  - Tipo Promoción: ${globalPromotion['tipo_promocion']}');

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
            'tipo_descuento': _getTipoDescuentoFromNombre(
              globalPromotion['tipo_promocion'],
            ),
            'tipo_promocion_nombre': globalPromotion['tipo_promocion'],
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

  /// Obtiene promociones específicas para un producto
  Future<Map<String, dynamic>?> getProductPromotion(
    int idTienda,
    String productName,
  ) async {
    try {
      print(
        '🎯 PromotionService: Buscando promoción para producto "$productName"',
      );

      final rpcResponse = await _supabase.rpc(
        'fn_listar_promociones',
        params: {'p_id_tienda': idTienda},
      );

      if (rpcResponse != null &&
          rpcResponse is List &&
          rpcResponse.isNotEmpty) {
        print("promos_: $rpcResponse");
        // Buscar promociones específicas de producto (aplica_todo = false y nombre contiene " - ")
        final productPromotions =
            rpcResponse
                .where(
                  (promo) =>
                      promo['aplica_todo'] == false &&
                      promo['nombre'] != null &&
                      promo['nombre'].toString().contains(' - '),
                )
                .toList();

        for (final promo in productPromotions) {
          // Extraer nombre del producto de la promoción (después del " - ")
          final promoName = promo['nombre'].toString();
          final dashIndex = promoName.indexOf(' - ');
          if (dashIndex != -1 && dashIndex < promoName.length - 3) {
            final promoProductName = promoName.substring(dashIndex + 3).trim();

            // Comparar nombres (insensible a mayúsculas/minúsculas)
            if (promoProductName.toLowerCase() == productName.toLowerCase()) {
              print('✅ Promoción específica encontrada para producto:');
              print('  - ID: ${promo['id']}');
              print('  - Código: ${promo['codigo_promocion']}');
              print('  - Nombre: ${promo['nombre']}');
              print('  - Valor Descuento: ${promo['valor_descuento']}');
              print('  - Tipo Promoción: ${promo['tipo_promocion']}');

              return {
                'id_promocion': promo['id'],
                'codigo_promocion': promo['codigo_promocion'],
                'nombre': promo['nombre'],
                'descripcion': promo['descripcion'],
                'valor_descuento':
                    double.tryParse(promo['valor_descuento'].toString()) ?? 0.0,
                'tipo_descuento': _getTipoDescuentoFromNombre(
                  promo['tipo_promocion'],
                ),
                'tipo_promocion_nombre': promo['tipo_promocion'],
                'producto_nombre': promoProductName,
              };
            }
          }
        }
      }

      print(
        'ℹ️ No se encontró promoción específica para el producto "$productName"',
      );
      return null;
    } catch (e) {
      print('❌ Error obteniendo promoción de producto: $e');
      return null;
    }
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
      default:
        return 1; // Default porcentual
    }
  }

  /// Convierte ID numérico a nombre del tipo de promoción
  String _getTipoPromocionNombre(int? tipoId) {
    switch (tipoId) {
      case 1:
        return 'Descuento porcentual';
      case 2:
        return 'Descuento exacto';
      case 3:
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
