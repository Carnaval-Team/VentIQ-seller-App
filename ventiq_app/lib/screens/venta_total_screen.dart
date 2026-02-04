import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/expense.dart';
import '../services/order_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/printer_manager.dart';
import '../services/web_summary_printer_service.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';
import '../services/currency_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/egresos_list_screen.dart';
import '../widgets/filtered_orders_screen.dart';
import '../screens/orders_screen.dart';

class VentaTotalScreen extends StatefulWidget {
  const VentaTotalScreen({Key? key}) : super(key: key);

  @override
  State<VentaTotalScreen> createState() => _VentaTotalScreenState();
}

class _VentaTotalScreenState extends State<VentaTotalScreen> {
  final OrderService _orderService = OrderService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final PrinterManager _printerManager = PrinterManager();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  List<OrderItem> _productosVendidos = [];
  List<Order> _ordenesVendidas = [];
  double _totalVentas = 0.0;
  int _totalProductos = 0;
  double _totalEgresado = 0.0; // Cambio: era _totalCosto
  double _totalEfectivoReal = 0.0; // Cambio: era _totalDescuentos
  bool _isLoading = true;

  // Expenses data
  List<Expense> _expenses = [];
  double _totalEgresos = 0.0;
  double _egresosEfectivo = 0.0;
  double _egresosTransferencias = 0.0;

  // USD rate data
  double _usdRate = 0.0;
  bool _isLoadingUsdRate = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
    _loadUsdRate();
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _isExcludedPendingOrder(Map<String, dynamic> orderData) {
    final rawStatus = orderData['estado'] ?? orderData['status'];

    if (rawStatus is String) {
      final normalized = rawStatus.toLowerCase();
      return normalized == 'cancelada' || normalized == 'devuelta';
    }

    if (rawStatus is num) {
      final statusIndex = rawStatus.toInt();
      return statusIndex == OrderStatus.cancelada.index ||
          statusIndex == OrderStatus.devuelta.index;
    }

    return false;
  }

  Map<String, dynamic> _calculatePendingOrdersTotals(
    List<Map<String, dynamic>> pendingOrders,
  ) {
    double ventasOffline = 0.0;
    double efectivoOffline = 0.0;
    double transferenciasOffline = 0.0;
    int productosOffline = 0;

    for (final orderData in pendingOrders) {
      if (_isExcludedPendingOrder(orderData)) {
        continue;
      }
      final total = _parseDouble(
        orderData['total'] ??
            orderData['total_operacion'] ??
            orderData['total_venta'],
      );
      ventasOffline += total;

      final items = orderData['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            productosOffline += _parseInt(item['cantidad']);
          }
        }
      }

      final pagos = orderData['pagos'] ?? orderData['desglose_pagos'];
      double efectivoOrden = 0.0;
      double transferenciaOrden = 0.0;

      if (pagos is List && pagos.isNotEmpty) {
        for (final pago in pagos) {
          if (pago is Map) {
            final monto = _parseDouble(
              pago['monto'] ??
                  pago['monto_pago'] ??
                  pago['monto_total'] ??
                  pago['monto_entrega'],
            );
            final esEfectivo =
                pago['es_efectivo'] == true || pago['id_medio_pago'] == 1;
            final esDigital = pago['es_digital'] == true;

            if (esEfectivo) {
              efectivoOrden += monto;
            } else if (esDigital) {
              transferenciaOrden += monto;
            } else {
              transferenciaOrden += monto;
            }
          }
        }
      }

      if (total > 0 && (efectivoOrden + transferenciaOrden) == 0) {
        efectivoOrden = total * 0.7;
        transferenciaOrden = total * 0.3;
      }

