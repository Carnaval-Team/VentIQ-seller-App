import 'package:flutter/material.dart';
import '../services/product_search_service.dart';
import '../services/user_preferences_service.dart';
import 'dart:async';

/// Widget genérico para selección de productos con búsqueda paginada
class ProductSelectorWidget extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductSelected;
  final String searchHint;
  final ProductSearchType searchType;
  final bool requireInventory;
  final int? locationId;
  final int? supplierId;
  
  const ProductSelectorWidget({
    Key? key,
    required this.onProductSelected,
    this.searchHint = 'Buscar productos...',
    this.searchType = ProductSearchType.all,
    this.requireInventory = false,
    this.locationId,
    this.supplierId,
  }) : super(key: key);

  @override
  State<ProductSelectorWidget> createState() => _ProductSelectorWidgetState();
}

class _ProductSelectorWidgetState extends State<ProductSelectorWidget> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  ProductSearchResult _searchResult = ProductSearchResult.empty();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _showDescriptionInSelectors = false;
  Timer? _debounceTimer;
  String _lastSearchQuery = '';

  /// Contador de peticiones: solo la ultima respuesta pinta la lista.
  /// Sin esto, una busqueda lenta ("gasolina") puede llegar DESPUES de otra
  /// mas nueva y sobrescribirla con datos viejos/vacios.
  int _searchRequestId = 0;

  /// Mensaje de error de la ultima busqueda (timeout / red / RPC).
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _loadShowDescriptionConfig();
    _loadInitialProducts();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }
  
  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShowDescriptionConfig() async {
    try {
      final showDescription = await _userPreferencesService.getShowDescriptionInSelectors();
      if (!mounted) return;
      setState(() {
        _showDescriptionInSelectors = showDescription;
      });
      print('📋 ProductSelector - Configuración "Mostrar descripción en selectores" cargada: $showDescription');
    } catch (e) {
      print('❌ ProductSelector - Error al cargar configuración de mostrar descripción: $e');
      // Mantener valor por defecto (false)
    }
  }
  
  Future<void> _loadInitialProducts() async {
    final requestId = ++_searchRequestId;
    setState(() {
      _isLoading = true;
      _searchError = null;
    });
    final result = await ProductSearchService.searchProducts(
      searchType: widget.searchType,
      requireInventory: widget.requireInventory,
      locationId: widget.locationId,
      supplierId: widget.supplierId,
    );
    if (!mounted || requestId != _searchRequestId) return;
    setState(() {
      _searchResult = result;
      _searchError = result.errorMessage;
      _isLoading = false;
    });
  }
  
  Future<void> _searchProducts() async {
    final query = _searchController.text.trim();
    final requestId = ++_searchRequestId;
    setState(() {
      _isLoading = true;
      _searchError = null;
    });
    final result = await ProductSearchService.searchProducts(
      searchQuery: query.isEmpty ? null : query,
      searchType: widget.searchType,
      page: 1, // Siempre empezar desde la página 1 en nueva búsqueda
      requireInventory: widget.requireInventory,
      locationId: widget.locationId,
      supplierId: widget.supplierId,
    );
    // Respuesta obsoleta: llego despues de que el usuario siguiera escribiendo.
    if (!mounted || requestId != _searchRequestId) {
      print('⏭️ ProductSelector - Respuesta descartada (obsoleta) para "$query"');
      return;
    }
    setState(() {
      _searchResult = result;
      _searchError = result.errorMessage;
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
              : _searchError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 56,
                              color: Colors.orange[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No se pudo completar la búsqueda',
                              style: TextStyle(
                                color: Colors.orange[800],
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _searchError!,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _searchProducts,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
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
            // Mostrar descripción si está habilitado y existe
            if (_showDescriptionInSelectors && _hasDescription(product))
              Text(
                _getProductDescription(product),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text('SKU: ${product['sku'] ?? product['sku_producto'] ?? 'N/A'}'),
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

  /// Verifica si el producto tiene descripción disponible
  bool _hasDescription(Map<String, dynamic> product) {
    final descripcion = product['descripcion'];
    final descripcionCorta = product['descripcion_corta'];
    
    return (descripcion != null && descripcion.toString().isNotEmpty) ||
           (descripcionCorta != null && descripcionCorta.toString().isNotEmpty);
  }

  /// Obtiene la descripción del producto, priorizando descripcion sobre descripcion_corta
  String _getProductDescription(Map<String, dynamic> product) {
    final descripcion = product['descripcion'] ?? product['description'];
    final descripcionCorta = product['descripcion_corta'];
    
    if (descripcion != null && descripcion.toString().isNotEmpty) {
      return descripcion.toString();
    } else if (descripcionCorta != null && descripcionCorta.toString().isNotEmpty) {
      return descripcionCorta.toString();
    }
    
    return '';
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
    // 500ms era muy corto: el RPC de inventario tarda 300ms-4s, asi que cada
    // pulsacion lanzaba una consulta nueva y se pisaban entre ellas.
    _debounceTimer = Timer(const Duration(milliseconds: 700), () {
      _searchProducts();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoading || _isLoadingMore || !_searchResult.hasNextPage) return;

    final requestId = _searchRequestId;
    setState(() => _isLoadingMore = true);
    
    try {
      final result = await ProductSearchService.searchProducts(
        searchQuery: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        searchType: widget.searchType,
        page: _searchResult.currentPage + 1,
        requireInventory: widget.requireInventory,
        locationId: widget.locationId,
        supplierId: widget.supplierId,
      );

      // Si mientras paginabamos empezo otra busqueda, descartar esta pagina.
      if (!mounted || requestId != _searchRequestId) return;

      if (result.hasError) {
        setState(() => _isLoadingMore = false);
        return;
      }
      
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
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar más productos: $e')),
      );
    }
  }
}
