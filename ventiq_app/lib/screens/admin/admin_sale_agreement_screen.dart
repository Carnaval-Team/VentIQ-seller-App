import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_inventory_service.dart';
import '../../services/admin_ticket_printer_service.dart';
import '../../services/payment_method_service.dart';
import '../../services/user_preferences_service.dart';
import '../../utils/presentacion_cadena_local.dart';
import '../../utils/presentation_selection.dart';
import '../../widgets/captura_mixta_presentacion.dart';

/// Venta por acuerdo simplificada (offline-first).
class AdminSaleAgreementScreen extends StatefulWidget {
  const AdminSaleAgreementScreen({super.key});

  @override
  State<AdminSaleAgreementScreen> createState() =>
      _AdminSaleAgreementScreenState();
}

class _AdminSaleAgreementScreenState extends State<AdminSaleAgreementScreen> {
  final _service = AdminInventoryService();
  final _prefs = UserPreferencesService();
  final _clienteCtrl = TextEditingController();
  final _obsCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  List<Map<String, dynamic>> _paymentMethods = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _customerHits = [];
  int? _medioPagoId;
  int? _idTpv;
  int? _idCliente;
  List<Map<String, dynamic>> _searchResults = [];
  final List<Map<String, dynamic>> _lines = [];
  Map<String, dynamic>? _selected;
  // FASE 4 presentaciones: lineas capturadas por presentacion en el widget mixto.
  List<LineaPresentacion> _lineasMixtas = [];
  // Se calcula al SELECCIONAR, no en el build: resolver() ordena y parte toda la
  // cadena y el build corre en cada tecla.
  bool _tieneCadena = false;
  bool _loading = true;
  bool _saving = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final idTpv = await _prefs.getIdTpv();
    final offline = await _prefs.shouldUseLocalData();
    final methods = await PaymentMethodService.getPaymentMethodsWithCache(
      isOfflineModeEnabled: offline,
    );
    final customers = await _service.listCachedCustomers();
    if (!mounted) return;
    setState(() {
      _idTpv = idTpv;
      _customers = customers;
      _paymentMethods = methods
          .where((m) => m.esActivo)
          .map((m) => m.toJson())
          .toList();
      _medioPagoId = _paymentMethods.isNotEmpty
          ? (_paymentMethods.first['id'] as num?)?.toInt()
          : null;
      _loading = false;
    });
  }

  void _onClienteChanged(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _customerHits = [];
        _idCliente = null;
      });
      return;
    }
    setState(() {
      _idCliente = null;
      _customerHits = _customers
          .where((c) {
            final name =
                c['nombre_completo']?.toString().toLowerCase() ?? '';
            final phone = c['telefono']?.toString().toLowerCase() ?? '';
            return name.contains(query) || phone.contains(query);
          })
          .take(8)
          .toList();
    });
  }

  @override
  void dispose() {
    _clienteCtrl.dispose();
    _obsCtrl.dispose();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  double get _total {
    double t = 0;
    for (final l in _lines) {
      final qty = (l['cantidad'] as num?)?.toDouble() ?? 0;
      final price = (l['precio_unitario'] as num?)?.toDouble() ?? 0;
      t += qty * price;
    }
    return t;
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

  double _priceOf(Map<String, dynamic> p) {
    final direct = (p['precio'] as num?)?.toDouble();
    if (direct != null && direct > 0) return direct;
    final detalles = p['detalles_completos'];
    if (detalles is Map) {
      final precios = detalles['precios'];
      if (precios is Map) {
        return (precios['precio_venta_cup'] as num?)?.toDouble() ?? 0;
      }
    }
    return 0;
  }

  void _addLine() {
    final p = _selected;
    if (p == null) return;

    int? ubicacionId;
    final detalles = p['detalles_completos'];
    if (detalles is Map) {
      final inv = detalles['inventario'];
      if (inv is List && inv.isNotEmpty && inv.first is Map) {
        ubicacionId = (inv.first['id_ubicacion'] as num?)?.toInt();
      }
    }

    final price = _priceOf(p);

    // ── FASE 4: una linea por presentacion, con su cantidad y su precio ──────
    //
    // El precio del catalogo es POR UNIDAD BASE, asi que para una Caja de 12 hay
    // que multiplicarlo por el factor. Es la misma convencion que usa el TPV
    // (`product_details_screen`): cantidad en la presentacion, precio x factor.
    // Sin esto se venderia una Caja al precio de una Unidad.
    if (_lineasMixtas.isNotEmpty) {
      setState(() {
        for (final linea in _lineasMixtas) {
          _lines.add({
            'id_producto': p['id'],
            'id_variante': null,
            'id_opcion_variante': null,
            'id_ubicacion': ubicacionId,
            'id_presentacion': linea.presentacion.idPresentacion,
            'cantidad': linea.cantidad,
            'precio_unitario': price * linea.presentacion.factorRel,
            'sku_producto': p['sku']?.toString() ?? '${p['id']}',
            'es_producto_venta': true,
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

    setState(() {
      _lines.add({
        'id_producto': p['id'],
        'id_variante': null,
        'id_opcion_variante': null,
        'id_ubicacion': ubicacionId,
        // FASE 1 presentaciones: se manda null si no hay presentacion elegida,
        // NO `?? 1`. Ese 1 era el id de la presentacion de OTRO producto y la
        // validacion de la RPC ahora lo rechaza con un error explicito.
        'id_presentacion': PresentationSelection.forInventoryPayload(),
        'cantidad': qty,
        'precio_unitario': price,
        'sku_producto': p['sku']?.toString() ?? '${p['id']}',
        'es_producto_venta': true,
        'denominacion': p['denominacion'],
      });
      _limpiarSeleccion();
    });
  }

  /// "2 Cajas" o "2" si no se conoce la presentación de la línea.
  ///
  /// FASE 4. No se inventa la palabra "unidades" cuando falta la presentación:
  /// la línea no sabe en qué unidad está (misma regla que `FormatoPresentacion`).
  String _cantidadConPresentacion(Map<String, dynamic> l) {
    final cant = (l['cantidad'] as num?)?.toDouble() ?? 0;
    final n = FormatoPresentacion.cantidad(cant);
    final pres = l['presentacion_nombre']?.toString();
    if (pres == null || pres.isEmpty) return n;
    return '$n ${FormatoPresentacion.plural(pres, cant)}';
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
    if (_idTpv == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin TPV en sesión. Inicia sesión online o prepara el dispositivo.',
          ),
        ),
      );
      return;
    }
    if (_medioPagoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona medio de pago')),
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
      await _service.registerSaleByAgreement(
        productos: _lines
            .map(
              (l) => {
                'id_producto': l['id_producto'],
                'id_variante': l['id_variante'],
                'id_opcion_variante': l['id_opcion_variante'],
                'id_ubicacion': l['id_ubicacion'],
                'id_presentacion': l['id_presentacion'],
                'cantidad': l['cantidad'],
                'precio_unitario': l['precio_unitario'],
                'sku_producto': l['sku_producto'],
                'es_producto_venta': true,
              },
            )
            .toList(),
        idTpv: _idTpv!,
        idMedioPago: _medioPagoId!,
        montoTotal: _total,
        cliente: _clienteCtrl.text.trim(),
        observaciones: _obsCtrl.text.trim(),
        idCliente: _idCliente,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Venta por acuerdo registrada (se sincronizará si está offline)',
          ),
          backgroundColor: Colors.green,
        ),
      );
      final medioNombre = _paymentMethods
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (m) => (m?['id'] as num?)?.toInt() == _medioPagoId,
            orElse: () => null,
          )?['denominacion']
          ?.toString();
      await AdminTicketPrinterService().confirmAndPrint(
        context,
        title: 'Venta por acuerdo',
        lines: AdminTicketPrinterService.saleAgreementLines(
          cliente: _clienteCtrl.text.trim(),
          medioPago: medioNombre ?? '$_medioPagoId',
          total: _total,
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
        title: const Text('Venta por acuerdo'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_idTpv == null)
                  Card(
                    color: Colors.orange.shade50,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No hay TPV asociado a esta sesión. La venta no se '
                        'podrá sincronizar hasta tener id_tpv.',
                      ),
                    ),
                  ),
                TextField(
                  controller: _clienteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cliente (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _onClienteChanged,
                ),
                if (_customerHits.isNotEmpty)
                  ..._customerHits.map(
                    (c) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(c['nombre_completo']?.toString() ?? ''),
                      subtitle: Text(c['telefono']?.toString() ?? ''),
                      onTap: () => setState(() {
                        _idCliente = (c['id'] as num?)?.toInt();
                        _clienteCtrl.text =
                            c['nombre_completo']?.toString() ?? '';
                        _customerHits = [];
                      }),
                    ),
                  ),
                if (_idCliente != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Cliente cacheado #$_idCliente',
                      style: TextStyle(color: Colors.green[700], fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _medioPagoId,
                  decoration: const InputDecoration(
                    labelText: 'Medio de pago',
                    border: OutlineInputBorder(),
                  ),
                  items: _paymentMethods
                      .map(
                        (m) => DropdownMenuItem<int>(
                          value: (m['id'] as num?)?.toInt(),
                          child: Text(m['denominacion']?.toString() ?? ''),
                        ),
                      )
                      .where((i) => i.value != null)
                      .toList(),
                  onChanged: (v) => setState(() => _medioPagoId = v),
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
                      subtitle: Text(
                        'Stock: ${p['cantidad'] ?? 0} · '
                        '\$${_priceOf(p).toStringAsFixed(2)}',
                      ),
                      onTap: () => setState(() {
                        _selected = p;
                        _lineasMixtas = [];
                        // FASE 4: se resuelve aqui, no en el build.
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
                  // FASE 4: un campo por presentacion. Si el producto no tiene
                  // cadena en el cache, el widget lo avisa y abajo queda el
                  // campo unico de siempre.
                  CapturaMixtaPresentacion(
                    key: ValueKey('acuerdo_${_selected!['id']}'),
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
                  final lineTotal =
                      ((l['cantidad'] as num?)?.toDouble() ?? 0) *
                          ((l['precio_unitario'] as num?)?.toDouble() ?? 0);
                  return ListTile(
                    title: Text(l['denominacion']?.toString() ?? 'Producto'),
                    // FASE 4: "2 Cajas x $120.00" en vez de "2 x $120.00". Sin
                    // la presentacion, dos lineas del mismo producto se ven
                    // identicas aunque una sea Caja y la otra Unidad.
                    subtitle: Text(
                      '${_cantidadConPresentacion(l)} x '
                      '\$${((l['precio_unitario'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} '
                      '= \$${lineTotal.toStringAsFixed(2)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _lines.removeAt(i)),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total: \$${_total.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.handshake_outlined),
                  label: Text(
                    _saving ? 'Guardando...' : 'Registrar venta por acuerdo',
                  ),
                ),
              ],
            ),
    );
  }
}
