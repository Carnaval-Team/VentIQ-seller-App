import 'dart:async';
import 'connectivity_service.dart';
import 'auto_sync_service.dart';
import 'user_preferences_service.dart';
import 'reauthentication_service.dart';
import 'network_request_queue.dart';

/// Gestor inteligente del modo offline
/// Coordina la activación automática del modo offline y la sincronización automática
/// basándose en el estado de conectividad
class SmartOfflineManager {
  static final SmartOfflineManager _instance = SmartOfflineManager._internal();
  factory SmartOfflineManager() => _instance;
  SmartOfflineManager._internal();

  final ConnectivityService _connectivityService = ConnectivityService();
  final AutoSyncService _autoSyncService = AutoSyncService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final ReauthenticationService _reauthService = ReauthenticationService();

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<ConnectivityEvent>? _connectivityEventSubscription;
  StreamSubscription<AutoSyncEvent>? _autoSyncEventSubscription;

  bool _isInitialized = false;
  bool _wasOfflineModeManuallyEnabled = false;
  DateTime? _lastAutoActivation;

  bool _connectionLostDialogPending = false;
  bool _connectionRestoredDialogPending = false;
  DateTime? _lastNetworkFailureReport;

  // Configuración
  static const Duration _connectionLostThreshold = Duration(
    seconds: 3,
  ); // Reducido de 10s a 3s para activación más rápida

  // Stream para notificar eventos del manager
  final StreamController<SmartOfflineEvent> _eventController =
      StreamController<SmartOfflineEvent>.broadcast();
  Stream<SmartOfflineEvent> get eventStream => _eventController.stream;

  /// Estado actual del manager
  bool get isInitialized => _isInitialized;
  DateTime? get lastAutoActivation => _lastAutoActivation;

  /// Inicializar el gestor inteligente
  Future<void> initialize() async {
    if (_isInitialized) {
      print('🧠 SmartOfflineManager ya está inicializado');
      return;
    }

    print('🚀 Inicializando SmartOfflineManager...');

    try {
      // Verificar estado inicial del modo offline
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();
      _wasOfflineModeManuallyEnabled = isOfflineModeEnabled;

      print('📊 Estado inicial:');
      print(
        '  - Modo offline: ${isOfflineModeEnabled ? "Activado" : "Desactivado"}',
      );

      // Iniciar monitoreo de conectividad
      await _connectivityService.startMonitoring();

      // Configurar listeners
      _setupConnectivityListeners();
      _setupAutoSyncListeners();

      // Decidir qué servicio iniciar basándose en el estado actual
      if (isOfflineModeEnabled) {
        print(
          '🔌 Modo offline activado - No iniciando sincronización automática',
        );
        _eventController.add(
          SmartOfflineEvent(
            type: SmartOfflineEventType.offlineModeActive,
            timestamp: DateTime.now(),
            message: 'Modo offline ya estaba activado',
          ),
        );
      } else {
        print('🌐 Modo online - Iniciando sincronización automática');
        await _autoSyncService.startAutoSync();
        _eventController.add(
          SmartOfflineEvent(
            type: SmartOfflineEventType.autoSyncStarted,
            timestamp: DateTime.now(),
            message: 'Sincronización automática iniciada',
          ),
        );
      }

      _isInitialized = true;

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.initialized,
          timestamp: DateTime.now(),
          message: 'SmartOfflineManager inicializado correctamente',
        ),
      );

