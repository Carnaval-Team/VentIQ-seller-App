import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'auth_service.dart';
import 'seller_service.dart';
import 'promotion_service.dart';
import 'admin_access_service.dart';
import 'comanda_service.dart';

/// Servicio para reautenticar automáticamente al usuario cuando se restaura la conexión
/// Replica el proceso de autenticación completo del login_screen.dart
class ReauthenticationService {
  static final ReauthenticationService _instance =
      ReauthenticationService._internal();
  factory ReauthenticationService() => _instance;
  ReauthenticationService._internal();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final AuthService _authService = AuthService();
  final SellerService _sellerService = SellerService();
  final PromotionService _promotionService = PromotionService();

  /// Reautenticar automáticamente usando credenciales guardadas
  /// Retorna true si la reautenticación fue exitosa
  Future<bool> reauthenticateUser() async {
    try {
      print('🔐 Iniciando reautenticación automática...');

      // Obtener credenciales guardadas
      final credentials = await _userPreferencesService.getSavedCredentials();
      final email = credentials['email'];
      final password = credentials['password'];

      if (email == null ||
          password == null ||
          email.isEmpty ||
          password.isEmpty) {
        print('❌ No hay credenciales guardadas para reautenticar');
        return false;
      }

      print('📧 Reautenticando usuario: $email');

      // PASO 1: Autenticar con Supabase
      final response = await _authService.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        print('❌ Error en autenticación con Supabase');
        return false;
      }

      print('✅ Autenticación con Supabase exitosa');
      print('  - User ID: ${response.user!.id}');
      print('  - Email: ${response.user!.email}');

      // PASO 2: Guardar datos básicos del usuario
      await _userPreferencesService.saveUserData(
        userId: response.user!.id,
        email: response.user!.email ?? email,
        accessToken: response.session?.accessToken ?? '',
      );

      print('✅ Datos básicos del usuario guardados');

      // PASO 3: Verificar acceso a Caja (vendedor / gerente / supervisor)
      try {
        final sellerProfile = await _sellerService.verifySellerAndGetProfile(
          response.user!.id,
        );

        final sellerData = sellerProfile['seller'] as Map<String, dynamic>;
        final workerData = sellerProfile['worker'] as Map<String, dynamic>;
        final entryRole = sellerProfile['entryRole']?.toString() ?? 'vendedor';

        final idTpv = (sellerProfile['idTpv'] as num).toInt();
        final idTienda = (sellerProfile['idTienda'] as num).toInt();
        final idSeller = (sellerData['id'] as num?)?.toInt() ?? 0;
        final idTrabajador =
            (sellerData['id_trabajador'] as num?)?.toInt() ?? 0;
        final idAlmacen = (sellerProfile['idAlmacen'] as num?)?.toInt();

        print('🔍 Perfil de acceso a Caja:');
        print('  - Entry role: $entryRole');
        print('  - ID TPV: $idTpv');
        print('  - ID Tienda: $idTienda');
        print('  - ID Seller: $idSeller');

        await _userPreferencesService.saveSellerData(
          idTpv: idTpv,
          idTrabajador: idTrabajador,
          permitirCustomizarPrecioVenta:
              sellerData['permitir_customizar_precio_venta'] == true,
        );

        if (idSeller > 0) {
          await _userPreferencesService.saveIdSeller(idSeller);
        }
        if (idAlmacen != null) {
          await _userPreferencesService.saveIdAlmacen(idAlmacen);
        }

        await _userPreferencesService.saveWorkerProfile(
          nombres: (workerData['nombres'] ?? '').toString(),
          apellidos: (workerData['apellidos'] ?? '').toString(),
          idTienda: idTienda,
          idRoll: (workerData['id_roll'] as num?)?.toInt() ?? 4,
        );

        await _userPreferencesService.ensureOfflineStoreScope(idTienda);

        await _userPreferencesService.setCajaEntryRole(entryRole);

        // Refrescar el rol de cocina en la reautenticación: si el admin acaba
        // de asignar o quitar la cocina, el home debe cambiar sin obligar a
        // cerrar sesión. Un fallo aquí no interrumpe la reautenticación.
        await _userPreferencesService.setCocinaRole(
          await ComandaService().rolDeCocina(),
        );

        try {
          await AdminAccessService().refreshAndCache();
        } catch (_) {}

        print('✅ Perfil de acceso a Caja guardado ($entryRole)');

        // PASO 6: Actualizar promoción global
        try {
          final globalPromotion = await _promotionService.getGlobalPromotion(
            idTienda,
          );

          if (globalPromotion != null) {
            await _promotionService.saveGlobalPromotion(
              idPromocion: globalPromotion['id_promocion'],
              codigoPromocion: globalPromotion['codigo_promocion'],
              valorDescuento: globalPromotion['valor_descuento'],
              tipoDescuento: globalPromotion['tipo_descuento'],
              idTipoPromocion: globalPromotion['id_tipo_promocion'],
              minCompra: (globalPromotion['min_compra'] as num?)?.toDouble(),
              aplicaTodo: globalPromotion['aplica_todo'],
              requiereMedioPago: globalPromotion['requiere_medio_pago'],
              idMedioPagoRequerido: globalPromotion['id_medio_pago_requerido'],
            );
            print('🎯 Promoción global actualizada');
          } else {
            await _promotionService.saveGlobalPromotion(
              idPromocion: null,
              codigoPromocion: null,
              valorDescuento: null,
              tipoDescuento: null,
            );
            print('ℹ️ No hay promoción global activa');
          }
        } catch (e) {
          print('⚠️ Error actualizando promoción global: $e');
          // Guardar null en caso de error
          await _promotionService.saveGlobalPromotion(
            idPromocion: null,
            codigoPromocion: null,
            valorDescuento: null,
            tipoDescuento: null,
          );
        }

        // PASO 7: Actualizar usuario en array offline (para futuras sesiones offline)
        await _userPreferencesService.saveOfflineUser(
          email: email,
          password: password,
          userId: response.user!.id,
        );

        print('✅ Reautenticación completa exitosa');
        print('🌐 Usuario listo para trabajar online');

        return true;
      } catch (e) {
        print('❌ Error verificando perfil del vendedor: $e');

        // Limpiar datos en caso de error
        await _userPreferencesService.clearUserData();
        await _authService.signOut();

        return false;
      }
    } catch (e) {
      print('❌ Error en reautenticación automática: $e');
      return false;
    }
  }

  /// Verificar si es necesario reautenticar
  /// Retorna true si el usuario necesita reautenticación
  Future<bool> needsReauthentication() async {
    try {
      // Verificar si hay una sesión activa en Supabase
      final currentUser = Supabase.instance.client.auth.currentUser;

      if (currentUser == null) {
        print(
          '🔍 No hay sesión activa en Supabase - Reautenticación necesaria',
        );
        return true;
      }

      // Verificar si la sesión ha expirado
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        print('🔍 Sesión expirada - Reautenticación necesaria');
        return true;
      }

      // Verificar si el token está próximo a expirar (menos de 5 minutos)
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        session.expiresAt! * 1000,
      );
      final now = DateTime.now();
      final timeUntilExpiry = expiresAt.difference(now);

      if (timeUntilExpiry.inMinutes < 5) {
        print(
          '🔍 Token próximo a expirar (${timeUntilExpiry.inMinutes} min) - Reautenticación necesaria',
        );
        return true;
      }

      // Verificar que los datos locales estén completos
      final userData = await _userPreferencesService.getUserData();
      final hasCompleteData =
          userData['userId'] != null &&
          userData['email'] != null &&
          userData['accessToken'] != null &&
          userData['accessToken'] != 'offline_mode';

      if (!hasCompleteData) {
        print('🔍 Datos locales incompletos - Reautenticación necesaria');
        return true;
      }

      print('✅ Sesión válida - No se requiere reautenticación');
      return false;
    } catch (e) {
      print('❌ Error verificando necesidad de reautenticación: $e');
      return true; // En caso de error, asumir que se necesita reautenticar
    }
  }

  /// Reautenticar solo si es necesario
  /// Retorna true si el usuario está autenticado (ya estaba o se reautenticó exitosamente)
  Future<bool> ensureAuthenticated() async {
    try {
      final loggedIn = await _userPreferencesService.isLoggedIn();
      if (!loggedIn) {
        print('🚫 ensureAuthenticated: no hay sesión local activa');
        return false;
      }

      final needsReauth = await needsReauthentication();

      if (!needsReauth) {
        print('✅ Usuario ya autenticado correctamente');
        return true;
      }

      print('🔄 Iniciando reautenticación automática...');
      return await reauthenticateUser();
    } catch (e) {
      print('❌ Error asegurando autenticación: $e');
      return false;
    }
  }

  /// Obtener información del estado de autenticación
  Future<AuthenticationStatus> getAuthenticationStatus() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final session = Supabase.instance.client.auth.currentSession;
      final userData = await _userPreferencesService.getUserData();
      final credentials = await _userPreferencesService.getSavedCredentials();

      return AuthenticationStatus(
        hasSupabaseSession: currentUser != null && session != null,
        hasLocalUserData: userData['userId'] != null,
        hasCredentials:
            credentials['email'] != null && credentials['password'] != null,
        isOfflineMode: userData['accessToken'] == 'offline_mode',
        sessionExpiresAt:
            session?.expiresAt != null
                ? DateTime.fromMillisecondsSinceEpoch(
                  session!.expiresAt! * 1000,
                )
                : null,
        currentUserId: currentUser?.id,
        currentEmail: currentUser?.email ?? userData['email'],
      );
    } catch (e) {
      print('❌ Error obteniendo estado de autenticación: $e');
      return AuthenticationStatus(
        hasSupabaseSession: false,
        hasLocalUserData: false,
        hasCredentials: false,
        isOfflineMode: false,
        sessionExpiresAt: null,
        currentUserId: null,
        currentEmail: null,
      );
    }
  }
}

