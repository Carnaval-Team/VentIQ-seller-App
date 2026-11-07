import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/supplier_payment_model.dart';
import '../services/inventtia_reparto_service.dart';
import '../services/supplier_payment_service.dart';

class PagoInventtiaResumen extends StatefulWidget {
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final DateTime licenciaMes;

  const PagoInventtiaResumen({
    super.key,
    required this.fechaInicio,
    required this.fechaFin,
    required this.licenciaMes,
  });

  @override
  State<PagoInventtiaResumen> createState() => _PagoInventtiaResumenState();
}

class _PagoInventtiaResumenState extends State<PagoInventtiaResumen> {
  final _money = NumberFormat('#,##0.00', 'es');
  RepartoInventtia? _data;
  bool _loading = true;
  String? _error;
  final _expanded = <int, bool>{};
  final _orders = <int, List<OrderPaymentDetail>>{};
  final _loadingOrders = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PagoInventtiaResumen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fechaInicio != widget.fechaInicio ||
        oldWidget.fechaFin != widget.fechaFin ||
        oldWidget.licenciaMes != widget.licenciaMes) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _expanded.clear();
      _orders.clear();
    });
    try {
      final data = await InventtiaRepartoService.cargar(
        desde: widget.fechaInicio,
        hasta: widget.fechaFin,
        licenciaMes: widget.licenciaMes,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editarCobro(CobroLicencia cobro) async {
    final usd = TextEditingController(text: cobro.recibidoUsd.toStringAsFixed(2));
    final cup = TextEditingController(text: cobro.recibidoCup.toStringAsFixed(2));
    final tx = TextEditingController(text: cobro.transaccion);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cobro.tienda),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Plan ${cobro.planUsd.toStringAsFixed(2)} USD · teórico ${_money.format(cobro.cupTeorico)} CUP. El reparto usa el CUP recibido.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usd,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Recibido USD',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cup,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Recibido CUP',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tx,
                decoration: const InputDecoration(
                  labelText: 'Transacción',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) {
      usd.dispose();
      cup.dispose();
      tx.dispose();
      return;
    }
    cobro.recibidoUsd = double.tryParse(usd.text.replaceAll(',', '.')) ?? cobro.recibidoUsd;
    cobro.recibidoCup = double.tryParse(cup.text.replaceAll(',', '.')) ?? cobro.recibidoCup;
    cobro.transaccion = tx.text.trim();
    usd.dispose();
    cup.dispose();
    tx.dispose();
    try {
      await InventtiaRepartoService.guardarAjuste(cobro);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el ajuste: $e')),
        );
      }
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    final data = _data!;
    final cupCobrado = data.cobros.fold<double>(0, (s, c) => s + c.recibidoCup);
    final veinte = data.cobros.fold<double>(0, (s, c) => s + c.agente20);
    final neto = data.cobros.fold<double>(0, (s, c) => s + c.quedaInventtia);
    final aPagar = data.personas.fold<double>(0, (s, p) => s + p.total);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (data.aviso != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(data.aviso!),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _stat('Cobrado CUP', cupCobrado),
              _stat('20% despliegue', veinte),
              _stat('Neto socios', neto),
              _stat('Carnaval 1%', data.comisionCarnavalCup),
              _stat('A pagar', aPagar),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            data.usoRenovaciones
                ? 'Licencias de ${_mes(widget.licenciaMes)}'
                : 'Licencias de ${_mes(widget.licenciaMes)} (no hay renovaciones; se usan las activas)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _tablaCobros(data.cobros),
          const SizedBox(height: 20),
          Text('A quién se le paga', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Pagos del ${DateFormat('dd/MM/yyyy').format(widget.fechaInicio)} al ${DateFormat('dd/MM/yyyy').format(widget.fechaFin)} · 1% de ${_money.format(data.pagoProveedoresCup)} CUP = ${_money.format(data.comisionCarnavalCup)} entre ${data.socios} socios',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _tablaPersonas(data.personas),
          const SizedBox(height: 20),
          Text('Pago a proveedores', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            _resumenProveedores(data.proveedores),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...data.proveedores.map(_proveedor),
          if (data.proveedores.isEmpty)
            const Text('Sin órdenes de proveedores en el período.'),
        ],
      ),
    );
  }

  Widget _stat(String label, double value) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(_money.format(value), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tablaCobros(List<CobroLicencia> cobros) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        showCheckboxColumn: false,
        columns: const [
          DataColumn(label: Text('Cliente')),
          DataColumn(label: Text('Plan USD'), numeric: true),
          DataColumn(label: Text('CUP teórico'), numeric: true),
          DataColumn(label: Text('Recibido CUP'), numeric: true),
          DataColumn(label: Text('20%'), numeric: true),
          DataColumn(label: Text('Queda'), numeric: true),
          DataColumn(label: Text('Transacción')),
          DataColumn(label: Text('Agente')),
        ],
        rows: cobros.map((c) {
          return DataRow(
            onSelectChanged: (_) => _editarCobro(c),
            cells: [
              DataCell(Text(c.tienda)),
              DataCell(Text(_money.format(c.planUsd))),
              DataCell(Text(_money.format(c.cupTeorico))),
              DataCell(Text(_money.format(c.recibidoCup))),
              DataCell(Text(_money.format(c.agente20))),
              DataCell(Text(_money.format(c.quedaInventtia))),
              DataCell(Text(c.transaccion.isEmpty ? '—' : c.transaccion)),
              DataCell(Text(c.agenteNombre ?? 'Sin asignar')),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _tablaPersonas(List<PersonaReparto> personas) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Trabajador')),
          DataColumn(label: Text('Parte igual'), numeric: true),
          DataColumn(label: Text('20%'), numeric: true),
          DataColumn(label: Text('Carnaval 1%'), numeric: true),
          DataColumn(label: Text('Agente 1%'), numeric: true),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('Tarjeta')),
        ],
        rows: personas.map((p) {
          final tarjeta = (p.tarjeta ?? '').replaceAll(RegExp(r'\s+'), '');
          return DataRow(cells: [
            DataCell(Text(p.nombre)),
            DataCell(Text(_money.format(p.parteIgual))),
            DataCell(Text(_money.format(p.despliegue20))),
            DataCell(Text(_money.format(p.carnavalGlobal))),
            DataCell(Text(_money.format(p.agenteCarnaval))),
            DataCell(Text(_money.format(p.total), style: const TextStyle(fontWeight: FontWeight.w700))),
            DataCell(tarjeta.isEmpty
                ? const Text('—')
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tarjeta.length <= 4 ? tarjeta : '···· ${tarjeta.substring(tarjeta.length - 4)}'),
                      IconButton(
                        tooltip: 'Copiar tarjeta',
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: tarjeta));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Tarjeta copiada')),
                          );
                        },
                      ),
                    ],
                  )),
          ]);
        }).toList(),
      ),
    );
  }

  String _resumenProveedores(List<SupplierPaymentSummary> proveedores) {
    final venta = proveedores.fold<double>(0, (sum, p) => sum + p.totalCup);
    final excluido = proveedores.fold<double>(0, (sum, p) => sum + p.excluidoCup);
    final pago = venta - excluido;
    return 'Venta ${_money.format(venta)} · excluido ${_money.format(excluido)} · para el pago ${_money.format(pago)} CUP';
  }

  Widget _proveedor(SupplierPaymentSummary supplier) {
    final abierto = _expanded[supplier.id] == true;
    final venta = supplier.totalCup;
    final excluido = supplier.excluidoCup;
    final pago = venta - excluido;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(supplier.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${supplier.totalOrders} órdenes · venta ${_money.format(venta)} · excluido ${_money.format(excluido)} · a pagar ${_money.format(pago)} CUP',
        ),
        initiallyExpanded: abierto,
        onExpansionChanged: (open) {
          setState(() => _expanded[supplier.id] = open);
          if (open) _cargarOrdenes(supplier.id);
        },
        children: [
          if (_loadingOrders[supplier.id] == true)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            )
          else
            ...(_orders[supplier.id] ?? const <OrderPaymentDetail>[]).map((orden) {
              final excluido = orden.excludedSubtotal;
              return ListTile(
                title: Text('Orden #${orden.orderId}'),
                subtitle: Text(
                  excluido > 0
                      ? '${DateFormat('dd/MM/yyyy').format(orden.createdAt)} · venta ${_money.format(orden.total)} · excluido ${_money.format(excluido)}'
                      : DateFormat('dd/MM/yyyy').format(orden.createdAt),
                ),
                trailing: Text(_money.format(orden.totalToPay())),
                onTap: () => _verOrden(orden),
              );
            }),
        ],
      ),
    );
  }

  String _mes(DateTime fecha) {
    return DateFormat('MMMM yyyy', 'es_ES').format(fecha);
  }

  Future<void> _cargarOrdenes(int proveedorId) async {
    if (_orders.containsKey(proveedorId)) return;
    setState(() => _loadingOrders[proveedorId] = true);
    final orders = await SupplierPaymentService.getSupplierOrders(
      proveedorId,
      widget.fechaInicio,
      widget.fechaFin,
      markExcluded: true,
    );
    if (!mounted) return;
    setState(() {
      _orders[proveedorId] = orders;
      _loadingOrders[proveedorId] = false;
    });
  }

  void _verOrden(OrderPaymentDetail orden) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Orden #${orden.orderId}'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                'Venta ${_money.format(orden.total)} · excluido ${_money.format(orden.excludedSubtotal)} · para el pago ${_money.format(orden.totalToPay())} CUP',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              ...orden.products.map((p) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.productName),
                  subtitle: Text(
                    p.isExcluded
                        ? '${p.quantity} × ${_money.format(p.price)} · excluido'
                        : '${p.quantity} × ${_money.format(p.price)}',
                  ),
                  trailing: Text(_money.format(p.isExcluded ? 0 : p.subtotal)),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}
