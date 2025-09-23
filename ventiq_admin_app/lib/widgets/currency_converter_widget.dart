import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/currency_display_service.dart';

/// Widget convertidor de monedas bidireccional tipo traductor
class CurrencyConverterWidget extends StatefulWidget {
  final String initialFromCurrency;
  final String initialToCurrency;
  final double? initialAmount;
  final Function(double, String, String)? onConversionChanged;

  const CurrencyConverterWidget({
    Key? key,
    this.initialFromCurrency = 'USD',
    this.initialToCurrency = 'CUP',
    this.initialAmount,
    this.onConversionChanged,
  }) : super(key: key);

  @override
  State<CurrencyConverterWidget> createState() => _CurrencyConverterWidgetState();
}

class _CurrencyConverterWidgetState extends State<CurrencyConverterWidget> {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  
  List<Map<String, dynamic>> _currencies = [];
  String _fromCurrency = 'USD';
  String _toCurrency = 'CUP';
  double? _exchangeRate;
  bool _isLoading = false;
  bool _isFromActive = true; // Controla cuál campo está siendo editado

  @override
  void initState() {
    super.initState();
    _fromCurrency = widget.initialFromCurrency;
    _toCurrency = widget.initialToCurrency;
    
    if (widget.initialAmount != null) {
      _fromController.text = widget.initialAmount!.toStringAsFixed(2);
    }
    
    _loadCurrencies();
    _loadExchangeRate();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
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
    setState(() => _isLoading = true);
    try {
      final rate = await CurrencyDisplayService.getExchangeRateForDisplay(_fromCurrency, _toCurrency);
      if (mounted) {
        setState(() {
          _exchangeRate = rate;
          _isLoading = false;
        });
        _performConversion();
      }
    } catch (e) {
      print('Error loading exchange rate: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _performConversion() {
    if (_exchangeRate == null) return;

    if (_isFromActive) {
      // Convertir de FROM a TO
      final fromAmount = double.tryParse(_fromController.text);
      if (fromAmount != null) {
        final toAmount = fromAmount * _exchangeRate!;
        _toController.text = toAmount.toStringAsFixed(4);
        
        // Notificar cambio
        widget.onConversionChanged?.call(fromAmount, _fromCurrency, _toCurrency);
      } else {
        _toController.clear();
      }
    } else {
      // Convertir de TO a FROM (conversión inversa)
      final toAmount = double.tryParse(_toController.text);
      if (toAmount != null && _exchangeRate! > 0) {
        final fromAmount = toAmount / _exchangeRate!;
        _fromController.text = fromAmount.toStringAsFixed(4);
        
        // Notificar cambio
        widget.onConversionChanged?.call(toAmount, _toCurrency, _fromCurrency);
      } else {
        _fromController.clear();
      }
    }
  }

  void _swapCurrencies() {
    setState(() {
      // Intercambiar monedas
      final tempCurrency = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = tempCurrency;

      // Intercambiar valores
      final tempText = _fromController.text;
      _fromController.text = _toController.text;
      _toController.text = tempText;

      // Mantener el foco en el campo activo
      _isFromActive = !_isFromActive;
    });

    // Recargar tasa de cambio con nueva dirección
    _loadExchangeRate();
  }

  Widget _buildCurrencyField({
    required TextEditingController controller,
    required String currency,
    required bool isActive,
    required Function(String) onCurrencyChanged,
    required Function() onTap,
  }) {
    final currencyInfo = _currencies.firstWhere(
      (c) => c['codigo'] == currency,
      orElse: () => {'codigo': currency, 'simbolo': '\$', 'nombre': currency},
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.blue : Colors.grey.withOpacity(0.3),
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selector de moneda
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: currency,
                    isDense: true,
                    items: _currencies.map((curr) {
                      return DropdownMenuItem<String>(
                        value: curr['codigo'],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              curr['simbolo'] ?? '\$',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              curr['codigo'],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onCurrencyChanged(value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  currencyInfo['nombre'] ?? currency,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Campo de entrada
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.blue[700] : Colors.grey[700],
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(
                fontSize: 24,
                color: Colors.grey[400],
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            onTap: onTap,
            onChanged: (value) {
              _performConversion();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.currency_exchange, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Convertidor de Monedas',
                  style: TextStyle(
                    fontSize: 16,
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
            
            const SizedBox(height: 16),
            
            // Campo FROM
            _buildCurrencyField(
              controller: _fromController,
              currency: _fromCurrency,
              isActive: _isFromActive,
              onCurrencyChanged: (currency) {
                setState(() {
                  _fromCurrency = currency;
                  _isFromActive = true;
                });
                _loadExchangeRate();
              },
              onTap: () {
                setState(() {
                  _isFromActive = true;
                });
                _performConversion();
              },
            ),
            
            const SizedBox(height: 8),
            
            // Botón de intercambio
            Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  icon: const Icon(Icons.swap_vert, color: Colors.white),
                  onPressed: _swapCurrencies,
                  tooltip: 'Intercambiar monedas',
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Campo TO
            _buildCurrencyField(
              controller: _toController,
              currency: _toCurrency,
              isActive: !_isFromActive,
              onCurrencyChanged: (currency) {
                setState(() {
                  _toCurrency = currency;
                  _isFromActive = false;
                });
                _loadExchangeRate();
              },
              onTap: () {
                setState(() {
                  _isFromActive = false;
                });
                _performConversion();
              },
            ),
            
            const SizedBox(height: 12),
            
            // Información de tasa
            if (_exchangeRate != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text(
                      '1 $_fromCurrency = ${_exchangeRate!.toStringAsFixed(4)} $_toCurrency',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
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
