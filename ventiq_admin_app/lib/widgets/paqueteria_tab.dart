import 'package:flutter/material.dart';
import '../services/carnaval_service.dart';
import '../services/user_preferences_service.dart';

class PaqueteriaTab extends StatefulWidget {
  const PaqueteriaTab({super.key});

  @override
  State<PaqueteriaTab> createState() => _PaqueteriaTabState();
}

class _PaqueteriaTabState extends State<PaqueteriaTab> {
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
  int? _idTienda;

  late DateTime _startDate;
  late DateTime _endDate;

  String? _selectedStatus;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _initWeekRange();
    _scrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _initWeekRange() {
    final now = DateTime.now();
    // Lunes como inicio de semana.
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    _startDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    final storeId = await UserPreferencesService().getIdTienda();
    if (storeId == null) {
      setState(() => _isLoading = false);
      return;
    }
    _idTienda = storeId;
    await _loadOrders();
  }

  int? get _searchOrderId {
    final text = _searchController.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<void> _loadOrders() async {
    if (_idTienda == null) return;
    setState(() => _isLoading = true);
    _currentPage = 0;
    final orders = await CarnavalService.getPaqueteriaOrdersByTienda(
      idTienda: _idTienda!,
      from: _startDate,
      to: _endDate,
      page: 0,
      pageSize: _pageSize,
      statusFilter: _selectedStatus,
      orderIdFilter: _searchOrderId,
    );
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _hasMore = orders.length == _pageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _idTienda == null) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    final orders = await CarnavalService.getPaqueteriaOrdersByTienda(
      idTienda: _idTienda!,
      from: _startDate,
      to: _endDate,
      page: _currentPage,
      pageSize: _pageSize,
      statusFilter: _selectedStatus,
      orderIdFilter: _searchOrderId,
    );
    if (!mounted) return;
    setState(() {
      _orders.addAll(orders);
      _hasMore = orders.length == _pageSize;
      _isLoadingMore = false;
    });
  }

  Future<void> _pickDateRange() async {
    final initial = DateTimeRange(start: _startDate, end: _endDate);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: initial,
      helpText: 'Rango de fechas',
      saveText: 'Aplicar',
    );
    if (range == null) return;
    setState(() {
      _startDate = DateTime(
          range.start.year, range.start.month, range.start.day, 0, 0, 0);
      _endDate = DateTime(
          range.end.year, range.end.month, range.end.day, 23, 59, 59);
    });
    _loadOrders();
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

