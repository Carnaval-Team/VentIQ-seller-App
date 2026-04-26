import 'package:flutter/material.dart';
import '../services/carnaval_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/carnaval_order_detail_sheet.dart';
import 'carnaval_orders_dashboard_screen.dart';

class CarnavalOrdersScreen extends StatefulWidget {
  const CarnavalOrdersScreen({Key? key}) : super(key: key);

  @override
  State<CarnavalOrdersScreen> createState() => _CarnavalOrdersScreenState();
}

class _CarnavalOrdersScreenState extends State<CarnavalOrdersScreen> {
  static const _adminIds = [3, 29, 38];
  static const _pageSize = 20;
  static const _allStatuses = [
    'Nuevo',
    'Procesando',
    'Asignado',
    'Entregando',
    'Completado',
    'Cancelado',
  ];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  int? _carnavalStoreId;
  bool _isAdmin = false;
  List<Map<String, dynamic>> _orders = [];
  Map<int, int> _ventiqOps = {}; // carnaval order id -> ventiq operation id
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  void _onSearch() {
    _loadOrders();
  }

  Future<void> _init() async {
    try {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final carnavalId = await CarnavalService.getCarnavalStoreId(storeId);
      if (carnavalId == null) {
        setState(() => _isLoading = false);
        return;
      }
      _carnavalStoreId = carnavalId;
      _isAdmin = _adminIds.contains(carnavalId);
      await _loadOrders();
    } catch (e) {
      print('❌ Error init carnaval orders: $e');
      setState(() => _isLoading = false);
    }
  }

