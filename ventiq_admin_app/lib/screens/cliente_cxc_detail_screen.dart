import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/cxc_cliente.dart';
import '../models/payment_method.dart';
import '../services/cxc_service.dart';
import '../services/payment_method_service.dart';
import '../utils/navigation_guard.dart';

class ClienteCxcDetailScreen extends StatefulWidget {
  final int idCliente;
  final String nombreCliente;

  const ClienteCxcDetailScreen({
    super.key,
    required this.idCliente,
    required this.nombreCliente,
  });

  @override
  State<ClienteCxcDetailScreen> createState() =>
      _ClienteCxcDetailScreenState();
}

class _ClienteCxcDetailScreenState extends State<ClienteCxcDetailScreen> {
  bool _isLoading = true;
  List<CxcVenta> _ventas = [];
  double _saldo = 0.0;
  bool _bloqueado = false;
  bool _canLiquidate = false;
  bool _canBlock = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadData();
  }

  Future<void> _loadPermissions() async {
    final results = await Future.wait([
      NavigationGuard.canPerformAction('cxc.liquidate'),
      NavigationGuard.canPerformAction('cxc.block'),
    ]);
    if (!mounted) return;
    setState(() {
      _canLiquidate = results[0];
      _canBlock = results[1];
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      CxcService.historialCliente(widget.idCliente),
      CxcService.saldoCliente(widget.idCliente),
      CxcService.estaBloqueado(widget.idCliente),
    ]);
    if (!mounted) return;
    setState(() {
      _ventas = results[0] as List<CxcVenta>;
      _saldo = results[1] as double;
      _bloqueado = results[2] as bool;
      _isLoading = false;
    });
  }

  List<CxcVenta> get _ventasPendientes =>
      _ventas.where((v) => !v.esPagada).toList();

  Future<void> _toggleBloqueo() async {
    final nuevoEstado = !_bloqueado;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(nuevoEstado ? 'Bloquear cliente' : 'Desbloquear cliente'),
        content: Text(
          nuevoEstado
              ? '${widget.nombreCliente} no podrá generar nuevas cuentas por cobrar. Las ventas pendientes actuales no se ven afectadas.'
              : '${widget.nombreCliente} podrá volver a generar cuentas por cobrar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await CxcService.setBloqueoCliente(widget.idCliente, nuevoEstado);
      if (!mounted) return;
      setState(() => _bloqueado = nuevoEstado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nuevoEstado ? '🔒 Cliente bloqueado para CxC' : '🔓 Cliente desbloqueado',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openLiquidarDialog() async {
    if (_ventasPendientes.isEmpty) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _LiquidarDialog(
        idCliente: widget.idCliente,
        saldoTotal: _saldo,
        ventasPendientes: _ventasPendientes,
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.nombreCliente,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_canBlock)
            IconButton(
              icon: Icon(
                _bloqueado ? Icons.lock_open : Icons.lock,
                color: Colors.white,
              ),
              tooltip: _bloqueado
                  ? 'Desbloquear para nuevas cuentas por cobrar'
                  : 'Bloquear para nuevas cuentas por cobrar',
              onPressed: _toggleBloqueo,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSaldoCard(),
                  const SizedBox(height: 16),
                  const Text(
                    'Historial de ventas a crédito',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (_ventas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Sin ventas a crédito registradas',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    ..._ventas.map(_buildVentaTile),
                ],
              ),
            ),
      floatingActionButton: (_canLiquidate && _ventasPendientes.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: _openLiquidarDialog,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.payments, color: Colors.white),
              label: const Text(
                'Registrar cobro',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildSaldoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo pendiente',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
                Text(
                  '\$${_saldo.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: _saldo > 0 ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
                Text(
                  '${_ventasPendientes.length} orden(es) pendiente(s)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (_bloqueado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'Bloqueado',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVentaTile(CxcVenta venta) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(
          venta.esPagada ? Icons.check_circle : Icons.pending_actions,
          color: venta.esPagada ? Colors.green : Colors.orange,
        ),
        title: Text('Orden #${venta.idOperacion}'),
        subtitle: Text(
          '${_formatDate(venta.fecha)} · Total: \$${venta.importeTotal.toStringAsFixed(2)} · Abonado: \$${venta.abonado.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          venta.esPagada ? 'Pagada' : '\$${venta.saldo.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: venta.esPagada ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

/// Diálogo para registrar un cobro (liquidación) de cuentas por cobrar.
class _LiquidarDialog extends StatefulWidget {
  final int idCliente;
  final double saldoTotal;
  final List<CxcVenta> ventasPendientes;

  const _LiquidarDialog({
    required this.idCliente,
    required this.saldoTotal,
    required this.ventasPendientes,
  });

  @override
  State<_LiquidarDialog> createState() => _LiquidarDialogState();
}

class _LiquidarDialogState extends State<_LiquidarDialog> {
  final _montoController = TextEditingController();
  final _referenciaController = TextEditingController();
  List<PaymentMethod> _mediosPago = [];
  PaymentMethod? _medioPagoSeleccionado;
  bool _isLoadingMedios = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _montoController.text = widget.saldoTotal.toStringAsFixed(2);
    _loadMediosPago();
  }

  Future<void> _loadMediosPago() async {
    final medios = await PaymentMethodService.getActivePaymentMethods();
    if (!mounted) return;
    setState(() {
      _mediosPago = medios;
      _medioPagoSeleccionado = medios.isNotEmpty ? medios.first : null;
      _isLoadingMedios = false;
    });
  }

  @override
  void dispose() {
    _montoController.dispose();
    _referenciaController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final monto = double.tryParse(_montoController.text.replaceAll(',', '.'));
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Ingresa un monto válido');
      return;
    }
    if (_medioPagoSeleccionado == null) {
      setState(() => _error = 'Selecciona un medio de pago');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      // Modo FIFO: se aplica automáticamente a las ventas más antiguas.
      await CxcService.registrarLiquidacion(
        idCliente: widget.idCliente,
        monto: monto,
        idMedioPago: _medioPagoSeleccionado!.id,
        referencia: _referenciaController.text.trim().isEmpty
            ? null
            : _referenciaController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Cobro registrado correctamente')),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = 'Error al registrar el cobro: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar cobro'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo total pendiente: \$${widget.saldoTotal.toStringAsFixed(2)} '
              '(${widget.ventasPendientes.length} orden(es))',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _montoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto a cobrar',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _isLoadingMedios
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<PaymentMethod>(
                    value: _medioPagoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Medio de pago',
                      border: OutlineInputBorder(),
                    ),
                    items: _mediosPago
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _medioPagoSeleccionado = value),
                  ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenciaController,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'El cobro se aplicará automáticamente a las órdenes pendientes más antiguas primero.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Registrar'),
        ),
      ],
    );
  }
}