  Future<void> _onAssignTap(Map<String, dynamic> order) async {
    final repartidorId = await _showRepartidorPicker(
      currentRepartidor: order['repartidor'] as int?,
    );
    if (repartidorId == null) return;
    final orderId = order['id'] as int;
    final ok = await CarnavalService.assignDelivery(
      orderId,
      repartidorId,
      metodoEntrega: 'Domicilio',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Repartidor asignado y orden marcada como Asignado'
            : 'Error al asignar repartidor'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
    if (ok) _loadOrders();
  }

  Future<int?> _showRepartidorPicker({int? currentRepartidor}) async {
    var repartidores = await CarnavalService.getRepartidores();
    if (!mounted) return null;

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.delivery_dining,
                            color: Colors.purple, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Asignar repartidor',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final created = await _showAddRepartidorDialog(ctx);
                          if (created != null) {
                            setSheetState(() {
                              repartidores = [created, ...repartidores];
                            });
                          }
                        },
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('Nuevo'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 12),
                if (repartidores.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay repartidores. Agrega uno con "Nuevo".',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: repartidores.length,
                      itemBuilder: (_, i) {
                        final r = repartidores[i];
                        final id = r['id'] as int;
                        final nombre =
                            r['nombre'] as String? ?? 'Repartidor #$id';
                        final telefono = r['telefono']?.toString() ?? '';
                        final isCurrent = id == currentRepartidor;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? Colors.purple.withValues(alpha: 0.08)
                                : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isCurrent
                                  ? Colors.purple.withValues(alpha: 0.4)
                                  : Colors.grey[200]!,
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx, id),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.purple
                                        .withValues(alpha: 0.15),
                                    child: Text(
                                      nombre.isNotEmpty
                                          ? nombre[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(nombre,
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600)),
                                        if (telefono.isNotEmpty)
                                          Text(telefono,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.purple,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Text('Actual',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<Map<String, dynamic>?> _showAddRepartidorDialog(
      BuildContext parentCtx) async {
    final nombreCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final correoCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<Map<String, dynamic>>(
      context: parentCtx,
      builder: (dctx) {
        bool saving = false;
        return StatefulBuilder(builder: (dctx, setDState) {
          return AlertDialog(
            title: const Text('Nuevo repartidor'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(labelText: 'Nombre *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: telCtrl,
                    decoration: const InputDecoration(labelText: 'Teléfono'),
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: correoCtrl,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.pop(dctx, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        setDState(() => saving = true);
                        final created = await CarnavalService.addRepartidor(
                          nombre: nombreCtrl.text.trim(),
                          telefono: telCtrl.text.trim(),
                          correo: correoCtrl.text.trim(),
                        );
                        if (!dctx.mounted) return;
                        if (created == null) {
                          setDState(() => saving = false);
                          ScaffoldMessenger.of(dctx).showSnackBar(
                            const SnackBar(
                              content: Text('Error al crear repartidor'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        Navigator.pop(dctx, created);
                      },
                child: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_idTienda == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No se pudo determinar la tienda actual.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _loadOrders(),
                  decoration: InputDecoration(
                    hintText: 'Buscar por ID de orden...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
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
              IconButton(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range),
                tooltip: 'Rango de fechas',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${_fmtDate(_startDate)} - ${_fmtDate(_endDate)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _buildStatusChip(null, 'Todos'),
              ..._allStatuses.map((s) => _buildStatusChip(s, s)),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadOrders,
            child: _orders.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No hay órdenes de paquetería',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _orders.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _orders.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                              child: CircularProgressIndicator()),
                        );
                      }
                      return _buildOrderCard(_orders[index]);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
          setState(() => _selectedStatus = isSelected ? null : status);
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
    final metodoPago = order['metodo_pago'] as String? ?? '-';
    final repartidor = order['repartidor'];
    final usuario = order['Usuarios'] as Map<String, dynamic>?;
    final clienteName = usuario?['name'] as String? ?? '';
    final clientePhone = usuario?['telefono'] as String? ?? '';
    final ventiqOpId = order['_ventiq_operacion_id'] as int?;

    final paqueteria = order['paqueteria'];
    final isPaqueteria = paqueteria is Map && paqueteria.isNotEmpty;
    final paquete = isPaqueteria ? paqueteria['paquete'] as Map? : null;
    final numeroPaquete = paquete?['numero']?.toString();
    final descPaquete = paquete?['descripcion']?.toString();
    Map? destinatarioInfo;
    if (isPaqueteria) {
      final inner = paqueteria['paqueteria'];
      if (inner is Map && inner['destinatario'] is Map) {
        destinatarioInfo = inner['destinatario'] as Map;
      } else if (paqueteria['destinatario'] is Map) {
        destinatarioInfo = paqueteria['destinatario'] as Map;
      }
    }
    final destNombre = destinatarioInfo?['nombre']?.toString();
    final destMunicipio = (destinatarioInfo?['ciudad_nombre'] ??
            destinatarioInfo?['municipio_nombre'])
        ?.toString();
    final destProvincia = (destinatarioInfo?['estado_nombre'] ??
            destinatarioInfo?['provincia_nombre'])
        ?.toString();

    String dateStr = '-';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateStr = _fmtDate(dt);
      }
    }

    final canAssign = status != 'Completado' && status != 'Cancelado';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.blue, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined,
                    size: 18, color: Colors.blue),
                const SizedBox(width: 6),
                Text(
                  'Orden #$orderId',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
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
            if (numeroPaquete != null || descPaquete != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (numeroPaquete != null && numeroPaquete.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.confirmation_number_outlined,
                              size: 13, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            'Paquete #$numeroPaquete',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
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
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[700]),
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
                              _formatDestino(
                                  destNombre, destMunicipio, destProvincia),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700]),
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
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[700]),
                          overflow: TextOverflow.ellipsis),
                    ),
                  if (clientePhone.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(clientePhone,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
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
                Text('\$${total.toStringAsFixed(2)} CUP',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800])),
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
            const SizedBox(height: 8),
            Row(
              children: [
                if (repartidor != null) ...[
                  Icon(Icons.delivery_dining,
                      size: 14, color: Colors.purple[400]),
                  const SizedBox(width: 4),
                  Text('Repartidor #$repartidor',
                      style: TextStyle(
                          fontSize: 12, color: Colors.purple[400])),
                ],
                const Spacer(),
                if (canAssign)
                  ElevatedButton.icon(
                    onPressed: () => _onAssignTap(order),
                    icon: const Icon(Icons.delivery_dining, size: 16),
                    label: Text(repartidor == null
                        ? 'Asignar chofer'
                        : 'Reasignar chofer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
