import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../services/order_service.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../services/currency_service.dart';
import '../utils/price_utils.dart';
import '../services/settings_integration_service.dart';
import '../services/auto_sync_service.dart';
import '../services/store_config_service.dart';
import '../services/printer_manager.dart';
import '../utils/navigation_helper.dart';
import '../services/update_service.dart';
import '../services/subscription_guard_service.dart';
import '../models/subscription.dart';
import '../theme/ventiq_home_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sync_status_chip.dart';
import '../widgets/selective_sync_dialog.dart';
import '../services/connectivity_service.dart';
import '../services/smart_offline_manager.dart';
import '../services/offline_license_service.dart';
import 'dart:async';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const String _downloadAppUrl =
      'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/apk/inventtia%20caja.apk';

  final OrderService _orderService = OrderService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final SettingsIntegrationService _integrationService =
      SettingsIntegrationService();
  final SubscriptionGuardService _subscriptionGuard =
      SubscriptionGuardService();
  final ConnectivityService _connectivity = ConnectivityService();

  bool _isPrintEnabled = true; // Valor por defecto
  bool _isPrintUsdEnabled = false; // Valor por defecto
  bool _isStaticTextEnabled = false; // Valor por defecto (marquee activo)
  bool _isShowSkuEnabled = false; // Valor por defecto (SKU oculto)
  bool _isLimitDataUsageEnabled = false; // Valor por defecto
  bool _isFluidModeEnabled =
      false; // Deshabilitado - Disponible en próxima versión
  bool _isOfflineModeEnabled = false; // Valor por defecto
  bool _isTogglingOfflineMode =
      false; // Cambio de modo offline en curso (deshabilita el switch)
  Map<String, dynamic>? _currentTurno; // Turno abierto (online u offline)
  Map<String, dynamic>? _dataSyncSummary; // Resumen de datos pendientes
  bool _isLoadingDataSection = false;
  bool _isModoRestauranteEnabled =
      false; // Modo restaurante (mesas y comensales)
  bool _isLoadingModoRestaurante = false;

  // Impresora recordada para el turno actual
  String? _savedPrinterDescription;
  bool _hasSavedPrinter = false;

  // Nuevas variables para servicios inteligentes
  StreamSubscription<SettingsIntegrationEvent>? _integrationSubscription;
  bool _isSmartServicesInitialized = false;
  String? _lastSmartEvent;
  SettingsIntegrationStatus? _smartIntegrationStatus;

  // Variable para la versión dinámica
  String _appVersion = 'Cargando...';

  // Variables para suscripción
  Subscription? _currentSubscription;
  OfflineLicenseStatus? _licenseStatus;
  bool _isLoadingSubscription = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _refreshDataSection();
    _loadAppVersion();
    _loadSubscriptionData();
    _initializeSmartServices();
  }

  int get _pendingOfflineTurnosCount =>
      _dataSyncSummary?['pending_turnos_count'] as int? ?? 0;

  int get _pendingOrdersCount =>
      _dataSyncSummary?['pending_orders_count'] as int? ?? 0;

  bool get _hasPendingOfflineData =>
      _pendingOfflineTurnosCount > 0 ||
      _pendingOrdersCount > 0 ||
      (_dataSyncSummary?['pending_operations_count'] as int? ?? 0) > 0;

  /// Cargar datos de suscripción y licencia para la sección de configuración.
  Future<void> _loadSubscriptionData() async {
    if (!mounted) return;
    setState(() => _isLoadingSubscription = true);

    try {
      final online = _connectivity.isConnected;

      // Verificar licencia/acceso (sin bloquear la carga de datos para UI).
      if (online) {
        await _subscriptionGuard.forceCheck();
      } else {
        await _subscriptionGuard.hasActiveSubscription(forceRefresh: false);
      }

      _licenseStatus = _subscriptionGuard.lastOfflineStatus;
      _currentSubscription = await _subscriptionGuard.getCurrentSubscription(
        forceRefresh: online,
      );

      // Sin suscripción en caché/servidor: intentar plan guardado en prefs.
      _currentSubscription ??= await _subscriptionFromStoredPlanName();

      print(
        '📋 Settings suscripción: '
        '${_currentSubscription?.planDenominacion ?? "sin plan"} — '
        'activa=${_currentSubscription?.isActive ?? false}, '
        'licencia=${_licenseStatus?.isValid ?? "n/a"}',
      );
    } catch (e) {
      print('❌ Error cargando datos de suscripción: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSubscription = false);
      }
    }
  }

  /// Fallback mínimo cuando solo hay nombre de plan en prefs (sin objeto completo).
  Future<Subscription?> _subscriptionFromStoredPlanName() async {
    final storeId = await _userPreferencesService.getIdTienda();
    if (storeId == null) return null;

    final stored = await _userPreferencesService.getSubscriptionData();
    if (stored == null) return null;

    final lastCheck = stored['last_check'] as DateTime? ?? DateTime.now();
    return Subscription(
      id: stored['subscription_id'] as int,
      idTienda: storeId,
      idPlan: stored['plan_id'] as int,
      fechaInicio: stored['start_date'] as DateTime,
      fechaFin: stored['end_date'] as DateTime?,
      estado: stored['state'] as int,
      creadoPor: 'local_cache',
      renovacionAutomatica: false,
      createdAt: lastCheck,
      updatedAt: lastCheck,
      planDenominacion: stored['plan_name'] as String?,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancelar suscripción de manera segura
    _integrationSubscription?.cancel();
    _integrationSubscription = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print('📱 App reanudada en Settings - Verificando estado de conexión...');

      // Verificar conexión cuando la app se reanuda
      _checkConnectionAfterResume();

      // Recargar configuraciones
      _loadSettings();
      unawaited(_refreshDataSection());
      unawaited(_refreshSmartStatus());
      unawaited(_loadSubscriptionData());
    } else if (state == AppLifecycleState.paused) {
      print('⏸️ App suspendida desde Settings');
    }
  }

  /// Verificar conexión después de que la app se reanuda
  Future<void> _checkConnectionAfterResume() async {
    try {
      // Esperar un poco para que el sistema restaure la conexión
      await Future.delayed(const Duration(seconds: 2));

      // Verificar si hay conexión real
      final connectivityService = ConnectivityService();
      final hasConnection = await connectivityService.checkConnectivity();

      // Verificar si el modo offline está activado
      final isOfflineMode =
          await _userPreferencesService.isOfflineModeEnabled();
      final stayFullyOffline =
          await _userPreferencesService.shouldStayFullyOffline();

      if (hasConnection && isOfflineMode && !stayFullyOffline) {
        print(
          '🔄 Conexión detectada después de reanudar - Modo offline puede ser innecesario',
        );

        // Mostrar notificación al usuario
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📶 Conexión disponible - Puede desactivar modo offline',
              ),
              backgroundColor: VentiqHomeTheme.primary,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Recargar configuraciones para reflejar el estado actual
        _loadSettings();
      } else if (hasConnection && stayFullyOffline) {
        print(
          '📦 Full offline: conexión detectada al reanudar — se ignora '
          '(solo el admin desactiva el modo offline)',
        );
      } else if (hasConnection) {
        print('✅ Conexión confirmada después de reanudar - Modo online activo');
      } else {
        print('📵 Sin conexión después de reanudar');
      }
    } catch (e) {
      print('❌ Error verificando conexión después de reanudar: $e');
    }
  }

  /// Navegar a detalles de suscripción
  void _navigateToSubscriptionDetail() {
    Navigator.pushNamed(context, '/subscription-detail').then((_) {
      if (mounted) unawaited(_loadSubscriptionData());
    });
  }

  /// Cargar versión de la app desde changelog.json
  Future<void> _loadAppVersion() async {
    try {
      final String changelogString = await rootBundle.loadString(
        'assets/changelog.json',
      );
      final Map<String, dynamic> changelog = json.decode(changelogString);
      final String version = changelog['current_version'] ?? '1.0.0';

      if (mounted) {
        setState(() {
          _appVersion = 'v$version';
        });
      }

      print('✅ Versión de la app cargada: $_appVersion');
    } catch (e) {
      print('❌ Error cargando versión desde changelog.json: $e');
      if (mounted) {
        setState(() {
          _appVersion = 'v1.0.0'; // Fallback
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final printEnabled = await _userPreferencesService.isPrintEnabled();
    final printUsdEnabled = await _userPreferencesService.isPrintUsdEnabled();
    final staticTextEnabled =
        await _userPreferencesService.isStaticTextEnabled();
    final showSkuEnabled = await _userPreferencesService.isShowSkuEnabled();
    final limitDataEnabled =
        await _userPreferencesService.isLimitDataUsageEnabled();
    final offlineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();

    // Modo restaurante - leer del cache (lo más rápido) sin bloquear el resto
    bool modoRestaurante = false;
    try {
      final cfg = await StoreConfigService.getStoreConfigFromCache();
      modoRestaurante = cfg?['modo_restaurante'] ?? false;
    } catch (e) {
      print('⚠️ No se pudo leer modo_restaurante del cache: $e');
    }

    // Impresora recordada para el turno actual
    String? savedPrinterDescription;
    bool hasSavedPrinter = false;
    try {
      final printerManager = PrinterManager();
      await printerManager.refreshSavedPrinter();
      hasSavedPrinter = printerManager.hasSavedPrinter;
      savedPrinterDescription = printerManager.savedPrinterDescription;
    } catch (e) {
      print('⚠️ No se pudo leer impresora guardada: $e');
    }

    // Verificar si el widget está montado antes de actualizar el estado
    if (mounted) {
      setState(() {
        _isPrintEnabled = printEnabled;
        _isPrintUsdEnabled = printUsdEnabled;
        _isStaticTextEnabled = staticTextEnabled;
        _isShowSkuEnabled = showSkuEnabled;
        _isLimitDataUsageEnabled = limitDataEnabled;
        // _isFluidModeEnabled permanece false - deshabilitado
        _isOfflineModeEnabled = offlineModeEnabled;
        _isModoRestauranteEnabled = modoRestaurante;
        _hasSavedPrinter = hasSavedPrinter;
        _savedPrinterDescription = savedPrinterDescription;
      });
    }
  }

  /// Turno actual + cola offline (fuente unificada con el resto de la app).
  Future<void> _refreshDataSection() async {
    if (!mounted) return;
    setState(() => _isLoadingDataSection = true);
    try {
      final turno = await TurnoService.getTurnoForDisplay();
      print(
        '[TURNO_SYNC] Settings._refreshDataSection display='
        'id=${turno?['id']} local=${turno?['local_id']} '
        'status=${turno?['status']} cerrado_online=${turno?['cerrado_online']} '
        'server_id=${turno?['server_id_turno']} '
        'fa=${turno?['fecha_apertura']} fc=${turno?['fecha_cierre']}',
      );
      final summary = await _userPreferencesService.getOfflineSyncSummary();
      print(
        '[TURNO_SYNC] Settings summary pending_turnos='
        '${summary['pending_turnos_count']} '
        'closed_pending=${summary['closed_turnos_pending_count']} '
        'has_open=${summary['has_open_turno']}',
      );
      if (!mounted) return;
      setState(() {
        _currentTurno = turno;
        _dataSyncSummary = summary;
        _isLoadingDataSection = false;
      });
    } catch (e) {
      print('❌ Error refrescando sección Datos: $e');
      if (mounted) {
        setState(() => _isLoadingDataSection = false);
      }
    }
  }

  Future<void> _clearSavedPrinter() async {
    try {
      PrinterManager().clearSavedPrinter();
      setState(() {
        _hasSavedPrinter = false;
        _savedPrinterDescription = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Impresora guardada eliminada'),
            backgroundColor: VentiqHomeTheme.warning,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error eliminando impresora guardada: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar impresora guardada: $e'),
            backgroundColor: VentiqHomeTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _onModoRestauranteChanged(bool value) async {
    // Optimistic UI
    setState(() {
      _isModoRestauranteEnabled = value;
      _isLoadingModoRestaurante = true;
    });

    final storeId = await _userPreferencesService.getIdTienda();
    if (storeId == null) {
      if (mounted) {
        setState(() {
          _isModoRestauranteEnabled = !value;
          _isLoadingModoRestaurante = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se pudo identificar la tienda'),
            backgroundColor: VentiqHomeTheme.danger,
          ),
        );
      }
      return;
    }

    final ok = await StoreConfigService.setModoRestaurante(storeId, value);

    if (!mounted) return;
    setState(() => _isLoadingModoRestaurante = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? '🍽️ Modo Restaurante activado — La opción "Mesas y Comensales" ya está disponible'
                : '🏪 Modo Restaurante desactivado — Volviendo a venta de mostrador',
          ),
          backgroundColor:
              value ? VentiqHomeTheme.success : VentiqHomeTheme.textSecondary,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      setState(() => _isModoRestauranteEnabled = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error guardando la configuración'),
          backgroundColor: VentiqHomeTheme.danger,
        ),
      );
    }
  }

  /// Inicializar servicios inteligentes
  Future<void> _initializeSmartServices() async {
    try {
      print('🚀 Inicializando servicios inteligentes en Settings...');

      await _integrationService.initialize();

      // Configurar listener para eventos
      _integrationSubscription = _integrationService.eventStream.listen(
        _onSmartServiceEvent,
        onError: (error) {
          print('❌ Error en stream de integración: $error');
        },
      );

      setState(() {
        _isSmartServicesInitialized = true;
      });
      await _refreshSmartStatus();

      print('✅ Servicios inteligentes inicializados en Settings');
    } catch (e) {
      print('❌ Error inicializando servicios inteligentes: $e');

      // Mostrar error al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error inicializando servicios inteligentes: $e'),
            backgroundColor: VentiqHomeTheme.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _refreshSmartStatus() async {
    try {
      final status = await _integrationService.getStatus();
      if (!mounted) return;
      setState(() {
        _smartIntegrationStatus = status;
      });
    } catch (e) {
      print('❌ Error refrescando estado de sincronización: $e');
    }
  }

  /// Manejar eventos de servicios inteligentes
  void _onSmartServiceEvent(SettingsIntegrationEvent event) {
    // Verificar si el widget y la suscripción siguen activos
    if (!mounted || _integrationSubscription == null) {
      print('⚠️ Widget no montado o suscripción cancelada, ignorando evento');
      return;
    }

    print('📡 Evento de integración: ${event.type} - ${event.message}');

    if (mounted) {
      setState(() {
        _lastSmartEvent = event.message;
      });
    }

    // Siempre refrescar el tile de estado general (switch manual, auto, sync).
    unawaited(_refreshSmartStatus());

    // Mostrar notificaciones importantes al usuario
    if (mounted) {
      switch (event.type) {
        case SettingsIntegrationEventType.offlineModeAutoActivated:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '🔌 Modo offline activado automáticamente por pérdida de conexión',
              ),
              backgroundColor: VentiqHomeTheme.warning,
              duration: Duration(seconds: 5),
            ),
          );
          // Recargar configuraciones para reflejar el cambio
          if (mounted) {
            _loadSettings();
            unawaited(_refreshDataSection());
          }
          break;

        case SettingsIntegrationEventType.offlineModeAutoDeactivated:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📶 Modo offline desactivado automáticamente - Conexión restaurada',
              ),
              backgroundColor: VentiqHomeTheme.success,
              duration: Duration(seconds: 4),
            ),
          );
          // Recargar configuraciones para reflejar el cambio
          if (mounted) {
            _loadSettings();
            unawaited(_refreshDataSection());
          }
          break;

        case SettingsIntegrationEventType.connectionRestored:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📶 Conexión restaurada — sincronizando pendientes',
              ),
              backgroundColor: VentiqHomeTheme.success,
              duration: Duration(seconds: 3),
            ),
          );
          unawaited(_refreshDataSection());
          break;

        case SettingsIntegrationEventType.autoSyncStarted:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔄 Sincronización automática iniciada'),
              backgroundColor: VentiqHomeTheme.primary,
              duration: Duration(seconds: 2),
            ),
          );
          unawaited(_refreshDataSection());
          break;

        case SettingsIntegrationEventType.reauthenticationStarted:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔐 Reautenticando usuario...'),
              backgroundColor: VentiqHomeTheme.warning,
              duration: Duration(seconds: 2),
            ),
          );
          break;

        case SettingsIntegrationEventType.reauthenticationSuccess:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Usuario reautenticado correctamente'),
              backgroundColor: VentiqHomeTheme.success,
              duration: Duration(seconds: 3),
            ),
          );
          break;

        case SettingsIntegrationEventType.reauthenticationFailed:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '⚠️ Error en reautenticación - Puede requerir login manual',
              ),
              backgroundColor: VentiqHomeTheme.warning,
              duration: Duration(seconds: 5),
            ),
          );
          break;

        case SettingsIntegrationEventType.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${event.message}'),
              backgroundColor: VentiqHomeTheme.danger,
              duration: const Duration(seconds: 4),
            ),
          );
          break;

        case SettingsIntegrationEventType.offlineModeManuallyEnabled:
        case SettingsIntegrationEventType.offlineModeManuallyDisabled:
        case SettingsIntegrationEventType.autoSyncEvent:
        case SettingsIntegrationEventType.syncForced:
          if (mounted) {
            _loadSettings();
            unawaited(_refreshDataSection());
          }
          break;

        default:
          // No mostrar notificación para otros eventos
          break;
      }
    }
  }

  Future<void> _onPrintSettingChanged(bool value) async {
    setState(() {
      _isPrintEnabled = value;
    });

    await _userPreferencesService.setPrintEnabled(value);

    // Mostrar confirmación al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '✅ Impresión habilitada - Las órdenes se imprimirán automáticamente'
              : '❌ Impresión deshabilitada - Las órdenes no se imprimirán',
        ),
        backgroundColor:
            value ? VentiqHomeTheme.success : VentiqHomeTheme.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onPrintUsdSettingChanged(bool value) async {
    setState(() {
      _isPrintUsdEnabled = value;
    });

    await _userPreferencesService.setPrintUsdEnabled(value);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '💵 USD habilitado en impresiones'
              : '💵 USD deshabilitado en impresiones',
        ),
        backgroundColor:
            value ? VentiqHomeTheme.success : VentiqHomeTheme.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onShowSkuSettingChanged(bool value) async {
    setState(() {
      _isShowSkuEnabled = value;
    });

    await _userPreferencesService.setShowSkuEnabled(value);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value ? 'SKU de producto visible' : 'SKU de producto oculto',
        ),
        backgroundColor:
            value ? VentiqHomeTheme.success : VentiqHomeTheme.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onStaticTextSettingChanged(bool value) async {
    setState(() {
      _isStaticTextEnabled = value;
    });

    await _userPreferencesService.setStaticTextEnabled(value);

    // Mostrar confirmación al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '📝 Textos estáticos activados - Los nombres no se moverán'
              : '🔄 Textos dinámicos activados - Los nombres se moverán si son largos',
        ),
        backgroundColor:
            value ? VentiqHomeTheme.primary : VentiqHomeTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _onLimitDataUsageChanged(bool value) async {
    setState(() {
      _isLimitDataUsageEnabled = value;
    });

    await _userPreferencesService.setLimitDataUsage(value);

    // Mostrar confirmación al usuario
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? '📱 Modo ahorro de datos activado - Las imágenes no se cargarán'
              : '📶 Modo ahorro de datos desactivado - Las imágenes se cargarán normalmente',
        ),
        backgroundColor:
            value ? VentiqHomeTheme.primary : VentiqHomeTheme.success,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<SettingsIntegrationStatus?> _getIntegrationStatusSafe() async {
    if (!_isSmartServicesInitialized) {
      return null;
    }

    try {
      return await _integrationService.getStatus();
    } catch (e) {
      print('❌ Error obteniendo estado de sincronización: $e');
      return null;
    }
  }

  Future<bool> _isAutoSyncBusy({required bool blockWhenRunning}) async {
    final status = await _getIntegrationStatusSafe();
    if (status == null) return false;

    final syncStats = status.smartOfflineStatus.syncStats;
    final isSyncing = syncStats['isSyncing'] == true;
    final isRunning = status.smartOfflineStatus.isAutoSyncRunning;

    return isSyncing || (blockWhenRunning && isRunning);
  }

  void _showAutoSyncBlockedMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: VentiqHomeTheme.warning,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _activateOfflineMode() async {
    try {
      final synced = await _forceSyncNow(
        blockWhenRunning: false,
        offlineReadinessOnly: true,
      );
      if (!synced) {
        if (mounted) {
          setState(() => _isOfflineModeEnabled = false);
        }
        _showAutoSyncBlockedMessage(
          'No se activó el modo offline: faltan módulos obligatorios. Revisa el detalle de sincronización.',
        );
        return;
      }

      await _userPreferencesService.setOfflineMode(true);

      // Notificar siempre al SmartOfflineManager (no solo cuando los
      // servicios inteligentes de esta pantalla están inicializados), para
      // que cualquier widget que escuche su eventStream (p.ej. el ícono de
      // conexión en otras pantallas) se actualice de inmediato.
      if (_isSmartServicesInitialized) {
        await _integrationService.handleOfflineModeChanged(true);
      } else {
        await SmartOfflineManager().onOfflineModeManuallyEnabled();
      }

      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = true;
        });
      }
      await _refreshSmartStatus();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔌 Modo offline activado - Datos listos sin conexión'),
          backgroundColor: VentiqHomeTheme.success,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Error activando modo offline: $e');
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = false;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error activando modo offline: $e'),
          backgroundColor: VentiqHomeTheme.danger,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<bool> _deactivateOfflineMode() async {
    try {
      final fullOfflineReady =
          await _userPreferencesService.isDeviceFullOfflineReady();
      if (fullOfflineReady) {
        final isAdmin = await _userPreferencesService.isInventoryOnlySession();
        if (!isAdmin) {
          if (mounted) {
            setState(() => _isOfflineModeEnabled = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Solo el administrador puede desactivar el modo offline '
                  'en este dispositivo',
                ),
                backgroundColor: VentiqHomeTheme.warning,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return false;
        }
      }

      // Verificar que realmente se puede volver online ANTES de mover el
      // switch o apagar el flag. Si no hay servidor, el modo debe seguir ON.
      final onlineError = await _ensureCanLeaveOfflineMode();
      if (onlineError != null) {
        if (mounted) {
          setState(() => _isOfflineModeEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(onlineError),
              backgroundColor: VentiqHomeTheme.warning,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return false;
      }

      if (fullOfflineReady) {
        // El dispositivo quedó preparado para full-offline: si solo se
        // apaga `offline_mode` sin quitar esa preparación, el splash
        // screen la vuelve a forzar a ON en el próximo inicio (ver
        // splash_screen.dart), dejando al admin sin forma real de volver
        // a modo online. Se confirma porque esta acción también elimina
        // la preparación full-offline (habrá que volver a prepararla si
        // se quiere reactivar).
        if (!mounted) return false;
        final confirmed = await showDialog<bool>(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Volver a modo online'),
                content: const Text(
                  'Este dispositivo está preparado para trabajar 100% offline. '
                  'Al continuar se desactivará el modo offline y se eliminará '
                  'la preparación full-offline del dispositivo (deberás volver '
                  'a prepararlo si quieres reactivarla). ¿Deseas continuar?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sí, volver a online'),
                  ),
                ],
              ),
        );
        if (confirmed != true) {
          if (mounted) {
            setState(() => _isOfflineModeEnabled = true);
          }
          return false;
        }
      }

      await _userPreferencesService.setOfflineMode(false);

      if (fullOfflineReady) {
        // Elimina la preparación full-offline para que el dispositivo deje
        // de forzar el modo offline al reabrir la app.
        await _userPreferencesService.clearDeviceFullOffline();
      }

      // Notificar siempre al SmartOfflineManager (ver comentario análogo en
      // _activateOfflineMode) para que el ícono de conexión y demás
      // widgets que dependen de su eventStream no queden desactualizados
      // mostrando "Offline" tras desactivarlo manualmente desde Ajustes.
      if (_isSmartServicesInitialized) {
        await _integrationService.handleOfflineModeChanged(false);
      } else {
        await SmartOfflineManager().onOfflineModeManuallyDisabled();
      }

      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = false;
        });
      }
      await _refreshSmartStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fullOfflineReady
                  ? '🌐 Modo offline desactivado por el admin — preparación full-offline eliminada, sync con el servidor habilitado'
                  : '🌐 Modo offline desactivado - Sincronización automática iniciada',
            ),
            backgroundColor: VentiqHomeTheme.primary,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return true;
    } catch (e) {
      print('❌ Error desactivando modo offline: $e');
      await _userPreferencesService.setOfflineMode(true);
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error desactivando modo offline: $e'),
            backgroundColor: VentiqHomeTheme.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return false;
    }
  }

  /// Comprueba red real + sesión usable antes de salir de offline.
  /// Devuelve un mensaje de error, o null si se puede desactivar.
  Future<String?> _ensureCanLeaveOfflineMode() async {
    print('🔐 Verificando si se puede salir del modo offline...');
    final connectivity = ConnectivityService();
    final hasInternet = await connectivity.performImmediateCheck();
    if (!hasInternet) {
      return 'No hay conexión a internet. No se puede salir del modo offline.';
    }

    final session = Supabase.instance.client.auth.currentSession;
    final sessionOk =
        session != null &&
        !session.isExpired &&
        session.accessToken.isNotEmpty &&
        session.accessToken != 'offline_mode';

    if (sessionOk) return null;

    try {
      final saved = await _userPreferencesService.getSavedCredentials();
      var email =
          saved['email'] ?? await _userPreferencesService.getUserEmail();
      var password = saved['password'];

      if ((password == null || password.isEmpty) &&
          email != null &&
          email.isNotEmpty) {
        final offlineUsers = await _userPreferencesService.getOfflineUsers();
        for (final user in offlineUsers) {
          if (user['email']?.toString().toLowerCase() == email.toLowerCase()) {
            password = user['password']?.toString();
            break;
          }
        }
      }

      if (email == null ||
          password == null ||
          email.isEmpty ||
          password.isEmpty) {
        final admin =
            await _userPreferencesService
                .getDeviceFullOfflineAdminCredentials();
        email = admin['email'] ?? email;
        password = admin['password'] ?? password;
      }

      if (email == null ||
          password == null ||
          email.isEmpty ||
          password.isEmpty) {
        return 'Hay internet, pero no hay credenciales para iniciar sesión '
            'online. El modo offline se mantiene activo.';
      }

      print('🔑 Reautenticando para salir de offline ($email)...');
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session == null) {
        return 'No se pudo iniciar sesión en el servidor. '
            'El modo offline se mantiene activo.';
      }
      return null;
    } catch (e) {
      print('❌ Reautenticación al salir de offline falló: $e');
      return 'No se pudo conectar con el servidor. '
          'El modo offline se mantiene activo.';
    }
  }

  Future<void> _onOfflineModeChanged(bool value) async {
    // Evitar reentradas si ya hay un cambio de modo en curso.
    if (_isTogglingOfflineMode) return;

    // Deshabilitar el switch mientras se procesa el cambio.
    if (mounted) {
      setState(() {
        _isTogglingOfflineMode = true;
      });
    }

    try {
      // Si hay un pase de sincronización (automático o forzado) en curso,
      // ESPERAR a que drene antes de cambiar de modo, en vez de bloquear y
      // revertir. Así no quedan trabajos a medias que generen inconsistencias.
      final isBusy = await _isAutoSyncBusy(blockWhenRunning: false);
      if (isBusy) {
        _showAutoSyncBlockedMessage(
          '⏳ Esperando a que termine la sincronización para cambiar el modo...',
        );
        await _integrationService.waitForSyncIdle();
      }

      if (value) {
        await _activateOfflineMode();
      } else {
        final deactivated = await _deactivateOfflineMode();
        if (!deactivated && mounted) {
          setState(() => _isOfflineModeEnabled = true);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingOfflineMode = false;
        });
      }
    }
  }

  /// Construir sección de suscripción
  Widget _buildSubscriptionSection() {
    return Column(
      children: [
        _buildSectionHeader('Suscripción'),
        _buildSettingsCard([_buildSubscriptionTile()]),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Construir tile de suscripción
  Widget _buildSubscriptionTile() {
    if (_isLoadingSubscription) {
      return ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusTile),
          ),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VentiqHomeTheme.primary,
              ),
            ),
          ),
        ),
        title: const Text('Suscripción', style: _tileTitleStyle),
        subtitle: const Text(
          'Verificando estado...',
          style: _tileSubtitleStyle,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      );
    }

    final subscription = _currentSubscription;
    final license = _licenseStatus;
    final licenseValid = license?.isValid == true;
    final subscriptionActive = subscription?.isActive == true;
    final isActive = subscriptionActive || licenseValid;

    String subtitle;
    if (subscription != null) {
      subtitle =
          '${subscription.planDenominacion ?? 'Plan desconocido'} · '
          '${subscription.estadoText}';
      if (subscription.fechaFin != null) {
        subtitle +=
            ' · Vence ${_formatSubscriptionDate(subscription.fechaFin!)}';
      }
      if (license != null && !license.isValid) {
        subtitle += '\n${license.message}';
      } else if (licenseValid && !subscriptionActive) {
        subtitle += '\nLicencia offline válida';
      }
    } else if (license != null) {
      subtitle = license.isValid ? 'Licencia offline válida' : license.message;
    } else {
      subtitle = 'No se encontró información de suscripción';
    }

    return _buildSettingsTile(
      icon: isActive ? Icons.verified : Icons.warning,
      iconColor:
          isActive ? VentiqHomeTheme.success : VentiqHomeTheme.warning,
      title: isActive ? 'Suscripción Activa' : 'Suscripción Inactiva',
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subscription != null &&
              subscription.diasRestantes > 0 &&
              subscription.diasRestantes <= 30)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: VentiqHomeTheme.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusChip),
                border: Border.all(
                  color: VentiqHomeTheme.warning.withValues(alpha: 0.30),
                ),
              ),
              child: Text(
                '${subscription.diasRestantes}d',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.warning,
                ),
              ),
            ),
          if (license?.daysUntilForcedReconnect != null &&
              license!.daysUntilForcedReconnect! <= 3)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusChip),
                border: Border.all(
                  color: VentiqHomeTheme.primary.withValues(alpha: 0.30),
                ),
              ),
              child: Text(
                'Revalidar ${license.daysUntilForcedReconnect}d',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.primary,
                ),
              ),
            ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            color: VentiqHomeTheme.textSecondary,
            size: 20,
          ),
        ],
      ),
      onTap: () => _navigateToSubscriptionDetail(),
    );
  }

  String _formatSubscriptionDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          // Indicador de estado de conexión
          if (_isSmartServicesInitialized)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isOfflineModeEnabled
                              ? '🔌 Modo offline activado - Trabajando con datos sincronizados'
                              : '🌐 Modo online - Conectado al servidor',
                        ),
                        backgroundColor:
                            _isOfflineModeEnabled
                                ? VentiqHomeTheme.textSecondary
                                : VentiqHomeTheme.success,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _isOfflineModeEnabled
                              ? Colors.white.withValues(alpha: 0.18)
                              : Colors.white,
                      borderRadius: BorderRadius.circular(
                        VentiqHomeTheme.radiusChip,
                      ),
                      border: Border.all(
                        color:
                            _isOfflineModeEnabled
                                ? Colors.white.withValues(alpha: 0.35)
                                : Colors.transparent,
                        width: 0.8,
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isOfflineModeEnabled
                                ? Icons.cloud_off
                                : Icons.cloud_done,
                            size: 13,
                            color:
                                _isOfflineModeEnabled
                                    ? Colors.white
                                    : VentiqHomeTheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isOfflineModeEnabled ? 'Offline' : 'Online',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color:
                                  _isOfflineModeEnabled
                                      ? Colors.white
                                      : VentiqHomeTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            children: [
              // Sección de cuenta
              // _buildSectionHeader('Cuenta'),
              /* _buildSettingsCard([
                _buildSettingsTile(
                  icon: Icons.person_outline,
                  title: 'Perfil de Usuario',
                  subtitle: 'Editar información personal',
                  onTap: () => _showComingSoon('Perfil de Usuario'),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.lock_outline,
                  title: 'Cambiar Contraseña',
                  subtitle: 'Actualizar credenciales de acceso',
                  onTap: () => _showComingSoon('Cambiar Contraseña'),
                ),
              ]), */
              const SizedBox(height: 16),

              // Sección de suscripción
              _buildSubscriptionSection(),

              // Sección de aplicación
              _buildSectionHeader('Aplicación'),
              _buildSettingsCard([
                _buildSettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notificaciones',
                  subtitle: 'Configurar alertas y avisos',
                  onTap: () => _showComingSoon('Notificaciones'),
                ),
                _buildDivider(),
                _buildPrintSettingsTile(),
                _buildDivider(),
                _buildPrintUsdSettingsTile(),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.wifi,
                  title: 'Impresoras WiFi',
                  subtitle: 'Gestionar impresoras de red',
                  onTap: () => Navigator.pushNamed(context, '/wifi-printers'),
                ),
                _buildDivider(),
                _buildSavedPrinterTile(),
                _buildDivider(),
                _buildStaticTextSettingsTile(),
                _buildDivider(),
                _buildShowSkuSettingsTile(),
                _buildDivider(),
                _buildFluidModeSettingsTile(),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.system_update_outlined,
                  title: 'Buscar Actualizaciones',
                  subtitle: 'Verificar si hay nuevas versiones',
                  onTap: () => _checkForUpdates(),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.language_outlined,
                  title: 'Idioma',
                  subtitle: 'Español',
                  onTap: () => _showComingSoon('Idioma'),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Tema',
                  subtitle: 'Claro',
                  onTap: () => _showComingSoon('Tema'),
                ),
              ]),

              const SizedBox(height: 16),

              // Sección Ventas
              _buildSectionHeader('Ventas'),
              _buildSettingsCard([
                _buildSettingsTile(
                  icon: Icons.playlist_add_check_outlined,
                  title: 'Productos por Defecto',
                  subtitle:
                      'Configura productos que se agregan automáticamente al crear una orden',
                  onTap:
                      () =>
                          Navigator.pushNamed(context, '/default-order-items'),
                ),
              ]),

              const SizedBox(height: 16),

              // Sección Modo de Operación (modo restaurante)
              _buildSectionHeader('Modo de Operación'),
              _buildSettingsCard([_buildModoRestauranteTile()]),

              const SizedBox(height: 16),

              // Sección de uso de datos
              _buildSectionHeader('Uso de datos'),
              _buildSettingsCard([
                _buildDataUsageSettingsTile(),
                _buildDivider(),
                _buildOfflineModeSettingsTile(),
                if (_isSmartServicesInitialized) ...[
                  _buildDivider(),
                  _buildSmartSyncStatusTile(),
                ],
              ]),

              const SizedBox(height: 16),

              // Sección de datos (turno actual + sincronización)
              _buildSectionHeader('Datos'),
              _buildSettingsCard([
                //_buildCurrentTurnoTile(),
                /* if (_hasPendingOfflineData) ...[
                  _buildDivider(),
                  _buildPendingDataSummaryTile(),
                ], */
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.sync_outlined,
                  title: 'Sincronización Manual',
                  subtitle: 'Sincronizar datos offline pendientes',
                  onTap: () => _showSyncDialog(),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.checklist_outlined,
                  title: 'Sincronizar por módulos',
                  subtitle: 'Elegir qué subir y qué bajar',
                  onTap: () => SelectiveSyncDialog.show(context),
                ),
                _buildDivider(),
                if (_isSmartServicesInitialized)
                  _buildSettingsTile(
                    icon: Icons.sync_alt,
                    title: 'Forzar Sincronización',
                    subtitle: 'Sincronizar datos inmediatamente',
                    onTap: () => _forceSyncNow(blockWhenRunning: false),
                  ),
                if (_isSmartServicesInitialized) _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.storage_outlined,
                  title: 'Almacenamiento',
                  subtitle: 'Gestionar datos locales',
                  onTap: () => _showStorageOptions(),
                ),
              ]),

              const SizedBox(height: 16),

              // Sección de ayuda
              _buildSectionHeader('Ayuda y Soporte'),
              _buildSettingsCard([
                _buildSettingsTile(
                  icon: Icons.help_outline,
                  title: 'Centro de Ayuda',
                  subtitle: 'Preguntas frecuentes y tutoriales',
                  onTap: () => _showComingSoon('Centro de Ayuda'),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Política de Privacidad',
                  subtitle: 'Términos y condiciones',
                  onTap: () => _showComingSoon('Política de Privacidad'),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.download_outlined,
                  title: 'Compartir Aplicación',
                  subtitle: 'Código QR para descargar la app',
                  onTap: () => _showDownloadDialog(),
                ),
                _buildDivider(),
                _buildSettingsTile(
                  icon: Icons.info_outline,
                  title: 'Acerca de',
                  subtitle: 'Inventtia Caja $_appVersion',
                  onTap: () => _showAboutDialog(),
                ),
              ]),

              const SizedBox(height: 24),

              // Botón de cerrar sesión
              _buildLogoutButton(),

              const SizedBox(height: 80), // Espacio para el bottom navigation
            ],
          ),
          if (_isSmartServicesInitialized)
            const Positioned(bottom: 80, left: 16, child: SyncStatusChip()),
        ],
      ),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 3, // Configuración tab
        onTap: _onBottomNavTap,
      ),
    );
  }

  // ── Estilos del rediseño ───────────────────────────────────────────────
  // Misma familia que el Home nuevo: superficie clara, tarjetas blancas con
  // borde suave, iconos en contenedor primary al 10 % y textos de token.

  static const TextStyle _tileTitleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: VentiqHomeTheme.textPrimary,
  );

  static const TextStyle _tileSubtitleStyle = TextStyle(
    fontSize: 13,
    height: 1.25,
    color: VentiqHomeTheme.textSecondary,
  );

  /// Contenedor redondeado del icono de una fila (primary al 10 % por defecto).
  Widget _settingsIcon(IconData icon, {Color color = VentiqHomeTheme.primary}) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusTile),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, top: 2),
      child: Text(title.toUpperCase(), style: VentiqHomeTheme.rotuloBloque),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VentiqHomeTheme.border, width: 1),
        boxShadow: VentiqHomeTheme.shadowCard,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    return ListTile(
      leading: _settingsIcon(icon, color: iconColor ?? VentiqHomeTheme.primary),
      title: Text(title, style: _tileTitleStyle),
      subtitle: Text(subtitle, style: _tileSubtitleStyle),
      trailing:
          trailing ??
          const Icon(
            Icons.chevron_right,
            color: VentiqHomeTheme.textSecondary,
            size: 20,
          ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildPrintUsdSettingsTile() {
    return ListTile(
      leading: _settingsIcon(Icons.attach_money),
      title: const Text(
        'Mostrar USD en impresiones',
        style: _tileTitleStyle,
      ),
      subtitle: Text(
        _isPrintUsdEnabled
            ? 'Se mostrará CUP + USD en tickets y vales'
            : 'Solo se mostrará CUP en tickets y vales',
        style: _tileSubtitleStyle,
      ),
      trailing: Switch(
        value: _isPrintUsdEnabled,
        onChanged: _onPrintUsdSettingChanged,
        activeColor: VentiqHomeTheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildDivider() {
    return const Divider(
      height: 1,
      thickness: 1,
      color: VentiqHomeTheme.border,
      indent: 70,
      endIndent: 16,
    );
  }

  Widget _buildPrintSettingsTile() {
    return ListTile(
      leading: _settingsIcon(Icons.print_outlined),
      title: const Text('Habilitar Impresión', style: _tileTitleStyle),
      subtitle: Text(
        _isPrintEnabled
            ? 'Las órdenes se imprimirán automáticamente'
            : 'Impresión deshabilitada',
        style: _tileSubtitleStyle,
      ),
      trailing: Switch(
        value: _isPrintEnabled,
        onChanged: _onPrintSettingChanged,
        activeColor: VentiqHomeTheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildShowSkuSettingsTile() {
    return ListTile(
      leading: _settingsIcon(Icons.tag_outlined),
      title: const Text('Mostrar SKU de Producto', style: _tileTitleStyle),
      subtitle: Text(
        _isShowSkuEnabled
            ? 'El código SKU será visible en los productos'
            : 'El código SKU no se mostrará en los productos',
        style: _tileSubtitleStyle,
      ),
      trailing: Switch(
        value: _isShowSkuEnabled,
        onChanged: _onShowSkuSettingChanged,
        activeColor: VentiqHomeTheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildSavedPrinterTile() {
    Future<void> confirmAndClear() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Olvidar impresora'),
              content: const Text(
                'La próxima impresión volverá a pedirte que selecciones una impresora.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    foregroundColor: VentiqHomeTheme.danger,
                  ),
                  child: const Text('Olvidar'),
                ),
              ],
            ),
      );
      if (confirmed == true) await _clearSavedPrinter();
    }

    return ListTile(
      leading: _settingsIcon(
        _hasSavedPrinter ? Icons.print : Icons.print_disabled,
        color:
            _hasSavedPrinter
                ? VentiqHomeTheme.success
                : VentiqHomeTheme.textSecondary,
      ),
      title: const Text('Impresora del Turno', style: _tileTitleStyle),
      subtitle: Text(
        _hasSavedPrinter && _savedPrinterDescription != null
            ? '$_savedPrinterDescription (pulsa para olvidar)'
            : 'No hay impresora recordada para este turno',
        style: _tileSubtitleStyle.copyWith(
          color:
              _hasSavedPrinter
                  ? VentiqHomeTheme.success
                  : VentiqHomeTheme.textSecondary,
        ),
      ),
      trailing:
          _hasSavedPrinter
              ? IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: VentiqHomeTheme.danger,
                ),
                tooltip: 'Eliminar impresora guardada',
                onPressed: confirmAndClear,
              )
              : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: _hasSavedPrinter ? confirmAndClear : null,
    );
  }

  Widget _buildStaticTextSettingsTile() {
    return ListTile(
      leading: _settingsIcon(Icons.text_fields_outlined),
      title: const Text('Mostrar Textos Estáticos', style: _tileTitleStyle),
      subtitle: Text(
        _isStaticTextEnabled
            ? 'Los nombres de productos no se moverán'
            : 'Los nombres largos se moverán de izquierda a derecha',
        style: _tileSubtitleStyle,
      ),
      trailing: Switch(
        value: _isStaticTextEnabled,
        onChanged: _onStaticTextSettingChanged,
        activeColor: VentiqHomeTheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildFluidModeSettingsTile() {
    return ListTile(
      leading: _settingsIcon(
        Icons.speed_outlined,
        color: VentiqHomeTheme.textSecondary,
      ),
      title: const Text(
        'Modo Fluido',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: VentiqHomeTheme.textSecondary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Navegación tradicional por pantallas separadas',
            style: _tileSubtitleStyle,
          ),
          const SizedBox(height: 4),
          const Text(
            'Estará disponible en una próxima versión',
            style: TextStyle(
              fontSize: 12,
              color: VentiqHomeTheme.warning,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      trailing: Switch(
        value: false,
        onChanged: null, // Deshabilitado
        activeColor: VentiqHomeTheme.textSecondary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildDataUsageSettingsTile() {
    return ListTile(
      leading: _settingsIcon(Icons.data_saver_on),
      title: const Text('Limitar uso de datos', style: _tileTitleStyle),
      subtitle: Text(
        _isLimitDataUsageEnabled
            ? 'Modo ahorro activado - No se cargarán imágenes'
            : 'Carga completa de imágenes',
        style: _tileSubtitleStyle,
      ),
      trailing: Switch(
        value: _isLimitDataUsageEnabled,
        onChanged: _onLimitDataUsageChanged,
        activeColor: VentiqHomeTheme.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildModoRestauranteTile() {
    return ListTile(
      leading: _settingsIcon(Icons.restaurant_menu),
      title: const Text('Modo Restaurante', style: _tileTitleStyle),
      subtitle: Text(
        _isModoRestauranteEnabled
            ? 'Mesas y comensales activos — el checkout pide mesa en lugar de cliente'
            : 'Activar para gestionar mesas y cuentas por comensal',
        style: _tileSubtitleStyle,
      ),
      trailing:
          _isLoadingModoRestaurante
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Switch(
                value: _isModoRestauranteEnabled,
                onChanged: _onModoRestauranteChanged,
                activeColor: VentiqHomeTheme.primary,
              ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildOfflineModeSettingsTile() {
    final Color accent =
        _isOfflineModeEnabled
            ? VentiqHomeTheme.warning
            : VentiqHomeTheme.primary;

    return ListTile(
      leading: _settingsIcon(Icons.cloud_off, color: accent),
      title: const Text('Modo Offline', style: _tileTitleStyle),
      subtitle: Text(
        _isTogglingOfflineMode
            ? 'Procesando cambio de modo...'
            : (_isOfflineModeEnabled
                ? 'Activo: sin sync ni servidor hasta desactivar'
                : 'Sincronizar datos para trabajar offline'),
        style: _tileSubtitleStyle,
      ),
      trailing:
          _isTogglingOfflineMode
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : Switch(
                value: _isOfflineModeEnabled,
                // Deshabilitar mientras se procesa el cambio para evitar
                // toggles rápidos que dejen trabajos de sync a medias.
                onChanged:
                    _isTogglingOfflineMode ? null : _onOfflineModeChanged,
                activeColor: VentiqHomeTheme.primary,
              ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  Widget _buildCurrentTurnoTile() {
    if (_isLoadingDataSection && _currentTurno == null) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        title: const Text(
          'Turno actual',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: VentiqHomeTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          'Consultando turno...',
          style: TextStyle(fontSize: 13, color: VentiqHomeTheme.textSecondary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );
    }

    final turno = _currentTurno;
    if (turno == null) {
      return ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.access_time,
            color: VentiqHomeTheme.textSecondary,
            size: 20,
          ),
        ),
        title: const Text(
          'Turno actual',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: VentiqHomeTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          'No hay turno abierto',
          style: TextStyle(fontSize: 13, color: VentiqHomeTheme.textSecondary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      );
    }

    final fechaApertura = turno['fecha_apertura']?.toString();
    final fechaCierre = turno['fecha_cierre']?.toString();
    final syncedAt = turno['synced_at']?.toString();
    final efectivoInicial = _readTurnoEfectivoInicial(turno);
    final turnoId = _formatTurnoId(turno);
    final detectedSource = _turnoSourceLabel(turno);
    final usuario = turno['usuario']?.toString();
    final status = turno['status']?.toString();
    final localId = turno['local_id']?.toString();
    final serverId = turno['server_id_turno'] ?? turno['id'];
    final hasServerTurno =
        serverId is num || int.tryParse(serverId?.toString() ?? '') != null;
    final pendingTurnoIds =
        (_dataSyncSummary?['pending_turno_ids'] as List<dynamic>? ?? [])
            .map((id) => id.toString())
            .toSet();
    final isOnlineSynced =
        status != UserPreferencesService.offlineTurnoStatusClosedPending &&
        hasServerTurno &&
        (localId == null || !pendingTurnoIds.contains(localId));
    final source = isOnlineSynced ? 'SINCRONIZADO' : detectedSource;
    final sourceColor = _turnoSourceColor(source);
    final titlePrefix =
        turno['cerrado_online'] == true ||
                status == UserPreferencesService.offlineTurnoStatusSynced ||
                isOnlineSynced
            ? 'Turno sincronizado'
            : status == UserPreferencesService.offlineTurnoStatusClosedPending
            ? 'Turno cerrado'
            : 'Turno actual';

    return ListTile(
      onTap:
          status == UserPreferencesService.offlineTurnoStatusClosedPending
              ? () {
                Navigator.pushNamed(
                  context,
                  '/cierre-pendiente',
                  arguments:
                      (localId != null && localId.isNotEmpty) ? localId : null,
                );
              }
              : null,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: sourceColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.access_time, color: sourceColor, size: 20),
      ),
      title: Text(
        '$titlePrefix · $turnoId',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: VentiqHomeTheme.textPrimary,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOnlineSynced)
            const Text(
              'Sin órdenes pendientes de sincronización',
              style: TextStyle(
                fontSize: 12,
                color: VentiqHomeTheme.success,
              ),
            ),
          if (fechaApertura != null)
            Text(
              'Apertura: ${_formatTurnoDate(fechaApertura)}',
              style: TextStyle(fontSize: 12, color: VentiqHomeTheme.textSecondary),
            ),
          if (fechaCierre != null)
            Text(
              'Cierre: ${_formatTurnoDate(fechaCierre)}',
              style: TextStyle(fontSize: 12, color: VentiqHomeTheme.textSecondary),
            ),
          if (syncedAt != null)
            Text(
              'Sincronizado: ${_formatTurnoDate(syncedAt)}',
              style: TextStyle(fontSize: 12, color: VentiqHomeTheme.textSecondary),
            ),
          if (efectivoInicial != null)
            Text(
              'Efectivo inicial: \$${efectivoInicial.toMoneyString(2)}',
              style: TextStyle(fontSize: 12, color: VentiqHomeTheme.textSecondary),
            ),
          if (usuario != null && usuario.isNotEmpty)
            Text(
              'Usuario: $usuario',
              style: TextStyle(fontSize: 12, color: VentiqHomeTheme.textSecondary),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: sourceColor.withValues(alpha: 0.30),
                ),
            ),
            child: Text(
              source,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: sourceColor,
              ),
            ),
          ),
          if (status == UserPreferencesService.offlineTurnoStatusClosedPending)
            Icon(
              Icons.chevron_right,
              color: VentiqHomeTheme.textSecondary,
            ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildPendingDataSummaryTile() {
    final pendingOps =
        _dataSyncSummary?['pending_operations_count'] as int? ?? 0;
    final closedPending =
        _dataSyncSummary?['closed_turnos_pending_count'] as int? ?? 0;
    final ordersInTurnos =
        _dataSyncSummary?['pending_turno_orders_count'] as int? ?? 0;

    final parts = <String>[];
    if (_pendingOrdersCount > 0) {
      parts.add(
        '$_pendingOrdersCount venta${_pendingOrdersCount == 1 ? '' : 's'}',
      );
    }
    if (_pendingOfflineTurnosCount > 0) {
      parts.add(
        '$_pendingOfflineTurnosCount turno${_pendingOfflineTurnosCount == 1 ? '' : 's'}'
        '${ordersInTurnos > 0 ? ' ($ordersInTurnos venta${ordersInTurnos == 1 ? '' : 's'} incluida${ordersInTurnos == 1 ? '' : 's'})' : ''}',
      );
    }
    if (pendingOps > 0) {
      parts.add('$pendingOps operación${pendingOps == 1 ? '' : 'es'}');
    }

    final subtitle =
        parts.isEmpty
            ? 'Datos pendientes de sincronizar'
            : '${parts.join(' · ')} por sincronizar';

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.cloud_upload_outlined,
          color: VentiqHomeTheme.primary,
          size: 20,
        ),
      ),
      title: const Text(
        'Pendientes de sincronizar',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: VentiqHomeTheme.textPrimary,
        ),
      ),
      subtitle: Text(
        closedPending > 0
            ? '$subtitle ($closedPending turno${closedPending == 1 ? '' : 's'} cerrado${closedPending == 1 ? '' : 's'})'
            : subtitle,
        style: TextStyle(fontSize: 12, color: VentiqHomeTheme.textSecondary),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: VentiqHomeTheme.textSecondary,
      ),
      onTap:
          _pendingOfflineTurnosCount > 0
              ? _showPendingTurnosDialog
              : () => _showSyncDialog(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  double? _readTurnoEfectivoInicial(Map<String, dynamic> turno) {
    final direct = turno['efectivo_inicial'];
    if (direct is num) return direct.toDouble();
    final apertura = turno['apertura'];
    if (apertura is Map) {
      final nested = apertura['efectivo_inicial'];
      if (nested is num) return nested.toDouble();
    }
    return double.tryParse(direct?.toString() ?? '');
  }

  String _shortLocalTurnoId(String localId) {
    final separator = localId.indexOf('-');
    return separator > 0 ? localId.substring(0, separator) : localId;
  }

  String _formatTurnoId(Map<String, dynamic> turno) {
    final localId = turno['local_id']?.toString();
    if (localId != null && localId.isNotEmpty) {
      return _shortLocalTurnoId(localId);
    }
    final serverId = turno['server_id_turno'] ?? turno['id'];
    if (serverId is int) return '#$serverId';
    if (serverId != null && int.tryParse(serverId.toString()) != null) {
      return '#${serverId.toString()}';
    }
    return 'local';
  }

  String _turnoSourceLabel(Map<String, dynamic> turno) {
    if (turno['cerrado_online'] == true) return 'SINCRONIZADO';

    final status = turno['status']?.toString();
    if (status == UserPreferencesService.offlineTurnoStatusSynced) {
      return 'SINCRONIZADO';
    }
    if (status == UserPreferencesService.offlineTurnoStatusClosedPending) {
      return 'CIERRE PEND.';
    }

    final localId = turno['local_id']?.toString();
    final serverId =
        turno['server_id_turno'] ?? (turno['id'] is int ? turno['id'] : null);
    if (localId != null && serverId == null) return 'OFFLINE';
    if (localId != null) return 'SYNC';
    return 'ONLINE';
  }

  Color _turnoSourceColor(String source) {
    switch (source) {
      case 'SINCRONIZADO':
        return VentiqHomeTheme.success;
      case 'CIERRE PEND.':
        return VentiqHomeTheme.warning;
      case 'OFFLINE':
        return VentiqHomeTheme.warning;
      case 'SYNC':
        return VentiqHomeTheme.primary;
      default:
        return VentiqHomeTheme.success;
    }
  }

  String _formatTurnoDate(String raw) {
    try {
      final fecha = DateTime.parse(raw);
      return '${fecha.day.toString().padLeft(2, '0')}/'
          '${fecha.month.toString().padLeft(2, '0')}/'
          '${fecha.year} '
          '${fecha.hour.toString().padLeft(2, '0')}:'
          '${fecha.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: VentiqHomeTheme.danger.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: VentiqHomeTheme.shadowCard,
      ),
      child: ListTile(
        leading: _settingsIcon(Icons.logout, color: VentiqHomeTheme.danger),
        title: const Text(
          'Cerrar Sesión',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: VentiqHomeTheme.danger,
          ),
        ),
        subtitle: const Text(
          'Salir de la aplicación',
          style: _tileSubtitleStyle,
        ),
        onTap: _showLogoutDialog,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
    );
  }

  Future<void> _showSyncDialog() async {
    final status = await _getIntegrationStatusSafe();
    if (status != null) {
      final isBusy = await _isAutoSyncBusy(blockWhenRunning: false);
      if (isBusy) {
        _showAutoSyncBlockedMessage(
          '🔄 Sincronización automática en progreso. Espera para sincronizar manualmente.',
        );
        return;
      }

      final hasPendingAutoSync =
          status.smartOfflineStatus.isConnected &&
          status.isOfflineModeEnabled &&
          status.smartOfflineStatus.wasOfflineModeManuallyEnabled == false;
      if (hasPendingAutoSync) {
        _showAutoSyncBlockedMessage(
          '📶 Conexión restaurada. Desactiva el modo offline para completar la sincronización automática.',
        );
        return;
      }
    }

    // Verificar si hay datos offline para sincronizar
    final syncSummary = await _userPreferencesService.getOfflineSyncSummary();
    final pendientesTotales =
        await _userPreferencesService.getUnsyncedOfflineCounts();
    final hasPendingData =
        syncSummary['pending_orders_count'] > 0 ||
        syncSummary['pending_operations_count'] > 0 ||
        syncSummary['has_open_turno'] == true ||
        (syncSummary['pending_turnos_count'] as int? ?? 0) > 0 ||
        (pendientesTotales['total'] ?? 0) > 0;

    if (!hasPendingData) {
      await _startManualSync();
      return;
    }

    // Mostrar diálogo de confirmación con resumen
    final shouldSync = await _showSyncConfirmationDialog(syncSummary);
    if (shouldSync == true) {
      // Iniciar sincronización
      await _startManualSync();
    }
  }

  void _showComingSoon(String feature) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('$feature'),
            content: Text(
              'Esta funcionalidad estará disponible en una próxima actualización.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// Verificar actualizaciones disponibles
  Future<void> _checkForUpdates() async {
    // Mostrar diálogo de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Verificando actualizaciones...'),
              ],
            ),
          ),
    );

    try {
      final updateInfo = await UpdateService.checkForUpdates();

      // Cerrar diálogo de carga
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (updateInfo['hay_actualizacion'] == true) {
        // Hay actualización disponible
        _showUpdateAvailableDialog(updateInfo);
      } else {
        // No hay actualizaciones
        _showNoUpdateDialog(updateInfo);
      }
    } catch (e) {
      // Cerrar diálogo de carga
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Mostrar error
      _showUpdateErrorDialog(e.toString());
    }
  }

  /// Mostrar diálogo cuando hay actualización disponible
  void _showUpdateAvailableDialog(Map<String, dynamic> updateInfo) {
    final bool isObligatory = updateInfo['obligatoria'] ?? false;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion =
        updateInfo['current_version'] ?? 'Desconocida';

    showDialog(
      context: context,
      barrierDismissible: !isObligatory,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  isObligatory ? Icons.warning : Icons.system_update,
                  color:
                      isObligatory
                          ? VentiqHomeTheme.warning
                          : VentiqHomeTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isObligatory
                        ? 'Actualización Obligatoria'
                        : 'Actualización Disponible',
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nueva versión disponible: $newVersion'),
                Text('Versión actual: $currentVersion'),
                const SizedBox(height: 16),
                if (isObligatory)
                  const Text(
                    'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.',
                    style: TextStyle(
                      color: VentiqHomeTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  const Text(
                    'Se recomienda actualizar para obtener las últimas mejoras y correcciones.',
                  ),
              ],
            ),
            actions: [
              if (!isObligatory)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Más tarde'),
                ),
              ElevatedButton(
                onPressed: () => _downloadUpdate(),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isObligatory
                          ? VentiqHomeTheme.warning
                          : VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Descargar'),
              ),
            ],
          ),
    );
  }

  /// Mostrar diálogo cuando no hay actualizaciones
  void _showNoUpdateDialog(Map<String, dynamic> updateInfo) {
    final String currentVersion =
        updateInfo['current_version'] ?? 'Desconocida';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: VentiqHomeTheme.success),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aplicación Actualizada',
                    style: TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Versión actual: $currentVersion'),
                const SizedBox(height: 8),
                const Text(
                  'Tu aplicación está actualizada con la última versión disponible.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// Mostrar diálogo de error
  void _showUpdateErrorDialog(String error) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: VentiqHomeTheme.danger),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Error de Verificación',
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No se pudo verificar si hay actualizaciones disponibles.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: $error',
                  style: const TextStyle(
                    fontSize: 12,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  /// Descargar actualización
  Future<void> _downloadUpdate() async {
    try {
      final Uri url = Uri.parse(UpdateService.downloadUrl);

      print('🔗 Intentando abrir URL: ${url.toString()}');

      // Intentar diferentes modos de lanzamiento
      bool launched = false;

      // Método 1: Intentar con navegador web
      try {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
        print('✅ Método 1 (externalApplication): $launched');
      } catch (e) {
        print('❌ Método 1 falló: $e');
      }

      // Método 2: Si falla, intentar con navegador interno
      if (!launched) {
        try {
          launched = await launchUrl(url, mode: LaunchMode.inAppWebView);
          print('✅ Método 2 (inAppWebView): $launched');
        } catch (e) {
          print('❌ Método 2 falló: $e');
        }
      }

      // Método 3: Si falla, intentar modo plataforma
      if (!launched) {
        try {
          launched = await launchUrl(url);
          print('✅ Método 3 (default): $launched');
        } catch (e) {
          print('❌ Método 3 falló: $e');
        }
      }

      if (launched) {
        // Cerrar diálogo
        if (mounted) {
          Navigator.of(context).pop();
        }

        // Mostrar mensaje de confirmación
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Descarga iniciada - Instala la nueva versión'),
            backgroundColor: VentiqHomeTheme.primary,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        // Si todos los métodos fallan, mostrar diálogo con URL para copiar
        _showManualDownloadDialog();
      }
    } catch (e) {
      print('❌ Error general abriendo enlace de descarga: $e');
      _showManualDownloadDialog();
    }
  }

  /// Mostrar diálogo para descarga manual
  void _showManualDownloadDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.download, color: VentiqHomeTheme.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Descarga Manual',
                    style: TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No se pudo abrir automáticamente el enlace de descarga.',
                ),
                const SizedBox(height: 16),
                const Text('Copia este enlace y ábrelo en tu navegador:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VentiqHomeTheme.border),
                  ),
                  child: SelectableText(
                    UpdateService.downloadUrl,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Cerrar diálogo manual
                  Navigator.of(
                    context,
                  ).pop(); // Cerrar diálogo de actualización
                },
                child: const Text('Cerrar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Intentar copiar al portapapeles
                  try {
                    await Clipboard.setData(
                      ClipboardData(text: UpdateService.downloadUrl),
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📋 Enlace copiado al portapapeles'),
                          backgroundColor: VentiqHomeTheme.success,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    print('❌ Error copiando al portapapeles: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Copiar Enlace'),
              ),
            ],
          ),
    );
  }

  void _openCierrePendienteDetalle({String? localId}) {
    Navigator.pushNamed(
      context,
      '/cierre-pendiente',
      arguments:
          (localId != null && localId.isNotEmpty && localId != 'N/A')
              ? localId
              : null,
    );
  }

  /// Línea del detalle de pendientes: icono, texto y cantidad.
  Widget _pendienteRow(IconData icon, String texto, int cantidad) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: VentiqHomeTheme.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
          Text(
            '$cantidad',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Todo lo que sigue en el dispositivo sin subir al servidor, por categoría.
  Widget _buildPendientesDetalle(Map<String, int> pendientes) {
    final total = pendientes['total'] ?? 0;
    if (total == 0) {
      return Row(
        children: const [
          Icon(
            Icons.cloud_done_outlined,
            size: 18,
            color: VentiqHomeTheme.success,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Todo sincronizado: no hay datos offline pendientes',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      );
    }
    final filas = <Widget>[
      if ((pendientes['ventas'] ?? 0) > 0)
        _pendienteRow(
          Icons.shopping_cart_outlined,
          'Ventas sin subir',
          pendientes['ventas']!,
        ),
      if ((pendientes['aperturas'] ?? 0) > 0)
        _pendienteRow(
          Icons.lock_open_outlined,
          'Aperturas de turno',
          pendientes['aperturas']!,
        ),
      if ((pendientes['cierres'] ?? 0) > 0)
        _pendienteRow(
          Icons.lock_outline,
          'Cierres de turno',
          pendientes['cierres']!,
        ),
      if ((pendientes['egresos'] ?? 0) > 0)
        _pendienteRow(
          Icons.payments_outlined,
          'Egresos',
          pendientes['egresos']!,
        ),
      if ((pendientes['cambiosEstado'] ?? 0) > 0)
        _pendienteRow(
          Icons.swap_horiz,
          'Cambios de estado de órdenes',
          pendientes['cambiosEstado']!,
        ),
      if ((pendientes['trabajadores'] ?? 0) > 0)
        _pendienteRow(
          Icons.groups_outlined,
          'Cambios de trabajadores',
          pendientes['trabajadores']!,
        ),
      if ((pendientes['otrasOperaciones'] ?? 0) > 0)
        _pendienteRow(
          Icons.pending_actions,
          'Otras operaciones',
          pendientes['otrasOperaciones']!,
        ),
      if ((pendientes['adminOps'] ?? 0) > 0)
        _pendienteRow(
          Icons.inventory_2_outlined,
          'Inventario/productos',
          pendientes['adminOps']!,
        ),
      if ((pendientes['sinVerificar'] ?? 0) > 0)
        _pendienteRow(
          Icons.help_outline,
          'No se pudo verificar el estado local',
          1,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pendiente de subir al servidor:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        ...filas,
      ],
    );
  }

  Future<void> _showStorageOptions() async {
    final pendientes = await _userPreferencesService.getUnsyncedOfflineCounts();
    if (!mounted) return;
    final closedPending =
        _dataSyncSummary?['closed_turnos_pending_count'] as int? ?? 0;
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Gestión de Datos'),
            content: SingleChildScrollView(
             child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPendientesDetalle(pendientes),
                if ((pendientes['total'] ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showSyncDialog();
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('Sincronizar ahora'),
                    ),
                  ),
                ],
                const Divider(),
                const Text('Opciones de almacenamiento:'),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: VentiqHomeTheme.danger,
                  ),
                  title: const Text('Limpiar todas las órdenes'),
                  subtitle: Text(
                    '${_orderService.totalOrders} órdenes guardadas',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showClearOrdersDialog();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    _pendingOfflineTurnosCount > 0
                        ? Icons.cloud_upload_outlined
                        : Icons.cloud_done_outlined,
                    color:
                        _pendingOfflineTurnosCount > 0
                            ? VentiqHomeTheme.warning
                            : VentiqHomeTheme.success,
                  ),
                  title: Text(
                    _pendingOfflineTurnosCount > 0
                        ? 'Turnos con sincronización pendiente'
                        : 'Turno sincronizado',
                  ),
                  subtitle: Text(
                    _pendingOfflineTurnosCount > 0
                        ? '$_pendingOfflineTurnosCount turno(s) con datos offline por sincronizar'
                        : 'Sin órdenes ni turnos pendientes de sincronización',
                  ),
                  onTap:
                      _pendingOfflineTurnosCount > 0
                          ? () {
                            Navigator.pop(context);
                            _showPendingTurnosDialog();
                          }
                          : null,
                ),
                if (closedPending > 0) ...[
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.visibility_outlined,
                      color: VentiqHomeTheme.primary,
                    ),
                    title: Text(
                      closedPending == 1
                          ? 'Ver cierre guardado'
                          : 'Ver cierres guardados ($closedPending)',
                    ),
                    subtitle: const Text(
                      'Detalle de lo guardado para sincronizar',
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _openCierrePendienteDetalle();
                    },
                  ),
                ],
              ],
             ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
    );
  }

  void _showClearOrdersDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Limpiar Órdenes'),
            content: Text(
              '¿Estás seguro de que quieres eliminar todas las órdenes guardadas? Esta acción no se puede deshacer.\n\nSe eliminarán ${_orderService.totalOrders} órdenes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  _orderService.clearAllOrders();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Todas las órdenes han sido eliminadas'),
                      backgroundColor: VentiqHomeTheme.success,
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: VentiqHomeTheme.danger,
                ),
                child: const Text('Eliminar Todo'),
              ),
            ],
          ),
    );
  }

  /// Mostrar diálogo de confirmación con resumen de datos
  Future<bool?> _showSyncConfirmationDialog(Map<String, dynamic> syncSummary) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.sync, color: VentiqHomeTheme.warning),
                const SizedBox(width: 8),
                const Text('Sincronizar Datos'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Se encontraron los siguientes datos offline pendientes:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                if ((syncSummary['pending_turnos_count'] as int? ?? 0) > 0)
                  _buildSyncItem(
                    Icons.calendar_month,
                    '${syncSummary['pending_turnos_count']} turno(s) pendientes de sync',
                    syncSummary['closed_turnos_pending_count'] != null &&
                            (syncSummary['closed_turnos_pending_count']
                                    as int) >
                                0
                        ? '${syncSummary['closed_turnos_pending_count']} cerrado(s) + '
                            '${syncSummary['has_open_turno'] == true ? '1 abierto' : '0 abiertos'}'
                        : 'Se subirán en orden (apertura → ventas → cierre)',
                  ),
                if (syncSummary['has_open_turno'] == true &&
                    (syncSummary['pending_turnos_count'] as int? ?? 0) <= 1)
                  _buildSyncItem(
                    Icons.access_time,
                    'Turno abierto offline',
                    'Se creará/actualizará el turno en el servidor',
                  ),
                if (syncSummary['pending_orders_count'] > 0)
                  _buildSyncItem(
                    Icons.shopping_cart,
                    '${syncSummary['pending_orders_count']} órdenes pendientes',
                    'Se registrarán las ventas y estados',
                  ),
                if (syncSummary['pending_operations_count'] > 0)
                  _buildSyncItem(
                    Icons.pending_actions,
                    '${syncSummary['pending_operations_count']} operaciones pendientes',
                    'Se procesarán egresos y cambios de estado',
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.warning.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: VentiqHomeTheme.warning.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi,
                        color: VentiqHomeTheme.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Asegúrate de tener conexión a internet estable',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sincronizar'),
              ),
            ],
          ),
    );
  }

  /// Widget para mostrar item de sincronización
  Widget _buildSyncItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: VentiqHomeTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
                Text(subtitle, style: _tileSubtitleStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Iniciar sincronización manual
  Future<void> _startManualSync() async {
    final synced = await _forceSyncNow(blockWhenRunning: false);
    if (synced && mounted) {
      await _refreshDataSection();
      await _loadSettings();
    }
  }

  /// Mostrar diálogo para descargar la aplicación
  void _showDownloadDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              _settingsIcon(Icons.download_outlined),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Descargar Inventtia Caja',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enlace directo para descargar Inventtia Caja:',
                style: TextStyle(
                  fontSize: 14,
                  color: VentiqHomeTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Inventtia Caja $_appVersion',
                style: const TextStyle(
                  fontSize: 12,
                  color: VentiqHomeTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/Lk1KNR.png',
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'O comparte el enlace directo:',
                style: TextStyle(
                  fontSize: 12,
                  color: VentiqHomeTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(
                _downloadAppUrl,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: VentiqHomeTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Share.share(_downloadAppUrl),
              icon: const Icon(Icons.share, size: 20),
              label: const Text('Compartir link'),
              style: TextButton.styleFrom(
                foregroundColor: VentiqHomeTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: VentiqHomeTheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Cerrar',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Inventtia Caja',
      applicationVersion: _appVersion,
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: VentiqHomeTheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.inventory_2, color: Colors.white, size: 32),
      ),
      children: [
        const Text(
          'Punto de venta (caja) de Inventtia para gestionar ventas y turnos.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Desarrollado para optimizar el proceso de pedidos y gestión de productos.',
        ),
      ],
    );
  }

  void _showLogoutDialog() {
    AppDrawer.promptLogoutOrSwitchUser(context);
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home → /mesas si modo restaurante, /categories si no
        NavigationHelper.goHome(context);
        break;
      case 1: // Carrito: preorden, o la cuenta de mesa abierta en restaurante
        NavigationHelper.goCarrito(context);
        break;
      case 2: // Órdenes
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración (current)
        break;
    }
  }

  /// Widget para mostrar el estado de sincronización inteligente
  Widget _buildSmartSyncStatusTile() {
    final status = _smartIntegrationStatus;
    if (status == null) {
      return ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: VentiqHomeTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusTile),
          ),
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: VentiqHomeTheme.primary,
              ),
            ),
          ),
        ),
        title: const Text(
          'Estado de Sincronización',
          style: _tileTitleStyle,
        ),
        subtitle: const Text('Cargando estado...', style: _tileSubtitleStyle),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      );
    }

    final smartStatus = status.smartOfflineStatus;

    IconData icon;
    Color iconColor;
    String title;
    String subtitle;

    if (status.isOfflineModeEnabled) {
      icon = Icons.cloud_off;
      iconColor = VentiqHomeTheme.warning;
      title = 'Modo Offline Activo';
      subtitle = 'Trabajando sin conexión';
    } else if (smartStatus.isConnected && smartStatus.isAutoSyncRunning) {
      icon = Icons.sync;
      iconColor = VentiqHomeTheme.success;
      title = 'Sincronización Automática';
      final syncCount = smartStatus.syncStats['syncCount'] ?? 0;
      subtitle = 'Ejecutándose - $syncCount sincronizaciones';
    } else if (smartStatus.isConnected) {
      icon = Icons.wifi;
      iconColor = VentiqHomeTheme.primary;
      title = 'Conectado';
      subtitle = 'Listo para sincronizar';
    } else {
      icon = Icons.wifi_off;
      iconColor = VentiqHomeTheme.danger;
      title = 'Sin Conexión';
      subtitle = 'Verificando conectividad...';
    }

    return ListTile(
      leading: _settingsIcon(icon, color: iconColor),
      title: Text(title, style: _tileTitleStyle),
      subtitle: Text(subtitle, style: _tileSubtitleStyle),
      trailing: IconButton(
        icon: const Icon(
          Icons.info_outline,
          color: VentiqHomeTheme.textSecondary,
        ),
        onPressed: () => _showSmartSyncDetails(status),
        tooltip: 'Ver detalles',
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    );
  }

  /// Mostrar detalles del estado de sincronización inteligente
  void _showSmartSyncDetails(SettingsIntegrationStatus status) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: VentiqHomeTheme.primary),
                SizedBox(width: 8),
                Text('Estado de Sincronización'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    'Servicios Inicializados',
                    status.isInitialized ? 'Sí' : 'No',
                  ),
                  _buildDetailRow(
                    'Conexión',
                    status.smartOfflineStatus.isConnected
                        ? 'Conectado'
                        : 'Desconectado',
                  ),
                  _buildDetailRow(
                    'Modo Offline',
                    status.isOfflineModeEnabled ? 'Activado' : 'Desactivado',
                  ),
                  _buildDetailRow(
                    'Sincronización Auto',
                    status.smartOfflineStatus.isAutoSyncRunning
                        ? 'Ejecutándose'
                        : 'Detenida',
                  ),

                  if (status.smartOfflineStatus.syncStats['lastSyncTime'] !=
                      null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Última Sincronización:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatDateTime(
                        DateTime.parse(
                          status.smartOfflineStatus.syncStats['lastSyncTime'],
                        ),
                      ),
                      style: const TextStyle(
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                  ],

                  if (status.smartOfflineStatus.lastAutoActivation != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Última Activación Automática:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatDateTime(
                        status.smartOfflineStatus.lastAutoActivation!,
                      ),
                      style: const TextStyle(
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: VentiqHomeTheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: VentiqHomeTheme.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ℹ️ Información:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '• La sincronización automática se ejecuta cada minuto cuando el modo offline está desactivado',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          '• El modo offline se activa automáticamente si se pierde la conexión',
                          style: TextStyle(fontSize: 12),
                        ),
                        Text(
                          '• Los datos se mantienen sincronizados para uso offline',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              if (!status.smartOfflineStatus.isAutoSyncRunning &&
                  status.smartOfflineStatus.isConnected)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _forceSyncNow(blockWhenRunning: false);
                  },
                  child: const Text('Sincronizar Ahora'),
                ),
            ],
          ),
    );
  }

  /// Widget para mostrar una fila de detalles
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Forzar sincronización inmediata
  Future<bool> _forceSyncNow({
    bool blockWhenRunning = true,
    bool offlineReadinessOnly = false,
  }) async {
    final status = await _getIntegrationStatusSafe();

    if (status != null) {
      final isBusy = await _isAutoSyncBusy(blockWhenRunning: blockWhenRunning);
      if (isBusy) {
        _showAutoSyncBlockedMessage(
          '🔄 Sincronización automática en curso. Intenta de nuevo en unos segundos.',
        );
        return false;
      }

      final hasPendingAutoSync =
          status.smartOfflineStatus.isConnected &&
          status.isOfflineModeEnabled &&
          status.smartOfflineStatus.wasOfflineModeManuallyEnabled == false;
      if (hasPendingAutoSync) {
        _showAutoSyncBlockedMessage(
          '📶 Conexión restaurada. Desactiva el modo offline para que la sincronización automática termine primero.',
        );
        return false;
      }
    }

    try {
      // Mostrar loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text('🔄 Iniciando sincronización...'),
            ],
          ),
          backgroundColor: VentiqHomeTheme.primary,
          duration: Duration(seconds: 2),
        ),
      );

      const requiredOfflineModules = {
        SyncModule.license,
        SyncModule.storeConfig,
        SyncModule.credentials,
        SyncModule.paymentMethods,
        SyncModule.promotions,
        SyncModule.categories,
        SyncModule.products,
        SyncModule.layouts,
        SyncModule.turno,
        SyncModule.egresos,
        SyncModule.orders,
        SyncModule.shiftWorkers,
        // SyncModule.defaultCashFund es opcional: se descarga si existe, pero
        // no bloquea la activación offline si la tienda aún no lo configura.
      };
      final result = await AutoSyncService().syncModules(
        offlineReadinessOnly
            ? requiredOfflineModules
            : SyncModule.values.toSet(),
        resumeFromCheckpoint: !offlineReadinessOnly,
        suspenderModoOffline: true,
      );
      final syncSucceeded = result.success;
      if (!mounted) return false;
      await _showSyncResultFeedback(result);

      unawaited(_refreshDataSection());
      return syncSucceeded;
    } catch (e) {
      print('❌ Error forzando sincronización: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error en sincronización: $e'),
          backgroundColor: VentiqHomeTheme.danger,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
  }

  /// Muestra resumen (completo / parcial / fallido) al terminar una sync manual.
  Future<void> _showSyncResultFeedback(SyncResult result) async {
    if (!mounted) return;

    Color bg;
    String title;
    if (result.success) {
      bg = VentiqHomeTheme.success;
      title = '✅ Sincronización completada';
    } else if (result.hasProgress) {
      bg = VentiqHomeTheme.warning;
      title =
          result.interrupted
              ? '⚠️ Sincronización interrumpida'
              : '⚠️ Sincronización parcial';
    } else {
      bg = VentiqHomeTheme.danger;
      title = '❌ Sincronización fallida';
    }

    final okCount = result.syncedItems.length;
    final errCount = result.errors.length;
    final skipCount = result.skippedItems.length;
    final short =
        '$title · OK $okCount'
        '${errCount > 0 ? ' · Errores $errCount' : ''}'
        '${skipCount > 0 ? ' · Pendientes $skipCount' : ''}'
        ' (${result.duration.inSeconds}s)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(short),
        backgroundColor: bg,
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(
          label: 'Detalle',
          textColor: Colors.white,
          onPressed: () => _showSyncResultDialog(result),
        ),
      ),
    );

    // Si hubo interrupción o errores, abrir detalle automáticamente.
    if (!result.success) {
      await _showSyncResultDialog(result);
    }
  }

  Future<void> _showSyncResultDialog(SyncResult result) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            result.success
                ? 'Sincronización completada'
                : result.interrupted
                ? 'Sincronización interrumpida'
                : result.hasProgress
                ? 'Sincronización parcial'
                : 'Sincronización fallida',
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result.abortReason != null) ...[
                    Text(
                      'Motivo: ${result.abortReason}',
                      style: TextStyle(
                        color: VentiqHomeTheme.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Duración: ${result.duration.inSeconds}s',
                    style: const TextStyle(
                      fontSize: 13,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (result.syncedItems.isNotEmpty) ...[
                    const Text(
                      'Completado',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(result.syncedItems.map((e) => '• $e').join('\n')),
                    const SizedBox(height: 12),
                  ],
                  if (result.errors.isNotEmpty) ...[
                    const Text(
                      'Errores',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.errors.map((e) => '• $e').join('\n'),
                      style: TextStyle(color: VentiqHomeTheme.danger),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (result.skippedItems.isNotEmpty) ...[
                    const Text(
                      'Quedó pendiente (se reanudará)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.skippedItems.map((e) => '• $e').join('\n'),
                      style: TextStyle(color: VentiqHomeTheme.warning),
                    ),
                  ],
                  if (result.syncedItems.isEmpty &&
                      result.errors.isEmpty &&
                      result.skippedItems.isEmpty)
                    const Text('No hubo cambios en esta pasada.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  /// Formatear fecha y hora de manera amigable
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Hace unos segundos';
    } else if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''}';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} hora${difference.inHours > 1 ? 's' : ''}';
    } else {
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  /// Mostrar diálogo con los turnos offline pendientes de sincronizar.
  void _showPendingTurnosDialog() {
    showDialog(
      context: context,
      builder: (context) {
        var refreshKey = 0;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Turnos offline pendientes'),
              content: FutureBuilder<List<Map<String, dynamic>>>(
                key: ValueKey(refreshKey),
                future: _userPreferencesService.getOfflineTurnosPendingSync(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final turnos = snapshot.data ?? [];
                  if (turnos.isEmpty) {
                    return const Text(
                      'No hay turnos pendientes de sincronizar.',
                    );
                  }
                  return SizedBox(
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: turnos.length,
                      itemBuilder: (context, index) {
                        final t = turnos[index];
                        final localId = t['local_id']?.toString() ?? 'N/A';
                        final displayId = _shortLocalTurnoId(localId);
                        final status = t['status']?.toString() ?? '';
                        final pendingOrders =
                            (t['pending_orders_count'] as num?)?.toInt() ?? 0;
                        final fechaApertura =
                            t['fecha_apertura']?.toString() ?? '';
                        final estado =
                            status == 'open'
                                ? 'Abierto'
                                : 'Cerrado (pendiente)';
                        return ListTile(
                          leading: Icon(
                            status == 'open'
                                ? Icons.lock_open
                                : Icons.lock_outline,
                            color:
                                status == 'open'
                                    ? VentiqHomeTheme.success
                                    : VentiqHomeTheme.warning,
                          ),
                          title: Text('Turno $displayId'),
                          subtitle: Text(
                            'Apertura: $fechaApertura\nEstado: $estado'
                            '${pendingOrders > 0 ? '\n$pendingOrders venta${pendingOrders == 1 ? '' : 's'} pendiente${pendingOrders == 1 ? '' : 's'} incluida${pendingOrders == 1 ? '' : 's'}' : ''}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (status != 'open')
                                IconButton(
                                  tooltip: 'Ver cierre guardado',
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    color: VentiqHomeTheme.primary,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _openCierrePendienteDetalle(
                                      localId: localId,
                                    );
                                  },
                                ),
                              if (status == 'open')
                                IconButton(
                                  tooltip: 'Cerrar turno',
                                  icon: const Icon(
                                    Icons.point_of_sale,
                                    color: VentiqHomeTheme.warning,
                                  ),
                                  onPressed: () async {
                                    await _cerrarTurnoPendiente(localId);
                                    setDialogState(() => refreshKey++);
                                  },
                                ),
                              IconButton(
                                tooltip: 'Sincronizar',
                                icon: const Icon(
                                  Icons.sync,
                                  color: VentiqHomeTheme.primary,
                                ),
                                onPressed: () async {
                                  await _syncSingleTurno(localId);
                                  setDialogState(() => refreshKey++);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            if (status != 'open') {
                              Navigator.pop(context);
                              _openCierrePendienteDetalle(localId: localId);
                              return;
                            }
                            _showTurnoDetailDialog(
                              t,
                              onSync: () => setDialogState(() => refreshKey++),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Muestra la información de apertura y cierre de un turno offline.
  void _showTurnoDetailDialog(
    Map<String, dynamic> turno, {
    VoidCallback? onSync,
  }) {
    final localId = turno['local_id']?.toString() ?? 'N/A';
    final displayId = _shortLocalTurnoId(localId);
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Cierre de caja - $displayId'),
            content: FutureBuilder<List<dynamic>>(
              future: Future.wait([
                _userPreferencesService.getOfflineTurnoCuadre(turno),
                CurrencyService.getUsdRate(),
              ]),
              builder: (context, snapshot) {
                final apertura = turno['apertura'] ?? {};
                final cierre = turno['cierre'] ?? {};
                final cuadre =
                    (snapshot.data != null
                        ? snapshot.data![0] as Map<String, dynamic>?
                        : null) ??
                    {};
                final usdRate =
                    (snapshot.data != null
                        ? snapshot.data![1] as double?
                        : null) ??
                    0.0;

                final fechaApertura =
                    apertura['fecha_apertura']?.toString() ??
                    turno['fecha_apertura']?.toString() ??
                    'N/A';
                final efectivoInicial =
                    (apertura['efectivo_inicial'] as num? ??
                            turno['efectivo_inicial'] as num? ??
                            0)
                        .toDouble();
                final fechaCierre =
                    cierre['fecha_cierre']?.toString() ?? 'Sin cierre';
                final totalVentas =
                    (cuadre['total_ventas'] as num? ??
                            cuadre['ventas_totales'] as num? ??
                            0)
                        .toDouble();
                final totalEfectivo =
                    (cuadre['total_efectivo'] as num? ??
                            cuadre['efectivo_real'] as num? ??
                            0)
                        .toDouble();
                final totalTransferencias =
                    (cuadre['total_transferencias'] as num? ?? 0).toDouble();
                final efectivoEsperado =
                    (cuadre['efectivo_esperado'] as num? ??
                            efectivoInicial + totalEfectivo)
                        .toDouble();
                final egresosEfectivo =
                    (cuadre['egresos_efectivo'] as num? ?? 0).toDouble();
                final egresosDigitales =
                    (cuadre['egresos_digitales'] as num? ?? 0).toDouble();
                final egresosTotales =
                    (cuadre['egresos_totales'] as num? ??
                            egresosEfectivo + egresosDigitales)
                        .toDouble();
                // FASE 3: sin .toInt() — las cantidades fraccionadas (0,5 kg)
                // se perdian al truncar.
                final productosVendidos =
                    (cuadre['productos_vendidos'] as num? ?? 0);
                final operacionesTotales =
                    (cuadre['operaciones_totales'] as num? ?? 0).toInt();
                final ticketPromedio =
                    (cuadre['ticket_promedio'] as num? ?? 0).toDouble();
                final diferencia =
                    (cuadre['diferencia'] as num? ?? 0).toDouble();
                final totalVentasUsd =
                    usdRate > 0 ? totalVentas / usdRate : null;

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Apertura: $fechaApertura',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Efectivo inicial: \$${efectivoInicial.toMoneyString(2)}',
                      ),
                      Text('Cierre: $fechaCierre'),
                      const SizedBox(height: 12),
                      Text(
                        'Resumen:',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Total ventas: \$${totalVentas.toMoneyString(2)} CUP'
                        '${totalVentasUsd != null ? ' (≈ \$${totalVentasUsd.toMoneyString(2)} USD)' : ''}',
                      ),
                      Text('Productos vendidos: $productosVendidos'),
                      Text('Operaciones: $operacionesTotales'),
                      Text(
                        'Ticket promedio: \$${ticketPromedio.toMoneyString(2)}',
                      ),
                      const SizedBox(height: 8),
                      Text('Efectivo: \$${totalEfectivo.toMoneyString(2)}'),
                      Text(
                        'Transferencias: \$${totalTransferencias.toMoneyString(2)}',
                      ),
                      Text(
                        'Efectivo esperado: \$${efectivoEsperado.toMoneyString(2)}',
                      ),
                      if (diferencia.abs() > 0.01)
                        Text(
                          'Diferencia: ${diferencia >= 0 ? '+' : ''}\$${diferencia.toMoneyString(2)}',
                          style: TextStyle(
                            color:
                                diferencia >= 0
                                    ? VentiqHomeTheme.success
                                    : VentiqHomeTheme.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Egresos:',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Egresos efectivo: \$${egresosEfectivo.toMoneyString(2)}',
                      ),
                      Text(
                        'Egresos digitales: \$${egresosDigitales.toMoneyString(2)}',
                      ),
                      Text(
                        'Egresos totales: \$${egresosTotales.toMoneyString(2)}',
                      ),
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
              if ((turno['status']?.toString() ?? '') ==
                  UserPreferencesService.offlineTurnoStatusClosedPending)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(
                      context,
                      '/cierre-pendiente',
                      arguments: localId == 'N/A' ? null : localId,
                    );
                  },
                  child: const Text('Ver todo'),
                ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _syncSingleTurno(localId);
                  onSync?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sincronizar'),
              ),
            ],
          ),
    );
  }

  /// Abre el flujo completo de cierre de caja (conteo de efectivo,
  /// inventario, egresos, etc.) para un turno abierto que está en la cola
  /// pendiente de sincronizar.
  ///
  /// `CierreScreen` siempre opera sobre "el" turno abierto ambiente (el que
  /// devuelve `getOfflineTurno()`/la sesión activa del vendedor), así que
  /// primero verificamos que el turno tocado en la lista sea justamente ese;
  /// si es un turno abierto "huérfano" de otra sesión/TPV, avisamos en vez
  /// de arriesgarnos a cerrar el turno equivocado.
  Future<void> _cerrarTurnoPendiente(String localId) async {
    final activeTurno = await _userPreferencesService.getOfflineTurno();
    final activeLocalId = activeTurno?['local_id']?.toString();

    if (activeLocalId != localId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este turno no es el activo en este dispositivo/sesión. '
            'Solo se puede completar el cierre del turno actualmente abierto.',
          ),
          backgroundColor: VentiqHomeTheme.warning,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context); // Cierra el diálogo de turnos pendientes
    await Navigator.pushNamed(context, '/cierre');
    if (mounted) await _refreshDataSection();
  }

  /// Sincroniza un único turno (apertura + órdenes + cierre).
  Future<void> _syncSingleTurno(String localId) async {
    print('[TURNO_SYNC] Settings._syncSingleTurno START localId=$localId');
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'Settings ANTES sync single',
    );
    final sync = AutoSyncService();
    final result = await sync.syncOfflineTurnoAfterLocalCierre(
      localId: localId,
      allowWhileOffline: true,
    );
    print(
      '[TURNO_SYNC] Settings._syncSingleTurno END '
      'success=${result['success']} msg=${result['message']}',
    );
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'Settings DESPUÉS sync single',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'Sincronización del turno completada'
              : 'Error: ${result['message'] ?? 'No especificado'}',
        ),
        backgroundColor:
            result['success'] == true
                ? VentiqHomeTheme.success
                : VentiqHomeTheme.danger,
      ),
    );
    await _refreshDataSection();
  }
}
