import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';
import '../../services/user_preferences_service.dart';
import '../../utils/presentacion_cadena_local.dart';
import '../../utils/presentation_selection.dart';
import '../../widgets/captura_mixta_presentacion.dart';

/// Transferencia entre layouts/ubicaciones (offline-first).
class AdminTransferScreen extends StatefulWidget {
  const AdminTransferScreen({super.key});

  @override
  State<AdminTransferScreen> createState() => _AdminTransferScreenState();
}

class _AdminTransferScreenState extends State<AdminTransferScreen> {
  final _service = AdminInventoryService();
  final _entregadoCtrl = TextEditingController();
  final _transportadoCtrl = TextEditingController();
  final _recibidoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  List<Map<String, dynamic>> _layouts = [];
  int? _origenId;
  int? _destinoId;
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic>? _selected;
  bool _loadingLayouts = true;
  bool _saving = false;
  bool _searching = false;

  // ── FASE 2 presentaciones ────────────────────────────────────────────────
  // Transferir 2 cajas mueve 2 cajas (la RPC ya no aplana a base), asi que la
  // presentacion elegida por el usuario ahora SI importa.
  List<LineaPresentacion> _lineasMixtas = [];
  bool _tieneCadena = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final profile = await UserPreferencesService().getWorkerProfile();
    final name =
        '${profile['nombres'] ?? ''} ${profile['apellidos'] ?? ''}'.trim();
    if (name.isNotEmpty) {
      _entregadoCtrl.text = name;
      _transportadoCtrl.text = name;
      _recibidoCtrl.text = name;
    }

