import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/currency_display_service.dart';
import '../services/liquidacion_service.dart';

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

  double _tasaCambio = 1.0;
  double _montoUsd = 0.0;
  bool _isLoading = false;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadTasaCambio();
    _montoCupController.addListener(_calcularConversion);
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
      // Obtener tasa CUP -> USD (ej: 1 CUP = 0.025 USD)
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay('CUP', 'USD');
      if (mounted) {
        setState(() {
          _tasaCambio = rate;
          _isLoading = false;
        });
        debugPrint('💱 Tasa de cambio cargada: 1 CUP = $_tasaCambio USD');
      }
    } catch (e) {
      debugPrint('⚠️ Error cargando tasa de cambio: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _calcularConversion() {
    final montoCup = double.tryParse(_montoCupController.text) ?? 0.0;
    setState(() {
      // Convertir CUP a USD: multiplicar por la tasa (1 CUP = X USD)
      _montoUsd = montoCup * _tasaCambio;
    });
  }

  Future<void> _crearLiquidacion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final montoCup = double.parse(_montoCupController.text);
      
      final result = await LiquidacionService.crearLiquidacion(
        contratoId: widget.contratoId,
        montoCup: montoCup,
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
                                        _tasaCambio > 0 
                                            ? '\$${(saldoPendiente / _tasaCambio).toStringAsFixed(2)}'
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
                            'Tasa: 1 CUP = ${_tasaCambio.toStringAsFixed(4)} USD',
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