      print('✅ SmartOfflineManager inicializado correctamente');
    } catch (e) {
      print('❌ Error inicializando SmartOfflineManager: $e');

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.error,
          timestamp: DateTime.now(),
          message: 'Error inicializando SmartOfflineManager: $e',
          error: e.toString(),
        ),
      );

      throw e;
    }
  }

  /// Configurar listeners de conectividad
  void _setupConnectivityListeners() {
    // Escuchar cambios de estado de conexión
    _connectivitySubscription = _connectivityService.connectionStatusStream
        .listen(
          _onConnectionStatusChanged,
          onError: (error) {
            print('❌ Error en stream de conectividad: $error');
          },
        );

    // Escuchar eventos detallados de conectividad
    _connectivityEventSubscription = _connectivityService
        .connectivityEventStream
        .listen(
          _onConnectivityEvent,
          onError: (error) {
            print('❌ Error en stream de eventos de conectividad: $error');
          },
        );
  }

  /// Configurar listeners de sincronización automática
  void _setupAutoSyncListeners() {
    _autoSyncEventSubscription = _autoSyncService.syncEventStream.listen(
      _onAutoSyncEvent,
      onError: (error) {
        print('❌ Error en stream de sincronización automática: $error');
      },
    );
  }

  /// Manejar cambios de estado de conexión
  Future<void> _onConnectionStatusChanged(bool isConnected) async {
    print(
      '🔄 Cambio de estado de conexión: ${isConnected ? "Conectado" : "Desconectado"}',
    );

    if (!isConnected) {
      await _handleConnectionLost();
    } else {
      await _handleConnectionRestored();
    }
  }

  /// Manejar eventos detallados de conectividad
  Future<void> _onConnectivityEvent(ConnectivityEvent event) async {
    print('📡 Evento de conectividad: ${event.type} - ${event.reason}');

    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.connectivityChanged,
        timestamp: event.timestamp,
        message: event.reason,
        connectivityEvent: event,
      ),
    );
  }

  /// Manejar eventos de sincronización automática
  void _onAutoSyncEvent(AutoSyncEvent event) {
    print('🔄 Evento de sincronización: ${event.type} - ${event.message}');

    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.autoSyncEvent,
        timestamp: event.timestamp,
        message: event.message,
        autoSyncEvent: event,
      ),
    );
  }

  /// Manejar pérdida de conexión
  Future<void> _handleConnectionLost() async {
    print('📵 Manejando pérdida de conexión...');

    // Verificar si el modo offline ya está activado manualmente
    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();

    if (isOfflineModeEnabled) {
      print('🔌 Modo offline ya está activado - No se requiere acción');
      return;
    }

    if (_connectionLostDialogPending) {
      print('⚠️ Diálogo de pérdida ya pendiente - omitiendo');
      return;
    }

    // Esperar un poco para confirmar que la conexión realmente se perdió
    print(
      '⏳ Esperando ${_connectionLostThreshold.inSeconds}s para confirmar pérdida de conexión...',
    );
    await Future.delayed(_connectionLostThreshold);

    // Verificar nuevamente el estado de conexión
    print('🔍 Verificando estado de conexión después del threshold...');
    final isStillDisconnected = !_connectivityService.isConnected;

    if (isStillDisconnected) {
      // Verificación adicional: intentar hacer una petición real
      print('🌐 Haciendo verificación adicional de conectividad real...');
      final hasRealConnection = await _connectivityService.checkConnectivity();

      if (!hasRealConnection) {
        print(
          '🚨 Conexión perdida confirmada - Solicitando confirmación al usuario',
        );
        _emitConnectionLostPendingConfirmation();
      } else {
        print(
          '✅ Conexión real detectada en verificación adicional - No solicitando confirmación',
        );
      }
    } else {
      print(
        '📶 Conexión restaurada durante verificación - No solicitando confirmación',
      );
    }
  }

  void _emitConnectionLostPendingConfirmation() {
    _connectionLostDialogPending = true;
    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.connectionLostPendingConfirmation,
        timestamp: DateTime.now(),
        message: 'Pérdida de conexión - esperando decisión del usuario',
      ),
    );
  }

  void _emitConnectionRestoredPendingConfirmation() {
    _connectionRestoredDialogPending = true;
    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.connectionRestoredPendingConfirmation,
        timestamp: DateTime.now(),
        message: 'Conexión restaurada - esperando decisión del usuario',
      ),
    );
  }

  /// Reportar fallo de red detectado por una petición real (interceptor).
  Future<void> reportNetworkFailure(String description, Object error) async {
    print('🚨 reportNetworkFailure: "$description" → $error');

    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();
    if (isOfflineModeEnabled) {
      print('🔌 Ya en modo offline - no se solicita confirmación');
      return;
    }

    if (_connectionLostDialogPending) {
      print('⚠️ Diálogo de pérdida ya pendiente');
      return;
    }

    // Debounce: no spamear el ping de verificación
    final now = DateTime.now();
    if (_lastNetworkFailureReport != null &&
        now.difference(_lastNetworkFailureReport!).inSeconds < 2) {
      print('⏳ Debounce activo en reportNetworkFailure');
      return;
    }
    _lastNetworkFailureReport = now;

    final hasRealConnection =
        await _connectivityService.performImmediateCheck();

    if (!hasRealConnection) {
      print(
        '🚨 Confirmado sin internet por interceptor - Solicitando confirmación',
      );
      _emitConnectionLostPendingConfirmation();
    } else {
      print(
        '✅ Internet OK pese al fallo reportado - probablemente error puntual',
      );
    }
  }

  /// Usuario presionó "Reintentar" en el diálogo de pérdida de conexión.
  /// Retorna true si la conexión se restauró exitosamente.
  Future<bool> userChoseRetry() async {
    print('👤 Usuario eligió Reintentar');
    final hasConnection = await _connectivityService.performImmediateCheck();

    if (hasConnection) {
      print('✅ Conexión confirmada al reintentar - reintentando cola');
      _connectionLostDialogPending = false;
      _lastNetworkFailureReport = null;
      await NetworkRequestQueue().retryAll();

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.connectionConfirmedOnline,
          timestamp: DateTime.now(),
          message: 'Conexión confirmada por reintento del usuario',
        ),
      );
      return true;
    }

    print('❌ Reintento falló - sigue sin conexión');
    return false;
  }

  /// Usuario presionó "Modo Offline" en el diálogo de pérdida de conexión.
  Future<void> userChoseOffline() async {
    print('👤 Usuario eligió Modo Offline');
    _connectionLostDialogPending = false;

    NetworkRequestQueue().rejectAll(
      Exception('Usuario eligió modo offline'),
    );

    await _activateOfflineModeAutomatically();
  }

  /// Usuario presionó "Activar Modo Online" en el diálogo de restauración.
  Future<void> userChoseGoOnline() async {
    print('👤 Usuario eligió Activar Modo Online');
    _connectionRestoredDialogPending = false;

    try {
      await _userPreferencesService.setOfflineMode(false);
      _wasOfflineModeManuallyEnabled = false;

      // Reautenticar si es necesario
      try {
        final needsReauth = await _reauthService.needsReauthentication();
        if (needsReauth) {
          await _reauthService.reauthenticateUser();
        }
      } catch (e) {
        print('⚠️ Error reautenticando tras volver online: $e');
      }

      if (!_autoSyncService.isRunning) {
        await _autoSyncService.startAutoSync();
      }

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.offlineModeAutoDeactivated,
          timestamp: DateTime.now(),
          message: 'Modo offline desactivado por el usuario',
        ),
      );
    } catch (e) {
      print('❌ Error activando modo online: $e');
      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.error,
          timestamp: DateTime.now(),
          message: 'Error activando modo online: $e',
          error: e.toString(),
        ),
      );
    }
  }

  /// Usuario presionó "Continuar Offline" en el diálogo de restauración.
  Future<void> userChoseStayOffline() async {
    print('👤 Usuario eligió Continuar Offline');
    _connectionRestoredDialogPending = false;
    _wasOfflineModeManuallyEnabled = true;

    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.offlineModeManuallyEnabled,
        timestamp: DateTime.now(),
        message: 'Usuario decidió mantener modo offline',
      ),
    );
  }

  /// Manejar restauración de conexión
  Future<void> _handleConnectionRestored() async {
    print('📶 Manejando restauración de conexión...');

    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();

    if (!isOfflineModeEnabled) {
      // El modo offline no está activado - reautenticar y sincronizar
      print('🔐 Verificando autenticación tras restauración de conexión...');

      try {
        // Verificar si necesita reautenticación
        final needsReauth = await _reauthService.needsReauthentication();

        if (needsReauth) {
          print('🔄 Reautenticando usuario automáticamente...');

          _eventController.add(
            SmartOfflineEvent(
              type: SmartOfflineEventType.reauthenticationStarted,
              timestamp: DateTime.now(),
              message:
                  'Iniciando reautenticación automática tras restauración de conexión',
            ),
          );

          final reauthSuccess = await _reauthService.reauthenticateUser();

          if (reauthSuccess) {
            print('✅ Reautenticación exitosa');

            _eventController.add(
              SmartOfflineEvent(
                type: SmartOfflineEventType.reauthenticationSuccess,
                timestamp: DateTime.now(),
                message: 'Reautenticación automática completada exitosamente',
              ),
            );
          } else {
            print('❌ Error en reautenticación automática');

            _eventController.add(
              SmartOfflineEvent(
                type: SmartOfflineEventType.reauthenticationFailed,
                timestamp: DateTime.now(),
                message:
                    'Error en reautenticación automática - Puede requerir login manual',
              ),
            );

            // No bloquear la sincronización por error de reautenticación
            // El usuario puede seguir trabajando con datos locales
          }
        } else {
          print('✅ Usuario ya autenticado correctamente');
        }

        // Iniciar sincronización automática si no está corriendo
        if (!_autoSyncService.isRunning) {
          print(
            '🔄 Iniciando sincronización automática tras restauración de conexión',
          );
          await _autoSyncService.startAutoSync();

          _eventController.add(
            SmartOfflineEvent(
              type: SmartOfflineEventType.autoSyncStarted,
              timestamp: DateTime.now(),
              message:
                  'Sincronización automática iniciada tras restauración de conexión',
            ),
          );
        }
      } catch (e) {
        print('❌ Error en proceso de restauración de conexión: $e');

        _eventController.add(
          SmartOfflineEvent(
            type: SmartOfflineEventType.error,
            timestamp: DateTime.now(),
            message: 'Error en restauración de conexión: $e',
            error: e.toString(),
          ),
        );

        // Intentar iniciar sincronización de todos modos
        if (!_autoSyncService.isRunning) {
          try {
            await _autoSyncService.startAutoSync();
          } catch (syncError) {
            print(
              '❌ Error iniciando sincronización tras error de reautenticación: $syncError',
            );
          }
        }
      }
    } else {
      print(
        '🔌 Modo offline activado - Solicitando confirmación al usuario...',
      );

      if (_connectionRestoredDialogPending) {
        print('⚠️ Diálogo de restauración ya pendiente - omitiendo');
        return;
      }

      _emitConnectionRestoredPendingConfirmation();
    }
  }

  /// Activar modo offline automáticamente
  Future<void> _activateOfflineModeAutomatically() async {
    try {
      print('🔌 Activando modo offline automáticamente...');

      // Verificar que tenemos datos offline disponibles
      final hasOfflineData = await _userPreferencesService.hasOfflineData();

      if (!hasOfflineData) {
        print(
          '⚠️ No hay datos offline disponibles - No se puede activar modo offline automáticamente',
        );

        _eventController.add(
          SmartOfflineEvent(
            type: SmartOfflineEventType.autoActivationFailed,
            timestamp: DateTime.now(),
            message:
                'No hay datos offline disponibles para activación automática',
          ),
        );

        return;
      }

      // Detener sincronización automática
      await _autoSyncService.stopAutoSync();

      // Activar modo offline
      await _userPreferencesService.setOfflineMode(true);

      _lastAutoActivation = DateTime.now();
      _wasOfflineModeManuallyEnabled = false; // Fue activado automáticamente

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.offlineModeAutoActivated,
          timestamp: _lastAutoActivation!,
          message:
              'Modo offline activado automáticamente por pérdida de conexión',
        ),
      );

      print('✅ Modo offline activado automáticamente');
    } catch (e) {
      print('❌ Error activando modo offline automáticamente: $e');

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.autoActivationFailed,
          timestamp: DateTime.now(),
          message: 'Error activando modo offline automáticamente: $e',
          error: e.toString(),
        ),
      );
    }
  }

  /// Manejar activación manual del modo offline
  Future<void> onOfflineModeManuallyEnabled() async {
    print('👤 Modo offline activado manualmente por el usuario');

    _wasOfflineModeManuallyEnabled = true;

    // Detener sincronización automática
    await _autoSyncService.stopAutoSync();

    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.offlineModeManuallyEnabled,
        timestamp: DateTime.now(),
        message: 'Modo offline activado manualmente por el usuario',
      ),
    );
  }

  /// Manejar desactivación manual del modo offline
  Future<void> onOfflineModeManuallyDisabled() async {
    print('👤 Modo offline desactivado manualmente por el usuario');

    _wasOfflineModeManuallyEnabled = false;

    // Si hay conexión, iniciar sincronización automática
    if (_connectivityService.isConnected) {
      print('📶 Hay conexión - Iniciando sincronización automática');
      await _autoSyncService.startAutoSync();

      _eventController.add(
        SmartOfflineEvent(
          type: SmartOfflineEventType.autoSyncStarted,
          timestamp: DateTime.now(),
          message:
              'Sincronización automática iniciada tras desactivación manual del modo offline',
        ),
      );
    } else {
      print('📵 Sin conexión - No iniciando sincronización automática');
    }

    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.offlineModeManuallyDisabled,
        timestamp: DateTime.now(),
        message: 'Modo offline desactivado manualmente por el usuario',
      ),
    );
  }

  /// Obtener estado actual del manager
  Future<SmartOfflineStatus> getStatus() async {
    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();
    final connectivityInfo = await _connectivityService.getConnectivityInfo();
    final syncStats = _autoSyncService.getSyncStats();

    return SmartOfflineStatus(
      isInitialized: _isInitialized,
      isConnected: _connectivityService.isConnected,
      isOfflineModeEnabled: isOfflineModeEnabled,
      wasOfflineModeManuallyEnabled: _wasOfflineModeManuallyEnabled,
      isAutoSyncRunning: _autoSyncService.isRunning,
      lastAutoActivation: _lastAutoActivation,
      connectivityInfo: connectivityInfo,
      syncStats: syncStats,
    );
  }

  /// Detener el gestor inteligente
  Future<void> stop() async {
    if (!_isInitialized) return;

    print('🛑 Deteniendo SmartOfflineManager...');

    await _connectivitySubscription?.cancel();
    await _connectivityEventSubscription?.cancel();
    await _autoSyncEventSubscription?.cancel();

    await _connectivityService.stopMonitoring();
    await _autoSyncService.stopAutoSync();

    _isInitialized = false;

    _eventController.add(
      SmartOfflineEvent(
        type: SmartOfflineEventType.stopped,
        timestamp: DateTime.now(),
        message: 'SmartOfflineManager detenido',
      ),
    );

    print('✅ SmartOfflineManager detenido');
  }

  /// Limpiar recursos
  void dispose() {
    stop();
    _eventController.close();
    _connectivityService.dispose();
    _autoSyncService.dispose();
  }
}

