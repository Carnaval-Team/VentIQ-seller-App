import 'dart:async';
import 'connectivity_service.dart';
import 'auto_sync_service.dart';
import 'user_preferences_service.dart';
import 'reauthentication_service.dart';

/// Gestor inteligente del modo offline
/// Coordina la activación automática del modo offline y la sincronización automática
/// basándose en el estado de conectividad
class SmartOfflineManager {
  static final SmartOfflineManager _instance = SmartOfflineManager._internal();
  factory SmartOfflineManager() => _instance;
  SmartOfflineManager._internal();

  final ConnectivityService _connectivityService = ConnectivityService();
  final AutoSyncService _autoSyncService = AutoSyncService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final ReauthenticationService _reauthService = ReauthenticationService();
  
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<ConnectivityEvent>? _connectivityEventSubscription;
  StreamSubscription<AutoSyncEvent>? _autoSyncEventSubscription;
  
  bool _isInitialized = false;
  bool _wasOfflineModeManuallyEnabled = false;
  DateTime? _lastAutoActivation;
  
  // Configuración
  static const Duration _connectionLostThreshold = Duration(seconds: 10);
  static const Duration _autoActivationCooldown = Duration(minutes: 5);
  
  // Stream para notificar eventos del manager
  final StreamController<SmartOfflineEvent> _eventController = StreamController<SmartOfflineEvent>.broadcast();
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
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      _wasOfflineModeManuallyEnabled = isOfflineModeEnabled;
      
      print('📊 Estado inicial:');
      print('  - Modo offline: ${isOfflineModeEnabled ? "Activado" : "Desactivado"}');
      
      // Iniciar monitoreo de conectividad
      await _connectivityService.startMonitoring();
      
      // Configurar listeners
      _setupConnectivityListeners();
      _setupAutoSyncListeners();
      
