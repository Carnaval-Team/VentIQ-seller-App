import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';
import '../../services/user_preferences_service.dart';

/// Recepción simple de mercancía (offline-first).
class AdminReceptionScreen extends StatefulWidget {
  const AdminReceptionScreen({super.key});

  @override
  State<AdminReceptionScreen> createState() => _AdminReceptionScreenState();
}

class _AdminReceptionScreenState extends State<AdminReceptionScreen> {
  final _service = AdminInventoryService();
  final _entregadoCtrl = TextEditingController();
  final _recibidoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _selectedPresentations = [];
  int? _selectedPresentationId;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _layouts = [];
  int? _idProveedor;
  int? _idUbicacion;
  bool _saving = false;
  bool _searching = false;
  bool _loadingLayouts = false;

  @override
  void initState() {
    super.initState();
    _prefillReceiver();
    _loadSuppliers();
    _loadLayouts();
  }

  Future<void> _loadLayouts() async {
    setState(() => _loadingLayouts = true);
    try {
      final list = await _service.listCachedLayouts();
      if (!mounted) return;
      setState(() {
        _layouts = list;
        _loadingLayouts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingLayouts = false);
    }
  }

  Future<void> _loadSuppliers() async {
    final list = await _service.listCachedSuppliers();
    if (!mounted) return;
    setState(() => _suppliers = list);
  }

  Future<void> _prefillReceiver() async {
    final profile = await UserPreferencesService().getWorkerProfile();
    final name =
        '${profile['nombres'] ?? ''} ${profile['apellidos'] ?? ''}'.trim();
    if (name.isNotEmpty) _recibidoCtrl.text = name;
  }

  @override
  void dispose() {
    _entregadoCtrl.dispose();
    _recibidoCtrl.dispose();
    _obsCtrl.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _extractPresentations(Map<String, dynamic> p) {
    final candidates = [
      p['presentaciones'],
      p['detalles_completos']?['presentaciones'],
      p['detalles_producto']?['presentaciones'],
      p['producto_presentacion'],
      p['presentacion'],
    ];
    for (final raw in candidates) {
      if (raw is List) {
        final list =
            raw
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
        if (list.isNotEmpty) return list;
      }
      if (raw is Map) {
        return [Map<String, dynamic>.from(raw)];
      }
    }
    return [];
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

  void _addLine() {
    final p = _selected;
    if (p == null) return;
    if (_idUbicacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una ubicación de destino')),
      );
      return;
    }
    if (_selectedPresentationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una presentación')),
      );
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad inválida')),
      );
      return;
    }

    final presentationId = _selectedPresentationId;
    if (presentationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El producto no tiene presentación válida')),
      );
      return;
    }

    setState(() {
      _lines.add({
        'id_producto': p['id'],
        'id_variante': null,
        'id_presentacion': presentationId,
        'id_ubicacion': _idUbicacion,
        'cantidad': qty,
        'costo_real': 0,
        'denominacion': p['denominacion'],
      });
      _selected = null;
      _selectedPresentations = [];
      _selectedPresentationId = null;
      _searchCtrl.clear();
      _searchResults = [];
      _qtyCtrl.text = '1';
    });
  }

  Future<void> _save() async {
    if (_entregadoCtrl.text.trim().isEmpty ||
        _recibidoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa entregado por y recibido por')),
      );
      return;
    }
    if (_idUbicacion == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una ubicación de destino')),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.registerReception(
        productos: _lines
            .map(
              (l) => {
                'id_producto': l['id_producto'],
                'id_variante': l['id_variante'],
                'id_presentacion': l['id_presentacion'],
                'id_ubicacion': l['id_ubicacion'],
                'cantidad': l['cantidad'],
                'costo_real': l['costo_real'] ?? 0,
              },
            )
            .toList(),
        entregadoPor: _entregadoCtrl.text.trim(),
        recibidoPor: _recibidoCtrl.text.trim(),
        observaciones: _obsCtrl.text.trim(),
        idProveedor: _idProveedor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recepción registrada (se sincronizará si está offline)'),
          backgroundColor: Colors.green,
        ),
      );
      final proveedorNombre = _suppliers
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (s) => (s?['id'] as num?)?.toInt() == _idProveedor,
            orElse: () => null,
          )?['denominacion']
          ?.toString();
      await AdminTicketPrinterService().confirmAndPrint(
        context,
        title: 'Recepción',
        lines: AdminTicketPrinterService.receptionLines(
          entregadoPor: _entregadoCtrl.text.trim(),
          recibidoPor: _recibidoCtrl.text.trim(),
          productos: _lines,
          proveedor: proveedorNombre,
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
        title: const Text('Recepción'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _entregadoCtrl,
            decoration: const InputDecoration(
              labelText: 'Entregado por',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _recibidoCtrl,
            decoration: const InputDecoration(
              labelText: 'Recibido por',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _idUbicacion,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ubicación de destino *',
              border: OutlineInputBorder(),
            ),
            items: _layouts.map(
              (l) => DropdownMenuItem<int?>(
                value: (l['id'] as num?)?.toInt(),
                child: Text(
                  l['denominacion']?.toString() ?? '#${l['id']}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ).toList(),
            onChanged: (v) => setState(() => _idUbicacion = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _idProveedor,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Proveedor (opcional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Sin proveedor'),
              ),
              ..._suppliers.map(
                (s) => DropdownMenuItem<int?>(
                  value: (s['id'] as num?)?.toInt(),
                  child: Text(
                    s['denominacion']?.toString() ?? '#${s['id']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _idProveedor = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _obsCtrl,
            decoration: const InputDecoration(
              labelText: 'Observaciones',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          const Text('Agregar producto', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar producto...',
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
              constraints: const BoxConstraints(maxHeight: 180),
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
                    onTap: () {
                      final list = _extractPresentations(p);
                      final base = list.cast<Map?>().firstWhere(
                        (x) => x?['es_base'] == true,
                        orElse: () => list.isNotEmpty ? list.first : null,
                      );
                      setState(() {
                        _selected = p;
                        _selectedPresentations = list;
                        _selectedPresentationId =
                            (base?['id'] as num?)?.toInt() ??
                            (base?['id_presentacion'] as num?)?.toInt();
                        _searchCtrl.text = p['denominacion']?.toString() ?? '';
                        _searchResults = [];
                      });
                    },
                  );
                },
              ),
            ),
          if (_selected != null) ...[
            const SizedBox(height: 8),
            if (_selectedPresentations.isNotEmpty)
              DropdownButtonFormField<int?>(
                value: _selectedPresentationId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Presentación *',
                  border: OutlineInputBorder(),
                ),
                items:
                    _selectedPresentations.map(
                      (pres) => DropdownMenuItem<int?>(
                        value:
                            (pres['id'] as num?)?.toInt() ??
                            (pres['id_presentacion'] as num?)?.toInt(),
                        child: Text(
                          '${pres['denominacion']?.toString() ?? ''} '
                          '${pres['es_base'] == true ? '(base)' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ).toList(),
                onChanged:
                    (v) => setState(() => _selectedPresentationId = v),
              ),
            if (_selectedPresentations.isNotEmpty) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addLine,
                  child: const Text('Agregar'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          ..._lines.asMap().entries.map((e) {
            final i = e.key;
            final l = e.value;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l['denominacion']?.toString() ?? 'Producto'),
              subtitle: Text('Cantidad: ${l['cantidad']}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() => _lines.removeAt(i)),
              ),
            );
          }),
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
            label: Text(_saving ? 'Guardando...' : 'Registrar recepción'),
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
