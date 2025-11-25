import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

/// Servicio para gestionar permisos y acceso por roles
class PermissionsService {
  static final PermissionsService _instance = PermissionsService._internal();
  factory PermissionsService() => _instance;
  PermissionsService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPrefs = UserPreferencesService();

  // Cache del rol del usuario
  UserRole? _cachedRole;
  int? _cachedWarehouseId;
  String? _cachedUserId;
  
  // Cache de roles por tienda
  Map<int, UserRole>? _cachedRolesByStore;

  // SOLO PARA DESARROLLO: Forzar un rol específico
  UserRole? _forcedRole;

  /// SOLO PARA DESARROLLO: Forzar un rol específico para pruebas
  void forceRole(UserRole role) {
    print('⚠️ MODO DESARROLLO: Forzando rol a ${getRoleName(role)}');
    _forcedRole = role;
    _cachedRole = role;
  }

  /// SOLO PARA DESARROLLO: Limpiar rol forzado
  void clearForcedRole() {
    print('✅ Limpiando rol forzado');
    _forcedRole = null;
    clearCache();
  }

  /// Obtener el rol del usuario actual
  /// Primero intenta obtener del caché, luego de preferencias guardadas, y finalmente de la BD
  Future<UserRole> getUserRole() async {
    // Si hay un rol forzado (modo desarrollo), usarlo
    if (_forcedRole != null) {
      print('⚠️ USANDO ROL FORZADO: ${getRoleName(_forcedRole!)}');
      return _forcedRole!;
    }

    if (_cachedRole != null) {
      print('💾 Usando rol en caché: ${getRoleName(_cachedRole!)}');
      return _cachedRole!;
    }

    try {
      // Intentar obtener el rol guardado en preferencias primero
      final savedRole = await _userPrefs.getAdminRole();
      if (savedRole != null && savedRole.isNotEmpty) {
        print('💾 Usando rol guardado en preferencias: $savedRole');
        final role = _convertStringToUserRole(savedRole);
        _cachedRole = role;
        return role;
      }

      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('❌ No hay usuario autenticado');
        return UserRole.none;
      }

      _cachedUserId = user.id;
      print('🔍 Verificando roles para UUID: ${user.id}');

      // Verificar en orden de jerarquía
      // 1. Gerente
      final gerenteData =
          await _supabase
              .from('app_dat_gerente')
              .select('id')
              .eq('uuid', user.id)
              .maybeSingle();

      print('  • Gerente: ${gerenteData != null ? "✅ Sí" : "❌ No"}');
      if (gerenteData != null) {
        print('✅ ROL DETECTADO Y GUARDADO EN CACHÉ: GERENTE');
        _cachedRole = UserRole.gerente;
        return UserRole.gerente;
      }

      // 2. Supervisor
      final supervisorData =
          await _supabase
              .from('app_dat_supervisor')
              .select('id')
              .eq('uuid', user.id)
              .maybeSingle();

      print('  • Supervisor: ${supervisorData != null ? "✅ Sí" : "❌ No"}');
      if (supervisorData != null) {
        print('✅ ROL DETECTADO Y GUARDADO EN CACHÉ: SUPERVISOR');
        _cachedRole = UserRole.supervisor;
        return UserRole.supervisor;
      }

      // 3. Almacenero
      final almaceneroData =
          await _supabase
              .from('app_dat_almacenero')
              .select('id, id_almacen')
              .eq('uuid', user.id)
              .maybeSingle();

      print('  • Almacenero: ${almaceneroData != null ? "✅ Sí" : "❌ No"}');
      if (almaceneroData != null) {
        print(
          '✅ ROL DETECTADO Y GUARDADO EN CACHÉ: ALMACENERO (Almacén: ${almaceneroData['id_almacen']})',
        );
        _cachedRole = UserRole.almacenero;
        _cachedWarehouseId = almaceneroData['id_almacen'] as int?;
        return UserRole.almacenero;
      }

      // 4. Vendedor
      final vendedorData =
          await _supabase
              .from('app_dat_vendedor')
              .select('id')
              .eq('uuid', user.id)
              .maybeSingle();

      print('  • Vendedor: ${vendedorData != null ? "✅ Sí" : "❌ No"}');
      if (vendedorData != null) {
        print('✅ ROL DETECTADO Y GUARDADO EN CACHÉ: VENDEDOR');
        _cachedRole = UserRole.vendedor;
        return UserRole.vendedor;
      }

      // Sin rol
      print('❌ No se encontró ningún rol para este usuario');
      _cachedRole = UserRole.none;
      return UserRole.none;
    } catch (e) {
      print('❌ Error al obtener rol del usuario: $e');
      return UserRole.none;
    }
  }

  /// Convertir string de rol a UserRole enum
  UserRole _convertStringToUserRole(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'gerente':
        return UserRole.gerente;
      case 'supervisor':
        return UserRole.supervisor;
      case 'almacenero':
        return UserRole.almacenero;
      case 'vendedor':
        return UserRole.vendedor;
      default:
        return UserRole.none;
    }
  }

  /// Obtener todos los roles del usuario para cada tienda
  /// Retorna: Map<idTienda, UserRole>
  Future<Map<int, UserRole>> getUserRolesByStore() async {
    if (_cachedRolesByStore != null) {
      print('💾 Usando roles por tienda en caché: $_cachedRolesByStore');
      return _cachedRolesByStore!;
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('❌ No hay usuario autenticado');
        return {};
      }

      _cachedUserId = user.id;
      final rolesByStore = <int, UserRole>{};
      print('🔍 Verificando roles por tienda para UUID: ${user.id}');

      // 1. Gerentes - puede serlo en múltiples tiendas
      final gerenteData = await _supabase
          .from('app_dat_gerente')
          .select('id_tienda')
          .eq('uuid', user.id);

      if (gerenteData is List && gerenteData.isNotEmpty) {
        for (final record in gerenteData) {
          final idTienda = record['id_tienda'] as int;
          rolesByStore[idTienda] = UserRole.gerente;
          print('  ✅ Gerente en tienda: $idTienda');
        }
      }

      // 2. Supervisores - puede serlo en múltiples tiendas
      final supervisorData = await _supabase
          .from('app_dat_supervisor')
          .select('id_tienda')
          .eq('uuid', user.id);

      if (supervisorData is List && supervisorData.isNotEmpty) {
        for (final record in supervisorData) {
          final idTienda = record['id_tienda'] as int;
          // Si ya es gerente en esta tienda, mantener el rol más alto
          if (!rolesByStore.containsKey(idTienda)) {
            rolesByStore[idTienda] = UserRole.supervisor;
            print('  ✅ Supervisor en tienda: $idTienda');
          }
        }
      }

      // 3. Almaceneros - puede serlo en múltiples almacenes (pero de una sola tienda)
      final almaceneroData = await _supabase
          .from('app_dat_almacenero')
          .select('id_almacen, app_dat_almacen(id_tienda)')
          .eq('uuid', user.id);

      if (almaceneroData is List && almaceneroData.isNotEmpty) {
        for (final record in almaceneroData) {
          final idTienda = record['app_dat_almacen']['id_tienda'] as int;
          // Si ya es gerente o supervisor en esta tienda, mantener el rol más alto
          if (!rolesByStore.containsKey(idTienda)) {
            rolesByStore[idTienda] = UserRole.almacenero;
            print('  ✅ Almacenero en tienda: $idTienda');
          }
        }
      }

      // Nota: Los vendedores no se incluyen aquí porque no tienen acceso a la administración
      // Solo se retornan roles de admin: gerente, supervisor, almacenero

      _cachedRolesByStore = rolesByStore;
      print('✅ Roles por tienda detectados: ${rolesByStore.length} tiendas');
      return rolesByStore;
    } catch (e) {
      print('❌ Error al obtener roles por tienda: $e');
      return {};
    }
  }

  /// Obtener el rol del usuario para una tienda específica
  /// Si la tienda está en el mapa, retorna ese rol
  /// Si no está pero el usuario tiene un solo rol, retorna ese rol
  /// Si no está y hay múltiples roles, retorna none
  Future<UserRole> getUserRoleForStore(int storeId) async {
    final rolesByStore = await getUserRolesByStore();
    
    // Si la tienda está en el mapa, retornar ese rol
    if (rolesByStore.containsKey(storeId)) {
      return rolesByStore[storeId]!;
    }
    
    // Si hay un solo rol en el mapa, asumir que es para esta tienda también
    if (rolesByStore.length == 1) {
      return rolesByStore.values.first;
    }
    
    // Si no hay roles o hay múltiples pero no coincide, retornar none
    return UserRole.none;
  }

  /// Obtener el almacén asignado al almacenero
  Future<int?> getAssignedWarehouse() async {
    if (_cachedWarehouseId != null) return _cachedWarehouseId;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final almaceneroData =
          await _supabase
              .from('app_dat_almacenero')
              .select('id_almacen')
              .eq('uuid', user.id)
              .maybeSingle();

      if (almaceneroData != null) {
        _cachedWarehouseId = almaceneroData['id_almacen'] as int?;
        return _cachedWarehouseId;
      }

      return null;
    } catch (e) {
      print('❌ Error al obtener almacén asignado: $e');
      return null;
    }
  }

  /// Limpiar caché de permisos
  void clearCache() {
    _cachedRole = null;
    _cachedWarehouseId = null;
    _cachedUserId = null;
    _cachedRolesByStore = null;
  }

  /// Verificar si el usuario puede acceder a una pantalla
  /// Usa el rol de la tienda actualmente seleccionada
  Future<bool> canAccessScreen(String screenRoute) async {
    final currentStoreId = await _userPrefs.getIdTienda();
    UserRole role;
    
    if (currentStoreId != null) {
      // Obtener rol para la tienda actual
      role = await getUserRoleForStore(currentStoreId);
      
      // Si no se encuentra el rol en la tienda, intentar con el rol principal
      if (role == UserRole.none) {
        print('⚠️ Rol no encontrado para tienda $currentStoreId, usando rol principal');
        role = await getUserRole();
      }
    } else {
      // Fallback al rol principal si no hay tienda seleccionada
      role = await getUserRole();
    }
    
    final permissions = _screenPermissions[screenRoute];

    if (permissions == null) {
      // Si no está en la matriz, permitir acceso por defecto
      return true;
    }

    return permissions.contains(role);
  }

  /// Verificar si el usuario puede realizar una acción
  /// Usa el rol de la tienda actualmente seleccionada
  Future<bool> canPerformAction(String action) async {
    final currentStoreId = await _userPrefs.getIdTienda();
    UserRole role;
    
    if (currentStoreId != null) {
      // Obtener rol para la tienda actual
      role = await getUserRoleForStore(currentStoreId);
      
      // Si no se encuentra el rol en la tienda, intentar con el rol principal
      if (role == UserRole.none) {
        print('⚠️ Rol no encontrado para tienda $currentStoreId, usando rol principal');
        role = await getUserRole();
      }
    } else {
      // Fallback al rol principal si no hay tienda seleccionada
      role = await getUserRole();
    }
    
    final permissions = _actionPermissions[action];

    print('🔍 canPerformAction("$action")');
    print('  • Tienda actual: $currentStoreId');
    print('  • Rol detectado: ${getRoleName(role)}');
    print(
      '  • Permisos para esta acción: ${permissions?.map((r) => getRoleName(r)).join(", ") ?? "NO DEFINIDOS"}',
    );

    if (permissions == null) {
      // Si no está en la matriz, denegar por defecto
      print('  ❌ Acción no definida en matriz - DENEGADO');
      return false;
    }

    final hasPermission = permissions.contains(role);
    print(
      '  ${hasPermission ? "✅" : "❌"} Resultado: ${hasPermission ? "PERMITIDO" : "DENEGADO"}',
    );
    return hasPermission;
  }

  /// Obtener lista de pantallas permitidas para el rol
  /// Usa el rol de la tienda actualmente seleccionada
  Future<List<String>> getAllowedScreens() async {
    final currentStoreId = await _userPrefs.getIdTienda();
    UserRole role;
    
    if (currentStoreId != null) {
      // Obtener rol para la tienda actual
      role = await getUserRoleForStore(currentStoreId);
      
      // Si no se encuentra el rol en la tienda, intentar con el rol principal
      if (role == UserRole.none) {
        print('⚠️ Rol no encontrado para tienda $currentStoreId, usando rol principal');
        role = await getUserRole();
      }
    } else {
      // Fallback al rol principal si no hay tienda seleccionada
      role = await getUserRole();
    }
    
    final allowedScreens = <String>[];

    _screenPermissions.forEach((route, roles) {
      if (roles.contains(role)) {
        allowedScreens.add(route);
      }
    });

    return allowedScreens;
  }

  /// Obtener nombre del rol en español
  String getRoleName(UserRole role) {
    switch (role) {
      case UserRole.gerente:
        return 'Gerente';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.almacenero:
        return 'Almacenero';
      case UserRole.vendedor:
        return 'Vendedor';
      case UserRole.none:
        return 'Sin Rol';
    }
  }

  // =====================================================
  // MATRIZ DE PERMISOS POR PANTALLA
  // =====================================================
  static const Map<String, List<UserRole>> _screenPermissions = {
    // Dashboard
    '/dashboard': [UserRole.gerente, UserRole.supervisor, UserRole.almacenero],
    '/unified-dashboard': [UserRole.gerente],
    '/dashboard-web': [UserRole.gerente],

    // Productos (Almacenero NO tiene acceso)
    '/products': [UserRole.gerente, UserRole.supervisor],
    '/products-dashboard': [UserRole.gerente, UserRole.supervisor],
    '/add-product': [UserRole.gerente],
    '/categories': [UserRole.gerente, UserRole.supervisor],
    '/tpv-prices': [UserRole.gerente, UserRole.supervisor],

    // Inventario (Almacenero NO tiene acceso a vista general)
    '/inventory': [UserRole.gerente, UserRole.supervisor],
    '/inventory-operations': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],
    '/inventory-reception': [UserRole.gerente, UserRole.almacenero],
    '/inventory-extraction': [UserRole.gerente],
    '/inventory-transfer': [UserRole.gerente, UserRole.almacenero],
    '/inventory-adjustment': [UserRole.gerente, UserRole.supervisor],
    '/inventory-history': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],

    // Almacenes (Almacenero solo ve su almacén)
    '/warehouse': [UserRole.gerente, UserRole.supervisor, UserRole.almacenero],
    '/add-warehouse': [UserRole.gerente],

    // Ventas (Almacenero NO tiene acceso)
    '/sales': [UserRole.gerente, UserRole.supervisor],
    '/promotions': [UserRole.gerente],

    // Finanzas (Solo Gerente)
    '/financial': [UserRole.gerente],
    '/financial-dashboard': [UserRole.gerente],
    '/financial-reports': [UserRole.gerente],
    '/financial-expenses': [UserRole.gerente],
    '/financial-setup': [UserRole.gerente],
    '/financial-configuration': [UserRole.gerente],
    '/production-costs': [UserRole.gerente],
    '/cost-assignments': [UserRole.gerente],
    '/cost-audit': [UserRole.gerente],
    '/exchange-rates': [UserRole.gerente],

    // Marketing y CRM (Solo Gerente)
    '/marketing-dashboard': [UserRole.gerente],
    '/campaigns': [UserRole.gerente],
    '/communications': [UserRole.gerente],
    '/segments': [UserRole.gerente],
    '/loyalty': [UserRole.gerente],
    '/crm-dashboard': [UserRole.gerente],
    '/crm-analytics': [UserRole.gerente],
    '/crm-relationships': [UserRole.gerente],
    '/customers': [UserRole.gerente],

    // Proveedores
    '/suppliers': [UserRole.gerente, UserRole.supervisor],
    '/supplier-detail': [UserRole.gerente, UserRole.supervisor],
    '/add-supplier': [UserRole.gerente],
    '/supplier-reports': [UserRole.gerente, UserRole.supervisor],

    // Personal
    '/workers': [UserRole.gerente, UserRole.supervisor],
    '/tpv-management': [UserRole.gerente, UserRole.supervisor],
    '/vendor-management': [UserRole.gerente, UserRole.supervisor],

    // Configuración (Solo Gerente)
    '/settings': [UserRole.gerente],
    '/excel-import': [UserRole.gerente],

    // Análisis
    '/analytics': [UserRole.gerente, UserRole.supervisor],
  };

  // =====================================================
  // MATRIZ DE PERMISOS POR ACCIÓN
  // =====================================================
  static const Map<String, List<UserRole>> _actionPermissions = {
    // Productos
    'product.create': [UserRole.gerente],
    'product.edit': [UserRole.gerente],
    'product.delete': [UserRole.gerente],
    'product.view': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],

    // Inventario
    'inventory.create_reception': [UserRole.gerente, UserRole.almacenero],
    'inventory.create_extraction': [UserRole.gerente],
    'inventory.create_transfer': [UserRole.gerente, UserRole.almacenero],
    'inventory.create_adjustment': [UserRole.gerente],
    'inventory.approve_adjustment': [UserRole.gerente, UserRole.supervisor],
    'inventory.view': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],

    // Almacenes
    'warehouse.create': [UserRole.gerente],
    'warehouse.edit': [UserRole.gerente],
    'warehouse.delete': [UserRole.gerente],
    'warehouse.view': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],

    // Trabajadores
    'worker.create': [UserRole.gerente],
    'worker.edit': [UserRole.gerente],
    'worker.delete': [UserRole.gerente],
    'worker.view': [UserRole.gerente, UserRole.supervisor],

    // Ventas
    'sales.view': [UserRole.gerente, UserRole.supervisor],
    'sales.modify': [UserRole.gerente],

    // Proveedores
    'supplier.create': [UserRole.gerente],
    'supplier.edit': [UserRole.gerente],
    'supplier.delete': [UserRole.gerente],
    'supplier.view': [UserRole.gerente, UserRole.supervisor],

    // Finanzas
    'financial.view': [UserRole.gerente],
    'financial.edit': [UserRole.gerente],

    // Configuración
    'settings.view': [UserRole.gerente],
    'settings.edit': [UserRole.gerente],
  };
}

/// Enum de roles de usuario
enum UserRole { gerente, supervisor, almacenero, vendedor, none }
