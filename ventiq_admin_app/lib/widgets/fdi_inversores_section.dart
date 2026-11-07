import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/fondo_inversion_service.dart';
import '../services/permissions_service.dart';
import 'fdi_inversor_dialog.dart';

class FdiInversoresSection extends StatefulWidget {
  final int idTienda;
  const FdiInversoresSection({super.key, required this.idTienda});

  @override
  State<FdiInversoresSection> createState() => _FdiInversoresSectionState();
}

class _FdiInversoresSectionState extends State<FdiInversoresSection> {
  final _service = FondoInversionService();
  final _fmt = NumberFormat('#,##0.00');
  List<Map<String, dynamic>> _inversores = [];
  List<Map<String, dynamic>> _historial = [];
  DateTimeRange? _periodo;
  int? _inversor;
  bool _loading = true;
  bool _busy = false;
  bool _allowed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final allowed = await PermissionsService().canViewGanancias();
      if (!allowed) {
        if (mounted) {
          setState(() {
            _allowed = false;
            _loading = false;
          });
        }
        return;
      }
      final results = await Future.wait([
        _service.listInversores(widget.idTienda),
        _service.historialInversores(
          widget.idTienda,
          desde: _periodo?.start,
          hasta: _periodo?.end,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _allowed = true;
        _inversores = results[0];
        _historial = results[1];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editar([Map<String, dynamic>? inversor]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => FdiInversorDialog(inversor: inversor),
    );
    if (result != null && mounted) {
      await _run(
        () => _service.guardarInversor(
          widget.idTienda,
          id: (inversor?['id'] as num?)?.toInt(),
          nombre: result['nombre'] as String,
          porcentaje: result['porcentaje'] as double,
          activo: result['activo'] as bool,
        ),
      );
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pagar(Map<String, dynamic> reparto) async {
    final referencia = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pago realizado'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reparto['nombre_snapshot']} · ${_fmt.format(reparto['monto'])} ${reparto['moneda']}',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Confirma únicamente si el inversor ya recibió este importe. No se realizará una transferencia bancaria.',
                ),
                TextFormField(
                  controller: referencia,
                  decoration: const InputDecoration(
                    labelText: 'Referencia o comprobante',
                  ),
                  validator: (s) => s == null || s.trim().isEmpty
                      ? 'Indique la referencia'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Confirmar pago'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _run(
        () => _service.pagarInversor(
          (reparto['id'] as num).toInt(),
          referencia.text.trim(),
        ),
      );
    }
    referencia.dispose();
  }

  Future<void> _elegirPeriodo() async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _periodo,
    );
    if (result == null || !mounted) return;
    setState(() => _periodo = result);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_allowed && _error == null) return const SizedBox.shrink();
    final total = _inversores
        .where((i) => i['activo'] == true)
        .fold<double>(0, (s, i) => s + (i['porcentaje'] as num).toDouble());
    final rows = _historial
        .where((r) => _inversor == null || r['id_inversor'] == _inversor)
        .toList();
    final totales = <String, List<double>>{};
    for (final r in rows) {
      final nombre = _inversores.firstWhere(
        (i) => i['id'] == r['id_inversor'],
        orElse: () => {'nombre': r['nombre_snapshot']},
      )['nombre'];
      final key = '$nombre (#${r['id_inversor']}) · ${r['moneda']}';
      final values = totales.putIfAbsent(key, () => [0, 0]);
      values[r['pagado_at'] == null ? 0 : 1] += (r['monto'] as num).toDouble();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Inversores', style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
              onPressed: _busy ? null : _editar,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Agregar'),
            ),
          ],
        ),
        Text(
          'Participación activa: ${total.toStringAsFixed(4)}% · Debe sumar 100% para liquidar.',
        ),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ],
        if (_inversores.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Agrega los inversores y sus porcentajes antes de crear una liquidación.',
            ),
          ),
        for (final i in _inversores)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(i['nombre'] as String),
            subtitle: Text(
              '${i['porcentaje']}% · ${i['activo'] == true ? 'Activo' : 'Inactivo'}',
            ),
            trailing: IconButton(
              tooltip: 'Editar inversor',
              onPressed: _busy ? null : () => _editar(i),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        const Divider(height: 32),
        Text(
          'Historial de repartos y pagos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _inversor,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Inversor',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<int>(
              value: null,
              child: Text('Todos los inversores'),
            ),
            for (final i in _inversores)
              DropdownMenuItem(
                value: (i['id'] as num).toInt(),
                child: Text(
                  i['nombre'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _inversor = v),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _elegirPeriodo,
              icon: const Icon(Icons.date_range),
              label: Text(
                _periodo == null
                    ? 'Filtrar período'
                    : '${DateFormat('dd/MM/yyyy').format(_periodo!.start)} – ${DateFormat('dd/MM/yyyy').format(_periodo!.end)}',
              ),
            ),
            if (_periodo != null)
              TextButton(
                onPressed: () {
                  setState(() => _periodo = null);
                  _load();
                },
                child: const Text('Historial completo'),
              ),
          ],
        ),
        const Text(
          'El filtro incluye liquidaciones cuyo período se solapa con las fechas seleccionadas. Los importes se mantienen separados por moneda.',
        ),
        const SizedBox(height: 12),
        for (final entry in totales.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${entry.key}\nAsignado: ${_fmt.format(entry.value[0] + entry.value[1])} · Pendiente: ${_fmt.format(entry.value[0])} · Pagado: ${_fmt.format(entry.value[1])}',
            ),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No hay repartos registrados para este filtro. Las liquidaciones anteriores a esta actualización no se reparten retroactivamente.',
            ),
          ),
        for (final r in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['nombre_snapshot']} · ${_fmt.format(r['monto'])} ${r['moneda']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Liquidación #${r['id_liquidacion']} · ${r['porcentaje_snapshot']}% · Medio #${r['id_medio_pago']}',
                  ),
                  Text('${r['fecha_desde']} – ${r['fecha_hasta']}'),
                  Text(
                    r['pagado_at'] == null
                        ? 'Pendiente de pago'
                        : 'Pagado: ${r['pagado_at']} · ${r['referencia_pago']}',
                  ),
                  if (r['pagado_at'] == null && (r['monto'] as num) > 0)
                    TextButton(
                      onPressed: _busy ? null : () => _pagar(r),
                      child: const Text('Registrar pago'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
