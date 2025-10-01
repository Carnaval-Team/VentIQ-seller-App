import 'package:flutter/material.dart';
import '../services/currency_display_service.dart';

/// Widget especializado para conversión de precios en diálogos de inventario
class PriceCurrencyConverterWidget extends StatefulWidget {
  final String invoiceCurrency; // Moneda de la factura (objetivo)
  final TextEditingController priceController; // Controller del precio
  final Function(double, String)?
  onPriceConverted; // Callback cuando se convierte

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
  double? _exchangeRate;
  double? _convertedAmount;
  bool _isLoading = false;
  List<Map<String, dynamic>> _currencies = [];

  @override
  void initState() {
    super.initState();
    _inputCurrency = widget.invoiceCurrency; // Iniciar con moneda de factura
    _loadCurrencies();
    _loadExchangeRate();
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

  Future<void> _loadExchangeRate() async {
    if (_inputCurrency == widget.invoiceCurrency) {
      setState(() {
        _exchangeRate = 1.0;
        _convertedAmount = null;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay(
        _inputCurrency,
        widget.invoiceCurrency,
      );
      if (mounted) {
        setState(() {
          _exchangeRate = rate;
          _isLoading = false;
        });
        _onPriceChanged();
      }
    } catch (e) {
      print('Error loading exchange rate: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onPriceChanged() {
    final inputAmount = double.tryParse(widget.priceController.text);
    if (inputAmount != null && _exchangeRate != null) {
      final converted = inputAmount * _exchangeRate!;
      setState(() {
        _convertedAmount = converted;
      });

      // Notificar el precio convertido
      widget.onPriceConverted?.call(converted, widget.invoiceCurrency);
    } else {
      setState(() {
        _convertedAmount = null;
      });
    }
  }

  void _onCurrencyChanged(String newCurrency) {
    setState(() {
      _inputCurrency = newCurrency;
      _exchangeRate = null;
      _convertedAmount = null;
    });
    _loadExchangeRate();
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

            // Información de conversión
            if (_convertedAmount != null &&
                _inputCurrency != widget.invoiceCurrency) ...[
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
                            'Precio convertido a ${widget.invoiceCurrency}:',
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
                      '${_getCurrencySymbol(widget.invoiceCurrency)}${_convertedAmount!.toStringAsFixed(4)} ${widget.invoiceCurrency}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                    if (_exchangeRate != null)
                      Text(
                        'Tasa: 1 $_inputCurrency = ${_exchangeRate!.toStringAsFixed(4)} ${widget.invoiceCurrency}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[600],
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (_inputCurrency == widget.invoiceCurrency) ...[
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
                        'Precio en moneda de factura (${widget.invoiceCurrency})',
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

  String _getCurrencySymbol(String currencyCode) {
    switch (currencyCode) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'CUP':
        return '\$';
      default:
        return '';
    }
  }
}
