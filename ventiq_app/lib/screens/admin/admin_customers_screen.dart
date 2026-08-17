import 'package:flutter/material.dart';

import '../../services/admin_inventory_service.dart';

/// Lista local de clientes (cache offline).
class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});

  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  final _service = AdminInventoryService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _syncing = false;

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

  Future<void> _load({String? q}) async {
    setState(() => _loading = true);
    final list = await _service.listCachedCustomers(query: q);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final n = await _service.syncCrmCacheFromServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cache: ${n['customers']} clientes, ${n['suppliers']} proveedores',
          ),
        ),
      );
      await _load(q: _searchCtrl.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => _load(q: v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'Sin clientes en cache.\nSincroniza online.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = _items[i];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(
                              c['nombre_completo']?.toString() ?? '',
                            ),
                            subtitle: Text(
                              [
                                if (c['codigo_cliente'] != null)
                                  c['codigo_cliente'],
                                if (c['telefono'] != null) c['telefono'],
                                if (c['email'] != null) c['email'],
                              ].where((e) => '$e'.isNotEmpty).join(' · '),
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
