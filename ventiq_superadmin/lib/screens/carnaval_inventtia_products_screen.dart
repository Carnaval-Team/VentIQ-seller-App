import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_inventtia_products_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

class CarnavalInventtiaProductsScreen extends StatefulWidget {
  const CarnavalInventtiaProductsScreen({super.key});

  @override
  State<CarnavalInventtiaProductsScreen> createState() =>
      _CarnavalInventtiaProductsScreenState();
}

class _CarnavalInventtiaProductsScreenState
    extends State<CarnavalInventtiaProductsScreen> {
  final _service = CarnavalInventtiaProductsService();

  bool _isLoadingStores = false;
  List<Map<String, dynamic>> _stores = [];
  Map<String, dynamic>? _selectedStore;

  bool _isLoadingKpis = false;
  Map<String, dynamic> _kpis = {
    'total_productos_sincronizados': 0,
    'total_productos_precio_mal': 0,
    'total_productos_stock_diferente': 0,
  };

  // Stock table state
  final ScrollController _stockScroll = ScrollController();
  bool _isLoadingStock = false;
  bool _isMoreLoadingStock = false;
  final int _pageSizeStock = 25;
  int _stockPage = 0;
  int _stockTotal = 0;
  String _stockSearch = '';
  List<Map<String, dynamic>> _stockItems = [];

  // Prices table state
  final ScrollController _pricesScroll = ScrollController();
  bool _isLoadingPrices = false;
  bool _isMoreLoadingPrices = false;
  final int _pageSizePrices = 25;
  int _pricesPage = 0;
  int _pricesTotal = 0;
  String _pricesSearch = '';
  List<Map<String, dynamic>> _pricesItems = [];

  @override
  void initState() {
    super.initState();
    _loadStores();
    _stockScroll.addListener(_onStockScroll);
    _pricesScroll.addListener(_onPricesScroll);
  }

  @override
  void dispose() {
    _stockScroll.dispose();
    _pricesScroll.dispose();
    super.dispose();
  }

  void _onStockScroll() {
    if (_stockScroll.position.pixels >=
            _stockScroll.position.maxScrollExtent - 200 &&
        !_isMoreLoadingStock &&
        _stockItems.length < _stockTotal) {
      _loadMoreStock();
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

  Future<void> _loadStores() async {
    setState(() => _isLoadingStores = true);
    try {
      final stores = await _service.getStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar tiendas: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingStores = false);
    }
  }

  Future<void> _onSelectStore(Map<String, dynamic> store) async {
    setState(() {
      _selectedStore = store;
    });

    await Future.wait([
      _loadKpis(),
      _loadStock(reset: true),
      _loadPrices(reset: true),
    ]);
  }

  Future<void> _loadKpis() async {
    final storeId = _selectedStore?['id'];
    if (storeId == null) return;

    setState(() => _isLoadingKpis = true);
    try {
      final kpis = await _service.getKpis(storeId: storeId as int);
      if (!mounted) return;
      setState(() => _kpis = kpis);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando KPIs: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingKpis = false);
    }
  }

  Future<void> _loadStock({required bool reset}) async {
    final storeId = _selectedStore?['id'];
    if (storeId == null) return;

    if (reset) {
      setState(() {
        _isLoadingStock = true;
        _stockPage = 0;
        _stockItems = [];
        _stockTotal = 0;
      });
    }

    try {
      final result = await _service.getStockPage(
        storeId: storeId as int,
        limit: _pageSizeStock,
        offset: _stockPage * _pageSizeStock,
        search: _stockSearch,
      );

      if (!mounted) return;
      setState(() {
        final items = List<Map<String, dynamic>>.from(result['items'] as List);
        if (reset) {
          _stockItems = items;
        } else {
          _stockItems.addAll(items);
        }
        _stockTotal = result['total'] as int;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando stock: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStock = false;
        });
      }
    }
  }

  Future<void> _loadMoreStock() async {
    if (_isMoreLoadingStock) return;
    setState(() => _isMoreLoadingStock = true);
    _stockPage++;
    await _loadStock(reset: false);
    if (mounted) setState(() => _isMoreLoadingStock = false);
  }

  Future<void> _loadPrices({required bool reset}) async {
    final storeId = _selectedStore?['id'];
    if (storeId == null) return;

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
        storeId: storeId as int,
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

  Color _diffStockColor(double inv, double car) {
    if (inv > car) return AppColors.success;
    if (inv < car) return AppColors.error;
    return AppColors.textSecondary;
  }

  String _formatNum(dynamic v, {int decimals = 0}) {
    final d = (v as num?)?.toDouble() ?? 0.0;
    return d.toStringAsFixed(decimals);
  }

  Future<void> _editCarnavalStock(Map<String, dynamic> row) async {
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

    final controller = TextEditingController(
      text: ((row['stock_carnaval'] as num?)?.toInt() ?? 0).toString(),
    );

    final newValue = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar Stock (Carnaval)'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Stock',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                Navigator.of(context).pop(parsed);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (newValue == null) return;

    try {
      await _service.updateCarnavalStock(
        carnavalProductId: (carnavalProductId as num).toInt(),
        newStock: newValue,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock actualizado en Carnaval.'),
          backgroundColor: AppColors.success,
        ),
      );

      await Future.wait([_loadKpis(), _loadStock(reset: true)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error actualizando stock: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
      text: _formatNum(row['precio_carnaval_descuento'], decimals: 2),
    );
    final priceController = TextEditingController(
      text: _formatNum(row['precio_carnaval_price'], decimals: 2),
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

      await Future.wait([_loadKpis(), _loadPrices(reset: true)]);
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

  Widget _buildStoreSelector() {
    if (_isLoadingStores) return const LinearProgressIndicator();

    return Padding(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        decoration: const InputDecoration(
          labelText: 'Seleccionar Tienda',
          prefixIcon: Icon(Icons.store),
          border: OutlineInputBorder(),
        ),
        value: _selectedStore,
        items:
            _stores
                .map(
                  (store) => DropdownMenuItem(
                    value: store,
                    child: Text(store['denominacion'] ?? 'Sin Nombre'),
                  ),
                )
                .toList(),
        onChanged: (value) {
          if (value != null) {
            _onSelectStore(value);
          }
        },
      ),
    );
  }

  Widget _buildKpis() {
    final synced = (_kpis['total_productos_sincronizados'] ?? 0).toString();
    final badPrice = (_kpis['total_productos_precio_mal'] ?? 0).toString();
    final diffStock =
        (_kpis['total_productos_stock_diferente'] ?? 0).toString();

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: PlatformUtils.getScreenPadding(),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Sincronizados',
                  value: synced,
                  icon: Icons.link,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  title: 'Precios Mal',
                  value: badPrice,
                  icon: Icons.price_change,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildKpiCard(
                  title: 'Stock Diferente',
                  value: diffStock,
                  icon: Icons.inventory_2,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          if (_isLoadingKpis)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockTable() {
    if (_selectedStore == null) {
      return const Center(child: Text('Seleccione una tienda'));
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Stock Inventtia vs Carnaval (${_stockItems.length}/$_stockTotal)',
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
                      _stockSearch = v;
                      _loadStock(reset: true);
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
                  width: 360,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 88,
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
                        width: 88,
                        child: Center(
                          child: Text(
                            'Carnaval',
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
                        width: 88,
                        child: Center(
                          child: Text(
                            'Diferencia',
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
          if (_isLoadingStock)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: Scrollbar(
              controller: _stockScroll,
              child: ListView.builder(
                controller: _stockScroll,
                itemCount: _stockItems.length + (_isMoreLoadingStock ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _stockItems.length) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final row = _stockItems[index];
                  final inv =
                      (row['stock_inventtia'] as num?)?.toDouble() ?? 0.0;
                  final car =
                      (row['stock_carnaval'] as num?)?.toDouble() ?? 0.0;
                  final diff = (inv - car);
                  final diffColor = _diffStockColor(inv, car);

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
                      width: 360,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: Center(
                              child: _chip(_formatNum(inv), AppColors.primary),
                            ),
                          ),
                          SizedBox(
                            width: 88,
                            child: Center(
                              child: _chip(
                                _formatNum(car),
                                AppColors.textSecondary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 88,
                            child: Center(
                              child: _chip(_formatNum(diff), diffColor),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 44,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Editar stock en Carnaval',
                              onPressed: () => _editCarnavalStock(row),
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

  Widget _buildPricesTable() {
    if (_selectedStore == null) {
      return const Center(child: Text('Seleccione una tienda'));
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
                  width: 520,
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
                            'Caraval',
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
                            'Carnaval Tra.',
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

                  final badgeColor =
                      isBad ? AppColors.error : AppColors.success;
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
                      width: 520,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: _chip(
                                inv.toStringAsFixed(2),
                                AppColors.primary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: _chip(
                                carD.toStringAsFixed(2),
                                AppColors.textSecondary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 68,
                            child: Center(
                              child: _chip(
                                carP.toStringAsFixed(2),
                                AppColors.textSecondary,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Center(
                              child: _chip(
                                '${diffD == null ? '—' : diffD.toStringAsFixed(2)}%',
                                AppColors.warning,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Center(
                              child: _chip(
                                '${diffP == null ? '—' : diffP.toStringAsFixed(2)}%',
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(size.width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos Carnaval - Inventtia'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed:
                _selectedStore == null
                    ? null
                    : () async {
                      await Future.wait([
                        _loadKpis(),
                        _loadStock(reset: true),
                        _loadPrices(reset: true),
                      ]);
                    },
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          _buildStoreSelector(),
          if (_selectedStore != null) ...[
            _buildKpis(),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: PlatformUtils.getScreenPadding(),
                ),
                child:
                    isDesktop
                        ? Row(
                          children: [
                            Expanded(child: _buildStockTable()),
                            const SizedBox(width: 12),
                            Expanded(child: _buildPricesTable()),
                          ],
                        )
                        : Column(
                          children: [
                            Expanded(child: _buildStockTable()),
                            const SizedBox(height: 12),
                            Expanded(child: _buildPricesTable()),
                          ],
                        ),
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            const Expanded(
              child: Center(
                child: Text('Selecciona una tienda para ver los productos'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
