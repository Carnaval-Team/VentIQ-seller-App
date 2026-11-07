import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/currency_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/price_utils.dart';
import '../theme/ventiq_home_theme.dart';

/// Conteo de efectivo **multimoneda**.
///
/// Cierra devolviendo el importe **NATIVO** de cada divisa —`{'CUP': 1500.0,
/// 'USD': 18.0}`—, nunca un único total ya convertido: aplastar las divisas en
/// el cierre hace imposible reconstruir el arqueo por moneda. La consolidación a
/// la moneda base es solo presentación; el consumidor la resuelve con la misma
/// tasa que usó el servidor al cobrar (`fn_cerrar_turno_tpv_monedas`).
class CashCountDialog extends StatefulWidget {
  final UserPreferencesService userPreferencesService;

  const CashCountDialog({Key? key, required this.userPreferencesService})
    : super(key: key);

  @override
  State<CashCountDialog> createState() => _CashCountDialogState();
}

class _CashCountDialogState extends State<CashCountDialog> {
  bool _isLoading = true;
  final List<String> _currencies = [];
  String? _selectedCurrency;

  /// Tasa hacia la moneda base de cada divisa contable (`{'CUP': 1, 'USD': 900}`).
  /// Es la única fuente de conversión del diálogo; una divisa sin tasa aquí no
  /// llega a mostrarse.
  Map<String, double> _rates = const {};

  /// Importe nativo contado por divisa. Acumulador único, sin conversiones.
  final Map<String, double> _nativeTotals = {};

  final Map<String, List<Map<String, dynamic>>> _denominationsByCurrency = {};
  final Map<String, Map<int, TextEditingController>> _controllersByCurrency =
      {};
  final Map<String, Map<int, int>> _countsByCurrency = {};

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
      final configuradas =
          await widget.userPreferencesService.getMonedasDisponibles();
      final rates = await _tasasContables(configuradas);
      final divisas = _contables(configuradas, rates);

      for (final divisa in divisas) {
        _registrarDivisa(divisa, await _denominacionesDe(divisa));
      }

