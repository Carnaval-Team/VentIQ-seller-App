import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/product_detail_service.dart';

/// Pantalla de detalles del producto del marketplace
class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ProductDetailService _productDetailService = ProductDetailService();
  
  Map<String, dynamic>? _productDetails;
  List<Map<String, dynamic>> _variants = [];
  bool _isLoading = true;
  String? _errorMessage;
  
  // Selecciones múltiples: Key = variant id, Value = cantidad
  Map<String, int> _selectedQuantities = {};

  @override
  void initState() {
    super.initState();
    _loadProductDetails();
  }

  /// Carga los detalles completos del producto desde Supabase
  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final productId = widget.product['id_producto'] as int;
      
      final details = await _productDetailService.getProductDetail(productId);

      setState(() {
        _productDetails = details;
        _variants = List<Map<String, dynamic>>.from(details['variantes'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando detalles: $e');
      setState(() {
        _errorMessage = 'Error al cargar los detalles del producto';
        _isLoading = false;
      });
    }
  }

  /// Actualiza la cantidad seleccionada de una variante
  void _updateQuantity(String variantId, int quantity) {
    setState(() {
      if (quantity > 0) {
        _selectedQuantities[variantId] = quantity;
      } else {
        _selectedQuantities.remove(variantId);
      }
    });
  }

  /// Agrega los productos seleccionados al carrito
  void _addToCart() {
    if (_selectedQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // TODO: Implementar lógica de agregar al carrito
    final totalItems = _selectedQuantities.values.fold<int>(0, (sum, qty) => sum + qty);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$totalItems ${totalItems == 1 ? 'producto agregado' : 'productos agregados'} al carrito'),
        backgroundColor: AppTheme.successColor,
      ),
    );

    // Limpiar selecciones
    setState(() {
      _selectedQuantities.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product['denominacion'] ?? 'Producto'),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.favorite_border), onPressed: () {}),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Imagen y información básica
                            _buildProductHeader(),

                            const Divider(height: 1, thickness: 1),

                            // Descripción
                            if (_productDetails?['descripcion'] != null)
                              _buildDescriptionSection(),

                            const Divider(height: 1, thickness: 1),

                            // Variantes disponibles
                            _buildVariantsSection(),
                          ],
                        ),
                      ),
                    ),

                    // Botón de agregar al carrito (fijo abajo)
                    if (_selectedQuantities.isNotEmpty) _buildCartButton(),
                  ],
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Error desconocido',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProductDetails,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductHeader() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagen del producto
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: _productDetails?['imagen'] != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    child: Image.network(
                      _productDetails!['imagen'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.shopping_bag_outlined,
                          size: 50,
                          color: Colors.grey[400],
                        );
                      },
                    ),
                  )
                : Icon(
                    Icons.shopping_bag_outlined,
                    size: 50,
                    color: Colors.grey[400],
                  ),
          ),
          const SizedBox(width: AppTheme.paddingM),

          // Información del producto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nombre
                Text(
                  _productDetails?['denominacion'] ?? widget.product['denominacion'] ?? 'Producto',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Categoría
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppTheme.secondaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    _productDetails?['categoria'] ?? 'Sin categoría',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Rating (siempre se muestra, incluso si es 0.0)
                Row(
                  children: [
                    const Icon(
                      Icons.star,
                      size: 18,
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${((_productDetails?['rating_promedio'] as num?) ?? 0.0).toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${(_productDetails?['total_ratings'] as int?) ?? 0} ${(_productDetails?['total_ratings'] as int?) == 1 ? 'reseña' : 'reseñas'})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Stock total
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_productDetails?['cantidad_total'] ?? 0} disponibles',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Descripción',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _productDetails!['descripcion'],
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsSection() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: AppTheme.backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Presentaciones Disponibles',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_variants.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (_variants.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.paddingL),
                child: Text(
                  'No hay presentaciones disponibles',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ..._variants.map((variant) => _buildVariantCard(variant)),
        ],
      ),
    );
  }

  Widget _buildVariantCard(Map<String, dynamic> variant) {
    final variantId = variant['id'] as String;
    final nombre = variant['nombre'] as String? ?? 'Variante';
    final descripcion = variant['descripcion'] as String?;
    final precio = (variant['precio'] as num?)?.toDouble() ?? 0.0;
    final cantidadTotal = variant['cantidad_total'] as int? ?? 0;
    final esBase = variant['es_base'] as bool? ?? false;
    final currentQuantity = _selectedQuantities[variantId] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(
          color: currentQuantity > 0 
              ? AppTheme.primaryColor 
              : Colors.grey[300]!,
          width: currentQuantity > 0 ? 2 : 1,
        ),
        boxShadow: currentQuantity > 0
            ? [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con nombre y badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    nombre,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (esBase)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 12, color: AppTheme.warningColor),
                        SizedBox(width: 2),
                        Text(
                          'Base',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warningColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            
            if (descripcion != null) ...[
              const SizedBox(height: 4),
              Text(
                descripcion,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            
            const SizedBox(height: 8),
            
            // Precio y stock
            Row(
              children: [
                Text(
                  '\$${precio.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentColor,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: cantidadTotal > 0 ? AppTheme.successColor : AppTheme.errorColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '$cantidadTotal disponibles',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cantidadTotal > 0 ? AppTheme.successColor : AppTheme.errorColor,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Selector de cantidad
            Row(
              children: [
                // Botón menos
                IconButton(
                  onPressed: currentQuantity > 0
                      ? () => _updateQuantity(variantId, currentQuantity - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppTheme.primaryColor,
                  iconSize: 28,
                ),
                
                // Cantidad
                Container(
                  width: 60,
                  alignment: Alignment.center,
                  child: Text(
                    '$currentQuantity',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                
                // Botón más
                IconButton(
                  onPressed: currentQuantity < cantidadTotal
                      ? () => _updateQuantity(variantId, currentQuantity + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppTheme.primaryColor,
                  iconSize: 28,
                ),
                
                const Spacer(),
                
                // Subtotal
                if (currentQuantity > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Subtotal: \$${(precio * currentQuantity).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartButton() {
    final totalItems = _selectedQuantities.values.fold<int>(0, (sum, qty) => sum + qty);
    final totalPrice = _selectedQuantities.entries.fold<double>(0.0, (sum, entry) {
      final variant = _variants.firstWhere((v) => v['id'] == entry.key);
      final precio = (variant['precio'] as num?)?.toDouble() ?? 0.0;
      return sum + (precio * entry.value);
    });

    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Resumen
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalItems ${totalItems == 1 ? 'producto' : 'productos'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      'Total: \$${totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _addToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shopping_cart, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Agregar',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
