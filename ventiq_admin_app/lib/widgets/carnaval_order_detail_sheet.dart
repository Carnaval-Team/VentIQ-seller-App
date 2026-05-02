import 'package:flutter/material.dart';
import '../services/carnaval_service.dart';

class CarnavalOrderDetailSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isAdmin;
  final int carnavalStoreId;
  final VoidCallback onOrderUpdated;

  const CarnavalOrderDetailSheet({
    Key? key,
    required this.order,
    required this.isAdmin,
    required this.carnavalStoreId,
    required this.onOrderUpdated,
  }) : super(key: key);

  @override
  State<CarnavalOrderDetailSheet> createState() =>
      _CarnavalOrderDetailSheetState();
}

class _CarnavalOrderDetailSheetState extends State<CarnavalOrderDetailSheet> {
  bool _isLoading = true;
  bool _isActionLoading = false;
  List<Map<String, dynamic>> _details = [];
  Map<String, dynamic> _order = {};

  // Extra data
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _direccionInfo;
  int? _ventiqOperationId;

  @override
  void initState() {
    super.initState();
    _order = Map.from(widget.order);
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);

    final detailsFuture = CarnavalService.getOrderDetails(
      _order['id'],
      proveedorFilter: widget.isAdmin ? null : widget.carnavalStoreId,
    );

    // Load extra data in parallel
    final userId = _order['user_id'] as int?;
    final direccion = _order['direccion'] as String?;
    final orderId = _order['id'] as int?;

    final futures = await Future.wait([
      detailsFuture,
      if (userId != null) CarnavalService.getOrderUserInfo(userId),
      if (direccion != null && direccion.isNotEmpty)
        CarnavalService.getOrderDireccion(direccion),
      if (orderId != null) CarnavalService.getVentiqOperationId(orderId),
    ]);

