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

  /// Obtener el rol del usuario actual
  Future<UserRole> getUserRole() async {
    if (_cachedRole != null) return _cachedRole!;

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return UserRole.none;

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
        print('✅ Rol detectado: GERENTE');
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
        print('✅ Rol detectado: SUPERVISOR');
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
          '✅ Rol detectado: ALMACENERO (Almacén: ${almaceneroData['id_almacen']})',
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
        print('✅ Rol detectado: VENDEDOR');
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
  }

  /// Verificar si el usuario puede acceder a una pantalla
  Future<bool> canAccessScreen(String screenRoute) async {
    final role = await getUserRole();
    final permissions = _screenPermissions[screenRoute];

    if (permissions == null) {
      // Si no está en la matriz, permitir acceso por defecto
      return true;
    }

    return permissions.contains(role);
  }

  /// Verificar si el usuario puede realizar una acción
  Future<bool> canPerformAction(String action) async {
    final role = await getUserRole();
    final permissions = _actionPermissions[action];

    if (permissions == null) {
      // Si no está en la matriz, denegar por defecto
      return false;
    }

    return permissions.contains(role);
  }

  /// Obtener lista de pantallas permitidas para el rol
  Future<List<String>> getAllowedScreens() async {
    final role = await getUserRole();
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
    '/inventory-reception': [UserRole.gerente],
    '/inventory-extraction': [UserRole.gerente, UserRole.almacenero],
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
    'inventory.create_reception': [UserRole.gerente],
    'inventory.create_extraction': [UserRole.gerente, UserRole.almacenero],
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
