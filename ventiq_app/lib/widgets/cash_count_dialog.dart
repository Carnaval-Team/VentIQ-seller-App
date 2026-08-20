import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_preferences_service.dart';

/// Diálogo para contar billetes de CUP y USD y calcular el monto total en CUP
/// usando el tipo de cambio de la tienda. Devuelve el total en CUP al cerrar.
class CashCountDialog extends StatefulWidget {
  final UserPreferencesService userPreferencesService;

  const CashCountDialog({
    Key? key,
    required this.userPreferencesService,
  }) : super(key: key);

  @override
  State<CashCountDialog> createState() => _CashCountDialogState();
}

class _CashCountDialogState extends State<CashCountDialog> {
  bool _isLoading = true;
  double _cambioCupUsd = 420.0;
  final List<String> _currencies = [];
  String? _selectedCurrency;

  final Map<String, List<Map<String, dynamic>>> _denominationsByCurrency = {};
  final Map<String, Map<int, TextEditingController>> _controllersByCurrency = {};
  final Map<String, Map<int, int>> _countsByCurrency = {};

  double _totalCup = 0.0;
  double _totalUsdCup = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final map in _controllersByCurrency.values) {
      for (final controller in map.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final rate = await widget.userPreferencesService.getCambioCupUsd();
      final availableCurrencies =
          await widget.userPreferencesService.getMonedasDisponibles();

      // Asegurar que siempre estén CUP y USD si están configuradas
      final currencies = <String>[];
      if (availableCurrencies.contains('CUP')) currencies.add('CUP');
      if (availableCurrencies.contains('USD')) currencies.add('USD');
      // Fallback: si no hay monedas configuradas, mostrar al menos CUP y USD
      if (currencies.isEmpty) {
        currencies.addAll(['CUP', 'USD']);
      }

      for (final currency in currencies) {
        var denoms = await widget.userPreferencesService
            .getDenominacionesPorMoneda(currency);
        if (denoms.isEmpty && currency == 'CUP') {
          denoms = _defaultCupDenominations();
        } else if (denoms.isEmpty && currency == 'USD') {
          denoms = _defaultUsdDenominations();
        }
        _denominationsByCurrency[currency] = denoms;
        _countsByCurrency[currency] = {};
        _controllersByCurrency[currency] = {};
        for (final denom in denoms) {
          final id = denom['id'] as int;
          _countsByCurrency[currency]![id] = 0;
          _controllersByCurrency[currency]![id] =
              TextEditingController(text: '');
        }
      }

      if (mounted) {
        setState(() {
          _cambioCupUsd = rate;
          _currencies.addAll(currencies);
          _selectedCurrency = currencies.isNotEmpty ? currencies.first : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando contador de efectivo: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _defaultCupDenominations() {
    const values = [1000, 500, 200, 100, 50, 20, 10, 5, 3, 1];
    return values
        .asMap()
        .entries
        .map((e) => {'id': -100 - e.key, 'denominacion': e.value, 'moneda': 'CUP'})
        .toList();
  }

  List<Map<String, dynamic>> _defaultUsdDenominations() {
    const values = [100, 50, 20, 10, 5, 1];
    return values
        .asMap()
        .entries
        .map((e) => {'id': -200 - e.key, 'denominacion': e.value, 'moneda': 'USD'})
        .toList();
  }

  void _setCount(String currency, int denominationId, int count) {
    setState(() {
      _countsByCurrency[currency]?[denominationId] = count;
      final controller = _controllersByCurrency[currency]?[denominationId];
      if (controller != null) {
        final newText = count == 0 ? '' : count.toString();
        if (controller.text != newText) {
          controller.text = newText;
        }
      }
      _calculateTotals();
    });
  }

  void _updateCountFromInput(String currency, int denominationId, String value) {
    final count = int.tryParse(value) ?? 0;
    setState(() {
      _countsByCurrency[currency]?[denominationId] = count;
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    double cup = 0.0;
    double usdCup = 0.0;

    for (final entry in _denominationsByCurrency.entries) {
      final currency = entry.key;
      for (final denom in entry.value) {
        final id = denom['id'] as int;
        final value = (denom['denominacion'] as num).toDouble();
        final count = _countsByCurrency[currency]?[id] ?? 0;
        if (currency == 'USD') {
          usdCup += value * count * _cambioCupUsd;
        } else {
          cup += value * count;
        }
      }
    }

    setState(() {
      _totalCup = cup;
      _totalUsdCup = usdCup;
    });
  }

  void _useTotal() {
    Navigator.pop(context, _totalCup + _totalUsdCup);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlertDialog(
        content: Container(
          height: 150,
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF4A90E2)),
              SizedBox(height: 16),
              Text('Cargando denominaciones...'),
            ],
          ),
        ),
      );
    }

    if (_currencies.isEmpty) {
      return AlertDialog(
        title: const Text('Error'),
        content: const Text('No hay monedas configuradas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      );
    }

    final selectedDenoms = _denominationsByCurrency[_selectedCurrency] ?? [];
    final totalCounted = _totalCup + _totalUsdCup;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Contador de Billetes')),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tasa de cambio
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Text(
                'Tasa de cambio: 1 USD = ${_cambioCupUsd.toStringAsFixed(2)} CUP',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.amber[800],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Selector de moneda
            if (_currencies.length > 1) ...[
              Row(
                children: _currencies.map((currency) {
                  final selected = _selectedCurrency == currency;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(currency),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _selectedCurrency = currency);
                        },
                        selectedColor: const Color(0xFF4A90E2),
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Lista de denominaciones
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: selectedDenoms.length,
                itemBuilder: (context, index) {
                  final denom = selectedDenoms[index];
                  final id = denom['id'] as int;
                  final value = (denom['denominacion'] as num).toDouble();
                  final currency = _selectedCurrency!;
                  final controller = _controllersByCurrency[currency]![id]!;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(
                            '\$${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: controller,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: 'Cantidad',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            onChanged: (value) {
                              _updateCountFromInput(currency, id, value);
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          onPressed: () {
                            final current =
                                int.tryParse(controller.text) ?? 0;
                            if (current > 0) {
                              _setCount(currency, id, current - 1);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: Color(0xFF4A90E2)),
                          onPressed: () {
                            final current =
                                int.tryParse(controller.text) ?? 0;
                            _setCount(currency, id, current + 1);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const Divider(height: 24),

            // Totales
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CUP:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                Text(
                  '\$${_totalCup.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'USD en CUP:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                Text(
                  '\$${_totalUsdCup.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total CUP:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '\$${totalCounted.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _useTotal,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90E2),
            foregroundColor: Colors.white,
          ),
          child: const Text('Usar monto'),
        ),
      ],
    );
  }
}
