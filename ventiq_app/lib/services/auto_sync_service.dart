import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'category_service.dart';
import 'product_service.dart';
import 'payment_method_service.dart';
import 'turno_service.dart';
import 'reauthentication_service.dart';
import 'store_config_service.dart';
import 'shift_workers_service.dart';
import 'promotion_service.dart';
import 'product_detail_service.dart';
import 'offline_license_service.dart';
import 'admin_inventory_service.dart';
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

    // Si el modo offline está activo, no iniciar (prep usa syncModules).
    if (await _userPreferencesService.isOfflineModeEnabled()) {
      print('🔌 Modo offline activado - No se inicia sincronización automática');
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
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

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
      final result = await syncModules(modules);

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
    }
    if (_syncCount % 2 == 0) {
      modules.add(SyncModule.orders);
    }

    return modules;
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

  /// Asegura en servidor la apertura de UN turno de la cola offline.
  /// Devuelve el `server_id_turno` o null si falló.
  Future<int?> _ensureAperturaForQueueEntry(Map<String, dynamic> entry) async {
    final localId = entry['local_id']?.toString();
    if (localId == null) return null;

    final existingServer = entry['server_id_turno'];
    if (existingServer is int) return existingServer;
    if (existingServer is num) return existingServer.toInt();

    final aperturaRaw = entry['apertura'];
    final aperturaData =
        aperturaRaw is Map
            ? Map<String, dynamic>.from(aperturaRaw)
            : Map<String, dynamic>.from(entry);

    final idTpv =
        (entry['id_tpv'] ?? aperturaData['id_tpv']) as int? ??
        await _userPreferencesService.getIdTpv();
    final idVendedor =
        (entry['id_vendedor'] ?? aperturaData['id_vendedor']) as int? ??
        await _userPreferencesService.getIdSeller();

    if (idTpv == null || idVendedor == null) {
      print(
        '  ⚠️ No se pudo obtener TPV o vendedor para turno $localId',
      );
      return null;
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
        (aperturaData['efectivo_inicial'] ?? 0.0).toDouble();
    final usuario = (aperturaData['usuario'] ?? entry['usuario'] ?? '').toString();
    final manejaInventario =
        aperturaData['maneja_inventario'] as bool? ?? false;
    final observaciones = aperturaData['observaciones'] as String?;
    final productosRaw = aperturaData['productos'] as List<dynamic>? ?? [];
    final productos =
        productosRaw.map((item) => item as Map<String, dynamic>).toList();
    final fechaApertura =
        entry['fecha_apertura'] ?? aperturaData['fecha_apertura'];

    print('  🔄 Apertura cola turno $localId...');
    bool aperturaOk = false;
    int? serverId;

    try {
      final resp = await Supabase.instance.client.rpc(
        'fn_apertura_turno_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_efectivo_inicial': efectivoInicial,
          'p_id_tpv': idTpv,
          'p_id_vendedor': idVendedor,
          'p_usuario': usuario,
          'p_maneja_inventario': manejaInventario,
          'p_productos': productos,
          'p_observaciones': observaciones,
          'p_fecha_apertura': fechaApertura,
        },
      );
      if (resp is Map && resp['status'] == 'success') {
        aperturaOk = true;
        final rawId = resp['id_turno'];
        if (rawId is int) {
          serverId = rawId;
        } else if (rawId is num) {
          serverId = rawId.toInt();
        }
        print(
          '  ✅ Apertura $localId → id_turno=$serverId'
          '${resp['idempotent'] == true ? ' (idempotente)' : ''}',
        );
      }
    } catch (e) {
      print(
        '  ⚠️ fn_apertura_turno_offline no disponible ($e). Fallback.',
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
    }

    if (!aperturaOk) return null;

    if (serverId == null) {
      final online = await _getOnlineOpenShift(
        idTpv: idTpv,
        idVendedor: idVendedor,
      );
      final raw = online?['id'];
      if (raw is int) {
        serverId = raw;
      } else if (raw is num) {
        serverId = raw.toInt();
      }
      if (online != null && fechaApertura != null) {
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

    if (serverId != null) {
      await _userPreferencesService.setOfflineTurnoServerId(localId, serverId);
    }
    return serverId;
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

  /// Cierra en servidor un turno de la cola (closed_pending_sync).
  Future<bool> _syncCierreForQueueEntry(Map<String, dynamic> entry) async {
    if (entry['status'] !=
        UserPreferencesService.offlineTurnoStatusClosedPending) {
      return false;
    }

    final cierreRaw = entry['cierre'];
    if (cierreRaw is! Map) {
      print('  ⚠️ Turno ${entry['local_id']} closed sin payload de cierre');
      return false;
    }
    final cierreData = Map<String, dynamic>.from(cierreRaw);

    final idTpv =
        cierreData['id_tpv'] ??
        entry['id_tpv'] ??
        await _userPreferencesService.getIdTpv();
    final usuario = cierreData['usuario'] ?? entry['usuario'];
    final efectivoFinal = cierreData['efectivo_final'] ?? 0.0;
    final observaciones = cierreData['observaciones'] as String?;
    final productosRaw = cierreData['productos'] as List<dynamic>? ?? [];
    final productos =
        productosRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (idTpv == null || usuario == null) {
      print('  ⚠️ Cierre sin id_tpv/usuario; se omite');
      return false;
    }

    var clientUuid =
        entry['client_uuid_cierre']?.toString() ??
        cierreData['client_uuid']?.toString();
    if (clientUuid == null || clientUuid.isEmpty) {
      clientUuid = UuidGenerator.v4();
    }

    print('  🔄 Cierre cola turno ${entry['local_id']} (TPV $idTpv)...');
    bool cerrado = false;

    try {
      final resp = await Supabase.instance.client.rpc(
        'fn_cerrar_turno_offline',
        params: {
          'p_client_uuid': clientUuid,
          'p_id_tpv': idTpv,
          'p_efectivo_real': efectivoFinal,
          'p_usuario': usuario,
          'p_productos': productos,
          'p_observaciones': observaciones,
          'p_fecha_cierre':
              cierreData['fecha_cierre'] ?? entry['fecha_cierre'],
        },
      );
      cerrado = resp is Map && resp['status'] == 'success';
      if (cerrado) {
        print('  ✅ Cierre sincronizado (idempotent=${resp['idempotent']})');
      } else {
        print('  ⚠️ Cierre offline rechazado: $resp');
      }
    } catch (e) {
      print('  ⚠️ fn_cerrar_turno_offline no disponible ($e). Fallback.');
      try {
        final result = await TurnoService.cerrarTurnoDetailed(
          efectivoReal: (efectivoFinal as num).toDouble(),
          productos: productos,
          observaciones: observaciones,
        );
        cerrado = result.success;
      } catch (e2) {
        print('  ❌ Error en fallback de cierre offline: $e2');
      }
    }

    if (cerrado) {
      final localId = entry['local_id']?.toString();
      if (localId != null) {
        await _userPreferencesService.purgeFinalizedSyncedOrdersForTurno(
          localId,
        );
        await _userPreferencesService.markOfflineTurnoSynced(localId);
      }
      return true;
    }
    return false;
  }

  /// Replay ordenado: por cada turno pending → apertura → ventas → egresos → cierre.
  Future<Map<String, dynamic>> _syncOfflineTurnoQueue() async {
    await _hydrateTurnosFromLegacyPendingOps();

    final pending = await _userPreferencesService.getOfflineTurnosPendingSync();
    if (pending.isEmpty) {
      print('  📝 No hay turnos offline pendientes en cola');
      return {'turnos': 0, 'sales': 0, 'egresos': 0, 'cierres': 0};
    }

    print('  🔄 Replay de ${pending.length} turno(s) offline...');
    int salesTotal = 0;
    int egresosTotal = 0;
    int cierres = 0;
    int aperturas = 0;

    for (final entry in pending) {
      final localId = entry['local_id']?.toString() ?? '?';
      print('  ——— Turno $localId (${entry['status']}) ———');

      final serverId = await _ensureAperturaForQueueEntry(entry);
      if (serverId == null) {
        print('  ❌ No se pudo abrir turno $localId; se detiene el replay');
        break;
      }
      aperturas++;

      // Refrescar entry tras set server_id
      final refreshed =
          await _userPreferencesService.getOfflineTurnoByLocalId(localId) ??
          entry;

      final sales = await _syncOfflineSales(forTurno: refreshed);
      salesTotal += sales;

      final egresos = await _syncOfflineEgresos(
        forLocalTurnoId: localId,
        serverIdTurno: serverId,
      );
      egresosTotal += egresos;

      // Workers: remapear id_turno local → server antes de sync global.
      await _remapShiftWorkerOpsForTurno(localId, serverId);

      if (refreshed['status'] ==
          UserPreferencesService.offlineTurnoStatusClosedPending) {
        final ok = await _syncCierreForQueueEntry(refreshed);
        if (ok) {
          cierres++;
        } else {
          print('  ❌ Cierre falló para $localId; se detiene el replay');
          break;
        }
      }
    }

    // Sync workers restantes (ya remapeados).
    try {
      await ShiftWorkersService.syncPendingOperations();
    } catch (e) {
      print('  ⚠️ Error sync trabajadores tras cola: $e');
    }

    return {
      'turnos': aperturas,
      'sales': salesTotal,
      'egresos': egresosTotal,
      'cierres': cierres,
    };
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

    for (final op in aperturas) {
      final data = op['data'];
      if (data is! Map) continue;
      final map = Map<String, dynamic>.from(data);
      final cu = map['client_uuid']?.toString();
      if (cu != null && knownClients.contains(cu)) continue;

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
        'id_presentacion': inventoryMetadata['id_presentacion'],
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
        final paymentBreakdown = orderData['desglose_pagos'] as List<dynamic>?;
        if (paymentBreakdown != null && paymentBreakdown.isNotEmpty) {
          await _registerPaymentBreakdownFromOfflineData(
            operationId,
            paymentBreakdown,
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

  /// Sincroniza solo los módulos indicados.
  /// La licencia firmada se incluye siempre si hay alguno de descarga.
  Future<SyncResult> syncModules(
    Set<SyncModule> modules, {
    bool requireAuth = true,
  }) async {
    final startTime = DateTime.now();
    final syncedItems = <String>[];
    final errors = <String>[];
    final syncedData = <String, dynamic>{};

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
          message: 'Sincronización selectiva iniciada',
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
        SyncModule.turno,
        SyncModule.egresos,
        SyncModule.orders,
      ];
      final totalSteps = pipelineOrder.where(effective.contains).length;
      var stepIndex = 0;

      Future<void> run(
        SyncModule module,
        String label,
        Future<void> Function() action,
      ) async {
        if (!effective.contains(module)) return;
        stepIndex++;
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
          await action();
          syncedItems.add(label);
        } catch (e) {
          print('❌ Error en módulo $label: $e');
          errors.add('$label: $e');
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

      if (syncedData.isNotEmpty) {
        await _userPreferencesService.mergeOfflineData(syncedData);
      }

      final duration = DateTime.now().difference(startTime);
      final success = errors.isEmpty;

      _syncEventController.add(
        AutoSyncEvent(
          type:
              success
                  ? AutoSyncEventType.syncCompleted
                  : AutoSyncEventType.syncFailed,
          timestamp: DateTime.now(),
          message:
              success
                  ? 'Sincronización selectiva completada: ${syncedItems.join(", ")}'
                  : 'Sincronización selectiva con errores: ${errors.join("; ")}',
          duration: duration,
          itemsSynced: syncedItems,
          error: success ? null : errors.join('; '),
        ),
      );

      return SyncResult(
        success: success,
        syncedItems: syncedItems,
        errors: errors,
        duration: duration,
      );
    } catch (e) {
      final duration = DateTime.now().difference(startTime);
      errors.add(e.toString());
      _syncEventController.add(
        AutoSyncEvent(
          type: AutoSyncEventType.syncFailed,
          timestamp: DateTime.now(),
          message: 'Error en sincronización selectiva: $e',
          duration: duration,
          error: e.toString(),
        ),
      );
      return SyncResult(
        success: false,
        syncedItems: syncedItems,
        errors: errors,
        duration: duration,
      );
    }
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
  final String? error;
  /// Paso actual (1-based) durante [syncProgress].
  final int? progressCurrent;
  /// Total de pasos del pase actual.
  final int? progressTotal;

  AutoSyncEvent({
    required this.type,
    required this.timestamp,
    required this.message,
    this.duration,
    this.itemsSynced,
    this.error,
    this.progressCurrent,
    this.progressTotal,
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
        'progress: $progressCurrent/$progressTotal)';
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
  final bool success;
  final List<String> syncedItems;
  final List<String> errors;
  final Duration duration;

  const SyncResult({
    required this.success,
    required this.syncedItems,
    required this.errors,
    required this.duration,
  });
}
