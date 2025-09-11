import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/expense.dart';
import '../services/order_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/user_preferences_service.dart';
import '../services/turno_service.dart';

class VentaTotalScreen extends StatefulWidget {
  const VentaTotalScreen({Key? key}) : super(key: key);

  @override
  State<VentaTotalScreen> createState() => _VentaTotalScreenState();
}

class _VentaTotalScreenState extends State<VentaTotalScreen> {
  final OrderService _orderService = OrderService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
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

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadExpenses();
    await _calcularVentaTotal();
  }

  Future<void> _calcularVentaTotal() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Primero cargar las órdenes desde Supabase
      _orderService.clearAllOrders();
      await _orderService.listOrdersFromSupabase();

      // Obtener datos del turno abierto
      final turnoAbierto = await TurnoService.getTurnoAbierto();
      if (turnoAbierto == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Obtener preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTpv = await userPrefs.getIdTpv();
      final userID = await userPrefs.getUserId();

      if (idTpv != null) {
        // Llamar a la función de resumen diario
        final resumenCierre = await Supabase.instance.client.rpc(
          'fn_resumen_diario_cierre',
          params: {'id_tpv_param': idTpv, 'id_usuario_param': userID},
        );

        if (resumenCierre != null && resumenCierre is List && resumenCierre.isNotEmpty) {
          final data = resumenCierre[0];

          // Obtener órdenes locales para productos vendidos (ahora ya cargadas)
          final orders = _orderService.orders;
          final productosVendidos = <OrderItem>[];
          final ordenesVendidas = <Order>[];

          for (final order in orders) {
            if (order.status == OrderStatus.completada) {
              ordenesVendidas.add(order);
              for (final item in order.items) {
                productosVendidos.add(item);
              }
            }
          }

          setState(() {
            _productosVendidos = productosVendidos;
            _ordenesVendidas = ordenesVendidas;
            // Usar ventas_totales de la función
            _totalVentas = (data['ventas_totales'] ?? 0.0).toDouble();
            _totalProductos = (data['productos_vendidos'] ?? 0).toInt();

            // Calcular egresado: ventas_totales - efectivo_real + egresos en efectivo
            final ventasTotales = (data['ventas_totales'] ?? 0.0).toDouble();
            final efectivoReal = (data['efectivo_real'] ?? 0.0).toDouble();
            _totalEgresado = ventasTotales - efectivoReal + _egresosEfectivo;

            // Efectivo real: efectivo_esperado - egresos en efectivo
            final efectivoEsperado = (data['efectivo_esperado'] ?? 0.0).toDouble();
            _totalEfectivoReal = efectivoEsperado - _egresosEfectivo;

            _isLoading = false;
          });

          print('DEBUG - Venta Total Screen Data:');
          print('Ventas Totales: $_totalVentas');
          print('Productos Vendidos: $_totalProductos');
          print('Órdenes cargadas: ${orders.length}');
          print('Órdenes completadas: ${ordenesVendidas.length}');
          print('Productos vendidos: ${productosVendidos.length}');
          print('Total Egresado: $_totalEgresado (incluye egresos efectivo: $_egresosEfectivo)');
          print('Efectivo Real: $_totalEfectivoReal (descontando egresos efectivo)');
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
        if (order.status == OrderStatus.completada) {
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
      final expenses = await TurnoService.getEgresosEnriquecidos();

      // Calculate total expenses and separate by payment type
      double total = 0.0;
      double efectivo = 0.0;
      double transferencias = 0.0;

      for (final expense in expenses) {
        total += expense.montoEntrega;
        // Si esDigital es false explícitamente, es efectivo
        // Si esDigital es true o null, considerarlo como transferencia/digital
        if (expense.esDigital == false) {
          efectivo += expense.montoEntrega;
        } else {
          transferencias += expense.montoEntrega;
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
      body: Column(
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
                      child: _buildSummaryCard(
                        'Total Productos',
                        _totalProductos.toString(),
                        Icons.inventory,
                        const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Ventas',
                        '\$${_totalVentas.toStringAsFixed(0)}',
                        Icons.attach_money,
                        const Color(0xFF4A90E2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Egresado',
                        '\$${_totalEgresado.toStringAsFixed(0)}',
                        Icons.money_off,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Efectivo Real',
                        '\$${_totalEfectivoReal.toStringAsFixed(0)}',
                        Icons.account_balance_wallet,
                        Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de órdenes vendidas
          Expanded(
            child: _isLoading
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

    final productosFinales = productosAgrupados.values.toList();

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
                  'Cant.',
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
                  'Costo',
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
                  'Desc.',
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
    final cantidad = producto['cantidad'] as int;
    final subtotal = producto['subtotal'] as double;
    final costo = producto['costo'] as double;
    final descuento = producto['descuento'] as double;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          // Nombre del producto
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombre,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '\$${item.precioUnitario.toStringAsFixed(0)} c/u',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          // Cantidad
          Expanded(
            child: Text(
              cantidad.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Costo
          Expanded(
            child: Text(
              '\$${costo.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Descuento
          Expanded(
            child: Text(
              '\$${descuento.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Total
          Expanded(
            child: Text(
              '\$${subtotal.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A90E2),
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
      // Mostrar diálogo de confirmación
      bool shouldPrint = await _printerService.showPrintConfirmationDialog(
        context,
        order,
      );
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
                  Text('Conectando e imprimiendo...'),
                ],
              ),
            ),
      );

      // Conectar a la impresora
      bool connected = await _printerService.connectToDevice(device);
      if (!connected) {
        Navigator.pop(context); // Cerrar diálogo de carga
        _showErrorDialog(
          'Error de Conexión',
          'No se pudo conectar a la impresora.',
        );
        return;
      }

      // Imprimir el ticket
      bool printed = await _printerService.printInvoice(order);
      Navigator.pop(context); // Cerrar diálogo de carga

      if (printed) {
        _showSuccessDialog(
          '¡Ticket Impreso!',
          'El ticket se ha impreso correctamente.',
        );
      } else {
        _showErrorDialog(
          'Error de Impresión',
          'No se pudo imprimir el ticket.',
        );
      }

      // Desconectar
      await _printerService.disconnect();
    } catch (e) {
      Navigator.pop(context); // Cerrar diálogo de carga si está abierto
      _showErrorDialog('Error', 'Ocurrió un error al imprimir: $e');
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
        'VENTIQ',
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
        'VENTIQ - Sistema de Ventas',
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
}
