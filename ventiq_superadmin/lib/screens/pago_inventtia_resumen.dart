import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';
import '../models/supplier_payment_model.dart';
import '../services/inventtia_reparto_service.dart';
import '../services/supplier_payment_service.dart';
import '../widgets/fixed_header_table.dart';

class PagoInventtiaResumen extends StatefulWidget {
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final DateTime licenciaMes;
  final int seccion;
  final int revision;
  final Future<RepartoInventtia> Function()? cargar;

  /// Navega a otra tab mostrando el origen de un importe del resumen.
  /// `personaId` resalta en Licencias los cobros de ese agente;
  /// `agenteCarnavalId` resalta ese agente en el tab Agentes.
  final void Function(int tab, {int? personaId, int? agenteCarnavalId})?
  onNavegarOrigen;

  /// Persona (app_dat_agente) cuyos cobros se resaltan en Licencias.
  final int? highlightPersonaId;

  const PagoInventtiaResumen({
    super.key,
    required this.fechaInicio,
    required this.fechaFin,
    required this.licenciaMes,
    this.seccion = 0,
    this.revision = 0,
    this.cargar,
    this.onNavegarOrigen,
    this.highlightPersonaId,
  });

  @override
  State<PagoInventtiaResumen> createState() => _PagoInventtiaResumenState();
}

