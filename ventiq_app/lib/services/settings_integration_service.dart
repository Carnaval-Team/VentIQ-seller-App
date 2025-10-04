import 'dart:async';
import 'smart_offline_manager.dart';
import 'connectivity_service.dart';
import 'auto_sync_service.dart';
import 'user_preferences_service.dart';

/// Servicio para integrar la funcionalidad inteligente en SettingsScreen
/// Maneja la inicialización y coordinación de todos los servicios
class SettingsIntegrationService {
  static final SettingsIntegrationService _instance = SettingsIntegrationService._internal();
  factory SettingsIntegrationService() => _instance;
  SettingsIntegrationService._internal();

  final SmartOfflineManager _smartOfflineManager = SmartOfflineManager();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  
  bool _isInitialized = false;
  StreamSubscription<SmartOfflineEvent>? _eventSubscription;
  
  // Stream para notificar cambios a la UI
  final StreamController<SettingsIntegrationEvent> _eventController = StreamController<SettingsIntegrationEvent>.broadcast();
  Stream<SettingsIntegrationEvent> get eventStream => _eventController.stream;

  /// Inicializar el servicio de integración
  Future<void> initialize() async {
    if (_isInitialized) {
      print('🔧 SettingsIntegrationService ya está inicializado');
      return;
    }

    print('🚀 Inicializando SettingsIntegrationService...');
    
    try {
      // Inicializar el gestor inteligente
      await _smartOfflineManager.initialize();
      
      // Configurar listener para eventos
      _setupEventListener();
      
      _isInitialized = true;
      
      _eventController.add(SettingsIntegrationEvent(
        type: SettingsIntegrationEventType.initialized,
        timestamp: DateTime.now(),
        message: 'Servicios inteligentes inicializados correctamente',
      ));
      
      print('✅ SettingsIntegrationService inicializado correctamente');
      
    } catch (e) {
      print('❌ Error inicializando SettingsIntegrationService: $e');
      
      _eventController.add(SettingsIntegrationEvent(
        type: SettingsIntegrationEventType.error,
        timestamp: DateTime.now(),
        message: 'Error inicializando servicios: $e',
        error: e.toString(),
      ));
      
      throw e;
    }
  }

  /// Configurar listener para eventos del SmartOfflineManager
  void _setupEventListener() {
    _eventSubscription = _smartOfflineManager.eventStream.listen(
      (event) {
        print('📡 Evento SmartOffline recibido: ${event.type} - ${event.message}');
        
        // Convertir eventos del SmartOfflineManager a eventos de integración
        SettingsIntegrationEventType eventType;
        
        switch (event.type) {
          case SmartOfflineEventType.offlineModeAutoActivated:
            eventType = SettingsIntegrationEventType.offlineModeAutoActivated;
            break;
          case SmartOfflineEventType.connectionRestoredWhileOffline:
            eventType = SettingsIntegrationEventType.connectionRestored;
            break;
          case SmartOfflineEventType.autoSyncStarted:
            eventType = SettingsIntegrationEventType.autoSyncStarted;
            break;
          case SmartOfflineEventType.autoSyncEvent:
            eventType = SettingsIntegrationEventType.autoSyncEvent;
            break;
          case SmartOfflineEventType.connectivityChanged:
            eventType = SettingsIntegrationEventType.connectivityChanged;
            break;
          case SmartOfflineEventType.reauthenticationStarted:
            eventType = SettingsIntegrationEventType.reauthenticationStarted;
            break;
          case SmartOfflineEventType.reauthenticationSuccess:
            eventType = SettingsIntegrationEventType.reauthenticationSuccess;
            break;
          case SmartOfflineEventType.reauthenticationFailed:
            eventType = SettingsIntegrationEventType.reauthenticationFailed;
            break;
          default:
            eventType = SettingsIntegrationEventType.other;
        }
        
        _eventController.add(SettingsIntegrationEvent(
          type: eventType,
          timestamp: event.timestamp,
          message: event.message,
          smartOfflineEvent: event,
        ));
      },
      onError: (error) {
        print('❌ Error en stream de SmartOfflineManager: $error');
        
        _eventController.add(SettingsIntegrationEvent(
          type: SettingsIntegrationEventType.error,
          timestamp: DateTime.now(),
          message: 'Error en monitoreo inteligente: $error',
          error: error.toString(),
        ));
      },
    );
  }

