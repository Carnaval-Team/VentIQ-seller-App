import 'package:flutter/material.dart';
import '../services/product_search_service.dart';
import 'dart:async';

/// Widget genérico para selección de productos con búsqueda paginada
class ProductSelectorWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductSelected;
  final String searchHint;
  final ProductSearchType searchType;
  final bool requireInventory;
  final int? locationId;
  
  const ProductSelectorWidget({
    Key? key,
    required this.onProductSelected,
    this.searchHint = 'Buscar productos...',
    this.searchType = ProductSearchType.all,
    this.requireInventory = false,
    this.locationId,
  }) : super(key: key);

  @override
  State<ProductSelectorWidget> createState() => _ProductSelectorWidgetState();
}

class _ProductSelectorWidgetState extends State<ProductSelectorWidget> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  ProductSearchResult _searchResult = ProductSearchResult.empty();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  Timer? _debounceTimer;
  String _lastSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInitialProducts();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadInitialProducts() async {
    setState(() => _isLoading = true);
    final result = await ProductSearchService.searchProducts(
      searchType: widget.searchType,
      requireInventory: widget.requireInventory,
      locationId: widget.locationId,
    );
    setState(() {
      _searchResult = result;
      _isLoading = false;
    });
  }
  
  Future<void> _searchProducts() async {
    setState(() => _isLoading = true);
    final result = await ProductSearchService.searchProducts(
      searchQuery: _searchController.text.isEmpty ? null : _searchController.text,
      searchType: widget.searchType,
      page: 1, // Siempre empezar desde la página 1 en nueva búsqueda
      requireInventory: widget.requireInventory,
      locationId: widget.locationId,
    );
    setState(() {
      _searchResult = result;
      _isLoading = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra de búsqueda
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        
        // Lista de productos
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _searchResult.products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isNotEmpty
                                ? 'No se encontraron productos'
                                : 'No hay productos disponibles',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _searchResult.products.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index < _searchResult.products.length) {
                          final product = _searchResult.products[index];
                          return _buildProductCard(product);
                        } else {
                          return const Center(child: CircularProgressIndicator());
                        }
                      },
                    ),
        ),
      ],
    );
  }
  
  Widget _buildProductCard(Map<String, dynamic> product) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: product['es_elaborado'] == true 
              ? Colors.orange[100] 
              : Colors.blue[100],
          child: Icon(
            product['es_elaborado'] == true 
                ? Icons.restaurant 
                : Icons.inventory,
            color: product['es_elaborado'] == true 
                ? Colors.orange[700] 
                : Colors.blue[700],
          ),
        ),
        title: Text(
          product['denominacion'] ?? product['nombre_producto'] ?? 'Sin nombre',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SKU: ${product['sku_producto'] ?? product['sku'] ?? 'N/A'}'),
            if (product['precio_venta_cup'] != null)
              Text(
                'Precio: \$${product['precio_venta_cup'].toStringAsFixed(2)}',
                style: TextStyle(
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            Text(
              product['es_elaborado'] == true
                  ? 'Producto Elaborado'
                  : product['es_servicio'] == true
                  ? 'Es Servicio'
                  : 'Producto Simple',
              style: TextStyle(
                fontSize: 12,
                color: product['es_elaborado'] == true
                    ? Colors.orange[600]
                    : product['es_servicio'] == true
                    ? Colors.purple // Color purple para servicio
                    : Colors.blue[600], // Color azul para producto simple
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.add_circle_outline),
        onTap: () {
          widget.onProductSelected(product);
          _searchController.clear();
        },
      ),
    );
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query != _lastSearchQuery) {
      _lastSearchQuery = query;
      _debounceSearch();
    }
  }

  void _debounceSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchProducts();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_searchResult.hasNextPage) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final result = await ProductSearchService.searchProducts(
        searchQuery: _searchController.text.isEmpty ? null : _searchController.text,
        searchType: widget.searchType,
        page: _searchResult.currentPage + 1,
        requireInventory: widget.requireInventory,
        locationId: widget.locationId,
      );
      
      setState(() {
        _searchResult = ProductSearchResult(
          products: [..._searchResult.products, ...result.products],
          totalCount: result.totalCount,
          currentPage: result.currentPage,
          pageSize: result.pageSize,
          hasNextPage: result.hasNextPage,
          hasPreviousPage: result.hasPreviousPage,
        );
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar más productos: $e')),
        );
      }
    }
  }
}
