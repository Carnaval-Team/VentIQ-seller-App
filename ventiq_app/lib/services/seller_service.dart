import 'package:supabase_flutter/supabase_flutter.dart';

/// Roles de entrada válidos a Caja (ventiq_app).
enum CajaEntryRole {
  vendedor,
  gerente,
  supervisor,
}

class SellerService {
  static final SellerService _instance = SellerService._internal();
  factory SellerService() => _instance;
  SellerService._internal();

  SupabaseClient get client => Supabase.instance.client;

  /// Verifica si el usuario (por uuid de auth.users) está en app_dat_superadmin
  /// y activo. Usado para mostrar herramientas ocultas (p. ej. visor de datos
  /// offline). Ante error de red, retorna false (no expone la herramienta).
  Future<bool> isSuperAdmin(String userUuid) async {
    try {
      final response = await client
          .from('app_dat_superadmin')
          .select('id')
          .eq('uuid', userUuid)
          .eq('activo', true)
          .limit(1);
      return response.isNotEmpty;
    } catch (e) {
      print('⚠️ Error verificando superadmin: $e');
      return false;
    }
  }

  // Verificar si el usuario es un vendedor válido
  Future<Map<String, dynamic>?> checkSellerByUuid(String userUuid) async {
    try {
      final response = await client
          .from('app_dat_vendedor')
          .select('*')
          .eq('uuid', userUuid);
      print('respuesta: $response $userUuid');
      if (response.isEmpty) {
        return null;
      }
      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error al verificar vendedor: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getWorkerById(int idTrabajador) async {
    try {
      final response = await client
          .from('app_dat_trabajadores')
          .select('*')
          .eq('id', idTrabajador);

      if (response.isEmpty) {
        return null;
      }
      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error al obtener datos del trabajador: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> geTpvById(int idTpv) async {
    try {
      final response =
          await client.from('app_dat_tpv').select('*').eq('id', idTpv);

      if (response.isEmpty) {
        return null;
      }
      return response.first;
    } catch (e) {
      print('❌ Error al obtener datos del tpv: $e');
      rethrow;
    }
  }

  /// Verifica acceso a Caja.
  /// Solo vendedor: gerente/supervisor sin fila en app_dat_vendedor no entran.
  Future<Map<String, dynamic>> verifySellerAndGetProfile(
    String userUuid,
  ) async {
    try {
      final sellerData = await checkSellerByUuid(userUuid);
      if (sellerData != null) {
        return await _profileFromSeller(sellerData);
      }

      throw Exception('Usuario no autorizado: debe ser vendedor');
    } catch (e) {
      print('❌ Error en verificación de acceso a Caja: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _profileFromSeller(
    Map<String, dynamic> sellerData,
  ) async {
    print('✅ Vendedor verificado:');
    print('  - ID: ${sellerData['id']}');
    print('  - ID TPV: ${sellerData['id_tpv']}');
    print('  - ID Trabajador: ${sellerData['id_trabajador']}');

    final workerData = await getWorkerById(
      (sellerData['id_trabajador'] as num).toInt(),
    );
    final tpvData = await geTpvById((sellerData['id_tpv'] as num).toInt());
    if (workerData == null) {
      throw Exception('No se encontraron datos del trabajador');
    }

    return {
      'seller': sellerData,
      'worker': workerData,
      'idTpv': sellerData['id_tpv'],
      'idTienda': workerData['id_tienda'],
      'idAlmacen': tpvData?['id_almacen'],
      'entryRole': CajaEntryRole.vendedor.name,
      'inventoryOnly': false,
    };
  }

}
