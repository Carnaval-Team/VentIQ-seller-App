import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';

/// Precios diferenciados por TPV (offline-first).
class AdminTpvPricesScreen extends StatefulWidget {
  const AdminTpvPricesScreen({super.key});

  @override
  State<AdminTpvPricesScreen> createState() => _AdminTpvPricesScreenState();
}

class _AdminTpvPricesScreenState extends State<AdminTpvPricesScreen> {
  final _service = AdminInventoryService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _tpvs = [];
  List<Map<String, dynamic>> _prices = [];
  int? _selectedTpv;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final tpvs = await _service.listCachedTpvs();
    if (!mounted) return;
    setState(() {
      _tpvs = tpvs;
      _selectedTpv ??= tpvs.isNotEmpty
          ? (tpvs.first['id'] as num?)?.toInt()
          : null;
    });
    await _loadPrices();
  }

  Future<void> _loadPrices() async {
    setState(() => _loading = true);
    final list = await _service.listCachedTpvPrices(
      idTpv: _selectedTpv,
      query: _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _prices = list;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final n = await _service.syncTpvsAndPricesFromServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cache: ${n['tpvs']} TPVs, ${n['tpv_prices']} precios',
          ),
        ),
      );
      await _bootstrap();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final priceCtrl = TextEditingController(
      text: existing != null
          ? '${existing['precio_venta_cup'] ?? ''}'
          : '',
    );
    final productSearch = TextEditingController(
      text: existing?['producto_nombre']?.toString() ?? '',
    );
    int? productId = (existing?['id_producto'] as num?)?.toInt();
    String? productName = existing?['producto_nombre']?.toString();
    int? tpvId = (existing?['id_tpv'] as num?)?.toInt() ?? _selectedTpv;
    List<Map<String, dynamic>> hits = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Nuevo precio TPV' : 'Editar precio TPV',
              ),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        value: tpvId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'TPV',
                          border: OutlineInputBorder(),
                        ),
                        items: _tpvs
                            .map(
                              (t) => DropdownMenuItem<int>(
                                value: (t['id'] as num?)?.toInt(),
                                child: Text(
                                  t['denominacion']?.toString() ?? '#${t['id']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .where((i) => i.value != null)
                            .toList(),
                        onChanged: existing != null
                            ? null
                            : (v) => setLocal(() => tpvId = v),
                      ),
                      const SizedBox(height: 12),
                      if (existing == null) ...[
                        TextField(
                          controller: productSearch,
                          decoration: const InputDecoration(
                            labelText: 'Buscar producto',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (q) async {
                            if (q.trim().isEmpty) {
                              setLocal(() => hits = []);
                              return;
                            }
                            final list = await _service.listCachedProducts(
                              query: q.trim(),
                            );
                            setLocal(() => hits = list.take(12).toList());
                          },
                        ),
                        if (hits.isNotEmpty)
                          ...hits.map(
                            (p) => ListTile(
                              dense: true,
                              title: Text(p['denominacion']?.toString() ?? ''),
                              subtitle: Text('Precio base: ${p['precio'] ?? 0}'),
                              onTap: () => setLocal(() {
                                productId = (p['id'] as num?)?.toInt();
                                productName =
                                    p['denominacion']?.toString();
                                productSearch.text = productName ?? '';
                                hits = [];
                                if (priceCtrl.text.trim().isEmpty) {
                                  priceCtrl.text = '${p['precio'] ?? ''}';
                                }
                              }),
                            ),
                          ),
                        if (productId != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Producto #$productId',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ] else
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(productName ?? 'Producto #$productId'),
                          subtitle: Text('ID $productId'),
                        ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Precio venta CUP',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
    if (price == null || price < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Precio inválido')),
      );
      return;
    }
    if (productId == null || tpvId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona producto y TPV')),
      );
      return;
    }

    final tpvName = _tpvs
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (t) => (t?['id'] as num?)?.toInt() == tpvId,
          orElse: () => null,
        )?['denominacion']
        ?.toString();

    try {
      await _service.upsertTpvPrice(
        idProducto: productId!,
        idTpv: tpvId!,
        precioVentaCup: price,
        existingPriceId: (existing?['id'] as num?)?.toInt(),
        productoNombre: productName,
        tpvNombre: tpvName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio TPV guardado (sync offline si aplica)'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadPrices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Precios por TPV'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Sincronizar cache',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _tpvs.isEmpty ? null : () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<int?>(
              value: _selectedTpv,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Filtrar TPV',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Todos'),
                ),
                ..._tpvs.map(
                  (t) => DropdownMenuItem<int?>(
                    value: (t['id'] as num?)?.toInt(),
                    child: Text(
                      t['denominacion']?.toString() ?? '#${t['id']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) async {
                setState(() => _selectedTpv = v);
                await _loadPrices();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar producto / TPV',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => _loadPrices(),
            ),
          ),
          if (_tpvs.isEmpty)
            Material(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Sin TPVs en cache. Conéctate y pulsa sync '
                  '(o Preparar dispositivo).',
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _prices.isEmpty
                    ? Center(
                        child: Text(
                          'Sin precios TPV en cache',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _prices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _prices[i];
                          final pending = p['pending_local'] == true;
                          return ListTile(
                            title: Text(
                              p['producto_nombre']?.toString() ??
                                  'Producto #${p['id_producto']}',
                            ),
                            subtitle: Text(
                              [
                                p['tpv_nombre'] ?? 'TPV ${p['id_tpv']}',
                                if (p['producto_sku'] != null)
                                  'SKU ${p['producto_sku']}',
                                if (pending) 'pendiente sync',
                              ].join(' · '),
                            ),
                            trailing: Text(
                              '\$${((p['precio_venta_cup'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            onTap: () => _openEditor(existing: p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
