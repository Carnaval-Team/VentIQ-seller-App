import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';
import '../../services/user_preferences_service.dart';
import '../../utils/presentacion_cadena_local.dart';

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

  // ── FASE 2 presentaciones: captura mixta offline ─────────────────────────
  // La cadena se resuelve desde el payload cacheado con la misma cascada que
  // fn_presentaciones_producto (ver utils/presentacion_cadena_local.dart), asi
  // que funciona sin red. El modo mixto solo se ofrece con 2+ presentaciones.
  List<PresentacionLocal> _cadena = [];
  bool _modoMixto = false;
  final Map<int, TextEditingController> _ctrlPorPresentacion = {};

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
    for (final c in _ctrlPorPresentacion.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Deja listos los controllers del modo mixto para la cadena del producto.
  void _prepararMixto(List<PresentacionLocal> cadena) {
    for (final c in _ctrlPorPresentacion.values) {
      c.dispose();
    }
    _ctrlPorPresentacion.clear();
    for (final p in cadena) {
      _ctrlPorPresentacion[p.idPresentacion] = TextEditingController();
    }
  }

  double _cantidadDe(int idPresentacion) {
    final txt =
        _ctrlPorPresentacion[idPresentacion]?.text.trim().replaceAll(',', '.');
    if (txt == null || txt.isEmpty) return 0;
    return double.tryParse(txt) ?? 0;
  }

  Map<int, double> get _cantidadesMixtas {
    final out = <int, double>{};
    for (final p in _cadena) {
      final v = _cantidadDe(p.idPresentacion);
      if (v > 0) out[p.idPresentacion] = v;
    }
    return out;
  }

  String get _nombreBase =>
      PresentacionCadenaLocal.base(_cadena)?.nombre ?? 'unidad';

  List<Map<String, dynamic>> _extractPresentations(Map<String, dynamic> p) {
    // Delegado al helper compartido: antes cada pantalla repetia esta cascada
    // de candidatos y se desincronizaban entre si.
    return PresentacionCadenaLocal.extraerCrudas(p);
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

    // ── Modo mixto: una linea por presentacion con cantidad ────────────────
    if (_modoMixto) {
      final cantidades = _cantidadesMixtas;
      if (cantidades.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Escribe la cantidad de al menos una presentación'),
          ),
        );
        return;
      }

      setState(() {
        // Se recorre la cadena (no el mapa) para que las lineas queden en el
        // orden del empaque mayor al menor, igual que en los reportes.
        for (final pres in _cadena) {
          final qty = cantidades[pres.idPresentacion];
          if (qty == null) continue;
          _lines.add({
            'id_producto': p['id'],
            'id_variante': null,
            'id_presentacion': pres.idPresentacion,
            'id_ubicacion': _idUbicacion,
            'cantidad': qty,
            'costo_real': 0,
            'denominacion': p['denominacion'],
            // Para el ticket y la lista: el ledger guarda el id, el texto es
            // para el humano.
            'presentacion_nombre': pres.nombre,
          });
        }
        _limpiarSeleccion();
      });
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
        'presentacion_nombre': _cadena
            .where((x) => x.idPresentacion == presentationId)
            .map((x) => x.nombre)
            .firstOrNull,
      });
      _limpiarSeleccion();
    });
  }

  void _limpiarSeleccion() {
    _selected = null;
    _selectedPresentations = [];
    _selectedPresentationId = null;
    _cadena = [];
    _modoMixto = false;
    _prepararMixto(const []);
    _searchCtrl.clear();
    _searchResults = [];
    _qtyCtrl.text = '1';
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

  /// Alterna entre captura mixta y una sola presentacion.
  Widget _buildSelectorModo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(
            _modoMixto ? Icons.view_list : Icons.looks_one,
            size: 18,
            color: Colors.blue[700],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _modoMixto
                  ? 'Varias presentaciones a la vez'
                  : 'Una sola presentación',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _modoMixto = !_modoMixto;
                // Cambiar de modo descarta lo escrito en el otro: dejarlo
                // guardaria cantidades que el formulario visible ya no muestra.
                for (final c in _ctrlPorPresentacion.values) {
                  c.clear();
                }
                _qtyCtrl.text = '1';
              });
            },
            child: Text(
              _modoMixto ? 'Cambiar a una' : 'Cambiar a varias',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Un campo por eslabon de la cadena, del empaque mayor al menor.
  Widget _buildCapturaMixta() {
    final cantidades = _cantidadesMixtas;
    final equivalente =
        PresentacionCadenaLocal.equivalenteBase(_cadena, cantidades);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._cadena.map(
          (pres) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pres.nombre,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        FormatoPresentacion.equivalencia(pres, _nombreBase),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ctrlPorPresentacion[pres.idPresentacion],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      hintText: '0',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Resumen en el formato acordado: mixto + equivalente.
        if (cantidades.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FormatoPresentacion.mixto(_cadena, cantidades),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade900,
                  ),
                ),
                if (cantidades.length > 1)
                  Text(
                    '= ${FormatoPresentacion.cantidad(equivalente)} '
                    '${FormatoPresentacion.plural(_nombreBase, equivalente)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
              ],
            ),
          ),

        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _addLine,
            child: const Text('Agregar'),
          ),
        ),
      ],
    );
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
                      final crudas = _extractPresentations(p);
                      // La cadena se resuelve con la cascada del SQL, no con un
                      // firstWhere(es_base): hay 9 productos sin fila es_base y
                      // 1 con tres marcadas.
                      final cadena =
                          PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
                      final base = PresentacionCadenaLocal.base(cadena);
                      setState(() {
                        _selected = p;
                        _selectedPresentations = crudas;
                        _cadena = cadena;
                        _selectedPresentationId = base?.idPresentacion;
                        // Con 2+ presentaciones el mixto es lo que la fase vino
                        // a habilitar; con una sola seria el mismo formulario
                        // con mas pasos.
                        _modoMixto = cadena.length > 1;
                        _prepararMixto(cadena);
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

            // ── FASE 2: selector de modo (solo con cadena real) ────────────
            if (_cadena.length > 1) ...[
              _buildSelectorModo(),
              const SizedBox(height: 8),
            ],

            if (_modoMixto)
              _buildCapturaMixta()
            else ...[
              if (_selectedPresentations.isNotEmpty)
                DropdownButtonFormField<int?>(
                  value: _selectedPresentationId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Presentación *',
                    border: OutlineInputBorder(),
                  ),
                  items: _cadena.isNotEmpty
                      ? _cadena
                          .map(
                            (pres) => DropdownMenuItem<int?>(
                              value: pres.idPresentacion,
                              child: Text(
                                pres.esBase
                                    ? '${pres.nombre} (base)'
                                    : '${pres.nombre} '
                                        '= ${FormatoPresentacion.cantidad(pres.factorRel)} '
                                        '${FormatoPresentacion.plural(_nombreBase, pres.factorRel)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList()
                      : _selectedPresentations
                          .map(
                            (pres) => DropdownMenuItem<int?>(
                              value: (pres['id'] as num?)?.toInt(),
                              child: Text(
                                pres['denominacion']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedPresentationId = v),
                ),
              if (_selectedPresentations.isNotEmpty)
                const SizedBox(height: 8),
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
          ],
          const SizedBox(height: 16),
          ..._lines.asMap().entries.map((e) {
            final i = e.key;
            final l = e.value;
            final cant = (l['cantidad'] as num?)?.toDouble() ?? 0;
            final pres = l['presentacion_nombre']?.toString();
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l['denominacion']?.toString() ?? 'Producto'),
              // FASE 2: la linea dice "4 Bultos", no "Cantidad: 4.0". Sin
              // presentacion conocida se muestra la cantidad sola: el ledger no
              // sabe en que unidad esta.
              subtitle: Text(
                pres == null || pres.isEmpty
                    ? 'Cantidad: ${FormatoPresentacion.cantidad(cant)}'
                    : '${FormatoPresentacion.cantidad(cant)} '
                        '${FormatoPresentacion.plural(pres, cant)}',
              ),
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
