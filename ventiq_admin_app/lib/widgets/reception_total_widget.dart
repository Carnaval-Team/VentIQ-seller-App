import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/currency_display_service.dart';

/// Widget para mostrar el total de la recepción con conversión de monedas
class ReceptionTotalWidget extends StatefulWidget {
  final double totalAmount;
  final String invoiceCurrency;
  final List<Map<String, dynamic>> selectedProducts;
  final Function(double, String)? onTotalConverted;

  const ReceptionTotalWidget({
    Key? key,
    required this.totalAmount,
    required this.invoiceCurrency,
    required this.selectedProducts,
    this.onTotalConverted,
  }) : super(key: key);

  @override
  State<ReceptionTotalWidget> createState() => _ReceptionTotalWidgetState();
}

class _ReceptionTotalWidgetState extends State<ReceptionTotalWidget> {
  String _comparisonCurrency = 'CUP';
  double? _convertedAmount;
  double? _exchangeRate;
  bool _isLoading = false;
  List<Map<String, dynamic>> _currencies = [];

  @override
  void initState() {
    super.initState();
    _comparisonCurrency = widget.invoiceCurrency == 'CUP' ? 'USD' : 'CUP';
    _loadCurrencies();
    _loadExchangeRate();
  }

  @override
  void didUpdateWidget(ReceptionTotalWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoiceCurrency != widget.invoiceCurrency) {
      // If the invoice currency changes and now matches the comparison currency,
      // we need to select a new, valid comparison currency to avoid the error.
      if (widget.invoiceCurrency == _comparisonCurrency) {
        setState(() {
          // A simple, predictable fallback.
          _comparisonCurrency = widget.invoiceCurrency == 'CUP' ? 'USD' : 'CUP';
        });
      }
    }
    // Always reload the exchange rate if amount or currency changes.
    if (oldWidget.totalAmount != widget.totalAmount ||
        oldWidget.invoiceCurrency != widget.invoiceCurrency) {
      _loadExchangeRate();
    }
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
    if (widget.invoiceCurrency == _comparisonCurrency) {
      setState(() {
        _exchangeRate = 1.0;
        _convertedAmount = widget.totalAmount;
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay(
        widget.invoiceCurrency,
        _comparisonCurrency,
      );
      if (mounted) {
        setState(() {
          _exchangeRate = rate;
          _convertedAmount = widget.totalAmount * rate;
          _isLoading = false;
        });

        // Notificar el total convertido
        widget.onTotalConverted?.call(_convertedAmount!, _comparisonCurrency);
      }
    } catch (e) {
      print('Error loading exchange rate: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onComparisonCurrencyChanged(String newCurrency) {
    setState(() {
      _comparisonCurrency = newCurrency;
      _exchangeRate = null;
      _convertedAmount = null;
    });
    _loadExchangeRate();
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: ExpansionTile(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.receipt_long,
                color: AppColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Datos de la Recepción',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${widget.selectedProducts.length} productos • ${_getCurrencySymbol(widget.invoiceCurrency)}${widget.totalAmount.toStringAsFixed(2)} ${widget.invoiceCurrency}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing:
            _isLoading
                ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
                : null,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Total principal (moneda de factura)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total en ${widget.invoiceCurrency}',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${_getCurrencySymbol(widget.invoiceCurrency)}${widget.totalAmount.toStringAsFixed(2)} ${widget.invoiceCurrency}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Selector de moneda de comparación
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ver también en:',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _comparisonCurrency,
                        isDense: true,
                        items:
                            _currencies
                                .where(
                                  (curr) =>
                                      curr['codigo'] != widget.invoiceCurrency,
                                )
                                .map((curr) {
                                  return DropdownMenuItem<String>(
                                    value: curr['codigo'],
                                    child: Text(
                                      '${curr['simbolo']} ${curr['codigo']}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                })
                                .toList(),
                        onChanged: (value) {
                          if (value != null)
                            _onComparisonCurrencyChanged(value);
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Total convertido
              if (_convertedAmount != null && !_isLoading) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.currency_exchange,
                        color: AppColors.info,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Equivalente en $_comparisonCurrency:',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.info,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${_getCurrencySymbol(_comparisonCurrency)}${_convertedAmount!.toStringAsFixed(2)} $_comparisonCurrency',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.info,
                              ),
                            ),
                            if (_exchangeRate != null && _exchangeRate != 1.0)
                              Text(
                                'Tasa: 1 ${widget.invoiceCurrency} = ${_exchangeRate!.toStringAsFixed(4)} $_comparisonCurrency',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Resumen de productos
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de Productos:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Productos únicos:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${widget.selectedProducts.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cantidad total:',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${widget.selectedProducts.fold(0.0, (sum, item) => sum + (item['cantidad'] as double? ?? 0.0)).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
