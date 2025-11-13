import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SellerService {
  static final SellerService _instance = SellerService._internal();
  factory SellerService() => _instance;
  SellerService._internal();

  SupabaseClient get client => Supabase.instance.client;

  // Verificar si el usuario es un vendedor válido
  Future<Map<String, dynamic>?> checkSellerByUuid(String userUuid) async {
    try {
      final response = await client
          .from('app_dat_vendedor')
          .select('*')
          .eq('uuid', userUuid);
      print('respuesta: $response $userUuid');
      if (response.isEmpty) {
        return null; // Usuario no es vendedor
      }

      // Retornar el primer vendedor encontrado
      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error al verificar vendedor: $e');
      rethrow;
    }
  }

  // Obtener datos del trabajador por ID
  Future<Map<String, dynamic>?> getWorkerById(int idTrabajador) async {
    try {
      final response = await client
          .from('app_dat_trabajadores')
          .select('*')
          .eq('id', idTrabajador);

      if (response.isEmpty) {
        return null; // Trabajador no encontrado
      }

      // Retornar el primer trabajador encontrado
      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error al obtener datos del trabajador: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> geTpvById(int idTpv) async {
    try {
      final response = await client
          .from('app_dat_tpv')
          .select('*')
          .eq('id', idTpv);

      if (response.isEmpty) {
        return null; // Trabajador no encontrado
      }

      // Retornar el primer trabajador encontrado
      return response.first;
    } catch (e) {
      print('❌ Error al obtener datos del tpv: $e');
      rethrow;
    }
  }

  // Verificar vendedor y obtener perfil completo (método combinado)
  Future<Map<String, dynamic>> verifySellerAndGetProfile(
    String userUuid,
  ) async {
    try {
      // 1. Verificar si es vendedor
      final sellerData = await checkSellerByUuid(userUuid);

      if (sellerData == null) {
        throw Exception('Usuario no pertenece a los vendedores autorizados');
      }

      print('✅ Vendedor verificado:');
      print('  - ID: ${sellerData['id']}');
      print('  - ID TPV: ${sellerData['id_tpv']} (desde app_dat_vendedor)');
      print('  - ID Trabajador: ${sellerData['id_trabajador']}');

      // 2. Obtener datos del trabajador
      final workerData = await getWorkerById(sellerData['id_trabajador']);
      final tpvData = await geTpvById(sellerData['id_tpv']);
      if (workerData == null) {
        throw Exception('No se encontraron datos del trabajador');
      }

      print('✅ Perfil del trabajador obtenido:');
      print('  - Nombres: ${workerData['nombres']}');
      print('  - Apellidos: ${workerData['apellidos']}');
      print(
        '  - ID Tienda: ${workerData['id_tienda']} (desde app_dat_trabajadores)',
      );
      print('  - ID Roll: ${workerData['id_roll']}');

      // 3. Retornar datos combinados con IDs separados
      return {
        'seller': sellerData,
        'worker': workerData,
        'idTpv': sellerData['id_tpv'], // ID TPV desde app_dat_vendedor
        'idTienda': workerData['id_tienda'], 
        'idAlmacen':tpvData?['id_almacen']// ID Tienda desde app_dat_trabajadores
      };
    } catch (e) {
      print('❌ Error en verificación de vendedor: $e');
      rethrow;
    }
  }
}
