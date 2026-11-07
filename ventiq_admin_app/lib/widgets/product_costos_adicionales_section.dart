import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/costos_adicionales_service.dart';
import '../services/currency_service.dart';
import '../services/financial_service.dart';

/// Sección CRUD de costos adicionales en el detalle de producto.
class ProductCostosAdicionalesSection extends StatefulWidget {
  final int idProducto;
  final bool canEdit;

  const ProductCostosAdicionalesSection({
    super.key,
    required this.idProducto,
    required this.canEdit,
  });

  @override
  State<ProductCostosAdicionalesSection> createState() =>
      _ProductCostosAdicionalesSectionState();
}

class _ProductCostosAdicionalesSectionState
    extends State<ProductCostosAdicionalesSection> {
  final _service = CostosAdicionalesService();
  final _financial = FinancialService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  double _usdRate = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rate = await CurrencyService.getEffectiveUsdToCupRate();
      final items = await _service.listarPorProducto(widget.idProducto);
      if (!mounted) return;
      setState(() {
        _usdRate = rate > 0 ? rate : 1.0;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando costos adicionales: $e')),
      );
    }
  }

  String _nombre(Map<String, dynamic> item) {
    final tipo = item['app_cont_tipo_costo'];
    if (tipo is Map) return tipo['denominacion']?.toString() ?? 'Concepto';
    return 'Concepto';
  }

  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final tipos = await _financial.getCostTypes();
    if (!mounted) return;

    int? selectedTipo = existing?['id_tipo_costo'] as int?;
    String moneda = 'USD';
    final montoCtrl = TextEditingController(
      text: existing == null
          ? ''
          : ((existing['monto_usd'] as num?)?.toDouble() ?? 0).toStringAsFixed(4),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Agregar costo adicional'
                    : 'Editar monto configurado',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (existing == null)
                      DropdownButtonFormField<int>(
                        value: selectedTipo,
                        decoration: const InputDecoration(
                          labelText: 'Concepto',
                        ),
                        items: tipos
                            .map(
                              (t) => DropdownMenuItem<int>(
                                value: t['id'] as int,
                                child: Text(t['denominacion'] ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => selectedTipo = v),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _nombre(existing),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'USD', label: Text('USD')),
                        ButtonSegment(value: 'CUP', label: Text('CUP')),
                      ],
                      selected: {moneda},
                      onSelectionChanged: (s) =>
                          setLocal(() => moneda = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: montoCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Monto por unidad base ($moneda)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final raw = double.tryParse(montoCtrl.text.replaceAll(',', '.'));
    if (raw == null || raw < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monto inválido')),
      );
      return;
    }
    final montoUsd = moneda == 'USD' ? raw : raw / _usdRate;

    try {
      if (existing == null) {
        if (selectedTipo == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seleccione un concepto')),
          );
          return;
        }
        await _service.crear(
          idProducto: widget.idProducto,
          idTipoCosto: selectedTipo!,
          montoUsd: montoUsd,
        );
      } else {
        await _service.actualizarMonto(
          id: existing['id'] as int,
          montoUsd: montoUsd,
        );
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.add_chart, size: 18, color: Colors.teal[700]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Costos adicionales',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ),
            if (widget.canEdit)
              IconButton(
                tooltip: 'Agregar',
                onPressed: () => _showEditor(),
                icon: const Icon(Icons.add_circle_outline),
              ),
          ],
        ),
        Text(
          'Por unidad base, en USD. El promedio ponderado se actualiza en cada recepción.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Sin costos adicionales configurados',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          )
        else
          ..._items.map((item) {
            final monto = (item['monto_usd'] as num?)?.toDouble() ?? 0;
            final avg = (item['monto_promedio_usd'] as num?)?.toDouble() ?? 0;
            final activo = item['activo'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_nombre(item)),
                subtitle: Text(
                  'Config: \$${fmt.format(monto)} USD'
                  ' (₱${fmt.format(monto * _usdRate)} CUP)\n'
                  'Promedio: \$${fmt.format(avg)} USD'
                  ' (₱${fmt.format(avg * _usdRate)} CUP)',
                ),
                isThreeLine: true,
                trailing: widget.canEdit
                    ? Wrap(
                        spacing: 0,
                        children: [
                          Switch(
                            value: activo,
                            onChanged: (v) async {
                              await _service.setActivo(
                                id: item['id'] as int,
                                activo: v,
                              );
                              await _load();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _showEditor(existing: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20),
                            color: Colors.red,
                            onPressed: () async {
                              await _service.eliminar(item['id'] as int);
                              await _load();
                            },
                          ),
                        ],
                      )
                    : null,
              ),
            );
          }),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 4),
          Builder(
            builder: (_) {
              final sumaAvg = _items
                  .where((i) => i['activo'] == true)
                  .fold<double>(
                    0,
                    (s, i) =>
                        s +
                        ((i['monto_promedio_usd'] as num?)?.toDouble() ?? 0),
                  );
              return Text(
                'Suma promedios activos: \$${fmt.format(sumaAvg)} USD'
                ' (₱${fmt.format(sumaAvg * _usdRate)} CUP)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal[800],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
