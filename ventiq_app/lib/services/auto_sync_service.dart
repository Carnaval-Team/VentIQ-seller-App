import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'category_service.dart';
import 'product_service.dart';
import 'payment_method_service.dart';
import 'turno_service.dart';
import 'reauthentication_service.dart';

/// Servicio para sincronización automática periódica de datos
/// Se ejecuta cuando el modo offline NO está activado para mantener datos actualizados
class AutoSyncService {
  static final AutoSyncService _instance = AutoSyncService._internal();
  factory AutoSyncService() => _instance;
  AutoSyncService._internal();

  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final ReauthenticationService _reauthService = ReauthenticationService();
  
  Timer? _syncTimer;
  bool _isRunning = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _syncCount = 0;
  
  // Configuración
  static const Duration _syncInterval = Duration(minutes: 1); // Cada 1 minuto
  static const Duration _syncTimeout = Duration(minutes: 5); // Timeout de 5 minutos
  
  // Stream para notificar eventos de sincronización
  final StreamController<AutoSyncEvent> _syncEventController = StreamController<AutoSyncEvent>.broadcast();
  Stream<AutoSyncEvent> get syncEventStream => _syncEventController.stream;
  
  /// Estado actual del servicio
  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get syncCount => _syncCount;

  /// Iniciar la sincronización automática periódica
  Future<void> startAutoSync() async {
    if (_isRunning) {
      print('🔄 AutoSyncService ya está ejecutándose');
      return;
    }

    print('🚀 Iniciando sincronización automática periódica...');
    print('⏰ Intervalo de sincronización: ${_syncInterval.inMinutes} minutos');
    
    _isRunning = true;
    
    // Ejecutar primera sincronización inmediatamente
    await _performSync();
    
    // Programar sincronizaciones periódicas
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      if (!_isRunning) return;
      
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Pausando sincronización automática');
        await stopAutoSync();
        return;
      }
      
