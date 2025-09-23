import 'package:flutter/material.dart';
import '../services/currency_display_service.dart';

/// Widget ligero para mostrar información de moneda y tasa de cambio
class CurrencyInfoWidget extends StatefulWidget {
  final String selectedCurrency;
  final double? amount;
  final Function(String)? onCurrencyChanged;
  final bool showConverter;

  const CurrencyInfoWidget({
    Key? key,
    this.selectedCurrency = 'USD',
    this.amount,
    this.onCurrencyChanged,
    this.showConverter = true,
  }) : super(key: key);

  @override
  State<CurrencyInfoWidget> createState() => _CurrencyInfoWidgetState();
}

class _CurrencyInfoWidgetState extends State<CurrencyInfoWidget> {
  List<Map<String, dynamic>> _currencies = [];
  Map<String, dynamic>? _exchangeRateInfo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    _loadExchangeRate();
  }

  @override
  void didUpdateWidget(CurrencyInfoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCurrency != widget.selectedCurrency) {
      _loadExchangeRate();
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencies = await CurrencyDisplayService.getActiveCurrenciesForDisplay();
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
    if (widget.selectedCurrency == 'CUP') return;

    setState(() => _isLoading = true);
    try {
      final rateInfo = await CurrencyDisplayService.getExchangeRateInfoForDisplay(
        widget.selectedCurrency,
        'CUP',
      );
      if (mounted) {
        setState(() {
          _exchangeRateInfo = rateInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading exchange rate: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.currency_exchange, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Información de Moneda',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // Selector de moneda
            if (widget.onCurrencyChanged != null) ...[
              Row(
                children: [
                  Text('Moneda:', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: widget.selectedCurrency,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      items: _currencies.map((currency) {
                        return DropdownMenuItem<String>(
                          value: currency['codigo'],
                          child: Text(
                            '${currency['simbolo']} ${currency['codigo']} - ${currency['nombre']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          widget.onCurrencyChanged!(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Información de tasa de cambio
            if (widget.selectedCurrency != 'CUP') ...[
              if (_isLoading)
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('Cargando tasa...', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                )
              else if (_exchangeRateInfo != null) ...[
                Row(
                  children: [
                    Text('Tasa ${widget.selectedCurrency}/CUP:', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    Text(
                      '${_exchangeRateInfo!['tasa'].toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _exchangeRateInfo!['is_current'] ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (!_exchangeRateInfo!['is_current'])
                      Icon(Icons.warning, size: 14, color: Colors.orange),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Actualizada: ${_formatDate(_exchangeRateInfo!['fecha_actualizacion'])}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ] else
                Text(
                  'Tasa no disponible',
                  style: TextStyle(fontSize: 11, color: Colors.red),
                ),
            ],

            // Conversión de monto (si se proporciona)
            if (widget.showConverter && widget.amount != null && widget.amount! > 0 && widget.selectedCurrency != 'CUP') ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conversión:',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[700]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyDisplayService.formatAmountForDisplay(widget.amount!, widget.selectedCurrency),
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_exchangeRateInfo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '≈ ${CurrencyDisplayService.formatAmountForDisplay(widget.amount! * _exchangeRateInfo!['tasa'], 'CUP')}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green[700]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Hoy';
      } else if (difference.inDays == 1) {
        return 'Ayer';
      } else if (difference.inDays < 7) {
        return 'Hace ${difference.inDays} días';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return 'Fecha no válida';
    }
  }
}
