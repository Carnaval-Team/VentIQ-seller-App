import 'package:flutter/material.dart';
import '../models/payment_method.dart';
import '../theme/ventiq_home_theme.dart';
import '../utils/price_utils.dart';

class CheckoutPaymentLinesEditor extends StatefulWidget {
  final List<Map<String, dynamic>> initialPayments;
  final List<PaymentMethod> methods;
  final Map<String, double> rates;
  final double totalCup;
  final ValueChanged<List<Map<String, dynamic>>> onSave;

  const CheckoutPaymentLinesEditor({
    super.key,
    required this.initialPayments,
    required this.methods,
    required this.rates,
    required this.totalCup,
    required this.onSave,
  });

  @override
  State<CheckoutPaymentLinesEditor> createState() =>
      _CheckoutPaymentLinesEditorState();
}

class _CheckoutPaymentLinesEditorState
    extends State<CheckoutPaymentLinesEditor> {
  final _formKey = GlobalKey<FormState>();
  final _lines = <Map<String, dynamic>>[];
  final _amounts = <TextEditingController>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final payment in widget.initialPayments) {
      _lines.add(Map<String, dynamic>.from(payment));
      _amounts.add(
        TextEditingController(
          text: PriceUtils.paymentAmount(payment).toString(),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _amounts) {
      controller.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _payments => List.generate(_lines.length, (i) {
    final method = widget.methods.firstWhere(
      (m) => m.id == _lines[i]['id_medio_pago'],
    );
    final currency = PriceUtils.paymentCurrency(_lines[i]);
    final rate = widget.rates[currency] ?? 0;
    final amount = double.tryParse(_amounts[i].text.replaceAll(',', '.')) ?? 0;
    return {
      'id_medio_pago': method.id,
      'denominacion': method.denominacion,
      'monto': amount,
      'moneda': currency,
      'tasa_cambio': rate,
      'tasa_usd': currency == 'USD' ? rate : null,
      'monto_cup_equivalente': amount * rate,
      'tipo_pago': method.id == 1 ? 1 : 2,
      'es_digital': method.esDigital,
      'es_efectivo': method.esEfectivo,
      'es_transferencia': method.esTransferencia,
    };
  });

  @override
  Widget build(BuildContext context) {
    final payments = _payments;
    final paid = PriceUtils.paymentTotalCup(payments);
    final remaining = widget.totalCup - paid;
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Distribuir pagos',
              style: VentiqHomeTheme.tituloSeccion,
            ),
            const SizedBox(height: 8),
            const Text(
              'Puedes repetir un medio en distintas monedas. Los precios de los productos no cambian.',
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _lines[i]['id_medio_pago'] as int,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Medio de pago ${i + 1}',
                            ),
                            items:
                                widget.methods
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m.id,
                                        child: Text(m.denominacion),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (id) => setState(() {
                                  _lines[i]['id_medio_pago'] = id;
                                  _error = null;
                                }),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Eliminar pago ${i + 1}',
                          onPressed:
                              () => setState(() {
                                _lines.removeAt(i);
                                final controller = _amounts.removeAt(i);
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => controller.dispose(),
                                );
                                _error = null;
                              }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _amounts[i],
                            decoration: const InputDecoration(
                              labelText: 'Importe',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() => _error = null),
                            validator: (text) {
                              final amount = double.tryParse(
                                (text ?? '').replaceAll(',', '.'),
                              );
                              return amount == null ||
                                      !amount.isFinite ||
                                      amount <= 0
                                  ? 'Introduce un importe mayor que cero'
                                  : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('currency-$i'),
                            initialValue: PriceUtils.paymentCurrency(_lines[i]),
                            decoration: const InputDecoration(
                              labelText: 'Moneda',
                            ),
                            items:
                                widget.rates.keys
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                            onChanged:
                                (currency) => setState(() {
                                  _lines[i]['moneda'] = currency;
                                  _error = null;
                                }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed:
                  widget.methods.isEmpty || widget.rates.isEmpty
                      ? null
                      : () => setState(() {
                        _lines.add({
                          'id_medio_pago': widget.methods.first.id,
                          'moneda': widget.rates.keys.first,
                        });
                        _amounts.add(TextEditingController());
                        _error = null;
                      }),
              icon: const Icon(Icons.add),
              label: const Text('Añadir pago'),
            ),
            const SizedBox(height: 12),
            Text(
              'Total de la orden: ${widget.totalCup.toStringAsFixed(2)} CUP',
            ),
            Text('Total asignado: ${paid.toStringAsFixed(2)} CUP'),
            Text(
              '${remaining >= 0 ? 'Falta' : 'Exceso'}: ${remaining.abs().toStringAsFixed(2)} CUP',
            ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: VentiqHomeTheme.danger),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (!_formKey.currentState!.validate()) return;
                if (_lines.isEmpty ||
                    !remaining.isFinite ||
                    remaining.abs() > 0.01) {
                  setState(
                    () =>
                        _error =
                            'El desglose debe coincidir con el total de la orden.',
                  );
                  return;
                }
                widget.onSave(_payments);
              },
              child: const Text('Guardar desglose'),
            ),
          ],
        ),
      ),
    );
  }
}
