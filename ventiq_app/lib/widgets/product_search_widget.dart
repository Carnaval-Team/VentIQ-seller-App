import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../services/user_preferences_service.dart';

class ProductSearchWidget extends StatefulWidget {
  final Function(Product) onProductSelected;

  const ProductSearchWidget({
    Key? key,
    required this.onProductSelected,
  }) : super(key: key);

  @override
  State<ProductSearchWidget> createState() => _ProductSearchWidgetState();
}

class _ProductSearchWidgetState extends State<ProductSearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  List<Product> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query != _searchQuery) {
      _searchQuery = query;
      if (query.length >= 2) {
        _performSearch(query);
      } else {
        setState(() {
          _searchResults.clear();
          _hasSearched = false;
        });
      }
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      print('🔍 Buscando productos con query: "$query"');
      
      // Obtener datos del usuario
      final idTienda = await _userPreferencesService.getIdTienda();
      final idTpv = await _userPreferencesService.getIdTpv();

      if (idTienda == null || idTpv == null) {
        throw Exception('Datos de usuario no disponibles');
      }

      // Realizar búsqueda usando el mismo RPC que las categorías pero sin filtro de categoría
      final response = await Supabase.instance.client.rpc(
        'get_productos_by_categoria_tpv_meta',
        params: {
          'id_categoria_param': null, // null para buscar en todas las categorías
          'id_tienda_param': idTienda,
          'id_tpv_param': idTpv
        },
      );

      print('📋 Respuesta de búsqueda: ${response?.length ?? 0} productos encontrados');

      if (response != null) {
        final products = (response as List).map((productData) {
          return Product(
            id: productData['id_producto'] ?? 0,
            denominacion: productData['denominacion'] ?? 'Sin nombre',
            precio: (productData['precio_venta'] ?? 0.0).toDouble(),
            cantidad: productData['stock_disponible'] ?? 0,
            categoria: productData['categoria_nombre'] ?? 'Sin categoría',
            esRefrigerado: productData['es_refrigerado'] ?? false,
            esFragil: productData['es_fragil'] ?? false,
            esPeligroso: false, // Default value
            esVendible: productData['es_vendible'] ?? true,
            esComprable: true, // Default value
            esInventariable: true, // Default value
            esPorLotes: false, // Default value
            esElaborado: (productData['metadata'] != null && productData['metadata']['es_elaborado'] != null) 
                ? productData['metadata']['es_elaborado'] as bool 
                : false,
            esServicio: (productData['metadata'] != null && productData['metadata']['es_servicio'] != null) 
                ? productData['metadata']['es_servicio'] as bool 
                : false,
            descripcion: productData['descripcion'],
            foto: productData['imagen'],
            variantes: [], // Se cargarán después al seleccionar
          );
        }).toList();

        // Filtrar por query localmente si el RPC no lo hace
        final filteredProducts = products.where((product) {
          return product.denominacion.toLowerCase().contains(query.toLowerCase()) ||
                 (product.descripcion?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
                 (product.categoria.toLowerCase().contains(query.toLowerCase()));
        }).toList();

        setState(() {
          _searchResults = List<Product>.from(filteredProducts);
        });

        print('✅ Productos filtrados: ${filteredProducts.length}');
      }
    } catch (e) {
      print('❌ Error en búsqueda: $e');
      setState(() {
        _searchResults.clear();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Campo de búsqueda
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar productos...',
                prefixIcon: const Icon(Icons.search, color: Colors.purple),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.purple,
                          ),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults.clear();
                                _hasSearched = false;
                              });
                            },
                          )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: (query) {
                if (query.trim().isNotEmpty) {
                  _performSearch(query.trim());
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          // Instrucciones o resultados
          if (!_hasSearched)
            _buildInstructions()
          else if (_isSearching)
            _buildLoadingState()
          else if (_searchResults.isEmpty)
            _buildNoResultsState()
          else
            _buildSearchResults(),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Expanded(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search,
                size: 60,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 12),
              Text(
                'Buscar Productos',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Escribe el nombre del producto que deseas vender',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb, color: Colors.purple, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'Consejos:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Mínimo 2 caracteres\n'
                      '• Busca por nombre o categoría\n'
                      '• Búsqueda en tiempo real',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 16),
            Text(
              'Buscando productos...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No se encontraron productos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Intenta con otros términos de búsqueda',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchResults.clear();
                  _hasSearched = false;
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Nueva búsqueda'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_searchResults.length} producto${_searchResults.length != 1 ? 's' : ''} encontrado${_searchResults.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final product = _searchResults[index];
                return _buildProductCard(product);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => widget.onProductSelected(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Imagen del producto
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade200,
                ),
                child: product.foto != null && product.foto!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          product.foto!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.image_not_supported,
                              color: Colors.grey.shade400,
                            );
                          },
                        ),
                      )
                    : Icon(
                        Icons.inventory,
                        color: Colors.grey.shade400,
                        size: 30,
                      ),
              ),
              const SizedBox(width: 16),
              
              // Información del producto
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.denominacion,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.categoria,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (product.descripcion != null && product.descripcion!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product.descripcion!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '\$${product.precio.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: product.esElaborado
                                ? Colors.orange.withOpacity(0.1)
                                : product.esServicio
                                    ? Colors.blue.withOpacity(0.1)
                                    : Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.esElaborado
                                ? '(elaborado)'
                                : product.esServicio
                                    ? '(servicio)'
                                    : product.cantidad > 0
                                        ? 'Stock: ${product.cantidad}'
                                        : 'Agotado',
                            style: TextStyle(
                              fontSize: 12,
                              color: product.esElaborado
                                  ? Colors.orange[700]
                                  : product.esServicio
                                      ? Colors.blue[700]
                                      : product.cantidad > 0
                                          ? Colors.green[700]
                                          : Colors.red[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Icono de selección
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.purple,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
