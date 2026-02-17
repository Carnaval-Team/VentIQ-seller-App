import 'package:flutter/material.dart';
import '../services/currency_display_service.dart';
import '../services/currency_service.dart';

/// Widget especializado para conversión de precios en diálogos de inventario.
/// IMPORTANTE: El precio_unitario siempre se guarda en USD.
/// Si el usuario escribe en CUP, se convierte a USD antes de guardar.
/// Si escribe en USD, no se convierte.
class PriceCurrencyConverterWidget extends StatefulWidget {
  final String invoiceCurrency; // Moneda de la factura (informativo)
  final TextEditingController priceController; // Controller del precio
  final Function(double, String)?
  onPriceConverted; // Callback: (precioEnUSD, 'USD')

  const PriceCurrencyConverterWidget({
    Key? key,
    required this.invoiceCurrency,
    required this.priceController,
    this.onPriceConverted,
  }) : super(key: key);

  @override
  State<PriceCurrencyConverterWidget> createState() =>
      _PriceCurrencyConverterWidgetState();
}

class _PriceCurrencyConverterWidgetState
    extends State<PriceCurrencyConverterWidget> {
  String _inputCurrency = 'USD'; // Moneda en la que el usuario escribe
  double? _usdToCupRate; // Tasa USD→CUP (ej: 1 USD = 300 CUP)
  double? _convertedAmount; // Precio convertido a USD
  bool _isLoading = false;
  List<Map<String, dynamic>> _currencies = [];

  @override
  void initState() {
    super.initState();
    _inputCurrency = widget.invoiceCurrency; // Iniciar con moneda de factura
    _loadCurrencies();
    _loadUsdToCupRate();
    widget.priceController.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    widget.priceController.removeListener(_onPriceChanged);
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencies =
          await CurrencyDisplayService.getActiveCurrenciesForDisplay();
      if (mounted) {
        setState(() {
          _currencies = currencies;
        });
      }
    } catch (e) {
      print('Error loading currencies: $e');
    }
  }

  /// Carga la tasa USD→CUP usando CurrencyService (incluye override por tienda)
  Future<void> _loadUsdToCupRate() async {
    setState(() => _isLoading = true);
    try {
      final rate = await CurrencyService.getEffectiveUsdToCupRate();
      print('💱 Tasa USD→CUP obtenida: $rate');
      if (mounted) {
        setState(() {
          _usdToCupRate = rate;
          _isLoading = false;
        });
        _onPriceChanged();
      }
    } catch (e) {
      print('❌ Error loading USD→CUP rate: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Convierte el precio ingresado a USD
  void _onPriceChanged() {
    final inputAmount = double.tryParse(widget.priceController.text);
    if (inputAmount == null || inputAmount <= 0) {
      setState(() => _convertedAmount = null);
      return;
    }

    if (_inputCurrency == 'USD') {
      // Ya está en USD, no necesita conversión
      setState(() => _convertedAmount = null);
      widget.onPriceConverted?.call(inputAmount, 'USD');
    } else if (_inputCurrency == 'CUP' && _usdToCupRate != null && _usdToCupRate! > 0) {
      // CUP → USD: dividir por la tasa (si 1 USD = 300 CUP, entonces X CUP / 300 = Y USD)
      final priceInUsd = inputAmount / _usdToCupRate!;
      setState(() => _convertedAmount = priceInUsd);
      widget.onPriceConverted?.call(priceInUsd, 'USD');
    } else {
      setState(() => _convertedAmount = null);
    }
  }

  void _onCurrencyChanged(String newCurrency) {
    setState(() {
      _inputCurrency = newCurrency;
      _convertedAmount = null;
    });
    _onPriceChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.currency_exchange, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Conversión de Precio',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Selector de moneda de entrada
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Escribir precio en:',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _inputCurrency,
                      isDense: true,
                      items:
                          _currencies.map((curr) {
                            return DropdownMenuItem<String>(
                              value: curr['codigo'],
                              child: Text(
                                '${curr['simbolo']} ${curr['codigo']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _onCurrencyChanged(value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Información de conversión (siempre a USD)
            if (_convertedAmount != null &&
                _inputCurrency != 'USD') ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Precio convertido a USD:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${_convertedAmount!.toStringAsFixed(4)} USD',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    if (_usdToCupRate != null)
                      Text(
                        'Tasa: 1 USD = ${_usdToCupRate!.toStringAsFixed(2)} CUP',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[600],
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (_inputCurrency == 'USD') ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Precio en USD (se guarda directamente)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
