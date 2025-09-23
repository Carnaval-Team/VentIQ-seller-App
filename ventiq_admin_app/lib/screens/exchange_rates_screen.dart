import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/currency_display_service.dart';
import '../widgets/currency_converter_widget.dart';

/// Pantalla para visualizar tasas de cambio (solo lectura)
class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({Key? key}) : super(key: key);

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  List<Map<String, dynamic>> _rates = [];
  List<Map<String, dynamic>> _currencies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final currencies = await CurrencyDisplayService.getActiveCurrenciesForDisplay();
      final rates = await CurrencyDisplayService.getAllRatesForDisplay();
      
      setState(() {
        _currencies = currencies;
        _rates = rates;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshRates() async {
    setState(() => _isLoading = true);
    try {
      final success = await CurrencyDisplayService.refreshRatesForDisplay();
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tasas actualizadas correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadData(); // Recargar datos después de actualizar
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al actualizar tasas'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasas de Cambio'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshRates,
            tooltip: 'Actualizar tasas desde API',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header info
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.blue.withOpacity(0.1),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Las tasas de cambio se actualizan automáticamente. Usa el convertidor para ver precios en diferentes monedas.',
                            style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Convertidor de monedas
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: CurrencyConverterWidget(
                      onConversionChanged: (amount, fromCurrency, toCurrency) {
                        // Callback opcional para manejar cambios
                        print('Conversión: $amount $fromCurrency → $toCurrency');
                      },
                    ),
                  ),

                  // Título de tasas actuales
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.list, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Tasas Actuales',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Lista de tasas (solo lectura)
                  _rates.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.currency_exchange, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'No hay tasas de cambio disponibles',
                                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _rates.length,
                          itemBuilder: (context, index) {
                            final rate = _rates[index];
                            return _buildRateCard(rate);
                          },
                        ),

                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildRateCard(Map<String, dynamic> rate) {
    final fromCurrency = rate['moneda_origen'];
    final toCurrency = rate['moneda_destino'];
    final rateValue = (rate['tasa'] as num).toDouble();
    final lastUpdate = DateTime.parse(rate['fecha_actualizacion']);
    final isRecent = CurrencyDisplayService.isRateCurrentForDisplay(rate['fecha_actualizacion']);

    // Obtener información de las monedas
    final fromCurrencyInfo = _currencies.firstWhere(
      (c) => c['codigo'] == fromCurrency,
      orElse: () => {'codigo': fromCurrency, 'simbolo': '\$'},
    );
    final toCurrencyInfo = _currencies.firstWhere(
      (c) => c['codigo'] == toCurrency,
      orElse: () => {'codigo': toCurrency, 'simbolo': '\$'},
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isRecent ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isRecent ? Colors.green : Colors.orange,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                fromCurrencyInfo['simbolo'] ?? '\$',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isRecent ? Colors.green[700] : Colors.orange[700],
                ),
              ),
              Text(
                fromCurrency,
                style: TextStyle(
                  fontSize: 8,
                  color: isRecent ? Colors.green[600] : Colors.orange[600],
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: [
            Text(
              fromCurrency,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Icon(Icons.arrow_forward, size: 16, color: Colors.grey[600]),
            Text(
              toCurrency,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (!isRecent)
              Icon(Icons.schedule, size: 16, color: Colors.orange),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '1 ${fromCurrencyInfo['simbolo']}1.00 = ',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${toCurrencyInfo['simbolo']}${rateValue.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Actualizada: ${_formatDate(lastUpdate)}',
              style: TextStyle(
                fontSize: 10,
                color: isRecent ? Colors.green[600] : Colors.orange[600],
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.visibility,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} h';
    } else if (difference.inDays == 1) {
      return 'Ayer';
    } else if (difference.inDays < 7) {
      return 'Hace ${difference.inDays} días';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