    int idx = 1;
    setState(() {
      _details = futures[0] as List<Map<String, dynamic>>;
      if (userId != null) {
        _userInfo = futures[idx] as Map<String, dynamic>?;
        idx++;
      }
      if (direccion != null && direccion.isNotEmpty) {
        _direccionInfo = futures[idx] as Map<String, dynamic>?;
        idx++;
      }
      if (orderId != null) {
        _ventiqOperationId = futures[idx] as int?;
      }
      _isLoading = false;
    });
  }

  Future<void> _refreshOrder() async {
    final updated = await CarnavalService.getOrderById(_order['id']);
    if (updated != null) {
      setState(() => _order = updated);
    }
  }

  String get _status => _order['status'] as String? ?? '';

  bool get _canEditProducts =>
      const ['Nuevo', 'En Revision', 'Procesando', 'Pendiente de Pago']
          .contains(_status);

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

  Future<void> _doAction(Future<bool> Function() action) async {
    setState(() => _isActionLoading = true);
    final ok = await action();
    if (ok) {
      await _refreshOrder();
      await _loadDetails();
      widget.onOrderUpdated();
    }
    setState(() => _isActionLoading = false);
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orden actualizada')),
      );
    }
  }

  Future<void> _acceptOrder() async {
    await _doAction(() =>
        CarnavalService.updateOrderStatus(_order['id'], 'Procesando'));
  }

  Future<void> _validatePayment() async {
    await _doAction(() =>
        CarnavalService.updateOrderStatus(_order['id'], 'Procesando'));
  }

  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar Orden'),
        content: const Text('¿Estás seguro de cancelar esta orden?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (confirmed == true) {
      await _doAction(() =>
          CarnavalService.updateOrderStatus(_order['id'], 'Cancelado'));
    }
  }

  Future<int?> _showRepartidorPicker() async {
    final repartidores = await CarnavalService.getRepartidores();
    if (!mounted) return null;
    if (repartidores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay repartidores disponibles')),
      );
      return null;
    }

    final currentRepartidor = _order['repartidor'] as int?;

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
              // Title
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Seleccionar Repartidor',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Elige un repartidor disponible',
                              style:
                                  TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),
              // List
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
                    final correo = r['correo'] as String? ?? '';
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
                              // Avatar
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    Colors.purple.withValues(alpha: 0.15),
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
                              // Info
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(nombre,
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight:
                                                      FontWeight.w600),
                                              overflow:
                                                  TextOverflow.ellipsis),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text('Actual',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    if (telefono.isNotEmpty)
                                      Row(
                                        children: [
                                          Icon(Icons.phone,
                                              size: 13,
                                              color: Colors.grey[500]),
                                          const SizedBox(width: 4),
                                          Text(telefono,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600])),
                                        ],
                                      ),
                                    if (correo.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.email_outlined,
                                              size: 13,
                                              color: Colors.grey[500]),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(correo,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey[600]),
                                                overflow: TextOverflow
                                                    .ellipsis),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Arrow
                              Icon(Icons.arrow_forward_ios,
                                  size: 14, color: Colors.grey[400]),
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
      },
    );
  }

  Future<void> _assignDelivery() async {
    final selected = await _showRepartidorPicker();
    if (selected != null) {
      final metodoEntrega = _order['metodo_entrega'] as String? ?? 'Domicilio';
      await _doAction(() =>
          CarnavalService.assignDelivery(_order['id'], selected,
              metodoEntrega: metodoEntrega));
    }
  }

  Future<void> _reassignDelivery() async {
    final selected = await _showRepartidorPicker();
    if (selected != null) {
      await _doAction(() =>
          CarnavalService.reassignDelivery(_order['id'], selected));
    }
  }

  Future<void> _updateQuantity(Map<String, dynamic> detail, int delta) async {
    final currentQty = (detail['quantity'] as num?)?.toInt() ?? 1;
    final newQty = currentQty + delta;
    if (newQty < 1) return;

    setState(() => _isActionLoading = true);
    final ok =
        await CarnavalService.updateOrderDetailQuantity(detail['id'], newQty);
    if (ok) {
      await CarnavalService.recalculateOrderTotal(_order['id']);
      await _refreshOrder();
      await _loadDetails();
      widget.onOrderUpdated();
    }
    setState(() => _isActionLoading = false);
  }

  Future<void> _deleteDetail(Map<String, dynamic> detail) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: const Text('¿Eliminar este producto de la orden?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, eliminar')),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _isActionLoading = true);
      final ok = await CarnavalService.deleteOrderDetail(detail['id']);
      if (ok) {
        await CarnavalService.recalculateOrderTotal(_order['id']);
        await _refreshOrder();
        await _loadDetails();
        widget.onOrderUpdated();
      }
      setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: _isActionLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Header
                    _buildHeader(),
                    const SizedBox(height: 16),
                    // VentIQ Operation
                    if (_ventiqOperationId != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link, size: 16, color: Colors.indigo),
                            const SizedBox(width: 8),
                            Text(
                              'Operación Inventtia #$_ventiqOperationId',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Paquetería (si aplica)
                    if (_isPaqueteria) ...[
                      _buildPaqueteriaBanner(),
                      const SizedBox(height: 12),
                      _buildSection('Paquete', _buildPaqueteInfo()),
                      const SizedBox(height: 12),
                      _buildSection('Remitente', _buildPersonaInfo(_remitente)),
                      const SizedBox(height: 12),
                      _buildSection(
                          'Destinatario', _buildPersonaInfo(_destinatarioPaq)),
                      const SizedBox(height: 12),
                    ],
                    // Cliente
                    _buildSection('Cliente', _buildClienteInfo()),
                    const SizedBox(height: 12),
                    // Dirección
                    _buildSection('Dirección', _buildDireccionInfo()),
                    const SizedBox(height: 12),
                    // Entrega
                    _buildSection('Entrega', _buildEntregaInfo()),
                    const SizedBox(height: 12),
                    // Pago
                    _buildSection('Pago', _buildPagoInfo()),
                    const SizedBox(height: 12),
                    // Productos
                    _buildSection(
                      'Productos',
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildProductosList(),
                    ),
                    const SizedBox(height: 12),
                    // Repartidor
                    if (_order['repartidor'] != null)
                      _buildSection('Repartidor', Text(
                        'Repartidor #${_order['repartidor']}',
                        style: const TextStyle(fontSize: 14),
                      )),
                    const SizedBox(height: 16),
                    // Acciones admin
                    if (widget.isAdmin) _buildAdminActions(),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final orderId = _order['id'];
    final createdAt = _order['created_at'] as String?;
    String dateStr = '-';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Orden #$orderId',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(dateStr,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _statusColor(_status).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _status.isEmpty ? 'Desconocido' : _status,
            style: TextStyle(
              color: _statusColor(_status),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Map<String, dynamic>? get _paqueteria {
    final p = _order['paqueteria'];
    if (p is Map && p.isNotEmpty) return Map<String, dynamic>.from(p);
    return null;
  }

  bool get _isPaqueteria => _paqueteria != null;

  /// Sub-objeto interno: el nuevo formato anida `paqueteria.paqueteria.{...}`.
  /// Si no existe el wrapper interno, cae al objeto raíz para retro-compat.
  Map<String, dynamic>? get _paqueteriaInner {
    final inner = _paqueteria?['paqueteria'];
    if (inner is Map && inner.isNotEmpty) {
      return Map<String, dynamic>.from(inner);
    }
    return _paqueteria;
  }

  Map<String, dynamic>? get _paquete {
    final v = _paqueteriaInner?['paquete'];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Map<String, dynamic>? get _remitente {
    final v = _paqueteriaInner?['remitente'];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Map<String, dynamic>? get _destinatarioPaq {
    final v = _paqueteriaInner?['destinatario'];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Widget _buildPaqueteriaBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 20, color: Colors.deepPurple.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Orden de Paquetería',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.deepPurple.shade700,
              ),
            ),
          ),
          if (_paquete?['numero'] != null)
            Text(
              '#${_paquete!['numero']}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.deepPurple.shade400,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaqueteInfo() {
    final p = _paquete ?? const {};
    final fotoUrl = p['foto_url']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Número', p['numero']?.toString() ?? '-'),
        _buildInfoRow('Descripción', p['descripcion']?.toString() ?? '-'),
        if (p['peso'] != null && p['peso'].toString().isNotEmpty)
          _buildInfoRow('Peso', p['peso'].toString()),
        if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              onTap: () => _showPhotoPreview(fotoUrl),
              child: Image.network(
                fotoUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: Colors.grey[200],
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
                loadingBuilder: (ctx, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 120,
                    color: Colors.grey[100],
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPersonaInfo(Map<String, dynamic>? persona) {
    if (persona == null) {
      return const Text('-', style: TextStyle(color: Colors.grey));
    }
    // Formato nuevo (GeoNames): pais_nombre / estado_nombre / ciudad_nombre.
    // Formato antiguo (carnavalapp): provincia_nombre / municipio_nombre.
    final ciudad = (persona['ciudad_nombre'] ?? persona['municipio_nombre'])
        ?.toString();
    final estado = (persona['estado_nombre'] ?? persona['provincia_nombre'])
        ?.toString();
    final pais = persona['pais_nombre']?.toString();
    return Column(
      children: [
        _buildInfoRow('Nombre', persona['nombre']?.toString() ?? '-'),
        _buildInfoRow('Teléfono', persona['telefono']?.toString() ?? '-'),
        _buildInfoRow('Dirección', persona['direccion']?.toString() ?? '-'),
        _buildInfoRow('Ciudad',
            (ciudad != null && ciudad.isNotEmpty) ? ciudad : '-'),
        _buildInfoRow('Estado/Provincia',
            (estado != null && estado.isNotEmpty) ? estado : '-'),
        if (pais != null && pais.isNotEmpty)
          _buildInfoRow('País', pais),
      ],
    );
  }

  void _showPhotoPreview(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  Widget _buildClienteInfo() {
    final name = _userInfo?['name'] as String? ?? _order['destinatario'] ?? '-';
    final email = _userInfo?['email'] as String? ?? '-';
    final telefono =
        _userInfo?['telefono'] as String? ?? _order['telefono'] ?? '-';
    final carnet = _userInfo?['carnet_id']?.toString() ?? '-';

    return Column(
      children: [
        _buildInfoRow('Nombre', name),
        _buildInfoRow('Email', email),
        _buildInfoRow('Teléfono', telefono),
        _buildInfoRow('Carnet', carnet),
        _buildInfoRow('Destinatario', _order['destinatario'] ?? '-'),
        _buildInfoRow('Notas', _order['notas'] ?? '-'),
      ],
    );
  }

  Widget _buildDireccionInfo() {
    final provincia = _direccionInfo?['provincia_nombre'] ?? '-';
    final municipio = _direccionInfo?['municipio_nombre'] ?? '-';
    final direccion = _order['direccion'] ?? '-';

    return Column(
      children: [
        _buildInfoRow('Provincia', provincia),
        _buildInfoRow('Municipio', municipio),
        _buildInfoRow('Dirección', direccion),
      ],
    );
  }

  Widget _buildEntregaInfo() {
    return Column(
      children: [
        _buildInfoRow('Método', _order['metodo_entrega'] ?? '-'),
        _buildInfoRow('Dirección', _order['direccion_entrega'] ?? '-'),
        _buildInfoRow('Costo envío',
            '\$${(_order['costo_envio'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
        _buildInfoRow('Fecha entrega', _order['fecha_entrega'] ?? '-'),
      ],
    );
  }

  Widget _buildPagoInfo() {
    final moneda = (_order['moneda'] as String?)?.toUpperCase();
    final totalUsd = (_order['totalUsd'] as num?)?.toDouble();
    final totalEuro = (_order['totalEuro'] as num?)?.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('Método', _order['metodo_pago'] ?? '-'),
        _buildInfoRow('Moneda', _order['moneda'] ?? '-'),
        _buildInfoRow('Total',
            '\$${(_order['total'] as num?)?.toStringAsFixed(2) ?? '0.00'} CUP'),
        if (moneda == 'USD' && totalUsd != null && totalUsd > 0) ...[
          const SizedBox(height: 6),
          _buildForeignCurrencyTile(
            symbol: '\$',
            amount: totalUsd,
            code: 'USD',
            label: 'Total en USD',
            color: Colors.green.shade700,
            bg: Colors.green.withValues(alpha: 0.10),
          ),
        ] else if (moneda == 'EUR' && totalEuro != null && totalEuro > 0) ...[
          const SizedBox(height: 6),
          _buildForeignCurrencyTile(
            symbol: '€',
            amount: totalEuro,
            code: 'EUR',
            label: 'Total en EUR',
            color: Colors.blue.shade700,
            bg: Colors.blue.withValues(alpha: 0.10),
          ),
        ],
        const SizedBox(height: 4),
        _buildInfoRow('Tax',
            '\$${(_order['tax'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
      ],
    );
  }

  Widget _buildForeignCurrencyTile({
    required String symbol,
    required double amount,
    required String code,
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            '$symbol${amount.toStringAsFixed(2)} $code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductosList() {
    if (_details.isEmpty) {
      return const Text('Sin productos', style: TextStyle(color: Colors.grey));
    }

    return Column(
      children: _details.map((d) {
        final producto = d['Productos'] as Map<String, dynamic>?;
        final name = producto?['name'] ?? 'Producto';
        final image = producto?['image'] as String?;
        final proveedorData = producto?['proveedores'] as Map<String, dynamic>?;
        final proveedorName = proveedorData?['name'] as String?;
        final qty = (d['quantity'] as num?)?.toInt() ?? 0;
        final price = (d['price'] as num?)?.toDouble() ?? 0;
        final subtotal = price * qty;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: image != null && image.isNotEmpty
                    ? Image.network(image,
                        width: 48, height: 48, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                              width: 48,
                              height: 48,
                              color: Colors.grey[200],
                              child: const Icon(Icons.image, color: Colors.grey),
                            ))
                    : Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[200],
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
              ),
              const SizedBox(width: 10),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                        '$qty x \$${price.toStringAsFixed(2)} = \$${subtotal.toStringAsFixed(2)}',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              if (proveedorName != null)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storefront, size: 12, color: Colors.deepPurple),
                      const SizedBox(width: 4),
                      Text(proveedorName,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple)),
                    ],
                  ),
                ),
              // Admin actions
              if (widget.isAdmin && _canEditProducts) ...[
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: () => _updateQuantity(d, -1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('$qty',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: () => _updateQuantity(d, 1),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Colors.red[400]),
                  onPressed: () => _deleteDetail(d),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAdminActions() {
    final actions = <Widget>[];
    final metodoPago = _order['metodo_pago'] as String? ?? '';
    final metodoEntrega = _order['metodo_entrega'] as String? ?? '';

    switch (_status) {
      case 'Nuevo':
        actions.add(_actionButton(
          'Aceptar y Procesar',
          'La orden pasará a preparación',
          Icons.check_circle_outline,
          Colors.green,
          _acceptOrder,
        ));
        actions.add(_actionButton(
          'Cancelar Orden',
          'Se cancelará permanentemente',
          Icons.cancel_outlined,
          Colors.red,
          _cancelOrder,
        ));
        break;
      case 'En Revision':
      case 'Pendiente de Pago':
        actions.add(_actionButton(
          'Aceptar y Procesar',
          'La orden pasará a preparación',
          Icons.check_circle_outline,
          Colors.green,
          _acceptOrder,
        ));
        actions.add(_actionButton(
          'Cancelar Orden',
          'Se cancelará permanentemente',
          Icons.cancel_outlined,
          Colors.red,
          _cancelOrder,
        ));
        break;
      case 'Procesando':
        final esRecogida = metodoEntrega == 'Entrega Cliente';
        actions.add(_actionButton(
          esRecogida ? 'Asignar y Completar' : 'Asignar Repartidor',
          esRecogida
              ? 'Recogida en tienda: se marcará como completada'
              : 'Seleccionar repartidor para envío a domicilio',
          esRecogida ? Icons.storefront : Icons.delivery_dining,
          Colors.purple,
          _assignDelivery,
        ));
        actions.add(_actionButton(
          'Cancelar Orden',
          'Cancelar preparación',
          Icons.cancel_outlined,
          Colors.red,
          _cancelOrder,
        ));
        break;
      case 'Asignado':
        actions.add(_actionButton(
          'Reasignar Repartidor',
          'Cambiar el repartidor asignado a esta orden',
          Icons.swap_horiz,
          Colors.purple,
          _reassignDelivery,
        ));
        actions.add(_actionButton(
          'Cancelar Orden',
          'Cancelar antes de la entrega',
          Icons.cancel_outlined,
          Colors.red,
          _cancelOrder,
        ));
        break;
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 4),
        Text('Acciones',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 8),
        ...actions,
      ],
    );
  }

  Widget _actionButton(
    String label,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.85))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }
}
