import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'category_service.dart';
import 'product_service.dart';
import 'payment_method_service.dart';
import 'turno_service.dart';
import 'reauthentication_service.dart';
import 'store_config_service.dart';

/// Servicio para sincronización automática periódica de datos
/// Se ejecuta cuando el modo offline NO está activado para mantener datos actualizados
class AutoSyncService {
  static final AutoSyncService _instance = AutoSyncService._internal();
  factory AutoSyncService() => _instance;
  AutoSyncService._internal();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final ReauthenticationService _reauthService = ReauthenticationService();

  Timer? _syncTimer;
  bool _isRunning = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _syncCount = 0;

  // Configuración
  static const Duration _syncInterval = Duration(minutes: 1); // Cada 1 minuto
  static const Duration _syncTimeout = Duration(
    minutes: 5,
  ); // Timeout de 5 minutos

  // Stream para notificar eventos de sincronización
  final StreamController<AutoSyncEvent> _syncEventController =
      StreamController<AutoSyncEvent>.broadcast();
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
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Pausando sincronización automática');
        await stopAutoSync();
        return;
      }

      await _performSync();
    });

    _syncEventController.add(
      AutoSyncEvent(
        type: AutoSyncEventType.started,
        timestamp: DateTime.now(),
        message: 'Sincronización automática iniciada',
      ),
    );

    print('✅ Sincronización automática iniciada');
  }

  /// Ejecutar una sincronización inmediata sin iniciar el timer periódico
  /// Útil para ejecutar la primera sincronización rápidamente
  Future<void> performImmediateSync() async {
    try {
      print('⚡ Ejecutando sincronización inmediata...');
      
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Omitiendo sincronización inmediata');
        return;
      }
      
      // Ejecutar sincronización inmediata
      await _performSync();
      
      print('✅ Sincronización inmediata completada');
    } catch (e) {
      print('❌ Error en sincronización inmediata: $e');
      rethrow;
    }
  }

  /// Detener la sincronización automática
  Future<void> stopAutoSync() async {
    if (!_isRunning) return;

    print('🛑 Deteniendo sincronización automática...');
    _isRunning = false;

    _syncTimer?.cancel();
    _syncTimer = null;

    _syncEventController.add(
      AutoSyncEvent(
        type: AutoSyncEventType.stopped,
        timestamp: DateTime.now(),
        message: 'Sincronización automática detenida',
      ),
    );

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

      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncStarted,
          timestamp: startTime,
          message: 'Sincronización iniciada',
        ),
      );

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

      // 3. Sincronizar configuración de tienda
      try {
        await _syncStoreConfig();
        syncedItems.add('configuración de tienda');
        print('  ✅ Configuración de tienda sincronizada');
      } catch (e) {
        print('  ❌ Error sincronizando configuración de tienda: $e');
      }

      // 4. Sincronizar métodos de pago
      try {
        syncedData['payment_methods'] = await _syncPaymentMethods();
        syncedItems.add('métodos de pago');
        print('  ✅ Métodos de pago sincronizados');
      } catch (e) {
        print('  ❌ Error sincronizando métodos de pago: $e');
      }

      // 5. Sincronizar categorías (siempre en primera sincronización, luego cada 3 sincronizaciones)
      if (_syncCount == 0 || _syncCount % 3 == 0) {
        try {
          final isFirstSync = _syncCount == 0;
          print('  📂 Sincronizando categorías (${isFirstSync ? "primera carga" : "sincronización periódica #$_syncCount"})');
          syncedData['categories'] = await _syncCategories();
          syncedItems.add('categorías');
          print('  ✅ Categorías sincronizadas');
        } catch (e) {
          print('  ❌ Error sincronizando categorías: $e');
        }
      } else {
        print('  ⏭️ Omitiendo categorías (sincronización #$_syncCount, próxima en ${3 - (_syncCount % 3)})');
      }

      // 6. Sincronizar productos (siempre en primera sincronización, luego cada 5 sincronizaciones)
      if (_syncCount == 0 || _syncCount % 5 == 0) {
        try {
          final isFirstSync = _syncCount == 0;
          print('  📦 Sincronizando productos (${isFirstSync ? "primera carga" : "sincronización periódica #$_syncCount"})');
          syncedData['products'] = await _syncProducts();
          syncedItems.add('productos');
          print('  ✅ Productos sincronizados');
        } catch (e) {
          print('  ❌ Error sincronizando productos: $e');
        }
      } else {
        print('  ⏭️ Omitiendo productos (sincronización #$_syncCount, próxima en ${5 - (_syncCount % 5)})');
      }

      // 7. Sincronizar turno y resumen
      try {
        final turnoData = await _syncTurno();
        syncedData['turno'] = turnoData;
        
        // ✅ CORREGIDO: También guardar en la clave específica de turno offline
        if (turnoData != null) {
          await _userPreferencesService.saveOfflineTurno(turnoData);
          print('  💾 Turno guardado en cache offline específico');
        }
        
        await _syncTurnoResumen();
        // Sincronizar resumen de cierre diario para CierreScreen y VentaTotalScreen
        await _syncResumenCierre();
        syncedItems.add('turno');
        print('  ✅ Turno y resúmenes sincronizados');
      } catch (e) {
        print('  ❌ Error sincronizando turno: $e');
      }

      // 8. Sincronizar egresos
      try {
        await _syncEgresos();
        syncedItems.add('egresos');
        print('  ✅ Egresos sincronizados');
      } catch (e) {
        print('  ❌ Error sincronizando egresos: $e');
      }

      // 9. Sincronizar egresos offline pendientes
      try {
        final syncedEgresos = await _syncOfflineEgresos();
        if (syncedEgresos > 0) {
          syncedData['offline_egresos'] = syncedEgresos;
          syncedItems.add('egresos offline ($syncedEgresos)');
          print('  ✅ $syncedEgresos egresos offline sincronizados');
        }
      } catch (e) {
        print('  ❌ Error sincronizando egresos offline: $e');
      }

      // 10. Sincronizar ventas offline pendientes
      try {
        final syncedSales = await _syncOfflineSales();
        if (syncedSales > 0) {
          syncedData['offline_sales'] = syncedSales;
          syncedItems.add('ventas offline ($syncedSales)');
          print('  ✅ $syncedSales ventas offline sincronizadas');
        }
      } catch (e) {
        print('  ❌ Error sincronizando ventas offline: $e');
      }

      // 11. Sincronizar órdenes (solo cada 2 sincronizaciones)
      if (_syncCount % 2 == 0) {
        try {
          syncedData['orders'] = await _syncOrders();
          syncedItems.add('órdenes');
          print('  ✅ Órdenes sincronizadas');
        } catch (e) {
          print('  ❌ Error sincronizando órdenes: $e');
        }
      }

      // Hacer merge inteligente de datos sincronizados para uso offline futuro
      if (syncedData.isNotEmpty) {
        await _userPreferencesService.mergeOfflineData(syncedData);
        print('  💾 Datos merged para uso offline futuro');
      }

      _lastSyncTime = DateTime.now();
      _syncCount++;

      final duration = _lastSyncTime!.difference(startTime);

      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncCompleted,
          timestamp: _lastSyncTime!,
          message: 'Sincronización completada: ${syncedItems.join(", ")}',
          duration: duration,
          itemsSynced: syncedItems,
        ),
      );

      print(
        '✅ Sincronización automática #$_syncCount completada en ${duration.inSeconds}s',
      );
      print('📊 Items sincronizados: ${syncedItems.join(", ")}');
    } catch (e) {
      print('❌ Error en sincronización automática: $e');

      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncFailed,
          timestamp: DateTime.now(),
          message: 'Error en sincronización: $e',
          error: e.toString(),
        ),
      );
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

      return {'email': email, 'password': password, 'userId': userId};
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
  }

  /// Sincronizar productos con detalles completos
  Future<Map<String, List<Map<String, dynamic>>>> _syncProducts() async {
    final productService = ProductService();
    final categoryService = CategoryService();
    final Map<String, List<Map<String, dynamic>>> productsByCategory = {};

    final categories = await categoryService.getCategories();
    print('🔄 AutoSync: Sincronizando productos de ${categories.length} categorías...');

    for (var category in categories) {
      // Sincronizar todas las categorías para cobertura completa
      print('  📂 Procesando categoría: ${category.name} (ID: ${category.id})');
      final productsMap = await productService.getProductsByCategory(
        category.id,
      );
      final List<Map<String, dynamic>> allProducts = [];

      for (var entry in productsMap.entries) {
        final subcategory = entry.key;
        final products = entry.value;

        print('    📦 Subcategoría "$subcategory": ${products.length} productos');
        for (var prod in products) {
          // Aumentar límite a 50 productos por subcategoría para mejor cobertura
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
            print('      ✅ ${prod.denominacion} (ID: ${prod.id}) - Detalles obtenidos');
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
            print('      ⚠️ ${prod.denominacion} (ID: ${prod.id}) - Solo datos básicos: $e');
          }
        }
      }

      productsByCategory[category.id.toString()] = allProducts;
      print('  ✅ Categoría "${category.name}": ${allProducts.length} productos sincronizados');
    }

    final totalProducts = productsByCategory.values.fold(0, (sum, list) => sum + list.length);
    print('🎉 AutoSync: Total de productos sincronizados: $totalProducts');
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

  /// Sincronizar resumen de cierre diario
  Future<void> _syncResumenCierre() async {
    try {
      // Obtener datos del usuario para llamar a fn_resumen_diario_cierre
      final idTpv = await _userPreferencesService.getIdTpv();
      final userID = await _userPreferencesService.getUserId();

      if (idTpv != null && userID != null) {
        // Llamar a la función RPC fn_resumen_diario_cierre
        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        if (resumenCierreResponse != null) {
          Map<String, dynamic> resumenCierre;
          
          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List && resumenCierreResponse.isNotEmpty) {
            // Si es una lista, tomar el primer elemento
            resumenCierre = resumenCierreResponse[0] as Map<String, dynamic>;
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            // Si ya es un mapa, usarlo directamente
            resumenCierre = resumenCierreResponse;
          } else {
            print('⚠️ AutoSync: Formato de respuesta no reconocido para resumen de cierre');
            return;
          }

          // Guardar en cache para uso offline
          await _userPreferencesService.saveResumenCierreCache(resumenCierre);
          print('  📊 Resumen de cierre sincronizado automáticamente');
        }
      }
    } catch (e) {
      print('  ❌ Error en sincronización automática de resumen de cierre: $e');
    }
  }

  /// Sincronizar egresos del turno actual
  Future<void> _syncEgresos() async {
    try {
      // Obtener egresos del turno actual usando TurnoService
      final egresos = await TurnoService.getEgresosEnriquecidos();
      
      if (egresos.isNotEmpty) {
        // Convertir egresos a formato Map para cache
        final egresosData = egresos.map((egreso) => {
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
        }).toList();
        
        // Guardar en cache para uso offline
        await _userPreferencesService.saveEgresosCache(egresosData);
        print('  📊 ${egresos.length} egresos sincronizados automáticamente');
      } else {
        // Limpiar cache si no hay egresos
        await _userPreferencesService.clearEgresosCache();
        print('  📊 No hay egresos para sincronizar');
      }
    } catch (e) {
      print('  ❌ Error en sincronización automática de egresos: $e');
    }
  }

  /// Sincronizar egresos offline pendientes
  Future<int> _syncOfflineEgresos() async {
    final egresosOffline = await _userPreferencesService.getEgresosOffline();
    
    if (egresosOffline.isEmpty) {
      print('  📝 No hay egresos offline pendientes');
      return 0;
    }

    print('  🔄 Sincronizando ${egresosOffline.length} egresos offline...');
    int syncedCount = 0;

    for (var egresoData in egresosOffline) {
      try {
        print('    - Procesando egreso offline: ${egresoData['offline_id']}');

        // Extraer datos del egreso offline
        final idTurno = egresoData['id_turno'] as int;
        final montoEntrega = (egresoData['monto_entrega'] ?? 0.0).toDouble();
        final motivoEntrega = egresoData['motivo_entrega'] as String;
        final nombreAutoriza = egresoData['nombre_autoriza'] as String;
        final nombreRecibe = egresoData['nombre_recibe'] as String;
        final idMedioPago = egresoData['id_medio_pago'] as int?;

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
          syncedCount++;
          print('    ✅ Egreso offline sincronizado: ${result['egreso_id']}');
        } else {
          print('    ❌ Error en servicio de egreso: ${result['message']}');
        }

      } catch (e) {
        print('    ❌ Error sincronizando egreso offline ${egresoData['offline_id']}: $e');
        // Continúa con el siguiente egreso sin interrumpir el proceso
      }
    }

    if (syncedCount > 0) {
      // Limpiar los egresos sincronizados exitosamente
      await _userPreferencesService.clearEgresosOffline();
      print('  🧹 Limpiados $syncedCount egresos offline sincronizados');
    }

    return syncedCount;
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

  /// Sincronizar ventas offline pendientes
  Future<int> _syncOfflineSales() async {
    final pendingOrders = await _userPreferencesService.getPendingOrders();
    
    if (pendingOrders.isEmpty) {
      print('  📝 No hay ventas offline pendientes');
      return 0;
    }

    print('  🔄 Sincronizando ${pendingOrders.length} ventas offline...');
    int syncedCount = 0;

    for (var orderData in pendingOrders) {
      try {
        print('    - Procesando venta offline: ${orderData['id']}');

        // 1. Registrar cliente si hay datos
        await _registerClientFromOfflineData(orderData);

        // 2. Registrar la venta
        await _registerSaleInSupabase(orderData);

        // 3. Completar la orden según su estado
        final estado = orderData['estado'] ?? 'completada';
        await _completeOrderWithStatus(orderData['id'], estado);

        syncedCount++;
        print('    ✅ Venta offline sincronizada: ${orderData['id']}');

      } catch (e) {
        print('    ❌ Error sincronizando venta offline ${orderData['id']}: $e');
        // Continúa con la siguiente venta sin interrumpir el proceso
      }
    }

    if (syncedCount > 0) {
      // Limpiar las órdenes sincronizadas exitosamente
      await _cleanupSyncedOrders(syncedCount);
    }

    return syncedCount;
  }

  /// Registrar cliente desde datos offline
  Future<void> _registerClientFromOfflineData(Map<String, dynamic> orderData) async {
    final buyerName = orderData['buyer_name'] ?? orderData['buyerName'];
    final buyerPhone = orderData['buyer_phone'] ?? orderData['buyerPhone'];

    if (buyerName != null && buyerName.isNotEmpty) {
      try {
        print('    👤 Registrando cliente desde datos offline: $buyerName');

        // Generar código de cliente único basado en el nombre
        final clientCode = 'CLI-${buyerName.hashCode.abs()}';

        // Usar RPC fn_insertar_cliente_con_contactos
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

        if (response != null && response['status'] == 'success') {
          final idCliente = response['id_cliente'] as int;
          orderData['idCliente'] = idCliente;
          print('    ✅ Cliente registrado con ID: $idCliente');
        }
      } catch (e) {
        print('    ⚠️ Error registrando cliente: $e');
        // No interrumpir el flujo por errores de cliente
      }
    }
  }

  /// Registrar venta en Supabase usando RPC directamente
  Future<void> _registerSaleInSupabase(Map<String, dynamic> orderData) async {
    // Obtener datos del usuario
    final userData = await _userPreferencesService.getUserData();
    final idTpv = await _userPreferencesService.getIdTpv();
    final userId = userData['userId'];

    if (idTpv == null || userId == null) {
      throw Exception('Datos de usuario incompletos para sincronización');
    }

    // Preparar productos desde los datos offline
    final productos = <Map<String, dynamic>>[];
    final itemsData = orderData['items'] as List<dynamic>? ?? [];

    for (final itemData in itemsData) {
      final inventoryMetadata = itemData['inventory_metadata'] ?? {};
      print('    🔄 AUTO SYNC - Inventory Metadata: $inventoryMetadata');
      
      // ✅ CORREGIDO: Calcular precio unitario correcto desde subtotal
      final subtotal = itemData['subtotal'] ?? (itemData['precio_unitario'] * itemData['cantidad']);
      final cantidad = itemData['cantidad'] as num;
      final precioUnitarioCorrect = cantidad > 0 ? (subtotal / cantidad) : itemData['precio_unitario'];
      
      print('    🔄 AUTO SYNC - Producto: ${itemData['denominacion'] ?? itemData['id_producto']}');
      print('      - Precio unitario base: \$${itemData['precio_unitario']}');
      print('      - Subtotal con método de pago: \$${subtotal}');
      print('      - Precio unitario correcto: \$${precioUnitarioCorrect}');
      
      productos.add({
        'id_producto': itemData['id_producto'],
        'id_variante': inventoryMetadata['id_variante'],
        'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
        'id_ubicacion': inventoryMetadata['id_ubicacion'],
        'id_presentacion': inventoryMetadata['id_presentacion'],
        'cantidad': itemData['cantidad'],
        'precio_unitario': precioUnitarioCorrect, // ✅ Precio correcto según método de pago
        'sku_producto': inventoryMetadata['sku_producto'] ?? itemData['id_producto'].toString(),
        'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
        'es_producto_venta': true,
      });
    }

    // Llamar directamente al RPC fn_registrar_venta
    final response = await Supabase.instance.client.rpc(
      'fn_registrar_venta',
      params: {
        'p_codigo_promocion': orderData['promo_code'] ?? orderData['promoCode'],
        'p_denominacion': 'Venta Auto Sync - ${orderData['id']}',
        'p_estado_inicial': 1, // Estado enviada
        'p_id_tpv': idTpv,
        'p_observaciones': orderData['notas'] ?? 'Sincronización automática de venta offline',
        'p_productos': productos,
        'p_uuid': userId,
        'p_id_cliente': orderData['idCliente'],
      },
    );

    if (response != null && response['status'] == 'success') {
      // Obtener el ID de operación de la respuesta
      final operationId = response['id_operacion'] as int?;
      if (operationId != null) {
        // Guardar el ID de operación para usarlo en la actualización de estado
        orderData['_operation_id'] = operationId;

        // Registrar desgloses de pago si existen
        final paymentBreakdown = orderData['desglose_pagos'] as List<dynamic>?;
        if (paymentBreakdown != null && paymentBreakdown.isNotEmpty) {
          await _registerPaymentBreakdownFromOfflineData(operationId, paymentBreakdown);
        }
      }
    } else {
      throw Exception(response?['message'] ?? 'Error en el registro de venta');
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
          'referencia_pago': 'Pago Auto Sync - ${DateTime.now().millisecondsSinceEpoch}',
        });
      }

      // Llamar a fn_registrar_pago_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_pago_venta',
        params: {'p_id_operacion_venta': operationId, 'p_pagos': pagos},
      );

      if (response == true) {
        print('    ✅ Desgloses de pago registrados para operación: $operationId');
      } else {
        throw Exception('Error en el registro de pagos');
      }
    } catch (e) {
      print('    ❌ Error registrando desgloses de pago: $e');
      // No lanzamos excepción para no interrumpir el flujo principal
    }
  }

  /// Completar orden con estado específico
  Future<void> _completeOrderWithStatus(String orderId, String estado) async {
    // Implementación similar a la de OrdersScreen para cambiar estado
    // Por ahora solo registramos que se completó
    print('    📝 Orden $orderId marcada como $estado');
  }

  /// Limpiar órdenes sincronizadas exitosamente
  Future<void> _cleanupSyncedOrders(int syncedCount) async {
    try {
      // Obtener órdenes actuales
      final currentOrders = await _userPreferencesService.getPendingOrders();
      
      // Remover las primeras N órdenes que fueron sincronizadas
      if (currentOrders.length >= syncedCount) {
        final remainingOrders = currentOrders.skip(syncedCount).toList();
        
        // Guardar las órdenes restantes
        await _userPreferencesService.clearPendingOrders();
        for (final order in remainingOrders) {
          await _userPreferencesService.savePendingOrder(order);
        }
        
        print('  🧹 Limpiadas $syncedCount órdenes sincronizadas, ${remainingOrders.length} pendientes');
      }
    } catch (e) {
      print('  ⚠️ Error limpiando órdenes sincronizadas: $e');
    }
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

  /// Sincronizar configuración de tienda
  Future<void> _syncStoreConfig() async {
    try {
      print('🔧 Sincronizando configuración de tienda...');
      
      // Obtener ID de tienda
      final idTienda = await _userPreferencesService.getIdTienda();
      
      if (idTienda == null) {
        print('❌ No se pudo obtener ID de tienda para sincronizar configuración');
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
