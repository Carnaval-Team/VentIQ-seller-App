import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/user_preferences_service.dart';
import '../services/pdf_service.dart';

class VentaTotalScreen extends StatefulWidget {
  const VentaTotalScreen({Key? key}) : super(key: key);

  @override
  State<VentaTotalScreen> createState() => _VentaTotalScreenState();
}

class _VentaTotalScreenState extends State<VentaTotalScreen> {
  final OrderService _orderService = OrderService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  List<OrderItem> _productosVendidos = [];
  List<Order> _ordenesVendidas = [];
  double _totalVentas = 0.0;
  int _totalProductos = 0;
  double _totalCosto = 0.0;
  double _totalDescuentos = 0.0;

  @override
  void initState() {
    super.initState();
    _calcularVentaTotal();
  }

  void _calcularVentaTotal() {
    final orders = _orderService.orders;
    final productosVendidos = <OrderItem>[];
    double total = 0.0;
    int totalProductos = 0;
    double totalCosto = 0.0;
    double totalDescuentos = 0.0;

    // Obtener solo órdenes completadas o con pago confirmado
    final ordersVendidas = orders.where((order) => 
      order.status == OrderStatus.completada || 
      order.status == OrderStatus.pagoConfirmado
    ).toList();

    for (final order in ordersVendidas) {
      productosVendidos.addAll(order.items);
      total += order.total;
      totalProductos += order.totalItems;
      
      // Calcular costos y descuentos estimados
      for (final item in order.items) {
        double costoPorProducto = item.precioUnitario * 0.6; // Estimamos 60% del precio como costo
        totalCosto += costoPorProducto * item.cantidad;
        
        double descuentoPorProducto = item.precioUnitario * 0.1; // Estimamos 10% como descuento promedio
        totalDescuentos += descuentoPorProducto * item.cantidad;
      }
    }

    setState(() {
      _productosVendidos = productosVendidos;
      _ordenesVendidas = ordersVendidas;
      _totalVentas = total;
      _totalProductos = totalProductos;
      _totalCosto = totalCosto;
      _totalDescuentos = totalDescuentos;
    });
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
            onPressed: _calcularVentaTotal,
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
                        'Costo Total',
                        '\$${_totalCosto.toStringAsFixed(0)}',
                        Icons.money_off,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildSummaryCard(
                        'Descuentos',
                        '\$${_totalDescuentos.toStringAsFixed(0)}',
                        Icons.discount,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Lista de órdenes vendidas
          Expanded(
            child: _ordenesVendidas.isEmpty 
                ? _buildEmptyState() 
                : _buildOrdersList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
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
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
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
          Icon(
            Icons.receipt_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
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
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
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
              children: _ordenesVendidas.map((order) => _buildOrderItem(order)).toList(),
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
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'pdf') {
                            _generarPdfResumenDetallado();
                          } else if (value == 'print') {
                            _imprimirResumenDetallado();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'pdf',
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Generar PDF'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'print',
                            child: Row(
                              children: [
                                Icon(Icons.print, color: Color(0xFF10B981)),
                                SizedBox(width: 8),
                                Text('Imprimir'),
                              ],
                            ),
                          ),
                        ],
                        icon: const Icon(
                          Icons.more_vert,
                          color: Color(0xFF4A90E2),
                        ),
                        tooltip: 'Opciones de reporte',
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          // Cliente
          Expanded(
            child: Text(
              order.buyerName ?? 'Sin nombre',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1F2937),
              ),
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
        productosAgrupados[key]!['costo'] += (item.precioUnitario * 0.6) * item.cantidad;
        productosAgrupados[key]!['descuento'] += (item.precioUnitario * 0.1) * item.cantidad;
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
        ...productosFinales.map((producto) => _buildDetailedProductItem(producto)),
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
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
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
      bool shouldPrint = await _printerService.showPrintConfirmationDialog(context, order);
      if (!shouldPrint) return;

      // Mostrar diálogo de selección de dispositivo
      final device = await _printerService.showDeviceSelectionDialog(context);
      if (device == null) return;

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
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
        _showErrorDialog('Error de Conexión', 'No se pudo conectar a la impresora.');
        return;
      }

      // Imprimir el ticket
      bool printed = await _printerService.printInvoice(order);
      Navigator.pop(context); // Cerrar diálogo de carga

      if (printed) {
        _showSuccessDialog('¡Ticket Impreso!', 'El ticket se ha impreso correctamente.');
      } else {
        _showErrorDialog('Error de Impresión', 'No se pudo imprimir el ticket.');
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
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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
        builder: (context) => const AlertDialog(
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
        _showErrorDialog('Error de Conexión', 'No se pudo conectar a la impresora.');
        return;
      }

      // Imprimir el resumen
      bool printed = await _printDetailedSummary();
      Navigator.pop(context);

      if (printed) {
        _showSuccessDialog('¡Resumen Impreso!', 'El resumen detallado se ha impreso correctamente.');
      } else {
        _showErrorDialog('Error de Impresión', 'No se pudo imprimir el resumen.');
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
      builder: (context) => AlertDialog(
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
            const Text('¿Deseas imprimir el resumen detallado de productos?'),
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
                  Text('Total Ventas: \$${_totalVentas.toStringAsFixed(0)}'),
                  Text('Costo Total: \$${_totalCosto.toStringAsFixed(0)}'),
                  Text('Descuentos: \$${_totalDescuentos.toStringAsFixed(0)}'),
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
    ) ?? false;
  }

  Future<bool> _printDetailedSummary() async {
    try {
      // Obtener información del vendedor
      final workerProfile = await _userPreferencesService.getWorkerProfile();
      final userEmail = await _userPreferencesService.getUserEmail();
      
      final sellerName = '${workerProfile['nombres'] ?? ''} ${workerProfile['apellidos'] ?? ''}'.trim();
      final sellerEmail = userEmail ?? 'Sin email';
      
      // Crear el contenido de impresión usando el formato ESC/POS
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // Header
      bytes += generator.text('VENTIQ', styles: PosStyles(align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('RESUMEN DE VENTAS', styles: PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('================================', styles: PosStyles(align: PosAlign.center));
      bytes += generator.emptyLines(1);

      // Información del vendedor y fecha
      final now = DateTime.now();
      bytes += generator.text('VENDEDOR: $sellerName', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('EMAIL: $sellerEmail', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('FECHA: ${_formatDateForPrint(now)}', styles: PosStyles(align: PosAlign.left));
      bytes += generator.emptyLines(1);

      // Resumen general
      bytes += generator.text('RESUMEN GENERAL:', styles: PosStyles(align: PosAlign.left, bold: true));
      bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));
      bytes += generator.text('Total Productos: $_totalProductos', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('Total Ventas: \$${_totalVentas.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('Costo Total: \$${_totalCosto.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left));
      bytes += generator.text('Descuentos: \$${_totalDescuentos.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left));
      bytes += generator.emptyLines(1);

      // Detalle de productos
      bytes += generator.text('DETALLE POR PRODUCTO:', styles: PosStyles(align: PosAlign.left, bold: true));
      bytes += generator.text('--------------------------------', styles: PosStyles(align: PosAlign.center));

      // Agrupar productos
      final productosAgrupados = <String, Map<String, dynamic>>{};
      for (final item in _productosVendidos) {
        final key = item.nombre;
        if (productosAgrupados.containsKey(key)) {
          productosAgrupados[key]!['cantidad'] += item.cantidad;
          productosAgrupados[key]!['subtotal'] += item.subtotal;
          productosAgrupados[key]!['costo'] += (item.precioUnitario * 0.6) * item.cantidad;
          productosAgrupados[key]!['descuento'] += (item.precioUnitario * 0.1) * item.cantidad;
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

        bytes += generator.text(item.nombre, styles: PosStyles(align: PosAlign.left, bold: true));
        bytes += generator.text('Cantidad: $cantidad', styles: PosStyles(align: PosAlign.left));
        bytes += generator.text('Precio Unit: \$${item.precioUnitario.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left));
        bytes += generator.text('Costo: \$${costo.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left));
        bytes += generator.text('Descuento: \$${descuento.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left));
        bytes += generator.text('Total: \$${subtotal.toStringAsFixed(0)}', styles: PosStyles(align: PosAlign.left, bold: true));
        bytes += generator.text('- - - - - - - - - - - - - - - -', styles: PosStyles(align: PosAlign.center));
      }

      // Footer
      bytes += generator.emptyLines(1);
      bytes += generator.text('TOTAL GENERAL: \$${_totalVentas.toStringAsFixed(0)}', 
                             styles: PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
      bytes += generator.emptyLines(1);
      bytes += generator.text('VENTIQ - Sistema de Ventas', styles: PosStyles(align: PosAlign.center));
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

  // Método para generar PDF del resumen detallado
  Future<void> _generarPdfResumenDetallado() async {
    try {
      // Mostrar diálogo de confirmación
      bool shouldGenerate = await _showPdfGenerationConfirmationDialog();
      if (!shouldGenerate) return;

      // Mostrar indicador de carga
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generando PDF...'),
            ],
          ),
        ),
      );

      // Generar el PDF
      final filePath = await PdfService.generateSalesReportPdf(
        productosVendidos: _productosVendidos,
        ordenesVendidas: _ordenesVendidas,
        totalVentas: _totalVentas,
        totalProductos: _totalProductos,
        totalCosto: _totalCosto,
        totalDescuentos: _totalDescuentos,
      );

      Navigator.pop(context); // Cerrar diálogo de carga

      if (filePath != null) {
        // Mostrar diálogo de éxito con opciones
        _showPdfSuccessDialog(filePath);
      } else {
        _showErrorDialog('Error de Generación', 'No se pudo generar el archivo PDF.');
      }
    } catch (e) {
      Navigator.pop(context); // Cerrar diálogo de carga si está abierto
      _showErrorDialog('Error', 'Ocurrió un error al generar el PDF: $e');
    }
  }

  Future<bool> _showPdfGenerationConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red),
            const SizedBox(width: 8),
            const Text('Generar PDF'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Deseas generar un PDF del resumen detallado de productos?'),
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
                  Text('📊 Total Productos: $_totalProductos'),
                  Text('💰 Total Ventas: \$${_totalVentas.toStringAsFixed(0)}'),
                  Text('📋 Órdenes: ${_ordenesVendidas.length}'),
                  const SizedBox(height: 8),
                  const Text(
                    '📄 El PDF se guardará en tu dispositivo y podrás compartirlo.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Generar PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showPdfSuccessDialog(String filePath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: const Color(0xFF10B981)),
            const SizedBox(width: 8),
            const Text('¡PDF Generado!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El resumen detallado se ha guardado exitosamente.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Archivo guardado en:\n${filePath.split('/').last}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              PdfService.openPdf(filePath, context);
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              PdfService.sharePdf(filePath, context);
            },
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
