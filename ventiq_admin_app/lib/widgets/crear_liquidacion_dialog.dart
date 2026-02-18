import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/currency_service.dart';
import '../services/liquidacion_service.dart';
import '../services/consignacion_movimientos_service.dart';

/// Diálogo para crear una nueva liquidación
/// Permite al consignatario ingresar monto en CUP y ver conversión a USD en tiempo real
class CrearLiquidacionDialog extends StatefulWidget {
  final int contratoId;
  final double montoTotalContrato;
  final double totalLiquidaciones;

  const CrearLiquidacionDialog({
    Key? key,
    required this.contratoId,
    required this.montoTotalContrato,
    required this.totalLiquidaciones,
  }) : super(key: key);

  @override
  State<CrearLiquidacionDialog> createState() => _CrearLiquidacionDialogState();
}

class _CrearLiquidacionDialogState extends State<CrearLiquidacionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCupController = TextEditingController();
  final _observacionesController = TextEditingController();

  double _tasaUsdCup = 0.0;
  double _montoUsd = 0.0;
  bool _isLoading = false;
  bool _isCreating = false;
  double _totalMontoVentasUsd = 0.0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _montoCupController.addListener(_calcularConversion);
  }

  Future<void> _loadInitialData() async {
    await _loadTasaCambio();
    await _cargarTotalVentas();
  }

  @override
  void dispose() {
    _montoCupController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _loadTasaCambio() async {
    setState(() => _isLoading = true);
    try {
      // Obtener tasa USD → CUP de CurrencyService (ej: 1 USD = 300 CUP)
      final rate = await CurrencyService.getEffectiveUsdToCupRate();
      if (mounted) {
        setState(() {
          _tasaUsdCup = rate;
        });
        debugPrint('💱 Tasa de cambio cargada (CurrencyService): 1 USD = $_tasaUsdCup CUP');
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando tasa de cambio: $e');
    }
  }

  Future<void> _cargarTotalVentas() async {
    try {
      debugPrint('📊 Cargando total de ventas para contrato: ${widget.contratoId}');
      final estadisticas = await ConsignacionMovimientosService.getEstadisticasVentas(
        idContrato: widget.contratoId,
        fechaDesde: null,
        fechaHasta: null,
      );
      
      final totalVentasCup = (estadisticas['totalMontoVentas'] as num?)?.toDouble() ?? 0.0;
      // Convertir CUP a USD usando la tasa de CurrencyService
      final totalVentasUsd = _tasaUsdCup > 0 ? totalVentasCup / _tasaUsdCup : 0.0;
      debugPrint('✅ Total de ventas: \$${totalVentasCup.toStringAsFixed(2)} CUP = \$${totalVentasUsd.toStringAsFixed(2)} USD');
      
      if (mounted) {
        setState(() {
          _totalMontoVentasUsd = totalVentasUsd;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando total de ventas: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _calcularConversion() {
    final montoCup = double.tryParse(_montoCupController.text) ?? 0.0;
    setState(() {
      // Convertir CUP a USD: dividir por tasa USD→CUP
      _montoUsd = _tasaUsdCup > 0 ? montoCup / _tasaUsdCup : 0.0;
    });
  }

  Future<void> _crearLiquidacion() async {
    if (!_formKey.currentState!.validate()) return;

    final montoCup = double.parse(_montoCupController.text);
    final montoUsd = _tasaUsdCup > 0 ? montoCup / _tasaUsdCup : 0.0;
    final totalLiquidadoNuevo = widget.totalLiquidaciones + montoUsd;

    // Verificar si es pago por adelantado
    if (totalLiquidadoNuevo > _totalMontoVentasUsd) {
      // Mostrar diálogo de confirmación
      final confirmar = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.orange),
              SizedBox(width: 8),
              Text('Pago por Adelantado'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ Atención',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'El monto total liquidado superará el monto de ventas realizadas.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Total vendido:', '\$${_totalMontoVentasUsd.toStringAsFixed(2)} USD'),
                const SizedBox(height: 8),
                _buildInfoRow('Total liquidado actualmente:', '\$${widget.totalLiquidaciones.toStringAsFixed(2)} USD'),
                const SizedBox(height: 8),
                _buildInfoRow('Nuevo monto a liquidar:', '\$${montoUsd.toStringAsFixed(2)} USD'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total a liquidar:',
                              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                            ),
                            Text(
                              '\$${totalLiquidadoNuevo.toStringAsFixed(2)} USD',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Exceso: \$${(totalLiquidadoNuevo - _totalMontoVentasUsd).toStringAsFixed(2)} USD',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '¿Deseas continuar con esta liquidación?',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );

      if (confirmar != true) return;
    }

    setState(() => _isCreating = true);

    try {
      final result = await LiquidacionService.crearLiquidacion(
        contratoId: widget.contratoId,
        montoCup: montoCup,
        tasaUsdCup: _tasaUsdCup,
        observaciones: _observacionesController.text.trim().isEmpty 
            ? null 
            : _observacionesController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(result); // Retornar resultado
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final saldoPendiente = widget.montoTotalContrato - widget.totalLiquidaciones;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payments, color: Colors.green),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Crear Liquidación',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: CircularProgressIndicator(),
              ),
            )
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Información del contrato
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Información del Contrato',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow('Valor total:', '\$${widget.montoTotalContrato.toStringAsFixed(2)} USD'),
                          _buildInfoRow('Liquidado:', '\$${widget.totalLiquidaciones.toStringAsFixed(2)} USD'),
                          const Divider(height: 16),
                          // Saldo pendiente - Label
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Saldo pendiente:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                          // Saldo pendiente - Valores en USD y CUP
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.orange.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        'USD',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '\$${saldoPendiente.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: saldoPendiente > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        'CUP',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _tasaUsdCup > 0 
                                            ? '\$${(saldoPendiente * _tasaUsdCup).toStringAsFixed(2)}'
                                            : '---',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: saldoPendiente > 0 ? Colors.blue.shade700 : Colors.green.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Campo de monto en CUP
                    Text(
                      'Monto a liquidar (CUP)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _montoCupController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '\$ ',
                        suffixText: 'CUP',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingrese un monto';
                        }
                        final monto = double.tryParse(value);
                        if (monto == null || monto <= 0) {
                          return 'Monto inválido';
                        }
                        
                        // Validar que no supere el saldo pendiente
                        final saldoPendiente = widget.montoTotalContrato - widget.totalLiquidaciones;
                        final montoUsd = _tasaUsdCup > 0 ? monto / _tasaUsdCup : 0.0;
                        
                        if (montoUsd > saldoPendiente) {
                          return 'El monto no puede superar el saldo pendiente (\$${saldoPendiente.toStringAsFixed(2)} USD)';
                        }
                        
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Conversión a USD
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.currency_exchange, size: 16, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Text(
                                'Conversión a USD',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tasa: 1 USD = ${_tasaUsdCup.toStringAsFixed(2)} CUP',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Monto en USD: \$${_montoUsd.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Observaciones
                    Text(
                      'Observaciones (opcional)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _observacionesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Ingrese observaciones...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _isCreating ? null : _crearLiquidacion,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check),
          label: Text(_isCreating ? 'Creando...' : 'Crear Liquidación'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor ?? Colors.grey[900],
            ),
          ),
        ],
      ),
    );
  }
}
