import 'package:flutter/material.dart';
import '../services/carnaval_service.dart';
import '../widgets/carnaval_order_detail_sheet.dart';

/// Auditoría Carnaval ↔ Inventtia.
///
/// Compara las cantidades de `carnavalapp.OrderDetails` contra las
/// extracciones de las operaciones Inventtia vinculadas a cada orden.
class CarnavalAuditScreen extends StatefulWidget {
  final int carnavalStoreId;
  final bool isAdmin;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? statusFilter;

  const CarnavalAuditScreen({
    Key? key,
    required this.carnavalStoreId,
    required this.isAdmin,
    this.dateFrom,
    this.dateTo,
    this.statusFilter,
  }) : super(key: key);

  @override
  State<CarnavalAuditScreen> createState() => _CarnavalAuditScreenState();
}

class _CarnavalAuditScreenState extends State<CarnavalAuditScreen> {
  bool _isLoading = true;
  String? _error;
  int _ordersChecked = 0;
  int _diffsCount = 0;
  int _sinOperacion = 0;
  int _mismatches = 0;
  List<Map<String, dynamic>> _diffs = [];
  String? _tipoFilter; // null = todos
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _dateFrom = widget.dateFrom;
    _dateTo = widget.dateTo;
    _runAudit();
  }

  Future<void> _runAudit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await CarnavalService.auditOrdersVsInventtia(
        carnavalStoreId: widget.carnavalStoreId,
        isAdmin: widget.isAdmin,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        statusFilter: widget.statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _ordersChecked = result['ordersChecked'] as int? ?? 0;
        _diffsCount = result['diffsCount'] as int? ?? 0;
        _sinOperacion = result['sinOperacion'] as int? ?? 0;
        _mismatches = result['mismatches'] as int? ?? 0;
        _diffs = List<Map<String, dynamic>>.from(result['diffs'] as List? ?? []);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredDiffs {
    if (_tipoFilter == null) return _diffs;
    return _diffs.where((d) => d['tipo'] == _tipoFilter).toList();
  }

  Color _tipoColor(String? tipo) {
    switch (tipo) {
      case 'sin_operacion':
        return Colors.red;
      case 'solo_carnaval':
        return Colors.orange;
      case 'solo_inventtia':
        return Colors.purple;
      case 'cantidad':
        return Colors.amber.shade800;
      default:
        return Colors.grey;
    }
  }

  String _tipoLabel(String? tipo) {
    switch (tipo) {
      case 'sin_operacion':
        return 'Sin operación Inventtia';
      case 'solo_carnaval':
        return 'Solo en Carnaval';
      case 'solo_inventtia':
        return 'Solo en Inventtia';
      case 'cantidad':
        return 'Cantidad distinta';
      default:
        return tipo ?? '—';
    }
  }

  String _fmtQty(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  Future<void> _openOrder(int orderId) async {
    final order = await CarnavalService.getOrderById(orderId);
    if (!mounted) return;
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró la orden #$orderId')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => CarnavalOrderDetailSheet(
            order: order,
            isAdmin: widget.isAdmin,
            carnavalStoreId: widget.carnavalStoreId,
            onOrderUpdated: _runAudit,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría Carnaval'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _runAudit,
            icon: const Icon(Icons.refresh),
            tooltip: 'Volver a auditar',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildDateRangeRow(),
          Expanded(child: _buildBodyContent()),
        ],
      ),
    );
  }

  Widget _buildBodyContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Comparando cantidades...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _runAudit,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        _buildSummary(),
        _buildFilters(),
        Expanded(
          child:
              _filteredDiffs.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 64,
                          color: Colors.teal.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _diffs.isEmpty
                              ? 'Sin diferencias encontradas'
                              : 'Sin resultados para este filtro',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_ordersChecked órdenes revisadas',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: _filteredDiffs.length,
                    itemBuilder: (context, index) {
                      return _buildDiffCard(_filteredDiffs[index]);
                    },
                  ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Widget _buildDateRangeRow() {
    final hasFilter = _dateFrom != null || _dateTo != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fecha de creación de la orden',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _dateFrom != null ? _fmtDate(_dateFrom!) : 'Desde',
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          _dateFrom != null ? Colors.indigo : Colors.grey[600],
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    side: BorderSide(
                      color:
                          _dateFrom != null
                              ? Colors.indigo
                              : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dateFrom ?? DateTime.now(),
                            firstDate: DateTime(2022),
                            lastDate: _dateTo ?? DateTime.now(),
                            helpText: 'Fecha creación desde',
                          );
                          if (picked != null) {
                            setState(() => _dateFrom = picked);
                            _runAudit();
                          }
                        },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('—', style: TextStyle(color: Colors.grey)),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _dateTo != null ? _fmtDate(_dateTo!) : 'Hasta',
                    style: TextStyle(
                      fontSize: 12,
                      color: _dateTo != null ? Colors.indigo : Colors.grey[600],
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    side: BorderSide(
                      color:
                          _dateTo != null
                              ? Colors.indigo
                              : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dateTo ?? DateTime.now(),
                            firstDate: _dateFrom ?? DateTime(2022),
                            lastDate: DateTime.now(),
                            helpText: 'Fecha creación hasta',
                          );
                          if (picked != null) {
                            setState(() => _dateTo = picked);
                            _runAudit();
                          }
                        },
                ),
              ),
              if (hasFilter) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Limpiar fechas',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(32, 32),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _dateFrom = null;
                            _dateTo = null;
                          });
                          _runAudit();
                        },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carnaval vs Inventtia',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            _rangeLabel(),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('Órdenes', '$_ordersChecked', Colors.blueGrey),
              _statChip('Diferencias', '$_diffsCount', Colors.red),
              _statChip('Sin operación', '$_sinOperacion', Colors.deepOrange),
              _statChip('Líneas', '$_mismatches', Colors.amber.shade800),
            ],
          ),
        ],
      ),
    );
  }

  String _rangeLabel() {
    final parts = <String>[];
    if (widget.statusFilter != null) {
      parts.add('Estado: ${widget.statusFilter}');
    }
    if (_dateFrom != null || _dateTo != null) {
      final from = _dateFrom != null ? _fmtDate(_dateFrom!) : '…';
      final to = _dateTo != null ? _fmtDate(_dateTo!) : '…';
      parts.add('Creación: $from – $to');
    } else {
      parts.add('Sin filtro de fechas (todas)');
    }
    if (!widget.isAdmin) parts.add('Solo tu proveedor');
    return parts.join(' · ');
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final chips = <MapEntry<String?, String>>[
      const MapEntry(null, 'Todos'),
      const MapEntry('sin_operacion', 'Sin operación'),
      const MapEntry('cantidad', 'Cantidad'),
      const MapEntry('solo_carnaval', 'Solo Carnaval'),
      const MapEntry('solo_inventtia', 'Solo Inventtia'),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children:
            chips.map((e) {
              final selected = _tipoFilter == e.key;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) => setState(() => _tipoFilter = e.key),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildDiffCard(Map<String, dynamic> diff) {
    final tipo = diff['tipo']?.toString();
    final color = _tipoColor(tipo);
    final orderId = (diff['order_id'] as num?)?.toInt();
    final opIds = (diff['operation_ids'] as List?) ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: orderId == null ? null : () => _openOrder(orderId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _tipoLabel(tipo),
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Orden #${orderId ?? '—'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (diff['status'] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${diff['status']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
              if (tipo != 'sin_operacion') ...[
                const SizedBox(height: 8),
                Text(
                  diff['product_name']?.toString() ?? 'Producto',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _qtyBox(
                        'Carnaval',
                        _fmtQty(diff['qty_carnaval']),
                        Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _qtyBox(
                        'Inventtia',
                        _fmtQty(diff['qty_inventtia']),
                        Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _qtyBox(
                        'Diff',
                        _fmtQty(diff['diferencia']),
                        color,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'La orden tiene ${_fmtQty(diff['qty_carnaval'])} uds en '
                  '${diff['lineas_carnaval'] ?? '?'} línea(s) Carnaval '
                  'pero no hay operación Inventtia vinculada.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
              if (opIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Ops Inventtia: ${opIds.join(', ')}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
