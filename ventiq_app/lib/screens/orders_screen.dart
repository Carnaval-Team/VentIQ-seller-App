import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/printer_manager.dart';
import '../services/user_preferences_service.dart';
import '../utils/platform_utils.dart';
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
  final PrinterManager _printerManager = PrinterManager();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final TextEditingController _searchController = TextEditingController();
  List<Order> _filteredOrders = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _filteredOrders = _orderService.orders;
    _searchController.addListener(_onSearchChanged);
    // Cargar órdenes desde Supabase y órdenes pendientes offline
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrdersFromSupabase();
    });
  }

  Future<void> _loadOrdersFromSupabase() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Preservando cambios locales y recargando...');
        
        // Guardar cambios de estado locales antes de limpiar
        final localStateChanges = <String, OrderStatus>{};
        final pendingOperations = await _userPreferencesService.getPendingOperations();
        
        // Identificar órdenes que han sido modificadas offline
        for (final order in _orderService.orders) {
          // Capturar órdenes pendientes de sincronización
          if (order.status == OrderStatus.pendienteDeSincronizacion) {
            localStateChanges[order.id] = order.status;
          }
          
          // Capturar órdenes que tienen operaciones pendientes de cambio de estado
          for (final operation in pendingOperations) {
            if (operation['type'] == 'order_status_change' && 
                operation['order_id'] == order.id) {
              final newStatusString = operation['new_status'] as String;
              final newStatus = _stringToOrderStatus(newStatusString);
              if (newStatus != null) {
                localStateChanges[order.id] = newStatus;
                print('📋 Cambio de estado offline detectado: ${order.id} -> $newStatusString');
              }
              break;
            }
          }
        }
        
        // Limpiar órdenes antes de cargar las nuevas
        _orderService.clearAllOrders();
        
        // Cargar órdenes sincronizadas desde cache
        final offlineData = await _userPreferencesService.getOfflineData();
        if (offlineData != null && offlineData['orders'] != null) {
          final ordersData = offlineData['orders'] as List<dynamic>;
          _orderService.transformSupabaseToOrdersPublic(ordersData);
          print('✅ Órdenes sincronizadas cargadas desde cache: ${ordersData.length}');
        }
        
        // Cargar órdenes pendientes de sincronización
        final pendingOrders = await _userPreferencesService.getPendingOrders();
        if (pendingOrders.isNotEmpty) {
          _orderService.addPendingOrdersToList(pendingOrders);
          print('⏳ Órdenes pendientes de sincronización: ${pendingOrders.length}');
        }
        
        // Aplicar cambios de estado offline después de cargar todas las órdenes
        if (localStateChanges.isNotEmpty) {
          print('🔄 Aplicando ${localStateChanges.length} cambios de estado offline...');
          for (final entry in localStateChanges.entries) {
            final orderId = entry.key;
            final newStatus = entry.value;
            
            final orderIndex = _orderService.orders.indexWhere((order) => order.id == orderId);
            if (orderIndex != -1) {
              final currentOrder = _orderService.orders[orderIndex];
              
              // Solo actualizar si el estado actual es diferente al cambio offline
              if (currentOrder.status != newStatus) {
                final updatedOrder = currentOrder.copyWith(status: newStatus);
                _orderService.orders[orderIndex] = updatedOrder;
                print('🔄 Estado aplicado: $orderId -> ${currentOrder.status} → ${newStatus.toString()}');
              } else {
                print('ℹ️ Estado ya correcto: $orderId -> ${newStatus.toString()}');
              }
            } else {
              print('⚠️ Orden no encontrada para restaurar estado: $orderId');
            }
          }
          
          // Verificar si hay operaciones pendientes que necesitan ser aplicadas
          final hasChanges = await _applyPendingStatusChanges();
          
          // Actualizar UI después de aplicar todos los cambios
          if (hasChanges) {
            print('🔄 Forzando actualización de UI después de cambios de estado...');
            setState(() {
              _filteredOrders = List.from(_orderService.orders);
              _filterOrders(); // Re-aplicar filtros si los hay
            });
          }
        }
        
      } else {
        print('🌐 Modo online - Cargando órdenes desde Supabase...');
        // Limpiar órdenes antes de cargar las nuevas para evitar mezclar usuarios
        _orderService.clearAllOrders();
        await _orderService.listOrdersFromSupabase();
        print('✅ Órdenes cargadas desde Supabase');
      }
      
      // Actualizar la UI después de cargar las órdenes
      if (mounted) {
        setState(() {
          _filteredOrders = _orderService.orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando órdenes: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      case OrderStatus.pendienteDeSincronizacion:
        return 0; // Órdenes offline - prioridad máxima
      case OrderStatus.borrador:
        return 1; // Borradores - prioridad muy alta
      case OrderStatus.enviada:
      case OrderStatus.procesando:
        return 2; // Pendientes - prioridad alta
      case OrderStatus.pagoConfirmado:
        return 3; // Pago confirmado - prioridad media
      case OrderStatus.completada:
      case OrderStatus.cancelada:
      case OrderStatus.devuelta:
        return 4; // Finalizadas - prioridad baja
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
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A90E2)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cargando órdenes...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
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

    // Agrupar órdenes por prioridad actualizada
    final offlineOrders =
        orders.where((o) => _getStatusPriority(o.status) == 0).toList(); // Pendientes de sincronización
    final draftOrders =
        orders.where((o) => _getStatusPriority(o.status) == 1).toList(); // Borradores
    final pendingOrders =
        orders.where((o) => _getStatusPriority(o.status) == 2).toList(); // Enviadas/Procesando
    final paymentConfirmedOrders =
        orders.where((o) => _getStatusPriority(o.status) == 3).toList(); // Pago confirmado
    final completedOrders =
        orders.where((o) => _getStatusPriority(o.status) == 4).toList(); // Completadas/Canceladas

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Órdenes offline pendientes de sincronización
        if (offlineOrders.isNotEmpty) ...[
          _buildSectionHeader('⏳ Pendientes de Sincronización', offlineOrders.length),
          ...offlineOrders.map((order) => _buildOrderCard(order)),
          const SizedBox(height: 16),
        ],

        // Órdenes borrador
        if (draftOrders.isNotEmpty) ...[
          _buildSectionHeader('📝 Borradores', draftOrders.length),
          ...draftOrders.map((order) => _buildOrderCard(order)),
          const SizedBox(height: 16),
        ],

        // Órdenes pendientes
        if (pendingOrders.isNotEmpty) ...[
          _buildSectionHeader('📋 Órdenes Pendientes', pendingOrders.length),
          ...pendingOrders.map((order) => _buildOrderCard(order)),
          const SizedBox(height: 16),
        ],

        // Órdenes con pago confirmado
        if (paymentConfirmedOrders.isNotEmpty) ...[
          _buildSectionHeader('💰 Pago Confirmado', paymentConfirmedOrders.length),
          ...paymentConfirmedOrders.map((order) => _buildOrderCard(order)),
          const SizedBox(height: 16),
        ],

        // Órdenes completadas/finalizadas
        if (completedOrders.isNotEmpty) ...[
          _buildSectionHeader('✅ Completadas', completedOrders.length),
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
      case OrderStatus.pendienteDeSincronizacion:
        return const Color(0xFFFF8C00); // Naranja oscuro para offline
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
                    OrderStatus.completada,
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
  ) async {
    // Verificar si es cancelación y si se requiere contraseña maestra
    if (newStatus == OrderStatus.cancelada) {
      try {
        final storeConfig = await _userPreferencesService.getStoreConfig();
        if (storeConfig != null && storeConfig['need_master_password_to_cancel'] == true) {
          _showMasterPasswordDialog(order, newStatus, title, message, color);
          return;
        }
      } catch (e) {
        print('❌ Error al verificar configuración de contraseña maestra: $e');
        // Continuar con el flujo normal si hay error en la configuración
      }
    }

    // Flujo normal para otros estados o cuando no se requiere contraseña maestra
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
      builder: (context) => AlertDialog(
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

  /// Verificar configuración de Impresión y mostrar diálogo si está habilitada
  Future<void> _checkAndShowPrintDialog(Order order) async {
    print('DEBUG: Verificando configuración de Impresión para orden ${order.id}');
    
    // Verificar si la Impresión está habilitada
    final isPrintEnabled = await _userPreferencesService.isPrintEnabled();
    print('DEBUG: Impresión habilitada: $isPrintEnabled');
    
    if (isPrintEnabled) {
      print('DEBUG: Impresión habilitada - Usando PrinterManager');
      print(' Plataforma detectada: ${PlatformUtils.isWeb ? "Web" : "Móvil"}');
      
      // Usar PrinterManager que decide automáticamente el tipo de Impresión
      Future.delayed(Duration(milliseconds: 500), () {
        _printOrderWithManager(order);
      });
    } else {
      print('DEBUG: Impresión deshabilitada - No se muestra diálogo de Impresión');
    }
  }

  /// Imprimir orden usando PrinterManager (detecta automáticamente la plataforma)
  Future<void> _printOrderWithManager(Order order) async {
    try {
      print('🖨️ Iniciando impresión con PrinterManager para orden ${order.id}');
      
      // Usar PrinterManager que maneja automáticamente web vs móvil
      final result = await _printerManager.printInvoice(context, order);
      
      if (result.success) {
        _showSuccessDialog(
          '¡Factura Impresa!',
          result.message,
        );
        print('✅ ${result.message} (${result.platform})');
      } else {
        _showErrorDialog(
          'Error de Impresión',
          result.message,
        );
        print('❌ ${result.message} (${result.platform})');
      }
      
      if (result.details != null) {
        print('ℹ️ Detalles: ${result.details}');
      }
      
    } catch (e) {
      _showErrorDialog('Error', 'Ocurrió un error durante la impresión: $e');
      print('❌ Error en _printOrderWithManager: $e');
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

  /// Imprimir orden individual (usa PrinterManager para detectar plataforma)
  Future<void> _printOrder(Order order) async {
    // Usar el mismo método unificado para impresión manual
    await _printOrderWithManager(order);
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

  // Convertir string a OrderStatus
  OrderStatus? _stringToOrderStatus(String statusString) {
    switch (statusString.toLowerCase()) {
      case 'borrador':
        return OrderStatus.borrador;
      case 'enviada':
        return OrderStatus.enviada;
      case 'pagoconfirmado':
      case 'pago_confirmado':
        return OrderStatus.pagoConfirmado;
      case 'completada':
        return OrderStatus.completada;
      case 'cancelada':
        return OrderStatus.cancelada;
      case 'devuelta':
        return OrderStatus.devuelta;
      case 'pendientedesincronizacion':
      case 'pendiente_de_sincronizacion':
        return OrderStatus.pendienteDeSincronizacion;
      default:
        print('⚠️ Estado no reconocido: $statusString');
        return null;
    }
  }

  /// Aplicar cambios de estado pendientes que no se han sincronizado
  Future<bool> _applyPendingStatusChanges() async {
    try {
      final pendingOperations = await _userPreferencesService.getPendingOperations();
      
      if (pendingOperations.isEmpty) {
        print('ℹ️ No hay operaciones pendientes de cambio de estado');
        return false;
      }
      
      print('🔄 Aplicando ${pendingOperations.length} operaciones pendientes...');
      bool hasChanges = false;
      
      for (final operation in pendingOperations) {
        if (operation['type'] == 'order_status_change') {
          final orderId = operation['order_id'] as String;
          final newStatusString = operation['new_status'] as String;
          final newStatus = _stringToOrderStatus(newStatusString);
          
          if (newStatus != null) {
            final orderIndex = _orderService.orders.indexWhere((order) => order.id == orderId);
            if (orderIndex != -1) {
              final currentOrder = _orderService.orders[orderIndex];
              
              // Aplicar el cambio de estado pendiente
              if (currentOrder.status != newStatus) {
                final updatedOrder = currentOrder.copyWith(status: newStatus);
                _orderService.orders[orderIndex] = updatedOrder;
                hasChanges = true;
                print('🔄 Operación pendiente aplicada: $orderId -> ${currentOrder.status} → ${newStatus.toString()}');
                print('🎯 Estado final confirmado: ${_orderService.orders[orderIndex].status}');
              } else {
                print('ℹ️ Estado ya aplicado: $orderId -> ${newStatus.toString()}');
              }
            } else {
              print('⚠️ Orden no encontrada para operación pendiente: $orderId');
            }
          }
        }
      }
      
      if (hasChanges) {
        print('✅ Se aplicaron cambios de estado - UI será actualizada');
      }
      
      return hasChanges;
      
    } catch (e) {
      print('❌ Error aplicando cambios de estado pendientes: $e');
      return false;
    }
  }

  void _showMasterPasswordDialog(
    Order order,
    OrderStatus newStatus,
    String title,
    String message,
    Color color,
  ) {
    final TextEditingController passwordController = TextEditingController();
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.vpn_key,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Contraseña Maestra',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresa la contraseña maestra para cancelar esta orden.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña Maestra',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final enteredPassword = passwordController.text.trim();
                if (enteredPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa la contraseña'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                // Verificar la contraseña
                try {
                  final storeConfig = await _userPreferencesService.getStoreConfig();
                  final storedPassword = storeConfig?['master_password'];
                  
                  if (storedPassword == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No hay contraseña maestra configurada'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Encriptar la contraseña ingresada para compararla
                  final bytes = utf8.encode(enteredPassword);
                  final digest = sha256.convert(bytes);
                  final encryptedEnteredPassword = digest.toString();

                  if (encryptedEnteredPassword == storedPassword) {
                    // Contraseña correcta - proceder con la cancelación
                    Navigator.pop(context); // Cerrar diálogo de contraseña
                    Navigator.pop(context); // Cerrar modal de detalles
                    _updateOrderStatus(order, newStatus);
                  } else {
                    // Contraseña incorrecta
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Contraseña incorrecta'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } catch (e) {
                  print('❌ Error al verificar contraseña maestra: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al verificar contraseña: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}
