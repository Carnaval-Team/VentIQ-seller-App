import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_store_products_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

class CarnavalStoreProductsScreen extends StatefulWidget {
  const CarnavalStoreProductsScreen({super.key});

  @override
  State<CarnavalStoreProductsScreen> createState() =>
      _CarnavalStoreProductsScreenState();
}

class _CarnavalStoreProductsScreenState
    extends State<CarnavalStoreProductsScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isLoadingStores = true;
  bool _isLoadingCategories = true;
  bool _isLoadingProducts = false;

  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];

  int? _selectedStoreId;
  int? _selectedCategoryId;
  int _totalProducts = 0;
  int _offset = 0;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoadingStores = true;
      _isLoadingCategories = true;
    });
    final results = await Future.wait([
      CarnavalStoreProductsService.getStores(),
      CarnavalStoreProductsService.getCategories(),
    ]);
    if (!mounted) return;
    setState(() {
      _stores = results[0];
      _categories = results[1];
      _isLoadingStores = false;
      _isLoadingCategories = false;
      if (_stores.isNotEmpty) {
        _selectedStoreId = _stores.first['id_tienda_carnaval'] as int?;
        _loadProducts(reset: true);
      }
    });
  }

  Future<void> _loadProducts({required bool reset}) async {
    if (_selectedStoreId == null) return;

    if (reset) {
      setState(() {
        _offset = 0;
        _products = [];
      });
    }

    setState(() => _isLoadingProducts = true);

    final result = await CarnavalStoreProductsService.getProducts(
      carnavalStoreId: _selectedStoreId!,
      categoryId: _selectedCategoryId,
      search: _searchController.text,
      limit: _pageSize,
      offset: _offset,
    );

    if (!mounted) return;

    setState(() {
      _products.addAll(result['items'] as List<Map<String, dynamic>>);
      _totalProducts = result['total'] as int? ?? 0;
      _offset += _pageSize;
      _isLoadingProducts = false;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingProducts &&
        _products.length < _totalProducts) {
      _loadProducts(reset: false);
    }
  }

  Future<void> _onSearchChanged() async {
    await _loadProducts(reset: true);
  }

  String _categoryName(dynamic category) {
    if (category == null) return 'Sin categoría';
    if (category is Map<String, dynamic>) {
      return category['name'] as String? ?? 'Sin categoría';
    }
    return 'Sin categoría';
  }

  String _formatPrice(dynamic value) {
    if (value == null) return '0.00';
    return (value as num).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final screenPadding = PlatformUtils.getScreenPadding();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos por Tienda en Carnaval'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      drawer: const AppDrawer(),
      body: Padding(
        padding: EdgeInsets.all(screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilters(),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingStores || _isLoadingCategories
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 260,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Tienda',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _selectedStoreId,
                items: _stores.map((store) {
                  final id = store['id_tienda_carnaval'] as int?;
                  return DropdownMenuItem<int?>(
                    value: id,
                    child: Text(
                      store['denominacion'] as String? ?? 'Sin nombre',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedStoreId = value);
                  _loadProducts(reset: true);
                },
              ),
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Categoría',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _selectedCategoryId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todas'),
                  ),
                  ..._categories.map((cat) {
                    final id = cat['id'] as int?;
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(
                        cat['name'] as String? ?? 'Sin nombre',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _selectedCategoryId = value);
                  _loadProducts(reset: true);
                },
              ),
            ),
          ),
        ),
        SizedBox(
          width: 280,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Buscar producto',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged();
                },
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _onSearchChanged(),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isLoadingProducts ? null : () => _loadProducts(reset: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Buscar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_selectedStoreId == null) {
      return const Center(child: Text('Selecciona una tienda'));
    }

    if (_products.isEmpty && !_isLoadingProducts) {
      return const Center(child: Text('No se encontraron productos'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mostrando ${_products.length} de $_totalProducts productos',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            itemCount: _products.length + (_isLoadingProducts ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index >= _products.length) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return _buildProductItem(_products[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductItem(Map<String, dynamic> product) {
    final name = product['name'] as String? ?? 'Sin nombre';
    final price = _formatPrice(product['price']);
    final discountPrice = _formatPrice(product['precio_descuento']);
    final stock = product['stock'] ?? 0;
    final status = product['status'] as bool? ?? false;
    final image = product['image'] as String?;
    final category = _categoryName(product['Categorias']);

    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: image != null && image.isNotEmpty
              ? Image.network(
                  image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholderImage(),
                )
              : _placeholderImage(),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Categoría: $category'),
          Text('Stock: $stock  |  Precio: \$$price'),
          if ((product['precio_descuento'] as num? ?? 0) > 0)
            Text('Descuento: \$$discountPrice'),
        ],
      ),
      trailing: Chip(
        label: Text(
          status ? 'Activo' : 'Inactivo',
          style: const TextStyle(fontSize: 12),
        ),
        backgroundColor: status ? AppColors.success : AppColors.error,
        labelStyle: TextStyle(
          color: status ? Colors.white : Colors.white,
        ),
      ),
    );
  }

  Widget _placeholderImage() {
    return Container(
      color: Colors.grey[200],
      child: const Icon(Icons.image, color: Colors.grey),
    );
  }
}
