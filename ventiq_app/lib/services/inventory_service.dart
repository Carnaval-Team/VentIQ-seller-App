import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_product.dart';
import 'user_preferences_service.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  /// Get inventory products using fn_listar_inventario_productos RPC
  static Future<List<InventoryProduct>> getInventoryProducts({
    String? busqueda,
    int? idAlmacen,
    String? nivelStock,
    int? limite = 50,
    int? pagina = 1,
  }) async {
    try {
      print('🔍 Obteniendo productos de inventario...');

      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró información de la tienda');
      }

      print('🏪 ID Tienda: $idTienda');
      print('🔍 Búsqueda: $busqueda');
      print('📦 ID Almacén: $idAlmacen');
      print('📊 Nivel Stock: $nivelStock');
      print('📄 Límite: $limite, Página: $pagina');

      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged',
        params: {
          'p_id_tienda': idTienda,
          'p_id_almacen': idAlmacen,
          'p_busqueda': busqueda,
          'p_limite': limite,
          'p_pagina': pagina,
        },
      );

      print('📦 Respuesta RPC recibida: ${response?.runtimeType}');

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      List<InventoryProduct> products = [];

      if (response is List) {
        print('📋 Procesando ${response.length} elementos de la respuesta');

        for (var item in response) {
          try {
            final product = InventoryProduct.fromSupabaseRpc(item);
            products.add(product);
          } catch (e) {
            print('❌ Error procesando producto: $e');
            print('📄 Datos del producto problemático: $item');
          }
        }

        // Calculate virtual stock levels after loading
        print('📊 Calculando niveles de stock virtuales...');
      } else {
        print('❌ Formato de respuesta inesperado: ${response.runtimeType}');
        return [];
      }

      print(
        '✅ ${products.length} productos de inventario cargados exitosamente',
      );
      return products;
    } catch (e) {
      print('❌ Error al obtener productos de inventario: $e');
      return [];
    }
  }

  /// Get warehouses for the current store
  static Future<List<Map<String, dynamic>>> getWarehouses() async {
    try {
      print('🏪 Obteniendo almacenes...');

      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró información de la tienda');
      }

      final response = await _supabase
          .from('app_dat_almacen')
          .select('id, denominacion, descripcion')
          .eq('id_tienda', idTienda)
          .eq('es_activo', true);

      print('✅ ${response.length} almacenes encontrados');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener almacenes: $e');
      return [];
    }
  }
}