/// Estado de autenticación del usuario
class AuthenticationStatus {
  final bool hasSupabaseSession;
  final bool hasLocalUserData;
  final bool hasCredentials;
  final bool isOfflineMode;
  final DateTime? sessionExpiresAt;
  final String? currentUserId;
  final String? currentEmail;

  AuthenticationStatus({
    required this.hasSupabaseSession,
    required this.hasLocalUserData,
    required this.hasCredentials,
    required this.isOfflineMode,
    this.sessionExpiresAt,
    this.currentUserId,
    this.currentEmail,
  });

  bool get isFullyAuthenticated =>
      hasSupabaseSession && hasLocalUserData && !isOfflineMode;
  bool get canReauthenticate => hasCredentials;
  bool get needsReauthentication => !hasSupabaseSession || isOfflineMode;

  @override
  String toString() {
    return 'AuthenticationStatus('
        'hasSupabaseSession: $hasSupabaseSession, '
        'hasLocalUserData: $hasLocalUserData, '
        'hasCredentials: $hasCredentials, '
        'isOfflineMode: $isOfflineMode, '
        'isFullyAuthenticated: $isFullyAuthenticated, '
        'canReauthenticate: $canReauthenticate, '
        'needsReauthentication: $needsReauthentication'
        ')';
  }
}
