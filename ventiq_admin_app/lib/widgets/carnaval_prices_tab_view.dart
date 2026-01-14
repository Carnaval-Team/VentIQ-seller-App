import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_prices_service.dart';
import '../services/store_service.dart';

class CarnavalPricesTabView extends StatefulWidget {
  const CarnavalPricesTabView({super.key});

  @override
  State<CarnavalPricesTabView> createState() => _CarnavalPricesTabViewState();
}

class _CarnavalPricesTabViewState extends State<CarnavalPricesTabView> {
  final _service = CarnavalPricesService();
  final ScrollController _pricesScroll = ScrollController();

  bool _isInitializing = true;
  bool _isLoadingPrices = false;
  bool _isMoreLoadingPrices = false;

  int? _storeId;
  final int _pageSizePrices = 25;
  int _pricesPage = 0;
  int _pricesTotal = 0;
  String _pricesSearch = '';
  List<Map<String, dynamic>> _pricesItems = [];

  @override
  void initState() {
    super.initState();
    _initStoreAndLoad();
    _pricesScroll.addListener(_onPricesScroll);
  }

  @override
  void dispose() {
    _pricesScroll.dispose();
    super.dispose();
  }

  Future<void> _initStoreAndLoad() async {
    setState(() => _isInitializing = true);
    try {
      _storeId = await StoreService.getCurrentStoreId();
      if (_storeId != null) {
        await _loadPrices(reset: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error obteniendo tienda: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  void _onPricesScroll() {
    if (_pricesScroll.position.pixels >=
            _pricesScroll.position.maxScrollExtent - 200 &&
        !_isMoreLoadingPrices &&
        _pricesItems.length < _pricesTotal) {
      _loadMorePrices();
    }
  }

  Future<void> _loadPrices({required bool reset}) async {
    if (_storeId == null) return;

    if (reset) {
      setState(() {
        _isLoadingPrices = true;
        _pricesPage = 0;
        _pricesItems = [];
        _pricesTotal = 0;
      });
    }

    try {
      final result = await _service.getPricesPage(
        storeId: _storeId!,
        limit: _pageSizePrices,
        offset: _pricesPage * _pageSizePrices,
        search: _pricesSearch,
      );

      if (!mounted) return;
      setState(() {
        final items = List<Map<String, dynamic>>.from(result['items'] as List);
        if (reset) {
          _pricesItems = items;
        } else {
          _pricesItems.addAll(items);
        }
        _pricesTotal = result['total'] as int;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando precios: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPrices = false;
        });
      }
    }
  }

  Future<void> _loadMorePrices() async {
    if (_isMoreLoadingPrices) return;
    setState(() => _isMoreLoadingPrices = true);
    _pricesPage++;
    await _loadPrices(reset: false);
    if (mounted) setState(() => _isMoreLoadingPrices = false);
  }

  Color _badgeColor(bool isBad) => isBad ? AppColors.error : AppColors.success;

  String _formatNum(dynamic v, {int decimals = 2}) {
    final d = (v as num?)?.toDouble() ?? 0.0;
    return d.toStringAsFixed(decimals);
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPricesTable() {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_storeId == null) {
      return const Center(
        child: Text(
          'No se encontró una tienda seleccionada.\nConfigura la tienda y vuelve a intentar.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.price_change, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Precios Inventtia vs Carnaval (${_pricesItems.length}/$_pricesTotal)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      _pricesSearch = v;
                      _loadPrices(reset: true);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Producto',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 564,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Center(
                          child: Text(
                            'Inventtia',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 68,
                        child: Center(
                          child: Text(
                            'Carnaval Desc.',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 68,
                        child: Center(
                          child: Text(
                            'Carnaval Price',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Text(
                            'Diff %',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Center(
                          child: Text(
                            'Diff transf%',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: Center(
                          child: Text(
                            'Estado',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 44,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Acc',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoadingPrices)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: Scrollbar(
              controller: _pricesScroll,
              child: ListView.builder(
                controller: _pricesScroll,
                itemCount: _pricesItems.length + (_isMoreLoadingPrices ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _pricesItems.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final row = _pricesItems[index];
                  final inv =
                      (row['precio_inventtia'] as num?)?.toDouble() ?? 0.0;
                  final carD =
                      (row['precio_carnaval_descuento'] as num?)?.toDouble() ??
                      0.0;
                  final carP =
                      (row['precio_carnaval_price'] as num?)?.toDouble() ?? 0.0;

                  final diffD =
                      (row['diff_percent_descuento'] as num?)?.toDouble();
                  final diffP = (row['diff_percent_price'] as num?)?.toDouble();
                  final isBad = (row['is_mal_precio'] as bool?) ?? false;

                  final badgeColor = _badgeColor(isBad);
                  final badgeText = isBad ? 'MAL' : 'OK';

                  return ListTile(
                    dense: true,
                    title: Text(
                      row['denominacion']?.toString() ?? 'Sin nombre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('SKU: ${row['sku'] ?? 'N/A'}'),
                    trailing: SizedBox(
                      width: 564,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: _chip(_formatNum(inv), AppColors.primary),
                            ),
                          ),
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: _chip(
                                _formatNum(carD),
                                AppColors.textSecondary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: _chip(
                                _formatNum(carP),
                                AppColors.textSecondary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Center(
                              child: _chip(
                                '${diffD == null ? '—' : _formatNum(diffD)}%',
                                AppColors.warning,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Center(
                              child: _chip(
                                '${diffP == null ? '—' : _formatNum(diffP)}%',
                                AppColors.warning,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 72,
                            child: Center(child: _chip(badgeText, badgeColor)),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar precios en Carnaval',
                              onPressed: () => _editCarnavalPrices(row),
                              icon: const Icon(Icons.edit),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editCarnavalPrices(Map<String, dynamic> row) async {
    final carnavalProductId = row['carnaval_product_id'];
    if (carnavalProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este producto no está enlazado a Carnaval.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final descuentoController = TextEditingController(
      text: _formatNum(row['precio_carnaval_descuento']),
    );
    final priceController = TextEditingController(
      text: _formatNum(row['precio_carnaval_price']),
    );

    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar Precios (Carnaval)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descuentoController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'precio_descuento',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'price',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final d = double.tryParse(descuentoController.text.trim());
                final p = double.tryParse(priceController.text.trim());
                if (d == null || p == null) {
                  Navigator.of(context).pop(null);
                  return;
                }
                Navigator.of(context).pop({'d': d, 'p': p});
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    try {
      await _service.updateCarnavalPrices(
        carnavalProductId: (carnavalProductId as num).toInt(),
        precioDescuento: result['d']!,
        price: result['p']!,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precios actualizados en Carnaval.'),
          backgroundColor: AppColors.success,
        ),
      );

      await _loadPrices(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error actualizando precios: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(Icons.price_check, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Precios Carnaval (tienda actual)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refrescar',
                  icon: const Icon(Icons.refresh),
                  onPressed:
                      _storeId == null
                          ? null
                          : () async {
                            await _loadPrices(reset: true);
                          },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildPricesTable()),
        ],
      ),
    );
  }
}