      await _performSync();
    });
    
    _syncEventController.add(AutoSyncEvent(
      type: AutoSyncEventType.started,
      timestamp: DateTime.now(),
      message: 'Sincronización automática iniciada',
    ));
    
    print('✅ Sincronización automática iniciada');
  }

  /// Detener la sincronización automática
  Future<void> stopAutoSync() async {
    if (!_isRunning) return;

    print('🛑 Deteniendo sincronización automática...');
    _isRunning = false;
    
    _syncTimer?.cancel();
    _syncTimer = null;
    
    _syncEventController.add(AutoSyncEvent(
      type: AutoSyncEventType.stopped,
      timestamp: DateTime.now(),
      message: 'Sincronización automática detenida',
    ));
    
    print('✅ Sincronización automática detenida');
  }

  /// Realizar una sincronización completa
  Future<void> _performSync() async {
    if (_isSyncing) {
      print('⏳ Sincronización ya en progreso, omitiendo...');
      return;
    }

    _isSyncing = true;
    final startTime = DateTime.now();
    
    try {
      print('🔄 Iniciando sincronización automática #${_syncCount + 1}...');
      
      _syncEventController.add(AutoSyncEvent(
        type: AutoSyncEventType.syncStarted,
        timestamp: startTime,
        message: 'Sincronización iniciada',
      ));

      // Verificar y asegurar autenticación
      print('🔐 Verificando autenticación antes de sincronizar...');
      final isAuthenticated = await _reauthService.ensureAuthenticated();
      
      if (!isAuthenticated) {
        throw Exception('No se pudo autenticar al usuario para sincronización');
      }
      
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('Usuario no autenticado después de verificación');
      }
      
      print('✅ Usuario autenticado correctamente para sincronización');

      final Map<String, dynamic> syncedData = {};
      final List<String> syncedItems = [];
      
      // 1. Sincronizar credenciales y datos del usuario
      try {
        syncedData['credentials'] = await _syncCredentials();
        syncedItems.add('credenciales');
        print('  ✅ Credenciales sincronizadas');
      } catch (e) {
        print('  ❌ Error sincronizando credenciales: $e');
      }

      // 2. Sincronizar promociones globales
      try {
        syncedData['promotions'] = await _syncPromotions();
        syncedItems.add('promociones');
        print('  ✅ Promociones sincronizadas');
      } catch (e) {
        print('  ❌ Error sincronizando promociones: $e');
      }

      // 3. Sincronizar métodos de pago
      try {
        syncedData['payment_methods'] = await _syncPaymentMethods();
        syncedItems.add('métodos de pago');
        print('  ✅ Métodos de pago sincronizados');
      } catch (e) {
        print('  ❌ Error sincronizando métodos de pago: $e');
      }

      // 4. Sincronizar categorías
      try {
        syncedData['categories'] = await _syncCategories();
        syncedItems.add('categorías');
        print('  ✅ Categorías sincronizadas');
      } catch (e) {
        print('  ❌ Error sincronizando categorías: $e');
      }

      // 5. Sincronizar productos (solo cada 3 sincronizaciones para no sobrecargar)
      if (_syncCount % 3 == 0) {
        try {
          syncedData['products'] = await _syncProducts();
          syncedItems.add('productos');
          print('  ✅ Productos sincronizados');
        } catch (e) {
          print('  ❌ Error sincronizando productos: $e');
        }
      }

      // 6. Sincronizar turno y resumen
      try {
        syncedData['turno'] = await _syncTurno();
        await _syncTurnoResumen();
        syncedItems.add('turno');
        print('  ✅ Turno sincronizado');
      } catch (e) {
        print('  ❌ Error sincronizando turno: $e');
      }

      // 7. Sincronizar órdenes (solo cada 2 sincronizaciones)
      if (_syncCount % 2 == 0) {
        try {
          syncedData['orders'] = await _syncOrders();
          syncedItems.add('órdenes');
          print('  ✅ Órdenes sincronizadas');
        } catch (e) {
          print('  ❌ Error sincronizando órdenes: $e');
        }
      }

      // Guardar datos sincronizados para uso offline futuro
      if (syncedData.isNotEmpty) {
        await _userPreferencesService.saveOfflineData(syncedData);
        print('  💾 Datos guardados para uso offline futuro');
      }

      _lastSyncTime = DateTime.now();
      _syncCount++;
      
      final duration = _lastSyncTime!.difference(startTime);
      
      _syncEventController.add(AutoSyncEvent(
        type: AutoSyncEventType.syncCompleted,
        timestamp: _lastSyncTime!,
        message: 'Sincronización completada: ${syncedItems.join(", ")}',
        duration: duration,
        itemsSynced: syncedItems,
      ));
      
      print('✅ Sincronización automática #$_syncCount completada en ${duration.inSeconds}s');
      print('📊 Items sincronizados: ${syncedItems.join(", ")}');
      
    } catch (e) {
      print('❌ Error en sincronización automática: $e');
      
      _syncEventController.add(AutoSyncEvent(
        type: AutoSyncEventType.syncFailed,
        timestamp: DateTime.now(),
        message: 'Error en sincronización: $e',
        error: e.toString(),
      ));
    } finally {
      _isSyncing = false;
    }
  }

  /// Sincronizar credenciales del usuario
  Future<Map<String, dynamic>> _syncCredentials() async {
    final userData = await _userPreferencesService.getUserData();
    final credentials = await _userPreferencesService.getSavedCredentials();
    
    final email = userData['email'] ?? credentials['email'];
    final password = credentials['password'];
    final userId = userData['userId'];
    
    if (email != null && password != null && userId != null) {
      // Actualizar usuario en el array de usuarios offline
      await _userPreferencesService.saveOfflineUser(
        email: email,
        password: password,
        userId: userId,
      );
      
      return {
        'email': email,
        'password': password,
        'userId': userId,
      };
    }
    
    return {};
  }

  /// Sincronizar promociones globales
  Future<Map<String, dynamic>> _syncPromotions() async {
    final promotionData = await _userPreferencesService.getPromotionData();
    return promotionData ?? {};
  }

  /// Sincronizar métodos de pago
  Future<List<Map<String, dynamic>>> _syncPaymentMethods() async {
    final paymentMethods = await PaymentMethodService.getActivePaymentMethods();
    return paymentMethods.map((pm) => pm.toJson()).toList();
  }

  /// Sincronizar categorías
  Future<List<Map<String, dynamic>>> _syncCategories() async {
    final categoryService = CategoryService();
    final categories = await categoryService.getCategories();
    return categories.map((cat) => {
      'id': cat.id,
      'name': cat.name,
      'imageUrl': cat.imageUrl,
      'color': cat.color.value,
    }).toList();
  }

  /// Sincronizar productos con detalles completos
  Future<Map<String, List<Map<String, dynamic>>>> _syncProducts() async {
    final productService = ProductService();
    final categoryService = CategoryService();
    final Map<String, List<Map<String, dynamic>>> productsByCategory = {};
    
    final categories = await categoryService.getCategories();
    
    for (var category in categories.take(3)) { // Limitar a 3 categorías por sincronización
      final productsMap = await productService.getProductsByCategory(category.id);
      final List<Map<String, dynamic>> allProducts = [];
      
      for (var entry in productsMap.entries) {
        final subcategory = entry.key;
        final products = entry.value;
        
        for (var prod in products.take(10)) { // Limitar a 10 productos por subcategoría
          try {
            // Obtener detalles completos usando RPC
            final detailResponse = await Supabase.instance.client.rpc(
              'get_detalle_producto',
              params: {'id_producto_param': prod.id},
            );
            
            final productWithDetails = {
              'id': prod.id,
              'denominacion': prod.denominacion,
              'precio': prod.precio,
              'foto': prod.foto,
              'categoria': prod.categoria,
              'descripcion': prod.descripcion,
              'cantidad': prod.cantidad,
              'subcategoria': subcategory,
              'detalles_completos': detailResponse,
            };
            
            allProducts.add(productWithDetails);
          } catch (e) {
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
    }
    
    return productsByCategory;
  }

  /// Sincronizar turno actual
  Future<Map<String, dynamic>?> _syncTurno() async {
    final hasOpenShift = await TurnoService.hasOpenShift();
    
    if (hasOpenShift) {
      final userPrefs = UserPreferencesService();
      final idTpv = await userPrefs.getIdTpv();
      
      if (idTpv != null) {
        final response = await Supabase.instance.client
            .from('app_dat_caja_turno')
            .select('*')
            .eq('id_tpv', idTpv)
            .eq('estado', 1)
            .order('fecha_apertura', ascending: false, nullsFirst: false)
            .limit(1);
            
        if (response.isNotEmpty) {
          return response.first;
        }
      }
    }
    
    return null;
  }

  /// Sincronizar resumen de turno anterior
  Future<void> _syncTurnoResumen() async {
    final resumenTurno = await TurnoService.getResumenTurnoKPI();
    
    if (resumenTurno != null) {
      await _userPreferencesService.saveTurnoResumenCache(resumenTurno);
    }
  }

  /// Sincronizar órdenes recientes
  Future<List<Map<String, dynamic>>> _syncOrders() async {
    final userData = await _userPreferencesService.getUserData();
    final idTienda = await _userPreferencesService.getIdTienda();
    final idTpv = await _userPreferencesService.getIdTpv();
    final userId = userData['userId'];

    if (idTienda == null || idTpv == null || userId == null) {
      return [];
    }

    final response = await Supabase.instance.client.rpc(
      'listar_ordenes',
      params: {
        'con_inventario_param': false,
        'fecha_desde_param': null,
        'fecha_hasta_param': null,
        'id_estado_param': null,
        'id_tienda_param': idTienda,
        'id_tipo_operacion_param': null,
        'id_tpv_param': idTpv,
        'id_usuario_param': userId,
        'limite_param': 50, // Limitar a 50 órdenes más recientes
        'pagina_param': null,
        'solo_pendientes_param': false,
      },
    );

    if (response is List && response.isNotEmpty) {
      return response.cast<Map<String, dynamic>>();
    }

    return [];
  }

  /// Forzar una sincronización inmediata
  Future<void> forceSyncNow() async {
    if (_isSyncing) {
      print('⏳ Sincronización ya en progreso');
      return;
    }

    print('🚀 Forzando sincronización inmediata...');
    await _performSync();
  }

  /// Obtener estadísticas de sincronización
  Map<String, dynamic> getSyncStats() {
    return {
      'isRunning': _isRunning,
      'isSyncing': _isSyncing,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'syncCount': _syncCount,
      'syncInterval': _syncInterval.inMinutes,
    };
  }

  /// Limpiar recursos
  void dispose() {
    stopAutoSync();
    _syncEventController.close();
  }
}

/// Tipos de eventos de sincronización automática
enum AutoSyncEventType {
  started,
  stopped,
  syncStarted,
  syncCompleted,
  syncFailed,
}

/// Evento de sincronización automática
class AutoSyncEvent {
  final AutoSyncEventType type;
  final DateTime timestamp;
  final String message;
  final Duration? duration;
  final List<String>? itemsSynced;
  final String? error;

  AutoSyncEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.duration,
    this.itemsSynced,
    this.error,
  });

  @override
  String toString() {
    return 'AutoSyncEvent(type: $type, timestamp: $timestamp, message: $message, duration: $duration, itemsSynced: $itemsSynced, error: $error)';
  }
}