/// Tipos de eventos del gestor inteligente
enum SmartOfflineEventType {
  initialized,
  stopped,
  connectivityChanged,
  offlineModeActive,
  offlineModeAutoActivated,
  offlineModeAutoDeactivated,
  offlineModeManuallyEnabled,
  offlineModeManuallyDisabled,
  autoActivationFailed,
  connectionRestoredWhileOffline,
  connectionLostPendingConfirmation,
  connectionRestoredPendingConfirmation,
  connectionConfirmedOnline,
  autoSyncStarted,
  autoSyncEvent,
  reauthenticationStarted,
  reauthenticationSuccess,
  reauthenticationFailed,
  error,
}

/// Evento del gestor inteligente
class SmartOfflineEvent {
  final SmartOfflineEventType type;
  final DateTime timestamp;
  final String message;
  final String? error;
  final ConnectivityEvent? connectivityEvent;
  final AutoSyncEvent? autoSyncEvent;

  SmartOfflineEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.error,
    this.connectivityEvent,
    this.autoSyncEvent,
  });

  @override
  String toString() {
    return 'SmartOfflineEvent(type: $type, timestamp: $timestamp, message: $message, error: $error)';
  }
}

/// Estado del gestor inteligente
class SmartOfflineStatus {
  final bool isInitialized;
  final bool isConnected;
  final bool isOfflineModeEnabled;
  final bool wasOfflineModeManuallyEnabled;
  final bool isAutoSyncRunning;
  final DateTime? lastAutoActivation;
  final ConnectivityInfo connectivityInfo;
  final Map<String, dynamic> syncStats;

  SmartOfflineStatus({
    required this.isInitialized,
    required this.isConnected,
    required this.isOfflineModeEnabled,
    required this.wasOfflineModeManuallyEnabled,
    required this.isAutoSyncRunning,
    this.lastAutoActivation,
    required this.connectivityInfo,
    required this.syncStats,
  });

  @override
  String toString() {
    return 'SmartOfflineStatus(isInitialized: $isInitialized, isConnected: $isConnected, isOfflineModeEnabled: $isOfflineModeEnabled, wasOfflineModeManuallyEnabled: $wasOfflineModeManuallyEnabled, isAutoSyncRunning: $isAutoSyncRunning)';
  }
}
