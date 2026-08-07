import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';

/// Lista de productos + editar precio/costo + alta rápida.
class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
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

  Future<void> _load([String? q]) async {
    setState(() => _loading = true);
    final list = await _service.listCachedProducts(query: q);
    if (!mounted) return;
    setState(() {
      _products = list;
      _loading = false;
    });
  }

  Future<void> _editPrices(Map<String, dynamic> p) async {
    final ventaCtrl = TextEditingController(
      text: '${p['precio'] ?? ''}',
    );
    double? costoActual;
    int? presentationId;
    final detalles = p['detalles_completos'];
    if (detalles is Map) {
      final precios = detalles['precios'];
      if (precios is Map) {
        costoActual = (precios['precio_costo'] as num?)?.toDouble() ??
            (precios['precio_promedio'] as num?)?.toDouble();
      }
      final presentaciones = detalles['presentaciones'];
      if (presentaciones is List && presentaciones.isNotEmpty) {
        final base = presentaciones.cast<Map>().firstWhere(
              (x) => x['es_base'] == true,
              orElse: () => presentaciones.first as Map,
            );
        presentationId = (base['id'] as num?)?.toInt() ??
            (base['id_presentacion'] as num?)?.toInt();
        costoActual ??= (base['precio_promedio'] as num?)?.toDouble();
      }
    }
    final costoCtrl = TextEditingController(
      text: costoActual != null ? '$costoActual' : '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p['denominacion']?.toString() ?? 'Editar precios'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ventaCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Precio venta (CUP)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Costo (USD / promedio)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final venta = double.tryParse(ventaCtrl.text.replaceAll(',', '.'));
    final costo = double.tryParse(costoCtrl.text.replaceAll(',', '.'));
    if (venta == null && costo == null) return;

    try {
      await _service.updateProductPrices(
        productId: (p['id'] as num).toInt(),
        presentationId: presentationId,
        precioVentaCup: venta,
        precioCostoUsd: costo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precios actualizados'),
          backgroundColor: Colors.green,
        ),
      );
      await _load(_searchCtrl.text.isEmpty ? null : _searchCtrl.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createQuick() async {
    final nameCtrl = TextEditingController();
    final ventaCtrl = TextEditingController();
    final costoCtrl = TextEditingController(text: '0');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alta rápida de producto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ventaCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio venta CUP',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: costoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final venta = double.tryParse(ventaCtrl.text.replaceAll(',', '.')) ?? 0;
    final costo = double.tryParse(costoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (name.isEmpty) return;

    try {
      await _service.createProductQuick(
        denominacion: name,
        precioVentaCup: venta,
        precioCostoUsd: costo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Producto encolado / creado'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
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
        title: const Text('Productos'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Alta rápida',
            onPressed: _createQuick,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
                : ListView.separated(
                    itemCount: _products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final p = _products[i];
                      return ListTile(
                        title: Text(p['denominacion']?.toString() ?? ''),
                        subtitle: Text(
                          'Precio: ${p['precio'] ?? '-'}  ·  Stock: ${p['cantidad'] ?? 0}',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editPrices(p),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createQuick,
        backgroundColor: Colors.blue[700],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
