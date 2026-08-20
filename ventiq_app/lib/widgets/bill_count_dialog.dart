import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order.dart';
import '../services/user_preferences_service.dart';

class BillCountDialog extends StatefulWidget {
  final Order order;
  final UserPreferencesService userPreferencesService;
  final VoidCallback onConfirmPayment;
  final bool closeOnly;
  final String confirmLabel;
  final String cancelLabel;

  const BillCountDialog({
    Key? key,
    required this.order,
    required this.userPreferencesService,
    required this.onConfirmPayment,
    this.closeOnly = false,
    this.confirmLabel = 'Confirmar Pago',
    this.cancelLabel = 'Cancelar',
  }) : super(key: key);

  @override
  State<BillCountDialog> createState() => _BillCountDialogState();
}

class _BillCountDialogState extends State<BillCountDialog> {
  List<String> _availableCurrencies = [];
  String? _selectedCurrency;
  List<Map<String, dynamic>> _denominations = [];
  List<Map<String, dynamic>> _allDenominations = [];
  Set<int> _hiddenDenominations = {};
  Map<int, TextEditingController> _controllers = {};
  Map<int, int> _billCounts = {};
  double _totalAmount = 0.0;
  double _remainingAmount = 0.0;
  double _cambioCupUsd = 420.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
    _remainingAmount = widget.order.total;
  }

  Future<void> _initialize() async {
    _hiddenDenominations =
        await widget.userPreferencesService.getHiddenDenominations();
    await _loadCurrencies();
    _loadCambioCupUsd();
  }

  Future<void> _loadCambioCupUsd() async {
    try {
      final cambio = await widget.userPreferencesService.getCambioCupUsd();
      setState(() {
        _cambioCupUsd = cambio;
      });
      print('💱 Tipo de cambio CUP-USD cargado: $_cambioCupUsd');
    } catch (e) {
      print('❌ Error cargando tipo de cambio: $e');
      setState(() {
        _cambioCupUsd = 420.0;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencies =
          await widget.userPreferencesService.getMonedasDisponibles();
      setState(() {
        _availableCurrencies = currencies;
        _isLoading = false;

        if (currencies.contains('CUP')) {
          _selectedCurrency = 'CUP';
          _loadDenominations('CUP');
        } else if (currencies.isNotEmpty) {
          _selectedCurrency = currencies.first;
          _loadDenominations(currencies.first);
        }
      });
    } catch (e) {
      print('❌ Error cargando monedas: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDenominations(String currency) async {
    try {
      _allDenominations =
          await widget.userPreferencesService.getDenominacionesPorMoneda(
            currency,
          );

      setState(() {
        _denominations =
            _allDenominations
                .where(
                  (d) => !_hiddenDenominations.contains(d['id'] as int),
                )
                .toList();
        _billCounts.clear();
        _totalAmount = 0.0;
        _remainingAmount = widget.order.total;

        for (final controller in _controllers.values) {
          controller.dispose();
        }
        _controllers.clear();

        for (final denom in _denominations) {
          final denominationId = denom['id'] as int;
          _billCounts[denominationId] = 0;
          _controllers[denominationId] = TextEditingController(text: '');
        }
      });
    } catch (e) {
      print('❌ Error cargando denominaciones: $e');
    }
  }

  Future<void> _applyHiddenFilter() async {
    setState(() {
      _denominations =
          _allDenominations
              .where(
                (d) => !_hiddenDenominations.contains(d['id'] as int),
              )
              .toList();
      for (final denom in _denominations) {
        final id = denom['id'] as int;
        _billCounts.putIfAbsent(id, () => 0);
        _controllers.putIfAbsent(
          id,
          () => TextEditingController(text: ''),
        );
      }
      _calculateTotals();
    });
  }

  void _setCount(int denominationId, int count) {
    setState(() {
      _billCounts[denominationId] = count;
      final controller = _controllers[denominationId];
      if (controller != null) {
        final newText = count == 0 ? '' : count.toString();
        if (controller.text != newText) {
          controller.text = newText;
        }
      }
      _calculateTotals();
    });
  }

  void _updateCountFromInput(int denominationId, String value) {
    final count = int.tryParse(value) ?? 0;
    setState(() {
      _billCounts[denominationId] = count;
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    double total = 0.0;

    for (final denom in _denominations) {
      final denominationValue = (denom['denominacion'] as num).toDouble();
      final count = _billCounts[denom['id']] ?? 0;

      if (_selectedCurrency == 'USD') {
        total += denominationValue * count * _cambioCupUsd;
      } else {
        total += denominationValue * count;
      }
    }

    _totalAmount = total;
    _remainingAmount = widget.order.total - total;

    print('💰 Cálculo de totales:');
    print('  - Moneda: $_selectedCurrency');
    print('  - Total contado: $_totalAmount');
    print('  - Tipo de cambio USD: $_cambioCupUsd');
    print('  - Falta/Sobra: $_remainingAmount');
  }

  void _showDenominationConfigDialog() {
    if (_allDenominations.isEmpty || _selectedCurrency == null) return;
    final all = List<Map<String, dynamic>>.from(_allDenominations);
    final tempHidden = Set<int>.from(_hiddenDenominations);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Mostrar / ocultar denominaciones'),
            content: StatefulBuilder(
              builder:
                  (context, setStateDialog) => SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children:
                          all.map((denom) {
                            final id = denom['id'] as int;
                            final value =
                                (denom['denominacion'] as num).toDouble();
                            final isVisible = !tempHidden.contains(id);
                            return CheckboxListTile(
                              dense: true,
                              title: Text('\$${value.toStringAsFixed(0)}'),
                              value: isVisible,
                              onChanged: (v) {
                                setStateDialog(() {
                                  if (v == true) {
                                    tempHidden.remove(id);
                                  } else {
                                    tempHidden.add(id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                    ),
                  ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () async {
                  _hiddenDenominations = tempHidden;
                  await widget.userPreferencesService
                      .saveHiddenDenominations(_hiddenDenominations);
                  await _applyHiddenFilter();
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 200,
        child: const Center(
          child: Column(
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

    if (_availableCurrencies.isEmpty) {
      return Container(
        height: 300,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'No hay denominaciones de moneda configuradas. '
              'Contacta al administrador.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }

    final viewPadding = MediaQuery.of(context).viewPadding;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8 + viewPadding.top,
                  bottom: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Contar Billetes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: _showDenominationConfigDialog,
                              icon: const Icon(Icons.settings),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (_availableCurrencies.length > 1) ...[
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _selectedCurrency,
                        decoration: InputDecoration(
                          labelText: 'Moneda',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        items: _availableCurrencies.map((currency) {
                          return DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedCurrency = value;
                            });
                            _loadDenominations(value);
                          }
                        },
                      ),
                    ],
                    if (_selectedCurrency == 'USD') ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amber[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.amber[700],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Conversión USD → CUP: 1 USD = ${_cambioCupUsd.toStringAsFixed(2)} CUP',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber[700],
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

              // Denominaciones (SCROLLABLE)
              Expanded(
                child: ListView.builder(

                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: _denominations.length,
                  itemBuilder: (context, index) {
                    final denom = _denominations[index];
                    final denominationValue =
                        (denom['denominacion'] as num).toDouble();
                    final denominationId = denom['id'] as int;
                    final count = _billCounts[denominationId] ?? 0;

                    final subtotal = _selectedCurrency == 'USD'
                        ? denominationValue * count * _cambioCupUsd
                        : denominationValue * count;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text(
                              '\$${denominationValue.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: count > 0
                                      ? () => _setCount(
                                            denominationId,
                                            count - 1,
                                          )
                                      : null,
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 18,
                                  ),
                                  color: const Color(0xFF4A90E2),
                                ),
                              ),
                              SizedBox(
                                width: 46,
                                height: 28,
                                child: TextField(
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  controller: _controllers[denominationId]!,
                                  onChanged: (value) {
                                    _updateCountFromInput(
                                      denominationId,
                                      value,
                                    );
                                  },
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => _setCount(
                                    denominationId,
                                    count + 1,
                                  ),
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                  ),
                                  color: const Color(0xFF4A90E2),
                                ),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '\$${subtotal.toStringAsFixed(2)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (_selectedCurrency == 'USD' && count > 0)
                                  Text(
                                    '(${(denominationValue * count).toStringAsFixed(2)} USD)',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Footer fijo
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  8 + bottomPadding,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Resumen de totales
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _remainingAmount > 0
                            ? Colors.orange[50]
                            : _remainingAmount < 0
                                ? Colors.green[50]
                                : Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _remainingAmount > 0
                              ? Colors.orange[300]!
                              : _remainingAmount < 0
                                  ? Colors.green[300]!
                                  : Colors.blue[300]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total a pagar:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '\$${widget.order.total.toStringAsFixed(2)} CUP',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total contado:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '\$${_totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _remainingAmount > 0
                                    ? 'Falta:'
                                    : _remainingAmount < 0
                                        ? 'Sobra:'
                                        : 'Exacto:',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _remainingAmount > 0
                                      ? Colors.orange[700]
                                      : _remainingAmount < 0
                                          ? Colors.green[700]
                                          : Colors.blue[700],
                                ),
                              ),
                              Text(
                                '\$${_remainingAmount.abs().toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _remainingAmount > 0
                                      ? Colors.orange[700]
                                      : _remainingAmount < 0
                                          ? Colors.green[700]
                                          : Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Botones
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            child: Text(widget.cancelLabel),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.closeOnly
                                ? () => Navigator.pop(context)
                                : _remainingAmount <= 0
                                    ? () {
                                        Navigator.pop(context);
                                        widget.onConfirmPayment();
                                      }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            child: Text(widget.confirmLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }
}
