import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';

class StoreService {
  static final _supabase = Supabase.instance.client;

  // Obtener todas las tiendas con estadísticas
  static Future<List<Store>> getAllStores() async {
    try {
      debugPrint('📊 Obteniendo todas las tiendas...');
      
      // Usar método simple directamente (sin RPC para evitar ambigüedad)
      return await _getAllStoresSimple();
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas: $e');
      return [];
    }
  }

  // Método fallback simple sin RPC functions
  static Future<List<Store>> _getAllStoresSimple() async {
    try {
      final response = await _supabase
          .from('app_dat_tienda')
          .select('''
            id,
            denominacion,
            direccion,
            ubicacion,
            created_at,
            es_prueba,
            app_suscripciones!left(
              id_plan,
              fecha_inicio,
              fecha_fin,
              estado,
              app_suscripciones_plan!inner(
                denominacion,
                precio_mensual
              )
            )
          ''');

      List<Store> stores = [];
      
      for (var storeData in response) {
        final storeId = storeData['id'];
        final suscripciones = storeData['app_suscripciones'] as List?;
        
        // Buscar suscripción activa
        Map<String, dynamic>? suscripcionActiva;
        if (suscripciones != null && suscripciones.isNotEmpty) {
          suscripcionActiva = suscripciones.firstWhere(
            (s) => s['estado'] == 1,
            orElse: () => suscripciones.first,
          );
        }
        
        stores.add(Store(
          id: storeId,
          denominacion: storeData['denominacion'],
          direccion: storeData['direccion'],
          ubicacion: storeData['ubicacion'],
          createdAt: DateTime.parse(storeData['created_at']),
          totalVentas: 0, // Se calculará después si es necesario
          totalProductos: 0,
          totalTrabajadores: 0,
          ventasDelMes: 0.0,
          activa: true,
          esPrueba: storeData['es_prueba'] == true,
          planSuscripcion: suscripcionActiva?['app_suscripciones_plan']?['denominacion'],
          fechaVencimientoSuscripcion: suscripcionActiva?['fecha_fin'] != null
              ? DateTime.parse(suscripcionActiva!['fecha_fin'])
              : null,
        ));
      }

      return stores;
    } catch (e) {
      debugPrint('❌ Error en método simple: $e');
      return [];
    }
  }

  // Obtener estadísticas generales del sistema
  static Future<Map<String, dynamic>> getSystemStats() async {
    try {
      debugPrint('📊 Obteniendo estadísticas del sistema...');
      
      // Total de tiendas
      final tiendasResponse = await _supabase
          .from('app_dat_tienda')
          .select('id')
          .count();
      
      // Total de usuarios
      final usuariosResponse = await _supabase
          .from('auth.users')
          .select('id')
          .count();
      
      // Total de ventas del mes
      final inicioMes = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final ventasMesResponse = await _supabase
          .from('app_dat_operacion_venta')
          .select('importe_total')
          .gte('created_at', inicioMes.toIso8601String());
      
      double ventasTotalesMes = 0;
      int totalVentasMes = ventasMesResponse.length;
      for (var venta in ventasMesResponse) {
        ventasTotalesMes += (venta['importe_total'] ?? 0).toDouble();
      }
      
      // Total de productos en el sistema
      final productosResponse = await _supabase
          .from('app_dat_producto')
          .select('id')
          .count();
      
      return {
        'total_tiendas': tiendasResponse.count,
        'total_usuarios': usuariosResponse.count,
        'ventas_totales_mes': ventasTotalesMes,
        'total_ventas_mes': totalVentasMes,
        'total_productos': productosResponse.count,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return {
        'total_tiendas': 0,
        'total_usuarios': 0,
        'ventas_totales_mes': 0.0,
        'total_ventas_mes': 0,
        'total_productos': 0,
      };
    }
  }

  // Buscar tiendas
  static Future<List<Store>> searchStores(String query) async {
    try {
      final response = await _supabase
          .from('app_dat_tienda')
          .select()
          .or('denominacion.ilike.%$query%,direccion.ilike.%$query%,ubicacion.ilike.%$query%');

      return response.map<Store>((json) => Store.fromJson(json)).toList();
    } catch (e) {
      debugPrint('❌ Error buscando tiendas: $e');
      return [];
    }
  }

  // Obtener detalles de una tienda específica
  static Future<Map<String, dynamic>> getStoreDetails(int storeId) async {
    try {
      debugPrint('📊 Obteniendo detalles de tienda ID: $storeId');
      
      // Información básica de la tienda
      final storeResponse = await _supabase
          .from('app_dat_tienda')
          .select()
          .eq('id', storeId)
          .single();
      
      // Gerentes de la tienda
      final gerentesResponse = await _supabase
          .from('app_dat_gerente')
          .select('''
            *,
            app_dat_trabajadores!inner(
              nombres,
              apellidos
            )
          ''')
          .eq('id_tienda', storeId);
      
      // TPVs de la tienda
      final tpvsResponse = await _supabase
          .from('app_dat_tpv')
          .select()
          .eq('id_tienda', storeId);
      
      // Almacenes de la tienda
      final almacenesResponse = await _supabase
          .from('app_dat_almacen')
          .select()
          .eq('id_tienda', storeId);
      
      // Ventas del último mes
      final inicioMes = DateTime.now().subtract(const Duration(days: 30));
      final ventasResponse = await _supabase
          .from('app_dat_operacion_venta')
          .select('created_at, importe_total')
          .gte('created_at', inicioMes.toIso8601String())
          .order('created_at');
      
      return {
        'store': Store.fromJson(storeResponse),
        'gerentes': gerentesResponse,
        'tpvs': tpvsResponse,
        'almacenes': almacenesResponse,
        'ventas_recientes': ventasResponse,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo detalles de tienda: $e');
      return {};
    }
  }

  // Actualizar información de una tienda
  static Future<bool> updateStore(int storeId, Map<String, dynamic> updates) async {
    try {
      await _supabase
          .from('app_dat_tienda')
          .update(updates)
          .eq('id', storeId);
      
      debugPrint('✅ Tienda actualizada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando tienda: $e');
      return false;
    }
  }

  // Activar/Desactivar tienda
  static Future<bool> toggleStoreStatus(int storeId, bool active) async {
    try {
      // Aquí podrías implementar lógica adicional como
      // desactivar usuarios, TPVs, etc.
      
      await _supabase
          .from('app_dat_tienda')
          .update({'activa': active})
          .eq('id', storeId);
      
      debugPrint('✅ Estado de tienda actualizado: ${active ? "Activa" : "Inactiva"}');
      return true;
    } catch (e) {
      debugPrint('❌ Error cambiando estado de tienda: $e');
      return false;
    }
  }

  // Obtener ventas por período
  static Future<List<Map<String, dynamic>>> getSalesByPeriod(
    int storeId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final response = await _supabase
          .from('app_dat_operacion_venta')
          .select('''
            *,
            app_dat_operaciones!inner(
              id_tienda,
              created_at
            )
          ''')
          .eq('app_dat_operaciones.id_tienda', storeId)
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String())
          .order('created_at');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo ventas: $e');
      return [];
    }
  }
}
