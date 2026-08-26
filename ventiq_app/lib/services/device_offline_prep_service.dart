import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_access_service.dart';
import 'auth_service.dart';
import 'auto_sync_service.dart';
import 'settings_integration_service.dart';
import 'smart_offline_manager.dart';
import 'store_config_service.dart';
import 'subscription_guard_service.dart';
import 'user_preferences_service.dart';
import '../utils/navigation_helper.dart';

/// Prepara el dispositivo para operar full offline:
/// sync de catálogo/licencia + registro local de vendedores con password.
class DeviceOfflinePrepService {
  static final DeviceOfflinePrepService _instance =
      DeviceOfflinePrepService._internal();
  factory DeviceOfflinePrepService() => _instance;
  DeviceOfflinePrepService._internal();

  final _prefs = UserPreferencesService();
  final _auth = AuthService();
  final _supabase = Supabase.instance.client;
  final _autoSync = AutoSyncService();

  /// Mismos módulos que el sync operativo, forzando catálogo y órdenes.
  static final Set<SyncModule> prepModules = {
    SyncModule.uploadTurno,
    SyncModule.uploadSales,
    SyncModule.uploadEgresos,
    SyncModule.uploadShiftWorkers,
    SyncModule.uploadAdminOps,
    SyncModule.license,
    SyncModule.storeConfig,
    SyncModule.credentials,
    SyncModule.paymentMethods,
    SyncModule.promotions,
    SyncModule.categories,
    SyncModule.products,
    SyncModule.layouts,
    SyncModule.orders,
    SyncModule.turno,
    SyncModule.egresos,
  };

