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

  @override
  void initState() {
    super.initState();
    _order = Map.from(widget.order);
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    final details = await CarnavalService.getOrderDetails(
      _order['id'],
      proveedorFilter: widget.isAdmin ? null : widget.carnavalStoreId,
    );
    setState(() {
      _details = details;
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
      const ['En Revision', 'Procesando', 'Pendiente de Pago', 'Pagado']
          .contains(_status);

  Color _statusColor(String? status) {
    switch (status) {
      case 'Pendiente':
        return Colors.orange;
      case 'En Revision':
        return Colors.blue;
      case 'Procesando':
        return Colors.indigo;
      case 'Pagado':
        return Colors.green;
      case 'Cancelado':
        return Colors.red;
      case 'Asignado':
        return Colors.purple;
      case 'Completado':
        return Colors.teal;
      case 'Creando':
        return Colors.grey;
      case 'Pendiente de Pago':
        return Colors.amber;
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

  Future<void> _confirmPayment() async {
    await _doAction(() =>
        CarnavalService.updateOrderStatus(_order['id'], 'Pagado'));
  }

  Future<void> _assignDelivery() async {
    final repartidores = await CarnavalService.getRepartidores();
    if (!mounted) return;
    if (repartidores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay repartidores disponibles')),
      );
      return;
    }

    final selected = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Asignar Repartidor'),
        children: repartidores
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, r['id'] as int),
                  child: Text(r['nombre'] ?? r['name'] ?? 'Repartidor #${r['id']}'),
                ))
            .toList(),
      ),
    );
    if (selected != null) {
      await _doAction(() =>
          CarnavalService.assignDelivery(_order['id'], selected));
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
                    // Cliente
                    _buildSection('Cliente', _buildClienteInfo()),
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
                    if (_order['repartidor_id'] != null)
                      _buildSection('Repartidor', Text(
                        'Repartidor #${_order['repartidor_id']}',
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
            color: _statusColor(_status).withOpacity(0.15),
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

  Widget _buildClienteInfo() {
    return Column(
      children: [
        _buildInfoRow('Dirección', _order['direccion'] ?? '-'),
        _buildInfoRow('Destinatario', _order['destinatario'] ?? '-'),
        _buildInfoRow('Teléfono', _order['telefono'] ?? '-'),
        _buildInfoRow('Notas', _order['notas'] ?? '-'),
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
    return Column(
      children: [
        _buildInfoRow('Método', _order['metodo_pago'] ?? '-'),
        _buildInfoRow('Moneda', _order['moneda'] ?? '-'),
        _buildInfoRow('Total',
            '\$${(_order['total'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
        _buildInfoRow('Tax',
            '\$${(_order['tax'] as num?)?.toStringAsFixed(2) ?? '0.00'}'),
      ],
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

    if (_status == 'En Revision' || _status == 'Pagado') {
      actions.add(_actionButton('Aceptar', Colors.green, _acceptOrder));
    }
    if (_status == 'En Revision' || _status == 'Pendiente de Pago') {
      actions.add(_actionButton('Cancelar', Colors.red, _cancelOrder));
    }
    if (_status == 'Procesando') {
      actions
          .add(_actionButton('Asignar Repartidor', Colors.purple, _assignDelivery));
    }
    if (_status == 'Pendiente de Pago') {
      actions
          .add(_actionButton('Confirmar Pago', Colors.green, _confirmPayment));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions,
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}
