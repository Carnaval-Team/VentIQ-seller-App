import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/inventory_product.dart';
import '../models/expense.dart';
import '../services/order_service.dart';
import '../services/notification_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/uuid_generator.dart';
import '../services/turno_service.dart';
import '../services/shift_workers_service.dart';
import '../services/printer_manager.dart';
import '../services/inventory_service.dart';
import '../services/auto_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/server_time_service.dart';
import '../widgets/cash_count_dialog.dart';

class CierreScreen extends StatefulWidget {
  const CierreScreen({Key? key}) : super(key: key);

  @override
  State<CierreScreen> createState() => _CierreScreenState();
}

class _CierreScreenState extends State<CierreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoFinalController = TextEditingController();
  final _observacionesController = TextEditingController();
  final OrderService _orderService = OrderService();
  final UserPreferencesService _userPrefs = UserPreferencesService();

  bool _isProcessing = false;
  bool _isLoadingData = true;
  bool _isLoadingInventory =
      false; // Cambiado a false para que cargue al abrir el modal
  bool _isLoadingExpenses = true;

  // Inventory data
  List<InventoryProduct> _inventoryProducts = [];
  Map<int, TextEditingController> _inventoryControllers = {};
  /// Stock real por producto (RPC batch / offline). Key = id_producto.
  Map<int, _StockRealProducto> _stockRealByProduct = {};
  bool _inventorySet = false;

  // Conteos de inventario introducidos localmente (persistidos).
  Map<int, double> _pendingInventoryCounts = {};
  Timer? _inventorySaveTimer;

  // Productos que aún no tienen cantidad ingresada (marcados al guardar).
  final Set<int> _missingInventoryProductIds = {};

  // New state variables for conditional inventory
  bool _isLastOpenShift = false;
  bool _checkingShiftStatus = true;

  // Expenses data
  List<Expense> _expenses = [];
  double _totalEgresos = 0.0; // Total de todos los egresos
  double _egresosEfectivo = 0.0; // Solo egresos en efectivo (no digitales)
  double _egresosTransferencias =
      0.0; // Solo egresos por transferencias/digitales

  // Data from RPC
  double _ventasTotales = 0.0;
  double _montoInicialCaja = 0.0;
  double _totalEfectivo = 0.0;
  double _totalTransferencias = 0.0;
  double _efectivoEsperado = 0.0;
  int _productosVendidos = 0;
  double _ticketPromedio = 0.0;
  double _porcentajeEfectivo = 0.0;
  double _porcentajeOtros = 0.0;

  // New fields from updated RPC
  int _operacionesTotales = 0;
  double _operacionesPorHora = 0.0;
  String _conciliacionEstado = '';
  double _efectivoRealAjustado = 0.0;
  double _diferenciaAjustada = 0.0;

  // Shift workers closed
  int _trabajadoresCerrados = 0;

  // Fecha/hora real de apertura del turno que se está cerrando (para mostrar
  // en el encabezado junto a la hora actual y evitar confusiones cuando el
  // turno lleva abierto varios días).
  DateTime? _fechaAperturaTurno;

  // Orders data
  int _ordenesAbiertas = 0;
  List<Order> _ordenesPendientes = [];
  String _userName = 'Cargando...';
  bool _manejaInventario =
      false; // Nueva variable para controlar si mostrar inventario
  bool _mostrarDebeHaberEnConteo = false;
  bool _autocompletarCantidadRealConteo = false;

  // Worker configuration for inventory control
  bool _trabajadorManejaAperturaControl =
      true; // Default to true (safe behavior)

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStoreConfiguration();
    _loadWorkerConfig(); // Load worker inventory control settings
    _loadDailySummary(); // también recalcula órdenes del turno
    _loadExpenses();
  }

  /// Check if this is the last open shift in the warehouse
  Future<void> _checkIfLastOpenShift() async {
    try {
      setState(() {
        _checkingShiftStatus = true;
      });

      final idAlmacen = await _userPrefs.getIdAlmacen();
      if (idAlmacen == null) {
        print('❌ No warehouse ID found for shift check');
        setState(() {
          _checkingShiftStatus = false;
        });
        return;
      }

      final supabase = Supabase.instance.client;

      // Get all active shifts (estado = 1) for the same warehouse
      final activeShiftsResponse = await supabase
          .from('app_dat_caja_turno')
          .select('id, app_dat_tpv!inner(id_almacen)')
          .eq('estado', 1)
          .eq('app_dat_tpv.id_almacen', idAlmacen);

      final activeShifts = activeShiftsResponse as List<dynamic>;

      // If only 1 shift is open, this is the last one
      final isLastShift = activeShifts.length == 1;

      if (mounted) {
        setState(() {
          _isLastOpenShift = isLastShift;
          _checkingShiftStatus = false;
        });

        if (isLastShift) {
          print(
            '⚠️ This is the LAST open shift in warehouse $idAlmacen. Inventory is MANDATORY.',
          );
        } else {
          print(
            'ℹ️ There are ${activeShifts.length} open shifts in warehouse $idAlmacen. Inventory is OPTIONAL.',
          );
        }
      }
    } catch (e) {
      print('❌ Error checking shift status: $e');
      if (mounted) {
        setState(() {
          _checkingShiftStatus = false;
          // Default to mandatory (safe)
          _isLastOpenShift = true;
        });
      }
    }
  }

  /// Cargar productos de inventario desde cache offline (sin categorías)
  Future<void> _loadInventoryProductsOffline() async {
    try {
      final products = await InventoryService.buildFromOfflineCache();
      for (var product in products) {
        if (!_inventoryControllers.containsKey(product.id)) {
          _inventoryControllers[product.id] = TextEditingController();
        }
      }

      setState(() {
        _inventoryProducts = products;
      });

      print('✅ ${products.length} productos offline cargados para inventario');
    } catch (e, stack) {
      print('❌ Error cargando productos offline: $e');
      print(stack);
      setState(() {
        _inventoryProducts = [];
      });
    }
  }

  Future<void> _loadStoreConfiguration() async {
    try {
      final isOffline = await _userPrefs.shouldUseLocalData();
      final storeConfig = await _userPrefs.getStoreConfig();

      if (storeConfig != null) {
        final manejaInventario = storeConfig['maneja_inventario'] ?? false;
        final mostrarDebeHaber =
            storeConfig['mostrar_debe_haber_en_conteo_inventario'] ?? false;
        final autocompletarCantidad =
            storeConfig['autocompletar_cantidad_real_conteo'] ?? false;
        print(
          '🏪 Configuración de tienda cargada - Maneja inventario 2: $manejaInventario, '
          'Mostrar debe haber: $mostrarDebeHaber, '
          'Autocompletar cantidad real: $autocompletarCantidad',
        );

        if (mounted) {
          setState(() {
            _manejaInventario = manejaInventario;
            _mostrarDebeHaberEnConteo = mostrarDebeHaber;
            _autocompletarCantidadRealConteo = autocompletarCantidad;
            print(
              '✅ setState ejecutado - _manejaInventario ahora es: $_manejaInventario',
            );
          });

          // If inventory is managed, check if this is the last open shift (solo online)
          if (_manejaInventario) {
            if (!isOffline) {
              _checkIfLastOpenShift();
            } else {
              setState(() {
                _checkingShiftStatus = false;
              });
            }
          } else {
            setState(() {
              _checkingShiftStatus = false;
            });
          }
        } else {
          print('⚠️ Widget no montado, no se puede ejecutar setState');
        }
      } else {
        print('⚠️ No se encontró configuración de tienda');
        if (mounted) {
          setState(() {
            _manejaInventario = false;
            _mostrarDebeHaberEnConteo = false;
            _autocompletarCantidadRealConteo = false;
            _checkingShiftStatus = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando configuración de tienda: $e');
      if (mounted) {
        setState(() {
          _manejaInventario = false;
          _mostrarDebeHaberEnConteo = false;
          _autocompletarCantidadRealConteo = false;
          _checkingShiftStatus = false;
        });
      }
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
          '👤 Trabajador maneja apertura control (cierre): $_trabajadorManejaAperturaControl',
        );
      }
    } catch (e) {
      print('❌ Error cargando configuración de trabajador: $e');
      // Mantener valor por defecto (true) en caso de error
    }
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Calcula totales de cierre a partir de las órdenes locales. Soporta pagos
  /// mixtos y usa las mismas claves que devuelve listar_ordenes.
  ({double ventas, double efectivo, double transferencia, int productos, int operaciones})
  _calculateClosureTotalsFromOrders(List<Order> orders) {
    double ventas = 0.0;
    double efectivo = 0.0;
    double transferencia = 0.0;
    int productos = 0;
    int operaciones = 0;

    for (final order in orders) {
      final isVendida =
          order.status == OrderStatus.completada ||
          order.status == OrderStatus.pagoConfirmado ||
          order.status == OrderStatus.pendienteDeSincronizacion ||
          order.status == OrderStatus.enviada;

      if (!isVendida) continue;

      operaciones++;
      ventas += order.total;
      productos += order.items.fold<int>(
        0,
        (sum, item) => sum + item.cantidad.toInt(),
      );

      double efectivoOrden = 0.0;
      double transferenciaOrden = 0.0;
      final pagos = order.pagos;

      if (pagos != null && pagos.isNotEmpty) {
        for (final pago in pagos) {
          if (pago is! Map) continue;
          final monto = _parseDouble(
            pago['monto'] ??
                pago['monto_pago'] ??
                pago['monto_total'] ??
                pago['monto_entrega'] ??
                pago['total'],
          );
          final esEfectivo =
              pago['es_efectivo'] == true ||
              pago['medio_pago_es_efectivo'] == true ||
              pago['id_medio_pago'] == 1 ||
              pago['medio_pago_id'] == 1;
          final esDigital =
              pago['es_digital'] == true ||
              pago['medio_pago_es_digital'] == true;

          if (esEfectivo) {
            efectivoOrden += monto;
          } else if (esDigital) {
            transferenciaOrden += monto;
          } else {
            transferenciaOrden += monto;
          }
        }
      }

      // Fallback solo para órdenes offline sin pagos desglosados.
      if (order.isOfflineOrder &&
          efectivoOrden + transferenciaOrden == 0 &&
          order.total > 0) {
        final method = (order.paymentMethod ?? '').toLowerCase();
        if (method.contains('efectivo') || method.contains('cash')) {
          efectivoOrden = order.total;
        } else {
          transferenciaOrden = order.total;
        }
      }

      efectivo += efectivoOrden;
      transferencia += transferenciaOrden;
    }

    return (
      ventas: ventas,
      efectivo: efectivo,
      transferencia: transferencia,
      productos: productos,
      operaciones: operaciones,
    );
  }

  Future<void> _loadDailySummary() async {
    try {
      setState(() {
        _isLoadingData = true;
      });

      final useLocal = await _userPrefs.shouldUseLocalData();

      // Turno abierto obligatorio para el cierre.
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        print('⚠️ No open shift found');
        setState(() {
          _isLoadingData = false;
        });
        if (mounted) {
          _showNoOpenShiftAlert();
        }
        return;
      }

      _fechaAperturaTurno = DateTime.tryParse(
        turnoAbierto['fecha_apertura']?.toString() ?? '',
      )?.toLocal();

      // Cargar TODAS las órdenes de ESTE turno combinando cache offline +
      // pendientes de sincronización + (si hay conexión real) datos frescos
      // del servidor. Así, si se pasó a modo offline habiendo ya ventas
      // hechas en línea, esas ventas se siguen sumando en el cierre. La
      // sincronización de pendientes hacia el servidor sigue siendo
      // responsabilidad independiente de auto_sync_service.
      await _orderService.loadOrdersForOpenTurnoUnified();

      if (useLocal) {
        print('🔌 Modo local - Resumen del turno abierto...');
        await _loadDailySummaryOffline();
      } else {
        print('🌐 Modo online - Resumen del turno abierto...');
        await _loadDailySummaryOnline(turnoAbierto);
      }

      await _calcularDatosCierre();
    } catch (e) {
      print('❌ Error loading daily summary: $e');
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  Future<void> _loadDailySummaryOnline(Map<String, dynamic> turnoAbierto) async {
    try {
      // Preferir resumen por id de turno (no el diario, que mezcla turnos).
      final idRaw = turnoAbierto['id'] ?? turnoAbierto['server_id_turno'];
      final idTurno =
          idRaw is int
              ? idRaw
              : (idRaw is num ? idRaw.toInt() : int.tryParse('$idRaw'));

      Map<String, dynamic>? data;
      if (idTurno != null) {
        print('🧪 Loading summary with fn_resumen_turno_por_id ($idTurno)');
        data = await TurnoService.getResumenTurnoPorId(idTurno);
      }
      data ??= await TurnoService.getResumenTurnoKPI();

      if (data == null) {
        // Último recurso: RPC diario (puede incluir más de un turno del día).
        final idTpv = await _userPrefs.getIdTpv();
        final userID = await _userPrefs.getUserId();
        if (idTpv != null) {
          print(
            '⚠️ Fallback fn_resumen_diario_cierre - TPV: $idTpv (puede mezclar turnos)',
          );
          final resumenCierreResponse = await Supabase.instance.client.rpc(
            'fn_resumen_diario_cierre',
            params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
          );
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            data = Map<String, dynamic>.from(
              resumenCierreResponse[0] as Map,
            );
          } else if (resumenCierreResponse is Map) {
            data = Map<String, dynamic>.from(resumenCierreResponse);
          }
        }
      }

      if (data == null) {
        setState(() {
          _isLoadingData = false;
        });
        return;
      }

      setState(() {
        _montoInicialCaja = (data!['efectivo_inicial'] ?? 0.0).toDouble();
        _ventasTotales = (data['ventas_totales'] ?? 0.0).toDouble();
        _productosVendidos = (data['productos_vendidos'] ?? 0).toInt();
        _ticketPromedio = (data['ticket_promedio'] ?? 0.0).toDouble();
        _operacionesTotales = (data['operaciones_totales'] ?? 0).toInt();
        _operacionesPorHora =
            (data['operaciones_por_hora'] ?? 0.0).toDouble();
        _totalEfectivo =
            (data['total_efectivo'] ?? data['efectivo_real'] ?? 0.0)
                .toDouble();
        _totalTransferencias =
            (data['total_transferencias'] ??
                    (_ventasTotales - _totalEfectivo))
                .toDouble();
        _porcentajeEfectivo =
            (data['porcentaje_efectivo'] ?? 70.0).toDouble();
        _porcentajeOtros = (data['porcentaje_otros'] ?? 30.0).toDouble();
        _efectivoEsperado =
            (data['efectivo_esperado'] ??
                    _montoInicialCaja + _totalEfectivo)
                .toDouble();
        _conciliacionEstado =
            data['conciliacion_estado']?.toString() ?? 'Pendiente';
        _efectivoRealAjustado =
            (data['efectivo_real_ajustado'] ?? _efectivoEsperado)
                .toDouble();
        _diferenciaAjustada =
            (data['diferencia_ajustada'] ?? 0.0).toDouble();
        _isLoadingData = false;
      });
    } catch (e) {
      print('❌ Error loading online daily summary: $e');
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  Future<void> _loadDailySummaryOffline() async {
    try {
      print('📱 Cargando resumen de cierre desde cache offline...');

      // Obtener resumen de cierre actualizado con órdenes offline
      final resumenCierre =
          await _userPrefs.getResumenCierreWithOfflineOrders();

      if (resumenCierre != null) {
        print('✅ Resumen de cierre cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenCierre.keys.toList()}');

        setState(() {
          // Mapear campos desde el cache del resumen de cierre
          _montoInicialCaja =
              (resumenCierre['efectivo_inicial'] ??
                      resumenCierre['monto_inicial_caja'] ??
                      0.0)
                  .toDouble();
          _ventasTotales =
              (resumenCierre['total_ventas'] ??
                      resumenCierre['ventas_totales'] ??
                      0.0)
                  .toDouble();
          _productosVendidos =
              (resumenCierre['productos_vendidos'] ?? 0).toInt();
          _ticketPromedio =
              (resumenCierre['ticket_promedio'] ?? 0.0).toDouble();

          // Campos específicos del resumen de cierre
          _operacionesTotales =
              (resumenCierre['operaciones_totales'] ?? 0).toInt();
          _operacionesPorHora =
              (resumenCierre['operaciones_por_hora'] ?? 0.0).toDouble();
          _totalEfectivo =
              (resumenCierre['total_efectivo'] ??
                      resumenCierre['efectivo_real'] ??
                      _ventasTotales * 0.7)
                  .toDouble();
          _totalTransferencias =
              (resumenCierre['total_transferencias'] ??
                      _ventasTotales - _totalEfectivo)
                  .toDouble();
          _porcentajeEfectivo =
              (resumenCierre['porcentaje_efectivo'] ?? 70.0).toDouble();
          _porcentajeOtros =
              (resumenCierre['porcentaje_otros'] ?? 30.0).toDouble();
          _efectivoEsperado =
              (resumenCierre['efectivo_esperado'] ??
                      _montoInicialCaja + _totalEfectivo)
                  .toDouble();
          _conciliacionEstado =
              resumenCierre['conciliacion_estado'] ?? 'Pendiente';
          _efectivoRealAjustado =
              (resumenCierre['efectivo_real_ajustado'] ?? _efectivoEsperado)
                  .toDouble();
          _diferenciaAjustada =
              (resumenCierre['diferencia_ajustada'] ?? 0.0).toDouble();
          // _manejaInventario = resumenCierre['maneja_inventario'] ?? false; // Comentado: se usa valor de configuración

          _isLoadingData = false;
        });

        print('💰 Datos cargados desde cache offline (con órdenes offline):');
        print('  - Monto inicial: $_montoInicialCaja');
        print('  - Ventas totales: $_ventasTotales');
        print('  - Productos vendidos: $_productosVendidos');
        print('  - Ticket promedio: $_ticketPromedio');
        print('  - Total efectivo: $_totalEfectivo');
        print('  - Total transferencias: $_totalTransferencias');

        // Mostrar información de órdenes offline si las hay
        if (resumenCierre['ordenes_offline'] != null &&
            resumenCierre['ordenes_offline'] > 0) {
          print('📱 Órdenes offline incluidas:');
          print('  - Órdenes offline: ${resumenCierre['ordenes_offline']}');
          print('  - Ventas offline: \$${resumenCierre['ventas_offline']}');
        }
      } else {
        // Fallback: intentar cargar desde resumen de turno si no hay resumen de cierre
        print('⚠️ No hay resumen de cierre - intentando resumen de turno...');
        final resumenTurno = await _userPrefs.getTurnoResumenCache();

        if (resumenTurno != null) {
          print('✅ Usando resumen de turno como fallback');
          setState(() {
            _montoInicialCaja =
                (resumenTurno['efectivo_inicial'] ?? 0.0).toDouble();
            _ventasTotales = (resumenTurno['ventas_totales'] ?? 0.0).toDouble();
            _productosVendidos =
                (resumenTurno['productos_vendidos'] ?? 0).toInt();
            _ticketPromedio =
                (resumenTurno['ticket_promedio'] ?? 0.0).toDouble();

            // Estimaciones para campos faltantes
            _operacionesTotales = 0;
            _operacionesPorHora = 0.0;
            _totalEfectivo = _ventasTotales * 0.7;
            _totalTransferencias = _ventasTotales * 0.3;
            _porcentajeEfectivo = 70.0;
            _porcentajeOtros = 30.0;
            _efectivoEsperado = _montoInicialCaja + _totalEfectivo;
            _conciliacionEstado = 'Pendiente (Fallback)';
            _efectivoRealAjustado = _efectivoEsperado;
            _diferenciaAjustada = 0.0;
            // _manejaInventario = false; // Comentado: se usa valor de configuración

            _isLoadingData = false;
          });
        } else {
          print('⚠️ No hay cache disponible - usando valores por defecto');
          setState(() {
            // Valores por defecto cuando no hay cache
            _montoInicialCaja = 500.0;
            _ventasTotales = 0.0;
            _productosVendidos = 0;
            _ticketPromedio = 0.0;
            _operacionesTotales = 0;
            _operacionesPorHora = 0.0;
            _totalEfectivo = 0.0;
            _totalTransferencias = 0.0;
            _porcentajeEfectivo = 0.0;
            _porcentajeOtros = 0.0;
            _efectivoEsperado = 500.0;
            _conciliacionEstado = 'Sin datos';
            _efectivoRealAjustado = 500.0;
            _diferenciaAjustada = 0.0;
            // _manejaInventario = false; // Comentado: se usa valor de configuración

            _isLoadingData = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando resumen offline: $e');
      setState(() {
        _montoInicialCaja = 500.0; // Fallback por defecto
        _ventasTotales = 0.0;
        _isLoadingData = false;
      });
    }
  }

  void _showNoOpenShiftAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('No hay turno abierto'),
            content: const Text(
              'No se puede crear un cierre sin un turno abierto',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
    );
  }

  @override
  void dispose() {
    _montoFinalController.dispose();
    _observacionesController.dispose();
    _inventorySaveTimer?.cancel();
    // Dispose inventory controllers
    for (var controller in _inventoryControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInventoryProducts() async {
    // Offline / full-offline: cache local (evitar RPCs).
    final isOffline = await _userPrefs.shouldUseLocalData();
    if (isOffline) {
      print('🔌 Modo offline - cargando inventario desde cache');
      return _loadInventoryProductsOffline();
    }

    if (!_manejaInventario) {
      print('⏭️ Tienda no maneja inventario - Omitiendo carga');
      return;
    }

    try {
      print('📦 Cargando productos de inventario para cierre...');

      final idTienda = await _userPrefs.getIdTienda();
      print('🏪 ID Tienda obtenido: $idTienda');
      if (idTienda == null) {
        throw Exception('ID de tienda no encontrado');
      }
      final idAlmacen = await _userPrefs.getIdAlmacen();

      print(
        '🔄 Llamando a fn_listar_inventario_productos_paged... ${idAlmacen}',
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
      print('✅ Respuesta recibida: ${response?.length ?? 0} items');

      if (response != null && response is List) {
        // Agrupar productos SOLO por id_producto (sin considerar ubicaciones ni presentaciones)
        final Map<int, InventoryProduct> productsByIdMap = {};

        for (var item in response) {
          // print(item);
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
            productsByIdMap.values
                .where((p) => p.cantidadFinal > 0)
                .toList();
        for (var product in products) {
          // Crear controller para cada producto único
          if (!_inventoryControllers.containsKey(product.id)) {
            _inventoryControllers[product.id] = TextEditingController();
          }
        }

        setState(() {
          _inventoryProducts = products;
        });

        print('✅ ${products.length} productos únicos de inventario cargados');
      } else {
        setState(() {
          _inventoryProducts = [];
        });
      }
    } catch (e) {
      print('❌ Error cargando productos de inventario: $e');
      rethrow;
    }
  }

  /// Mostrar modal de control de inventario
  Future<void> _showInventoryCountModal() async {
    if (_isLoadingInventory) return;

    print('🔍 Estado antes de cargar:');
    print('  - _inventoryProducts.isEmpty: ${_inventoryProducts.isEmpty}');
    print('  - _inventoryProducts.length: ${_inventoryProducts.length}');

    setState(() {
      _isLoadingInventory = true;
    });

    try {
      // Cargar productos ANTES de mostrar el modal
      if (_inventoryProducts.isEmpty) {
        print('📦 Cargando productos antes de mostrar modal...');
        await _loadInventoryProducts();
      } else {
        print('⏭️ Productos ya cargados');
      }

      await _loadStockRealProductos();
      await _loadInventoryCounts();

      // Restaurar conteos previos o dejar vacío para marcarlos como pendientes.
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
  /// Offline: suma cantidades del cache local.
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
          // Solo el almacén del vendedor (no toda la tienda).
          'p_id_almacen': idAlmacen,
          'p_ids_producto': productIds,
        },
      );

      final map = <int, _StockRealProducto>{};
      if (response is List) {
        for (final raw in response) {
          if (raw is! Map) continue;
          final row = Map<String, dynamic>.from(raw);
          final id = (row['id_producto'] as num?)?.toInt();
          if (id == null) continue;
          map[id] = _StockRealProducto(
            stockSistema: (row['stock_sistema'] as num?)?.toDouble() ?? 0,
            pendienteCarnaval:
                (row['pendiente_carnaval'] as num?)?.toDouble() ?? 0,
            enCamino: (row['en_camino'] as num?)?.toDouble() ?? 0,
            debeHaber: (row['debe_haber'] as num?)?.toDouble() ?? 0,
          );
        }
      }

      // Completar productos sin fila (0).
      for (final p in _inventoryProducts) {
        map.putIfAbsent(
          p.id,
          () => const _StockRealProducto(
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
          p.id: _StockRealProducto(
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
        p.id: _StockRealProducto(
          stockSistema: p.cantidadFinal,
          pendienteCarnaval: 0,
          enCamino: 0,
          debeHaber: p.cantidadFinal,
        ),
    };
  }

  /// Carga los conteos de inventario previamente guardados localmente.
  Future<void> _loadInventoryCounts() async {
    final idTpv = await _userPrefs.getIdTpv();
    final saved = await _userPrefs.getInventoryCountCierre(idTpv);
    _pendingInventoryCounts = saved.map(
      (key, value) => MapEntry(int.tryParse(key) ?? 0, value),
    );
  }

  /// Guarda los conteos localmente con un pequeño retardo para no saturar
  /// SharedPreferences mientras el usuario escribe.
  void _onInventoryCountChanged(int productId, String value) {
    final qty = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
    _pendingInventoryCounts[productId] = qty;
    _scheduleSaveInventoryCounts();
  }

  void _scheduleSaveInventoryCounts() {
    _inventorySaveTimer?.cancel();
    _inventorySaveTimer = Timer(const Duration(milliseconds: 500), () async {
      final idTpv = await _userPrefs.getIdTpv();
      await _userPrefs.saveInventoryCountCierre(
        idTpv,
        _pendingInventoryCounts.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      );
    });
  }

  Future<void> _clearInventoryCounts() async {
    _inventorySaveTimer?.cancel();
    _pendingInventoryCounts.clear();
    final idTpv = await _userPrefs.getIdTpv();
    await _userPrefs.clearInventoryCountCierre(idTpv);
  }

  /// Widget del modal de control de inventario
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
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[700],
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
                        'Control de Inventario',
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

              // Info text — ocultar con teclado para ganar espacio
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
                              : 'Ingresa la cantidad real contada de cada producto',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              // Acciones masivas — ocultar con teclado
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
                              _inventoryControllers[p.id]?.text =
                                  _formatInventoryQty(debe);
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

              // Lista de productos
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
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                          itemCount: _inventoryProducts.length,
                          itemBuilder: (context, index) {
                            final product = _inventoryProducts[index];
                            final controller =
                                _inventoryControllers[product.id]!;
                            final debeHaber =
                                _stockRealByProduct[product.id]?.debeHaber ??
                                    product.cantidadFinalReal;
                            final isMissing =
                                _missingInventoryProductIds.contains(
                                  product.id,
                                );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMissing ? Colors.red[50] : Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isMissing ? Colors.red[400]! : Colors.grey[200]!,
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
                                      style: const TextStyle(
                                        fontSize: 14,
                                      ),
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

              // Botones — se mantienen visibles; el Padding exterior ya los
              // sube por encima del teclado.
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
                            const SnackBar(
                              content: Text(
                                'Inventario controlado correctamente',
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
                          'Guardar',
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

  Future<void> _loadExpenses() async {
    try {
      setState(() {
        _isLoadingExpenses = true;
      });

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      List<Expense> expenses = [];

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Cargando egresos desde cache...');
        // Cargar egresos desde cache offline
        expenses = await _loadExpensesOffline();
      } else {
        print('🌐 Modo online - Obteniendo egresos desde servidor...');
        expenses = await TurnoService.getEgresosEnriquecidos();
      }

      // Calculate total expenses and separate by payment type
      double total = 0.0;
      double efectivo = 0.0;
      double transferencias = 0.0;

      for (final expense in expenses) {
        total += expense.montoEntrega;
        // ✅ Solo es transferencia si esDigital == true. null cuenta como efectivo.
        final isDigital = expense.esDigital == true;
        if (isDigital) {
          transferencias += expense.montoEntrega;
        } else {
          efectivo += expense.montoEntrega;
        }
      }

      setState(() {
        _expenses = expenses;
        _totalEgresos = total;
        _egresosEfectivo = efectivo;
        _egresosTransferencias = transferencias;
        _isLoadingExpenses = false;
      });
    } catch (e) {
      print('Error loading expenses: $e');
      setState(() {
        _isLoadingExpenses = false;
      });
    }
  }

  Future<List<Expense>> _loadExpensesOffline() async {
    try {
      print('📱 Cargando egresos desde cache offline...');

      // Obtener egresos desde cache específico (no desde offlineData general)
      final egresosData = await _userPrefs.getEgresosCache();

      if (egresosData.isNotEmpty) {
        final expenses =
            egresosData.map((expenseJson) {
              return Expense(
                idEgreso: expenseJson['id_egreso'] ?? 0,
                montoEntrega: (expenseJson['monto_entrega'] ?? 0.0).toDouble(),
                motivoEntrega: expenseJson['motivo_entrega'] ?? 'Sin motivo',
                nombreRecibe: expenseJson['nombre_recibe'] ?? 'Sin nombre',
                nombreAutoriza:
                    expenseJson['nombre_autoriza'] ?? 'Sin autorización',
                fechaEntrega:
                    expenseJson['fecha_entrega'] != null
                        ? DateTime.parse(expenseJson['fecha_entrega'])
                        : DateTime.now(),
                idMedioPago: expenseJson['id_medio_pago'],
                turnoEstado: expenseJson['turno_estado'] ?? 1,
                medioPago: expenseJson['medio_pago'],
                esDigital: expenseJson['es_digital'] ?? false,
              );
            }).toList();

        print('✅ Egresos cargados desde cache offline: ${expenses.length}');
        return expenses;
      } else {
        print('ℹ️ No hay egresos en cache offline');
        return [];
      }
    } catch (e) {
      print('❌ Error cargando egresos offline: $e');
      return [];
    }
  }

  /// Órdenes del turno abierto.
  ///
  /// `_orderService.orders` ya viene acotado al turno abierto por
  /// [OrderService.loadOrdersForOpenTurnoUnified] (que prioriza el match por
  /// id de turno y sólo cae a un filtro por fecha como respaldo). Volver a
  /// filtrar aquí por fecha de forma estricta podía descartar órdenes
  /// válidas del turno por pequeñas diferencias de zona horaria entre el
  /// `fecha_creacion` de la orden y el `fecha_apertura` del turno, por eso
  /// simplemente se devuelve la lista ya cargada.
  Future<List<Order>> _ordersOfOpenTurno() async {
    return List<Order>.from(_orderService.orders);
  }

  Future<void> _calcularDatosCierre() async {
    final orders = await _ordersOfOpenTurno();

    // Calcular totales reales desde las órdenes locales (online + offline).
    // Esto asegura que el cierre refleje los pagos reales, incluyendo ajustes
    // parciales hechos en el desglose de pagos.
    final totals = _calculateClosureTotalsFromOrders(orders);

    // Órdenes pendientes que deben cerrarse
    final pendientes =
        orders
            .where(
              (order) =>
                  order.status == OrderStatus.enviada ||
                  order.status == OrderStatus.procesando ||
                  order.status == OrderStatus.pagoConfirmado,
            )
            .toList();

    if (!mounted) return;
    setState(() {
      // Solo pisar los totales si tenemos órdenes cargadas; si no, conservar
      // los valores que vengan del resumen del servidor/cache.
      if (orders.isNotEmpty) {
        _ventasTotales = totals.ventas;
        _totalEfectivo = totals.efectivo;
        _totalTransferencias = totals.transferencia;
        _productosVendidos = totals.productos;
        _operacionesTotales = totals.operaciones;
        _ticketPromedio =
            totals.operaciones > 0 ? totals.ventas / totals.operaciones : 0.0;
        // Recalcular efectivo esperado con los valores reales de este turno.
        _efectivoEsperado = _montoInicialCaja + _totalEfectivo;
      }
      _ordenesAbiertas = pendientes.length;
      _ordenesPendientes = pendientes;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Calcular efectivo esperado final (efectivo_esperado - egresos en efectivo)
    final montoEsperado = _efectivoEsperado - _egresosEfectivo;

    print('🔍 BUILD - _manejaInventario: $_manejaInventario');

    return Scaffold(
      backgroundColor: Colors.grey[50],
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Crear Cierre',
          style: TextStyle(
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
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Información del cierre
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
                        Icon(Icons.lock, color: Colors.orange[700], size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'Cierre de Caja',
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
                    if (_fechaAperturaTurno != null) ...[
                      _buildInfoRow(
                        'Turno abierto desde:',
                        '${_formatDate(_fechaAperturaTurno!)} '
                            '${_formatTime(_fechaAperturaTurno!)}',
                      ),
                    ],
                    _buildInfoRow('Usuario:', _userName),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Resumen de ventas
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
                      'Resumen del Turno',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_isLoadingData) ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: Color(0xFF4A90E2),
                          ),
                        ),
                      ),
                    ] else ...[
                      // Ventas y productos
                      _buildInfoRow(
                        'Monto inicial:',
                        '\$${_montoInicialCaja.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Ventas totales:',
                        '\$${_ventasTotales.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Productos vendidos:',
                        '$_productosVendidos unidades',
                      ),
                      _buildInfoRow(
                        'Ticket promedio:',
                        '\$${_ticketPromedio.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Operaciones totales:',
                        '$_operacionesTotales operaciones',
                      ),
                      _buildInfoRow(
                        'Operaciones por hora:',
                        '${_operacionesPorHora.toStringAsFixed(1)} op/h',
                      ),

                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Medios de pago
                      const Text(
                        'Medios de Pago',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Total efectivo:',
                        '\$${_totalEfectivo.toStringAsFixed(2)} (${_porcentajeEfectivo.toStringAsFixed(1)}%)',
                      ),
                      _buildInfoRow(
                        'Transferencias/Otros:',
                        '\$${_totalTransferencias.toStringAsFixed(2)} (${_porcentajeOtros.toStringAsFixed(1)}%)',
                      ),
                      _buildInfoRow(
                        'Efectivo esperado inicial:',
                        '\$${_efectivoEsperado.toStringAsFixed(2)}',
                      ),
                      _buildInfoRow(
                        'Efectivo esperado final:',
                        '\$${montoEsperado.toStringAsFixed(2)}',
                      ),

                      // Show expenses breakdown if there are any
                      if (_totalEgresos > 0) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Egresos del Turno',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          'Egresos en efectivo:',
                          '-\$${_egresosEfectivo.toStringAsFixed(2)}',
                          isNegative: true,
                        ),
                        _buildInfoRow(
                          'Egresos digitales:',
                          '-\$${_egresosTransferencias.toStringAsFixed(2)}',
                          isNegative: true,
                        ),
                        _buildInfoRow(
                          'Total egresos:',
                          '-\$${_totalEgresos.toStringAsFixed(2)}',
                          isNegative: true,
                        ),
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                      ],
                      // Show conciliation status
                      if (_conciliacionEstado.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _conciliacionEstado == 'Conciliado'
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color:
                                  _conciliacionEstado == 'Conciliado'
                                      ? Colors.green[600]
                                      : Colors.orange[600],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Estado: $_conciliacionEstado',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    _conciliacionEstado == 'Conciliado'
                                        ? Colors.green[700]
                                        : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],

                    // Órdenes pendientes warning (always show if there are pending orders)
                    if (_ordenesAbiertas > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning,
                              color: Colors.orange[700],
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _trabajadorManejaAperturaControl
                                  ? '$_ordenesAbiertas órdenes pendientes. Debes cerrarlas antes...'
                                  : '$_ordenesAbiertas órdenes pendientes. No se completarán automáticamente.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Egresos del turno
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
                        Icon(Icons.money_off, color: Colors.red[600], size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Egresos del Turno',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Salidas de dinero registradas durante el turno',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    _buildExpensesList(),

                    // Show total expenses summary if there are expenses
                    if (_expenses.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Egresos:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Text(
                            '\$${_totalEgresos.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Monto final en caja
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
                      'Monto Final en Caja',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ingrese el monto real contado en caja',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCashCountDialog,
                        icon: const Icon(Icons.calculate_outlined,
                            color: Color(0xFF4A90E2)),
                        label: const Text(
                          'Contar billetes',
                          style: TextStyle(color: Color(0xFF4A90E2)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF4A90E2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _montoFinalController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      scrollPadding: const EdgeInsets.only(bottom: 140),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Monto final (\$)',
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
                          return 'El monto final es requerido';
                        }
                        final monto = double.tryParse(value);
                        if (monto == null || monto < 0) {
                          return 'Ingrese un monto válido';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        setState(() {}); // Para actualizar la diferencia
                      },
                    ),

                    // Mostrar diferencia si hay monto ingresado
                    if (_montoFinalController.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildDiferencia(montoEsperado),
                    ],
                  ],
                ),
              ),

              // Órdenes pendientes
              if (_ordenesPendientes.isNotEmpty) ...[
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
                        'Órdenes Pendientes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _trabajadorManejaAperturaControl
                            ? 'Debes cerrar estas órdenes antes de realizar el cierre'
                            : 'Estas órdenes no se completarán automáticamente',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      ..._ordenesPendientes
                          .take(3)
                          .map((order) => _buildOrderItem(order)),
                      if (_ordenesPendientes.length > 3)
                        Text(
                          'Y ${_ordenesPendientes.length - 3} órdenes más...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Observaciones
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
                      'Opcional - Notas sobre el cierre del día',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _observacionesController,
                      maxLines: 3,
                      scrollPadding: const EdgeInsets.only(bottom: 140),
                      decoration: InputDecoration(
                        hintText: 'Ej: Cierre normal, inventario cuadrado...',
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

              // Botón de control de inventario (si maneja inventario)
              if (_manejaInventario) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        _isLoadingInventory ? null : _showInventoryCountModal,
                    icon: _isLoadingInventory
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Icon(
                            _inventorySet ? Icons.edit : Icons.inventory_2,
                          ),
                    label: Text(
                      _isLoadingInventory
                          ? 'Cargando inventario...'
                          : (_inventorySet
                              ? 'Editar Inventario'
                              : (_isLastOpenShift
                                  ? 'Controlar Inventario'
                                  : 'Controlar Inventario (OPCIONAL)')),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _inventorySet
                              ? Colors.green
                              : (_isLastOpenShift
                                  ? Colors.orange
                                  : Colors.blue),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          (_inventorySet
                                  ? Colors.green
                                  : (_isLastOpenShift
                                      ? Colors.orange
                                      : Colors.blue))
                              .withOpacity(0.7),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // Botón crear cierre
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _crearCierre,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[700],
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
                            'Crear Cierre',
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

  Widget _buildInfoRow(String label, String value, {bool isNegative = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isNegative ? Colors.red : Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCashCountDialog() async {
    final total = await showDialog<double>(
      context: context,
      builder: (context) => CashCountDialog(
        userPreferencesService: _userPrefs,
      ),
    );
    if (total != null && mounted) {
      setState(() {
        _montoFinalController.text = total.toStringAsFixed(2);
      });
    }
  }

  Widget _buildDiferencia(double montoEsperado) {
    final montoFinal = double.tryParse(_montoFinalController.text) ?? 0.0;
    final diferencia = montoFinal - montoEsperado;
    final isPositive = diferencia >= 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPositive ? Colors.green[300]! : Colors.red[300]!,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Diferencia:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
          Text(
            '${isPositive ? '+' : ''}\$${diferencia.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isPositive ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              order.id,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '\$${order.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A90E2),
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

  String _formatInventoryCount(double quantity) {
    if (quantity.isNaN || quantity.isInfinite) return '0';
    if (quantity % 1 == 0) return quantity.toInt().toString();
    return quantity.toStringAsFixed(2);
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildExpensesList() {
    if (_isLoadingExpenses) {
      return Container(
        height: 200,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Cargando egresos...'),
            ],
          ),
        ),
      );
    }

    if (_expenses.isEmpty) {
      return Container(
        height: 120,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.money_off_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No hay egresos registrados en este turno',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: _expenses.length > 3 ? 200 : null,
      child: ListView.builder(
        shrinkWrap: _expenses.length <= 3,
        itemCount: _expenses.length,
        itemBuilder: (context, index) {
          final expense = _expenses[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        expense.motivoEntrega,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      expense.formattedAmount,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      expense.formattedTime,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.payment, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      expense.medioPago ?? 'N/A',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            expense.medioPago == 'Efectivo'
                                ? Colors.green[700]
                                : Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Recibe: ${expense.nombreRecibe}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (expense.nombreAutoriza.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Autoriza: ${expense.nombreAutoriza}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _crearCierre() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final montoFinal = double.parse(_montoFinalController.text.trim());
    final montoEsperado = _montoInicialCaja + _totalEfectivo - _egresosEfectivo;
    final diferencia = montoFinal - montoEsperado;

    final currentPendingOrders =
        (await _ordersOfOpenTurno())
            .where(
              (order) =>
                  order.status == OrderStatus.enviada ||
                  order.status == OrderStatus.procesando ||
                  order.status == OrderStatus.pagoConfirmado,
            )
            .toList();

    final carnavalOrderIdsToReactivate = <String>{};
    for (final order in currentPendingOrders) {
      final notas = order.notas;
      if (notas == null) continue;

      final match = RegExp(r'Venta desde orden (\d+)').firstMatch(notas);
      final carnavalOrderId = match?.group(1);
      if (carnavalOrderId != null) {
        carnavalOrderIdsToReactivate.add(carnavalOrderId);
      }
    }

    if (currentPendingOrders.isNotEmpty &&
        carnavalOrderIdsToReactivate.isNotEmpty) {
      NotificationService()
          .reactivateVentaNotificationsForOrdenIds(carnavalOrderIdsToReactivate)
          .catchError((e) {
            print('❌ Error reactivando notificaciones Carnaval: $e');
            return 0;
          });
    }

    if (currentPendingOrders.isNotEmpty) {
      setState(() {
        _ordenesAbiertas = currentPendingOrders.length;
        _ordenesPendientes = currentPendingOrders;
      });

      if (_trabajadorManejaAperturaControl) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tienes ${currentPendingOrders.length} órdenes pendientes. Debes cerrarlas antes de cerrar el turno.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    // Mostrar confirmación si hay diferencia significativa
    if (diferencia.abs() > 0.01) {
      final confirmar = await _showDiferenciaDialog(diferencia);
      if (!confirmar) return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // Validar que si maneja inventario y es el último turno, se haya establecido
      // Si NO es el último turno, el inventario es opcional
      // NUEVO: También es opcional si el trabajador tiene maneja_apertura_control = false
      if (_manejaInventario &&
          _isLastOpenShift &&
          !_inventorySet &&
          _trabajadorManejaAperturaControl) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debes controlar el inventario antes de cerrar el último turno',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isProcessing = false;
        });
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
          setState(() {
            _isProcessing = false;
          });
          return;
        }
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
              // Agregar producto con TODOS los campos requeridos
              productCounts.add({
                'id_producto': product.id,
                'id_variante': product.idVariante,
                'id_ubicacion': product.idUbicacion,
                'id_presentacion': product.idPresentacion,
                'cantidad': cantidadContada,
              });

              // Calcular diferencia vs "debe haber" (stock real del RPC batch)
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

      print('📦 Productos para cierre:');
      if (productCounts != null && productCounts.isNotEmpty) {
        for (var prod in productCounts) {
          print(
            '  - ID: ${prod['id_producto']}, Ubicación: ${prod['id_ubicacion']}, Variante: ${prod['id_variante']}, Presentación: ${prod['id_presentacion']}, Cantidad: ${prod['cantidad']}',
          );
        }
      }
      print('📊 Total productos: ${productCounts?.length ?? 0}');
      print('📝 Observaciones finales: $observacionesFinales');

      // Cerrar trabajadores activos antes de cerrar el turno
      await _closeActiveWorkers();

      // Si la apertura fue offline (cola local), el cierre debe ir por la cola
      // y, si hay red, abrir+cerrar en servidor en este momento.
      //
      // OJO: cualquier turno abierto se cachea localmente en la cola offline
      // "por resiliencia" (ver `saveOfflineTurno`) aunque se haya operado
      // 100% online, marcado con `apertura.origen_apertura == 'online'`. Si
      // forzamos SIEMPRE el camino de la cola offline solo porque existe esa
      // copia cacheada, un cierre que en realidad es online termina pasando
      // por la cola (con sus reintentos automáticos) y puede quedar
      // "pendiente de sync" indefinidamente si algo en ese camino falla,
      // aunque hubiera red disponible en todo momento. Por eso, si hay red
      // ahora mismo y la copia local es solo ese cache de resiliencia (no un
      // turno genuinamente creado offline), preferimos el cierre directo.
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();
      final offlineOpen = await _userPrefs.getOfflineTurno();
      final aperturaOffline = offlineOpen?['apertura'];
      final isCachedOnlineTurno =
          aperturaOffline is Map && aperturaOffline['origen_apertura'] == 'online';
      final hasNetworkNow =
          !isOfflineModeEnabled &&
          await ConnectivityService().performImmediateCheck();
      final useOfflineTurnoPath =
          isOfflineModeEnabled ||
          (offlineOpen != null && !(isCachedOnlineTurno && hasNetworkNow));

      if (useOfflineTurnoPath) {
        print(
          '🔌 Cierre vía turno offline'
          '${offlineOpen != null ? ' (${offlineOpen['local_id']})' : ''}...',
        );
        await _createOfflineCierre(
          efectivoFinal: montoFinal,
          productos: productCounts ?? [],
          observaciones: observacionesFinales,
          diferencia: diferencia,
        );
      } else {
        print('🌐 Modo online - Creando cierre en Supabase...');
        // Call TurnoService to close the shift
        final result = await TurnoService.cerrarTurnoDetailed(
          efectivoReal: montoFinal,
          productos: productCounts ?? [],
          observaciones:
              observacionesFinales.isEmpty ? null : observacionesFinales,
        );
        if (result.success) {
          await _userPrefs.clearOfflineTurno();
          await _userPrefs.clearResumenCierreCache();
          await _userPrefs.clearTurnoResumenCache();
          print(
            '🧹 Cache de turno/resúmenes offline limpiado tras cierre online',
          );

          await _clearInventoryCounts();
          PrinterManager().clearSavedPrinter();
          _showSuccessDialog(montoFinal, diferencia);
        } else if (result.isNetworkError) {
          print(
            '📵 Error de red en cierre online. Creando cierre offline de respaldo',
          );
          await _createOfflineCierre(
            efectivoFinal: montoFinal,
            productos: productCounts ?? [],
            observaciones: observacionesFinales,
            diferencia: diferencia,
          );
        } else {
          // Error de negocio: NO crear cierre offline. Mostrar mensaje real.
          print('⚠️ Cierre rechazado por el servidor: ${result.message}');
          _showErrorMessage(
            result.message ?? 'No se pudo cerrar el turno',
          );
        }
      }
    } catch (e) {
      _showErrorMessage('Error al crear el cierre: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// Cerrar automáticamente todos los trabajadores activos del turno
  Future<void> _closeActiveWorkers() async {
    try {
      print('👥 Verificando trabajadores activos para cerrar...');

      // Obtener turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        print('⚠️ No hay turno abierto, omitiendo cierre de trabajadores');
        return;
      }

      final idRaw = turnoAbierto['id'] ?? turnoAbierto['server_id_turno'];
      final idTurno =
          idRaw is int
              ? idRaw
              : (idRaw is num
                  ? idRaw.toInt()
                  : int.tryParse('$idRaw'));
      if (idTurno == null) {
        print(
          '⚠️ Turno offline sin id de servidor; omitiendo cierre de trabajadores',
        );
        return;
      }

      // Obtener trabajadores del turno
      final workers = await ShiftWorkersService.getShiftWorkers(idTurno);

      // Filtrar solo los trabajadores activos (sin hora de salida)
      final activeWorkers = workers.where((w) => w.isActive).toList();

      if (activeWorkers.isEmpty) {
        print('✅ No hay trabajadores activos para cerrar');
        return;
      }

      print('👥 Cerrando ${activeWorkers.length} trabajador(es) activo(s)...');

      // Hora de cierre del turno (ahora)
      final horaCierre = DateTime.now();

      // Registrar salida de todos los trabajadores activos
      final idsRegistros = activeWorkers.map((w) => w.id!).toList();
      final result = await ShiftWorkersService.registerWorkersExit(
        idsRegistros: idsRegistros,
        horaSalida: horaCierre,
      );

      if (result['success'] == true) {
        _trabajadoresCerrados = activeWorkers.length;
        print(
          '✅ $_trabajadoresCerrados trabajador(es) cerrado(s) automáticamente',
        );
        print('⏰ Hora de cierre: ${horaCierre.toIso8601String()}');
      } else {
        print('⚠️ Error cerrando trabajadores: ${result['message']}');
      }
    } catch (e) {
      print('❌ Error al cerrar trabajadores activos: $e');
      // No lanzar error para no interrumpir el cierre del turno
    }
  }

  Future<bool> _showDiferenciaDialog(double diferencia) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Diferencia en Caja'),
            content: Text(
              'Hay una diferencia de \$${diferencia.toStringAsFixed(2)} entre el monto esperado y el contado.\n\n¿Desea continuar con el cierre?',
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
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  void _showSuccessDialog(double montoFinal, double diferencia) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                const Text('Cierre Creado'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El cierre de caja ha sido registrado exitosamente.',
                ),
                const SizedBox(height: 12),
                Text('Monto final: \$${montoFinal.toStringAsFixed(2)}'),
                Text('Ventas del día: \$${_ventasTotales.toStringAsFixed(2)}'),
                if (diferencia.abs() > 0.01)
                  Text('Diferencia: \$${diferencia.toStringAsFixed(2)}'),
                Text('Órdenes pendientes: ${_ordenesPendientes.length}'),
                if (_trabajadoresCerrados > 0)
                  Text('Trabajadores cerrados: $_trabajadoresCerrados'),
                Text('Fecha: ${_formatDate(DateTime.now())}'),
                Text('Hora: ${_formatTime(DateTime.now())}'),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// Crear cierre offline
  Future<void> _createOfflineCierre({
    required double efectivoFinal,
    required List<Map<String, dynamic>> productos,
    required String observaciones,
    required double diferencia,
  }) async {
    try {
      final userData = await _userPrefs.getUserData();
      final openTurno = await _userPrefs.getOfflineTurno();
      // Usar el mismo id_tpv con el que se abrió ESTE turno, no el TPV
      // seleccionado actualmente en preferencias (puede haber cambiado entre
      // la apertura y el cierre). Si no está disponible, caer al de prefs.
      final aperturaTpvRaw =
          openTurno?['id_tpv'] ??
          (openTurno?['apertura'] is Map
              ? (openTurno!['apertura'] as Map)['id_tpv']
              : null);
      final idTpv =
          (aperturaTpvRaw is int
              ? aperturaTpvRaw
              : (aperturaTpvRaw is num
                  ? aperturaTpvRaw.toInt()
                  : int.tryParse('$aperturaTpvRaw'))) ??
          await _userPrefs.getIdTpv();
      final userUuid = userData['userId'];

      if (idTpv == null || userUuid == null) {
        throw Exception('Faltan datos requeridos para el cierre offline');
      }

      // Generar ID único para el cierre offline + client_uuid de idempotencia.
      final cierreId = '${DateTime.now().millisecondsSinceEpoch}';
      final clientUuid = UuidGenerator.v4();
      final localTurnoId =
          openTurno?['local_id']?.toString() ??
          openTurno?['local_turno_id']?.toString();

      // Hora corregida contra el servidor (ver ServerTimeService), para que
      // fecha_cierre no quede desfasada si el reloj del dispositivo está mal.
      final nowServerCorrected = ServerTimeService().now();

      // Crear estructura de cierre offline
      final cierreData = {
        'id': cierreId,
        'client_uuid': clientUuid,
        'id_tpv': idTpv,
        'usuario': userUuid,
        'tipo_operacion': 'cierre',
        'efectivo_final': efectivoFinal,
        'diferencia': diferencia,
        'fecha_cierre': nowServerCorrected.toIso8601String(),
        'observaciones': observaciones.isEmpty ? null : observaciones,
        'maneja_inventario': _manejaInventario,
        'productos': productos,
        'created_offline_at': nowServerCorrected.toIso8601String(),
        if (localTurnoId != null) 'local_turno_id': localTurnoId,
      };

      // Snapshot del cuadre para que el admin lo vea offline (multi-turno).
      final resumenSnapshot = {
        'efectivo_inicial': _montoInicialCaja,
        'ventas_totales': _ventasTotales,
        'total_efectivo': _totalEfectivo,
        'total_transferencias': _totalTransferencias,
        'productos_vendidos': _productosVendidos,
        'operaciones_totales': _operacionesTotales,
        'ticket_promedio': _ticketPromedio,
        'egresos_efectivo': _egresosEfectivo,
        'egresos_digitales': _egresosTransferencias,
        'egresos_totales': _totalEgresos,
        'efectivo_esperado': _efectivoEsperado - _egresosEfectivo,
        'efectivo_final': efectivoFinal,
        'diferencia': diferencia,
        'fecha_apertura': openTurno?['fecha_apertura'],
        'fecha_cierre': cierreData['fecha_cierre'],
        'observaciones': observaciones.isEmpty ? null : observaciones,
        'reconstruido': false,
      };

      // Cola multi-turno: marca closed_pending_sync (no borra el historial).
      await _userPrefs.markOfflineTurnoClosed(
        localId: localTurnoId,
        cierrePayload: cierreData,
        resumen: resumenSnapshot,
      );

      await _clearInventoryCounts();
      PrinterManager().clearSavedPrinter();

      // En modo online (o con red): abrir+cerrar en servidor ahora.
      // Si el modo offline está activo O el dispositivo quedó preparado
      // para trabajar 100% full-offline, NUNCA se debe intentar contactar
      // al servidor aquí: el cierre queda guardado localmente y la cola de
      // auto_sync se encarga de subirlo cuando corresponda.
      var syncedToServer = false;
      String? syncMessage;
      final useLocalData = await _userPrefs.shouldUseLocalData();
      final isOnlineMode = !useLocalData;
      final hasNetwork =
          !useLocalData &&
          await ConnectivityService().performImmediateCheck();

      if (hasNetwork) {
        print(
          '🌐 Intentando registrar cierre en servidor '
          '(modo ${isOnlineMode ? 'online' : 'offline+red'})...',
        );
        final syncResult =
            await AutoSyncService().syncOfflineTurnoAfterLocalCierre(
              localId: localTurnoId,
            );
        syncedToServer = syncResult['success'] == true;
        syncMessage = syncResult['message']?.toString();
        print(
          syncedToServer
              ? '✅ Cierre sincronizado al servidor'
              : '⚠️ Sync post-cierre no completó: $syncMessage',
        );
      } else {
        print('📵 Sin red tras cierre local; queda pending sync');
        syncMessage = 'Sin conexión a internet';
      }

      if (syncedToServer) {
        await _userPrefs.clearResumenCierreCache();
        await _userPrefs.clearTurnoResumenCache();
      }

      if (mounted) {
        if (syncedToServer) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cierre registrado en el servidor.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          _showSuccessDialog(efectivoFinal, diferencia);
        } else if (isOnlineMode) {
          // Estaba en online: no fingir éxito offline silencioso.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                syncMessage ??
                    'No se pudo registrar en el servidor. Quedó pendiente de sync.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
          _showOfflineSuccessDialog(
            efectivoFinal,
            diferencia,
            syncFailedOnline: true,
            syncMessage: syncMessage,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cierre guardado localmente. Se sincronizará cuando haya conexión.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
          _showOfflineSuccessDialog(efectivoFinal, diferencia);
        }
      }

      print(
        syncedToServer
            ? '✅ Cierre offline sincronizado al servidor: $cierreId'
            : '✅ Cierre offline pendiente de sync: $cierreId',
      );
    } catch (e, stackTrace) {
      print('❌ Error creando cierre offline: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        _showErrorMessage('Error creando cierre offline: $e');
      }
    }
  }

  void _showOfflineSuccessDialog(
    double montoFinal,
    double diferencia, {
    bool syncFailedOnline = false,
    String? syncMessage,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  syncFailedOnline ? Icons.sync_problem : Icons.cloud_off,
                  color: Colors.orange[700],
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    syncFailedOnline
                        ? 'Cierre pendiente de sync'
                        : 'Cierre Offline Creado',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  syncFailedOnline
                      ? (syncMessage ??
                          'Estabas en modo online, pero no se pudo registrar el cierre en el servidor. Quedó guardado localmente para reintentar.')
                      : 'El cierre se ha guardado localmente y se sincronizará automáticamente cuando tengas conexión a internet.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      _buildDialogInfoRow(
                        'Monto Final:',
                        '\$${montoFinal.toStringAsFixed(2)}',
                      ),
                      if (diferencia.abs() > 0.01)
                        _buildDialogInfoRow(
                          'Diferencia:',
                          '${diferencia >= 0 ? '+' : ''}\$${diferencia.toStringAsFixed(2)}',
                          isHighlight: true,
                          color: diferencia >= 0 ? Colors.green : Colors.red,
                        ),
                      _buildDialogInfoRow(
                        'Estado:',
                        'Pendiente de sincronización',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
    );
  }

  Widget _buildDialogInfoRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color ?? (isHighlight ? Colors.black87 : Colors.black87),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatInventoryQty(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}

/// Totales de stock real por producto para el control de inventario (cierre).
class _StockRealProducto {
  final double stockSistema;
  final double pendienteCarnaval;
  final double enCamino;
  final double debeHaber;

  const _StockRealProducto({
    required this.stockSistema,
    required this.pendienteCarnaval,
    required this.enCamino,
    required this.debeHaber,
  });
}
