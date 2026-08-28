import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';
import '../../utils/presentacion_cadena_local.dart';
import '../../utils/presentation_selection.dart';

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

  // ── FASE 2 presentaciones ────────────────────────────────────────────────
  // El ajuste es DISTINTO de recepcion/extraccion: no se capturan varias
  // presentaciones a la vez, porque "cantidad nueva" es un conteo fisico de UNA
  // presentacion concreta. Sumar 2 cajas y 3 unidades en un ajuste no significa
  // nada: hay que decir cuanto hay de cada una, por separado.
  //
  // Asi que aca la cadena sirve para dos cosas: elegir CUAL presentacion se
  // esta contando (antes se mandaba null y el SQL adivinaba la base), y mostrar
  // la equivalencia para que el operador sepa en que esta contando.
  List<PresentacionLocal> _cadena = [];
  int? _idPresentacionElegida;

  PresentacionLocal? get _presentacionElegida {
    for (final p in _cadena) {
      if (p.idPresentacion == _idPresentacionElegida) return p;
    }
    return null;
  }

  String get _nombreBase =>
      PresentacionCadenaLocal.base(_cadena)?.nombre ?? 'unidad';

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
    final cadena = PresentacionCadenaLocal.resolver(p);
    setState(() {
      _selected = p;
      _cadena = cadena;
      // Arranca en la base: es la presentacion en la que se cuenta por defecto y
      // coincide con lo que hacia el SQL cuando se le mandaba null.
      _idPresentacionElegida =
          PresentacionCadenaLocal.base(cadena)?.idPresentacion;
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
    }

    // FASE 2: la presentacion la elige el usuario en el dropdown, resuelta desde
    // el cache con la cascada del SQL. Si el producto no tiene cadena cacheada
    // se manda null y la resuelve fn_insertar_ajuste_inventario2 (que ademas LEE
    // el saldo real en vez de creerle a cantidadAnterior).
    presentationId =
        _idPresentacionElegida ?? PresentationSelection.forInventoryPayload();

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

            // ── FASE 2: en qué presentación se está contando ───────────────
            if (_cadena.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _idPresentacionElegida,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Presentación que se cuenta *',
                  border: OutlineInputBorder(),
                  helperText: 'El ajuste solo toca esta presentación',
                ),
                items: _cadena
                    .map(
                      (p) => DropdownMenuItem<int>(
                        value: p.idPresentacion,
                        child: Text(
                          p.esBase
                              ? '${p.nombre} (base)'
                              : '${p.nombre} = '
                                  '${FormatoPresentacion.cantidad(p.factorRel)} '
                                  '${FormatoPresentacion.plural(_nombreBase, p.factorRel)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => _idPresentacionElegida = v),
              ),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              // La etiqueta dice la unidad para que nadie cuente cajas creyendo
              // que anota unidades.
              labelText: _presentacionElegida == null
                  ? 'Cantidad nueva'
                  : 'Cantidad nueva (${_presentacionElegida!.nombre})',
              border: const OutlineInputBorder(),
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
