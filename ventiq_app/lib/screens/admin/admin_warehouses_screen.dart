import 'package:flutter/material.dart';

import '../../services/admin_inventory_service.dart';

/// Stock agrupado por ubicación/layout a partir del cache local.
class AdminWarehousesScreen extends StatefulWidget {
  const AdminWarehousesScreen({super.key});

  @override
  State<AdminWarehousesScreen> createState() => _AdminWarehousesScreenState();
}

class _AdminWarehousesScreenState extends State<AdminWarehousesScreen> {
  final _service = AdminInventoryService();
  bool _loading = true;
  Map<String, List<Map<String, dynamic>>> _byLocation = {};
  Map<int, String> _layoutNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final layouts = await _service.listCachedLayouts();
    final names = <int, String>{};
    for (final l in layouts) {
      final id = (l['id'] as num?)?.toInt();
      if (id == null) continue;
      names[id] = l['label']?.toString() ??
          l['denominacion']?.toString() ??
          'Ubicación $id';
    }

    final products = await _service.listCachedProducts();
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final p in products) {
      int? ubicacionId;
      String? ubicacionName;
      String? almacenName;
      final detalles = p['detalles_completos'];
      if (detalles is Map) {
        final inv = detalles['inventario'];
        if (inv is List && inv.isNotEmpty) {
          final first = inv.first;
          if (first is Map) {
            final firstMap = Map<String, dynamic>.from(first as Map);
            final ubMap = firstMap['ubicacion'] is Map
                ? Map<String, dynamic>.from(firstMap['ubicacion'] as Map)
                : null;
            final almMap = ubMap?['almacen'] is Map
                ? Map<String, dynamic>.from(ubMap!['almacen'] as Map)
                : null;
            ubicacionId = (firstMap['id_ubicacion'] as num?)?.toInt() ??
                (ubMap?['id'] as num?)?.toInt() ??
                (p['id_ubicacion'] as num?)?.toInt();
            ubicacionName = firstMap['ubicacion_nombre']?.toString() ??
                firstMap['denominacion_ubicacion']?.toString() ??
                firstMap['ubicacion_label']?.toString() ??
                ubMap?['denominacion']?.toString() ??
                p['ubicacion_nombre']?.toString();
            almacenName = firstMap['almacen_nombre']?.toString() ??
                almMap?['denominacion']?.toString() ??
                p['almacen_nombre']?.toString();
          }
        }
      }
      ubicacionId ??= (p['id_ubicacion'] as num?)?.toInt();
      ubicacionName ??= p['ubicacion_nombre']?.toString();
      almacenName ??= p['almacen_nombre']?.toString();

      String displayName;
      if (ubicacionId != null && names.containsKey(ubicacionId)) {
        displayName = names[ubicacionId]!;
      } else if (ubicacionName != null && ubicacionName.isNotEmpty) {
        displayName = almacenName != null && almacenName.isNotEmpty
            ? '$almacenName · $ubicacionName'
            : ubicacionName;
      } else if (almacenName != null && almacenName.isNotEmpty) {
        displayName = almacenName;
      } else if (ubicacionId != null) {
        displayName = 'Ubicación $ubicacionId';
      } else {
        displayName = 'Sin ubicación en cache';
      }
      grouped.putIfAbsent(displayName, () => []).add(p);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    final ordered = <String, List<Map<String, dynamic>>>{};
    for (final k in sortedKeys) {
      final list = grouped[k]!;
      list.sort(
        (a, b) => (a['denominacion']?.toString() ?? '').compareTo(
          b['denominacion']?.toString() ?? '',
        ),
      );
      ordered[k] = list;
    }

    if (!mounted) return;
    setState(() {
      _layoutNames = names;
      _byLocation = ordered;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock por ubicación'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _byLocation.isEmpty
              ? Center(
                  child: Text(
                    'No hay productos en cache',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                )
              : ListView(
                  children: [
                    if (_layoutNames.isEmpty)
                      Material(
                        color: Colors.orange.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Layouts no cacheados: sincroniza productos/'
                            'ubicaciones (Preparar dispositivo o Sync selectivo). '
                            'Se agrupa con la ubicación embebida si existe.',
                          ),
                        ),
                      ),
                    ..._byLocation.entries.map((entry) {
                      final products = entry.value;
                      final totalQty = products.fold<double>(
                        0,
                        (sum, p) =>
                            sum + ((p['cantidad'] as num?)?.toDouble() ?? 0),
                      );
                      return ExpansionTile(
                        initiallyExpanded: _byLocation.length == 1,
                        title: Text(entry.key),
                        subtitle: Text(
                          '${products.length} producto(s) · qty $totalQty',
                        ),
                        children: products
                            .map(
                              (p) => ListTile(
                                dense: true,
                                title: Text(
                                  p['denominacion']?.toString() ?? '',
                                ),
                                trailing: Text('${p['cantidad'] ?? 0}'),
                              ),
                            )
                            .toList(),
                      );
                    }),
                  ],
                ),
    );
  }
}
