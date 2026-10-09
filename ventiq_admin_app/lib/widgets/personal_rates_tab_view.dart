import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/personal_rates_service.dart';
import '../services/store_service.dart';

class PersonalRatesTabView extends StatefulWidget {
  final bool canEdit;
  const PersonalRatesTabView({super.key, required this.canEdit});

  @override
  State<PersonalRatesTabView> createState() => _PersonalRatesTabViewState();
}

class _PersonalRatesTabViewState extends State<PersonalRatesTabView> {
  static const int _cupId = 1;
  static const int _usdId = 2;

  bool _isLoading = true;
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _rates = [];
  int? _storeId;

  @override
  void initState() {
    super.initState();
    _loadStoreAndData();
  }

  Set<int> get _activeOriginIds =>
      _rates
          .map((r) => (r['id_moneda_origen'] as num?)?.toInt())
          .whereType<int>()
          .toSet();

  Future<void> _loadStoreAndData() async {
    setState(() => _isLoading = true);
    try {
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId == null) {
        throw Exception('No se pudo obtener la tienda actual');
      }
      final results = await Future.wait([
        PersonalRatesService.getCurrencies(),
        PersonalRatesService.getRatesToCup(storeId),
      ]);
      if (!mounted) return;
      setState(() {
        _storeId = storeId;
        _currencies = results[0];
        _rates = results[1];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando tasas: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showRateDialog({Map<String, dynamic>? rate}) async {
    if (!widget.canEdit) return;

    final isEdit = rate != null;
    final previousRateId = rate?['id'] as int?;
    final previousOriginId = (rate?['id_moneda_origen'] as num?)?.toInt();
    int? selectedCurrencyId = previousOriginId;
    double? valorCambio = (rate?['valor_cambio'] as num?)?.toDouble();
    bool usarPrecioToque = rate?['usar_precio_toque'] == true;
    var isSaving = false;

    // Al crear, solo monedas sin tasa activa. Al editar, la actual + las libres.
    List<Map<String, dynamic>> availableCurrencies() {
      return _currencies.where((c) {
        final id = c['id'] as int;
        if (id == _cupId) return false;
        if (isEdit && (id == previousOriginId || id == selectedCurrencyId)) {
          return true;
        }
        return !_activeOriginIds.contains(id);
      }).toList();
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final currencies = availableCurrencies();
            return AlertDialog(
              title: Text(isEdit ? 'Editar tasa' : 'Agregar tasa'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isEdit && currencies.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Todas las monedas ya tienen una tasa activa. '
                        'Edita o desactiva una existente.',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  DropdownButtonFormField<int>(
                    value:
                        currencies.any((c) => c['id'] == selectedCurrencyId)
                            ? selectedCurrencyId
                            : null,
                    decoration: const InputDecoration(
                      labelText: 'Moneda origen',
                    ),
                    items:
                        currencies
                            .map(
                              (c) => DropdownMenuItem<int>(
                                value: c['id'] as int,
                                child: Text(
                                  '${c['simbolo'] ?? ''} ${c['denominacion'] ?? c['nombre_corto'] ?? ''}',
                                ),
                              ),
                            )
                            .toList(),
                    onChanged:
                        isSaving
                            ? null
                            : (value) {
                              setLocalState(() {
                                selectedCurrencyId = value;
                                if (selectedCurrencyId != _usdId) {
                                  usarPrecioToque = false;
                                }
                              });
                            },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue:
                        valorCambio != null ? valorCambio.toString() : '',
                    enabled: !isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Valor cambio (→ CUP)',
                      prefixText: '1 = ',
                      suffixText: ' CUP',
                    ),
                    onChanged: (value) {
                      setLocalState(() {
                        valorCambio = double.tryParse(value);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (selectedCurrencyId == _usdId)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Usar precio de ElToque'),
                      subtitle: const Text(
                        'Si está activo, la tasa tomará el valor de la API ElToque para USD.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: usarPrecioToque,
                      onChanged:
                          isSaving
                              ? null
                              : (value) {
                                setLocalState(() => usarPrecioToque = value);
                              },
                    ),
                  if (isEdit)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Al guardar se crea un registro nuevo y se desactiva el anterior '
                        '(historial + triggers de precio).',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed:
                      isSaving || currencies.isEmpty
                          ? null
                          : () async {
                            if (selectedCurrencyId == null ||
                                valorCambio == null ||
                                valorCambio! <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Completa moneda y valor válido',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }

                            setLocalState(() => isSaving = true);
                            try {
                              if (isEdit) {
                                await PersonalRatesService.replaceRate(
                                  previousRateId: previousRateId!,
                                  storeId: _storeId!,
                                  monedaOrigenId: selectedCurrencyId!,
                                  valorCambio: valorCambio!,
                                  usarPrecioToque: usarPrecioToque,
                                );
                              } else {
                                await PersonalRatesService.createRate(
                                  storeId: _storeId!,
                                  monedaOrigenId: selectedCurrencyId!,
                                  valorCambio: valorCambio!,
                                  usarPrecioToque: usarPrecioToque,
                                );
                              }
                              if (!mounted) return;
                              Navigator.of(context).pop();
                              await _loadStoreAndData();
                            } catch (e) {
                              setLocalState(() => isSaving = false);
                              if (!mounted) return;
                              final msg =
                                  e is StateError
                                      ? e.message
                                      : 'Error guardando tasa: $e';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                  child:
                      isSaving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeactivate(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Desactivar tasa'),
            content: const Text('¿Deseas desactivar esta tasa?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Desactivar'),
              ),
            ],
          ),
    );
    if (ok == true) {
      await PersonalRatesService.deactivateRate(id);
      if (!mounted) return;
      await _loadStoreAndData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final canAddMore = _currencies.any((c) {
      final id = c['id'] as int;
      return id != _cupId && !_activeOriginIds.contains(id);
    });

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.currency_exchange, color: Colors.blue),
              const SizedBox(width: 8),
              const Text(
                'Tasas personalizadas hacia CUP',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (widget.canEdit)
                ElevatedButton.icon(
                  onPressed: canAddMore ? () => _showRateDialog() : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                ),
            ],
          ),
          if (widget.canEdit && !canAddMore) ...[
            const SizedBox(height: 8),
            Text(
              'Cada moneda solo puede tener una tasa activa. Edita o desactiva una existente.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child:
                _rates.isEmpty
                    ? Center(
                      child: Text(
                        'No hay tasas configuradas',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                    : ListView.separated(
                      itemCount: _rates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final rate = _rates[index];
                        final currency = rate['moneda_origen'] ?? {};
                        final title =
                            '${currency['simbolo'] ?? ''} ${currency['denominacion'] ?? currency['nombre_corto'] ?? ''}';
                        final valor =
                            (rate['valor_cambio'] as num?)?.toDouble() ?? 0.0;
                        final bool toque = rate['usar_precio_toque'] == true;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade50,
                              child: Text(
                                currency['nombre_corto']
                                        ?.toString()
                                        .toUpperCase() ??
                                    'FX',
                                style: const TextStyle(color: Colors.blue),
                              ),
                            ),
                            title: Text(title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('1 → ${valor.toStringAsFixed(2)} CUP'),
                                if (toque)
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.flash_on,
                                        size: 14,
                                        color: Colors.orange,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Usando precio ElToque',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            trailing:
                                widget.canEdit
                                    ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') {
                                          _showRateDialog(rate: rate);
                                        } else if (value == 'delete') {
                                          _confirmDeactivate(rate['id'] as int);
                                        }
                                      },
                                      itemBuilder:
                                          (context) => const [
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Editar'),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Desactivar'),
                                            ),
                                          ],
                                    )
                                    : null,
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
