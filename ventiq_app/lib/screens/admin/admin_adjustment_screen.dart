import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';

/// Ajuste de inventario (offline-first).
class AdminAdjustmentScreen extends StatefulWidget {
  const AdminAdjustmentScreen({super.key});

  @override
  State<AdminAdjustmentScreen> createState() => _AdminAdjustmentScreenState();
}

class _AdminAdjustmentScreenState extends State<AdminAdjustmentScreen> {
  final _service = AdminInventoryService();
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _motivoCtrl = TextEditingController(text: 'Ajuste desde Caja');
  final _obsCtrl = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selected;
  bool _saving = false;
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _motivoCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    final list = await _service.listCachedProducts(query: q.trim());
    if (!mounted) return;
    setState(() {
      _searchResults = list.take(20).toList();
      _searching = false;
    });
  }

  void _select(Map<String, dynamic> p) {
    setState(() {
      _selected = p;
      _searchCtrl.text = p['denominacion']?.toString() ?? '';
      _searchResults = [];
      _qtyCtrl.text = '${p['cantidad'] ?? 0}';
    });
  }

  Future<void> _save() async {
    final p = _selected;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un producto')),
      );
      return;
    }
    final nueva = double.tryParse(_qtyCtrl.text.replaceAll(',', '.'));
    if (nueva == null || nueva < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad inválida')),
      );
      return;
    }

    final anterior = (p['cantidad'] as num?)?.toDouble() ?? 0;
    int? presentationId;
    int? locationId;
    final detalles = p['detalles_completos'];
    if (detalles is Map) {
      final inv = detalles['inventario'];
      if (inv is List && inv.isNotEmpty) {
        final first = Map<String, dynamic>.from(inv.first as Map);
        locationId = (first['id_ubicacion'] as num?)?.toInt() ??
            (first['ubicacion'] is Map
                ? (first['ubicacion']['id'] as num?)?.toInt()
                : null);
      }
      final presentaciones = detalles['presentaciones'];
      if (presentaciones is List && presentaciones.isNotEmpty) {
        final base = presentaciones.cast<Map>().firstWhere(
              (x) => x['es_base'] == true,
              orElse: () => presentaciones.first as Map,
            );
        presentationId = (base['id'] as num?)?.toInt() ??
            (base['id_presentacion'] as num?)?.toInt();
      }
    }

    setState(() => _saving = true);
    try {
      await _service.adjustStock(
        productId: (p['id'] as num).toInt(),
        presentationId: presentationId,
        locationId: locationId,
        cantidadAnterior: anterior,
        cantidadNueva: nueva,
        motivo: _motivoCtrl.text.trim().isEmpty
            ? 'Ajuste desde Caja'
            : _motivoCtrl.text.trim(),
        observaciones: _obsCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajuste registrado'),
          backgroundColor: Colors.green,
        ),
      );
      await AdminTicketPrinterService().confirmAndPrint(
        context,
        title: 'Ajuste inventario',
        lines: AdminTicketPrinterService.adjustmentLines(
          producto: p['denominacion']?.toString() ?? '#${p['id']}',
          anterior: anterior,
          nueva: nueva,
          motivo: _motivoCtrl.text.trim().isEmpty
              ? 'Ajuste desde Caja'
              : _motivoCtrl.text.trim(),
          observaciones: _obsCtrl.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajuste de inventario'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: 'Producto',
              border: const OutlineInputBorder(),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.search),
            ),
            onChanged: _search,
          ),
          if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, i) {
                  final p = _searchResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(p['denominacion']?.toString() ?? ''),
                    subtitle: Text('Stock: ${p['cantidad'] ?? 0}'),
                    onTap: () => _select(p),
                  );
                },
              ),
            ),
          if (_selected != null) ...[
            const SizedBox(height: 12),
            Text(
              'Stock actual: ${_selected!['cantidad'] ?? 0}',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Cantidad nueva',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _motivoCtrl,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observaciones',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Guardando...' : 'Guardar ajuste'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }
}