  Future<void> assertCanPrepare() async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) {
      throw Exception('Sin tienda en sesión');
    }
    final offlineCompleto =
        await StoreConfigService.getPermitirModoOfflineCompleto(storeId);
    if (!offlineCompleto) {
      throw Exception(
        'La tienda no tiene habilitado el modo offline completo',
      );
    }
    final hasLicense =
        await SubscriptionGuardService().hasActiveSubscription();
    if (!hasLicense) {
      throw Exception('Licencia/suscripción no válida');
    }
    final inventoryOnly = await _prefs.isInventoryOnlySession();
    if (!inventoryOnly) {
      throw Exception(
        'Solo el administrador (gerente/supervisor) puede preparar el dispositivo',
      );
    }
  }

  /// Sync completo compatible con el modo offline general de la app.
  Future<SyncResult> runPrepSync({String? ensurePassword}) async {
    await assertCanPrepare();

    final email = await _prefs.getUserEmail();
    final userId = await _prefs.getUserId();
    final saved = await _prefs.getSavedCredentials();
    final password = (ensurePassword != null && ensurePassword.trim().isNotEmpty)
        ? ensurePassword.trim()
        : saved['password'];

    if (email != null &&
        userId != null &&
        password != null &&
        password.isNotEmpty) {
      await _prefs.saveCredentials(email, password);
      await _prefs.mergeOfflineData({
        'credentials': {
          'email': email,
          'password': password,
          'userId': userId,
        },
      });
    }

    // _performSync omite trabajo si offline ya está ON; syncModules no,
    // pero dejamos el flag en false durante la prep por seguridad.
    final wasOffline = await _prefs.isOfflineModeEnabled();
    if (wasOffline) {
      await _prefs.setOfflineMode(false);
    }

    late final SyncResult result;
    try {
      result = await _autoSync.syncModules(prepModules);
    } finally {
      // Si el dispositivo ya estaba en full offline, reactivar el flag
      // (activateAppOfflineMode hace el resto al marcar listo).
      if (wasOffline || await _prefs.isDeviceFullOfflineReady()) {
        await _prefs.setOfflineMode(true);
      }
    }

    if (email != null &&
        userId != null &&
        password != null &&
        password.isNotEmpty) {
      await _prefs.saveOfflineUser(
        email: email,
        password: password,
        userId: userId,
      );
      await _prefs.mergeOfflineData({
        'credentials': {
          'email': email,
          'password': password,
          'userId': userId,
        },
      });
    }

    return result;
  }

  /// Activa el modo offline general igual que Settings.
  Future<void> activateAppOfflineMode() async {
    var hasData = await _prefs.hasOfflineData();
    if (!hasData) {
      await runPrepSync();
      hasData = await _prefs.hasOfflineData();
    }
    if (!hasData) {
      throw Exception(
        'No hay datos offline suficientes (credenciales + categorías). '
        'Sincroniza de nuevo antes de activar.',
      );
    }

    await _prefs.setOfflineMode(true);

    try {
      final integration = SettingsIntegrationService();
      if (integration.isInitialized) {
        await integration.handleOfflineModeChanged(true);
      } else {
        await SmartOfflineManager().onOfflineModeManuallyEnabled();
      }
    } catch (e) {
      print('⚠️ No se pudo notificar SmartOfflineManager: $e');
      try {
        await SmartOfflineManager().onOfflineModeManuallyEnabled();
      } catch (_) {}
    }

    print('✅ Modo offline general de la app activado (prep admin)');
  }

  Future<List<Map<String, dynamic>>> listStoreSellers() async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) return [];

    final trabajadores = await _supabase
        .from('app_dat_trabajadores')
        .select('id, nombres, apellidos, id_roll, id_tienda, user_mail, uuid')
        .eq('id_tienda', storeId);

    final trabajadorIds =
        (trabajadores as List)
            .map((t) => t['id'])
            .where((id) => id != null)
            .toList();
    if (trabajadorIds.isEmpty) return [];

    final vendedores = await _supabase
        .from('app_dat_vendedor')
        .select('''
          id,
          uuid,
          id_tpv,
          id_trabajador,
          permitir_customizar_precio_venta,
          trabajador:app_dat_trabajadores(
            id, nombres, apellidos, id_roll, id_tienda, user_mail, uuid
          ),
          tpv:app_dat_tpv(id, id_almacen, denominacion)
        ''')
        .inFilter('id_trabajador', trabajadorIds);

    final registered = await _prefs.getOfflineUsersForStore(storeId);
    final registeredEmails =
        registered.map((u) => u['email']?.toString().toLowerCase()).toSet();

    return (vendedores as List).map((raw) {
      final v = Map<String, dynamic>.from(raw as Map);
      final trab = v['trabajador'] is Map
          ? Map<String, dynamic>.from(v['trabajador'] as Map)
          : <String, dynamic>{};
      final tpv = v['tpv'] is Map
          ? Map<String, dynamic>.from(v['tpv'] as Map)
          : <String, dynamic>{};
      final email = (trab['user_mail'] ?? '').toString().trim();
      return {
        'idSeller': v['id'],
        'userId': v['uuid'] ?? trab['uuid'],
        'idTpv': v['id_tpv'] ?? tpv['id'],
        'idAlmacen': tpv['id_almacen'],
        'idTrabajador': v['id_trabajador'] ?? trab['id'],
        'nombres': trab['nombres'] ?? '',
        'apellidos': trab['apellidos'] ?? '',
        'idRoll': trab['id_roll'] ?? 4,
        'idTienda': trab['id_tienda'] ?? storeId,
        'email': email,
        'permitir_customizar_precio_venta':
            v['permitir_customizar_precio_venta'] == true,
        'entryRole': 'vendedor',
        'registeredOffline':
            email.isNotEmpty && registeredEmails.contains(email.toLowerCase()),
      };
    }).toList();
  }

  Future<void> registerCurrentAdmin({required String password}) async {
    final storeId = await _prefs.getIdTienda();
    final email = await _prefs.getUserEmail();
    final userId = await _prefs.getUserId();
    if (storeId == null || email == null || userId == null) {
      throw Exception('Sesión de admin incompleta');
    }
    if (password.trim().isEmpty) {
      throw Exception('Contraseña del administrador requerida');
    }

    await _auth.signInWithEmailAndPassword(email: email, password: password);

    await _prefs.saveCredentials(email, password);
    await _prefs.mergeOfflineData({
      'credentials': {
        'email': email,
        'password': password,
        'userId': userId,
      },
    });

    final profile = await _prefs.getWorkerProfile();
    final entryRole = await _prefs.getCajaEntryRole() ?? 'gerente';
    await _prefs.upsertOfflineUserProfile({
      'email': email,
      'password': password,
      'userId': userId,
      'idTienda': storeId,
      'idTpv': profile['idTpv'] ?? await _prefs.getIdTpv(),
      'idTrabajador': profile['idTrabajador'],
      'idSeller': profile['idSeller'] ?? 0,
      'nombres': profile['nombres'] ?? 'Administrador',
      'apellidos': profile['apellidos'] ?? '',
      'idRoll': profile['idRoll'] ?? 1,
      'entryRole': entryRole,
      'permitir_customizar_precio_venta': true,
      'idAlmacen': await _prefs.getIdAlmacen(),
    });

    await _prefs.setDeviceFullOfflineReady(
      storeId: storeId,
      adminEmail: email,
      adminPassword: password,
    );
  }

  Future<void> registerSellerWithPassword({
    required Map<String, dynamic> sellerProfile,
    required String password,
  }) async {
    final email = sellerProfile['email']?.toString().trim() ?? '';
    if (email.isEmpty) {
      throw Exception('El vendedor no tiene email (user_mail) configurado');
    }
    if (password.trim().isEmpty) {
      throw Exception('Contraseña requerida');
    }

    final adminCreds = await _prefs.getDeviceFullOfflineAdminCredentials();
    var adminEmail = adminCreds['email'];
    var adminPassword = adminCreds['password'];
    if (adminEmail == null ||
        adminPassword == null ||
        adminEmail.isEmpty ||
        adminPassword.isEmpty) {
      adminEmail = await _prefs.getUserEmail();
      final saved = await _prefs.getSavedCredentials();
      adminPassword = saved['password'];
    }
    if (adminEmail == null ||
        adminPassword == null ||
        adminPassword.isEmpty) {
      throw Exception(
        'Registra primero al administrador con su contraseña '
        'para poder validar vendedores y restaurar la sesión',
      );
    }

    final storeId = await _prefs.getIdTienda();
    if (storeId == null) throw Exception('Sin tienda');

    try {
      final response = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final authUser = response.user;
      if (authUser == null) {
        throw Exception('No se pudo validar el vendedor');
      }

      await _prefs.upsertOfflineUserProfile({
        'email': email,
        'password': password,
        'userId': sellerProfile['userId'] ?? authUser.id,
        'idTienda': storeId,
        'idTpv': sellerProfile['idTpv'],
        'idTrabajador': sellerProfile['idTrabajador'],
        'idSeller': sellerProfile['idSeller'],
        'nombres': sellerProfile['nombres'],
        'apellidos': sellerProfile['apellidos'],
        'idRoll': sellerProfile['idRoll'] ?? 4,
        'entryRole': 'vendedor',
        'permitir_customizar_precio_venta':
            sellerProfile['permitir_customizar_precio_venta'] == true,
        'idAlmacen': sellerProfile['idAlmacen'],
      });
    } finally {
      try {
        await _auth.signInWithEmailAndPassword(
          email: adminEmail,
          password: adminPassword,
        );
      } catch (e) {
        print('❌ No se pudo restaurar sesión admin tras registrar vendedor: $e');
        rethrow;
      }
    }
  }

  Future<bool> canMarkReady() async {
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) return false;
    final users = await _prefs.getOfflineUsersForStore(storeId);
    final hasAdmin = users.any((u) {
      final role = u['entryRole']?.toString();
      return role == 'gerente' || role == 'supervisor';
    });
    final hasSeller =
        users.any((u) => u['entryRole']?.toString() == 'vendedor');
    return hasAdmin && hasSeller;
  }

  Future<void> markReadyIfPossible() async {
    if (!await canMarkReady()) {
      throw Exception(
        'Se requiere al menos un administrador y un vendedor registrados offline',
      );
    }
    final storeId = await _prefs.getIdTienda();
    if (storeId == null) {
      throw Exception('Falta registrar al administrador');
    }

    final adminCreds = await _prefs.getDeviceFullOfflineAdminCredentials();
    final String adminEmail;
    final String adminPassword;
    if (adminCreds['email'] != null && adminCreds['password'] != null) {
      adminEmail = adminCreds['email']!;
      adminPassword = adminCreds['password']!;
    } else {
      // Si el admin está registrado en offline_users pero faltan las claves
      // de dispositivo full-offline, recuperarlas del perfil guardado.
      final users = await _prefs.getOfflineUsersForStore(storeId);
      final admin = users.firstWhere(
        (u) {
          final role = u['entryRole']?.toString();
          return (role == 'gerente' || role == 'supervisor') &&
              u['email'] != null &&
              u['password'] != null;
        },
        orElse: () => <String, dynamic>{},
      );
      final recoveredEmail = admin['email']?.toString();
      final recoveredPassword = admin['password']?.toString();
      if (recoveredEmail == null ||
          recoveredEmail.isEmpty ||
          recoveredPassword == null ||
          recoveredPassword.isEmpty) {
        throw Exception('Falta registrar al administrador');
      }
      adminEmail = recoveredEmail;
      adminPassword = recoveredPassword;
      await _prefs.setDeviceFullOfflineReady(
        storeId: storeId,
        adminEmail: recoveredEmail,
        adminPassword: recoveredPassword,
      );
    }

    await _prefs.setDeviceFullOfflineReady(
      storeId: storeId,
      adminEmail: adminEmail,
      adminPassword: adminPassword,
    );

    await activateAppOfflineMode();
  }
}

