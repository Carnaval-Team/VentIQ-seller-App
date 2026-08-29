import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_preferences_service.dart';
import '../services/auto_sync_service.dart';
import '../services/turno_service.dart';
import '../services/server_time_service.dart';
import '../services/inventory_service.dart';
import '../services/connectivity_service.dart';
import '../utils/uuid_generator.dart';
import '../utils/connection_error_handler.dart';
import '../models/inventory_product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/global_navigator.dart';
import '../widgets/connection_status_widget.dart';
import '../services/notification_service.dart';
import '../models/notification_model.dart';

class AperturaScreen extends StatefulWidget {
  const AperturaScreen({Key? key}) : super(key: key);

  @override
  State<AperturaScreen> createState() => _AperturaScreenState();
}

class _AperturaScreenState extends State<AperturaScreen>
    with RouteAware, WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _montoInicialController = TextEditingController();
  final _observacionesController = TextEditingController();
  final UserPreferencesService _userPrefs = UserPreferencesService();
  final NotificationService _notificationService = NotificationService();

  bool _isProcessing = false;
  bool _isLoadingPreviousShift = true;
  bool _manejaInventario = false; // Se cargará desde configuración de tienda
  bool _mostrarDebeHaberEnConteo = false;
  bool _autocompletarCantidadRealConteo = false;
  bool _isLoadingStoreConfig = true;
  String _userName = 'Cargando...';

  // Inventory management
  List<InventoryProduct> _inventoryProducts = [];
  Map<int, TextEditingController> _inventoryControllers = {};

  /// Stock real por producto (RPC batch / offline). Key = id_producto.
  Map<int, _StockRealProductoApertura> _stockRealByProduct = {};
  bool _isLoadingInventory = false;
  bool _inventorySet = false;

  // Conteos introducidos localmente (persistidos, igual que en cierre).
  Map<int, double> _pendingInventoryCounts = {};
  Timer? _inventorySaveTimer;
  final Set<int> _missingInventoryProductIds = {};

  // New state variables for conditional inventory
  bool _inventoryAlreadyDone = false;
  bool _checkingInventoryStatus = true;

  // Worker configuration for inventory control
  bool _trabajadorManejaAperturaControl =
      true; // Default to true (safe behavior)

  // Previous shift data
  double _previousShiftSales = 0.0;
  double _previousShiftCash = 0.0;
  // FASE 3 presentaciones: `num`, no `int`. Es la cantidad de productos del
  // turno anterior y puede ser fraccionada (0,5 kg); truncarla hacia 0 haria
  // que un turno con solo ventas al peso pareciera vacio.
  num _previousShiftProducts = 0;
  double _previousShiftTicketAvg = 0.0;

  /// Si ya hay turno abierto: mostrar detalles en lugar del formulario.
  bool _checkingExistingShift = true;
  Map<String, dynamic>? _existingOpenTurno;
  bool _existingTurnoIsOffline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExistingShift();
    _loadStoreConfig();
    _loadWorkerConfig(); // Load worker inventory control settings
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _inventorySaveTimer?.cancel();
    for (final c in _inventoryControllers.values) {
      c.dispose();
    }
    _montoInicialController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // Volviendo de otra pantalla (p.ej. Cierre) — revalidar turno abierto.
    unawaited(_checkExistingShift(forceRefresh: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkExistingShift(forceRefresh: true));
    }
  }

  /// Preguntar y recibir órdenes Carnaval creadas antes del turno
  Future<void> _promptReceiveCarnavalOrders() async {
    try {
      final isOffline = await _userPrefs.isOfflineModeEnabled();
      if (isOffline) {
        print('🔌 Modo offline: no se pueden recibir órdenes Carnaval');
        return;
      }

      // Asegurar notificaciones cargadas
      await _notificationService.loadNotifications();
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) return;

      final fechaTurno = DateTime.parse(
        turnoAbierto['fecha_apertura'] as String,
      );

      // Filtrar notificaciones de venta con data válida y no leídas
      final candidates =
          _notificationService.notifications.where((n) {
            if (n.tipo != NotificationType.venta || n.leida) return false;
            final data = n.data;
            if (data == null) return false;
            return data['operacion_id'] != null && data['orden_id'] != null;
          }).toList();

      if (candidates.isEmpty) {
        print('ℹ️ No hay notificaciones de venta pendientes');
        return;
      }

      final supabase = Supabase.instance.client;
      final List<NotificationModel> prevTurnNotifications = [];

      for (final notification in candidates) {
        final opId = notification.data!['operacion_id'];
        try {
          final opResponse =
              await supabase
                  .from('app_dat_operaciones')
                  .select('created_at')
                  .eq('id', opId)
                  .maybeSingle();

          final createdAtRaw = opResponse?['created_at'] as String?;
          if (createdAtRaw == null) continue;
          final fechaOperacion = DateTime.parse(createdAtRaw);
          if (!fechaOperacion.isBefore(fechaTurno)) continue;

          // Verificar que el último estado de la operación sea 1 (pendiente)
          final estadoResponse =
              await supabase
                  .from('app_dat_estado_operacion')
                  .select('estado')
                  .eq('id_operacion', opId)
                  .order('id', ascending: false)
                  .limit(1)
                  .maybeSingle();

          final ultimoEstado = estadoResponse?['estado'] as int?;
          if (ultimoEstado != null && ultimoEstado != 1) {
            print(
              '⏭️ Operación $opId tiene estado $ultimoEstado, no se puede recibir',
            );
            continue;
          }

          prevTurnNotifications.add(notification);
        } catch (e) {
          print('⚠️ No se pudo validar operación $opId: $e');
        }
      }

      if (prevTurnNotifications.isEmpty) {
        print('ℹ️ No hay operaciones anteriores al turno actual');
        return;
      }

      if (!mounted) return;
      final shouldReceive = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Órdenes Carnaval pendientes'),
              content: Text(
                'Hay ${prevTurnNotifications.length} órdenes de Carnaval creadas antes de abrir el turno. ¿Quieres recibirlas ahora?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Luego'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                  ),
                  child: const Text('Recibir'),
                ),
              ],
            ),
      );

      if (shouldReceive != true) return;

      int processed = 0;
      for (final notification in prevTurnNotifications) {
        final ok = await _receiveCarnavalOperation(notification);
        if (ok) processed++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Órdenes recibidas: $processed'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('❌ Error en prompt de órdenes Carnaval: $e');
    }
  }

  /// Recibir una operación Carnaval previa al turno (misma lógica que NotificationWidget)
  Future<bool> _receiveCarnavalOperation(NotificationModel notification) async {
    try {
      final data = notification.data;
      if (data == null) return false;
      final operacionId = data['operacion_id'];
      if (operacionId == null) return false;

      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) return false;
      final fechaTurno = DateTime.parse(
        turnoAbierto['fecha_apertura'] as String,
      );

      final supabase = Supabase.instance.client;
      final operacionResponse =
          await supabase
              .from('app_dat_operaciones')
              .select('created_at')
              .eq('id', operacionId)
              .maybeSingle();

      final fechaOperacionRaw = operacionResponse?['created_at'] as String?;
      if (fechaOperacionRaw == null) return false;
      final fechaOperacion = DateTime.parse(fechaOperacionRaw);

      if (!fechaOperacion.isBefore(fechaTurno)) {
        print('⏭️ Operación $operacionId es posterior al turno, se omite');
        return false;
      }

      // Verificar que el último estado de la operación sea 1 (pendiente)
      final estadoResponse =
          await supabase
              .from('app_dat_estado_operacion')
              .select('estado')
              .eq('id_operacion', operacionId)
              .order('id', ascending: false)
              .limit(1)
              .maybeSingle();

      final ultimoEstado = estadoResponse?['estado'] as int?;
      if (ultimoEstado != null && ultimoEstado != 1) {
        print(
          '⏭️ Operación $operacionId tiene estado $ultimoEstado, no se puede recibir',
        );
        return false;
      }

      await supabase
          .from('app_dat_operaciones')
          .update({'created_at': DateTime.now().toIso8601String()})
          .eq('id', operacionId);

      await _notificationService.markAsRead(notification.id);
      return true;
    } catch (e) {
      print('❌ Error recibiendo operación Carnaval: $e');
      return false;
    }
  }

  /// Check if inventory has already been done for the current warehouse in an active shift
  Future<void> _checkWarehouseInventoryStatus() async {
    try {
      setState(() {
        _checkingInventoryStatus = true;
      });

      // Si estamos offline / sin datos de servidor, no verificar en red.
      final useLocal = await _userPrefs.shouldUseLocalData();
      if (useLocal) {
        print(
          '🔌 Modo local - Omitiendo verificación de inventario en servidor',
        );
        setState(() {
          _inventoryAlreadyDone = false;
          _checkingInventoryStatus = false;
        });
        return;
      }

      final idAlmacen = await _userPrefs.getIdAlmacen();
      if (idAlmacen == null) {
        print('❌ No warehouse ID found');
        setState(() {
          _checkingInventoryStatus = false;
        });
        return;
      }

      final supabase = Supabase.instance.client;

      // 1. Get all active shifts (estado = 1) for the same warehouse
      // We need to join with app_dat_tpv to filter by id_almacen
      final activeShiftsResponse = await supabase
          .from('app_dat_caja_turno')
          .select('id, id_operacion_apertura, app_dat_tpv!inner(id_almacen)')
          .eq('estado', 1)
          .eq('app_dat_tpv.id_almacen', idAlmacen);

      final activeShifts = activeShiftsResponse as List<dynamic>;

      if (activeShifts.isEmpty) {
        print('ℹ️ No active shifts found for warehouse $idAlmacen');
        setState(() {
          _inventoryAlreadyDone = false;
          _checkingInventoryStatus = false;
        });
        return;
      }

      print(
        'ℹ️ Found ${activeShifts.length} active shifts for warehouse $idAlmacen',
      );

      // 2. Check if any of these shifts has an associated inventory control record
      bool inventoryFound = false;

      for (var shift in activeShifts) {
        final operationId = shift['id_operacion_apertura'];
        if (operationId != null) {
          final controlResponse = await supabase
              .from('app_dat_control_productos')
              .select('id')
              .eq('id_operacion', operationId)
              .limit(1);

          if (controlResponse != null && controlResponse.isNotEmpty) {
            inventoryFound = true;
            print('✅ Inventory control found for operation $operationId');
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _inventoryAlreadyDone = inventoryFound;
          _checkingInventoryStatus = false;
        });

        if (inventoryFound) {
          print(
            '✅ Inventory already done for this warehouse. Optional for this shift.',
          );
        } else {
          print('⚠️ Inventory required for this shift.');
        }
      }
    } catch (e) {
      print('❌ Error checking warehouse inventory status: $e');
      if (mounted) {
        setState(() {
          _checkingInventoryStatus = false;
          // Default to false (required) on error to be safe
          _inventoryAlreadyDone = false;
        });
      }
      // No mostrar snackbar de conexión: el conteo sigue disponible offline.
    }
  }

  Future<void> _checkExistingShift({bool forceRefresh = false}) async {
    try {
      if (mounted) {
        setState(() {
          _checkingExistingShift = true;
          if (forceRefresh) {
            _existingOpenTurno = null;
            _existingTurnoIsOffline = false;
          }
        });
      }

      // Preferir datos locales en offline / full-offline / sin red.
      // No disparar sync ni llamadas al servidor al abrir la vista: eso
      // muestra diálogos de "error de conexión" al vendedor aunque el
      // flujo offline esté pensado precisamente para operar sin red.
      final useLocal = await _userPrefs.shouldUseLocalData();
      final offlineOpen = await _userPrefs.getOfflineTurno();

      if (!useLocal && offlineOpen != null) {
        // Solo intentar sync si hay red real; si no, seguir con datos locales.
        final hasNetwork = await ConnectivityService().performImmediateCheck();
        if (hasNetwork) {
          await _triggerPendingAperturaSync();
        } else {
          print(
            '🔌 Apertura: sin red — omitiendo sync de turno pendiente '
            '(se usará cola local)',
          );
        }
      }

      Map<String, dynamic>? existing;
      var isOffline = false;

      if (useLocal) {
        final offlineOpenAfter = await _userPrefs.getOfflineTurno();
        existing = offlineOpenAfter ?? await TurnoService.getTurnoAbierto();
        isOffline =
            existing != null &&
            (_isOfflineTurno(existing) || offlineOpenAfter != null);
      } else {
        final turnoAbierto = await TurnoService.getTurnoAbierto();
        final offlineOpenAfterSync = await _userPrefs.getOfflineTurno();

        if (turnoAbierto != null && !_isOfflineTurno(turnoAbierto)) {
          existing = turnoAbierto;
          isOffline = false;
        } else if (offlineOpenAfterSync != null) {
          existing = offlineOpenAfterSync;
          isOffline = true;
        } else if (turnoAbierto != null) {
          existing = turnoAbierto;
          isOffline = _isOfflineTurno(turnoAbierto);
        }
      }

      // Resumen reciente de cierre online: no mostrar como turno abierto.
      if (existing != null) {
        final resumen = await _userPrefs.getTurnoResumenCache();
        if (resumen?['cerrado_online'] == true ||
            resumen?['cerrado_local'] == true) {
          final closedId = resumen!['id'] ?? resumen['server_id_turno'];
          final openId = existing['id'] ?? existing['server_id_turno'];
          if (closedId != null &&
              openId != null &&
              closedId.toString() == openId.toString()) {
            await _userPrefs.clearOfflineTurno();
            existing = null;
          }
        }
      }

      await _loadUserData();

      if (existing != null) {
        print(
          'ℹ️ Turno abierto detectado (${isOffline || useLocal ? 'OFFLINE/LOCAL' : 'ONLINE'}): ${existing['id']}',
        );
        if (mounted) {
          setState(() {
            _existingOpenTurno = existing;
            _existingTurnoIsOffline = isOffline || useLocal;
            _checkingExistingShift = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _existingOpenTurno = null;
          _existingTurnoIsOffline = false;
          _checkingExistingShift = false;
        });
      }
      _loadPreviousShiftSummary();
    } catch (e) {
      print('Error checking existing shift: $e');
      // Sin snackbar de conexión: en offline/local se continúa con cache.
      if (mounted) {
        setState(() {
          _existingOpenTurno = null;
          _existingTurnoIsOffline = false;
          _checkingExistingShift = false;
        });
      }
      _loadUserData();
      _loadPreviousShiftSummary();
    }
  }

  Future<void> _triggerPendingAperturaSync() async {
    try {
      await AutoSyncService().performReconnectSync();
    } catch (e) {
      print('⚠️ No se pudo iniciar la sincronización del turno: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final workerProfile = await _userPrefs.getWorkerProfile();

      setState(() {
        _userName = '${workerProfile['nombres']} ${workerProfile['apellidos']}';
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _userName = 'Usuario';
      });
    }
  }

  /// Cargar productos de inventario desde cache offline (sin categorías)
  Future<void> _loadInventoryProductsOffline() async {
    try {
      setState(() {
        _isLoadingInventory = true;
      });

      final products = await InventoryService.buildFromOfflineCache();
      for (var product in products) {
        if (!_inventoryControllers.containsKey(product.id)) {
          _inventoryControllers[product.id] = TextEditingController();
        }
      }

      setState(() {
        _inventoryProducts = products;
        _isLoadingInventory = false;
      });

      print('✅ ${products.length} productos offline cargados para inventario');
    } catch (e, stack) {
      print('❌ Error cargando productos offline: $e');
      print(stack);
      setState(() {
        _inventoryProducts = [];
        _isLoadingInventory = false;
      });
    }
  }

  // Inventory loading removed since inventory management is disabled

  Future<void> _loadPreviousShiftSummary() async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingPreviousShift = true;
        });
      }

      final useLocal = await _userPrefs.shouldUseLocalData();
      Map<String, dynamic>? resumenTurno;

      if (useLocal) {
        print('🔌 Modo local - Resumen turno anterior desde cache/cola...');
        resumenTurno = await _userPrefs.getPreviousShiftSummaryFromLocal();
      } else {
        print('🌐 Modo online - Resumen del último turno cerrado...');
        try {
          final online = await TurnoService.getResumenUltimoTurnoCerrado();
          if (online != null) {
            resumenTurno = _userPrefs.normalizePreviousShiftSummary(online);
            // Solo cachear turnos cerrados (no pisar un buen cierre local
            // con un KPI de turno abierto).
            await _userPrefs.saveTurnoResumenCache({
              ...resumenTurno,
              'cerrado_online': true,
              'status': UserPreferencesService.offlineTurnoStatusSynced,
            });
          }
        } catch (e) {
          print('⚠️ Resumen online falló ($e) — fallback local');
        }
        resumenTurno ??= await _userPrefs.getPreviousShiftSummaryFromLocal();
      }

      if (resumenTurno != null) {
        print('🔍 Debug - Resumen Turno Anterior: $resumenTurno');
        final sales =
            (resumenTurno['ventas_totales'] as num?)?.toDouble() ?? 0.0;
        final cashSuggested =
            (resumenTurno['efectivo_sugerido_apertura'] as num?)?.toDouble() ??
            (resumenTurno['efectivo_real'] as num?)?.toDouble() ??
            (resumenTurno['efectivo_final'] as num?)?.toDouble() ??
            (resumenTurno['efectivo_inicial'] as num?)?.toDouble() ??
            0.0;
        final products =
            (resumenTurno['productos_vendidos'] as num?) ?? 0;
        final ticket =
            (resumenTurno['ticket_promedio'] as num?)?.toDouble() ?? 0.0;

        if (mounted) {
          setState(() {
            _previousShiftSales = sales;
            // Referencia para nueva apertura = efectivo al cierre anterior.
            _previousShiftCash = cashSuggested;
            _previousShiftProducts = products;
            _previousShiftTicketAvg = ticket;
            _isLoadingPreviousShift = false;
          });
        }
      } else {
        print('ℹ️ No hay datos del turno anterior');
        if (mounted) {
          setState(() {
            _isLoadingPreviousShift = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error loading previous shift summary: $e');
      if (mounted) {
        setState(() {
          _isLoadingPreviousShift = false;
        });
      }
    }
  }

  /// Cargar configuración de tienda para verificar si maneja inventario
  Future<void> _loadStoreConfig() async {
    try {
      setState(() {
        _isLoadingStoreConfig = true;
      });

      final isOffline = await _userPrefs.shouldUseLocalData();
      final storeConfig = await _userPrefs.getStoreConfig();

      if (storeConfig != null) {
        final manejaInventario = storeConfig['maneja_inventario'] ?? false;
        final mostrarDebeHaber =
            storeConfig['mostrar_debe_haber_en_conteo_inventario'] ?? false;
        final autocompletarCantidad =
            storeConfig['autocompletar_cantidad_real_conteo'] ?? false;
        print(
          '🏪 Configuración de tienda cargada - Maneja inventario: $manejaInventario, '
          'Mostrar debe haber: $mostrarDebeHaber, '
          'Autocompletar cantidad real: $autocompletarCantidad',
        );

        if (mounted) {
          setState(() {
            _manejaInventario = manejaInventario;
            _mostrarDebeHaberEnConteo = mostrarDebeHaber;
            _autocompletarCantidadRealConteo = autocompletarCantidad;
            _isLoadingStoreConfig = false;
          });

          // If inventory is managed, load products immediately y verificar estado
          if (_manejaInventario) {
            if (isOffline) {
              _loadInventoryProductsOffline();
              setState(() {
                _checkingInventoryStatus = false;
              });
            } else {
              _loadInventoryProducts();
              _checkWarehouseInventoryStatus();
            }
          } else {
            setState(() {
              _checkingInventoryStatus = false;
            });
          }
        }
      } else {
        print('⚠️ No se encontró configuración de tienda');
        setState(() {
          _manejaInventario = false;
          _mostrarDebeHaberEnConteo = false;
          _autocompletarCantidadRealConteo = false;
          _isLoadingStoreConfig = false;
          _checkingInventoryStatus = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando configuración de tienda: $e');
      setState(() {
        _manejaInventario = false;
        _mostrarDebeHaberEnConteo = false;
        _autocompletarCantidadRealConteo = false;
        _isLoadingStoreConfig = false;
        _checkingInventoryStatus = false;
      });
    }
  }

  /// Cargar configuración del trabajador para control de inventario
  Future<void> _loadWorkerConfig() async {
    try {
      final manejaAperturaControl =
          await _userPrefs.loadWorkerManejaAperturaControl();

      if (mounted) {
        setState(() {
          _trabajadorManejaAperturaControl = manejaAperturaControl;
        });

        print(
          '👤 Trabajador maneja apertura control: $_trabajadorManejaAperturaControl',
        );
      }
    } catch (e) {
      print('❌ Error cargando configuración de trabajador: $e');
      // Mantener valor por defecto (true) en caso de error
    }
  }

  Future<void> _loadInventoryProducts() async {
    try {
      setState(() {
        _isLoadingInventory = true;
      });

      final userData = await _userPrefs.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró información de la tienda');
      }

      final idAlmacen = await _userPrefs.getIdAlmacen();
      print(
        '📦 Cargando productos de inventario para tienda: $idTienda almacen: $idAlmacen',
      );

      final response = await Supabase.instance.client.rpc(
        'fn_listar_inventario_productos_paged2',
        params: {
          'p_id_tienda': idTienda,
          'p_limite': 9999,
          'p_mostrar_sin_stock': false, // Excluir productos con stock 0
          'p_pagina': 1,
          'p_id_almacen': idAlmacen,
        },
      );

      if (response != null && response is List) {
        // Agrupar productos SOLO por id_producto (sin considerar ubicaciones ni presentaciones)
        final Map<int, InventoryProduct> productsByIdMap = {};

        for (var item in response) {
          if (!item['es_elaborado'] && !item['es_servicio']) {
            try {
              final product = InventoryProduct.fromSupabaseRpc(item);

              // Solo agregar el primer producto de cada ID (ignorar duplicados por presentación/ubicación)
              if (!productsByIdMap.containsKey(product.id)) {
                productsByIdMap[product.id] = product;
                print(
                  '📦 Producto agregado: ${product.nombreProducto} (ID: ${product.id})',
                );
              } else {
                print(
                  '⏭️ Omitiendo duplicado: ${product.nombreProducto} (ID: ${product.id})',
                );
              }
            } catch (e) {
              print('❌ Error procesando producto: $e');
            }
          }
        }

        // Crear lista consolidada (solo con stock) y controllers
        final products =
            productsByIdMap.values.where((p) => p.cantidadFinal > 0).toList();
        for (var product in products) {
          // Crear controller para cada producto único
          if (!_inventoryControllers.containsKey(product.id)) {
            _inventoryControllers[product.id] = TextEditingController();
          }
        }

        setState(() {
          _inventoryProducts = products;
          _isLoadingInventory = false;
        });

        print('✅ ${products.length} productos únicos de inventario cargados');
      } else {
        setState(() {
          _inventoryProducts = [];
          _isLoadingInventory = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando productos de inventario: $e');
      // En error de red / sin conexión: caer a cache offline sin alarmar al
      // vendedor (el modo offline existe precisamente para esto).
      if (ConnectionErrorHandler.isConnectionError(e) ||
          await _userPrefs.shouldUseLocalData()) {
        print('🔌 Fallback inventario offline tras error de red');
        await _loadInventoryProductsOffline();
        return;
      }

      if (mounted) {
        setState(() {
          _isLoadingInventory = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando inventario: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Obtener todas las ubicaciones de un producto con sus cantidades
  /// Carga los conteos de inventario previamente guardados localmente.
  Future<void> _loadInventoryCounts() async {
    final idTpv = await _userPrefs.getIdTpv();
    final saved = await _userPrefs.getInventoryCountApertura(idTpv);
    _pendingInventoryCounts = saved.map(
      (key, value) => MapEntry(int.tryParse(key) ?? 0, value),
    );
  }

  void _onInventoryCountChanged(int productId, String value) {
    final qty = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    _pendingInventoryCounts[productId] = qty;
    _scheduleSaveInventoryCounts();
  }

  void _scheduleSaveInventoryCounts() {
    _inventorySaveTimer?.cancel();
    _inventorySaveTimer = Timer(const Duration(milliseconds: 500), () async {
      final idTpv = await _userPrefs.getIdTpv();
      await _userPrefs.saveInventoryCountApertura(
        idTpv,
        _pendingInventoryCounts.map((k, v) => MapEntry(k.toString(), v)),
      );
    });
  }

  Future<void> _clearInventoryCounts() async {
    _inventorySaveTimer?.cancel();
    _pendingInventoryCounts.clear();
    final idTpv = await _userPrefs.getIdTpv();
    await _userPrefs.clearInventoryCountApertura(idTpv);
  }

  /// Mostrar modal de conteo de inventario
  Future<void> _showInventoryCountModal() async {
    if (_isLoadingInventory) return;

    setState(() {
      _isLoadingInventory = true;
    });

    try {
      // Cargar productos ANTES de mostrar el modal
      if (_inventoryProducts.isEmpty) {
        print('📦 Cargando productos antes de mostrar modal...');
        final isOffline = await _userPrefs.shouldUseLocalData();
        if (isOffline) {
          await _loadInventoryProductsOffline();
        } else {
          await _loadInventoryProducts();
        }
      }

      await _loadStockRealProductos();
      await _loadInventoryCounts();

      // Sin cantidad por defecto (igual que cierre); restaurar lo ya guardado.
      for (final product in _inventoryProducts) {
        final controller = _inventoryControllers[product.id];
        if (controller == null) continue;
        final savedQty = _pendingInventoryCounts[product.id];
        if (savedQty != null) {
          controller.text = _formatInventoryQty(savedQty);
        } else {
          controller.text = '';
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInventory = false;
        });
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: _buildInventoryCountModal(),
        );
      },
    );
  }

  /// Una sola llamada: stock_sistema + pendiente + en_camino + debe_haber.
  Future<void> _loadStockRealProductos() async {
    _stockRealByProduct = {};
    if (_inventoryProducts.isEmpty) return;

    try {
      final isOffline = await _userPrefs.shouldUseLocalData();
      if (isOffline) {
        await _loadStockRealProductosOffline();
        return;
      }

      final idTienda = await _userPrefs.getIdTienda();
      if (idTienda == null) return;

      final idAlmacen = await _userPrefs.getIdAlmacen();
      final productIds = _inventoryProducts.map((p) => p.id).toList();
      print(
        '📦 RPC fn_stock_real_productos_cierre '
        '(tienda=$idTienda, almacen=$idAlmacen, ${productIds.length} productos)...',
      );

      final response = await Supabase.instance.client.rpc(
        'fn_stock_real_productos_cierre',
        params: {
          'p_id_tienda': idTienda,
          'p_id_almacen': idAlmacen,
          'p_ids_producto': productIds,
        },
      );

      final map = <int, _StockRealProductoApertura>{};
      if (response is List) {
        for (final raw in response) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final id = (row['id_producto'] as num?)?.toInt();
          if (id == null) continue;
          map[id] = _StockRealProductoApertura(
            stockSistema: (row['stock_sistema'] as num?)?.toDouble() ?? 0,
            pendienteCarnaval:
                (row['pendiente_carnaval'] as num?)?.toDouble() ?? 0,
            enCamino: (row['en_camino'] as num?)?.toDouble() ?? 0,
            debeHaber: (row['debe_haber'] as num?)?.toDouble() ?? 0,
          );
        }
      }

      for (final p in _inventoryProducts) {
        map.putIfAbsent(
          p.id,
          () => const _StockRealProductoApertura(
            stockSistema: 0,
            pendienteCarnaval: 0,
            enCamino: 0,
            debeHaber: 0,
          ),
        );
      }

      _stockRealByProduct = map;
      print('✅ Stock real cargado para ${map.length} productos');
    } catch (e) {
      print('⚠️ Error cargando stock real batch: $e');
      _stockRealByProduct = {
        for (final p in _inventoryProducts)
          p.id: _StockRealProductoApertura(
            stockSistema: p.cantidadFinal,
            pendienteCarnaval: 0,
            enCamino: 0,
            debeHaber: p.cantidadFinal,
          ),
      };
    }
  }

  Future<void> _loadStockRealProductosOffline() async {
    // Usar cantidades ya resueltas por InventoryService.buildFromOfflineCache.
    _stockRealByProduct = {
      for (final p in _inventoryProducts)
        p.id: _StockRealProductoApertura(
          stockSistema: p.cantidadFinal,
          pendienteCarnaval: 0,
          enCamino: 0,
          debeHaber: p.cantidadFinal,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: Text(
          _existingOpenTurno != null ? 'Turno abierto' : 'Crear Apertura',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: ConnectionStatusWidget(showDetails: true, compact: true),
            ),
          ),
        ],
      ),
      body:
          _checkingExistingShift
              ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                ),
              )
              : _existingOpenTurno != null
              ? _buildExistingOpenTurnoView()
              : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lock_open,
                                  color: const Color(0xFF4A90E2),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Apertura de Caja',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              'Fecha actual:',
                              _formatDate(DateTime.now().toLocal()),
                            ),
                            _buildInfoRow(
                              'Hora actual:',
                              _formatTime(DateTime.now().toLocal()),
                            ),
                            _buildInfoRow('Usuario:', _userName),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      _buildPreviousShiftSummary(),

                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row(
                            // children: [
                            //   Icon(
                            //     Icons.checklist,
                            //     color: const Color(0xFF4A90E2),
                            //     size: 20,
                            //   ),
                            //   const SizedBox(width: 8),
                            //   const Text(
                            //     'Opciones de Apertura',
                            //     style: TextStyle(
                            //       fontSize: 16,
                            //       fontWeight: FontWeight.w600,
                            //       color: Color(0xFF1F2937),
                            //     ),
                            //   ),
                            // ],
                            //),
                            // const SizedBox(height: 16),
                            if (_isLoadingStoreConfig ||
                                _checkingInventoryStatus)
                              Container(
                                padding: const EdgeInsets.all(16),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF4A90E2),
                                    ),
                                  ),
                                ),
                              )
                            else if (_manejaInventario)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      _inventorySet
                                          ? Colors.green[50]
                                          : (_inventoryAlreadyDone
                                              ? Colors.blue[50]
                                              : Colors.orange[50]),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color:
                                        _inventorySet
                                            ? Colors.green[200]!
                                            : (_inventoryAlreadyDone
                                                ? Colors.blue[200]!
                                                : Colors.orange[200]!),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          _inventorySet
                                              ? Icons.check_circle
                                              : (_inventoryAlreadyDone
                                                  ? Icons.info_outline
                                                  : Icons.warning_amber),
                                          color:
                                              _inventorySet
                                                  ? Colors.green[700]
                                                  : (_inventoryAlreadyDone
                                                      ? Colors.blue[700]
                                                      : Colors.orange[700]),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _inventorySet
                                              ? 'Inventario Establecido'
                                              : (_inventoryAlreadyDone
                                                  ? 'Inventario Opcional'
                                                  : 'Inventario Requerido'),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                _inventorySet
                                                    ? Colors.green[700]
                                                    : (_inventoryAlreadyDone
                                                        ? Colors.blue[700]
                                                        : Colors.orange[700]),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _inventorySet
                                          ? 'Has establecido el inventario inicial del turno (${_inventoryProducts.where((p) => (_inventoryControllers[p.id]?.text ?? '').isNotEmpty).length} productos contados)'
                                          : (_inventoryAlreadyDone
                                              ? 'Ya se realizó un inventario en este almacén. Puedes realizar otro si lo deseas.'
                                              : 'Debes establecer el inventario inicial del turno anterior antes de continuar'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _showInventoryCountModal,
                                        icon: Icon(
                                          _inventorySet
                                              ? Icons.edit
                                              : Icons.inventory_2,
                                        ),
                                        label: Text(
                                          _inventorySet
                                              ? 'Editar Inventario'
                                              : 'Establecer Inventario',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              _inventorySet
                                                  ? Colors.green
                                                  : (_inventoryAlreadyDone
                                                      ? Colors.blue
                                                      : Colors.orange),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: const Color(0xFF4A90E2),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Opciones de Inventario',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4A90E2),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '1. ',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'Este turno no manejará inventario (solo ventas)',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          '2. ',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'La apertura se realizará sin conteo de productos',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Monto Inicial en Caja',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _montoInicialController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d+\.?\d{0,2}'),
                                ),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Monto inicial (\$)',
                                prefixIcon: const Icon(Icons.attach_money),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'El monto inicial es requerido';
                                }
                                final monto = double.tryParse(value);
                                if (monto == null || monto < 0) {
                                  return 'Ingrese un monto válido';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Inventory counting section removed since it's disabled
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Observaciones',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Opcional - Notas adicionales sobre la apertura',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _observacionesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText:
                                    'Ej: Apertura normal del día, billetes verificados...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessing ? null : _crearApertura,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90E2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child:
                              _isProcessing
                                  ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                  : const Text(
                                    'Crear Apertura',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }

  Widget _buildExistingOpenTurnoView() {
    final turno = _existingOpenTurno!;
    final isOffline = _existingTurnoIsOffline;
    final typeColor = isOffline ? Colors.orange : const Color(0xFF059669);
    final typeBg = isOffline ? Colors.orange.shade50 : const Color(0xFFECFDF5);
    final typeBorder =
        isOffline ? Colors.orange.shade200 : const Color(0xFFA7F3D0);

    final fechaRaw = turno['fecha_apertura']?.toString();
    DateTime? fecha;
    if (fechaRaw != null && fechaRaw.isNotEmpty) {
      fecha = DateTime.tryParse(fechaRaw)?.toLocal();
    }

    final efectivo = _parseMonto(
      turno['efectivo_inicial'] ?? turno['monto_inicial'],
    );
    final usuario =
        (turno['usuario']?.toString().trim().isNotEmpty == true)
            ? turno['usuario'].toString()
            : _userName;
    final observaciones = (turno['observaciones']?.toString() ?? '').trim();
    final idDisplay =
        (turno['server_id_turno'] ?? turno['id'] ?? turno['local_id'])
            ?.toString() ??
        '—';
    final localId = turno['local_id']?.toString();
    final idTpv = turno['id_tpv']?.toString() ?? '—';
    final idVendedor = turno['id_vendedor']?.toString() ?? '—';
    final manejaInventario = turno['maneja_inventario'] == true;
    final productos = turno['productos'];
    final productosCount = productos is List ? productos.length : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: typeBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: typeBorder),
            ),
            child: Row(
              children: [
                Icon(
                  isOffline ? Icons.cloud_off : Icons.cloud_done,
                  color: typeColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOffline ? 'Apertura OFFLINE' : 'Apertura ONLINE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: typeColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOffline
                            ? 'Turno creado sin conexión (pendiente de sincronizar o local).'
                            : 'Turno registrado en el servidor.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isOffline ? 'Offline' : 'Online',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.lock_open,
                      color: Color(0xFF4A90E2),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Detalles de la apertura',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildInfoRow('ID turno:', idDisplay),
                if (isOffline &&
                    localId != null &&
                    localId.isNotEmpty &&
                    localId != idDisplay)
                  _buildInfoRow('ID local:', localId),
                if (fecha != null) ...[
                  _buildInfoRow('Fecha:', _formatDate(fecha)),
                  _buildInfoRow('Hora:', _formatTime(fecha)),
                ] else
                  _buildInfoRow('Fecha apertura:', fechaRaw ?? '—'),
                _buildInfoRow('Usuario:', usuario),
                _buildInfoRow('TPV:', idTpv),
                _buildInfoRow('Vendedor:', idVendedor),
                _buildInfoRow(
                  'Efectivo inicial:',
                  '\$${efectivo.toStringAsFixed(2)}',
                ),
                _buildInfoRow(
                  'Inventario:',
                  manejaInventario
                      ? (productosCount > 0
                          ? 'Sí ($productosCount productos)'
                          : 'Sí')
                      : 'No',
                ),
                if (observaciones.isNotEmpty)
                  _buildInfoRow('Observaciones:', observaciones),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ya existe un turno abierto para este TPV. Debe cerrarlo antes de abrir uno nuevo.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Volver',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _parseMonto(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final localDate = date.toLocal();
    return '${localDate.day.toString().padLeft(2, '0')}/${localDate.month.toString().padLeft(2, '0')}/${localDate.year}';
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  bool _isOfflineTurno(Map<String, dynamic> turno) {
    // Marcador explícito de origen (ver `saveOfflineTurno` en
    // UserPreferencesService): una apertura hecha en línea y luego cacheada
    // para resiliencia offline queda marcada 'online' aunque estructuralmente
    // viva dentro de la misma cola de turnos offline. Sin este marcador,
    // campos como `local_id`/`tipo_operacion` (presentes en TODA entrada de
    // la cola, sin importar su origen real) hacían que una apertura online
    // se mostrara incorrectamente como "creada offline".
    final origen = turno['origen_apertura'];
    if (origen == 'online') return false;
    if (origen == 'offline') return true;

    // Sin marcador (entradas antiguas persistidas antes de este cambio):
    // usar `created_offline_at` como única señal de origen real offline.
    final turnoId = turno['id'];
    return turno['created_offline_at'] != null ||
        (turnoId is String && turno['server_id_turno'] == null);
  }

  String _formatInventoryCount(double quantity) {
    if (quantity.isNaN || quantity.isInfinite) return '0';
    if (quantity % 1 == 0) return quantity.toInt().toString();
    return quantity.toStringAsFixed(2);
  }

  // Inventory list method removed since inventory management is disabled

  Future<void> _crearApertura() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validar que si maneja inventario y NO se ha hecho ya, se haya establecido
    // Si ya se hizo (_inventoryAlreadyDone), es opcional, así que permitimos continuar sin _inventorySet
    // NUEVO: También es opcional si el trabajador tiene maneja_apertura_control = false
    if (_manejaInventario &&
        !_inventoryAlreadyDone &&
        !_inventorySet &&
        _trabajadorManejaAperturaControl) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes establecer el inventario inicial antes de continuar',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validar que todos los productos tengan cantidad ingresada
    if (_manejaInventario && _inventorySet) {
      int productosVacios = 0;
      for (var product in _inventoryProducts) {
        final controller = _inventoryControllers[product.id];
        final cantidadText = controller?.text ?? '';
        if (cantidadText.isEmpty) {
          productosVacios++;
        }
      }

      if (productosVacios > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Debes ingresar la cantidad para todos los productos ($productosVacios pendientes)',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    final montoInicial = double.parse(_montoInicialController.text);

    setState(() {
      _isProcessing = true;
    });

    try {
      final workerProfile = await _userPrefs.getWorkerProfile();
      final userData = await _userPrefs.getUserData();
      final sellerId = await _userPrefs.getIdSeller();
      final tpvId = await _userPrefs.getIdTpv();
      final userUuid = userData['userId'];

      print('🔍 Debug - Worker Profile: $workerProfile');
      print('🔍 Debug - TPV ID: $tpvId');
      print('🔍 Debug - Seller ID: $sellerId');
      print('🔍 Debug - User UUID: $userUuid');

      if (sellerId == null) {
        throw Exception('ID de vendedor no encontrado');
      }

      if (tpvId == null) {
        throw Exception('ID de TPV no encontrado');
      }

      if (userUuid == null) {
        throw Exception('UUID de usuario no encontrado');
      }

      // Preparar datos de inventario y generar observaciones si está habilitado
      List<Map<String, dynamic>>? productCounts;
      String observacionesInventario = '';

      if (_manejaInventario && _inventorySet) {
        productCounts = [];
        final List<String> excesos = [];
        final List<String> defectos = [];

        for (var product in _inventoryProducts) {
          final controller = _inventoryControllers[product.id];
          final cantidadText = controller?.text ?? '';

          if (cantidadText.isNotEmpty) {
            final cantidadContada = double.tryParse(cantidadText);
            if (cantidadContada != null && cantidadContada >= 0) {
              // Agregar producto con TODOS los campos requeridos por la función v3
              productCounts.add({
                'id_producto': product.id,
                'id_variante': product.idVariante,
                'id_ubicacion': product.idUbicacion,
                'id_presentacion': product.idPresentacion,
                'cantidad': cantidadContada,
              });

              // Diferencia vs debe-haber (oculto al usuario; va a observaciones)
              final cantidadSistema =
                  _stockRealByProduct[product.id]?.debeHaber ??
                  product.cantidadFinalReal;
              final diferencia = cantidadContada - cantidadSistema;

              if (diferencia > 0) {
                // Hay exceso
                excesos.add(
                  'Sobran ${diferencia.toStringAsFixed(2)} unidades de ${product.nombreProducto}',
                );
              } else if (diferencia < 0) {
                // Hay defecto
                defectos.add(
                  'Faltan ${diferencia.abs().toStringAsFixed(2)} unidades de ${product.nombreProducto}',
                );
              }
            }
          }
        }

        // Construir observaciones de inventario
        if (excesos.isNotEmpty || defectos.isNotEmpty) {
          final List<String> observaciones = [];

          if (defectos.isNotEmpty) {
            observaciones.add('FALTANTES:');
            observaciones.addAll(defectos);
          }

          if (excesos.isNotEmpty) {
            if (observaciones.isNotEmpty) observaciones.add('');
            observaciones.add('EXCESOS:');
            observaciones.addAll(excesos);
          }

          observacionesInventario = observaciones.join('\n');
          print('📋 Observaciones de inventario generadas:');
          print(observacionesInventario);
        }

        print('📦 Productos contados: ${productCounts.length}');
      }

      // Combinar observaciones del usuario con observaciones de inventario
      String observacionesFinales = _observacionesController.text.trim();
      if (observacionesInventario.isNotEmpty) {
        if (observacionesFinales.isNotEmpty) {
          observacionesFinales +=
              '\n\n--- INVENTARIO ---\n$observacionesInventario';
        } else {
          observacionesFinales = observacionesInventario;
        }
      }

      print('📦 Productos para apertura:');
      if (productCounts != null && productCounts.isNotEmpty) {
        for (var prod in productCounts) {
          print(
            '  - ID: ${prod['id_producto']}, Ubicación: ${prod['id_ubicacion']}, Variante: ${prod['id_variante']}, Presentación: ${prod['id_presentacion']}, Cantidad: ${prod['cantidad']}',
          );
        }
      }
      print('📊 Total productos: ${productCounts?.length ?? 0}');
      print('📝 Observaciones finales: $observacionesFinales');

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Creando apertura offline...');
        await _createOfflineApertura(
          efectivoInicial: double.parse(_montoInicialController.text),
          idTpv: tpvId,
          idVendedor: sellerId,
          usuario: userUuid,
          observaciones: observacionesFinales,
          productos: productCounts,
        );
      } else {
        print('🌐 Modo online - Creando apertura en Supabase...');
        // Usar el nuevo método del TurnoService
        final result = await TurnoService.registrarAperturaTurno(
          efectivoInicial: double.parse(_montoInicialController.text),
          idTpv: tpvId,
          idVendedor: sellerId,
          usuario: userUuid,
          manejaInventario: _manejaInventario,
          productos: productCounts,
          observaciones: observacionesFinales,
        );

        if (mounted) {
          if (result['success'] == true) {
            await _userPrefs.clearPreviousTurnoCaches();
            // Guardar turno abierto en cache offline para uso en modo sin conexión
            try {
              final turnoAbierto = await TurnoService.getTurnoAbierto();
              if (turnoAbierto != null && !_isOfflineTurno(turnoAbierto)) {
                await _userPrefs.saveOfflineTurno(turnoAbierto);
                print('💾 Turno online guardado en cache offline');
              } else {
                print('⚠️ No se pudo obtener turno online para cachear');
              }
              await _userPrefs.removePendingOperationsByType('apertura_turno');
            } catch (e) {
              print('⚠️ No se pudo cachear el turno online: $e');
            }

            // Preguntar si desea recibir órdenes Carnaval anteriores al turno
            await _promptReceiveCarnavalOrders();
            await _clearInventoryCounts();

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result['message'] ?? 'Apertura creada exitosamente',
                ),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true);
          } else {
            final errorKind = result['errorKind'];
            final isNetwork = errorKind == TurnoErrorKind.network;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isNetwork
                      ? 'Sin conexión al servidor. Intenta nuevamente cuando tengas conexión.'
                      : (result['message'] ?? 'Error desconocido'),
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error creando apertura: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Widget _buildPreviousShiftSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: const Color(0xFF4A90E2), size: 24),
              const SizedBox(width: 8),
              const Text(
                'Resumen Turno Anterior',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingPreviousShift)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                ),
              ),
            )
          else if (_previousShiftSales > 0 ||
              _previousShiftCash > 0 ||
              _previousShiftProducts > 0)
            Column(
              children: [
                _buildInfoRow(
                  'Ventas Totales:',
                  '\$${_previousShiftSales.toStringAsFixed(2)}',
                ),
                _buildInfoRow(
                  'Efectivo al cierre:',
                  '\$${_previousShiftCash.toStringAsFixed(2)}',
                ),
                _buildInfoRow(
                  'Productos Vendidos:',
                  _previousShiftProducts.toString(),
                ),
                if (_previousShiftTicketAvg > 0)
                  _buildInfoRow(
                    'Ticket Promedio:',
                    '\$${_previousShiftTicketAvg.toStringAsFixed(2)}',
                  ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'No hay datos del turno anterior',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Widget del modal de conteo de inventario (misma UX que el cierre).
  Widget _buildInventoryCountModal() {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return StatefulBuilder(
          builder: (modalContext, modalSetState) {
            final keyboardOpen =
                MediaQuery.viewInsetsOf(modalContext).bottom > 0;
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A90E2),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2, color: Colors.white),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Conteo de Inventario',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  if (!keyboardOpen)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.blue[50],
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _mostrarDebeHaberEnConteo
                                  ? 'Compara el "debe haber" e ingresa la cantidad real contada'
                                  : 'Ingresa la cantidad real contada de cada producto (sin rellenar por defecto)',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!keyboardOpen &&
                      !_isLoadingInventory &&
                      _inventoryProducts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: Colors.grey[50],
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          if (_mostrarDebeHaberEnConteo &&
                              _autocompletarCantidadRealConteo)
                            TextButton.icon(
                              onPressed: () {
                                for (final p in _inventoryProducts) {
                                  final debe =
                                      _stockRealByProduct[p.id]?.debeHaber ??
                                      p.cantidadFinalReal;
                                  _inventoryControllers[p.id]
                                      ?.text = _formatInventoryQty(debe);
                                  _pendingInventoryCounts[p.id] = debe;
                                }
                                _scheduleSaveInventoryCounts();
                                modalSetState(() {});
                              },
                              icon: const Icon(Icons.auto_fix_high, size: 18),
                              label: const Text("Rellenar con 'debe haber'"),
                            ),
                          TextButton.icon(
                            onPressed: () {
                              for (final p in _inventoryProducts) {
                                _inventoryControllers[p.id]?.text = '0';
                                _pendingInventoryCounts[p.id] = 0.0;
                              }
                              _scheduleSaveInventoryCounts();
                              modalSetState(() {});
                            },
                            icon: const Icon(Icons.exposure_zero, size: 18),
                            label: const Text('Todo en 0'),
                          ),
                        ],
                      ),
                    ),

                  Expanded(
                    child:
                        _isLoadingInventory
                            ? const Center(child: CircularProgressIndicator())
                            : _inventoryProducts.isEmpty
                            ? const Center(
                              child: Text('No hay productos de inventario'),
                            )
                            : ListView.builder(
                              controller: scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              itemCount: _inventoryProducts.length,
                              itemBuilder: (context, index) {
                                final product = _inventoryProducts[index];
                                final controller =
                                    _inventoryControllers[product.id]!;
                                final debeHaber =
                                    _stockRealByProduct[product.id]
                                        ?.debeHaber ??
                                    product.cantidadFinalReal;
                                final isMissing = _missingInventoryProductIds
                                    .contains(product.id);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color:
                                        isMissing
                                            ? Colors.red[50]
                                            : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          isMissing
                                              ? Colors.red[400]!
                                              : Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (isMissing) ...[
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          color: Colors.red[700],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.nombreProducto,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF1F2937),
                                              ),
                                            ),
                                            if (_mostrarDebeHaberEnConteo) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Debe haber: ${_formatInventoryQty(debeHaber)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue[700],
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      SizedBox(
                                        width: 100,
                                        child: TextFormField(
                                          controller: controller,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          textInputAction: TextInputAction.next,
                                          scrollPadding: const EdgeInsets.only(
                                            bottom: 120,
                                          ),
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d+\.?\d{0,2}'),
                                            ),
                                          ],
                                          decoration: InputDecoration(
                                            labelText: 'Real',
                                            hintText: '0',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                            isDense: true,
                                          ),
                                          style: const TextStyle(fontSize: 14),
                                          onChanged: (value) {
                                            _onInventoryCountChanged(
                                              product.id,
                                              value,
                                            );
                                            if (_missingInventoryProductIds
                                                .contains(product.id)) {
                                              _missingInventoryProductIds
                                                  .remove(product.id);
                                              modalSetState(() {});
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.grey[400]!),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              final missing =
                                  _inventoryProducts
                                      .where(
                                        (p) =>
                                            (_inventoryControllers[p.id]?.text
                                                    .trim()
                                                    .isEmpty ??
                                                true),
                                      )
                                      .map((p) => p.id)
                                      .toSet();
                              if (missing.isNotEmpty) {
                                modalSetState(() {
                                  _missingInventoryProductIds
                                    ..clear()
                                    ..addAll(missing);
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Faltan ${missing.length} productos por contar',
                                    ),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                                return;
                              }

                              _inventorySaveTimer?.cancel();
                              _scheduleSaveInventoryCounts();

                              setState(() {
                                _missingInventoryProductIds.clear();
                                _inventorySet = true;
                              });
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Inventario establecido: ${_inventoryProducts.length} productos contados',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A90E2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Guardar Inventario',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Crear apertura offline
  Future<void> _createOfflineApertura({
    required double efectivoInicial,
    required int idTpv,
    required int idVendedor,
    required String usuario,
    String? observaciones,
    List<Map<String, dynamic>>? productos,
  }) async {
    try {
      // client_uuid estable para idempotencia al sincronizar la apertura.
      final clientUuid = UuidGenerator.v4();
      final localId = UuidGenerator.v4();

      // Usar la hora corregida contra el servidor (ver ServerTimeService)
      // para que fecha_apertura no quede desfasada si el reloj del
      // dispositivo está mal ajustado.
      final nowServerCorrected = ServerTimeService().now();

      // Crear estructura de apertura offline
      final aperturaData = {
        'id': localId,
        'local_id': localId,
        'local_turno_id': localId,
        'client_uuid': clientUuid,
        'id_tpv': idTpv,
        'id_vendedor': idVendedor,
        'usuario': usuario,
        'tipo_operacion': 'apertura',
        'origen_apertura': 'offline',
        'efectivo_inicial': efectivoInicial,
        'fecha_apertura': nowServerCorrected.toIso8601String(),
        'observaciones': observaciones ?? '',
        'maneja_inventario': _manejaInventario,
        'productos': productos ?? [],
        'created_offline_at': nowServerCorrected.toIso8601String(),
      };

      // Cola multi-turno: crea entrada status=open (no sobrescribe cerrados).
      await _userPrefs.clearPreviousTurnoCaches();
      await _userPrefs.createOpenOfflineTurno(aperturaPayload: aperturaData);
      await _clearInventoryCounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Apertura creada offline. Se sincronizará cuando tengas conexión.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(true);
      }

      print('✅ Apertura offline creada: $localId');
    } catch (e, stackTrace) {
      print('❌ Error creando apertura offline: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creando apertura offline: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatInventoryQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

/// Totales de stock real por producto para el control de inventario (apertura).
class _StockRealProductoApertura {
  final double stockSistema;
  final double pendienteCarnaval;
  final double enCamino;
  final double debeHaber;

  const _StockRealProductoApertura({
    required this.stockSistema,
    required this.pendienteCarnaval,
    required this.enCamino,
    required this.debeHaber,
  });
}
