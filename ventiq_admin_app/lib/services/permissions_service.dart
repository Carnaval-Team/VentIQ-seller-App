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
  int? _cachedRoleStoreId;
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

    final currentStoreId = await _userPrefs.getIdTienda();

    // Si hay una tienda seleccionada, el rol debe ser store-aware
    if (currentStoreId != null) {
      if (_cachedRole != null && _cachedRoleStoreId == currentStoreId) {
        print(
          '💾 Usando rol en caché (tienda $currentStoreId): ${getRoleName(_cachedRole!)}',
        );
        return _cachedRole!;
      }

      final storeRole = await getUserRoleForStore(currentStoreId);
      if (storeRole != UserRole.none) {
        _cachedRole = storeRole;
        _cachedRoleStoreId = currentStoreId;
        return storeRole;
      }
    } else {
      // Sin tienda seleccionada, usar caché global si existe
      if (_cachedRole != null) {
        print('💾 Usando rol en caché: ${getRoleName(_cachedRole!)}');
        return _cachedRole!;
      }
    }

    try {
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
        _cachedRoleStoreId = currentStoreId;
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
        _cachedRoleStoreId = currentStoreId;
        return UserRole.supervisor;
      }

      // 3. Auditor
      final auditorData =
          await _supabase
              .from('auditor')
              .select('id')
              .eq('uuid', user.id)
              .maybeSingle();

      print('  • Auditor: ${auditorData != null ? "✅ Sí" : "❌ No"}');
      if (auditorData != null) {
        print('✅ ROL DETECTADO Y GUARDADO EN CACHÉ: AUDITOR');
        _cachedRole = UserRole.auditor;
        _cachedRoleStoreId = currentStoreId;
        return UserRole.auditor;
      }

      // 4. Almacenero
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
        _cachedRoleStoreId = currentStoreId;
        _cachedWarehouseId = almaceneroData['id_almacen'] as int?;
        return UserRole.almacenero;
      }

      // 5. Vendedor
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
        _cachedRoleStoreId = currentStoreId;
        return UserRole.vendedor;
      }

      // 6. Recursos Humanos
      final rrhhData =
          await _supabase
              .from('app_dat_recursos_humanos')
              .select('id')
              .eq('uuid', user.id)
              .maybeSingle();

      print('  • Recursos Humanos: ${rrhhData != null ? "✅ Sí" : "❌ No"}');
      if (rrhhData != null) {
        print('✅ ROL DETECTADO Y GUARDADO EN CACHÉ: RECURSOS HUMANOS');
        _cachedRole = UserRole.recursosHumanos;
        _cachedRoleStoreId = currentStoreId;
        return UserRole.recursosHumanos;
      }

      // Sin rol
      print('❌ No se encontró ningún rol para este usuario');
      _cachedRole = UserRole.none;
      _cachedRoleStoreId = currentStoreId;
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
      case 'auditor':
        return UserRole.auditor;
      case 'almacenero':
        return UserRole.almacenero;
      case 'vendedor':
        return UserRole.vendedor;
      case 'recursos humanos':
        return UserRole.recursosHumanos;
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

      if (gerenteData.isNotEmpty) {
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

      if (supervisorData.isNotEmpty) {
        for (final record in supervisorData) {
          final idTienda = record['id_tienda'] as int;
          // Si ya es gerente en esta tienda, mantener el rol más alto
          if (!rolesByStore.containsKey(idTienda)) {
            rolesByStore[idTienda] = UserRole.supervisor;
            print('  ✅ Supervisor en tienda: $idTienda');
          }
        }
      }

      // 3. Auditores - puede serlo en múltiples tiendas
      final auditorData = await _supabase
          .from('auditor')
          .select('id_tienda')
          .eq('uuid', user.id);

      if (auditorData.isNotEmpty) {
        for (final record in auditorData) {
          final idTienda = (record['id_tienda'] as num).toInt();
          // Si ya es gerente o supervisor en esta tienda, mantener el rol más alto
          if (!rolesByStore.containsKey(idTienda)) {
            rolesByStore[idTienda] = UserRole.auditor;
            print('  ✅ Auditor en tienda: $idTienda');
          }
        }
      }

      // 4. Almaceneros - puede serlo en múltiples almacenes (pero de una sola tienda)
      final almaceneroData = await _supabase
          .from('app_dat_almacenero')
          .select('id_almacen, app_dat_almacen(id_tienda)')
          .eq('uuid', user.id);

      if (almaceneroData.isNotEmpty) {
        for (final record in almaceneroData) {
          final idTienda = record['app_dat_almacen']['id_tienda'] as int;
          // Si ya es gerente o supervisor en esta tienda, mantener el rol más alto
          if (!rolesByStore.containsKey(idTienda)) {
            rolesByStore[idTienda] = UserRole.almacenero;
            print('  ✅ Almacenero en tienda: $idTienda');
          }
        }
      }

      // 5. Recursos Humanos - puede serlo en múltiples tiendas
      final rrhhData = await _supabase
          .from('app_dat_recursos_humanos')
          .select('id_tienda')
          .eq('uuid', user.id);

      if (rrhhData.isNotEmpty) {
        for (final record in rrhhData) {
          final idTienda = (record['id_tienda'] as num).toInt();
          // Si ya tiene un rol de mayor jerarquía, mantenerlo
          if (!rolesByStore.containsKey(idTienda)) {
            rolesByStore[idTienda] = UserRole.recursosHumanos;
            print('  ✅ Recursos Humanos en tienda: $idTienda');
          }
        }
      }

      // Nota: Los vendedores no se incluyen aquí porque no tienen acceso a la administración

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
    // Primero intentar con roles guardados en preferencias (más rápido y consistente)
    final storedRoleName = await _userPrefs.getUserRoleForStore(storeId);
    if (storedRoleName != null && storedRoleName.isNotEmpty) {
      return _convertStringToUserRole(storedRoleName);
    }

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
  /// NOTA: No limpia _cachedRolesByStore porque los roles por tienda no cambian
  /// al cambiar de tienda. Solo se limpia el rol individual y el almacén.
  void clearCache() {
    _cachedRole = null;
    _cachedRoleStoreId = null;
    _cachedWarehouseId = null;
    _cachedUserId = null;
    // NO limpiar _cachedRolesByStore - se mantiene durante toda la sesión
    print('🧹 Caché de permisos limpiado (roles por tienda preservados)');
  }

  /// Limpiar TODO el caché incluyendo roles por tienda
  /// Solo usar al cerrar sesión
  void clearAllCache() {
    _cachedRole = null;
    _cachedRoleStoreId = null;
    _cachedWarehouseId = null;
    _cachedUserId = null;
    _cachedRolesByStore = null;
    print('🧹 TODO el caché de permisos limpiado');
  }

  /// Verificar si el usuario puede acceder a una pantalla
  /// Usa el rol de la tienda actualmente seleccionada
  Future<bool> canAccessScreen(String screenRoute) async {
    final currentStoreId = await _userPrefs.getIdTienda();
    UserRole role;

    if (currentStoreId != null) {
      // Obtener rol para la tienda actual
      role = await getUserRoleForStore(currentStoreId);
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
      case UserRole.auditor:
        return 'Auditor';
      case UserRole.almacenero:
        return 'Almacenero';
      case UserRole.vendedor:
        return 'Vendedor';
      case UserRole.recursosHumanos:
        return 'Recursos Humanos';
      case UserRole.none:
        return 'Sin Rol';
    }
  }

  // =====================================================
  // MATRIZ DE PERMISOS POR PANTALLA
  // =====================================================
  static const Map<String, List<UserRole>> _screenPermissions = {
    // Dashboard
    '/dashboard': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],
    '/unified-dashboard': [UserRole.gerente, UserRole.auditor],
    '/dashboard-web': [UserRole.gerente, UserRole.auditor],

    // Productos (Almacenero tiene acceso solo lectura)
    '/products': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],
    '/products-dashboard': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],
    '/add-product': [UserRole.gerente],
    '/categories': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],
    '/tpv-prices': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],

    // Inventario (Almacenero NO tiene acceso a vista general)
    '/inventory': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],
    '/inventory-operations': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],
    '/inventory-reception': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],
    '/inventory-extraction': [UserRole.gerente],
    '/inventory-transfer': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],
    '/inventory-adjustment': [UserRole.gerente, UserRole.supervisor],
    '/inventory-history': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],

    // Almacenes (Almacenero solo ve su almacén)
    '/warehouse': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],
    '/add-warehouse': [UserRole.gerente],

    // Ventas (Almacenero NO tiene acceso)
    '/sales': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],
    '/promotions': [UserRole.gerente, UserRole.auditor],

    // Finanzas (Solo Gerente)
    '/financial': [UserRole.gerente, UserRole.auditor],
    '/financial-dashboard': [UserRole.gerente, UserRole.auditor],
    '/financial-reports': [UserRole.gerente, UserRole.auditor],
    '/financial-expenses': [UserRole.gerente, UserRole.auditor],
    '/financial-setup': [UserRole.gerente, UserRole.auditor],
    '/financial-configuration': [UserRole.gerente, UserRole.auditor],
    '/production-costs': [UserRole.gerente, UserRole.auditor],
    '/cost-assignments': [UserRole.gerente, UserRole.auditor],
    '/cost-audit': [UserRole.gerente, UserRole.auditor],
    '/exchange-rates': [UserRole.gerente, UserRole.auditor],

    // Marketing y CRM (Solo Gerente)
    '/marketing-dashboard': [UserRole.gerente],
    '/campaigns': [UserRole.gerente, UserRole.auditor],
    '/communications': [UserRole.gerente, UserRole.auditor],
    '/segments': [UserRole.gerente, UserRole.auditor],
    '/loyalty': [UserRole.gerente, UserRole.auditor],
    '/crm-dashboard': [UserRole.gerente, UserRole.auditor],
    '/crm-analytics': [UserRole.gerente, UserRole.auditor],
    // Compatibilidad: algunas pantallas usan /relationships
    '/crm-relationships': [UserRole.gerente, UserRole.auditor],
    '/relationships': [UserRole.gerente, UserRole.auditor],
    '/customers': [UserRole.gerente, UserRole.auditor],
    '/interacciones-clientes': [UserRole.gerente, UserRole.auditor],

    // Proveedores
    '/suppliers': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],
    '/supplier-detail': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
    ],
    '/add-supplier': [UserRole.gerente],
    '/supplier-reports': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
    ],

    // Personal
    '/workers': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],
    '/tpv-management': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
    ],
    '/vendor-management': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
    ],

    // Recursos Humanos (Gerente, Supervisor y Recursos Humanos)
    '/hr-dashboard': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    '/hr-checkin': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    '/hr-checkout': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    '/hr-salary-report': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    '/hr-worker-config': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],

    // Configuración (Gerente y Supervisor)
    '/settings': [UserRole.gerente, UserRole.supervisor],
    '/excel-import': [UserRole.gerente],

    // Consignaciones
    '/consignacion': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],

    // Dispositivos
    '/wifi-printers': [UserRole.gerente, UserRole.auditor],

    // Análisis
    '/analytics': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],

    // Costos (alias de rutas históricas)
    '/restaurant-costs': [UserRole.gerente, UserRole.auditor],
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
      UserRole.auditor,
      UserRole.almacenero,
    ],

    // Inventario
    'inventory.create_reception': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],
    'inventory.create_extraction': [UserRole.gerente],
    'inventory.create_transfer': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.almacenero,
    ],
    'inventory.create_adjustment': [UserRole.gerente],
    'inventory.approve_adjustment': [UserRole.gerente, UserRole.supervisor],
    'inventory.view': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],

    // Almacenes
    'warehouse.create': [UserRole.gerente],
    'warehouse.edit': [UserRole.gerente],
    'warehouse.delete': [UserRole.gerente],
    'warehouse.view': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.auditor,
      UserRole.almacenero,
    ],

    // Trabajadores
    'worker.create': [UserRole.gerente, UserRole.supervisor],
    'worker.edit': [UserRole.gerente, UserRole.supervisor],
    'worker.delete': [UserRole.gerente, UserRole.supervisor],
    'worker.view': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],

    // Ventas
    'sales.view': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],
    'sales.view_realtime': [UserRole.gerente, UserRole.auditor],
    'sales.modify': [UserRole.gerente],

    // Proveedores
    'supplier.create': [UserRole.gerente],
    'supplier.edit': [UserRole.gerente],
    'supplier.delete': [UserRole.gerente],
    'supplier.view': [UserRole.gerente, UserRole.supervisor, UserRole.auditor],

    // Finanzas
    'financial.view': [UserRole.gerente, UserRole.auditor],
    'financial.edit': [UserRole.gerente],

    // Configuración
    'settings.view': [UserRole.gerente, UserRole.supervisor],
    'settings.edit': [UserRole.gerente, UserRole.supervisor],

    // TPVs
    'tpv.create': [UserRole.gerente, UserRole.supervisor],
    'tpv.edit': [UserRole.gerente, UserRole.supervisor],
    'tpv.delete': [UserRole.gerente, UserRole.supervisor],

    // Precios por TPV
    'tpv_price.create': [UserRole.gerente, UserRole.supervisor],
    'tpv_price.edit': [UserRole.gerente, UserRole.supervisor],
    'tpv_price.delete': [UserRole.gerente, UserRole.supervisor],
    'tpv_price.restore': [UserRole.gerente, UserRole.supervisor],
    'tpv_price.import': [UserRole.gerente, UserRole.supervisor],

    // Vendedores / asignación TPV
    'vendor.assign_tpv': [UserRole.gerente, UserRole.supervisor],
    'vendor.unassign_tpv': [UserRole.gerente, UserRole.supervisor],
    'vendor.create': [UserRole.gerente, UserRole.supervisor],
    'vendor.delete': [UserRole.gerente, UserRole.supervisor],
    'vendor.edit_price_permission': [UserRole.gerente, UserRole.supervisor],

    // Clientes (CRM)
    'customer.create': [UserRole.gerente],
    'customer.edit': [UserRole.gerente],
    'customer.delete': [UserRole.gerente],

    // CRM - Relaciones
    'crm.relationship.create': [UserRole.gerente],
    'crm.relationship.edit': [UserRole.gerente],
    'crm.relationship.delete': [UserRole.gerente],

    // Marketing
    'marketing.create': [UserRole.gerente],
    'marketing.edit': [UserRole.gerente],
    'marketing.delete': [UserRole.gerente],

    // Consignaciones
    'consignacion.create': [UserRole.gerente, UserRole.supervisor],
    'consignacion.edit': [UserRole.gerente, UserRole.supervisor],
    'consignacion.delete': [UserRole.gerente, UserRole.supervisor],
    'consignacion.confirm': [UserRole.gerente, UserRole.supervisor],

    // Impresoras / dispositivos
    'printers.edit': [UserRole.gerente],

    // Recursos Humanos
    'hr.checkin': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    'hr.checkout': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    'hr.salary_report': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    'hr.worker_config': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
    'hr.dashboard': [
      UserRole.gerente,
      UserRole.supervisor,
      UserRole.recursosHumanos,
    ],
  };
}

/// Enum de roles de usuario
enum UserRole { gerente, supervisor, auditor, almacenero, vendedor, recursosHumanos, none }