      if (mounted) {
        setState(() {
          _rates = rates;
          _currencies.addAll(_denominationsByCurrency.keys);
          _selectedCurrency = _currencies.isEmpty ? null : _currencies.first;
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

  /// Tasa a moneda base de cada divisa configurada en la tienda.
  ///
  /// Se parte de `getRatesForStore()` —la misma `fn_tasa_cambio` que usa el
  /// servidor al cobrar— y se completa con `getRate()` la divisa que no venga en
  /// el mapa: sin conexión `getRatesForStore()` no puede listar la tienda, y ese
  /// es justo el camino documentado que resuelve USD con la última tasa cacheada
  /// (decisión D2). Así el respaldo offline no se duplica aquí.
  Future<Map<String, double>> _tasasContables(List<String> configuradas) async {
    final tasas = Map<String, double>.from(
      await CurrencyService.getRatesForStore(),
    );

    for (final codigo in _normalizar(configuradas)) {
      if (codigo == PriceUtils.baseCurrency || (tasas[codigo] ?? 0) > 0) {
        continue;
      }
      final tasa = await CurrencyService.getRate(
        codigo,
        PriceUtils.baseCurrency,
      );
      if (tasa > 0) tasas[codigo] = tasa;
    }
    return tasas;
  }

  /// Divisas contables: las configuradas **con tasa resoluble** hacia la base.
  ///
  /// Sin tasa no se puede consolidar lo contado (decisión B4 del plan), así que
  /// la divisa no se ofrece. Si no queda ninguna —caché fría y sin red— se cae a
  /// la moneda base, cuyo arqueo no necesita tasa alguna.
  List<String> _contables(
    List<String> configuradas,
    Map<String, double> rates,
  ) {
    final divisas = _normalizar(configuradas)
        .where((c) => _rateToBase(c, rates) > 0)
        .toList();

    return divisas.isEmpty ? [PriceUtils.baseCurrency] : divisas;
  }

  List<String> _normalizar(List<String> codigos) => codigos
      .map((c) => c.trim().toUpperCase())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList();

  /// Planilla de la divisa: la configurada o, para la moneda base, un catálogo
  /// de respaldo —contar la base no debe depender de que la caché esté caliente.
  Future<List<Map<String, dynamic>>> _denominacionesDe(String divisa) async {
    final configuradas = await widget.userPreferencesService
        .getDenominacionesPorMoneda(divisa);
    if (configuradas.isNotEmpty) return configuradas;
    return divisa == PriceUtils.baseCurrency
        ? _defaultCupDenominations()
        : const [];
  }

  void _registrarDivisa(
    String divisa,
    List<Map<String, dynamic>> denominaciones,
  ) {
    _denominationsByCurrency[divisa] = denominaciones;
    _countsByCurrency[divisa] = {};
    _controllersByCurrency[divisa] = {};
    _nativeTotals[divisa] = 0;
    for (final denom in denominaciones) {
      final id = denom['id'] as int;
      _countsByCurrency[divisa]![id] = 0;
      _controllersByCurrency[divisa]![id] = TextEditingController(text: '');
    }
  }

  /// Tasa de [divisa] hacia la moneda base. La base es 1 por definición; el
  /// resto solo si el servidor pudo resolverla (`0` = desconocida).
  double _rateToBase(String divisa, [Map<String, double>? rates]) {
    if (divisa == PriceUtils.baseCurrency) return 1;
    return (rates ?? _rates)[divisa] ?? 0;
  }

  /// Divisas distintas de la base con tasa conocida, para el aviso de cambio.
  List<MapEntry<String, double>> get _conversiones => _rates.entries
      .where((e) => e.key != PriceUtils.baseCurrency && e.value > 0)
      .toList();

  List<Map<String, dynamic>> _defaultCupDenominations() {
    const values = [1000, 500, 200, 100, 50, 20, 10, 5, 3, 1];
    return values
        .asMap()
        .entries
        .map(
          (e) => {'id': -100 - e.key, 'denominacion': e.value, 'moneda': 'CUP'},
        )
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
      _recalcular();
    });
  }

  void _updateCountFromInput(
    String currency,
    int denominationId,
    String value,
  ) {
    final count = int.tryParse(value) ?? 0;
    setState(() {
      _countsByCurrency[currency]?[denominationId] = count;
      _recalcular();
    });
  }

  /// Suma los conteos en su importe **nativo**, sin pasar por ninguna tasa.
  Map<String, double> _contarNativo() {
    final totales = <String, double>{};
    for (final entry in _denominationsByCurrency.entries) {
      final counts = _countsByCurrency[entry.key] ?? const {};
      var nativo = 0.0;
      for (final denom in entry.value) {
        final id = denom['id'] as int;
        nativo +=
            (denom['denominacion'] as num).toDouble() * (counts[id] ?? 0);
      }
      totales[entry.key] = nativo;
    }
    return totales;
  }

  void _recalcular() {
    _nativeTotals
      ..clear()
      ..addAll(_contarNativo());
  }

  /// Consolidado en moneda base, **solo para mostrar**: no es lo que se devuelve.
  double get _totalEnBase => _nativeTotals.entries.fold(
    0.0,
    (total, e) => total + e.value * _rateToBase(e.key),
  );

  void _useTotal() {
    // Contrato con el arqueo: importes nativos por divisa, sin convertir.
    Navigator.pop<Map<String, double>>(
      context,
      Map<String, double>.from(_nativeTotals),
    );
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
              CircularProgressIndicator(color: VentiqHomeTheme.primary),
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
            // Tasas de la tienda. Una tienda de una sola divisa —el caso
            // mayoritario— no ve este aviso.
            if (_conversiones.isNotEmpty) _buildRatePanel(),
            const SizedBox(height: 12),

            // Selector de moneda
            if (_currencies.length > 1) ...[
              Row(
                children:
                    _currencies.map((currency) {
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
                            selectedColor: VentiqHomeTheme.primary,
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
                            '\$${value.toMoneyString(value % 1 == 0 ? 0 : 2)}',
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
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            final current = int.tryParse(controller.text) ?? 0;
                            if (current > 0) {
                              _setCount(currency, id, current - 1);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline,
                            color: VentiqHomeTheme.primary,
                          ),
                          onPressed: () {
                            final current = int.tryParse(controller.text) ?? 0;
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

            // Un renglón por divisa: el importe nativo es el dato que se
            // persiste, y el equivalente solo orienta al cajero.
            for (final divisa in _currencies) _buildNativeTotalRow(divisa),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VentiqHomeTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total ${PriceUtils.baseCurrency}:',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '\$${_totalEnBase.toMoneyString(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: VentiqHomeTheme.textPrimary,
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
            backgroundColor: VentiqHomeTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Usar monto'),
        ),
      ],
    );
  }

  Widget _buildRatePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final tasa in _conversiones)
            Text(
              '1 ${tasa.key} = '
              '${tasa.value.toMoneyString(2)} ${PriceUtils.baseCurrency}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.amber[800],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNativeTotalRow(String divisa) {
    final nativo = _nativeTotals[divisa] ?? 0;
    final esBase = divisa == PriceUtils.baseCurrency;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$divisa:',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${nativo.toMoneyString(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!esBase)
                Text(
                  '≈ \$${(nativo * _rateToBase(divisa)).toMoneyString(2)} '
                  '${PriceUtils.baseCurrency}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