  int? get _searchOrderId {
    final text = _searchController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _loadVentiqOps(List<Map<String, dynamic>> orders) async {
    final futures = <Future<MapEntry<int, int?>>>[];
    for (final o in orders) {
      final id = o['id'] as int?;
      if (id != null && !_ventiqOps.containsKey(id)) {
        futures.add(
          CarnavalService.getVentiqOperationId(id)
              .then((opId) => MapEntry(id, opId)),
        );
      }
    }
    if (futures.isEmpty) return;
    final results = await Future.wait(futures);
    final newOps = <int, int>{};
    for (final entry in results) {
      if (entry.value != null) newOps[entry.key] = entry.value!;
    }
    if (newOps.isNotEmpty && mounted) {
      setState(() => _ventiqOps.addAll(newOps));
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    _currentPage = 0;
    _ventiqOps = {};
    final orders = await CarnavalService.getCarnavalOrders(
      _carnavalStoreId!,
      _isAdmin,
      page: 0,
      pageSize: _pageSize,
      statusFilter: _selectedStatus,
      orderIdFilter: _searchOrderId,
    );
    setState(() {
      _orders = orders;
      _hasMore = orders.length == _pageSize;
      _isLoading = false;
    });
    _loadVentiqOps(orders);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    final orders = await CarnavalService.getCarnavalOrders(
      _carnavalStoreId!,
      _isAdmin,
      page: _currentPage,
      pageSize: _pageSize,
      statusFilter: _selectedStatus,
      orderIdFilter: _searchOrderId,
    );
    setState(() {
      _orders.addAll(orders);
      _hasMore = orders.length == _pageSize;
      _isLoadingMore = false;
    });
    _loadVentiqOps(orders);
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'Nuevo':
        return Colors.orange;
      case 'En Revision':
        return Colors.blue;
      case 'Pendiente de Pago':
        return Colors.amber;
      case 'Procesando':
        return Colors.indigo;
      case 'Asignado':
        return Colors.purple;
      case 'Entregando':
        return Colors.deepOrange;
      case 'Completado':
        return Colors.teal;
      case 'Cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDestino(String? nombre, String? municipio, String? provincia) {
    final parts = <String>[];
    if (nombre != null && nombre.isNotEmpty) parts.add(nombre);
    final loc = [
      if (municipio != null && municipio.isNotEmpty && municipio != '-')
        municipio,
      if (provincia != null && provincia.isNotEmpty && provincia != '-')
        provincia,
    ].join(', ');
    if (loc.isNotEmpty) parts.add('→ $loc');
    return parts.join(' ');
  }

  Color _paymentColor(String? metodoPago) {
    switch (metodoPago?.toLowerCase()) {
      case 'efectivo':
        return Colors.green;
      case 'transferencia':
        return Colors.blue;
      default:
        return Colors.grey[600]!;
    }
  }

  void _openOrderDetail(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CarnavalOrderDetailSheet(
        order: order,
        isAdmin: _isAdmin,
        carnavalStoreId: _carnavalStoreId!,
        onOrderUpdated: _loadOrders,
      ),
    );
  }

  void _openDashboard() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CarnavalOrdersDashboardScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes Carnaval'),
      ),
      drawer: const AdminDrawer(),
      body: _isLoading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _carnavalStoreId == null
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Tu tienda no está vinculada a Carnaval.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              : Column(
                  children: [
                    // Search bar + dashboard icon
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              keyboardType: TextInputType.number,
                              onSubmitted: (_) => _onSearch(),
                              decoration: InputDecoration(
                                hintText: 'Buscar por ID de orden...',
                                prefixIcon:
                                    const Icon(Icons.search, size: 20),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear,
                                            size: 20),
                                        onPressed: () {
                                          _searchController.clear();
                                          _loadOrders();
                                        },
                                      )
                                    : null,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_isAdmin)
                            IconButton(
                              onPressed: _openDashboard,
                              icon: const Icon(Icons.dashboard),
                              tooltip: 'Dashboard',
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    Colors.indigo.withValues(alpha: 0.1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Status chips
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        children: [
                          _buildStatusChip(null, 'Todos'),
                          ..._allStatuses
                              .map((s) => _buildStatusChip(s, s)),
                        ],
                      ),
                    ),
                    // Orders list
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : RefreshIndicator(
                              onRefresh: _loadOrders,
                              child: _orders.isEmpty
                                  ? ListView(
                                      children: const [
                                        SizedBox(height: 120),
                                        Center(
                                          child: Column(
                                            children: [
                                              Icon(Icons.receipt_long,
                                                  size: 64,
                                                  color: Colors.grey),
                                              SizedBox(height: 16),
                                              Text('No hay órdenes',
                                                  style: TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.grey)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.all(12),
                                      itemCount: _orders.length +
                                          (_hasMore ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        if (index == _orders.length) {
                                          return const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Center(
                                                child:
                                                    CircularProgressIndicator()),
                                          );
                                        }
                                        return _buildOrderCard(
                                            _orders[index]);
                                      },
                                    ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatusChip(String? status, String label) {
    final isSelected = _selectedStatus == status;
    final color = status != null ? _statusColor(status) : Colors.grey[700]!;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.white : color,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedColor: color,
        backgroundColor: color.withValues(alpha: 0.1),
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          setState(() {
            _selectedStatus = isSelected ? null : status;
          });
          _loadOrders();
        },
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = order['status'] as String? ?? 'Desconocido';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final createdAt = order['created_at'] as String?;
    final orderId = order['id'];
    final metodoEntrega = order['metodo_entrega'] as String? ?? '-';
    final metodoPago = order['metodo_pago'] as String? ?? '-';
    final proveedorId = order['proveedor_id'];
    final repartidor = order['repartidor'];
    final usuario = order['Usuarios'] as Map<String, dynamic>?;
    final clienteName = usuario?['name'] as String? ?? '';
    final clientePhone = usuario?['telefono'] as String? ?? '';
    final ventiqOpId = _ventiqOps[orderId];

    final paqueteria = order['paqueteria'];
    final isPaqueteria = paqueteria is Map && paqueteria.isNotEmpty;
    final paquete = isPaqueteria ? paqueteria['paquete'] as Map? : null;
    final numeroPaquete = paquete?['numero']?.toString();
    final descPaquete = paquete?['descripcion']?.toString();
    final destinatarioInfo =
        isPaqueteria ? paqueteria['destinatario'] as Map? : null;
    final destNombre = destinatarioInfo?['nombre']?.toString();
    final destMunicipio =
        destinatarioInfo?['municipio_nombre']?.toString();
    final destProvincia =
        destinatarioInfo?['provincia_nombre']?.toString();

    String dateStr = '-';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isPaqueteria ? Colors.deepPurple.withValues(alpha: 0.04) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPaqueteria
            ? BorderSide(color: Colors.deepPurple.shade200, width: 1.2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _openOrderDetail(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isPaqueteria) ...[
                    Icon(Icons.local_shipping_outlined,
                        size: 18, color: Colors.deepPurple.shade400),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    'Orden #$orderId',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isPaqueteria) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 12, color: Colors.deepPurple.shade400),
                          const SizedBox(width: 3),
                          Text(
                            'Paquete',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple.shade400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: _statusColor(status),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (isPaqueteria && (numeroPaquete != null || descPaquete != null)) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.deepPurple.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (numeroPaquete != null && numeroPaquete.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.confirmation_number_outlined,
                                size: 13,
                                color: Colors.deepPurple.shade400),
                            const SizedBox(width: 4),
                            Text(
                              'Paquete #$numeroPaquete',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.deepPurple.shade700,
                              ),
                            ),
                          ],
                        ),
                      if (descPaquete != null && descPaquete.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          descPaquete,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                      if (destNombre != null && destNombre.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.person_pin_circle_outlined,
                                size: 13, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _formatDestino(destNombre, destMunicipio,
                                    destProvincia),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (clienteName.isNotEmpty || clientePhone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    if (clienteName.isNotEmpty)
                      Flexible(
                        child: Text(clienteName,
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            overflow: TextOverflow.ellipsis),
                      ),
                    if (clientePhone.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(clientePhone,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ],
              if (ventiqOpId != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: Colors.indigo),
                    const SizedBox(width: 4),
                    Text('Op. Inventtia #$ventiqOpId',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(dateStr,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 16),
                  Icon(Icons.attach_money,
                      size: 14, color: Colors.grey[600]),
                  Text('\$${total.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800])),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.local_shipping,
                      size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(metodoEntrega,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 16),
                  Icon(Icons.payment, size: 14, color: _paymentColor(metodoPago)),
                  const SizedBox(width: 4),
                  Text(metodoPago,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _paymentColor(metodoPago))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.store, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Proveedor #$proveedorId',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (repartidor != null) ...[
                    Icon(Icons.delivery_dining,
                        size: 14, color: Colors.purple[400]),
                    const SizedBox(width: 4),
                    Text('Repartidor #$repartidor',
                        style: TextStyle(
                            fontSize: 12, color: Colors.purple[400])),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