      efectivoOffline += efectivoOrden;
      transferenciasOffline += transferenciaOrden;
    }

    return {
      'ventasOffline': ventasOffline,
      'efectivoOffline': efectivoOffline,
      'transferenciasOffline': transferenciasOffline,
      'productosOffline': productosOffline,
    };
  }

  Future<void> _initializeData() async {
    await _loadExpenses();
    await _calcularVentaTotal();
  }

  Future<void> _loadUsdRate() async {
    setState(() {
      _isLoadingUsdRate = true;
    });

    try {
      final rate = await CurrencyService.getUsdRate();
      setState(() {
        _usdRate = rate;
        _isLoadingUsdRate = false;
      });
    } catch (e) {
      print('❌ Error loading USD rate: $e');
      setState(() {
        _usdRate = 420.0; // Default fallback rate
        _isLoadingUsdRate = false;
      });
    }
  }

  Future<void> _calcularVentaTotal() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Obtener preferencias del usuario
      final userPrefs = UserPreferencesService();

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await userPrefs.isOfflineModeEnabled();

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline activado - Cargando datos desde cache...');
        await _calcularVentaTotalOffline();
        return;
      }

      // Modo online: cargar desde Supabase
      print('🌐 Modo online - Cargando datos desde servidor...');

      // Primero cargar las órdenes desde Supabase
      _orderService.clearAllOrders();
      await _orderService.listOrdersFromSupabase();

      // Agregar órdenes offline pendientes (para lista y totales reales)
      final pendingOrders = await userPrefs.getPendingOrders();
      if (pendingOrders.isNotEmpty) {
        _orderService.addPendingOrdersToList(pendingOrders);
      }
      final offlineTotals = _calculatePendingOrdersTotals(pendingOrders);

      // Obtener datos del turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        // Llamar a la función de resumen diario
        final resumenCierreResponse = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        print('📈 VentaTotal Resumen Response: $resumenCierreResponse');
        print('📈 Tipo de respuesta: ${resumenCierreResponse.runtimeType}');

        if (resumenCierreResponse != null) {
          Map<String, dynamic> data;

          // Manejar tanto List como Map de respuesta
          if (resumenCierreResponse is List &&
              resumenCierreResponse.isNotEmpty) {
            // Si es una lista, tomar el primer elemento
            data = resumenCierreResponse[0] as Map<String, dynamic>;
            print(
              '📈 VentaTotal datos extraídos de lista: ${data.keys.toList()}',
            );
          } else if (resumenCierreResponse is Map<String, dynamic>) {
            // Si ya es un mapa, usarlo directamente
            data = resumenCierreResponse;
            print(
              '📈 VentaTotal datos recibidos como mapa: ${data.keys.toList()}',
            );
          } else {
            print('⚠️ Formato de respuesta no reconocido en VentaTotalScreen');
            setState(() {
              _isLoading = false;
            });
            return;
          }

          // Obtener órdenes locales para productos vendidos (ahora ya cargadas)
          final orders = _orderService.orders;
          final productosVendidos = <OrderItem>[];
          final ordenesVendidas = <Order>[];

          for (final order in orders) {
            final isCompletedOrOffline =
                order.status == OrderStatus.completada ||
                order.status == OrderStatus.pagoConfirmado ||
                order.status == OrderStatus.pendienteDeSincronizacion ||
                order.status == OrderStatus.enviada;

            if (isCompletedOrOffline) {
              ordenesVendidas.add(order);
              for (final item in order.items) {
                productosVendidos.add(item);
              }
            }
          }

          setState(() {
            _productosVendidos = productosVendidos;
            _ordenesVendidas = ordenesVendidas;

            final offlineVentas =
                (offlineTotals['ventasOffline'] ?? 0.0).toDouble();
            final offlineProductos =
                (offlineTotals['productosOffline'] ?? 0).toInt();
            final offlineEfectivo =
                (offlineTotals['efectivoOffline'] ?? 0.0).toDouble();

            final ventasTotalesBase =
                (data['ventas_totales'] ?? 0.0).toDouble();
            final efectivoRealBase = (data['efectivo_real'] ?? 0.0).toDouble();
            final efectivoEsperadoBase =
                (data['efectivo_esperado'] ?? 0.0).toDouble();

            // Totales reales = resumen online + ventas offline pendientes
            final ventasTotales = ventasTotalesBase + offlineVentas;
            final efectivoReal = efectivoRealBase + offlineEfectivo;
            final efectivoEsperado = efectivoEsperadoBase + offlineEfectivo;

            _totalVentas = ventasTotales;
            _totalProductos =
                (data['productos_vendidos'] ?? 0).toInt() + offlineProductos;

            // Calcular egresado: ventas_totales - efectivo_real + egresos en efectivo
            _totalEgresado = ventasTotales - efectivoReal + _egresosEfectivo;

            // Efectivo real: efectivo_esperado - egresos en efectivo
            _totalEfectivoReal = efectivoEsperado - _egresosEfectivo;

            _isLoading = false;
          });

          print('DEBUG - Venta Total Screen Data:');
          print('Ventas Totales: $_totalVentas');
          print('Productos Vendidos: $_totalProductos');
          print('Órdenes cargadas: ${orders.length}');
          print('Órdenes completadas: ${ordenesVendidas.length}');
          print('Productos vendidos: ${productosVendidos.length}');
          print(
            'Total Egresado: $_totalEgresado (incluye egresos efectivo: $_egresosEfectivo)',
          );
          print(
            'Efectivo Real: $_totalEfectivoReal (descontando egresos efectivo)',
          );
        }
      }
    } catch (e) {
      print('Error al calcular venta total: $e');
      // Fallback a cálculo local con las órdenes ya cargadas
      final orders = _orderService.orders;
      final productosVendidos = <OrderItem>[];
      final ordenesVendidas = <Order>[];
      double totalVentas = 0.0;
      int totalProductos = 0;

      for (final order in orders) {
        final isCompletedOrOffline =
            order.status == OrderStatus.completada ||
            order.status == OrderStatus.pagoConfirmado ||
            order.status == OrderStatus.pendienteDeSincronizacion ||
            order.status == OrderStatus.enviada;

        if (isCompletedOrOffline) {
          ordenesVendidas.add(order);
          totalVentas += order.total;

          for (final item in order.items) {
            productosVendidos.add(item);
            totalProductos += item.cantidad;
          }
        }
      }

      setState(() {
        _productosVendidos = productosVendidos;
        _ordenesVendidas = ordenesVendidas;
        _totalVentas = totalVentas;
        _totalProductos = totalProductos;
        _totalEgresado = 0.0;
        _totalEfectivoReal = 0.0;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExpenses() async {
    try {
      final userPrefs = UserPreferencesService();

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await userPrefs.isOfflineModeEnabled();

      List<Expense> expenses = [];

      if (isOfflineModeEnabled) {
        print(
          '🔌 VentaTotal - Modo offline activado, cargando egresos desde cache...',
        );
        expenses = await _loadExpensesOffline();
      } else {
        print(
          '🌐 VentaTotal - Modo online, obteniendo egresos desde servidor...',
        );
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
      });

      print('DEBUG - Expenses loaded:');
      print('Total egresos: $_totalEgresos');
      print('Egresos efectivo: $_egresosEfectivo');
      print('Egresos transferencias: $_egresosTransferencias');
    } catch (e) {
      print('Error loading expenses: $e');
      setState(() {
        _expenses = [];
        _totalEgresos = 0.0;
        _egresosEfectivo = 0.0;
        _egresosTransferencias = 0.0;
      });
    }
  }

  Future<List<Expense>> _loadExpensesOffline() async {
    try {
      print('📱 VentaTotal - Cargando egresos desde cache offline...');

      final userPrefs = UserPreferencesService();

      // Obtener egresos desde cache específico
      final egresosData = await userPrefs.getEgresosCache();

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

        print(
          '✅ VentaTotal - Egresos cargados desde cache offline: ${expenses.length}',
        );
        return expenses;
      } else {
        print('ℹ️ VentaTotal - No hay egresos en cache offline');
        return [];
      }
    } catch (e) {
      print('❌ VentaTotal - Error cargando egresos offline: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Venta Total',
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _initializeData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Resumen de ventas
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey, width: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: const Color(0xFF4A90E2),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Resumen de Ventas',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildClickableSummaryCard(
                            'Total Egresado',
                            _egresosEfectivo.toStringAsFixed(0),
                            Icons.attach_money,
                            const Color.fromARGB(255, 160, 22, 22),
                            onTap: _showEgresosList,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildClickableSummaryCard(
                            'Total Ventas',
                            '\$${_totalVentas.toStringAsFixed(0)}',
                            Icons.attach_money,
                            Colors.green,
                            onTap: _showAllOrders,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildClickableSummaryCard(
                            'Total Transferencia',
                            '\$${((_totalEgresado - _egresosEfectivo) > 0 ? (_totalEgresado - _egresosEfectivo) : 0).toStringAsFixed(0)}',
                            Icons.credit_card,
                            Colors.orange,
                            onTap: _showTransferOrders,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildClickableSummaryCard(
                            'Efectivo Real',
                            '\$${_totalEfectivoReal.toStringAsFixed(0)}',
                            Icons.account_balance_wallet,
                            Colors.green,
                            onTap: _showCashOrders,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Lista de órdenes vendidas
              Expanded(
                child:
                    _isLoading
                        ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Cargando datos de ventas...'),
                            ],
                          ),
                        )
                        : _ordenesVendidas.isEmpty
                        ? _buildEmptyState()
                        : _buildOrdersList(),
              ),
            ],
          ),
          // USD Rate Chip positioned at bottom left
          Positioned(bottom: 16, left: 16, child: _buildUsdRateChip()),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildClickableSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(icon, color: color, size: 24)],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showEgresosList() {
    print('🔍 Mostrando lista de egresos...');
    print('📊 Total egresos: $_totalEgresos');
    print('💰 Egresos efectivo: $_egresosEfectivo');
    print('💳 Egresos transferencias: $_egresosTransferencias');
    print('📋 Número de egresos: ${_expenses.length}');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => EgresosListScreen(
              expenses: _expenses,
              totalEgresos: _totalEgresos,
              egresosEfectivo: _egresosEfectivo,
              egresosTransferencias: _egresosTransferencias,
            ),
      ),
    );
  }

  void _showAllOrders() {
    print('🔍 Navegando a todas las órdenes...');
    print('📊 Total órdenes: ${_orderService.orders.length}');
    print('💰 Total ventas: $_totalVentas');

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const OrdersScreen()),
    );
  }

  void _showCashOrders() {
    print('🔍 Mostrando órdenes pagadas con efectivo...');
    print('💰 Efectivo real: $_totalEfectivoReal');

    final completedOrders =
        _orderService.orders
            .where(
              (order) =>
                  order.status == OrderStatus.completada ||
                  order.status == OrderStatus.pagoConfirmado ||
                  order.status == OrderStatus.pendienteDeSincronizacion ||
                  order.status == OrderStatus.enviada,
            )
            .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => FilteredOrdersScreen(
              filter: PaymentFilter.cash,
              title: 'Órdenes - Efectivo',
              orders: completedOrders,
              totalAmount: _totalEfectivoReal,
            ),
      ),
    );
  }

  void _showTransferOrders() {
    print('🔍 Mostrando órdenes pagadas con transferencias...');
    print('💳 Total transferencias: ${(_totalEgresado - _egresosEfectivo)}');

    final completedOrders =
        _orderService.orders
            .where(
              (order) =>
                  order.status == OrderStatus.completada ||
                  order.status == OrderStatus.pagoConfirmado ||
                  order.status == OrderStatus.pendienteDeSincronizacion ||
                  order.status == OrderStatus.enviada,
            )
            .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => FilteredOrdersScreen(
              filter: PaymentFilter.transfer,
              title: 'Órdenes - Transferencias',
              orders: completedOrders,
              totalAmount: (_totalEgresado - _egresosEfectivo),
            ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay ventas registradas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Los productos vendidos aparecerán aquí',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header de la lista
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Orden',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Cliente',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Acción',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          // Lista de órdenes
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children:
                  _ordenesVendidas
                      .map((order) => _buildOrderItem(order))
                      .toList(),
            ),
          ),

          // Resumen de productos detallado
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.summarize, color: const Color(0xFF4A90E2)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Resumen Detallado de Productos',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _imprimirResumenDetallado,
                        icon: const Icon(Icons.print),
                        color: const Color(0xFF10B981),
                        tooltip: 'Imprimir resumen',
                      ),
                    ],
                  ),
                ),
                _buildDetailedProductsTable(),
              ],
            ),
          ),

          // Total final
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TOTAL GENERAL:',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '\$${_totalVentas.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Información de la orden
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orden ${order.id}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${order.items.length} productos',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // Cliente
          Expanded(
            child: Text(
              order.buyerName ?? 'Sin nombre',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Total
          Expanded(
            child: Text(
              '\$${order.total.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A90E2),
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Botón de imprimir
          Expanded(
            child: Center(
              child: IconButton(
                onPressed: () => _imprimirTicketIndividual(order),
                icon: const Icon(Icons.print),
                color: const Color(0xFF10B981),
                tooltip: 'Imprimir ticket',
                iconSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedProductsTable() {
    // Agrupar productos por nombre para mostrar cantidades totales
    final productosAgrupados = <String, Map<String, dynamic>>{};

    for (final item in _productosVendidos) {
      print('🔍 Procesando item: ${item.nombre}');
      print('🔍 Ingredientes: ${item.ingredientes?.length ?? 0}');

      // Si el producto tiene ingredientes, mostrar los ingredientes en lugar del producto
      if (item.ingredientes != null && item.ingredientes!.isNotEmpty) {
        print('🍽️ Producto elaborado detectado: ${item.nombre}');

        // Procesar cada ingrediente
        for (final ingrediente in item.ingredientes!) {
          final nombreIngrediente =
              ingrediente['nombre_ingrediente'] as String? ?? 'Ingrediente';
          final cantidadVendida =
              (ingrediente['cantidad_vendida'] as num?)?.toDouble() ?? 0.0;
          final cantidadFinal =
              (ingrediente['cantidad_final'] as num?)?.toDouble() ?? 0.0;
          // Calcular cantidad inicial como: final + vendido
          final cantidadInicial = cantidadFinal + cantidadVendida;
          final unidadMedida =
              ingrediente['unidad_medida'] as String? ?? 'unidades';
          final precioUnitario =
              (ingrediente['precio_unitario'] as num?)?.toDouble() ?? 0.0;
          final importe = (ingrediente['importe'] as num?)?.toDouble() ?? 0.0;

          final keyIngrediente = '$nombreIngrediente ($unidadMedida)';

          print('📦 Procesando ingrediente: $keyIngrediente');
          print('   - Cantidad vendida: $cantidadVendida');
          print('   - Cantidad final: $cantidadFinal');
          print(
            '   - Cantidad inicial (calculada): $cantidadInicial = $cantidadFinal + $cantidadVendida',
          );
          print('   - Precio unitario: $precioUnitario');
          print('   - Importe: $importe');

          if (productosAgrupados.containsKey(keyIngrediente)) {
            // Sumar cantidades vendidas e importes de ingredientes duplicados
            productosAgrupados[keyIngrediente]!['cantidad'] += cantidadVendida;
            productosAgrupados[keyIngrediente]!['subtotal'] += importe;
            // Recalcular cantidad inicial como: final + total vendido para ingredientes
            if (productosAgrupados[keyIngrediente]!['cantidadFinal'] != null) {
              productosAgrupados[keyIngrediente]!['cantidadInicial'] =
                  productosAgrupados[keyIngrediente]!['cantidadFinal'] +
                  productosAgrupados[keyIngrediente]!['cantidad'];
            }
            if (productosAgrupados[keyIngrediente]!['cantidadFinal'] == null) {
              productosAgrupados[keyIngrediente]!['cantidadFinal'] =
                  cantidadFinal;
              // Recalcular inicial después de asignar final
              productosAgrupados[keyIngrediente]!['cantidadInicial'] =
                  cantidadFinal +
                  productosAgrupados[keyIngrediente]!['cantidad'];
            }
          } else {
            // Crear entrada para el ingrediente
            productosAgrupados[keyIngrediente] = {
              'item': OrderItem(
                id:
                    'ING-${ingrediente['id_ingrediente']}-${DateTime.now().millisecondsSinceEpoch}',
                producto:
                    item.producto, // Usar el producto padre para referencia
                cantidad: cantidadVendida.toInt(),
                precioUnitario:
                    precioUnitario, // Precio unitario del ingrediente
                ubicacionAlmacen: item.ubicacionAlmacen,
              ),
              'nombre': nombreIngrediente,
              'unidadMedida': unidadMedida,
              'cantidad': cantidadVendida,
              'subtotal': importe, // Importe del ingrediente
              'cantidadInicial': cantidadInicial,
              'cantidadFinal': cantidadFinal,
              'entradasProducto':
                  (ingrediente['entradas_producto'] as num?)?.toDouble() ?? 0.0,
              'esIngrediente': true,
            };
          }
        }
      } else {
        // Producto (elaborado o normal)
        final key = item.nombre;
        final esElaborado = item.producto.esElaborado;

        if (esElaborado) {
          print('🍽️ Producto elaborado: $key');
        } else {
          print('📦 Producto normal: $key');
        }

        if (productosAgrupados.containsKey(key)) {
          productosAgrupados[key]!['cantidad'] += item.cantidad;
          productosAgrupados[key]!['subtotal'] += item.subtotal;

          // Solo calcular cantidades iniciales y finales para productos NO elaborados
          if (!esElaborado) {
            // Recalcular cantidad inicial como: final + total vendido
            if (productosAgrupados[key]!['cantidadFinal'] != null) {
              productosAgrupados[key]!['cantidadInicial'] =
                  productosAgrupados[key]!['cantidadFinal'] +
                  productosAgrupados[key]!['cantidad'];
            }
            if (productosAgrupados[key]!['cantidadFinal'] == null &&
                item.cantidadFinal != null) {
              productosAgrupados[key]!['cantidadFinal'] = item.cantidadFinal;
              // Recalcular inicial después de asignar final
              productosAgrupados[key]!['cantidadInicial'] =
                  (item.cantidadFinal ?? 0.0) +
                  productosAgrupados[key]!['cantidad'];
            }
          }
        } else {
          if (esElaborado) {
            // Para productos elaborados: cantidades inicial y final = null (se mostrarán como "-")
            productosAgrupados[key] = {
              'item': item,
              'nombre': item.nombre,
              'cantidad': item.cantidad,
              'subtotal': item.subtotal,
              'cantidadInicial': null, // Se mostrará como "-"
              'cantidadFinal': null, // Se mostrará como "-"
              'entradasProducto': item.entradasProducto ?? 0.0,
              'esIngrediente': false,
              'esElaborado': true,
            };
          } else {
            // Calcular cantidad inicial como: final + vendido para productos normales
            final cantidadInicialCalculada =
                (item.cantidadFinal ?? 0.0) + item.cantidad;

            productosAgrupados[key] = {
              'item': item,
              'nombre': item.nombre,
              'cantidad': item.cantidad,
              'subtotal': item.subtotal,
              'cantidadInicial': cantidadInicialCalculada,
              'cantidadFinal': item.cantidadFinal,
              'entradasProducto': item.entradasProducto ?? 0.0,
              'esIngrediente': false,
              'esElaborado': false,
            };
          }
        }
      }
    }

    final productosFinales = productosAgrupados.values.toList();
    print('📋 Total items en resumen: ${productosFinales.length}');

    return Column(
      children: [
        // Header de la tabla detallada
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey[100],
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Producto',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Inicial',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Entra.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Vend.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Final',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  'Total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),

        // Lista de productos detallada
        ...productosFinales.map(
          (producto) => _buildDetailedProductItem(producto),
        ),
      ],
    );
  }

  Widget _buildDetailedProductItem(Map<String, dynamic> producto) {
    final item = producto['item'] as OrderItem;
    final cantidad = producto['cantidad'] as num;
    final subtotal = producto['subtotal'] as double;
    final cantidadInicial = producto['cantidadInicial'] as double?;
    final cantidadFinal = producto['cantidadFinal'] as double?;
    final entradasProducto = producto['entradasProducto'] as double? ?? 0.0;
    final esIngrediente = producto['esIngrediente'] as bool? ?? false;
    final esElaborado = producto['esElaborado'] as bool? ?? false;
    final nombre = producto['nombre'] as String? ?? item.nombre;
    final unidadMedida = producto['unidadMedida'] as String?;

    // Para ingredientes, usar las cantidades reales del ingrediente
    final cantidadMostrar =
        esIngrediente ? cantidad.toDouble() : cantidad.toDouble();

    // Para productos elaborados, mostrar "-" en cantidades inicial, entradas y final
    final cantidadInicialTexto =
        (esElaborado && cantidadInicial == null)
            ? "-"
            : (cantidadInicial ?? 0.0).toStringAsFixed(esIngrediente ? 1 : 0);
    final entradasTexto =
        esElaborado
            ? "-"
            : entradasProducto.toStringAsFixed(esIngrediente ? 1 : 0);
    final cantidadFinalTexto =
        (esElaborado && cantidadFinal == null)
            ? "-"
            : (cantidadFinal ?? 0.0).toStringAsFixed(esIngrediente ? 1 : 0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        // Fondo diferente para ingredientes
        color: esIngrediente ? Colors.orange[50] : Colors.white,
      ),
      child: Row(
        children: [
          // Nombre del producto/ingrediente
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Ícono para ingredientes
                    if (esIngrediente) ...[
                      Icon(
                        Icons.restaurant,
                        size: 14,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        nombre,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color:
                              esIngrediente
                                  ? Colors.orange[800]
                                  : const Color(0xFF1F2937),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (esIngrediente) ...[
                  Text(
                    'Ingrediente${unidadMedida != null ? ' ($unidadMedida)' : ''}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Text(
                    '\$${item.precioUnitario.toStringAsFixed(2)} c/u',
                    style: TextStyle(fontSize: 10, color: Colors.orange[600]),
                  ),
                ] else ...[
                  Text(
                    '\$${item.precioUnitario.toStringAsFixed(0)} c/u',
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),

          // Cantidad Inicial
          Expanded(
            child: Text(
              cantidadInicialTexto,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blue,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Entradas del Producto
          Expanded(
            child: Text(
              entradasTexto,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.purple,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Cantidad Vendida
          Expanded(
            child: Text(
              cantidadMostrar.toStringAsFixed(esIngrediente ? 1 : 0),
              style: TextStyle(
                fontSize: 12,
                color: esIngrediente ? Colors.orange[700] : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Cantidad Final
          Expanded(
            child: Text(
              cantidadFinalTexto,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Total (ahora incluye ingredientes)
          Expanded(
            child: Text(
              '\$${subtotal.toStringAsFixed(esIngrediente ? 2 : 0)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    esIngrediente
                        ? Colors.orange[700]
                        : const Color(0xFF4A90E2),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // Método para imprimir ticket individual
  Future<void> _imprimirTicketIndividual(Order order) async {
    try {
      print(
        '🖨️ Iniciando impresión de ticket individual para orden ${order.id}',
      );

      // Usar PrinterManager para manejar tanto web como Bluetooth
      final result = await _printerManager.printInvoice(context, order);

      if (result.success) {
        _showSuccessDialog('¡Ticket Impreso!', result.message);
        print('✅ ${result.message}');
        if (result.details != null) {
          print('ℹ️ Detalles: ${result.details}');
        }
      } else {
        _showErrorDialog('Error de Impresión', result.message);
        print('❌ ${result.message}');
        if (result.details != null) {
          print('ℹ️ Detalles: ${result.details}');
        }
      }
    } catch (e) {
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
      print('❌ Error en _imprimirTicketIndividual: $e');
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: const Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  // Método para imprimir resumen detallado de productos
  Future<void> _imprimirResumenDetallado() async {
    try {
      print('🖨️ Iniciando impresión de resumen detallado');

      // Verificar si estamos en web
      if (PlatformUtils.isWeb) {
        // Usar impresión web
        await _imprimirResumenDetalladoWeb();
      } else {
        // Usar impresión Bluetooth
        await _imprimirResumenDetalladoBluetooth();
      }
    } catch (e) {
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
      print('❌ Error en _imprimirResumenDetallado: $e');
    }
  }

  // Método para imprimir resumen detallado en web
  Future<void> _imprimirResumenDetalladoWeb() async {
    try {
      // Mostrar diálogo de confirmación
      bool shouldPrint = await _showPrintSummaryConfirmationDialog();
      if (!shouldPrint) return;

      print('🌐 Imprimiendo resumen detallado en web...');

      // Importar el servicio web
      final webSummaryService = WebSummaryPrinterService();

      // Imprimir usando el servicio web
      bool printed = await webSummaryService.printDetailedSummary(
        productosVendidos: _productosVendidos,
        totalVentas: _totalVentas,
        totalProductos: _totalProductos,
        totalEgresado: _totalEgresado,
        totalEfectivoReal: _totalEfectivoReal,
      );

      if (printed) {
        _showSuccessDialog(
          '¡Resumen Impreso!',
          'El resumen detallado se ha enviado a impresión web correctamente.',
        );
        print('✅ Resumen detallado impreso en web exitosamente');
      } else {
        _showErrorDialog(
          'Error de Impresión Web',
          'No se pudo imprimir el resumen detallado en web.',
        );
        print('❌ Error imprimiendo resumen detallado en web');
      }
    } catch (e) {
      _showErrorDialog('Error Web', 'Ocurrió un error al imprimir en web: $e');
      print('❌ Error en _imprimirResumenDetalladoWeb: $e');
    }
  }

  // Método para imprimir resumen detallado en Bluetooth
  Future<void> _imprimirResumenDetalladoBluetooth() async {
    try {
      // Mostrar diálogo de confirmación
      bool shouldPrint = await _showPrintSummaryConfirmationDialog();
      if (!shouldPrint) return;

      // Mostrar diálogo de selección de dispositivo
      final device = await _printerService.showDeviceSelectionDialog(context);
      if (device == null) return;

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Conectando e imprimiendo resumen...'),
                ],
              ),
            ),
      );

      // Conectar a la impresora
      bool connected = await _printerService.connectToDevice(device);
      if (!connected) {
        Navigator.pop(context);
        _showErrorDialog(
          'Error de Conexión',
          'No se pudo conectar a la impresora.',
        );
        return;
      }

      // Imprimir el resumen
      bool printed = await _printDetailedSummary();
      Navigator.pop(context);

      if (printed) {
        _showSuccessDialog(
          '¡Resumen Impreso!',
          'El resumen detallado se ha impreso correctamente.',
        );
      } else {
        _showErrorDialog(
          'Error de Impresión',
          'No se pudo imprimir el resumen.',
        );
      }

      // Desconectar
      await _printerService.disconnect();
    } catch (e) {
      Navigator.pop(context);
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
    }
  }

  Future<bool> _showPrintSummaryConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.summarize, color: const Color(0xFF4A90E2)),
                    const SizedBox(width: 8),
                    const Text('Imprimir Resumen'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '¿Deseas imprimir el resumen detallado de productos?',
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Productos: $_totalProductos'),
                          Text(
                            'Total Ventas: \$${_totalVentas.toStringAsFixed(0)}',
                          ),
                          Text(
                            'Total Egresado: \$${_totalEgresado.toStringAsFixed(0)}',
                          ),
                          Text(
                            'Efectivo Real: \$${_totalEfectivoReal.toStringAsFixed(0)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.print),
                    label: const Text('Imprimir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A90E2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<bool> _printDetailedSummary() async {
    try {
      // Obtener información del vendedor
      final workerProfile = await _userPreferencesService.getWorkerProfile();
      final userEmail = await _userPreferencesService.getUserEmail();

      final sellerName =
          '${workerProfile['nombres'] ?? ''} ${workerProfile['apellidos'] ?? ''}'
              .trim();
      final sellerEmail = userEmail ?? 'Sin email';

      // Crear el contenido de impresión usando el formato ESC/POS
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // Header
      bytes += generator.text(
        'INVENTTIA',
        styles: PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.text(
        'RESUMEN DE VENTAS',
        styles: PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '================================',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(1);

      // Información del vendedor y fecha
      final now = DateTime.now();
      bytes += generator.text(
        'VENDEDOR: $sellerName',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'EMAIL: $sellerEmail',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'FECHA: ${_formatDateForPrint(now)}',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.emptyLines(1);

      // Resumen general
      bytes += generator.text(
        'RESUMEN GENERAL:',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
      bytes += generator.text(
        '--------------------------------',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.text(
        'Total Productos: $_totalProductos',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'Total Ventas: \$${_totalVentas.toStringAsFixed(0)}',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'Total Egresado: \$${_totalEgresado.toStringAsFixed(0)}',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.text(
        'Efectivo Real: \$${_totalEfectivoReal.toStringAsFixed(0)}',
        styles: PosStyles(align: PosAlign.left),
      );
      bytes += generator.emptyLines(1);

      // Detalle de productos
      bytes += generator.text(
        'DETALLE POR PRODUCTO:',
        styles: PosStyles(align: PosAlign.left, bold: true),
      );
      bytes += generator.text(
        '--------------------------------',
        styles: PosStyles(align: PosAlign.center),
      );

      // Agrupar productos
      final productosAgrupados = <String, Map<String, dynamic>>{};
      for (final item in _productosVendidos) {
        final key = item.nombre;
        if (productosAgrupados.containsKey(key)) {
          productosAgrupados[key]!['cantidad'] += item.cantidad;
          productosAgrupados[key]!['subtotal'] += item.subtotal;
          productosAgrupados[key]!['costo'] +=
              (item.precioUnitario * 0.6) * item.cantidad;
          productosAgrupados[key]!['descuento'] +=
              (item.precioUnitario * 0.1) * item.cantidad;
        } else {
          productosAgrupados[key] = {
            'item': item,
            'cantidad': item.cantidad,
            'subtotal': item.subtotal,
            'costo': (item.precioUnitario * 0.6) * item.cantidad,
            'descuento': (item.precioUnitario * 0.1) * item.cantidad,
          };
        }
      }

      // Imprimir cada producto
      for (final producto in productosAgrupados.values) {
        final item = producto['item'] as OrderItem;
        final cantidad = producto['cantidad'] as int;
        final subtotal = producto['subtotal'] as double;
        final costo = producto['costo'] as double;
        final descuento = producto['descuento'] as double;

        bytes += generator.text(
          item.nombre,
          styles: PosStyles(align: PosAlign.left, bold: true),
        );
        bytes += generator.text(
          'Cantidad: $cantidad',
          styles: PosStyles(align: PosAlign.left),
        );
        bytes += generator.text(
          'Precio Unit: \$${item.precioUnitario.toStringAsFixed(0)}',
          styles: PosStyles(align: PosAlign.left),
        );
        bytes += generator.text(
          'Costo: \$${costo.toStringAsFixed(0)}',
          styles: PosStyles(align: PosAlign.left),
        );
        bytes += generator.text(
          'Descuento: \$${descuento.toStringAsFixed(0)}',
          styles: PosStyles(align: PosAlign.left),
        );
        bytes += generator.text(
          'Total: \$${subtotal.toStringAsFixed(0)}',
          styles: PosStyles(align: PosAlign.left, bold: true),
        );
        bytes += generator.text(
          '- - - - - - - - - - - - - - - -',
          styles: PosStyles(align: PosAlign.center),
        );
      }

      // Footer
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        'TOTAL GENERAL: \$${_totalVentas.toStringAsFixed(0)}',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      );
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        'INVENTTIA - Sistema de Ventas',
        styles: PosStyles(align: PosAlign.center),
      );
      bytes += generator.emptyLines(3);
      bytes += generator.cut();

      // Enviar a la impresora
      bool result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      debugPrint('Error printing detailed summary: $e');
      return false;
    }
  }

  String _formatDateForPrint(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
        "${date.month.toString().padLeft(2, '0')}/"
        "${date.year} "
        "${date.hour.toString().padLeft(2, '0')}:"
        "${date.minute.toString().padLeft(2, '0')}";
  }

  Widget _buildUsdRateChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_money, size: 16, color: Color(0xFF4A90E2)),
          const SizedBox(width: 4),
          _isLoadingUsdRate
              ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4A90E2),
                ),
              )
              : Text(
                'USD: \$${_usdRate.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
        ],
      ),
    );
  }

  /// Calcular venta total en modo offline usando cache
  Future<void> _calcularVentaTotalOffline() async {
    try {
      print('📱 Calculando venta total desde cache offline...');

      final userPrefs = UserPreferencesService();

      // Cargar órdenes offline (sincronizadas + pendientes)
      _orderService.clearAllOrders();
      final offlineData = await userPrefs.getOfflineData();
      if (offlineData != null && offlineData['orders'] != null) {
        _orderService.transformSupabaseToOrdersPublic(
          offlineData['orders'] as List<dynamic>,
        );
      }

      final pendingOrders = await userPrefs.getPendingOrders();
      if (pendingOrders.isNotEmpty) {
        _orderService.addPendingOrdersToList(pendingOrders);
      }
      final offlineTotals = _calculatePendingOrdersTotals(pendingOrders);

      // Obtener resumen de cierre base desde cache
      final resumenCierre = await userPrefs.getResumenCierreCache();

      if (resumenCierre != null) {
        print('✅ Resumen de cierre cargado desde cache offline');
        print('📊 Datos disponibles: ${resumenCierre.keys.toList()}');

        // Obtener órdenes locales (offline)
        final orders = _orderService.orders;
        final productosVendidos = <OrderItem>[];
        final ordenesVendidas = <Order>[];

        // Filtrar órdenes completadas y offline
        for (final order in orders) {
          final isCompletedOrOffline =
              order.status == OrderStatus.completada ||
              order.status == OrderStatus.pagoConfirmado ||
              order.status == OrderStatus.pendienteDeSincronizacion ||
              order.status == OrderStatus.enviada;

          if (isCompletedOrOffline) {
            ordenesVendidas.add(order);
            for (final item in order.items) {
              productosVendidos.add(item);
            }
          }
        }

        setState(() {
          _productosVendidos = productosVendidos;
          _ordenesVendidas = ordenesVendidas;

          // Usar datos del resumen de cierre (ya incluye órdenes offline)
          // Mapear correctamente los nombres de campos del cache
          final ventasTotalesBase =
              (resumenCierre['ventas_totales'] ??
                      resumenCierre['total_ventas'] ??
                      0.0)
                  .toDouble();
          final productosBase =
              (resumenCierre['productos_vendidos'] ?? 0).toInt();

          final offlineVentas =
              (offlineTotals['ventasOffline'] ?? 0.0).toDouble();
          final offlineProductos =
              (offlineTotals['productosOffline'] ?? 0).toInt();
          final offlineEfectivo =
              (offlineTotals['efectivoOffline'] ?? 0.0).toDouble();

          // Calcular valores reales incluyendo pendientes offline
          final ventasTotales = ventasTotalesBase + offlineVentas;
          final efectivoReal =
              (resumenCierre['efectivo_real'] ??
                      resumenCierre['total_efectivo'] ??
                      ventasTotalesBase * 0.7)
                  .toDouble() +
              offlineEfectivo;

          // Egresado: ventas_totales - efectivo_real + egresos en efectivo
          _totalEgresado = ventasTotales - efectivoReal + _egresosEfectivo;

          // Efectivo real: efectivo_esperado - egresos en efectivo
          final efectivoEsperadoCache = resumenCierre['efectivo_esperado'];
          final efectivoEsperado =
              efectivoEsperadoCache != null
                  ? _parseDouble(efectivoEsperadoCache) + offlineEfectivo
                  : _parseDouble(resumenCierre['efectivo_inicial'] ?? 500.0) +
                      efectivoReal;

          _totalVentas = ventasTotales;
          _totalProductos = productosBase + offlineProductos;
          _totalEfectivoReal = efectivoEsperado - _egresosEfectivo;

          _isLoading = false;
        });

        print('💰 Datos calculados desde cache offline:');
        print('  - Ventas Totales: $_totalVentas');
        print('  - Productos Vendidos: $_totalProductos');
        print('  - Órdenes locales: ${orders.length}');
        print('  - Órdenes completadas/offline: ${ordenesVendidas.length}');
        print('  - Items vendidos: ${productosVendidos.length}');
        print(
          '  - Total Egresado: $_totalEgresado (incluye egresos efectivo: $_egresosEfectivo)',
        );
        print(
          '  - Efectivo Real: $_totalEfectivoReal (descontando egresos efectivo)',
        );

        // Mostrar información de órdenes offline si las hay
        if (pendingOrders.isNotEmpty) {
          print('📱 Órdenes offline incluidas en el cálculo:');
          print('  - Órdenes offline: ${pendingOrders.length}');
          print('  - Ventas offline: \$${offlineTotals['ventasOffline']}');
        }
      } else {
        print('⚠️ No hay resumen de cierre en cache - usando cálculo local');
        await _calcularVentaTotalLocalFallback();
      }
    } catch (e) {
      print('❌ Error calculando venta total offline: $e');
      await _calcularVentaTotalLocalFallback();
    }
  }

  /// Fallback: calcular usando solo órdenes locales
  Future<void> _calcularVentaTotalLocalFallback() async {
    try {
      print('🔄 Calculando venta total usando solo órdenes locales...');

      final orders = _orderService.orders;
      final productosVendidos = <OrderItem>[];
      final ordenesVendidas = <Order>[];
      double totalVentas = 0.0;
      int totalProductos = 0;

      for (final order in orders) {
        if (order.status == OrderStatus.completada ||
            order.status == OrderStatus.pagoConfirmado ||
            order.status == OrderStatus.pendienteDeSincronizacion ||
            order.status == OrderStatus.enviada) {
          ordenesVendidas.add(order);
          totalVentas += order.total;

          for (final item in order.items) {
            productosVendidos.add(item);
            totalProductos += item.cantidad;
          }
        }
      }

      setState(() {
        _productosVendidos = productosVendidos;
        _ordenesVendidas = ordenesVendidas;
        _totalVentas = totalVentas;
        _totalProductos = totalProductos;

        // Estimaciones básicas
        final efectivoEstimado = totalVentas * 0.7; // 70% efectivo
        _totalEgresado = totalVentas - efectivoEstimado + _egresosEfectivo;
        _totalEfectivoReal = efectivoEstimado - _egresosEfectivo;

        _isLoading = false;
      });

      print('💰 Datos calculados localmente (fallback):');
      print('  - Ventas Totales: $_totalVentas');
      print('  - Productos Vendidos: $_totalProductos');
      print('  - Órdenes completadas: ${ordenesVendidas.length}');
      print('  - Items vendidos: ${productosVendidos.length}');
    } catch (e) {
      print('❌ Error en cálculo local fallback: $e');
      setState(() {
        _isLoading = false;
        // Valores por defecto en caso de error total
        _totalVentas = 0.0;
        _totalProductos = 0;
        _productosVendidos = [];
        _ordenesVendidas = [];
        _totalEgresado = 0.0;
        _totalEfectivoReal = 0.0;
      });
    }
  }
}
