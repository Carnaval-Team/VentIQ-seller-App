import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order.dart';
import '../services/user_preferences_service.dart';

class BillCountDialog extends StatefulWidget {
  final Order order;
  final UserPreferencesService userPreferencesService;
  final VoidCallback onConfirmPayment;

  const BillCountDialog({
    Key? key,
    required this.order,
    required this.userPreferencesService,
    required this.onConfirmPayment,
  }) : super(key: key);

  @override
  State<BillCountDialog> createState() => _BillCountDialogState();
}

class _BillCountDialogState extends State<BillCountDialog> {
  List<String> _availableCurrencies = [];
  String? _selectedCurrency;
  List<Map<String, dynamic>> _denominations = [];
  Map<int, TextEditingController> _controllers =
      {}; // Controllers para cada campo
  Map<int, int> _billCounts = {}; // denominacion_id -> cantidad
  double _totalAmount = 0.0;
  double _remainingAmount = 0.0;
  double _cambioCupUsd = 420.0; // Tipo de cambio CUP-USD
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
    _loadCambioCupUsd();
    _remainingAmount = widget.order.total;
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
        _cambioCupUsd = 420.0; // Valor por defecto
      });
    }
  }

  @override
  void dispose() {
    // Limpiar controllers
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

        // Seleccionar USD por defecto si está disponible
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
      final denominations = await widget.userPreferencesService
          .getDenominacionesPorMoneda(currency);

      setState(() {
        _denominations = denominations;
        _billCounts.clear();
        _totalAmount = 0.0;
        _remainingAmount = widget.order.total;

        // Limpiar controllers anteriores
        for (final controller in _controllers.values) {
          controller.dispose();
        }
        _controllers.clear();

        // Inicializar contadores y controllers
        for (final denom in denominations) {
          final denominationId = denom['id'] as int;
          _billCounts[denominationId] = 0;
          _controllers[denominationId] = TextEditingController(text: '0');
        }
      });
    } catch (e) {
      print('❌ Error cargando denominaciones: $e');
    }
  }

  void _updateBillCount(int denominationId, int count) {
    setState(() {
      _billCounts[denominationId] = count;
      // Actualizar el controller correspondiente
      final controller = _controllers[denominationId];
      if (controller != null && controller.text != count.toString()) {
        controller.text = count.toString();
      }
      _calculateTotals();
    });
  }

  void _calculateTotals() {
    double total = 0.0;

    for (final denom in _denominations) {
      final denominationValue = (denom['denominacion'] as num).toDouble();
      final count = _billCounts[denom['id']] ?? 0;

      // Si la moneda seleccionada es USD, aplicar conversión a CUP
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

  List<Map<String, dynamic>> _calculateChange() {
    if (_remainingAmount >= 0) return [];

    double changeAmount = -_remainingAmount; // Cantidad positiva de vuelto

    // Si es USD, convertir el vuelto a USD para calcular denominaciones
    if (_selectedCurrency == 'USD') {
      changeAmount = changeAmount / _cambioCupUsd;
    }

    final changeBreakdown = <Map<String, dynamic>>[];
    double remaining = changeAmount;

    // Separar denominaciones en dos grupos:
    // 1. Denominaciones que tienen billetes contados (prioritarias)
    // 2. Denominaciones sin billetes contados (secundarias)
    final denominationsWithBills = <Map<String, dynamic>>[];
    final denominationsWithoutBills = <Map<String, dynamic>>[];

    for (final denom in _denominations) {
      final denominationId = denom['id'] as int;
      final count = _billCounts[denominationId] ?? 0;

      if (count > 0) {
        denominationsWithBills.add(denom);
      } else {
        denominationsWithoutBills.add(denom);
      }
    }

    // Ordenar ambos grupos de mayor a menor denominación
    denominationsWithBills.sort(
      (a, b) => (b['denominacion'] as num).compareTo(a['denominacion'] as num),
    );
    denominationsWithoutBills.sort(
      (a, b) => (b['denominacion'] as num).compareTo(a['denominacion'] as num),
    );

    // Primero intentar dar vuelto con denominaciones que tienen billetes
    print(
      '💰 Calculando vuelto prioritario con denominaciones que tienen billetes:',
    );
    for (final denom in denominationsWithBills) {
      final denominationValue = (denom['denominacion'] as num).toDouble();
      final denominationId = denom['id'] as int;
      final availableBills = _billCounts[denominationId] ?? 0;

      if (remaining >= denominationValue && remaining > 0.01) {
        final count = (remaining / denominationValue).floor();
        if (count > 0) {
          print(
            '  - \$${denominationValue.toStringAsFixed(0)} $_selectedCurrency: ${count} billetes (disponibles: $availableBills)',
          );
          changeBreakdown.add({
            'denominacion': denominationValue,
            'cantidad': count,
            'total': denominationValue * count,
            'moneda': _selectedCurrency,
          });
          remaining -= denominationValue * count;
        }
      }
    }

    // Si aún queda vuelto, usar las otras denominaciones
    if (remaining > 0.01 && denominationsWithoutBills.isNotEmpty) {
      print(
        '💰 Vuelto restante: \$${remaining.toStringAsFixed(2)} $_selectedCurrency - usando denominaciones sin billetes:',
      );
      for (final denom in denominationsWithoutBills) {
        final denominationValue = (denom['denominacion'] as num).toDouble();
        if (remaining >= denominationValue && remaining > 0.01) {
          final count = (remaining / denominationValue).floor();
          if (count > 0) {
            print(
              '  - \$${denominationValue.toStringAsFixed(0)} $_selectedCurrency: ${count} billetes',
            );
            changeBreakdown.add({
              'denominacion': denominationValue,
              'cantidad': count,
              'total': denominationValue * count,
              'moneda': _selectedCurrency,
            });
            remaining -= denominationValue * count;
          }
        }
      }
    }

    return changeBreakdown;
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

    final changeBreakdown = _calculateChange();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.6,
      builder:
          (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Contar Billetes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Información de la orden
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Orden: ${widget.order.id}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Total a pagar: \$${widget.order.total.toStringAsFixed(2)} CUP',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            // Mostrar información de conversión si es USD
                            if (_selectedCurrency == 'USD') ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
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
                      const SizedBox(height: 16),

                      // Selector de moneda
                      if (_availableCurrencies.length > 1) ...[
                        const Text(
                          'Moneda:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _selectedCurrency,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          items:
                              _availableCurrencies.map((currency) {
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
                        const SizedBox(height: 16),
                      ],

                      // Lista de denominaciones
                      const Text(
                        'Denominaciones:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Lista de denominaciones sin Expanded
                      ...List.generate(_denominations.length, (index) {
                        final denom = _denominations[index];
                        final denominationValue =
                            (denom['denominacion'] as num).toDouble();
                        final denominationId = denom['id'] as int;
                        final count = _billCounts[denominationId] ?? 0;

                        // Calcular subtotal con conversión si es USD
                        final subtotal =
                            _selectedCurrency == 'USD'
                                ? denominationValue * count * _cambioCupUsd
                                : denominationValue * count;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              // Denominación
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '\$${denominationValue.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Controles de cantidad
                              Expanded(
                                flex: 3,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Botón menos más compacto
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        onPressed:
                                            count > 0
                                                ? () => _updateBillCount(
                                                  denominationId,
                                                  count - 1,
                                                )
                                                : null,
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20,
                                        ),
                                        color: const Color(0xFF4A90E2),
                                      ),
                                    ),
                                    // Campo de texto más compacto
                                    Expanded(
                                      child: Container(
                                        height: 36,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: TextField(
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          controller:
                                              _controllers[denominationId]!,
                                          onChanged: (value) {
                                            final newCount =
                                                int.tryParse(value) ?? 0;
                                            _updateBillCount(
                                              denominationId,
                                              newCount,
                                            );
                                          },
                                          style: const TextStyle(fontSize: 14),
                                          decoration: const InputDecoration(
                                            border: OutlineInputBorder(),
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 8,
                                                ),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Botón más compacto
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        onPressed:
                                            () => _updateBillCount(
                                              denominationId,
                                              count + 1,
                                            ),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 20,
                                        ),
                                        color: const Color(0xFF4A90E2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Subtotal
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '\$${subtotal.toStringAsFixed(2)}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (_selectedCurrency == 'USD' && count > 0)
                                      Text(
                                        '(${(denominationValue * count).toStringAsFixed(2)} USD)',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontSize: 11,
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
                      }),
                      const SizedBox(height: 16),

                      // Resumen de totales
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              _remainingAmount > 0
                                  ? Colors.orange[50]
                                  : _remainingAmount < 0
                                  ? Colors.green[50]
                                  : Colors.blue[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                _remainingAmount > 0
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
                                  'Total contado:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '\$${_totalAmount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
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
                                    color:
                                        _remainingAmount > 0
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
                                    color:
                                        _remainingAmount > 0
                                            ? Colors.orange[700]
                                            : _remainingAmount < 0
                                            ? Colors.green[700]
                                            : Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),

                            // Mostrar vuelto si sobra dinero
                            if (changeBreakdown.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Divider(),
                              const SizedBox(height: 8),
                              const Text(
                                'Vuelto a devolver:',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...changeBreakdown.map(
                                (change) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${change['cantidad']}x \$${change['denominacion'].toStringAsFixed(0)} ${change['moneda']}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '\$${change['total'].toStringAsFixed(2)} ${change['moneda']}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          // Si es USD, mostrar también el equivalente en CUP
                                          if (change['moneda'] == 'USD')
                                            Text(
                                              '(\$${(change['total'] * _cambioCupUsd).toStringAsFixed(2)} CUP)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

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
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  _remainingAmount <= 0
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
                              child: const Text('Confirmar Pago'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
