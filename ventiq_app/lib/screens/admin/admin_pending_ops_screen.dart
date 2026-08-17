import 'package:flutter/material.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/offline_database_service.dart';

/// Cola e historial local de operaciones Admin Lite (offline-first).
class AdminPendingOpsScreen extends StatefulWidget {
  const AdminPendingOpsScreen({super.key});

  @override
  State<AdminPendingOpsScreen> createState() => _AdminPendingOpsScreenState();
}

class _AdminPendingOpsScreenState extends State<AdminPendingOpsScreen> {
  final _db = OfflineDatabaseService();
  final _service = AdminInventoryService();

  List<Map<String, dynamic>> _ops = [];
  bool _loading = true;
  bool _syncing = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final history = await _db.getAdminOpsHistory(limit: 150);
    final pending = await _db.countPendingAdminOps();
    if (!mounted) return;
    setState(() {
      _ops = history;
      _pendingCount = pending;
      _loading = false;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final n = await _service.syncPendingOps();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n > 0
                ? 'Sincronizadas $n operación(es)'
                : 'No hay operaciones pendientes o sin red/sesión',
          ),
          backgroundColor: n > 0 ? Colors.green : Colors.orange,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case AdminOpType.priceUpdate:
        return 'Precio';
      case AdminOpType.stockAdjustment:
        return 'Ajuste';
      case AdminOpType.reception:
        return 'Recepción';
      case AdminOpType.productCreate:
        return 'Alta producto';
      case AdminOpType.extraction:
        return 'Extracción';
      case AdminOpType.transfer:
        return 'Transferencia';
      case AdminOpType.saleByAgreement:
        return 'Venta acuerdo';
      case AdminOpType.tpvPriceUpsert:
        return 'Precio TPV';
      case AdminOpType.tpvCreate:
        return 'Alta TPV';
      case AdminOpType.tpvUpdate:
        return 'Editar TPV';
      case AdminOpType.vendorAssignTpv:
        return 'Asignar TPV';
      case AdminOpType.vendorUpdateFlags:
        return 'Flags vendedor';
      default:
        return type ?? 'Op';
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case AdminOpType.priceUpdate:
        return Icons.sell_outlined;
      case AdminOpType.stockAdjustment:
        return Icons.tune;
      case AdminOpType.reception:
        return Icons.move_to_inbox;
      case AdminOpType.productCreate:
        return Icons.add_box_outlined;
      case AdminOpType.extraction:
        return Icons.outbox;
      case AdminOpType.transfer:
        return Icons.swap_horiz;
      case AdminOpType.saleByAgreement:
        return Icons.handshake_outlined;
      case AdminOpType.tpvPriceUpsert:
        return Icons.point_of_sale;
      case AdminOpType.tpvCreate:
      case AdminOpType.tpvUpdate:
        return Icons.storefront_outlined;
      case AdminOpType.vendorAssignTpv:
      case AdminOpType.vendorUpdateFlags:
        return Icons.person_outline;
      default:
        return Icons.pending_actions;
    }
  }

  String _summary(Map<String, dynamic> op) {
    final payload = op['payload'];
    if (payload is! Map) return '';
    final map = Map<String, dynamic>.from(payload);
    final type = op['op_type']?.toString();
    switch (type) {
      case AdminOpType.priceUpdate:
        return 'Producto #${map['id_producto']} · venta ${map['precio_venta_cup'] ?? '-'}';
      case AdminOpType.stockAdjustment:
        return 'Producto #${map['id_producto']} · ${map['cantidad_anterior']} → ${map['cantidad_nueva']}';
      case AdminOpType.reception:
        final prods = map['productos'];
        final n = prods is List ? prods.length : 0;
        return '$n producto(s) · ${map['entregado_por'] ?? ''}';
      case AdminOpType.productCreate:
        return '${map['denominacion'] ?? ''} · ${map['precio_venta_cup'] ?? ''} CUP';
      case AdminOpType.extraction:
        final prods = map['productos'];
        final n = prods is List ? prods.length : 0;
        return '$n producto(s) · motivo ${map['id_motivo_operacion'] ?? '-'}';
      case AdminOpType.transfer:
        final prods = map['productos'];
        final n = prods is List ? prods.length : 0;
        return '$n producto(s) · ${map['id_layout_origen']} → ${map['id_layout_destino']}';
      case AdminOpType.saleByAgreement:
        final prods = map['productos'];
        final n = prods is List ? prods.length : 0;
        return '$n producto(s) · \$${map['monto_total'] ?? 0} · ${map['cliente'] ?? ''}';
      case AdminOpType.tpvPriceUpsert:
        return 'Prod #${map['id_producto']} · TPV ${map['id_tpv']} · \$${map['precio_venta_cup']}';
      case AdminOpType.tpvCreate:
        return '${map['denominacion'] ?? ''} · almacén ${map['id_almacen']}';
      case AdminOpType.tpvUpdate:
        return 'TPV #${map['id']} · ${map['denominacion'] ?? ''}';
      case AdminOpType.vendorAssignTpv:
        return 'Vend #${map['id_vendedor']} → TPV ${map['id_tpv']}';
      case AdminOpType.vendorUpdateFlags:
        return 'Vend #${map['id_vendedor']} · customizar=${map['permitir_customizar_precio_venta']}';
      default:
        return map.keys.take(3).join(', ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ops / movimientos'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Sincronizar pendientes',
            onPressed: _syncing ? null : _syncNow,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: _pendingCount > 0
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      _pendingCount > 0
                          ? '$_pendingCount operación(es) pendiente(s) de sync'
                          : 'Sin pendientes — historial local reciente',
                      style: TextStyle(
                        color: _pendingCount > 0
                            ? Colors.orange.shade900
                            : Colors.green.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _ops.isEmpty
                      ? Center(
                          child: Text(
                            'Aún no hay operaciones admin en este dispositivo',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _ops.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final op = _ops[i];
                            final synced = op['synced'] == true ||
                                op['synced'] == 1;
                            final err = op['last_error']?.toString();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: synced
                                    ? Colors.green.shade50
                                    : (err != null && err.isNotEmpty
                                        ? Colors.red.shade50
                                        : Colors.orange.shade50),
                                child: Icon(
                                  _typeIcon(op['op_type']?.toString()),
                                  color: synced
                                      ? Colors.green.shade700
                                      : (err != null && err.isNotEmpty
                                          ? Colors.red.shade700
                                          : Colors.orange.shade800),
                                ),
                              ),
                              title: Text(_typeLabel(op['op_type']?.toString())),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_summary(op)),
                                  Text(
                                    op['created_at']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (err != null && err.isNotEmpty)
                                    Text(
                                      err,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.red[700],
                                      ),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                synced ? 'OK' : 'Pendiente',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: synced
                                      ? Colors.green[700]
                                      : Colors.orange[800],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
