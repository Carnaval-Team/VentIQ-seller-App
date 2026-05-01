import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';

/// Servicio para monitorear el estado de conectividad de la aplicación
/// Detecta cambios en la conexión de red y valida conectividad real a internet
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Stream controllers para notificar cambios
  final StreamController<bool> _connectionStatusController =
      StreamController<bool>.broadcast();
  final StreamController<ConnectivityEvent> _connectivityEventController =
      StreamController<ConnectivityEvent>.broadcast();

  // Estado actual
  bool _isConnected = true;
  bool _isMonitoring = false;
  DateTime? _lastConnectionLost;
  DateTime? _lastConnectionRestored;

  // Configuración
  static const Duration _checkInterval = Duration(seconds: 30);
  static const Duration _timeoutDuration = Duration(seconds: 8);
  static String get _testUrl =>
      '${SupabaseConfig.supabaseUrl}/auth/v1/health';

  Timer? _periodicCheckTimer;

  /// Stream que emite el estado de conexión (true = conectado, false = desconectado)
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;

  /// Stream que emite eventos de conectividad con detalles
  Stream<ConnectivityEvent> get connectivityEventStream =>
      _connectivityEventController.stream;

  /// Estado actual de conexión
  bool get isConnected => _isConnected;

  /// Indica si el servicio está monitoreando
  bool get isMonitoring => _isMonitoring;

  /// Última vez que se perdió la conexión
  DateTime? get lastConnectionLost => _lastConnectionLost;

  /// Última vez que se restauró la conexión
  DateTime? get lastConnectionRestored => _lastConnectionRestored;

  /// Iniciar el monitoreo de conectividad
  Future<void> startMonitoring() async {
    if (_isMonitoring) {
      print('🔍 ConnectivityService ya está monitoreando');
      return;
    }

    print('🚀 Iniciando monitoreo de conectividad...');
    _isMonitoring = true;

    // Verificar estado inicial
    await _checkInitialConnectivity();

    // Escuchar cambios de conectividad del sistema
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        print('❌ Error en monitoreo de conectividad: $error');
      },
    );

    // Iniciar verificación periódica
    _startPeriodicCheck();

    print('✅ Monitoreo de conectividad iniciado');
  }

  /// Detener el monitoreo de conectividad
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    print('🛑 Deteniendo monitoreo de conectividad...');
    _isMonitoring = false;

    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;

    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;

    print('✅ Monitoreo de conectividad detenido');
  }

  /// Verificar conectividad inicial
  Future<void> _checkInitialConnectivity() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      print('📡 Estado inicial de conectividad: $connectivityResults');

      // Verificar si hay alguna conexión disponible
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        await _updateConnectionStatus(false, 'Sin conexión de red');
      } else {
        // Verificar conectividad real a internet
        final hasInternet = await _hasInternetConnection();
        await _updateConnectionStatus(
          hasInternet,
          hasInternet ? 'Conectado a internet' : 'Sin acceso a internet',
        );
      }
    } catch (e) {
      print('❌ Error verificando conectividad inicial: $e');
      await _updateConnectionStatus(false, 'Error verificando conectividad');
    }
  }

  /// Manejar cambios de conectividad del sistema
  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    print('📡 Cambio de conectividad detectado: $results');

    // Verificar si hay alguna conexión disponible
    final hasConnection = results.any(
      (result) => result != ConnectivityResult.none,
    );

    if (!hasConnection) {
      await _updateConnectionStatus(false, 'Conexión de red perdida');
    } else {
      // Verificar si realmente hay acceso a internet
      print('🔍 Verificando acceso real a internet...');
      final hasInternet = await _hasInternetConnection();

      if (hasInternet) {
        await _updateConnectionStatus(true, 'Conexión a internet restaurada');
      } else {
        await _updateConnectionStatus(
          false,
          'Red disponible pero sin acceso a internet',
        );
      }
    }
  }

  /// Verificar si hay conexión real a internet
  Future<bool> _hasInternetConnection() async {
    if (kIsWeb) {
      print('🌐 Web detectada - Asumiendo conexión activa');
      return true;
    }

    try {
      final response = await http.get(
        Uri.parse(_testUrl),
        headers: {
          'apikey': SupabaseConfig.supabaseAnonKey,
        },
      ).timeout(_timeoutDuration);
      // Cualquier respuesta HTTP del servidor (incluso 4xx) confirma conexión.
      // Solo 5xx o errores de red indican problemas reales.
      final hasConnection =
          response.statusCode > 0 && response.statusCode < 500;
      print(
        '🌐 Verificación de internet (Supabase ${response.statusCode}): ${hasConnection ? "✅ Conectado" : "❌ Sin acceso"}',
      );
      return hasConnection;
    } on SocketException catch (e) {
      print('🌐 Sin acceso a internet (Socket): $e');
      return false;
    } on TimeoutException catch (e) {
      print('🌐 Sin acceso a internet (Timeout): $e');
      return false;
    } catch (e) {
      print('🌐 Sin acceso a internet: $e');
      return false;
    }
  }

  /// Forzar una verificación inmediata de conectividad y actualizar el estado.
  /// Usado por el botón "Reintentar" del diálogo de pérdida de conexión.
  Future<bool> performImmediateCheck() async {
    print('⚡ ConnectivityService: verificación inmediata solicitada');
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );

      if (!hasConnection) {
        await _updateConnectionStatus(false, 'Sin conexión de red');
        return false;
      }

      final hasInternet = await _hasInternetConnection();
      await _updateConnectionStatus(
        hasInternet,
        hasInternet
            ? 'Verificación inmediata: conexión activa'
            : 'Verificación inmediata: sin acceso a internet',
      );
      return hasInternet;
    } catch (e) {
      print('❌ Error en verificación inmediata: $e');
      return false;
    }
  }

  /// Actualizar el estado de conexión
  Future<void> _updateConnectionStatus(bool isConnected, String reason) async {
    final wasConnected = _isConnected;
    _isConnected = isConnected;

    final now = DateTime.now();

    if (wasConnected && !isConnected) {
      // Se perdió la conexión
      _lastConnectionLost = now;
      print('📵 CONEXIÓN PERDIDA: $reason');

      _connectivityEventController.add(
        ConnectivityEvent(
          type: ConnectivityEventType.connectionLost,
          timestamp: now,
          reason: reason,
        ),
      );
    } else if (!wasConnected && isConnected) {
      // Se restauró la conexión
      _lastConnectionRestored = now;
      final downtime =
          _lastConnectionLost != null
              ? now.difference(_lastConnectionLost!).inSeconds
              : 0;

      print('📶 CONEXIÓN RESTAURADA: $reason (desconectado por ${downtime}s)');

      _connectivityEventController.add(
        ConnectivityEvent(
          type: ConnectivityEventType.connectionRestored,
          timestamp: now,
          reason: reason,
          downtimeSeconds: downtime,
        ),
      );
    }

    // Emitir cambio de estado
    _connectionStatusController.add(isConnected);
  }

  /// Iniciar verificación periódica
  void _startPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(_checkInterval, (_) async {
      if (!_isMonitoring) return;

      try {
        final connectivityResults = await _connectivity.checkConnectivity();
        print(connectivityResults);
        // Verificar si hay alguna conexión disponible
        final hasConnection = connectivityResults.any(
          (result) => result != ConnectivityResult.none,
        );

        if (hasConnection) {
          final hasInternet = await _hasInternetConnection();

          if (_isConnected != hasInternet) {
            await _updateConnectionStatus(
              hasInternet,
              hasInternet
                  ? 'Conexión verificada periódicamente'
                  : 'Pérdida de internet detectada periódicamente',
            );
          }
        }
      } catch (e) {
        print('❌ Error en verificación periódica: $e');
      }
    });
  }

  /// Verificar conectividad manualmente
  Future<bool> checkConnectivity() async {
    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      // Verificar si hay alguna conexión disponible
      final hasConnection = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );
      print('has: $hasConnection');

      if (!hasConnection) {
        return false;
      }

      return await _hasInternetConnection();
    } catch (e) {
      print('❌ Error verificando conectividad: $e');
      return false;
    }
  }

  /// Obtener información detallada de conectividad
  Future<ConnectivityInfo> getConnectivityInfo() async {
    final connectivityResults = await _connectivity.checkConnectivity();
    final hasInternet = await _hasInternetConnection();

    // Tomar el primer resultado disponible o none si la lista está vacía
    final primaryResult =
        connectivityResults.isNotEmpty
            ? connectivityResults.first
            : ConnectivityResult.none;

    return ConnectivityInfo(
      connectivityResult: primaryResult,
      hasInternet: hasInternet,
      isMonitoring: _isMonitoring,
      lastConnectionLost: _lastConnectionLost,
      lastConnectionRestored: _lastConnectionRestored,
    );
  }

  /// Limpiar recursos
  void dispose() {
    stopMonitoring();
    _connectionStatusController.close();
    _connectivityEventController.close();
  }
}

/// Tipos de eventos de conectividad
enum ConnectivityEventType { connectionLost, connectionRestored }

/// Evento de conectividad con detalles
class ConnectivityEvent {
  final ConnectivityEventType type;
  final DateTime timestamp;
  final String reason;
  final int? downtimeSeconds;

  ConnectivityEvent({
    required this.type,
    required this.timestamp,
    required this.reason,
    this.downtimeSeconds,
  });

  @override
  String toString() {
    return 'ConnectivityEvent(type: $type, timestamp: $timestamp, reason: $reason, downtimeSeconds: $downtimeSeconds)';
  }
}

/// Información detallada de conectividad
class ConnectivityInfo {
  final ConnectivityResult connectivityResult;
  final bool hasInternet;
  final bool isMonitoring;
  final DateTime? lastConnectionLost;
  final DateTime? lastConnectionRestored;

  ConnectivityInfo({
    required this.connectivityResult,
    required this.hasInternet,
    required this.isMonitoring,
    this.lastConnectionLost,
    this.lastConnectionRestored,
  });

  @override
  String toString() {
    return 'ConnectivityInfo(connectivityResult: $connectivityResult, hasInternet: $hasInternet, isMonitoring: $isMonitoring)';
  }
}
