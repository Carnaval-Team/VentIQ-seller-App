import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fondo_inversion.dart';

class FdiLiquidacionDetalleDialog extends StatefulWidget {
  final FdiLiquidacion liquidacion;
  final Future<List<Map<String, dynamic>>> Function() cargarRepartos;

  const FdiLiquidacionDetalleDialog({
    super.key,
    required this.liquidacion,
    required this.cargarRepartos,
  });

  @override
  State<FdiLiquidacionDetalleDialog> createState() =>
      _FdiLiquidacionDetalleDialogState();
}

class _FdiLiquidacionDetalleDialogState
    extends State<FdiLiquidacionDetalleDialog> {
  final _fmt = NumberFormat('#,##0.##');
  late Future<List<Map<String, dynamic>>> _repartos;

  @override
  void initState() {
    super.initState();
    _repartos = widget.cargarRepartos();
  }

  String _monto(num value, String moneda) => '${_fmt.format(value)} $moneda';

  Widget _dato(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.titleSmall),
    ],
  );

  Widget _distribucion(List<Map<String, dynamic>> rows) {
    final totales = <String, double>{};
    final inversores = <(Object, String), List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final moneda = r['moneda'].toString();
      final monto = (r['monto'] as num).toDouble();
      totales.update(moneda, (v) => v + monto, ifAbsent: () => monto);
      inversores
          .putIfAbsent((
            r['id_inversor'] ?? r['nombre_snapshot'],
            moneda,
          ), () => [])
          .add(r);
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ganancia repartida',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              for (final e in totales.entries)
                Text(
                  _monto(e.value, e.key),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              if (rows.isEmpty) const Text('Sin reparto registrado'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Reparto entre inversores', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Text('Esta liquidación no tiene repartos registrados.'),
        for (final grupo in inversores.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    grupo.first['nombre_snapshot'].toString(),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    _monto(
                      grupo.fold<double>(
                        0,
                        (s, r) => s + (r['monto'] as num).toDouble(),
                      ),
                      grupo.first['moneda'].toString(),
                    ),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.liquidacion;
    final fecha = DateFormat('dd/MM/yyyy');
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text('Liquidación #${l.id}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _dato(
                'Período',
                '${fecha.format(l.fechaDesde)} – ${fecha.format(l.fechaHasta)}',
              ),
              const SizedBox(height: 16),
              _dato('Destino', '${l.conceptoDestino} · ${l.cuentaDestino}'),
              const SizedBox(height: 16),
              _dato(
                'Creada',
                l.createdAt == null
                    ? 'No registrada'
                    : DateFormat(
                        'dd/MM/yyyy HH:mm',
                      ).format(l.createdAt!.toLocal()),
              ),
              const Divider(height: 32),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _dato('Venta', _monto(l.ventaTotal, 'CUP'))),
                  const SizedBox(width: 16),
                  Expanded(child: _dato('Costo', _monto(l.costoTotal, 'CUP'))),
                ],
              ),
              const SizedBox(height: 24),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _repartos,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Cargando reparto',
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No se pudo cargar el reparto de inversores.',
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _repartos = widget.cargarRepartos();
                          }),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    );
                  }
                  return _distribucion(snapshot.data ?? []);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
