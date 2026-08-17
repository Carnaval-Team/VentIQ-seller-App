import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';

/// Inventario físico / IPV lite desde cache local (conteo y exportación texto).
class AdminIpvScreen extends StatefulWidget {
  const AdminIpvScreen({super.key});

  @override
  State<AdminIpvScreen> createState() => _AdminIpvScreenState();
}

class _AdminIpvScreenState extends State<AdminIpvScreen> {
  final _service = AdminInventoryService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  bool _includeZero = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _service.listCachedProducts();
    products.sort(
      (a, b) => (a['denominacion']?.toString() ?? '').compareTo(
        b['denominacion']?.toString() ?? '',
      ),
    );
    if (!mounted) return;
    setState(() {
      _all = products;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = _all.where((p) {
        final qty = (p['cantidad'] as num?)?.toDouble() ?? 0;
        if (!_includeZero && qty <= 0) return false;
        if (q.isEmpty) return true;
        final name = p['denominacion']?.toString().toLowerCase() ?? '';
        final sku = p['sku']?.toString().toLowerCase() ?? '';
        return name.contains(q) || sku.contains(q);
      }).toList();
    });
  }

  String _ubicacionOf(Map<String, dynamic> p) {
    final top = p['ubicacion_nombre']?.toString();
    if (top != null && top.isNotEmpty) return top;
    final detalles = p['detalles_completos'];
    if (detalles is Map) {
      final inv = detalles['inventario'];
      if (inv is List && inv.isNotEmpty && inv.first is Map) {
        final first = Map<String, dynamic>.from(inv.first as Map);
        final ub = first['ubicacion'];
        if (ub is Map) {
          return ub['denominacion']?.toString() ?? '';
        }
        return first['ubicacion_nombre']?.toString() ??
            first['denominacion_ubicacion']?.toString() ??
            first['ubicacion_label']?.toString() ??
            '';
      }
    }
    return '';
  }

  Future<void> _share() async {
    final buf = StringBuffer();
    buf.writeln('IPV / Inventario físico (cache local)');
    buf.writeln('Generado: ${DateTime.now().toIso8601String()}');
    buf.writeln('Productos: ${_filtered.length}');
    buf.writeln('---');
    for (final p in _filtered) {
      final name = p['denominacion'] ?? '';
      final qty = p['cantidad'] ?? 0;
      final sku = p['sku'] ?? '';
      final ubi = _ubicacionOf(p);
      buf.writeln(
        '$name | qty=$qty${sku.toString().isNotEmpty ? ' | sku=$sku' : ''}'
        '${ubi.isNotEmpty ? ' | $ubi' : ''}',
      );
    }
    await Share.share(buf.toString(), subject: 'Reporte IPV offline');
  }

  @override
  Widget build(BuildContext context) {
    final totalQty = _filtered.fold<double>(
      0,
      (s, p) => s + ((p['cantidad'] as num?)?.toDouble() ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('IPV / Inventario'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Imprimir',
            onPressed: _filtered.isEmpty
                ? null
                : () => AdminTicketPrinterService().confirmAndPrint(
                      context,
                      title: 'IPV / Inventario',
                      lines: AdminTicketPrinterService.ipvLines(_filtered),
                    ),
            icon: const Icon(Icons.print),
          ),
          IconButton(
            tooltip: 'Compartir',
            onPressed: _filtered.isEmpty ? null : _share,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Buscar producto',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => _applyFilter(),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Incluir stock 0'),
                  value: _includeZero,
                  onChanged: (v) {
                    setState(() => _includeZero = v);
                    _applyFilter();
                  },
                ),
                Material(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_filtered.length} ítems',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text('Qty total: ${totalQty.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Sin productos para mostrar',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final p = _filtered[i];
                            final ubi = _ubicacionOf(p);
                            return ListTile(
                              dense: true,
                              title: Text(p['denominacion']?.toString() ?? ''),
                              subtitle: Text(
                                [
                                  if (p['sku'] != null) 'SKU ${p['sku']}',
                                  if (ubi.isNotEmpty) ubi,
                                ].join(' · '),
                              ),
                              trailing: Text(
                                '${p['cantidad'] ?? 0}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
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