/// Activa una sesión local desde un registro de offline_users (sin servidor).
class LocalOfflineSessionService {
  static final LocalOfflineSessionService _instance =
      LocalOfflineSessionService._internal();
  factory LocalOfflineSessionService() => _instance;
  LocalOfflineSessionService._internal();

  final _prefs = UserPreferencesService();

  Future<String> activateFromOfflineUser({
    required String email,
    required String password,
  }) async {
    final offlineUser = await _prefs.validateOfflineUser(
      email: email,
      password: password,
    );
    if (offlineUser == null) {
      throw Exception('Credenciales incorrectas');
    }

    await _prefs.saveUserData(
      userId: offlineUser['userId'],
      email: offlineUser['email'],
      accessToken: 'offline_mode',
    );

    final idTpv = offlineUser['idTpv'];
    final idTrabajador = offlineUser['idTrabajador'];
    if (idTpv != null && idTrabajador != null) {
      await _prefs.saveSellerData(
        idTpv: idTpv is int ? idTpv : (idTpv as num).toInt(),
        idTrabajador:
            idTrabajador is int ? idTrabajador : (idTrabajador as num).toInt(),
        permitirCustomizarPrecioVenta:
            offlineUser['permitir_customizar_precio_venta'] == true,
      );
    }

    final idSeller = offlineUser['idSeller'];
    if (idSeller is num && idSeller > 0) {
      await _prefs.saveIdSeller(idSeller.toInt());
    }

    final idAlmacen = offlineUser['idAlmacen'];
    if (idAlmacen is num) {
      await _prefs.saveIdAlmacen(idAlmacen.toInt());
    }

    if (offlineUser['nombres'] != null &&
        offlineUser['idTienda'] != null &&
        offlineUser['idRoll'] != null) {
      final storeId = offlineUser['idTienda'] is int
          ? offlineUser['idTienda'] as int
          : (offlineUser['idTienda'] as num).toInt();
      await _prefs.saveWorkerProfile(
        nombres: offlineUser['nombres']?.toString() ?? '',
        apellidos: offlineUser['apellidos']?.toString() ?? '',
        idTienda: storeId,
        idRoll: offlineUser['idRoll'] is int
            ? offlineUser['idRoll'] as int
            : (offlineUser['idRoll'] as num).toInt(),
      );
      await _prefs.ensureOfflineStoreScope(storeId);
    }

    final entryRole = offlineUser['entryRole']?.toString() ?? 'vendedor';
    await _prefs.setCajaEntryRole(entryRole);

    // Alinear cache de rol admin con el usuario local (evita drawer de
    // gerente cuando entra un vendedor en el mismo dispositivo/tienda).
    final storeIdForRole = offlineUser['idTienda'];
    if (storeIdForRole != null) {
      final sid = storeIdForRole is int
          ? storeIdForRole
          : (storeIdForRole as num).toInt();
      final adminRole = (entryRole == 'gerente' || entryRole == 'supervisor')
          ? entryRole
          : 'none';
      await _prefs.setCachedAdminRoleRaw(sid, adminRole);
    }

    await _prefs.setOfflineMode(true);
    try {
      await SmartOfflineManager().onOfflineModeManuallyEnabled();
    } catch (_) {}

    await _prefs.saveCredentials(email, password);
    await _prefs.mergeOfflineData({
      'credentials': {
        'email': email,
        'password': password,
        'userId': offlineUser['userId'],
      },
    });

    AdminAccessService().clearMemoryCache();

    // Home del switch local: mismo criterio que el login (gerente → gestión,
    // personal de cocina → KDS, resto → catálogo/mesas). Sin red no se puede
    // consultar el rol de cocina, así que se usa el cacheado del último login
    // online, que es exactamente para lo que se cachea.
    return NavigationHelper.homeRoute();
  }
}
