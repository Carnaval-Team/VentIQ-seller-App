import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/order_service.dart';

class VentaTotalScreen extends StatefulWidget {
  const VentaTotalScreen({Key? key}) : super(key: key);

  @override
  State<VentaTotalScreen> createState() => _VentaTotalScreenState();
}

class _VentaTotalScreenState extends State<VentaTotalScreen> {
  final OrderService _orderService = OrderService();
  List<OrderItem> _productosVendidos = [];
  double _totalVentas = 0.0;
  int _totalProductos = 0;

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

    // Obtener solo órdenes completadas o con pago confirmado
    final ordersVendidas = orders.where((order) => 
      order.status == OrderStatus.completada || 
      order.status == OrderStatus.pagoConfirmado
    ).toList();

    for (final order in ordersVendidas) {
      productosVendidos.addAll(order.items);
      total += order.total;
      totalProductos += order.totalItems;
    }

    setState(() {
      _productosVendidos = productosVendidos;
      _totalVentas = total;
      _totalProductos = totalProductos;
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'Total Ventas',
                        '\$${_totalVentas.toStringAsFixed(2)}',
                        Icons.attach_money,
                        const Color(0xFF4A90E2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Lista de productos vendidos
          Expanded(
            child: _productosVendidos.isEmpty 
                ? _buildEmptyState() 
                : _buildProductsList(),
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

  Widget _buildProductsList() {
    // Agrupar productos por nombre para mostrar cantidades totales
    final productosAgrupados = <String, Map<String, dynamic>>{};
    
    for (final item in _productosVendidos) {
      final key = item.nombre;
      if (productosAgrupados.containsKey(key)) {
        productosAgrupados[key]!['cantidad'] += item.cantidad;
        productosAgrupados[key]!['subtotal'] += item.subtotal;
      } else {
        productosAgrupados[key] = {
          'item': item,
          'cantidad': item.cantidad,
          'subtotal': item.subtotal,
        };
      }
    }

    final productosFinales = productosAgrupados.values.toList();

    return Column(
      children: [
        // Header de la lista
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: const Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Producto',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Cant.',
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
                  'Precio',
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
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
        
        // Lista de productos
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: productosFinales.length,
            itemBuilder: (context, index) {
              final producto = productosFinales[index];
              final item = producto['item'] as OrderItem;
              final cantidad = producto['cantidad'] as int;
              final subtotal = producto['subtotal'] as double;
              
              return _buildProductItem(item, cantidad, subtotal);
            },
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
                '\$${_totalVentas.toStringAsFixed(2)}',
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
    );
  }

  Widget _buildProductItem(OrderItem item, int cantidad, double subtotal) {
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
          // Nombre del producto
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.ubicacionAlmacen,
                  style: TextStyle(
                    fontSize: 12,
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Precio unitario
          Expanded(
            child: Text(
              '\$${item.precioUnitario.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF1F2937),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Subtotal
          Expanded(
            child: Text(
              '\$${subtotal.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 14,
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
}
