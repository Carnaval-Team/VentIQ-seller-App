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
  Map<int, Future<List<Map<String, dynamic>>>> _productLocationsFutures =
      {}; // Cache for futures
  bool _inventorySet = false;

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

  // Orders data
  int _ordenesAbiertas = 0;
  List<Order> _ordenesPendientes = [];
  String _userName = 'Cargando...';
  bool _manejaInventario =
      false; // Nueva variable para controlar si mostrar inventario

  // Worker configuration for inventory control
  bool _trabajadorManejaAperturaControl =
      true; // Default to true (safe behavior)

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadStoreConfiguration();
    _loadWorkerConfig(); // Load worker inventory control settings
    _loadDailySummary();
    _calcularDatosCierre();
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
      setState(() {
        _isLoadingInventory = true;
      });

      final offlineData = await _userPrefs.getOfflineData();

      if (offlineData == null || offlineData['products'] == null) {
        print('⚠️ No hay productos cacheados para inventario offline');
        setState(() {
          _inventoryProducts = [];
          _isLoadingInventory = false;
        });
        return;
      }

      final productsData = Map<String, dynamic>.from(
        offlineData['products'] as Map,
      );
      final Map<int, InventoryProduct> productsByIdMap = {};

      for (final categoryProducts in productsData.values) {
        final productList = List<dynamic>.from(categoryProducts as List);

        for (final prodDataRaw in productList) {
          final prodData = Map<String, dynamic>.from(prodDataRaw as Map);
          final detalles =
              prodData['detalles_completos'] as Map<String, dynamic>?;
          if (detalles == null) continue;

          final productoInfo = detalles['producto'] as Map<String, dynamic>?;
          final inventarioList = detalles['inventario'] as List<dynamic>? ?? [];
          if (productoInfo == null || inventarioList.isEmpty) continue;

          // Saltar productos elaborados o servicios
          final esElaborado = productoInfo['es_elaborado'] == true;
          final esServicio = productoInfo['es_servicio'] == true;
          if (esElaborado || esServicio) continue;

          final productId = (productoInfo['id'] ?? prodData['id']) as int;
          if (productsByIdMap.containsKey(productId)) continue;

          final firstInventory = Map<String, dynamic>.from(
            inventarioList.first as Map,
          );
          final ubicacion = Map<String, dynamic>.from(
            firstInventory['ubicacion'] ?? {},
          );
          final almacen = Map<String, dynamic>.from(ubicacion['almacen'] ?? {});
          final variante =
              firstInventory['variante'] != null &&
                      firstInventory['variante'] is Map
                  ? Map<String, dynamic>.from(firstInventory['variante'])
                  : null;
          final presentacion =
              firstInventory['presentacion'] != null &&
                      firstInventory['presentacion'] is Map
                  ? Map<String, dynamic>.from(firstInventory['presentacion'])
                  : null;

          String varianteNombre = 'Variante';
          if (variante != null &&
              variante['atributo'] != null &&
              variante['opcion'] != null) {
            final atributo = variante['atributo'] as Map<String, dynamic>?;
            final opcion = variante['opcion'] as Map<String, dynamic>?;
            if (atributo != null && opcion != null) {
              varianteNombre =
                  '${atributo['label'] ?? 'Atributo'}: ${opcion['valor'] ?? ''}';
            }
          }

          final cantidadDisponible =
              (firstInventory['cantidad_disponible'] as num?)?.toDouble() ??
              0.0;

          productsByIdMap[productId] = InventoryProduct(
            id: productId,
            skuProducto: firstInventory['sku_producto']?.toString() ?? '',
            nombreProducto:
                productoInfo['denominacion'] ??
                prodData['denominacion'] ??
                'Producto',
            idCategoria: (productoInfo['id_categoria'] ?? 0) as int,
            categoria:
                productoInfo['categoria']?['denominacion'] ??
                prodData['categoria'] ??
                'Sin categoría',
            idSubcategoria: (productoInfo['id_subcategoria'] ?? 0) as int,
            subcategoria: prodData['subcategoria'] ?? 'General',
            idTienda:
                (productoInfo['id_tienda'] ?? prodData['id_tienda'] ?? 0)
                    as int,
            tienda: '',
            idAlmacen: (almacen['id'] ?? 0) as int,
            almacen: almacen['denominacion']?.toString() ?? 'Almacén',
            idUbicacion: (ubicacion['id'] ?? 0) as int,
            ubicacion: ubicacion['denominacion']?.toString() ?? 'Ubicación',
            idVariante: variante?['id'] as int?,
            variante: varianteNombre,
            idOpcionVariante: variante?['opcion']?['id'] as int?,
            opcionVariante:
                (variante?['opcion']?['valor'] as String?) ?? varianteNombre,
            idPresentacion: presentacion?['id'] as int?,
            presentacion: presentacion?['denominacion']?.toString() ?? 'Unidad',
            cantidadInicial: cantidadDisponible,
            cantidadFinal: cantidadDisponible,
            stockDisponible: cantidadDisponible,
            stockReservado: 0,
            stockDisponibleAjustado: cantidadDisponible,
            esVendible: true,
            esInventariable: true,
            precioVenta:
                (productoInfo['precio_actual'] ?? prodData['precio'] ?? 0)
                    .toDouble(),
            costoPromedio: null,
            margenActual: null,
            clasificacionAbc: 3,
            abcDescripcion: '',
            fechaUltimaActualizacion: DateTime.now(),
            totalCount: 0,
            resumenInventario: null,
            infoPaginacion: null,
          );
        }
      }

      // Crear lista consolidada y controllers
      final products = productsByIdMap.values.toList();
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

  Future<void> _loadStoreConfiguration() async {
    try {
      final isOffline = await _userPrefs.isOfflineModeEnabled();
      final storeConfig = await _userPrefs.getStoreConfig();

      if (storeConfig != null) {
        final manejaInventario = storeConfig['maneja_inventario'] ?? false;
        print(
          '🏪 Configuración de tienda cargada - Maneja inventario 2: $manejaInventario',
        );

        if (mounted) {
          setState(() {
            _manejaInventario = manejaInventario;
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
            _checkingShiftStatus = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando configuración de tienda: $e');
      if (mounted) {
        setState(() {
          _manejaInventario = false;
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

  Future<void> _loadDailySummary() async {
    try {
      setState(() {
        _isLoadingData = true;
      });

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Cargando datos desde cache...');
        await _loadDailySummaryOffline();
        return;
      }

      print('🌐 Modo online - Obteniendo datos desde servidor...');

      // Get current open shift first
      final turnoAbierto = await TurnoService.getTurnoAbierto();

      if (turnoAbierto == null) {
        print('⚠️ No open shift found');
        setState(() {
          _isLoadingData = false;
        });

        // Show alert and navigate back
        if (mounted) {
          _showNoOpenShiftAlert();
        }
        return;
      }

      // Use the new fn_resumen_diario_cierre function
      final userPrefs = UserPreferencesService();
      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        print(
          '🧪 Loading daily summary with fn_resumen_diario_cierre - TPV: $idTpv',
        );

        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        print('📈 Resumen Cierre Response: $resumenCierreResponse');
        print('📈 Tipo de respuesta: ${resumenCierreResponse.runtimeType}');

        if (resumenCierreResponse != null) {
          Map<String, dynamic> data;

          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            // Si es una lista, tomar el primer elemento
            data = resumenCierreResponse[0] as Map<String, dynamic>;
            print('📈 Datos extraídos de lista: ${data.keys.toList()}');
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            // Si ya es un mapa, usarlo directamente
            data = resumenCierreResponse;
            print('📈 Datos recibidos como mapa: ${data.keys.toList()}');
          } else {
            print('⚠️ Formato de respuesta no reconocido en CierreScreen');
            setState(() {
              _isLoadingData = false;
            });
            return;
          }

          setState(() {
            // Map fields according to your specifications
            _montoInicialCaja = (data['efectivo_inicial'] ?? 0.0).toDouble();
            _ventasTotales = (data['ventas_totales'] ?? 0.0).toDouble();
            _productosVendidos = (data['productos_vendidos'] ?? 0).toInt();
            _ticketPromedio = (data['ticket_promedio'] ?? 0.0).toDouble();
            _operacionesTotales = (data['operaciones_totales'] ?? 0).toInt();
            _operacionesPorHora =
                (data['operaciones_por_hora'] ?? 0.0).toDouble();

            // Payment methods mapping
            _totalEfectivo = (data['efectivo_real'] ?? 0.0).toDouble();
            _totalTransferencias = _ventasTotales - _totalEfectivo;
            _porcentajeEfectivo =
                (data['porcentaje_efectivo'] ?? 0.0).toDouble();
            _porcentajeOtros = (data['porcentaje_otros'] ?? 0.0).toDouble();

            // Expected cash amounts
            _efectivoEsperado = (data['efectivo_esperado'] ?? 0.0).toDouble();

            // Additional fields
            _conciliacionEstado = data['conciliacion_estado'] ?? '';
            _efectivoRealAjustado =
                (data['efectivo_real_ajustado'] ?? 0.0).toDouble();
            _diferenciaAjustada =
                (data['diferencia_ajustada'] ?? 0.0).toDouble();

            _isLoadingData = false;
            // _manejaInventario = turnoAbierto['maneja_inventario'] ?? false; // Comentado: se usa valor de configuración
          });

          print('💰 Mapped Data:');
          print('  - Monto inicial: $_montoInicialCaja');
          print('  - Ventas totales: $_ventasTotales');
          print('  - Productos vendidos: $_productosVendidos');
          print('  - Ticket promedio: $_ticketPromedio');
          print('  - Operaciones totales: $_operacionesTotales');
          print('  - Operaciones por hora: $_operacionesPorHora');
          print('  - Total efectivo: $_totalEfectivo');
          print('  - Transferencias/otros: $_totalTransferencias');
          print('  - Estado conciliación: $_conciliacionEstado');
        } else {
          // Fallback to default values if no data
          setState(() {
            _montoInicialCaja = 500.0; // Default fallback
            _isLoadingData = false;
          });
        }
      } else {
        // Fallback if no TPV ID
        setState(() {
          _montoInicialCaja = 500.0; // Default fallback
          _isLoadingData = false;
        });
      }
    } catch (e) {
      print('Error loading daily summary: $e');
      setState(() {
        _montoInicialCaja = 500.0; // Default fallback
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
    // Dispose inventory controllers
    for (var controller in _inventoryControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInventoryProducts() async {
    // Si estamos offline, usamos cache local y evitamos llamadas a Supabase
    final isOffline = await _userPrefs.isOfflineModeEnabled();
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
      setState(() {
        _isLoadingInventory = true;
      });

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
          'p_mostrar_sin_stock': true,
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

        // Crear lista consolidada y controllers
        final products = productsByIdMap.values.toList();
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
      setState(() {
        _isLoadingInventory = false;
      });
    }
  }

  /// Mostrar modal de control de inventario
  Future<void> _showInventoryCountModal() async {
    print('🔍 Estado antes de cargar:');
    print('  - _inventoryProducts.isEmpty: ${_inventoryProducts.isEmpty}');
    print('  - _isLoadingInventory: $_isLoadingInventory');
    print('  - _inventoryProducts.length: ${_inventoryProducts.length}');

    // Cargar productos ANTES de mostrar el modal
    if (_inventoryProducts.isEmpty && !_isLoadingInventory) {
      print('📦 Cargando productos antes de mostrar modal...');
      await _loadInventoryProducts();
    } else {
      print('⏭️ Omitiendo carga - Condición no cumplida');
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildInventoryCountModal(),
    );
  }

  /// Widget del modal de control de inventario
  Widget _buildInventoryCountModal() {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
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

              // Info text - SIN mostrar cantidades del sistema
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.blue[50],
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Ingresa la cantidad real contada de cada producto',
                        style: TextStyle(fontSize: 14),
                      ),
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
                          padding: const EdgeInsets.all(16),
                          itemCount: _inventoryProducts.length,
                          itemBuilder: (context, index) {
                            final product = _inventoryProducts[index];
                            final controller =
                                _inventoryControllers[product.id]!;

                            // Use cached Future or create new one
                            final locationsFuture = _productLocationsFutures
                                .putIfAbsent(
                                  product.id,
                                  () => _getProductLocations(product.id),
                                );

                            return FutureBuilder<List<Map<String, dynamic>>>(
                              future: locationsFuture,
                              builder: (context, snapshot) {
                                // Show loading state while fetching quantities
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            product.nombreProducto,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final locations = snapshot.data ?? [];
                                final totalQuantity = locations.fold<double>(
                                  0.0,
                                  (sum, loc) =>
                                      sum + (loc['cantidad'] as double),
                                );
                                final totalReservadoCarnaval = locations.fold<double>(
                                  0.0,
                                  (sum, loc) =>
                                      sum + ((loc['reservado_carnaval'] as num?)?.toDouble() ?? 0.0),
                                );
                                final totalPendienteCarnaval = locations.fold<double>(
                                  0.0,
                                  (sum, loc) =>
                                      sum + ((loc['pendiente_carnaval'] as num?)?.toDouble() ?? 0.0),
                                );
                                final totalSistema = totalQuantity;
                                final totalReal = totalQuantity + totalPendienteCarnaval;

                                if (snapshot.connectionState ==
                                        ConnectionState.done &&
                                    controller.text.trim().isEmpty) {
                                  controller.text = _formatInventoryCount(
                                    totalReal,
                                  );
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
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
                                                const SizedBox(height: 4),
                                                // Mostrar cantidad total del sistema
                                                Wrap(
                                                  spacing: 6,
                                                  runSpacing: 4,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue[50],
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors.blue[200]!,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'Sistema: ${totalSistema.toStringAsFixed(2)} unidades',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.blue[700],
                                                        ),
                                                      ),
                                                    ),
                                                    if (totalReservadoCarnaval > 0)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange[50],
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.orange[300]!),
                                                        ),
                                                        child: Text(
                                                          'Reservado: ${totalReservadoCarnaval.toStringAsFixed(0)}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.orange[800],
                                                          ),
                                                        ),
                                                      ),
                                                    if (totalPendienteCarnaval > 0)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green[50],
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.green[300]!),
                                                        ),
                                                        child: Text(
                                                          'Pendiente: ${totalPendienteCarnaval.toStringAsFixed(0)}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                            color: Colors.green[800],
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
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
                                            ),
                                          ),
                                        ],
                                      ),
                                      // Desglose por ubicación (muy pequeño)
                                      if (locations.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Desglose por ubicación:',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              ...locations.map((loc) {
                                                final locCantidad =
                                                    loc['cantidad'] as double;
                                                final locReservado =
                                                    ((loc['reservado_carnaval']
                                                                as num?)
                                                            ?.toDouble() ??
                                                        0.0);
                                                final locPendiente =
                                                    ((loc['pendiente_carnaval']
                                                                as num?)
                                                            ?.toDouble() ??
                                                        0.0);
                                                final locReal = locCantidad;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 2,
                                                      ),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '${loc['almacen']} - ${loc['ubicacion']}',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey[700],
                                                          ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            locReal
                                                                .toStringAsFixed(
                                                                  2,
                                                                ),
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .grey[900],
                                                            ),
                                                          ),
                                                          if (locReservado >
                                                              0) ...[
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              '(res: ${locReservado.toStringAsFixed(0)})',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .orange[700],
                                                              ),
                                                            ),
                                                          ],
                                                          if (locPendiente >
                                                              0) ...[
                                                            const SizedBox(
                                                              width: 3,
                                                            ),
                                                            Text(
                                                              '(pend: +${locPendiente.toStringAsFixed(0)})',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: Colors
                                                                    .green[700],
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
              ),

              // Botones
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
                          setState(() {
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
  }

  Future<List<Map<String, dynamic>>> _getProductLocations(int productId) async {
    try {
      final isOffline = await _userPrefs.isOfflineModeEnabled();
      if (isOffline) {
        final offlineData = await _userPrefs.getOfflineData();
        if (offlineData == null || offlineData['products'] == null) return [];
        final productsData = Map<String, dynamic>.from(
          offlineData['products'] as Map,
        );

        final Map<String, Map<String, dynamic>> locationsMap = {};

        for (final categoryProducts in productsData.values) {
          final productList = List<dynamic>.from(categoryProducts as List);
          for (final prodDataRaw in productList) {
            final prodData = Map<String, dynamic>.from(prodDataRaw as Map);
            final detalles =
                prodData['detalles_completos'] as Map<String, dynamic>?;
            if (detalles == null) continue;
            final productoInfo = detalles['producto'] as Map<String, dynamic>?;
            if (productoInfo == null) continue;
            final pid = (productoInfo['id'] ?? prodData['id']) as int;
            if (pid != productId) continue;

            final inventarioList =
                detalles['inventario'] as List<dynamic>? ?? [];
            for (final invRaw in inventarioList) {
              final inv = Map<String, dynamic>.from(invRaw as Map);
              final ubicacion = Map<String, dynamic>.from(
                inv['ubicacion'] ?? {},
              );
              final almacen = Map<String, dynamic>.from(
                ubicacion['almacen'] ?? {},
              );
              final locationKey =
                  '${almacen['id'] ?? 0}_${ubicacion['id'] ?? 0}';
              final cantidad =
                  (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0.0;
              locationsMap[locationKey] = {
                'ubicacion': ubicacion['denominacion'] ?? 'Ubicación',
                'almacen': almacen['denominacion'] ?? 'Almacén',
                'cantidad': cantidad,
                'reservado_carnaval': 0.0,
                'pendiente_carnaval': 0.0,
              };
            }
          }
        }

        return locationsMap.values.toList();
      }

      final userData = await _userPrefs.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) return [];
      print(
        '📦 Obteniendo ubicaciones del producto $productId para tienda $idTienda (todos los almacenes)...',
      );
      final response = await Supabase.instance.client.rpc(
        'fn_listar_inventario_productos_paged2',
        params: {
          'p_id_tienda': idTienda,
          'p_id_producto': productId,
          'p_limite': 9999,
          'p_mostrar_sin_stock': true,
          'p_pagina': 1,
        },
      );

      if (response != null && response is List) {
        // Agrupar por ubicación única para evitar duplicados por presentaciones
        final Map<String, Map<String, dynamic>> locationsMap = {};

        for (var item in response) {
          try {
            final product = InventoryProduct.fromSupabaseRpc(item);

            // Crear clave única por ubicación (almacén + ubicación)
            final locationKey = '${product.idAlmacen}_${product.idUbicacion}';

            // Solo agregar la primera vez que vemos esta ubicación
            if (!locationsMap.containsKey(locationKey)) {
              locationsMap[locationKey] = {
                'ubicacion': product.ubicacion,
                'almacen': product.almacen,
                'cantidad': product.cantidadFinal,
                'reservado_carnaval': product.reservadoCarnaval,
                'pendiente_carnaval': product.pendienteCarnaval,
              };
            }
          } catch (e) {
            print('❌ Error procesando ubicación: $e');
          }
        }

        return locationsMap.values.toList();
      }

      return [];
    } catch (e) {
      print('❌ Error obteniendo ubicaciones del producto: $e');
      return [];
    }
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

  void _calcularDatosCierre() {
    final orders = _orderService.orders;

    // Calcular ventas totales (órdenes completadas y con pago confirmado)
    final ordersVendidas =
        orders
            .where(
              (order) =>
                  order.status == OrderStatus.completada ||
                  order.status == OrderStatus.pagoConfirmado,
            )
            .toList();

    double ventas = 0.0;
    for (final order in ordersVendidas) {
      ventas += order.total;
    }

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

    setState(() {
      _ventasTotales = ventas;
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
          padding: const EdgeInsets.all(16),
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
                      'Fecha:',
                      _formatDate(DateTime.now().toLocal()),
                    ),
                    _buildInfoRow(
                      'Hora:',
                      _formatTime(DateTime.now().toLocal()),
                    ),
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
                    TextFormField(
                      controller: _montoFinalController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
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
                    onPressed: _showInventoryCountModal,
                    icon: Icon(_inventorySet ? Icons.edit : Icons.inventory_2),
                    label: Text(
                      _inventorySet
                          ? 'Editar Inventario'
                          : (_isLastOpenShift
                              ? 'Controlar Inventario'
                              : 'Controlar Inventario (OPCIONAL)'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _inventorySet
                              ? Colors.green
                              : (_isLastOpenShift
                                  ? Colors.orange
                                  : Colors.blue),
                      foregroundColor: Colors.white,
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
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isNegative ? Colors.red : Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
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
        _orderService.orders
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

              // Calcular diferencia con cantidad del sistema (descontando reservas Carnaval)
              final cantidadSistema = product.cantidadFinalReal;
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

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Creando cierre offline...');
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

      final idTurno = turnoAbierto['id'] as int;

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
      final idTpv = await _userPrefs.getIdTpv();
      final userUuid = userData['userId'];

      if (idTpv == null || userUuid == null) {
        throw Exception('Faltan datos requeridos para el cierre offline');
      }

      // Generar ID único para el cierre offline + client_uuid de idempotencia.
      final cierreId = '${DateTime.now().millisecondsSinceEpoch}';
      final clientUuid = UuidGenerator.v4();

      // Crear estructura de cierre offline
      final cierreData = {
        'id': cierreId,
        'client_uuid': clientUuid,
        'id_tpv': idTpv,
        'usuario': userUuid,
        'tipo_operacion': 'cierre',
        'efectivo_final': efectivoFinal,
        'diferencia': diferencia,
        'fecha_cierre': DateTime.now().toIso8601String(),
        'observaciones': observaciones.isEmpty ? null : observaciones,
        'maneja_inventario': _manejaInventario,
        'productos': productos,
        'created_offline_at': DateTime.now().toIso8601String(),
      };

      // Guardar operación pendiente
      await _userPrefs.savePendingOperation({
        'type': 'cierre_turno',
        'data': cierreData,
      });

      // Limpiar turno offline (ya que se está cerrando)
      await _userPrefs.clearOfflineTurno();

      // Cerrar órdenes pendientes localmente
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cierre creado offline. Se sincronizará cuando tengas conexión.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );

        // Mostrar diálogo de éxito offline
        _showOfflineSuccessDialog(efectivoFinal, diferencia);
      }

      print('✅ Cierre offline creado: $cierreId');
    } catch (e, stackTrace) {
      print('❌ Error creando cierre offline: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        _showErrorMessage('Error creando cierre offline: $e');
      }
    }
  }

  void _showOfflineSuccessDialog(double montoFinal, double diferencia) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.cloud_off, color: Colors.orange[700], size: 28),
                const SizedBox(width: 8),
                const Text(
                  'Cierre Offline Creado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El cierre se ha guardado localmente y se sincronizará automáticamente cuando tengas conexión a internet.',
                  style: TextStyle(fontSize: 14),
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
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? (isHighlight ? Colors.black87 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