      // Decidir qué servicio iniciar basándose en el estado actual
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - No iniciando sincronización automática');
        _eventController.add(SmartOfflineEvent(
          type: SmartOfflineEventType.offlineModeActive,
          timestamp: DateTime.now(),
          message: 'Modo offline ya estaba activado',
        ));
      } else {
        print('🌐 Modo online - Iniciando sincronización automática');
        await _autoSyncService.startAutoSync();
        _eventController.add(SmartOfflineEvent(
          type: SmartOfflineEventType.autoSyncStarted,
          timestamp: DateTime.now(),
          message: 'Sincronización automática iniciada',
        ));
      }
      
      _isInitialized = true;
      
      _eventController.add(SmartOfflineEvent(
        type: SmartOfflineEventType.initialized,
        timestamp: DateTime.now(),
        message: 'SmartOfflineManager inicializado correctamente',
      ));
      
      print('✅ SmartOfflineManager inicializado correctamente');
      
    } catch (e) {
      print('❌ Error inicializando SmartOfflineManager: $e');
      
      _eventController.add(SmartOfflineEvent(
        type: SmartOfflineEventType.error,
        timestamp: DateTime.now(),
        message: 'Error inicializando SmartOfflineManager: $e',
        error: e.toString(),
      ));
      
      throw e;
    }
  }

  /// Configurar listeners de conectividad
  void _setupConnectivityListeners() {
    // Escuchar cambios de estado de conexión
    _connectivitySubscription = _connectivityService.connectionStatusStream.listen(
      _onConnectionStatusChanged,
      onError: (error) {
        print('❌ Error en stream de conectividad: $error');
      },
    );
    
    // Escuchar eventos detallados de conectividad
    _connectivityEventSubscription = _connectivityService.connectivityEventStream.listen(
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
    print('🔄 Cambio de estado de conexión: ${isConnected ? "Conectado" : "Desconectado"}');
    
    if (!isConnected) {
      await _handleConnectionLost();
    } else {
      await _handleConnectionRestored();
    }
  }

  /// Manejar eventos detallados de conectividad
  Future<void> _onConnectivityEvent(ConnectivityEvent event) async {
    print('📡 Evento de conectividad: ${event.type} - ${event.reason}');
    
    _eventController.add(SmartOfflineEvent(
      type: SmartOfflineEventType.connectivityChanged,
      timestamp: event.timestamp,
      message: event.reason,
      connectivityEvent: event,
    ));
  }

  /// Manejar eventos de sincronización automática
  void _onAutoSyncEvent(AutoSyncEvent event) {
    print('🔄 Evento de sincronización: ${event.type} - ${event.message}');
    
    _eventController.add(SmartOfflineEvent(
      type: SmartOfflineEventType.autoSyncEvent,
      timestamp: event.timestamp,
      message: event.message,
      autoSyncEvent: event,
    ));
  }

  /// Manejar pérdida de conexión
  Future<void> _handleConnectionLost() async {
    print('📵 Manejando pérdida de conexión...');
    
    // Verificar si el modo offline ya está activado manualmente
    final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
    
    if (isOfflineModeEnabled) {
      print('🔌 Modo offline ya está activado - No se requiere acción');
      return;
    }
    
    // Verificar cooldown para evitar activaciones muy frecuentes
    if (_lastAutoActivation != null) {
      final timeSinceLastActivation = DateTime.now().difference(_lastAutoActivation!);
      if (timeSinceLastActivation < _autoActivationCooldown) {
        print('⏳ Cooldown activo - No activando modo offline automáticamente');
        return;
      }
    }
    
    // Esperar un poco para confirmar que la conexión realmente se perdió
    await Future.delayed(_connectionLostThreshold);
    
    // Verificar nuevamente el estado de conexión
    final isStillDisconnected = !_connectivityService.isConnected;
    
    if (isStillDisconnected) {
      print('🚨 Conexión perdida confirmada - Activando modo offline automáticamente');
      await _activateOfflineModeAutomatically();
    } else {
      print('📶 Conexión restaurada durante verificación - No activando modo offline');
    }
  }

  /// Manejar restauración de conexión
  Future<void> _handleConnectionRestored() async {
    print('📶 Manejando restauración de conexión...');
    
    final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
    
    if (!isOfflineModeEnabled) {
      // El modo offline no está activado - reautenticar y sincronizar
      print('🔐 Verificando autenticación tras restauración de conexión...');
      
      try {
        // Verificar si necesita reautenticación
        final needsReauth = await _reauthService.needsReauthentication();
        
        if (needsReauth) {
          print('🔄 Reautenticando usuario automáticamente...');
          
          _eventController.add(SmartOfflineEvent(
            type: SmartOfflineEventType.reauthenticationStarted,
            timestamp: DateTime.now(),
            message: 'Iniciando reautenticación automática tras restauración de conexión',
          ));
          
          final reauthSuccess = await _reauthService.reauthenticateUser();
          
          if (reauthSuccess) {
            print('✅ Reautenticación exitosa');
            
            _eventController.add(SmartOfflineEvent(
              type: SmartOfflineEventType.reauthenticationSuccess,
              timestamp: DateTime.now(),
              message: 'Reautenticación automática completada exitosamente',
            ));
          } else {
            print('❌ Error en reautenticación automática');
            
            _eventController.add(SmartOfflineEvent(
              type: SmartOfflineEventType.reauthenticationFailed,
              timestamp: DateTime.now(),
              message: 'Error en reautenticación automática - Puede requerir login manual',
            ));
            
            // No bloquear la sincronización por error de reautenticación
            // El usuario puede seguir trabajando con datos locales
          }
        } else {
          print('✅ Usuario ya autenticado correctamente');
        }
        
        // Iniciar sincronización automática si no está corriendo
        if (!_autoSyncService.isRunning) {
          print('🔄 Iniciando sincronización automática tras restauración de conexión');
          await _autoSyncService.startAutoSync();
          
          _eventController.add(SmartOfflineEvent(
            type: SmartOfflineEventType.autoSyncStarted,
            timestamp: DateTime.now(),
            message: 'Sincronización automática iniciada tras restauración de conexión',
          ));
        }
        
      } catch (e) {
        print('❌ Error en proceso de restauración de conexión: $e');
        
        _eventController.add(SmartOfflineEvent(
          type: SmartOfflineEventType.error,
          timestamp: DateTime.now(),
          message: 'Error en restauración de conexión: $e',
          error: e.toString(),
        ));
        
        // Intentar iniciar sincronización de todos modos
        if (!_autoSyncService.isRunning) {
          try {
            await _autoSyncService.startAutoSync();
          } catch (syncError) {
            print('❌ Error iniciando sincronización tras error de reautenticación: $syncError');
          }
        }
      }
      
    } else {
      print('🔌 Modo offline activado - Manteniendo estado actual');
      
      // Si el modo offline está activado, informar al usuario que hay conexión disponible
      _eventController.add(SmartOfflineEvent(
        type: SmartOfflineEventType.connectionRestoredWhileOffline,
        timestamp: DateTime.now(),
        message: 'Conexión restaurada - Puede desactivar modo offline para sincronizar',
      ));
    }
  }

  /// Activar modo offline automáticamente
  Future<void> _activateOfflineModeAutomatically() async {
    try {
      print('🔌 Activando modo offline automáticamente...');
      
      // Verificar que tenemos datos offline disponibles
      final hasOfflineData = await _userPreferencesService.hasOfflineData();
      
      if (!hasOfflineData) {
        print('⚠️ No hay datos offline disponibles - No se puede activar modo offline automáticamente');
        
        _eventController.add(SmartOfflineEvent(
          type: SmartOfflineEventType.autoActivationFailed,
          timestamp: DateTime.now(),
          message: 'No hay datos offline disponibles para activación automática',
        ));
        
        return;
      }
      
      // Detener sincronización automática
      await _autoSyncService.stopAutoSync();
      
      // Activar modo offline
      await _userPreferencesService.setOfflineMode(true);
      
      _lastAutoActivation = DateTime.now();
      _wasOfflineModeManuallyEnabled = false; // Fue activado automáticamente
      
      _eventController.add(SmartOfflineEvent(
        type: SmartOfflineEventType.offlineModeAutoActivated,
        timestamp: _lastAutoActivation!,
        message: 'Modo offline activado automáticamente por pérdida de conexión',
      ));
      
      print('✅ Modo offline activado automáticamente');
      
    } catch (e) {
      print('❌ Error activando modo offline automáticamente: $e');
      
      _eventController.add(SmartOfflineEvent(
        type: SmartOfflineEventType.autoActivationFailed,
        timestamp: DateTime.now(),
        message: 'Error activando modo offline automáticamente: $e',
        error: e.toString(),
      ));
    }
  }

  /// Manejar activación manual del modo offline
  Future<void> onOfflineModeManuallyEnabled() async {
    print('👤 Modo offline activado manualmente por el usuario');
    
    _wasOfflineModeManuallyEnabled = true;
    
    // Detener sincronización automática
    await _autoSyncService.stopAutoSync();
    
    _eventController.add(SmartOfflineEvent(
      type: SmartOfflineEventType.offlineModeManuallyEnabled,
      timestamp: DateTime.now(),
      message: 'Modo offline activado manualmente por el usuario',
    ));
  }

  /// Manejar desactivación manual del modo offline
  Future<void> onOfflineModeManuallyDisabled() async {
    print('👤 Modo offline desactivado manualmente por el usuario');
    
    _wasOfflineModeManuallyEnabled = false;
    
    // Si hay conexión, iniciar sincronización automática
    if (_connectivityService.isConnected) {
      print('📶 Hay conexión - Iniciando sincronización automática');
      await _autoSyncService.startAutoSync();
      
      _eventController.add(SmartOfflineEvent(
        type: SmartOfflineEventType.autoSyncStarted,
        timestamp: DateTime.now(),
        message: 'Sincronización automática iniciada tras desactivación manual del modo offline',
      ));
    } else {
      print('📵 Sin conexión - No iniciando sincronización automática');
    }
    
    _eventController.add(SmartOfflineEvent(
      type: SmartOfflineEventType.offlineModeManuallyDisabled,
      timestamp: DateTime.now(),
      message: 'Modo offline desactivado manualmente por el usuario',
    ));
  }

  /// Obtener estado actual del manager
  Future<SmartOfflineStatus> getStatus() async {
    final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
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
    
    _eventController.add(SmartOfflineEvent(
      type: SmartOfflineEventType.stopped,
      timestamp: DateTime.now(),
      message: 'SmartOfflineManager detenido',
    ));
    
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
  offlineModeManuallyEnabled,
  offlineModeManuallyDisabled,
  autoActivationFailed,
  connectionRestoredWhileOffline,
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
