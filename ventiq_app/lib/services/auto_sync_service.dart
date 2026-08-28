import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'category_service.dart';
import 'product_service.dart';
import 'payment_method_service.dart';
import '../models/payment_method.dart' as pm;
import 'turno_service.dart';
import 'reauthentication_service.dart';
import 'store_config_service.dart';
import 'shift_workers_service.dart';
import 'promotion_service.dart';
import 'product_detail_service.dart';
import 'offline_license_service.dart';
import 'admin_inventory_service.dart';
import 'inventory_service.dart';
import 'offline_database_service.dart';
import 'order_service.dart';
import 'connectivity_service.dart';
import '../models/order.dart';
import '../utils/uuid_generator.dart';

/// Servicio para sincronización automática periódica de datos
/// Se ejecuta cuando el modo offline NO está activado para mantener datos actualizados
class AutoSyncService {
  static final AutoSyncService _instance = AutoSyncService._internal();
  factory AutoSyncService() => _instance;
  AutoSyncService._internal();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final ReauthenticationService _reauthService = ReauthenticationService();
  final PromotionService _promotionService = PromotionService();
  final ProductDetailService _productDetailService = ProductDetailService();

  Timer? _syncTimer;
  bool _isRunning = false;
  bool _isSyncing = false;
  bool _pendingSyncRequested = false;
  bool _pendingReconnectSync = false;
  DateTime? _lastSyncTime;
  DateTime? _lastReconnectSyncAt;
  int _syncCount = 0;

  // Configuración
  static const Duration _syncInterval = Duration(minutes: 1); // Cada 1 minuto
  static const Duration _syncTimeout = Duration(
    minutes: 5,
  ); // Timeout de 5 minutos
  /// Evita sync ligera en ráfaga (Wi‑Fi inestable, resume + stream duplicado).
  static const Duration _reconnectSyncDebounce = Duration(seconds: 45);

  // Stream para notificar eventos de sincronización
  final StreamController<AutoSyncEvent> _syncEventController =
      StreamController<AutoSyncEvent>.broadcast();
  Stream<AutoSyncEvent> get syncEventStream => _syncEventController.stream;

  /// Estado actual del servicio
  bool get isRunning => _isRunning;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get syncCount => _syncCount;

  /// ¿Hay contexto mínimo (sesión + tienda) para sincronizar con el servidor?
  Future<bool> _canRunSync(String reason) async {
    if (await _userPreferencesService.isOfflineModeEnabled()) {
      print('🔌 Sync omitida ($reason): modo offline activo');
      return false;
    }

    final loggedIn = await _userPreferencesService.isLoggedIn();
    if (!loggedIn) {
      print('🚫 Sync omitida ($reason): no hay usuario logueado');
      return false;
    }

    final idTienda = await _userPreferencesService.getIdTienda();
    if (idTienda == null) {
      print('🚫 Sync omitida ($reason): sin tienda configurada');
      return false;
    }

    return true;
  }

  /// Iniciar la sincronización automática periódica
  Future<void> startAutoSync() async {
    if (_isRunning) {
      print('🔄 AutoSyncService ya está ejecutándose');
      return;
    }

    if (!await _canRunSync('startAutoSync')) {
      return;
    }

    print('🚀 Iniciando sincronización automática periódica...');
    print('⏰ Intervalo de sincronización: ${_syncInterval.inMinutes} minutos');

    _isRunning = true;

    // Pasada inicial completa (login / arranque con sesión).
    await _performSync();

    _startPeriodicSyncTimer();

    _syncEventController.add(
      AutoSyncEvent(
        type: AutoSyncEventType.started,
        timestamp: DateTime.now(),
        message: 'Sincronización automática iniciada',
      ),
    );

    print('✅ Sincronización automática iniciada');
  }

  /// Programa el timer periódico sin ejecutar sync inmediata (p.ej. tras reconexión).
  Future<void> ensurePeriodicSyncScheduled() async {
    if (_isRunning) return;
    if (!await _canRunSync('ensurePeriodicSyncScheduled')) return;

    print('⏰ Programando sync periódica (sin pasada completa inmediata)...');
    _isRunning = true;
    _startPeriodicSyncTimer();

    _syncEventController.add(
      AutoSyncEvent(
        type: AutoSyncEventType.started,
        timestamp: DateTime.now(),
        message: 'Sincronización periódica programada',
      ),
    );
  }

