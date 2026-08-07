import 'package:supabase_flutter/supabase_flutter.dart';

import 'connectivity_service.dart';
import 'user_preferences_service.dart';

/// Roles que habilitan Admin Lite (inventario/productos) en Caja.
/// Gerente y supervisor: solo gestión, no venta.
enum CajaAdminRole {
  none,
  gerente,
  supervisor,
}

extension CajaAdminRoleX on CajaAdminRole {
  String get storageValue => name;

  static CajaAdminRole fromStorage(String? raw) {
    switch (raw) {
      case 'gerente':
        return CajaAdminRole.gerente;
      case 'supervisor':
        return CajaAdminRole.supervisor;
      default:
        return CajaAdminRole.none;
    }
  }

  bool get canManageInventory =>
      this == CajaAdminRole.gerente || this == CajaAdminRole.supervisor;

  /// Sesión solo de gestión (sin flujo de venta/caja).
  bool get isInventoryOnly => canManageInventory;
}

/// Acceso a inventario/productos y sesión “solo gestión” en Caja.
class AdminAccessService {
  static final AdminAccessService _instance = AdminAccessService._internal();
  factory AdminAccessService() => _instance;
  AdminAccessService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _prefs = UserPreferencesService();
  final ConnectivityService _connectivity = ConnectivityService();

  CajaAdminRole? _memoryCache;
  int? _memoryStoreId;

  Future<bool> canManageInventory({bool forceRefresh = false}) async {
    // En switch local full-offline el entryRole es la fuente de verdad:
    // el cache de rol admin puede quedar de la sesión anterior en la misma tienda.
    final entry = await _prefs.getCajaEntryRole();
    if (entry == 'vendedor') return false;
    if (entry == 'gerente' || entry == 'supervisor') return true;

    final role = await resolveRole(forceRefresh: forceRefresh);
    return role.canManageInventory;
  }

  /// Gerente/supervisor no venden: solo inventario y productos.
  Future<bool> isInventoryOnlySession({bool forceRefresh = false}) async {
    final entry = await _prefs.getCajaEntryRole();
    if (entry == 'gerente' || entry == 'supervisor') return true;
    // Vendedor (o sesión de venta): no ocultar menú de caja por un cache
    // de gerente/supervisor de otro usuario en el mismo dispositivo.
    if (entry == 'vendedor') return false;

    final role = await resolveRole(forceRefresh: forceRefresh);
    return role.isInventoryOnly;
  }

  Future<CajaAdminRole> resolveRole({bool forceRefresh = false}) async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) return CajaAdminRole.none;

    if (!forceRefresh &&
        _memoryCache != null &&
        _memoryStoreId == storeId) {
      return _memoryCache!;
    }

    if (!forceRefresh) {
      final cachedRaw = await _prefs.getCachedAdminRoleRaw(storeId);
      if (cachedRaw != null) {
        final cached = CajaAdminRoleX.fromStorage(cachedRaw);
        _memoryCache = cached;
        _memoryStoreId = storeId;
        return cached;
      }
    }

    if (!_connectivity.isConnected) {
      final cachedRaw = await _prefs.getCachedAdminRoleRaw(storeId);
      final role = CajaAdminRoleX.fromStorage(cachedRaw);
      _memoryCache = role;
      _memoryStoreId = storeId;
      return role;
    }

    final role = await _fetchRoleOnline(storeId);
    await _prefs.setCachedAdminRoleRaw(storeId, role.storageValue);
    _memoryCache = role;
    _memoryStoreId = storeId;
    return role;
  }

  Future<CajaAdminRole> refreshAndCache() async {
    return resolveRole(forceRefresh: true);
  }

  void clearMemoryCache() {
    _memoryCache = null;
    _memoryStoreId = null;
  }

  Future<CajaAdminRole> _fetchRoleOnline(int storeId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return CajaAdminRole.none;

    try {
      final gerente = await _supabase
          .from('app_dat_gerente')
          .select('id')
          .eq('uuid', user.id)
          .eq('id_tienda', storeId)
          .limit(1)
          .maybeSingle();
      if (gerente != null) {
        print('✅ AdminAccess: gerente en tienda $storeId');
        return CajaAdminRole.gerente;
      }

      final supervisor = await _supabase
          .from('app_dat_supervisor')
          .select('id')
          .eq('uuid', user.id)
          .eq('id_tienda', storeId)
          .limit(1)
          .maybeSingle();
      if (supervisor != null) {
        print('✅ AdminAccess: supervisor en tienda $storeId');
        return CajaAdminRole.supervisor;
      }
    } catch (e) {
      print('❌ AdminAccess: error consultando roles: $e');
      final cachedRaw = await _prefs.getCachedAdminRoleRaw(storeId);
      return CajaAdminRoleX.fromStorage(cachedRaw);
    }

    print('ℹ️ AdminAccess: sin rol de gestión en tienda $storeId');
    return CajaAdminRole.none;
  }
}