class _PagoInventtiaResumenState extends State<PagoInventtiaResumen> {
  int _loadId = 0;
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
        oldWidget.licenciaMes != widget.licenciaMes ||
        oldWidget.revision != widget.revision) {
      _load();
    }
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
      _expanded.clear();
      _orders.clear();
      _loadingOrders.clear();
    });
    try {
      final data =
          await (widget.cargar?.call() ??
              InventtiaRepartoService.cargar(
                desde: widget.fechaInicio,
                hasta: widget.fechaFin,
                licenciaMes: widget.licenciaMes,
              ));
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _editarCobro(CobroLicencia cobro) async {
    final usd = TextEditingController(
      text: cobro.recibidoUsd.toStringAsFixed(2),
    );
    final cup = TextEditingController(
      text: cobro.recibidoCup.toStringAsFixed(2),
    );
    final tx = TextEditingController(text: cobro.transaccion);
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Recibido USD',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cup,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
    if (ok != true) {
      usd.dispose();
      cup.dispose();
      tx.dispose();
      return;
    }
    cobro.recibidoUsd =
        double.tryParse(usd.text.replaceAll(',', '.')) ?? cobro.recibidoUsd;
    cobro.recibidoCup =
        double.tryParse(cup.text.replaceAll(',', '.')) ?? cobro.recibidoCup;
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
          if (widget.seccion == 0) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _stat('Cobrado Licencia', cupCobrado),
                _stat('1% de Carnaval Total', data.comisionCarnavalCup),
                _stat('Total a pagar', aPagar),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'A quién se le paga',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Pagos del ${DateFormat('dd/MM/yyyy').format(widget.fechaInicio)} al ${DateFormat('dd/MM/yyyy').format(widget.fechaFin)} · 1% de ${_money.format(data.pagoProveedoresCup)} CUP = ${_money.format(data.comisionCarnavalCup)} entre ${data.socios} socios',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            _tablaPersonas(data.personas),
          ],
          if (widget.seccion == 1) ...[
            Text(
              data.usoRenovaciones
                  ? 'Licencias de ${_mes(widget.licenciaMes)}'
                  : 'Licencias de ${_mes(widget.licenciaMes)} (no hay renovaciones; se usan las activas)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _tablaCobros(data.cobros),
          ],
          if (widget.seccion == 2) ...[
            Text(
              'Carnaval App',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _resumenProveedores(data.proveedores),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            FixedHeaderTable(
              headers: const ['Tienda', 'Total vendido (CUP)', '1% (CUP)'],
              flex: const [5, 4, 3],
              minWidth: 480,
              maxHeight: 480,
              onRowTap: (i) {
                final p = data.proveedores[i];
                setState(() => _expanded[p.id] = !(_expanded[p.id] ?? false));
                if (_expanded[p.id] == true) _cargarOrdenes(p.id);
              },
              rows: data.proveedores.map((p) {
                final neto = p.totalCup - p.excluidoCup;
                return [
                  Text(p.name),
                  Text(_money.format(neto)),
                  Text(_money.format(neto * 0.01)),
                ];
              }).toList(),
            ),
            ...data.proveedores.where((p) => _expanded[p.id] == true).map(_proveedor),
            if (data.proveedores.isEmpty)
              const Text('Sin órdenes de proveedores en el período.'),
          ],
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
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _money.format(value),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tablaCobros(List<CobroLicencia> cobros) {
    final highlightId = widget.highlightPersonaId;
    final highlighted =
        highlightId == null
            ? null
            : {
              for (var i = 0; i < cobros.length; i++)
                if (cobros[i].agenteId == highlightId) i,
            };
    return FixedHeaderTable(
      highlightedRows: highlighted,
      headers: const [
        'Cliente',
        'Plan USD',
        'CUP teórico',
        'Recibido CUP',
        '20%',
        'Queda',
        'Transacción',
        'Agente',
      ],
      flex: const [5, 3, 3, 3, 3, 3, 4, 4],
      minWidth: 760,
      maxHeight: 520,
      onRowTap: (i) => _editarCobro(cobros[i]),
      rows:
          cobros.map((c) {
            return [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    c.tienda,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (c.secundarias.isNotEmpty)
                    Text(
                      'Multitienda: incluye ${c.secundarias.join(', ')}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.info,
                      ),
                    )
                  else if (c.secundariaDe != null)
                    Text(
                      'Secundaria de ${c.secundariaDe}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
              Text(_money.format(c.planUsd)),
              Text(_money.format(c.cupTeorico)),
              Text(_money.format(c.recibidoCup)),
              Text(_money.format(c.agente20)),
              Text(_money.format(c.quedaInventtia)),
              Text(c.transaccion.isEmpty ? '—' : c.transaccion),
              Text(c.agenteNombre ?? 'Sin asignar'),
            ];
          }).toList(),
    );
  }

  Widget _tablaPersonas(List<PersonaReparto> personas) {
    return FixedHeaderTable(
      headers: const [
        'Trabajador',
        'Parte igual Socios',
        'Carnaval a Inventtia 1%',
        'Despliegue 20%',
        'Agente Carnaval 1%',
        'Total',
        'Tarjeta',
      ],
      flex: const [4, 3, 3, 3, 3, 3, 5],
      minWidth: 700,
      maxHeight: 480,
      rows:
          personas.map((p) {
            final tarjeta = (p.tarjeta ?? '').replaceAll(RegExp(r'\s+'), '');
            final tarjetaFmt = tarjeta
                .replaceAllMapped(
                  RegExp(r'.{1,4}'),
                  (m) => '${m[0]} ',
                )
                .trim();
            return [
              Text(p.nombre),
              _linkCell(p.parteIgual, 'Licencias', () {
                widget.onNavegarOrigen?.call(1);
              }),
              _linkCell(p.carnavalGlobal, 'Carnaval App', () {
                widget.onNavegarOrigen?.call(2);
              }),
              _linkCell(p.despliegue20, 'Licencias', () {
                widget.onNavegarOrigen?.call(1, personaId: p.id);
              }),
              _linkCell(p.agenteCarnaval, 'Agentes', () {
                widget.onNavegarOrigen?.call(
                  3,
                  agenteCarnavalId: p.agenteCarnavalId,
                );
              }),
              Text(
                _money.format(p.total),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              tarjeta.isEmpty
                  ? const Text('—')
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(tarjetaFmt),
                      IconButton(
                        tooltip: 'Copiar tarjeta',
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: tarjeta),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tarjeta copiada'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
            ];
          }).toList(),
    );
  }

  /// Celda importe que navega a la tab donde sale ese dato.
  Widget _linkCell(double value, String origen, VoidCallback onTap) {
    return InkWell(
      onTap: widget.onNavegarOrigen == null ? null : onTap,
      child: Tooltip(
        message: 'Ver origen en $origen',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _money.format(value),
              style: TextStyle(
                color:
                    widget.onNavegarOrigen == null
                        ? null
                        : AppColors.primary,
                decoration:
                    widget.onNavegarOrigen == null
                        ? null
                        : TextDecoration.underline,
              ),
            ),
            if (widget.onNavegarOrigen != null)
              const Icon(
                Icons.open_in_new,
                size: 12,
                color: AppColors.primary,
              ),
          ],
        ),
      ),
    );
  }

  String _resumenProveedores(List<SupplierPaymentSummary> proveedores) {
    final venta = proveedores.fold<double>(0, (sum, p) => sum + p.totalCup);
    final excluido = proveedores.fold<double>(
      0,
      (sum, p) => sum + p.excluidoCup,
    );
    final pago = venta - excluido;
    return 'Total vendido ${_money.format(pago)} CUP · 1%: ${_money.format(pago * 0.01)} CUP · Exclusiones descontadas';
  }

  Widget _proveedor(SupplierPaymentSummary supplier) {
    final abierto = _expanded[supplier.id] == true;
    final venta = supplier.totalCup;
    final excluido = supplier.excluidoCup;
    final pago = venta - excluido;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          supplier.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${supplier.totalOrders} órdenes · Total vendido ${_money.format(pago)} CUP · 1%: ${_money.format(pago * 0.01)} CUP',
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
            ...(_orders[supplier.id] ?? const <OrderPaymentDetail>[]).map((
              orden,
            ) {
              final excluido = orden.excludedSubtotal;
              return ListTile(
                title: Text('Orden #${orden.orderId}'),
                subtitle: Text(
                  excluido > 0
                      ? '${DateFormat('dd/MM/yyyy').format(orden.createdAt)} · venta ${_money.format(orden.total)} · excluido ${_money.format(excluido)}'
                      : DateFormat('dd/MM/yyyy').format(orden.createdAt),
                ),
                trailing: Text(
                  '1%: ${_money.format(orden.totalToPay() * 0.01)} CUP',
                ),
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
    final loadId = _loadId;
    setState(() => _loadingOrders[proveedorId] = true);
    final orders = await SupplierPaymentService.getSupplierOrders(
      proveedorId,
      widget.fechaInicio,
      widget.fechaFin,
      markExcluded: true,
    );
    if (!mounted || loadId != _loadId) return;
    setState(() {
      _orders[proveedorId] = orders;
      _loadingOrders[proveedorId] = false;
    });
  }

  void _verOrden(OrderPaymentDetail orden) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
                      trailing: Text(
                        _money.format(p.isExcluded ? 0 : p.subtotal),
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }
}
