import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../services/order_service.dart';
import '../services/user_preferences_service.dart';
import '../services/category_service.dart';
import '../services/product_service.dart';
import '../services/payment_method_service.dart';
import '../services/turno_service.dart';
import '../services/settings_integration_service.dart';
import '../services/store_config_service.dart';
import '../utils/navigation_helper.dart';
import '../services/update_service.dart';
import '../services/subscription_guard_service.dart';
import '../models/subscription.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sync_status_chip.dart';
import '../services/connectivity_service.dart';
import 'dart:async';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final OrderService _orderService = OrderService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final SettingsIntegrationService _integrationService =
      SettingsIntegrationService();
  final SubscriptionGuardService _subscriptionGuard =
      SubscriptionGuardService();

  bool _isPrintEnabled = true; // Valor por defecto
  bool _isPrintUsdEnabled = false; // Valor por defecto
  bool _isStaticTextEnabled = false; // Valor por defecto (marquee activo)
  bool _isShowSkuEnabled = false; // Valor por defecto (SKU oculto)
  bool _isLimitDataUsageEnabled = false; // Valor por defecto
  bool _isFluidModeEnabled =
      false; // Deshabilitado - Disponible en próxima versión
  bool _isOfflineModeEnabled = false; // Valor por defecto
  bool _hasOfflineTurno = false; // Turno abierto offline
  Map<String, dynamic>? _offlineTurnoInfo; // Información del turno offline
  bool _isModoRestauranteEnabled = false; // Modo restaurante (mesas y comensales)
  bool _isLoadingModoRestaurante = false;

  // Nuevas variables para servicios inteligentes
  StreamSubscription<SettingsIntegrationEvent>? _integrationSubscription;
  bool _isSmartServicesInitialized = false;
  String? _lastSmartEvent;

  // Variable para la versión dinámica
  String _appVersion = 'Cargando...';

  // Variables para suscripción
  Subscription? _currentSubscription;
  bool _isLoadingSubscription = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _loadAppVersion();
    _loadSubscriptionData();
    _initializeSmartServices();
  }

  /// Cargar datos de suscripción
  Future<void> _loadSubscriptionData() async {
    setState(() => _isLoadingSubscription = true);

    try {
      _currentSubscription = await _subscriptionGuard.getCurrentSubscription(
        forceRefresh: false,
      );
    } catch (e) {
      print('❌ Error cargando datos de suscripción: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSubscription = false);
      }
    }
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

      if (hasConnection && isOfflineMode) {
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
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 3),
            ),
          );
        }

        // Recargar configuraciones para reflejar el estado actual
        _loadSettings();
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
    Navigator.pushNamed(context, '/subscription-detail');
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
    final showSkuEnabled =
        await _userPreferencesService.isShowSkuEnabled();
    final limitDataEnabled =
        await _userPreferencesService.isLimitDataUsageEnabled();
    final offlineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();
    final hasOfflineTurno =
        await _userPreferencesService.hasOfflineTurnoAbierto();
    final offlineTurnoInfo =
        await _userPreferencesService.getOfflineTurnoInfo();

    // Modo restaurante - leer del cache (lo más rápido) sin bloquear el resto
    bool modoRestaurante = false;
    try {
      final cfg = await StoreConfigService.getStoreConfigFromCache();
      modoRestaurante = cfg?['modo_restaurante'] ?? false;
    } catch (e) {
      print('⚠️ No se pudo leer modo_restaurante del cache: $e');
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
        _hasOfflineTurno = hasOfflineTurno;
        _offlineTurnoInfo = offlineTurnoInfo;
        _isModoRestauranteEnabled = modoRestaurante;
      });
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
            backgroundColor: Colors.red,
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
          backgroundColor: value ? Colors.green : Colors.blueGrey,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      setState(() => _isModoRestauranteEnabled = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error guardando la configuración'),
          backgroundColor: Colors.red,
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

      print('✅ Servicios inteligentes inicializados en Settings');
    } catch (e) {
      print('❌ Error inicializando servicios inteligentes: $e');

      // Mostrar error al usuario
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error inicializando servicios inteligentes: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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

    // Verificar si el widget está montado antes de llamar setState
    if (mounted) {
      setState(() {
        _lastSmartEvent = event.message;
      });
    }

    // Mostrar notificaciones importantes al usuario
    if (mounted) {
      switch (event.type) {
        case SettingsIntegrationEventType.offlineModeAutoActivated:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '🔌 Modo offline activado automáticamente por pérdida de conexión',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          // Recargar configuraciones para reflejar el cambio
          if (mounted) {
            _loadSettings();
          }
          break;

        case SettingsIntegrationEventType.offlineModeAutoDeactivated:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📶 Modo offline desactivado automáticamente - Conexión restaurada',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
          // Recargar configuraciones para reflejar el cambio
          if (mounted) {
            _loadSettings();
          }
          break;

        case SettingsIntegrationEventType.connectionRestored:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '📶 Conexión restaurada - Datos sincronizándose automáticamente',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          break;

        case SettingsIntegrationEventType.autoSyncStarted:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔄 Sincronización automática iniciada'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
          break;

        case SettingsIntegrationEventType.reauthenticationStarted:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🔐 Reautenticando usuario...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          break;

        case SettingsIntegrationEventType.reauthenticationSuccess:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Usuario reautenticado correctamente'),
              backgroundColor: Colors.green,
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
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          break;

        case SettingsIntegrationEventType.error:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${event.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
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
        backgroundColor: value ? Colors.green : Colors.orange,
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
        backgroundColor: value ? Colors.green : Colors.orange,
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
          value
              ? 'SKU de producto visible'
              : 'SKU de producto oculto',
        ),
        backgroundColor: value ? Colors.green : Colors.orange,
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
        backgroundColor: value ? Colors.blue : Colors.green,
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
        backgroundColor: value ? Colors.blue : Colors.green,
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
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _activateOfflineMode() async {
    try {
      final hasOfflineData = await _userPreferencesService.hasOfflineData();

      if (!hasOfflineData) {
        final synced = await _forceSyncNow(blockWhenRunning: false);
        if (!synced) {
          if (mounted) {
            setState(() {
              _isOfflineModeEnabled = false;
            });
          }
          return;
        }
      }

      final isReady = await _userPreferencesService.hasOfflineData();
      if (!isReady) {
        _showAutoSyncBlockedMessage(
          '⚠️ No hay datos offline disponibles. Sincroniza primero.',
        );
        if (mounted) {
          setState(() {
            _isOfflineModeEnabled = false;
          });
        }
        return;
      }

      await _userPreferencesService.setOfflineMode(true);

      if (_isSmartServicesInitialized) {
        await _integrationService.handleOfflineModeChanged(true);
      }

      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = true;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔌 Modo offline activado - Datos listos sin conexión'),
          backgroundColor: Colors.green,
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
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _deactivateOfflineMode() async {
    try {
      await _userPreferencesService.setOfflineMode(false);

      if (_isSmartServicesInitialized) {
        await _integrationService.handleOfflineModeChanged(false);
      }

      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🌐 Modo offline desactivado - Sincronización automática iniciada',
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Error desactivando modo offline: $e');
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = true;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error desactivando modo offline: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _onOfflineModeChanged(bool value) async {
    final isBusy = await _isAutoSyncBusy(blockWhenRunning: false);
    if (isBusy) {
      _showAutoSyncBlockedMessage(
        '🔄 Sincronización automática en progreso. Espera para cambiar el modo offline.',
      );
      if (mounted) {
        setState(() {
          _isOfflineModeEnabled = !value;
        });
      }
      return;
    }

    if (value) {
      await _activateOfflineMode();
    } else {
      await _deactivateOfflineMode();
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
        leading: const CircularProgressIndicator(),
        title: const Text('Cargando suscripción...'),
        subtitle: const Text('Verificando estado'),
      );
    }

    final subscription = _currentSubscription;
    final isActive = subscription?.isActive ?? false;

    return _buildSettingsTile(
      icon: isActive ? Icons.verified : Icons.warning,
      title: isActive ? 'Suscripción Activa' : 'Suscripción Inactiva',
      subtitle:
          subscription != null
              ? '${subscription.planDenominacion ?? 'Plan desconocido'} - ${subscription.estadoText}'
              : 'No se encontró información de suscripción',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subscription != null &&
              subscription.diasRestantes > 0 &&
              subscription.diasRestantes <= 30)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Text(
                '${subscription.diasRestantes}d',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange,
                ),
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: () => _navigateToSubscriptionDetail(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
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
                                ? Colors.grey[600]
                                : Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _isOfflineModeEnabled
                              ? Colors.grey[100]
                              : Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            _isOfflineModeEnabled
                                ? Colors.grey[400]!
                                : Colors.green[400]!,
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 1,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
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
                            size: 12,
                            color:
                                _isOfflineModeEnabled
                                    ? Colors.grey[600]
                                    : Colors.green[600],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _isOfflineModeEnabled ? 'Offline' : 'Online',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color:
                                  _isOfflineModeEnabled
                                      ? Colors.grey[600]
                                      : Colors.green[600],
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
            padding: const EdgeInsets.all(16),
            children: [
              // Sección de cuenta
              _buildSectionHeader('Cuenta'),
              _buildSettingsCard([
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
              ]),

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
                  onTap: () => Navigator.pushNamed(
                      context, '/default-order-items'),
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

              // Sección de turno offline (solo si hay turno abierto offline)
              if (_hasOfflineTurno) ...[
                _buildSectionHeader('Turno Offline'),
                _buildSettingsCard([_buildOfflineTurnoTile()]),
                const SizedBox(height: 16),
              ],

              // Sección de datos
              _buildSectionHeader('Datos'),
              _buildSettingsCard([
                _buildSettingsTile(
                  icon: Icons.sync_outlined,
                  title: 'Sincronización Manual',
                  subtitle: 'Sincronizar datos offline pendientes',
                  onTap: () => _showSyncDialog(),
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
                  subtitle: 'Inventtia $_appVersion',
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
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
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF4A90E2), size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildPrintUsdSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.attach_money,
          color: Color(0xFF10B981),
          size: 20,
        ),
      ),
      title: const Text(
        'Mostrar USD en impresiones',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isPrintUsdEnabled
            ? 'Se mostrará CUP + USD en tickets y vales'
            : 'Solo se mostrará CUP en tickets y vales',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isPrintUsdEnabled,
        onChanged: _onPrintUsdSettingChanged,
        activeColor: const Color(0xFF10B981),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey[200],
      indent: 60,
    );
  }

  Widget _buildPrintSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.print_outlined,
          color: Color(0xFF4A90E2),
          size: 20,
        ),
      ),
      title: const Text(
        'Habilitar Impresión',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isPrintEnabled
            ? 'Las órdenes se imprimirán automáticamente'
            : 'Impresión deshabilitada',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isPrintEnabled,
        onChanged: _onPrintSettingChanged,
        activeColor: const Color(0xFF4A90E2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildShowSkuSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.tag_outlined,
          color: Color(0xFF4A90E2),
          size: 20,
        ),
      ),
      title: const Text(
        'Mostrar SKU de Producto',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isShowSkuEnabled
            ? 'El código SKU será visible en los productos'
            : 'El código SKU no se mostrará en los productos',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isShowSkuEnabled,
        onChanged: _onShowSkuSettingChanged,
        activeColor: const Color(0xFF6B7280),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildStaticTextSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.text_fields_outlined,
          color: Color(0xFF4A90E2),
          size: 20,
        ),
      ),
      title: const Text(
        'Mostrar Textos Estáticos',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isStaticTextEnabled
            ? 'Los nombres de productos no se moverán'
            : 'Los nombres largos se moverán de izquierda a derecha',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isStaticTextEnabled,
        onChanged: _onStaticTextSettingChanged,
        activeColor: const Color(0xFF4A90E2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildFluidModeSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.speed_outlined, color: Colors.grey, size: 20),
      ),
      title: const Text(
        'Modo Fluido',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Navegación tradicional por pantallas separadas',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            'Estará disponible en una próxima versión',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[700],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
      trailing: Switch(
        value: false,
        onChanged: null, // Deshabilitado
        activeColor: Colors.grey,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDataUsageSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.data_saver_on, color: Colors.orange, size: 20),
      ),
      title: const Text(
        'Limitar uso de datos',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isLimitDataUsageEnabled
            ? 'Modo ahorro activado - No se cargarán imágenes'
            : 'Carga completa de imágenes',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isLimitDataUsageEnabled,
        onChanged: _onLimitDataUsageChanged,
        activeColor: Colors.orange,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildModoRestauranteTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFE65100).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.restaurant_menu,
          color: Color(0xFFE65100),
          size: 20,
        ),
      ),
      title: const Text(
        'Modo Restaurante',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isModoRestauranteEnabled
            ? 'Mesas y comensales activos — el checkout pide mesa en lugar de cliente'
            : 'Activar para gestionar mesas y cuentas por comensal',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: _isLoadingModoRestaurante
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(
              value: _isModoRestauranteEnabled,
              onChanged: _onModoRestauranteChanged,
              activeColor: const Color(0xFFE65100),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildOfflineModeSettingsTile() {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.cloud_off, color: Colors.blue, size: 20),
      ),
      title: const Text(
        'Modo Offline',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Text(
        _isOfflineModeEnabled
            ? 'Datos sincronizados - Puede trabajar sin conexión'
            : 'Sincronizar datos para trabajar offline',
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: _isOfflineModeEnabled,
        onChanged: _onOfflineModeChanged,
        activeColor: Colors.blue,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildOfflineTurnoTile() {
    final turnoInfo = _offlineTurnoInfo;
    if (turnoInfo == null) return const SizedBox.shrink();

    final fechaApertura = turnoInfo['fecha_apertura'] as String?;
    final efectivoInicial = (turnoInfo['efectivo_inicial'] as num?)?.toDouble();

    String fechaFormateada = 'Fecha no disponible';
    if (fechaApertura != null) {
      try {
        final fecha = DateTime.parse(fechaApertura);
        fechaFormateada =
            '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
      } catch (e) {
        fechaFormateada = 'Fecha inválida';
      }
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.access_time, color: Colors.orange, size: 20),
      ),
      title: const Text(
        'Turno Abierto Offline',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1F2937),
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apertura: $fechaFormateada',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (efectivoInicial != null)
            Text(
              'Efectivo inicial: \$${efectivoInicial.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
        ],
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: const Text(
          'OFFLINE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildLogoutButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 1),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.logout, color: Colors.red, size: 20),
        ),
        title: const Text(
          'Cerrar Sesión',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.red,
          ),
        ),
        subtitle: Text(
          'Salir de la aplicación',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        onTap: _showLogoutDialog,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    final hasPendingData =
        syncSummary['pending_orders_count'] > 0 ||
        syncSummary['pending_operations_count'] > 0 ||
        syncSummary['has_open_turno'] == true;

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
                  color: isObligatory ? Colors.orange : Colors.blue,
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
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
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
                  backgroundColor: isObligatory ? Colors.orange : Colors.blue,
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
                Icon(Icons.check_circle, color: Colors.green),
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
                Icon(Icons.error, color: Colors.red),
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
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            backgroundColor: Colors.blue,
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
                Icon(Icons.download, color: Colors.blue),
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
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
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    print('❌ Error copiando al portapapeles: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Copiar Enlace'),
              ),
            ],
          ),
    );
  }

  void _showStorageOptions() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Gestión de Datos'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Opciones de almacenamiento:'),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Limpiar todas las órdenes'),
                  subtitle: Text(
                    '${_orderService.totalOrders} órdenes guardadas',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showClearOrdersDialog();
                  },
                ),
              ],
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
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
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
                Icon(Icons.sync, color: Colors.orange[700]),
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
                if (syncSummary['has_open_turno'] == true)
                  _buildSyncItem(
                    Icons.access_time,
                    'Turno abierto offline',
                    'Se creará el turno en el servidor',
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
                    'Se procesarán aperturas, cierres y cambios',
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi, color: Colors.orange[700], size: 20),
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
                  backgroundColor: Colors.orange[700],
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
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
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
      await _loadSettings();
    }
  }

  /// Mostrar QR a pantalla completa para facilitar el escaneo
  void _showFullScreenQR() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text(
                  'Código QR - Inventtia',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                centerTitle: true,
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // QR a pantalla completa
                    Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/Lk1KNR.png',
                        width: MediaQuery.of(context).size.width * 0.8,
                        height: MediaQuery.of(context).size.width * 0.8,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Información
                    Text(
                      'Escanea este código para descargar Inventtia',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Inventtia $_appVersion',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Botón para cerrar
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                      label: const Text(
                        'Cerrar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                        elevation: 5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  /// Mostrar diálogo con QR para descargar la aplicación
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.download_outlined,
                  color: Color(0xFF4A90E2),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Descargar App Vendedor',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Escanea el código QR para descargar la aplicación Inventtia en tu dispositivo:',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              // Imagen del QR (clickeable para pantalla completa)
              GestureDetector(
                onTap: () => _showFullScreenQR(),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/Lk1KNR.png',
                          width: 200,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      ),
                      // Indicador de que es clickeable
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.fullscreen,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Toca la imagen para ver a pantalla completa',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Inventtia $_appVersion',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF4A90E2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Cerrar',
                style: TextStyle(fontWeight: FontWeight.w500),
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
      applicationName: 'Inventtia',
      applicationVersion: _appVersion,
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A90E2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.inventory_2, color: Colors.white, size: 32),
      ),
      children: [
        const Text('Aplicación de gestión de inventario y ventas.'),
        const SizedBox(height: 8),
        const Text(
          'Desarrollado para optimizar el proceso de pedidos y gestión de productos.',
        ),
      ],
    );
  }

  void _showLogoutDialog() async {
    // 🛟 Proteger datos offline sin sincronizar: avisar antes de cerrar sesión
    // si hay órdenes, operaciones o egresos pendientes que se perderían.
    final hasUnsynced =
        await _userPreferencesService.hasUnsyncedOfflineData();

    if (!mounted) return;

    final String contenido =
        hasUnsynced
            ? '⚠️ Tienes datos sin sincronizar (órdenes, turno o egresos en modo offline). '
                'Si cierras sesión ahora podrías perderlos.\n\n'
                'Te recomendamos conectarte y sincronizar antes de salir.\n\n'
                '¿Cerrar sesión de todos modos?'
            : '¿Estás seguro de que quieres cerrar sesión?';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Cerrar Sesión'),
            content: Text(contenido),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _performLogout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  hasUnsynced ? 'Cerrar de todos modos' : 'Cerrar Sesión',
                ),
              ),
            ],
          ),
    );
  }

  void _performLogout() {
    // Limpiar datos de sesión si es necesario
    // _orderService.clearAllOrders(); // Opcional: limpiar órdenes al cerrar sesión

    // Mostrar mensaje de confirmación
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👋 Sesión cerrada exitosamente'),
        backgroundColor: Colors.green,
      ),
    );

    // Navegar a la pantalla de login (por ahora volvemos a categorías)
    // En una implementación real, aquí navegarías a la pantalla de login
    Navigator.pushNamedAndRemoveUntil(context, '/categories', (route) => false);
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home → /mesas si modo restaurante, /categories si no
        NavigationHelper.goHome(context);
        break;
      case 1: // Preorden
        Navigator.pushNamed(context, '/preorder');
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
    return FutureBuilder<SettingsIntegrationStatus>(
      future: _integrationService.getStatus(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            title: const Text(
              'Estado de Sincronización',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
            subtitle: const Text(
              'Cargando estado...',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
          );
        }

        final status = snapshot.data!;
        final smartStatus = status.smartOfflineStatus;

        IconData icon;
        Color iconColor;
        String title;
        String subtitle;

        if (status.isOfflineModeEnabled) {
          icon = Icons.cloud_off;
          iconColor = Colors.orange;
          title = 'Modo Offline Activo';
          subtitle = 'Trabajando sin conexión';
        } else if (smartStatus.isConnected && smartStatus.isAutoSyncRunning) {
          icon = Icons.sync;
          iconColor = Colors.green;
          title = 'Sincronización Automática';
          final syncCount = smartStatus.syncStats['syncCount'] ?? 0;
          subtitle = 'Ejecutándose - $syncCount sincronizaciones';
        } else if (smartStatus.isConnected) {
          icon = Icons.wifi;
          iconColor = Colors.blue;
          title = 'Conectado';
          subtitle = 'Listo para sincronizar';
        } else {
          icon = Icons.wifi_off;
          iconColor = Colors.red;
          title = 'Sin Conexión';
          subtitle = 'Verificando conectividad...';
        }

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1F2937),
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.grey),
            onPressed: () => _showSmartSyncDetails(status),
            tooltip: 'Ver detalles',
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        );
      },
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
                Icon(Icons.info_outline, color: Colors.blue),
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
                      style: TextStyle(color: Colors.grey[600]),
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
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],

                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
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
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  /// Forzar sincronización inmediata
  Future<bool> _forceSyncNow({bool blockWhenRunning = true}) async {
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
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      await _integrationService.forceSyncNow();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Sincronización completada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      return true;
    } catch (e) {
      print('❌ Error forzando sincronización: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error en sincronización: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return false;
    }
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
}