    final layouts = await _service.listCachedLayouts();
    if (!mounted) return;
    setState(() {
      _layouts = layouts;
      if (layouts.length >= 2) {
        _origenId = (layouts[0]['id'] as num?)?.toInt();
        _destinoId = (layouts[1]['id'] as num?)?.toInt();
      } else if (layouts.length == 1) {
        _origenId = (layouts[0]['id'] as num?)?.toInt();
      }
      _loadingLayouts = false;
    });
  }

  @override
  void dispose() {
    _entregadoCtrl.dispose();
    _transportadoCtrl.dispose();
    _recibidoCtrl.dispose();
    _obsCtrl.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
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

  void _addLine() {
    final p = _selected;
    if (p == null) return;

    // ── FASE 2: una linea por presentacion ─────────────────────────────────
    if (_lineasMixtas.isNotEmpty) {
      setState(() {
        for (final linea in _lineasMixtas) {
          _lines.add({
            'id_producto': p['id'],
            'id_variante': null,
            'id_presentacion': linea.presentacion.idPresentacion,
            'cantidad': linea.cantidad,
            'denominacion': p['denominacion'],
            'presentacion_nombre': linea.presentacion.nombre,
          });
        }
        _limpiarSeleccion();
      });
      return;
    }

    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad inválida')),
      );
      return;
    }

    // Fallback sin cadena en el cache: la resuelve el SQL.
    final int? presentationId = PresentationSelection.forInventoryPayload();

    setState(() {
      _lines.add({
        'id_producto': p['id'],
        'id_variante': null,
        'id_presentacion': presentationId,
        'cantidad': qty,
        'denominacion': p['denominacion'],
      });
      _limpiarSeleccion();
    });
  }

  void _limpiarSeleccion() {
    _selected = null;
    _lineasMixtas = [];
    _tieneCadena = false;
    _searchCtrl.clear();
    _searchResults = [];
    _qtyCtrl.text = '1';
  }

  Future<void> _save() async {
    if (_origenId == null || _destinoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecciona origen y destino. Si no hay layouts, prepara el '
            'dispositivo online primero.',
          ),
        ),
      );
      return;
    }
    if (_entregadoCtrl.text.trim().isEmpty ||
        _transportadoCtrl.text.trim().isEmpty ||
        _recibidoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa entregado, transportado y recibido por'),
        ),
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
      await _service.registerTransfer(
        idLayoutOrigen: _origenId!,
        idLayoutDestino: _destinoId!,
        productos: _lines
            .map(
              (l) => {
                'id_producto': l['id_producto'],
                'id_variante': l['id_variante'],
                'id_presentacion': l['id_presentacion'],
                'cantidad': l['cantidad'],
              },
            )
            .toList(),
        entregadoPor: _entregadoCtrl.text.trim(),
        transportadoPor: _transportadoCtrl.text.trim(),
        recibidoPor: _recibidoCtrl.text.trim(),
        observaciones: _obsCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Transferencia registrada (se sincronizará si está offline)',
          ),
          backgroundColor: Colors.green,
        ),
      );
      String layoutLabel(int? id) {
        final hit = _layouts.cast<Map<String, dynamic>?>().firstWhere(
              (l) => (l?['id'] as num?)?.toInt() == id,
              orElse: () => null,
            );
        return hit?['label']?.toString() ??
            hit?['denominacion']?.toString() ??
            '$id';
      }

      await AdminTicketPrinterService().confirmAndPrint(
        context,
        title: 'Transferencia',
        lines: AdminTicketPrinterService.transferLines(
          origen: layoutLabel(_origenId),
          destino: layoutLabel(_destinoId),
          entregadoPor: _entregadoCtrl.text.trim(),
          productos: _lines,
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

  Widget _layoutDropdown({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: _layouts
          .map(
            (l) => DropdownMenuItem<int>(
              value: (l['id'] as num?)?.toInt(),
              child: Text(
                l['label']?.toString() ??
                    l['denominacion']?.toString() ??
                    '#${l['id']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .where((i) => i.value != null)
          .toList(),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transferencia'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar layouts',
            onPressed: _loadingLayouts
                ? null
                : () async {
                    setState(() => _loadingLayouts = true);
                    await _service.syncLayoutsFromServer();
                    await _bootstrap();
                  },
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _loadingLayouts
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_layouts.isEmpty)
                  Card(
                    color: Colors.orange.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No hay layouts en cache. Conéctate y pulsa sync '
                        '(o Preparar dispositivo offline) para descargarlos.',
                      ),
                    ),
                  ),
                _layoutDropdown(
                  label: 'Origen',
                  value: _origenId,
                  onChanged: (v) => setState(() => _origenId = v),
                ),
                const SizedBox(height: 12),
                _layoutDropdown(
                  label: 'Destino',
                  value: _destinoId,
                  onChanged: (v) => setState(() => _destinoId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _entregadoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Entregado por',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _transportadoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Transportado por',
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
                TextField(
                  controller: _obsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Productos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar producto',
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
                  ..._searchResults.map(
                    (p) => ListTile(
                      title: Text(p['denominacion']?.toString() ?? ''),
                      subtitle: Text('Stock: ${p['cantidad'] ?? 0}'),
                      onTap: () => setState(() {
                        _selected = p;
                        _lineasMixtas = [];
                        _tieneCadena =
                            PresentacionCadenaLocal.resolver(p).isNotEmpty;
                        _searchCtrl.text =
                            p['denominacion']?.toString() ?? '';
                        _searchResults = [];
                      }),
                    ),
                  ),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  // FASE 2: un campo por presentacion. avisarRebalanceo porque
                  // la extraccion del origen puede abrir un empaque.
                  CapturaMixtaPresentacion(
                    key: ValueKey('trf_${_selected!['id']}'),
                    producto: _selected!,
                    avisarRebalanceo: true,
                    onChanged: (lineas) =>
                        setState(() => _lineasMixtas = lineas),
                  ),
                  if (!_tieneCadena) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
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
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addLine,
                          child: const Text('Agregar'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _addLine,
                        child: const Text('Agregar'),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                ..._lines.asMap().entries.map((e) {
                  final i = e.key;
                  final l = e.value;
                  final cant = (l['cantidad'] as num?)?.toDouble() ?? 0;
                  final pres = l['presentacion_nombre']?.toString();
                  return ListTile(
                    title: Text(l['denominacion']?.toString() ?? 'Producto'),
                    subtitle: Text(
                      pres == null || pres.isEmpty
                          ? 'Cantidad: ${FormatoPresentacion.cantidad(cant)}'
                          : '${FormatoPresentacion.cantidad(cant)} '
                              '${FormatoPresentacion.plural(pres, cant)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _lines.removeAt(i)),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz),
                  label: Text(
                    _saving ? 'Guardando...' : 'Registrar transferencia',
                  ),
                ),
              ],
            ),
    );
  }
}
