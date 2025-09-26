import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/turno_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sales_monitor_fab.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({Key? key}) : super(key: key);

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final OrderService _orderService = OrderService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  List<Order> _filteredOrders = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredOrders = _orderService.orders;
    _searchController.addListener(_onSearchChanged);
    // Cargar órdenes desde Supabase
    _loadOrdersFromSupabase();
  }

  Future<void> _loadOrdersFromSupabase() async {
    // Limpiar órdenes antes de cargar las nuevas para evitar mezclar usuarios
    _orderService.clearAllOrders();

    await _orderService.listOrdersFromSupabase();
    // Actualizar la UI después de cargar las órdenes
    if (mounted) {
      setState(() {
        _filteredOrders = _orderService.orders;
      });
    }
  }

  Future<void> _refreshOrders() async {
    // Recargar órdenes desde Supabase
    await _loadOrdersFromSupabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterOrders();
    });
  }

  void _filterOrders() {
    final allOrders = _orderService.orders;
    List<Order> filtered;

    if (_searchQuery.isEmpty) {
      // Crear una nueva lista para evitar modificar la original
      filtered = List<Order>.from(allOrders);
    } else {
      filtered =
          allOrders.where((order) {
            final buyerName = order.buyerName?.toLowerCase() ?? '';
            final buyerPhone = order.buyerPhone?.toLowerCase() ?? '';
            return buyerName.contains(_searchQuery) ||
                buyerPhone.contains(_searchQuery);
          }).toList();
    }

    // Ordenar por prioridad de estado y luego por fecha
    filtered.sort((a, b) {
      final aPriority = _getStatusPriority(a.status);
      final bPriority = _getStatusPriority(b.status);

      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }

      // Si tienen la misma prioridad, ordenar por fecha (más recientes primero)
      return b.fechaCreacion.compareTo(a.fechaCreacion);
    });

    _filteredOrders = filtered;
  }

  int _getStatusPriority(OrderStatus status) {
    switch (status) {
      case OrderStatus.enviada:
      case OrderStatus.procesando:
        return 1; // Pendientes - prioridad alta
      case OrderStatus.pagoConfirmado:
        return 2; // Pago confirmado - prioridad media
      case OrderStatus.completada:
      case OrderStatus.cancelada:
      case OrderStatus.devuelta:
        return 3; // Finalizadas - prioridad baja
      case OrderStatus.borrador:
        return 0; // Borradores - prioridad más alta
    }
  }

  @override
  Widget build(BuildContext context) {
    _filterOrders();
    final orders = _filteredOrders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshOrders,
            tooltip: 'Actualizar órdenes',
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshOrders,
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child:
                  orders.isEmpty
                      ? _buildEmptyState()
                      : _buildOrdersList(orders),
            ),
          ],
        ),
      ),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 2, // Órdenes tab
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: const SalesMonitorFAB(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o teléfono del cliente...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFF4A90E2)),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4A90E2)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.list_alt_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No tienes órdenes aún',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Crea tu primera orden desde el catálogo',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _onBottomNavTap(0), // Ir a Home
            icon: const Icon(Icons.home),
            label: const Text('Ir al Catálogo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<Order> orders) {
    if (orders.isEmpty) return _buildEmptyState();

    // Agrupar órdenes por estado
    final pendingOrders =
        orders.where((o) => _getStatusPriority(o.status) == 1).toList();
    final paymentConfirmedOrders =
        orders.where((o) => _getStatusPriority(o.status) == 2).toList();
    final completedOrders =
        orders.where((o) => _getStatusPriority(o.status) == 3).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Órdenes pendientes
        if (pendingOrders.isNotEmpty) ...[
          _buildSectionHeader('Órdenes Pendientes', pendingOrders.length),
          ...pendingOrders.map((order) => _buildOrderCard(order)),
        ],

        // Órdenes con pago confirmado
        if (paymentConfirmedOrders.isNotEmpty) ...[
          if (pendingOrders.isNotEmpty) const SizedBox(height: 16),
          _buildSectionHeader('Pago Confirmado', paymentConfirmedOrders.length),
          ...paymentConfirmedOrders.map((order) => _buildOrderCard(order)),
        ],

        // Órdenes completadas/finalizadas
        if (completedOrders.isNotEmpty) ...[
          if (pendingOrders.isNotEmpty || paymentConfirmedOrders.isNotEmpty)
            const SizedBox(height: 16),
          _buildSectionHeader('Completadas', completedOrders.length),
          ...completedOrders.map((order) => _buildOrderCard(order)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A90E2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final statusColor = _getStatusColor(order.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con ID y estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      order.id,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      order.status.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Cliente y fecha
              Row(
                children: [
                  if (order.buyerName != null) ...[
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.buyerName!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(order.fechaCreacion),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Información de productos y total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    '\$${order.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A90E2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Preview de productos y botón de impresión
              if (order.items.isNotEmpty) ...[
                const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Productos: ${order.items.take(2).map((item) => item.nombre).join(', ')}${order.items.length > 2 ? '...' : ''}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Botón de impresión pequeño para órdenes con pago confirmado o completadas
                    if (order.status == OrderStatus.pagoConfirmado ||
                        order.status == OrderStatus.completada)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        child: InkWell(
                          onTap: () => _printOrder(order),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4A90E2).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF4A90E2).withOpacity(0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.print,
                              size: 16,
                              color: Color(0xFF4A90E2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.borrador:
        return Colors.orange;
      case OrderStatus.enviada:
        return const Color(0xFF4A90E2);
      case OrderStatus.procesando:
        return Colors.amber;
      case OrderStatus.completada:
        return Colors.green;
      case OrderStatus.cancelada:
        return Colors.red;
      case OrderStatus.devuelta:
        return const Color(0xFFFF6B35);
      case OrderStatus.pagoConfirmado:
        return const Color(0xFF10B981);
    }
  }

  String _formatDate(DateTime date) {
    // Convert to local time if it's not already
    final localDate = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(localDate);

    if (difference.inDays == 0) {
      return 'Hoy ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Ayer ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} días atrás';
    } else {
      return '${localDate.day}/${localDate.month}/${localDate.year}';
    }
  }

  void _showOrderDetails(Order order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.5,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Detalles de ${order.id}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Content
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Información general
                            _buildDetailRow(
                              'Estado:',
                              order.status.displayName,
                            ),
                            _buildDetailRow(
                              'Fecha:',
                              _formatDate(order.fechaCreacion),
                            ),
                            _buildDetailRow(
                              'Total productos:',
                              '${order.totalItems}',
                            ),
                            _buildDetailRow(
                              'Total:',
                              '\$${order.total.toStringAsFixed(2)}',
                            ),

                            // Desglose de pagos
                            if (order.operationId != null) ...[
                              const SizedBox(height: 16),
                              _buildPaymentBreakdown(order.operationId!),
                            ],

                            // Datos del cliente
                            if (order.buyerName != null ||
                                order.buyerPhone != null) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Datos del Cliente:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (order.buyerName != null)
                                _buildDetailRow('Nombre:', order.buyerName!),
                              if (order.buyerPhone != null)
                                _buildDetailRow('Teléfono:', order.buyerPhone!),
                              if (order.extraContacts != null &&
                                  order.extraContacts!.isNotEmpty)
                                _buildDetailRow(
                                  'Contactos extra:',
                                  order.extraContacts!,
                                ),
                              // if (order.paymentMethod != null)
                              //   _buildDetailRow(
                              //     'Método de pago:',
                              //     order.paymentMethod!,
                              //   ),
                            ],

                            const SizedBox(height: 16),
                            const Text(
                              'Productos:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Lista de productos (filtrar productos con precio 0)
                            ...order.items.where((item) => item.subtotal > 0).map(
                              (item) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
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
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Cantidad: ${item.cantidad} • ${item.ubicacionAlmacen}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        Text(
                                          '\$${item.subtotal.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF4A90E2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Botones de acción
                            const SizedBox(height: 24),
                            _buildActionButtons(order),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildActionButtons(Order order) {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 16),
        const Text(
          'Acciones:',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),

        // Botón de imprimir (siempre disponible para órdenes con pago confirmado o completadas)
        if (order.status == OrderStatus.pagoConfirmado ||
            order.status == OrderStatus.completada) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _printOrder(order),
              icon: const Icon(Icons.print),
              label: const Text('Imprimir Factura'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Botones de gestión solo para órdenes que no estén en estado final
        if (order.status != OrderStatus.cancelada &&
            order.status != OrderStatus.devuelta &&
            order.status != OrderStatus.completada) ...[
          Row(
            children: [
              // Botón Cancelar
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      () => _showConfirmationDialog(
                        order,
                        OrderStatus.cancelada,
                        'Cancelar Orden',
                        '¿Estás seguro de que quieres cancelar esta orden?',
                        Colors.red,
                      ),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón Devolver
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      () => _showConfirmationDialog(
                        order,
                        OrderStatus.devuelta,
                        'Devolver Orden',
                        '¿Estás seguro de que quieres marcar esta orden como devuelta?',
                        const Color(0xFFFF6B35),
                      ),
                  icon: const Icon(Icons.keyboard_return),
                  label: const Text('Devolver'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    side: const BorderSide(color: Color(0xFFFF6B35)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Botón Confirmar Pago (ancho completo)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  () => _showConfirmationDialog(
                    order,
                    OrderStatus.pagoConfirmado,
                    'Confirmar Pago',
                    '¿Confirmas que el pago de esta orden ha sido recibido?',
                    const Color(0xFF10B981),
                  ),
              icon: const Icon(Icons.payment),
              label: const Text('Confirmar Pago'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showConfirmationDialog(
    Order order,
    OrderStatus newStatus,
    String title,
    String message,
    Color color,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  _updateOrderStatus(order, newStatus);
                  Navigator.pop(context); // Cerrar diálogo
                  Navigator.pop(context); // Cerrar modal de detalles
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    );
  }

  Future<void> _updateOrderStatus(Order order, OrderStatus newStatus) async {
    // Mostrar indicador de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF4A90E2)),
                SizedBox(height: 16),
                Text('Actualizando estado...'),
              ],
            ),
          ),
    );

    try {
      // Llamar al servicio actualizado que ahora es async
      final result = await _orderService.updateOrderStatus(order.id, newStatus);

      // Cerrar indicador de carga
      Navigator.pop(context);

      if (result['success'] == true) {
        // Actualizar la UI solo si fue exitoso
        setState(() {
          _filterOrders(); // Actualizar la lista filtrada
        });

        String statusMessage = '';
        switch (newStatus) {
          case OrderStatus.cancelada:
            statusMessage = 'Orden cancelada exitosamente';
            break;
          case OrderStatus.devuelta:
            statusMessage = 'Orden marcada como devuelta';
            break;
          case OrderStatus.pagoConfirmado:
            statusMessage = 'Pago confirmado exitosamente';
            // Verificar si la impresión está habilitada antes de mostrar el diálogo
            _checkAndShowPrintDialog(order);
            break;
          default:
            statusMessage = 'Estado actualizado correctamente';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(statusMessage), backgroundColor: Colors.green),
        );
      } else {
        // Mostrar error si falló la actualización
        _showErrorDialog(
          'Error al actualizar estado',
          result['error'] ?? 'No se pudo actualizar el estado de la orden',
        );
      }
    } catch (e) {
      // Cerrar indicador de carga si hay excepción
      Navigator.pop(context);

      _showErrorDialog(
        'Error de conexión',
        'No se pudo conectar con el servidor. Verifica tu conexión a internet.',
      );

      print('Error en _updateOrderStatus: $e');
    }
  }

  Widget _buildPaymentBreakdown(int operationId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _orderService.getSalePayments(operationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Desglose de Pagos:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('Cargando desglose de pagos...'),
                  ],
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Desglose de Pagos:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: const Text(
                  'No hay información de pagos disponible',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          );
        }

        final payments = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Desglose de Pagos:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            ...payments.map(
              (payment) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    // Icono del método de pago
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _getPaymentMethodColor(payment),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        _getPaymentMethodIcon(payment),
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Información del pago
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getCustomPaymentMethodName(payment),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          if (payment['referencia_pago'] != null &&
                              payment['referencia_pago']
                                  .toString()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Ref: ${payment['referencia_pago']}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Monto
                    Text(
                      '\$${(payment['monto'] ?? 0.0).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4A90E2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _getPaymentMethodColor(Map<String, dynamic> payment) {
    final esEfectivo = payment['medio_pago_es_efectivo'] ?? false;
    final esDigital = payment['medio_pago_es_digital'] ?? false;

    if (esEfectivo) {
      return Colors.green;
    } else if (esDigital) {
      return Colors.blue;
    } else {
      return Colors.orange;
    }
  }

  IconData _getPaymentMethodIcon(Map<String, dynamic> payment) {
    final esEfectivo = payment['medio_pago_es_efectivo'] ?? false;
    final esDigital = payment['medio_pago_es_digital'] ?? false;

    if (esEfectivo) {
      return Icons.payments;
    } else if (esDigital) {
      return Icons.credit_card;
    } else {
      return Icons.account_balance;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/categories',
          (route) => false,
        );
        break;
      case 1: // Preorden
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2: // Órdenes (current)
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  /// Verificar configuración de impresión y mostrar diálogo si está habilitada
  Future<void> _checkAndShowPrintDialog(Order order) async {
    print('DEBUG: Verificando configuración de impresión para orden ${order.id}');
    
    // Verificar si la impresión está habilitada
    final isPrintEnabled = await _userPreferencesService.isPrintEnabled();
    print('DEBUG: Impresión habilitada: $isPrintEnabled');
    
    if (isPrintEnabled) {
      print('DEBUG: Impresión habilitada - Mostrando diálogo de impresión');
      // Agregar un pequeño delay para asegurar que el contexto esté disponible
      Future.delayed(Duration(milliseconds: 500), () {
        _showPrintDialog(order);
      });
    } else {
      print('DEBUG: Impresión deshabilitada - No se muestra diálogo de impresión');
    }
  }

  /// Mostrar diálogo de impresión después de confirmar pago
  Future<void> _showPrintDialog(Order order) async {
    print('DEBUG: Iniciando _showPrintDialog para orden ${order.id}');

    // Mostrar diálogo de confirmación de impresión
    print('DEBUG: Mostrando diálogo de confirmación de impresión');
    bool shouldPrint = await _printerService.showPrintConfirmationDialog(
      context,
      order,
    );
    print('DEBUG: Resultado del diálogo de confirmación: $shouldPrint');

    if (!shouldPrint) return;

    // Mostrar diálogo de selección de impresora
    var selectedDevice = await _printerService.showDeviceSelectionDialog(
      context,
    );

    if (selectedDevice == null) return;

    // Mostrar diálogo de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF4A90E2)),
                SizedBox(height: 16),
                Text('Conectando a impresora...'),
              ],
            ),
          ),
    );

    try {
      // Conectar a la impresora
      bool connected = await _printerService.connectToDevice(selectedDevice);

      if (!connected) {
        Navigator.pop(context); // Cerrar diálogo de progreso
        _showErrorDialog(
          'Error de Conexión',
          'No se pudo conectar a la impresora. Verifica que esté encendida y en rango.',
        );
        return;
      }

      // Actualizar mensaje de progreso
      Navigator.pop(context); // Cerrar diálogo anterior
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Imprimiendo factura...'),
                ],
              ),
            ),
      );

      // Imprimir la factura
      bool printed = await _printerService.printInvoice(order);

      Navigator.pop(context); // Cerrar diálogo de progreso

      if (printed) {
        _showSuccessDialog(
          '¡Factura Impresa!',
          'La factura de la orden ${order.id} se ha impreso correctamente.',
        );
      } else {
        _showErrorDialog(
          'Error de Impresión',
          'No se pudo imprimir la factura. Verifica la conexión con la impresora.',
        );
      }

      // Desconectar de la impresora
      await _printerService.disconnect();
    } catch (e) {
      Navigator.pop(context); // Cerrar diálogo de progreso si está abierto
      _showErrorDialog('Error', 'Ocurrió un error durante la impresión: $e');
      await _printerService.disconnect();
    }
  }

  /// Mostrar diálogo de error
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
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

  /// Mostrar diálogo de éxito
  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('¡Genial!'),
              ),
            ],
          ),
    );
  }

  /// Imprimir orden individual
  Future<void> _printOrder(Order order) async {
    try {
      // Mostrar diálogo de confirmación de impresión
      bool shouldPrint = await _printerService.showPrintConfirmationDialog(
        context,
        order,
      );
      if (!shouldPrint) return;

      // Mostrar diálogo de selección de impresora
      var selectedDevice = await _printerService.showDeviceSelectionDialog(
        context,
      );
      if (selectedDevice == null) return;

      // Mostrar diálogo de progreso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Conectando a impresora...'),
                ],
              ),
            ),
      );

      // Conectar a la impresora
      bool connected = await _printerService.connectToDevice(selectedDevice);

      if (!connected) {
        Navigator.pop(context); // Cerrar diálogo de progreso
        _showErrorDialog(
          'Error de Conexión',
          'No se pudo conectar a la impresora. Verifica que esté encendida y en rango.',
        );
        return;
      }

      // Actualizar mensaje de progreso
      Navigator.pop(context); // Cerrar diálogo anterior
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4A90E2)),
                  SizedBox(height: 16),
                  Text('Imprimiendo factura...'),
                ],
              ),
            ),
      );

      // Imprimir la factura
      bool printed = await _printerService.printInvoice(order);

      Navigator.pop(context); // Cerrar diálogo de progreso

      if (printed) {
        _showSuccessDialog(
          '¡Factura Impresa!',
          'La factura de la orden ${order.id} se ha impreso correctamente.',
        );
      } else {
        _showErrorDialog(
          'Error de Impresión',
          'No se pudo imprimir la factura. Verifica la conexión con la impresora.',
        );
      }

      // Desconectar de la impresora
      await _printerService.disconnect();
    } catch (e) {
      Navigator.pop(context); // Cerrar diálogo de progreso si está abierto
      _showErrorDialog('Error', 'Ocurrió un error durante la impresión: $e');
      await _printerService.disconnect();
    }
  }

  // Personalizar nombres de métodos de pago para el desglose
  String _getCustomPaymentMethodName(Map<String, dynamic> payment) {
    final mediopagoId = payment['medio_pago_id'];
    
    if (mediopagoId == 1) {
      return 'Dinero en efectivo';
    } else {
      return 'Transferencia';
    }
  }
}
