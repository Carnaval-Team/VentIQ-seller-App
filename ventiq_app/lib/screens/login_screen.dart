import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_preferences_service.dart';
import '../services/seller_service.dart';
import '../services/promotion_service.dart';
import '../services/store_config_service.dart';
import '../services/settings_integration_service.dart';
import '../services/auto_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/subscription_guard_service.dart';
import '../services/subscription_service.dart';
import '../services/admin_access_service.dart';
import '../services/smart_offline_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../services/comanda_service.dart';
import '../utils/navigation_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _userPreferencesService = UserPreferencesService();
  final _sellerService = SellerService();
  final _promotionService = PromotionService();
  final _integrationService = SettingsIntegrationService();
  final _connectivityService = ConnectivityService();
  final _subscriptionGuard = SubscriptionGuardService();
  final _subscriptionService = SubscriptionService();
  bool _isLoading = false;
  bool _obscure = true;
  bool _rememberMe = false;
  bool _deviceFullOfflineReady = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pauseSyncForLoginScreen();
    _loadSavedCredentials();
    _checkFullOffline();
  }

  /// Detiene sync/monitoring mientras el usuario no ha iniciado sesión.
  Future<void> _pauseSyncForLoginScreen() async {
    try {
      await AutoSyncService().stopAutoSync();
      await SettingsIntegrationService().stop();
      print('🛑 Sync pausado en pantalla de login (sin sesión activa)');
    } catch (e) {
      print('⚠️ No se pudo pausar sync en login: $e');
    }
  }

  Future<void> _checkFullOffline() async {
    final ready = await _userPreferencesService.isDeviceFullOfflineReady();
    if (mounted) setState(() => _deviceFullOfflineReady = ready);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final shouldRemember = await _userPreferencesService.shouldRememberMe();
    if (shouldRemember) {
      final credentials = await _userPreferencesService.getSavedCredentials();
      setState(() {
        _emailController.text = credentials['email'] ?? '';
        _passwordController.text = credentials['password'] ?? '';
        _rememberMe = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      FocusScope.of(context).unfocus();

      // Full offline locked: nunca autenticar contra el servidor aunque haya red.
      if (await _userPreferencesService.shouldStayFullyOffline()) {
        print('📦 Full offline activo: login solo local (sin servidor)');
        final offlineOk = await _attemptOfflineLogin();
        if (!offlineOk && mounted) {
          setState(() {
            _errorMessage =
                'No se pudo iniciar sesión offline. Verifica usuario/contraseña '
                'registrados en este dispositivo.';
            _isLoading = false;
          });
        }
        return;
      }

      // PASO 1: Verificar si hay conexión real a internet
      print('🔍 Verificando conexión a internet...');
      final hasInternetConnection =
          await _connectivityService.checkConnectivity();

      if (hasInternetConnection) {
        // ✅ HAY CONEXIÓN: Desactivar modo offline automáticamente y hacer login normal
        print('✅ Conexión a internet detectada');

        // Verificar si el modo offline estaba activado
        final wasOfflineModeEnabled =
            await _userPreferencesService.isOfflineModeEnabled();

        if (wasOfflineModeEnabled) {
          final fullOfflineReady =
              await _userPreferencesService.isDeviceFullOfflineReady();
          if (fullOfflineReady) {
            print(
              '📦 Dispositivo full-offline: se mantiene el modo offline '
              '(no se desactiva por tener conexión)',
            );
          } else {
            print(
              '🔄 Desactivando modo offline automáticamente (hay conexión disponible)',
            );
            await _userPreferencesService.setOfflineMode(false);
          }
        }

        // Continuar con login online normal
        print('🌐 Modo online - Autenticando con Supabase...');
      } else {
        // ❌ NO HAY CONEXIÓN: Intentar login offline
        print('📵 Sin conexión a internet - Intentando login offline...');

        // Verificar si el usuario existe en el array de usuarios offline
        final hasOfflineUser = await _userPreferencesService.hasOfflineUser(
          _emailController.text.trim(),
        );

        if (hasOfflineUser) {
          print('📱 Usuario encontrado en modo offline');

          // Intentar login offline
          final offlineLoginSuccess = await _attemptOfflineLogin();

          if (offlineLoginSuccess) {
            return; // Login offline exitoso
          } else {
            // Credenciales incorrectas en modo offline
            setState(() {
              _errorMessage = 'Contraseña incorrecta (Modo Offline)';
              _isLoading = false;
            });
            return;
          }
        } else {
          print('⚠️ Usuario no encontrado en modo offline - Requiere conexión');
          setState(() {
            _errorMessage =
                'Usuario no sincronizado. Requiere conexión a internet para primer login.';
            _isLoading = false;
          });
          return;
        }
      }

      // PASO 2: Login normal con conexión (modo online)

      try {
        final response = await _authService.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (response.user != null) {
          // Guardar datos básicos del usuario en las preferencias
          await _userPreferencesService.saveUserData(
            userId: response.user!.id,
            email: response.user!.email ?? _emailController.text.trim(),
            accessToken: response.session?.accessToken ?? '',
          );

          print('✅ Usuario guardado en preferencias:');
          print('  - ID: ${response.user!.id}');
          print('  - Email: ${response.user!.email}');
          print(
            '  - Access Token: ${response.session?.accessToken != null ? response.session!.accessToken.substring(0, 20) : "null"}...',
          );

          // Verificar y cachear si es superadmin (para herramientas ocultas).
          // Se cachea para que la entrada del drawer funcione también offline.
          try {
            final esSuperAdmin =
                await _sellerService.isSuperAdmin(response.user!.id);
            await _userPreferencesService.setIsSuperAdmin(esSuperAdmin);
            print('  - Superadmin: $esSuperAdmin');
          } catch (e) {
            print('⚠️ No se pudo verificar superadmin: $e');
          }

          // Gate Admin Lite: solo gerente (mismo uuid) sin segundo login.
          // Se cachea después de guardar id_tienda (más abajo); aquí solo
          // preparamos el clear de memoria por si cambia de cuenta.
          try {
            AdminAccessService().clearMemoryCache();
          } catch (_) {}

          // Verificar acceso a Caja: vendedor, gerente o supervisor
          try {
            final sellerProfile = await _sellerService
                .verifySellerAndGetProfile(response.user!.id);

            final sellerData = sellerProfile['seller'] as Map<String, dynamic>;
            final workerData = sellerProfile['worker'] as Map<String, dynamic>;
            final entryRole = sellerProfile['entryRole']?.toString() ?? 'vendedor';

            // Extraer IDs por separado
            final idTpv = (sellerProfile['idTpv'] as num).toInt();
            final idTienda = (sellerProfile['idTienda'] as num).toInt();
            final idSeller = (sellerData['id'] as num?)?.toInt() ?? 0;
            final idAlmacen = (sellerProfile['idAlmacen'] as num?)?.toInt();
            final idTrabajador =
                (sellerData['id_trabajador'] as num?)?.toInt() ?? 0;
            print('🔍 IDs extraídos por separado:');
            print('  - Entry role: $entryRole');
            print('  - ID TPV: $idTpv');
            print('  - ID Tienda: $idTienda');
            print('  - ID Seller: $idSeller');
            print('  - ID Almacen: $idAlmacen');

            // Guardar datos operativos (TPV/trabajador). Gerente/supervisor
            // sin fila de vendedor usan TPV por defecto de la tienda.
            await _userPreferencesService.saveSellerData(
              idTpv: idTpv,
              idTrabajador: idTrabajador,
              permitirCustomizarPrecioVenta:
                  sellerData['permitir_customizar_precio_venta'] == true,
            );
            if (idAlmacen != null) {
              await _userPreferencesService.saveIdAlmacen(idAlmacen);
            }

            if (idSeller > 0) {
              await _userPreferencesService.saveIdSeller(idSeller);
            }

            // Guardar perfil del trabajador
            await _userPreferencesService.saveWorkerProfile(
              nombres: (workerData['nombres'] ?? '').toString(),
              apellidos: (workerData['apellidos'] ?? '').toString(),
              idTienda: idTienda,
              idRoll: (workerData['id_roll'] as num?)?.toInt() ?? 4,
            );

            // Misma tienda = mismo inventario local (vendedor + admin).
            await _userPreferencesService.ensureOfflineStoreScope(idTienda);

            await _userPreferencesService.setCajaEntryRole(entryRole);

            // Rol de cocina: decide el home de la sesión (KDS para el personal
            // de cocina). Se cachea aquí para no consultar
            // `fn_cocinas_del_usuario` en cada navegación a Home.
            //
            // Se salta para gerente/supervisor: aunque tengan cocinas, su home
            // es la administración de la tienda. Y si la consulta falla no se
            // interrumpe el login: se queda sin rol de cocina y el usuario
            // entra al home de siempre.
            final rolCocina = await ComandaService().rolDeCocina();
            await _userPreferencesService.setCocinaRole(rolCocina);
            print('  - Rol de cocina: ${rolCocina.isEmpty ? "(ninguno)" : rolCocina}');

            // Cachear rol admin (gerente/supervisor) para menú offline.
            try {
              final adminRole = await AdminAccessService().refreshAndCache();
              print('  - Admin Lite role: $adminRole');
            } catch (e) {
              print('⚠️ No se pudo cachear rol admin: $e');
            }

            // Guardar credenciales si el usuario marcó "Recordarme"
            if (_rememberMe) {
              await _userPreferencesService.saveCredentials(
                _emailController.text.trim(),
                _passwordController.text,
              );
            } else {
              await _userPreferencesService.clearSavedCredentials();
            }

            print('✅ Perfil de acceso a Caja guardado ($entryRole)');

            // Buscar promoción global para la tienda
            try {
              final globalPromotion = await _promotionService
                  .getGlobalPromotion(idTienda);
              if (globalPromotion != null) {
                await _promotionService.saveGlobalPromotion(
                  idPromocion: globalPromotion['id_promocion'],
                  codigoPromocion: globalPromotion['codigo_promocion'],
                  valorDescuento: globalPromotion['valor_descuento'],
                  tipoDescuento: globalPromotion['tipo_descuento'],
                  idTipoPromocion: globalPromotion['id_tipo_promocion'],
                  minCompra:
                      (globalPromotion['min_compra'] as num?)?.toDouble(),
                  aplicaTodo: globalPromotion['aplica_todo'],
                  requiereMedioPago: globalPromotion['requiere_medio_pago'],
                  idMedioPagoRequerido:
                      globalPromotion['id_medio_pago_requerido'],
                );
                print('🎯 Promoción global configurada para la tienda');
              } else {
                // Guardar null cuando no hay promoción
                await _promotionService.saveGlobalPromotion(
                  idPromocion: null,
                  codigoPromocion: null,
                  valorDescuento: null,
                  tipoDescuento: null,
                );
                print('ℹ️ No hay promoción global activa - guardando null');
              }
            } catch (e) {
              print('⚠️ Error obteniendo promoción global: $e');
              // Guardar null en caso de error también
              await _promotionService.saveGlobalPromotion(
                idPromocion: null,
                codigoPromocion: null,
                valorDescuento: null,
                tipoDescuento: null,
              );
            }

            // Cargar configuración de tienda
            try {
              print('🔧 Cargando configuración de tienda...');
              final storeConfig = await StoreConfigService.getStoreConfig(
                idTienda,
              );
              if (storeConfig != null) {
                print('✅ Configuración de tienda cargada exitosamente');
                print(
                  '  - need_master_password_to_cancel: ${storeConfig['need_master_password_to_cancel']}',
                );
                print(
                  '  - need_all_orders_completed_to_continue: ${storeConfig['need_all_orders_completed_to_continue']}',
                );
              } else {
                print(
                  '⚠️ No se pudo cargar configuración de tienda - usando valores por defecto',
                );
              }
            } catch (e) {
              print('❌ Error cargando configuración de tienda: $e');
            }

            // Cargar denominaciones de moneda
            try {
              print('💰 Cargando denominaciones de moneda...');
              await _loadCurrencyDenominations();
              print('✅ Denominaciones de moneda cargadas exitosamente');
            } catch (e) {
              print('❌ Error cargando denominaciones de moneda: $e');
            }

            // Inicializar servicios inteligentes en segundo plano
            _initializeSmartServices();

            // Verificar suscripción antes de navegar
            if (mounted) {
              final hasActiveSubscription = await _subscriptionGuard
                  .hasActiveSubscription(forceRefresh: true);

              // Guardar datos de suscripción si existe
              if (hasActiveSubscription) {
                final subscription =
                    await _subscriptionGuard.getCurrentSubscription();
                if (subscription != null) {
                  await _userPreferencesService.saveSubscriptionData(
                    subscriptionId: subscription.id,
                    state: subscription.estado,
                    planId: subscription.idPlan,
                    planName:
                        subscription.planDenominacion ?? 'Plan desconocido',
                    startDate: subscription.fechaInicio,
                    endDate: subscription.fechaFin,
                    features: subscription.planFuncionesHabilitadas,
                  );
                  print('💾 Datos de suscripción guardados en login');
                }
              }

              if (hasActiveSubscription) {
                // Verificar si la suscripción está próxima a vencer
                await _checkAndShowSubscriptionWarning(idTienda);

                // Destino según rol: gerente/supervisor → gestión, personal de
                // cocina → KDS, resto → catálogo o mesas. Lo resuelve
                // NavigationHelper para no duplicar el criterio aquí.
                final destino = await NavigationHelper.homeRoute();
                if (!mounted) return;
                Navigator.of(context).pushReplacementNamed(destino);
              } else {
                // Sin suscripción activa - ir a detalles de suscripción
                Navigator.of(
                  context,
                ).pushReplacementNamed('/subscription-detail');
              }
            }
          } catch (e) {
            // Error: usuario no es vendedor válido
            print('❌ Error de verificación: $e');

            // Limpiar datos guardados
            await _userPreferencesService.clearUserData();
            await _authService.signOut();

            setState(() {
              _errorMessage = 'Acceso denegado: $e';
              _isLoading = false;
            });
            return;
          }
        } else {
          setState(() {
            _errorMessage =
                'Error de autenticación. Verifica tus credenciales.';
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = _getErrorMessage(e.toString());
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  /// Intentar login offline validando credenciales locales
  Future<bool> _attemptOfflineLogin() async {
    try {
      print('🔐 Intentando login offline...');

      // Validar credenciales contra el array de usuarios offline
      final offlineUser = await _userPreferencesService.validateOfflineUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (offlineUser == null) {
        print('❌ Credenciales offline inválidas');
        return false;
      }

      print('✅ Credenciales offline válidas');
      print('  - Email: ${offlineUser['email']}');
      print('  - UserId: ${offlineUser['userId']}');
      print('  - idTienda: ${offlineUser['idTienda']}');
      print('  - idTpv: ${offlineUser['idTpv']}');
      print('  - Última sincronización: ${offlineUser['lastSync']}');

      // Cargar datos offline del usuario
      final offlineData = await _userPreferencesService.getOfflineData();

      if (offlineData == null) {
        print('❌ No hay datos offline guardados');
        if (mounted) {
          setState(() {
            _errorMessage =
                'No hay datos sincronizados. Active modo offline con conexión primero.';
            _isLoading = false;
          });
        }
        return false;
      }

      // Restaurar TODOS los datos del usuario en SharedPreferences
      await _userPreferencesService.saveUserData(
        userId: offlineUser['userId'],
        email: offlineUser['email'],
        accessToken: 'offline_mode', // Token especial para modo offline
      );

      // Restaurar datos del vendedor
      if (offlineUser['idTpv'] != null && offlineUser['idTrabajador'] != null) {
        await _userPreferencesService.saveSellerData(
          idTpv: offlineUser['idTpv'],
          idTrabajador: offlineUser['idTrabajador'],
          permitirCustomizarPrecioVenta:
              offlineUser['permitir_customizar_precio_venta'] == true,
        );
      }

      // Restaurar ID del vendedor
      if (offlineUser['idSeller'] != null) {
        await _userPreferencesService.saveIdSeller(offlineUser['idSeller']);
      }

      // Restaurar perfil del trabajador
      if (offlineUser['nombres'] != null &&
          offlineUser['apellidos'] != null &&
          offlineUser['idTienda'] != null &&
          offlineUser['idRoll'] != null) {
        await _userPreferencesService.saveWorkerProfile(
          nombres: offlineUser['nombres'],
          apellidos: offlineUser['apellidos'],
          idTienda: offlineUser['idTienda'],
          idRoll: offlineUser['idRoll'],
        );
        final storeId = offlineUser['idTienda'];
        if (storeId is int) {
          await _userPreferencesService.ensureOfflineStoreScope(storeId);
        } else if (storeId is num) {
          await _userPreferencesService.ensureOfflineStoreScope(storeId.toInt());
        }
      }

      final entryRole = offlineUser['entryRole']?.toString();
      if (entryRole != null && entryRole.isNotEmpty) {
        await _userPreferencesService.setCajaEntryRole(entryRole);
        final storeId = offlineUser['idTienda'];
        if (storeId != null) {
          final sid = storeId is int ? storeId : (storeId as num).toInt();
          final adminRole =
              (entryRole == 'gerente' || entryRole == 'supervisor')
                  ? entryRole
                  : 'none';
          await _userPreferencesService.setCachedAdminRoleRaw(sid, adminRole);
        }
        AdminAccessService().clearMemoryCache();
      }

      print('✅ Login offline exitoso - Todos los datos restaurados');
      print('🔌 Trabajando en modo offline');
      await _userPreferencesService.setOfflineMode(true);

      // En full offline no inicializar auto-sync; en offline temporal sí
      // (initialize respeta el flag offline y no arranca sync).
      if (!await _userPreferencesService.isDeviceFullOfflineReady()) {
        _initializeSmartServices();
      } else {
        try {
          await SmartOfflineManager().onOfflineModeManuallyEnabled();
        } catch (_) {}
      }

      // Verificar suscripción antes de navegar (modo offline)
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // En modo offline, validar licencia firmada (no solo caché de 5 min)
        final hasActiveSubscription =
            await _subscriptionGuard.hasActiveSubscription();

        if (hasActiveSubscription) {
          // Mismo criterio que el login online, pero SIN consultar el rol de
          // cocina: aquí no hay red. Se usa el que quedó cacheado del último
          // login online, que es justo para lo que se cacheó.
          final destino = await NavigationHelper.homeRoute();
          if (!mounted) return true;
          Navigator.of(context).pushReplacementNamed(destino);
        } else {
          // Sin licencia válida - bloquear app en detalles de suscripción
          Navigator.of(context).pushReplacementNamed('/subscription-detail');
        }
      }

      return true;
    } catch (e) {
      print('❌ Error en login offline: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error en login offline: $e';
          _isLoading = false;
        });
      }
      return false;
    }
  }

  /// Inicializar servicios inteligentes después del login exitoso
  Future<void> _initializeSmartServices() async {
    try {
      print('🚀 Inicializando servicios inteligentes después del login...');

      // ✅ MEJORADO: Ejecutar primera sincronización inmediatamente
      // Inicializar el servicio de integración en segundo plano
      _integrationService
          .initialize()
          .then((_) {
            print('✅ Servicios inteligentes inicializados correctamente');
          })
          .catchError((e) {
            print('❌ Error inicializando servicios inteligentes: $e');
            // No mostramos error al usuario ya que no es crítico para el login
          });

      // Ejecutar primera sincronización inmediatamente sin esperar la inicialización completa
      print('⚡ Ejecutando primera sincronización inmediata...');
      final autoSyncService = AutoSyncService();
      autoSyncService
          .performImmediateSync()
          .then((_) {
            print('✅ Primera sincronización inmediata completada');
          })
          .catchError((e) {
            print('❌ Error en primera sincronización inmediata: $e');
          });
    } catch (e) {
      print('❌ Error configurando servicios inteligentes: $e');
      // No lanzamos el error para no afectar el flujo de login
    }
  }

  String _getErrorMessage(String error) {
    if (error.contains('Invalid login credentials')) {
      return 'Credenciales inválidas. Verifica tu email y contraseña.';
    } else if (error.contains('Email not confirmed')) {
      return 'Email no confirmado. Revisa tu bandeja de entrada.';
    } else if (error.contains('Too many requests')) {
      return 'Demasiados intentos. Intenta de nuevo más tarde.';
    } else if (error.contains('Network')) {
      return 'Error de conexión. Verifica tu internet.';
    }
    return 'Error de autenticación. Intenta de nuevo.';
  }

  /// Cargar denominaciones de moneda desde Supabase
  Future<void> _loadCurrencyDenominations() async {
    try {
      print('💰 Consultando denominaciones de moneda en Supabase...');

      final response = await Supabase.instance.client
          .from('app_dat_denominaciones_moneda')
          .select('*')
          .eq('active', true)
          .order('codigo_moneda', ascending: true)
          .order('denominacion', ascending: true);

      if (response.isNotEmpty) {
        print('💱 Denominaciones obtenidas: ${response.length}');

        // Guardar en UserPreferencesService
        await _userPreferencesService.saveMonedasDenominacion(
          List<Map<String, dynamic>>.from(response),
        );

        // Log de monedas disponibles
        final monedas =
            response.map((d) => d['codigo_moneda']).toSet().toList();
        print('💰 Monedas configuradas: ${monedas.join(', ')}');

        // Log de denominaciones por moneda
        for (final moneda in monedas) {
          final denominacionesMoneda =
              response
                  .where((d) => d['codigo_moneda'] == moneda)
                  .map((d) => d['denominacion'])
                  .toList();
          print('  - $moneda: ${denominacionesMoneda.join(', ')}');
        }
      } else {
        print('⚠️ No se encontraron denominaciones de moneda activas');
        // Guardar lista vacía para evitar errores
        await _userPreferencesService.saveMonedasDenominacion([]);
      }
    } catch (e) {
      print('❌ Error cargando denominaciones de moneda: $e');
      // En caso de error, guardar lista vacía
      await _userPreferencesService.saveMonedasDenominacion([]);
      rethrow;
    }
  }

  /// Verificar si la suscripción está próxima a vencer y mostrar diálogo de advertencia
  Future<void> _checkAndShowSubscriptionWarning(int idTienda) async {
    try {
      print('⏰ Verificando expiración de suscripción...');

      final expirationInfo = await _subscriptionService
          .checkSubscriptionExpiration(idTienda);

      if (expirationInfo != null && mounted) {
        final diasRestantes = expirationInfo['diasRestantes'] as int;
        final fechaFin = expirationInfo['fechaFin'] as DateTime;
        final planNombre = expirationInfo['planNombre'] as String;
        final estado = expirationInfo['estado'] as String;

        print('⚠️ Suscripción próxima a vencer: $diasRestantes días restantes');

        // Obtener información de la tienda
        final idTiendaActual = await _userPreferencesService.getIdTienda();
        String nombreTienda = 'Tu tienda';

        if (idTiendaActual != null) {
          try {
            final tiendaData =
                await Supabase.instance.client
                    .from('app_dat_tienda')
                    .select('denominacion')
                    .eq('id', idTiendaActual)
                    .single();
            nombreTienda = tiendaData['denominacion'] ?? nombreTienda;
          } catch (e) {
            print('⚠️ No se pudo obtener nombre de tienda: $e');
          }
        }

        final dateFormat = DateFormat('dd/MM/yyyy');

        // Mostrar diálogo de advertencia
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: diasRestantes == 0 ? Colors.red : Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '⚠️ Suscripción Próxima a Vencer',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              diasRestantes == 0
                                  ? Colors.red.shade50
                                  : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                diasRestantes == 0
                                    ? Colors.red.shade200
                                    : Colors.orange.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              diasRestantes == 0
                                  ? '¡Tu suscripción vence HOY!'
                                  : diasRestantes == 1
                                  ? '¡Tu suscripción vence MAÑANA!'
                                  : 'Tu suscripción vence en $diasRestantes días',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color:
                                    diasRestantes == 0
                                        ? Colors.red.shade700
                                        : Colors.orange.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Divider(),
                            const SizedBox(height: 8),
                            _buildInfoRow('🏪 Tienda:', nombreTienda),
                            const SizedBox(height: 6),
                            _buildInfoRow('📦 Plan:', planNombre),
                            const SizedBox(height: 6),
                            _buildInfoRow('📊 Estado:', estado),
                            const SizedBox(height: 6),
                            _buildInfoRow(
                              '📅 Fecha de vencimiento:',
                              dateFormat.format(fechaFin),
                            ),
                            const SizedBox(height: 6),
                            _buildInfoRow(
                              '⏰ Días restantes:',
                              diasRestantes == 0
                                  ? 'Vence hoy'
                                  : '$diasRestantes días',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Por favor, renueva tu suscripción para continuar disfrutando de todos los servicios sin interrupciones.',
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Entendido'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Navegar a la pantalla de suscripción
                      Navigator.of(context).pushNamed('/subscription-detail');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Ver Suscripción'),
                  ),
                ],
              ),
        );
      } else {
        print('✅ Suscripción no requiere advertencia');
      }
    } catch (e) {
      print('❌ Error verificando expiración de suscripción: $e');
      // No mostrar error al usuario, solo log
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Solid blue background
          Container(decoration: const BoxDecoration(color: Color(0xFF4A90E2))),
          // Top section with logo
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: Container(
              color: const Color(0xFF4A90E2),
              child: Center(
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/inventia_logo.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          // White wavy panel with form
          Positioned(
            top: 250,
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            // Email field
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(
                                  color: const Color(0xFFE9ECEF),
                                ),
                              ),
                              child: TextFormField(
                                controller: _emailController,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  hintText: 'Email',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: Color(0xFF4A90E2),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 20,
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'Ingrese su email';
                                  }
                                  if (!v.contains('@')) {
                                    return 'Ingrese un email válido';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Password field
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(25),
                                border: Border.all(
                                  color: const Color(0xFFE9ECEF),
                                ),
                              ),
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Color(0xFF4A90E2),
                                  ),
                                  suffixIcon: IconButton(
                                    onPressed:
                                        () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 20,
                                  ),
                                ),
                                onFieldSubmitted: (_) => _submit(),
                                validator:
                                    (v) =>
                                        (v == null || v.isEmpty)
                                            ? 'Ingrese su contraseña'
                                            : null,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_deviceFullOfflineReady) ...[
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushReplacementNamed(
                                    '/offline-user-switch',
                                  );
                                },
                                icon: const Icon(Icons.people_outline),
                                label: const Text(
                                  'Usuarios offline del dispositivo',
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            // Remember me checkbox
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? false;
                                    });
                                  },
                                  activeColor: const Color(0xFF4A90E2),
                                ),
                                const Text(
                                  'Recordarme',
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Error message
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red.shade600,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_errorMessage != null)
                              const SizedBox(height: 16),
                            // Login button
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4A90E2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: _isLoading ? null : _submit,
                                child:
                                    _isLoading
                                        ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                        : const Text(
                                          'Login',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Forgot password link
                            TextButton(
                              onPressed: () {
                                /* TODO: forgot password flow */
                              },
                              child: const Text(
                                'FORGOT PASSWORD ?',
                                style: TextStyle(
                                  color: Color(0xFF4A90E2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple wave clipper for the top edge of the white panel
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    // Create a panel with a wavy TOP edge and straight sides/bottom
    final path =
        Path()
          ..moveTo(0, 60)
          // First curve peak/trough
          ..quadraticBezierTo(size.width * 0.25, 20, size.width * 0.5, 40)
          // Second curve
          ..quadraticBezierTo(size.width * 0.75, 60, size.width, 30)
          // Right edge down to bottom
          ..lineTo(size.width, size.height)
          // Bottom edge to left
          ..lineTo(0, size.height)
          // Close back to start to complete shape
          ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
