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

  /// Primer TPV de la tienda (fallback para gerente/supervisor sin vendedor).
  Future<Map<String, dynamic>?> getDefaultTpvForStore(int idTienda) async {
    try {
      final response = await client
          .from('app_dat_tpv')
          .select('*')
          .eq('id_tienda', idTienda)
          .order('id')
          .limit(1);
      if (response.isEmpty) return null;
      return Map<String, dynamic>.from(response.first as Map);
    } catch (e) {
      print('❌ Error obteniendo TPV por defecto: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _findGerenteByUuid(String userUuid) async {
    try {
      final response = await client
          .from('app_dat_gerente')
          .select('*')
          .eq('uuid', userUuid)
          .order('id')
          .limit(1);
      if (response.isEmpty) return null;
      return Map<String, dynamic>.from(response.first as Map);
    } catch (e) {
      print('❌ Error consultando gerente: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _findSupervisorByUuid(String userUuid) async {
    try {
      final response = await client
          .from('app_dat_supervisor')
          .select('*')
          .eq('uuid', userUuid)
          .order('id')
          .limit(1);
      if (response.isEmpty) return null;
      return Map<String, dynamic>.from(response.first as Map);
    } catch (e) {
      print('❌ Error consultando supervisor: $e');
      return null;
    }
  }

  /// Verifica acceso a Caja.
  /// Prioridad: gerente → supervisor → vendedor.
  /// Gerente/supervisor son sesión solo-gestión (no venta).
  Future<Map<String, dynamic>> verifySellerAndGetProfile(
    String userUuid,
  ) async {
    try {
      // 1) Gerente (solo inventario/productos)
      final gerente = await _findGerenteByUuid(userUuid);
      if (gerente != null) {
        return await _profileFromAdminRole(
          userUuid: userUuid,
          role: CajaEntryRole.gerente,
          idTienda: (gerente['id_tienda'] as num).toInt(),
          idTrabajador: (gerente['id_trabajador'] as num?)?.toInt(),
          defaultRoll: 1,
        );
      }

      // 2) Supervisor (solo inventario/productos)
      final supervisor = await _findSupervisorByUuid(userUuid);
      if (supervisor != null) {
        return await _profileFromAdminRole(
          userUuid: userUuid,
          role: CajaEntryRole.supervisor,
          idTienda: (supervisor['id_tienda'] as num).toInt(),
          idTrabajador: (supervisor['id_trabajador'] as num?)?.toInt(),
          defaultRoll: 2,
        );
      }

      // 3) Vendedor (flujo de venta)
      final sellerData = await checkSellerByUuid(userUuid);
      if (sellerData != null) {
        return await _profileFromSeller(sellerData);
      }

      throw Exception(
        'Usuario no autorizado: debe ser vendedor, gerente o supervisor',
      );
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

  Future<Map<String, dynamic>> _profileFromAdminRole({
    required String userUuid,
    required CajaEntryRole role,
    required int idTienda,
    required int? idTrabajador,
    required int defaultRoll,
  }) async {
    print('✅ Acceso Caja como ${role.name} (sin vendedor obligatorio)');
    print('  - ID Tienda: $idTienda');
    print('  - ID Trabajador: $idTrabajador');

    Map<String, dynamic>? workerData;
    if (idTrabajador != null) {
      workerData = await getWorkerById(idTrabajador);
    }

    workerData ??= {
      'id': idTrabajador,
      'nombres': role == CajaEntryRole.gerente ? 'Gerente' : 'Supervisor',
      'apellidos': '',
      'id_tienda': idTienda,
      'id_roll': defaultRoll,
    };

    final tpvData = await getDefaultTpvForStore(idTienda);
    if (tpvData == null || tpvData['id'] == null) {
      throw Exception(
        'La tienda $idTienda no tiene TPV configurado. '
        'Crea un TPV antes de entrar a Caja como ${role.name}.',
      );
    }

    final idTpv = (tpvData['id'] as num).toInt();
    final syntheticSeller = <String, dynamic>{
      'id': 0,
      'uuid': userUuid,
      'id_tpv': idTpv,
      'id_trabajador': idTrabajador ?? 0,
      'permitir_customizar_precio_venta': true,
      'es_admin_sin_vendedor': true,
    };

    return {
      'seller': syntheticSeller,
      'worker': {
        ...workerData,
        'id_tienda': workerData['id_tienda'] ?? idTienda,
        'id_roll': workerData['id_roll'] ?? defaultRoll,
      },
      'idTpv': idTpv,
      'idTienda': idTienda,
      'idAlmacen': tpvData['id_almacen'],
      'entryRole': role.name,
      'inventoryOnly': true,
    };
  }
}