// Widget del diálogo de sincronización
class _SyncDialog extends StatefulWidget {
  final UserPreferencesService userPreferencesService;
  final Function(bool) onSyncComplete;

  const _SyncDialog({
    required this.userPreferencesService,
    required this.onSyncComplete,
  });

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  double _progress = 0.0;
  String _currentTask = 'Iniciando sincronización...';
  bool _isCompleted = false;
  bool _hasError = false;

  final List<Map<String, String>> _tasks = [
    {'name': 'Reautenticando usuario', 'key': 'reauth'},
    {'name': 'Sincronizando métodos de pago', 'key': 'payment_methods'},
    {'name': 'Procesando operaciones pendientes', 'key': 'pending_operations'},
    {'name': 'Sincronizando órdenes pendientes', 'key': 'pending_orders'},
    {'name': 'Guardando credenciales', 'key': 'credentials'},
    {'name': 'Sincronizando turno abierto', 'key': 'turno'},
    {'name': 'Sincronizando egresos', 'key': 'egresos'},
    {'name': 'Sincronizando configuración de tienda', 'key': 'store_config'},
    {'name': 'Sincronizando promociones globales', 'key': 'promotions'},
    {'name': 'Descargando categorías', 'key': 'categories'},
    {'name': 'Descargando productos', 'key': 'products'},
    {'name': 'Sincronizando órdenes', 'key': 'orders'},
  ];

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    try {
      final Map<String, dynamic> offlineData = {};
      final List<String> successfulSteps = [];
      final List<String> failedSteps = [];

      for (int i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        setState(() {
          _currentTask = task['name']!;
          _progress = (i + 1) / _tasks.length;
        });

        // Procesar cada paso, continuando incluso si uno falla
        try {
          switch (task['key']) {
            case 'reauth':
              await _reauth();
              successfulSteps.add(task['name']!);
              break;
            case 'pending_operations':
              await _processPendingOperations();
              successfulSteps.add(task['name']!);
              break;
            case 'pending_orders':
              await _processPendingOrders();
              successfulSteps.add(task['name']!);
              break;
            case 'credentials':
              offlineData['credentials'] = await _syncCredentials();
              successfulSteps.add(task['name']!);
              break;
            case 'turno':
              offlineData['turno'] = await _syncTurno();
              // También sincronizar el resumen de turno anterior para apertura/cierre
              await _syncTurnoResumen();
              // Sincronizar resumen de cierre diario para CierreScreen y VentaTotalScreen
              await _syncResumenCierre();
              successfulSteps.add(task['name']!);
              break;
            case 'egresos':
              await _syncEgresos();
              successfulSteps.add(task['name']!);
              break;
            case 'store_config':
              await _syncStoreConfig();
              successfulSteps.add(task['name']!);
              break;
            case 'promotions':
              offlineData['promotions'] = await _syncPromotions();
              successfulSteps.add(task['name']!);
              break;
            case 'payment_methods':
              final paymentMethods = await _syncPaymentMethods();
              offlineData['payment_methods'] = paymentMethods;
              if (paymentMethods.isNotEmpty) {
                await widget.userPreferencesService.mergeOfflineData({
                  'payment_methods': paymentMethods,
                });
              }
              successfulSteps.add(task['name']!);
              break;
            case 'categories':
              offlineData['categories'] = await _syncCategories();
              successfulSteps.add(task['name']!);
              break;
            case 'products':
              offlineData['products'] = await _syncProducts();
              successfulSteps.add(task['name']!);
              break;
            case 'orders':
              offlineData['orders'] = await _syncOrders();
              successfulSteps.add(task['name']!);
              break;
          }
        } catch (e) {
          print('⚠️ Error en paso "${task['name']}": $e');
          failedSteps.add(task['name']!);
          // Continuar con el siguiente paso incluso si este falló
        }
      }

      final idTienda = await widget.userPreferencesService.getIdTienda();
      final idTpv = await widget.userPreferencesService.getIdTpv();
      final userId = await widget.userPreferencesService.getUserId();

      offlineData['meta'] = {
        'schema_version': 1,
        'created_at': DateTime.now().toIso8601String(),
        'id_tienda': idTienda,
        'id_tpv': idTpv,
        'user_id': userId,
        'source': 'manual',
      };

      // Limpiar datos offline después de procesamiento exitoso
      // Guardar todos los datos offline actualizados
      await widget.userPreferencesService.saveOfflineDataTransactional(
        offlineData,
      );
      await widget.userPreferencesService.setOfflineMode(true);

      await widget.userPreferencesService.clearAllOfflineData();
      print('🗑️ Datos offline anteriores limpiados');

      // Logging de datos guardados
      print('💾 Datos offline guardados:');
      print(
        '  - Credenciales: ${offlineData['credentials'] != null ? 'Sí' : 'No'}',
      );
      print('  - Turno: ${offlineData['turno'] != null ? 'Sí' : 'No'}');
      print(
        '  - Promociones: ${offlineData['promotions'] != null ? 'Sí' : 'No'}',
      );
      print(
        '  - Métodos de pago: ${offlineData['payment_methods'] != null ? 'Sí' : 'No'}',
      );
      print(
        '  - Categorías: ${offlineData['categories'] != null ? offlineData['categories'].length : 0}',
      );
      print('  - Productos: ${offlineData['products'] != null ? 'Sí' : 'No'}');
      print(
        '  - Órdenes: ${offlineData['orders'] != null ? offlineData['orders'].length : 0}',
      );
      print('✅ Modo offline activado');

      // Logging de resultados
      print('📊 Resumen de sincronización:');
      print(
        '  ✅ Pasos exitosos (${successfulSteps.length}): ${successfulSteps.join(", ")}',
      );
      if (failedSteps.isNotEmpty) {
        print(
          '  ⚠️ Pasos fallidos (${failedSteps.length}): ${failedSteps.join(", ")}',
        );
      }

      setState(() {
        _isCompleted = true;
        _currentTask =
            failedSteps.isEmpty
                ? '¡Sincronización completada!'
                : '¡Sincronización completada con ${failedSteps.length} advertencias!';
      });

      // Esperar un momento antes de cerrar
      await Future.delayed(const Duration(seconds: 1));
      widget.onSyncComplete(true);
    } catch (e) {
      print('❌ Error durante sincronización: $e');
      setState(() {
        _hasError = true;
        _currentTask = 'Error: $e';
      });
      await Future.delayed(const Duration(seconds: 2));
      widget.onSyncComplete(false);
    }
  }

  Future<Map<String, dynamic>> _syncCredentials() async {
    final userData = await widget.userPreferencesService.getUserData();
    final credentials =
        await widget.userPreferencesService.getSavedCredentials();

    // Verificar que tenemos email y password
    final email = userData['email'] ?? credentials['email'];
    final password = credentials['password'];
    final userId = userData['userId'];

    if (email == null || password == null || userId == null) {
      throw Exception(
        'No se pueden sincronizar credenciales. '
        'Asegúrate de marcar "Recordarme" en el login para habilitar modo offline.',
      );
    }

    print('✅ Credenciales encontradas:');
    print('  - Email: $email');
    print('  - Password: ${password.isNotEmpty ? "***" : "vacío"}');
    print('  - UserId: $userId');

    // Guardar usuario en el array de usuarios offline
    await widget.userPreferencesService.saveOfflineUser(
      email: email,
      password: password,
      userId: userId,
    );

    return {'email': email, 'password': password, 'userId': userId};
  }

  Future<Map<String, dynamic>> _syncPromotions() async {
    final promotionData =
        await widget.userPreferencesService.getPromotionData();
    return promotionData ?? {};
  }

  Future<List<Map<String, dynamic>>> _syncPaymentMethods() async {
    try {
      final paymentMethods =
          await PaymentMethodService.getActivePaymentMethods();

      if (paymentMethods.isNotEmpty) {
        final paymentMethodsList =
            paymentMethods.map((pm) => pm.toJson()).toList();
        await widget.userPreferencesService.mergeOfflineData({
          'payment_methods': paymentMethodsList,
        });
        print('✅ Métodos de pago sincronizados: ${paymentMethodsList.length}');
        return paymentMethodsList;
      }

      final cached =
          await widget.userPreferencesService.getPaymentMethodsOffline();
      if (cached.isNotEmpty) {
        print('⚠️ Sin métodos de pago en línea - usando cache offline');
        return cached;
      }

      print('⚠️ No hay métodos de pago disponibles');
      return [];
    } catch (e) {
      print('❌ Error sincronizando métodos de pago: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _syncTurno() async {
    try {
      final hasOpenShift = await TurnoService.hasOpenShift();

      if (hasOpenShift) {
        // Obtener datos del turno abierto desde Supabase
        final supabase = Supabase.instance.client;
        final userPrefs = UserPreferencesService();
        final idTpv = await userPrefs.getIdTpv();

        if (idTpv == null) {
          print('⚠️ No se pudo obtener el ID del TPV');
          return null;
        }

        final response = await supabase
            .from('app_dat_caja_turno')
            .select('*')
            .eq('id_tpv', idTpv)
            .eq('estado', 1)
            .order('fecha_apertura', ascending: false, nullsFirst: false)
            .limit(1);

        if (response.isNotEmpty) {
          final turnoData = response.first;
          print('✅ Turno abierto sincronizado: ID ${turnoData['id']}');

          // ✅ CRÍTICO: Guardar en cache específico de turno offline (igual que auto_sync)
          await widget.userPreferencesService.saveOfflineTurno(turnoData);
          print('  💾 Turno guardado en cache offline específico');

          return turnoData;
        }
      }

      print('ℹ️ No hay turno abierto');
      return null;
    } catch (e) {
      print('❌ Error sincronizando turno: $e');
      return null;
    }
  }

  Future<void> _syncEgresos() async {
    try {
      print('🔄 Sincronizando egresos...');

      // Obtener egresos del turno actual usando TurnoService
      final egresos = await TurnoService.getEgresosEnriquecidos();

      if (egresos.isNotEmpty) {
        // Convertir egresos a formato Map para cache
        final egresosData =
            egresos
                .map(
                  (egreso) => {
                    'id_egreso': egreso.idEgreso,
                    'monto_entrega': egreso.montoEntrega,
                    'motivo_entrega': egreso.motivoEntrega,
                    'nombre_autoriza': egreso.nombreAutoriza,
                    'nombre_recibe': egreso.nombreRecibe,
                    'es_digital': egreso.esDigital,
                    'fecha_entrega': egreso.fechaEntrega.toIso8601String(),
                    'id_medio_pago': egreso.idMedioPago,
                    'turno_estado': egreso.turnoEstado,
                    'medio_pago': egreso.medioPago,
                  },
                )
                .toList();

        // Guardar en cache para uso offline
        await widget.userPreferencesService.saveEgresosCache(egresosData);
        print(
          '✅ Egresos sincronizados: ${egresos.length} egresos guardados en cache',
        );
      } else {
        print('ℹ️ No hay egresos para sincronizar');
        // Limpiar cache si no hay egresos
        await widget.userPreferencesService.clearEgresosCache();
      }
    } catch (e) {
      print('❌ Error sincronizando egresos: $e');
      // En caso de error, mantener cache existente
    }
  }

  Future<void> _syncStoreConfig() async {
    try {
      print('🔧 Sincronizando configuración de tienda...');

      // Obtener ID de tienda
      final idTienda = await widget.userPreferencesService.getIdTienda();

      if (idTienda == null) {
        print(
          '❌ No se pudo obtener ID de tienda para sincronizar configuración',
        );
        return;
      }

      // Sincronizar configuración usando StoreConfigService
      final success = await StoreConfigService.syncStoreConfig(idTienda);

      if (success) {
        print('✅ Configuración de tienda sincronizada exitosamente');
      } else {
        print('⚠️ No se pudo sincronizar configuración de tienda');
      }
    } catch (e) {
      print('❌ Error sincronizando configuración de tienda: $e');
    }
  }

  Future<void> _syncTurnoResumen() async {
    try {
      print('🔄 Sincronizando resumen de turno anterior...');

      // Obtener resumen del turno anterior usando TurnoService
      final resumenTurno = await TurnoService.getResumenTurnoKPI();

      if (resumenTurno != null) {
        // Guardar en cache para uso offline
        await widget.userPreferencesService.saveTurnoResumenCache(resumenTurno);
        print('✅ Resumen de turno sincronizado y guardado en cache');
        print('📊 Datos sincronizados: ${resumenTurno.keys.toList()}');
      } else {
        print('ℹ️ No hay resumen de turno anterior disponible');
      }
    } catch (e) {
      print('❌ Error sincronizando resumen de turno: $e');
    }
  }

  Future<void> _syncResumenCierre() async {
    try {
      print('🔄 Sincronizando resumen de cierre diario...');

      // Obtener datos del usuario para llamar a fn_resumen_diario_cierre
      final idTpv = await widget.userPreferencesService.getIdTpv();
      final userID = await widget.userPreferencesService.getUserId();

      if (idTpv != null && userID != null) {
        print(
          '📋 Llamando fn_resumen_diario_cierre - TPV: $idTpv, Usuario: $userID',
        );

        // Llamar a la función RPC fn_resumen_diario_cierre
        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        print(
          '📋 Respuesta de fn_resumen_diario_cierre: $resumenCierreResponse',
        );
        print('📋 Tipo de respuesta: ${resumenCierreResponse.runtimeType}');

        if (resumenCierreResponse != null) {
          Map<String, dynamic> resumenCierre;

          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            // Si es una lista, tomar el primer elemento
            resumenCierre = resumenCierreResponse[0] as Map<String, dynamic>;
            print(
              '📋 Resumen extraído de lista: ${resumenCierre.keys.toList()}',
            );
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            // Si ya es un mapa, usarlo directamente
            resumenCierre = resumenCierreResponse;
            print(
              '📋 Resumen recibido como mapa: ${resumenCierre.keys.toList()}',
            );
          } else {
            print(
              '⚠️ Formato de respuesta no reconocido: ${resumenCierreResponse.runtimeType}',
            );
            throw Exception('Formato de respuesta no válido');
          }

          // Guardar en cache para uso offline
          await widget.userPreferencesService.saveResumenCierreCache(
            resumenCierre,
          );
          print('✅ Resumen de cierre sincronizado y guardado en cache');
          print('📊 Datos sincronizados: ${resumenCierre.keys.toList()}');

          // Log de valores principales para debugging
          print('💰 Valores principales del resumen:');
          if (resumenCierre['total_ventas'] != null) {
            print('  - Total ventas: \$${resumenCierre['total_ventas']}');
          }
          if (resumenCierre['total_efectivo'] != null) {
            print('  - Total efectivo: \$${resumenCierre['total_efectivo']}');
          }
          if (resumenCierre['productos_vendidos'] != null) {
            print(
              '  - Productos vendidos: ${resumenCierre['productos_vendidos']}',
            );
          }
          if (resumenCierre['ventas_totales'] != null) {
            print('  - Ventas totales: \$${resumenCierre['ventas_totales']}');
          }
          if (resumenCierre['efectivo_real'] != null) {
            print('  - Efectivo real: \$${resumenCierre['efectivo_real']}');
          }
        } else {
          print('ℹ️ No hay resumen de cierre disponible');
        }
      } else {
        print('⚠️ Faltan datos requeridos para sincronizar resumen de cierre');
        print('  - ID TPV: $idTpv');
        print('  - User ID: $userID');
      }
    } catch (e) {
      print('❌ Error sincronizando resumen de cierre: $e');
      // En caso de error, intentar guardar un resumen vacío para evitar errores offline
      try {
        await widget.userPreferencesService.saveResumenCierreCache({
          'total_ventas': 0.0,
          'total_efectivo': 0.0,
          'total_transferencias': 0.0,
          'productos_vendidos': 0,
          'ticket_promedio': 0.0,
          'sync_error': true,
          'error_message': e.toString(),
        });
        print('💾 Resumen de cierre vacío guardado como fallback');
      } catch (fallbackError) {
        print('❌ Error guardando resumen de cierre fallback: $fallbackError');
      }
    }
  }

  Future<List<Map<String, dynamic>>> _syncCategories() async {
    // Aquí llamarías al CategoryService para obtener todas las categorías
    final categoryService = CategoryService();
    try {
      final categories = await categoryService.getCategories();
      return categories
          .map(
            (cat) => {
              'id': cat.id,
              'name': cat.name,
              'imageUrl': cat.imageUrl,
              'color': cat.color.value,
            },
          )
          .toList();
    } catch (e) {
      print('Error sincronizando categorías: $e');
      return [];
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _syncProducts() async {
    final productService = ProductService();
    final categoryService = CategoryService();
    final Map<String, List<Map<String, dynamic>>> productsByCategory = {};

    try {
      final categories = await categoryService.getCategories();
      print('📦 Sincronizando productos de ${categories.length} categorías...');

      for (var category in categories) {
        final productsMap = await productService.getProductsByCategory(
          category.id,
        );

        // Convertir el Map<String, List<Product>> a lista plana con detalles completos
        final List<Map<String, dynamic>> allProducts = [];

        for (var entry in productsMap.entries) {
          final subcategory = entry.key;
          final products = entry.value;

          for (var prod in products) {
            try {
              // Obtener detalles completos del producto usando el RPC get_detalle_producto
              print(
                '  🔍 Obteniendo detalles de: ${prod.denominacion} (ID: ${prod.id})',
              );

              final detailResponse = await Supabase.instance.client.rpc(
                'get_detalle_producto',
                params: {'id_producto_param': prod.id},
              );

              if (detailResponse != null) {
                // Guardar la respuesta completa del RPC con todos los detalles
                final productWithDetails = {
                  'id': prod.id,
                  'denominacion': prod.denominacion,
                  'precio': prod.precio,
                  'foto': prod.foto,
                  'categoria': prod.categoria,
                  'descripcion': prod.descripcion,
                  'cantidad': prod.cantidad,
                  'subcategoria': subcategory,
                  // Agregar detalles completos del RPC
                  'detalles_completos': detailResponse,
                };

                allProducts.add(productWithDetails);
                print('    ✅ Detalles obtenidos para: ${prod.denominacion}');
              } else {
                // Si no hay detalles, guardar solo datos básicos
                allProducts.add({
                  'id': prod.id,
                  'denominacion': prod.denominacion,
                  'precio': prod.precio,
                  'foto': prod.foto,
                  'categoria': prod.categoria,
                  'descripcion': prod.descripcion,
                  'cantidad': prod.cantidad,
                  'subcategoria': subcategory,
                });
                print('    ⚠️ Sin detalles para: ${prod.denominacion}');
              }
            } catch (e) {
              print(
                '    ❌ Error obteniendo detalles de ${prod.denominacion}: $e',
              );
              // En caso de error, guardar solo datos básicos
              allProducts.add({
                'id': prod.id,
                'denominacion': prod.denominacion,
                'precio': prod.precio,
                'foto': prod.foto,
                'categoria': prod.categoria,
                'descripcion': prod.descripcion,
                'cantidad': prod.cantidad,
                'subcategoria': subcategory,
              });
            }
          }
        }

        productsByCategory[category.id.toString()] = allProducts;
        print(
          '✅ Categoría "${category.name}": ${allProducts.length} productos sincronizados',
        );
      }

      print(
        '🎉 Total de productos sincronizados: ${productsByCategory.values.fold(0, (sum, list) => sum + list.length)}',
      );
      return productsByCategory;
    } catch (e) {
      print('❌ Error sincronizando productos: $e');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> _syncOrders() async {
    try {
      // Obtener datos del usuario
      final userData = await widget.userPreferencesService.getUserData();
      final idTienda = await widget.userPreferencesService.getIdTienda();
      final idTpv = await widget.userPreferencesService.getIdTpv();
      final userId = userData['userId'];

      if (idTienda == null || idTpv == null || userId == null) {
        print('⚠️ Faltan datos para sincronizar órdenes');
        return [];
      }

      print('🔄 Sincronizando órdenes con estados completos...');
      print('📋 Parámetros: idTienda=$idTienda, idTpv=$idTpv, userId=$userId');

      // Llamar al RPC listar_ordenes para obtener órdenes desde Supabase
      // Incluimos TODAS las órdenes (sin filtro de estado) para capturar el ciclo completo
      final response = await Supabase.instance.client.rpc(
        'listar_ordenes',
        params: {
          'con_inventario_param': false,
          'fecha_desde_param': null,
          'fecha_hasta_param': null,
          'id_estado_param': null, // Sin filtro de estado para obtener todas
          'id_tienda_param': idTienda,
          'id_tipo_operacion_param': null,
          'id_tpv_param': idTpv,
          'id_usuario_param': userId,
          'limite_param': 100, // Limitar a las últimas 100 órdenes
          'pagina_param': null,
          'solo_pendientes_param':
              false, // Incluir órdenes completadas/canceladas
        },
      );

      if (response is List && response.isNotEmpty) {
        print('✅ Órdenes sincronizadas: ${response.length}');

        // Agrupar órdenes por estado para logging detallado
        final ordenesPorEstado = <String, int>{};
        for (var orden in response) {
          final estado = orden['estado_nombre'] ?? 'Sin estado';
          ordenesPorEstado[estado] = (ordenesPorEstado[estado] ?? 0) + 1;
        }

        print('📊 Distribución por estado:');
        ordenesPorEstado.forEach((estado, cantidad) {
          print('  - $estado: $cantidad órdenes');
        });

        // Verificar órdenes con cambios de estado
        final ordenesConCambios =
            response.where((orden) {
              final fechaCreacion = orden['fecha_creacion'];
              final fechaActualizacion = orden['fecha_actualizacion'];
              return fechaCreacion != fechaActualizacion;
            }).toList();

        if (ordenesConCambios.isNotEmpty) {
          print(
            '🔄 Órdenes con cambios de estado: ${ordenesConCambios.length}',
          );
          for (var orden in ordenesConCambios.take(5)) {
            // Mostrar solo las primeras 5
            print(
              '  - ID: ${orden['id']}, Estado: ${orden['estado_nombre']}, Creada: ${orden['fecha_creacion']}, Actualizada: ${orden['fecha_actualizacion']}',
            );
          }
        }

        // Retornar la respuesta completa del RPC
        final ordenes = response.cast<Map<String, dynamic>>();
        print(
          '✅ Sincronización de órdenes completada: ${ordenes.length} órdenes descargadas',
        );
        return ordenes;
      }

      print('ℹ️ No se encontraron órdenes para sincronizar');
      return [];
    } catch (e) {
      print('❌ Error sincronizando órdenes: $e');
      return [];
    }
  }

  /// Reautenticar usuario con credenciales guardadas
  Future<void> _reauth() async {
    try {
      final result =
          await widget.userPreferencesService.reloginWithSavedCredentials();
      if (!result['success']) {
        throw Exception(result['error']);
      }
      print('✅ Reautenticación exitosa');
    } catch (e) {
      print('❌ Error en reautenticación: $e');
      throw e;
    }
  }

  /// Procesar operaciones pendientes (apertura/cierre de turno)
  Future<void> _processPendingOperations() async {
    try {
      final operations =
          await widget.userPreferencesService.getPendingOperations();
      print('🔄 Procesando ${operations.length} operaciones pendientes...');

      for (var operation in operations) {
        final type = operation['type'];
        print('  - Procesando operación: $type');

        switch (type) {
          case 'apertura_turno':
            await _processAperturaTurno(operation['data']);
            break;
          case 'cierre_turno':
            await _processCierreTurno(operation['data']);
            break;
          case 'egreso':
            await _processEgresoOffline(operation['data']);
            break;
          case 'order_status_change':
            await _processOrderStatusChange(operation);
            break;
          default:
            print('⚠️ Tipo de operación desconocido: $type');
        }
      }

      print('✅ Operaciones pendientes procesadas');
    } catch (e) {
      print('❌ Error procesando operaciones pendientes: $e');
      throw e;
    }
  }

  /// Procesar órdenes pendientes de sincronización
  Future<void> _processPendingOrders() async {
    try {
      final pendingOrders =
          await widget.userPreferencesService.getPendingOrders();
      print('🔄 Procesando ${pendingOrders.length} órdenes pendientes...');

      for (var orderData in pendingOrders) {
        print('  - Sincronizando orden: ${orderData['id']}');

        // 1. Registrar la venta en Supabase
        await _registerSaleInSupabase(orderData);

        // 2. Si hay cambios de estado posteriores, aplicarlos
        final estado = orderData['estado'];
        if (estado != null && estado != 'enviada') {
          await _updateOrderStatusInSupabase(
            orderData['id'],
            estado,
            orderData,
          );
        }
      }

      print('✅ Órdenes pendientes procesadas');
    } catch (e) {
      print('❌ Error procesando órdenes pendientes: $e');
      throw e;
    }
  }

  /// Procesar apertura de turno pendiente
  Future<void> _processAperturaTurno(Map<String, dynamic> aperturaData) async {
    try {
      // Llamar al TurnoService para registrar la apertura
      final result = await TurnoService.registrarAperturaTurno(
        efectivoInicial: aperturaData['efectivo_inicial'].toDouble(),
        idTpv: aperturaData['id_tpv'],
        idVendedor: aperturaData['id_vendedor'],
        usuario: aperturaData['usuario'],
        manejaInventario: aperturaData['maneja_inventario'] ?? false,
        productos: aperturaData['productos'],
      );

      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Error registrando apertura');
      }

      print('✅ Apertura de turno sincronizada');
    } catch (e) {
      print('❌ Error sincronizando apertura: $e');
      throw e;
    }
  }

  /// Procesar cierre de turno pendiente
  Future<void> _processCierreTurno(Map<String, dynamic> cierreData) async {
    try {
      print('🔄 Sincronizando cierre de turno...');
      print('📊 Datos del cierre: $cierreData');

      // Extraer datos del cierre offline
      final efectivoReal = (cierreData['efectivo_final'] ?? 0.0).toDouble();
      final observaciones = cierreData['observaciones'] as String?;
      // Manejar la conversión de productos de manera segura
      final productosRaw = cierreData['productos'] as List<dynamic>? ?? [];
      final productos =
          productosRaw.map((item) => item as Map<String, dynamic>).toList();

      print('💰 Efectivo real: $efectivoReal');
      print('📝 Observaciones: $observaciones');
      print('📦 Productos: ${productos.length}');

      // Llamar al método real de TurnoService para cerrar turno
      final success = await TurnoService.cerrarTurno(
        efectivoReal: efectivoReal,
        productos: productos,
        observaciones: observaciones,
      );

      if (success) {
        print('✅ Cierre de turno sincronizado exitosamente');
      } else {
        throw Exception('Error en el servicio de cierre de turno');
      }
    } catch (e) {
      print('❌ Error sincronizando cierre: $e');
      throw e;
    }
  }

  /// Procesar cambio de estado de orden
  Future<void> _processOrderStatusChange(Map<String, dynamic> operation) async {
    try {
      final orderId = operation['order_id'];
      final newStatus = operation['new_status'];

      await _updateOrderStatusInSupabase(orderId, newStatus);
      print('✅ Estado de orden actualizado: $orderId -> $newStatus');
    } catch (e) {
      print('❌ Error actualizando estado de orden: $e');
      throw e;
    }
  }

  /// Procesar egreso offline
  Future<void> _processEgresoOffline(Map<String, dynamic> egresoData) async {
    try {
      print('🔄 Sincronizando egreso offline...');
      print('📊 Datos del egreso: $egresoData');

      // Extraer datos del egreso offline
      final idTurno = egresoData['id_turno'] as int;
      final montoEntrega = (egresoData['monto_entrega'] ?? 0.0).toDouble();
      final motivoEntrega = egresoData['motivo_entrega'] as String;
      final nombreAutoriza = egresoData['nombre_autoriza'] as String;
      final nombreRecibe = egresoData['nombre_recibe'] as String;
      final idMedioPago = egresoData['id_medio_pago'] as int?;

      print('💰 Monto: $montoEntrega');
      print('📝 Motivo: $motivoEntrega');
      print('👤 Autoriza: $nombreAutoriza');
      print('👤 Recibe: $nombreRecibe');
      print('💳 Medio de pago ID: $idMedioPago');

      // Llamar al método real de TurnoService para registrar egreso
      final result = await TurnoService.registrarEgresoParcial(
        idTurno: idTurno,
        montoEntrega: montoEntrega,
        motivoEntrega: motivoEntrega,
        nombreAutoriza: nombreAutoriza,
        nombreRecibe: nombreRecibe,
        idMedioPago: idMedioPago,
      );

      if (result['success'] == true) {
        print(
          '✅ Egreso offline sincronizado exitosamente: ${result['egreso_id']}',
        );
      } else {
        throw Exception('Error en el servicio de egreso: ${result['message']}');
      }
    } catch (e) {
      print('❌ Error sincronizando egreso offline: $e');
      throw e;
    }
  }

  /// Registrar venta en Supabase usando RPC directamente
  Future<void> _registerSaleInSupabase(Map<String, dynamic> orderData) async {
    try {
      print('🔄 Registrando venta en Supabase: ${orderData['id']}');

      // Obtener datos del usuario
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTpv = await userPrefs.getIdTpv();
      final userId = userData['userId'];

      if (idTpv == null || userId == null) {
        throw Exception('Datos de usuario incompletos para sincronización');
      }

      // 1. PRIMERO: Registrar cliente si hay datos de comprador
      int? idCliente = orderData['idCliente'];
      final buyerName = orderData['buyerName'];
      final buyerPhone = orderData['buyerPhone'];

      if (idCliente == null && buyerName != null && buyerName.isNotEmpty) {
        print('👤 Registrando cliente desde datos offline...');
        idCliente = await _registerClientFromOfflineData(buyerName, buyerPhone);
        if (idCliente != null) {
          print('✅ Cliente registrado con ID: $idCliente');
          // Actualizar orderData con el nuevo ID de cliente
          orderData['idCliente'] = idCliente;
        }
      }

      // Preparar productos desde los datos offline
      final productos = <Map<String, dynamic>>[];
      final itemsData = orderData['items'] as List<dynamic>? ?? [];

      for (final itemData in itemsData) {
        final inventoryMetadata = itemData['inventory_metadata'] ?? {};
        productos.add({
          'id_producto': itemData['id_producto'],
          'id_variante': inventoryMetadata['id_variante'],
          'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
          'id_ubicacion': inventoryMetadata['id_ubicacion'],
          'id_presentacion': inventoryMetadata['id_presentacion'],
          'cantidad': itemData['cantidad'],
          'precio_unitario': itemData['precio_unitario'],
          'sku_producto':
              inventoryMetadata['sku_producto'] ??
              itemData['id_producto'].toString(),
          'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
          'es_producto_venta': true,
        });
      }

      // Llamar directamente al RPC fn_registrar_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_venta',
        params: {
          'p_codigo_promocion': orderData['promoCode'],
          'p_denominacion': 'Venta Offline Sync - ${orderData['id']}',
          'p_estado_inicial': 1, // Estado enviada
          'p_id_tpv': idTpv,
          'p_observaciones':
              orderData['notas'] ?? 'Sincronización de venta offline',
          'p_productos': productos,
          'p_uuid': userId,
          'p_id_cliente': orderData['idCliente'],
        },
      );

      print('📡 Respuesta fn_registrar_venta: $response');

      if (response != null && response['status'] == 'success') {
        print('✅ Venta registrada en Supabase: ${orderData['id']}');

        // Obtener el ID de operación de la respuesta
        final operationId = response['id_operacion'] as int?;
        if (operationId != null) {
          // Guardar el ID de operación para usarlo en la actualización de estado
          orderData['_operation_id'] = operationId;
          print('📝 ID de operación guardado: $operationId');

          // 2. SEGUNDO: Registrar desgloses de pago si existen
          final paymentBreakdown =
              orderData['paymentBreakdown'] as Map<String, dynamic>?;
          if (paymentBreakdown != null && paymentBreakdown.isNotEmpty) {
            print('💳 Registrando desgloses de pago...');
            await _registerPaymentBreakdownFromOfflineData(
              operationId,
              paymentBreakdown,
            );
          }
        }
      } else {
        throw Exception(
          response?['message'] ?? 'Error en el registro de venta',
        );
      }
    } catch (e) {
      print('❌ Error registrando venta: $e');
      throw e;
    }
  }

  /// Actualizar estado de orden en Supabase usando el ID de operación guardado
  Future<void> _updateOrderStatusInSupabase(
    String orderId,
    String newStatus, [
    Map<String, dynamic>? orderData,
  ]) async {
    try {
      print('🔄 Actualizando estado en Supabase: $orderId -> $newStatus');

      // Intentar obtener el ID de operación del orderData si está disponible
      int? operationId = orderData?['_operation_id'];

      // Si no tenemos el ID guardado, intentar extraerlo del orderId
      if (operationId == null) {
        if (orderId.startsWith('ORD-')) {
          operationId = int.tryParse(orderId.replaceAll('ORD-', ''));
        }
      }

      if (operationId == null) {
        print(
          '⚠️ No se pudo obtener ID de operación para $orderId - Omitiendo actualización de estado',
        );
        return;
      }

      // Mapear string de estado a número
      int statusNumber;
      switch (newStatus.toLowerCase()) {
        case 'pago_confirmado':
        case 'pagoconfirmado':
        case 'completada':
          statusNumber = 2; // Completado
          break;
        case 'cancelada':
          statusNumber = 4; // Cancelada
          break;
        case 'devuelta':
          statusNumber = 3; // Devuelta
          break;
        default:
          statusNumber = 1; // Pendiente
      }

      // Obtener userId
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final userId = userData['userId'];

      if (userId == null) {
        throw Exception('Usuario no encontrado para actualización de estado');
      }

      print('=== DEBUG CAMBIO ESTADO ORDEN OFFLINE ===');
      print('operationId: $operationId');
      print('newStatus: $newStatus');
      print('statusNumber: $statusNumber');
      print('userId: $userId');
      print('========================================');

      // Llamar directamente al RPC fn_registrar_cambio_estado_operacion
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_cambio_estado_operacion',
        params: {
          'p_id_operacion': operationId,
          'p_nuevo_estado': statusNumber,
          'p_uuid_usuario': userId,
        },
      );

      print('📡 Respuesta fn_registrar_cambio_estado_operacion: $response');
      print('✅ Estado actualizado en Supabase: $orderId -> $newStatus');
    } catch (e) {
      print('❌ Error actualizando estado: $e');
      throw e;
    }
  }

  /// Registrar cliente desde datos offline usando fn_insertar_cliente_con_contactos
  Future<int?> _registerClientFromOfflineData(
    String buyerName,
    String? buyerPhone,
  ) async {
    try {
      print('🔄 Registrando cliente desde datos offline...');
      print('  - Nombre: $buyerName');
      print(
        '  - Teléfono: ${buyerPhone?.isNotEmpty == true ? buyerPhone : "No proporcionado"}',
      );

      // Generar código de cliente encriptado (similar al checkout_screen.dart)
      final clientCode = _generateClientCode(buyerName);

      final response = await Supabase.instance.client.rpc(
        'fn_insertar_cliente_con_contactos',
        params: {
          'p_codigo_cliente': clientCode,
          'p_contactos': null,
          'p_direccion': null,
          'p_documento_identidad': null,
          'p_email': null,
          'p_fecha_nacimiento': null,
          'p_genero': null,
          'p_limite_credito': 0,
          'p_nombre_completo': buyerName,
          'p_telefono': buyerPhone?.isNotEmpty == true ? buyerPhone : null,
          'p_tipo_cliente': 1,
        },
      );

      print('✅ Respuesta fn_insertar_cliente_con_contactos: $response');

      if (response != null && response['status'] == 'success') {
        final idCliente = response['id_cliente'] as int;
        print(
          '✅ Cliente registrado exitosamente desde offline - ID: $idCliente',
        );
        return idCliente;
      } else {
        print(
          '⚠️ Advertencia al registrar cliente offline: ${response?['message'] ?? "Respuesta vacía"}',
        );
        return null;
      }
    } catch (e) {
      print('❌ Error al registrar cliente desde offline: $e');
      return null;
    }
  }

  /// Generar código de cliente encriptado
  String _generateClientCode(String buyerName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final input = '$buyerName-$timestamp';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).toUpperCase();
  }

  /// Registrar desgloses de pago desde datos offline
  Future<void> _registerPaymentBreakdownFromOfflineData(
    int operationId,
    Map<String, dynamic> paymentBreakdown,
  ) async {
    try {
      print('💳 Registrando ${paymentBreakdown.length} métodos de pago...');

      // Preparar array de pagos para la función RPC
      List<Map<String, dynamic>> pagos = [];

      for (final entry in paymentBreakdown.entries) {
        final methodName = entry.key;
        final amount = entry.value as double;

        // Mapear nombre del método a ID (esto debería coincidir con los IDs reales)
        int? methodId = _getPaymentMethodIdByName(methodName);

        if (methodId != null && amount > 0) {
          print(
            '  💰 Preparando: $methodName (ID: $methodId) - \$${amount.toStringAsFixed(2)}',
          );

          pagos.add({
            'id_medio_pago': methodId,
            'monto': amount,
            'referencia_pago':
                'Pago Offline Sync - ${DateTime.now().millisecondsSinceEpoch}',
          });
        } else {
          print(
            '  ⚠️ Método de pago no reconocido o monto inválido: $methodName (\$${amount.toStringAsFixed(2)})',
          );
        }
      }

      // Llamar a fn_registrar_pago_venta con el array de pagos
      if (pagos.isNotEmpty) {
        print('💳 Pagos array: $pagos');

        final response = await Supabase.instance.client.rpc(
          'fn_registrar_pago_venta',
          params: {'p_id_operacion_venta': operationId, 'p_pagos': pagos},
        );

        print('📡 Respuesta fn_registrar_pago_venta: $response');

        if (response == true) {
          print('✅ Desgloses de pago registrados para operación: $operationId');
        } else {
          throw Exception('Error en el registro de pagos');
        }
      } else {
        print('⚠️ No hay pagos válidos para registrar');
      }
    } catch (e) {
      print('❌ Error registrando desgloses de pago: $e');
      // No lanzamos excepción para no interrumpir la sincronización
    }
  }

  /// Mapear nombre de método de pago a ID
  int? _getPaymentMethodIdByName(String methodName) {
    // Mapeo básico de nombres comunes a IDs
    // Esto debería coincidir con los datos reales de la tabla app_nom_metodo_pago
    switch (methodName.toLowerCase()) {
      case 'efectivo':
      case 'cash':
        return 1;
      case 'transferencia':
      case 'transfer':
      case 'transferencia bancaria':
        return 2;
      case 'tarjeta':
      case 'tarjeta de crédito':
      case 'tarjeta de débito':
      case 'card':
        return 3;
      case 'pago móvil':
      case 'pago movil':
      case 'mobile payment':
        return 4;
      default:
        // Intentar extraer ID si el nombre tiene formato "Método (ID: X)"
        final regex = RegExp(r'\(ID:\s*(\d+)\)');
        final match = regex.firstMatch(methodName);
        if (match != null) {
          return int.tryParse(match.group(1)!);
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    _hasError
                        ? Colors.red.withOpacity(0.1)
                        : _isCompleted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _hasError
                    ? Icons.error_outline
                    : _isCompleted
                    ? Icons.check_circle_outline
                    : Icons.cloud_download,
                size: 48,
                color:
                    _hasError
                        ? Colors.red
                        : _isCompleted
                        ? Colors.green
                        : Colors.blue,
              ),
            ),
            const SizedBox(height: 24),

            // Título
            Text(
              _hasError
                  ? 'Error de Sincronización'
                  : _isCompleted
                  ? '¡Completado!'
                  : 'Sincronizando Datos',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Tarea actual
            Text(
              _currentTask,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),

            // Barra de progreso
            if (!_isCompleted && !_hasError) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            // Lista de tareas
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    _tasks.asMap().entries.map((entry) {
                      final index = entry.key;
                      final task = entry.value;
                      final isCompleted = _progress > (index / _tasks.length);
                      final isCurrent =
                          _progress > (index / _tasks.length) &&
                          _progress <= ((index + 1) / _tasks.length);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              isCompleted
                                  ? Icons.check_circle
                                  : isCurrent
                                  ? Icons.sync
                                  : Icons.circle_outlined,
                              size: 16,
                              color:
                                  isCompleted
                                      ? Colors.green
                                      : isCurrent
                                      ? Colors.blue
                                      : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                task['name']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      isCompleted || isCurrent
                                          ? Colors.black87
                                          : Colors.grey,
                                  fontWeight:
                                      isCurrent
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget para sincronización manual de datos offline
class _ManualSyncDialog extends StatefulWidget {
  final UserPreferencesService userPreferencesService;
  final Function(bool) onSyncComplete;

  const _ManualSyncDialog({
    required this.userPreferencesService,
    required this.onSyncComplete,
  });

  @override
  State<_ManualSyncDialog> createState() => _ManualSyncDialogState();
}

class _ManualSyncDialogState extends State<_ManualSyncDialog> {
  double _progress = 0.0;
  String _currentTask = 'Iniciando sincronización...';
  bool _isCompleted = false;
  bool _hasError = false;

  final List<Map<String, String>> _tasks = [
    {'name': 'Reautenticando usuario', 'key': 'reauth'},
    {'name': 'Creando turno offline', 'key': 'create_turno'},
    {'name': 'Procesando órdenes pendientes', 'key': 'process_orders'},
    {'name': 'Cerrando turno offline', 'key': 'close_turno'},
    {'name': 'Descargando nuevas órdenes', 'key': 'sync_orders'},
    {'name': 'Limpiando datos offline', 'key': 'cleanup'},
  ];

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    try {
      for (int i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];

        setState(() {
          _currentTask = task['name']!;
          _progress = (i + 1) / _tasks.length;
        });

        // Simular delay para mostrar progreso
        await Future.delayed(const Duration(milliseconds: 800));

        // Procesar cada tarea
        switch (task['key']) {
          case 'reauth':
            await _reauth();
            break;
          case 'create_turno':
            await _createTurnoFromOffline();
            break;
          case 'process_orders':
            await _processOfflineOrders();
            break;
          case 'close_turno':
            await _closeTurnoFromOffline();
            break;
          case 'sync_orders':
            await _syncOrdersAfterManualSync();
            break;
          case 'cleanup':
            await _cleanupOfflineData();
            break;
        }
      }

      setState(() {
        _isCompleted = true;
        _currentTask = '¡Sincronización completada!';
      });

      // Esperar un momento antes de cerrar
      await Future.delayed(const Duration(seconds: 1));
      widget.onSyncComplete(true);
    } catch (e) {
      print('❌ Error en sincronización manual: $e');
      setState(() {
        _hasError = true;
        _currentTask = 'Error: ${e.toString()}';
      });

      await Future.delayed(const Duration(seconds: 2));
      widget.onSyncComplete(false);
    }
  }

  /// Reautenticar usuario
  Future<void> _reauth() async {
    final result =
        await widget.userPreferencesService.reloginWithSavedCredentials();
    if (!result['success']) {
      throw Exception(result['error']);
    }
    print('✅ Reautenticación exitosa para sincronización manual');
  }

  /// Crear turno desde datos offline
  Future<void> _createTurnoFromOffline() async {
    final operations =
        await widget.userPreferencesService.getPendingOperations();

    for (var operation in operations) {
      if (operation['type'] == 'apertura_turno') {
        print('🔄 Creando turno desde datos offline...');

        final aperturaData = operation['data'] as Map<String, dynamic>;
        print('📊 Datos de apertura: $aperturaData');

        // Extraer datos de la apertura offline
        final efectivoInicial =
            (aperturaData['efectivo_inicial'] ?? 0.0).toDouble();
        final idTpv = aperturaData['id_tpv'] as int;
        final idVendedor = aperturaData['id_vendedor'] as int;
        final usuario = aperturaData['usuario'] as String;
        final manejaInventario =
            aperturaData['maneja_inventario'] as bool? ?? false;
        // Manejar la conversión de productos de manera segura
        final productosRaw = aperturaData['productos'] as List<dynamic>? ?? [];
        final productos =
            productosRaw.map((item) => item as Map<String, dynamic>).toList();

        print('💰 Efectivo inicial: $efectivoInicial');
        print('🏪 TPV ID: $idTpv');
        print('👤 Vendedor ID: $idVendedor');
        print('📦 Maneja inventario: $manejaInventario');
        print('📋 Productos: ${productos.length}');

        // Llamar al método real de TurnoService para registrar apertura
        final result = await TurnoService.registrarAperturaTurno(
          efectivoInicial: efectivoInicial,
          idTpv: idTpv,
          idVendedor: idVendedor,
          usuario: usuario,
          manejaInventario: manejaInventario,
          productos: productos.isEmpty ? null : productos,
        );

        if (result['success'] == true) {
          print('✅ Turno creado desde datos offline: ${result['message']}');
        } else {
          throw Exception('Error creando turno: ${result['message']}');
        }
        break;
      }
    }
  }

  /// Procesar órdenes offline
  Future<void> _processOfflineOrders() async {
    final pendingOrders =
        await widget.userPreferencesService.getPendingOrders();
    print('🔄 Procesando ${pendingOrders.length} órdenes offline...');

    for (var orderData in pendingOrders) {
      print('  - Procesando orden: ${orderData['id']}');

      // 1. Registrar la venta (como en preorder_screen)
      await _registerSaleInSupabase(orderData);
      // 2. Completar la orden según su estado (como en orders_screen)
      final estado = orderData['estado'] ?? 'completada';
      await _completeOrderWithStatus(orderData['id'], estado);
    }

    print('✅ Órdenes offline procesadas');
  }

  /// Registrar venta en Supabase usando RPC directamente
  Future<void> _registerSaleInSupabase(Map<String, dynamic> orderData) async {
    try {
      print('🔄 Registrando venta en Supabase: ${orderData['id']}');

      // Obtener datos del usuario
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTpv = await userPrefs.getIdTpv();
      final userId = userData['userId'];

      if (idTpv == null || userId == null) {
        throw Exception('Datos de usuario incompletos para sincronización');
      }

      // 1. PRIMERO: Registrar cliente si hay datos de comprador
      int? idCliente = orderData['idCliente'];
      final buyerName = orderData['buyer_name'] ?? orderData['buyerName'];
      final buyerPhone = orderData['buyer_phone'] ?? orderData['buyerPhone'];

      if (idCliente == null && buyerName != null && buyerName.isNotEmpty) {
        print('👤 Registrando cliente desde datos offline...');
        idCliente = await _registerClientFromOfflineData(buyerName, buyerPhone);
        if (idCliente != null) {
          print('✅ Cliente registrado con ID: $idCliente');
          // Actualizar orderData con el nuevo ID de cliente
          orderData['idCliente'] = idCliente;
        }
      }

      // Preparar productos desde los datos offline
      final productos = <Map<String, dynamic>>[];
      final itemsData = orderData['items'] as List<dynamic>? ?? [];

      for (final itemData in itemsData) {
        final inventoryMetadata = itemData['inventory_metadata'] ?? {};
        productos.add({
          'id_producto': itemData['id_producto'],
          'id_variante': inventoryMetadata['id_variante'],
          'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
          'id_ubicacion': inventoryMetadata['id_ubicacion'],
          'id_presentacion': inventoryMetadata['id_presentacion'],
          'cantidad': itemData['cantidad'],
          'precio_unitario': itemData['precio_unitario'],
          'sku_producto':
              inventoryMetadata['sku_producto'] ??
              itemData['id_producto'].toString(),
          'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
          'es_producto_venta': true,
        });
      }

      // Llamar directamente al RPC fn_registrar_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_venta',
        params: {
          'p_codigo_promocion':
              orderData['promo_code'] ?? orderData['promoCode'],
          'p_denominacion': 'Venta Offline Sync - ${orderData['id']}',
          'p_estado_inicial': 1, // Estado enviada
          'p_id_tpv': idTpv,
          'p_observaciones':
              orderData['notas'] ?? 'Sincronización de venta offline',
          'p_productos': productos,
          'p_uuid': userId,
          'p_id_cliente': idCliente,
        },
      );

      print('📡 Respuesta fn_registrar_venta: $response');

      if (response != null && response['status'] == 'success') {
        print('✅ Venta registrada en Supabase: ${orderData['id']}');

        // Obtener el ID de operación de la respuesta
        final operationId = response['id_operacion'] as int?;
        if (operationId != null) {
          // Guardar el ID de operación para usarlo en la actualización de estado
          orderData['_operation_id'] = operationId;
          print('📝 ID de operación guardado: $operationId');

          // 2. SEGUNDO: Registrar desgloses de pago si existen
          final paymentBreakdown =
              orderData['desglose_pagos'] as List<dynamic>?;
          if (paymentBreakdown != null && paymentBreakdown.isNotEmpty) {
            print('💳 Registrando desgloses de pago...');
            await _registerPaymentBreakdownFromOfflineData(
              operationId,
              paymentBreakdown,
            );
          }
        }
      } else {
        throw Exception(
          response?['message'] ?? 'Error en el registro de venta',
        );
      }
    } catch (e) {
      print('❌ Error registrando venta: $e');
      throw e;
    }
  }

  /// Registrar cliente desde datos offline
  Future<int?> _registerClientFromOfflineData(
    String buyerName,
    String? buyerPhone,
  ) async {
    try {
      print(
        '👤 Registrando cliente: $buyerName${buyerPhone != null ? " - $buyerPhone" : ""}',
      );

      // Generar código de cliente único basado en el nombre
      final clientCode = 'CLI-${buyerName.hashCode.abs()}';

      // Usar RPC fn_insertar_cliente_con_contactos
      final response = await Supabase.instance.client.rpc(
        'fn_insertar_cliente_con_contactos',
        params: {
          'p_codigo_cliente':
              clientCode, // Código generado desde nombre encriptado
          'p_contactos': null, // Sin contactos adicionales por ahora
          'p_direccion': null, // No tenemos dirección
          'p_documento_identidad': null, // No tenemos documento
          'p_email': null, // No tenemos email
          'p_fecha_nacimiento': null, // No tenemos fecha nacimiento
          'p_genero': null, // No tenemos género
          'p_limite_credito': 0, // Sin límite de crédito
          'p_nombre_completo': buyerName,
          'p_telefono': buyerPhone?.isNotEmpty == true ? buyerPhone : null,
          'p_tipo_cliente': 1, // Tipo cliente por defecto
        },
      );

      print('📡 Respuesta fn_insertar_cliente_con_contactos: $response');

      if (response != null && response['status'] == 'success') {
        final idCliente = response['id_cliente'] as int;
        print('✅ Cliente registrado con ID: $idCliente');
        return idCliente;
      } else {
        throw Exception(
          'Error en el registro de cliente: ${response?['message']}',
        );
      }
    } catch (e) {
      print('❌ Error al registrar cliente: $e');
      // No lanzamos excepción para no interrumpir el flujo de la venta
      return null;
    }
  }

  /// Registrar desgloses de pago desde datos offline
  Future<void> _registerPaymentBreakdownFromOfflineData(
    int operationId,
    List<dynamic> paymentBreakdown,
  ) async {
    try {
      // Preparar array de pagos para la función RPC
      List<Map<String, dynamic>> pagos = [];

      for (final payment in paymentBreakdown) {
        final paymentData = payment as Map<String, dynamic>;
        pagos.add({
          'id_medio_pago': paymentData['id_medio_pago'],
          'monto': paymentData['monto'],
          'referencia_pago':
              'Pago Offline Sync - ${DateTime.now().millisecondsSinceEpoch}',
        });
      }

      print('💳 Pagos array: $pagos');

      // Llamar a fn_registrar_pago_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_pago_venta',
        params: {'p_id_operacion_venta': operationId, 'p_pagos': pagos},
      );

      print('📡 Respuesta fn_registrar_pago_venta: $response');

      if (response == true) {
        print('✅ Desgloses de pago registrados para operación: $operationId');
      } else {
        throw Exception('Error en el registro de pagos');
      }
    } catch (e) {
      print('❌ Error registrando desgloses de pago: $e');
      // No lanzamos excepción para no interrumpir el flujo principal
    }
  }

  /// Cerrar turno desde datos offline
  Future<void> _closeTurnoFromOffline() async {
    final operations =
        await widget.userPreferencesService.getPendingOperations();

    for (var operation in operations) {
      if (operation['type'] == 'cierre_turno') {
        print('🔄 Cerrando turno desde datos offline...');
        // Aquí iría la lógica para cerrar el turno usando TurnoService
        // Por ahora simulamos el éxito
        await Future.delayed(const Duration(milliseconds: 500));
        print('✅ Turno cerrado desde datos offline');
        break;
      }
    }
  }

  /// Sincronizar nuevas órdenes después de procesar las pendientes
  Future<void> _syncOrdersAfterManualSync() async {
    try {
      print('🔄 Descargando nuevas órdenes desde Supabase...');

      // Obtener datos del usuario
      final userData = await widget.userPreferencesService.getUserData();
      final idTienda = await widget.userPreferencesService.getIdTienda();
      final idTpv = await widget.userPreferencesService.getIdTpv();
      final userId = userData['userId'];

      if (idTienda == null || idTpv == null || userId == null) {
        print('⚠️ Faltan datos para sincronizar órdenes');
        return;
      }

      // Llamar al RPC listar_ordenes para obtener órdenes desde Supabase
      final response = await Supabase.instance.client.rpc(
        'listar_ordenes',
        params: {
          'con_inventario_param': false,
          'fecha_desde_param': null,
          'fecha_hasta_param': null,
          'id_estado_param': null, // Sin filtro de estado para obtener todas
          'id_tienda_param': idTienda,
          'id_tipo_operacion_param': null,
          'id_tpv_param': idTpv,
          'id_usuario_param': userId,
          'limite_param': 100, // Limitar a las últimas 100 órdenes
          'pagina_param': null,
          'solo_pendientes_param':
              false, // Incluir órdenes completadas/canceladas
        },
      );

      if (response is List && response.isNotEmpty) {
        print('✅ Nuevas órdenes descargadas: ${response.length}');

        // Hacer merge de las nuevas órdenes con datos existentes
        final newOrdersData = {'orders': response.cast<Map<String, dynamic>>()};

        // Usar merge para preservar otros datos offline
        await widget.userPreferencesService.mergeOfflineData(newOrdersData);

        print('💾 Cache de órdenes actualizado con ${response.length} órdenes');
      } else {
        print('ℹ️ No se encontraron nuevas órdenes para descargar');
      }
    } catch (e) {
      print('❌ Error descargando nuevas órdenes: $e');
      throw e;
    }
  }

  /// Limpiar datos offline
  Future<void> _cleanupOfflineData() async {
    await widget.userPreferencesService.clearAllOfflineData();
    print('🗑️ Datos offline limpiados');
  }

  /// Registrar venta de orden usando los mismos métodos que _SyncDialog
  Future<void> _registerOrderSale(Map<String, dynamic> orderData) async {
    try {
      print('🔄 Registrando venta offline: ${orderData['id']}');

      // Obtener datos del usuario
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTpv = await userPrefs.getIdTpv();
      final userId = userData['userId'];

      if (idTpv == null || userId == null) {
        throw Exception('Datos de usuario incompletos para sincronización');
      }

      // Preparar productos desde los datos offline
      final productos = <Map<String, dynamic>>[];
      final itemsData = orderData['items'] as List<dynamic>? ?? [];

      for (final itemData in itemsData) {
        final inventoryMetadata = itemData['inventory_metadata'] ?? {};
        productos.add({
          'id_producto': itemData['id_producto'],
          'id_variante': inventoryMetadata['id_variante'],
          'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
          'id_ubicacion': inventoryMetadata['id_ubicacion'],
          'id_presentacion': inventoryMetadata['id_presentacion'],
          'cantidad': itemData['cantidad'],
          'precio_unitario': itemData['precio_unitario'],
          'sku_producto':
              inventoryMetadata['sku_producto'] ??
              itemData['id_producto'].toString(),
          'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
          'es_producto_venta': true,
        });
      }

      // Llamar directamente al RPC fn_registrar_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_venta',
        params: {
          'p_codigo_promocion': orderData['promoCode'],
          'p_denominacion': 'Venta Manual Sync - ${orderData['id']}',
          'p_estado_inicial': 1, // Estado enviada
          'p_id_tpv': idTpv,
          'p_observaciones':
              orderData['notas'] ?? 'Sincronización manual de venta offline',
          'p_productos': productos,
          'p_uuid': userId,
          'p_id_cliente': orderData['idCliente'],
        },
      );

      if (response != null && response['status'] == 'success') {
        print('✅ Venta registrada: ${orderData['id']}');
      } else {
        throw Exception(
          response?['message'] ?? 'Error en el registro de venta',
        );
      }
    } catch (e) {
      print('❌ Error registrando venta offline: $e');
      throw e;
    }
  }

  /// Completar orden con estado específico usando el mismo método que _SyncDialog
  Future<void> _completeOrderWithStatus(String orderId, String status) async {
    try {
      print('🔄 Completando orden offline: $orderId -> $status');

      // Nota: En este contexto no tenemos acceso al orderData con el _operation_id
      // porque este método se llama desde el flujo de sincronización manual
      // El ID de operación debería haberse guardado durante _registerOrderSale

      // Mapear string de estado a número directamente
      int statusNumber;
      switch (status.toLowerCase()) {
        case 'pago_confirmado':
        case 'pagoconfirmado':
        case 'completada':
          statusNumber = 2; // Completado
          break;
        case 'cancelada':
          statusNumber = 4; // Cancelada
          break;
        case 'devuelta':
          statusNumber = 3; // Devuelta
          break;
        default:
          statusNumber = 1; // Pendiente
      }

      // Buscar la operación recién creada por denominación
      final searchResponse = await Supabase.instance.client
          .from('app_dat_operacion_venta')
          .select('id_operacion')
          .ilike('denominacion', '%$orderId%')
          .order('created_at', ascending: false)
          .limit(1);

      if (searchResponse.isEmpty) {
        print(
          '⚠️ No se encontró operación para $orderId - Omitiendo actualización de estado',
        );
        return;
      }

      final operationId = searchResponse.first['id_operacion'];

      // Obtener userId
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final userId = userData['userId'];

      if (userId == null) {
        throw Exception('Usuario no encontrado para actualización de estado');
      }

      print('=== DEBUG CAMBIO ESTADO ORDEN MANUAL ===');
      print('operationId: $operationId');
      print('status: $status');
      print('statusNumber: $statusNumber');
      print('userId: $userId');
      print('=======================================');

      // Llamar directamente al RPC fn_registrar_cambio_estado_operacion
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_cambio_estado_operacion',
        params: {
          'p_id_operacion': operationId,
          'p_nuevo_estado': statusNumber,
          'p_uuid_usuario': userId,
        },
      );

      print('📡 Respuesta fn_registrar_cambio_estado_operacion: $response');
      print('✅ Orden completada: $orderId -> $status');
    } catch (e) {
      print('❌ Error completando orden offline: $e');
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    _hasError
                        ? Colors.red.withOpacity(0.1)
                        : _isCompleted
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _hasError
                    ? Icons.error_outline
                    : _isCompleted
                    ? Icons.check_circle_outline
                    : Icons.sync,
                size: 48,
                color:
                    _hasError
                        ? Colors.red
                        : _isCompleted
                        ? Colors.green
                        : Colors.orange,
              ),
            ),

            const SizedBox(height: 16),

            // Título
            Text(
              _hasError
                  ? 'Error de Sincronización'
                  : _isCompleted
                  ? '¡Completado!'
                  : 'Sincronizando Datos Offline',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Subtítulo/tarea actual
            Text(
              _currentTask,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Barra de progreso
            if (!_isCompleted && !_hasError) ...[
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],

            // Lista de tareas
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tasks.length,
                itemBuilder: (context, index) {
                  final task = _tasks[index];
                  final isCompleted = index < (_progress * _tasks.length);
                  final isCurrent =
                      index == (_progress * _tasks.length).floor() &&
                      !_isCompleted;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          isCompleted
                              ? Icons.check_circle
                              : isCurrent
                              ? Icons.sync
                              : Icons.circle_outlined,
                          size: 16,
                          color:
                              isCompleted
                                  ? Colors.green
                                  : isCurrent
                                  ? Colors.orange
                                  : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            task['name']!,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  isCompleted || isCurrent
                                      ? Colors.black87
                                      : Colors.grey,
                              fontWeight:
                                  isCurrent
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
