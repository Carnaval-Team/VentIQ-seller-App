import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';
import '../../services/user_preferences_service.dart';
import '../../utils/presentacion_cadena_local.dart';
import '../../utils/presentation_selection.dart';
import '../../widgets/captura_mixta_presentacion.dart';

/// Extracción de mercancía (offline-first).
class AdminExtractionScreen extends StatefulWidget {
  const AdminExtractionScreen({super.key});

  @override
  State<AdminExtractionScreen> createState() => _AdminExtractionScreenState();
}

class _AdminExtractionScreenState extends State<AdminExtractionScreen> {
  final _service = AdminInventoryService();
  final _autorizadoCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  List<Map<String, dynamic>> _motives = [];
  int? _motivoId;
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic>? _selected;
  bool _saving = false;
  bool _searching = false;
  bool _loadingMotives = true;

  // ── FASE 2 presentaciones ────────────────────────────────────────────────
  // Las lineas capturadas por presentacion. Vacio = el usuario no escribio
  // nada todavia (o el producto no tiene cadena en el cache).
  List<LineaPresentacion> _lineasMixtas = [];

  /// Si el producto elegido tiene cadena en el cache. Se calcula UNA vez al
  /// seleccionar, no en cada build: resolver() ordena y divide toda la cadena.
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
    if (name.isNotEmpty) _autorizadoCtrl.text = name;

    final motives = await _service.listExtractionMotives();
    if (!mounted) return;
    setState(() {
      _motives = motives;
      _motivoId = (motives.isNotEmpty)
          ? (motives.first['id'] as num?)?.toInt()
          : null;
      _loadingMotives = false;
    });
  }

  @override
  void dispose() {
    _autorizadoCtrl.dispose();
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

    // ── FASE 2: una linea por presentacion con cantidad ────────────────────
    // El widget resuelve la cadena desde el cache; si el producto la tiene,
    // _lineasMixtas trae la presentacion REAL elegida por el usuario en vez del
    // null que mandaba PresentationSelection.
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

    // Fallback: producto sin cadena en el cache. Se manda null y la RPC resuelve
    // la base con fn_presentaciones_producto (cascada correcta, aguanta los 9
    // productos sin fila es_base).
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cantidad inválida')),
      );
      return;
    }

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
    if (_autorizadoCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indica quién autoriza')),
      );
      return;
    }
    if (_motivoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un motivo')),
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
      await _service.registerExtraction(
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
        idMotivoOperacion: _motivoId!,
        autorizadoPor: _autorizadoCtrl.text.trim(),
        observaciones: _obsCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Extracción registrada (se sincronizará si está offline)',
          ),
          backgroundColor: Colors.green,
        ),
      );
      final motivoLabel = _motives
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (m) => (m?['id'] as num?)?.toInt() == _motivoId,
            orElse: () => null,
          );
      await AdminTicketPrinterService().confirmAndPrint(
        context,
        title: 'Extracción',
        lines: AdminTicketPrinterService.extractionLines(
          autorizadoPor: _autorizadoCtrl.text.trim(),
          motivo: motivoLabel?['denominacion']?.toString() ??
              motivoLabel?['nombre']?.toString() ??
              '$_motivoId',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extracción'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _autorizadoCtrl,
            decoration: const InputDecoration(
              labelText: 'Autorizado por',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingMotives)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<int>(
              value: _motivoId,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                border: OutlineInputBorder(),
              ),
              items: _motives
                  .map(
                    (m) => DropdownMenuItem<int>(
                      value: (m['id'] as num?)?.toInt(),
                      child: Text(
                        m['denominacion']?.toString() ??
                            m['nombre']?.toString() ??
                            '#${m['id']}',
                      ),
                    ),
                  )
                  .where((i) => i.value != null)
                  .toList(),
              onChanged: (v) => setState(() => _motivoId = v),
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
          Text('Productos', style: Theme.of(context).textTheme.titleMedium),
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
                  _searchCtrl.text = p['denominacion']?.toString() ?? '';
                  _searchResults = [];
                }),
              ),
            ),
          if (_selected != null) ...[
            const SizedBox(height: 8),
            // FASE 2: un campo por presentacion. Si el producto no tiene cadena
            // en el cache, el widget lo avisa y abajo queda el campo unico.
            CapturaMixtaPresentacion(
              key: ValueKey('ext_${_selected!['id']}'),
              producto: _selected!,
              avisarRebalanceo: true,
              onChanged: (lineas) => setState(() => _lineasMixtas = lineas),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
              // Sin presentacion conocida se muestra la cantidad sola: el
              // ledger no sabe en que unidad esta esa linea.
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
                : const Icon(Icons.outbox),
            label: Text(_saving ? 'Guardando...' : 'Registrar extracción'),
          ),
        ],
      ),
    );
  }
}