  /// Manejar cambio manual del modo offline desde SettingsScreen
  Future<void> handleOfflineModeChanged(bool enabled) async {
    print('🔧 Manejando cambio manual de modo offline: $enabled');
    
    try {
      if (enabled) {
        // El usuario activó el modo offline manualmente
        await _smartOfflineManager.onOfflineModeManuallyEnabled();
        
        _eventController.add(SettingsIntegrationEvent(
          type: SettingsIntegrationEventType.offlineModeManuallyEnabled,
          timestamp: DateTime.now(),
          message: 'Modo offline activado manualmente',
        ));
        
      } else {
        // El usuario desactivó el modo offline manualmente
        await _smartOfflineManager.onOfflineModeManuallyDisabled();
        
        _eventController.add(SettingsIntegrationEvent(
          type: SettingsIntegrationEventType.offlineModeManuallyDisabled,
          timestamp: DateTime.now(),
          message: 'Modo offline desactivado manualmente',
        ));
      }
      
    } catch (e) {
      print('❌ Error manejando cambio de modo offline: $e');
      
      _eventController.add(SettingsIntegrationEvent(
        type: SettingsIntegrationEventType.error,
        timestamp: DateTime.now(),
        message: 'Error cambiando modo offline: $e',
        error: e.toString(),
      ));
      
      throw e;
    }
  }

  /// Obtener estado actual de todos los servicios
  Future<SettingsIntegrationStatus> getStatus() async {
    try {
      final smartOfflineStatus = await _smartOfflineManager.getStatus();
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      return SettingsIntegrationStatus(
        isInitialized: _isInitialized,
        smartOfflineStatus: smartOfflineStatus,
        isOfflineModeEnabled: isOfflineModeEnabled,
      );
      
    } catch (e) {
      print('❌ Error obteniendo estado: $e');
      throw e;
    }
  }

  /// Forzar sincronización inmediata
  Future<void> forceSyncNow() async {
    try {
      final autoSyncService = AutoSyncService();
      await autoSyncService.forceSyncNow();
      
      _eventController.add(SettingsIntegrationEvent(
        type: SettingsIntegrationEventType.syncForced,
        timestamp: DateTime.now(),
        message: 'Sincronización forzada iniciada',
      ));
      
    } catch (e) {
      print('❌ Error forzando sincronización: $e');
      
      _eventController.add(SettingsIntegrationEvent(
        type: SettingsIntegrationEventType.error,
        timestamp: DateTime.now(),
        message: 'Error forzando sincronización: $e',
        error: e.toString(),
      ));
      
      throw e;
    }
  }

  /// Verificar conectividad manualmente
  Future<bool> checkConnectivity() async {
    try {
      final connectivityService = ConnectivityService();
      return await connectivityService.checkConnectivity();
    } catch (e) {
      print('❌ Error verificando conectividad: $e');
      return false;
    }
  }

  /// Obtener información de conectividad
  Future<ConnectivityInfo?> getConnectivityInfo() async {
    try {
      final connectivityService = ConnectivityService();
      return await connectivityService.getConnectivityInfo();
    } catch (e) {
      print('❌ Error obteniendo info de conectividad: $e');
      return null;
    }
  }

  /// Detener todos los servicios
  Future<void> stop() async {
    if (!_isInitialized) return;

    print('🛑 Deteniendo SettingsIntegrationService...');
    
    await _eventSubscription?.cancel();
    await _smartOfflineManager.stop();
    
    _isInitialized = false;
    
    _eventController.add(SettingsIntegrationEvent(
      type: SettingsIntegrationEventType.stopped,
      timestamp: DateTime.now(),
      message: 'Servicios inteligentes detenidos',
    ));
    
    print('✅ SettingsIntegrationService detenido');
  }

  /// Limpiar recursos
  void dispose() {
    stop();
    _eventController.close();
    _smartOfflineManager.dispose();
  }

  /// Getter para verificar si está inicializado
  bool get isInitialized => _isInitialized;
}

/// Tipos de eventos de integración
enum SettingsIntegrationEventType {
  initialized,
  stopped,
  offlineModeAutoActivated,
  offlineModeManuallyEnabled,
  offlineModeManuallyDisabled,
  connectionRestored,
  autoSyncStarted,
  autoSyncEvent,
  connectivityChanged,
  syncForced,
  reauthenticationStarted,
  reauthenticationSuccess,
  reauthenticationFailed,
  error,
  other,
}

/// Evento de integración
class SettingsIntegrationEvent {
  final SettingsIntegrationEventType type;
  final DateTime timestamp;
  final String message;
  final String? error;
  final SmartOfflineEvent? smartOfflineEvent;

  SettingsIntegrationEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.error,
    this.smartOfflineEvent,
  });

  @override
  String toString() {
    return 'SettingsIntegrationEvent(type: $type, timestamp: $timestamp, message: $message, error: $error)';
  }
}

/// Estado de la integración
class SettingsIntegrationStatus {
  final bool isInitialized;
  final SmartOfflineStatus smartOfflineStatus;
  final bool isOfflineModeEnabled;

  SettingsIntegrationStatus({
    required this.isInitialized,
    required this.smartOfflineStatus,
    required this.isOfflineModeEnabled,
  });

  @override
  String toString() {
    return 'SettingsIntegrationStatus(isInitialized: $isInitialized, isOfflineModeEnabled: $isOfflineModeEnabled)';
  }
}