  void _startPeriodicSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) async {
      if (!_isRunning) return;

      if (!await _canRunSync('timer')) {
        await stopAutoSync();
        return;
      }

      await _performSync();
    });
  }

  /// Sync ligera al recuperar conexión: sube pendientes + datos operativos del
  /// turno. **No** baja catálogo completo (productos/categorías/layouts).
  Future<void> performReconnectSync() async {
    if (!await _canRunSync('performReconnectSync')) return;

    final now = DateTime.now();
    if (_lastReconnectSyncAt != null &&
        now.difference(_lastReconnectSyncAt!) < _reconnectSyncDebounce) {
      print(
        '⏳ Sync por reconexión omitida (debounce '
        '${_reconnectSyncDebounce.inSeconds}s)',
      );
      return;
    }

    if (_isSyncing) {
      _pendingReconnectSync = true;
      print('⏳ Sync en curso; reconexión encolada');
      return;
    }

    _lastReconnectSyncAt = now;
    _isSyncing = true;

    try {
      print('📶 Sync ligera por reconexión (pendientes + turno)...');
      await syncModules(_modulesForReconnectPass(), acquireLock: false);
      print('✅ Sync ligera por reconexión completada');
    } catch (e) {
      print('❌ Error en sync por reconexión: $e');
      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncFailed,
          timestamp: DateTime.now(),
          message: 'Error en sync por reconexión: $e',
          error: e.toString(),
        ),
      );
    } finally {
      _isSyncing = false;
      if (_pendingReconnectSync) {
        _pendingReconnectSync = false;
        unawaited(performReconnectSync());
      }
    }
  }

  /// Ejecutar una sincronización inmediata sin iniciar el timer periódico
  /// Útil para ejecutar la primera sincronización rápidamente
  Future<void> performImmediateSync() async {
    try {
      print('⚡ Ejecutando sincronización inmediata...');

      if (!await _canRunSync('performImmediateSync')) {
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

    // ⚠️ Limpiar cualquier pase encolado: si una sincronización está corriendo
    // y dejó pendiente otra pasada (ver finally de _performSync), NO debe
    // relanzarse después de detener el servicio (p. ej. al activar modo
    // offline), porque sobrescribiría el estado offline con datos del servidor.
    _pendingSyncRequested = false;

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

  /// Realizar una sincronización completa (delega en [syncModules]).
  Future<void> _performSync() async {
    if (!await _canRunSync('_performSync')) {
      _pendingSyncRequested = false;
      return;
    }

    // Guarda defensiva: si el modo offline ya está activado, no sincronizar.
    // (La prep admin / sync selectiva usa [syncModules] directamente.)
    if (await _userPreferencesService.isOfflineModeEnabled()) {
      print('🔌 Modo offline activado - Omitiendo _performSync');
      _pendingSyncRequested = false;
      return;
    }

    if (_isSyncing) {
      _pendingSyncRequested = true;
      print('⏳ Sincronización en progreso; se encola una nueva al terminar');
      return;
    }

    _isSyncing = true;

    try {
      print('🔄 Iniciando sincronización automática #${_syncCount + 1}...');
      final modules = _modulesForAutoSyncPass();
      final result = await syncModules(modules, acquireLock: false);

      if (result.syncedItems.isNotEmpty || result.success) {
        _lastSyncTime = DateTime.now();
        _syncCount++;
      }

      print(
        '✅ Sincronización automática #$_syncCount '
        'en ${result.duration.inSeconds}s '
        '(${result.syncedItems.join(", ")})',
      );
      if (result.errors.isNotEmpty) {
        print('⚠️ Errores parciales: ${result.errors.join("; ")}');
      }
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

      if (_pendingSyncRequested) {
        _pendingSyncRequested = false;
        print('🔁 Ejecutando sincronización encolada...');
        unawaited(_performSync());
      }
    }
  }

  /// Módulos de la pasada automática (respeta frecuencias periódicas).
  Set<SyncModule> _modulesForAutoSyncPass() {
    final modules = <SyncModule>{
      SyncModule.uploadTurno,
      SyncModule.uploadSales,
      SyncModule.uploadEgresos,
      SyncModule.uploadShiftWorkers,
      SyncModule.uploadAdminOps,
      SyncModule.license,
      SyncModule.paymentMethods,
      SyncModule.credentials,
      SyncModule.promotions,
      SyncModule.storeConfig,
      SyncModule.turno,
      SyncModule.egresos,
    };

    if (_syncCount == 0 || _syncCount % 3 == 0) {
      modules.add(SyncModule.categories);
    }
    if (_syncCount == 0 || _syncCount % 5 == 0) {
      modules.add(SyncModule.products);
      modules.add(SyncModule.layouts);
    }
    if (_syncCount % 2 == 0) {
      modules.add(SyncModule.orders);
    }

    return modules;
  }

  /// Pasada al recuperar conexión: prioriza subir pendientes y refrescar turno.
  Set<SyncModule> _modulesForReconnectPass() {
    return {
      SyncModule.uploadTurno,
      SyncModule.uploadSales,
      SyncModule.uploadEgresos,
      SyncModule.uploadShiftWorkers,
      SyncModule.uploadAdminOps,
      SyncModule.license,
      SyncModule.storeConfig,
      SyncModule.paymentMethods,
      SyncModule.promotions,
      SyncModule.turno,
      SyncModule.egresos,
      SyncModule.orders,
    };
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
    final idTienda = await _userPreferencesService.getIdTienda();
    if (idTienda == null) {
      print('  ⚠️ No se pudo obtener ID de tienda para promociones');
      return {};
    }

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
      print('  🎯 Promoción global actualizada');
    } else {
      await _promotionService.saveGlobalPromotion(
        idPromocion: null,
        codigoPromocion: null,
        valorDescuento: null,
        tipoDescuento: null,
      );
      print('  ℹ️ No hay promoción global activa');
    }

    return globalPromotion ?? {};
  }

  /// Sincronizar métodos de pago
  Future<List<Map<String, dynamic>>> _syncPaymentMethods() async {
    final paymentMethods = await PaymentMethodService.getActivePaymentMethods();

    if (paymentMethods.isEmpty) {
      final offlineData = await _userPreferencesService.getOfflineData();
      final cached = offlineData?['payment_methods'];
      if (cached is List) {
        print('  ⚠️ Sin métodos de pago en línea - usando cache offline');
        return List<Map<String, dynamic>>.from(cached);
      }
    }

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
    print(
      '🔄 AutoSync: Sincronizando productos de ${categories.length} categorías...',
    );

    for (var category in categories) {
      // Sincronizar todas las categorías para cobertura completa
      print('  📂 Procesando categoría: ${category.name} (ID: ${category.id})');
      final productsMap = await productService.getProductsByCategory(
        category.id,
      );
      final List<Map<String, dynamic>> allProducts = [];

      // 1) Aplanar todas las subcategorías a una sola lista de productos de la
      //    categoría (sin pedir detalles todavía), conservando 'subcategoria'.
      for (var entry in productsMap.entries) {
        final subcategory = entry.key;
        final products = entry.value;

        print(
          '    📦 Subcategoría "$subcategory": ${products.length} productos',
        );

        for (var prod in products) {
          allProducts.add(<String, dynamic>{
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

      // 2) 🚀 BATCH POR CATEGORÍA: obtener los detalles completos de TODOS los
      //    productos de la categoría en UNA sola llamada (antes era 1 RPC por
      //    subcategoría; igualamos el patrón ya usado para presentaciones).
      if (allProducts.isNotEmpty) {
        final productIds = allProducts.map((p) => p['id'] as int).toList();
        Map<int, dynamic> detallesPorId = {};
        try {
          detallesPorId = await _productDetailService.getProductDetailsBatch(
            productIds,
          );
          print(
            '    ✅ Detalles batch (categoría): ${detallesPorId.length}/${productIds.length}',
          );
        } catch (e) {
          print('    ⚠️ Error obteniendo detalles batch de categoría: $e');
        }

        // Solo añadir detalles_completos si vinieron del servidor; si no, el
        // producto queda con datos básicos (igual que el fallback previo).
        for (var product in allProducts) {
          final detalle = detallesPorId[product['id'] as int];
          if (detalle != null) {
            product['detalles_completos'] = detalle;
            _normalizeInventarioUbicaciones(product);
            _alignProductCantidadWithInventario(product);
          }
        }
      }

      // 🎯 OPTIMIZACIÓN: Obtener presentaciones en batch para TODOS los productos de la categoría
      if (allProducts.isNotEmpty) {
        try {
          final productIds = allProducts.map((p) => p['id'] as int).toList();
          print(
            '  📦 Obteniendo presentaciones para ${productIds.length} productos en batch...',
          );

          // Una sola consulta con WHERE IN para todas las presentaciones
          final allPresentations = await Supabase.instance.client
              .from('app_dat_producto_presentacion')
              .select('''
                id,
                id_producto,
                id_presentacion,
                cantidad,
                es_base,
                presentacion:app_nom_presentacion!inner(
                  id,
                  denominacion,
                  descripcion,
                  sku_codigo,
                  es_fraccionable
                )
              ''')
              .inFilter('id_producto', productIds)
              .order('es_base', ascending: false);

          print('  ✅ ${allPresentations.length} presentaciones obtenidas');

          // Agrupar presentaciones por id_producto
          final Map<int, List<dynamic>> presentationsByProduct = {};
          for (var presentation in allPresentations) {
            final productId = presentation['id_producto'] as int;
            if (!presentationsByProduct.containsKey(productId)) {
              presentationsByProduct[productId] = [];
            }
            presentationsByProduct[productId]!.add(presentation);
          }

          // Asignar presentaciones a cada producto
          for (var product in allProducts) {
            final productId = product['id'] as int;
            product['presentaciones'] = presentationsByProduct[productId] ?? [];
          }

          print(
            '  ✅ Presentaciones asignadas a ${productIds.length} productos',
          );
        } catch (presError) {
          print('  ⚠️ Error obteniendo presentaciones en batch: $presError');
          // Si falla, los productos quedan sin presentaciones (array vacío)
          for (var product in allProducts) {
            product['presentaciones'] = [];
          }
        }
      }

      // Métricas de ubicación para diagnóstico.
      var withDetalles = 0;
      var withUbicacion = 0;
      for (final p in allProducts) {
        if (p['detalles_completos'] != null) withDetalles++;
        if (p['ubicacion_nombre'] != null &&
            p['ubicacion_nombre'].toString().isNotEmpty) {
          withUbicacion++;
        }
      }
      print(
        '  📍 Categoría "${category.name}": '
        '$withDetalles/${allProducts.length} productos con detalles, '
        '$withUbicacion con ubicación',
      );

      productsByCategory[category.id.toString()] = allProducts;
      print(
        '  ✅ Categoría "${category.name}": ${allProducts.length} productos sincronizados',
      );
    }

    final totalProducts = productsByCategory.values.fold(
      0,
      (sum, list) => sum + list.length,
    );
    print('🎉 AutoSync: Total de productos sincronizados: $totalProducts');
    return productsByCategory;
  }

  /// Si el detalle trae inventario con stock, alinea `cantidad` del listado.
  /// Si el inventario viene vacío, conserva la cantidad del listado (RPC).
  void _alignProductCantidadWithInventario(Map<String, dynamic> product) {
    final detalle = product['detalles_completos'];
    if (detalle is! Map) return;
    final inv = detalle['inventario'];
    if (inv is! List || inv.isEmpty) return;

    num sum = 0;
    for (final row in inv) {
      if (row is Map) {
        sum += (row['cantidad_disponible'] as num?) ?? 0;
      }
    }
    if (sum > 0) {
      product['cantidad'] = sum;
    }
  }

  /// Aplana `ubicacion` anidada del RPC a campos que Admin Lite / POS usan:
  /// `id_ubicacion`, `ubicacion_nombre`, `denominacion_ubicacion`, `almacen_nombre`.
  void _normalizeInventarioUbicaciones(Map<String, dynamic> product) {
    final detalle = product['detalles_completos'];
    if (detalle is! Map) return;
    final invRaw = detalle['inventario'];
    if (invRaw is! List || invRaw.isEmpty) return;

    final normalized = <Map<String, dynamic>>[];
    for (final row in invRaw) {
      if (row is! Map) continue;
      final inv = Map<String, dynamic>.from(row);
      final ubicacion = inv['ubicacion'] is Map
          ? Map<String, dynamic>.from(inv['ubicacion'] as Map)
          : null;
      final almacen = ubicacion?['almacen'] is Map
          ? Map<String, dynamic>.from(ubicacion!['almacen'] as Map)
          : null;

      final idUbicacion = (inv['id_ubicacion'] as num?)?.toInt() ??
          (ubicacion?['id'] as num?)?.toInt();
      final nombreUbicacion = inv['ubicacion_nombre']?.toString() ??
          inv['denominacion_ubicacion']?.toString() ??
          ubicacion?['denominacion']?.toString();
      final nombreAlmacen = inv['almacen_nombre']?.toString() ??
          almacen?['denominacion']?.toString();

      if (idUbicacion != null) {
        inv['id_ubicacion'] = idUbicacion;
      }
      if (nombreUbicacion != null && nombreUbicacion.isNotEmpty) {
        inv['ubicacion_nombre'] = nombreUbicacion;
        inv['denominacion_ubicacion'] = nombreUbicacion;
        // String corto para UIs que hacen `ubicacion.toString()` sobre el map.
        if (inv['ubicacion'] is! String) {
          inv['ubicacion_label'] = nombreUbicacion;
        }
      }
      if (nombreAlmacen != null && nombreAlmacen.isNotEmpty) {
        inv['almacen_nombre'] = nombreAlmacen;
      }
      if (ubicacion != null && inv['sku_ubicacion'] == null) {
        inv['sku_ubicacion'] = ubicacion['sku_codigo'];
      }
      normalized.add(inv);
    }

    product['detalles_completos'] = {
      ...Map<String, dynamic>.from(detalle),
      'inventario': normalized,
    };

    // Primer ubicación a nivel producto (atajos admin / ajuste).
    final first = normalized.isNotEmpty ? normalized.first : null;
    if (first != null) {
      if (first['id_ubicacion'] != null) {
        product['id_ubicacion'] = first['id_ubicacion'];
      }
      if (first['ubicacion_nombre'] != null) {
        product['ubicacion_nombre'] = first['ubicacion_nombre'];
      }
      if (first['almacen_nombre'] != null) {
        product['almacen_nombre'] = first['almacen_nombre'];
      }
    }
  }

  /// Sincronizar promociones específicas por producto
  Future<int> _syncProductPromotions(Map<String, dynamic> productsData) async {
    final productIds = _extractProductIdsFromProductsData(productsData);

    if (productIds.isEmpty) {
      return 0;
    }

    print(
      '  🎯 Sincronizando promociones de ${productIds.length} productos...',
    );

    int productsWithPromotions = 0;

    // 🚀 BATCH: todas las promociones de todos los productos en UNA llamada.
    final promosPorProducto = await _promotionService.getProductPromotionsBatch(
      productIds,
    );

    // Persistir por producto. Para los que no tienen promos, guardar lista
    // vacía para limpiar promos viejas que ya no apliquen.
    for (final productId in productIds) {
      final promotions = promosPorProducto[productId] ?? const [];
      try {
        await _userPreferencesService.saveProductPromotions(
          productId,
          List<Map<String, dynamic>>.from(promotions),
        );
        if (promotions.isNotEmpty) productsWithPromotions++;
      } catch (e) {
        print('  ❌ Error guardando promociones del producto $productId: $e');
      }
    }

    return productsWithPromotions;
  }

  List<int> _extractProductIdsFromProductsData(
    Map<String, dynamic> productsData,
  ) {
    final ids = <int>{};

    for (final categoryProducts in productsData.values) {
      if (categoryProducts is List) {
        for (final product in categoryProducts) {
          if (product is Map<String, dynamic>) {
            final rawId = product['id'] ?? product['id_producto'];
            if (rawId is int) {
              ids.add(rawId);
            } else if (rawId is num) {
              ids.add(rawId.toInt());
            }
          }
        }
      }
    }

    return ids.toList();
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

  /// Resuelve el UUID EXACTO que exige `cerrar_turno` en el servidor para
  /// poder cerrar el turno abierto de [idTpv].
  ///
  /// La función real (`fn_cerrar_turno_tpv`, verificada directamente en la
  /// base) filtra así:
  /// ```sql
  /// WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1 AND ct.creado_por = p_usuario
  /// ```
  /// Es decir, `p_usuario` debe coincidir con `app_dat_caja_turno.creado_por`
  /// (el usuario que ejecutó la apertura), NO con el UUID del vendedor en
  /// `app_dat_vendedor.uuid` (son campos distintos; usar el segundo es lo
  /// que causaba que el cierre siguiera fallando aunque "coincidiera" el
  /// vendedor). Se lee `creado_por` directo de la fila del turno.
  Future<String?> _resolveUsuarioForOpenTpvTurno(int idTpv) async {
    try {
      final turnoRow =
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .select('creado_por')
              .eq('id_tpv', idTpv)
              .eq('estado', 1)
              .order('fecha_apertura', ascending: false, nullsFirst: false)
              .limit(1)
              .maybeSingle();
      final creadoPor = turnoRow?['creado_por']?.toString();
      if (creadoPor != null && creadoPor.isNotEmpty) {
        print(
          '  🔎 Usuario real (creado_por) del turno TPV $idTpv → $creadoPor',
        );
        return creadoPor;
      }
      return null;
    } catch (e) {
      print(
        '  ⚠️ No se pudo resolver creado_por del turno abierto para TPV '
        '$idTpv: $e',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getOnlineOpenShift({
    required int idTpv,
    required int idVendedor,
  }) async {
    final response = await Supabase.instance.client
        .from('app_dat_caja_turno')
        .select('*')
        .eq('id_tpv', idTpv)
        .eq('id_vendedor', idVendedor)
        .eq('estado', 1)
        .order('fecha_apertura', ascending: false, nullsFirst: false)
        .limit(1);

    if (response.isNotEmpty) {
      return response.first;
    }

    return null;
  }

  int? _parseTurnoId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  Future<bool> _isServerTurnoOpen(int serverId) async {
    try {
      final row =
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .select('id, estado')
              .eq('id', serverId)
              .maybeSingle();
      return row != null && (row['estado'] as num?)?.toInt() == 1;
    } catch (e) {
      print('  ⚠️ No se pudo verificar estado del turno $serverId: $e');
      return false;
    }
  }

  /// Diagnostica un turno `closed_pending_sync` atascado: consulta en el
  /// servidor el estado real y el `id_tpv` real del turno para detectar
  /// discrepancias. Caso típico: el turno sigue abierto en el servidor pero
  /// para un TPV distinto al guardado localmente, por lo que
  /// `fn_cerrar_turno_offline`/`cerrar_turno` (que busca por TPV) nunca lo
  /// encuentra y el cierre queda atascado en la cola para siempre.
  Future<Map<String, dynamic>> diagnoseStuckTurno(String localId) async {
    final entry = await _userPreferencesService.getOfflineTurnoByLocalId(
      localId,
    );
    if (entry == null) {
      return {
        'found': false,
        'message': 'El turno ya no está en la cola local.',
      };
    }

    final serverId = _parseTurnoId(entry['server_id_turno']);
    if (serverId == null) {
      return {
        'found': true,
        'hasServerId': false,
        'message':
            'Este turno nunca llegó a abrirse en el servidor '
            '(sin server_id_turno registrado).',
      };
    }

    try {
      final row =
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .select('id, id_tpv, id_vendedor, estado')
              .eq('id', serverId)
              .maybeSingle();

      if (row == null) {
        return {
          'found': true,
          'hasServerId': true,
          'serverId': serverId,
          'existsOnServer': false,
          'message': 'El turno $serverId ya no existe en el servidor.',
        };
      }

      final serverEstado = (row['estado'] as num?)?.toInt();
      final serverIdTpv = _parseTurnoId(row['id_tpv']);
      final localIdTpv = _parseTurnoId(entry['id_tpv']);
      final tpvMismatch =
          serverIdTpv != null &&
          localIdTpv != null &&
          serverIdTpv != localIdTpv;

      return {
        'found': true,
        'hasServerId': true,
        'serverId': serverId,
        'existsOnServer': true,
        'serverEstado': serverEstado,
        'serverIsOpen': serverEstado == 1,
        'serverIdTpv': serverIdTpv,
        'localIdTpv': localIdTpv,
        'tpvMismatch': tpvMismatch,
        'message':
            tpvMismatch
                ? 'El turno $serverId sigue abierto en el servidor pero para '
                    'el TPV $serverIdTpv, no para el TPV $localIdTpv guardado '
                    'localmente. Por eso el cierre falla ("no se encontró un '
                    'turno abierto para el TPV $localIdTpv").'
                : (serverEstado == 1
                    ? 'El turno $serverId sigue abierto en el servidor '
                        '(TPV $serverIdTpv).'
                    : 'El turno $serverId ya está cerrado en el servidor '
                        '(estado=$serverEstado).'),
      };
    } catch (e) {
      return {
        'found': true,
        'error': e.toString(),
        'message': 'No se pudo consultar el servidor: $e',
      };
    }
  }

  /// Reconciliación automática y silenciosa de la cola de turnos offline
  /// contra el estado real del servidor. Pensada para llamarse antes de
  /// mostrar avisos de "hay datos sin sincronizar" (p.ej. al cerrar sesión):
  /// si una entrada local quedó huérfana (el servidor ya no la tiene abierta
  /// o ya no existe, algo que puede pasar tras resoluciones manuales o
  /// cierres hechos desde el backoffice), se retira de la cola local sin
  /// pedir confirmación. Nunca fuerza el cierre de un turno que el servidor
  /// SÍ reporta como abierto (eso requiere el flujo normal o la resolución
  /// manual desde Admin). Requiere conexión; si falla, no hace nada.
  Future<void> reconcileStaleOfflineTurnos() async {
    List<Map<String, dynamic>> pending;
    try {
      pending = await _userPreferencesService.getOfflineTurnosPendingSync();
    } catch (e) {
      print('⚠️ reconcileStaleOfflineTurnos: no se pudo leer la cola: $e');
      return;
    }
    if (pending.isEmpty) return;

    for (final t in pending) {
      final localId = t['local_id']?.toString();
      if (localId == null || localId.isEmpty) continue;
      try {
        final diag = await diagnoseStuckTurno(localId);
        final orphaned =
            diag['found'] == true &&
            (diag['hasServerId'] != true ||
                diag['existsOnServer'] == false ||
                diag['serverIsOpen'] == false);
        if (orphaned) {
          print(
            '🧹 reconcileStaleOfflineTurnos: turno $localId huérfano '
            '(${diag['message']}); retirando de la cola local',
          );
          await _userPreferencesService.markOfflineTurnoSynced(localId);
        }
      } catch (e) {
        print('⚠️ reconcileStaleOfflineTurnos: error con $localId: $e');
      }
    }
  }

  /// Intenta resolver manualmente (desde Admin) un turno
  /// `closed_pending_sync` atascado que el replay normal no puede cerrar:
  ///  - Si el servidor ya no tiene ese turno abierto (cerrado o inexistente),
  ///    no hay nada que cerrar: se retira la entrada de la cola local.
  ///  - Si sigue abierto pero para un TPV distinto (ver [diagnoseStuckTurno]),
  ///    se reintenta el cierre usando el `id_tpv` REAL reportado por el
  ///    servidor en vez del guardado localmente.
  Future<Map<String, dynamic>> forceResolveStuckTurno(String localId) async {
    final diag = await diagnoseStuckTurno(localId);
    if (diag['found'] != true) {
      return {'success': false, 'message': diag['message']};
    }

    // Sin server_id o turno inexistente en servidor: no hay nada que cerrar
    // remotamente. Descartar la entrada local (turno huérfano).
    if (diag['hasServerId'] != true || diag['existsOnServer'] == false) {
      final removed = await _userPreferencesService.markOfflineTurnoSynced(
        localId,
      );
      return {
        'success': removed,
        'discarded': true,
        'message':
            removed
                ? '${diag['message']} Se retiró de la cola local.'
                : 'No se pudo retirar el turno de la cola local.',
      };
    }

    if (diag['serverIsOpen'] != true) {
      // Ya cerrado en servidor: nada que cerrar, solo purgar localmente.
      final removed = await _userPreferencesService.markOfflineTurnoSynced(
        localId,
      );
      return {
        'success': removed,
        'discarded': true,
        'message':
            removed
                ? 'El turno ya estaba cerrado en el servidor; se retiró de '
                    'la cola local.'
                : 'No se pudo retirar el turno de la cola local.',
      };
    }

    final entry = await _userPreferencesService.getOfflineTurnoByLocalId(
      localId,
    );
    if (entry == null) {
      return {'success': false, 'message': 'El turno ya no está en la cola.'};
    }

    // Sin datos de cierre locales (turno todavía "open", nunca se llegó a
    // pedir el cierre desde la app): no hay efectivo final/productos reales
    // que enviar, así que no se puede forzar un cierre aquí sin arriesgar
    // datos incorrectos. Sólo se informa al admin.
    final cierreRaw = entry['cierre'];
    if (cierreRaw is! Map) {
      return {
        'success': false,
        'message':
            'El turno sigue abierto en el servidor (TPV ${diag['serverIdTpv']}) '
            'y no tiene un cierre local pendiente de enviar. Debe cerrarse '
            'normalmente desde la app del vendedor (verifica que el TPV '
            'configurado en el dispositivo coincida con el TPV '
            '${diag['serverIdTpv']}).',
      };
    }

    // Sigue abierto y SÍ hay datos de cierre pendientes: reintentar con el
    // id_tpv REAL del servidor.
    final serverIdTpv = diag['serverIdTpv'] as int?;
    if (serverIdTpv == null) {
      return {
        'success': false,
        'message': 'No se pudo determinar el TPV real del turno en servidor.',
      };
    }

    // Ver comentario en `_clearStaleFechaCierre`: un `fecha_cierre` residual
    // de un cierre/apertura anterior puede hacer que `cerrar_turno` no
    // encuentre el turno como abierto aunque `estado=1`.
    final serverIdForCierre = diag['serverId'] as int?;
    if (serverIdForCierre != null) {
      await _clearStaleFechaCierre(serverIdForCierre);
    }

    final cierreData = Map<String, dynamic>.from(cierreRaw);
    // Igual que en _syncCierreForQueueEntry: priorizar el UUID real del
    // vendedor propietario del turno en el servidor.
    final resolvedRealUsuarioForce =
        await _resolveUsuarioForOpenTpvTurno(serverIdTpv);
    final aperturaRawForce = entry['apertura'];
    final aperturaUsuarioForce =
        aperturaRawForce is Map
            ? aperturaRawForce['usuario']?.toString()
            : null;
    final usuario =
        resolvedRealUsuarioForce ??
        ((aperturaUsuarioForce != null && aperturaUsuarioForce.isNotEmpty)
            ? aperturaUsuarioForce
            : (entry['usuario'] ?? cierreData['usuario']));
    final efectivoFinal = cierreData['efectivo_final'] ?? 0.0;
    final observaciones = cierreData['observaciones'] as String?;
    final productos =
        (cierreData['productos'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final clientUuid =
        entry['client_uuid_cierre']?.toString() ??
        cierreData['client_uuid']?.toString() ??
        UuidGenerator.v4();

    try {
      final resp = await Supabase.instance.client.rpc(
        'fn_cerrar_turno_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_tpv': serverIdTpv,
          'p_efectivo_real': efectivoFinal,
          'p_usuario': usuario,
          'p_productos': productos,
          'p_observaciones': observaciones,
        },
      );
      final map = _asRpcMap(resp);
      final ok = _rpcStatusSuccess(map);
      if (ok) {
        final removed = await _userPreferencesService.markOfflineTurnoSynced(
          localId,
          serverIdTurno: serverIdForCierre,
        );
        return {
          'success': removed,
          'message':
              'Cierre forzado con el TPV real ($serverIdTpv) exitoso.',
        };
      }
      return {
        'success': false,
        'message':
            'El servidor rechazó el cierre incluso con el TPV correcto: '
            '${map?['message'] ?? resp}',
      };
    } catch (e) {
      return {'success': false, 'message': 'Error forzando el cierre: $e'};
    }
  }

  /// Garantiza que la entrada de la cola tenga un `usuario` (UUID) válido
  /// guardado (a nivel superior y dentro de `apertura`). Si falta —típico
  /// en entradas antiguas o en turnos abiertos online y luego cacheados—
  /// usa como fallback el usuario actualmente autenticado y PERSISTE el
  /// resultado, para que apertura y cierre usen siempre el mismo usuario
  /// (`cerrar_turno` resuelve el vendedor a partir de `p_usuario`; si no
  /// coincide con el que abrió el turno, el servidor no lo encuentra).
  /// Devuelve el usuario resuelto, o `null` si no hay ninguno disponible.
  Future<String?> _ensureEntryHasUsuario(
    Map<String, dynamic> entry,
    Map<String, dynamic> aperturaData,
    String localId,
  ) async {
    var usuario =
        (aperturaData['usuario'] ?? entry['usuario'] ?? '').toString();
    if (usuario.isNotEmpty) return usuario;

    final userData = await _userPreferencesService.getUserData();
    usuario = (userData['userId'] ?? '').toString();
    if (usuario.isEmpty) {
      print(
        '  ❌ Turno $localId sin usuario válido (ni guardado ni '
        'autenticado)',
      );
      return null;
    }

    print(
      '  ⚠️ Turno $localId sin usuario guardado; usando usuario '
      'autenticado actual como fallback',
    );
    aperturaData['usuario'] = usuario;
    await _userPreferencesService.upsertOfflineTurno({
      ...entry,
      'usuario': usuario,
      'apertura': aperturaData,
    });
    return usuario;
  }

  /// Asegura en servidor la apertura de UN turno de la cola offline.
  /// Devuelve el `server_id_turno` (abierto) o null si falló.
  Future<int?> _ensureAperturaForQueueEntry(Map<String, dynamic> entry) async {
    final localId = entry['local_id']?.toString();
    if (localId == null) {
      print('[TURNO_SYNC] ❌ _ensureApertura: sin local_id');
      return null;
    }

    print(
      '[TURNO_SYNC] ▶ _ensureApertura START '
      '${UserPreferencesService.describeOfflineTurnoEntry(entry)}',
    );

    // Si ya hay server_id, solo reutilizarlo si SIGUE abierto.
    // Un id de un turno ya cerrado hace fallar el cierre ("no hay turno abierto").
    final existingRaw = entry['server_id_turno'];
    final existingId = _parseTurnoId(existingRaw);
    if (existingId != null) {
      final stillOpen = await _isServerTurnoOpen(existingId);
      print(
        '[TURNO_SYNC] _ensureApertura server_id=$existingId '
        'stillOpenOnServer=$stillOpen',
      );
      if (stillOpen) {
        print(
          '[TURNO_SYNC] ✅ reutiliza server_id=$existingId (sigue abierto)',
        );
        // Aunque el turno ya esté abierto (no se llama a la apertura RPC
        // en este camino), igualmente hay que garantizar que la entrada
        // tenga un `usuario` válido guardado: el cierre posterior lo usa
        // para que `cerrar_turno` resuelva el mismo vendedor. Sin este
        // chequeo aquí, una entrada antigua sin usuario nunca se corrige
        // porque este camino (turno ya abierto) nunca llega al bloque de
        // resolución de usuario más abajo.
        final aperturaRawEarly = entry['apertura'];
        final aperturaDataEarly =
            aperturaRawEarly is Map
                ? Map<String, dynamic>.from(aperturaRawEarly)
                : <String, dynamic>{};
        await _ensureEntryHasUsuario(entry, aperturaDataEarly, localId);
        await _clearStaleFechaCierre(existingId);
        return existingId;
      }

      // closed_pending cuyo server_id YA está cerrado: no reabrir.
      // El cierre ya se aplicó en servidor; el sync solo debe marcar synced.
      if (entry['status'] ==
          UserPreferencesService.offlineTurnoStatusClosedPending) {
        print(
          '[TURNO_SYNC] ✅ closed_pending $localId ya cerrado en servidor '
          '(id=$existingId) — no se reabre',
        );
        return existingId;
      }

      print(
        '  ⚠️ server_id_turno=$existingId ya cerrado/inexistente; '
        'se reabre la apertura offline',
      );
    }

    final aperturaRaw = entry['apertura'];
    final aperturaData =
        aperturaRaw is Map
            ? Map<String, dynamic>.from(aperturaRaw)
            : Map<String, dynamic>.from(entry);

    final idTpvRaw = entry['id_tpv'] ?? aperturaData['id_tpv'];
    final idVendedorRaw = entry['id_vendedor'] ?? aperturaData['id_vendedor'];
    final idTpv =
        (idTpvRaw is int
            ? idTpvRaw
            : (idTpvRaw is num
                ? idTpvRaw.toInt()
                : int.tryParse('$idTpvRaw'))) ??
        await _userPreferencesService.getIdTpv();
    final idVendedor =
        (idVendedorRaw is int
            ? idVendedorRaw
            : (idVendedorRaw is num
                ? idVendedorRaw.toInt()
                : int.tryParse('$idVendedorRaw'))) ??
        await _userPreferencesService.getIdSeller();

    if (idTpv == null || idVendedor == null) {
      print(
        '  ⚠️ No se pudo obtener TPV o vendedor para turno $localId',
      );
      return null;
    }

    // Preferir reutilizar un turno YA abierto en servidor para este
    // TPV/vendedor ANTES de crear otro. Sin esto, syncs concurrentes o
    // reintentos dejan 2+ filas estado=1 y fn_cerrar_turno_tpv falla
    // ("query returned more than one row") dejando el turno abierto online.
    final alreadyOpen = await _getOnlineOpenShift(
      idTpv: idTpv,
      idVendedor: idVendedor,
    );
    final alreadyOpenId = _parseTurnoId(alreadyOpen?['id']);
    if (alreadyOpenId != null && await _isServerTurnoOpen(alreadyOpenId)) {
      print(
        '[TURNO_SYNC] ✅ _ensureApertura reutiliza turno ya abierto '
        'id=$alreadyOpenId (sin nueva apertura)',
      );
      await _userPreferencesService.setOfflineTurnoServerId(
        localId,
        alreadyOpenId,
      );
      await _ensureEntryHasUsuario(entry, aperturaData, localId);
      await _clearStaleFechaCierre(alreadyOpenId);
      return alreadyOpenId;
    }

    var clientUuid =
        entry['client_uuid_apertura']?.toString() ??
        aperturaData['client_uuid']?.toString();
    if (clientUuid == null || clientUuid.isEmpty) {
      clientUuid = UuidGenerator.v4();
      entry['client_uuid_apertura'] = clientUuid;
      aperturaData['client_uuid'] = clientUuid;
      await _userPreferencesService.upsertOfflineTurno({
        ...entry,
        'apertura': aperturaData,
        'client_uuid_apertura': clientUuid,
      });
    }

    final efectivoInicial =
        (aperturaData['efectivo_inicial'] as num?)?.toDouble() ?? 0.0;
    final usuario = await _ensureEntryHasUsuario(entry, aperturaData, localId);
    if (usuario == null) return null;
    final manejaInventario =
        aperturaData['maneja_inventario'] as bool? ?? false;
    final observaciones = aperturaData['observaciones'] as String?;
    final productosRaw = aperturaData['productos'] as List<dynamic>? ?? [];
    final productos =
        productosRaw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    final fechaApertura =
        entry['fecha_apertura'] ?? aperturaData['fecha_apertura'];

    print('  🔄 Apertura cola turno $localId (TPV $idTpv)...');
    bool aperturaOk = false;
    int? serverId;

    Future<void> tryAperturaRpc({required bool withFecha}) async {
      final params = <String, dynamic>{
        'p_client_uuid': clientUuid,
        'p_efectivo_inicial': efectivoInicial,
        'p_id_tpv': idTpv,
        'p_id_vendedor': idVendedor,
        'p_usuario': usuario,
        'p_maneja_inventario': manejaInventario,
        'p_productos': productos,
        'p_observaciones': observaciones,
      };
      if (withFecha && fechaApertura != null) {
        params['p_fecha_apertura'] = fechaApertura;
      }
      final resp = await Supabase.instance.client.rpc(
        'fn_apertura_turno_offline',
        params: params,
      );
      final map = _asRpcMap(resp);
      if (_rpcStatusSuccess(map)) {
        aperturaOk = true;
        serverId = _parseTurnoId(map!['id_turno']);
        print(
          '  ✅ Apertura $localId → id_turno=$serverId'
          '${map['idempotent'] == true ? ' (idempotente)' : ''}',
        );
      }
    }

    try {
      try {
        await tryAperturaRpc(withFecha: true);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('PGRST202') || msg.contains('Could not find the function')) {
          print(
            '  ⚠️ fn_apertura_turno_offline con fecha no disponible; reintento sin p_fecha_apertura',
          );
          await tryAperturaRpc(withFecha: false);
        } else {
          rethrow;
        }
      }
    } catch (e) {
      print(
        '  ⚠️ fn_apertura_turno_offline no disponible ($e). Fallback.',
      );
      // Antes del fallback: otra pasada pudo haber abierto el turno.
      final raced = await _getOnlineOpenShift(
        idTpv: idTpv,
        idVendedor: idVendedor,
      );
      final racedId = _parseTurnoId(raced?['id']);
      if (racedId != null && await _isServerTurnoOpen(racedId)) {
        aperturaOk = true;
        serverId = racedId;
        print('  ♻️ Fallback omitido; turno $racedId ya abierto');
      } else {
        final result = await TurnoService.registrarAperturaTurno(
          efectivoInicial: efectivoInicial,
          idTpv: idTpv,
          idVendedor: idVendedor,
          usuario: usuario,
          manejaInventario: manejaInventario,
          productos: productos.isEmpty ? null : productos,
          observaciones: observaciones,
        );
        aperturaOk = result['success'] == true;
      }
    }

    // Idempotencia stale: el RPC puede devolver un id_turno YA CERRADO.
    if (aperturaOk && serverId != null && !await _isServerTurnoOpen(serverId!)) {
      print(
        '  ⚠️ Apertura idempotente devolvió turno cerrado $serverId; '
        'forzando nueva apertura en servidor',
      );
      final result = await TurnoService.registrarAperturaTurno(
        efectivoInicial: efectivoInicial,
        idTpv: idTpv,
        idVendedor: idVendedor,
        usuario: usuario,
        manejaInventario: manejaInventario,
        productos: productos.isEmpty ? null : productos,
        observaciones: observaciones,
      );
      aperturaOk = result['success'] == true;
      serverId = null;
    }

    // Si la apertura falló (p.ej. "ya hay turno abierto"), reutilizar el
    // turno abierto existente en servidor para este TPV/vendedor.
    if (!aperturaOk || serverId == null) {
      final online = await _getOnlineOpenShift(
        idTpv: idTpv,
        idVendedor: idVendedor,
      );
      final existingOpenId = _parseTurnoId(online?['id']);
      if (existingOpenId != null && await _isServerTurnoOpen(existingOpenId)) {
        print(
          '  ♻️ Reutilizando turno ya abierto en servidor id=$existingOpenId '
          'para cola $localId',
        );
        aperturaOk = true;
        serverId = existingOpenId;
      }
    }

    if (!aperturaOk) return null;

    if (serverId == null) {
      final online = await _getOnlineOpenShift(
        idTpv: idTpv,
        idVendedor: idVendedor,
      );
      serverId = _parseTurnoId(online?['id']);
      if (online != null && fechaApertura != null && serverId != null) {
        try {
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .update({'fecha_apertura': fechaApertura})
              .eq('id', serverId!);
        } catch (e) {
          print('  ⚠️ No se pudo alinear fecha_apertura: $e');
        }
      }
    }

    if (serverId == null) {
      print('  ❌ Apertura OK pero sin id_turno resoluble para $localId');
      return null;
    }

    // closed_pending cuyo id ya está cerrado: OK (idempotente).
    final alreadyClosedPending =
        entry['status'] ==
            UserPreferencesService.offlineTurnoStatusClosedPending &&
        !await _isServerTurnoOpen(serverId!);
    if (alreadyClosedPending) {
      print(
        '[TURNO_SYNC] ✅ apertura/cierre ya aplicados en servidor '
        'id=$serverId para $localId',
      );
      await _userPreferencesService.setOfflineTurnoServerId(localId, serverId!);
      return serverId;
    }

    if (!await _isServerTurnoOpen(serverId!)) {
      print('  ❌ Tras apertura, el turno $serverId no quedó abierto');
      return null;
    }

    await _userPreferencesService.setOfflineTurnoServerId(localId, serverId!);
    await _clearStaleFechaCierre(serverId!);
    return serverId;
  }

  /// Un turno reabierto (misma fila reutilizada tras cerrar/reabrir varias
  /// veces) puede conservar un `fecha_cierre` de un cierre anterior aunque
  /// `estado` vuelva a 1 (abierto) — visto en logs con
  /// `fecha_cierre` anterior a `fecha_apertura` y duración negativa. Un
  /// `fecha_cierre` residual puede hacer que `cerrar_turno` en el servidor
  /// no encuentre el turno como realmente abierto ("No se encontró un
  /// turno abierto para el TPV X") aunque `estado=1`. Se limpia por las
  /// dudas cada vez que confirmamos que un turno está abierto.
  Future<void> _clearStaleFechaCierre(int serverId) async {
    try {
      final row =
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .select('fecha_cierre')
              .eq('id', serverId)
              .maybeSingle();
      if (row != null && row['fecha_cierre'] != null) {
        print(
          '  🧹 Turno $serverId abierto con fecha_cierre residual '
          '(${row['fecha_cierre']}); limpiando',
        );
        await Supabase.instance.client
            .from('app_dat_caja_turno')
            .update({'fecha_cierre': null})
            .eq('id', serverId);
      }
    } catch (e) {
      print('  ⚠️ No se pudo verificar/limpiar fecha_cierre residual: $e');
    }
  }

  /// Compat: asegura el turno OPEN de la cola (o false si no hay).
  Future<bool> _ensureOnlineTurnoFromOffline() async {
    final open = await _userPreferencesService.getOpenOfflineTurno();
    if (open == null) return false;
    final id = await _ensureAperturaForQueueEntry(open);
    return id != null;
  }

  DateTime? _parseTurnoDt(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  /// ¿La orden pertenece a este turno de la cola?
  bool _orderBelongsToTurno(
    Map<String, dynamic> order,
    Map<String, dynamic> turno,
  ) {
    final orderLid = order['local_turno_id']?.toString();
    final turnoLid = turno['local_id']?.toString();
    if (orderLid != null && orderLid.isNotEmpty) {
      return orderLid == turnoLid;
    }
    // Fallback legacy: ventana [apertura, cierre].
    final created = _parseTurnoDt(
      order['fecha_creacion'] ?? order['created_offline_at'],
    );
    if (created == null) return false;
    final from = _parseTurnoDt(turno['fecha_apertura']);
    final to = _parseTurnoDt(turno['fecha_cierre']);
    if (from != null && created.isBefore(from)) return false;
    if (to != null && created.isAfter(to)) return false;
    if (from == null && to == null) return false;
    return true;
  }

  /// Normaliza respuestas RPC jsonb (Map, List\<Map\> o String JSON).
  Map<String, dynamic>? _asRpcMap(dynamic resp) {
    if (resp == null) return null;
    if (resp is Map) return Map<String, dynamic>.from(resp);
    if (resp is List && resp.isNotEmpty && resp.first is Map) {
      return Map<String, dynamic>.from(resp.first as Map);
    }
    if (resp is String && resp.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(resp);
        return _asRpcMap(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _rpcStatusSuccess(Map<String, dynamic>? map) {
    if (map == null) return false;
    final status = map['status']?.toString().toLowerCase();
    return status == 'success' || map['success'] == true;
  }

  int? _asPositiveInt(dynamic raw) {
    final n =
        raw is int
            ? raw
            : (raw is num ? raw.toInt() : int.tryParse('$raw'));
    if (n == null || n <= 0) return null;
    return n;
  }

  int? _ubicacionIdFromInvRow(Map<String, dynamic> inv) {
    final direct = _asPositiveInt(inv['id_ubicacion']);
    if (direct != null) return direct;
    final ubic = inv['ubicacion'];
    if (ubic is Map) {
      return _asPositiveInt(ubic['id']);
    }
    return _asPositiveInt(inv['ubicacion_id']);
  }

  int? _almacenIdFromInvRow(Map<String, dynamic> inv) {
    final direct = _asPositiveInt(inv['id_almacen']);
    if (direct != null) return direct;
    final ubic = inv['ubicacion'];
    if (ubic is Map) {
      final alm = ubic['almacen'];
      if (alm is Map) return _asPositiveInt(alm['id']);
      return _asPositiveInt(ubic['id_almacen']);
    }
    return null;
  }

  Future<int?> _fallbackUbicacionId(int? idAlmacen) async {
    try {
      final layouts = await OfflineDatabaseService().getCachedLayouts();
      for (final l in layouts) {
        final alm = _asPositiveInt(l['id_almacen']);
        if (idAlmacen != null && alm != null && alm != idAlmacen) continue;
        final id = _asPositiveInt(l['id']);
        if (id != null) return id;
      }
    } catch (e) {
      print('  ⚠️ No se pudo leer layouts cache para ubicación: $e');
    }
    return null;
  }

  /// Índice productoId → filas de inventario offline (con ubicación válida).
  Future<Map<int, List<Map<String, dynamic>>>> _offlineInventarioByProduct({
    int? idAlmacen,
  }) async {
    final byProduct = <int, List<Map<String, dynamic>>>{};
    Map<String, dynamic>? productsData;
    try {
      final offlineData = await _userPreferencesService.getOfflineData();
      final raw = offlineData?['products'];
      if (raw is Map && raw.isNotEmpty) {
        productsData = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}
    if (productsData == null || productsData.isEmpty) {
      final grouped =
          await OfflineDatabaseService().getProductsGroupedByCategory();
      if (grouped.isNotEmpty) {
        productsData = {for (final e in grouped.entries) e.key: e.value};
      }
    }
    if (productsData == null) return byProduct;

    for (final categoryProducts in productsData.values) {
      if (categoryProducts is! List) continue;
      for (final prodDataRaw in categoryProducts) {
        if (prodDataRaw is! Map) continue;
        final prodData = Map<String, dynamic>.from(prodDataRaw);
        final detallesRaw = prodData['detalles_completos'];
        final detalles =
            detallesRaw is Map ? Map<String, dynamic>.from(detallesRaw) : null;
        final productoInfo =
            detalles?['producto'] is Map
                ? Map<String, dynamic>.from(detalles!['producto'] as Map)
                : null;
        final productId =
            _asPositiveInt(productoInfo?['id']) ??
            _asPositiveInt(prodData['id']);
        if (productId == null) continue;

        final invRaw = detalles?['inventario'];
        if (invRaw is! List) continue;
        for (final row in invRaw) {
          if (row is! Map) continue;
          final inv = Map<String, dynamic>.from(row);
          final almId = _almacenIdFromInvRow(inv);
          if (idAlmacen != null && almId != null && almId != idAlmacen) {
            continue;
          }
          final ubicId = _ubicacionIdFromInvRow(inv);
          if (ubicId == null) continue;
          final variante =
              inv['variante'] is Map
                  ? Map<String, dynamic>.from(inv['variante'] as Map)
                  : null;
          final presentacion =
              inv['presentacion'] is Map
                  ? Map<String, dynamic>.from(inv['presentacion'] as Map)
                  : null;
          byProduct.putIfAbsent(productId, () => []).add({
            'id_producto': productId,
            'id_variante': _asPositiveInt(variante?['id'] ?? inv['id_variante']),
            'id_ubicacion': ubicId,
            'id_presentacion': _asPositiveInt(
              presentacion?['id'] ?? inv['id_presentacion'],
            ),
            'cantidad_disponible':
                (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0.0,
          });
        }
      }
    }
    return byProduct;
  }

  /// Si el cierre offline guardó `productos: []` (o con ubicaciones inválidas)
  /// y el turno maneja inventario, reconstruye filas válidas para el RPC.
  Future<List<Map<String, dynamic>>> _resolveCierreProductos({
    required Map<String, dynamic> latest,
    required Map<String, dynamic> cierreData,
    required List<Map<String, dynamic>> productos,
    int? idTpv,
  }) async {
    final apertura =
        latest['apertura'] is Map
            ? Map<String, dynamic>.from(latest['apertura'] as Map)
            : <String, dynamic>{};
    final manejaInventario =
        cierreData['maneja_inventario'] == true ||
        apertura['maneja_inventario'] == true;

    if (!manejaInventario) {
      return productos;
    }

    final counts = await _userPreferencesService.getInventoryCountCierre(idTpv);
    final idAlmacen = await _userPreferencesService.getIdAlmacen();
    final invByProduct = await _offlineInventarioByProduct(idAlmacen: idAlmacen);
    final fallbackUbic = await _fallbackUbicacionId(idAlmacen);

    List<Map<String, dynamic>> sanitize(List<Map<String, dynamic>> src) {
      final out = <Map<String, dynamic>>[];
      for (final raw in src) {
        final id = _asPositiveInt(raw['id_producto'] ?? raw['id']);
        if (id == null) continue;
        var ubic = _asPositiveInt(raw['id_ubicacion']);
        if (ubic == null) {
          final invRows = invByProduct[id];
          if (invRows != null && invRows.isNotEmpty) {
            ubic = _asPositiveInt(invRows.first['id_ubicacion']);
          }
        }
        ubic ??= fallbackUbic;
        if (ubic == null) {
          print('  ⚠️ Producto $id sin id_ubicacion válido; se omite');
          continue;
        }
        final qty =
            (raw['cantidad'] as num?)?.toDouble() ??
            counts[id.toString()] ??
            0.0;
        out.add({
          'id_producto': id,
          'id_variante': _asPositiveInt(raw['id_variante']),
          'id_ubicacion': ubic,
          'id_presentacion': _asPositiveInt(raw['id_presentacion']),
          'cantidad': qty,
        });
      }
      return out;
    }

    // 1) Sanear los que ya venían en el payload (puede traer ubicacion=0).
    var rebuilt = sanitize(productos);

    // 2) Plantilla de apertura.
    if (rebuilt.isEmpty) {
      final aperturaProds = apertura['productos'];
      if (aperturaProds is List && aperturaProds.isNotEmpty) {
        final mapped = <Map<String, dynamic>>[];
        for (final raw in aperturaProds) {
          if (raw is! Map) continue;
          final p = Map<String, dynamic>.from(raw);
          final id = _asPositiveInt(p['id_producto'] ?? p['id']);
          if (id == null) continue;
          mapped.add({
            ...p,
            'cantidad':
                counts[id.toString()] ??
                (p['cantidad'] as num?)?.toDouble() ??
                0.0,
          });
        }
        rebuilt = sanitize(mapped);
      }
    }

    // 3) Filas reales de inventario offline (ubicación válida).
    if (rebuilt.isEmpty) {
      print(
        '  ⚠️ Cierre con inventario sin productos válidos; '
        'reconstruyendo desde inventario offline...',
      );
      final seen = <String>{};
      for (final entry in invByProduct.entries) {
        final productId = entry.key;
        final qtyCounted = counts[productId.toString()];
        for (final row in entry.value) {
          final ubic = _asPositiveInt(row['id_ubicacion']);
          if (ubic == null) continue;
          final key = '$productId|$ubic|${row['id_variante']}|${row['id_presentacion']}';
          if (!seen.add(key)) continue;
          rebuilt.add({
            'id_producto': productId,
            'id_variante': row['id_variante'],
            'id_ubicacion': ubic,
            'id_presentacion': row['id_presentacion'],
            // Si hay conteo por producto, úsalo en la primera ubicación;
            // si no, cantidad disponible del cache.
            'cantidad':
                qtyCounted ??
                (row['cantidad_disponible'] as num?)?.toDouble() ??
                0.0,
          });
          // El conteo de cierre es por producto (no por ubicación): solo una vez.
          if (qtyCounted != null) break;
        }
      }
    }

    // 4) Último recurso: productos del InventoryService + layout fallback.
    if (rebuilt.isEmpty && fallbackUbic != null) {
      try {
        final cached = await InventoryService.buildFromOfflineCache();
        for (final product in cached) {
          final ubic = _asPositiveInt(product.idUbicacion) ?? fallbackUbic;
          rebuilt.add({
            'id_producto': product.id,
            'id_variante': product.idVariante,
            'id_ubicacion': ubic,
            'id_presentacion': product.idPresentacion,
            'cantidad':
                counts[product.id.toString()] ?? product.cantidadFinal,
          });
        }
      } catch (e) {
        print('  ⚠️ No se pudo reconstruir productos desde cache: $e');
      }
    }

    final invalid = rebuilt.where((p) => _asPositiveInt(p['id_ubicacion']) == null).length;
    if (invalid > 0) {
      rebuilt =
          rebuilt
              .where((p) => _asPositiveInt(p['id_ubicacion']) != null)
              .toList();
    }

    print(
      '  📦 Productos para cierre: ${rebuilt.length} '
      '(con id_ubicacion válido)',
    );
    return rebuilt;
  }

  /// UUID `creado_por` de un turno concreto en servidor.
  Future<String?> _resolveUsuarioForServerTurnoId(int serverId) async {
    try {
      final row =
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .select('creado_por')
              .eq('id', serverId)
              .maybeSingle();
      final creadoPor = row?['creado_por']?.toString();
      if (creadoPor != null && creadoPor.isNotEmpty) {
        print(
          '  🔎 creado_por del turno $serverId → $creadoPor',
        );
        return creadoPor;
      }
    } catch (e) {
      print('  ⚠️ No se pudo leer creado_por del turno $serverId: $e');
    }
    return null;
  }

  /// Cierra TODOS los turnos abiertos de un TPV/usuario (post-cierre limpio).
  Future<void> _closeAllRemainingOpenTurnos({
    required int idTpv,
    required String usuario,
  }) async {
    try {
      final rows = await Supabase.instance.client
          .from('app_dat_caja_turno')
          .select('id')
          .eq('id_tpv', idTpv)
          .eq('estado', 1)
          .eq('creado_por', usuario);
      for (final row in rows as List) {
        final id = _parseTurnoId((row as Map)['id']);
        if (id == null) continue;
        await Supabase.instance.client
            .from('app_dat_caja_turno')
            .update({
              'estado': 2,
              'fecha_cierre': DateTime.now().toUtc().toIso8601String(),
              'observaciones':
                  'Cierre automático residual (sync offline)',
              'cerrado_por': usuario,
            })
            .eq('id', id)
            .eq('estado', 1);
        print('[TURNO_SYNC] 🧹 residual abierto $id cerrado');
      }
    } catch (e) {
      print('[TURNO_SYNC] ⚠️ closeAllRemaining falló: $e');
    }
  }

  /// Si hay varios turnos abiertos del mismo TPV/usuario (sync duplicado),
  /// deja solo [keepServerId] (o el más reciente) y cierra el resto con
  /// update directo. Así `fn_cerrar_turno_tpv` no falla por multi-row.
  Future<int?> _collapseDuplicateOpenTurnos({
    required int idTpv,
    required String usuario,
    int? keepServerId,
  }) async {
    try {
      final rows = await Supabase.instance.client
          .from('app_dat_caja_turno')
          .select('id, fecha_apertura, creado_por')
          .eq('id_tpv', idTpv)
          .eq('estado', 1)
          .eq('creado_por', usuario)
          .order('fecha_apertura', ascending: false, nullsFirst: false);

      final opens = List<Map<String, dynamic>>.from(
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
      if (opens.length <= 1) {
        return keepServerId ?? _parseTurnoId(opens.isEmpty ? null : opens.first['id']);
      }

      print(
        '[TURNO_SYNC] ⚠️ ${opens.length} turnos abiertos duplicados '
        'TPV=$idTpv usuario=$usuario — colapsando',
      );

      int? keep = keepServerId;
      if (keep == null || !opens.any((o) => _parseTurnoId(o['id']) == keep)) {
        keep = _parseTurnoId(opens.first['id']);
      }

      for (final row in opens) {
        final id = _parseTurnoId(row['id']);
        if (id == null || id == keep) continue;
        try {
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .update({
                'estado': 2,
                'fecha_cierre': DateTime.now().toUtc().toIso8601String(),
                'observaciones':
                    'Cierre automático de duplicado (sync offline)',
                'cerrado_por': usuario,
              })
              .eq('id', id)
              .eq('estado', 1);
          print('[TURNO_SYNC] 🧹 duplicado $id cerrado; se conserva $keep');
        } catch (e) {
          print('[TURNO_SYNC] ⚠️ no se pudo cerrar duplicado $id: $e');
        }
      }
      return keep;
    } catch (e) {
      print('[TURNO_SYNC] ⚠️ collapse duplicados falló: $e');
      return keepServerId;
    }
  }

  /// Cierra en servidor un turno de la cola (closed_pending_sync).
  /// Solo retorna true si el servidor aceptó el cierre Y se marcó synced local.
  Future<bool> _syncCierreForQueueEntry(Map<String, dynamic> entry) async {
    final localId = entry['local_id']?.toString() ?? '';
    if (localId.isEmpty) {
      print('[TURNO_SYNC] ❌ _syncCierre: sin local_id');
      return false;
    }

    print(
      '[TURNO_SYNC] ▶ _syncCierreForQueueEntry START '
      '${UserPreferencesService.describeOfflineTurnoEntry(entry)}',
    );

    // Releer desde disco para no usar un snapshot stale sin `cierre`.
    var latest =
        await _userPreferencesService.getOfflineTurnoByLocalId(localId) ??
        entry;
    print(
      '[TURNO_SYNC] _syncCierre re-leído desde disco: '
      '${UserPreferencesService.describeOfflineTurnoEntry(latest)}',
    );

    if (latest['status'] !=
        UserPreferencesService.offlineTurnoStatusClosedPending) {
      print(
        '[TURNO_SYNC] ℹ️ _syncCierre omitido: status=${latest['status']} '
        '(esperado closed_pending_sync)',
      );
      return latest['status'] ==
          UserPreferencesService.offlineTurnoStatusSynced;
    }

    final cierreRaw = latest['cierre'];
    if (cierreRaw is! Map) {
      print(
        '[TURNO_SYNC] ❌ _syncCierre: closed_pending SIN payload cierre',
      );
      return false;
    }
    final cierreData = Map<String, dynamic>.from(cierreRaw);

    // Idempotencia: si el server_id ya está cerrado, solo marcar synced.
    final earlyServerId = _parseTurnoId(latest['server_id_turno']);
    if (earlyServerId != null &&
        !await _isServerTurnoOpen(earlyServerId)) {
      print(
        '[TURNO_SYNC] ✅ _syncCierre: turno $earlyServerId ya cerrado '
        'en servidor — marcando synced',
      );
      await _userPreferencesService.purgeFinalizedSyncedOrdersForTurno(
        localId,
      );
      return _userPreferencesService.markOfflineTurnoSynced(
        localId,
        serverIdTurno: earlyServerId,
      );
    }

    final aperturaRaw = latest['apertura'];
    final aperturaIdTpv =
        aperturaRaw is Map ? aperturaRaw['id_tpv'] : null;
    final idTpvRaw =
        latest['id_tpv'] ??
        aperturaIdTpv ??
        cierreData['id_tpv'] ??
        await _userPreferencesService.getIdTpv();
    final idTpv =
        idTpvRaw is int
            ? idTpvRaw
            : (idTpvRaw is num
                ? idTpvRaw.toInt()
                : int.tryParse('$idTpvRaw'));

    var serverId = _parseTurnoId(latest['server_id_turno']);
    final resolvedByServer =
        serverId != null
            ? await _resolveUsuarioForServerTurnoId(serverId)
            : null;
    final resolvedRealUsuario =
        resolvedByServer ??
        (idTpv != null
            ? await _resolveUsuarioForOpenTpvTurno(idTpv)
            : null);
    final aperturaUsuario =
        aperturaRaw is Map ? aperturaRaw['usuario']?.toString() : null;
    final usuarioRaw =
        resolvedRealUsuario ??
        ((aperturaUsuario != null && aperturaUsuario.isNotEmpty)
            ? aperturaUsuario
            : (latest['usuario'] ?? cierreData['usuario']));
    final usuario = usuarioRaw?.toString();
    final efectivoFinal = (cierreData['efectivo_final'] as num?)?.toDouble() ??
        0.0;
    final observaciones = cierreData['observaciones'] as String?;
    var productosRaw = cierreData['productos'] as List<dynamic>? ?? [];
    var productos =
        productosRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    print(
      '[TURNO_SYNC] _syncCierre params: '
      'idTpv=$idTpv '
      'usuario=$usuario '
      '(creado_por=$resolvedRealUsuario apertura_u=$aperturaUsuario '
      'entry_u=${latest['usuario']} cierre_u=${cierreData['usuario']}) '
      'efectivo_final=$efectivoFinal '
      'productos_raw=${productos.length} '
      'server_id=$serverId '
      'uuid_cierre=${latest['client_uuid_cierre'] ?? cierreData['client_uuid']}',
    );

    if (idTpv == null || usuario == null || usuario.isEmpty) {
      print(
        '[TURNO_SYNC] ❌ _syncCierre abortado: id_tpv=$idTpv usuario=$usuario',
      );
      return false;
    }

    // Colapsar duplicados ANTES del RPC de cierre.
    final keepId = await _collapseDuplicateOpenTurnos(
      idTpv: idTpv,
      usuario: usuario,
      keepServerId: serverId,
    );
    if (keepId != null && keepId != serverId) {
      serverId = keepId;
      await _userPreferencesService.setOfflineTurnoServerId(localId, keepId);
      latest =
          await _userPreferencesService.getOfflineTurnoByLocalId(localId) ??
          latest;
    }

    productos = await _resolveCierreProductos(
      latest: latest,
      cierreData: cierreData,
      productos: productos,
      idTpv: idTpv,
    );
    print(
      '[TURNO_SYNC] _syncCierre productos tras resolve=${productos.length}',
    );
    final manejaInventario =
        cierreData['maneja_inventario'] == true ||
        (latest['apertura'] is Map &&
            latest['apertura']['maneja_inventario'] == true);
    if (manejaInventario && productos.isEmpty) {
      // No abortar el cierre: el servidor rechazará si realmente exige
      // inventario; si el turno en BD no maneja inventario, debe cerrar.
      print(
        '[TURNO_SYNC] ⚠️ cierre con inventario declarado pero sin productos; '
        'se intenta el cierre igual (el servidor valida)',
      );
    }
    if (productos.isNotEmpty) {
      await _userPreferencesService.upsertOfflineTurno({
        ...latest,
        'cierre': {...cierreData, 'productos': productos},
      });
    }

    var clientUuid =
        latest['client_uuid_cierre']?.toString() ??
        cierreData['client_uuid']?.toString();
    if (clientUuid == null || clientUuid.isEmpty) {
      clientUuid = UuidGenerator.v4();
      print('[TURNO_SYNC] _syncCierre generó client_uuid_cierre=$clientUuid');
      await _userPreferencesService.upsertOfflineTurno({
        ...latest,
        'client_uuid_cierre': clientUuid,
        'cierre': {
          ...cierreData,
          'client_uuid': clientUuid,
          'productos': productos,
        },
      });
    }

    bool cerrado = false;
    String? cierreMessage;
    Map<String, dynamic>? cierreRespMap;

    bool isMissingRpc(Object e) {
      final msg = e.toString();
      return msg.contains('PGRST202') ||
          msg.contains('Could not find the function');
    }

    Future<void> tryCierreRpc({required bool withFecha}) async {
      final params = <String, dynamic>{
        'p_client_uuid': clientUuid,
        'p_id_tpv': idTpv,
        'p_efectivo_real': efectivoFinal,
        'p_usuario': usuario,
        'p_productos': productos,
        'p_observaciones': observaciones,
      };
      if (withFecha) {
        final fecha = cierreData['fecha_cierre'] ?? latest['fecha_cierre'];
        if (fecha != null) params['p_fecha_cierre'] = fecha;
      }
      print(
        '[TURNO_SYNC] RPC fn_cerrar_turno_offline '
        'withFecha=$withFecha params=${{
          ...params,
          'p_productos': '(${productos.length} items)',
        }}',
      );
      final resp = await Supabase.instance.client.rpc(
        'fn_cerrar_turno_offline',
        params: params,
      );
      cierreRespMap = _asRpcMap(resp);
      cerrado = _rpcStatusSuccess(cierreRespMap);
      cierreMessage = cierreRespMap?['message']?.toString();
      print(
        '[TURNO_SYNC] RPC respuesta: cerrado=$cerrado '
        'resp=$resp map=$cierreRespMap',
      );
    }

    Future<bool> tryFallbackCierre() async {
      try {
        final result = await TurnoService.cerrarTurnoDetailed(
          efectivoReal: efectivoFinal,
          productos: productos,
          observaciones: observaciones,
        );
        print(
          '[TURNO_SYNC] fallback cerrarTurnoDetailed '
          'success=${result.success} msg=${result.message}',
        );
        return result.success;
      } catch (e2) {
        print('[TURNO_SYNC] ❌ fallback cierre falló: $e2');
        return false;
      }
    }

    try {
      try {
        await tryCierreRpc(withFecha: false);
      } catch (e) {
        if (isMissingRpc(e)) {
          print(
            '[TURNO_SYNC] ⚠️ firma sin fecha no encontrada; reintento con fecha',
          );
          await tryCierreRpc(withFecha: true);
        } else {
          print('[TURNO_SYNC] ⚠️ RPC cierre error: $e — reintento tras colapsar');
          await _collapseDuplicateOpenTurnos(
            idTpv: idTpv,
            usuario: usuario,
            keepServerId: serverId,
          );
          try {
            await tryCierreRpc(withFecha: false);
          } catch (e2) {
            print('[TURNO_SYNC] ❌ RPC cierre rechazado: $e2');
            cerrado = await tryFallbackCierre();
          }
        }
      }

      if (cerrado) {
        final fecha = cierreData['fecha_cierre'] ?? latest['fecha_cierre'];
        final sid = serverId ?? _parseTurnoId(latest['server_id_turno']);
        if (fecha != null && sid != null) {
          try {
            await Supabase.instance.client
                .from('app_dat_caja_turno')
                .update({'fecha_cierre': fecha})
                .eq('id', sid);
            print(
              '[TURNO_SYNC] fecha_cierre alineada en servidor id=$sid → $fecha',
            );
          } catch (e) {
            print('[TURNO_SYNC] ⚠️ no se pudo alinear fecha_cierre: $e');
          }
        }
      }
    } catch (e) {
      if (!isMissingRpc(e)) {
        print('[TURNO_SYNC] ❌ _syncCierre falló: $e');
        cerrado = await tryFallbackCierre();
      } else {
        print(
          '[TURNO_SYNC] ⚠️ fn_cerrar_turno_offline no disponible → fallback',
        );
        cerrado = await tryFallbackCierre();
      }
    }

    // Si el RPC dijo OK por "no hay turno abierto" pero nuestro id sigue
    // abierto, no marcar synced. Si hay otros abiertos, cerrarlos.
    final sidCheck = serverId ?? _parseTurnoId(latest['server_id_turno']);
    if (cerrado) {
      final noOpenMsg = (cierreMessage ?? '').toLowerCase().contains(
        'no hay turno abierto',
      );
      if (sidCheck != null && await _isServerTurnoOpen(sidCheck)) {
        print(
          '[TURNO_SYNC] ⚠️ RPC OK pero turno $sidCheck sigue abierto'
          '${noOpenMsg ? ' (msg sin turno abierto)' : ''} — reintento',
        );
        await _collapseDuplicateOpenTurnos(
          idTpv: idTpv,
          usuario: usuario,
          keepServerId: sidCheck,
        );
        try {
          await tryCierreRpc(withFecha: false);
        } catch (_) {
          cerrado = await tryFallbackCierre();
        }
        if (await _isServerTurnoOpen(sidCheck)) {
          // Último recurso: cerrar la fila concreta.
          try {
            await Supabase.instance.client
                .from('app_dat_caja_turno')
                .update({
                  'estado': 2,
                  'efectivo_real': efectivoFinal,
                  'fecha_cierre':
                      cierreData['fecha_cierre'] ??
                      DateTime.now().toUtc().toIso8601String(),
                  'observaciones':
                      observaciones ??
                      'Cierre sync offline (forzado por id)',
                  'cerrado_por': usuario,
                })
                .eq('id', sidCheck)
                .eq('estado', 1);
            cerrado = !await _isServerTurnoOpen(sidCheck);
            print(
              '[TURNO_SYNC] forzado por id $sidCheck → cerrado=$cerrado',
            );
          } catch (e) {
            print('[TURNO_SYNC] ❌ forzado por id falló: $e');
            cerrado = false;
          }
        }
      }
    }

    if (!cerrado) {
      // Aún puede quedar abierto: un último intento de colapso + fallback.
      await _collapseDuplicateOpenTurnos(
        idTpv: idTpv,
        usuario: usuario,
        keepServerId: sidCheck,
      );
      cerrado = await tryFallbackCierre();
      if (!cerrado &&
          sidCheck != null &&
          await _isServerTurnoOpen(sidCheck)) {
        print(
          '[TURNO_SYNC] ❌ _syncCierre: servidor NO cerró '
          'msg=$cierreMessage resp=$cierreRespMap sid=$sidCheck',
        );
        return false;
      }
      if (!cerrado && sidCheck != null) {
        // Ya no está abierto → tratar como cerrado.
        cerrado = true;
      }
      if (!cerrado) {
        print(
          '[TURNO_SYNC] ❌ _syncCierre: servidor NO cerró '
          'msg=$cierreMessage resp=$cierreRespMap',
        );
        return false;
      }
    }

    // Verificar estado final: nuestro server_id (si existe) no debe seguir abierto.
    if (sidCheck != null && await _isServerTurnoOpen(sidCheck)) {
      print(
        '[TURNO_SYNC] ❌ post-cierre: turno $sidCheck sigue estado=1',
      );
      return false;
    }

    // Cerrar cualquier otro abierto residual del mismo TPV/usuario.
    await _closeAllRemainingOpenTurnos(idTpv: idTpv, usuario: usuario);

    await _userPreferencesService.purgeFinalizedSyncedOrdersForTurno(localId);
    final sid = sidCheck ?? _parseTurnoId(cierreRespMap?['id_turno']);
    print(
      '[TURNO_SYNC] marcando synced localId=$localId serverId=$sid',
    );
    final marked = await _userPreferencesService.markOfflineTurnoSynced(
      localId,
      serverIdTurno: sid,
    );
    if (!marked) {
      print(
        '[TURNO_SYNC] ❌ cierre OK en servidor pero markSynced falló '
        'localId=$localId',
      );
      return false;
    }
    print('[TURNO_SYNC] ✅ _syncCierreForQueueEntry OK localId=$localId');
    return true;
  }

  /// Sincroniza UN turno de la cola (apertura → ventas → egresos → cierre).
  /// No se detiene por fallos de otros turnos.
  Future<bool> _syncSingleOfflineTurnoEntry(Map<String, dynamic> entry) async {
    final localId = entry['local_id']?.toString() ?? '';
    if (localId.isEmpty) {
      print('[TURNO_SYNC] ❌ _syncSingle: sin local_id');
      return false;
    }

    print(
      '[TURNO_SYNC] ▶▶▶ _syncSingleOfflineTurnoEntry START '
      '${UserPreferencesService.describeOfflineTurnoEntry(entry)}',
    );
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'ANTES _syncSingle ($localId)',
    );

    if (entry['status'] == UserPreferencesService.offlineTurnoStatusSynced) {
      print('[TURNO_SYNC] ℹ️ _syncSingle: $localId ya synced → OK');
      return true;
    }

    final serverId = await _ensureAperturaForQueueEntry(entry);
    print(
      '[TURNO_SYNC] _syncSingle apertura → serverId=$serverId '
      'localId=$localId',
    );
    if (serverId == null) {
      print('[TURNO_SYNC] ❌ _syncSingle: no se pudo abrir en servidor');
      await _userPreferencesService.dumpOfflineTurnosQueue(
        'FALLO apertura ($localId)',
      );
      return false;
    }

    final refreshed =
        await _userPreferencesService.getOfflineTurnoByLocalId(localId) ??
        entry;
    print(
      '[TURNO_SYNC] _syncSingle tras apertura: '
      '${UserPreferencesService.describeOfflineTurnoEntry(refreshed)}',
    );

    final sales = await _syncOfflineSales(forTurno: refreshed);
    print('[TURNO_SYNC] _syncSingle ventas synced=$sales');
    final egresos = await _syncOfflineEgresos(
      forLocalTurnoId: localId,
      serverIdTurno: serverId,
    );
    print('[TURNO_SYNC] _syncSingle egresos synced=$egresos');
    await _remapShiftWorkerOpsForTurno(localId, serverId);

    try {
      await ShiftWorkersService.syncPendingOperations();
    } catch (e) {
      print('[TURNO_SYNC] ⚠️ workers sync: $e');
    }

    final latest =
        await _userPreferencesService.getOfflineTurnoByLocalId(localId) ??
        refreshed;
    print(
      '[TURNO_SYNC] _syncSingle antes de cierre: '
      '${UserPreferencesService.describeOfflineTurnoEntry(latest)}',
    );

    if (latest['status'] !=
        UserPreferencesService.offlineTurnoStatusClosedPending) {
      print(
        '[TURNO_SYNC] ℹ️ _syncSingle: sin cierre pendiente '
        '(status=${latest['status']}) → OK (solo apertura)',
      );
      await _userPreferencesService.dumpOfflineTurnosQueue(
        'FIN _syncSingle sin cierre ($localId)',
      );
      return true;
    }

    final ok = await _syncCierreForQueueEntry(latest);
    print(
      '[TURNO_SYNC] ◀◀◀ _syncSingleOfflineTurnoEntry END '
      'localId=$localId ok=$ok',
    );
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'DESPUÉS _syncSingle ($localId ok=$ok)',
    );
    return ok;
  }

  /// Replay ordenado: por cada turno pending → apertura → ventas → egresos → cierre.
  Future<Map<String, dynamic>> _syncOfflineTurnoQueue() async {
    print('[TURNO_SYNC] ▶ _syncOfflineTurnoQueue START');
    await _hydrateTurnosFromLegacyPendingOps();

    final pending = await _userPreferencesService.getOfflineTurnosPendingSync();
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'cola pending=${pending.length}',
    );
    if (pending.isEmpty) {
      print('[TURNO_SYNC] cola vacía — nada que sync');
      return {
        'turnos': 0,
        'sales': 0,
        'egresos': 0,
        'cierres': 0,
        'closed_remaining': 0,
        'pending_remaining': 0,
      };
    }

    print('[TURNO_SYNC] Replay de ${pending.length} turno(s)...');
    int salesTotal = 0;
    int egresosTotal = 0;
    int cierres = 0;
    int aperturas = 0;
    final failedCierres = <String>[];

    for (final entry in pending) {
      final localId = entry['local_id']?.toString() ?? '';
      if (localId.isEmpty) {
        print('[TURNO_SYNC] ⚠️ entrada sin local_id; omitida');
        continue;
      }
      print(
        '[TURNO_SYNC] ——— queue item '
        '${UserPreferencesService.describeOfflineTurnoEntry(entry)} ———',
      );

      final serverId = await _ensureAperturaForQueueEntry(entry);
      if (serverId == null) {
        print(
          '[TURNO_SYNC] ❌ no se pudo abrir $localId; se DETIENE el replay',
        );
        break;
      }
      aperturas++;

      // Refrescar entry tras set server_id
      final refreshed =
          await _userPreferencesService.getOfflineTurnoByLocalId(localId) ??
          entry;

      final sales = await _syncOfflineSales(forTurno: refreshed);
      salesTotal += sales;
      print('[TURNO_SYNC] queue $localId ventas=$sales');

      final egresos = await _syncOfflineEgresos(
        forLocalTurnoId: localId,
        serverIdTurno: serverId,
      );
      egresosTotal += egresos;
      print('[TURNO_SYNC] queue $localId egresos=$egresos');

      // Workers: remapear id_turno local → server antes de sync global.
      await _remapShiftWorkerOpsForTurno(localId, serverId);

      if (refreshed['status'] ==
          UserPreferencesService.offlineTurnoStatusClosedPending) {
        final ok = await _syncCierreForQueueEntry(refreshed);
        if (ok) {
          cierres++;
          print('[TURNO_SYNC] ✅ cierre OK en queue: $localId');
        } else {
          failedCierres.add(localId);
          print(
            '[TURNO_SYNC] ❌ cierre FALLÓ en queue: $localId; se detiene replay',
          );
          break;
        }
      } else {
        print(
          '[TURNO_SYNC] queue $localId status=${refreshed['status']} '
          '— sin cierre en este pase',
        );
      }
    }

    // Sync workers restantes (ya remapeados).
    try {
      await ShiftWorkersService.syncPendingOperations();
    } catch (e) {
      print('[TURNO_SYNC] ⚠️ Error sync trabajadores tras cola: $e');
    }

    final remaining =
        await _userPreferencesService.getOfflineTurnosPendingSync();
    final closedRemaining =
        remaining
            .where(
              (t) =>
                  t['status'] ==
                  UserPreferencesService.offlineTurnoStatusClosedPending,
            )
            .length;

    final result = {
      'turnos': aperturas,
      'sales': salesTotal,
      'egresos': egresosTotal,
      'cierres': cierres,
      'closed_remaining': closedRemaining,
      'pending_remaining': remaining.length,
      'failed_cierres': failedCierres,
    };
    print('[TURNO_SYNC] ◀ _syncOfflineTurnoQueue END $result');
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'FIN queue result=$result',
    );
    return result;
  }

  /// Incorpora apertura/cierre legacy de pending_operations a la cola.
  Future<void> _hydrateTurnosFromLegacyPendingOps() async {
    final ops = await _userPreferencesService.getPendingOperations();
    final aperturas =
        ops.where((o) => o['type'] == 'apertura_turno').toList();
    final cierres = ops.where((o) => o['type'] == 'cierre_turno').toList();
    if (aperturas.isEmpty && cierres.isEmpty) return;

    final existing = await _userPreferencesService.getOfflineTurnos();
    final knownClients =
        existing
            .map((t) => t['client_uuid_apertura']?.toString())
            .whereType<String>()
            .toSet();
    final knownLocalIds =
        existing
            .map((t) => t['local_id']?.toString())
            .whereType<String>()
            .toSet();

    for (final op in aperturas) {
      final data = op['data'];
      if (data is! Map) continue;
      final map = Map<String, dynamic>.from(data);
      final cu = map['client_uuid']?.toString();
      final legacyLocalId =
          map['local_id']?.toString() ?? map['local_turno_id']?.toString();
      if (cu != null && knownClients.contains(cu)) continue;
      if (legacyLocalId != null && knownLocalIds.contains(legacyLocalId)) {
        continue;
      }

      // ¿Hay cierre legacy pareado? (mismo id_tpv, posterior)
      Map<String, dynamic>? cierreMatch;
      for (final cOp in cierres) {
        final cData = cOp['data'];
        if (cData is! Map) continue;
        final cMap = Map<String, dynamic>.from(cData);
        if (cMap['id_tpv'] == map['id_tpv']) {
          cierreMatch = cMap;
          break;
        }
      }

      try {
        if (cierreMatch != null) {
          final localId = map['local_id']?.toString() ??
              map['local_turno_id']?.toString() ??
              UuidGenerator.v4();
          await _userPreferencesService.upsertOfflineTurno({
            'local_id': localId,
            'client_uuid_apertura':
                map['client_uuid']?.toString() ?? UuidGenerator.v4(),
            'client_uuid_cierre':
                cierreMatch['client_uuid']?.toString() ?? UuidGenerator.v4(),
            'status':
                UserPreferencesService.offlineTurnoStatusClosedPending,
            'id_tpv': map['id_tpv'],
            'id_vendedor': map['id_vendedor'],
            'usuario': map['usuario'],
            'fecha_apertura': map['fecha_apertura'],
            'fecha_cierre': cierreMatch['fecha_cierre'],
            'apertura': {...map, 'local_id': localId},
            'cierre': {...cierreMatch, 'local_turno_id': localId},
          });
        } else if (await _userPreferencesService.getOpenOfflineTurno() ==
            null) {
          await _userPreferencesService.createOpenOfflineTurno(
            aperturaPayload: map,
          );
        }
      } catch (e) {
        print('  ⚠️ hydrate legacy apertura: $e');
      }
    }

    // Limpiar ops de turno legacy: la cola es fuente de verdad.
    final filtered =
        ops
            .where(
              (o) =>
                  o['type'] != 'apertura_turno' && o['type'] != 'cierre_turno',
            )
            .toList();
    if (filtered.length != ops.length) {
      await _userPreferencesService.savePendingOperations(filtered);
      print('  🧹 Ops legacy apertura/cierre movidas a cola offline_turnos');
    }
  }

  Future<void> _remapShiftWorkerOpsForTurno(
    String localTurnoId,
    int serverId,
  ) async {
    final ops = await _userPreferencesService.getPendingOperations();
    var changed = false;
    for (final op in ops) {
      if (op['type'] != 'add_shift_worker') continue;
      final data = op['data'];
      if (data is! Map) continue;
      final map = Map<String, dynamic>.from(data);
      final lid = map['local_turno_id']?.toString();
      final idTurno = map['id_turno'];
      final matches =
          lid == localTurnoId ||
          idTurno?.toString() == localTurnoId ||
          (idTurno is! int && lid == null);
      if (!matches && lid != null && lid != localTurnoId) continue;
      if (lid == localTurnoId || idTurno?.toString() == localTurnoId) {
        map['id_turno'] = serverId;
        map['local_turno_id'] = localTurnoId;
        op['data'] = map;
        changed = true;
      }
    }
    if (changed) {
      await _userPreferencesService.savePendingOperations(ops);
    }
  }

  /// Compat: cierra el primer closed_pending_sync de la cola.
  Future<bool> _syncOfflineCierreIfPending() async {
    final pending = await _userPreferencesService.getOfflineTurnosPendingSync();
    for (final t in pending) {
      if (t['status'] ==
          UserPreferencesService.offlineTurnoStatusClosedPending) {
        // Debe haberse abierto antes; el queue loop es el camino correcto.
        final serverId = await _ensureAperturaForQueueEntry(t);
        if (serverId == null) return false;
        return _syncCierreForQueueEntry(t);
      }
    }
    return false;
  }

  /// Sincronizar resumen de turno anterior (solo turnos cerrados).
  /// No usar getResumenTurnoKPI a ciegas: si el TPV tiene turno abierto,
  /// el KPI pisa el cache del cierre y la apertura muestra datos vacíos/malos.
  Future<void> _syncTurnoResumen() async {
    final resumenTurno = await TurnoService.getResumenUltimoTurnoCerrado();

    if (resumenTurno != null) {
      final normalized =
          _userPreferencesService.normalizePreviousShiftSummary(resumenTurno);
      await _userPreferencesService.saveTurnoResumenCache({
        ...normalized,
        'cerrado_online': true,
        'status': UserPreferencesService.offlineTurnoStatusSynced,
      });
      await _userPreferencesService.saveResumenCierreCache({
        ...normalized,
        'total_ventas': normalized['ventas_totales'],
        'efectivo_real':
            normalized['efectivo_real'] ?? normalized['efectivo_final'],
      });
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
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            // Si es una lista, tomar el primer elemento
            resumenCierre = resumenCierreResponse[0] as Map<String, dynamic>;
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            // Si ya es un mapa, usarlo directamente
            resumenCierre = resumenCierreResponse;
          } else {
            print(
              '⚠️ AutoSync: Formato de respuesta no reconocido para resumen de cierre',
            );
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

  /// Sincronizar egresos offline pendientes.
  /// Si [forLocalTurnoId] se indica, solo sube egresos de ese turno y usa
  /// [serverIdTurno] como id_turno en el RPC.
  Future<int> _syncOfflineEgresos({
    String? forLocalTurnoId,
    int? serverIdTurno,
  }) async {
    final egresosOffline = await _userPreferencesService.getEgresosOffline();

    final filtered =
        forLocalTurnoId == null
            ? egresosOffline
            : egresosOffline.where((e) {
              final lid = e['local_turno_id']?.toString();
              if (lid != null) return lid == forLocalTurnoId;
              // Legacy sin local_turno_id: incluir solo si no hay filtro estricto
              // o si el id_turno ya es el server id.
              if (serverIdTurno != null && e['id_turno'] == serverIdTurno) {
                return true;
              }
              // Sin vínculo: solo al sync global (sin filtro).
              return false;
            }).toList();

    if (filtered.isEmpty) {
      print('  📝 No hay egresos offline pendientes'
          '${forLocalTurnoId != null ? ' para turno $forLocalTurnoId' : ''}');
      return 0;
    }

    print('  🔄 Sincronizando ${filtered.length} egresos offline...');
    int syncedCount = 0;
    final syncedOfflineIds = <String>[];
    final userId = await _userPreferencesService.getUserId();

    for (var egresoData in filtered) {
      final offlineId = egresoData['offline_id']?.toString();
      try {
        print('    - Procesando egreso offline: $offlineId');

        final idTurno =
            serverIdTurno ??
            (egresoData['id_turno'] is int
                ? egresoData['id_turno'] as int
                : int.tryParse('${egresoData['id_turno']}'));
        if (idTurno == null) {
          print('    ⚠️ Egreso sin id_turno servidor; se omite');
          continue;
        }
        final montoEntrega = (egresoData['monto_entrega'] ?? 0.0).toDouble();
        final motivoEntrega = egresoData['motivo_entrega'] as String;
        final nombreAutoriza = egresoData['nombre_autoriza'] as String;
        final nombreRecibe = egresoData['nombre_recibe'] as String;
        final idMedioPago = egresoData['id_medio_pago'] as int?;

        var clientUuid = egresoData['client_uuid']?.toString();
        if (clientUuid == null || clientUuid.isEmpty) {
          clientUuid = UuidGenerator.v4();
          egresoData['client_uuid'] = clientUuid;
        }

        Map<String, dynamic>? result;
        try {
          final resp = await Supabase.instance.client.rpc(
            'fn_registrar_egreso_offline',
            params: {
              'p_client_uuid': clientUuid,
              'p_id_turno': idTurno,
              'p_monto_entrega': montoEntrega,
              'p_nombre_recibe': nombreRecibe,
              'p_nombre_autoriza': nombreAutoriza,
              'p_motivo_entrega': motivoEntrega,
              'p_id_medio_pago': idMedioPago,
              'p_uuid_usuario': userId,
            },
          );
          if (resp is Map) {
            result = Map<String, dynamic>.from(resp);
          }
        } catch (e) {
          print(
            '    ⚠️ fn_registrar_egreso_offline no disponible ($e). Usando registrarEgresoParcial.',
          );
          result = await TurnoService.registrarEgresoParcial(
            idTurno: idTurno,
            montoEntrega: montoEntrega,
            motivoEntrega: motivoEntrega,
            nombreAutoriza: nombreAutoriza,
            nombreRecibe: nombreRecibe,
            idMedioPago: idMedioPago,
          );
        }

        if (result != null && result['success'] == true) {
          syncedCount++;
          if (offlineId != null) syncedOfflineIds.add(offlineId);
          print(
            '    ✅ Egreso offline sincronizado: ${result['egreso_id']}'
            '${result['idempotent'] == true ? " (idempotente)" : ""}',
          );
        } else {
          print('    ❌ Error en servicio de egreso: ${result?['message']}');
        }
      } catch (e) {
        print('    ❌ Error sincronizando egreso offline $offlineId: $e');
      }
    }

    if (syncedOfflineIds.isNotEmpty) {
      await _userPreferencesService.removeEgresosOfflineByIds(syncedOfflineIds);
    }

    return syncedCount;
  }

  /// Ventana [apertura, cierre] del turno actual (offline / pending / servidor).
  /// Las operaciones del turno son las que caen dentro de ese intervalo.
  Future<({DateTime? from, DateTime? to})> _resolveTurnoOperacionesWindow() async {
    DateTime? from;
    DateTime? to;

    DateTime? parseDt(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw.toUtc();
      return DateTime.tryParse(raw.toString())?.toUtc();
    }

    final offlineTurno = await _userPreferencesService.getOfflineTurno();
    if (offlineTurno != null) {
      from = parseDt(offlineTurno['fecha_apertura']);
      to = parseDt(offlineTurno['fecha_cierre']);
    }

    // Cola multi-turno: usar el turno open o el más reciente closed_pending.
    if (from == null) {
      final pending =
          await _userPreferencesService.getOfflineTurnosPendingSync();
      if (pending.isNotEmpty) {
        final last = pending.last;
        from = parseDt(last['fecha_apertura']);
        to = parseDt(last['fecha_cierre']);
      }
    }

    final pendingOps = await _userPreferencesService.getPendingOperations();
    for (final op in pendingOps) {
      final type = op['type']?.toString();
      final data = op['data'];
      if (data is! Map) continue;
      final map = Map<String, dynamic>.from(data);
      if (type == 'apertura_turno') {
        from ??= parseDt(map['fecha_apertura']);
      } else if (type == 'cierre_turno') {
        to ??= parseDt(map['fecha_cierre']);
        from ??= parseDt(map['fecha_apertura']);
      }
    }

    // Si aún no hay apertura local, usar el turno abierto en servidor.
    if (from == null) {
      try {
        final idTpv = await _userPreferencesService.getIdTpv();
        final idVendedor = await _userPreferencesService.getIdSeller();
        if (idTpv != null && idVendedor != null) {
          final online = await _getOnlineOpenShift(
            idTpv: idTpv,
            idVendedor: idVendedor,
          );
          from = parseDt(online?['fecha_apertura']);
          to ??= parseDt(online?['fecha_cierre']);
        }
      } catch (e) {
        print('  ⚠️ No se pudo leer turno online para ventana: $e');
      }
    }

    // Turno abierto: hasta "ahora".
    to ??= DateTime.now().toUtc();

    return (from: from, to: to);
  }

  String? _toDateParam(DateTime? dt) {
    if (dt == null) return null;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Filtra filas de listar_ordenes al intervalo exacto del turno.
  List<Map<String, dynamic>> _filterOrdersByTurnoWindow(
    List<Map<String, dynamic>> orders, {
    required DateTime? from,
    required DateTime? to,
  }) {
    if (from == null && to == null) return orders;

    DateTime? parseDt(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw.toUtc();
      return DateTime.tryParse(raw.toString())?.toUtc();
    }

    final filtered =
        orders.where((row) {
          final fo = parseDt(
            row['fecha_operacion'] ?? row['created_at'] ?? row['fecha'],
          );
          if (fo == null) return true;
          if (from != null && fo.isBefore(from)) return false;
          if (to != null && fo.isAfter(to)) return false;
          return true;
        }).toList();

    print(
      '  📅 Filtro turno: ${orders.length} → ${filtered.length} ops '
      '(desde=${from?.toIso8601String()} hasta=${to?.toIso8601String()})',
    );
    return filtered;
  }

  /// Sincronizar órdenes del turno actual (apertura → cierre/ahora).
  Future<List<Map<String, dynamic>>> _syncOrders() async {
    final userData = await _userPreferencesService.getUserData();
    final idTienda = await _userPreferencesService.getIdTienda();
    final idTpv = await _userPreferencesService.getIdTpv();
    final userId = userData['userId'];

    if (idTienda == null || idTpv == null || userId == null) {
      return [];
    }

    final window = await _resolveTurnoOperacionesWindow();
    final fechaDesde = _toDateParam(window.from);
    final fechaHasta = _toDateParam(window.to);

    print(
      '  📅 listar_ordenes por turno: desde=$fechaDesde hasta=$fechaHasta '
      '(apertura=${window.from?.toIso8601String()}, '
      'cierre=${window.to?.toIso8601String()})',
    );

    final response = await Supabase.instance.client.rpc(
      'listar_ordenes',
      params: {
        'con_inventario_param': false,
        // Fechas de calendario para acotar en servidor (el RPC usa DATE).
        // El filtro fino por hora del turno se aplica después en cliente.
        'fecha_desde_param': fechaDesde,
        'fecha_hasta_param': fechaHasta,
        'id_estado_param': null,
        'id_tienda_param': idTienda,
        'id_tipo_operacion_param': null,
        'id_tpv_param': idTpv,
        'id_usuario_param': userId,
        'limite_param': 200,
        'pagina_param': 1,
        'solo_pendientes_param': false,
      },
    );

    if (response is! List || response.isEmpty) {
      return [];
    }

    final raw = response.cast<Map<String, dynamic>>();
    return _filterOrdersByTurnoWindow(
      raw,
      from: window.from,
      to: window.to,
    );
  }

  /// Baja al cache local las órdenes/operaciones del servidor (turno abierto)
  /// e incluye las que solo existen allá. Reconcilia pending locales synced
  /// que ya aparecen en servidor para no duplicar en el listado.
  Future<int> _pullServerOrdersIntoCache() async {
    print('  ⬇️ Descargando operaciones del turno actual al dispositivo...');
    final window = await _resolveTurnoOperacionesWindow();
    if (window.from == null) {
      print(
        '  ⚠️ Sin fecha_apertura de turno: no se bajará cache de órdenes '
        '(evita mezclar turnos)',
      );
      return 0;
    }

    final orders = await _syncOrders();
    if (orders.isEmpty) {
      print(
        '  ℹ️ No hay operaciones en el rango del turno '
        '(${window.from?.toIso8601String()} → ${window.to?.toIso8601String()})',
      );
      // Limpia cache de órdenes de turnos anteriores para este dispositivo.
      await _userPreferencesService.mergeOfflineData({'orders': <dynamic>[]});
      return 0;
    }

    await _userPreferencesService.mergeOfflineData({'orders': orders});

    final serverOpIds = <int>{};
    for (final row in orders) {
      final raw = row['id_operacion'] ?? row['id'];
      final id =
          raw is int
              ? raw
              : (raw is num ? raw.toInt() : int.tryParse('$raw'));
      if (id != null) serverOpIds.add(id);
    }

    await _userPreferencesService.removeSyncedPendingPresentOnServer(
      serverOpIds,
    );

    try {
      await _syncResumenCierre();
      await _syncTurnoResumen();
    } catch (e) {
      print('  ⚠️ No se pudo refrescar resumen tras bajar órdenes: $e');
    }

    print(
      '  ✅ Cache local actualizado con ${orders.length} órdenes del turno',
    );
    return orders.length;
  }

  /// API pública: baja operaciones del turno actual (apertura→cierre/ahora).
  Future<int> pullServerOrdersForCurrentShift() => _pullServerOrdersIntoCache();

  /// Sincronizar ventas offline pendientes.
  /// Si [forTurno] se indica, solo sube órdenes de ese turno (local_turno_id
  /// o ventana de fechas legacy).
  Future<int> _syncOfflineSales({Map<String, dynamic>? forTurno}) async {
    final pendingOrders = await _userPreferencesService.getPendingOrders();
    var toSync =
        pendingOrders.where((o) => o['synced'] != true).toList(growable: false);

    if (forTurno != null) {
      toSync =
          toSync.where((o) => _orderBelongsToTurno(o, forTurno)).toList(
            growable: false,
          );
    }

    if (toSync.isEmpty) {
      print(
        '  📝 No hay ventas offline pendientes de subir'
        '${forTurno != null ? ' para turno ${forTurno['local_id']}' : ''}',
      );
      return 0;
    }

    print('  🔄 Sincronizando ${toSync.length} ventas offline...');
    int syncedCount = 0;
    final syncedOrderIds = <String>[];
    final syncedOperationIds = <String, int>{};

    for (var orderData in toSync) {
      final orderId = orderData['id']?.toString();
      try {
        if (orderId == null || orderId.isEmpty) {
          throw Exception('Orden offline sin ID');
        }

        print('    - Procesando venta offline: $orderId');

        await _userPreferencesService.clearPendingOrderError(orderId);
        await _registerClientFromOfflineData(orderData);
        await _registerSaleInSupabase(orderData);

        final estado = (orderData['estado'] ?? 'completada').toString();
        await _completeOrderWithStatus(orderId, estado);

        final opId = orderData['_operation_id'];
        if (opId is int) {
          syncedOperationIds[orderId] = opId;
        }

        syncedCount++;
        syncedOrderIds.add(orderId);
        print('    ✅ Venta offline sincronizada: $orderId');
      } catch (e) {
        print('    ❌ Error sincronizando venta offline ${orderData['id']}: $e');
        if (orderId != null && orderId.isNotEmpty) {
          await _userPreferencesService.markPendingOrderSyncFailure(
            orderId,
            e.toString(),
          );
        }
      }
    }

    if (syncedOrderIds.isNotEmpty) {
      await _userPreferencesService.markOrdersSyncedById(
        syncedOrderIds,
        operationIds: syncedOperationIds,
      );
      print(
        '  synced conservadas hasta cierre: ${syncedOrderIds.length}',
      );
    }

    return syncedCount;
  }

  /// Sube cambios de estado hechos offline sobre órdenes ya existentes en el
  /// servidor (creadas en modo online).
  Future<int> _syncOrderStatusChanges() async {
    final ops = await _userPreferencesService.getPendingOperations();
    final statusOps =
        ops.where((o) => o['type'] == 'order_status_change').toList();
    if (statusOps.isEmpty) return 0;

    print('  🔄 Sincronizando ${statusOps.length} cambios de estado...');
    final remaining = ops
        .where((o) => o['type'] != 'order_status_change')
        .map((o) => Map<String, dynamic>.from(o))
        .toList();
    var synced = 0;

    for (final op in statusOps) {
      try {
        final orderId = op['order_id']?.toString() ?? '';
        final rawOp = op['id_operacion'];
        int? operationId = rawOp is int
            ? rawOp
            : (rawOp is num ? rawOp.toInt() : int.tryParse('$rawOp'));
        operationId ??=
            int.tryParse(orderId.replaceFirst(RegExp(r'^ORD-'), ''));

        if (operationId == null) {
          // Orden 100% local: el estado viaja con pending_orders al subirla.
          remaining.add(Map<String, dynamic>.from(op));
          continue;
        }

        final statusStr = op['new_status']?.toString() ?? 'completada';
        final status = _orderStatusFromString(statusStr);
        if (status == null) {
          remaining.add(Map<String, dynamic>.from(op));
          continue;
        }

        final result = await OrderService().updateOrderStatusInSupabase(
          operationId,
          status,
        );
        if (result['success'] == true) {
          synced++;
          print('    ✅ Estado sync $orderId (op $operationId) -> $statusStr');
        } else {
          remaining.add(Map<String, dynamic>.from(op));
          print('    ⚠️ Estado no sync $orderId: ${result['error']}');
        }
      } catch (e) {
        remaining.add(Map<String, dynamic>.from(op));
        print('    ❌ Error sync cambio de estado: $e');
      }
    }

    await _userPreferencesService.savePendingOperations(remaining);
    return synced;
  }

  OrderStatus? _orderStatusFromString(String status) {
    switch (status.toLowerCase()) {
      case 'enviada':
      case 'pendiente':
      case 'procesando':
        return OrderStatus.enviada;
      case 'pago_confirmado':
      case 'pagoconfirmado':
        return OrderStatus.pagoConfirmado;
      case 'completada':
        return OrderStatus.completada;
      case 'cancelada':
        return OrderStatus.cancelada;
      case 'devuelta':
        return OrderStatus.devuelta;
      default:
        return null;
    }
  }

  /// Sincronizar una sola orden pendiente (para reintentos manuales desde la UI)
  /// Retorna true si la sincronización fue exitosa
  Future<bool> syncSinglePendingOrder(String orderId) async {
    try {
      // Verificar autenticación antes de intentar
      final isAuthenticated = await _reauthService.ensureAuthenticated();
      if (!isAuthenticated) {
        throw Exception('No se pudo autenticar al usuario');
      }

      final pendingOrders = await _userPreferencesService.getPendingOrders();
      final orderData = pendingOrders.firstWhere(
        (o) => o['id']?.toString() == orderId,
        orElse: () => <String, dynamic>{},
      );

      if (orderData.isEmpty) {
        print('⚠️ Orden $orderId no encontrada en pendientes');
        return false;
      }

      print('🔁 Reintento manual de orden offline: $orderId');
      await _userPreferencesService.clearPendingOrderError(orderId);

      await _registerClientFromOfflineData(orderData);
      await _registerSaleInSupabase(orderData);

      final estado = (orderData['estado'] ?? 'completada').toString();
      await _completeOrderWithStatus(orderId, estado);

      // Igual que el sync batch: asociar id_operacion y marcar sincronizada.
      final opId = orderData['_operation_id'];
      final operationIds = <String, int>{};
      if (opId is int) {
        operationIds[orderId] = opId;
      }

      await _userPreferencesService.markOrdersSyncedById(
        [orderId],
        operationIds: operationIds.isEmpty ? null : operationIds,
      );
      // Conservar en dispositivo hasta cierre de turno.
      print('✅ Reintento manual exitoso: $orderId (op=$opId)');
      return true;
    } catch (e) {
      print('❌ Reintento manual falló para $orderId: $e');
      await _userPreferencesService.markPendingOrderSyncFailure(
        orderId,
        e.toString(),
      );
      return false;
    }
  }

  /// Registrar cliente desde datos offline
  Future<void> _registerClientFromOfflineData(
    Map<String, dynamic> orderData,
  ) async {
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
      final subtotal =
          itemData['subtotal'] ??
          (itemData['precio_unitario'] * itemData['cantidad']);
      final cantidad = itemData['cantidad'] as num;
      final precioUnitarioCorrect =
          cantidad > 0 ? (subtotal / cantidad) : itemData['precio_unitario'];

      print(
        '    🔄 AUTO SYNC - Producto: ${itemData['denominacion'] ?? itemData['id_producto']}',
      );
      print('      - Precio unitario base: \$${itemData['precio_unitario']}');
      print('      - Subtotal con método de pago: \$${subtotal}');
      print('      - Precio unitario correcto: \$${precioUnitarioCorrect}');

      productos.add({
        'id_producto': itemData['id_producto'],
        'id_variante': inventoryMetadata['id_variante'],
        'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
        'id_ubicacion': inventoryMetadata['id_ubicacion'],
        // FASE 4: la presentación elegida vive en `inventory_metadata` (la pone
        // `_buildInventoryData`), pero la orden pendiente también la guarda al
        // nivel del ítem. Se prefiere la del ítem por si una metadata vieja no
        // la trae. `null` → el servidor resuelve la base.
        'id_presentacion': itemData['id_presentacion'] ??
            inventoryMetadata['id_presentacion'],
        'cantidad': itemData['cantidad'],
        'precio_unitario':
            precioUnitarioCorrect, // ✅ Precio correcto según método de pago
        'sku_producto':
            inventoryMetadata['sku_producto'] ??
            itemData['id_producto'].toString(),
        'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
        'es_producto_venta': true,
      });
    }

    // 🔑 IDEMPOTENCIA: usar client_uuid para que reintentos no dupliquen.
    // Si la orden no tiene client_uuid (creada antes de esta mejora), se genera
    // uno y se persiste para futuros reintentos.
    String? clientUuid = orderData['client_uuid']?.toString();
    if (clientUuid == null || clientUuid.isEmpty) {
      clientUuid = UuidGenerator.v4();
      orderData['client_uuid'] = clientUuid;
    }

    dynamic response;
    try {
      // Preferir el wrapper idempotente fn_registrar_venta_offline.
      response = await Supabase.instance.client.rpc(
        'fn_registrar_venta_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_codigo_promocion':
              orderData['promo_code'] ?? orderData['promoCode'],
          'p_denominacion': 'Venta Offline - ${orderData['id']}',
          'p_estado_inicial': 1, // Estado enviada
          'p_id_tpv': idTpv,
          'p_observaciones':
              orderData['notas'] ?? 'Sincronización de venta offline',
          'p_productos': productos,
          'p_uuid': userId,
          'p_id_cliente': orderData['idCliente'],
          'p_fecha_creacion':
              orderData['fecha_creacion'] ?? orderData['created_offline_at'],
        },
      );
    } catch (e) {
      // Fallback: si el RPC idempotente no existe aún (no se subió el .sql),
      // usar el RPC original. NOTA: sin idempotencia del servidor, el control
      // de duplicados depende del marcado local de órdenes sincronizadas.
      print(
        '⚠️ fn_registrar_venta_offline no disponible ($e). Usando fn_registrar_venta.',
      );
      response = await Supabase.instance.client.rpc(
        'fn_registrar_venta',
        params: {
          'p_codigo_promocion':
              orderData['promo_code'] ?? orderData['promoCode'],
          'p_denominacion': 'Venta Auto Sync - ${orderData['id']}',
          'p_estado_inicial': 1,
          'p_id_tpv': idTpv,
          'p_observaciones':
              orderData['notas'] ??
              'Sincronización automática de venta offline',
          'p_productos': productos,
          'p_uuid': userId,
          'p_id_cliente': orderData['idCliente'],
        },
      );
    }

    if (response != null && response['status'] == 'success') {
      // Obtener el ID de operación de la respuesta
      final operationId = response['id_operacion'] as int?;
      final bool yaExistia = response['idempotent'] == true;

      if (operationId != null) {
        // Guardar el ID de operación para usarlo en la actualización de estado
        orderData['_operation_id'] = operationId;

        if (yaExistia) {
          print(
            '    ♻️ Operación $operationId ya existía (idempotente); se reintentan pagos/estado de forma idempotente',
          );
        }

        // ⚠️ Pagos y cambio de estado se ejecutan SIEMPRE (también si la venta
        // ya existía), porque la conexión pudo cortarse ENTRE la creación de la
        // operación y estos pasos. Son idempotentes (client_uuid propio por
        // propósito), así que reintentarlos no duplica.

        // Registrar desgloses de pago si existen (idempotente).
        // El desglose de "Pago Pendiente" (CxC, id sentinel 998) se excluye:
        // no genera fila en app_dat_pago_venta y deja la venta con
        // es_pagada = false (cuenta por cobrar).
        final paymentBreakdown = orderData['desglose_pagos'] as List<dynamic>?;
        final montoPendienteCxc = (paymentBreakdown ?? [])
            .cast<Map<String, dynamic>>()
            .where((p) => p['id_medio_pago'] == pm.PaymentMethod.pagoPendienteId)
            .fold<double>(0.0, (sum, p) => sum + ((p['monto'] as num?)?.toDouble() ?? 0.0));
        if (montoPendienteCxc > 0) {
          try {
            final idClienteCxcRaw =
                orderData['id_cliente_cxc'] ?? orderData['idClienteCxc'];
            final idClienteCxc =
                idClienteCxcRaw is int
                    ? idClienteCxcRaw
                    : (idClienteCxcRaw is num
                        ? idClienteCxcRaw.toInt()
                        : int.tryParse('$idClienteCxcRaw'));
            await Supabase.instance.client
                .from('app_dat_operacion_venta')
                .update({
                  'es_pagada': false,
                  if (idClienteCxc != null) 'id_cliente_cxc': idClienteCxc,
                })
                .eq('id_operacion', operationId);
            if (idClienteCxc == null) {
              print(
                '    ⚠️ CxC sync sin id_cliente_cxc en orden local '
                '(op=$operationId) — no aparecerá en cartera hasta asociarlo',
              );
            }
          } catch (e) {
            print('    ⚠️ No se pudo marcar es_pagada=false en $operationId: $e');
          }
        }
        final pagosSinCxc = (paymentBreakdown ?? [])
            .cast<Map<String, dynamic>>()
            .where((p) => p['id_medio_pago'] != pm.PaymentMethod.pagoPendienteId)
            .toList();
        if (pagosSinCxc.isNotEmpty) {
          await _registerPaymentBreakdownFromOfflineData(
            operationId,
            pagosSinCxc,
            orderData,
            userId,
          );
        }

        // Cambio de estado final según el estado de NEGOCIO de la orden.
        // 'estado' puede valer 'pendiente_sincronizacion' (estado de sync, no
        // de negocio); en ese caso se usa 'estado_final' (default 'completada'
        // para ventas de checkout). Idempotente.
        var estado = orderData['estado'];
        if (estado == null || estado == 'pendiente_sincronizacion') {
          estado = orderData['estado_final'] ?? 'completada';
        }
        int? nuevoEstado;
        if (estado == 'completada') {
          nuevoEstado = 2;
        } else if (estado == 'cancelada') {
          nuevoEstado = 4;
        } else if (estado == 'devuelta') {
          nuevoEstado = 3;
        }

        if (nuevoEstado != null) {
          await _registerCambioEstadoIdempotente(
            operationId: operationId,
            nuevoEstado: nuevoEstado,
            userId: userId,
            orderData: orderData,
          );
        }

        // Subir foto de operación pendiente (si se capturó offline)
        await _uploadPendingOperationPhoto(operationId, orderData);
      }
    } else {
      throw Exception(response?['message'] ?? 'Error en el registro de venta');
    }
  }

  /// Sube la foto guardada localmente (o en base64) y la asocia a la operación.
  Future<void> _uploadPendingOperationPhoto(
    int operationId,
    Map<String, dynamic> orderData,
  ) async {
    try {
      Uint8List? bytes;
      final mime =
          orderData['foto_operacion_mime']?.toString() ?? 'image/jpeg';
      final localPath = orderData['foto_operacion_local_path']?.toString();
      final b64 = orderData['foto_operacion_base64']?.toString();

      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (await file.exists()) {
          bytes = await file.readAsBytes();
        }
      } else if (b64 != null && b64.isNotEmpty) {
        bytes = Uint8List.fromList(base64Decode(b64));
      }

      if (bytes == null || bytes.isEmpty) return;

      final ext = mime.contains('png') ? 'png' : 'jpg';
      final path =
          'operaciones/${operationId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage
          .from('productos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime),
          );
      final url =
          Supabase.instance.client.storage.from('productos').getPublicUrl(path);

      await Supabase.instance.client
          .from('app_dat_operaciones')
          .update({'foto_operacion_url': url})
          .eq('id', operationId);

      // Limpiar archivo local
      if (localPath != null) {
        try {
          final file = File(localPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      orderData.remove('foto_operacion_local_path');
      orderData.remove('foto_operacion_base64');
      print('    📷 Foto de operación $operationId subida');
    } catch (e) {
      // No fallar toda la sync por la foto; se reintentará en el próximo pase
      // mientras el archivo local siga existiendo.
      print('    ⚠️ Error subiendo foto de operación $operationId: $e');
    }
  }

  /// Aplica un cambio de estado de operación de forma idempotente.
  /// Usa un client_uuid propio por (orden, estado) persistido en orderData para
  /// que un reintento no duplique el registro de auditoría. Fallback al RPC
  /// original si el wrapper offline no está desplegado.
  Future<void> _registerCambioEstadoIdempotente({
    required int operationId,
    required int nuevoEstado,
    required dynamic userId,
    required Map<String, dynamic> orderData,
  }) async {
    // client_uuid estable por cambio de estado (uno por estado destino).
    final key = 'client_uuid_estado_$nuevoEstado';
    var estadoUuid = orderData[key]?.toString();
    if (estadoUuid == null || estadoUuid.isEmpty) {
      estadoUuid = UuidGenerator.v4();
      orderData[key] = estadoUuid;
    }

    try {
      await Supabase.instance.client.rpc(
        'fn_registrar_cambio_estado_offline',
        params: {
          'p_client_uuid': estadoUuid,
          'p_id_operacion': operationId,
          'p_nuevo_estado': nuevoEstado,
          'p_uuid_usuario': userId,
        },
      );
      print('    ✅ Estado $nuevoEstado aplicado (idempotente) a op $operationId');
    } catch (e) {
      // Fallback: wrapper no disponible. NOTA: sin idempotencia del servidor,
      // un reintento podría duplicar el registro de auditoría del cambio.
      print(
        '    ⚠️ fn_registrar_cambio_estado_offline no disponible ($e). Usando RPC original.',
      );
      await Supabase.instance.client.rpc(
        'fn_registrar_cambio_estado_operacion',
        params: {
          'p_id_operacion': operationId,
          'p_nuevo_estado': nuevoEstado,
          'p_uuid_usuario': userId,
        },
      );
    }
  }

  /// Registrar desgloses de pago desde datos offline (idempotente).
  ///
  /// Usa fn_registrar_pago_venta_offline con un client_uuid propio por orden
  /// (persistido en orderData), de modo que un reintento NO duplique los pagos.
  /// Fallback a fn_registrar_pago_venta si el wrapper no está desplegado.
  Future<void> _registerPaymentBreakdownFromOfflineData(
    int operationId,
    List<dynamic> paymentBreakdown,
    Map<String, dynamic> orderData,
    dynamic userId,
  ) async {
    try {
      // Referencia determinista (basada en la orden) para que el fallback NO
      // genere referencias distintas en cada reintento.
      final refBase = orderData['client_uuid'] ?? orderData['id'] ?? operationId;

      // Preparar array de pagos para la función RPC
      List<Map<String, dynamic>> pagos = [];

      for (final payment in paymentBreakdown) {
        final paymentData = payment as Map<String, dynamic>;
        pagos.add({
          'id_medio_pago': paymentData['id_medio_pago'],
          'monto': paymentData['monto'],
          'referencia_pago': 'Pago Offline - $refBase',
        });
      }

      // client_uuid estable para el registro de pagos de esta operación.
      var pagoUuid = orderData['client_uuid_pago']?.toString();
      if (pagoUuid == null || pagoUuid.isEmpty) {
        pagoUuid = UuidGenerator.v4();
        orderData['client_uuid_pago'] = pagoUuid;
      }

      bool ok = false;
      try {
        // Preferir el wrapper idempotente.
        final resp = await Supabase.instance.client.rpc(
          'fn_registrar_pago_venta_offline',
          params: {
            'p_client_uuid': pagoUuid,
            'p_id_operacion_venta': operationId,
            'p_pagos': pagos,
            'p_uuid_usuario': userId,
          },
        );
        ok = resp is Map && resp['success'] == true;
        if (ok && resp['idempotent'] == true) {
          print('    ♻️ Pagos ya registrados (idempotente) para op $operationId');
        }
      } catch (e) {
        // Fallback: wrapper no disponible. NOTA: sin idempotencia del servidor,
        // un reintento podría duplicar los pagos.
        print(
          '    ⚠️ fn_registrar_pago_venta_offline no disponible ($e). Usando RPC original.',
        );
        final response = await Supabase.instance.client.rpc(
          'fn_registrar_pago_venta',
          params: {'p_id_operacion_venta': operationId, 'p_pagos': pagos},
        );
        ok = response == true;
      }

      if (ok) {
        print(
          '    ✅ Desgloses de pago registrados para operación: $operationId',
        );
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

  /// Marcar órdenes como sincronizadas SIN eliminarlas.
  ///
  /// ⚠️ Antes este método BORRABA las órdenes sincronizadas de pending_orders.
  /// Como en modo offline la pantalla de órdenes solo lee de pending_orders /
  /// caché, las órdenes activas (no completadas) DESAPARECÍAN de la vista tras
  /// sincronizar aunque siguieran activas en el servidor.
  ///
  /// Nuevo comportamiento: la orden se MARCA `synced: true` y conserva su
  /// `id_operacion` del servidor. Sigue visible en orders_screen. La purga real
  /// del array local ocurre por separado (ver markOrdersSyncedById /
  /// purgeFinalizedSyncedOrders en UserPreferencesService) solo cuando la orden
  /// llega a estado final o cuando ya se recargó del servidor.
  Future<void> _cleanupSyncedOrders(List<String> syncedOrderIds) async {
    try {
      await _userPreferencesService.markOrdersSyncedById(syncedOrderIds);
      print(
        '  🔖 ${syncedOrderIds.length} órdenes marcadas como sincronizadas (conservadas para la vista)',
      );
    } catch (e) {
      print('  ⚠️ Error marcando órdenes sincronizadas: $e');
    }
  }

  /// Forzar una sincronización inmediata.
  ///
  /// [allowWhileOffline]: si true, ejecuta uploads (ventas pendientes, etc.)
  /// aunque el modo offline esté activo — usado por el FAB de órdenes cuando
  /// el usuario confirma explícitamente sincronizar.
  Future<void> forceSyncNow({bool allowWhileOffline = false}) async {
    if (_isSyncing) {
      print('⏳ Sincronización ya en progreso');
      return;
    }

    print(
      '🚀 Forzando sincronización inmediata'
      '${allowWhileOffline ? " (permitida en modo offline)" : ""}...',
    );

    if (!allowWhileOffline) {
      await _performSync();
      return;
    }

    // Bypass del guard de modo offline: solo módulos de subida.
    final wasOffline = await _userPreferencesService.isOfflineModeEnabled();
    if (wasOffline) {
      await _userPreferencesService.setOfflineMode(false);
    }
    try {
      await syncModules({
        SyncModule.uploadTurno,
        SyncModule.uploadSales,
        SyncModule.uploadEgresos,
        SyncModule.uploadShiftWorkers,
        SyncModule.uploadAdminOps,
      });
    } finally {
      if (wasOffline) {
        await _userPreferencesService.setOfflineMode(true);
      }
    }
  }


  /// Sincroniza la cola de turnos offline (apertura → ventas → egresos → cierre).
  /// Pensado para Admin Lite en full offline cuando el gerente tiene red.
  Future<Map<String, dynamic>> syncOfflineTurnosFromAdmin({
    bool includeRelatedUploads = true,
  }) async {
    if (_isSyncing) {
      throw Exception('Ya hay una sincronización en curso');
    }

    final wasOffline = await _userPreferencesService.isOfflineModeEnabled();
    if (wasOffline) {
      await _userPreferencesService.setOfflineMode(false);
    }

    _isSyncing = true;
    final start = DateTime.now();
    try {
      final isAuthenticated = await _reauthService.ensureAuthenticated();
      if (!isAuthenticated) {
        throw Exception(
          'No se pudo autenticar. Inicia sesión online o registra '
          'credenciales en Preparar dispositivo.',
        );
      }

      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncStarted,
          timestamp: start,
          message: 'Sincronizando turnos offline (admin)',
        ),
      );

      final queue = await _syncOfflineTurnoQueue();
      final related = <String, dynamic>{};

      if (includeRelatedUploads) {
        try {
          related['shift_workers'] =
              await ShiftWorkersService.syncPendingOperations();
        } catch (e) {
          print('⚠️ Admin sync workers: $e');
          related['shift_workers_error'] = e.toString();
        }
        try {
          related['admin_ops'] =
              await AdminInventoryService().syncPendingOps();
        } catch (e) {
          print('⚠️ Admin sync ops: $e');
          related['admin_ops_error'] = e.toString();
        }
      }

      final duration = DateTime.now().difference(start);
      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncCompleted,
          timestamp: DateTime.now(),
          message: 'Turnos offline sincronizados',
          duration: duration,
        ),
      );

      return {
        'success': true,
        'queue': queue,
        'related': related,
        'duration_ms': duration.inMilliseconds,
      };
    } catch (e) {
      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncFailed,
          timestamp: DateTime.now(),
          message: 'Error sincronizando turnos: $e',
          error: e.toString(),
        ),
      );
      rethrow;
    } finally {
      _isSyncing = false;
      if (wasOffline) {
        await _userPreferencesService.setOfflineMode(true);
      }
    }
  }

  /// Tras un cierre local de un turno offline: intenta ahora
  /// apertura → ventas → egresos → cierre en el servidor.
  ///
  /// Prioriza [localId] (no se bloquea por otros turnos fallidos de la cola).
  /// Retorna un mapa: `{success: bool, message: String?}`.
  Future<Map<String, dynamic>> syncOfflineTurnoAfterLocalCierre({
    String? localId,
  }) async {
    print(
      '[TURNO_SYNC] ▶▶▶ syncOfflineTurnoAfterLocalCierre START '
      'localId=$localId isSyncing=$_isSyncing',
    );
    await _userPreferencesService.dumpOfflineTurnosQueue(
      'ENTRADA syncOfflineTurnoAfterLocalCierre',
    );

    // Esperar a que termine un sync automático en curso (puede ser largo).
    for (var attempt = 0; attempt < 3; attempt++) {
      await waitUntilIdle(timeout: const Duration(seconds: 60));
      if (!_isSyncing) break;
      print(
        '[TURNO_SYNC] ⏳ syncOfflineTurnoAfterLocalCierre esperando sync '
        '(intento ${attempt + 1}/3)...',
      );
    }

    if (_isSyncing) {
      _pendingSyncRequested = true;
      print(
        '[TURNO_SYNC] ⚠️ sync aún ocupado; se encola pase al terminar',
      );
      return {
        'success': false,
        'message':
            'Hay una sincronización en curso. El cierre quedó pendiente '
            'y se reintentará automáticamente.',
      };
    }

    final wasOffline = await _userPreferencesService.isOfflineModeEnabled();
    print('[TURNO_SYNC] wasOffline=$wasOffline → forzando online temporal');
    _isSyncing = true;
    try {
      if (wasOffline) {
        await _userPreferencesService.setOfflineMode(false);
      }

      final isAuthenticated = await _reauthService.ensureAuthenticated();
      print('[TURNO_SYNC] autenticado=$isAuthenticated');
      if (!isAuthenticated) {
        return {
          'success': false,
          'message':
              'No se pudo autenticar. El cierre quedó pendiente de sync.',
        };
      }

      var ok = false;
      String? detail;

      if (localId != null && localId.isNotEmpty) {
        final entry =
            await _userPreferencesService.getOfflineTurnoByLocalId(localId);
        if (entry == null) {
          ok = true;
          detail = 'Turno ya no estaba pendiente';
          print('[TURNO_SYNC] entry null para $localId → tratado synced');
        } else if (entry['status'] ==
            UserPreferencesService.offlineTurnoStatusSynced) {
          ok = true;
          detail = 'Turno ya sincronizado';
          print(
            '[TURNO_SYNC] entry ya synced: '
            '${UserPreferencesService.describeOfflineTurnoEntry(entry)}',
          );
        } else {
          print(
            '[TURNO_SYNC] syncando entry: '
            '${UserPreferencesService.describeOfflineTurnoEntry(entry)}',
          );
          ok = await _syncSingleOfflineTurnoEntry(entry);
          if (!ok) {
            detail =
                'No se pudo abrir/cerrar el turno en el servidor. '
                'Revisa inventario/productos o reintenta desde Admin.';
          }
        }
      } else {
        final result = await _syncOfflineTurnoQueue();
        print('[TURNO_SYNC] Resultado sync post-cierre (cola): $result');
        ok = (result['closed_remaining'] as int? ?? 1) == 0;
        if (!ok) {
          final failed = result['failed_cierres'];
          detail =
              failed is List && failed.isNotEmpty
                  ? 'Falló el cierre de: ${failed.join(", ")}'
                  : 'Quedaron turnos pendientes de sincronizar';
        }
      }

      if (ok) {
        try {
          await _syncOfflineTurnoQueue();
        } catch (e) {
          print('[TURNO_SYNC] ⚠️ Sync cola restante post-cierre: $e');
        }
      }

      print(
        '[TURNO_SYNC] ◀◀◀ syncOfflineTurnoAfterLocalCierre END '
        'ok=$ok detail=$detail',
      );
      await _userPreferencesService.dumpOfflineTurnosQueue(
        'SALIDA syncOfflineTurnoAfterLocalCierre ok=$ok',
      );

      return {
        'success': ok,
        'message': detail,
      };
    } catch (e, st) {
      print('[TURNO_SYNC] ❌ syncOfflineTurnoAfterLocalCierre falló: $e');
      print(st);
      return {
        'success': false,
        'message': 'Error sincronizando el cierre: $e',
      };
    } finally {
      _isSyncing = false;
      if (wasOffline) {
        await _userPreferencesService.setOfflineMode(true);
        print('[TURNO_SYNC] restaurado modo offline=true');
      }
      if (_pendingSyncRequested &&
          !(await _userPreferencesService.isOfflineModeEnabled())) {
        _pendingSyncRequested = false;
        // ignore: unawaited_futures
        _performSync();
      }
    }
  }

  /// Sincroniza turno (apertura) + ventas pendientes + baja operaciones del
  /// servidor + cierre (si aplica). Replay ordenado de la cola multi-turno.
  Future<int> forceSyncPendingOrders() async {
    final isAuthenticated = await _reauthService.ensureAuthenticated();
    if (!isAuthenticated) {
      throw Exception('No se pudo autenticar al usuario para sincronización');
    }

    int synced = 0;
    try {
      final result = await _syncOfflineTurnoQueue();
      synced = (result['sales'] as int?) ?? 0;
    } catch (e) {
      print('⚠️ Error en replay de cola de turnos: ');
      synced = await _syncOfflineSales();
    }

    try {
      await _pullServerOrdersIntoCache();
    } catch (e) {
      print('⚠️ No se pudieron descargar órdenes del servidor: ');
    }

    try {
      await _syncOrderStatusChanges();
    } catch (e) {
      print('⚠️ No se pudieron sincronizar cambios de estado: $e');
    }

    return synced;
  }

  /// Esperar a que NO haya ningún pase de sincronización en curso.
  ///
  /// Si no se está sincronizando, retorna de inmediato. Si hay un pase en
  /// curso, espera el próximo evento de fin (`syncCompleted` o `syncFailed`)
  /// del stream existente. El [timeout] es una red de seguridad: si se agota,
  /// retorna igualmente (no lanza) para no dejar la UI bloqueada.
  ///
  /// Se usa al cambiar el modo offline para drenar cualquier sincronización
  /// (automática o forzada) antes de cambiar de estado y evitar inconsistencias.
  Future<void> waitUntilIdle({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isSyncing) return;

    print('⏳ Esperando a que termine la sincronización en curso...');
    try {
      await _syncEventController.stream
          .firstWhere(
            (event) =>
                event.type == AutoSyncEventType.syncCompleted ||
                event.type == AutoSyncEventType.syncFailed,
          )
          .timeout(timeout);
    } on TimeoutException {
      print('⚠️ waitUntilIdle agotó el timeout; continuando de todos modos');
    } catch (e) {
      print('⚠️ waitUntilIdle terminó con error ($e); continuando');
    }
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
        print(
          '❌ No se pudo obtener ID de tienda para sincronizar configuración',
        );
        return;
      }

      // Sincronizar configuración usando StoreConfigService
      final success = await StoreConfigService.syncStoreConfig(idTienda);

      if (success) {
        print('✅ Configuración de tienda sincronizada exitosamente');

        // Renovar licencia firmada junto con la config (obligatorio para offline)
        try {
          print('🔐 Renovando licencia firmada...');
          final fetched =
              await OfflineLicenseService().fetchAndStoreSignedLicense(idTienda);
          print(fetched
              ? '✅ Licencia firmada renovada'
              : '⚠️ No se pudo renovar licencia firmada');
        } catch (e) {
          print('⚠️ Error renovando licencia firmada: $e');
        }
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

  // ========== SYNC SELECTIVA POR MÓDULOS (Fase 4) ==========

  /// Sincroniza solo los módulos indicados, por partes y con recuperación.
  ///
  /// - Timeout por módulo (no cuelga indefinido si cae la red).
  /// - Si se pierde la conexión, aborta el resto y guarda checkpoint.
  /// - En la siguiente corrida reanuda saltando módulos ya OK.
  /// - El resultado reporta OK / fallidos / omitidos aunque sea parcial.
  ///
  /// [acquireLock]: false cuando el caller ya puso [_isSyncing] (auto/reconnect).
  Future<SyncResult> syncModules(
    Set<SyncModule> modules, {
    bool requireAuth = true,
    bool acquireLock = true,
    bool resumeFromCheckpoint = true,
  }) async {
    final startTime = DateTime.now();
    final syncedItems = <String>[];
    final errors = <String>[];
    final skippedItems = <String>[];
    final completedModuleNames = <String>[];
    final syncedData = <String, dynamic>{};
    final connectivity = ConnectivityService();

    var tookLock = false;
    if (acquireLock) {
      if (_isSyncing) {
        return SyncResult(
          success: false,
          interrupted: false,
          syncedItems: const [],
          errors: const ['Ya hay una sincronización en curso'],
          skippedItems: modules.map((m) => m.label).toList(),
          duration: Duration.zero,
        );
      }
      _isSyncing = true;
      tookLock = true;
    }

    // Licencia siempre si hay módulos de descarga
    final hasDownload = modules.any((m) => m.isDownload);
    final effective = Set<SyncModule>.from(modules);
    if (hasDownload) {
      effective.add(SyncModule.license);
    }

    try {
      if (requireAuth) {
        final isAuthenticated = await _reauthService.ensureAuthenticated();
        if (!isAuthenticated) {
          throw Exception('No se pudo autenticar al usuario para sincronización');
        }
      }

      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncStarted,
          timestamp: startTime,
          message: 'Sincronización iniciada',
        ),
      );

      // Orden fijo del pipeline (solo cuentan los seleccionados en [effective]).
      const pipelineOrder = [
        SyncModule.uploadTurno,
        SyncModule.uploadSales,
        SyncModule.uploadEgresos,
        SyncModule.uploadShiftWorkers,
        SyncModule.uploadAdminOps,
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
      ];
      final ordered = pipelineOrder.where(effective.contains).toList();
      final totalSteps = ordered.length;
      var stepIndex = 0;

      final skipCompleted = <SyncModule>{};
      if (resumeFromCheckpoint) {
        final cp = await _userPreferencesService.getSyncModulesCheckpoint();
        if (cp != null) {
          final completed =
              (cp['completed'] as List?)?.map((e) => '$e').toSet() ?? {};
          for (final m in ordered) {
            if (completed.contains(m.name)) {
              skipCompleted.add(m);
            }
          }
          if (skipCompleted.isNotEmpty) {
            print(
              '♻️ Reanudando sync: saltando ${skipCompleted.length} '
              'módulo(s) ya OK del checkpoint',
            );
          }
        }
      }

      var aborted = false;
      String? abortReason;
      final deadline = startTime.add(_syncTimeout);

      Future<bool> connectionAlive({bool probe = false}) async {
        if (!connectivity.isConnected || probe) {
          return connectivity.probeInternetSilent();
        }
        return true;
      }

      Future<void> persistCheckpoint() async {
        final pending =
            ordered
                .where((m) => !completedModuleNames.contains(m.name))
                .map((m) => m.name)
                .toList();
        if (completedModuleNames.isEmpty && pending.isEmpty) return;
        if (errors.isEmpty && pending.isEmpty) {
          await _userPreferencesService.clearSyncModulesCheckpoint();
          return;
        }
        await _userPreferencesService.saveSyncModulesCheckpoint(
          completedModules: List<String>.from(completedModuleNames),
          pendingModules: pending,
          errors: List<String>.from(errors),
          abortReason: abortReason,
        );
      }

      Future<void> run(
        SyncModule module,
        String label,
        Future<void> Function() action,
      ) async {
        if (!effective.contains(module)) return;

        if (aborted) {
          skippedItems.add(label);
          return;
        }

        if (DateTime.now().isAfter(deadline)) {
          aborted = true;
          abortReason = 'Tiempo máximo de sincronización agotado';
          errors.add(abortReason!);
          skippedItems.add(label);
          return;
        }

        stepIndex++;

        if (skipCompleted.contains(module)) {
          syncedItems.add('$label (reanudado)');
          completedModuleNames.add(module.name);
          _syncEventController.add(
            AutoSyncEvent(
              type: AutoSyncEventType.syncProgress,
              timestamp: DateTime.now(),
              message: '$label (ya OK)',
              progressCurrent: stepIndex,
              progressTotal: totalSteps,
            ),
          );
          return;
        }

        final online = await connectionAlive();
        if (!online) {
          aborted = true;
          abortReason = 'Conexión perdida';
          errors.add('Interrumpido: conexión perdida antes de $label');
          skippedItems.add(label);
          await persistCheckpoint();
          return;
        }

        try {
          _syncEventController.add(
            AutoSyncEvent(
              type: AutoSyncEventType.syncProgress,
              timestamp: DateTime.now(),
              message: label,
              progressCurrent: stepIndex,
              progressTotal: totalSteps,
            ),
          );
          await action().timeout(_timeoutForModule(module));
          syncedItems.add(label);
          completedModuleNames.add(module.name);
          await persistCheckpoint();
        } on TimeoutException catch (e) {
          print('⏱️ Timeout en módulo $label: $e');
          errors.add('$label: tiempo agotado (posible pérdida de red)');
          final stillOnline = await connectionAlive(probe: true);
          if (!stillOnline) {
            aborted = true;
            abortReason = 'Conexión perdida';
            errors.add('Interrumpido tras timeout en $label');
          }
          await persistCheckpoint();
        } catch (e) {
          print('❌ Error en módulo $label: $e');
          errors.add('$label: $e');
          if (_looksLikeConnectionError(e)) {
            final stillOnline = await connectionAlive(probe: true);
            if (!stillOnline) {
              aborted = true;
              abortReason = 'Conexión perdida';
              errors.add('Interrumpido por red en $label');
            }
          }
          await persistCheckpoint();
        }
      }

      // --- Upload primero (para no perder ventas locales) ---
      // Replay ordenado: apertura → ventas → egresos → cierre por cada turno.
      var queueAlreadyRan = false;
      await run(SyncModule.uploadTurno, 'Turnos offline (cola)', () async {
        final result = await _syncOfflineTurnoQueue();
        queueAlreadyRan = true;
        if ((result['turnos'] as int? ?? 0) > 0) {
          syncedData['offline_turnos'] = result;
        }
      });

      await run(SyncModule.uploadSales, 'Ventas offline (subir)', () async {
        if (!queueAlreadyRan) {
          final result = await _syncOfflineTurnoQueue();
          queueAlreadyRan = true;
          if ((result['sales'] as int? ?? 0) > 0) {
            syncedData['offline_sales'] = result['sales'];
          }
        } else {
          final n = await _syncOfflineSales();
          if (n > 0) syncedData['offline_sales'] = n;
        }
        final statusN = await _syncOrderStatusChanges();
        if (statusN > 0) {
          syncedData['order_status_changes'] = statusN;
        }
      });

      await run(SyncModule.uploadEgresos, 'Egresos offline (subir)', () async {
        if (!queueAlreadyRan) {
          final result = await _syncOfflineTurnoQueue();
          queueAlreadyRan = true;
          if ((result['egresos'] as int? ?? 0) > 0) {
            syncedData['offline_egresos'] = result['egresos'];
          }
        } else {
          final n = await _syncOfflineEgresos();
          if (n > 0) syncedData['offline_egresos'] = n;
        }
      });

      await run(
        SyncModule.uploadShiftWorkers,
        'Trabajadores de turno (subir)',
        () async {
          final n = await ShiftWorkersService.syncPendingOperations();
          if (n > 0) syncedData['shift_workers_synced'] = n;
        },
      );

      await run(
        SyncModule.uploadAdminOps,
        'Admin inventario/productos (subir)',
        () async {
          final n = await AdminInventoryService().syncPendingOps();
          if (n > 0) syncedData['admin_ops_synced'] = n;
        },
      );

      // --- Download ---
      await run(SyncModule.license, 'Licencia', () async {
        final idTienda = await _userPreferencesService.getIdTienda();
        if (idTienda == null) throw Exception('Sin id de tienda');
        final ok =
            await OfflineLicenseService().fetchAndStoreSignedLicense(idTienda);
        if (!ok) throw Exception('No se pudo renovar la licencia firmada');
      });

      await run(SyncModule.storeConfig, 'Configuración de tienda', () async {
        await _syncStoreConfig();
      });

      await run(SyncModule.credentials, 'Credenciales', () async {
        syncedData['credentials'] = await _syncCredentials();
      });

      await run(SyncModule.paymentMethods, 'Métodos de pago', () async {
        final methods = await _syncPaymentMethods();
        if (methods.isNotEmpty) {
          syncedData['payment_methods'] = methods;
        }
      });

      await run(SyncModule.promotions, 'Promociones', () async {
        syncedData['promotions'] = await _syncPromotions();
      });

      await run(SyncModule.categories, 'Categorías', () async {
        syncedData['categories'] = await _syncCategories();
      });

      await run(SyncModule.products, 'Productos', () async {
        syncedData['products'] = await _syncProducts();
        final productsData = syncedData['products'];
        if (productsData is Map<String, dynamic> && productsData.isNotEmpty) {
          await _syncProductPromotions(productsData);
        }
        try {
          final crm = await AdminInventoryService().syncCrmCacheFromServer();
          print(
            '✅ CRM cache admin: ${crm['suppliers']} proveedores, '
            '${crm['customers']} clientes',
          );
        } catch (e) {
          print('⚠️ Sync CRM admin (no bloqueante): $e');
        }
        try {
          final tpv = await AdminInventoryService().syncTpvsAndPricesFromServer();
          print(
            '✅ TPV cache admin: ${tpv['tpvs']} TPVs, '
            '${tpv['tpv_prices']} precios',
          );
        } catch (e) {
          print('⚠️ Sync precios TPV admin (no bloqueante): $e');
        }
      });

      await run(SyncModule.layouts, 'Ubicaciones / layouts', () async {
        final n = await AdminInventoryService().syncLayoutsFromServer();
        print('✅ Layouts/ubicaciones cacheados: $n');
        if (n == 0) {
          throw Exception(
            'No se obtuvieron layouts/ubicaciones. '
            'Verifica almacenes de la tienda y sesión.',
          );
        }
      });

      await run(SyncModule.turno, 'Turno (bajar)', () async {
        final turnoData = await _syncTurno();
        syncedData['turno'] = turnoData;
        if (turnoData != null) {
          await _userPreferencesService.saveOfflineTurno(turnoData);
        }
        await _syncTurnoResumen();
        await _syncResumenCierre();
      });

      await run(SyncModule.egresos, 'Egresos (bajar)', () async {
        await _syncEgresos();
      });

      await run(SyncModule.orders, 'Órdenes (bajar)', () async {
        final orders = await _syncOrders();
        syncedData['orders'] = orders;
        final serverOpIds = <int>{};
        for (final row in orders) {
          final raw = row['id_operacion'] ?? row['id'];
          final id =
              raw is int
                  ? raw
                  : (raw is num ? raw.toInt() : int.tryParse('$raw'));
          if (id != null) serverOpIds.add(id);
        }
        await _userPreferencesService.removeSyncedPendingPresentOnServer(
          serverOpIds,
        );
      });

      // Si abortamos a mitad, marcar el resto del pipeline como omitido.
      if (aborted) {
        for (final m in ordered) {
          if (completedModuleNames.contains(m.name)) continue;
          final label = m.label;
          if (!skippedItems.contains(label) &&
              !syncedItems.any((s) => s.startsWith(label)) &&
              !errors.any((e) => e.startsWith(label))) {
            skippedItems.add(label);
          }
        }
      }

      if (syncedData.isNotEmpty) {
        await _userPreferencesService.mergeOfflineData(syncedData);
      }

      final duration = DateTime.now().difference(startTime);
      final fullyOk = errors.isEmpty && !aborted;
      final isPartial =
          syncedItems.isNotEmpty && (errors.isNotEmpty || aborted);
      final hardFail = syncedItems.isEmpty && (errors.isNotEmpty || aborted);

      if (fullyOk) {
        await _userPreferencesService.clearSyncModulesCheckpoint();
      } else {
        await persistCheckpoint();
      }

      final summary = SyncResult.buildSummary(
        syncedItems: syncedItems,
        errors: errors,
        skippedItems: skippedItems,
        interrupted: aborted,
        abortReason: abortReason,
      );

      _syncEventController.add(
        AutoSyncEvent(
          type:
              hardFail
                  ? AutoSyncEventType.syncFailed
                  : AutoSyncEventType.syncCompleted,
          timestamp: DateTime.now(),
          message: summary,
          duration: duration,
          itemsSynced: syncedItems,
          skippedItems: skippedItems,
          error: fullyOk ? null : errors.join('; '),
          isPartial: isPartial || aborted,
          progressCurrent: totalSteps,
          progressTotal: totalSteps,
        ),
      );

      return SyncResult(
        success: fullyOk,
        interrupted: aborted,
        syncedItems: syncedItems,
        errors: errors,
        skippedItems: skippedItems,
        duration: duration,
        abortReason: abortReason,
      );
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      errors.add(e.toString());
      if (completedModuleNames.isNotEmpty || syncedItems.isNotEmpty) {
        await _userPreferencesService.saveSyncModulesCheckpoint(
          completedModules: completedModuleNames,
          pendingModules:
              modules
                  .where((m) => !completedModuleNames.contains(m.name))
                  .map((m) => m.name)
                  .toList(),
          errors: errors,
          abortReason: e.toString(),
        );
      }

      final summary = SyncResult.buildSummary(
        syncedItems: syncedItems,
        errors: errors,
        skippedItems: skippedItems,
        interrupted: true,
        abortReason: e.toString(),
      );

      _syncEventController.add(
        AutoSyncEvent(
          type:
              syncedItems.isEmpty
                  ? AutoSyncEventType.syncFailed
                  : AutoSyncEventType.syncCompleted,
          timestamp: DateTime.now(),
          message: summary,
          duration: duration,
          itemsSynced: syncedItems,
          skippedItems: skippedItems,
          error: e.toString(),
          isPartial: syncedItems.isNotEmpty,
        ),
      );
      return SyncResult(
        success: false,
        interrupted: true,
        syncedItems: syncedItems,
        errors: errors,
        skippedItems: skippedItems,
        duration: duration,
        abortReason: e.toString(),
      );
    } finally {
      if (tookLock) {
        _isSyncing = false;
        if (_pendingSyncRequested) {
          _pendingSyncRequested = false;
          unawaited(_performSync());
        } else if (_pendingReconnectSync) {
          _pendingReconnectSync = false;
          unawaited(performReconnectSync());
        }
      }
    }
  }

  Duration _timeoutForModule(SyncModule module) {
    switch (module) {
      case SyncModule.products:
        return const Duration(seconds: 120);
      case SyncModule.uploadTurno:
        return const Duration(minutes: 3);
      case SyncModule.uploadSales:
      case SyncModule.orders:
        return const Duration(seconds: 120);
      case SyncModule.layouts:
      case SyncModule.categories:
        return const Duration(seconds: 90);
      default:
        return const Duration(seconds: 60);
    }
  }

  bool _looksLikeConnectionError(Object e) {
    if (e is TimeoutException || e is SocketException) return true;
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('failed host lookup') ||
        s.contains('clientexception') ||
        s.contains('connection closed') ||
        s.contains('software caused connection abort');
  }
}

/// Tipos de eventos de sincronización automática
enum AutoSyncEventType {
  started,
  stopped,
  syncStarted,
  syncProgress, // Evento de progreso durante la sincronización
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
  final List<String>? skippedItems;
  final String? error;
  /// Paso actual (1-based) durante [syncProgress].
  final int? progressCurrent;
  /// Total de pasos del pase actual.
  final int? progressTotal;
  /// True si hubo avance parcial (algunos módulos OK, otros no).
  final bool isPartial;

  AutoSyncEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.duration,
    this.itemsSynced,
    this.skippedItems,
    this.error,
    this.progressCurrent,
    this.progressTotal,
    this.isPartial = false,
  });

  double? get progressFraction {
    final c = progressCurrent;
    final t = progressTotal;
    if (c == null || t == null || t <= 0) return null;
    return (c / t).clamp(0.0, 1.0);
  }

  @override
  String toString() {
    return 'AutoSyncEvent(type: $type, timestamp: $timestamp, message: $message, '
        'duration: $duration, itemsSynced: $itemsSynced, error: $error, '
        'progress: $progressCurrent/$progressTotal, partial: $isPartial)';
  }
}

/// Módulos seleccionables para sincronización manual/selectiva.
enum SyncModule {
  // Download
  license,
  storeConfig,
  credentials,
  paymentMethods,
  promotions,
  categories,
  products,
  layouts,
  orders,
  turno,
  egresos,
  // Upload
  uploadSales,
  uploadEgresos,
  uploadTurno,
  uploadShiftWorkers,
  uploadAdminOps,
}

extension SyncModuleX on SyncModule {
  bool get isDownload => switch (this) {
        SyncModule.uploadSales ||
        SyncModule.uploadEgresos ||
        SyncModule.uploadTurno ||
        SyncModule.uploadShiftWorkers ||
        SyncModule.uploadAdminOps =>
          false,
        _ => true,
      };

  bool get isUpload => !isDownload;

  /// Licencia no se puede deseleccionar en la UI de descarga.
  bool get isRequired => this == SyncModule.license;

  String get label => switch (this) {
        SyncModule.license => 'Licencia (obligatoria)',
        SyncModule.storeConfig => 'Configuración de tienda',
        SyncModule.credentials => 'Credenciales',
        SyncModule.paymentMethods => 'Métodos de pago',
        SyncModule.promotions => 'Promociones',
        SyncModule.categories => 'Categorías',
        SyncModule.products => 'Productos',
        SyncModule.layouts => 'Ubicaciones / layouts',
        SyncModule.orders => 'Órdenes',
        SyncModule.turno => 'Turno',
        SyncModule.egresos => 'Egresos',
        SyncModule.uploadSales => 'Ventas offline',
        SyncModule.uploadEgresos => 'Egresos offline',
        SyncModule.uploadTurno => 'Turno (apertura/cierre)',
        SyncModule.uploadShiftWorkers => 'Cambios de trabajadores',
        SyncModule.uploadAdminOps => 'Admin inventario/productos',
      };
}

class SyncResult {
  /// True solo si todos los módulos pedidos terminaron sin error.
  final bool success;
  /// True si se cortó el pipeline (red caída, timeout global, etc.).
  final bool interrupted;
  final List<String> syncedItems;
  final List<String> errors;
  final List<String> skippedItems;
  final Duration duration;
  final String? abortReason;

  const SyncResult({
    required this.success,
    required this.syncedItems,
    required this.errors,
    required this.duration,
    this.interrupted = false,
    this.skippedItems = const [],
    this.abortReason,
  });

  bool get isPartial =>
      syncedItems.isNotEmpty && (errors.isNotEmpty || interrupted);

  bool get hasProgress => syncedItems.isNotEmpty;

  String get userSummary => buildSummary(
        syncedItems: syncedItems,
        errors: errors,
        skippedItems: skippedItems,
        interrupted: interrupted,
        abortReason: abortReason,
      );

  static String buildSummary({
    required List<String> syncedItems,
    required List<String> errors,
    required List<String> skippedItems,
    required bool interrupted,
    String? abortReason,
  }) {
    final parts = <String>[];
    if (syncedItems.isNotEmpty) {
      parts.add('OK (${syncedItems.length}): ${syncedItems.join(", ")}');
    }
    if (errors.isNotEmpty) {
      parts.add('Errores (${errors.length}): ${errors.join("; ")}');
    }
    if (skippedItems.isNotEmpty) {
      parts.add(
        'Pendientes (${skippedItems.length}): ${skippedItems.join(", ")}',
      );
    }
    if (interrupted) {
      parts.insert(
        0,
        'Sincronización interrumpida'
            '${abortReason != null ? " ($abortReason)" : ""}',
      );
    } else if (errors.isEmpty && skippedItems.isEmpty) {
      return 'Sincronización completada: ${syncedItems.join(", ")}';
    } else if (syncedItems.isNotEmpty) {
      parts.insert(0, 'Sincronización parcial');
    } else {
      parts.insert(0, 'Sincronización fallida');
    }
    return parts.join(' · ');
  }
}
