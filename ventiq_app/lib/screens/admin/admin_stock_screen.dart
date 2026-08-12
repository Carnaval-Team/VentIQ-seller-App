import 'package:flutter/material.dart';

import '../../services/admin_inventory_service.dart';

/// Consulta de stock desde cache SQLite offline.
class AdminStockScreen extends StatefulWidget {
  const AdminStockScreen({super.key});

  @override
  State<AdminStockScreen> createState() => _AdminStockScreenState();
}

class _AdminStockScreenState extends State<AdminStockScreen> {
  final _service = AdminInventoryService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

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

  Future<void> _load([String? query]) async {
    setState(() => _loading = true);
    final list = await _service.listCachedProducts(query: query);
    if (!mounted) return;
    setState(() {
      _products = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _load();
                  },
                ),
              ),
              onSubmitted: (v) => _load(v),
              onChanged: (v) {
                if (v.isEmpty) _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(child: Text('Sin productos en cache'))
                    : ListView.separated(
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _products[i];
                          final name =
                              p['denominacion']?.toString() ?? 'Sin nombre';
                          final qty = p['cantidad'];
                          final price = p['precio'];
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(
                              'Precio: ${price ?? '-'}  ·  SKU: ${p['sku'] ?? '-'}',
                            ),
                            trailing: Text(
                              '${qty ?? 0}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue[800],
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
